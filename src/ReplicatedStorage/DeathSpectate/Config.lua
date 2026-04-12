-- Shared tuning for killer spectate after a sniper elimination (server delay + client camera).

return {
	Enabled = true,
	-- Modes that manage their own respawn / CharacterAutoLoads; do not hijack.
	SkipWhenBombTag = true,
	SkipWhenZombieTag = true,

	-- Camera: offset from killer Head along look/up (studs).
	EyeForwardStuds = 0.42,
	EyeUpStuds = 0.07,

	-- Phase durations (server respawn waits for the sum of all three).
	TransitionInSeconds = 0.34,
	SpectateHoldSeconds = 2,
	TransitionOutSeconds = 0.26,

	-- Out phase: pull camera back along killer look (studs) for a short cinematic ease-off.
	TransitionOutPullBackStuds = 1.35,

	-- Subtle FOV bump during hold (then restore on cleanup).
	FovHoldBonus = 6,

	-- Vignette (ScreenGui) max transparency during hold; 1 = invisible.
	VignetteMaxTransparency = 0.78,
}
