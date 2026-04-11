-- Maps the local player's Humanoid + HRP into coarse locomotion phases for viewmodel layers.

local Config = require(script.Parent.Config)

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
	if horizontal < (Config.SniperViewModelAnimIdleSpeedMax or 0.35) then
		return "Idle"
	end

	local runThreshold = Config.SniperViewModelAnimRunSpeedThreshold or 14
	if horizontal >= runThreshold then
		return "Run"
	end
	return "Walk"
end

return ViewModelLocomotionSample
