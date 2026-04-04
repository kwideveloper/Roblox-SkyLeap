local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local playerProfileModule = ServerScriptService:FindFirstChild("PlayerProfile")
if not playerProfileModule then
	warn("[DailyReset] PlayerProfile module not found in ServerScriptService")
	return
end
local PlayerProfile = require(playerProfileModule)
local leaderboardsEntry = ServerScriptService:FindFirstChild("Leaderboards")
if not leaderboardsEntry then
	warn("[DailyReset] Leaderboards module not found in ServerScriptService")
	return
end
local Leaderboards = require(leaderboardsEntry)

local currentDate = Leaderboards.GetCurrentDailyKey()

local function resetPlayerDailyStats(player)
	if not player or not player.Parent then
		return
	end
	PlayerProfile.resetDailyStats(player.UserId)
end

Players.PlayerAdded:Connect(function(player)
	resetPlayerDailyStats(player)
end)

for _, player in ipairs(Players:GetPlayers()) do
	resetPlayerDailyStats(player)
end

task.spawn(function()
	while true do
		task.wait(60)
		local newDate = Leaderboards.GetCurrentDailyKey()
		if newDate ~= currentDate then
			currentDate = newDate
			for _, player in ipairs(Players:GetPlayers()) do
				resetPlayerDailyStats(player)
			end
		end
	end
end)

