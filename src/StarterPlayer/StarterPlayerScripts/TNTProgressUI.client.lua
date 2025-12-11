-- TNT Platform Progress UI
-- Shows a thin vertical bar with level markers (circles with numbers) and player positions
-- Based on actual Y heights of TNTPlatforms

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local CONFIG = {
	TNT_LEVEL_PATTERN = "^TNT_Level_%d+$",
	TNT_PLATFORM_NAME = "TNTPlatform",
	MAX_PLATFORMS = 6, -- Maximum number of platforms to show
	UPDATE_INTERVAL = 0.1, -- Update every 0.1 seconds for smooth movement
	BAR_WIDTH = 8, -- Thin bar width
	BAR_HEIGHT = 300, -- Bar height in pixels
	LEVEL_MARKER_SIZE = 32, -- Size of level number circles
	PLAYER_ICON_SIZE = 24, -- Size of player avatars
	BACKGROUND_COLOR = Color3.fromRGB(30, 32, 40),
	BAR_COLOR = Color3.fromRGB(50, 55, 65),
	LEVEL_MARKER_COLOR = Color3.fromRGB(70, 75, 85),
	LEVEL_MARKER_ACTIVE_COLOR = Color3.fromRGB(100, 200, 255), -- Active level color (blue)
	LEVEL_MARKER_COMPLETED_COLOR = Color3.fromRGB(255, 80, 80), -- Completed level color (red)
	LEVEL_TEXT_COLOR = Color3.fromRGB(255, 255, 255),
	PLAYER_ICON_BORDER = Color3.fromRGB(100, 200, 255), -- Highlight for local player
	FALLBACK_ICON = "rbxassetid://6026568198",
}

local screenGui
local mainFrame
local progressBar
local progressFill
local levelMarkers = {} -- [levelIndex] = {marker, info}
local playerIcons = {} -- [userId] = {icon, tween}
local platformInfos = {} -- Sorted by height (highest = level 1)
local minHeight = 0
local maxHeight = 0
local heightRange = 0
local thumbnailCache = {}
local updateAccumulator = 0
local highestCompletedLevel = 0 -- Track the lowest level the player has reached (highest index number)
local lastPlayerY = nil -- Track last Y position to determine movement direction
local currentPlayerLevelContainer = nil -- Track which TNT_Level_X the player is currently in

local function ensureScreenGui()
	if screenGui and screenGui.Parent then
		-- Ensure progressFill reference is set
		if not progressFill then
			progressFill = progressBar and progressBar:FindFirstChild("ProgressFill")
		end
		return
	end

	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "TNTProgressUI"
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.Parent = playerGui

	-- Main container frame
	mainFrame = Instance.new("Frame")
	mainFrame.Name = "MainFrame"
	mainFrame.AnchorPoint = Vector2.new(1, 0.5)
	mainFrame.Position = UDim2.new(1, -20, 0.5, 0)
	mainFrame.Size = UDim2.new(0, 60, 0, CONFIG.BAR_HEIGHT)
	mainFrame.BackgroundTransparency = 1
	mainFrame.BorderSizePixel = 0
	mainFrame.Visible = false
	mainFrame.Parent = screenGui

	-- Progress bar background (thin vertical bar)
	progressBar = Instance.new("Frame")
	progressBar.Name = "ProgressBar"
	progressBar.AnchorPoint = Vector2.new(0.5, 0.5)
	progressBar.Position = UDim2.new(0.5, 0, 0.5, 0)
	progressBar.Size = UDim2.new(0, CONFIG.BAR_WIDTH, 1, 0)
	progressBar.BackgroundColor3 = CONFIG.BAR_COLOR
	progressBar.BackgroundTransparency = 0.3
	progressBar.BorderSizePixel = 0
	progressBar.Parent = mainFrame

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, CONFIG.BAR_WIDTH / 2)
	barCorner.Parent = progressBar

	-- Progress fill (fills from top to bottom as player descends)
	progressFill = Instance.new("Frame")
	progressFill.Name = "ProgressFill"
	progressFill.AnchorPoint = Vector2.new(0.5, 0) -- Anchor to top
	progressFill.Position = UDim2.new(0.5, 0, 0, 0)
	progressFill.Size = UDim2.new(1, 0, 0, 0) -- Starts at 0 height
	progressFill.BackgroundColor3 = CONFIG.LEVEL_MARKER_ACTIVE_COLOR
	progressFill.BackgroundTransparency = 0.2
	progressFill.BorderSizePixel = 0
	progressFill.Parent = progressBar

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, CONFIG.BAR_WIDTH / 2)
	fillCorner.Parent = progressFill

	-- Container for level markers and player icons (absolute positioning)
	local contentFrame = Instance.new("Frame")
	contentFrame.Name = "ContentFrame"
	contentFrame.Size = UDim2.new(1, 0, 1, 0)
	contentFrame.BackgroundTransparency = 1
	contentFrame.BorderSizePixel = 0
	contentFrame.Parent = mainFrame
end

local function getAncestorTNTLevel(instance)
	local ancestor = instance
	while ancestor and ancestor ~= Workspace do
		if ancestor.Name:match(CONFIG.TNT_LEVEL_PATTERN) then
			return ancestor
		end
		ancestor = ancestor.Parent
	end
	return nil
end


-- Detect which TNT_Level_X the player is currently in
local function detectPlayerLevelContainer()
	local character = localPlayer.Character
	if not character then
		return nil
	end
	
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return nil
	end
	
	-- Find the TNT_Level_X container that contains the player's position
	local playerPosition = rootPart.Position
	
	-- Check all TNT level containers
	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if (descendant:IsA("Folder") or descendant:IsA("Model")) and descendant.Name:match(CONFIG.TNT_LEVEL_PATTERN) then
			-- Check if player is within this level's bounds
			-- We'll consider the player "in" a level if they're near any platform in that level
			for _, platform in ipairs(descendant:GetDescendants()) do
				if platform:IsA("Model") and platform.Name == CONFIG.TNT_PLATFORM_NAME then
					local cf, size = platform:GetBoundingBox()
					local distance = (playerPosition - cf.Position).Magnitude
					-- If player is within 100 studs of any platform in this level, they're in this level
					if distance < 100 then
						return descendant
					end
				end
			end
		end
	end
	
	return nil
end

local function collectTNTPlatforms()
	-- First, detect which level the player is currently in
	local playerLevelContainer = detectPlayerLevelContainer()
	
	-- If player is not in any level, try to use the last known level or find the first one
	if not playerLevelContainer then
		if currentPlayerLevelContainer and currentPlayerLevelContainer.Parent then
			playerLevelContainer = currentPlayerLevelContainer
		else
			-- Find the first TNT level (lowest number)
			local firstLevel = nil
			local lowestNumber = math.huge
			for _, descendant in ipairs(Workspace:GetDescendants()) do
				if (descendant:IsA("Folder") or descendant:IsA("Model")) and descendant.Name:match(CONFIG.TNT_LEVEL_PATTERN) then
					local levelStr = descendant.Name:match("TNT_Level_(%d+)")
					local levelNumber = levelStr and tonumber(levelStr) or math.huge
					if levelNumber < lowestNumber then
						lowestNumber = levelNumber
						firstLevel = descendant
					end
				end
			end
			playerLevelContainer = firstLevel
		end
	end
	
	-- Update current level container
	currentPlayerLevelContainer = playerLevelContainer
	
	if not playerLevelContainer then
		platformInfos = {}
		mainFrame.Visible = false
		return
	end
	
	-- Only collect platforms from the player's current level container
	local collected = {}
	local seenModels = {} -- Track models to avoid duplicates

	-- Search only within the player's current level container
	for _, descendant in ipairs(playerLevelContainer:GetDescendants()) do
		if descendant:IsA("Model") and descendant.Name == CONFIG.TNT_PLATFORM_NAME then
			-- Skip if we've already seen this model
			if not seenModels[descendant] then
				-- Verify this platform is actually in the level container (should be, but double-check)
				local levelContainer = getAncestorTNTLevel(descendant)
				if levelContainer == playerLevelContainer then
					local cf, _ = descendant:GetBoundingBox()
					seenModels[descendant] = true
					
					table.insert(collected, {
						model = descendant,
						levelContainer = levelContainer,
						height = cf.Position.Y,
					})
				end
			end
		end
	end

	-- Sort by height descending (highest = level 1)
	table.sort(collected, function(a, b)
		return a.height > b.height
	end)

	-- Limit to MAX_PLATFORMS
	if #collected > CONFIG.MAX_PLATFORMS then
		-- Keep only the first MAX_PLATFORMS (highest ones)
		for i = #collected, CONFIG.MAX_PLATFORMS + 1, -1 do
			table.remove(collected, i)
		end
	end

	platformInfos = {}
	minHeight = math.huge
	maxHeight = -math.huge

	for index, info in ipairs(collected) do
		info.levelIndex = index -- UI position (1-6)
		-- Always use levelIndex (1-6) as display number for consistency
		info.displayLevelNumber = index
		table.insert(platformInfos, info)
		
		if info.height > maxHeight then
			maxHeight = info.height
		end
		if info.height < minHeight then
			minHeight = info.height
		end
	end

	if #platformInfos == 0 then
		minHeight = 0
		maxHeight = 0
	end

	heightRange = maxHeight - minHeight
	if heightRange == 0 then
		heightRange = 1 -- Avoid division by zero
	end

	mainFrame.Visible = #platformInfos > 0
end

-- Convert world Y position to UI position (0 = top, 1 = bottom)
local function heightToUIPosition(worldY)
	if heightRange == 0 then
		return 0.5
	end
	-- Invert: higher Y = lower UI position (top of bar)
	local normalized = (maxHeight - worldY) / heightRange
	return math.clamp(normalized, 0, 1)
end

local function getPlayerThumbnail(userId)
	if thumbnailCache[userId] then
		return thumbnailCache[userId]
	end

	local success, content = pcall(function()
		local thumbnail, isReady = Players:GetUserThumbnailAsync(
			userId,
			Enum.ThumbnailType.HeadShot,
			Enum.ThumbnailSize.Size100x100
		)
		if isReady then
			return thumbnail
		end
		return nil
	end)

	if success and content then
		thumbnailCache[userId] = content
		return content
	end

	return CONFIG.FALLBACK_ICON
end

local function createLevelMarker(levelIndex, displayLevelNumber, totalLevels)
	local contentFrame = mainFrame:FindFirstChild("ContentFrame")
	if not contentFrame then
		return nil
	end

	local marker = Instance.new("Frame")
	marker.Name = ("LevelMarker_%d"):format(levelIndex)
	marker.Size = UDim2.new(0, CONFIG.LEVEL_MARKER_SIZE, 0, CONFIG.LEVEL_MARKER_SIZE)
	marker.BackgroundColor3 = CONFIG.LEVEL_MARKER_COLOR
	marker.BackgroundTransparency = 0 -- No transparency
	marker.BorderSizePixel = 0
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.Parent = contentFrame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0) -- Perfect circle
	corner.Parent = marker

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = CONFIG.LEVEL_MARKER_COLOR
	stroke.Transparency = 0.3
	stroke.Parent = marker

	local label = Instance.new("TextLabel")
	label.Name = "LevelLabel"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = tostring(displayLevelNumber)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 16
	label.TextColor3 = CONFIG.LEVEL_TEXT_COLOR
	label.Parent = marker

	-- Distribute markers evenly across the entire bar height
	-- Leave margins at top and bottom for marker size
	local margin = (CONFIG.LEVEL_MARKER_SIZE / 2) / CONFIG.BAR_HEIGHT
	local availableSpace = 1 - (2 * margin)
	
	-- Calculate position: evenly spaced from top to bottom
	-- Level 1 at top, Level 6 at bottom
	local positionInSequence = (levelIndex - 1) / math.max(1, totalLevels - 1)
	local uiPosition = margin + (positionInSequence * availableSpace)
	
	-- Clamp to valid range
	uiPosition = math.max(margin, math.min(1 - margin, uiPosition))
	marker.Position = UDim2.new(0.5, 0, uiPosition, 0)

	return marker
end

local function rebuildLevelMarkers()
	-- Clear existing markers
	for _, data in pairs(levelMarkers) do
		if data.marker then
			data.marker:Destroy()
		end
	end
	levelMarkers = {}

	local totalLevels = #platformInfos
	if totalLevels == 0 then
		return
	end

	-- Create new markers evenly distributed (1 to 6)
	for _, info in ipairs(platformInfos) do
		local displayNumber = info.displayLevelNumber or info.levelIndex
		local marker = createLevelMarker(info.levelIndex, displayNumber, totalLevels)
		if marker then
			levelMarkers[info.levelIndex] = {
				marker = marker,
				info = info,
			}
		end
	end
end

local function createOrUpdatePlayerIcon(userId, playerInstance, worldY)
	local contentFrame = mainFrame:FindFirstChild("ContentFrame")
	if not contentFrame then
		return
	end

	local isLocal = (playerInstance == localPlayer)
	local iconName = ("PlayerIcon_%d"):format(userId)
	
	-- First, check if we already have this icon tracked and it's valid
	local icon = nil
	if playerIcons[userId] and playerIcons[userId].icon then
		icon = playerIcons[userId].icon
		-- Verify it still exists and is in the right parent
		if not icon.Parent or icon.Parent ~= contentFrame or not icon:IsDescendantOf(contentFrame) then
			-- Icon is invalid, clear tracking
			icon = nil
			playerIcons[userId] = nil
		end
	end
	
	-- If not found in tracking, search for any existing icons with this name
	-- and destroy ALL duplicates (there might be multiple)
	if not icon then
		local existingIcons = {}
		for _, child in ipairs(contentFrame:GetChildren()) do
			if child.Name == iconName and child:IsA("ImageLabel") then
				table.insert(existingIcons, child)
			end
		end
		
		-- If we found any, keep the first one (or none if multiple found)
		if #existingIcons == 1 then
			icon = existingIcons[1]
		elseif #existingIcons > 1 then
			-- Multiple duplicates found, destroy all
			for _, dupIcon in ipairs(existingIcons) do
				dupIcon:Destroy()
			end
			icon = nil
		end
	end

	-- Create new icon only if we don't have one
	if not icon then
		icon = Instance.new("ImageLabel")
		icon.Name = iconName
		icon.Size = UDim2.new(0, CONFIG.PLAYER_ICON_SIZE, 0, CONFIG.PLAYER_ICON_SIZE)
		icon.BackgroundTransparency = 0.2
		icon.BackgroundColor3 = Color3.fromRGB(40, 45, 60)
		icon.BorderSizePixel = 0
		icon.Image = getPlayerThumbnail(userId)
		icon.ImageTransparency = 0
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Parent = contentFrame

		local iconCorner = Instance.new("UICorner")
		iconCorner.CornerRadius = UDim.new(1, 0) -- Circular
		iconCorner.Parent = icon

		if isLocal then
			local stroke = Instance.new("UIStroke")
			stroke.Thickness = 2.5
			stroke.Color = CONFIG.PLAYER_ICON_BORDER
			stroke.Parent = icon
		end
		
		-- Immediately track this new icon
		playerIcons[userId] = {
			icon = icon,
			tween = nil,
		}
	end

	-- Update position based on world Y
	local uiPosition = heightToUIPosition(worldY)
	local targetPosition = UDim2.new(0, -CONFIG.PLAYER_ICON_SIZE / 2 - 4, uiPosition, 0)

	-- Smoothly tween to new position
	if playerIcons[userId] and playerIcons[userId].tween then
		playerIcons[userId].tween:Cancel()
	end

	if icon.Position ~= targetPosition then
		local tween = TweenService:Create(
			icon,
			TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = targetPosition }
		)
		playerIcons[userId] = {
			icon = icon,
			tween = tween,
		}
		tween:Play()
		tween.Completed:Connect(function()
			if playerIcons[userId] and playerIcons[userId].tween == tween then
				playerIcons[userId].tween = nil
			end
		end)
	else
		-- Ensure tracking is up to date even if no movement
		if not playerIcons[userId] or playerIcons[userId].icon ~= icon then
			playerIcons[userId] = {
				icon = icon,
				tween = nil,
			}
		end
	end

	-- Update ZIndex (local player on top)
	if isLocal then
		icon.ZIndex = 10
	else
		icon.ZIndex = 5
	end
end

local function removePlayerIcon(userId)
	if playerIcons[userId] then
		if playerIcons[userId].tween then
			playerIcons[userId].tween:Cancel()
		end
		if playerIcons[userId].icon then
			playerIcons[userId].icon:Destroy()
		end
		playerIcons[userId] = nil
	end
end

-- Get the level index closest to a given world Y position
-- Improved logic: detects level based on proximity threshold, prioritizing higher levels when at same height
local PLATFORM_DETECTION_THRESHOLD = 10 -- Consider player "on" platform if within 10 studs

local function getLevelForHeight(worldY)
	if #platformInfos == 0 then
		return nil
	end

	-- Sort platforms by height (descending - level 1 is highest)
	local sortedPlatforms = {}
	for _, info in ipairs(platformInfos) do
		table.insert(sortedPlatforms, info)
	end
	table.sort(sortedPlatforms, function(a, b)
		return a.height > b.height
	end)

	-- Determine movement direction
	local isDescending = false
	if lastPlayerY ~= nil then
		isDescending = worldY < lastPlayerY
	end
	lastPlayerY = worldY

	-- First, check if player is within threshold of any platform
	-- But we need to be smart: if player is between two levels, prefer the higher one
	-- Only activate a level if player is very close to it (within 3 studs) OR if it's the highest level they're near
	
	-- Find all platforms within threshold
	local nearbyPlatforms = {}
	for _, info in ipairs(sortedPlatforms) do
		local delta = worldY - info.height
		local distance = math.abs(delta)
		
		local canActivate = false
		if isDescending then
			-- When descending, only consider if very close (3 studs) and at or above platform
			canActivate = distance <= 3 and delta >= 0
		else
			-- When ascending/stationary, use normal threshold with tolerance
			canActivate = distance <= PLATFORM_DETECTION_THRESHOLD and delta >= -2
		end
		
		if canActivate then
			table.insert(nearbyPlatforms, {info = info, distance = distance, delta = delta})
		end
	end
	
	-- If we found nearby platforms, return the highest one (lowest index number)
	if #nearbyPlatforms > 0 then
		-- Sort by level index (ascending - lower number = higher level)
		table.sort(nearbyPlatforms, function(a, b)
			return a.info.levelIndex < b.info.levelIndex
		end)
		
		local selected = nearbyPlatforms[1]
		return selected.info.levelIndex
	end

	-- If player is above the highest platform, return level 1
	if worldY >= sortedPlatforms[1].height then
		return sortedPlatforms[1].levelIndex
	end

	-- If player is below the lowest platform, return the lowest level
	if worldY <= sortedPlatforms[#sortedPlatforms].height then
		return sortedPlatforms[#sortedPlatforms].levelIndex
	end

	-- Find which two platforms the player is between
	for i = 1, #sortedPlatforms - 1 do
		local upperPlatform = sortedPlatforms[i]
		local lowerPlatform = sortedPlatforms[i + 1]
		
		-- If player is between these two platforms
		if worldY <= upperPlatform.height and worldY >= lowerPlatform.height then
			local distanceToLower = math.abs(worldY - lowerPlatform.height)
			
			-- Always prefer the upper level (higher level number = lower index) unless player is very close to the lower
			-- This ensures we don't skip levels and always show the level the player is currently on
			-- Only switch to lower level if player is very close to it (within 3 studs)
			
			if distanceToLower <= 3 then
				-- Player is very close to lower level, activate it
				return lowerPlatform.levelIndex
			else
				-- Player is not close enough to lower level, prefer upper level
				return upperPlatform.levelIndex
			end
		end
	end

	-- Fallback: return closest by distance
	local closestLevel = nil
	local closestDistance = math.huge
	for _, info in ipairs(sortedPlatforms) do
		local distance = math.abs(worldY - info.height)
		-- If same distance, prefer higher level (lower index number)
		if distance < closestDistance or (distance == closestDistance and info.levelIndex < closestLevel) then
			closestDistance = distance
			closestLevel = info.levelIndex
		end
	end

	return closestLevel
end

-- Update active level marker and progress fill based on local player position
local function updateActiveLevelMarker()
	-- Check if player has changed level containers - if so, refresh platform collection
	local detectedLevel = detectPlayerLevelContainer()
	if detectedLevel ~= currentPlayerLevelContainer then
		-- Player has moved to a different level, refresh everything
		collectTNTPlatforms()
		rebuildLevelMarkers()
		highestCompletedLevel = 0 -- Reset progress for new level
		lastPlayerY = nil -- Reset movement tracking
	end

	if #platformInfos == 0 then
		return
	end

	local character = localPlayer.Character
	if not character then
		-- Reset all markers to inactive
		for _, data in pairs(levelMarkers) do
			if data.marker then
				data.marker.BackgroundColor3 = CONFIG.LEVEL_MARKER_COLOR
				local stroke = data.marker:FindFirstChild("UIStroke")
				if stroke then
					stroke.Color = CONFIG.LEVEL_MARKER_COLOR
					stroke.Transparency = 0.3
					stroke.Thickness = 2
				end
			end
		end
		-- Reset progress fill
		if progressFill then
			progressFill.Size = UDim2.new(1, 0, 0, 0)
		end
		highestCompletedLevel = 0
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	local playerY = root.Position.Y
	
	-- Use height-based detection to determine active level
	local activeLevel = getLevelForHeight(playerY)

	-- Update highest completed level ONLY when player has reached a new lower level
	-- This ensures that once a level is marked as completed (red), it never gets unmarked
	-- We only update when activeLevel is valid and is greater than the current highestCompletedLevel
	if activeLevel and activeLevel > highestCompletedLevel then
		-- Only update if we're actually descending (not jumping up)
		-- Check if the player is actually at or below the platform height of the new level
		if #platformInfos > 0 and activeLevel <= #platformInfos then
			local targetPlatform = platformInfos[activeLevel]
			if targetPlatform then
				-- Only mark as completed if player is actually at or near the platform (within reasonable range)
				-- This prevents marking levels as completed when the player is just jumping
				local distanceToPlatform = math.abs(playerY - targetPlatform.height)
				-- If player is within 15 studs of the platform, consider it reached
				if distanceToPlatform <= 15 then
					-- Mark the previous level as completed (the one above the current)
					-- This ensures that once a level is marked red, it stays red
					highestCompletedLevel = activeLevel
				end
			end
		end
	end

	-- Update progress fill (fills from top as player descends)
	if progressFill then
		local uiPosition = heightToUIPosition(playerY)
		-- Fill from top (0) to current position
		local fillHeight = uiPosition
		fillHeight = math.max(0, math.min(1, fillHeight)) -- Clamp to 0-1
		
		local targetSize = UDim2.new(1, 0, fillHeight, 0)
		
		-- Smoothly tween the fill
		if progressFill.Size ~= targetSize then
			local tween = TweenService:Create(
				progressFill,
				TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Size = targetSize }
			)
			tween:Play()
		end
	end

	-- Update all markers
	-- Current level: blue (active)
	-- Completed levels (above highestCompletedLevel): red (permanently marked - NEVER unmarked)
	-- Inactive levels (below current): default gray
	for levelIndex, data in pairs(levelMarkers) do
		if data.marker then
			local isCurrent = levelIndex == activeLevel and activeLevel ~= nil
			-- Levels above the highest completed level are permanently marked as completed (red)
			-- This check is based ONLY on highestCompletedLevel, not on activeLevel
			-- Once highestCompletedLevel is set, levels above it stay red forever
			local isCompleted = highestCompletedLevel > 0 and levelIndex < highestCompletedLevel
			
			local stroke = data.marker:FindFirstChild("UIStroke")
			
			-- Priority: Completed (red) > Current (blue) > Inactive (gray)
			-- This ensures that completed levels stay red even if activeLevel changes
			if isCompleted then
				-- Completed levels (above highestCompletedLevel): red (permanently marked - NEVER changes)
				-- This takes highest priority - once red, always red
				data.marker.BackgroundColor3 = CONFIG.LEVEL_MARKER_COMPLETED_COLOR
				if stroke then
					stroke.Color = CONFIG.LEVEL_MARKER_COMPLETED_COLOR
					stroke.Transparency = 0
					stroke.Thickness = 2.5
				end
			elseif isCurrent then
				-- Current level: blue (only if not already marked as completed)
				data.marker.BackgroundColor3 = CONFIG.LEVEL_MARKER_ACTIVE_COLOR
				if stroke then
					stroke.Color = CONFIG.LEVEL_MARKER_ACTIVE_COLOR
					stroke.Transparency = 0
					stroke.Thickness = 3
				end
			else
				-- Inactive levels (not yet reached): default gray
				data.marker.BackgroundColor3 = CONFIG.LEVEL_MARKER_COLOR
				if stroke then
					stroke.Color = CONFIG.LEVEL_MARKER_COLOR
					stroke.Transparency = 0.3
					stroke.Thickness = 2
				end
			end
		end
	end
end

local function updatePlayerPositions()
	if not mainFrame or not mainFrame.Visible then
		return
	end

	local contentFrame = mainFrame:FindFirstChild("ContentFrame")
	if not contentFrame then
		return
	end

	-- First, clean up any duplicate icons that might exist
	local iconCounts = {}
	for _, child in ipairs(contentFrame:GetChildren()) do
		if child:IsA("ImageLabel") and child.Name:match("^PlayerIcon_%d+$") then
			local userId = tonumber(child.Name:match("(%d+)$"))
			if userId then
				if not iconCounts[userId] then
					iconCounts[userId] = {}
				end
				table.insert(iconCounts[userId], child)
			end
		end
	end

	-- Destroy duplicates, keep only one per user
	for userId, icons in pairs(iconCounts) do
		if #icons > 1 then
			-- Keep the first one that's tracked, or just the first one
			local keepIcon = nil
			if playerIcons[userId] and playerIcons[userId].icon then
				for _, icon in ipairs(icons) do
					if icon == playerIcons[userId].icon then
						keepIcon = icon
						break
					end
				end
			end
			
			-- If no tracked icon found, keep the first one
			if not keepIcon then
				keepIcon = icons[1]
			end
			
			-- Destroy all others
			for _, icon in ipairs(icons) do
				if icon ~= keepIcon then
					icon:Destroy()
				end
			end
			
			-- Update tracking if needed
			if keepIcon and (not playerIcons[userId] or playerIcons[userId].icon ~= keepIcon) then
				playerIcons[userId] = {
					icon = keepIcon,
					tween = nil,
				}
			end
		end
	end

	-- Track which players are still active
	local activePlayers = {}

	for _, playerInstance in ipairs(Players:GetPlayers()) do
		local character = playerInstance.Character
		if character then
			local root = character:FindFirstChild("HumanoidRootPart")
			if root then
				activePlayers[playerInstance.UserId] = true
				createOrUpdatePlayerIcon(playerInstance.UserId, playerInstance, root.Position.Y)
			end
		end
	end

	-- Remove icons for players who left or don't have characters
	for userId, _ in pairs(playerIcons) do
		if not activePlayers[userId] then
			removePlayerIcon(userId)
		end
	end

	-- Update active level marker
	updateActiveLevelMarker()
end

local function refreshPlatforms()
	collectTNTPlatforms()
	rebuildLevelMarkers()
end

local function onDescendantChanged(instance)
	if instance:IsA("Model") and (instance.Name == CONFIG.TNT_PLATFORM_NAME or instance.Name:match(CONFIG.TNT_LEVEL_PATTERN)) then
		task.defer(function()
			refreshPlatforms()
		end)
	end
end

-- Initialize
ensureScreenGui()
refreshPlatforms()

-- Listen for workspace changes
Workspace.DescendantAdded:Connect(onDescendantChanged)
Workspace.DescendantRemoving:Connect(onDescendantChanged)

-- Update loop
RunService.Heartbeat:Connect(function(dt)
	updateAccumulator += dt
	if updateAccumulator < CONFIG.UPDATE_INTERVAL then
		return
	end

	updateAccumulator = 0

	if #platformInfos == 0 then
		return
	end

	updatePlayerPositions()
end)

-- Handle player join/leave
Players.PlayerAdded:Connect(function()
	updateAccumulator = CONFIG.UPDATE_INTERVAL
end)

Players.PlayerRemoving:Connect(function(leavingPlayer)
	removePlayerIcon(leavingPlayer.UserId)
end)
