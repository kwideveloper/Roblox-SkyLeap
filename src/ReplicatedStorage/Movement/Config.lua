-- Movement configuration constants for SkyLeap

local Config = {}

Config.LoadingScreenEnabled = false
Config.LoadingScreenDuration = 4
Config.PlaytimeDebugUI = false

-- Core humanoid speeds - OPTIMIZED FOR HIGH VELOCITY BUNNY HOP
-- Config.BaseWalkSpeed = 25 -- INCREASED: Better base speed for momentum building
-- Config.SprintWalkSpeed = 50 -- INCREASED: Higher sprint speed to complement bunny hop
Config.BaseWalkSpeed = 20 -- INCREASED: Better base speed for momentum building
Config.SprintWalkSpeed = 45 -- INCREASED: Higher sprint speed to complement bunny hop
-- Sprint acceleration ramp
Config.SprintAccelSeconds = 0.50 -- REDUCED: Faster acceleration for better responsiveness
Config.SprintDecelSeconds = 0.30 -- SLIGHTLY INCREASED: Smoother deceleration for better control

-- Landing roll
Config.MinRollDrop = 25

-- Stamina
Config.StaminaMax = 300 -- 200
Config.SprintDrainPerSecond = 20 -- 20
Config.StaminaRegenPerSecond = 80 -- 40
Config.SprintStartThreshold = 20 -- minimum stamina required to start sprinting
-- When false: no stamina costs, no stamina bar/costs in HUD; sprint is not limited by stamina.
-- Set true for modes that use stamina (BombTag infinite stamina still overrides when active).
-- Full guide: docs/CustomAttributesAndTags.md → section "Stamina system (global on/off)".
Config.StaminaEnabled = false

-- Momentum system - OPTIMIZED FOR VELOCITY MAINTENANCE
Config.MomentumIncreaseFactor = 0.12 -- INCREASED: Faster momentum buildup for bunny hop chains
Config.MomentumDecayPerSecond = 2.5 -- REDUCED: Slower decay to maintain velocity longer
Config.MomentumMax = 120 -- INCREASED: Higher momentum cap for sustained high speeds
Config.MomentumSuperJumpThreshold = 60 -- REDUCED: Earlier access to super jump for chaining
Config.MomentumAirDashThreshold = 40 -- REDUCED: Earlier access to air dash for better flow

-- Dash
Config.DashImpulse = 60
Config.DashCooldownSeconds = 0 -- 1.25
Config.DashStaminaCost = 20
Config.DashVfxDuration = 0.2
Config.DashDurationSeconds = 0.18 -- 0.18
Config.DashSpeed = 70

-- Double Jump
Config.DoubleJumpEnabled = true
Config.DoubleJumpMax = 1 -- extra jumps allowed while airborne
Config.DoubleJumpStaminaCost = 15
Config.DoubleJumpImpulse = 50 -- vertical speed applied on double jump

-- Air dash charges (per airtime)
Config.DashAirChargesDefault = 1
Config.DashAirChargesMax = 1
Config.GroundedRefillDwellSeconds = 0.01 -- time grounded before refilling dash/double jump (reduced for fast gameplay)
Config.GroundedRefillMinFallSpeed = 5 -- minimum downward velocity to qualify for fast reset (studs/s)
Config.GroundedRefillFastDwellSeconds = 0.01 -- fast reset time for legitimate falls

-- Slide
Config.SlideDurationSeconds = 0.5
-- Distance-based ground slide: total horizontal distance traveled over the slide duration
Config.SlideDistanceStuds = 10
-- Extra forward burst at the start of the slide (studs/s added, decays over SlideImpulseSeconds)
Config.SlideForwardImpulse = 60
Config.SlideImpulseSeconds = 0.15
Config.SlideSpeedBoost = 0
-- Slide input/requirements
Config.SlideRequireSprint = true -- only allow slide while sprinting
Config.SlideMinSpeedFractionOfSprint = 0.5 -- minimum speed fraction of sprint speed to start
-- Slide collider adjustments (kept subtle vs crawl)
Config.SlideColliderHeight = 1.4 -- reduced character collider height during slide
Config.SlideJointOffsetUp = 0.5 -- raise collider locally to avoid clipping the ground when compressed
-- Slide camera offset (lower view slightly during slide)
Config.SlideCameraOffsetY = -1.0
Config.SlideCameraLerpSeconds = 0.12
-- Jump carry from slide (percentages of current horizontal speed)
-- Example: if speed=50 and VerticalPercent=0.3 -> +15 studs/s vertical on jump frame
Config.SlideJumpVerticalPercent = 0.30 -- 0..1 fraction of horizontal speed added to vertical
Config.SlideJumpHorizontalPercent = 0.15 -- 0..1 fraction added to horizontal magnitude
Config.SlideFrictionMultiplier = 0.5
Config.SlideHipHeightDelta = 0 -- Keep character at normal height during slide
Config.SlideStaminaCost = 12
Config.SlideVfxDuration = 0.25
Config.SlideCooldownSeconds = 1 -- 1.0

-- Prone / Crawl
Config.ProneCameraOffsetY = -2.5
Config.CrawlCameraLerpSeconds = 0.12
Config.DebugProne = false
-- Crouch clearance probe (reduces false positives against front walls)
Config.CrawlStandProbeSideWidth = 0.8 -- studs, sideways width of clearance box
Config.CrawlStandProbeForwardDepth = 0.25 -- studs, forward depth of clearance box (keep small to ignore front walls)
-- Obstacle local-collision toggles during vault/mantle (safer default: don't modify obstacles)
Config.VaultDisableObstacleLocal = false
Config.MantleDisableObstacleLocal = false
-- Crawl geometry/speed
Config.CrawlRootHeight = 1 -- studs height for HumanoidRootPart while crawling
Config.CrawlSpeed = 10
Config.CrawlRunSpeed = 20
Config.CrawlStandUpHeight = 2
Config.CrawlAutoEnabled = true
Config.CrawlAutoSampleSeconds = 0.12
Config.CrawlAutoGroundOnly = true

-- First-person helper (show body when fully zoomed in)
-- Forward offset applied only at max zoom to bring view in front of the head
Config.FirstPersonForwardOffsetZ = -1.5 -- -1
-- If true, show whole body in FP; if false, show only distal limbs (hands/feet) to avoid clipping
Config.FirstPersonShowWholeBody = false

-- Camera dynamics (shake, FOV ramp, speed wind)
Config.CameraDynamicsEnabled = true
-- FOV
Config.CameraBaseFov = 70
Config.CameraMaxFov = 130
Config.CameraFovSpeedMin = 10 -- speed at which FOV starts ramping
Config.CameraFovSpeedMax = 180 -- speed at which FOV hits max
Config.CameraFovLerpPerSecond = 16 --6 -- smoothing speed towards target FOV
Config.CameraFovLerpUpPerSecond = 4 -- ramp up speed
Config.CameraFovLerpDownPerSecond = 12 -- faster decay back to base
Config.CameraFovUpDegPerSecond = 80 -- linear cap when increasing FOV (deg/s)
Config.CameraFovDownDegPerSecond = 220 -- linear cap when decreasing FOV (deg/s)
Config.CameraFovSprintBonus = 30 --6 -- extra degrees added while sprinting
Config.CameraFovMomentumWeight = 0.7 -- 0..1; higher gives more weight to momentum over raw speed
-- Shake
Config.CameraShakeEnabled = true
Config.CameraShakeAmplitudeMinDeg = 0.0
Config.CameraShakeAmplitudeMaxDeg = 1.0
Config.CameraShakeFrequencyHz = 7.0
Config.CameraShakeSprintMultiplier = 1.5
Config.CameraShakeAirborneMultiplier = 0.8
-- First-person strafe tilt: camera roll opposite to lateral movement (move left → tilt right). Only when camera is first person (same rule as sniper FP gate when available).
Config.CameraStrafeTiltEnabled = true
-- Config.CameraStrafeTiltMaxDegrees = 2.8
Config.CameraStrafeTiltMaxDegrees = 1.8
Config.CameraStrafeTiltLerpPerSecond = 12
Config.CameraStrafeTiltMoveDeadzone = 0.06 -- Humanoid.MoveDirection magnitude below this yields no tilt
-- First person + weapon + falling: disable procedural fall camera shake and head IK wobble (stable ADS-style view).
Config.CameraStabilizeFpWeaponFallEnabled = true
-- HRP velocity Y must be below this (negative = falling) to count as “cayendo”.
Config.CameraStabilizeFpWeaponFallVyThreshold = -1
-- While stabilized, also zero strafe-roll tilt so the view stays level.
Config.CameraStabilizeFpWeaponFallDisableStrafeTilt = true
-- Speed wind FX
Config.SpeedWindEnabled = true
Config.SpeedWindMinSpeed = 24 --24
Config.SpeedWindMaxSpeed = 85 --85
Config.SpeedWindRateMin = 6 --6
Config.SpeedWindRateMax = 500 --50
Config.SpeedWindLifetime = 0.15 --0.15
Config.SpeedWindOpacity = 0 --0.35
Config.SpeedWindSpreadX = 0.4 --0.4 -- lateral spread near camera
Config.SpeedWindSpreadY = 0.6 --0.6 -- vertical spread near camera
Config.SpeedWindAccelFactor = 28 -- how strongly particles accelerate backwards relative to camera facing

-- Wall run
-- Wall running configuration:
-- WallRunMaxDurationSeconds: Maximum time (in seconds) a player can wall run before being forced off.
Config.WallRunMaxDurationSeconds = 1.75
Config.WallRunMinSpeed = 25
-- WallRunSpeed: The speed at which the player moves while wall running.
Config.WallRunSpeed = 30
-- WallDetectionDistance: The distance (in studs) to check for a wall when attempting to start a wall run.
Config.WallDetectionDistance = 4

-- WallRunDownSpeed: The downward velocity applied to the player while wall running (controls how quickly they slide down).
Config.WallRunDownSpeed = 3

-- WallStickVelocity: The force applied to keep the player attached to the wall during a wall run.
Config.WallStickVelocity = 4

-- Wall hop (Space while wall running)
Config.WallHopForwardBoost = 18

-- Wall jump
-- Config.WallJumpImpulseUp = 110
-- Config.WallJumpImpulseAway = 160 -- 65
Config.WallJumpImpulseUp = 50
Config.WallJumpImpulseAway = 85 -- 65
Config.WallJumpCooldownSeconds = 0.2
Config.WallJumpStaminaCost = 14
Config.WallJumpCarryFactor = 1

-- Wall jump momentum preservation
Config.WallJumpPreserveMomentum = true -- Preserve horizontal momentum from wallrun
Config.WallJumpMomentumMultiplier = 0.8 -- Multiplier for preserved momentum (0.8 = 80% of original speed)
Config.WallJumpMinMomentumSpeed = 20 -- Minimum speed required to preserve momentum
Config.WallRunLockAfterWallJumpSeconds = 0
Config.AirControlUnlockAfterWallJumpSeconds = 0
-- Camera nudge assists
Config.CameraNudgeWallJumpSeconds = 0.2
Config.CameraNudgeWallJumpFraction = 0.45 -- 0..1 blend towards away direction
-- [Removed] Camera nudge during wall slide
-- Camera nudge after wall jump (subtle assist to show away direction)
Config.CameraNudgeWallJumpSeconds = 0.2
Config.CameraNudgeWallJumpFraction = 0.45 -- 0..1 blend towards away direction

-- Wall slide
Config.WallSlideFallSpeed = 5
Config.WallSlideStickVelocity = 4 -- 4
Config.WallSlideMaxDurationSeconds = 100 -- 100
Config.WallSlideDetectionDistance = 4 -- 4
Config.WallSlideGroundProximityStuds = 5 -- distance from feet to ground to exit slide
Config.WallSlideDrainPerSecond = Config.SprintDrainPerSecond * 0.5

-- Climb system
Config.ClimbEnabled = true
Config.ClimbDetectionDistance = 3.5 -- how far to detect climbable walls
Config.ClimbSpeed = 8 -- studs/s movement speed while climbing
Config.ClimbStickVelocity = 8 -- how strongly to stick to the wall
Config.ClimbMinStamina = 10 -- minimum stamina required to start climbing
Config.ClimbStaminaDrainPerSecond = 15 -- stamina drain rate while climbing
Config.ClimbMaxStamina = 100 -- maximum stamina for climbing
Config.DebugClimb = false -- verbose climb logs (ground checks, velocity, mantle gate)
-- Compact [Climb:trace] while climbing. Also on in Roblox Studio when ClimbTraceInStudio is true (default).
Config.ClimbTraceEnabled = false
Config.ClimbTraceInStudio = true
Config.ClimbTraceIntervalSeconds = 0.12
Config.ClimbForceGroundDetection = true -- force ground detection even when not moving (for testing auto-disable)
Config.ClimbGroundDetectionRaycastDistance = 5.0 -- distance to cast ray downward for ground detection
Config.ClimbFeetOffsetMultiplier = 0.5 -- multiplier for calculating feet position from character center (0.5 = half height)
Config.ClimbUseHumanoidHipHeight = true -- use Humanoid's HipHeight for more accurate feet position calculation
Config.ClimbGroundDetectionAggressive = true -- enable more aggressive ground detection for testing
Config.ClimbAlwaysCheckGround = true -- always check ground proximity regardless of input direction

-- Climb-Mantle Integration
Config.ClimbMantleIntegrationEnabled = true -- enable automatic climb state cleanup when mantle is executed
Config.ClimbLedgeEdgeDetectionDistance = 0.3 -- distance threshold to detect when climbing near a ledge edge (much more restrictive)
Config.ClimbLedgeEdgeHeightRange = { 0, 3 } -- height range (relative to player) to consider for ledge edge detection
Config.ClimbLedgeEdgeDetectionEnabled = true -- enable ledge edge detection during climb (set to false to completely disable)
Config.ClimbLedgeEdgeDetectionCompletelyDisabled = false -- set to true to completely bypass all ledge edge detection
Config.ClimbAutoDisableForMantle = true -- automatically disable climb when player is at correct distance for mantle
Config.ClimbLedgeEdgeMovementLimit = 0.3 -- limit upward movement when near ledge edge to prevent auto-mantle
Config.ClimbLedgeEdgeRestrictiveDistance = 0.2 -- very restrictive distance to avoid interfering with normal mantle detection
Config.ClimbLedgeEdgeMovementLimitEnabled = true -- enable limiting upward movement when near ledge edge
Config.ClimbLedgeEdgeMovementLimitThreshold = 0.15 -- distance threshold to start limiting movement (very restrictive)
-- Mantle handoff while climbing: detectLedgeForMantle can false-positive mid-wall (overlap fan, trims, CanQuery gaps).
-- Only allow climb->mantle / ledge-edge logic when HumanoidRootPart is near the *actual top* of the part being climbed.
Config.ClimbMantleRequireNearClimbedWallTop = true
Config.ClimbMantleMinClearanceBelowWallTop = -2 -- root may be this many studs above the wall top face and still count as "at top"
-- Wider window only for "near top" gating (ledge checks). Keep only slightly above lip max.
Config.ClimbMantleMaxClearanceBelowWallTop = 3.25
-- When generic mantle detection fails on Climbable-only walls (no Mantle=true), still run mantle at the lip using climb context.
Config.ClimbAutoMantleAtWallTop = true
-- wallTopY - rootY: only trigger climb-finish mantle inside this tight band (studs below top face)
Config.ClimbFinishMantleClearanceMin = -0.5
Config.ClimbFinishMantleClearanceMax = 1.35
-- If using ray ledge detect, ledge topY must match climbed part top within this (studs)
Config.ClimbFinishMantleTopYTolerance = 1.25

Config.ClimbGroundProximityCheck = true -- enable checking if player is too close to ground during climb
Config.ClimbMinGroundDistance = 2.0 -- minimum distance from ground to allow climbing
Config.ClimbAutoGroundAdjust = true -- automatically adjust player position when starting climb from ground
Config.ClimbAutoGroundAdjustHeight = 2.5 -- height above ground to position player when auto-adjusting
Config.ClimbAutoGroundAdjustAlways = true -- if true, always auto-adjust when on ground, regardless of distance to wall
Config.ClimbAutoDisableImmediateAfterAdjust = false -- if true, auto-disable works immediately after auto-adjustment
Config.ClimbSpaceExecutesWallJump = true -- if true, Space during climb executes walljump directly instead of climb hop
Config.ClimbWallJumpStaminaCost = 0 -- stamina cost for walljump when executed from climb (0 = no cost)
Config.ClimbWallJumpDelay = 0.1 -- delay in seconds between walljump execution and climb deactivation
Config.ClimbWallJumpImmediate = true -- if true, walljump executes immediately without delay
Config.ClimbAutoDisableAtGround = true -- automatically disable climb when player is 1.5 studs from ground
Config.ClimbAutoDisableGroundThreshold = 3.5 -- distance from ground to auto-disable climb (increased from 1.5)
Config.ClimbAutoDisableOnlyWhenDescending = false -- if true, only auto-disable when manually descending (v < 0)
Config.ClimbGroundMovementLimit = 0.2 -- limit downward movement when too close to ground
Config.ClimbGroundNormalThreshold = 0.7 -- threshold for considering a surface as ground (dot product with up vector)
Config.ClimbGroundExcludeClimbingWall = true -- exclude the climbing wall from ground detection
Config.ClimbGroundCheckOnlyWhenDescending = true -- only check ground proximity when moving downward (more efficient)

-- Climb animation speeds (in seconds per animation cycle)
Config.ClimbAnimationSpeed = {
	ClimbUp = 0.5, -- Duration for upward climbing animation
	ClimbDown = 1.0, -- Duration for downward climbing animation
	ClimbLeft = 1.0, -- Duration for left climbing animation
	ClimbRight = 1.0, -- Duration for right climbing animation
	ClimbIdle = 2.0, -- Duration for idle climbing animation
	Default = 1.0, -- Default duration for ClimbLoop if not configured
}

-- Vertical Climb animation speed (in seconds per animation cycle)
Config.VerticalClimbAnimationSpeed = 0.25 -- Duration for vertical climb animation (matches VerticalClimbDurationSeconds)

-- Air animation speeds (in seconds per animation cycle)
Config.AirAnimationSpeed = {
	Jump = 1.0, -- Duration for jump animation
	Fall = 1.0, -- Duration for fall animation
	Rise = 1.0, -- Duration for rise animation
	Default = 1.0, -- Default duration for air animations
}

-- Raycast
Config.RaycastIgnoreWater = true
-- Surface verticality filter (dot with world up): allow only near-vertical walls for wall mechanics
Config.SurfaceVerticalDotMin = 1 -- legacy; prefer SurfaceVerticalDotMax below
-- Use SurfaceVerticalDotMax for acceptance threshold. Lower means stricter vertical (e.g., 0.1 ≈ within ~6°).
Config.SurfaceVerticalDotMax = 0.1

-- Air jump (while falling, no wall): upward and forward boosts
Config.AirJumpImpulseUp = 50
Config.AirJumpForwardBoost = 20

-- Zipline
Config.ZiplineSpeed = 45
Config.ZiplineDetectionDistance = 7
Config.ZiplineStickVelocity = 6
Config.ZiplineEndDetachDistance = 2
-- Zipline Tag System
Config.ZiplineTagName = "Zipline" -- Tag name used to identify zipline objects
Config.ZiplineAutoInitialize = true -- Whether to automatically create RopeConstraints for tagged objects

-- Hook / Grapple animation durations (in seconds - EXACT duration the animation will play)
-- The system automatically calculates SpeedMultiplier = OriginalDuration / TargetDuration
-- Example: If animation is 2 seconds and you want 5 seconds, SpeedMultiplier = 2/5 = 0.4 (slower)
-- Example: If animation is 2 seconds and you want 0.5 seconds, SpeedMultiplier = 2/0.5 = 4.0 (faster)
-- IMPORTANT: Uses Play() first, then AdjustSpeed() for reliable speed control
Config.HookStartDurationSeconds = 0.5 -- EXACT duration for hook start animation (grabbing the hook)
Config.HookFinishDurationSeconds = 0.35 -- EXACT duration for hook finish animation (releasing/jumping off)

-- Zipline animation durations (in seconds - EXACT duration the animation will play)
-- Same system: SpeedMultiplier = OriginalDuration / TargetDuration
-- IMPORTANT: Uses Play() with speed parameters for reliable speed control
Config.ZiplineStartDurationSeconds = 0.5 -- EXACT duration for zipline start animation (grabbing the line)
Config.ZiplineEndDurationSeconds = 0.35 -- EXACT duration for zipline end animation (releasing/jumping off)

-- Camera alignment (body yaw + head tracking)
Config.CameraAlignEnabled = false
Config.CameraAlignBodyLerpAlpha = 0.25 -- 0..1 per frame smoothing for body yaw
Config.CameraAlignHeadEnabled = true
Config.CameraAlignHeadYawDeg = 60
Config.CameraAlignHeadPitchDeg = 30
Config.CameraAlignBodyYawDeg = 45

-- Bunny hop (OPTIMIZED FOR HIGH VELOCITY GAINS)
Config.BunnyHopWindowSeconds = 0.18 -- INCREASED: More forgiving timing window for better responsiveness
Config.BunnyHopMaxStacks = 5 -- INCREASED: More stacking potential for longer chains
Config.BunnyHopBaseBoost = 4 -- BALANCED: Good initial boost without being overwhelming
Config.BunnyHopPerStackBoost = 3 -- BALANCED: Steady progression per stack for smooth acceleration to cap
Config.BunnyHopMomentumBonusBase = 6 -- INCREASED: More momentum gain for sustained speed
Config.BunnyHopMomentumBonusPerStack = 5 -- INCREASED: Better momentum scaling for velocity maintenance
Config.BunnyHopDirectionCarry = 0.4 -- INCREASED: Preserve more lateral momentum for better flow
Config.BunnyHopOppositeCancel = 0.6 -- REDUCED: Less cancellation to maintain more speed
Config.BunnyHopPerpDampOnFlip = 0.5 -- REDUCED: Preserve even more perpendicular momentum
-- Hard reorientation on hop: completely retarget horizontal velocity to desired direction, preserving magnitude
Config.BunnyHopReorientHard = false
Config.BunnyHopLockSeconds = 0.1 -- REDUCED: Even shorter lock for maximum fluidity
Config.BunnyHopMaxAddPerHop = 12 -- INCREASED: Much higher speed gain per hop for constant velocity buildup
Config.BunnyHopTotalSpeedCap = 90 -- BALANCED: Sweet spot for exciting but controlled bunny hop gameplay
-- NEW: Sprint requirement settings
Config.BunnyHopRequireSprint = false -- Allow bunny hop without sprinting for casual use
Config.BunnyHopSprintBonus = 1.3 -- BALANCED: Good sprint bonus without being too powerful

-- Air control (Quake/CS-style) - OPTIMIZED FOR BUNNY HOP VELOCITY MAINTENANCE
Config.AirControlEnabled = true
Config.AirControlUseCameraFacing = true -- when no MoveDirection, use camera facing
Config.AirControlAccelerate = 40 -- INCREASED: Better acceleration for velocity maintenance
Config.AirStrafeAccelerate = 180 -- BALANCED: Good strafe acceleration without being too aggressive
Config.AirControlMaxWishSpeed = 45 -- BALANCED: Good speed contribution without overwhelming acceleration
Config.AirControlMaxAddPerTick = 20 -- BALANCED: Reasonable safety cap for controlled acceleration
Config.AirControlTotalSpeedCap = 90 -- BALANCED: Match bunny hop cap for consistent controlled gameplay

-- LaunchPad (trampoline) defaults
Config.LaunchPadUpSpeed = 80
Config.LaunchPadForwardSpeed = 0
Config.LaunchPadCarryFactor = 1 -- 0..1 how much of current velocity to preserve
Config.LaunchPadCooldownSeconds = 0 -- 0.35
Config.LaunchPadMinUpLift = 0 -- 12  -- ensures detachment from ground even on forward pads
-- If true, interpret UpSpeed/ForwardSpeed as distances (studs). We'll convert to velocities.
Config.LaunchPadDistanceMode = false
Config.LaunchPadMinFlightTime = 0.25 -- seconds for forward travel conversion
-- Default flight time when UpSpeed==0 to map ForwardSpeed to exact distance
Config.LaunchPadDefaultForwardFlightTime = 1.0 -- seconds

-- Style / Combo system
Config.StyleEnabled = true
Config.StylePerSecondBase = 5
Config.StyleSpeedFactor = 0.12
Config.StyleSpeedThreshold = 18
Config.StyleAirTimePerSecond = 6
Config.StyleWallRunPerSecond = 10 -- per-second scoring aligns with Wallrun: 10 points
Config.StyleWallRunEventBonus = 10 -- on start of a wallrun, as a discrete action
Config.StyleBreakTimeoutSeconds = 3.0 -- break combo if no valid action in this time
Config.StyleMultiplierStep = 0.10 -- x1.1, x1.2, etc.
Config.StyleMultiplierMax = 5.0
-- Action bonuses
Config.StyleBunnyHopBonusBase = 5 -- per jump
Config.StyleBunnyHopBonusPerStack = 5
Config.StyleDashBonus = 8 -- counts only when chained
Config.StyleDoubleJumpBonus = 12 -- counts only when chained
Config.StyleWallJumpBonus = 15
Config.StyleWallSlideBonus = 10 -- counts only when chained
Config.StylePadChainBonus = 5 -- counts only when chained
Config.StyleVaultBonus = 12
Config.StyleGroundSlideBonus = 8
Config.StyleLedgeJumpBonus = 15 -- bonus for directional jumps from ledge hang (A/D/W/S + Space)
-- Combo/variety rules
Config.ComboChainWindowSeconds = 3.0 -- window to chain dependent actions (dash, pad, wallslide, zipline)
Config.StyleRepeatLimit = 3 -- identical consecutive actions beyond this won't bump combo
Config.StyleVarietyWindow = 6 -- last N actions to consider for variety
Config.StyleVarietyDistinctThreshold = 4 -- distinct actions in window to grant bonus
Config.StyleCreativityBonus = 20
-- WallJump streak scaling (more points for fast consecutive walljumps, combo still +1 each)
Config.StyleWallJumpChainWindowSeconds = 0.6
Config.StyleWallJumpStreakBonusPer = 4
Config.StyleWallJumpStreakMaxBonus = 20
Config.StyleRequireSprint = true
Config.StyleCommitInactivitySeconds = 3.0
-- Anti-abuse: max consecutive chain actions on the same wall surface before requiring variety
Config.MaxWallChainPerSurface = 3
Config.StyleComboPopupWindowSeconds = 0.2 -- time to aggregate combo increases into a single popup

-- Wall jump control gating
Config.WallJumpAirControlSuppressSeconds = 1.0

-- Vault (parkour over low obstacles)
Config.VaultEnabled = true
Config.VaultDetectionDistance = 4.5
Config.VaultMinHeight = 2 -- studs above feet
Config.VaultMaxHeight = 5 -- studs above feet
Config.VaultMinSpeed = 24 -- require decent speed (sprinting)
Config.VaultUpBoost = 0
Config.VaultForwardBoost = 40 -- base minimum forward speed to ensure clearance
Config.VaultDurationSeconds = 0.25 --0.18 -- shorter for snappier feel
Config.VaultPreserveSpeed = false -- preserve current horizontal speed if higher than base
Config.VaultCooldownSeconds = 0.6
-- Vault Animation System Configuration
-- Enable/disable random vault animation selection (Premium Feature)
Config.VaultRandomAnimationsEnabled = true -- Set to false to disable random selection (Premium Feature)
-- Available vault animations for random selection
Config.VaultAnimationKeys = { "Vault_Speed", "Vault_Monkey", "Vault_1_Hand", "Front_Flip", "Jump_Over" }
-- Config.VaultAnimationKeys = { "Jump_Over" }
-- Fallback animation if random selection is disabled or fails
Config.VaultFallbackAnimation = "Vault_Speed"

-- Vault Animation Duration Control
Config.VaultAnimationDuration = 0.8 -- Target duration for vault animations to complete (seconds)
Config.VaultAnimationSpeedOverride = true -- If true, override animation speed to match target duration
Config.VaultAnimationMinSpeed = 0 -- Minimum animation speed multiplier (prevents too slow playback)
Config.VaultAnimationMaxSpeed = 3.0 -- Maximum animation speed multiplier (prevents too fast playback)
Config.VaultAnimationIndependentDuration = true -- If true, animation completes independently of vault physics duration

-- Custom duration for specific vault animations (optional)
-- If not specified, uses Config.VaultAnimationDuration
Config.VaultAnimationCustomDurations = {
	-- ["AnimationName"] = duration_in_seconds,
	Vault_Monkey = 0.45, -- Standard monkey vault
	Vault_1_Hand = 0.45, -- Slower one-hand vault
	Front_Flip = 0.5, -- Longer flip animation
	Jump_Over = 0.5, -- Medium jump over
	-- Add more as needed...
}

Config.DebugVault = false
-- Dynamic vault clearance: how many studs above obstacle top we aim to pass
Config.VaultClearanceStuds = 1.5
-- Heights (fractions of root height) to probe obstacle front for estimating top
Config.VaultSampleHeights = { 0.2, 0.4, 0.6, 0.85 }
-- Forward-biased vault tuning
Config.VaultForwardGainPerHeight = 2.5 -- extra forward speed per stud of obstacle height
Config.VaultUpMin = 8
Config.VaultUpMax = 26

-- Ledge Hanging (when mantle fails due to insufficient clearance)
Config.LedgeHangEnabled = true
Config.DebugLedgeHang = false
Config.MantleLedgeHangCooldown = 0.25 -- seconds to wait after successful mantle before allowing ledge hang
Config.LedgeHangCooldown = 0.5 -- seconds to wait after ledge hang before allowing another hang
Config.LedgeHangDetectionDistance = 2 -- max distance to detect ledge
Config.LedgeHangMinHeight = 1.5 -- min height above waist for hang
Config.LedgeHangMaxHeight = 4.0 -- max height above waist for hang
Config.LedgeHangMinClearance = 5.0 -- min clearance above ledge required to mantle instead of hang (character height + headroom)
Config.LedgeHangDistance = 1.4 -- horizontal distance from wall while hanging
Config.LedgeHangDropDistance = 1.5 -- how far below ledge to hang
Config.LedgeHangMoveSpeed = 15 -- horizontal movement speed while hanging (studs/s)
-- Ignore tiny A/D input so MoveDirection flicker does not swap loop/move animations every frame
Config.LedgeHangMoveInputDeadzone = 0.12
Config.LedgeHangStaminaCost = 5 -- initial stamina cost to start hanging
Config.LedgeHangStaminaDrainPerSecond = 5 -- stamina cost per second while hanging
Config.LedgeHangMinStamina = 10 -- Minimum stamina required to start a ledge hang
Config.LedgeHangStaminaDepletionCooldown = 1.0 -- Cooldown after stamina depletion before allowing auto hang again

-- Ledge Hang Jump impulses
Config.LedgeHangJumpUpForce = 80 -- vertical impulse when pressing W + Space
Config.LedgeHangJumpSideForce = 80 -- horizontal impulse when pressing A/D + Space (increased for side momentum)
Config.LedgeHangJumpBackForce = 100 -- backward impulse when pressing S + Space
Config.LedgeHangJumpStaminaCost = 10 -- stamina cost for directional jumps
Config.LedgeHangWallSeparationForce = 0 -- force to push away from wall during jumps

-- Wall slide suppression after leaving ledge (manual release)
Config.WallSlideSuppressAfterLedgeReleaseSeconds = 0.25 -- time to disable wallslide after pressing C to release

-- Animation Duration Control
Config.LedgeHangStartAnimationDuration = 0.5 -- seconds for LedgeHangStart animation to complete
Config.LedgeHangUpAnimationDuration = 0.25 -- seconds for LedgeHangUp animation to complete
Config.LedgeHangLeftAnimationDuration = 1 -- seconds for LedgeHangLeft animation to complete (optional)
Config.LedgeHangRightAnimationDuration = 1 -- seconds for LedgeHangRight animation to complete (optional)

-- Ledge Hang IK (Inverse Kinematics) for hand positioning
Config.LedgeHangIKEnabled = true -- enable/disable hand IK during ledge hang
Config.LedgeHangIKWeight = 0.5 -- --1 IK weight (0.0 to 1.0, higher = stronger positioning)
Config.LedgeHangIKHandOffset = 0.8 -- 0.6 -- distance between hands (studs)
Config.LedgeHangIKHeightOffset = 1 -- 0.02 -- how much above ledge surface to place hands
Config.LedgeHangIKBackOffset = 0.1 -- how far back from edge to place hands
-- Retarget authored vault (3 studs) to any obstacle height
Config.VaultCanonicalHeightStuds = 3.0
Config.VaultAlignBlendSeconds = 0.06
Config.VaultAlignHoldSeconds = 0.0
Config.VaultUseGroundHeight = true -- if true, measure obstacle height from ground under player instead of HRP feet

-- Tagged Ledge Auto-Hang
Config.LedgeTagAutoEnabled = true -- auto-detect tagged ledges nearby
Config.LedgeTagName = "Ledge" -- CollectionService tag name
-- How far from the ledge part's bounding box the player can be and still be considered (coarse filter)
Config.LedgeTagAutoHangRange = 3 -- studs: horizontal half-extent (X/Z) expanded around the part
-- Vertical half-extent above/below the part (tighter than before for less “magnetic” vertical grab)
Config.LedgeTagAutoVerticalRange = 5 -- studs
-- Max 3D distance HRP → part AABB (slightly below old 6.5 so vertical approaches are a bit stricter)
Config.LedgeTagAutoMaxSurfaceDistance = 5.5
Config.LedgeTagFaceLateralMargin = 0.75 -- lateral slack on the orthogonal axis when selecting outward face

-- Ledge-to-Ledge chaining (jump up to catch the next ledge above)
Config.LedgeHangChainEnabled = true
Config.LedgeHangChainMaxUpSearch = 6.0 -- how far above current ledge to search (studs)
Config.LedgeHangChainMaxHorizontal = 1.5 -- allowed horizontal offset from current wall alignment
Config.LedgeHangChainNormalDotMin = 0.8 -- require new ledge surface normal to match current wall direction
-- Up-ray often hits the bottom of the upper part (normal ~ vertical); use hang surface normal instead
Config.LedgeHangChainUndersideNormalThreshold = 0.85 -- if abs(hit.Normal.Y) >= this, treat as shelf underside
-- After W+Space ledge jump, short global gate (upper ledge can still be a different Instance)
Config.LedgeHangUpJumpGlobalCooldown = 0.14
-- After any directional jump off a hang, block re-attaching to that same ledge part (auto-hang spam)
Config.LedgeHangSameLedgeRehangCooldownAfterJump = 0.5
Config.VaultApproachSpeedMin = 6
Config.VaultFacingDotMin = 0.35
Config.VaultApproachDotMin = 0.35
Config.VaultForwardUseHeight = false -- if true, adds VaultForwardGainPerHeight * needUp to forward speed; else constant boost

-- Mantle (ledge grab over medium obstacles)
Config.MantleEnabled = true
Config.MantleDetectionDistance = 4 -- 4.5 -- forward ray distance to detect a ledge
-- Height window relative to root (waist): if obstacle top is within [min, max], allow mantle
Config.MantleMinAboveWaist = 1 -- 0
Config.MantleMaxAboveWaist = 10
Config.MantleAboveWaistWhileClimbing = 6
Config.MantleForwardOffset = 0.5 -- 1.2 -- how far onto the platform to place the character
Config.MantleUpClearance = 1.5 -- 1.5 -- extra vertical clearance above top to ensure space
Config.MantleDurationSeconds = 0.35 -- 0.22 -- baseline; may be overridden by preserve-speed
Config.MantlePreserveSpeed = true
Config.MantleMinHorizontalSpeed = 24 -- studs/s floor while mantling
Config.MantleCooldownSeconds = 0.35
-- Blocks ParkourController auto-mantle right after climb ends (avoids race with climb-finish + false ledge mid-wall)
Config.MantleSuppressAfterClimbSeconds = 0.55
Config.MantleStaminaCost = 10
-- Mantle approach gating: require facing and velocity towards wall
Config.MantleApproachSpeedMin = 6 -- min horizontal speed towards wall to allow mantle
Config.MantleFacingDotMin = 0.35 -- dot(root forward, towards-wall) >= this
Config.MantleApproachDotMin = 0.35 -- dot(velocity, towards-wall) >= this
Config.MantleWallSlideSuppressSeconds = 0.6 -- extra window after mantle to suppress wall slide
Config.MantleGroundedConfirmSeconds = 1 -- require being grounded this long before re-enabling wall slide
Config.MantleUseMoveDirFallback = true
Config.MantleSpeedRelaxDot = 0.9
Config.MantleSpeedRelaxFactor = 0.4

-- Grapple / Hook
Config.GrappleEnabled = true
Config.GrappleMaxDistance = 120
Config.GrapplePullForce = 6000
Config.GrappleReelSpeed = 28
Config.GrappleRopeVisible = true
Config.GrappleRopeThickness = 0.06
-- Hook targeting
Config.HookTag = "Hookable"
Config.HookDefaultRange = 90 -- studs radius from hookable center where hook can be used (default)
Config.HookCooldownSeconds = 5.5
-- Hook approach controls
Config.HookMaxApproachSpeed = 120 -- studs/s clamp for approach speed (default)
Config.HookAutoDetachDistance = 30 -- studs from target to auto-detach (default)
-- Hook line-of-sight controls
Config.HookRequireLineOfSight = true -- require clear LOS to the hookable target
Config.HookIgnoreTag = "HookIgnoreLOS" -- parts/models with this tag will be ignored for Line Of Sight (LOS) blocking
-- Hook labels / logging
Config.HookCooldownLabels = true -- show user-facing per-hookable cooldown labels (client-side)
Config.DebugHookCooldownLogs = false -- print cooldown debug logs to the output
Config.DebugRaycast = false -- enable debug prints for raycast system (DISABLED - causes lag)

-- Vertical wall climb (sprint into wall to climb up briefly)
Config.VerticalClimbEnabled = true
Config.VerticalClimbDetectionDistance = 4
Config.VerticalClimbMinSpeed = 18
Config.VerticalClimbUpSpeed = 26
Config.VerticalClimbStickVelocity = 6
Config.VerticalClimbDurationSeconds = 0.45
Config.VerticalClimbCooldownSeconds = 0.6 -- 0.6

-- Trails
Config.TrailEnabled = true
Config.TrailBodyPartName = "UpperTorso" -- fallback to "Torso" then HRP
Config.TrailAttachmentNameA = "TrailA"
Config.TrailAttachmentNameB = "TrailB"
Config.TrailBaseTransparency = 0.3
Config.TrailMinTransparency = 0.2
-- Config.TrailLifeTime = 0.30 -- 0.25
Config.TrailLifeTime = 0.8 -- 0.8
Config.TrailWidth = 0.35 -- 0.3
Config.TrailSpeedMin = 10 -- 10
Config.TrailSpeedMax = 80 -- 80

-- Hand trails
Config.TrailHandsEnabled = true
Config.TrailHandsScale = 0.6 -- width/transparency scaling relative to main trail
Config.TrailHandsLifetimeFactor = 0.8 -- 0.5 lifetime relative to main trail
Config.TrailHandsSizeFactor = 2.15 -- extra width factor vs main-scaled width

-- Trail particles configuration
Config.TrailParticlesEnabled = true
Config.TrailParticlesTexture = "rbxassetid://130950887223800" -- Default particle texture
Config.TrailParticlesLifetime = 1.5
Config.TrailParticlesRate = 4
Config.TrailParticlesEmissionDirection = "Front"
Config.TrailParticlesSpeedMin = 8 -- Minimum speed to start emitting particles
Config.TrailParticlesSizeMin = 0.8 -- Minimum particle size
Config.TrailParticlesSizeMax = 1.5 -- Maximum particle size
Config.TrailParticlesTransparencyStart = 0 -- Starting transparency (0 = fully visible)
Config.TrailParticlesTransparencyMid = 0.2 -- Mid-life transparency
Config.TrailParticlesTransparencyEnd = 0.5 -- End transparency (1 = fully transparent)

-- Debug flags
Config.DebugLaunchPad = false
Config.DebugLandingRoll = false

-- Powerups Configuration
-- Default values for powerup effects when no attributes are specified
Config.PowerupStaminaPercentDefault = 25 -- percentage of max stamina to restore
Config.PowerupJumpCountDefault = 1 -- number of jumps to restore (only if player doesn't have double jump)
Config.PowerupDashCountDefault = 1 -- number of dashes to restore (only if player doesn't have dash)
Config.PowerupCooldownSecondsDefault = 2 -- default cooldown time in seconds for all powerups

-- Speed Wind Lines Configuration (visual feedback when moving fast)
-- Enable/disable the wind lines effect completely
Config.SpeedWindLinesEnabled = true

-- Speed thresholds for wind effect activation
Config.SpeedWindLinesMinSpeed = 18 -- minimum speed to start showing wind lines
Config.SpeedWindLinesMaxSpeed = 80 -- speed at which wind effect reaches maximum intensity

-- Spawn rate controls (how many wind lines appear per second)
Config.SpeedWindLinesRateMin = 12 -- wind lines per second at minimum speed
Config.SpeedWindLinesRateMax = 35 -- wind lines per second at maximum speed

-- Visual appearance of wind lines
Config.SpeedWindLinesColor = Color3.new(0.7, 0.8, 1) -- light blue-white color
Config.SpeedWindLinesOpacityStart = 0 -- transparency at spawn (0=visible, 1=invisible)
Config.SpeedWindLinesOpacityEnd = 1.0 -- transparency when fading out

-- Wind line size/width scaling
Config.SpeedWindLinesWidthStart = 0.8 -- width at the ends of the trail
Config.SpeedWindLinesWidthMiddle = 3.2 -- width at the middle of the trail (thickest part)

-- Wind line length and lifetime
Config.SpeedWindLinesLengthBase = 18 -- base trail length in studs
Config.SpeedWindLinesLengthSpeedFactor = 0.25 -- extra length per speed unit
Config.SpeedWindLinesLengthMin = 20 -- minimum trail length
Config.SpeedWindLinesLengthMax = 35 -- maximum trail length
Config.SpeedWindLinesLifetimeMin = 0.2 --0.8 -- minimum time each wind line lives (seconds)
Config.SpeedWindLinesLifetimeMax = 0.5 --1.3 -- maximum time each wind line lives (seconds)

-- Spawn positioning around camera
Config.SpeedWindLinesSpawnDistanceMin = 20 --20 -- closest spawn distance from camera (increased for better visibility)
Config.SpeedWindLinesSpawnDistanceMax = 35 --45 -- farthest spawn distance from camera (increased for better visibility)
Config.SpeedWindLinesSpawnAngleX = 35 --35 -- maximum angle up/down from camera center (degrees)
Config.SpeedWindLinesSpawnAngleY = 50 --50 -- maximum angle left/right from camera center (degrees)
Config.SpeedWindLinesSpawnForwardOffset = 30 --15 -- additional forward distance from camera (pushes lines further ahead)

-- Movement physics of wind lines
Config.SpeedWindLinesSpeedFactor = 0.3 -- how fast wind lines move relative to player speed
Config.SpeedWindLinesSpeedVariation = 0.2 -- random speed variation (0.2 = ±20%)

-- Wave motion for natural wind movement
Config.SpeedWindLinesWaveAmplitudeX = 1.0 -- horizontal wave strength
Config.SpeedWindLinesWaveAmplitudeY = 1.5 -- vertical wave strength
Config.SpeedWindLinesWaveAmplitudeZ = 0.8 -- depth wave strength
Config.SpeedWindLinesWaveSpeed = 0.15 -- how fast the wave motion changes

Config.DashAllowedDuringClimb = false -- prevent dash execution while climbing
Config.DashAllowedDuringZipline = false -- prevent dash execution while ziplining
Config.DashAllowedDuringVault = false -- prevent dash execution while vaulting
Config.DashAllowedDuringMantle = false -- prevent dash execution while mantling
Config.DebugDash = false -- enable debug prints for dash system

-- Parkour surfaces: true = opt-in (default OFF). Use EnableAll = true on a model/part or set each mechanic = true.
--   LedgeHang is special: auto hang at edges without standing room still works without tags (block with LedgeHang = false).
-- false = legacy: parkour allowed unless a mechanic is explicitly false on the surface chain.
Config.ParkourOptInSurfaces = true

-- One-shot FX / fly debug (ParkourController.client)
Config.DebugFX = false
Config.DebugFly = false

-- Player profile persistence pacing (ServerScriptService.PlayerProfile)
Config.PlayerProfileSaveIntervalSeconds = 30
Config.PlayerProfileCriticalSaveThreshold = 5000

return Config
