-- Level Progress UI
-- Shows a progress bar displaying all players' positions in the current level
-- Highlights the local player's position

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Wait for Remotes (with timeout to avoid infinite yield)
local Remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
if not Remotes then
	warn("[LevelProgressUI] Remotes folder not found, creating...")
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end

local progressUpdateRemote = Remotes:WaitForChild("LevelProgressUpdate", 10)
if not progressUpdateRemote then
	warn("[LevelProgressUI] LevelProgressUpdate RemoteEvent not found - progress tracking may not work")
end

-- UI Configuration (only for icon creation)
local UI_CONFIG = {
	PLAYER_ICON_SIZE = 32, -- Size of player avatar icons
}

-- UI Elements
local screenGui = nil
local mainFrame = nil
local progressBar = nil
local progressFill = nil
local playersContainer = nil

-- State
local currentPlayers = {} -- [userId] = { userId, username, progress }
local isNearSpawn = true
local iconTweens = {} -- [userId] = tween

local function initializeUIRefs()
	-- Get existing ScreenGui named "LevelProgressUI"
	screenGui = playerGui:WaitForChild("LevelProgressUI")
	mainFrame = screenGui:FindFirstChild("MainFrame")
	progressBar = screenGui:FindFirstChild("ProgressBar", true)
	progressFill = screenGui:FindFirstChild("ProgressFill", true)
	playersContainer = screenGui:FindFirstChild("PlayersContainer", true)
end

-- Get player thumbnail
local function getPlayerThumbnail(userId)
	-- Use Roblox thumbnail service (HeadShot for avatar)
	-- This will use the Roblox API to get the player's headshot
	local thumbnailUrl = string.format(
		"https://thumbnails.roblox.com/v1/users/avatar-headshot?userIds=%d&size=150x150&format=Png&isCircular=false",
		userId
	)
	
	-- For immediate use, we can use the headshot thumbnail endpoint
	-- Note: This requires internet access, for offline use we'd need cached images
	return string.format(
		"https://www.roblox.com/headshot-thumbnail/image?userId=%d&width=150&height=150&format=png",
		userId
	)
end

-- Create or update player icon
local function updatePlayerIcon(userId, username, progress, isLocalPlayer)
	if not playersContainer or not progressBar then
		return
	end

	-- Find existing icon or create new one
	local iconName = "PlayerIcon_" .. userId
	local icon = playersContainer:FindFirstChild(iconName)

	if not icon then
		-- Create minimal icon - no styling, just the image
		icon = Instance.new("ImageLabel")
		icon.Name = iconName
		icon.Size = UDim2.new(0, UI_CONFIG.PLAYER_ICON_SIZE, 0, UI_CONFIG.PLAYER_ICON_SIZE)
		icon.Image = getPlayerThumbnail(userId)
		icon.BackgroundTransparency = 1
		icon.Parent = playersContainer
	end

	-- Update position based on progress
	-- Clamp progress to 0-1 range
	progress = math.max(0, math.min(1, progress))
	
	local barWidth = progressBar.AbsoluteSize.X
	local xPosition = progress * barWidth
	
	-- Clamp xPosition to stay within bar bounds
	xPosition = math.max(UI_CONFIG.PLAYER_ICON_SIZE / 2, math.min(xPosition, barWidth - UI_CONFIG.PLAYER_ICON_SIZE / 2))

	local targetPosition = UDim2.new(0, xPosition - (UI_CONFIG.PLAYER_ICON_SIZE / 2), 0, 0)

	-- Smoothly tween to the new position
	if iconTweens[userId] then
		iconTweens[userId]:Cancel()
		iconTweens[userId] = nil
	end

	if icon.Position == targetPosition then
		-- No movement needed
	else
		local tween = TweenService:Create(
			icon,
			TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = targetPosition }
		)
		iconTweens[userId] = tween
		tween.Completed:Connect(function()
			if iconTweens[userId] == tween then
				iconTweens[userId] = nil
			end
		end)
		tween:Play()
	end

	-- Update ZIndex for local player (bring to front)
	if isLocalPlayer then
		icon.ZIndex = 10
	else
		icon.ZIndex = 5
	end
end

-- Remove player icon
local function removePlayerIcon(userId)
	if not playersContainer then
		return
	end

	local iconName = "PlayerIcon_" .. userId
	local icon = playersContainer:FindFirstChild(iconName)
	if icon then
		if iconTweens[userId] then
			iconTweens[userId]:Cancel()
			iconTweens[userId] = nil
		end
		icon:Destroy()
	end
end

-- Update progress fill (shows overall level completion)
local function updateProgressFill()
	if not progressFill or not progressBar then
		return
	end

	-- Calculate average progress or max progress
	local maxProgress = 0
	local localPlayerProgress = 0

	for userId, data in pairs(currentPlayers) do
		if data.progress > maxProgress then
			maxProgress = data.progress
		end
		if userId == player.UserId then
			localPlayerProgress = data.progress
		end
	end

	-- Use local player's progress for fill
	local fillProgress = localPlayerProgress

	-- Animate fill
	local targetSize = UDim2.new(fillProgress, 0, 1, 0)
	local tween = TweenService:Create(
		progressFill,
		TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = targetSize }
	)
	tween:Play()
end

-- Check if player is near spawn
local function checkSpawnProximity()
	-- Check if UI should be visible based on distance from spawn
	-- For now, always show when in a level
	return true
end

-- Update UI with progress data
local function updateUI(progressData)
	if not playersContainer or not progressBar or not progressFill then
		return
	end

	-- Handle both array format and table format
	local playersList = {}
	
	if type(progressData) == "table" then
		if progressData.players then
			-- Format: { levelId = "...", levelName = "...", players = {...} }
			playersList = progressData.players
		elseif progressData[1] then
			-- Format: { {...}, {...} } (array)
			playersList = progressData
		end
	end

	-- Update current players list
	currentPlayers = {}
	local hasLocalPlayer = false

	for _, data in ipairs(playersList) do
		if type(data) == "table" and data.userId then
			currentPlayers[data.userId] = data
			if data.userId == player.UserId then
				hasLocalPlayer = true
			end
		end
	end

	-- Update all player icons (don't touch MainFrame visibility)
	if #playersList > 0 then
		-- Update all player icons
		local existingIcons = {}
		for _, child in ipairs(playersContainer:GetChildren()) do
			if child.Name:match("^PlayerIcon_") then
				local userId = tonumber(child.Name:match("(%d+)$"))
				if userId then
					existingIcons[userId] = true
				end
			end
		end

		-- Create/update icons for current players
		for userId, data in pairs(currentPlayers) do
			existingIcons[userId] = nil -- Mark as still exists
			local isLocalPlayer = (userId == player.UserId)
			updatePlayerIcon(userId, data.username, data.progress, isLocalPlayer)
		end

		-- Remove icons for players who left
		for userId, _ in pairs(existingIcons) do
			removePlayerIcon(userId)
		end

		-- Update progress fill
		updateProgressFill()
	else
		-- Clear all icons only (don't modify MainFrame)
		for _, child in ipairs(playersContainer:GetChildren()) do
			if child.Name:match("^PlayerIcon_") then
				child:Destroy()
			end
		end
	end
end

-- Listen for progress updates
progressUpdateRemote.OnClientEvent:Connect(function(progressData)
	updateUI(progressData)
end)

-- Initialize UI references
initializeUIRefs()

-- Handle player leaving (cleanup only our icons, not the UI)
Players.PlayerRemoving:Connect(function(leavingPlayer)
	if leavingPlayer == player then
		-- Cleanup only our icons
		if playersContainer then
			for _, child in ipairs(playersContainer:GetChildren()) do
				if child.Name:match("^PlayerIcon_") then
					child:Destroy()
				end
			end
		end
	end
end)

