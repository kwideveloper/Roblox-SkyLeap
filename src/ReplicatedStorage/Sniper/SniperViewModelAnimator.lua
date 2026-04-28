-- Client: walk / run / air locomotion, recoil, shoot, and inspect on the sniper viewmodel clone (same AnimationIds for all viewmodels).
-- Requires Motor6D (or compatible) rig; only PrimaryPart stays anchored when SniperViewModelAnimationsEnabled.

local Config = require(script.Parent.Config)
local Locomotion = require(script.Parent.ViewModelLocomotionSample)
local RigHelper = require(script.Parent.ViewModelAnimationRigHelper)
local Workspace = game:GetService("Workspace")

export type LocomotionPhase = "Idle" | "Walk" | "Run" | "Air"

export type AnimatorHandle = {
	step: (self: AnimatorHandle, camera: Camera, offset: CFrame) -> (),
	destroy: (self: AnimatorHandle) -> (),
}

-- Active viewmodel animation handle per player (local client = one player).
local activeHandles: { [Player]: any } = {}

local SniperViewModelAnimator = {}
local DEBUG_PREFIX = "[SniperVMAnim]"
local DEFAULT_RELOAD_FAILED_ONE_IN = 10000
local COLLIDER_ENTER_FADE = 0.06
local COLLIDER_RELEASE_FADE = 0.06
local COLLIDER_RELEASE_MAX_SECONDS = 0.12
local COLLIDER_RELEASE_SPEED_MIN = 0.35
local COLLIDER_RELEASE_SPEED_MAX = 3.2

local function debugLog(msg: string, ...: any)
	print(DEBUG_PREFIX .. " " .. string.format(msg, ...))
end

function SniperViewModelAnimator.fireRecoil(player: Player)
	local h = activeHandles[player]
	if h then
		h:_playRecoilInternal()
	else
		debugLog("fireRecoil skipped: no active handle (player=%s)", player.Name)
	end
end

function SniperViewModelAnimator.notifyInspect(player: Player)
	local h = activeHandles[player]
	if h then
		debugLog("notifyInspect received (player=%s)", player.Name)
		h:_playInspectInternal()
	else
		debugLog("notifyInspect skipped: no active handle (player=%s)", player.Name)
	end
end

function SniperViewModelAnimator.notifyReload(player: Player, desiredDuration: number?)
	local h = activeHandles[player]
	if h then
		debugLog("notifyReload received (player=%s, desiredDuration=%s)", player.Name, tostring(desiredDuration))
		h:_playReloadInternal(desiredDuration)
	else
		debugLog("notifyReload skipped: no active handle (player=%s)", player.Name)
	end
end

function SniperViewModelAnimator.notifyReloadFailed(player: Player, desiredDuration: number?)
	local h = activeHandles[player]
	if h then
		debugLog("notifyReloadFailed received (player=%s, desiredDuration=%s)", player.Name, tostring(desiredDuration))
		h:_playReloadFailedInternal(desiredDuration)
	else
		debugLog("notifyReloadFailed skipped: no active handle (player=%s)", player.Name)
	end
end

function SniperViewModelAnimator.getReloadFailedOneIn(player: Player): number
	local h = activeHandles[player]
	if not h then
		return DEFAULT_RELOAD_FAILED_ONE_IN
	end
	local n = h._reloadFailedOneIn
	if type(n) ~= "number" or n < 1 or n ~= n or n == math.huge or n == -math.huge then
		return DEFAULT_RELOAD_FAILED_ONE_IN
	end
	return math.max(1, math.floor(n + 0.5))
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
	local ok, trackOrErr = pcall(function()
		return animator:LoadAnimation(animObj)
	end)
	if not ok then
		debugLog("loadTrack failed: id=%s err=%s", id, tostring(trackOrErr))
		return nil
	end
	local track = trackOrErr
	if not track then
		debugLog("loadTrack failed: id=%s returned nil track", id)
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
	Shoot: AnimationTrack?,
	Inspect: AnimationTrack?,
	Reload: AnimationTrack?,
	ReloadFailed: AnimationTrack?,
	Collider: AnimationTrack?,
}

type ViewModelAnimationMap = {
	Idle: string,
	Walk: string,
	Run: string,
	Air: string,
	Recoil: string,
	Shoot: string,
	Inspect: string,
	Reload: string,
	ReloadFailed: string,
	Collider: string,
}

type DurationOverrideMap = {
	Inspect: number?,
	Reload: number?,
	ReloadFailed: number?,
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

local function buildCameraBoneTargetCFrame(camCf: CFrame, offset: CFrame): CFrame
	if Config.SniperViewModelCameraBoneMatchCameraBasis == false then
		return camCf * offset
	end
	local pos = (camCf * offset).Position
	local look = camCf.LookVector
	local upRef = camCf.UpVector
	local cf = CFrame.lookAt(pos, pos + look, upRef)
	local rollDeg = tonumber(Config.SniperViewModelCameraBoneRollDegrees) or 0
	if math.abs(rollDeg) > 1e-4 then
		cf = cf * CFrame.Angles(0, 0, math.rad(rollDeg))
	end
	return cf
end

local function solveViewmodelWorldPivot(clone: Model, camCf: CFrame, offset: CFrame): CFrame
	if Config.SniperViewModelPivotUsesCameraBone == false then
		return camCf * offset
	end
	local boneName = Config.SniperViewModelCameraBoneName or "CameraBone"
	local bone = clone:FindFirstChild(boneName, true)
	if not bone or not bone:IsA("BasePart") then
		return buildCameraBoneTargetCFrame(camCf, offset)
	end
	local target = buildCameraBoneTargetCFrame(camCf, offset)
	local rel = clone:GetPivot():ToObjectSpace(bone.CFrame)
	return target * rel:Inverse()
end

local function findColliderPart(clone: Model): BasePart?
	local p = clone:FindFirstChild("Collider", true)
	if p and p:IsA("BasePart") then
		return p
	end
	return nil
end

local function isExternalCollisionPart(part: BasePart, clone: Model, player: Player): boolean
	if not part:IsDescendantOf(Workspace) then
		return false
	end
	if part:IsDescendantOf(clone) then
		return false
	end
	local character = player.Character
	if character and part:IsDescendantOf(character) then
		return false
	end
	local modelAncestor = part:FindFirstAncestorOfClass("Model")
	if modelAncestor and modelAncestor:FindFirstChildOfClass("Humanoid") then
		return false
	end
	return true
end

local function colliderTouchesExternal(colliderPart: BasePart, clone: Model, player: Player): boolean
	local ok, touching = pcall(function()
		return colliderPart:GetTouchingParts()
	end)
	if ok and touching then
		for _, p in ipairs(touching) do
			if p:IsA("BasePart") and isExternalCollisionPart(p, clone, player) then
				return true
			end
		end
	end

	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { clone, player.Character }
	local ok2, overlap = pcall(function()
		return Workspace:GetPartsInPart(colliderPart, params)
	end)
	if not ok2 or not overlap then
		return false
	end
	for _, p in ipairs(overlap) do
		if p:IsA("BasePart") and isExternalCollisionPart(p, clone, player) then
			return true
		end
	end
	return false
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
	stopTrack(trs.Shoot, 0.05)
	stopTrack(trs.Inspect, 0.05)
	stopTrack(trs.Reload, 0.05)
	stopTrack(trs.ReloadFailed, 0.05)
	stopTrack(trs.Collider, 0.05)
	self._tracks = {
		Idle = nil,
		Walk = nil,
		Run = nil,
		Air = nil,
		Recoil = nil,
		Shoot = nil,
		Inspect = nil,
		Reload = nil,
		ReloadFailed = nil,
		Collider = nil,
	}
	self._colliderReleaseUntil = nil
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
	-- No Idle track: still treat phase as Idle (do NOT substitute Walk — that looked like "walking" while standing still).
	if desired == "Idle" then
		return "Idle"
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
		-- Idle with no Idle animation: silence movement layer instead of jumping to Walk.
		if effective == "Idle" then
			nextTrack = nil
		else
			nextTrack = firstFallback(self._tracks, { "Idle", "Walk", "Run", "Air" })
		end
	end
	self._locoPhase = effective
	self._locoTrack = nextTrack
	if prevTrack and prevTrack ~= nextTrack then
		self:_stopLocomotionTrack(prevTrack, fade)
	end
	self:_playLocomotionTrack(nextTrack, fade)
end

function Handle:_inspectInterruptStopFade(): number
	local n = Config.SniperViewModelAnimInspectInterruptStopFade
	if type(n) == "number" and n >= 0 and n == n and n ~= math.huge and n ~= -math.huge then
		return math.clamp(n, 0, 0.5)
	end
	return 0.1
end

-- Cancelling Inspect with Stop(0) can leave joints in a bad blended state; fade out + nudge Movement layer.
function Handle:_cutInspectForHigherPriorityAction()
	if self._gone then
		return
	end
	local inspectTr = self._tracks.Inspect
	if inspectTr and inspectTr.IsPlaying then
		stopTrack(inspectTr, self:_inspectInterruptStopFade())
	end
	if not self._hasLocomotion then
		return
	end
	local tr = self._locoTrack
	if not tr then
		return
	end
	local cross = self._crossFade or 0.12
	local fade = math.clamp(cross * 0.45, 0.04, 0.12)
	pcall(function()
		if tr.IsPlaying then
			tr:Stop(fade * 0.55)
		end
		tr:Play(fade, 1, 1)
	end)
end

function Handle:_shootTrackStillPlaying(shootTr: AnimationTrack): boolean
	if not shootTr.IsPlaying then
		return false
	end
	local len = shootTr.Length
	if type(len) ~= "number" or len <= 1e-3 then
		return false
	end
	local margin = tonumber(Config.SniperViewModelAnimShootCompleteMargin) or 0.045
	margin = math.clamp(margin, 1e-3, math.max(len * 0.5, margin))
	return shootTr.TimePosition < len - margin
end

function Handle:_playRecoilInternal()
	if self._gone then
		return
	end
	self:_cutInspectForHigherPriorityAction()

	local shootTr = self._tracks.Shoot
	if shootTr then
		if Config.SniperViewModelAnimShootMustFinish ~= false then
			if self:_shootTrackStillPlaying(shootTr) then
				return
			end
		end
		local fade = Config.SniperViewModelAnimRecoilFadeIn or 0.04
		local speed = Config.SniperViewModelAnimRecoilSpeed or 1
		pcall(function()
			shootTr.Looped = false
			if shootTr.IsPlaying then
				shootTr:Stop(0.02)
			end
			shootTr:Play(fade, 1, speed)
		end)
		return
	end

	local tr = self._tracks.Recoil
	if not tr then
		return
	end
	local fade = Config.SniperViewModelAnimRecoilFadeIn or 0.04
	local speed = Config.SniperViewModelAnimRecoilSpeed or 1
	pcall(function()
		tr:Play(fade, 1, speed)
	end)
end

local function resolveDurationSpeed(track: AnimationTrack, desiredDuration: number?): number
	if type(desiredDuration) ~= "number" or desiredDuration <= 0 then
		return 1
	end
	local len = track.Length
	if type(len) ~= "number" or len <= 1e-4 then
		return 1
	end
	local speed = len / desiredDuration
	if speed ~= speed or speed == math.huge or speed == -math.huge then
		return 1
	end
	return math.max(0.05, speed)
end

function Handle:_playInspectInternal()
	local tr = self._tracks.Inspect
	if not tr or self._gone then
		debugLog("_playInspectInternal skipped: track missing or handle gone")
		return
	end
	local fade = Config.SniperViewModelAnimInspectFadeIn or 0.06
	local forcedDuration = self._durationOverrides and self._durationOverrides.Inspect or nil
	local speed = 1
	if type(forcedDuration) == "number" and forcedDuration > 0 then
		speed = resolveDurationSpeed(tr, forcedDuration)
	end
	pcall(function()
		if tr.IsPlaying then
			tr:Stop(0.02)
		end
		tr:Play(fade, 1, speed)
		debugLog(
			"_playInspectInternal play called: isPlaying=%s length=%.3f forcedDuration=%s speed=%.3f",
			tostring(tr.IsPlaying),
			tr.Length,
			tostring(forcedDuration),
			speed
		)
	end)
end

function Handle:_playReloadInternal(desiredDuration: number?)
	local tr = self._tracks.Reload
	if not tr or self._gone then
		debugLog("_playReloadInternal skipped: track missing or handle gone")
		return
	end
	self:_cutInspectForHigherPriorityAction()
	local overrideDuration = self._durationOverrides and self._durationOverrides.Reload or nil
	local finalDuration = overrideDuration or desiredDuration
	local speed = resolveDurationSpeed(tr, finalDuration)
	pcall(function()
		if tr.IsPlaying then
			tr:Stop(0.02)
		end
		tr:Play(0.06, 1, speed)
		debugLog(
			"_playReloadInternal play called: isPlaying=%s length=%.3f desiredDuration=%s overrideDuration=%s finalDuration=%s speed=%.3f",
			tostring(tr.IsPlaying),
			tr.Length,
			tostring(desiredDuration),
			tostring(overrideDuration),
			tostring(finalDuration),
			speed
		)
	end)
end

function Handle:_playReloadFailedInternal(desiredDuration: number?)
	local tr = self._tracks.ReloadFailed
	if not tr or self._gone then
		debugLog("_playReloadFailedInternal skipped: track missing or handle gone")
		return
	end
	self:_cutInspectForHigherPriorityAction()
	local overrideDuration = self._durationOverrides and self._durationOverrides.ReloadFailed or nil
	local finalDuration = overrideDuration or desiredDuration
	local speed = resolveDurationSpeed(tr, finalDuration)
	pcall(function()
		if tr.IsPlaying then
			tr:Stop(0.02)
		end
		tr:Play(0.03, 1, speed)
		debugLog(
			"_playReloadFailedInternal play called: isPlaying=%s length=%.3f desiredDuration=%s overrideDuration=%s finalDuration=%s speed=%.3f",
			tostring(tr.IsPlaying),
			tr.Length,
			tostring(desiredDuration),
			tostring(overrideDuration),
			tostring(finalDuration),
			speed
		)
	end)
end

function Handle:step(camera: Camera, offset: CFrame)
	if self._gone or not self._model.Parent then
		return
	end
	self._model:PivotTo(solveViewmodelWorldPivot(self._model, camera.CFrame, offset))
	local colliderTrack = self._tracks.Collider
	local colliderPart = self._colliderPart
	if colliderTrack and colliderPart and colliderPart.Parent then
		if self._colliderReleaseUntil and os.clock() >= self._colliderReleaseUntil then
			self._colliderReleaseUntil = nil
			self._colliderActive = false
			self._colliderLocked = false
			stopTrack(colliderTrack, COLLIDER_RELEASE_FADE)
		end
		local touchingExternal = colliderTouchesExternal(colliderPart, self._model, self._player)
		if touchingExternal then
			if not self._colliderActive then
				self._colliderActive = true
				self._colliderLocked = false
				self._colliderReleaseUntil = nil
				pcall(function()
					if colliderTrack.IsPlaying then
						colliderTrack:Stop(0.03)
					end
					colliderTrack:Play(COLLIDER_ENTER_FADE, 1, 1)
				end)
			end
			if not self._colliderLocked and colliderTrack.IsPlaying then
				local len = colliderTrack.Length
				if type(len) == "number" and len > 0 and colliderTrack.TimePosition >= (len - 0.03) then
					self._colliderLocked = true
					pcall(function()
						colliderTrack:AdjustSpeed(0)
					end)
				end
			end
		elseif self._colliderActive then
			-- Smooth return: try to scrub back from the held end frame by playing backwards briefly.
			-- If reverse playback is not supported by the runtime, timeout fallback still fades out softly.
			pcall(function()
				colliderTrack:AdjustSpeed(-COLLIDER_RELEASE_SPEED_MAX)
			end)
			self._colliderReleaseUntil = os.clock() + COLLIDER_RELEASE_MAX_SECONDS
			if self._colliderLocked then
				self._colliderLocked = false
			end
		end
		if self._colliderReleaseUntil and colliderTrack.IsPlaying then
			-- Ease-out while going back to start:
			-- fast when near the end frame, slower when approaching frame 0.
			local len = colliderTrack.Length
			if type(len) == "number" and len > 1e-4 then
				local t = math.clamp(colliderTrack.TimePosition / len, 0, 1)
				local speed = COLLIDER_RELEASE_SPEED_MIN + (COLLIDER_RELEASE_SPEED_MAX - COLLIDER_RELEASE_SPEED_MIN) * t
				pcall(function()
					colliderTrack:AdjustSpeed(-speed)
				end)
			end
		end
		if self._colliderReleaseUntil and colliderTrack.IsPlaying and colliderTrack.TimePosition <= 0.03 then
			self._colliderReleaseUntil = nil
			self._colliderActive = false
			self._colliderLocked = false
			stopTrack(colliderTrack, COLLIDER_RELEASE_FADE)
		end
	end
	if not self._hasLocomotion then
		return
	end
	local phase = Locomotion.fromPlayer(self._player)
	self:_setLocomotionPhase(phase)
end

-- `Animations` may be a direct child of the viewmodel clone or under `Gun` (same place as `Gun` stats).
local function getViewModelAnimationsFolder(clone: Model): Folder?
	local direct = clone:FindFirstChild("Animations")
	if direct and direct:IsA("Folder") then
		return direct
	end
	local gun = clone:FindFirstChild("Gun")
	if gun and gun:IsA("Model") then
		local nested = gun:FindFirstChild("Animations")
		if nested and nested:IsA("Folder") then
			return nested
		end
	end
	return nil
end

function SniperViewModelAnimator.hasConfiguredAnimations(clone: Model?): boolean
	local ids = {
		Config.SniperViewModelAnimIdle,
		Config.SniperViewModelAnimWalk,
		Config.SniperViewModelAnimRun,
		Config.SniperViewModelAnimJump,
		Config.SniperViewModelAnimRecoil,
		Config.SniperViewModelAnimShoot,
		Config.SniperViewModelAnimInspect,
	}
	for _, raw in ipairs(ids) do
		if type(raw) == "string" and normalizeAnimId(raw) ~= "" then
			return true
		end
	end
	if clone then
		local folder = getViewModelAnimationsFolder(clone)
		if folder then
			for _, child in ipairs(folder:GetChildren()) do
				if child:IsA("StringValue") and normalizeAnimId(child.Value) ~= "" then
					return true
				end
			end
		end
	end
	return false
end

local function readAnimationIdFromStringValue(folder: Instance?, key: string): string
	if not folder or key == "" then
		return ""
	end
	local valueObj = folder:FindFirstChild(key)
	if not valueObj or not valueObj:IsA("StringValue") then
		return ""
	end
	if type(valueObj.Value) ~= "string" then
		return ""
	end
	return valueObj.Value
end

local function readDurationOverrideFromStringValue(folder: Instance?, key: string): number?
	if not folder or key == "" then
		return nil
	end
	local valueObj = folder:FindFirstChild(key)
	if not valueObj or not valueObj:IsA("StringValue") then
		return nil
	end
	local duration = valueObj:GetAttribute("Duration")
	if
		type(duration) == "number"
		and duration > 0
		and duration == duration
		and duration ~= math.huge
		and duration ~= -math.huge
	then
		return duration
	end
	return nil
end

local function readOneInProbabilityFromStringValue(folder: Instance?, key: string): number?
	if not folder or key == "" then
		return nil
	end
	local valueObj = folder:FindFirstChild(key)
	if not valueObj or not valueObj:IsA("StringValue") then
		return nil
	end
	local oneIn = valueObj:GetAttribute("OneIn")
	if type(oneIn) == "number" and oneIn > 0 and oneIn == oneIn and oneIn ~= math.huge and oneIn ~= -math.huge then
		return math.max(1, math.floor(oneIn + 0.5))
	end
	return nil
end

local function resolveAnimationIdsForClone(clone: Model): ViewModelAnimationMap
	local animationsFolder = getViewModelAnimationsFolder(clone)
	return {
		Idle = readAnimationIdFromStringValue(animationsFolder, "Idle"),
		Walk = readAnimationIdFromStringValue(animationsFolder, "Walk"),
		Run = readAnimationIdFromStringValue(animationsFolder, "Run"),
		Air = readAnimationIdFromStringValue(animationsFolder, "Jump"),
		Recoil = readAnimationIdFromStringValue(animationsFolder, "Recoil"),
		Shoot = readAnimationIdFromStringValue(animationsFolder, "Shoot"),
		Inspect = readAnimationIdFromStringValue(animationsFolder, "Inspect"),
		Reload = readAnimationIdFromStringValue(animationsFolder, "Reload"),
		ReloadFailed = readAnimationIdFromStringValue(animationsFolder, "ReloadFailed"),
		Collider = readAnimationIdFromStringValue(animationsFolder, "Collider"),
	}
end

local function resolveDurationOverridesForClone(clone: Model): DurationOverrideMap
	local animationsFolder = getViewModelAnimationsFolder(clone)
	return {
		Inspect = readDurationOverrideFromStringValue(animationsFolder, "Inspect"),
		Reload = readDurationOverrideFromStringValue(animationsFolder, "Reload"),
		ReloadFailed = readDurationOverrideFromStringValue(animationsFolder, "ReloadFailed"),
	}
end

local function resolveReloadFailedOneInForClone(clone: Model): number
	local animationsFolder = getViewModelAnimationsFolder(clone)
	local fromAttr = readOneInProbabilityFromStringValue(animationsFolder, "ReloadFailed")
	if type(fromAttr) == "number" then
		return fromAttr
	end
	return DEFAULT_RELOAD_FAILED_ONE_IN
end

local function logRigDiagnostics(clone: Model)
	local motorCount = 0
	local partNameCount: { [string]: number } = {}
	local motorDetails: { string } = {}
	local anchoredParts: { string } = {}
	local unanchoredParts: { string } = {}
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("Motor6D") then
			motorCount += 1
			local p0 = d.Part0
			local p1 = d.Part1
			table.insert(
				motorDetails,
				string.format(
					"%s [Part0=%s(anchored=%s) Part1=%s(anchored=%s)]",
					d.Name,
					p0 and p0.Name or "nil",
					tostring(p0 and p0:IsA("BasePart") and p0.Anchored or "?"),
					p1 and p1.Name or "nil",
					tostring(p1 and p1:IsA("BasePart") and p1.Anchored or "?")
				)
			)
		elseif d:IsA("BasePart") then
			partNameCount[d.Name] = (partNameCount[d.Name] or 0) + 1
			local entry = string.format("%s(%s)", d.Name, d.Parent and d.Parent.Name or "?")
			if d.Anchored then
				table.insert(anchoredParts, entry)
			else
				table.insert(unanchoredParts, entry)
			end
		end
	end
	local duplicatePartNames = 0
	local duplicateList: { string } = {}
	for _, n in pairs(partNameCount) do
		if n > 1 then
			duplicatePartNames += 1
		end
	end
	for name, n in pairs(partNameCount) do
		if n > 1 then
			table.insert(duplicateList, string.format("%s(x%d)", name, n))
		end
	end
	table.sort(duplicateList)
	debugLog(
		"rig diagnostics (clone=%s): motor6d=%d duplicatePartNames=%d primary=%s",
		clone.Name,
		motorCount,
		duplicatePartNames,
		tostring(clone.PrimaryPart and clone.PrimaryPart.Name or "nil")
	)
	if #duplicateList > 0 then
		debugLog("duplicate part names: %s", table.concat(duplicateList, ", "))
	end
	for _, line in ipairs(motorDetails) do
		debugLog("motor6d: %s", line)
	end
	debugLog("anchored parts (%d): %s", #anchoredParts, table.concat(anchoredParts, ", "))
	debugLog("unanchored parts (%d): %s", #unanchoredParts, table.concat(unanchoredParts, ", "))
end

function SniperViewModelAnimator.attachToClone(clone: Model, player: Player): AnimatorHandle?
	if not SniperViewModelAnimator.hasConfiguredAnimations(clone) then
		debugLog("attachToClone skipped: no configured animations (clone=%s)", clone.Name)
		return nil
	end
	logRigDiagnostics(clone)
	local animator, _host = RigHelper.getAnimator(clone)
	if not animator then
		debugLog("attachToClone failed: no Animator/AnimationController (clone=%s)", clone.Name)
		return nil
	end

	local movementPriority = Enum.AnimationPriority.Movement
	local inspectPriority = Enum.AnimationPriority.Action2
	local actionPriority = Enum.AnimationPriority.Action4
	local animIds = resolveAnimationIdsForClone(clone)
	local durationOverrides = resolveDurationOverridesForClone(clone)
	local reloadFailedOneIn = resolveReloadFailedOneInForClone(clone)
	debugLog(
		"animation ids (clone=%s): Walk=%s Run=%s Shoot=%s Inspect=%s Reload=%s ReloadFailed=%s",
		clone.Name,
		animIds.Walk ~= "" and normalizeAnimId(animIds.Walk) or "<empty>",
		animIds.Run ~= "" and normalizeAnimId(animIds.Run) or "<empty>",
		animIds.Shoot ~= "" and normalizeAnimId(animIds.Shoot) or "<empty>",
		animIds.Inspect ~= "" and normalizeAnimId(animIds.Inspect) or "<empty>",
		animIds.Reload ~= "" and normalizeAnimId(animIds.Reload) or "<empty>",
		animIds.ReloadFailed ~= "" and normalizeAnimId(animIds.ReloadFailed) or "<empty>"
	)
	debugLog(
		"duration overrides (clone=%s): Inspect=%s Reload=%s ReloadFailed=%s",
		clone.Name,
		tostring(durationOverrides.Inspect),
		tostring(durationOverrides.Reload),
		tostring(durationOverrides.ReloadFailed)
	)
	debugLog("reloadFailed probability (clone=%s): 1/%d", clone.Name, reloadFailedOneIn)

	local tracks: TrackSet = {
		Idle = loadTrack(
			animator,
			animIds.Idle ~= "" and animIds.Idle or (Config.SniperViewModelAnimIdle or ""),
			true,
			movementPriority
		),
		Walk = loadTrack(
			animator,
			animIds.Walk ~= "" and animIds.Walk or (Config.SniperViewModelAnimWalk or ""),
			true,
			movementPriority
		),
		Run = loadTrack(
			animator,
			animIds.Run ~= "" and animIds.Run or (Config.SniperViewModelAnimRun or ""),
			true,
			movementPriority
		),
		Air = loadTrack(
			animator,
			animIds.Air ~= "" and animIds.Air or (Config.SniperViewModelAnimJump or ""),
			true,
			movementPriority
		),
		Recoil = loadTrack(
			animator,
			animIds.Recoil ~= "" and animIds.Recoil or (Config.SniperViewModelAnimRecoil or ""),
			false,
			actionPriority
		),
		Shoot = loadTrack(
			animator,
			animIds.Shoot ~= "" and animIds.Shoot or (Config.SniperViewModelAnimShoot or ""),
			false,
			actionPriority
		),
		Inspect = loadTrack(
			animator,
			animIds.Inspect ~= "" and animIds.Inspect or (Config.SniperViewModelAnimInspect or ""),
			false,
			inspectPriority
		),
		Reload = loadTrack(animator, animIds.Reload, false, actionPriority),
		ReloadFailed = loadTrack(animator, animIds.ReloadFailed, false, actionPriority),
		Collider = loadTrack(animator, animIds.Collider, false, actionPriority),
	}

	local function forceLooped(tr: AnimationTrack?)
		if tr then
			tr.Looped = true
		end
	end
	forceLooped(tracks.Idle)
	forceLooped(tracks.Walk)
	forceLooped(tracks.Run)
	forceLooped(tracks.Air)
	if tracks.Shoot then
		tracks.Shoot.Looped = false
	end

	if
		not tracks.Idle
		and not tracks.Walk
		and not tracks.Run
		and not tracks.Air
		and not tracks.Recoil
		and not tracks.Shoot
		and not tracks.Inspect
		and not tracks.Reload
		and not tracks.ReloadFailed
		and not tracks.Collider
	then
		debugLog("attachToClone failed: no tracks loaded (clone=%s)", clone.Name)
		return nil
	end

	debugLog(
		"attachToClone loaded tracks (clone=%s): Inspect=%s Reload=%s ReloadFailed=%s Idle=%s Walk=%s Run=%s Air=%s Recoil=%s Shoot=%s",
		clone.Name,
		tostring(tracks.Inspect ~= nil),
		tostring(tracks.Reload ~= nil),
		tostring(tracks.ReloadFailed ~= nil),
		tostring(tracks.Idle ~= nil),
		tostring(tracks.Walk ~= nil),
		tostring(tracks.Run ~= nil),
		tostring(tracks.Air ~= nil),
		tostring(tracks.Recoil ~= nil),
		tostring(tracks.Shoot ~= nil)
	)

	local hasLocomotion = tracks.Idle ~= nil or tracks.Walk ~= nil or tracks.Run ~= nil or tracks.Air ~= nil
	local colliderPart = findColliderPart(clone)
	if colliderPart then
		pcall(function()
			colliderPart.CanTouch = true
			colliderPart.CanQuery = true
		end)
	end

	local self = setmetatable({
		_gone = false,
		_model = clone,
		_player = player,
		_tracks = tracks,
		_hasLocomotion = hasLocomotion,
		_locoPhase = nil :: LocomotionPhase?,
		_locoTrack = nil :: AnimationTrack?,
		_crossFade = Config.SniperViewModelAnimCrossFade or 0.12,
		_durationOverrides = durationOverrides,
		_reloadFailedOneIn = reloadFailedOneIn,
		_colliderPart = colliderPart,
		_colliderActive = false,
		_colliderLocked = false,
		_colliderReleaseUntil = nil :: number?,
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
