-- Level Management System
-- Handles level progression, unlocking, completion tracking, and player spawning
-- 
-- Level Structure in Workspace:
--   workspace.Levels/
--     Level_1/ (Model or Folder - both work identically!)
--       - Spawn (BasePart or Model with "LevelSpawn" tag)
--       - Finish (BasePart or Model with "LevelFinish" tag)
--       - Checkpoints, obstacles, etc.
--     Level_2/
--       ...
--
-- Level Attributes (on the level folder/model):
--   - LevelId (string): Unique identifier for the level (e.g., "Level_1")
--   - LevelName (string): Display name (e.g., "The Beginning")
--   - LevelNumber (number): Sequential level number for unlocking (1, 2, 3...)
--   - Difficulty (string): "Easy", "Medium", "Hard", "Extreme" (optional)
--   - RequiredLevel (number): Minimum level number that must be completed to unlock (optional)
--   - CoinsReward (number): Coins awarded on completion (optional)
--   - DiamondsReward (number): Diamonds awarded on completion (optional)
--   - XPReward (number): XP awarded on completion (optional)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")

local PlayerProfile = require(ServerScriptService:WaitForChild("PlayerProfile"))

local BOMB_TAG_ACTIVE_ATTRIBUTE = "BombTagActive"

-- Configuration
local LEVELS_FOLDER_NAME = "Levels"
local SPAWN_TAG = "LevelSpawn"
local FINISH_TAG = "LevelFinish"

-- Testing flag: Always award rewards on completion (even if already completed)
local ALWAYS_AWARD_REWARDS = true -- Set to false in production

-- Store player level state
local playerCurrentLevel = {} -- [player] = levelId
local playerLevelStartTime = {} -- [player] = startTime (for completion time tracking)
local playerCheckpointTimes = {} -- [player][checkpointId] = time
local playerFinishCooldown = {} -- [player] = lastFinishTime (prevent multiple triggers)

-- Wait for Remotes folder
local remoteFolder = ReplicatedStorage:WaitForChild("Remotes", 10)
if not remoteFolder then
	remoteFolder = Instance.new("Folder")
	remoteFolder.Name = "Remotes"
	remoteFolder.Parent = ReplicatedStorage
end

-- Create RemoteEvents
local function getRemote(name)
	local remote = remoteFolder:FindFirstChild(name)
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = remoteFolder
	end
	return remote
end

local levelSelectRemote = getRemote("SelectLevel")
local levelCompleteRemote = getRemote("LevelComplete")

-- Find the Levels folder in workspace
local function findLevelsFolder()
	local levelsFolder = workspace:FindFirstChild(LEVELS_FOLDER_NAME)
	if not levelsFolder then
		warn(string.format("[LevelSystem] Levels folder '%s' not found in workspace. Please create it.", LEVELS_FOLDER_NAME))
		return nil
	end
	return levelsFolder
end

-- Get all level objects (Models or Folders)
local function getAllLevels()
	local levelsFolder = findLevelsFolder()
	if not levelsFolder then
		return {}
	end

	local levels = {}
	for _, child in ipairs(levelsFolder:GetChildren()) do
		if child:IsA("Model") or child:IsA("Folder") then
			local levelId = child:GetAttribute("LevelId") or child.Name
			levels[levelId] = child
		end
	end
	return levels
end

-- Get level metadata from attributes
local function getLevelMetadata(levelObject)
	if not levelObject then
		return nil
	end

	return {
		id = levelObject:GetAttribute("LevelId") or levelObject.Name,
		name = levelObject:GetAttribute("LevelName") or levelObject.Name,
		number = tonumber(levelObject:GetAttribute("LevelNumber")) or 1,
		difficulty = levelObject:GetAttribute("Difficulty") or "Easy",
		requiredLevel = tonumber(levelObject:GetAttribute("RequiredLevel")) or nil,
		coinsReward = tonumber(levelObject:GetAttribute("CoinsReward")) or 0,
		diamondsReward = tonumber(levelObject:GetAttribute("DiamondsReward")) or 0,
		xpReward = tonumber(levelObject:GetAttribute("XPReward")) or 0,
		object = levelObject,
	}
end

-- Recursively find an object by name in a hierarchy
local function findInHierarchy(parent, name, objectType)
	if not parent then
		return nil
	end
	
	-- Check all descendants recursively
	for _, descendant in ipairs(parent:GetDescendants()) do
		if descendant.Name == name then
			if not objectType or descendant:IsA(objectType) then
				return descendant
			end
		end
	end
	
	-- Also check direct children
	local directChild = parent:FindFirstChild(name)
	if directChild then
		if not objectType or directChild:IsA(objectType) then
			return directChild
		end
	end
	
	return nil
end

-- Get position from any object (BasePart, MeshPart, or Model)
local function getObjectPosition(obj)
	if not obj then
		return nil
	end
	
	if obj:IsA("BasePart") or obj:IsA("MeshPart") then
		return obj.Position
	elseif obj:IsA("Model") then
		local primaryPart = obj.PrimaryPart
		if primaryPart then
			return primaryPart.Position
		end
		-- Find first BasePart/MeshPart
		for _, descendant in ipairs(obj:GetDescendants()) do
			if descendant:IsA("BasePart") or descendant:IsA("MeshPart") then
				return descendant.Position
			end
		end
	end
	
	return nil
end

-- Find spawn point in a level (searches recursively in entire hierarchy)
local function findLevelSpawn(levelObject)
	if not levelObject then
		return nil
	end

	-- First: Look for objects with LevelSpawn tag
	local spawns = CollectionService:GetTagged(SPAWN_TAG)
	for _, spawn in ipairs(spawns) do
		-- Check if spawn is inside this level
		local ancestor = spawn
		while ancestor do
			if ancestor == levelObject then
				return spawn
			end
			ancestor = ancestor.Parent
		end
	end

	-- Second: Recursively search for anything named "LevelStart" in the level hierarchy
	local spawn = findInHierarchy(levelObject, "LevelStart")
	if spawn then
		-- Return the spawn object itself (could be BasePart, MeshPart, or Model)
		return spawn
	end

	warn(string.format("[LevelSystem] No spawn point found for level: %s (searched recursively for 'LevelStart' or 'LevelSpawn' tag)", levelObject.Name))
	return nil
end

-- Find finish point in a level (searches recursively in entire hierarchy)
local function findLevelFinish(levelObject)
	if not levelObject then
		return nil
	end

	-- First: Look for objects with LevelFinish tag
	local finishes = CollectionService:GetTagged(FINISH_TAG)
	for _, finish in ipairs(finishes) do
		-- Check if finish is inside this level
		local ancestor = finish
		while ancestor do
			if ancestor == levelObject then
				return finish
			end
			ancestor = ancestor.Parent
		end
	end

	-- Second: Recursively search for anything named "LevelFinish" in the level hierarchy
	local finish = findInHierarchy(levelObject, "LevelFinish")
	if finish then
		-- Return the finish object itself (could be BasePart, MeshPart, or Model)
		return finish
	end

	return nil
end

-- Get spawn position from spawn object (works with BasePart, MeshPart, or Model)
local function getSpawnPosition(spawnObject)
	return getObjectPosition(spawnObject)
end

-- Check if player has unlocked a level
local function isLevelUnlocked(player, levelMetadata)
	if not player or not levelMetadata then
		return false
	end

	local profile = PlayerProfile.load(player.UserId)

	-- Level 1 is always unlocked
	if levelMetadata.number == 1 then
		return true
	end

	-- Check required level completion
	if levelMetadata.requiredLevel then
		local completedLevels = profile.progression.completedLevels or {}
		return completedLevels[tostring(levelMetadata.requiredLevel)] == true
	end

	-- Default: unlock if previous level is completed
	local previousLevel = levelMetadata.number - 1
	local completedLevels = profile.progression.completedLevels or {}
	return completedLevels[tostring(previousLevel)] == true
end

-- Spawn player at a level
local function spawnPlayerAtLevel(player, levelId)
	if not player or not levelId then
		return false
	end

	if player:GetAttribute(BOMB_TAG_ACTIVE_ATTRIBUTE) then
		return false
	end

	local levels = getAllLevels()
	local levelObject = levels[levelId]
	if not levelObject then
		warn(string.format("[LevelSystem] Level not found: %s", levelId))
		return false
	end

	-- Get level metadata
	local metadata = getLevelMetadata(levelObject)
	if not metadata then
		return false
	end

	-- Check if level is unlocked
	if not isLevelUnlocked(player, metadata) then
		warn(string.format("[LevelSystem] Player %s tried to access locked level: %s", player.Name, levelId))
		levelSelectRemote:FireClient(player, false, "Level is locked")
		return false
	end

	-- Wait for character
	if not player.Character then
		player:LoadCharacter()
		player.CharacterAdded:Wait()
	end

	local character = player.Character
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return false
	end

	-- Find spawn point
	local spawnObject = findLevelSpawn(levelObject)
	if not spawnObject then
		warn(string.format("[LevelSystem] No spawn point found for level: %s", levelId))
		return false
	end

	local spawnPosition = getSpawnPosition(spawnObject)
	if not spawnPosition then
		return false
	end

	-- Teleport player to spawn
	rootPart.CFrame = CFrame.new(spawnPosition + Vector3.new(0, 5, 0))
	rootPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)

	-- Set current level
	playerCurrentLevel[player] = levelId
	playerLevelStartTime[player] = os.time()
	playerCheckpointTimes[player] = {}

	-- Initialize progress tracking (if LevelProgressTracker is available)
	-- Use a delay to ensure LevelProgressTracker is loaded
	task.spawn(function()
		task.wait(1) -- Wait for LevelProgressTracker to be ready
		local success, progressTracker = pcall(function()
			-- Try to require, but don't wait forever
			local trackerScript = script.Parent:FindFirstChild("LevelProgressTracker")
			if trackerScript then
				return require(trackerScript)
			end
			return nil
		end)
		if success and progressTracker then
			local initSuccess = pcall(function()
				progressTracker.initializePlayerProgress(player, levelId)
			end)
			if not initSuccess then
				warn(string.format("[LevelSystem] Failed to initialize progress tracking for player %s", player.Name))
			end
		else
			-- Don't warn, it's optional
		end
	end)

	-- Notify client
	levelSelectRemote:FireClient(player, true, metadata)

	print(string.format("[LevelSystem] Player %s spawned at level: %s (%s)", player.Name, metadata.name, levelId))
	return true
end

-- Handle level completion
local function handleLevelComplete(player, levelId)
	if not player or not levelId then
		return
	end

	-- Verify player is actually in this level
	if playerCurrentLevel[player] ~= levelId then
		return
	end

	local levels = getAllLevels()
	local levelObject = levels[levelId]
	if not levelObject then
		return
	end

	local metadata = getLevelMetadata(levelObject)
	if not metadata then
		return
	end

	local profile = PlayerProfile.load(player.UserId)

	-- Calculate completion time
	local startTime = playerLevelStartTime[player] or os.time()
	local completionTime = os.time() - startTime

	-- Mark level as completed
	profile.progression = profile.progression or {}
	profile.progression.completedLevels = profile.progression.completedLevels or {}
	local levelKey = tostring(metadata.number)
	local wasAlreadyCompleted = profile.progression.completedLevels[levelKey] == true

	-- Update best time if this is better or first completion
	profile.progression.levelTimes = profile.progression.levelTimes or {}
	local currentBestTime = profile.progression.levelTimes[levelKey]
	if not currentBestTime or completionTime < currentBestTime then
		profile.progression.levelTimes[levelKey] = completionTime
	end

	-- Mark as completed (only first time rewards)
	if not wasAlreadyCompleted then
		profile.progression.completedLevels[levelKey] = true
	end

	-- Award rewards (always if ALWAYS_AWARD_REWARDS is true, otherwise only on first completion)
	local shouldAward = ALWAYS_AWARD_REWARDS or not wasAlreadyCompleted
	if shouldAward then
		local coinsAwarded = 0
		local diamondsAwarded = 0
		
		if metadata.coinsReward > 0 then
			PlayerProfile.addCoins(player.UserId, metadata.coinsReward)
			coinsAwarded = metadata.coinsReward
		end
		if metadata.diamondsReward > 0 then
			PlayerProfile.addDiamonds(player.UserId, metadata.diamondsReward)
			diamondsAwarded = metadata.diamondsReward
		end
		if metadata.xpReward > 0 then
			-- XP system would be handled here
			-- For now, we'll just log it
			print(string.format("[LevelSystem] Player %s earned %d XP from level %s", player.Name, metadata.xpReward, levelId))
		end
		
		-- Notify client to show reward animations (using existing Currency system)
		if coinsAwarded > 0 or diamondsAwarded > 0 then
			-- Get current balances to send to client
			local currentCoins, currentDiamonds = PlayerProfile.getBalances(player.UserId)
			
			local currencyRemote = remoteFolder:FindFirstChild("CurrencyUpdated")
			if currencyRemote then
				currencyRemote:FireClient(player, {
					Coins = currentCoins,
					Diamonds = currentDiamonds,
					AwardedCoins = coinsAwarded,
					AwardedDiamonds = diamondsAwarded,
				})
				print(string.format("[LevelSystem] Awarded %d coins and %d diamonds to %s (with animations)", coinsAwarded, diamondsAwarded, player.Name))
			end
		end
	end

	-- Always try to teleport to next level (whether first completion or not)
	local nextLevelNumber = metadata.number + 1
	local nextLevelId = nil
	local allLevels = getAllLevels()
	
	print(string.format("[LevelSystem] Looking for next level: Level %d (current: Level %d)", nextLevelNumber, metadata.number))
	
	for id, obj in pairs(allLevels) do
		local nextMetadata = getLevelMetadata(obj)
		if nextMetadata and nextMetadata.number == nextLevelNumber then
			-- Check if next level is unlocked
			if isLevelUnlocked(player, nextMetadata) then
				nextLevelId = id
				print(string.format("[LevelSystem] Found next level: %s (Level %d)", nextLevelId, nextLevelNumber))
				break
			else
				print(string.format("[LevelSystem] Next level %s exists but is locked", id))
			end
		end
	end

	if nextLevelId then
		if not wasAlreadyCompleted then
			print(string.format("[LevelSystem] Player %s unlocked level: %s", player.Name, nextLevelId))
		end
		
		-- Automatically teleport to next level after a short delay
		task.spawn(function()
			task.wait(2) -- 2 second delay to show completion UI
			
			-- Check if player is still in game and hasn't manually selected a different level
			if player and player.Parent then
				-- Clear finish cooldown so they can complete next level
				playerFinishCooldown[player] = nil
				
				-- Only teleport if still in the same level (or no level assigned)
				local currentLevel = playerCurrentLevel[player]
				if not currentLevel or currentLevel == levelId then
					print(string.format("[LevelSystem] Auto-teleporting %s to next level: %s", player.Name, nextLevelId))
					local success = spawnPlayerAtLevel(player, nextLevelId)
					if success then
						print(string.format("[LevelSystem] Successfully teleported %s to %s", player.Name, nextLevelId))
					else
						warn(string.format("[LevelSystem] Failed to teleport %s to %s", player.Name, nextLevelId))
					end
				else
					print(string.format("[LevelSystem] Player %s changed level manually to %s, skipping auto-teleport", player.Name, currentLevel))
				end
			else
				warn(string.format("[LevelSystem] Player %s left the game before teleportation", player.Name))
			end
		end)
	else
		print(string.format("[LevelSystem] No next level found for player %s (completed level %d). Total levels: %d", 
			player.Name, metadata.number, 
			(function() local count = 0 for _ in pairs(allLevels) do count = count + 1 end return count end)()))
	end

	-- Save profile
	PlayerProfile.save(player.UserId)

	-- Notify client
	local completionData = {
		levelId = levelId,
		levelName = metadata.name,
		completionTime = completionTime,
		bestTime = profile.progression.levelTimes[levelKey],
		firstCompletion = not wasAlreadyCompleted,
		coinsReward = (ALWAYS_AWARD_REWARDS or not wasAlreadyCompleted) and metadata.coinsReward or 0,
		diamondsReward = (ALWAYS_AWARD_REWARDS or not wasAlreadyCompleted) and metadata.diamondsReward or 0,
		xpReward = (ALWAYS_AWARD_REWARDS or not wasAlreadyCompleted) and metadata.xpReward or 0,
	}

	levelCompleteRemote:FireClient(player, completionData)

	print(string.format("[LevelSystem] Player %s completed level: %s in %d seconds", player.Name, metadata.name, completionTime))

	-- Stop progress tracking for this level
	local success, progressTracker = pcall(function()
		return require(script.Parent.LevelProgressTracker)
	end)
	if success and progressTracker then
		progressTracker.stopTrackingPlayer(player)
	end

	-- Clear level state (will be set again when spawning at next level)
	-- Don't clear immediately to allow completion UI to show
	task.spawn(function()
		task.wait(3) -- Wait a bit longer than teleport delay
		if playerCurrentLevel[player] == levelId then
			playerCurrentLevel[player] = nil
			playerLevelStartTime[player] = nil
			playerCheckpointTimes[player] = nil
		end
	end)
end

-- Setup finish detection for a level
local function setupFinishDetection(levelObject, finishObject)
	if not levelObject or not finishObject then
		return
	end

	local levelId = levelObject:GetAttribute("LevelId") or levelObject.Name

	-- Handle BasePart/MeshPart finish
	if finishObject:IsA("BasePart") or finishObject:IsA("MeshPart") then
		if finishObject:GetAttribute("_FinishWired") then
			return
		end
		finishObject:SetAttribute("_FinishWired", true)

		local connection
		connection = finishObject.Touched:Connect(function(hit)
			if not hit then
				return
			end

			local character = hit.Parent
			if not character then
				return
			end

			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if not humanoid then
				return
			end

			local player = Players:GetPlayerFromCharacter(character)
			if not player then
				return
			end

			-- Verify player is in this level
			if playerCurrentLevel[player] ~= levelId then
				return
			end

			-- Cooldown to prevent multiple triggers (1 second)
			local lastFinishTime = playerFinishCooldown[player] or 0
			local currentTime = tick()
			if currentTime - lastFinishTime < 1 then
				return -- Still on cooldown
			end
			playerFinishCooldown[player] = currentTime

			-- Complete level (tag verification removed - works with named parts too)
			print(string.format("[LevelSystem] Player %s touched finish for level: %s", player.Name, levelId))
			handleLevelComplete(player, levelId)
		end)

		finishObject.Destroying:Connect(function()
			if connection then
				connection:Disconnect()
			end
		end)
	end

	-- Handle Model finish
	if finishObject:IsA("Model") then
		if finishObject:GetAttribute("_FinishWired") then
			return
		end
		finishObject:SetAttribute("_FinishWired", true)

		local connections = {}

		local function connectPart(part)
			if not (part:IsA("BasePart") or part:IsA("MeshPart")) then
				return
			end

			local connection
			connection = part.Touched:Connect(function(hit)
				if not hit then
					return
				end

				local character = hit.Parent
				if not character then
					return
				end

				local humanoid = character:FindFirstChildOfClass("Humanoid")
				if not humanoid then
					return
				end

				local player = Players:GetPlayerFromCharacter(character)
				if not player then
					return
				end

				-- Verify player is in this level
				if playerCurrentLevel[player] ~= levelId then
					return
				end

				-- Cooldown to prevent multiple triggers (1 second)
				local lastFinishTime = playerFinishCooldown[player] or 0
				local currentTime = tick()
				if currentTime - lastFinishTime < 1 then
					return -- Still on cooldown
				end
				playerFinishCooldown[player] = currentTime

				-- Complete level (tag verification removed - works with named parts too)
				print(string.format("[LevelSystem] Player %s touched finish for level: %s", player.Name, levelId))
				handleLevelComplete(player, levelId)
			end)

			table.insert(connections, connection)
		end

		-- Connect existing parts (BasePart, MeshPart, or nested models)
		for _, descendant in ipairs(finishObject:GetDescendants()) do
			if descendant:IsA("BasePart") or descendant:IsA("MeshPart") then
				connectPart(descendant)
			end
		end

		-- Connect new parts
		local descendantAddedConnection
		descendantAddedConnection = finishObject.DescendantAdded:Connect(function(descendant)
			if descendant:IsA("BasePart") or descendant:IsA("MeshPart") then
				connectPart(descendant)
			end
		end)

		finishObject.Destroying:Connect(function()
			for _, conn in ipairs(connections) do
				if conn then
					conn:Disconnect()
				end
			end
			if descendantAddedConnection then
				descendantAddedConnection:Disconnect()
			end
		end)
	end
end

-- Initialize finish detection for all levels
local function initializeLevels()
	local levels = getAllLevels()
	local levelCount = 0
	for _ in pairs(levels) do
		levelCount = levelCount + 1
	end
	print(string.format("[LevelSystem] Initializing %d levels...", levelCount))
	for levelId, levelObject in pairs(levels) do
		local finish = findLevelFinish(levelObject)
		if finish then
			print(string.format("[LevelSystem] Found finish for level: %s (finish type: %s)", levelId, finish.ClassName))
			setupFinishDetection(levelObject, finish)
		else
			warn(string.format("[LevelSystem] No finish point found for level: %s (make sure there's a part named 'LevelFinish' or a part with 'LevelFinish' tag)", levelId))
		end
	end
end

-- Handle player joining - spawn at first level
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		task.wait(0.5) -- Wait for character to fully load

		if player:GetAttribute(BOMB_TAG_ACTIVE_ATTRIBUTE) then
			return
		end

		-- Spawn at first available level (Level 1)
		local levels = getAllLevels()
		local firstLevel = nil
		local lowestNumber = math.huge

		for levelId, levelObject in pairs(levels) do
			local metadata = getLevelMetadata(levelObject)
			if metadata and metadata.number < lowestNumber then
				lowestNumber = metadata.number
				firstLevel = levelId
			end
		end

		if firstLevel then
			spawnPlayerAtLevel(player, firstLevel)
		end
	end)
end)

-- Handle RemoteEvent for level selection
levelSelectRemote.OnServerEvent:Connect(function(player, levelId)
	spawnPlayerAtLevel(player, levelId)
end)

-- Cleanup on player leave
Players.PlayerRemoving:Connect(function(player)
	playerCurrentLevel[player] = nil
	playerLevelStartTime[player] = nil
	playerCheckpointTimes[player] = nil
	playerFinishCooldown[player] = nil
end)

-- Connect to CollectionService for dynamic finish detection
CollectionService:GetInstanceAddedSignal(FINISH_TAG):Connect(function(obj)
	-- Find which level this finish belongs to
	local ancestor = obj.Parent
	while ancestor and ancestor ~= workspace do
		if ancestor:GetAttribute("LevelId") or ancestor.Name:match("^Level_") then
			local levelId = ancestor:GetAttribute("LevelId") or ancestor.Name
			setupFinishDetection(ancestor, obj)
			break
		end
		ancestor = ancestor.Parent
	end
end)

-- Initialize on server start
task.wait(1) -- Wait for workspace to load
initializeLevels()

-- Export functions for other scripts
local LevelSystem = {}

function LevelSystem.getPlayerLevel(player)
	return playerCurrentLevel[player]
end

function LevelSystem.getAllLevels()
	return getAllLevels()
end

function LevelSystem.getLevelMetadata(levelId)
	local levels = getAllLevels()
	local levelObject = levels[levelId]
	if levelObject then
		return getLevelMetadata(levelObject)
	end
	return nil
end

function LevelSystem.isLevelUnlocked(player, levelId)
	local levels = getAllLevels()
	local levelObject = levels[levelId]
	if levelObject then
		local metadata = getLevelMetadata(levelObject)
		return isLevelUnlocked(player, metadata)
	end
	return false
end

function LevelSystem.spawnPlayerAtLevel(player, levelId)
	return spawnPlayerAtLevel(player, levelId)
end

-- Register with LevelSystemAPI so other scripts can access it
task.spawn(function()
	local LevelSystemAPI = require(ReplicatedStorage:WaitForChild("LevelSystemAPI", 10))
	if LevelSystemAPI then
		LevelSystemAPI.register(LevelSystem)
		print("[LevelSystem] Registered with LevelSystemAPI")
	end
end)

-- Also return for backward compatibility (if someone requires this as ModuleScript in the future)
return LevelSystem

