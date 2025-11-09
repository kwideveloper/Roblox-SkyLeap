local DataStoreService = game:GetService("DataStoreService")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerProfile = require(ServerScriptService:WaitForChild("PlayerProfile"))

local Leaderboards = {}

local DAILY_WINS_PREFIX = "LB_DailyWins_"
local DAILY_KILLS_PREFIX = "LB_DailyKills_"
local STREAK_STORE_NAME = "LB_BestKillStreak_AllTime"
local DONATION_STORE_NAME = "LB_Donations_AllTime"
local MATCH_TIME_STORE_NAME = "LB_MatchTime_AllTime"
local WINS_ALL_TIME_STORE_NAME = "LB_Wins_AllTime"
local KILLS_ALL_TIME_STORE_NAME = "LB_Kills_AllTime"

local orderedCache = {}

local function getDateString()
	local utc = os.date("!*t")
	return string.format("%04d%02d%02d", utc.year, utc.month, utc.day)
end

local function getOrderedStore(name)
	if not orderedCache[name] then
		orderedCache[name] = DataStoreService:GetOrderedDataStore(name)
	end
	return orderedCache[name]
end

local function getDailyStore(prefix)
	local dateKey = getDateString()
	local name = prefix .. dateKey
	return getOrderedStore(name), name
end

local function incrementOrdered(store, userId, delta)
	userId = tostring(userId)
	local ok, err = pcall(function()
		store:IncrementAsync(userId, delta)
	end)
	if not ok then
		warn(string.format("[Leaderboards] Increment failed for %s: %s", tostring(userId), tostring(err)))
	end
end

local function updateOrderedMax(store, userId, candidate)
	userId = tostring(userId)
	local ok, err = pcall(function()
		store:UpdateAsync(userId, function(prev)
			prev = tonumber(prev) or 0
			return math.max(prev, candidate)
		end)
	end)
	if not ok then
		warn(string.format("[Leaderboards] UpdateAsync failed for %s: %s", tostring(userId), tostring(err)))
	end
end

function Leaderboards.RecordDailyWin(userId, amount)
	amount = tonumber(amount) or 0
	if amount == 0 then
		return
	end
	local store = select(1, getDailyStore(DAILY_WINS_PREFIX))
	incrementOrdered(store, userId, amount)
end

function Leaderboards.RecordWinAllTime(userId, amount)
	amount = tonumber(amount) or 0
	if amount == 0 then
		return
	end
	local store = getOrderedStore(WINS_ALL_TIME_STORE_NAME)
	incrementOrdered(store, userId, amount)
end

function Leaderboards.RecordDailyKill(userId, amount)
	amount = tonumber(amount) or 0
	if amount == 0 then
		return
	end
	local store = select(1, getDailyStore(DAILY_KILLS_PREFIX))
	incrementOrdered(store, userId, amount)
end

function Leaderboards.RecordKillAllTime(userId, amount)
	amount = tonumber(amount) or 0
	if amount == 0 then
		return
	end
	local store = getOrderedStore(KILLS_ALL_TIME_STORE_NAME)
	incrementOrdered(store, userId, amount)
end

function Leaderboards.RecordBestStreak(userId, streak)
	streak = tonumber(streak) or 0
	if streak <= 0 then
		return
	end
	local store = getOrderedStore(STREAK_STORE_NAME)
	updateOrderedMax(store, userId, streak)
end

function Leaderboards.RecordDonation(userId, amount)
	amount = tonumber(amount) or 0
	if amount == 0 then
		return
	end
	local store = getOrderedStore(DONATION_STORE_NAME)
	incrementOrdered(store, userId, amount)
end

function Leaderboards.RecordDonationPurchase(player, amount)
	if not player or not player.Parent then
		return 0
	end
	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 then
		local profile = PlayerProfile.load(player.UserId)
		return (profile.stats and profile.stats.donatedRobuxTotal) or 0
	end
	local total = PlayerProfile.addDonationRobux(player.UserId, amount)
	Leaderboards.RecordDonation(player.UserId, amount)
	return total
end

function Leaderboards.RecordMatchTime(userId, seconds)
	seconds = tonumber(seconds) or 0
	if seconds <= 0 then
		return
	end
	local store = getOrderedStore(MATCH_TIME_STORE_NAME)
	incrementOrdered(store, userId, seconds)
end

local function getTopEntries(storeName, limit, ascending)
	limit = math.clamp(tonumber(limit) or 10, 1, 50)
	local ascendingFlag = ascending == true
	local result = {}
	local ok, err = pcall(function()
		local store = getOrderedStore(storeName)
		local pages = store:GetSortedAsync(ascendingFlag, limit)
		local page = pages:GetCurrentPage()
		for _, entry in ipairs(page) do
			table.insert(result, {
				UserId = tonumber(entry.key),
				Value = entry.value,
			})
		end
	end)
	if not ok then
		warn(string.format("[Leaderboards] GetTopEntries failed for %s: %s", tostring(storeName), tostring(err)))
	end
	return result
end

function Leaderboards.GetTopDailyWins(limit)
	local _, name = getDailyStore(DAILY_WINS_PREFIX)
	return getTopEntries(name, limit)
end

function Leaderboards.GetTopDailyKills(limit)
	local _, name = getDailyStore(DAILY_KILLS_PREFIX)
	return getTopEntries(name, limit)
end

function Leaderboards.GetTopBestStreak(limit)
	return getTopEntries(STREAK_STORE_NAME, limit)
end

function Leaderboards.GetTopDonations(limit)
	return getTopEntries(DONATION_STORE_NAME, limit)
end

function Leaderboards.GetTopMatchTime(limit)
	return getTopEntries(MATCH_TIME_STORE_NAME, limit)
end

function Leaderboards.GetTopWinsAllTime(limit)
	return getTopEntries(WINS_ALL_TIME_STORE_NAME, limit)
end

function Leaderboards.GetTopKillsAllTime(limit)
	return getTopEntries(KILLS_ALL_TIME_STORE_NAME, limit)
end

function Leaderboards.GetCurrentDailyKey()
	return getDateString()
end

return Leaderboards

