local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage:WaitForChild("Sniper"):WaitForChild("Config"))
local PlayerProfile = require(ServerScriptService:WaitForChild("PlayerProfile"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local CurrencyUpdated = Remotes:WaitForChild("CurrencyUpdated")
local KillRewardEvent = Remotes:WaitForChild("KillRewardEvent")

type KillPayload = {
	isHeadshot: boolean?,
	targetType: string?,
}

type ComboState = {
	killCount: number,
	pendingCoins: number,
	token: number,
	lastKillTime: number,
}

local KillRewardService = {}
local comboByPlayer: { [Player]: ComboState } = {}

local function refreshLeaderstats(player: Player, coins: number?)
	local stats = player:FindFirstChild("leaderstats")
	local coinsValue = stats and stats:FindFirstChild("Coins")
	if coinsValue and coinsValue:IsA("IntValue") then
		coinsValue.Value = math.max(0, math.floor(tonumber(coins) or 0))
	end
end

local function getMultiKillLabel(killCount: number): string?
	if killCount == 2 then
		return "DOUBLE KILL"
	elseif killCount == 3 then
		return "TRIPLE KILL"
	elseif killCount == 4 then
		return "QUADRA KILL"
	elseif killCount == 5 then
		return "PENTA KILL"
	end
	return nil
end

local function getMultiKillBonus(killCount: number): number
	if killCount == 2 then
		return Config.KillRewardMultiKillBonusDouble or 5
	elseif killCount == 3 then
		return Config.KillRewardMultiKillBonusTriple or 10
	elseif killCount == 4 then
		return Config.KillRewardMultiKillBonusQuadra or 15
	elseif killCount == 5 then
		return Config.KillRewardMultiKillBonusPenta or 20
	end
	return 0
end

local function getOrCreateComboState(player: Player): ComboState
	local state = comboByPlayer[player]
	if state then
		return state
	end
	state = {
		killCount = 0,
		pendingCoins = 0,
		token = 0,
		lastKillTime = 0,
	}
	comboByPlayer[player] = state
	return state
end

local function payoutCombo(player: Player, token: number)
	local state = comboByPlayer[player]
	if not state or state.token ~= token then
		return
	end
	local award = math.max(0, math.floor(state.pendingCoins))
	local kills = state.killCount
	if award <= 0 then
		state.killCount = 0
		state.pendingCoins = 0
		return
	end

	local newCoins = select(1, PlayerProfile.addCoins(player.UserId, award))
	refreshLeaderstats(player, newCoins)

	CurrencyUpdated:FireClient(player, {
		Coins = newCoins,
		AwardedCoins = award,
		AwardedCoinsAnimationSpeedMultiplier = Config.KillRewardCoinAnimSpeedMultiplier or 1.35,
	})
	KillRewardEvent:FireClient(player, {
		eventType = "Payout",
		awardedCoins = award,
		totalKills = kills,
	})

	state.killCount = 0
	state.pendingCoins = 0
end

function KillRewardService.registerKill(shooter: Player, payload: KillPayload?)
	if Config.KillRewardEnabled == false then
		return
	end
	if not shooter or not shooter.Parent then
		return
	end

	local state = getOrCreateComboState(shooter)
	local windowSeconds = Config.KillRewardWindowSeconds or 3
	local now = os.clock()

	if state.lastKillTime <= 0 or (now - state.lastKillTime) > windowSeconds then
		state.killCount = 0
		state.pendingCoins = 0
	end

	state.killCount += 1
	state.lastKillTime = now

	local base = Config.KillRewardBaseCoins or 20
	local rapidStep = Config.KillRewardRapidBonusStep or 5
	local rapidCap = Config.KillRewardRapidBonusMax or 30
	local rapidBonus = math.min(rapidCap, math.max(0, (state.killCount - 1) * rapidStep))
	local headshotBonus = (payload and payload.isHeadshot) and (Config.KillRewardHeadshotBonus or 10) or 0
	local multiBonus = getMultiKillBonus(state.killCount)
	local streakBonus = 0
	local streakLabel: string? = nil
	if state.killCount >= 6 then
		streakBonus = (state.killCount - 5) * (Config.KillRewardStreakPerKillBonus or 3)
		streakLabel = string.format("%d KILL STREAK", state.killCount)
	end

	local gained = base + rapidBonus + headshotBonus + multiBonus + streakBonus
	state.pendingCoins += gained

	KillRewardEvent:FireClient(shooter, {
		eventType = "KillRegistered",
		coinsGained = gained,
		pendingCoins = state.pendingCoins,
		killCount = state.killCount,
		isHeadshot = payload and payload.isHeadshot == true or false,
		targetType = payload and payload.targetType or "unknown",
		multiKillLabel = getMultiKillLabel(state.killCount),
		streakLabel = streakLabel,
		windowSeconds = windowSeconds,
	})

	state.token += 1
	local token = state.token
	task.delay(windowSeconds, function()
		payoutCombo(shooter, token)
	end)
end

function KillRewardService.registerCollateral(shooter: Player, killsInShot: number)
	if Config.KillRewardEnabled == false then
		return
	end
	if not shooter or not shooter.Parent then
		return
	end
	killsInShot = math.floor(tonumber(killsInShot) or 0)
	if killsInShot < 2 then
		return
	end

	local state = getOrCreateComboState(shooter)
	local base = Config.KillRewardCollateralBonus or 20
	local perExtra = Config.KillRewardCollateralPerExtraKill or 8
	local bonus = base + math.max(0, killsInShot - 2) * perExtra
	state.pendingCoins += bonus
	state.lastKillTime = os.clock()

	local windowSeconds = Config.KillRewardWindowSeconds or 6
	state.token += 1
	local token = state.token
	task.delay(windowSeconds, function()
		payoutCombo(shooter, token)
	end)

	KillRewardEvent:FireClient(shooter, {
		eventType = "Collateral",
		coinsGained = bonus,
		pendingCoins = state.pendingCoins,
		collateralKills = killsInShot,
		collateralLabel = "COLLATERAL",
		windowSeconds = windowSeconds,
	})
end

Players.PlayerRemoving:Connect(function(player)
	comboByPlayer[player] = nil
end)

return KillRewardService
