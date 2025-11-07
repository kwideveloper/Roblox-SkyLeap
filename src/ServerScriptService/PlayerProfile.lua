-- Centralized player profile management using a single DataStore schema

local DataStoreService = game:GetService("DataStoreService")

local PROFILE_STORE_NAME = "SkyLeap_Profiles_v1"
local store = DataStoreService:GetDataStore(PROFILE_STORE_NAME)

local PlayerProfile = {}

local ACTIVE = {}
local PENDING_CHANGES = {} -- Buffer changes before saving
local LAST_SAVE = {} -- Track last save time per user
local SAVE_INTERVAL = 30 -- Save every 30 seconds maximum
local CRITICAL_SAVE_THRESHOLD = 5000 -- Auto-save if coins/diamonds change by this much
local LOADING = {} -- Track profiles currently being loaded to prevent duplicate requests
local SAVE_QUEUE = {} -- Queue for DataStore operations to prevent overload
local MAX_CONCURRENT_SAVES = 1 -- Maximum concurrent DataStore operations (reduced to prevent overload)

local function defaultProfile()
	return {
		version = 1,
		stats = {
			level = 1,
			xp = 0,
			styleTotal = 0,
			maxCombo = 0,
			timePlayedMinutes = 0,
			coins = 0,
			diamonds = 0,
		},
		progression = {
			unlockedAbilities = {},
			completedLevels = {}, -- [levelNumber] = true
			levelTimes = {}, -- [levelNumber] = bestTime (seconds)
		},
		cosmetics = {
			owned = {},
			equipped = {
				outfitId = nil,
				trailId = nil,
				handTrailId = nil,
			},
		},
		purchases = {
			developerProducts = {},
			gamePasses = {},
		},
		rewards = {
			playtimeClaimed = {}, -- [index]=true for claimed rewards
			lastPlaytimeDay = nil, -- YYYYMMDD string for daily reset
			playtimeAccumulatedSeconds = 0, -- accumulated play seconds for the day
		},
		settings = {
			cameraFov = nil,
			uiScale = nil,
		},
		meta = {
			createdAt = os.time(),
			updatedAt = os.time(),
		},
	}
end

local function migrate(profile)
	if type(profile) ~= "table" then
		return defaultProfile()
	end
	-- Example migration hook; bump as schema evolves
	profile.version = profile.version or 1
	profile.stats = profile.stats or {}
	profile.stats.level = profile.stats.level or 1
	profile.stats.xp = profile.stats.xp or 0
	profile.stats.styleTotal = profile.stats.styleTotal or 0
	profile.stats.maxCombo = profile.stats.maxCombo or 0
	profile.stats.timePlayedMinutes = profile.stats.timePlayedMinutes or 0
	profile.stats.coins = profile.stats.coins or 0
	profile.stats.diamonds = profile.stats.diamonds or 0
	profile.progression = profile.progression or { unlockedAbilities = {}, completedLevels = {}, levelTimes = {} }
	profile.progression.completedLevels = profile.progression.completedLevels or {}
	profile.progression.levelTimes = profile.progression.levelTimes or {}
	profile.cosmetics = profile.cosmetics
		or { owned = {}, equipped = { outfitId = nil, trailId = nil, handTrailId = nil } }
	profile.purchases = profile.purchases or { developerProducts = {}, gamePasses = {} }
	profile.settings = profile.settings or { cameraFov = nil, uiScale = nil }
	profile.rewards = profile.rewards or { playtimeClaimed = {}, lastPlaytimeDay = nil, playtimeAccumulatedSeconds = 0 }
	profile.rewards.playtimeClaimed = profile.rewards.playtimeClaimed or {}
	profile.rewards.lastPlaytimeDay = profile.rewards.lastPlaytimeDay or nil
	profile.rewards.playtimeAccumulatedSeconds = tonumber(profile.rewards.playtimeAccumulatedSeconds) or 0
	profile.meta = profile.meta or { createdAt = os.time(), updatedAt = os.time() }
	return profile
end

local function keyFor(userId)
	return "u:" .. tostring(userId)
end

-- OPTIMIZED: Queue system to prevent DataStore overload
local activeSaveCount = 0
local function processSaveQueue()
	while #SAVE_QUEUE > 0 and activeSaveCount < MAX_CONCURRENT_SAVES do
		local saveRequest = table.remove(SAVE_QUEUE, 1)
		activeSaveCount = activeSaveCount + 1

		task.spawn(function()
			local success = saveRequest.callback()
			activeSaveCount = activeSaveCount - 1

			if not success and saveRequest.retries < 3 then
				saveRequest.retries = saveRequest.retries + 1
				table.insert(SAVE_QUEUE, saveRequest)
				task.wait(2 ^ saveRequest.retries) -- Exponential backoff
			end
		end)
	end
end

local function queueSaveOperation(userId, callback)
	table.insert(SAVE_QUEUE, {
		userId = userId,
		callback = callback,
		retries = 0,
		timestamp = os.time(),
	})
	processSaveQueue()
	return true -- Return true to indicate operation was queued
end

-- OPTIMIZED: Use GetAsync for reads, prevent duplicate loads, only UpdateAsync when migration needed
function PlayerProfile.load(userId)
	userId = tostring(userId)

	-- Return immediately if already loaded
	if ACTIVE[userId] then
		return ACTIVE[userId]
	end

	-- If already loading, wait for it to complete (prevents duplicate requests)
	if LOADING[userId] then
		local attempts = 0
		while LOADING[userId] and attempts < 50 do -- Max 5 second wait
			task.wait(0.1)
			attempts = attempts + 1
		end
		-- Return the loaded profile or fallback
		return ACTIVE[userId] or defaultProfile()
	end

	-- Mark as loading to prevent duplicate requests
	LOADING[userId] = true

	local loaded
	local needsMigration = false

	-- STEP 1: Try to load with GetAsync (read-only, no DataStore write request)
	local ok, data = pcall(function()
		return store:GetAsync(keyFor(userId))
	end)

	if ok and data then
		-- Check if migration is needed
		local migrated = migrate(data)
		if migrated.version ~= data.version or not data.meta or not data.meta.updatedAt then
			needsMigration = true
			loaded = migrated
		else
			loaded = data
		end
	else
		-- No data found or error, use defaults and mark for save
		loaded = defaultProfile()
		needsMigration = true
	end

	-- STEP 2: Only use UpdateAsync if migration is actually needed
	if needsMigration then
		local ok2, err = pcall(function()
			loaded = store:UpdateAsync(keyFor(userId), function(old)
				local migrated = migrate(old or defaultProfile())
				migrated.meta.updatedAt = os.time()
				return migrated
			end)
		end)
		if not ok2 then
			-- Fallback to in-memory profile
			loaded = loaded or defaultProfile()
			warn(string.format("[PlayerProfile] Migration failed for user %s: %s", userId, err))
		end
	end

	ACTIVE[userId] = loaded
	LAST_SAVE[userId] = os.time() -- Mark as "recently saved" to prevent immediate save
	LOADING[userId] = nil -- Clear loading flag

	return loaded
end

-- OPTIMIZED: Batched save system with queue to reduce DataStore requests
local function forceSave(userId)
	userId = tostring(userId) -- Ensure userId is string
	local data = ACTIVE[userId]
	if not data then
		warn(string.format("[PlayerProfile] forceSave failed: No active data for user %s", userId))
		return false
	end

	-- ANTI-DUPLICATE: Prevent multiple saves within 5 seconds (throttle rapid saves)
	local lastSave = LAST_SAVE[userId] or 0
	local timeSinceLastSave = os.time() - lastSave
	if timeSinceLastSave < 5 then
		return true -- Return success since data is already recent
	end

	data.meta.updatedAt = os.time()

	return queueSaveOperation(userId, function()
		local success = false
		local err = nil
		local ok, errorMsg = pcall(function()
			store:SetAsync(keyFor(userId), data)
			LAST_SAVE[userId] = os.time()
			PENDING_CHANGES[userId] = nil -- Clear pending changes after successful save
			success = true
		end)

		if not ok then
			err = errorMsg
		end

		if not success then
			warn(string.format("[PlayerProfile] forceSave FAILED for user %s: %s", userId, tostring(err)))
		end

		return success
	end)
end

-- OPTIMIZED: Checks if user needs saving based on time or critical changes
local function shouldSave(userId)
	local lastSave = LAST_SAVE[userId] or 0
	local timeSinceLastSave = os.time() - lastSave

	-- Save if interval exceeded
	if timeSinceLastSave >= SAVE_INTERVAL then
		return true, "time_interval"
	end

	-- Save if critical changes pending
	local pending = PENDING_CHANGES[userId]
	if pending then
		local coinChange = math.abs((pending.coins or 0))
		local diamondChange = math.abs((pending.diamonds or 0))
		if coinChange >= CRITICAL_SAVE_THRESHOLD or diamondChange >= CRITICAL_SAVE_THRESHOLD then
			return true, "critical_changes"
		end
	end

	return false, "no_need"
end

-- OPTIMIZED: Batch changes in memory, save periodically
local function applyChanges(userId, changes)
	local profile = ACTIVE[userId]
	if not profile then
		return false
	end

	-- Apply changes to in-memory profile
	if changes.timePlayedMinutes then
		profile.stats.timePlayedMinutes = (profile.stats.timePlayedMinutes or 0) + changes.timePlayedMinutes
	end
	if changes.coins then
		profile.stats.coins = math.max(0, (profile.stats.coins or 0) + changes.coins)
	end
	if changes.diamonds then
		profile.stats.diamonds = math.max(0, (profile.stats.diamonds or 0) + changes.diamonds)
	end
	if changes.styleTotal then
		profile.stats.styleTotal = (profile.stats.styleTotal or 0) + changes.styleTotal
	end
	if changes.maxCombo then
		profile.stats.maxCombo = math.max(profile.stats.maxCombo or 0, changes.maxCombo)
	end
	if changes.playtimeClaimed then
		profile.rewards = profile.rewards or { playtimeClaimed = {} }
		for index, value in pairs(changes.playtimeClaimed) do
			profile.rewards.playtimeClaimed[index] = value
		end
	end

	-- Track pending changes for batching
	PENDING_CHANGES[userId] = PENDING_CHANGES[userId] or {}
	local pending = PENDING_CHANGES[userId]
	pending.coins = (pending.coins or 0) + (changes.coins or 0)
	pending.diamonds = (pending.diamonds or 0) + (changes.diamonds or 0)

	-- Check if we should save now
	local shouldSaveNow, reason = shouldSave(userId)
	if shouldSaveNow then
		return forceSave(userId)
	end

	return true
end

function PlayerProfile.save(userId)
	return forceSave(userId)
end

-- OPTIMIZED: Coordinated save on player leave - consolidates all final changes
function PlayerProfile.release(userId)
	userId = tostring(userId)

	-- Check if profile exists
	if not ACTIVE[userId] then
		return false
	end

	-- Force save any pending changes before cleanup
	local success = forceSave(userId)

	-- Clean up all memory
	ACTIVE[userId] = nil
	LOADING[userId] = nil
	PENDING_CHANGES[userId] = nil
	LAST_SAVE[userId] = nil

	return success
end

-- OPTIMIZED: Use batching system instead of individual UpdateAsync
function PlayerProfile.addTimePlayed(userId, minutes, onLeave)
	userId = tostring(userId)
	minutes = tonumber(minutes) or 0
	if minutes <= 0 then
		return 0
	end

	local profile = PlayerProfile.load(userId) -- Ensure profile is loaded

	if onLeave then
		-- When called on player leave, just update in memory - don't save
		profile.stats.timePlayedMinutes = (profile.stats.timePlayedMinutes or 0) + minutes
	else
		-- Normal operation - use batching
		applyChanges(userId, { timePlayedMinutes = minutes })
	end

	return profile.stats.timePlayedMinutes or 0
end

-- OPTIMIZED: Use batching system
function PlayerProfile.setMaxComboIfHigher(userId, value, onLeave)
	userId = tostring(userId)
	value = tonumber(value) or 0
	if value <= 0 then
		return 0
	end

	local profile = PlayerProfile.load(userId)
	local currentMax = profile.stats.maxCombo or 0

	if value > currentMax then
		if onLeave then
			-- When called on player leave, just update in memory - don't save
			profile.stats.maxCombo = value
		else
			-- Normal operation - use batching
			applyChanges(userId, { maxCombo = value })
		end
		return value
	end

	return currentMax
end

-- OPTIMIZED: Use batching system
function PlayerProfile.addStyleTotal(userId, amount)
	amount = tonumber(amount) or 0
	if amount <= 0 then
		return 0
	end

	local profile = PlayerProfile.load(userId)
	applyChanges(userId, { styleTotal = amount })

	return profile.stats.styleTotal or 0
end

-- Currency helpers
function PlayerProfile.getBalances(userId)
	local prof = PlayerProfile.load(userId)
	local coins = tonumber((prof.stats and prof.stats.coins) or 0) or 0
	local diamonds = tonumber((prof.stats and prof.stats.diamonds) or 0) or 0
	return coins, diamonds
end

-- OPTIMIZED: Force save for significant coin additions, batch small ones
function PlayerProfile.addCoins(userId, amount)
	userId = tostring(userId)
	amount = math.floor(tonumber(amount) or 0)
	if amount == 0 then
		return PlayerProfile.getBalances(userId)
	end

	local profile = PlayerProfile.load(userId)

	-- CRITICAL: Force immediate save for significant amounts (rewards, purchases)
	-- This prevents data loss and double-claiming
	if amount >= 100 then -- Any reward amount or significant gain
		-- Apply change directly to profile and force save
		profile.stats.coins = math.max(0, (profile.stats.coins or 0) + amount)
		local success = forceSave(userId)
	else
		-- Small amounts can use batching
		applyChanges(userId, { coins = amount })
	end

	return PlayerProfile.getBalances(userId)
end

-- OPTIMIZED: Force save for significant diamond additions, batch small ones
function PlayerProfile.addDiamonds(userId, amount)
	userId = tostring(userId)
	amount = math.floor(tonumber(amount) or 0)
	if amount == 0 then
		return PlayerProfile.getBalances(userId)
	end

	local profile = PlayerProfile.load(userId)

	-- CRITICAL: Force immediate save for any diamond additions (diamonds are precious)
	-- Apply change directly to profile and force save
	profile.stats.diamonds = math.max(0, (profile.stats.diamonds or 0) + amount)
	local success = forceSave(userId)

	return PlayerProfile.getBalances(userId)
end

-- OPTIMIZED: Atomic spending with immediate save to prevent double-spending
function PlayerProfile.trySpend(userId, currency, amount)
	currency = tostring(currency)
	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 then
		return false, PlayerProfile.getBalances(userId)
	end

	local profile = PlayerProfile.load(userId)
	local field = (currency == "Coins") and "coins" or (currency == "Diamonds") and "diamonds" or nil
	if not field then
		return false, PlayerProfile.getBalances(userId)
	end

	local current = math.floor(profile.stats[field] or 0)
	if current >= amount then
		-- Apply spending directly to profile (subtract amount)
		profile.stats[field] = math.max(0, current - amount)

		-- Clear any pending changes for this currency to prevent conflicts
		if PENDING_CHANGES[userId] then
			PENDING_CHANGES[userId][field] = nil
		end

		-- Force immediate save for spending operations (critical for preventing double-spending)
		local success = forceSave(userId)
		if not success then
			-- Refund if save failed
			profile.stats[field] = current
			return false, PlayerProfile.getBalances(userId)
		end

		return true, PlayerProfile.getBalances(userId)
	end

	return false, PlayerProfile.getBalances(userId)
end

-- Rewards helpers
function PlayerProfile.isPlaytimeClaimed(userId, index)
	index = tonumber(index)
	if not index then
		return false
	end
	local prof = PlayerProfile.load(userId)
	local t = (prof.rewards and prof.rewards.playtimeClaimed) or {}
	return t[index] == true
end

-- CRITICAL: Force immediate save for playtime claims to prevent double-claims
function PlayerProfile.markPlaytimeClaimed(userId, index)
	userId = tostring(userId)
	index = tonumber(index)
	if not index then
		return false
	end

	local profile = PlayerProfile.load(userId)

	-- Apply change directly to profile
	profile.rewards = profile.rewards or { playtimeClaimed = {} }
	profile.rewards.playtimeClaimed[index] = true

	-- FORCE IMMEDIATE SAVE - this is critical for preventing double claims
	local success = forceSave(userId)
	print(
		string.format(
			"[PlayerProfile] CRITICAL: Marked playtime claim %d for user %s, save success: %s",
			index,
			userId,
			tostring(success)
		)
	)

	return success
end

-- OPTIMIZATION: Periodic auto-save system with queue management
task.spawn(function()
	while true do
		task.wait(SAVE_INTERVAL)

		-- Process pending saves
		for userId, _ in pairs(ACTIVE) do
			local shouldSaveNow, reason = shouldSave(userId)
			if shouldSaveNow then
				forceSave(userId)
			end
		end

		-- Clean up old queue entries (older than 5 minutes)
		local currentTime = os.time()
		local cleanedQueue = {}
		for _, request in ipairs(SAVE_QUEUE) do
			if currentTime - request.timestamp < 300 then -- 5 minutes
				table.insert(cleanedQueue, request)
			end
		end
		SAVE_QUEUE = cleanedQueue

		-- Process queue if not at capacity
		processSaveQueue()
	end
end)

-- REMOVED: PlayerRemoving cleanup - PlayerData.server.lua handles all cleanup via release()
-- This prevents any race conditions or duplicate cleanup operations

-- DEBUG: Add monitoring function for DataStore queue status
function PlayerProfile.getQueueStatus()
	return {
		queueSize = #SAVE_QUEUE,
		activeSaves = activeSaveCount,
		maxConcurrent = MAX_CONCURRENT_SAVES,
		activeProfiles = #ACTIVE,
	}
end

-- DEBUG: Function to force process queue (for debugging purposes)
function PlayerProfile.processQueue()
	processSaveQueue()
end

-- DEBUG: Periodic monitoring of DataStore queue health
task.spawn(function()
	while true do
		task.wait(60) -- Check every minute

		local status = PlayerProfile.getQueueStatus()
		if status.queueSize > 10 then
			warn(
				string.format(
					"[PlayerProfile] WARNING: Large DataStore queue detected. Queue: %d, Active: %d/%d, Profiles: %d",
					status.queueSize,
					status.activeSaves,
					status.maxConcurrent,
					status.activeProfiles
				)
			)
		end

		-- Force process queue if it's getting too large
		if status.queueSize > 20 then
			warn("[PlayerProfile] Queue overload detected, forcing processing...")
			processSaveQueue()
		end
	end
end)

-- Trail management functions
function PlayerProfile.ownsTrail(userId, trailId)
	userId = tostring(userId)
	trailId = tostring(trailId)
	local profile = PlayerProfile.load(userId)
	local owned = profile.cosmetics and profile.cosmetics.owned or {}
	return owned[trailId] == true
end

function PlayerProfile.purchaseTrail(userId, trailId)
	userId = tostring(userId)
	trailId = tostring(trailId)

	local profile = PlayerProfile.load(userId)
	profile.cosmetics = profile.cosmetics
		or { owned = {}, equipped = { outfitId = nil, trailId = nil, handTrailId = nil } }
	profile.cosmetics.owned = profile.cosmetics.owned or {}

	-- Mark trail as owned
	profile.cosmetics.owned[trailId] = true

	-- Force save for purchase
	local success = forceSave(userId)
	return success
end

function PlayerProfile.equipTrail(userId, trailId)
	userId = tostring(userId)
	trailId = tostring(trailId)

	-- Verify ownership first
	if not PlayerProfile.ownsTrail(userId, trailId) then
		return false, "Trail not owned"
	end

	local profile = PlayerProfile.load(userId)
	profile.cosmetics = profile.cosmetics
		or { owned = {}, equipped = { outfitId = nil, trailId = nil, handTrailId = nil } }
	profile.cosmetics.equipped = profile.cosmetics.equipped or { outfitId = nil, trailId = nil }

	-- Check if already equipped (avoid unnecessary save)
	if profile.cosmetics.equipped.trailId == trailId then
		return true, "Trail already equipped"
	end

	-- Equip the trail
	profile.cosmetics.equipped.trailId = trailId

	-- Force save for equipment change
	local success = forceSave(userId)
	return success, "Trail equipped"
end

function PlayerProfile.getEquippedTrail(userId)
	userId = tostring(userId)
	local profile = PlayerProfile.load(userId)
	local equipped = profile.cosmetics and profile.cosmetics.equipped or {}
	return equipped.trailId or "default"
end

function PlayerProfile.getOwnedTrails(userId)
	userId = tostring(userId)
	local profile = PlayerProfile.load(userId)
	local owned = profile.cosmetics and profile.cosmetics.owned or {}
	local ownedList = {}

	for trailId, isOwned in pairs(owned) do
		if isOwned then
			table.insert(ownedList, trailId)
		end
	end

	-- Always include default trail
	if not owned["default"] then
		table.insert(ownedList, "default")
	end

	return ownedList
end

-- Hand trail management functions
function PlayerProfile.ownsHandTrail(userId, trailId)
	userId = tostring(userId)
	trailId = tostring(trailId)
	local profile = PlayerProfile.load(userId)
	local owned = profile.cosmetics and profile.cosmetics.owned or {}
	return owned["hand_" .. trailId] == true
end

function PlayerProfile.purchaseHandTrail(userId, trailId)
	userId = tostring(userId)
	trailId = tostring(trailId)

	local profile = PlayerProfile.load(userId)
	profile.cosmetics = profile.cosmetics
		or { owned = {}, equipped = { outfitId = nil, trailId = nil, handTrailId = nil } }
	profile.cosmetics.owned = profile.cosmetics.owned or {}

	-- Mark hand trail as owned with "hand_" prefix
	profile.cosmetics.owned["hand_" .. trailId] = true

	-- Force save for purchase
	local success = forceSave(userId)
	return success
end

function PlayerProfile.equipHandTrail(userId, trailId)
	userId = tostring(userId)
	trailId = tostring(trailId)

	-- Verify ownership first
	if not PlayerProfile.ownsHandTrail(userId, trailId) then
		return false, "Hand trail not owned"
	end

	local profile = PlayerProfile.load(userId)
	profile.cosmetics = profile.cosmetics
		or { owned = {}, equipped = { outfitId = nil, trailId = nil, handTrailId = nil } }
	profile.cosmetics.equipped = profile.cosmetics.equipped or { outfitId = nil, trailId = nil, handTrailId = nil }

	-- Check if already equipped (avoid unnecessary save)
	if profile.cosmetics.equipped.handTrailId == trailId then
		return true, "Hand trail already equipped"
	end

	-- Equip the hand trail
	profile.cosmetics.equipped.handTrailId = trailId

	-- Force save for equipment change
	local success = forceSave(userId)
	return success, "Hand trail equipped"
end

function PlayerProfile.getEquippedHandTrail(userId)
	userId = tostring(userId)
	local profile = PlayerProfile.load(userId)
	local equipped = profile.cosmetics and profile.cosmetics.equipped or {}
	return equipped.handTrailId or "default"
end

function PlayerProfile.getOwnedHandTrails(userId)
	userId = tostring(userId)
	local profile = PlayerProfile.load(userId)
	local owned = profile.cosmetics and profile.cosmetics.owned or {}
	local ownedList = {}

	for trailId, isOwned in pairs(owned) do
		if isOwned and trailId:sub(1, 5) == "hand_" then
			-- Remove "hand_" prefix for the returned list
			local cleanTrailId = trailId:sub(6)
			table.insert(ownedList, cleanTrailId)
		end
	end

	-- Always include default hand trail
	if not owned["hand_default"] then
		table.insert(ownedList, "default")
	end

	return ownedList
end

return PlayerProfile
