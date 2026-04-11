-- Client-side binding for the Sniper Tool: input, local laser preview, remote fire request.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

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

local rng = Random.new()

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

	tool.Destroying:Connect(function()
		SniperLoadoutState.clearSniperTool(tool)
	end)

	if Config.SniperViewModelEnabled then
		ViewModelClient.attach(tool, options.LocalPlayer)
	end
	if Config.SniperCrosshairEnabled then
		SniperCrosshairClient.attach(tool, options.LocalPlayer)
	end

	local remotes = getRemotes()
	if not remotes or not remotes.RequestFire or not remotes.LaserFx or not remotes.AudioFeedback then
		warn("[Sniper] Remotes missing — ensure Remotes.server.lua ran.")
		return
	end

	local barrelName = Config.FireOriginPartName
	local barrel: BasePart? = nil
	if not Config.SniperVirtualInventoryEnabled then
		local b = tool:WaitForChild(barrelName, 15)
		if not b or not b:IsA("BasePart") then
			warn(("[Sniper] Tool needs a BasePart named %q (FireOriginPartName in Config)."):format(barrelName))
			return
		end
		barrel = b
	else
		local b = tool:FindFirstChild(barrelName)
		if b and b:IsA("BasePart") then
			barrel = b
		end
	end

	local localPlayer = options.LocalPlayer
	local reloadEndsAt = 0

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

	local inspectKey = Config.SniperViewModelInspectKeyCode or Enum.KeyCode.F
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.Keyboard or input.KeyCode ~= inspectKey then
			return
		end
		if not isReadyToFire() then
			return
		end
		SniperViewModelAnimator.notifyInspect(localPlayer)
	end)

	local function tryFire()
		local character = localPlayer.Character
		if not character then
			return
		end

		local now = os.clock()
		if now < reloadEndsAt then
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

		-- Hitscan origin: FireOriginPartName on viewmodel, else Tool part, else camera (virtual only).
		local fireOriginCf: CFrame? = nil
		if Config.SniperViewModelEnabled then
			fireOriginCf = ViewModelClient.getViewModelPartWorldCFrame(tool, Config.FireOriginPartName or "Barrel")
		end
		if not fireOriginCf and barrel then
			fireOriginCf = barrel.CFrame
		end

		local origin: Vector3
		if fireOriginCf then
			origin = fireOriginCf.Position
		elseif Config.SniperVirtualInventoryEnabled then
			origin = ray.Origin
		else
			return
		end

		local endPos = raycastPreview(origin, direction, character)
		SniperShotVisualizer.play(origin, endPos)

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
			local m = tool:FindFirstChild(smokePartName, true)
			if m and m:IsA("BasePart") then
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

		spawnPhysicalCasing(tool, localPlayer)

		playOneShot2D(Config.FireSoundId, Config.FireSoundVolume, Config.FireSoundFadeOutSeconds)
		playOneShot2D(Config.ReloadSoundId, Config.ReloadSoundVolume)

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

		reloadEndsAt = now + Config.ReloadSeconds
		remotes.RequestFire:FireServer(origin, direction)
	end

	if Config.SniperVirtualInventoryEnabled then
		UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
			if gameProcessed then
				return
			end
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
				return
			end
			if not isReadyToFire() then
				return
			end
			tryFire()
		end)
	else
		tool.Activated:Connect(function()
			if not isReadyToFire() then
				return
			end
			tryFire()
		end)
	end

	SniperLoadoutState.registerSniperTool(tool)
	SniperWeaponBarClient.ensureStarted(localPlayer)
	SniperRobloxCompanionClient.start(localPlayer)
end

return {
	bindTool = bindTool,
}
