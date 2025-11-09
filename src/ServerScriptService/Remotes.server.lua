-- TEMPORARY: Creates RemoteEvents (security temporarily disabled for debugging)
-- Will re-enable security once basic functionality is working

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local function ensureFolder(parent, name)
	local folder = parent:FindFirstChild(name)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = parent
	end
	return folder
end

local function ensureRemoteEvent(parent, name)
	local remote = parent:FindFirstChild(name)
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = parent
	end
	return remote
end

local function ensureRemoteFunction(parent, name)
	local remote = parent:FindFirstChild(name)
	if not remote then
		remote = Instance.new("RemoteFunction")
		remote.Name = name
		remote.Parent = parent
	end
	return remote
end

local remotesFolder = ensureFolder(ReplicatedStorage, "Remotes")

-- Core gameplay remotes
ensureRemoteEvent(remotesFolder, "DashActivated")
ensureRemoteEvent(remotesFolder, "MomentumUpdated")
ensureRemoteEvent(remotesFolder, "StyleCommit")
ensureRemoteEvent(remotesFolder, "MaxComboReport")
ensureRemoteEvent(remotesFolder, "PadTriggered")
ensureRemoteEvent(remotesFolder, "RopeAttach")
ensureRemoteEvent(remotesFolder, "RopeRelease")
ensureRemoteEvent(remotesFolder, "PowerupTouched")
ensureRemoteEvent(remotesFolder, "PowerupActivated")

-- LedgeHang system remotes
ensureRemoteEvent(remotesFolder, "LedgeHangStart")
ensureRemoteEvent(remotesFolder, "LedgeHangMove")
ensureRemoteEvent(remotesFolder, "LedgeHangStop")

-- Audio settings remotes
ensureRemoteEvent(remotesFolder, "AudioSettingsLoaded")
ensureRemoteEvent(remotesFolder, "SetAudioSettings")

-- Playtime rewards remotes
ensureRemoteFunction(remotesFolder, "PlaytimeRequest")
ensureRemoteFunction(remotesFolder, "PlaytimeClaim")

-- Currency system remotes
ensureRemoteEvent(remotesFolder, "CurrencyUpdated")
ensureRemoteFunction(remotesFolder, "RequestBalances")
ensureRemoteFunction(remotesFolder, "RequestSpendCurrency")

-- SECURITY: Only create debug remotes in Studio environment
if RunService:IsStudio() then
	-- Debug remotes for Playtime Rewards (DEVELOPMENT ONLY)
	ensureRemoteFunction(remotesFolder, "DebugResetPlaytime")
	ensureRemoteFunction(remotesFolder, "DebugUnlockNext")
	ensureRemoteFunction(remotesFolder, "DebugGetPlaytimeStatus")
end

-- Currency remotes
ensureRemoteEvent(remotesFolder, "CurrencyUpdated")
ensureRemoteFunction(remotesFolder, "RequestBalances")
ensureRemoteFunction(remotesFolder, "RequestSpendCurrency")

-- Trail system remotes
ensureRemoteFunction(remotesFolder, "PurchaseTrail")
ensureRemoteFunction(remotesFolder, "EquipTrail")
ensureRemoteFunction(remotesFolder, "GetTrailData")
ensureRemoteEvent(remotesFolder, "TrailEquipped")

-- Hand trail system remotes
ensureRemoteFunction(remotesFolder, "PurchaseHandTrail")
ensureRemoteFunction(remotesFolder, "EquipHandTrail")
ensureRemoteFunction(remotesFolder, "GetHandTrailData")
ensureRemoteEvent(remotesFolder, "HandTrailEquipped")

-- Bomb Tag system remotes
ensureRemoteEvent(remotesFolder, "BombTagGameStart")
ensureRemoteEvent(remotesFolder, "BombTagCountdownUpdate")
ensureRemoteEvent(remotesFolder, "BombTagBombAssigned")
ensureRemoteEvent(remotesFolder, "BombTagBombTimerUpdate")
ensureRemoteEvent(remotesFolder, "BombTagPlayerEliminated")
ensureRemoteEvent(remotesFolder, "BombTagGameEnd")
ensureRemoteEvent(remotesFolder, "BombTagBombPassed")
ensureRemoteEvent(remotesFolder, "BombTagPlatformPrompt")
ensureRemoteEvent(remotesFolder, "BombTagReadyStatus")
ensureRemoteEvent(remotesFolder, "BombTagReadyWarning")
ensureRemoteEvent(remotesFolder, "BombTagReadyToggle")
ensureRemoteEvent(remotesFolder, "BombTagScoreboardUpdate")

-- Global leaderboards
ensureRemoteEvent(remotesFolder, "LeaderboardsUpdate")

-- TEMPORARY: Anti-cheat remotes disabled for debugging
-- if RunService:IsStudio() then
-- 	-- Anti-cheat debug remotes (DEVELOPMENT ONLY)
-- 	ensureRemoteFunction(remotesFolder, "AntiCheatGetLogs")
-- 	ensureRemoteFunction(remotesFolder, "AntiCheatClearLogs")
-- 	ensureRemoteFunction(remotesFolder, "AntiCheatGetStats")
-- end
