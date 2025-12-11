local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")

local BOMB_TAG_ATTRIBUTE = "BombTagActive"

local PlayerProfile = require(ServerScriptService:WaitForChild("PlayerProfile"))
local Leaderboards = require(ServerScriptService:WaitForChild("Leaderboards"))

local BombLevelFFAController = {}
BombLevelFFAController.__index = BombLevelFFAController

type CallbackTable = {
	onPlayerJoined: ((Player, any) -> ())?,
	onPlayerLeft: ((Player, any) -> ())?,
}

type ControllerArgs = {
	level: Model | Folder,
	lobbySpawner: BasePart | Model?,
	remotes: {
		GameStart: RemoteEvent,
		CountdownUpdate: RemoteEvent,
		BombAssigned: RemoteEvent,
		BombPassed: RemoteEvent,
		BombTimerUpdate: RemoteEvent,
		PlayerEliminated: RemoteEvent,
		GameEnd: RemoteEvent,
		ScoreboardUpdate: RemoteEvent,
		PlatformPrompt: RemoteEvent?,
		ReadyStatus: RemoteEvent?,
		ReadyWarning: RemoteEvent?,
		ReadyToggle: RemoteEvent?,
	},
	configModule: ModuleScript?,
	config: table?,
	levelId: string?,
	levelName: string?,
	callbacks: CallbackTable?,
}

type PlayerData = {
	kills: number,
	joinOrder: number,
	deathConn: RBXScriptConnection?,
	charAddedConn: RBXScriptConnection?,
	currentSpawn: Instance?,
}

type BombRecord = {
	id: number,
	holder: Player?,
	timer: number,
	active: boolean,
	task: thread?,
	lastPassTick: number?,
	lastPasser: Player?,
}

local DEFAULT_BOMB_COUNTDOWN = 15
local DEFAULT_PASS_DISTANCE = 10
local DEFAULT_PASS_COOLDOWN = 1
local DEFAULT_RESPAWN_DELAY = 2.5

local function isPlayerActive(player: Player?): boolean
	if not player or not player.Parent then
		return false
	end
	local ok, value = pcall(player.GetAttribute, player, BOMB_TAG_ATTRIBUTE)
	if not ok then
		return false
	end
	return value == true
end

local function computeSurfaceCFrameForObject(object, offset, config)
	if not object then
		return nil
	end

	offset = offset or 0
	local extraHeight = (config and config.RespawnExtraHeight) or 0

	local baseCFrame
	local size

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

	local up = baseCFrame.UpVector.Unit
	local position = baseCFrame.Position + up * ((size.Y / 2) + offset + extraHeight)

	return CFrame.fromMatrix(position, baseCFrame.XVector, baseCFrame.YVector, baseCFrame.ZVector)
end

local function findFirstDescendant(instance, predicate)
	if not instance then
		return nil
	end
	if predicate(instance) then
		return instance
	end
	for _, descendant in ipairs(instance:GetDescendants()) do
		if predicate(descendant) then
			return descendant
		end
	end
	return nil
end

local function gatherDescendants(instance, predicate)
	local results = {}
	if not instance then
		return results
	end
	if predicate(instance) then
		table.insert(results, instance)
	end
	for _, descendant in ipairs(instance:GetDescendants()) do
		if predicate(descendant) then
			table.insert(results, descendant)
		end
	end
	return results
end

local function teleportCharacterToCFrame(character: Model?, targetCFrame: CFrame?, config: table?)
	if not character or not targetCFrame then
		return false
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not rootPart then
		return false
	end

	humanoid.PlatformStand = true
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0

	rootPart.CFrame = targetCFrame
	rootPart.AssemblyLinearVelocity = Vector3.zero

	task.defer(function()
		if humanoid.Parent then
			humanoid.PlatformStand = false
			humanoid.WalkSpeed = (config and config.PlayerDefaultWalkSpeed) or 16
			humanoid.JumpPower = (config and config.PlayerDefaultJumpPower) or 50
		end
	end)

	return true
end

local function serializePlayer(player: Player?)
	if not player then
		return nil
	end
	return {
		UserId = player.UserId,
		Name = player.Name,
		DisplayName = player.DisplayName,
	}
end

function BombLevelFFAController.new(args: ControllerArgs)
	local self = setmetatable({}, BombLevelFFAController)

	self._level = args.level
	self._lobbySpawner = args.lobbySpawner
	self._remotes = args.remotes or {}
	self._config = args.config or (args.configModule and require(args.configModule)) or {}
	self._levelId = args.levelId or (self._level and self._level.Name) or "BombLevelFFA"
	self._levelName = args.levelName or self._levelId
	self._callbacks = args.callbacks or {}

	self._platform = findFirstDescendant(self._level, function(child)
		return child:IsA("BasePart") and child.Name == "Platform"
	end)

	self._spawns = gatherDescendants(self._level, function(child)
		if child:IsA("BasePart") or child:IsA("Model") then
			return child.Name == "Spawn" or child.Name:match("^Spawn%d+$")
		end
		return false
	end)

	self._players = {}
	self._playerData = {}
	self._bombRecords = {}
	self._holderToBomb = {}
	self._bombSequence = 0
	self._joinCounter = 0
	self._occupiedSpawns = {}
	self._destroyed = false
	self._timerDirty = false
	self._lastTimerBroadcast = 0

	if self._platform then
		self._platformTouchedConn = self._platform.Touched:Connect(function(part)
			self:_onPlatformTouched(part)
		end)
	else
		warn(string.format("[BombTag][FFA] Platform not found for level '%s'", tostring(self._levelId)))
	end

	self._heartbeatConn = RunService.Heartbeat:Connect(function()
		self:_onHeartbeat()
	end)

	return self
end

function BombLevelFFAController:_attachMetadata(payload)
	payload = payload or {}
	if payload.levelId == nil then
		payload.levelId = self._levelId
	end
	if payload.levelName == nil then
		payload.levelName = self._levelName
	end
	payload.mode = payload.mode or "FFA"
	return payload
end

function BombLevelFFAController:_fireClient(remote, player, payload)
	if not remote or not player or not player.Parent then
		return
	end
	remote:FireClient(player, self:_attachMetadata(payload))
end

function BombLevelFFAController:_broadcast(remote, payload)
	if not remote then
		return
	end
	local finalPayload = self:_attachMetadata(payload)
	for player in pairs(self._players) do
		if player and player.Parent then
			remote:FireClient(player, finalPayload)
		end
	end
end

function BombLevelFFAController:_markTimersDirty()
	self._timerDirty = true
end

function BombLevelFFAController:_ensurePlayerData(player: Player): PlayerData
	local data = self._playerData[player]
	if not data then
		data = {
			kills = 0,
			joinOrder = 0,
			deathConn = nil,
			charAddedConn = nil,
			currentSpawn = nil,
		}
		self._playerData[player] = data
	end
	return data
end

function BombLevelFFAController:_addPlayer(player: Player)
	if self._destroyed then
		return
	end

	if self._players[player] then
		if isPlayerActive(player) then
			-- Player is already registered; ensure scoreboard and timers stay up to date.
			self:_pushScoreboard()
			self:_ensureBombTargets()
			return
		end

		-- Player is tracked but inactive; clean up stale state to allow a fresh join.
		self:_removePlayer(player, "refresh", true)
	end

	self._players[player] = true

	local data = self:_ensurePlayerData(player)
	self._joinCounter += 1
	data.joinOrder = self._joinCounter
	self._playerData[player] = data

	if data.charAddedConn then
		data.charAddedConn:Disconnect()
	end

	data.charAddedConn = player.CharacterAdded:Connect(function(character)
		self:_onCharacterAdded(player, character)
	end)

	if player.Character then
		self:_onCharacterAdded(player, player.Character)
	end

	if self._callbacks.onPlayerJoined then
		task.defer(self._callbacks.onPlayerJoined, player, self)
	end

	self:_fireClient(self._remotes.GameStart, player, {
		active = true,
		mode = "FFA",
	})

	self:_fireClient(self._remotes.ReadyToggle, player, {
		enabled = true,
		mode = "FFA",
		reason = "enter",
		label = "Leave",
	})

	self:_pushScoreboard()
	self:_ensureBombTargets()
end

function BombLevelFFAController:_removePlayer(player: Player, reason: string?, skipTeleport: boolean?)
	if not self._players[player] then
		return
	end

	self._players[player] = nil

	local data = self._playerData[player]
	if data then
		if data.currentSpawn then
			self._occupiedSpawns[data.currentSpawn] = nil
			data.currentSpawn = nil
		end
		if data.deathConn then
			data.deathConn:Disconnect()
			data.deathConn = nil
		end
		if data.charAddedConn then
			data.charAddedConn:Disconnect()
			data.charAddedConn = nil
		end
	end

	local record = self._holderToBomb[player]
	if record then
		self:_handleHolderRemoved(record, "leave")
	end

	self._holderToBomb[player] = nil

	if not skipTeleport then
		self:_teleportPlayerToLobby(player)
	end

	self:_fireClient(self._remotes.ScoreboardUpdate, player, {
		active = false,
		mode = "FFA",
		topKillers = {},
	})

	self:_fireClient(self._remotes.ReadyToggle, player, {
		enabled = false,
		mode = "FFA",
		reason = reason or "leave",
	})

	self:_fireClient(self._remotes.GameEnd, player, {
		active = false,
		mode = "FFA",
		reason = reason or "leave",
	})

	if self._callbacks.onPlayerLeft then
		task.defer(self._callbacks.onPlayerLeft, player, self)
	end

	self:_pushScoreboard()
	self:_ensureBombTargets()
end

function BombLevelFFAController:_forEachParticipant(callback)
	for player in pairs(self._players) do
		if player and player.Parent then
			callback(player)
		end
	end
end

function BombLevelFFAController:_teleportPlayerToSpawn(player: Player)
	if not player or not player.Parent then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	if #self._spawns == 0 then
		warn(string.format("[BombTag][FFA] No spawn points configured for '%s'", tostring(self._levelId)))
		return
	end

	local data = self._playerData[player]
	if data and data.currentSpawn then
		self._occupiedSpawns[data.currentSpawn] = nil
		data.currentSpawn = nil
	end

	local available = {}
	for _, spawnObject in ipairs(self._spawns) do
		if spawnObject and spawnObject.Parent and not self._occupiedSpawns[spawnObject] then
			table.insert(available, spawnObject)
		end
	end

	local spawnObject
	if #available > 0 then
		spawnObject = available[math.random(1, #available)]
	else
		spawnObject = self._spawns[math.random(1, #self._spawns)]
	end
	local targetCFrame = computeSurfaceCFrameForObject(
		spawnObject,
		self._config.SpawnSurfaceOffset or 0,
		self._config
	)

	if not targetCFrame then
		return
	end

	if teleportCharacterToCFrame(character, targetCFrame, self._config) then
		local ensured = self:_ensurePlayerData(player)
		ensured.currentSpawn = spawnObject
		self._occupiedSpawns[spawnObject] = player
	end
end

function BombLevelFFAController:_teleportPlayerToLobby(player: Player)
	if not player or not player.Parent then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	local spawnObject = self._lobbySpawner or Workspace:FindFirstChild("BombLobbySpawner")
	if not spawnObject then
		return
	end

	local targetCFrame = computeSurfaceCFrameForObject(
		spawnObject,
		self._config.SpawnSurfaceOffset or 0.25,
		self._config
	)

	if not targetCFrame then
		return
	end

	teleportCharacterToCFrame(character, targetCFrame, self._config)
end

function BombLevelFFAController:_onCharacterAdded(player: Player, character: Model)
	if not self._players[player] then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		if self._playerData[player] then
			local previousConn = self._playerData[player].deathConn
			if previousConn then
				previousConn:Disconnect()
			end
			self._playerData[player].deathConn = humanoid.Died:Connect(function()
				self:_onPlayerDied(player)
			end)
		end
	end

	task.defer(function()
		self:_teleportPlayerToSpawn(player)
	end)
end

function BombLevelFFAController:_onPlayerDied(player: Player)
	if not self._players[player] then
		return
	end

	local record = self._holderToBomb[player]
	if record then
		self:_explodeBomb(record, "death")
	end

	task.delay(self._config.RespawnDelay or DEFAULT_RESPAWN_DELAY, function()
		if self._players[player] and player.Parent and player.Character then
			self:_teleportPlayerToSpawn(player)
		end
	end)
end

function BombLevelFFAController:_onPlatformTouched(part: BasePart)
	if self._destroyed then
		return
	end

	local character = part.Parent
	if not character then
		return
	end

	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end

	self:_addPlayer(player)
end

function BombLevelFFAController:_collectActivePlayers()
	local players = {}
	for player in pairs(self._players) do
		if player.Parent then
			table.insert(players, player)
		end
	end
	return players
end

function BombLevelFFAController:_getDesiredBombCount()
	local activePlayers = self:_collectActivePlayers()
	local count = #activePlayers
	if count < 2 then
		return 0
	end
	if count > 4 then
		return math.min(2, count)
	end
	return 1
end

function BombLevelFFAController:_ensureBombTargets()
	if self._destroyed then
		return
	end

	local desired = self:_getDesiredBombCount()
	local activeRecords = {}
	for _, record in pairs(self._bombRecords) do
		if record.active then
			table.insert(activeRecords, record)
		end
	end

	if #activeRecords > desired then
		local excess = #activeRecords - desired
		for _, record in ipairs(activeRecords) do
			if excess <= 0 then
				break
			end
			self:_deactivateBomb(record, "excess")
			excess -= 1
		end
	elseif #activeRecords < desired then
		local deficit = desired - #activeRecords
		for _ = 1, deficit do
			local candidate = self:_selectBombHolder()
			if candidate then
				self:_assignBomb(candidate)
			end
		end
	end

	self:_markTimersDirty()
end

function BombLevelFFAController:_selectBombHolder()
	local candidates = {}
	for player in pairs(self._players) do
		if player.Parent and not self._holderToBomb[player] then
			table.insert(candidates, player)
		end
	end

	if #candidates == 0 then
		return nil
	end

	local index = math.random(1, #candidates)
	return candidates[index]
end

function BombLevelFFAController:_assignBomb(player: Player)
	if self._holderToBomb[player] then
		return
	end

	self._bombSequence += 1
	local record: BombRecord = {
		id = self._bombSequence,
		holder = player,
		timer = self._config.BombCountdown or DEFAULT_BOMB_COUNTDOWN,
		active = true,
		task = nil,
		lastPassTick = tick(),
		lastPasser = nil,
	}

	self._bombRecords[record.id] = record
	self._holderToBomb[player] = record

	self:_broadcast(self._remotes.BombAssigned, {
		mode = "FFA",
		bombId = record.id,
		holder = serializePlayer(player),
		timer = record.timer,
	})

	self:_startBombTimer(record)
	self:_markTimersDirty()
end

function BombLevelFFAController:_cancelBombTask(record: BombRecord)
	if not record or not record.task then
		return
	end

	local thread = record.task
	if thread == coroutine.running() then
		record.task = nil
		return
	end

	local ok, err = pcall(task.cancel, thread)
	if not ok and err ~= "cannot cancel thread" then
		warn(string.format("[BombTag][FFA] Failed to cancel bomb timer %s: %s", tostring(record.id), tostring(err)))
	end
	record.task = nil
end

function BombLevelFFAController:_startBombTimer(record: BombRecord)
	if record.task then
		self:_cancelBombTask(record)
	end

	record.task = task.spawn(function()
		while record.active do
			task.wait(1)
			if not record.active then
				break
			end
			record.timer -= 1
			if record.timer <= 0 then
				self:_explodeBomb(record, "timer")
				break
			end
			self:_markTimersDirty()
		end
	end)
end

function BombLevelFFAController:_handleHolderRemoved(record: BombRecord, reason: string)
	if not record.active then
		return
	end

	local previousHolder = record.holder
	if previousHolder then
		self._holderToBomb[previousHolder] = nil
	end

	local replacement = self:_selectBombHolder()
	if replacement then
		record.holder = replacement
		record.lastPasser = nil
		record.lastPassTick = tick()
		self._holderToBomb[replacement] = record
		self:_broadcast(self._remotes.BombAssigned, {
			mode = "FFA",
			bombId = record.id,
			holder = serializePlayer(replacement),
			timer = record.timer,
			reason = reason,
		})
	else
		self:_deactivateBomb(record, reason)
	end

	self:_markTimersDirty()
end

function BombLevelFFAController:_deactivateBomb(record: BombRecord, reason: string?)
	if not record.active then
		return
	end

	record.active = false

	self:_cancelBombTask(record)

	if record.holder then
		if self._holderToBomb[record.holder] == record then
			self._holderToBomb[record.holder] = nil
		end
	end

	self._bombRecords[record.id] = nil

	self:_markTimersDirty()
end

function BombLevelFFAController:_explodeBomb(record: BombRecord, cause: string)
	if not record.active then
		return
	end

	record.active = false

	self:_cancelBombTask(record)

	local holder = record.holder
	if holder and self._holderToBomb[holder] == record then
		self._holderToBomb[holder] = nil
	end

	self._bombRecords[record.id] = nil

	if holder and holder.Parent then
		local killer = record.lastPasser
		if killer and killer ~= holder and self._players[killer] then
			self:_registerKill(killer)
		end

		local character = holder.Character
		if character then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				humanoid.Health = 0
			end

			local root = character:FindFirstChild("HumanoidRootPart")
			if root then
				local explosion = Instance.new("Explosion")
				explosion.BlastPressure = 0
				explosion.BlastRadius = 0
				explosion.Position = root.Position
				explosion.Parent = Workspace
				game:GetService("Debris"):AddItem(explosion, 0.25)
			end
		end

		self:_broadcast(self._remotes.PlayerEliminated, {
			mode = "FFA",
			player = serializePlayer(holder),
			cause = cause,
		})
	end

	self:_markTimersDirty()
	self:_pushScoreboard()
	self:_ensureBombTargets()
end

function BombLevelFFAController:_registerKill(player: Player)
	local data = self._playerData[player]
	if not data then
		return
	end

	data.kills = (data.kills or 0) + 1
	PlayerProfile.updateMatchStats(player.UserId, { kills = 1 })
	Leaderboards.RecordDailyKill(player.UserId, 1)
	Leaderboards.RecordKillAllTime(player.UserId, 1)

	self:_broadcast(self._remotes.ScoreboardUpdate, {
		mode = "FFA",
		topKillers = self:_collectTopKillers(3),
		active = true,
	})
end

function BombLevelFFAController:_collectTopKillers(limit: number)
	local entries = {}
	for player, data in pairs(self._playerData) do
		if self._players[player] and player.Parent then
			table.insert(entries, {
				player = player,
				kills = data.kills or 0,
				joinOrder = data.joinOrder or math.huge,
			})
		end
	end

	table.sort(entries, function(a, b)
		if a.kills ~= b.kills then
			return a.kills > b.kills
		end
		if a.joinOrder ~= b.joinOrder then
			return a.joinOrder < b.joinOrder
		end
		return (a.player.UserId or 0) < (b.player.UserId or 0)
	end)

	local results = {}
	for index = 1, math.min(limit, #entries) do
		local entry = entries[index]
		table.insert(results, {
			UserId = entry.player.UserId,
			Name = entry.player.Name,
			DisplayName = entry.player.DisplayName,
			Kills = entry.kills,
		})
	end
	return results
end

function BombLevelFFAController:_pushScoreboard()
	local payload = {
		mode = "FFA",
		active = next(self._players) ~= nil,
		topKillers = self:_collectTopKillers(3),
	}
	self:_broadcast(self._remotes.ScoreboardUpdate, payload)
end

function BombLevelFFAController:_broadcastTimersIfNeeded()
	if not self._timerDirty then
		return
	end
	if tick() - self._lastTimerBroadcast < 0.2 then
		return
	end

	self._timerDirty = false
	self._lastTimerBroadcast = tick()

	local bombs = {}
	for _, record in pairs(self._bombRecords) do
		if record.active and record.holder and self._players[record.holder] then
			table.insert(bombs, {
				bombId = record.id,
				holder = serializePlayer(record.holder),
				timer = record.timer,
			})
		end
	end

	self:_broadcast(self._remotes.BombTimerUpdate, {
		mode = "FFA",
		bombs = bombs,
	})
end

function BombLevelFFAController:_attemptBombPass(record: BombRecord)
	if not record.active then
		return
	end

	local holder = record.holder
	if not isPlayerActive(holder) then
		self:_handleHolderRemoved(record, "lost_holder")
		return
	end

	local holderCharacter = holder.Character
	local holderRoot = holderCharacter and holderCharacter:FindFirstChild("HumanoidRootPart")
	if not holderRoot then
		return
	end

	local cooldown = self._config.BombPassCooldown or DEFAULT_PASS_COOLDOWN
	if record.lastPassTick and tick() - record.lastPassTick < cooldown then
		return
	end

	local distanceThreshold = self._config.BombPassDistance or DEFAULT_PASS_DISTANCE

	for player in pairs(self._players) do
		if player ~= holder and isPlayerActive(player) and not self._holderToBomb[player] then
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root then
				local distance = (holderRoot.Position - root.Position).Magnitude
				if distance <= distanceThreshold then
					record.lastPasser = holder
					record.holder = player
					record.lastPassTick = tick()

					self._holderToBomb[holder] = nil
					self._holderToBomb[player] = record

					self:_broadcast(self._remotes.BombPassed, {
						mode = "FFA",
						bombId = record.id,
						from = serializePlayer(holder),
						to = serializePlayer(player),
						timer = record.timer,
					})

					self:_markTimersDirty()
					break
				end
			end
		end
	end
end

function BombLevelFFAController:_onHeartbeat()
	if self._destroyed then
		return
	end

	for _, record in pairs(self._bombRecords) do
		self:_attemptBombPass(record)
	end

	for _, record in pairs(self._bombRecords) do
		local holder = record.holder
		if not holder or not holder.Parent or not self._players[holder] then
			self:_handleHolderRemoved(record, "invalid_holder")
		end
	end

	self:_broadcastTimersIfNeeded()
end

function BombLevelFFAController:ownsPlayer(player: Player)
	return self._players[player] == true
end

function BombLevelFFAController:handleReadyToggle(player: Player)
	self:_removePlayer(player, "leave")
end

function BombLevelFFAController:onPlayerRemoving(player: Player)
	self:_removePlayer(player, "player_removing")
end

function BombLevelFFAController:onCharacterRemoving(_player: Player)
	-- handled via Humanoid.Died callbacks for FFA
end

function BombLevelFFAController:destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true

	if self._platformTouchedConn then
		self._platformTouchedConn:Disconnect()
		self._platformTouchedConn = nil
	end

	if self._heartbeatConn then
		self._heartbeatConn:Disconnect()
		self._heartbeatConn = nil
	end

	for _, record in pairs(self._bombRecords) do
		self:_deactivateBomb(record, "destroy")
	end

	for player in pairs(self._players) do
		self:_removePlayer(player, "destroy")
	end

	self._players = {}
	self._playerData = {}
	self._bombRecords = {}
	self._holderToBomb = {}
end

return BombLevelFFAController


