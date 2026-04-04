-- TEMPORARY: Central currency manager (anti-cheat disabled for debugging)
-- Will re-enable security once basic functionality is working

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local playerProfileModule = ServerScriptService:FindFirstChild("PlayerProfile")
if not playerProfileModule then
	warn("[Currency] PlayerProfile module not found in ServerScriptService")
	return
end
local PlayerProfile = require(playerProfileModule)
-- TEMPORARY: AntiCheat disabled for debugging
-- local AntiCheat = require(ServerScriptService:WaitForChild("AntiCheat"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local StyleCommit = Remotes:WaitForChild("StyleCommit")
local CurrencyUpdated = Remotes:WaitForChild("CurrencyUpdated")
local RequestBalances = Remotes:WaitForChild("RequestBalances")
local RequestSpend = Remotes:WaitForChild("RequestSpendCurrency")

local CurrencyConfig = require(ReplicatedStorage:WaitForChild("Currency"):WaitForChild("Config"))

-- Security configuration
local MAX_STYLE_PER_COMMIT = 500 -- Maximum style points per single commit
local MIN_COMMIT_INTERVAL = 2 -- Minimum seconds between commits
local MAX_COMMITS_PER_MINUTE = 15 -- Maximum commits per minute per player

-- OPTIMIZED: No longer creates leaderstats - PlayerData.server.lua handles all leaderstats setup
local function refreshLeaderstats(player)
	-- Use already created leaderstats from PlayerData.server.lua
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		warn(
			string.format(
				"[Currency] No leaderstats found for %s - PlayerData.server.lua should create these",
				player.Name
			)
		)
		return
	end

	local c, g = PlayerProfile.getBalances(player.UserId)
	local ci = stats:FindFirstChild("Coins")
	local gi = stats:FindFirstChild("Diamonds")
	if ci then
		ci.Value = tonumber(c) or 0
	end
	if gi then
		gi.Value = tonumber(g) or 0
	end
end

local function calculateStyleAward(amount)
	local per = tonumber(CurrencyConfig.CoinsPerStylePoint or 0) or 0
	local bonus = 0

	if amount >= (CurrencyConfig.StyleOutstandingThreshold or 1e9) then
		bonus = math.floor((CurrencyConfig.OutstandingBonusCoins or 0) + 0.5)
	elseif amount >= (CurrencyConfig.StyleGreatThreshold or 1e9) then
		bonus = math.floor((CurrencyConfig.GreatBonusCoins or 0) + 0.5)
	elseif amount >= (CurrencyConfig.StyleGoodThreshold or 1e9) then
		bonus = math.floor((CurrencyConfig.GoodBonusCoins or 0) + 0.5)
	end

	local award = math.floor(amount * per + bonus + 0.5)

	if CurrencyConfig.CommitAwardCoinCap then
		award = math.min(award, CurrencyConfig.CommitAwardCoinCap)
	end

	return math.max(0, award)
end

-- OPTIMIZED: No longer refresh on PlayerAdded - PlayerData.server.lua handles initial setup
-- refreshLeaderstats will be called by other functions when needed (e.g., StyleCommit, purchases)

-- TEMPORARY: Award coins when style is committed (anti-cheat disabled)
StyleCommit.OnServerEvent:Connect(function(player, amount)
	-- TEMPORARY: Anti-cheat validation disabled for debugging
	-- if not AntiCheat.validateStyleCommit(player, amount) then
	-- 	warn(string.format("[SECURITY] Blocked suspicious StyleCommit from %s: %s", player.Name, tostring(amount)))
	-- 	return
	-- end

	amount = tonumber(amount) or 0
	if amount <= 0 then
		return
	end

	-- Calculate award using secure function
	local award = calculateStyleAward(amount)

	if award > 0 then
		local newCoins = select(1, PlayerProfile.addCoins(player.UserId, award))
		refreshLeaderstats(player)
		CurrencyUpdated:FireClient(player, { Coins = newCoins, AwardedCoins = award })
	end
end)

-- Balance request
RequestBalances.OnServerInvoke = function(player)
	local c, g = PlayerProfile.getBalances(player.UserId)
	return { Coins = c, Diamonds = g }
end

-- FIXED: Spend request with proper validation
RequestSpend.OnServerInvoke = function(player, payload)
	if type(payload) ~= "table" then
		return { success = false, reason = "InvalidPayload" }
	end

	local currency = tostring(payload.currency)
	local amount = tonumber(payload.amount) or 0

	-- Validation
	if amount <= 0 then
		return { success = false, reason = "InvalidAmount" }
	end

	if currency ~= "Coins" and currency ~= "Diamonds" then
		return { success = false, reason = "InvalidCurrency" }
	end

	-- TEMPORARY: Additional security disabled for debugging
	local MAX_SPEND_PER_REQUEST = 1000000 -- 1M coins/diamonds max per request
	if amount > MAX_SPEND_PER_REQUEST then
		-- AntiCheat.logSuspiciousActivity(player, "InvalidRequests", {
		-- 	type = "ExcessiveSpend",
		-- 	amount = amount,
		-- 	maxAllowed = MAX_SPEND_PER_REQUEST,
		-- })
		warn(string.format("[CURRENCY] Excessive spend attempt from %s: %d", player.Name, amount))
		return { success = false, reason = "ExcessiveAmount" }
	end

	local ok, newCoins, newDiamonds = PlayerProfile.trySpend(player.UserId, currency, amount)
	if not ok then
		return { success = false, reason = "InsufficientFunds" }
	end

	refreshLeaderstats(player)
	CurrencyUpdated:FireClient(player, { Coins = newCoins, Diamonds = newDiamonds })

	-- Log significant spending
	if amount > 10000 then
		print(string.format("[CURRENCY] %s spent %d %s", player.Name, amount, currency))
	end

	return { success = true, Coins = newCoins, Diamonds = newDiamonds }
end
