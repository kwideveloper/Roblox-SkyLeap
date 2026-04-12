-- Delays respawn and tells the victim client to spectate the killer (sniper kills).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("DeathSpectate"):WaitForChild("Config"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local deathSpectatePayload = remotes:WaitForChild("DeathSpectatePayload")

local pending: { [Player]: boolean } = {}

local function writeCharacterAutoLoads(player: Player, value: boolean)
	pcall(function()
		(player :: any).CharacterAutoLoads = value
	end)
end

local function shouldSkip(victim: Player): boolean
	if Config.Enabled == false then
		return true
	end
	if Config.SkipWhenBombTag ~= false and victim:GetAttribute("BombTagActive") == true then
		return true
	end
	if Config.SkipWhenZombieTag ~= false and victim:GetAttribute("ZombieTagActive") == true then
		return true
	end
	return false
end

local M = {}

-- preKillCharAutoLoads: CharacterAutoLoads **before** SniperServer set it false (required for correct restore).
function M.tryBegin(victim: Player, killer: Player, preKillCharAutoLoads: boolean?): boolean
	if not victim or not killer or victim == killer then
		return false
	end
	if pending[victim] then
		return false
	end
	local restoreAutoLoads = preKillCharAutoLoads
	if restoreAutoLoads == nil then
		restoreAutoLoads = true
	end
	if shouldSkip(victim) then
		writeCharacterAutoLoads(victim, restoreAutoLoads)
		return false
	end

	pending[victim] = true
	writeCharacterAutoLoads(victim, false)

	local tIn = Config.TransitionInSeconds or 0.34
	local tHold = Config.SpectateHoldSeconds or 2
	local tOut = Config.TransitionOutSeconds or 0.26
	local totalDelay = tIn + tHold + tOut

	deathSpectatePayload:FireClient(victim, {
		killerUserId = killer.UserId,
		transitionInSec = tIn,
		spectateHoldSec = tHold,
		transitionOutSec = tOut,
	})

	task.delay(totalDelay, function()
		pending[victim] = nil
		if victim.Parent == nil then
			return
		end
		writeCharacterAutoLoads(victim, restoreAutoLoads)
		pcall(function()
			victim:LoadCharacter()
		end)
	end)

	return true
end

Players.PlayerRemoving:Connect(function(plr)
	pending[plr] = nil
end)

return M
