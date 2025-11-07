-- Level Progress Tracker
-- Tracks each player's progress through a level (distance from spawn to finish)
-- Sends progress updates to clients for the progress bar UI

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

-- Access LevelSystem through LevelSystemAPI (works with Scripts, not just ModuleScripts)
local LevelSystemAPI = require(ReplicatedStorage:WaitForChild("LevelSystemAPI", 10))

-- Wrapper to access LevelSystem functions
local LevelSystem = {}
local function waitForAPI()
	local startTime = tick()
	while not LevelSystemAPI.isReady() and (tick() - startTime) < 10 do
		task.wait(0.1)
	end
	return LevelSystemAPI.isReady()
end

-- Wait for API to be ready
task.spawn(function()
	if waitForAPI() then
		print("[LevelProgressTracker] LevelSystemAPI is ready")
	else
		warn("[LevelProgressTracker] LevelSystemAPI not ready after 10 seconds")
	end
end)

-- Configuration
local UPDATE_INTERVAL = 0.1 -- Update every 0.1 seconds (10 times per second)
local SPAWN_TAG = "LevelSpawn"
local FINISH_TAG = "LevelFinish"

-- Store player progress data
local playerProgress = {} -- [player] = { levelId, spawnPos, finishPos, currentPos, progress (0-1) }

-- Create RemoteEvent for progress updates (create immediately)
local function ensureRemotesFolder()
	local remoteFolder = ReplicatedStorage:FindFirstChild("Remotes")
	if not remoteFolder then
		remoteFolder = Instance.new("Folder")
		remoteFolder.Name = "Remotes"
		remoteFolder.Parent = ReplicatedStorage
	end
	return remoteFolder
end

local remoteFolder = ensureRemotesFolder()

-- Create RemoteEvent immediately so clients can wait for it
local progressUpdateRemote = remoteFolder:FindFirstChild("LevelProgressUpdate")
if not progressUpdateRemote then
	progressUpdateRemote = Instance.new("RemoteEvent")
	progressUpdateRemote.Name = "LevelProgressUpdate"
	progressUpdateRemote.Parent = remoteFolder
	print("[LevelProgressTracker] Created LevelProgressUpdate RemoteEvent")
end

-- Recursively find an object by name in a hierarchy
local function findInHierarchy(parent, name)
	if not parent then
		return nil
	end
	
	-- Check all descendants recursively
	for _, descendant in ipairs(parent:GetDescendants()) do
		if descendant.Name == name then
			return descendant
		end
	end
	
	-- Also check direct children
	local directChild = parent:FindFirstChild(name)
	if directChild then
		return directChild
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

-- Find spawn and finish positions for a level (searches recursively)
local function getLevelPoints(levelObject)
	if not levelObject then
		return nil, nil
	end

	-- Find spawn (first check tags, then recursive search)
	local spawnPos = nil
	local spawns = CollectionService:GetTagged(SPAWN_TAG)
	for _, spawn in ipairs(spawns) do
		local ancestor = spawn
		while ancestor do
			if ancestor == levelObject then
				spawnPos = getObjectPosition(spawn)
				break
			end
			ancestor = ancestor.Parent
		end
		if spawnPos then
			break
		end
	end

	-- Fallback: recursively search for "LevelStart"
	if not spawnPos then
		local spawn = findInHierarchy(levelObject, "LevelStart")
		if spawn then
			spawnPos = getObjectPosition(spawn)
		end
	end

	-- Find finish (first check tags, then recursive search)
	local finishPos = nil
	local finishes = CollectionService:GetTagged(FINISH_TAG)
	for _, finish in ipairs(finishes) do
		local ancestor = finish
		while ancestor do
			if ancestor == levelObject then
				finishPos = getObjectPosition(finish)
				break
			end
			ancestor = ancestor.Parent
		end
		if finishPos then
			break
		end
	end

	-- Fallback: recursively search for "LevelFinish"
	if not finishPos then
		local finish = findInHierarchy(levelObject, "LevelFinish")
		if finish then
			finishPos = getObjectPosition(finish)
		end
	end

	return spawnPos, finishPos
end

-- Calculate progress (0 to 1) based on distance from spawn to finish
local function calculateProgress(playerPos, spawnPos, finishPos)
	if not spawnPos or not finishPos then
		return 0
	end

	-- Calculate total distance from spawn to finish
	local totalDistance = (finishPos - spawnPos).Magnitude
	if totalDistance == 0 then
		return 0
	end

	-- Calculate distance from spawn to player position
	-- Project player position onto the spawn-finish line
	local spawnToFinish = finishPos - spawnPos
	local spawnToPlayer = playerPos - spawnPos

	-- Dot product to find projection
	local projection = spawnToPlayer:Dot(spawnToFinish.Unit)

	-- Clamp between 0 and totalDistance
	projection = math.max(0, math.min(projection, totalDistance))

	-- Calculate progress (0 to 1)
	local progress = projection / totalDistance

	return progress
end

-- Initialize tracking for a player in a level
local function initializePlayerProgress(player, levelId)
	if not player or not levelId then
		return
	end

	-- Check if API is ready
	if not LevelSystemAPI.isReady() then
		warn("[LevelProgressTracker] LevelSystemAPI not ready yet, retrying...")
		-- Retry after a delay
		task.spawn(function()
			if waitForAPI() then
				initializePlayerProgress(player, levelId)
			end
		end)
		return
	end

	local success, levels = pcall(function()
		return LevelSystemAPI.getAllLevels()
	end)
	
	if not success then
		warn("[LevelProgressTracker] Failed to get levels:", levels)
		return
	end
	
	local levelObject = levels[levelId]
	if not levelObject then
		warn(string.format("[LevelProgressTracker] Level not found: %s", levelId))
		return
	end

	local spawnPos, finishPos = getLevelPoints(levelObject)
	if not spawnPos or not finishPos then
		warn(string.format("[LevelProgressTracker] Could not find spawn or finish for level: %s (spawn: %s, finish: %s)", 
			levelId, 
			tostring(spawnPos ~= nil), 
			tostring(finishPos ~= nil)))
		return
	end

	playerProgress[player] = {
		levelId = levelId,
		spawnPos = spawnPos,
		finishPos = finishPos,
		currentPos = spawnPos,
		progress = 0,
	}

	print(string.format("[LevelProgressTracker] Started tracking player %s in level %s", player.Name, levelId))
end

-- Stop tracking for a player
local function stopTrackingPlayer(player)
	playerProgress[player] = nil
end

-- Update all players' progress
local function updateProgress()
	-- Check if API is ready
	if not LevelSystemAPI.isReady() then
		return -- API not ready yet
	end

	local allProgress = {}

	for player, data in pairs(playerProgress) do
		if not player or not player.Character then
			stopTrackingPlayer(player)
			continue
		end

		local rootPart = player.Character:FindFirstChild("HumanoidRootPart")
		if not rootPart then
			continue
		end

		-- Verify player is still in this level
		local success, currentLevel = pcall(function()
			return LevelSystemAPI.getPlayerLevel(player)
		end)
		
		if not success or currentLevel ~= data.levelId then
			if not success then
				-- API error, skip this update
			else
				stopTrackingPlayer(player)
			end
			continue
		end

		-- Update current position and progress
		data.currentPos = rootPart.Position
		data.progress = calculateProgress(data.currentPos, data.spawnPos, data.finishPos)

		-- Clamp progress between 0 and 1
		data.progress = math.max(0, math.min(1, data.progress))

		-- Store progress data for this player
		allProgress[player.UserId] = {
			userId = player.UserId,
			username = player.Name,
			progress = data.progress,
			levelId = data.levelId,
		}
	end

	-- Send updates to all players
	if next(allProgress) then
		-- Get all players in the same level and send their progress
		local levelGroups = {}
		for userId, progressData in pairs(allProgress) do
			local levelId = progressData.levelId
			if not levelGroups[levelId] then
				levelGroups[levelId] = {}
			end
			table.insert(levelGroups[levelId], progressData)
		end

		-- Send updates to each player showing all players in their level
		for trackedPlayer, data in pairs(playerProgress) do
			if trackedPlayer and trackedPlayer.Parent then
				local levelGroup = levelGroups[data.levelId] or {}
				if #levelGroup > 0 then
					progressUpdateRemote:FireClient(trackedPlayer, levelGroup)
				end
			end
		end
	else
		-- No progress data, but still send empty to hide UI if needed
		-- (This prevents UI from staying visible after level completion)
	end
end

-- Listen for player level changes
local function onPlayerLevelChanged(player, levelId)
	if levelId then
		initializePlayerProgress(player, levelId)
	else
		stopTrackingPlayer(player)
		-- Send empty progress to hide UI
		progressUpdateRemote:FireClient(player, {})
	end
end

-- Monitor LevelSystem for level changes
-- We'll need to hook into LevelSystem to detect when players change levels
local function monitorPlayerLevels()
	-- Check if API is ready
	if not LevelSystemAPI.isReady() then
		return -- API not ready yet
	end

	-- Check all players periodically
	for _, player in ipairs(Players:GetPlayers()) do
		local success, currentLevel = pcall(function()
			return LevelSystemAPI.getPlayerLevel(player)
		end)
		
		if success and currentLevel then
			local trackedLevel = playerProgress[player] and playerProgress[player].levelId

			if currentLevel ~= trackedLevel then
				onPlayerLevelChanged(player, currentLevel)
			end
		end
	end
end

-- Player cleanup
Players.PlayerRemoving:Connect(function(player)
	stopTrackingPlayer(player)
end)

-- Update loop
task.spawn(function()
	while true do
		task.wait(UPDATE_INTERVAL)
		monitorPlayerLevels()
		updateProgress()
	end
end)

-- Export functions
local LevelProgressTracker = {}

function LevelProgressTracker.getPlayerProgress(player)
	return playerProgress[player]
end

function LevelProgressTracker.initializePlayerProgress(player, levelId)
	initializePlayerProgress(player, levelId)
end

function LevelProgressTracker.stopTrackingPlayer(player)
	stopTrackingPlayer(player)
end

-- Wait for API before starting the update loop
task.spawn(function()
	if waitForAPI() then
		print("[LevelProgressTracker] Ready to track player progress")
	else
		warn("[LevelProgressTracker] LevelSystemAPI never became ready")
	end
end)

return LevelProgressTracker

