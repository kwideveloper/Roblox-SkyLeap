-- Client: walk / run / air locomotion, recoil, and inspect on the sniper viewmodel clone (same AnimationIds for all viewmodels).
-- Requires Motor6D (or compatible) rig; only PrimaryPart stays anchored when SniperViewModelAnimationsEnabled.

local Config = require(script.Parent.Config)
local Locomotion = require(script.Parent.ViewModelLocomotionSample)
local RigHelper = require(script.Parent.ViewModelAnimationRigHelper)

export type LocomotionPhase = "Idle" | "Walk" | "Run" | "Air"

export type AnimatorHandle = {
	step: (self: AnimatorHandle, camera: Camera, offset: CFrame) -> (),
	destroy: (self: AnimatorHandle) -> (),
}

-- Active viewmodel animation handle per player (local client = one player).
local activeHandles: { [Player]: any } = {}

local SniperViewModelAnimator = {}

function SniperViewModelAnimator.fireRecoil(player: Player)
	local h = activeHandles[player]
	if h then
		h:_playRecoilInternal()
	end
end

function SniperViewModelAnimator.notifyInspect(player: Player)
	local h = activeHandles[player]
	if h then
		h:_playInspectInternal()
	end
end

local function normalizeAnimId(raw: string): string
	local s = string.gsub(raw, "^%s+", "")
	s = string.gsub(s, "%s+$", "")
	if s == "" then
		return ""
	end
	if string.find(s, "rbxassetid://", 1, true) or string.find(s, "rbxasset://", 1, true) then
		return s
	end
	local n = string.match(s, "^(%d+)$")
	if n then
		return "rbxassetid://" .. n
	end
	return s
end

local function makeAnimationObject(animationId: string): Animation?
	if animationId == "" then
		return nil
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = animationId
	return anim
end

local function loadTrack(
	animator: Animator,
	animationId: string,
	looped: boolean,
	priority: Enum.AnimationPriority
): AnimationTrack?
	local id = normalizeAnimId(animationId)
	if id == "" then
		return nil
	end
	local animObj = makeAnimationObject(id)
	if not animObj then
		return nil
	end
	local ok, track = pcall(function()
		return animator:LoadAnimation(animObj)
	end)
	if not ok or not track then
		return nil
	end
	track.Looped = looped
	track.Priority = priority
	return track
end

type TrackSet = {
	Idle: AnimationTrack?,
	Walk: AnimationTrack?,
	Run: AnimationTrack?,
	Air: AnimationTrack?,
	Recoil: AnimationTrack?,
	Inspect: AnimationTrack?,
}

local function trackForPhase(tracks: TrackSet, phase: LocomotionPhase): AnimationTrack?
	if phase == "Idle" then
		return tracks.Idle
	elseif phase == "Walk" then
		return tracks.Walk
	elseif phase == "Run" then
		return tracks.Run
	elseif phase == "Air" then
		return tracks.Air
	end
	return nil
end

local function firstFallback(tracks: TrackSet, prefer: { LocomotionPhase }): AnimationTrack?
	for _, p in ipairs(prefer) do
		local t = trackForPhase(tracks, p)
		if t then
			return t
		end
	end
	return nil
end

local Handle = {}
Handle.__index = Handle

local function stopTrack(tr: AnimationTrack?, fade: number)
	if tr and tr.IsPlaying then
		pcall(function()
			tr:Stop(fade)
		end)
	end
end

function Handle:destroy()
	if self._gone then
		return
	end
	self._gone = true
	activeHandles[self._player] = nil
	if self._charConn then
		self._charConn:Disconnect()
		self._charConn = nil
	end
	if self._jumpConn then
		self._jumpConn:Disconnect()
		self._jumpConn = nil
	end
	local trs = self._tracks
	stopTrack(trs.Idle, 0.05)
	stopTrack(trs.Walk, 0.05)
	stopTrack(trs.Run, 0.05)
	stopTrack(trs.Air, 0.05)
	stopTrack(trs.Recoil, 0.05)
	stopTrack(trs.Inspect, 0.05)
	self._tracks = { Idle = nil, Walk = nil, Run = nil, Air = nil, Recoil = nil, Inspect = nil }
end

function Handle:_stopLocomotionTrack(tr: AnimationTrack?, fade: number)
	stopTrack(tr, fade)
end

function Handle:_playLocomotionTrack(tr: AnimationTrack?, fade: number)
	if not tr then
		return
	end
	if not tr.IsPlaying then
		pcall(function()
			tr:Play(fade, 1, 1)
		end)
	end
end

function Handle:_resolveEffectivePhase(desired: LocomotionPhase): LocomotionPhase
	local t = trackForPhase(self._tracks, desired)
	if t then
		return desired
	end
	if desired ~= "Idle" and self._tracks.Idle then
		return "Idle"
	end
	if desired ~= "Walk" and self._tracks.Walk then
		return "Walk"
	end
	if desired ~= "Run" and self._tracks.Run then
		return "Run"
	end
	return desired
end

function Handle:_setLocomotionPhase(phase: LocomotionPhase)
	local effective = self:_resolveEffectivePhase(phase)
	if self._locoPhase == effective then
		return
	end
	local fade = self._crossFade
	local prevTrack = self._locoTrack
	local nextTrack = trackForPhase(self._tracks, effective)
	if not nextTrack then
		nextTrack = firstFallback(self._tracks, { "Idle", "Walk", "Run", "Air" })
	end
	self._locoPhase = effective
	self._locoTrack = nextTrack
	if prevTrack and prevTrack ~= nextTrack then
		self:_stopLocomotionTrack(prevTrack, fade)
	end
	self:_playLocomotionTrack(nextTrack, fade)
end

function Handle:_playRecoilInternal()
	local tr = self._tracks.Recoil
	if not tr or self._gone then
		return
	end
	local fade = Config.SniperViewModelAnimRecoilFadeIn or 0.04
	local speed = Config.SniperViewModelAnimRecoilSpeed or 1
	pcall(function()
		tr:Play(fade, 1, speed)
	end)
end

function Handle:_playInspectInternal()
	local tr = self._tracks.Inspect
	if not tr or self._gone then
		return
	end
	local fade = Config.SniperViewModelAnimInspectFadeIn or 0.06
	local speed = Config.SniperViewModelAnimInspectSpeed or 1
	pcall(function()
		if tr.IsPlaying then
			tr:Stop(0.02)
		end
		tr:Play(fade, 1, speed)
	end)
end

function Handle:step(camera: Camera, offset: CFrame)
	if self._gone or not self._model.Parent then
		return
	end
	self._model:PivotTo(camera.CFrame * offset)
	if not self._hasLocomotion then
		return
	end
	local phase = Locomotion.fromPlayer(self._player)
	self:_setLocomotionPhase(phase)
end

function SniperViewModelAnimator.hasConfiguredAnimations(): boolean
	if not RigHelper.shouldUseAnimatedAnchors() then
		return false
	end
	local ids = {
		Config.SniperViewModelAnimIdle,
		Config.SniperViewModelAnimWalk,
		Config.SniperViewModelAnimRun,
		Config.SniperViewModelAnimJump,
		Config.SniperViewModelAnimRecoil,
		Config.SniperViewModelAnimInspect,
	}
	for _, raw in ipairs(ids) do
		if type(raw) == "string" and normalizeAnimId(raw) ~= "" then
			return true
		end
	end
	return false
end

function SniperViewModelAnimator.attachToClone(clone: Model, player: Player): AnimatorHandle?
	if not RigHelper.shouldUseAnimatedAnchors() or not SniperViewModelAnimator.hasConfiguredAnimations() then
		return nil
	end
	local animator, _host = RigHelper.getAnimator(clone)
	if not animator then
		return nil
	end

	local movementPriority = Enum.AnimationPriority.Movement
	local inspectPriority = Enum.AnimationPriority.Action2
	local actionPriority = Enum.AnimationPriority.Action4

	local tracks: TrackSet = {
		Idle = loadTrack(animator, Config.SniperViewModelAnimIdle or "", true, movementPriority),
		Walk = loadTrack(animator, Config.SniperViewModelAnimWalk or "", true, movementPriority),
		Run = loadTrack(animator, Config.SniperViewModelAnimRun or "", true, movementPriority),
		Air = loadTrack(animator, Config.SniperViewModelAnimJump or "", true, movementPriority),
		Recoil = loadTrack(animator, Config.SniperViewModelAnimRecoil or "", false, actionPriority),
		Inspect = loadTrack(animator, Config.SniperViewModelAnimInspect or "", false, inspectPriority),
	}

	if not tracks.Idle and not tracks.Walk and not tracks.Run and not tracks.Air and not tracks.Recoil and not tracks.Inspect then
		return nil
	end

	local hasLocomotion = tracks.Idle ~= nil or tracks.Walk ~= nil or tracks.Run ~= nil or tracks.Air ~= nil

	local self = setmetatable({
		_gone = false,
		_model = clone,
		_player = player,
		_tracks = tracks,
		_hasLocomotion = hasLocomotion,
		_locoPhase = nil :: LocomotionPhase?,
		_locoTrack = nil :: AnimationTrack?,
		_crossFade = Config.SniperViewModelAnimCrossFade or 0.12,
		_jumpConn = nil :: RBXScriptConnection?,
		_charConn = nil :: RBXScriptConnection?,
	}, Handle)

	activeHandles[player] = self

	local function bindJumpForCharacter(char: Model?)
		if self._jumpConn then
			self._jumpConn:Disconnect()
			self._jumpConn = nil
		end
		if not char or not tracks.Air or not hasLocomotion then
			return
		end
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not hum then
			return
		end
		self._jumpConn = hum.StateChanged:Connect(function(_old, new)
			if new == Enum.HumanoidStateType.Jumping then
				self:_setLocomotionPhase("Air")
			end
		end)
	end

	self._charConn = player.CharacterAdded:Connect(function(char)
		if self._gone then
			return
		end
		bindJumpForCharacter(char)
	end)
	bindJumpForCharacter(player.Character)

	if hasLocomotion then
		local startPhase = Locomotion.fromPlayer(player)
		self:_setLocomotionPhase(startPhase)
	end

	return (self :: any) :: AnimatorHandle
end

return SniperViewModelAnimator
