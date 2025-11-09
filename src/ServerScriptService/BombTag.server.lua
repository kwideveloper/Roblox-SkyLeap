local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local bombTagFolder = ReplicatedStorage:WaitForChild("BombTag")
local ConfigModule = bombTagFolder:WaitForChild("Config")
local Config = require(ConfigModule)

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local remotes = {
	GameStart = remotesFolder:WaitForChild("BombTagGameStart"),
	CountdownUpdate = remotesFolder:WaitForChild("BombTagCountdownUpdate"),
	BombAssigned = remotesFolder:WaitForChild("BombTagBombAssigned"),
	BombPassed = remotesFolder:WaitForChild("BombTagBombPassed"),
	BombTimerUpdate = remotesFolder:WaitForChild("BombTagBombTimerUpdate"),
	PlayerEliminated = remotesFolder:WaitForChild("BombTagPlayerEliminated"),
	GameEnd = remotesFolder:WaitForChild("BombTagGameEnd"),
	ScoreboardUpdate = remotesFolder:WaitForChild("BombTagScoreboardUpdate"),
	PlatformPrompt = remotesFolder:WaitForChild("BombTagPlatformPrompt"),
	ReadyStatus = remotesFolder:WaitForChild("BombTagReadyStatus"),
	ReadyWarning = remotesFolder:WaitForChild("BombTagReadyWarning"),
	ReadyToggle = remotesFolder:WaitForChild("BombTagReadyToggle"),
}
local currencyUpdatedRemote = remotesFolder:FindFirstChild("CurrencyUpdated")

local BombLevelController = require(ServerScriptService:WaitForChild("BombTag"):WaitForChild("BombLevelController"))

local BOMB_LEVEL_TAG = "BombLevel"
local BOMB_TAG_ATTRIBUTE = "BombTagActive"

local controllersByInstance: { [Instance]: any } = {}
local levelConnections: { [Instance]: { RBXScriptConnection } } = {}
local playerToController: { [Player]: any } = {}
local activeMatchParticipants: { [any]: { [Player]: true } } = {}

local function setPlayerActivity(player: Player?, isActive: boolean)
	if not player then
		return
	end
	player:SetAttribute(BOMB_TAG_ATTRIBUTE, isActive and true or false)
end

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

local function handlePlayerAssigned(player: Player, side: string, index: number, controller)
	playerToController[player] = controller
	setPlayerActivity(player, false)
end

local function handlePlayerRemoved(player: Player, _side: string?, _index: number?, controller)
	if playerToController[player] == controller then
		playerToController[player] = nil
	end

	local participants = activeMatchParticipants[controller]
	if participants then
		participants[player] = nil
	end

	setPlayerActivity(player, false)
end

local function handleMatchStarted(controller, context)
	local participants = {}
	for _, entry in ipairs(context.players or {}) do
		local player = entry.player
		if player and player.Parent then
			playerToController[player] = controller
			participants[player] = true
			setPlayerActivity(player, true)
		end
	end
	activeMatchParticipants[controller] = participants
end

local function handleMatchEnded(controller)
	local participants = activeMatchParticipants[controller]
	if participants then
		for player in pairs(participants) do
			setPlayerActivity(player, false)
			if playerToController[player] == controller then
				playerToController[player] = nil
			end
		end
	end
	activeMatchParticipants[controller] = nil
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

local function destroyController(level: Instance)
	local controller = controllersByInstance[level]
	if not controller then
		return
	end

	controllersByInstance[level] = nil
	cleanupLevelConnections(level)

	local participants = activeMatchParticipants[controller]
	if participants then
		for player in pairs(participants) do
			setPlayerActivity(player, false)
			if playerToController[player] == controller then
				playerToController[player] = nil
			end
		end
	end
	activeMatchParticipants[controller] = nil

	for player, mapped in pairs(playerToController) do
		if mapped == controller then
			playerToController[player] = nil
			setPlayerActivity(player, false)
		end
	end

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

	local lobbySpawner = resolveLobbySpawner(level)
	local levelId = (typeof(level) == "Instance" and level:GetAttribute("LevelId")) or level.Name
	local levelName = (typeof(level) == "Instance" and level:GetAttribute("LevelName")) or level.Name

	local controller = BombLevelController.new({
		level = level,
		lobbySpawner = lobbySpawner,
		remotes = remotes,
		currencyRemote = currencyUpdatedRemote,
		configModule = ConfigModule,
		config = Config,
		levelId = levelId,
		levelName = levelName,
		callbacks = {
			onPlayerAssigned = handlePlayerAssigned,
			onPlayerRemoved = handlePlayerRemoved,
			onMatchStarted = handleMatchStarted,
			onMatchEnded = handleMatchEnded,
		},
	})

	controllersByInstance[level] = controller
	activeMatchParticipants[controller] = nil

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
	for _, level in ipairs(CollectionService:GetTagged(BOMB_LEVEL_TAG)) do
		createController(level)
	end
end

local function onBombLevelAdded(level: Instance)
	createController(level)
end

local function onBombLevelRemoved(level: Instance)
	destroyController(level)
end

CollectionService:GetInstanceAddedSignal(BOMB_LEVEL_TAG):Connect(onBombLevelAdded)
CollectionService:GetInstanceRemovedSignal(BOMB_LEVEL_TAG):Connect(onBombLevelRemoved)

ensureExistingLevels()

local function handleReadyToggle(player: Player)
	local controller = findControllerForPlayer(player)
	if controller then
		controller:handleReadyToggle(player)
	end
end

remotes.ReadyToggle.OnServerEvent:Connect(handleReadyToggle)

local function handlePlayerRemoving(player: Player)
	local controller = findControllerForPlayer(player)
	if controller then
		controller:onPlayerRemoving(player)
	end
	playerToController[player] = nil
	setPlayerActivity(player, false)
end

local function handleCharacterRemoving(player: Player)
	local controller = findControllerForPlayer(player)
	if controller then
		controller:onCharacterRemoving(player)
	end
end

Players.PlayerRemoving:Connect(handlePlayerRemoving)

local function setupPlayer(player: Player)
	setPlayerActivity(player, false)
	player.CharacterRemoving:Connect(function()
		handleCharacterRemoving(player)
	end)
end

Players.PlayerAdded:Connect(setupPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	setupPlayer(player)
end

