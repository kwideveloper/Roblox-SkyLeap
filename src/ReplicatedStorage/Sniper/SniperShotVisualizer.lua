-- Client-only: (1) optional bright Beam along full hitscan line = tracer / bullet trace,
-- (2) fast invisible carrier + Trail = motion streak (local preview + SniperLaserFx for others).

local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(script.Parent.Config)

local FOLDER_NAME = "SkyLeapSniperShotVFX"

local function trailColor(): Color3
	local c = Config.SniperProjectileTrailColor
	if typeof(c) == "Color3" then
		return c
	end
	return Config.LaserColor or Color3.fromRGB(255, 120, 130)
end

local function travelDurationForDistance(dist: number): number
	local speed = Config.SniperProjectileSpeedStudsPerSec or 8000
	if speed < 1 then
		speed = 8000
	end
	local t = dist / speed
	local lo = Config.SniperProjectileTravelMin or 0.03
	local hi = Config.SniperProjectileTravelMax or 0.12
	return math.clamp(t, lo, hi)
end

local function buildLineTrail(part: BasePart, attA: Attachment, attB: Attachment)
	local trail = Instance.new("Trail")
	trail.Name = "ShotLineTrail"
	trail.Attachment0 = attA
	trail.Attachment1 = attB
	trail.FaceCamera = Config.SniperProjectileTrailFaceCamera ~= false
	trail.LightEmission = Config.SniperProjectileTrailLightEmission or 0.45
	trail.Lifetime = Config.SniperProjectileTrailLifetime or 0.18
	trail.MinLength = Config.SniperProjectileTrailMinLength or 0.02
	trail.MaxLength = Config.SniperProjectileTrailMaxLength or 10
	local core = trailColor()
	local mid = core:Lerp(Color3.new(1, 1, 1), 0.25)
	local tail = core:Lerp(Color3.fromRGB(30, 32, 40), 0.65)
	trail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, core),
		ColorSequenceKeypoint.new(0.35, mid),
		ColorSequenceKeypoint.new(1, tail),
	})
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.4, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, Config.SniperProjectileTrailWidth0 or 0.45),
		NumberSequenceKeypoint.new(0.7, Config.SniperProjectileTrailWidth1 or 0.12),
		NumberSequenceKeypoint.new(1, 0.04),
	})
	trail.Texture = "rbxasset://textures/particles/smoke_main.dds"
	trail.TextureMode = Enum.TextureMode.Stretch
	trail.TextureLength = Config.SniperProjectileTrailTextureLength or 0.55
	trail.Parent = part
	return trail
end

local function playLegacyBeam(from: Vector3, to: Vector3)
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = Workspace

	local anchor0 = Instance.new("Part")
	anchor0.Name = "LaserAnchor0"
	anchor0.Anchored = true
	anchor0.CanCollide = false
	anchor0.CanQuery = false
	anchor0.Transparency = 1
	anchor0.Size = Vector3.new(0.05, 0.05, 0.05)
	anchor0.Position = from
	anchor0.Parent = folder

	local anchor1 = Instance.new("Part")
	anchor1.Name = "LaserAnchor1"
	anchor1.Anchored = true
	anchor1.CanQuery = false
	anchor1.CanCollide = false
	anchor1.Transparency = 1
	anchor1.Size = Vector3.new(0.05, 0.05, 0.05)
	anchor1.Position = to
	anchor1.Parent = folder

	local att0 = Instance.new("Attachment")
	att0.Parent = anchor0
	local att1 = Instance.new("Attachment")
	att1.Parent = anchor1

	local beam = Instance.new("Beam")
	beam.Attachment0 = att0
	beam.Attachment1 = att1
	beam.Width0 = Config.LaserWidth
	beam.Width1 = Config.LaserWidth
	beam.Color = ColorSequence.new(Config.LaserColor)
	beam.LightEmission = Config.LaserLightEmission
	beam.FaceCamera = Config.LaserFaceCamera
	beam.Parent = anchor0

	Debris:AddItem(folder, Config.LaserFadeSeconds or 0.14)
end

local function easeOutCubic(t: number): number
	t = math.clamp(t, 0, 1)
	local inv = 1 - t
	return 1 - inv * inv * inv
end

-- Full-trajectory beam (FaceCamera): tracer from muzzle → impact; long ease-out fade + width taper.
local function playTracerBeam(from: Vector3, to: Vector3)
	local dir = to - from
	local dist = dir.Magnitude
	if dist < 1e-4 then
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = Workspace

	local anchor0 = Instance.new("Part")
	anchor0.Name = "TracerAnchor0"
	anchor0.Anchored = true
	anchor0.CanCollide = false
	anchor0.CanQuery = false
	anchor0.CastShadow = false
	anchor0.Transparency = 1
	anchor0.Size = Vector3.new(0.02, 0.02, 0.02)
	anchor0.Position = from
	anchor0.Parent = folder

	local anchor1 = Instance.new("Part")
	anchor1.Name = "TracerAnchor1"
	anchor1.Anchored = true
	anchor1.CanCollide = false
	anchor1.CanQuery = false
	anchor1.CastShadow = false
	anchor1.Transparency = 1
	anchor1.Size = Vector3.new(0.02, 0.02, 0.02)
	anchor1.Position = to
	anchor1.Parent = folder

	local att0 = Instance.new("Attachment")
	att0.Parent = anchor0
	local att1 = Instance.new("Attachment")
	att1.Parent = anchor1

	local beam = Instance.new("Beam")
	beam.Name = "BulletTracerBeam"
	beam.Attachment0 = att0
	beam.Attachment1 = att1
	local w0i = Config.SniperBulletTracerWidth0 or 0.12
	local w1i = Config.SniperBulletTracerWidth1 or 0.03
	beam.Width0 = w0i
	beam.Width1 = w1i
	beam.FaceCamera = Config.SniperBulletTracerFaceCamera ~= false
	local em0 = Config.SniperBulletTracerLightEmission or 1
	beam.LightEmission = em0
	beam.LightInfluence = Config.SniperBulletTracerLightInfluence or 0
	local c = Config.SniperBulletTracerColor
	if typeof(c) ~= "Color3" then
		c = trailColor()
	end
	local hot = c:Lerp(Color3.new(1, 1, 1), 0.4)
	local cool = c:Lerp(Color3.fromRGB(35, 32, 40), 0.55)
	beam.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, hot),
		ColorSequenceKeypoint.new(0.45, c),
		ColorSequenceKeypoint.new(1, cool),
	})
	local tex = Config.SniperBulletTracerTexture
	if type(tex) == "string" and tex ~= "" then
		beam.Texture = tex
		beam.TextureMode = Enum.TextureMode.Wrap
		beam.TextureSpeed = Config.SniperBulletTracerTextureSpeed or 3
		beam.TextureLength = math.clamp(dist * 0.06, 0.45, 10)
	end

	local tBase0 = Config.SniperBulletTracerTransparency0 or 0.06
	local tBase1 = Config.SniperBulletTracerTransparency1 or 0.12
	local tEnd0 = math.clamp(Config.SniperBulletTracerTransparencyEnd0 or 0.98, tBase0, 1)
	local tEnd1 = math.clamp(Config.SniperBulletTracerTransparencyEnd1 or 0.99, tBase1, 1)
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, tBase0),
		NumberSequenceKeypoint.new(1, tBase1),
	})
	beam.Parent = anchor0

	local dur = math.clamp(Config.SniperBulletTracerSeconds or 0.45, 0.08, 1.35)
	local widthEndScale = math.clamp(Config.SniperBulletTracerWidthEndScale or 0.22, 0.05, 1)
	local emEndScale = math.clamp(Config.SniperBulletTracerLightEmissionEndScale or 0.08, 0, 1)
	local tStart = os.clock()
	local conn: RBXScriptConnection? = nil
	conn = RunService.RenderStepped:Connect(function()
		if not beam.Parent then
			if conn then
				conn:Disconnect()
			end
			return
		end
		local u = (os.clock() - tStart) / dur
		if u >= 1 then
			if conn then
				conn:Disconnect()
			end
			if folder.Parent then
				folder:Destroy()
			end
			return
		end
		local fade = easeOutCubic(u)
		local a0 = tBase0 + (tEnd0 - tBase0) * fade
		local a1 = tBase1 + (tEnd1 - tBase1) * fade
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, math.clamp(a0, 0, 1)),
			NumberSequenceKeypoint.new(0.42, math.clamp(a0 * 0.92 + a1 * 0.08, 0, 1)),
			NumberSequenceKeypoint.new(1, math.clamp(a1, 0, 1)),
		})
		local wMul = 1 - (1 - widthEndScale) * fade
		beam.Width0 = math.max(0.008, w0i * wMul)
		beam.Width1 = math.max(0.004, w1i * wMul)
		beam.LightEmission = em0 * (1 - (1 - emEndScale) * fade)
	end)

	Debris:AddItem(folder, dur + 2)
end

local function playTrailOnly(from: Vector3, to: Vector3)
	local dir = to - from
	local dist = dir.Magnitude
	if dist < 1e-4 then
		return
	end

	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	folder.Parent = Workspace

	local span = math.clamp(Config.SniperProjectileCarrierSpan or 0.12, 0.04, 0.35)
	local carrier = Instance.new("Part")
	carrier.Name = "SniperShotCarrier"
	carrier.Shape = Enum.PartType.Block
	carrier.Size = Vector3.new(0.03, 0.03, span)
	carrier.Material = Enum.Material.SmoothPlastic
	carrier.Color = trailColor()
	carrier.Anchored = true
	carrier.CanCollide = false
	carrier.CanQuery = false
	carrier.CastShadow = false
	carrier.Transparency = 1
	carrier.Parent = folder

	local aim = CFrame.lookAt(from, to)
	carrier.CFrame = aim

	local half = span * 0.48
	local attA = Instance.new("Attachment")
	attA.Name = "TrailA"
	attA.Position = Vector3.new(0, 0, half)
	attA.Parent = carrier
	local attB = Instance.new("Attachment")
	attB.Name = "TrailB"
	attB.Position = Vector3.new(0, 0, -half)
	attB.Parent = carrier

	local trail = buildLineTrail(carrier, attA, attB)

	local travel = travelDurationForDistance(dist)
	local goalCf = aim * CFrame.new(0, 0, -dist)
	local tween = TweenService:Create(carrier, TweenInfo.new(travel, Enum.EasingStyle.Linear), { CFrame = goalCf })

	Debris:AddItem(folder, trail.Lifetime + travel + 1.5)

	tween.Completed:Connect(function()
		trail.Enabled = false
		task.delay(trail.Lifetime + 0.05, function()
			if folder.Parent then
				folder:Destroy()
			end
		end)
	end)
	tween:Play()
end

local SniperShotVisualizer = {}

function SniperShotVisualizer.play(from: Vector3, to: Vector3)
	local delta = to - from
	if delta.Magnitude < 1e-4 then
		return
	end

	local tracerOn = Config.SniperBulletTracerBeamEnabled ~= false
	if tracerOn then
		playTracerBeam(from, to)
	end

	if Config.SniperProjectileTrailEnabled == false then
		if not tracerOn then
			playLegacyBeam(from, to)
		end
		return
	end

	playTrailOnly(from, to)
end

return SniperShotVisualizer
