-- Server-side simple leaderboard for total style points

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local playerProfileModule = ServerScriptService:FindFirstChild("PlayerProfile")
if not playerProfileModule then
	warn("[Leaderboard] PlayerProfile module not found in ServerScriptService")
	return
end
local PlayerProfile = require(playerProfileModule)

local remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
if not remotes then
	warn("[Leaderboard] Remotes folder not found (timeout)")
	return
end
local styleCommit = remotes:WaitForChild("StyleCommit", 15)
if not styleCommit then
	warn("[Leaderboard] StyleCommit remote not found (timeout)")
	return
end
-- Currency is handled in Currency.server.lua

-- FIXED: Create Leaderboard folder that LeaderboardUI.client.lua expects
local leaderboardFolder = ReplicatedStorage:FindFirstChild("Leaderboard")
if not leaderboardFolder then
	leaderboardFolder = Instance.new("Folder")
	leaderboardFolder.Name = "Leaderboard"
	leaderboardFolder.Parent = ReplicatedStorage
end

-- OPTIMIZED: No longer loads profile here - PlayerData.server.lua handles all leaderstats setup
-- This script now only handles style commits

-- Helper function to get style total from already-loaded profile
local function getStyleTotal(player)
	-- Use already loaded profile (PlayerData.server.lua loads it first)
	local stats = player:FindFirstChild("leaderstats")
	if stats then
		local style = stats:FindFirstChild("Style")
		return style and style.Value or 0
	end
	return 0
end

-- REMOVED: PlayerAdded connection - PlayerData.server.lua now handles all leaderstats creation

-- No explicit save here; PlayerProfile.addStyleTotal already persists on commit

styleCommit.OnServerEvent:Connect(function(player, amount)
	amount = tonumber(amount) or 0
	if amount <= 0 then
		return
	end
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		return
	end
	local style = stats:FindFirstChild("Style")
	if not style then
		style = Instance.new("NumberValue")
		style.Name = "Style"
		style.Value = 0
		style.Parent = stats
	end
	style.Value = style.Value + amount
	-- Save asynchronously (fire-and-forget); PlayerRemoving persists too
	-- Mirror into PlayerProfile styleTotal for unified access (single source of truth)
	PlayerProfile.addStyleTotal(player.UserId, amount)
end)
