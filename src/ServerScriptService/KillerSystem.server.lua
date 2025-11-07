-- Handles parts/models with CollectionService "Killer" tag
-- When a player touches a Killer part/model:
--   - If it has a "Damage" attribute (number), applies that damage
--   - If no "Damage" attribute, instant kill

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

-- Apply damage or kill player
local function handleKillerTouch(player, killerObject)
	if not player or not player.Character then
		return
	end
	
	local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	
	-- Check for Damage attribute
	local damage = killerObject:GetAttribute("Damage")
	
	if damage ~= nil then
		-- Has Damage attribute - apply damage
		local damageValue = tonumber(damage)
		if damageValue and damageValue > 0 then
			-- Apply damage
			local currentHealth = humanoid.Health
			local newHealth = math.max(0, currentHealth - damageValue)
			humanoid.Health = newHealth
			
			-- Kill if health reaches 0
			if newHealth <= 0 then
				humanoid.Health = 0
			end
		else
			-- Invalid damage value, treat as instant kill
			humanoid.Health = 0
		end
	else
		-- No Damage attribute - instant kill
		humanoid.Health = 0
	end
end

-- Setup Killer behavior for a part/model
local function setupKiller(part)
	if not part then
		return
	end
	
	-- Skip if already wired
	if part:GetAttribute("_KillerWired") then
		return
	end
	
	part:SetAttribute("_KillerWired", true)
	
	-- Connect touch event
	local connection
	connection = part.Touched:Connect(function(hit)
		-- hit is the part from the player's character that touched this Killer part
		if not hit then
			return
		end
		
		-- Find the character that touched this part
		local character = hit.Parent
		if not character then
			return
		end
		
		-- Check if it's a player character
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end
		
		-- Find the player
		local player = Players:GetPlayerFromCharacter(character)
		if not player then
			return
		end
		
		-- We know 'part' is the Killer part (we set it up), so use it directly
		-- Verify it still has the tag (safety check)
		if not CollectionService:HasTag(part, "Killer") then
			return
		end
		
		-- Handle the killer touch
		handleKillerTouch(player, part)
	end)
	
	-- Cleanup connection when part is destroyed
	part.Destroying:Connect(function()
		if connection then
			connection:Disconnect()
		end
	end)
end

-- Setup Killer behavior for a model (handles all descendants)
local function setupKillerModel(model)
	if not model or not model:IsA("Model") then
		return
	end
	
	-- Skip if already wired
	if model:GetAttribute("_KillerWired") then
		return
	end
	
	model:SetAttribute("_KillerWired", true)
	
	-- Connect touch events to all BaseParts in the model
	local connections = {}
	
	local function connectPart(part)
		if not part:IsA("BasePart") then
			return
		end
		
		local connection
		connection = part.Touched:Connect(function(hit)
			-- hit is the part from the player's character that touched this part
			if not hit then
				return
			end
			
			-- Find the character that touched this part
			local character = hit.Parent
			if not character then
				return
			end
			
			-- Check if it's a player character
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if not humanoid then
				return
			end
			
			-- Find the player
			local player = Players:GetPlayerFromCharacter(character)
			if not player then
				return
			end
			
			-- We know 'model' is the Killer model (we set it up), so use it directly
			-- Verify it still has the tag (safety check)
			if not CollectionService:HasTag(model, "Killer") then
				return
			end
			
			-- Handle the killer touch
			handleKillerTouch(player, model)
		end)
		
		table.insert(connections, connection)
	end
	
	-- Connect existing parts
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			connectPart(descendant)
		end
	end
	
	-- Connect new parts added to the model
	local descendantAddedConnection
	descendantAddedConnection = model.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			connectPart(descendant)
		end
	end)
	
	-- Cleanup when model is destroyed
	model.Destroying:Connect(function()
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

-- Setup existing Killer parts/models
local function setupExistingKillers()
	local killerObjects = CollectionService:GetTagged("Killer")
	for _, obj in ipairs(killerObjects) do
		if obj:IsA("BasePart") then
			setupKiller(obj)
		elseif obj:IsA("Model") then
			setupKillerModel(obj)
		end
	end
end

-- Connect to CollectionService events for dynamic tag management
CollectionService:GetInstanceAddedSignal("Killer"):Connect(function(obj)
	if obj:IsA("BasePart") then
		setupKiller(obj)
	elseif obj:IsA("Model") then
		setupKillerModel(obj)
	end
end)

CollectionService:GetInstanceRemovedSignal("Killer"):Connect(function(obj)
	-- Clean up wiring attribute when tag is removed
	if obj:IsA("BasePart") or obj:IsA("Model") then
		obj:SetAttribute("_KillerWired", nil)
	end
end)

-- Initialize existing Killer objects
setupExistingKillers()

