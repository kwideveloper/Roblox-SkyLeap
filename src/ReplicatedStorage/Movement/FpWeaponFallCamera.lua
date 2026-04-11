-- Shared check: first-person + weapon + falling — used to stabilize camera (no fall shake, neutral head IK).

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent.Config)
local ParkourWeaponGate = require(script.Parent.ParkourWeaponGate)

local SniperFirstPersonGate = (function()
	local ok, m = pcall(function()
		return require(ReplicatedStorage:WaitForChild("Sniper"):WaitForChild("SniperFirstPersonGate"))
	end)
	return ok and m or nil
end)()

local FpWeaponFallCamera = {}

function FpWeaponFallCamera.isFirstPersonEnough(player: Player): boolean
	if SniperFirstPersonGate and SniperFirstPersonGate.isCameraCloseForFirstPerson then
		return SniperFirstPersonGate.isCameraCloseForFirstPerson(player) == true
	end
	if player.CameraMode == Enum.CameraMode.LockFirstPerson then
		return true
	end
	local cam = Workspace.CurrentCamera
	if not cam then
		return false
	end
	local distance = (cam.Focus.Position - cam.CFrame.Position).Magnitude
	local strict = (player.CameraMinZoomDistance or 0.5) + 0.15
	return distance <= strict
end

function FpWeaponFallCamera.shouldStabilize(player: Player, character: Model?, humanoid: Humanoid?, root: BasePart?): boolean
	if Config.CameraStabilizeFpWeaponFallEnabled == false then
		return false
	end
	if not character or not humanoid or not root then
		return false
	end
	if not ParkourWeaponGate.isHoldingWeapon(character) then
		return false
	end
	if humanoid.FloorMaterial ~= Enum.Material.Air then
		return false
	end
	local vyThresh = Config.CameraStabilizeFpWeaponFallVyThreshold or -1
	if root.AssemblyLinearVelocity.Y >= vyThresh then
		return false
	end
	return FpWeaponFallCamera.isFirstPersonEnough(player)
end

return FpWeaponFallCamera
