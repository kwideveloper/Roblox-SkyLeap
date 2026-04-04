-- SharedUtils: Common utility functions used across multiple modules
-- Reduces code duplication and improves maintainability

local SharedUtils = {}

-- Commonly used services
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

-- Cached tags to reduce repeated CollectionService calls
local tagCache = {}
local tagCacheExpiry = {}
local TAG_CACHE_DURATION = 1 -- seconds

-- Helper function to get attribute value with fallback to default
-- Used in: Powerups.lua, Powerups.server.lua, BreakablePlatforms.server.lua, LaunchPads.server.lua
function SharedUtils.getAttributeOrDefault(part, attributeName, defaultValue)
	if not part then
		return defaultValue
	end
	local value = part:GetAttribute(attributeName)
	if value == nil then
		return defaultValue
	end
	return value
end

-- Cached version of CollectionService:GetTagged to reduce performance overhead
function SharedUtils.getTaggedCached(tag)
	local now = os.clock()

	-- Check if cache is valid
	if tagCache[tag] and tagCacheExpiry[tag] and now < tagCacheExpiry[tag] then
		return tagCache[tag]
	end

	-- Update cache
	tagCache[tag] = CollectionService:GetTagged(tag)
	tagCacheExpiry[tag] = now + TAG_CACHE_DURATION

	return tagCache[tag]
end

-- Clear specific tag from cache (useful when tags are modified)
function SharedUtils.clearTagCache(tag)
	if tag then
		tagCache[tag] = nil
		tagCacheExpiry[tag] = nil
	else
		-- Clear all cache
		tagCache = {}
		tagCacheExpiry = {}
	end
end

-- Optimized tag checking with early exit
-- Returns the first valid tag found from a list of valid tags
function SharedUtils.getFirstValidTag(part, validTags)
	if not part then
		return nil
	end

	local tags = CollectionService:GetTags(part)
	for _, tag in ipairs(tags) do
		for _, validTag in ipairs(validTags) do
			if tag == validTag then
				return tag
			end
		end
	end
	return nil
end

-- Resolve the Player from a .Touched hit (handles accessories / nested instances)
function SharedUtils.getPlayerFromTouch(hit)
	if not hit then
		return nil
	end
	local inst = hit
	while inst do
		if inst:IsA("Model") then
			local humanoid = inst:FindFirstChildOfClass("Humanoid")
			if humanoid then
				return Players:GetPlayerFromCharacter(inst)
			end
		end
		inst = inst.Parent
	end
	return nil
end

-- Distance check optimization for touch validation
function SharedUtils.isWithinDistance(pos1, pos2, maxDistance)
	local dx = pos1.X - pos2.X
	local dy = pos1.Y - pos2.Y
	local dz = pos1.Z - pos2.Z
	local distanceSquared = dx * dx + dy * dy + dz * dz
	return distanceSquared <= (maxDistance * maxDistance)
end

-- Cooldown management utility
local cooldowns = {}

function SharedUtils.isOnCooldown(key, cooldownTime)
	local lastUsed = cooldowns[key]
	if not lastUsed then
		return false
	end
	local timeSinceUsed = os.clock() - lastUsed
	return timeSinceUsed < cooldownTime
end

function SharedUtils.setCooldown(key)
	cooldowns[key] = os.clock()
end

function SharedUtils.getRemainingCooldown(key, cooldownTime)
	local lastUsed = cooldowns[key]
	if not lastUsed then
		return 0
	end
	local elapsed = os.clock() - lastUsed
	return math.max(0, cooldownTime - elapsed)
end

-- Text formatting utilities (moved from Currency/Config.lua for reusability)
function SharedUtils.formatNumberWithAbbreviation(amount)
	amount = tonumber(amount) or 0

	if amount >= 1000000000 then
		local truncated = math.floor(amount / 1000000000 * 10) / 10
		return string.format("%.1fB", truncated):gsub("%.0", "")
	elseif amount >= 1000000 then
		local truncated = math.floor(amount / 1000000 * 10) / 10
		return string.format("%.1fM", truncated):gsub("%.0", "")
	elseif amount >= 1000 then
		local truncated = math.floor(amount / 1000 * 10) / 10
		return string.format("%.1fK", truncated):gsub("%.0", "")
	else
		return tostring(amount)
	end
end

-- Remote event batching utility for performance
local remoteBatches = {}
local batchTimers = {}

function SharedUtils.batchRemoteCall(remote, player, data, batchTime)
	batchTime = batchTime or 0.1 -- Default 100ms batching

	if not remoteBatches[remote] then
		remoteBatches[remote] = {}
	end

	if not remoteBatches[remote][player] then
		remoteBatches[remote][player] = {}
	end

	table.insert(remoteBatches[remote][player], data)

	-- Set timer to flush batch
	local key = tostring(remote) .. tostring(player)
	if batchTimers[key] then
		batchTimers[key]:Disconnect()
	end

	batchTimers[key] = task.delay(batchTime, function()
		if remoteBatches[remote] and remoteBatches[remote][player] then
			local batch = remoteBatches[remote][player]
			remoteBatches[remote][player] = nil
			batchTimers[key] = nil

			-- Send batched data
			remote:FireClient(player, batch)
		end
	end)
end

-- Debug utilities
function SharedUtils.debugPrint(module, message, level)
	level = level or "INFO"
	print(string.format("[%s] [%s] %s", module, level, message))
end

-- Get all player characters in the workspace
function getAllPlayerCharacters()
	local characters = {}
	local players = game:GetService("Players"):GetPlayers()
	for _, player in ipairs(players) do
		if player.Character then
			table.insert(characters, player.Character)
		end
	end
	return characters
end

-- Create RaycastParams that excludes all players (for parkour systems)
function SharedUtils.createParkourRaycastParams(character, additionalExclusions)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true

	-- Get all player characters to exclude
	local playerCharacters = getAllPlayerCharacters()

	-- Combine player characters with character and any additional exclusions
	local exclusions = {}
	if character then
		table.insert(exclusions, character)
	end
	for _, char in ipairs(playerCharacters) do
		table.insert(exclusions, char)
	end

	if additionalExclusions then
		for _, exclusion in ipairs(additionalExclusions) do
			table.insert(exclusions, exclusion)
		end
	end

	params.FilterDescendantsInstances = exclusions
	return params
end

-- Perform a raycast for parkour systems that ignores all players
function SharedUtils.raycastForParkour(character, origin, direction, additionalExclusions)
	local params = SharedUtils.createParkourRaycastParams(character, additionalExclusions)
	return workspace:Raycast(origin, direction, params)
end

-- Check if a part is breakable based on CollectionService "Breakable" tag
function SharedUtils.isBreakable(part)
	if not part then
		return false
	end
	return CollectionService:HasTag(part, "Breakable")
end

-- Cleanup function for memory management
function SharedUtils.cleanup()
	tagCache = {}
	tagCacheExpiry = {}
	cooldowns = {}
	remoteBatches = {}
	for _, timer in pairs(batchTimers) do
		if timer then
			timer:Disconnect()
		end
	end
	batchTimers = {}
end

return SharedUtils
