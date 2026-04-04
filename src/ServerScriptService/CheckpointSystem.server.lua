-- Checkpoint System: Detects parts/models with "Checkpoint" tag
-- When a player touches any part inside a checkpoint, saves that checkpoint
-- Player respawns at their last touched checkpoint when pressing R or dying

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SharedUtils = require(ReplicatedStorage:WaitForChild("SharedUtils"))

-- Store checkpoint position for each player
local playerCheckpoints = {}

-- Touched (and related) connections per checkpoint root — disconnect on destroy or when tag is removed
local checkpointWiring = {} -- [Instance] = { RBXScriptConnection, ... }

local function disconnectCheckpointWiring(rootInstance)
	local list = checkpointWiring[rootInstance]
	if list then
		for _, conn in ipairs(list) do
			if conn and conn.Connected then
				conn:Disconnect()
			end
		end
		checkpointWiring[rootInstance] = nil
	end
	if rootInstance and rootInstance.Parent then
		rootInstance:SetAttribute("_CheckpointWired", nil)
	end
end

-- Get the checkpoint position from a checkpoint object (part or model)
local function getCheckpointPosition(checkpointObject)
	if checkpointObject:IsA("BasePart") then
		return checkpointObject.Position
	elseif checkpointObject:IsA("Model") then
		local primaryPart = checkpointObject.PrimaryPart
		if primaryPart then
			return primaryPart.Position
		end
		-- Fallback: use first BasePart
		for _, descendant in ipairs(checkpointObject:GetDescendants()) do
			if descendant:IsA("BasePart") then
				return descendant.Position
			end
		end
	end
	return nil
end

-- Find the checkpoint object that contains a touched part
local function findCheckpointFromPart(touchedPart)
	-- Check if the part itself has the tag
	if CollectionService:HasTag(touchedPart, "Checkpoint") then
		return touchedPart
	end
	
	-- Check parent models
	local current = touchedPart.Parent
	while current do
		if current:IsA("Model") and CollectionService:HasTag(current, "Checkpoint") then
			return current
		end
		current = current.Parent
	end
	
	return nil
end

-- Handle checkpoint touch
local function handleCheckpointTouch(player, touchedPart)
	if not player or not player.Character then
		return
	end
	
	-- Find the checkpoint object
	local checkpointObject = findCheckpointFromPart(touchedPart)
	if not checkpointObject then
		return
	end
	
	-- Get checkpoint position
	local checkpointPosition = getCheckpointPosition(checkpointObject)
	if not checkpointPosition then
		return
	end
	
	-- Save checkpoint for this player
	playerCheckpoints[player] = checkpointPosition
	
	print("Checkpoint saved for", player.Name, "at", checkpointPosition)
end

-- Setup checkpoint detection for a part
local function setupCheckpointPart(part)
	if not part or not part:IsA("BasePart") then
		return
	end
	
	-- Skip if already wired
	if part:GetAttribute("_CheckpointWired") then
		return
	end
	
	part:SetAttribute("_CheckpointWired", true)

	local list = {}
	checkpointWiring[part] = list

	list[#list + 1] = part.Touched:Connect(function(hit)
		local player = SharedUtils.getPlayerFromTouch(hit)
		if not player then
			return
		end

		local checkpointObject = findCheckpointFromPart(part)
		if not checkpointObject then
			return
		end

		handleCheckpointTouch(player, part)
	end)

	list[#list + 1] = part.Destroying:Connect(function()
		disconnectCheckpointWiring(part)
	end)
end

-- Setup checkpoint detection for a model (handles all descendants)
local function setupCheckpointModel(model)
	if not model or not model:IsA("Model") then
		return
	end
	
	-- Skip if already wired
	if model:GetAttribute("_CheckpointWired") then
		return
	end
	
	model:SetAttribute("_CheckpointWired", true)

	local list = {}
	checkpointWiring[model] = list

	local function connectPart(part)
		if not part:IsA("BasePart") then
			return
		end

		list[#list + 1] = part.Touched:Connect(function(hit)
			local player = SharedUtils.getPlayerFromTouch(hit)
			if not player then
				return
			end

			if not CollectionService:HasTag(model, "Checkpoint") then
				return
			end

			handleCheckpointTouch(player, part)
		end)
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			connectPart(descendant)
		end
	end

	list[#list + 1] = model.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			connectPart(descendant)
		end
	end)

	list[#list + 1] = model.Destroying:Connect(function()
		disconnectCheckpointWiring(model)
	end)
end

-- Respawn player at their checkpoint
local function respawnAtCheckpoint(player)
	if not player then
		return
	end
	
	local checkpointPosition = playerCheckpoints[player]
	if not checkpointPosition then
		return
	end
	
	-- If character doesn't exist yet, mark for respawn when it's created
	if not player.Character then
		player:SetAttribute("ShouldRespawnAtCheckpoint", true)
		return
	end
	
	local character = player.Character
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	
	if not humanoid or not rootPart then
		-- Character not ready, mark for respawn
		player:SetAttribute("ShouldRespawnAtCheckpoint", true)
		return
	end
	
	-- Teleport to checkpoint
	rootPart.CFrame = CFrame.new(checkpointPosition + Vector3.new(0, 5, 0))
	
	-- Reset velocity
	rootPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	
	print("Respawned", player.Name, "at checkpoint", checkpointPosition)
end

-- Setup existing checkpoints
local function setupExistingCheckpoints()
	local checkpointObjects = CollectionService:GetTagged("Checkpoint")
	for _, obj in ipairs(checkpointObjects) do
		if obj:IsA("BasePart") then
			setupCheckpointPart(obj)
		elseif obj:IsA("Model") then
			setupCheckpointModel(obj)
		end
	end
end

-- Connect to CollectionService events for dynamic tag management
CollectionService:GetInstanceAddedSignal("Checkpoint"):Connect(function(obj)
	if obj:IsA("BasePart") then
		setupCheckpointPart(obj)
	elseif obj:IsA("Model") then
		setupCheckpointModel(obj)
	end
end)

CollectionService:GetInstanceRemovedSignal("Checkpoint"):Connect(function(obj)
	if obj:IsA("BasePart") or obj:IsA("Model") then
		disconnectCheckpointWiring(obj)
	end
end)

-- Handle player death - respawn at checkpoint
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid then
			humanoid.Died:Connect(function()
				-- Mark that we should respawn at checkpoint when character respawns
				if playerCheckpoints[player] then
					player:SetAttribute("ShouldRespawnAtCheckpoint", true)
				end
			end)
		end
	end)
	
	-- Handle respawn on character added (after death or manual respawn)
	player.CharacterAdded:Connect(function(character)
		-- Small delay to ensure character is fully loaded
		task.wait(0.1)
		-- Only respawn if we have a checkpoint and this is a respawn (not initial spawn)
		if playerCheckpoints[player] and player:GetAttribute("ShouldRespawnAtCheckpoint") then
			player:SetAttribute("ShouldRespawnAtCheckpoint", false)
			respawnAtCheckpoint(player)
		end
	end)
end)

-- Handle R key press for respawn (via RemoteEvent)
local remoteFolder = ReplicatedStorage:FindFirstChild("Remotes")
if not remoteFolder then
	remoteFolder = Instance.new("Folder")
	remoteFolder.Name = "Remotes"
	remoteFolder.Parent = ReplicatedStorage
end

local respawnRemote = remoteFolder:FindFirstChild("RespawnAtCheckpoint")
if not respawnRemote then
	respawnRemote = Instance.new("RemoteEvent")
	respawnRemote.Name = "RespawnAtCheckpoint"
	respawnRemote.Parent = remoteFolder
end

respawnRemote.OnServerEvent:Connect(function(player)
	respawnAtCheckpoint(player)
end)

-- Cleanup when player leaves
Players.PlayerRemoving:Connect(function(player)
	playerCheckpoints[player] = nil
end)

-- Initialize existing checkpoints
setupExistingCheckpoints()

