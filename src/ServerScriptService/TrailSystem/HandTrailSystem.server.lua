-- Server-side hand trail management system for purchasing and equipping hand trails
-- Handles hand trail purchases, equipment, and synchronization with client

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Import required modules
local playerProfileModule = ServerScriptService:FindFirstChild("PlayerProfile")
if not playerProfileModule then
	warn("[HandTrailSystem] PlayerProfile module not found in ServerScriptService")
	return
end
local PlayerProfile = require(playerProfileModule)
local HandTrailConfig =
	require(ReplicatedStorage:WaitForChild("Cosmetics"):WaitForChild("TrailSystem"):WaitForChild("HandTrailConfig"))
local HandTrailVisuals =
	require(ReplicatedStorage:WaitForChild("Cosmetics"):WaitForChild("TrailSystem"):WaitForChild("HandTrailVisuals"))

-- Cache for hand trail data to avoid repeated lookups
local handTrailDataCache = {}
local function getCachedHandTrailData()
	if not handTrailDataCache.allHandTrails then
		handTrailDataCache.allHandTrails = HandTrailConfig.HandTrails
	end
	return handTrailDataCache.allHandTrails
end

-- Wait for remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local PurchaseHandTrail = Remotes:WaitForChild("PurchaseHandTrail")
local EquipHandTrail = Remotes:WaitForChild("EquipHandTrail")
local GetHandTrailData = Remotes:WaitForChild("GetHandTrailData")
local HandTrailEquipped = Remotes:WaitForChild("HandTrailEquipped")

-- Security configuration
local MAX_PURCHASE_ATTEMPTS_PER_MINUTE = 10
local PURCHASE_COOLDOWN = 1 -- 1 second between purchases
local purchaseAttempts = {} -- [player] = {count, lastAttempt}

-- Helper function to check purchase cooldown
local function canPurchase(player)
	local now = os.time()
	local data = purchaseAttempts[player]

	if not data then
		purchaseAttempts[player] = { count = 0, lastAttempt = now }
		return true
	end

	-- Reset count if more than a minute has passed
	if now - data.lastAttempt > 60 then
		data.count = 0
	end

	-- Check cooldown
	if now - data.lastAttempt < PURCHASE_COOLDOWN then
		return false, "Please wait before making another purchase"
	end

	-- Check rate limit
	if data.count >= MAX_PURCHASE_ATTEMPTS_PER_MINUTE then
		return false, "Too many purchase attempts. Please wait a moment."
	end

	return true
end

-- Helper function to record purchase attempt
local function recordPurchaseAttempt(player)
	local now = os.time()
	local data = purchaseAttempts[player]

	if not data then
		purchaseAttempts[player] = { count = 1, lastAttempt = now }
	else
		data.count = data.count + 1
		data.lastAttempt = now
	end
end

-- Purchase hand trail remote
PurchaseHandTrail.OnServerInvoke = function(player, trailId)
	-- Security checks
	if not player or not player.Parent then
		return { success = false, reason = "InvalidPlayer" }
	end

	if type(trailId) ~= "string" or trailId == "" then
		return { success = false, reason = "InvalidTrailId" }
	end

	-- Check cooldown and rate limits
	local canBuy, reason = canPurchase(player)
	if not canBuy then
		return { success = false, reason = reason }
	end

	-- Get hand trail configuration
	local trail = HandTrailConfig.getHandTrailById(trailId)
	if not trail then
		return { success = false, reason = "TrailNotFound" }
	end

	-- Check if already owned
	if PlayerProfile.ownsHandTrail(player.UserId, trailId) then
		return { success = false, reason = "AlreadyOwned" }
	end

	-- Check if it's the default trail (should be free)
	if trailId == "default" then
		-- Default trail is always owned
		local success = PlayerProfile.purchaseHandTrail(player.UserId, trailId)
		if success then
			recordPurchaseAttempt(player)
			return { success = true, message = "Default hand trail unlocked" }
		else
			return { success = false, reason = "DatabaseError" }
		end
	end

	-- Validate price and currency
	if trail.price <= 0 then
		return { success = false, reason = "InvalidPrice" }
	end

	if trail.currency ~= "Coins" and trail.currency ~= "Diamonds" then
		return { success = false, reason = "InvalidCurrency" }
	end

	-- Get current balances before spending
	local currentCoins, currentDiamonds = PlayerProfile.getBalances(player.UserId)

	-- Attempt to spend currency (this now includes immediate save)
	local spendSuccess, newCoins, newDiamonds = PlayerProfile.trySpend(player.UserId, trail.currency, trail.price)
	if not spendSuccess then
		return { success = false, reason = "InsufficientFunds" }
	end

	-- Purchase the hand trail (this should be very fast since currency was already spent)
	local purchaseSuccess = PlayerProfile.purchaseHandTrail(player.UserId, trailId)
	if not purchaseSuccess then
		-- Refund the currency if purchase failed
		if trail.currency == "Coins" then
			PlayerProfile.addCoins(player.UserId, trail.price)
		else
			PlayerProfile.addDiamonds(player.UserId, trail.price)
		end
		return { success = false, reason = "PurchaseFailed" }
	end

	-- Record the attempt
	recordPurchaseAttempt(player)

	-- Update leaderstats first
	local stats = player:FindFirstChild("leaderstats")
	if stats then
		local ci = stats:FindFirstChild("Coins")
		local gi = stats:FindFirstChild("Diamonds")
		if ci then
			ci.Value = newCoins
		end
		if gi then
			gi.Value = newDiamonds
		end
	end

	-- Send currency update to client
	local CurrencyUpdated = Remotes:WaitForChild("CurrencyUpdated")
	CurrencyUpdated:FireClient(player, {
		Coins = newCoins,
		Diamonds = newDiamonds,
	})

	-- Log significant purchases
	if trail.price > 1000 then
		print(
			string.format(
				"[HandTrailSystem] %s purchased %s for %d %s",
				player.Name,
				trail.name,
				trail.price,
				trail.currency
			)
		)
	end

	return {
		success = true,
		message = string.format("Successfully purchased %s!", trail.name),
		coins = newCoins,
		diamonds = newDiamonds,
	}
end

-- Equip hand trail remote
EquipHandTrail.OnServerInvoke = function(player, trailId)
	-- Security checks
	if not player or not player.Parent then
		return { success = false, reason = "InvalidPlayer" }
	end

	if type(trailId) ~= "string" or trailId == "" then
		return { success = false, reason = "InvalidTrailId" }
	end

	-- Check if already equipped (avoid unnecessary DataStore operations)
	local currentEquipped = PlayerProfile.getEquippedHandTrail(player.UserId)
	if currentEquipped == trailId then
		return { success = true, message = "Hand trail already equipped" }
	end

	-- Verify hand trail exists
	local trail = HandTrailConfig.getHandTrailById(trailId)
	if not trail then
		return { success = false, reason = "TrailNotFound" }
	end

	-- Check ownership
	if not PlayerProfile.ownsHandTrail(player.UserId, trailId) then
		return { success = false, reason = "NotOwned" }
	end

	-- Equip the hand trail
	local success, message = PlayerProfile.equipHandTrail(player.UserId, trailId)
	if not success then
		return { success = false, reason = message }
	end

	-- Update hand trail visuals directly (server-side)
	HandTrailVisuals.setEquippedHandTrail(trailId, player)

	-- Notify all clients of successful equipment (so clients can update their local data)
	HandTrailEquipped:FireAllClients(player, trailId)

	return { success = true, message = message }
end

-- Get hand trail data remote
GetHandTrailData.OnServerInvoke = function(player)
	-- Security checks
	if not player or not player.Parent then
		return { success = false, reason = "InvalidPlayer" }
	end

	-- Get player's owned hand trails and equipped hand trail
	local ownedHandTrails = PlayerProfile.getOwnedHandTrails(player.UserId)
	local equippedHandTrail = PlayerProfile.getEquippedHandTrail(player.UserId)

	-- Get all hand trail configurations (use cache)
	local allHandTrails = getCachedHandTrailData()

	return {
		success = true,
		ownedHandTrails = ownedHandTrails,
		equippedHandTrail = equippedHandTrail,
		allHandTrails = allHandTrails,
	}
end

-- Clean up purchase attempts when players leave
Players.PlayerRemoving:Connect(function(player)
	purchaseAttempts[player] = nil
end)

-- Initialize hand trail for players
Players.PlayerAdded:Connect(function(player)
	task.wait(2) -- Wait for profile to load

	if PlayerProfile.load(player.UserId) then
		-- Ensure default hand trail is purchased
		if not PlayerProfile.ownsHandTrail(player.UserId, "default") then
			PlayerProfile.purchaseHandTrail(player.UserId, "default")
		end

		-- Load and equip the player's saved hand trail
		local equippedHandTrail = PlayerProfile.getEquippedHandTrail(player.UserId)
		if equippedHandTrail and PlayerProfile.ownsHandTrail(player.UserId, equippedHandTrail) then
			-- Update hand trail visuals directly
			HandTrailVisuals.setEquippedHandTrail(equippedHandTrail, player)
			-- Notify clients of the equipped hand trail
			HandTrailEquipped:FireAllClients(player, equippedHandTrail)
		else
			HandTrailVisuals.setEquippedHandTrail("default", player)
			HandTrailEquipped:FireAllClients(player, "default")
		end
	end
end)
