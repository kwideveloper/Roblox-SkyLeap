-- Client-side binding for the Sniper Tool: input, local laser preview, remote fire request.

local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local SniperGunStats = require(script.Parent.SniperGunStats)
local SniperAmmoHudClient = require(script.Parent.SniperAmmoHudClient)

local Config = require(script.Parent.Config)
local SniperShotVisualizer = require(script.Parent.SniperShotVisualizer)
local SniperFirstPersonGate = require(script.Parent.SniperFirstPersonGate)
local SniperLoadoutState = require(script.Parent.SniperLoadoutState)
local SniperWeaponBarClient = require(script.Parent.SniperWeaponBarClient)
local SniperRobloxCompanionClient = require(script.Parent.SniperRobloxCompanionClient)
local SniperViewModelAnimator = require(script.Parent.SniperViewModelAnimator)
local ViewModelClient = require(script.Parent.ViewModelClient)
local SniperCrosshairClient = require(script.Parent.SniperCrosshairClient)
local SniperMuzzleSmoke = require(script.Parent.SniperMuzzleSmoke)
local SniperWeaponPartResolve = require(script.Parent.SniperWeaponPartResolve)

local rng = Random.new()
local DEBUG_PREFIX = "[SniperClientAnim]"
local DEFAULT_RELOAD_FAILED_EASTER_EGG_DENOMINATOR = 10000

local function debugLog(msg: string, ...: any)
	if Config.SniperDebugApplyHit ~= true then
		return
	end
	print(DEBUG_PREFIX .. " " .. string.format(msg, ...))
end

local function scopeDebugEnabled(): boolean
	return Config.SniperDebugApplyHit == true
end

local function getCasingShellTemplate(): Model?
	local parent: Instance = ReplicatedStorage
	local path = Config.CasingShellPath
	if type(path) == "table" then
		for _, segment in ipairs(path) do
			if type(segment) == "string" and segment ~= "" then
				local sub = parent:FindFirstChild(segment)
				if not sub then
					return nil
				end
				parent = sub
			end
		end
	end
	local m = parent:FindFirstChild(Config.CasingShellModelName)
	if m and m:IsA("Model") then
		return m
	end
	return nil
end

local function spawnPhysicalCasing(tool: Tool, localPlayer: Player)
	if not Config.CasingPhysicsEnabled then
		return
	end

	local cam = Workspace.CurrentCamera
	local ejectName = Config.CasingEjectPartName or "CasingEject"
	local cf: CFrame?

	-- 1) Viewmodel eject point (virtual Backpack + first person, or any time clone is visible).
	if Config.SniperViewModelEnabled then
		cf = ViewModelClient.getViewModelPartWorldCFrame(tool, ejectName)
	end
	-- 2) Tool part only when equipped on Character (world CFrame is valid).
	if not cf then
		local ch = localPlayer.Character
		local eject = tool:FindFirstChild(ejectName, true)
		if eject and eject:IsA("BasePart") and ch and tool.Parent == ch then
			cf = eject.CFrame
		end
	end
	-- 3) Backpack + no viewmodel eject: camera offset.
	if not cf and Config.SniperVirtualInventoryEnabled and tool.Parent == localPlayer:FindFirstChildOfClass("Backpack") then
		if cam and Config.SniperCasingEjectCameraCFrame then
			cf = cam.CFrame * Config.SniperCasingEjectCameraCFrame
		end
	end
	if not cf then
		return
	end

	local template = getCasingShellTemplate()
	if not template then
		return
	end

	local clone = template:Clone()
	clone.Name = "CasingShellActive"

	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = Config.CasingCloneCanCollide
			d.CanQuery = false
			d:BreakJoints()
		end
	end

	local root = clone.PrimaryPart
	if not root then
		root = clone:FindFirstChildWhichIsA("BasePart", true)
	end
	if not root then
		clone:Destroy()
		return
	end
	if not clone.PrimaryPart then
		clone.PrimaryPart = root
	end

	clone.Parent = Workspace

	local bump = Vector3.new(
		rng:NextNumber(0.06, 0.22) * (rng:NextInteger(0, 1) == 1 and 1 or -1),
		rng:NextNumber(-0.06, 0.06),
		rng:NextNumber(-0.06, 0.06)
	)
	clone:PivotTo(cf * CFrame.new(bump))

	local vel: Vector3
	if cam and Config.CasingEjectUseViewerLeft ~= false then
		local camRight = cam.CFrame.RightVector
		local leftDir = -camRight
		local flat = Vector3.new(leftDir.X, 0, leftDir.Z)
		if flat.Magnitude > 0.12 then
			leftDir = flat.Unit
		else
			leftDir = -camRight.Unit
		end
		local up = cam.CFrame.UpVector.Unit
		local look = cam.CFrame.LookVector.Unit
		local fwd = rng:NextNumber(
			Config.CasingEjectViewerForwardSpreadMin or -5,
			Config.CasingEjectViewerForwardSpreadMax or 5
		)
		local jitter = up * rng:NextNumber(0.12, 0.95) + look * (fwd * 0.14)
		local wMain = rng:NextNumber(0.68, 1.0)
		local dir = (leftDir * wMain + jitter).Unit
		if dir:Dot(-camRight) < 0.28 then
			dir = (leftDir * 0.9 + up * 0.1).Unit
		end
		local spd = rng:NextNumber(
			Config.CasingEjectViewerLeftSpeedMin or 11,
			Config.CasingEjectViewerLeftSpeedMax or 24
		)
		local upBoost = rng:NextNumber(
			Config.CasingEjectViewerUpBoostMin or 2,
			Config.CasingEjectViewerUpBoostMax or 11
		)
		vel = dir * spd + up * upBoost
	else
		local r = rng:NextNumber(Config.CasingSpeedRightMin, Config.CasingSpeedRightMax)
		local u = rng:NextNumber(Config.CasingSpeedUpMin, Config.CasingSpeedUpMax)
		local l = rng:NextNumber(Config.CasingSpeedLookMin, Config.CasingSpeedLookMax)
		vel = cf.RightVector * r + cf.UpVector * u + cf.LookVector * l
	end
	local angVel = Vector3.new(
		rng:NextNumber(Config.CasingSpinRadMin, Config.CasingSpinRadMax),
		rng:NextNumber(Config.CasingSpinRadMin, Config.CasingSpinRadMax),
		rng:NextNumber(Config.CasingSpinRadMin, Config.CasingSpinRadMax)
	)
	root.AssemblyLinearVelocity = vel
	root.AssemblyAngularVelocity = angVel

	local life = rng:NextNumber(Config.CasingLifetimeMinSeconds, Config.CasingLifetimeMaxSeconds)
	Debris:AddItem(clone, life)
end

local function getRemotes()
	local folder = ReplicatedStorage:WaitForChild("Remotes", 30)
	if not folder then
		return nil
	end
	return {
		RequestFire = folder:WaitForChild("SniperRequestFire", 10),
		RequestReload = folder:WaitForChild("SniperRequestReload", 10),
		LaserFx = folder:WaitForChild("SniperLaserFx", 10),
		AudioFeedback = folder:WaitForChild("SniperAudioFeedback", 10),
	}
end

local function scheduleFireSoundVolumeFadeOut(sound: Sound, peakVolume: number, fadeSeconds: number)
	if fadeSeconds <= 0 or peakVolume <= 0 then
		return
	end
	task.spawn(function()
		if not sound.IsLoaded then
			local ok = pcall(function()
				sound.Loaded:Wait()
			end)
			if not ok then
				return
			end
		end
		if not sound.Parent then
			return
		end
		local len = sound.TimeLength
		if len <= 0 then
			return
		end
		local fadeTime = math.min(fadeSeconds, len * 0.99)
		local waitBeforeFade = math.max(0, len - fadeTime)
		task.delay(waitBeforeFade, function()
			if not sound.Parent then
				return
			end
			sound.Volume = peakVolume
			local tween = TweenService:Create(
				sound,
				TweenInfo.new(fadeTime, Enum.EasingStyle.Linear, Enum.EasingDirection.In),
				{ Volume = 0 }
			)
			tween:Play()
		end)
	end)
end

local function playOneShot2D(soundId: string, volume: number, fadeOutSeconds: number?)
	if soundId == nil or soundId == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.Parent = SoundService
	sound:Play()
	if fadeOutSeconds and fadeOutSeconds > 0 then
		scheduleFireSoundVolumeFadeOut(sound, volume, fadeOutSeconds)
	end
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
	Debris:AddItem(sound, 12)
end

local function playOneShot3D(soundId: string, volume: number, worldPosition: Vector3, maxDistance: number?, fadeOutSeconds: number?)
	if soundId == nil or soundId == "" then
		return
	end
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Position = worldPosition
	part.Parent = Workspace

	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.MaxDistance = maxDistance or 120
	sound.Parent = part
	sound:Play()
	if fadeOutSeconds and fadeOutSeconds > 0 then
		scheduleFireSoundVolumeFadeOut(sound, volume, fadeOutSeconds)
	end
	sound.Ended:Connect(function()
		part:Destroy()
	end)
	Debris:AddItem(part, 12)
end

local function raycastPreview(origin: Vector3, directionUnit: Vector3, filterInst: Instance)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { filterInst }
	local result = Workspace:Raycast(origin, directionUnit * Config.MaxRange, params)
	if result then
		return result.Position
	end
	return origin + directionUnit * Config.MaxRange
end

local function bindTool(tool: Tool, options: { LocalPlayer: Player })
	if tool:GetAttribute("_SniperClientBound") then
		return
	end
	tool:SetAttribute("_SniperClientBound", true)
	local localPlayer = options.LocalPlayer

	local fireHoldHeartbeatConn: RBXScriptConnection? = nil
	local scopeRenderConn: RBXScriptConnection? = nil
	local scopeGui: ScreenGui? = nil
	local scopeZoomLabel: TextLabel? = nil
	local scopeReticleRoot: Frame? = nil
	local scopeZoomIndex = 1
	local scopedVisualActive = false
	local scopedFovApplied = false
	local aimButtonHeld = false
	local scopeRecoilPitchDeg = 0
	local scopeRecoilYawDeg = 0
	local scopeRecoilYawSign = 1
	local scopeAppliedPitchRad = 0
	local scopeAppliedYawRad = 0
	local scopeAppliedForwardStuds = 0
	local scopeFovApplied = false
	local scopeLastFov: number? = nil
	local blurEffect: BlurEffect? = nil
	local dofEffect: DepthOfFieldEffect? = nil
	local savedMouseSensitivity: number? = nil
	local scopeLastCameraCf: CFrame? = nil
	local scopeDebugLastAt: { [string]: number } = {}
	local localNextAllowedShotAt = 0
	local localReloadEndsAt = 0
	local lastObservedReloadEndsAt = 0
	local lastReloadSoundAt = -math.huge
	local lastReloadAnimAt = -math.huge

	local function scopeLogThrottled(key: string, everySec: number, msg: string, ...: any)
		if not scopeDebugEnabled() then
			return
		end
		local now = os.clock()
		local last = scopeDebugLastAt[key] or -math.huge
		if (now - last) < everySec then
			return
		end
		scopeDebugLastAt[key] = now
		debugLog("[ScopeDebug] " .. msg, ...)
	end

	local function ensureClientStateFolder(): Folder
		local cs = ReplicatedStorage:FindFirstChild("ClientState")
		if not cs then
			cs = Instance.new("Folder")
			cs.Name = "ClientState"
			cs.Parent = ReplicatedStorage
		end
		return cs
	end

	local function setFovOverride(enable: boolean, fovValue: number)
		local cs = ensureClientStateFolder()
		local active = cs:FindFirstChild("CameraFovOverrideActive")
		if not active then
			active = Instance.new("BoolValue")
			active.Name = "CameraFovOverrideActive"
			active.Parent = cs
		end
		active.Value = enable

		local value = cs:FindFirstChild("CameraFovOverrideValue")
		if not value then
			value = Instance.new("NumberValue")
			value.Name = "CameraFovOverrideValue"
			value.Parent = cs
		end
		value.Value = math.clamp(tonumber(fovValue) or 70, 10, 120)
	end

	local function zoomLevelToFov(zoomLevel: number): number
		local baseFov = tonumber(Config.SniperScopeBaseFov) or 70
		local z = math.max(1.001, zoomLevel)
		return math.clamp(baseFov / z, 10, 120)
	end

	local function ensureScopePostFx()
		if blurEffect == nil or blurEffect.Parent == nil then
			local e = Lighting:FindFirstChild("SkyLeapSniperScopeBlur")
			if e and e:IsA("BlurEffect") then
				blurEffect = e
			else
				e = Instance.new("BlurEffect")
				e.Name = "SkyLeapSniperScopeBlur"
				e.Size = 0
				e.Parent = Lighting
				blurEffect = e
			end
		end
		if dofEffect == nil or dofEffect.Parent == nil then
			local e = Lighting:FindFirstChild("SkyLeapSniperScopeDoF")
			if e and e:IsA("DepthOfFieldEffect") then
				dofEffect = e
			else
				e = Instance.new("DepthOfFieldEffect")
				e.Name = "SkyLeapSniperScopeDoF"
				e.FarIntensity = 0
				e.NearIntensity = 0
				e.FocusDistance = 50
				e.InFocusRadius = 30
				e.Parent = Lighting
				dofEffect = e
			end
		end
	end

	local function applyScopePostFx(on: boolean)
		if Config.SniperScopePostFxEnabled == false then
			if blurEffect then
				blurEffect.Size = 0
			end
			if dofEffect then
				dofEffect.FarIntensity = 0
				dofEffect.NearIntensity = 0
			end
			return
		end
		ensureScopePostFx()
		if blurEffect then
			TweenService:Create(
				blurEffect,
				TweenInfo.new(
					on and (Config.SniperScopeZoomInSeconds or 0.2) or (Config.SniperScopeZoomOutSeconds or 0.14),
					Enum.EasingStyle.Sine,
					Enum.EasingDirection.InOut
				),
				{ Size = on and (Config.SniperScopeBlurSize or 10) or 0 }
			):Play()
		end
		if dofEffect then
			TweenService:Create(
				dofEffect,
				TweenInfo.new(
					on and (Config.SniperScopeZoomInSeconds or 0.2) or (Config.SniperScopeZoomOutSeconds or 0.14),
					Enum.EasingStyle.Sine,
					Enum.EasingDirection.InOut
				),
				{
					FarIntensity = on and (Config.SniperScopeDofFarIntensity or 0.45) or 0,
					NearIntensity = on and (Config.SniperScopeDofNearIntensity or 0.28) or 0,
				}
			):Play()
		end
	end

	local function getScopeZoomLevels(): { number }
		local raw = Config.SniperScopeZoomLevels
		if type(raw) ~= "table" then
			raw = Config.SniperScopeZoomFovLevels
		end
		local levels: { number } = {}
		if type(raw) == "table" then
			for _, n in ipairs(raw) do
				if type(n) == "number" and n > 0 and n == n and n ~= math.huge and n ~= -math.huge then
					table.insert(levels, n)
				end
			end
		end
		if #levels == 0 then
			levels = { 2, 3, 4, 5, 10 }
		end
		return levels
	end

	local function getGunModelForAimConfig(): Model?
		local vmGun = ViewModelClient.getGunModelForTool(tool)
		if vmGun and vmGun:IsA("Model") then
			return vmGun
		end
		local gun = tool:FindFirstChild("Gun")
		if gun and gun:IsA("Model") then
			return gun
		end
		return nil
	end

	local function readAimEnabledFromGun(): boolean
		local gun = getGunModelForAimConfig()
		if not gun then
			return true
		end
		local v = gun:GetAttribute("SniperAimEnabled")
		if type(v) == "boolean" then
			return v
		end
		return true
	end

	local function readAimZoomCountFromGun(): number?
		local gun = getGunModelForAimConfig()
		if not gun then
			return nil
		end
		local v = gun:GetAttribute("SniperAimZoomCount")
		if type(v) ~= "number" then
			return nil
		end
		if v ~= v or v == math.huge or v == -math.huge then
			return nil
		end
		return math.max(1, math.floor(v + 0.5))
	end

	local function getEffectiveScopeZoomLevels(): { number }
		local levels = getScopeZoomLevels()
		local count = readAimZoomCountFromGun()
		if type(count) ~= "number" then
			return levels
		end
		if count >= #levels then
			return levels
		end
		local cut: { number } = {}
		for i = 1, count do
			table.insert(cut, levels[i])
		end
		return cut
	end

	local function getScopeDisplayLevels(): { number? }
		local raw = Config.SniperScopeZoomDisplayLevels
		local labels: { number? } = {}
		if type(raw) == "table" then
			for _, n in ipairs(raw) do
				if type(n) == "number" and n > 0 and n == n and n ~= math.huge and n ~= -math.huge then
					table.insert(labels, n)
				end
			end
		end
		return labels
	end

	local function getScopeForwardOffsetLevels(): { number }
		local raw = Config.SniperScopeZoomForwardOffsetStudsLevels
		local levels: { number } = {}
		if type(raw) == "table" then
			for _, n in ipairs(raw) do
				if type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge then
					table.insert(levels, math.max(0, n))
				end
			end
		end
		return levels
	end

	local function computeDynamicScopeForwardStuds(character: Model?, zoomLevel: number): number
		local fallbackDist = tonumber(Config.SniperScopeZoomDistanceFallbackStuds) or 220
		local minOffset = tonumber(Config.SniperScopeZoomForwardOffsetMinStuds) or 0
		local maxOffset = tonumber(Config.SniperScopeZoomForwardOffsetMaxStuds) or 140
		minOffset = math.max(0, minOffset)
		maxOffset = math.max(minOffset, maxOffset)

		local camera = Workspace.CurrentCamera
		if not camera then
			return minOffset
		end

		local vs = camera.ViewportSize
		local ray = camera:ViewportPointToRay(vs.X * 0.5, vs.Y * 0.5)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character }
		local hit = Workspace:Raycast(ray.Origin, ray.Direction * Config.MaxRange, params)

		local dist = fallbackDist
		if hit then
			dist = (hit.Position - ray.Origin).Magnitude
		end
		if dist ~= dist or dist == math.huge or dist == -math.huge then
			dist = fallbackDist
		end
		dist = math.max(1, dist)

		local z = math.max(1.0001, zoomLevel)
		local desired = dist * (1 - 1 / z)
		return math.clamp(desired, minOffset, maxOffset)
	end

	local function resolveScopeForwardTargetStuds(character: Model?, zoomLevel: number): number
		if Config.SniperScopeZoomUseDistanceModel == false then
			local forwardLevels = getScopeForwardOffsetLevels()
			return forwardLevels[scopeZoomIndex] or 0
		end
		return computeDynamicScopeForwardStuds(character, zoomLevel)
	end

	local function ensureScopeGui(): ScreenGui?
		if scopeGui and scopeGui.Parent then
			return scopeGui
		end
		local pg = localPlayer:FindFirstChild("PlayerGui") or localPlayer:WaitForChild("PlayerGui")
		if not pg then
			return nil
		end
		local existing = pg:FindFirstChild("SkyLeapSniperScope")
		if existing and existing:IsA("ScreenGui") then
			scopeGui = existing
			scopeZoomLabel = existing:FindFirstChild("ZoomLabel", true) :: TextLabel?
			return scopeGui
		end
		local g = Instance.new("ScreenGui")
		g.Name = "SkyLeapSniperScope"
		g.ResetOnSpawn = false
		g.IgnoreGuiInset = true
		g.DisplayOrder = (Config.SniperCrosshairGuiDisplayOrder or 2000000) + 2
		g.Enabled = false
		g.Parent = pg

		local root = Instance.new("Frame")
		root.Name = "Root"
		root.BackgroundTransparency = 1
		root.Size = UDim2.fromScale(1, 1)
		root.Parent = g

		local lensDiameterScale = 0.86
		local halfGap = (1 - lensDiameterScale) * 0.5
		local thickness = math.clamp(math.floor(tonumber(Config.SniperScopeRingThicknessPx) or 6), 2, 36)
		local vignetteAlpha = tonumber(Config.SniperScopeOutsideMaskTransparency) or 0.3
		vignetteAlpha = math.clamp(vignetteAlpha, 0, 1)
		local top = Instance.new("Frame")
		top.BackgroundColor3 = Color3.new(0, 0, 0)
		top.BorderSizePixel = 0
		top.BackgroundTransparency = vignetteAlpha
		top.Size = UDim2.new(1, 0, halfGap, 0)
		top.Position = UDim2.fromScale(0, 0)
		top.Parent = root

		local bottom = Instance.new("Frame")
		bottom.BackgroundColor3 = Color3.new(0, 0, 0)
		bottom.BorderSizePixel = 0
		bottom.BackgroundTransparency = vignetteAlpha
		bottom.Size = UDim2.new(1, 0, halfGap, 0)
		bottom.Position = UDim2.new(0, 0, 1 - halfGap, 0)
		bottom.Parent = root

		local left = Instance.new("Frame")
		left.BackgroundColor3 = Color3.new(0, 0, 0)
		left.BorderSizePixel = 0
		left.BackgroundTransparency = vignetteAlpha
		left.Size = UDim2.new(halfGap, 0, lensDiameterScale, 0)
		left.Position = UDim2.new(0, 0, halfGap, 0)
		left.Parent = root

		local right = Instance.new("Frame")
		right.BackgroundColor3 = Color3.new(0, 0, 0)
		right.BorderSizePixel = 0
		right.BackgroundTransparency = vignetteAlpha
		right.Size = UDim2.new(halfGap, 0, lensDiameterScale, 0)
		right.Position = UDim2.new(1 - halfGap, 0, halfGap, 0)
		right.Parent = root

		local lensRing = Instance.new("Frame")
		lensRing.Name = "LensRing"
		lensRing.AnchorPoint = Vector2.new(0.5, 0.5)
		lensRing.Position = UDim2.fromScale(0.5, 0.5)
		lensRing.Size = UDim2.fromScale(lensDiameterScale, lensDiameterScale)
		lensRing.BackgroundTransparency = 1
		lensRing.Parent = root
		local ringCorner = Instance.new("UICorner")
		ringCorner.CornerRadius = UDim.new(1, 0)
		ringCorner.Parent = lensRing
		local ringStroke = Instance.new("UIStroke")
		ringStroke.Thickness = thickness
		ringStroke.Color = Color3.new(0, 0, 0)
		ringStroke.Transparency = 0.15
		ringStroke.Parent = lensRing

		local reticle = Instance.new("Frame")
		reticle.Name = "Reticle"
		reticle.AnchorPoint = Vector2.new(0.5, 0.5)
		reticle.Position = UDim2.fromScale(0.5, 0.5)
		reticle.Size = UDim2.fromOffset(2, 2)
		reticle.BackgroundTransparency = 1
		reticle.Parent = root
		scopeReticleRoot = reticle

		local hLine = Instance.new("Frame")
		hLine.Name = "Horizontal"
		hLine.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
		hLine.BorderSizePixel = 0
		hLine.AnchorPoint = Vector2.new(0.5, 0.5)
		hLine.Position = UDim2.fromScale(0.5, 0.5)
		hLine.Size = UDim2.fromOffset(320, 1)
		hLine.Parent = reticle

		local vLine = Instance.new("Frame")
		vLine.Name = "Vertical"
		vLine.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
		vLine.BorderSizePixel = 0
		vLine.AnchorPoint = Vector2.new(0.5, 0.5)
		vLine.Position = UDim2.fromScale(0.5, 0.5)
		vLine.Size = UDim2.fromOffset(1, 320)
		vLine.Parent = reticle

		local centerDot = Instance.new("Frame")
		centerDot.Name = "CenterDot"
		centerDot.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
		centerDot.BorderSizePixel = 0
		centerDot.AnchorPoint = Vector2.new(0.5, 0.5)
		centerDot.Position = UDim2.fromScale(0.5, 0.5)
		centerDot.Size = UDim2.fromOffset(3, 3)
		centerDot.Parent = reticle

		local label = Instance.new("TextLabel")
		label.Name = "ZoomLabel"
		label.BackgroundTransparency = 1
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, 0.8)
		label.Size = UDim2.fromOffset(160, 28)
		label.Font = Enum.Font.GothamBold
		label.TextSize = 16
		label.TextColor3 = Color3.fromRGB(220, 220, 220)
		label.TextStrokeColor3 = Color3.new(0, 0, 0)
		label.TextStrokeTransparency = 0.35
		label.Text = ""
		label.Parent = root

		scopeGui = g
		scopeZoomLabel = label
		return scopeGui
	end

	local function setScopeVisualActive(on: boolean, zoomLevel: number)
		local gui = ensureScopeGui()
		if gui then
			gui.Enabled = on
		end
		if scopeZoomLabel then
			local labels = getScopeDisplayLevels()
			local x = zoomLevel
			if labels[scopeZoomIndex] ~= nil then
				x = labels[scopeZoomIndex] :: number
			end
			scopeZoomLabel.Text = string.format("%.1fx  [Mouse Wheel]", x)
		end
		if not on and scopeReticleRoot then
			scopeReticleRoot.Position = UDim2.fromScale(0.5, 0.5)
		end
	end

	local function isReloadBlockingAim(nowServer: number?): boolean
		local now = nowServer or Workspace:GetServerTimeNow()
		if now < localReloadEndsAt then
			return true
		end
		local reloadEndsAt = tool:GetAttribute(SniperGunStats.ToolAttrReloadEndsAt)
		if type(reloadEndsAt) == "number" and reloadEndsAt > now then
			return true
		end
		return false
	end
	tool.Destroying:Connect(function()
		ViewModelClient.setAimHeld(tool, false)
		if scopeFovApplied then
			scopeFovApplied = false
			scopeLastFov = nil
			setFovOverride(false, tonumber(Config.SniperScopeBaseFov) or 70)
		end
		applyScopePostFx(false)
		if savedMouseSensitivity ~= nil then
			UserInputService.MouseDeltaSensitivity = savedMouseSensitivity
			savedMouseSensitivity = nil
		end
		if scopeGui then
			scopeGui.Enabled = false
		end
		if scopeRenderConn then
			scopeRenderConn:Disconnect()
			scopeRenderConn = nil
		end
		if fireHoldHeartbeatConn then
			fireHoldHeartbeatConn:Disconnect()
			fireHoldHeartbeatConn = nil
		end
		SniperLoadoutState.clearSniperTool(tool)
	end)

	if Config.SniperViewModelEnabled then
		ViewModelClient.attach(tool, options.LocalPlayer)
	end
	if Config.SniperCrosshairEnabled then
		SniperCrosshairClient.attach(tool, options.LocalPlayer)
	end

	local remotes = getRemotes()
	if not remotes or not remotes.RequestFire or not remotes.RequestReload or not remotes.LaserFx or not remotes.AudioFeedback then
		warn("[Sniper] Remotes missing — ensure Remotes.server.lua ran.")
		return
	end

	local barrelName = Config.FireOriginPartName
	local barrel: BasePart? = nil
	if not Config.SniperVirtualInventoryEnabled then
		local deadline = os.clock() + 15
		repeat
			barrel = SniperWeaponPartResolve.findFirstBasePartNamed(tool, barrelName)
			if barrel then
				break
			end
			task.wait(0.05)
		until os.clock() >= deadline
		if not barrel then
			warn(("[Sniper] Tool needs a BasePart named %q under the tool (FireOriginPartName); nested Model with same name is OK."):format(barrelName))
			return
		end
	else
		barrel = SniperWeaponPartResolve.findFirstBasePartNamed(tool, barrelName)
	end

	local function readAmmoAndMag(): (number?, number?)
		local ammo = tool:GetAttribute(SniperGunStats.ToolAttrAmmo)
		local mag = tool:GetAttribute(SniperGunStats.ToolAttrMagSize)
		if type(ammo) ~= "number" or type(mag) ~= "number" then
			return nil, nil
		end
		return ammo, mag
	end

	local function isServerReloadActive(nowServer: number): boolean
		local reloadEndsAt = tool:GetAttribute(SniperGunStats.ToolAttrReloadEndsAt)
		return type(reloadEndsAt) == "number" and reloadEndsAt > nowServer
	end

	local function playReloadSoundIfNeeded(nowServer: number)
		if (nowServer - lastReloadSoundAt) < 0.12 then
			return
		end
		lastReloadSoundAt = nowServer
		playOneShot2D(Config.ReloadSoundId, Config.ReloadSoundVolume)
	end

	local function playReloadAnimationIfNeeded(source: string, desiredDuration: number, nowServer: number)
		if (nowServer - lastReloadAnimAt) < 0.12 then
			return
		end
		lastReloadAnimAt = nowServer
		debugLog("Playing reload animation (%s) duration=%.3f", source, desiredDuration)
		SniperViewModelAnimator.notifyReload(localPlayer, desiredDuration)
		local oneIn = SniperViewModelAnimator.getReloadFailedOneIn(localPlayer)
		if type(oneIn) ~= "number" or oneIn < 1 then
			oneIn = DEFAULT_RELOAD_FAILED_EASTER_EGG_DENOMINATOR
		end
		local easterRoll = rng:NextInteger(1, oneIn)
		if easterRoll == 1 then
			debugLog("Reload easter egg triggered (%s): also playing ReloadFailed (1/%d)", source, oneIn)
			SniperViewModelAnimator.notifyReloadFailed(localPlayer, desiredDuration)
		end
	end

	remotes.LaserFx.OnClientEvent:Connect(function(shooterUserId: number, from: Vector3, to: Vector3)
		if shooterUserId == localPlayer.UserId then
			return
		end
		SniperShotVisualizer.play(from, to)
		if Config.FireSoundForOthersId ~= "" then
			playOneShot3D(
				Config.FireSoundForOthersId,
				Config.FireSoundForOthersVolume,
				from,
				nil,
				Config.FireSoundForOthersFadeOutSeconds
			)
		end
	end)

	remotes.AudioFeedback.OnClientEvent:Connect(function(kind: string)
		if kind == "KillConfirm" then
			playOneShot2D(Config.KillConfirmSoundId, Config.KillConfirmVolume)
		elseif kind == "VictimDeath" then
			playOneShot2D(Config.VictimDeathSoundId, Config.VictimDeathVolume)
		end
	end)

	tool:GetAttributeChangedSignal(SniperGunStats.ToolAttrReloadEndsAt):Connect(function()
		local nowServer = Workspace:GetServerTimeNow()
		local reloadEndsAt = tool:GetAttribute(SniperGunStats.ToolAttrReloadEndsAt)
		if type(reloadEndsAt) == "number" then
			if reloadEndsAt > nowServer and reloadEndsAt > lastObservedReloadEndsAt then
				playReloadSoundIfNeeded(nowServer)
				playReloadAnimationIfNeeded("server-reload-attr", math.max(0.05, reloadEndsAt - nowServer), nowServer)
				ViewModelClient.setAimHeld(tool, false)
			end
			lastObservedReloadEndsAt = reloadEndsAt
		else
			lastObservedReloadEndsAt = 0
		end
	end)

	local function isReadyToFire(): boolean
		local ch = localPlayer.Character
		if not ch then
			return false
		end
		if Config.SniperVirtualInventoryEnabled then
			local bp = localPlayer:FindFirstChildOfClass("Backpack")
			return bp ~= nil
				and tool.Parent == bp
				and SniperLoadoutState.isSniperActive(tool)
				and SniperFirstPersonGate.isCameraCloseForFirstPerson(localPlayer)
		end
		return tool.Parent == ch and SniperFirstPersonGate.isCameraCloseForFirstPerson(localPlayer)
	end

	local function explainNotReady(): string
		local ch = localPlayer.Character
		if not ch then
			return "no character"
		end
		local inFirstPerson = SniperFirstPersonGate.isCameraCloseForFirstPerson(localPlayer)
		if Config.SniperVirtualInventoryEnabled then
			local bp = localPlayer:FindFirstChildOfClass("Backpack")
			if not bp then
				return "no backpack"
			end
			if tool.Parent ~= bp then
				return "tool not in backpack (virtual inventory mode)"
			end
			if not SniperLoadoutState.isSniperActive(tool) then
				return "sniper slot inactive"
			end
			if not inFirstPerson then
				return "camera not in first person range"
			end
			return "unknown virtual inventory reason"
		end
		if tool.Parent ~= ch then
			return "tool not equipped on character"
		end
		if not inFirstPerson then
			return "camera not in first person range"
		end
		return "unknown reason"
	end

	local inspectKey = Config.SniperViewModelInspectKeyCode or Enum.KeyCode.F
	local reloadKey = Config.SniperReloadKeyCode or Enum.KeyCode.R

	local function tryStartReload(triggerSource: string, playFailedWhenFull: boolean): boolean
		local nowServer = Workspace:GetServerTimeNow()
		if nowServer < localReloadEndsAt then
			debugLog(
				"Reload blocked (%s): local reload cooldown active (endsAt=%.3f now=%.3f)",
				triggerSource,
				localReloadEndsAt,
				nowServer
			)
			return false
		end
		if isServerReloadActive(nowServer) then
			debugLog("Reload blocked (%s): server reports active reload", triggerSource)
			local reloadEndsAt = tool:GetAttribute(SniperGunStats.ToolAttrReloadEndsAt)
			if type(reloadEndsAt) == "number" then
				localReloadEndsAt = math.max(localReloadEndsAt, reloadEndsAt)
			end
			return false
		end

		local ammo, mag = readAmmoAndMag()
		local gun = ViewModelClient.getGunModelForTool(tool)
		local stats = SniperGunStats.readForClientLocal(tool, localPlayer, gun)
		if ammo ~= nil and mag ~= nil and ammo >= mag then
			debugLog("Reload blocked (%s): magazine full (ammo=%s mag=%s)", triggerSource, tostring(ammo), tostring(mag))
			if playFailedWhenFull then
				SniperViewModelAnimator.notifyReloadFailed(localPlayer, stats.reloadDuration)
			end
			return false
		end

		debugLog("Reload accepted (%s), requesting server + playing reload animation", triggerSource)
		remotes.RequestReload:FireServer()
		playReloadAnimationIfNeeded(triggerSource, stats.reloadDuration, nowServer)
		localReloadEndsAt = nowServer + stats.reloadDuration
		ViewModelClient.setAimHeld(tool, false)
		playReloadSoundIfNeeded(nowServer)
		return true
	end

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.Keyboard or input.KeyCode ~= inspectKey then
			return
		end
		debugLog("Inspect key detected (%s)", tostring(inspectKey))
		if not isReadyToFire() then
			debugLog("Inspect blocked: %s", explainNotReady())
			return
		end
		debugLog("Inspect accepted, notifying animator")
		SniperViewModelAnimator.notifyInspect(localPlayer)
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.Keyboard or input.KeyCode ~= reloadKey then
			return
		end
		debugLog("Reload key detected (%s)", tostring(reloadKey))
		if not isReadyToFire() then
			debugLog("Reload blocked: %s", explainNotReady())
			return
		end
		tryStartReload("manual-key", true)
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton2 then
			return
		end
		if not readAimEnabledFromGun() then
			return
		end
		aimButtonHeld = true
		if not isReloadBlockingAim() then
			ViewModelClient.setAimHeld(tool, true)
		else
			ViewModelClient.setAimHeld(tool, false)
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject, _gameProcessed: boolean)
		if input.UserInputType ~= Enum.UserInputType.MouseButton2 then
			return
		end
		aimButtonHeld = false
		ViewModelClient.setAimHeld(tool, false)
	end)

	UserInputService.InputChanged:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseWheel then
			return
		end
		if not ViewModelClient.isScopeActive(tool) then
			return
		end
		local levels = getEffectiveScopeZoomLevels()
		if #levels <= 1 then
			return
		end
		local delta = input.Position.Z
		if delta > 0 then
			-- Wheel forward: more zoom (lower FOV) -> advance, clamped at max zoom.
			scopeZoomIndex = math.min(#levels, scopeZoomIndex + 1)
			scopeLogThrottled("wheel", 0.05, "wheel up -> zoomIndex=%d/%d", scopeZoomIndex, #levels)
		elseif delta < 0 then
			-- Wheel back: less zoom (higher FOV) -> retreat, clamped at min zoom.
			scopeZoomIndex = math.max(1, scopeZoomIndex - 1)
			scopeLogThrottled("wheel", 0.05, "wheel down -> zoomIndex=%d/%d", scopeZoomIndex, #levels)
		end
	end)

	local function tryFire()
		local character = localPlayer.Character
		if not character then
			return
		end

		local nowServer = Workspace:GetServerTimeNow()
		if nowServer < localNextAllowedShotAt then
			return
		end
		if nowServer < localReloadEndsAt then
			return
		end
		local reloadEndsAt = tool:GetAttribute(SniperGunStats.ToolAttrReloadEndsAt)
		if type(reloadEndsAt) == "number" and reloadEndsAt > nowServer then
			localReloadEndsAt = reloadEndsAt
			return
		end
		local ammo, _mag = readAmmoAndMag()
		if type(ammo) == "number" and ammo <= 0 then
			tryStartReload("auto-empty-on-click", false)
			return
		end
		local nextShotAt = tool:GetAttribute(SniperGunStats.ToolAttrNextShotAt)
		if type(nextShotAt) == "number" and nextShotAt > nowServer then
			localNextAllowedShotAt = nextShotAt
			return
		end

		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end

		local vs = camera.ViewportSize
		local ray = camera:ViewportPointToRay(vs.X * 0.5, vs.Y * 0.5)
		local direction = ray.Direction
		if direction.Magnitude < 1e-4 then
			return
		end
		direction = direction.Unit

		local boreName = Config.FireOriginPartName or "Barrel"
		local boreCf: CFrame? = nil
		if Config.SniperViewModelEnabled then
			boreCf = ViewModelClient.getViewModelPartWorldCFrame(tool, boreName)
		end

		-- Hitscan: viewport center ray (matches crosshair). Using bore position + camera direction causes
		-- parallel-ray parallax (hits land down/right vs reticle when the barrel is below/right of the lens).
		local useViewportHitscan = Config.SniperHitscanUseViewportRayOrigin ~= false
		local hitscanOrigin: Vector3
		if useViewportHitscan then
			hitscanOrigin = ray.Origin + direction * (Config.SniperHitscanViewportOriginAlongDirStuds or 0)
		elseif boreCf then
			hitscanOrigin = boreCf.Position
		else
			local fireOriginCfLegacy: CFrame? = nil
			if barrel then
				fireOriginCfLegacy = barrel.CFrame
			end
			if fireOriginCfLegacy then
				hitscanOrigin = fireOriginCfLegacy.Position
			elseif Config.SniperVirtualInventoryEnabled then
				hitscanOrigin = ray.Origin
			else
				return
			end
		end

		local fireOriginCf: CFrame? = boreCf
		if not fireOriginCf and barrel then
			fireOriginCf = barrel.CFrame
		end

		local endPos = raycastPreview(hitscanOrigin, direction, character)
		-- Tracer line: start at bore (visible gun); hitscan still uses viewport ray above.
		local tracerFrom = hitscanOrigin
		if boreCf then
			tracerFrom = boreCf.Position
		elseif barrel then
			tracerFrom = barrel.Position
		end
		SniperShotVisualizer.play(tracerFrom, endPos)

		-- Smoke only at SniperMuzzleSmokePartName ("Muzzle" by default), not at the bore.
		local smokePartName = Config.SniperMuzzleSmokePartName or "Muzzle"
		local smokeCf: CFrame? = nil
		if Config.SniperViewModelEnabled then
			smokeCf = ViewModelClient.getViewModelPartWorldCFrame(tool, smokePartName)
		end
		local smokeFollowPart: BasePart? = nil
		if Config.SniperViewModelEnabled then
			smokeFollowPart = ViewModelClient.getViewModelPart(tool, smokePartName)
		end
		if not smokeFollowPart then
			local m = SniperWeaponPartResolve.findFirstBasePartNamed(tool, smokePartName)
			if m then
				smokeFollowPart = m
				if not smokeCf then
					smokeCf = m.CFrame
				end
			end
		end
		if smokeCf then
			SniperMuzzleSmoke.play(smokeCf, smokeFollowPart)
		end

		SniperViewModelAnimator.fireRecoil(localPlayer)
		if ViewModelClient.isScopeActive(tool) then
			scopeRecoilPitchDeg += (tonumber(Config.SniperScopeRecoilKickPitchDegrees) or 1.2)
			scopeRecoilYawSign = (scopeRecoilYawSign == 1) and -1 or 1
			scopeRecoilYawDeg += (tonumber(Config.SniperScopeRecoilKickYawDegrees) or 0.22) * scopeRecoilYawSign
		end

		spawnPhysicalCasing(tool, localPlayer)

		playOneShot2D(Config.FireSoundId, Config.FireSoundVolume, Config.FireSoundFadeOutSeconds)

		if Config.ShellCasingSoundId ~= "" then
			local delaySec = Config.ShellCasingDelaySeconds
			local charRef = character
			task.delay(delaySec, function()
				if not charRef.Parent then
					return
				end
				local hrp = charRef:FindFirstChild("HumanoidRootPart") :: BasePart?
				if not hrp then
					return
				end
				local atFeet = hrp.Position + Vector3.new(0, -2.4, 0)
				playOneShot3D(
					Config.ShellCasingSoundId,
					Config.ShellCasingVolume,
					atFeet,
					Config.ShellCasingMaxDistance
				)
			end)
		end

		remotes.RequestFire:FireServer(hitscanOrigin, direction)
		local gun = ViewModelClient.getGunModelForTool(tool)
		local stats = SniperGunStats.readForClientLocal(tool, localPlayer, gun)
		localNextAllowedShotAt = nowServer + stats.shotCooldown
		if type(ammo) == "number" and ammo <= 1 then
			localReloadEndsAt = localNextAllowedShotAt + stats.reloadDuration
			playReloadAnimationIfNeeded("post-shot-empty", stats.reloadDuration, nowServer)
		else
			localReloadEndsAt = 0
		end
	end

	-- Hold primary fire: tryFire() already enforces shotCooldown (from FireRate / ShotCooldown on Gun).
	local fireInputHeld = false
	fireHoldHeartbeatConn = RunService.Heartbeat:Connect(function()
		if not fireInputHeld then
			return
		end
		if not isReadyToFire() then
			return
		end
		tryFire()
	end)

	local function scopeTick(dt: number)
		local aimEnabled = readAimEnabledFromGun()
		if Config.SniperScopeEnabled == false or not aimEnabled then
			aimButtonHeld = false
			ViewModelClient.setAimHeld(tool, false)
			if scopedVisualActive or scopedFovApplied then
				local camera = Workspace.CurrentCamera
				if camera then
					if math.abs(scopeAppliedPitchRad) > 1e-6 or math.abs(scopeAppliedYawRad) > 1e-6 then
						camera.CFrame = camera.CFrame * CFrame.Angles(-scopeAppliedPitchRad, -scopeAppliedYawRad, 0)
					end
					if math.abs(scopeAppliedForwardStuds) > 1e-6 then
						camera.CFrame = camera.CFrame * CFrame.new(0, 0, scopeAppliedForwardStuds)
					end
				end
				scopeAppliedPitchRad = 0
				scopeAppliedYawRad = 0
				scopeAppliedForwardStuds = 0
				if scopeFovApplied then
					scopeFovApplied = false
					scopeLastFov = nil
					setFovOverride(false, tonumber(Config.SniperScopeBaseFov) or 70)
					applyScopePostFx(false)
				end
				if savedMouseSensitivity ~= nil then
					UserInputService.MouseDeltaSensitivity = savedMouseSensitivity
					savedMouseSensitivity = nil
				end
				scopedVisualActive = false
				scopedFovApplied = false
				setScopeVisualActive(false, 1)
			end
			return
		end
		local scopedNow = ViewModelClient.isScopeActive(tool)
		local levels = getEffectiveScopeZoomLevels()
		if scopeZoomIndex < 1 or scopeZoomIndex > #levels then
			scopeZoomIndex = 1
		end
		local targetZoom = levels[scopeZoomIndex]
		local nowServer = Workspace:GetServerTimeNow()
		local canAimNow = not isReloadBlockingAim(nowServer)
		if aimButtonHeld and canAimNow then
			ViewModelClient.setAimHeld(tool, true)
		else
			ViewModelClient.setAimHeld(tool, false)
		end
		if scopedNow then
			if not scopedVisualActive then
				scopedVisualActive = true
				scopeLogThrottled("enter", 0.01, "entered scope (zoomIndex=%d zoom=%.3f)", scopeZoomIndex, targetZoom)
			end
			setScopeVisualActive(true, targetZoom)
			if Config.SniperScopeUseFovZoom ~= false then
				local targetFov = zoomLevelToFov(targetZoom)
				if scopeLastFov == nil or math.abs(targetFov - scopeLastFov) > 1e-4 then
					setFovOverride(true, targetFov)
					scopeLastFov = targetFov
				end
				if not scopeFovApplied then
					scopeFovApplied = true
					applyScopePostFx(true)
				end
				if savedMouseSensitivity == nil then
					savedMouseSensitivity = UserInputService.MouseDeltaSensitivity
				end
				UserInputService.MouseDeltaSensitivity = tonumber(Config.SniperScopeMouseSensitivity) or 0.35
			end
			scopedFovApplied = true
			if scopeReticleRoot then
				scopeReticleRoot.Position = UDim2.fromScale(0.5, 0.5)
			end
			local camera = Workspace.CurrentCamera
			if camera then
				if scopeLastCameraCf then
					local posDrift = (camera.CFrame.Position - scopeLastCameraCf.Position).Magnitude
					if posDrift > 0.08 then
						scopeLogThrottled(
							"camera_override",
							0.15,
							"camera drift before scope apply (possible override): %.4f studs",
							posDrift
						)
					end
				end
				local targetForwardStuds = 0
				if Config.SniperScopeUseFovZoom == false then
					targetForwardStuds = resolveScopeForwardTargetStuds(localPlayer.Character, targetZoom)
				end
				local deltaForward = targetForwardStuds - scopeAppliedForwardStuds
				scopeAppliedForwardStuds = targetForwardStuds
				if math.abs(deltaForward) > 1e-6 then
					camera.CFrame = camera.CFrame * CFrame.new(0, 0, -deltaForward)
					scopeLogThrottled(
						"forward_apply",
						0.12,
						"forward apply: zoom=%.2f target=%.3f delta=%.3f",
						targetZoom,
						targetForwardStuds,
						deltaForward
					)
				end

				local t = os.clock()
				local breathSpeed = tonumber(Config.SniperScopeBreathSpeed) or 1.1
				local breathPitch = (tonumber(Config.SniperScopeBreathPitchDegrees) or 0.24) * math.sin(t * breathSpeed)
				local breathYaw = (tonumber(Config.SniperScopeBreathYawDegrees) or 0.18) * math.cos(t * breathSpeed * 0.87)
				local recoilRecovery = tonumber(Config.SniperScopeRecoilRecoveryPerSecond) or 8.5
				local damp = math.clamp(recoilRecovery * math.max(0, dt), 0, 1)
				scopeRecoilPitchDeg = scopeRecoilPitchDeg + (0 - scopeRecoilPitchDeg) * damp
				scopeRecoilYawDeg = scopeRecoilYawDeg + (0 - scopeRecoilYawDeg) * damp
				local targetPitchRad = math.rad(-(breathPitch + scopeRecoilPitchDeg))
				local targetYawRad = math.rad(breathYaw + scopeRecoilYawDeg)
				local deltaPitch = targetPitchRad - scopeAppliedPitchRad
				local deltaYaw = targetYawRad - scopeAppliedYawRad
				scopeAppliedPitchRad = targetPitchRad
				scopeAppliedYawRad = targetYawRad
				camera.CFrame = camera.CFrame * CFrame.Angles(deltaPitch, deltaYaw, 0)
				scopeLastCameraCf = camera.CFrame
			end
		else
			if scopedVisualActive or scopedFovApplied then
				local camera = Workspace.CurrentCamera
				if camera then
					if math.abs(scopeAppliedPitchRad) > 1e-6 or math.abs(scopeAppliedYawRad) > 1e-6 then
						camera.CFrame = camera.CFrame * CFrame.Angles(-scopeAppliedPitchRad, -scopeAppliedYawRad, 0)
					end
					if math.abs(scopeAppliedForwardStuds) > 1e-6 then
						camera.CFrame = camera.CFrame * CFrame.new(0, 0, scopeAppliedForwardStuds)
					end
				end
				scopeAppliedPitchRad = 0
				scopeAppliedYawRad = 0
				scopeAppliedForwardStuds = 0
				if scopeFovApplied then
					scopeFovApplied = false
					scopeLastFov = nil
					setFovOverride(false, tonumber(Config.SniperScopeBaseFov) or 70)
					applyScopePostFx(false)
				end
				if savedMouseSensitivity ~= nil then
					UserInputService.MouseDeltaSensitivity = savedMouseSensitivity
					savedMouseSensitivity = nil
				end
				scopedVisualActive = false
				scopedFovApplied = false
				setScopeVisualActive(false, targetZoom)
				scopeRecoilPitchDeg = 0
				scopeRecoilYawDeg = 0
				scopeLastCameraCf = nil
				scopeLogThrottled("exit", 0.01, "exit scope")
			end
		end
	end
	-- Use RenderStepped (not BindToRenderStep) so this runs after CameraDynamics' camera rewrite.
	scopeRenderConn = RunService.RenderStepped:Connect(scopeTick)

	if Config.SniperVirtualInventoryEnabled then
		UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
			if gameProcessed then
				return
			end
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
				return
			end
			fireInputHeld = true
			if isReadyToFire() then
				tryFire()
			end
		end)
		UserInputService.InputEnded:Connect(function(input: InputObject, _gameProcessed: boolean)
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
				return
			end
			fireInputHeld = false
		end)
	else
		tool.Activated:Connect(function()
			fireInputHeld = true
			if isReadyToFire() then
				tryFire()
			end
		end)
		tool.Deactivated:Connect(function()
			fireInputHeld = false
		end)
	end

	SniperLoadoutState.registerSniperTool(tool)
	SniperWeaponBarClient.ensureStarted(localPlayer)
	SniperAmmoHudClient.ensureStarted(localPlayer)
	SniperAmmoHudClient.setTrackedTool(tool)
	SniperRobloxCompanionClient.start(localPlayer)
end

return {
	bindTool = bindTool,
}
