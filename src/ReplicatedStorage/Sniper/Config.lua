-- Shared sniper / laser rifle configuration (server + client read the same table)

return {
	ToolName = "Sniper",

	-- BasePart name for hitscan / laser / trail origin (world position). Put this at the bore exit on the Tool AND on the viewmodel clone.
	-- Typical names: "Barrel", "FirePoint", "Tip". Must match exactly on both assets.
	FireOriginPartName = "Barrel",

	-- BasePart name for smoke VFX only (can sit slightly forward of the bore). Tool + viewmodel clone.
	SniperMuzzleSmokePartName = "Muzzle",

	-- Summary — three different attachments (all BaseParts, same names on Tool + viewmodel where used):
	--   FireOriginPartName      → bullet / hitscan / laser trail start (bore), NOT the casing.
	--   SniperMuzzleSmokePartName → muzzle VFX anchor (flash + heat wisps).
	--   CasingEjectPartName     → shell model spawn; velocity uses this part's Right/Up/Look (see casing block).

	-- Muzzle VFX at SniperMuzzleSmokePartName: muzzle flash burst, then rising heat wisps (match / hot metal style).
	SniperMuzzleSmokeEnabled = true,
	-- Phase 1 — fogonazo (bright sparks + point light pulse).
	SniperMuzzleFlashEmitCount = 28,
	SniperMuzzleFlashLifetimeMin = 0.055,
	SniperMuzzleFlashLifetimeMax = 0.13,
	SniperMuzzleFlashSpeedMin = 14,
	SniperMuzzleFlashSpeedMax = 36,
	SniperMuzzleFlashSpreadAngle = 88,
	SniperMuzzleFlashSize0 = 0.24,
	SniperMuzzleFlashSize1 = 0.62,
	SniperMuzzleFlashLightBrightness = 15,
	SniperMuzzleFlashLightRange = 12,
	SniperMuzzleFlashLightTweenSeconds = 0.12,
	SniperMuzzleFlashLightColor = Color3.fromRGB(255, 228, 190),
	-- Orange fire core inside the flash (larger = bigger muzzle detonation read).
	SniperMuzzleFireCoreLifetimeMin = 0.045,
	SniperMuzzleFireCoreLifetimeMax = 0.115,
	SniperMuzzleFireCoreSpreadAngle = 72,
	SniperMuzzleFireCoreSize0 = 0.52,
	SniperMuzzleFireCoreSize1 = 1.05,
	SniperMuzzleFireCoreSpeedMin = -38,
	SniperMuzzleFireCoreSpeedMax = -14,
	-- Phase 2 — heat trail (starts shortly after flash; drifts upward in world space).
	SniperMuzzleHeatDelaySeconds = 0.038,
	SniperMuzzleHeatEmitCount = 26,
	SniperMuzzleHeatLifetimeMin = 0.78,
	SniperMuzzleHeatLifetimeMax = 1.28,
	SniperMuzzleHeatSpeedMin = 0.32,
	SniperMuzzleHeatSpeedMax = 1.45,
	SniperMuzzleHeatSpreadAngle = 30,
	SniperMuzzleHeatDrag = 5.2,
	SniperMuzzleHeatAccelY = 4.25,
	SniperMuzzleHeatLightEmission = 0.16,
	SniperMuzzleHeatSize0 = 0.07,
	SniperMuzzleHeatSize1 = 0.26,
	SniperMuzzleHeatSize2 = 0.72,
	SniperMuzzleHeatColorHot = Color3.fromRGB(255, 235, 210),
	SniperMuzzleHeatColorMid = Color3.fromRGB(200, 195, 188),
	SniperMuzzleHeatColorCool = Color3.fromRGB(140, 138, 145),
	-- After the burst: soft smoke Rate from the Muzzle Attachment for this long (only when Muzzle BasePart exists; moves with the gun).
	SniperMuzzleHeatLingerEnabled = true,
	SniperMuzzleHeatLingerSeconds = 1.65,
	SniperMuzzleHeatLingerRate = 8,

	-- First-person viewmodel (client). Template: ReplicatedStorage.[ViewModelsFolderName].[SniperViewModelName] (Model; keep ViewModels as Studio assets only, no scripts).
	-- Shown when Sniper is equipped and camera orbit distance is small (strict min-zoom OR below MaxOrbitDistance).
	SniperViewModelEnabled = true,
	ViewModelsFolderName = "ViewModels",
	SniperViewModelName = "Sniper",
	-- Camera position–focus distance (studs): above strict first-person but still “close” zoom. Increase if the gun never appears.
	SniperViewModelMaxOrbitDistance = 8,
	-- Pivot in camera space: X right, Y up, Z along look direction. Multiply with CFrame.Angles(...) to roll/pitch the rifle.
	SniperViewModelCameraCFrame = CFrame.new(0.12, -0.22, -0.78),
	SniperViewModelCastShadow = false,
	-- Mouse ray (Mouse.Target / Hit) ignores the viewmodel clone so parts under the camera do not steal hover / “selection” cursor.
	SniperViewModelSetMouseTargetFilter = true,
	-- Remove ClickDetectors, ProximityPrompts, DragDetectors from the clone; set CanTouch = false on parts.
	SniperViewModelStripWorldInteractables = true,

	-- Viewmodel animation (client): same AnimationIds for every viewmodel clone. Needs a Motor6D (or R15) rig; only PrimaryPart stays anchored.
	-- Set at least one rbxassetid below to enable; leave all empty to keep the old fully-anchored static viewmodel.
	SniperViewModelAnimationsEnabled = false,
	SniperViewModelAnimIdle = "",
	SniperViewModelAnimWalk = "",
	SniperViewModelAnimRun = "",
	SniperViewModelAnimJump = "",
	SniperViewModelAnimRecoil = "",
	-- One-shot inspect (plays on key; same asset for all viewmodels). Default key: F.
	SniperViewModelAnimInspect = "",
	SniperViewModelInspectKeyCode = Enum.KeyCode.F,
	SniperViewModelAnimInspectFadeIn = 0.06,
	SniperViewModelAnimInspectSpeed = 1,
	SniperViewModelAnimIdleSpeedMax = 0.35,
	SniperViewModelAnimRunSpeedThreshold = 14,
	SniperViewModelAnimCrossFade = 0.12,
	SniperViewModelAnimRecoilFadeIn = 0.04,
	SniperViewModelAnimRecoilSpeed = 1,

	-- Crosshair (client): only while Sniper is equipped AND camera is first-person (same distance rule as SniperViewModel / SniperFirstPersonGate).
	-- LockCenter hides the OS pointer and stops hover cursors over HUD; set false if you need free mouse while aiming.
	SniperCrosshairLockMouseCenterWhileAiming = true,
	-- When LockCenter is true, MouseIcon is cleared; use this only if LockCenter is false (numeric id becomes rbxassetid://id).
	SniperCrosshairMouseIcon = "",
	SniperCrosshairEnabled = true,
	SniperCrosshairCenterGuiEnabled = true,
	-- Only hide the system cursor after the center ScreenGui exists (otherwise the screen looks empty).
	SniperCrosshairHideDefaultMouseWithCenterGui = true,
	-- High value so HUD/menus do not draw over the reticle.
	SniperCrosshairGuiDisplayOrder = 2000000,
	SniperCrosshairGuiColor = Color3.fromRGB(255, 255, 255),
	SniperCrosshairGuiTransparency = 0.12,
	SniperCrosshairGuiThicknessPx = 2,
	SniperCrosshairGuiGapPx = 4,
	SniperCrosshairGuiArmLengthPx = 10,
	SniperCrosshairGuiDotPx = 2,
	SniperCrosshairGuiStrokeEnabled = true,

	-- While the sniper viewmodel is visible (first-person), disable Roblox's automatic pointer over GuiObjects (hand / click cursor).
	SniperSuppressAutoPointerEnabled = true,

	-- Virtual weapon bar: Sniper Tool stays in Backpack (never Character). Viewmodel + crosshair + fire use slot selection + first person.
	SniperVirtualInventoryEnabled = true,
	SniperVirtualInventoryAutoSelectSlot1 = true,
	-- Bottom bar: if PlayerGui already has this ScreenGui name and a descendant GuiButton "Slot1", events are wired to it only.
	SniperWeaponBarScreenGuiName = "SkyLeapWeaponBar",
	SniperWeaponBarCreateIfMissing = true,
	SniperWeaponBarDisplayOrder = 80,
	-- Hide Roblox default backpack hotbar while the Sniper Tool exists in Backpack (use custom bar).
	SniperHideRobloxDefaultBackpack = true,
	-- Lock camera to first person while the sniper slot is selected (virtual loadout).
	SniperForceFirstPersonWhileSniperActive = true,
	-- Server: hitscan origin must be near the character Head (client sends camera / viewport origin).
	SniperMaxFireOriginFromHeadStuds = 22,
	-- Fallback when the Tool is only in Backpack and the viewmodel has no CasingEject part: spawn in camera space.
	SniperCasingEjectCameraCFrame = CFrame.new(0.14, -0.12, -0.55),

	-- Time after each shot before another shot is accepted (seconds)
	ReloadSeconds = 2.5,

	-- Hitscan ray length (studs) - Default: 2000
	MaxRange = 2000000,

	-- Hitscan streak (client): invisible point moves very fast; only Trail draws the line. False = legacy Beam.
	SniperProjectileTrailEnabled = true,
	SniperProjectileCarrierSpan = 0.12,
	SniperProjectileTrailColor = Color3.fromRGB(255, 185, 165),
	SniperProjectileTravelMin = 0.028,
	SniperProjectileTravelMax = 0.1,
	SniperProjectileSpeedStudsPerSec = 12000,
	SniperProjectileTrailLifetime = 0.16,
	SniperProjectileTrailMinLength = 0.02,
	SniperProjectileTrailMaxLength = 12,
	SniperProjectileTrailWidth0 = 0.42,
	SniperProjectileTrailWidth1 = 0.08,
	SniperProjectileTrailTextureLength = 0.5,
	SniperProjectileTrailLightEmission = 0.5,
	SniperProjectileTrailFaceCamera = true,

	-- Legacy instant laser (only when SniperProjectileTrailEnabled is false)
	LaserColor = Color3.fromRGB(255, 70, 90),
	LaserWidth = 0.22,
	LaserLightEmission = 0.95,
	LaserFaceCamera = true,
	LaserFadeSeconds = 0.14,

	-- Physical shell casing (client-only VFX).
	-- CasingEjectPartName: BasePart on viewmodel (first choice) or on Tool when Tool is parented to Character.
	-- Orient it: RightVector = eject direction, UpVector = upward kick, LookVector = forward/back mix (see CasingSpeed*).
	-- Model path: ReplicatedStorage.[CasingShellPath...].CasingShellModelName (e.g. Models / Snipers / CasingShell).
	CasingPhysicsEnabled = true,
	CasingEjectPartName = "CasingEject",
	CasingShellPath = { "Models", "Snipers" },
	CasingShellModelName = "CasingShell",
	CasingLifetimeMinSeconds = 10,
	CasingLifetimeMaxSeconds = 30,
	CasingCloneCanCollide = true,
	-- Initial velocity along CasingEject local axes (studs/s), random between min/max each shot
	CasingSpeedRightMin = -10,
	CasingSpeedRightMax = 10,
	CasingSpeedUpMin = 7,
	CasingSpeedUpMax = 20,
	CasingSpeedLookMin = -6,
	CasingSpeedLookMax = 6,
	CasingSpinRadMin = -16,
	CasingSpinRadMax = 16,
	-- If true: shell velocity biased to the viewer’s screen-left (camera); random spread still feels natural. Hitscan is unchanged.
	CasingEjectUseViewerLeft = true,
	CasingEjectViewerLeftSpeedMin = 11,
	CasingEjectViewerLeftSpeedMax = 24,
	CasingEjectViewerUpBoostMin = 2,
	CasingEjectViewerUpBoostMax = 11,
	CasingEjectViewerForwardSpreadMin = -5,
	CasingEjectViewerForwardSpreadMax = 5,

	-- CollectionService tag for destructible test targets (see EnemyDummySetup.server.lua)
	EnemyTag = "Enemy",

	-- Default health for auto-setup dummies (Humanoid or attribute on BasePart)
	EnemyDefaultHealth = 100,

	-- Overhead BillboardGui (name + health bar) for CollectionService-tagged enemies
	EnemyDisplayName = "Enemy",
	EnemyBillboardSizePx = Vector2.new(120, 42),
	EnemyBillboardStudsOffset = Vector3.new(0, 2.8, 0),
	EnemyBillboardMaxDistance = 80,
	EnemyHealthBarBackgroundColor = Color3.fromRGB(35, 35, 40),
	EnemyHealthBarFillColor = Color3.fromRGB(210, 55, 65),
	EnemyNameTextColor = Color3.fromRGB(255, 255, 255),

	-- Wander AI for Enemy-tagged Models (see EnemyWanderAI.server.lua). BaseParts are auto-wrapped into a Model + Humanoid in EnemyDummySetup.
	EnemyWanderEnabled = true,
	EnemyWanderWalkSpeed = 14,
	EnemyWanderRadius = 40,
	EnemyWanderMinWaitSeconds = 1.2,
	EnemyWanderMaxWaitSeconds = 3.8,
	-- Max distance to chosen wander goal (path may be longer along walkable mesh).
	EnemyWanderMaxStepStuds = 40,
	EnemyWanderRaycastUp = 60,
	EnemyWanderRaycastDown = 180,

	-- Pathfinding (PathfindingService): avoids walls/cliffs; smoother than a single MoveTo. Docs: create.roblox.com/docs/reference/engine/classes/PathfindingService
	EnemyPathfindingEnabled = true,
	EnemyPathAgentRadius = 2,
	EnemyPathAgentHeight = 5,
	EnemyPathAgentCanJump = true,
	-- Advance to next waypoint when HRP is within this distance (reduces stutter vs MoveToFinished-only).
	EnemyPathWaypointReachedRadius = 3.25,
	-- Max wait per waypoint before skipping (stuck recovery).
	EnemyPathWaypointTimeoutSeconds = 10,
	-- If path fails, fall back to straight Humanoid:MoveTo toward goal.
	EnemyPathFallbackStraightLine = true,

	-- Enemy walk/run: server-driven (recommended). NPC Humanoids do not replicate MoveDirection like players, so client-only scripts often stay idle.
	EnemyLocomotionEnabled = true,
	EnemyLocomotionUseServerAnimator = true,
	-- Client LocalScript ReplicatedStorage.AI.EnemyNpcLocomotion (only if EnemyLocomotionUseServerAnimator = false).
	-- Above this horizontal speed (studs/s) the Run animation is used instead of Walk.
	EnemyLocomotionRunSpeedThreshold = 13,

	-- Server: max distance between client-reported origin and server Barrel position (studs)
	MaxOriginDriftStuds = 12,

	-- Server: optional aim sanity — compare shot direction to Barrel LookVector (degrees).
	-- Third-person camera often disagrees with the barrel; keep high or disable via UseMuzzleDirectionCheck.
	UseMuzzleDirectionCheck = false,
	MaxAimVsMuzzleDegrees = 75,

	-- Sounds (rbxassetid://NUMERIC_ID). Leave as "" to skip that sound.
	-- Assign your asset IDs in Studio or here after uploading to Roblox.
	FireSoundId = "rbxassetid://77750088529371",
	FireSoundVolume = 0.85,
	-- Linear volume fade over the last N seconds of the fire SFX (shooter + other players). 0 = off.
	FireSoundFadeOutSeconds = 0.5,
	FireSoundForOthersFadeOutSeconds = 0.5,
	-- Plays once when the shot is accepted locally (start of reload cooldown).
	ReloadSoundId = "rbxassetid://122790640796504",
	ReloadSoundVolume = 0.55,
	-- Shell casing hitting the ground (shooter only). Plays after a short delay.
	ShellCasingSoundId = "rbxassetid://137532489135436",
	ShellCasingVolume = 0.75,
	ShellCasingDelaySeconds = 0.45,
	-- 3D falloff for casing (studs); kept short so it reads as “near your feet”.
	ShellCasingMaxDistance = 28,
	-- Shooter hears when the server registers a kill (player or Enemy-tagged target).
	KillConfirmSoundId = "",
	KillConfirmVolume = 0.9,
	-- Player who was eliminated by the sniper (not used for Enemy dummies).
	VictimDeathSoundId = "",
	VictimDeathVolume = 1,
	-- Other players: short 3D cue at the shooter's Barrel when they fire (uses SniperLaserFx).
	FireSoundForOthersId = "",
	FireSoundForOthersVolume = 0.45,
}
