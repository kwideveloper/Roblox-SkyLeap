local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerProfile = require(ServerScriptService:WaitForChild("PlayerProfile"))
local Leaderboards = require(ServerScriptService:WaitForChild("Leaderboards"))

export type MatchPlayerEntry = {
	player: Player,
	side: "Left" | "Right",
}

export type MatchContext = {
	matchId: number,
	round: number,
	players: { MatchPlayerEntry },
}

type RemotesRecord = {
	GameStart: RemoteEvent,
	CountdownUpdate: RemoteEvent,
	BombAssigned: RemoteEvent,
	BombPassed: RemoteEvent,
	BombTimerUpdate: RemoteEvent,
	PlayerEliminated: RemoteEvent,
	GameEnd: RemoteEvent,
	ScoreboardUpdate: RemoteEvent,
}

type WorkspaceRefs = {
	level: Model | Folder | nil,
	lobbySpawner: Model | BasePart | nil,
}

type Callbacks = {
	onMatchStarted: ((MatchContext) -> ())?,
	onMatchEnded: (() -> ())?,
	onPlayersTeleported: (({ Player }) -> ())?,
	onPlayerEliminated: ((Player) -> ())?,
}

type Dependencies = {
	remotes: RemotesRecord,
	config: ModuleScript,
	workspaceRefs: WorkspaceRefs,
	callbacks: Callbacks?,
}

type InternalPlayerState = {
	entry: MatchPlayerEntry,
	alive: boolean,
	respawnCFrame: CFrame?,
}

type ManagerState = {
	phase: "idle" | "teleport" | "prepare" | "active" | "round_end" | "match_end",
	matchId: number,
	round: number,
	generation: number,
	players: { InternalPlayerState },
	playerLookup: { [Player]: InternalPlayerState },
	teamScores: { Left: number, Right: number },
	bombHolder: Player?,
	bombTimer: number,
	countdownTask: thread?,
	timerTask: thread?,
	heartbeatConn: RBXScriptConnection?,
	lastBombPassTick: number?,
	passers: { [Player]: Player? },
	matchStartTick: number,
	pendingLobbyReturnTask: thread?,
}

local BombMatchManager = {}
BombMatchManager.__index = BombMatchManager

local singleton: any = nil

local function requireConfig(moduleScript: ModuleScript)
	local ok, result = pcall(require, moduleScript)
	if not ok then
		error(string.format("[BombMatchManager] Failed to require config: %s", tostring(result)))
	end
	return result
end

local function assertRemote(remotes: RemotesRecord, key: string): RemoteEvent
	local remote = remotes[key]
	if not remote then
		error(string.format("[BombMatchManager] Missing remote '%s'", key), 3)
	end
	return remote
end

local function gatherSpawnDescriptors(
	level: Model | Folder | nil
): { Left: { Instance }, Right: { Instance }, Shared: { Instance } }
	local result = {
		Left = {},
		Right = {},
		Shared = {},
	}

	if not level then
		return result
	end

	local function register(target: Instance, bucket: "Left" | "Right" | "Shared")
		table.insert(result[bucket], target)
	end

	for _, descendant in ipairs(level:GetDescendants()) do
		if descendant:IsA("BasePart") or descendant:IsA("Model") then
			local name = descendant.Name
			if name:match("^SpawnLeft%d*$") or name:match("^LeftSpawn%d*$") then
				register(descendant, "Left")
			elseif name:match("^SpawnRight%d*$") or name:match("^RightSpawn%d*$") then
				register(descendant, "Right")
			elseif name == "Spawn" or name:match("^SpawnShared%d*$") or name:match("^SharedSpawn%d*$") then
				register(descendant, "Shared")
			end
		end
	end

	local function sortByName(array)
		table.sort(array, function(a, b)
			return a.Name < b.Name
		end)
	end

	sortByName(result.Left)
	sortByName(result.Right)
	sortByName(result.Shared)

	return result
end

local function computeSurfaceCFrame(object: Instance, offset: number, extraHeight: number?): CFrame?
	offset = offset or 0
	extraHeight = extraHeight or 0

	local baseCFrame: CFrame
	local size: Vector3

	if object:IsA("BasePart") then
		baseCFrame = object.CFrame
		size = object.Size
	elseif object:IsA("Model") then
		local success, cf, boundsSize = pcall(object.GetBoundingBox, object)
		if not success then
			return nil
		end
		baseCFrame = cf
		size = boundsSize
	else
		return nil
	end

	local up = baseCFrame.YVector.Unit
	local position = baseCFrame.Position + up * ((size.Y / 2) + offset + extraHeight)

	return CFrame.fromMatrix(position, baseCFrame.XVector, baseCFrame.YVector, baseCFrame.ZVector)
end

local function cancelTaskThread(thread, label)
	if not thread then
		return
	end
	local status = coroutine.status(thread)
	if status == "dead" then
		return
	end
	local ok, err = pcall(task.cancel, thread)
	if not ok and err ~= "cannot cancel thread" then
		warn(string.format("[BombMatchManager] Failed to cancel %s: %s", label or "thread", tostring(err)))
	end
end

local function deepCloneArray<T>(array: { T }): { T }
	local cloned = table.create(#array)
	for index, value in ipairs(array) do
		cloned[index] = value
	end
	return cloned
end

local function newState(): ManagerState
	return {
		phase = "idle",
		matchId = 0,
		round = 0,
		generation = 0,
		players = {},
		playerLookup = {},
		teamScores = { Left = 0, Right = 0 },
		bombHolder = nil,
		bombTimer = 0,
		countdownTask = nil,
		timerTask = nil,
		heartbeatConn = nil,
		lastBombPassTick = nil,
		passers = {},
		matchStartTick = 0,
		pendingLobbyReturnTask = nil,
	}
end

local ManagerMethods = {}
ManagerMethods.__index = ManagerMethods

function ManagerMethods:_setPhase(phase)
	self._state.phase = phase
end

function ManagerMethods:_cleanupRunners()
	local state = self._state

	if state.countdownTask then
		cancelTaskThread(state.countdownTask, "countdown task")
		state.countdownTask = nil
	end

	if state.timerTask then
		cancelTaskThread(state.timerTask, "timer task")
		state.timerTask = nil
	end

	if state.heartbeatConn then
		state.heartbeatConn:Disconnect()
		state.heartbeatConn = nil
	end
end

function ManagerMethods:_resetRuntime()
	if self._state.pendingLobbyReturnTask then
		pcall(task.cancel, self._state.pendingLobbyReturnTask)
		self._state.pendingLobbyReturnTask = nil
	end
	self._state.players = {}
	self._state.playerLookup = {}
	self._state.teamScores = { Left = 0, Right = 0 }
	self._state.bombHolder = nil
	self._state.bombTimer = 0
	self._state.round = 0
	self._state.lastBombPassTick = nil
	self._state.passers = {}
	self._state.matchStartTick = 0
end

function ManagerMethods:_emit(callbackName, ...)
	local callbacks = self._callbacks
	local cb = callbacks and callbacks[callbackName]
	if cb then
		local ok, err = pcall(cb, ...)
		if not ok then
			warn(string.format("[BombMatchManager] %s callback error: %s", callbackName, err))
		end
	end
end

function ManagerMethods:_forEachActivePlayer(callback)
	for _, playerState in ipairs(self._state.players) do
		local player = playerState.entry.player
		if player and player.Parent then
			callback(player)
		end
	end
end

function ManagerMethods:_updatePlayerStats(player, params)
	if not player or not player.Parent then
		return
	end

	params = params or {}

	local result = PlayerProfile.updateMatchStats(player.UserId, {
		kills = params.kills,
		win = params.win,
		addToStreak = params.addToStreak,
		resetStreak = params.resetStreak,
		matchSeconds = params.matchSeconds,
	})

	if params.win then
		Leaderboards.RecordDailyWin(player.UserId, params.win)
		Leaderboards.RecordWinAllTime(player.UserId, params.win)
	end
	if params.kills then
		Leaderboards.RecordDailyKill(player.UserId, params.kills)
		Leaderboards.RecordKillAllTime(player.UserId, params.kills)
	end
	if params.matchSeconds then
		Leaderboards.RecordMatchTime(player.UserId, params.matchSeconds)
	end

	if result and result.bestKillStreak then
		Leaderboards.RecordBestStreak(player.UserId, result.bestKillStreak)
	end
end

function ManagerMethods:_registerKill(player)
	self:_updatePlayerStats(player, { kills = 1 })
end

function ManagerMethods:_releaseMovement(playerState)
	if playerState and playerState._movementRelease then
		local release = playerState._movementRelease
		playerState._movementRelease = nil
		local success, err = pcall(release)
		if not success then
			warn(
				string.format(
					"[BombMatchManager] Failed to release movement for %s: %s",
					playerState.entry.player.Name,
					tostring(err)
				)
			)
		end
	end
	if playerState and playerState._positionClampConn then
		playerState._positionClampConn:Disconnect()
		playerState._positionClampConn = nil
	end
	if playerState and playerState._respawnConn then
		playerState._respawnConn:Disconnect()
		playerState._respawnConn = nil
	end
end

function ManagerMethods:_releaseAllMovement()
	for _, playerState in ipairs(self._state.players) do
		self:_releaseMovement(playerState)
	end
end

function ManagerMethods:_scheduleRespawn(playerState, delay)
	delay = delay or 0
	task.delay(delay, function()
		local player = playerState.entry.player
		if not player or not player.Parent then
			return
		end

		local targetCFrame

		if self._state.phase == "active" and playerState.lobbySlot and playerState.lobbySlot.cframe then
			targetCFrame = playerState.lobbySlot.cframe
		else
			local descriptor = self:_selectRespawnDescriptor(playerState) or playerState.spawnDescriptor
			if descriptor then
				local cf = computeSurfaceCFrame(
					descriptor,
					self._config.SpawnSurfaceOffset or 0.25,
					self._config.RespawnExtraHeight or 0
				)
				if cf then
					playerState.spawnDescriptor = descriptor
					targetCFrame = cf
				end
			end
		end

		if not targetCFrame then
			warn(string.format("[BombMatchManager] Unable to determine respawn position for %s", player.Name))
			return
		end

		playerState.respawnCFrame = targetCFrame

		if playerState._respawnConn then
			playerState._respawnConn:Disconnect()
			playerState._respawnConn = nil
		end

		local function attach(character)
			if not character then
				return
			end
			task.defer(function()
				self:_ensureCharacterAtCFrame(playerState, playerState.respawnCFrame, { holdMovement = true })
			end)
		end

		playerState._respawnConn = player.CharacterAdded:Connect(function(char)
			attach(char)
		end)

		local successLoad, loadErr = pcall(function()
			player:LoadCharacter()
		end)
		if not successLoad then
			if playerState._respawnConn then
				playerState._respawnConn:Disconnect()
				playerState._respawnConn = nil
			end
			warn(
				string.format("[BombMatchManager] Failed to load character for %s: %s", player.Name, tostring(loadErr))
			)
			return
		end

		if player.Character then
			attach(player.Character)
		end
	end)
end

function ManagerMethods:_broadcastScoreboard(payload, targetPlayers)
	if targetPlayers then
		for _, player in ipairs(targetPlayers) do
			if player and player.Parent then
				self._remotes.ScoreboardUpdate:FireClient(player, payload)
			end
		end
		return
	end

	self:_forEachActivePlayer(function(player)
		self._remotes.ScoreboardUpdate:FireClient(player, payload)
	end)
end

function ManagerMethods:_scoreboardPayload(active, showPoints, teams)
	local function serializeTeam(teamPlayers: { Player })
		local entries = {}
		for _, player in ipairs(teamPlayers) do
			table.insert(entries, {
				UserId = player.UserId,
				Name = player.Name,
				DisplayName = player.DisplayName,
			})
		end
		return entries
	end

	return {
		active = active,
		showReadiness = false,
		showPoints = showPoints,
		scores = {
			Left = self._state.teamScores.Left,
			Right = self._state.teamScores.Right,
		},
		team1 = serializeTeam(teams.Left),
		team2 = serializeTeam(teams.Right),
	}
end

function ManagerMethods:_collectTeamEntries()
	local teams = { Left = {}, Right = {} }
	for _, playerState in ipairs(self._state.players) do
		local entry = playerState.entry
		if entry.side == "Left" then
			table.insert(teams.Left, entry.player)
		else
			table.insert(teams.Right, entry.player)
		end
	end
	return teams
end

function ManagerMethods:_selectRespawnDescriptor(playerState)
	local spawnSets = self._spawnDescriptors or {}
	local side = playerState.entry.side or "Left"
	local sideList = spawnSets[side] or {}
	local sharedList = spawnSets.Shared or {}

	local used = {}
	for _, otherState in ipairs(self._state.players) do
		if otherState ~= playerState and otherState.spawnDescriptor then
			used[otherState.spawnDescriptor] = true
		end
	end

	local candidates = {}
	local function addCandidates(list)
		for _, desc in ipairs(list) do
			if not used[desc] then
				table.insert(candidates, desc)
			end
		end
	end

	addCandidates(sideList)
	if #candidates == 0 then
		addCandidates(sharedList)
	end
	if #candidates == 0 then
		-- fall back to allowing already used descriptors
		for _, desc in ipairs(sideList) do
			table.insert(candidates, desc)
		end
		for _, desc in ipairs(sharedList) do
			table.insert(candidates, desc)
		end
	end

	if #candidates == 0 then
		return nil
	end
	return candidates[math.random(1, #candidates)]
end

function ManagerMethods:_restoreAutoLoads()
	for _, playerState in ipairs(self._state.players) do
		local player = playerState.entry.player
		if player and player.Parent and playerState.autoLoadBackup ~= nil then
			local successSet, setErr = pcall(function()
				player.CharacterAutoLoads = playerState.autoLoadBackup
			end)
			if not successSet then
				warn(
					string.format(
						"[BombMatchManager] Failed to restore auto loads for %s: %s",
						player.Name,
						tostring(setErr)
					)
				)
			end
		end
	end
end

local function restoreHumanoidDefaults(humanoid, config)
	if not humanoid or not humanoid.Parent then
		return
	end
	humanoid.PlatformStand = false
	humanoid.WalkSpeed = config.PlayerDefaultWalkSpeed or 16
	humanoid.JumpPower = config.PlayerDefaultJumpPower or 50
end

function ManagerMethods:_ensureCharacterAtCFrame(playerState, cf, opts)
	local player = playerState.entry.player
	local holdMovement = opts and opts.holdMovement

	local function apply(character)
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not rootPart or not humanoid then
			return
		end

		humanoid.PlatformStand = true
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		local hipHeight = humanoid.HipHeight or 2
		local rootHeight = rootPart.Size.Y or 2
		local offsetY = hipHeight - (rootHeight * 0.5)
		local desiredPosition = cf.Position + Vector3.new(0, offsetY, 0)
		rootPart.CFrame = CFrame.fromMatrix(desiredPosition, cf.RightVector, cf.UpVector, cf.LookVector)
		rootPart.AssemblyLinearVelocity = Vector3.zero

		local function releaseMovement()
			restoreHumanoidDefaults(humanoid, self._config)
		end

		if holdMovement then
			playerState._movementRelease = releaseMovement
			local clampDuration = self._config.RespawnClampDuration or 1
			if playerState._positionClampConn then
				playerState._positionClampConn:Disconnect()
			end
			local startTime = tick()
			playerState._positionClampConn = RunService.Heartbeat:Connect(function()
				if not playerState.respawnCFrame or tick() - startTime > clampDuration then
					playerState._positionClampConn:Disconnect()
					playerState._positionClampConn = nil
					return
				end
				if rootPart then
					local hipHeight = humanoid.HipHeight or 2
					local rootHeight = rootPart.Size.Y or 2
					local offsetY = hipHeight - (rootHeight * 0.5)
					local desiredPosition = playerState.respawnCFrame.Position + Vector3.new(0, offsetY, 0)
					rootPart.CFrame = CFrame.fromMatrix(
						desiredPosition,
						playerState.respawnCFrame.RightVector,
						playerState.respawnCFrame.UpVector,
						playerState.respawnCFrame.LookVector
					)
					rootPart.AssemblyLinearVelocity = Vector3.zero
				end
			end)
		else
			task.defer(releaseMovement)
		end
	end

	local character = player.Character
	if character then
		apply(character)
	else
		local connection
		connection = player.CharacterAdded:Connect(function(char)
			if connection then
				connection:Disconnect()
			end
			task.defer(function()
				apply(char)
			end)
		end)
		playerState._movementRelease = function()
			-- if character spawns later, defaults will be restored in apply
			restoreHumanoidDefaults(
				player.Character and player.Character:FindFirstChildOfClass("Humanoid"),
				self._config
			)
		end
	end
end

function ManagerMethods:_anchorPlayer(playerState, cf, holdMovement, descriptor)
	playerState.respawnCFrame = cf
	playerState.spawnDescriptor = descriptor or playerState.spawnDescriptor
	self:_ensureCharacterAtCFrame(playerState, cf, { holdMovement = holdMovement })
end

local function pickSpawn(spawns: { Instance }, used: { [number]: boolean })
	for index, spawn in ipairs(spawns) do
		if not used[index] then
			used[index] = true
			return spawn
		end
	end
	return nil
end

function ManagerMethods:_teleportPlayersToArena(holdMovement)
	local spawnSets = self._spawnDescriptors or {}
	local leftSpawns = spawnSets.Left or {}
	local rightSpawns = spawnSets.Right or {}
	local sharedSpawns = spawnSets.Shared or {}

	if #leftSpawns == 0 and #rightSpawns == 0 and #sharedSpawns == 0 then
		warn("[BombMatchManager] No spawn descriptors found in level")
		return false
	end

	local usedLeft = {}
	local usedRight = {}
	local usedShared = {}
	local teleportedPlayers = {}

	for _, playerState in ipairs(self._state.players) do
		local player = playerState.entry.player
		if player and player.Parent then
			local side = playerState.entry.side or "Left"
			local descriptor

			if side == "Left" then
				descriptor = pickSpawn(leftSpawns, usedLeft)
			else
				descriptor = pickSpawn(rightSpawns, usedRight)
			end

			if not descriptor then
				descriptor = pickSpawn(sharedSpawns, usedShared)
			end

			if descriptor then
				local spawnCFrame = computeSurfaceCFrame(
					descriptor,
					self._config.SpawnSurfaceOffset or 0.25,
					self._config.RespawnExtraHeight or 0
				)
				if spawnCFrame then
					self:_anchorPlayer(playerState, spawnCFrame, holdMovement, descriptor)
					table.insert(teleportedPlayers, player)
				else
					warn(
						string.format("[BombMatchManager] Failed to compute spawn surface for %s", tostring(descriptor))
					)
				end
			else
				warn(string.format("[BombMatchManager] No spawn available for side '%s'", tostring(side)))
			end
		end
	end

	self:_emit("onPlayersTeleported", teleportedPlayers)
	return true
end

function ManagerMethods:_returnPlayersToLobby()
	local teleportedPlayers = {}
	local lobbyFallback = self._workspaceRefs and self._workspaceRefs.lobbySpawner or nil
	local fallbackCFrame = nil

	if lobbyFallback then
		fallbackCFrame = computeSurfaceCFrame(
			lobbyFallback,
			self._config.SpawnSurfaceOffset or 0.25,
			self._config.RespawnExtraHeight or 0
		)
	end

	for _, playerState in ipairs(self._state.players) do
		local player = playerState.entry.player
		if player and player.Parent then
			local slot = playerState.lobbySlot or playerState.entry.lobbySlot
			local targetCFrame = slot and slot.cframe or nil

			if not targetCFrame and fallbackCFrame then
				targetCFrame = fallbackCFrame
			end

			if targetCFrame then
				self:_anchorPlayer(playerState, targetCFrame, false, nil)
				if not player.Character then
					pcall(function()
						player:LoadCharacter()
					end)
				end
				table.insert(teleportedPlayers, player)
			else
				warn(string.format("[BombMatchManager] No lobby slot found for %s", player.Name))
			end
		end
	end

	if #teleportedPlayers > 0 then
		self:_emit("onPlayersTeleported", teleportedPlayers)
	end
end

function ManagerMethods:_normalizeEntries(entries)
	local normalized = {}
	local lookup = {}

	for _, entry in ipairs(entries) do
		if entry.player and entry.player.Parent then
			local existing = lookup[entry.player]
			if existing then
				existing.entry.side = entry.side
			else
				local state: InternalPlayerState = {
					entry = entry,
					alive = true,
					respawnCFrame = nil,
				}
				state.lobbySlot = entry.lobbySlot
				local hasAutoLoads, autoLoadsValue = pcall(function()
					return entry.player.CharacterAutoLoads
				end)
				if hasAutoLoads then
					state.autoLoadBackup = autoLoadsValue
					local successSet, setErr = pcall(function()
						entry.player.CharacterAutoLoads = false
					end)
					if not successSet then
						warn(
							string.format(
								"[BombMatchManager] Failed to disable auto loads for %s: %s",
								entry.player.Name,
								tostring(setErr)
							)
						)
						state.autoLoadBackup = autoLoadsValue
					end
				else
					state.autoLoadBackup = nil
				end
				table.insert(normalized, state)
				lookup[entry.player] = state
			end
		end
	end

	return normalized, lookup
end

function ManagerMethods:_sendGameStartSignal(kind, countdown)
	local payload = {
		kind = kind,
		countdown = countdown,
	}
	self:_forEachActivePlayer(function(player)
		self._remotes.GameStart:FireClient(player, payload)
	end)
end

function ManagerMethods:_broadcastCountdown(value, phase)
	self:_forEachActivePlayer(function(player)
		self._remotes.CountdownUpdate:FireClient(player, value, phase)
	end)
end

function ManagerMethods:_broadcastBombAssigned(player)
	self:_forEachActivePlayer(function(target)
		self._remotes.BombAssigned:FireClient(target, player.Name, self._config.BombCountdown)
	end)
end

function ManagerMethods:_broadcastBombPassed(fromPlayer, toPlayer)
	self:_forEachActivePlayer(function(player)
		self._remotes.BombPassed:FireClient(player, fromPlayer.Name, toPlayer.Name, self._state.bombTimer)
	end)
end

function ManagerMethods:_broadcastBombTimer()
	self:_forEachActivePlayer(function(player)
		self._remotes.BombTimerUpdate:FireClient(player, self._state.bombTimer)
	end)
end

function ManagerMethods:_broadcastPlayerEliminated(player)
	self:_forEachActivePlayer(function(target)
		self._remotes.PlayerEliminated:FireClient(target, player.Name)
	end)
end

function ManagerMethods:_broadcastMatchEnd(payload)
	self:_forEachActivePlayer(function(player)
		self._remotes.GameEnd:FireClient(player, payload)
	end)
end

function ManagerMethods:_alivePlayers()
	local alive = {}
	for _, playerState in ipairs(self._state.players) do
		if playerState.alive and playerState.entry.player.Parent then
			table.insert(alive, playerState.entry.player)
		end
	end
	return alive
end

function ManagerMethods:_selectRandomAlive(exclude)
	local alive = {}
	for _, player in ipairs(self:_alivePlayers()) do
		if player ~= exclude then
			table.insert(alive, player)
		end
	end
	if #alive == 0 then
		return nil
	end
	return alive[math.random(1, #alive)]
end

function ManagerMethods:_setBombHolder(player, shouldResetTimer)
	self._state.bombHolder = player
	self._state.passers[player] = nil
	if shouldResetTimer ~= false then
		self._state.bombTimer = self._config.BombCountdown
	end
	self:_broadcastBombAssigned(player)
	self:_broadcastBombTimer()
end

function ManagerMethods:_assignInitialBomb()
	local selected = self:_selectRandomAlive(nil)
	if not selected then
		return false
	end
	self:_setBombHolder(selected, true)
	return true
end

function ManagerMethods:_tryPassBomb(toPlayer)
	local currentHolder = self._state.bombHolder
	if not currentHolder or currentHolder == toPlayer then
		return
	end

	local currentState = self._state.playerLookup[currentHolder]
	local targetState = self._state.playerLookup[toPlayer]
	if not currentState or not targetState then
		return
	end

	-- teammates cannot pass bomb between themselves
	if currentState.entry.side == targetState.entry.side then
		return
	end

	local cooldown = self._config.BombPassCooldown or 0
	if cooldown > 0 and self._state.lastBombPassTick then
		if tick() - self._state.lastBombPassTick < cooldown then
			return
		end
	end

	self._state.bombHolder = toPlayer
	self._state.lastBombPassTick = tick()
	self._state.passers[toPlayer] = currentHolder
	self:_broadcastBombPassed(currentHolder, toPlayer)
	self:_broadcastBombTimer()
end

function ManagerMethods:_heartbeatUpdate()
	local holder = self._state.bombHolder
	if not holder then
		return
	end

	local holderCharacter = holder.Character
	local holderRoot = holderCharacter and holderCharacter:FindFirstChild("HumanoidRootPart")
	if not holderRoot then
		return
	end

	local passDistance = self._config.BombPassDistance or 10

	for _, playerState in ipairs(self._state.players) do
		if playerState.alive then
			local otherPlayer = playerState.entry.player
			if otherPlayer ~= holder then
				local character = otherPlayer.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if root then
					local distance = (holderRoot.Position - root.Position).Magnitude
					if distance <= passDistance then
						self:_tryPassBomb(otherPlayer)
						break
					end
				end
			end
		end
	end
end

function ManagerMethods:_beginTimerLoop()
	self._state.timerTask = task.spawn(function()
		while self._state.phase == "active" do
			task.wait(1)
			if self._state.phase ~= "active" then
				break
			end

			self._state.bombTimer -= 1
			self:_broadcastBombTimer()
			if self._state.bombTimer <= 0 then
				local holder = self._state.bombHolder
				if holder then
					self:_eliminatePlayer(holder, "explosion")
				end

				local winningSide = self:_evaluateRoundEnd()
				if winningSide then
					self:_finishRound(winningSide)
					return
				end

				self:_assignNextHolderAfterElimination()
			end
		end
	end)
end

function ManagerMethods:_assignNextHolderAfterElimination()
	local nextHolder = self:_selectRandomAlive(nil)
	if nextHolder then
		self:_setBombHolder(nextHolder)
	end
end

function ManagerMethods:_teamAliveCounts()
	local counts = { Left = 0, Right = 0 }
	for _, playerState in ipairs(self._state.players) do
		if playerState.alive and playerState.entry.player.Parent then
			counts[playerState.entry.side] += 1
		end
	end
	return counts
end

function ManagerMethods:_evaluateRoundEnd()
	local counts = self:_teamAliveCounts()
	if counts.Left == 0 and counts.Right == 0 then
		return "draw"
	elseif counts.Left == 0 then
		return "Right"
	elseif counts.Right == 0 then
		return "Left"
	else
		return nil
	end
end

function ManagerMethods:_eliminatePlayer(player, reason)
	local playerState = self._state.playerLookup[player]
	if not playerState or not playerState.alive then
		return
	end

	local killer = self._state.passers[player]
	self._state.passers[player] = nil

	playerState.alive = false
	self:_broadcastPlayerEliminated(player)
	self:_emit("onPlayerEliminated", player)

	if reason == "explosion" then
		if killer and killer.Parent then
			self:_registerKill(killer)
		end

		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then
			local explosion = Instance.new("Explosion")
			explosion.Position = root.Position
			explosion.BlastPressure = 0
			explosion.BlastRadius = 0
			explosion.Parent = Workspace
			game.Debris:AddItem(explosion, 0.25)
		end
	end

	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Health = 0
	end

	if self._state.bombHolder == player then
		self._state.bombHolder = nil
	end

	self:_scheduleRespawn(playerState, self._config.RespawnDelay or 2.5)
end

function ManagerMethods:_finishRound(winningSide)
	self:_cleanupRunners()
	self._state.lastBombPassTick = nil
	self:_setPhase("round_end")
	self._state.round += 1

	for _, playerState in ipairs(self._state.players) do
		self:_releaseMovement(playerState)
	end

	if winningSide == "Left" or winningSide == "Right" then
		self._state.teamScores[winningSide] += 1
	end
	local teamEntries = self:_collectTeamEntries()
	self:_broadcastScoreboard(self:_scoreboardPayload(true, true, teamEntries))

	local targetScore = self._config.RoundsToWin or 3
	local winningTeam
	if winningSide == "Left" and self._state.teamScores.Left >= targetScore then
		winningTeam = "Team 1"
	elseif winningSide == "Right" and self._state.teamScores.Right >= targetScore then
		winningTeam = "Team 2"
	end

	if winningTeam then
		local winningPlayers = {}
		local sideEntries = nil
		if winningSide == "Left" then
			sideEntries = teamEntries.Left
		elseif winningSide == "Right" then
			sideEntries = teamEntries.Right
		end
		if sideEntries then
			for _, player in ipairs(sideEntries) do
				if player and player.Parent then
					table.insert(winningPlayers, player)
				end
			end
		end
		self:_endMatch(winningTeam, winningSide, winningPlayers)
	else
		local respawnDelay = self._config.RoundRespawnDelay or self._config.RoundCooldown or 2.5
		task.delay(respawnDelay, function()
			if self._state.phase ~= "round_end" then
				return
			end
			if not self:_teleportPlayersToArena(true) then
				self:_endMatch(nil)
				return
			end
			self:_startRound()
		end)
	end
end

function ManagerMethods:_startRound()
	self:_cleanupRunners()
	self:_setPhase("prepare")

	for _, playerState in ipairs(self._state.players) do
		playerState.alive = playerState.entry.player.Parent ~= nil
	end

	self._state.countdownTask = task.spawn(function()
		local countdown = self._config.InitialCountdown or 3
		self:_sendGameStartSignal("prepare", countdown)

		while countdown > 0 and self._state.phase == "prepare" do
			self:_broadcastCountdown(countdown, "prepare")
			task.wait(1)
			countdown -= 1
		end

		if self._state.phase ~= "prepare" then
			return
		end

		self:_broadcastCountdown(0, "prepare")
		task.wait(0.3)
		self:_broadcastCountdown(-1, "prepare")
		self:_activateRound()
	end)
end

function ManagerMethods:_activateRound()
	self:_setPhase("active")

	self:_releaseAllMovement()
	self:_broadcastScoreboard(self:_scoreboardPayload(true, true, self:_collectTeamEntries()))

	if not self:_assignInitialBomb() then
		warn("[BombMatchManager] Unable to assign initial bomb holder")
		self:_finishRound("draw")
		return
	end

	self._state.heartbeatConn = RunService.Heartbeat:Connect(function()
		if self._state.phase ~= "active" then
			return
		end
		self:_heartbeatUpdate()
	end)

	self:_beginTimerLoop()
end

function ManagerMethods:_endMatch(winningTeam, winningSide, winningPlayers)
	self:_cleanupRunners()
	self:_setPhase("match_end")
	self:_releaseAllMovement()
	self:_restoreAutoLoads()
	self._state.lastBombPassTick = nil
	self:_broadcastScoreboard(self:_scoreboardPayload(false, false, { Left = {}, Right = {} }))
	local winnerPlayers = {}
	if winningPlayers then
		for _, player in ipairs(winningPlayers) do
			if player and player.Parent then
				table.insert(winnerPlayers, player)
			end
		end
	end

	local coinsAwarded = #winnerPlayers > 0 and (self._config.WinnerCoins or 0) or 0
	if #winnerPlayers > 0 then
		self:_emit("onMatchWinners", {
			players = winnerPlayers,
			coins = coinsAwarded,
			side = winningSide,
		})
	end

	local winnerPayload = {}
	for _, player in ipairs(winnerPlayers) do
		table.insert(winnerPayload, {
			UserId = player.UserId,
			Name = player.Name,
			DisplayName = player.DisplayName,
		})
	end

	local winnerLookup = {}
	for _, player in ipairs(winnerPlayers) do
		winnerLookup[player] = true
	end

	local matchSeconds = 0
	if self._state.matchStartTick and self._state.matchStartTick > 0 then
		matchSeconds = math.max(0, math.floor(tick() - self._state.matchStartTick))
	end

	for _, playerState in ipairs(self._state.players) do
		local player = playerState.entry.player
		if player and player.Parent then
			if winnerLookup[player] then
				self:_updatePlayerStats(player, {
					win = 1,
					addToStreak = 1,
					matchSeconds = matchSeconds,
				})
			else
				self:_updatePlayerStats(player, {
					resetStreak = winningTeam ~= nil,
					matchSeconds = matchSeconds,
				})
			end
		end
	end

	self:_broadcastMatchEnd({
		teamName = winningTeam,
		teamSide = winningSide,
		coins = coinsAwarded,
		winners = winnerPayload,
	})
	self:_emit("onMatchEnded")

	local returnDelay = self._config.RoundRespawnDelay or self._config.RoundCooldown or 2.5
	if self._state.pendingLobbyReturnTask then
		pcall(task.cancel, self._state.pendingLobbyReturnTask)
		self._state.pendingLobbyReturnTask = nil
	end

	local matchId = self._state.matchId
	self._state.pendingLobbyReturnTask = task.delay(returnDelay, function()
		self._state.pendingLobbyReturnTask = nil
		-- Ensure we are still finishing this match
		if self._state.matchId ~= matchId or self._state.phase ~= "match_end" then
			return
		end
		self:_returnPlayersToLobby()
		self:_setPhase("idle")
		self:_resetRuntime()
		self._state.matchId += 1
	end)
end

function ManagerMethods:startMatch(entries)
	if self._state.phase ~= "idle" then
		return false, "match_active"
	end

	local normalized, lookup = self:_normalizeEntries(entries)
	if #normalized < (self._config.MinPlayers or 2) then
		return false, "not_enough_players"
	end

	self:_cleanupRunners()
	self:_resetRuntime()

	self._state.players = normalized
	self._state.playerLookup = lookup
	self._state.phase = "teleport"
	self._state.round = 0
	self._state.teamScores = { Left = 0, Right = 0 }
	self._state.generation += 1
	self._state.matchId += 1
	self._state.lastBombPassTick = nil

	self:_broadcastScoreboard(self:_scoreboardPayload(false, true, self:_collectTeamEntries()))

	if not self:_teleportPlayersToArena(true) then
		self:_endMatch(nil)
		return false, "teleport_failed"
	end

	self:_emit("onMatchStarted", {
		matchId = self._state.matchId,
		round = self._state.round,
		players = deepCloneArray(entries),
	})

	self._state.matchStartTick = tick()

	self:_startRound()
	return true
end

function ManagerMethods:isMatchActive()
	return self._state.phase == "active"
end

function ManagerMethods:handlePlayerDeath(player)
	if self._state.phase ~= "active" then
		return
	end

	self:_eliminatePlayer(player, "death")
	local outcome = self:_evaluateRoundEnd()
	if outcome then
		self:_finishRound(outcome)
	end
end

function ManagerMethods:removePlayer(player)
	local playerState = self._state.playerLookup[player]
	if not playerState then
		return
	end

	self._state.passers[player] = nil
	if self._state.phase ~= "idle" then
		self:_updatePlayerStats(player, { resetStreak = true })
	end

	if player and player.Parent then
		local desired = playerState.autoLoadBackup ~= nil and playerState.autoLoadBackup or true
		local successSet, setErr = pcall(function()
			player.CharacterAutoLoads = desired
		end)
		if not successSet then
			warn(
				string.format(
					"[BombMatchManager] Failed to restore auto loads for %s: %s",
					player.Name,
					tostring(setErr)
				)
			)
		end
	end

	playerState.alive = false
	self:_broadcastPlayerEliminated(player)

	local outcome = self:_evaluateRoundEnd()
	if outcome then
		self:_finishRound(outcome)
	end
end

function ManagerMethods:publishLobbySnapshot(entries, showPoints)
	local normalized = {}
	for _, entry in ipairs(entries) do
		if entry.player and entry.player.Parent then
			table.insert(normalized, entry)
		end
	end

	local teams = { Left = {}, Right = {} }
	local players = {}
	for _, entry in ipairs(normalized) do
		if entry.side == "Left" then
			table.insert(teams.Left, entry.player)
		else
			table.insert(teams.Right, entry.player)
		end
		table.insert(players, entry.player)
	end

	self:_broadcastScoreboard({
		active = false,
		showReadiness = true,
		showPoints = showPoints,
		scores = {
			Left = self._state.teamScores.Left,
			Right = self._state.teamScores.Right,
		},
		team1 = (function()
			local arr = {}
			for _, player in ipairs(teams.Left) do
				table.insert(arr, { UserId = player.UserId, Name = player.Name })
			end
			return arr
		end)(),
		team2 = (function()
			local arr = {}
			for _, player in ipairs(teams.Right) do
				table.insert(arr, { UserId = player.UserId, Name = player.Name })
			end
			return arr
		end)(),
	}, players)
end

function ManagerMethods:endMatch(reason)
	if self._state.phase == "idle" then
		return
	end
	warn("[BombMatchManager] Ending match:", reason or "no reason provided")
	self:_endMatch(nil)
end

-- Singleton API -------------------------------------------------------------------------

function BombMatchManager.init(deps)
	if singleton then
		error("[BombMatchManager] Already initialized", 2)
	end

	local manager = setmetatable({}, BombMatchManager)
	manager._remotes = {
		GameStart = assertRemote(deps.remotes, "GameStart"),
		CountdownUpdate = assertRemote(deps.remotes, "CountdownUpdate"),
		BombAssigned = assertRemote(deps.remotes, "BombAssigned"),
		BombPassed = assertRemote(deps.remotes, "BombPassed"),
		BombTimerUpdate = assertRemote(deps.remotes, "BombTimerUpdate"),
		PlayerEliminated = assertRemote(deps.remotes, "PlayerEliminated"),
		GameEnd = assertRemote(deps.remotes, "GameEnd"),
		ScoreboardUpdate = assertRemote(deps.remotes, "ScoreboardUpdate"),
	}

	manager._configModule = deps.config
	manager._config = requireConfig(deps.config)
	manager._workspaceRefs = deps.workspaceRefs
	manager._callbacks = deps.callbacks or {}
	manager._spawnDescriptors = gatherSpawnDescriptors(deps.workspaceRefs.level)
	manager._state = newState()

	singleton = setmetatable(manager, ManagerMethods)
	return singleton
end

function BombMatchManager.get()
	if not singleton then
		error("[BombMatchManager] Not initialized", 2)
	end
	return singleton
end

return BombMatchManager
