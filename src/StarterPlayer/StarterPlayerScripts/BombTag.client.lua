local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BombClientController = require(ReplicatedStorage:WaitForChild("BombTag"):WaitForChild("BombClientController"))
local Config = require(ReplicatedStorage:WaitForChild("BombTag"):WaitForChild("Config"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function getBombTagState(): (BoolValue, StringValue)
	local container = ReplicatedStorage:FindFirstChild("BombTagState")
	if not container then
		container = Instance.new("Folder")
		container.Name = "BombTagState"
		container.Parent = ReplicatedStorage
	end

	local isActive = container:FindFirstChild("IsActive")
	if not isActive then
		isActive = Instance.new("BoolValue")
		isActive.Name = "IsActive"
		isActive.Value = false
		isActive.Parent = container
	end

	local bombHolder = container:FindFirstChild("BombHolder")
	if not bombHolder then
		bombHolder = Instance.new("StringValue")
		bombHolder.Name = "BombHolder"
		bombHolder.Value = ""
		bombHolder.Parent = container
	end

	return isActive, bombHolder
end

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local remotesMap = {
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

local isActiveValue, bombHolderValue = getBombTagState()

local controller = BombClientController.init({
	player = player,
	playerGui = playerGui,
	config = Config,
	remotes = remotesMap,
	stateValues = {
		isActive = isActiveValue,
		bombHolder = bombHolderValue,
	},
})

player.AncestryChanged:Connect(function(_, parent)
	if not parent and controller and controller.cleanup then
		controller:cleanup()
	end
end)

