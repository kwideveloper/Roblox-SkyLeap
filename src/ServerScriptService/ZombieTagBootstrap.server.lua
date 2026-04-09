local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local zombieFolder = ReplicatedStorage:WaitForChild("ZombieTag")
local ConfigModule = zombieFolder:WaitForChild("Config")
local Config = require(ConfigModule)

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local remotes = {
	GameStart = remotesFolder:WaitForChild("BombTagGameStart"),
	GameEnd = remotesFolder:WaitForChild("BombTagGameEnd"),
	ReadyToggle = remotesFolder:WaitForChild("BombTagReadyToggle"),
	ZombieTagSync = remotesFolder:WaitForChild("ZombieTagSync"),
	-- Optional remotes: never block Zombie mode bootstrap if missing.
	ZombieTagAction = remotesFolder:FindFirstChild("ZombieTagAction"),
	CurrencyUpdated = remotesFolder:FindFirstChild("CurrencyUpdated"),
}

local ZombieLevelController = require(ServerScriptService:WaitForChild("ZombieTag"):WaitForChild("ZombieLevelController"))

local ZOMBIE_LEVEL_TAG = "ZombieLevel"
local BOMB_TAG_ATTRIBUTE = "BombTagActive"
local ZOMBIE_TAG_ACTIVE = "ZombieTagActive"
local LOG_PREFIX = "[ZombieTag][Server]"

local controllersByInstance: { [Instance]: any } = {}
local levelConnections: { [Instance]: { RBXScriptConnection } } = {}
local playerToController: { [Player]: any } = {}

local function setZombiePlayerActivity(player: Player?, inMatch: boolean)
	if not player then
		return
	end
	player:SetAttribute(BOMB_TAG_ATTRIBUTE, inMatch and true or false)
	player:SetAttribute(ZOMBIE_TAG_ACTIVE, inMatch and true or false)
	if not inMatch then
		player:SetAttribute("ZombieIsInfected", false)
	end
end

local function handleZombiePlayerJoined(player: Player, controller)
	playerToController[player] = controller
	setZombiePlayerActivity(player, true)
end

local function handleZombiePlayerLeft(player: Player, controller)
	if playerToController[player] == controller then
		playerToController[player] = nil
	end
	setZombiePlayerActivity(player, false)
end

local function cleanupLevelConnections(level: Instance)
	local connections = levelConnections[level]
	if connections then
		for _, conn in ipairs(connections) do
			conn:Disconnect()
		end
	end
	levelConnections[level] = nil
end

local function cleanupControllerPlayers(controller)
	for player, mapped in pairs(playerToController) do
		if mapped == controller then
			playerToController[player] = nil
			setZombiePlayerActivity(player, false)
		end
	end
end

local function destroyController(level: Instance)
	local controller = controllersByInstance[level]
	if not controller then
		return
	end

	controllersByInstance[level] = nil
	cleanupLevelConnections(level)
	cleanupControllerPlayers(controller)
	controller:destroy()
end

local function resolveLobbySpawner(level: Instance)
	local lobbySpawner = nil

	if typeof(level) == "Instance" then
		lobbySpawner = level:FindFirstChild("BombLobbySpawner")
			or level:FindFirstChild("LobbySpawner")
			or level:FindFirstChild("LobbySpawn")
	end

	if not lobbySpawner then
		lobbySpawner = Workspace:FindFirstChild("BombLobbySpawner")
	end

	return lobbySpawner
end

local function createController(level: Instance)
	if controllersByInstance[level] then
		return controllersByInstance[level]
	end

	print(string.format("%s createController level=%s class=%s", LOG_PREFIX, level:GetFullName(), level.ClassName))

	local lobbySpawner = resolveLobbySpawner(level)
	local levelId = (typeof(level) == "Instance" and level:GetAttribute("LevelId")) or level.Name
	local levelName = (typeof(level) == "Instance" and level:GetAttribute("LevelName")) or level.Name

	local ok, controllerOrErr = pcall(ZombieLevelController.new, {
		level = level,
		lobbySpawner = lobbySpawner,
		remotes = remotes,
		configModule = ConfigModule,
		config = Config,
		levelId = levelId,
		levelName = levelName,
		callbacks = {
			onPlayerJoined = handleZombiePlayerJoined,
			onPlayerLeft = handleZombiePlayerLeft,
		},
	})
	if not ok then
		warn(string.format("%s createController FAILED level=%s err=%s", LOG_PREFIX, level:GetFullName(), tostring(controllerOrErr)))
		return nil
	end
	local controller = controllerOrErr

	controllersByInstance[level] = controller
	print(string.format("%s controller ready levelId=%s", LOG_PREFIX, tostring(levelId)))

	local connections = {}
	levelConnections[level] = connections

	if level.AncestryChanged then
		table.insert(connections, level.AncestryChanged:Connect(function(_, parent)
			if not parent then
				destroyController(level)
			end
		end))
	end

	if level.Destroying then
		table.insert(connections, level.Destroying:Connect(function()
			destroyController(level)
		end))
	end

	return controller
end

local function ensureExistingLevels()
	print(string.format("%s ensureExistingLevels begin", LOG_PREFIX))
	for _, level in ipairs(CollectionService:GetTagged(ZOMBIE_LEVEL_TAG)) do
		createController(level)
	end

	-- Fallback discovery: some environments may not preserve CollectionService tags.
	-- If a level is named "ZombieLevel", we still bootstrap a controller.
	for _, inst in ipairs(Workspace:GetDescendants()) do
		if (inst:IsA("Model") or inst:IsA("Folder")) and inst.Name == ZOMBIE_LEVEL_TAG then
			createController(inst)
		end
	end
	print(string.format("%s ensureExistingLevels done", LOG_PREFIX))
end

local function onZombieLevelAdded(level: Instance)
	createController(level)
end

local function onZombieLevelRemoved(level: Instance)
	destroyController(level)
end

CollectionService:GetInstanceAddedSignal(ZOMBIE_LEVEL_TAG):Connect(onZombieLevelAdded)
CollectionService:GetInstanceRemovedSignal(ZOMBIE_LEVEL_TAG):Connect(onZombieLevelRemoved)

Workspace.DescendantAdded:Connect(function(inst)
	if (inst:IsA("Model") or inst:IsA("Folder")) and inst.Name == ZOMBIE_LEVEL_TAG then
		createController(inst)
	end
end)

Workspace.DescendantRemoving:Connect(function(inst)
	if controllersByInstance[inst] then
		destroyController(inst)
	end
end)

ensureExistingLevels()

local function findControllerForPlayer(player: Player)
	local controller = playerToController[player]
	if controller then
		return controller
	end

	for _, ctrl in pairs(controllersByInstance) do
		if ctrl:ownsPlayer(player) then
			playerToController[player] = ctrl
			return ctrl
		end
	end

	return nil
end

remotes.ReadyToggle.OnServerEvent:Connect(function(player: Player, data)
	if typeof(data) == "table" and data.mode == "Zombie" then
		local controller = findControllerForPlayer(player)
		if controller then
			controller:handleReadyToggle(player)
		end
	end
end)

local function handlePlayerRemoving(player: Player)
	local controller = findControllerForPlayer(player)
	if controller then
		controller:onPlayerRemoving(player)
	end
	playerToController[player] = nil
	setZombiePlayerActivity(player, false)
end

local function handleCharacterRemoving(player: Player)
	local controller = findControllerForPlayer(player)
	if controller then
		controller:onCharacterRemoving(player)
	end
end

Players.PlayerRemoving:Connect(handlePlayerRemoving)

local function setupPlayer(player: Player)
	if not player:GetAttribute(ZOMBIE_TAG_ACTIVE) then
		setZombiePlayerActivity(player, false)
	end
	player.CharacterRemoving:Connect(function()
		handleCharacterRemoving(player)
	end)
end

Players.PlayerAdded:Connect(setupPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	setupPlayer(player)
end

