-- Server: touch pickups tagged "CurrencyPickup" with GiveCoins / GiveDiamonds attributes.
-- Awards currency through PlayerProfile, syncs leaderstats, fires CurrencyUpdated with AwardedCoins/AwardedDiamonds
-- so CurrencyUI + RewardAnimations match LevelSystem-style feedback.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local SharedUtils = require(ReplicatedStorage:WaitForChild("SharedUtils"))
local PickupConfig = require(ReplicatedStorage:WaitForChild("Currency"):WaitForChild("PickupConfig"))

local PlayerProfile = require(ServerScriptService:WaitForChild("PlayerProfile"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local CurrencyUpdated = Remotes:WaitForChild("CurrencyUpdated")

local TAG = PickupConfig.TagName or "CurrencyPickup"
local MAX_GIVE = tonumber(PickupConfig.MaxGivePerAttribute) or 1_000_000
local DEBOUNCE = tonumber(PickupConfig.TouchDebounceSeconds) or 0.35
local MAX_DIST = PickupConfig.MaxTouchDistanceStuds
local DESTROY_ON_COLLECT = PickupConfig.DestroyOnCollect ~= false

-- [player] = { [pickupRoot] = lastClock }
local debounceByPlayer = setmetatable({}, { __mode = "k" })

local function clampAmount(n)
	local v = math.floor(tonumber(n) or 0)
	if v < 0 then
		return 0
	end
	if v > MAX_GIVE then
		return MAX_GIVE
	end
	return v
end

local function readRewards(root)
	local coins = clampAmount(root:GetAttribute("GiveCoins"))
	local diamonds = clampAmount(root:GetAttribute("GiveDiamonds"))
	return coins, diamonds
end

local function findTaggedRoot(startInstance)
	local cur = startInstance
	while cur do
		if CollectionService:HasTag(cur, TAG) then
			return cur
		end
		if cur == workspace or cur == game then
			break
		end
		cur = cur.Parent
	end
	return nil
end

local function updateLeaderstats(player, coins, diamonds)
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		return
	end
	local ci = stats:FindFirstChild("Coins")
	local gi = stats:FindFirstChild("Diamonds")
	if ci then
		ci.Value = coins
	end
	if gi then
		gi.Value = diamonds
	end
end

local function tryCollect(player, colliderPart, root)
	if root:GetAttribute("_CurrencyPickupConsumed") == true then
		return
	end

	local coins, diamonds = readRewards(root)
	if coins <= 0 and diamonds <= 0 then
		return
	end

	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local rootPart = char and char:FindFirstChild("HumanoidRootPart")
	if not hum or hum.Health <= 0 or not rootPart then
		return
	end

	if typeof(MAX_DIST) == "number" and MAX_DIST > 0 then
		if not SharedUtils.isWithinDistance(rootPart.Position, colliderPart.Position, MAX_DIST) then
			return
		end
	end

	local db = debounceByPlayer[player]
	if not db then
		db = {}
		debounceByPlayer[player] = db
	end
	local now = os.clock()
	local debounceKey = root:GetFullName()
	if (db[debounceKey] or 0) + DEBOUNCE > now then
		return
	end
	db[debounceKey] = now

	root:SetAttribute("_CurrencyPickupConsumed", true)

	local ok, err = pcall(function()
		if coins > 0 then
			PlayerProfile.addCoins(player.UserId, coins)
		end
		if diamonds > 0 then
			PlayerProfile.addDiamonds(player.UserId, diamonds)
		end
	end)

	if not ok then
		root:SetAttribute("_CurrencyPickupConsumed", nil)
		warn("[CurrencyPickup] Grant failed:", err)
		return
	end

	local newCoins, newDiamonds = PlayerProfile.getBalances(player.UserId)
	updateLeaderstats(player, newCoins, newDiamonds)

	CurrencyUpdated:FireClient(player, {
		Coins = newCoins,
		Diamonds = newDiamonds,
		AwardedCoins = coins > 0 and coins or nil,
		AwardedDiamonds = diamonds > 0 and diamonds or nil,
	})

	if DESTROY_ON_COLLECT then
		root:Destroy()
	else
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("BasePart") then
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d.Transparency = 1
			end
		end
	end
end

local function onTouched(hit, colliderPart, root)
	if not hit or not hit:IsA("BasePart") then
		return
	end
	local player = SharedUtils.getPlayerFromTouch(hit)
	if not player then
		return
	end
	-- Tagged root must match (collider under same pickup hierarchy)
	if findTaggedRoot(colliderPart) ~= root then
		return
	end
	tryCollect(player, colliderPart, root)
end

local function bindBasePart(part, root, connections)
	connections[#connections + 1] = part.Touched:Connect(function(hit)
		onTouched(hit, part, root)
	end)
end

local function wirePickup(root)
	if not CollectionService:HasTag(root, TAG) then
		return
	end
	if root:GetAttribute("_CurrencyPickupWired") == true then
		return
	end
	root:SetAttribute("_CurrencyPickupWired", true)

	local connections = {}

	if root:IsA("Model") then
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("BasePart") then
				bindBasePart(d, root, connections)
			end
		end
		connections[#connections + 1] = root.DescendantAdded:Connect(function(d)
			if d:IsA("BasePart") then
				bindBasePart(d, root, connections)
			end
		end)
	elseif root:IsA("BasePart") then
		bindBasePart(root, root, connections)
	else
		warn("[CurrencyPickup] Unsupported tagged instance (use Model or BasePart):", root:GetFullName())
		root:SetAttribute("_CurrencyPickupWired", nil)
		return
	end

	connections[#connections + 1] = root.Destroying:Connect(function()
		for _, c in ipairs(connections) do
			if typeof(c) == "RBXScriptConnection" then
				c:Disconnect()
			end
		end
	end)
end

CollectionService:GetInstanceAddedSignal(TAG):Connect(wirePickup)

for _, inst in ipairs(CollectionService:GetTagged(TAG)) do
	task.defer(wirePickup, inst)
end

Players.PlayerRemoving:Connect(function(player)
	debounceByPlayer[player] = nil
end)
