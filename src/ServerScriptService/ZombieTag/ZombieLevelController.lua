local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local BOMB_TAG_ATTRIBUTE = "BombTagActive"
local ZOMBIE_TAG_ACTIVE = "ZombieTagActive"
local ZOMBIE_IS_INFECTED = "ZombieIsInfected"
local ZOMBIE_ROUND_FROZEN = "ZombieRoundFrozen"
local ZOMBIE_HIGHLIGHT_NAME = "ZombieInfectionHighlight"
local SURVIVOR_HIGHLIGHT_NAME = "ZombieSurvivorHighlight"
local LOG_PREFIX = "[ZombieTag]"
local ZombieTagFolder = ServerScriptService:WaitForChild("ZombieTag")
local ZombieUtils = require(ZombieTagFolder:WaitForChild("ZombieUtils"))
local ZombieSpawnAllocator = require(ZombieTagFolder:WaitForChild("ZombieSpawnAllocator"))
local ZombieRoleHelpers = require(ZombieTagFolder:WaitForChild("ZombieRoleHelpers"))
local ZombiePlatformTracker = require(ZombieTagFolder:WaitForChild("ZombiePlatformTracker"))
local ZombiePayloadBuilder = require(ZombieTagFolder:WaitForChild("ZombiePayloadBuilder"))
local PlayerProfileModule = ServerScriptService:FindFirstChild("PlayerProfile")
local PlayerProfile = nil
if PlayerProfileModule then
	local ok, mod = pcall(require, PlayerProfileModule)
	if ok then
		PlayerProfile = mod
	else
		warn(string.format("%s Failed to load PlayerProfile: %s", LOG_PREFIX, tostring(mod)))
	end
end

local ZombieLevelController = {}
ZombieLevelController.__index = ZombieLevelController

type CallbackTable = {
	onPlayerJoined: ((Player, any) -> ())?,
	onPlayerLeft: ((Player, any) -> ())?,
}

type ControllerArgs = {
	level: Model | Folder,
	lobbySpawner: BasePart | Model?,
	remotes: {
		GameStart: RemoteEvent,
		GameEnd: RemoteEvent,
		ReadyToggle: RemoteEvent,
		ZombieTagSync: RemoteEvent,
		ZombieTagAction: RemoteEvent?,
		CurrencyUpdated: RemoteEvent?,
	},
	configModule: ModuleScript?,
	config: table?,
	levelId: string?,
	levelName: string?,
	callbacks: CallbackTable?,
}

local computeSurfaceCFrameForObject = ZombieUtils.computeSurfaceCFrameForObject
local findFirstDescendant = ZombieUtils.findFirstDescendant
local gatherDescendants = ZombieUtils.gatherDescendants
local teleportCharacterToCFrame = ZombieUtils.teleportCharacterToCFrame

local function removeZombieHighlight(character: Model)
	if not character then
		return
	end
	local h = character:FindFirstChild(ZOMBIE_HIGHLIGHT_NAME)
	if h then
		h:Destroy()
	end
end

local function removeSurvivorHighlight(character: Model)
	if not character then
		return
	end
	local h = character:FindFirstChild(SURVIVOR_HIGHLIGHT_NAME)
	if h then
		h:Destroy()
	end
end

local function clearRoleHighlights(character: Model)
	removeZombieHighlight(character)
	removeSurvivorHighlight(character)
end

function ZombieLevelController.new(args: ControllerArgs)
	local self = setmetatable({}, ZombieLevelController)

	self._level = args.level
	self._lobbySpawner = args.lobbySpawner
	self._remotes = args.remotes or {}
	self._config = args.config or (args.configModule and require(args.configModule)) or {}
	self._levelId = args.levelId or (self._level and self._level.Name) or "ZombieLevel"
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
	self._zombies = {}
	self._playerData = {}
	self._joinCounter = 0
	self._occupiedSpawns = {}
	self._zombieSpawnPool = {}
	self._humanSpawnPool = {}
	self._humanImmunityUntil = {}
	self._platformTracker = ZombiePlatformTracker.new(self._platform)
	self._destroyed = false

	self._phase = "idle"
	self._matchStarted = false
	self._roundEndsAt = 0
	self._lobbyCountdownEndsAt = 0
	self._lobbyTask = nil
	self._prepareCountdownEndsAt = 0
	self._prepareTask = nil
	self._intermissionEndsAt = 0
	self._lastStateBroadcast = 0

	if self._platform then
		print(string.format("%s Controller init level=%s platform=%s spawns=%d", LOG_PREFIX, tostring(self._levelId), self._platform:GetFullName(), #self._spawns))
		self._platformTouchedConn = self._platform.Touched:Connect(function(part)
			self:_onPlatformTouched(part)
		end)
		if self._platform.TouchEnded then
			self._platformTouchEndedConn = self._platform.TouchEnded:Connect(function(part)
				self:_onPlatformTouchEnded(part)
			end)
		end
	else
		warn(string.format("[ZombieTag] Platform not found for level '%s'", tostring(self._levelId)))
	end

	self._heartbeatConn = RunService.Heartbeat:Connect(function()
		self:_onHeartbeat()
	end)

	return self
end

function ZombieLevelController:_attachMetadata(payload)
	payload = payload or {}
	if payload.levelId == nil then
		payload.levelId = self._levelId
	end
	if payload.levelName == nil then
		payload.levelName = self._levelName
	end
	payload.mode = "Zombie"
	return payload
end

function ZombieLevelController:_fireClient(remote, player, payload)
	if not remote or not player or not player.Parent then
		return
	end
	remote:FireClient(player, self:_attachMetadata(payload))
end

function ZombieLevelController:_broadcast(remote, payload)
	if not remote then
		return
	end
	local finalPayload = self:_attachMetadata(payload)
	for plr in pairs(self._players) do
		if plr and plr.Parent then
			remote:FireClient(plr, finalPayload)
		end
	end
end

function ZombieLevelController:_countListedPlayers()
	return ZombieRoleHelpers.countListedPlayers(self._players)
end

function ZombieLevelController:_countZombies(): number
	return ZombieRoleHelpers.countZombies(self._players, self._zombies)
end

function ZombieLevelController:_countHumans(): number
	return ZombieRoleHelpers.countHumans(self._players, self._zombies)
end

function ZombieLevelController:_shouldAssignLateJoinAsZombie(): boolean
	return ZombieRoleHelpers.shouldAssignLateJoinAsZombie(self:_countListedPlayers(), self:_countZombies(), self._config)
end

function ZombieLevelController:_setPlayerRole(player: Player, isZombie: boolean)
	if not player or not player.Parent then
		return
	end
	if isZombie then
		self._zombies[player] = true
	else
		self._zombies[player] = nil
	end
	player:SetAttribute(ZOMBIE_IS_INFECTED, isZombie and true or false)

	task.defer(function()
		if not self._players[player] or self._destroyed then
			return
		end
		local char = player.Character
		if not char then
			return
		end
		-- Highlights are handled client-side by relationship (ally/enemy colors).
		-- Keeping server highlights off avoids self-highlight artifacts.
		clearRoleHighlights(char)
	end)
end

function ZombieLevelController:_grantHumanImmunity(player: Player)
	local dur = self._config.HumanSpawnImmunitySeconds or 0
	if dur > 0 then
		self._humanImmunityUntil[player] = tick() + dur
	else
		self._humanImmunityUntil[player] = nil
	end
end

function ZombieLevelController:_clearHumanImmunity(player: Player)
	self._humanImmunityUntil[player] = nil
end

function ZombieLevelController:_isHumanImmune(player: Player): boolean
	local untilT = self._humanImmunityUntil[player]
	return untilT ~= nil and tick() < untilT
end

function ZombieLevelController:_awardCoins(player: Player, coins: number)
	if not player or not player.Parent or coins <= 0 then
		return
	end
	if not PlayerProfile then
		warn(string.format("%s PlayerProfile missing; skipping infection coin reward.", LOG_PREFIX))
		return
	end

	local success, newCoins = pcall(PlayerProfile.addCoins, player.UserId, coins)
	if not success then
		warn(string.format("%s Failed to reward infection coins to %s: %s", LOG_PREFIX, player.Name, tostring(newCoins)))
		return
	end

	local currencyUpdated = self._remotes.CurrencyUpdated
	if currencyUpdated then
		local balance = tonumber(newCoins) or select(1, PlayerProfile.getBalances(player.UserId))
		currencyUpdated:FireClient(player, {
			Coins = balance,
			AwardedCoins = coins,
		})
	end
end

function ZombieLevelController:_sendInfectionAction(infector: Player, infected: Player)
	local actionRemote = self._remotes.ZombieTagAction
	if not actionRemote or not infector or not infector.Parent then
		return
	end
	actionRemote:FireClient(infector, self:_attachMetadata({
		mode = "Zombie",
		kind = "infection",
		coinsAwarded = self._config.InfectionKillCoins or 5,
		killDelta = 1,
		infectedUserId = infected and infected.UserId or nil,
		infectedName = infected and infected.Name or nil,
		killText = "+1 kill",
	}))
end

function ZombieLevelController:_ensurePlayerData(player: Player)
	local data = self._playerData[player]
	if not data then
		data = {
			joinOrder = 0,
			deathConn = nil,
			charAddedConn = nil,
			currentSpawn = nil,
		}
		self._playerData[player] = data
	end
	return data
end

function ZombieLevelController:_cancelLobbyTask()
	if self._lobbyTask then
		pcall(task.cancel, self._lobbyTask)
		self._lobbyTask = nil
	end
	self._lobbyCountdownEndsAt = 0
end

function ZombieLevelController:_cancelPrepareTask()
	if self._prepareTask then
		pcall(task.cancel, self._prepareTask)
		self._prepareTask = nil
	end
	self._prepareCountdownEndsAt = 0
end

function ZombieLevelController:_isPlayerOnJoinPlatform(player: Player): boolean
	return self._platformTracker:isPlayerOnPlatform(player)
end

function ZombieLevelController:_refreshPlatformReadyStates()
	self._platformTracker:refreshReadyStates(self._players)
end

function ZombieLevelController:_countReadyOnPlatform(): number
	return self._platformTracker:countReady(self._players)
end

function ZombieLevelController:_debugState(label: string)
	local listed = self:_countListedPlayers()
	local ready = self:_countReadyOnPlatform()
	local zombies = self:_countZombies()
	local humans = self:_countHumans()
	print(
		string.format(
			"%s %s | phase=%s listed=%d ready=%d zombies=%d humans=%d",
			LOG_PREFIX,
			label,
			tostring(self._phase),
			listed,
			ready,
			zombies,
			humans
		)
	)
end

function ZombieLevelController:_buildRoleSpawnPools()
	local info
	self._zombieSpawnPool, self._humanSpawnPool, info =
		ZombieSpawnAllocator.buildRoleSpawnPools(self._spawns, self._players, self._zombies)

	if info and info.sharedSingleSpawn then
		warn(string.format("%s Only 1 spawn found; cannot split zombie/survivor spawns.", LOG_PREFIX))
	end

	print(
		string.format(
			"%s SPAWN_POOLS total=%d zombies=%d humans=%d zSpawns=%d hSpawns=%d",
			LOG_PREFIX,
			(info and info.totalSpawns) or 0,
			(info and info.zombieCount) or 0,
			(info and info.humanCount) or 0,
			#self._zombieSpawnPool,
			#self._humanSpawnPool
		)
	)
end

function ZombieLevelController:_setPlayerFrozen(player: Player?, frozen: boolean)
	if not player or not player.Parent then
		return
	end
	player:SetAttribute(ZOMBIE_ROUND_FROZEN, frozen and true or false)
end

function ZombieLevelController:_setFrozenForAll(frozen: boolean)
	for plr in pairs(self._players) do
		self:_setPlayerFrozen(plr, frozen)
	end
end

function ZombieLevelController:_pickInitialZombies()
	local zombies, humans = ZombieRoleHelpers.pickInitialZombies(self._players, self._config)
	local total = #zombies + #humans
	if total < (self._config.MinPlayersToStart or 3) then
		return
	end

	for p in pairs(self._players) do
		self:_setPlayerRole(p, false)
	end

	for _, chosen in ipairs(zombies) do
		self:_setPlayerRole(chosen, true)
	end

	for _, p in ipairs(humans) do
		self:_grantHumanImmunity(p)
	end
	for z in pairs(self._zombies) do
		self:_clearHumanImmunity(z)
	end
end

function ZombieLevelController:_startRound()
	self:_debugState("START_ROUND_ENTER")
	self:_cancelPrepareTask()
	self:_setFrozenForAll(false)
	local n = self:_countListedPlayers()
	if n < (self._config.MinPlayersToStart or 3) then
		self._phase = "idle"
		return
	end

	self._matchStarted = true
	self._phase = "active"
	local dur = self._config.RoundDurationSeconds or 300
	self._roundEndsAt = tick() + dur

	self:_pickInitialZombies()
	self:_buildRoleSpawnPools()

	for plr in pairs(self._players) do
		if plr.Parent then
			self:_teleportPlayerToSpawn(plr)
			if not self._zombies[plr] then
				self:_grantHumanImmunity(plr)
			end
		end
	end

	self:_broadcastState(true)
	self:_broadcast(self._remotes.GameStart, {
		active = true,
		mode = "Zombie",
		kind = "round_start",
	})
	self:_debugState("START_ROUND_OK")
end

function ZombieLevelController:_startPrepareCountdown()
	if self._destroyed or self._prepareTask then
		return
	end

	local sec = math.max(1, math.floor(self._config.PrepareCountdownSeconds or 3))
	self._phase = "prepare_countdown"
	self._prepareCountdownEndsAt = tick() + sec
	self:_setFrozenForAll(true)

	self._prepareTask = task.spawn(function()
		self:_debugState("PREP_COUNTDOWN_BEGIN")
		local remaining = sec
		while remaining > 0 and not self._destroyed do
			if self:_countListedPlayers() < (self._config.MinPlayersToStart or 3) then
				self:_cancelPrepareTask()
				self._matchStarted = false
				self._phase = "idle"
				self:_setFrozenForAll(false)
				self:_broadcastState(true)
				return
			end
			self:_broadcastState(true)
			print(string.format("%s PREP_TICK remaining=%d", LOG_PREFIX, remaining))
			task.wait(1)
			remaining -= 1
		end

		self._prepareTask = nil
		self._prepareCountdownEndsAt = 0
		if self._destroyed then
			return
		end
		if self:_countListedPlayers() < (self._config.MinPlayersToStart or 3) then
			self._matchStarted = false
			self._phase = "idle"
			self:_setFrozenForAll(false)
			self:_broadcastState(true)
			return
		end
		self:_debugState("PREP_DONE_STARTING_ROUND")
		self:_startRound()
	end)
end

function ZombieLevelController:_beginRoundPreparation()
	self:_cancelLobbyTask()
	self:_cancelPrepareTask()
	self:_debugState("ROUND_PREP_ENTER")

	local n = self:_countReadyOnPlatform()
	if n < (self._config.MinPlayersToStart or 3) then
		self._matchStarted = false
		self._phase = "idle"
		self:_setFrozenForAll(false)
		self:_broadcastState(true)
		return
	end

	self:_pickInitialZombies()

	for plr in pairs(self._players) do
		if plr.Parent then
			self:_teleportPlayerToSpawn(plr)
			if not self._zombies[plr] then
				self:_grantHumanImmunity(plr)
			end
		end
	end
	self:_debugState("ROUND_PREP_TELEPORTED")

	self._matchStarted = false
	self:_startPrepareCountdown()
end

function ZombieLevelController:_beginLobbyCountdown()
	if self._destroyed then
		return
	end
	if self._phase == "active" or self._phase == "intermission" or self._phase == "prepare_countdown" then
		return
	end
	local n = self:_countReadyOnPlatform()
	if n < (self._config.MinPlayersToStart or 3) then
		return
	end
	if self._lobbyTask then
		return
	end

	self._phase = "lobby_countdown"
	local sec = math.max(1, math.floor(self._config.LobbyCountdownSeconds or 5))
	self._lobbyCountdownEndsAt = tick() + sec

	self._lobbyTask = task.spawn(function()
		self:_debugState("LOBBY_COUNTDOWN_BEGIN")
		local remaining = sec
		while remaining > 0 and not self._destroyed do
			self:_refreshPlatformReadyStates()
			if self:_countReadyOnPlatform() < (self._config.MinPlayersToStart or 3) then
				self:_cancelLobbyTask()
				self._phase = "idle"
				self:_broadcastState(true)
				return
			end
			self:_broadcastState(true)
			print(string.format("%s LOBBY_TICK remaining=%d ready=%d", LOG_PREFIX, remaining, self:_countReadyOnPlatform()))
			task.wait(1)
			remaining -= 1
		end

		self._lobbyTask = nil
		if self._destroyed then
			return
		end
		self:_debugState("LOBBY_DONE_BEGIN_PREP")
		self:_beginRoundPreparation()
	end)
end

function ZombieLevelController:_scheduleIntermission()
	self._phase = "intermission"
	self._matchStarted = false
	self._roundEndsAt = 0
	self._zombieSpawnPool = {}
	self._humanSpawnPool = {}
	self:_setFrozenForAll(false)
	for p in pairs(self._players) do
		self:_setPlayerRole(p, false)
		self:_clearHumanImmunity(p)
	end

	local waitSec = self._config.IntermissionSeconds or 6
	self._intermissionEndsAt = tick() + waitSec

	task.delay(waitSec, function()
		if self._destroyed then
			return
		end
		if self._phase ~= "intermission" then
			return
		end
		self._intermissionEndsAt = 0
		self._phase = "idle"
		if self:_countListedPlayers() >= (self._config.MinPlayersToStart or 3) then
			self:_beginLobbyCountdown()
		else
			self:_broadcastState(true)
		end
	end)

	self:_broadcastState(true)
end

function ZombieLevelController:_endRound(reason: string, winnerTeam: string)
	if self._phase == "ending" then
		return
	end
	self._phase = "ending"

	self:_broadcast(self._remotes.GameEnd, {
		active = false,
		mode = "Zombie",
		reason = reason,
		winnerTeam = winnerTeam,
	})

	for plr in pairs(self._players) do
		if plr.Parent then
			self:_teleportPlayerToLobby(plr)
		end
	end

	self:_scheduleIntermission()
end

function ZombieLevelController:_checkWinConditions()
	if self._phase ~= "active" then
		return
	end

	local humans = self:_countHumans()
	local zombies = self:_countZombies()

	-- Safety: keep at least one zombie while match is active.
	if zombies <= 0 and humans > 0 then
		local candidates = {}
		for p in pairs(self._players) do
			if p.Parent and not self._zombies[p] then
				table.insert(candidates, p)
			end
		end
		if #candidates > 0 then
			local selected = candidates[math.random(1, #candidates)]
			self:_setPlayerRole(selected, true)
			self:_clearHumanImmunity(selected)
			self:_broadcastState(true)
			humans = self:_countHumans()
			zombies = self:_countZombies()
		end
	end

	if humans <= 0 and zombies > 0 then
		self:_endRound("all_infected", "zombies")
		return
	end

	if tick() >= self._roundEndsAt then
		if humans > 0 then
			self:_endRound("time_up", "humans")
		else
			self:_endRound("time_up", "zombies")
		end
		return
	end
end

function ZombieLevelController:_tryInfect(zombie: Player, human: Player)
	if self._phase ~= "active" then
		return
	end
	if not self._zombies[zombie] or self._zombies[human] then
		return
	end
	if not self._players[zombie] or not self._players[human] then
		return
	end
	if self:_isHumanImmune(human) then
		return
	end

	local zChar = zombie.Character
	local hChar = human.Character
	local zRoot = zChar and zChar:FindFirstChild("HumanoidRootPart")
	local hRoot = hChar and hChar:FindFirstChild("HumanoidRootPart")
	if not zRoot or not hRoot then
		return
	end

	local dist = (zRoot.Position - hRoot.Position).Magnitude
	local maxDist = self._config.InfectionTouchDistance or 5
	if dist > maxDist then
		return
	end

	self:_setPlayerRole(human, true)
	self:_clearHumanImmunity(human)
	self:_awardCoins(zombie, self._config.InfectionKillCoins or 5)
	self:_sendInfectionAction(zombie, human)
	self:_broadcastState(true)
end

function ZombieLevelController:_scanInfections()
	if self._phase ~= "active" then
		return
	end

	local zombies = {}
	for z in pairs(self._zombies) do
		if self._players[z] and z.Parent then
			table.insert(zombies, z)
		end
	end

	local humans = {}
	for p in pairs(self._players) do
		if p.Parent and not self._zombies[p] then
			table.insert(humans, p)
		end
	end

	for _, z in ipairs(zombies) do
		for _, h in ipairs(humans) do
			self:_tryInfect(z, h)
		end
	end
end

function ZombieLevelController:_buildPersonalPayload(player: Player)
	local roundLeft = 0
	if self._phase == "active" and self._roundEndsAt > 0 then
		roundLeft = math.max(0, math.ceil(self._roundEndsAt - tick()))
	end

	local lobbyLeft = 0
	if self._phase == "lobby_countdown" and self._lobbyCountdownEndsAt > 0 then
		lobbyLeft = math.max(0, math.ceil(self._lobbyCountdownEndsAt - tick()))
	end
	local prepLeft = 0
	if self._phase == "prepare_countdown" and self._prepareCountdownEndsAt > 0 then
		prepLeft = math.max(0, math.ceil(self._prepareCountdownEndsAt - tick()))
	end

	return ZombiePayloadBuilder.buildForPlayer(player, self._players, self._zombies, {
		phase = self._phase,
		roundTimeLeft = roundLeft,
		lobbyCountdownLeft = lobbyLeft,
		prepareCountdownLeft = prepLeft,
		matchStarted = self._matchStarted,
	})
end

function ZombieLevelController:_broadcastState(force: boolean?)
	local interval = self._config.StateBroadcastInterval or 0.5
	if not force and tick() - self._lastStateBroadcast < interval then
		return
	end
	self._lastStateBroadcast = tick()

	if not self._remotes.ZombieTagSync then
		return
	end

	for plr in pairs(self._players) do
		if plr.Parent then
			self:_fireClient(self._remotes.ZombieTagSync, plr, self:_buildPersonalPayload(plr))
		end
	end
end

function ZombieLevelController:_teleportPlayerToSpawn(player: Player)
	if not player or not player.Parent then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	if #self._spawns == 0 then
		warn(string.format("[ZombieTag] No spawn points for '%s'", tostring(self._levelId)))
		return
	end

	local data = self._playerData[player]
	if data and data.currentSpawn then
		self._occupiedSpawns[data.currentSpawn] = nil
		data.currentSpawn = nil
	end

	local pool = self._spawns
	if self._phase == "active" or self._phase == "prepare_countdown" then
		if self._zombies[player] then
			if #self._zombieSpawnPool > 0 then
				pool = self._zombieSpawnPool
			end
		else
			if #self._humanSpawnPool > 0 then
				pool = self._humanSpawnPool
			end
		end
	end

	local available = {}
	for _, spawnObject in ipairs(pool) do
		if spawnObject and spawnObject.Parent and not self._occupiedSpawns[spawnObject] then
			table.insert(available, spawnObject)
		end
	end

	local spawnObject
	if #available > 0 then
		spawnObject = available[math.random(1, #available)]
	else
		spawnObject = pool[math.random(1, #pool)]
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

function ZombieLevelController:_teleportPlayerToLobby(player: Player)
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

	if targetCFrame then
		teleportCharacterToCFrame(character, targetCFrame, self._config)
	end

	local data = self._playerData[player]
	if data and data.currentSpawn then
		self._occupiedSpawns[data.currentSpawn] = nil
		data.currentSpawn = nil
	end
end

function ZombieLevelController:_onCharacterAdded(player: Player, character: Model)
	if not self._players[player] then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local data = self:_ensurePlayerData(player)
		if data.deathConn then
			data.deathConn:Disconnect()
		end
		data.deathConn = humanoid.Died:Connect(function()
			self:_onPlayerDied(player)
		end)
	end

	clearRoleHighlights(character)

	task.defer(function()
		if not self._players[player] then
			return
		end
		if self._phase == "intermission" then
			return
		end
		if self._matchStarted or self._phase == "prepare_countdown" then
			self:_teleportPlayerToSpawn(player)
			if not self._zombies[player] then
				self:_grantHumanImmunity(player)
			end
		else
			-- Idle/lobby_countdown: do not move them; they must stay on Platform
			-- so the "3 seconds without leaving" validation works correctly.
		end
	end)
end

function ZombieLevelController:_onPlayerDied(player: Player)
	if not self._players[player] then
		return
	end

	task.delay(self._config.RespawnDelay or 3, function()
		if self._players[player] and player.Parent and player.Character then
			if self._matchStarted and self._phase == "active" then
				self:_teleportPlayerToSpawn(player)
				if not self._zombies[player] then
					self:_grantHumanImmunity(player)
				end
			end
		end
	end)
end

function ZombieLevelController:_onPlatformTouched(part: BasePart)
	if self._destroyed then
		return
	end
	local player = self._platformTracker:onTouched(part)
	if not player then
		return
	end
	print(string.format("%s PLATFORM_TOUCHED player=%s phase=%s", LOG_PREFIX, player.Name, tostring(self._phase)))

	self:_addPlayer(player)
end

function ZombieLevelController:_onPlatformTouchEnded(part: BasePart)
	if self._destroyed then
		return
	end
	self._platformTracker:onTouchEnded(part)
end

function ZombieLevelController:_addPlayer(player: Player)
	if self._destroyed then
		return
	end

	local maxP = self._config.MaxPlayers or 20
	if not self._players[player] and self:_countListedPlayers() >= maxP then
		return
	end

	if self._players[player] then
		if player:GetAttribute(BOMB_TAG_ATTRIBUTE) then
			self:_broadcastState(true)
			return
		end
		self:_removePlayer(player, "refresh", true)
	end

	self._players[player] = true
	print(string.format("%s PLAYER_ADDED player=%s listed=%d ready=%d phase=%s", LOG_PREFIX, player.Name, self:_countListedPlayers(), self:_countReadyOnPlatform(), tostring(self._phase)))
	self:_setPlayerFrozen(player, self._phase == "prepare_countdown")
	local data = self:_ensurePlayerData(player)
	self._joinCounter += 1
	data.joinOrder = self._joinCounter

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

	if self._matchStarted and self._phase == "active" then
		if self:_shouldAssignLateJoinAsZombie() then
			self:_setPlayerRole(player, true)
			self:_clearHumanImmunity(player)
		else
			self:_setPlayerRole(player, false)
			self:_grantHumanImmunity(player)
		end
		self:_teleportPlayerToSpawn(player)
	else
		self:_setPlayerRole(player, false)
	end

	self:_fireClient(self._remotes.GameStart, player, {
		active = true,
		mode = "Zombie",
		kind = "enter",
	})

	self:_fireClient(self._remotes.ReadyToggle, player, {
		enabled = true,
		mode = "Zombie",
		reason = "enter",
		label = "Leave",
	})

	if
		not self._matchStarted
		and (self._phase == "idle" or self._phase == "lobby_countdown")
		and self:_countReadyOnPlatform() >= (self._config.MinPlayersToStart or 3)
	then
		self:_beginLobbyCountdown()
	end

	self:_broadcastState(true)
end

function ZombieLevelController:_removePlayer(player: Player, reason: string?, skipTeleport: boolean?)
	if not self._players[player] then
		return
	end

	self._players[player] = nil
	self._zombies[player] = nil
	self._platformTracker:removePlayer(player)
	self:_clearHumanImmunity(player)
	self:_setPlayerFrozen(player, false)

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

	if not skipTeleport then
		self:_teleportPlayerToLobby(player)
	end

	player:SetAttribute(ZOMBIE_IS_INFECTED, false)
	if player.Character then
		clearRoleHighlights(player.Character)
	end

	self:_fireClient(self._remotes.ReadyToggle, player, {
		enabled = false,
		mode = "Zombie",
		reason = reason or "leave",
	})

	self:_fireClient(self._remotes.GameEnd, player, {
		active = false,
		mode = "Zombie",
		reason = reason or "leave",
	})

	if self._callbacks.onPlayerLeft then
		task.defer(self._callbacks.onPlayerLeft, player, self)
	end

	if self._phase == "lobby_countdown" and self:_countReadyOnPlatform() < (self._config.MinPlayersToStart or 3) then
		self:_cancelLobbyTask()
		self._phase = "idle"
	end

	if self._phase == "prepare_countdown" and self:_countListedPlayers() < (self._config.MinPlayersToStart or 3) then
		self:_cancelPrepareTask()
		self._phase = "idle"
		self:_setFrozenForAll(false)
	end

	if self._phase == "active" and self:_countListedPlayers() < (self._config.MinPlayersToStart or 3) then
		self:_endRound("not_enough_players", "none")
	end

	self:_broadcastState(true)
end

function ZombieLevelController:_onHeartbeat()
	if self._destroyed then
		return
	end

	if self._phase == "idle" or self._phase == "lobby_countdown" then
		-- Fallback: if touch events are missed (streaming/accessory edge cases),
		-- enroll players that are physically standing on the join platform.
		for _, player in ipairs(Players:GetPlayers()) do
			if not self._players[player] and self:_isPlayerOnJoinPlatform(player) then
				self:_addPlayer(player)
			end
		end

		self:_refreshPlatformReadyStates()
		if self._phase == "idle" and self:_countReadyOnPlatform() >= (self._config.MinPlayersToStart or 3) then
			self:_beginLobbyCountdown()
		end
	end

	self:_scanInfections()
	self:_checkWinConditions()
	self:_broadcastState(false)
end

function ZombieLevelController:ownsPlayer(player: Player)
	return self._players[player] == true
end

function ZombieLevelController:handleReadyToggle(player: Player)
	self:_removePlayer(player, "leave")
end

function ZombieLevelController:onPlayerRemoving(player: Player)
	self:_removePlayer(player, "player_removing")
end

function ZombieLevelController:onCharacterRemoving(_player: Player)
end

function ZombieLevelController:destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true

	self:_cancelLobbyTask()
	self:_cancelPrepareTask()
	self:_setFrozenForAll(false)

	if self._platformTouchedConn then
		self._platformTouchedConn:Disconnect()
		self._platformTouchedConn = nil
	end
	if self._platformTouchEndedConn then
		self._platformTouchEndedConn:Disconnect()
		self._platformTouchEndedConn = nil
	end

	if self._heartbeatConn then
		self._heartbeatConn:Disconnect()
		self._heartbeatConn = nil
	end

	for plr in pairs(self._players) do
		self:_removePlayer(plr, "destroy")
	end

	self._players = {}
	self._zombies = {}
	self._playerData = {}
end

return ZombieLevelController
