-- TNT Game Mode System
-- Dynamically handles TNT levels with the following structure:
--   workspace/
--     TNT_Level_1/ (Folder or Model)
--       TNTPlatform/ (Model - multiple instances with same name)
--         TNT/ (Model)
--           Part/ (BasePart - multiple instances)
--     TNT_Level_2/
--       ...
--
-- Behavior:
--   - When a Part inside TNT is touched by a player:
--     1. Part color changes (configurable, default: red)
--     2. Part Material changes to Neon
--     3. Part disappears after configurable delay (default: 0.3 seconds)
--     4. Part never reappears (permanently destroyed)
--
-- Configuration (via Attributes):
--   - TNTColor (Color3): Color when touched (can be set on Part, TNT, TNTPlatform, or TNT_Level_X)
--   - TNTDisappearDelay (number): Time in seconds before part disappears (can be set on Part, TNT, TNTPlatform, or TNT_Level_X)
--   - Attributes are inherited from parent to child (Part checks TNT, then TNTPlatform, then TNT_Level_X)

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

-- Configuration
local TNT_LEVEL_PATTERN = "^TNT_Level_%d+$" -- Pattern to match TNT_Level_1, TNT_Level_2, etc.
local TNT_PLATFORM_NAME = "TNTPlatform"
local TNT_MODEL_NAME = "TNT"
local PART_NAME = "Part"
local DEFAULT_DISAPPEAR_DELAY = 0.15 -- seconds before part disappears (faster default)
local DEFAULT_TNT_COLOR = Color3.fromRGB(255, 0, 0) -- Default red color

-- Detection settings for instant touch detection
local DETECTION_EXPAND = Vector3.new(1, 2, 1) -- Expand bounds for initial check

-- Track which parts have been destroyed (to prevent re-processing)
local destroyedParts = {} -- [part] = true
local activeDetectionParts = {} -- [part] = {connection, tntModel, tntPlatform, levelFolder}

-- Check if a part has already been destroyed
local function isPartDestroyed(part)
	return destroyedParts[part] == true or not part.Parent
end

-- Mark a part as destroyed
local function markPartDestroyed(part)
	destroyedParts[part] = true
	-- Clean up detection if active
	if activeDetectionParts[part] then
		local data = activeDetectionParts[part]
		if data.connection then
			data.connection:Disconnect()
		end
		activeDetectionParts[part] = nil
	end
end

-- Get configuration value from hierarchy (Part -> TNT -> TNTPlatform -> TNT_Level_X)
local function getConfigValue(part, attributeName, defaultValue, tntModel, tntPlatform, levelFolder)
	-- Check Part first
	local value = part:GetAttribute(attributeName)
	if value ~= nil then
		return value
	end

	-- Check TNT model
	if tntModel then
		value = tntModel:GetAttribute(attributeName)
		if value ~= nil then
			return value
		end
	end

	-- Check TNTPlatform
	if tntPlatform then
		value = tntPlatform:GetAttribute(attributeName)
		if value ~= nil then
			return value
		end
	end

	-- Check TNT Level
	if levelFolder then
		value = levelFolder:GetAttribute(attributeName)
		if value ~= nil then
			return value
		end
	end

	return defaultValue
end

-- Get color configuration
local function getTNTColor(part, tntModel, tntPlatform, levelFolder)
	local colorValue = getConfigValue(part, "TNTColor", nil, tntModel, tntPlatform, levelFolder)

	if colorValue then
		-- If it's a Color3, return it directly
		if typeof(colorValue) == "Color3" then
			return colorValue
		end
		-- If it's a string like "255,0,0", parse it
		if typeof(colorValue) == "string" then
			local r, g, b = colorValue:match("(%d+),(%d+),(%d+)")
			if r and g and b then
				return Color3.fromRGB(tonumber(r), tonumber(g), tonumber(b))
			end
		end
	end

	return DEFAULT_TNT_COLOR
end

-- Get disappear delay configuration
local function getDisappearDelay(part, tntModel, tntPlatform, levelFolder)
	local delay = getConfigValue(part, "TNTDisappearDelay", nil, tntModel, tntPlatform, levelFolder)
	if delay then
		local numDelay = tonumber(delay)
		if numDelay and numDelay > 0 then
			return numDelay
		end
	end
	return DEFAULT_DISAPPEAR_DELAY
end

-- Handle part touch - change color/neon and destroy after delay
local function handlePartTouch(part, tntColor, disappearDelay)
	-- Skip if already destroyed or being processed
	if isPartDestroyed(part) then
		return
	end

	-- Mark as destroyed immediately to prevent multiple triggers
	markPartDestroyed(part)

	-- Change color to configured color
	part.Color = tntColor

	-- Change material to Neon
	part.Material = Enum.Material.Neon

	-- Wait for delay, then destroy permanently
	task.delay(disappearDelay, function()
		if part and part.Parent then
			part:Destroy()
		end
	end)
end

-- Check if a part is currently being touched by any player (for initial check)
local function isPartCurrentlyTouched(part)
	if not part or not part.Parent then
		return false
	end

	local expand = DETECTION_EXPAND
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { part } -- Exclude the part itself
	overlapParams.RespectCanCollide = false

	local parts = Workspace:GetPartBoundsInBox(part.CFrame, part.Size + expand, overlapParams)

	for _, overlappingPart in ipairs(parts) do
		local character = overlappingPart.Parent
		if character then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				local player = Players:GetPlayerFromCharacter(character)
				if player then
					return true
				end
			end
		end
	end

	return false
end

-- Verify if hit is from a valid player character
local function isValidPlayerTouch(hit)
	if not hit then
		return false
	end

	local character = hit.Parent
	if not character then
		return false
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end

	local player = Players:GetPlayerFromCharacter(character)
	return player ~= nil
end

-- Setup instant touch detection for a single Part using Touched event
local function setupTNTPart(part, tntModel, tntPlatform, levelFolder)
	if not part or not part:IsA("BasePart") then
		return
	end

	-- Skip if already wired
	if part:GetAttribute("_TNTWired") then
		return
	end

	part:SetAttribute("_TNTWired", true)

	-- Get configuration values
	local tntColor = getTNTColor(part, tntModel, tntPlatform, levelFolder)
	local disappearDelay = getDisappearDelay(part, tntModel, tntPlatform, levelFolder)

	-- Use Touched event for instant detection
	local touchConnection
	touchConnection = part.Touched:Connect(function(hit)
		-- Skip if already destroyed
		if isPartDestroyed(part) then
			return
		end

		-- Verify it's a valid player touch
		if isValidPlayerTouch(hit) then
			handlePartTouch(part, tntColor, disappearDelay)
		end
	end)

	-- Also check if part is already being touched (for parts that are set up while player is on them)
	task.spawn(function()
		task.wait() -- Small delay to ensure everything is set up
		if not isPartDestroyed(part) and isPartCurrentlyTouched(part) then
			handlePartTouch(part, tntColor, disappearDelay)
		end
	end)

	-- Store connection for cleanup
	activeDetectionParts[part] = {
		connection = touchConnection,
		tntModel = tntModel,
		tntPlatform = tntPlatform,
		levelFolder = levelFolder,
	}

	-- Cleanup connection when part is destroyed
	part.Destroying:Connect(function()
		if touchConnection then
			touchConnection:Disconnect()
		end
		markPartDestroyed(part)
	end)
end

-- Setup all Parts inside a TNT model
local function setupTNTModel(tntModel, tntPlatform, levelFolder)
	if not tntModel or not tntModel:IsA("Model") then
		return
	end

	-- Find all Parts inside the TNT model
	for _, descendant in ipairs(tntModel:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name == PART_NAME then
			setupTNTPart(descendant, tntModel, tntPlatform, levelFolder)
		end
	end

	-- Also handle new Parts added dynamically
	local descendantAddedConnection
	descendantAddedConnection = tntModel.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") and descendant.Name == PART_NAME then
			setupTNTPart(descendant, tntModel, tntPlatform, levelFolder)
		end
	end)

	-- Cleanup when TNT model is destroyed
	tntModel.Destroying:Connect(function()
		if descendantAddedConnection then
			descendantAddedConnection:Disconnect()
		end
	end)
end

-- Setup all TNT models inside a TNTPlatform
local function setupTNTPlatform(tntPlatform, levelFolder)
	if not tntPlatform or not tntPlatform:IsA("Model") then
		return
	end

	-- Find all TNT models inside the TNTPlatform
	for _, child in ipairs(tntPlatform:GetChildren()) do
		if child:IsA("Model") and child.Name == TNT_MODEL_NAME then
			setupTNTModel(child, tntPlatform, levelFolder)
		end
	end

	-- Also handle new TNT models added dynamically
	local childAddedConnection
	childAddedConnection = tntPlatform.ChildAdded:Connect(function(child)
		if child:IsA("Model") and child.Name == TNT_MODEL_NAME then
			setupTNTModel(child, tntPlatform, levelFolder)
		end
	end)

	-- Cleanup when TNTPlatform is destroyed
	tntPlatform.Destroying:Connect(function()
		if childAddedConnection then
			childAddedConnection:Disconnect()
		end
	end)
end

-- Setup all TNTPlatforms inside a TNT level
local function setupTNTLevel(levelFolder)
	if not levelFolder then
		return
	end

	-- Find all TNTPlatform models inside the level
	for _, child in ipairs(levelFolder:GetChildren()) do
		if child:IsA("Model") and child.Name == TNT_PLATFORM_NAME then
			setupTNTPlatform(child, levelFolder)
		end
	end

	-- Also handle new TNTPlatforms added dynamically
	local childAddedConnection
	childAddedConnection = levelFolder.ChildAdded:Connect(function(child)
		if child:IsA("Model") and child.Name == TNT_PLATFORM_NAME then
			setupTNTPlatform(child, levelFolder)
		end
	end)

	-- Cleanup when level is destroyed
	levelFolder.Destroying:Connect(function()
		if childAddedConnection then
			childAddedConnection:Disconnect()
		end
	end)
end

-- Check if a folder/model name matches the TNT level pattern
local function isTNTLevel(name)
	return name:match(TNT_LEVEL_PATTERN) ~= nil
end

-- Initialize all existing TNT levels
local function initializeTNTLevels()
	-- Search workspace for TNT level folders/models
	for _, child in ipairs(Workspace:GetChildren()) do
		if (child:IsA("Folder") or child:IsA("Model")) and isTNTLevel(child.Name) then
			print(string.format("[TNTSystem] Found TNT level: %s", child.Name))
			setupTNTLevel(child)
		end
	end

	-- Also search recursively in case levels are nested
	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if (descendant:IsA("Folder") or descendant:IsA("Model")) and isTNTLevel(descendant.Name) then
			-- Check if we already processed this (it might be a parent)
			local alreadyProcessed = false
			local ancestor = descendant.Parent
			while ancestor and ancestor ~= Workspace do
				if isTNTLevel(ancestor.Name) then
					alreadyProcessed = true
					break
				end
				ancestor = ancestor.Parent
			end

			if not alreadyProcessed then
				print(string.format("[TNTSystem] Found nested TNT level: %s", descendant.Name))
				setupTNTLevel(descendant)
			end
		end
	end
end

-- Handle new TNT levels added dynamically
local function setupDynamicTNTLevels()
	Workspace.ChildAdded:Connect(function(child)
		if (child:IsA("Folder") or child:IsA("Model")) and isTNTLevel(child.Name) then
			print(string.format("[TNTSystem] New TNT level added: %s", child.Name))
			setupTNTLevel(child)
		end
	end)

	-- Also handle nested levels
	Workspace.DescendantAdded:Connect(function(descendant)
		if (descendant:IsA("Folder") or descendant:IsA("Model")) and isTNTLevel(descendant.Name) then
			-- Check if parent is also a TNT level (if so, skip - parent handler will catch it)
			local parent = descendant.Parent
			if parent and parent ~= Workspace and isTNTLevel(parent.Name) then
				return
			end

			print(string.format("[TNTSystem] New nested TNT level added: %s", descendant.Name))
			setupTNTLevel(descendant)
		end
	end)
end

-- ============================================
-- TNT Player Spawn System
-- Spawns players on Parts of the highest platform with minimum 4 studs distance
-- ============================================

local MIN_SPAWN_DISTANCE = 4 -- Minimum distance between spawns in studs
local playerSpawnPositions = {} -- [player] = Vector3 (track where each player spawned)

-- Helper function to find TNT level ancestor (same as used in main code)
local function getAncestorTNTLevel(instance)
	local ancestor = instance
	while ancestor and ancestor ~= Workspace do
		if ancestor.Name:match(TNT_LEVEL_PATTERN) then
			return ancestor
		end
		ancestor = ancestor.Parent
	end
	return nil
end

-- Find the highest TNTPlatform (first platform)
local function findHighestTNTPlatform()
	local highestPlatform = nil
	local highestY = -math.huge

	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if descendant:IsA("Model") and descendant.Name == TNT_PLATFORM_NAME then
			local levelContainer = getAncestorTNTLevel(descendant)
			if levelContainer then
				local cf, _ = descendant:GetBoundingBox()
				if cf.Position.Y > highestY then
					highestY = cf.Position.Y
					highestPlatform = descendant
				end
			end
		end
	end

	return highestPlatform
end

-- Get all Parts from a TNTPlatform
local function getPartsFromPlatform(platform)
	local parts = {}

	-- Search for TNT models inside the platform
	for _, child in ipairs(platform:GetDescendants()) do
		if child:IsA("Model") and child.Name == TNT_MODEL_NAME then
			-- Get all Parts inside this TNT model
			for _, part in ipairs(child:GetDescendants()) do
				if part:IsA("BasePart") and part.Name == PART_NAME then
					table.insert(parts, part)
				end
			end
		end
	end

	return parts
end

-- Check if a position is far enough from all existing spawn positions
local function isPositionValid(newPos, existingPositions, minDistance)
	for _, existingPos in ipairs(existingPositions) do
		local distance = (newPos - existingPos).Magnitude
		if distance < minDistance then
			return false
		end
	end
	return true
end

-- Spawn player on a Part of the highest platform
local function spawnPlayerOnTNTPlatform(player)
	if not player or not player.Character then
		return false
	end

	local character = player.Character
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return false
	end

	-- Find highest platform
	local highestPlatform = findHighestTNTPlatform()
	if not highestPlatform then
		warn(string.format("[TNTSystem] No TNTPlatform found for spawning player %s", player.Name))
		return false
	end

	-- Get all Parts from the platform
	local parts = getPartsFromPlatform(highestPlatform)
	if #parts == 0 then
		warn(string.format("[TNTSystem] No Parts found in highest TNTPlatform for spawning player %s", player.Name))
		return false
	end

	-- Get existing spawn positions (from other players)
	local existingPositions = {}
	for otherPlayer, spawnPos in pairs(playerSpawnPositions) do
		if otherPlayer ~= player and otherPlayer.Parent and otherPlayer.Character then
			local otherRoot = otherPlayer.Character:FindFirstChild("HumanoidRootPart")
			if otherRoot then
				table.insert(existingPositions, otherRoot.Position)
			end
		end
	end

	-- Try to find a valid spawn position
	local validParts = {}
	for _, part in ipairs(parts) do
		if part and part.Parent then
			local partPosition = part.Position
			-- Add offset to spawn on top of the part
			local spawnPosition = partPosition + Vector3.new(0, part.Size.Y / 2 + 3, 0)

			if isPositionValid(spawnPosition, existingPositions, MIN_SPAWN_DISTANCE) then
				table.insert(validParts, { part = part, position = spawnPosition })
			end
		end
	end

	-- If no valid parts with distance, use any part (fallback)
	if #validParts == 0 then
		for _, part in ipairs(parts) do
			if part and part.Parent then
				local partPosition = part.Position
				local spawnPosition = partPosition + Vector3.new(0, part.Size.Y / 2 + 3, 0)
				table.insert(validParts, { part = part, position = spawnPosition })
			end
		end
	end

	if #validParts == 0 then
		warn(string.format("[TNTSystem] No valid spawn positions found for player %s", player.Name))
		return false
	end

	-- Pick a random valid part
	local selected = validParts[math.random(1, #validParts)]

	-- Spawn player
	rootPart.CFrame = CFrame.new(selected.position)
	rootPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)

	-- Track spawn position
	playerSpawnPositions[player] = selected.position

	print(
		string.format(
			"[TNTSystem] Spawned player %s on highest TNTPlatform at position %s",
			player.Name,
			tostring(selected.position)
		)
	)

	return true
end

-- Handle player joining - spawn on highest platform
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		task.wait(0.5) -- Wait for character to fully load

		-- Skip if player is in BombTag mode
		if player:GetAttribute("BombTagActive") then
			return
		end

		-- Spawn on highest TNT platform
		spawnPlayerOnTNTPlatform(player)
	end)
end)

-- Cleanup on player leave
Players.PlayerRemoving:Connect(function(player)
	playerSpawnPositions[player] = nil
end)

-- Initialize on server start
task.wait(1) -- Wait for workspace to load
initializeTNTLevels()
setupDynamicTNTLevels()

print("[TNTSystem] TNT Game Mode System initialized")
