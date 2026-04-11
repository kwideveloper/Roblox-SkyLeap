-- True when the local player should not use full parkour (any Tool on character, or virtual sniper slot active).
-- Allowed with weapon: vault, double jump, dash, ground slide — see ParkourController gating.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Climb = require(script.Parent.Climb)
local WallRun = require(script.Parent.WallRun)
local Zipline = require(script.Parent.Zipline)
local VerticalClimb = require(script.Parent.VerticalClimb)
local LedgeHang = require(script.Parent.LedgeHang)
local Grapple = require(script.Parent.Grapple)
local WallJump = require(script.Parent.WallJump)
local Fly = require(script.Parent.Fly)

local ParkourWeaponGate = {}

local function hasToolEquipped(character: Model): boolean
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") then
			return true
		end
	end
	return false
end

local function hasVirtualSniperHeld(): boolean
	local ok, loadout = pcall(function()
		return require(ReplicatedStorage:WaitForChild("Sniper"):WaitForChild("SniperLoadoutState"))
	end)
	if ok and loadout and type(loadout.isVirtualSniperHeld) == "function" then
		return loadout.isVirtualSniperHeld() == true
	end
	return false
end

function ParkourWeaponGate.isHoldingWeapon(character: Model?): boolean
	if not character then
		return false
	end
	return hasToolEquipped(character) or hasVirtualSniperHeld()
end

function ParkourWeaponGate.stopForbiddenParkour(character: Model)
	if not character then
		return
	end
	pcall(function()
		if WallRun.isActive(character) then
			WallRun.stop(character)
		end
	end)
	pcall(function()
		if VerticalClimb.isActive(character) then
			VerticalClimb.stop(character)
		end
	end)
	pcall(function()
		if Climb.isActive(character) then
			Climb.stop(character)
		end
	end)
	pcall(function()
		if Zipline.isActive(character) then
			Zipline.stop(character)
		end
	end)
	pcall(function()
		if LedgeHang.isActive(character) then
			LedgeHang.stop(character, true)
		end
	end)
	pcall(function()
		if Grapple.isActive(character) then
			Grapple.stop(character)
		end
	end)
	pcall(function()
		if WallJump.isWallSliding(character) then
			WallJump.stopSlide(character)
		end
	end)
	pcall(function()
		if Fly.isActive(character) then
			Fly.stop(character)
		end
	end)
end

return ParkourWeaponGate
