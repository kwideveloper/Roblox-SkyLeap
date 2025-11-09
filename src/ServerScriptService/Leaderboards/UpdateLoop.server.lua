local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Leaderboards = require(ServerScriptService:WaitForChild("Leaderboards"))

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local updateRemote = remotesFolder:WaitForChild("LeaderboardsUpdate")

local UPDATE_INTERVAL = 60

local function gatherPayload()
	return {
		WinsDaily = Leaderboards.GetTopDailyWins(10),
		WinsAllTime = Leaderboards.GetTopWinsAllTime(10),
		KillsDaily = Leaderboards.GetTopDailyKills(10),
		KillsAllTime = Leaderboards.GetTopKillsAllTime(10),
		KillStreakAllTime = Leaderboards.GetTopBestStreak(10),
		DonationsAllTime = Leaderboards.GetTopDonations(10),
		MatchTimeAllTime = Leaderboards.GetTopMatchTime(10),
		CurrentDailyKey = Leaderboards.GetCurrentDailyKey(),
	}
end

local function broadcast()
	local payload = gatherPayload()
	updateRemote:FireAllClients(payload)
end

broadcast()

task.spawn(function()
	while true do
		task.wait(UPDATE_INTERVAL)
		broadcast()
	end
end)

