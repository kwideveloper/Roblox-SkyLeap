-- Maps the local player's Humanoid + HRP into coarse locomotion phases for viewmodel layers.

local Config = require(script.Parent.Config)
local UserInputService = game:GetService("UserInputService")

export type LocomotionPhase = "Idle" | "Walk" | "Run" | "Air"

local ViewModelLocomotionSample = {}

local AIR_STATES = {
	[Enum.HumanoidStateType.Jumping] = true,
	[Enum.HumanoidStateType.Freefall] = true,
	[Enum.HumanoidStateType.Flying] = true,
}

function ViewModelLocomotionSample.fromPlayer(player: Player): LocomotionPhase
	local ch = player.Character
	if not ch then
		return "Idle"
	end
	local hum = ch:FindFirstChildOfClass("Humanoid")
	if not hum then
		return "Idle"
	end
	local hrp = hum.RootPart
	if not hrp then
		return "Idle"
	end

	local st = hum:GetState()
	if AIR_STATES[st] then
		return "Air"
	end

	local v = hrp.AssemblyLinearVelocity
	local horizontal = Vector3.new(v.X, 0, v.Z).Magnitude

	local idleByMoveDirection = Config.SniperViewModelAnimIdleUseMoveDirection
	if idleByMoveDirection == nil or idleByMoveDirection == true then
		local mdMax = Config.SniperViewModelAnimIdleMoveDirectionMax
		if mdMax == nil or type(mdMax) ~= "number" or mdMax < 0 then
			mdMax = 0.1
		end
		if hum.MoveDirection.Magnitude <= mdMax then
			return "Idle"
		end
	else
		local idleMax = Config.SniperViewModelAnimIdleSpeedMax or 0.35
		if horizontal < idleMax then
			return "Idle"
		end
	end

	local useShift = Config.SniperViewModelAnimRunUseShiftKey
	if useShift == nil or useShift == true then
		local shiftHeld =
			UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
		if shiftHeld then
			return "Run"
		end
		return "Walk"
	end

	local runThreshold = Config.SniperViewModelAnimRunSpeedThreshold or 14
	if horizontal >= runThreshold then
		return "Run"
	end
	return "Walk"
end

return ViewModelLocomotionSample
