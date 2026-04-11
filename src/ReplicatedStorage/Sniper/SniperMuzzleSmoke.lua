-- Muzzle VFX: flash + fire core + heat burst. When a Muzzle BasePart is passed, emitters parent to an Attachment on that part
-- so everything moves in real time with the gun; optional Rate-based linger smoke for a few seconds.

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(script.Parent.Config)

local SniperMuzzleSmoke = {}

local function buildFlashEmitter(): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "MuzzleFlashBurst"
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Rate = 0
	e.Enabled = false
	e.Lifetime = NumberRange.new(
		Config.SniperMuzzleFlashLifetimeMin or 0.04,
		Config.SniperMuzzleFlashLifetimeMax or 0.095
	)
	local sp = Config.SniperMuzzleFlashSpreadAngle or 80
	e.SpreadAngle = Vector2.new(sp, sp)
	e.Drag = 6
	e.RotSpeed = NumberRange.new(-400, 400)
	e.Rotation = NumberRange.new(0, 360)
	e.Orientation = Enum.ParticleOrientation.FacingCamera
	e.EmissionDirection = Enum.NormalId.Front
	e.LightEmission = 1
	e.LightInfluence = 0.15
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, Config.SniperMuzzleFlashSize0 or 0.12),
		NumberSequenceKeypoint.new(0.25, Config.SniperMuzzleFlashSize1 or 0.35),
		NumberSequenceKeypoint.new(1, 0.02),
	})
	e.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 245, 200)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(255, 170, 90)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(80, 60, 50)),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.35, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Speed = NumberRange.new(
		-(Config.SniperMuzzleFlashSpeedMax or 30),
		-(Config.SniperMuzzleFlashSpeedMin or 12)
	)
	return e
end

local function buildFireCoreEmitter(): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "MuzzleFireCore"
	e.Texture = "rbxasset://textures/particles/fire_main.dds"
	e.Rate = 0
	e.Enabled = false
	e.Lifetime = NumberRange.new(
		Config.SniperMuzzleFireCoreLifetimeMin or 0.045,
		Config.SniperMuzzleFireCoreLifetimeMax or 0.115
	)
	local fsp = Config.SniperMuzzleFireCoreSpreadAngle or 72
	e.SpreadAngle = Vector2.new(fsp, fsp)
	e.Drag = 7
	e.RotSpeed = NumberRange.new(-200, 200)
	e.Orientation = Enum.ParticleOrientation.FacingCamera
	e.EmissionDirection = Enum.NormalId.Front
	e.LightEmission = 1
	e.LightInfluence = 0
	local s0 = Config.SniperMuzzleFireCoreSize0 or 0.52
	local s1 = Config.SniperMuzzleFireCoreSize1 or 1.05
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, s0),
		NumberSequenceKeypoint.new(0.22, s1),
		NumberSequenceKeypoint.new(1, 0.03),
	})
	e.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 245)),
		ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 200, 80)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(60, 35, 20)),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.08),
		NumberSequenceKeypoint.new(0.45, 0.6),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Speed = NumberRange.new(
		Config.SniperMuzzleFireCoreSpeedMin or -38,
		Config.SniperMuzzleFireCoreSpeedMax or -14
	)
	return e
end

local function buildHeatEmitter(): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "MuzzleHeatWisp"
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Rate = 0
	e.Enabled = false
	e.Lifetime = NumberRange.new(
		Config.SniperMuzzleHeatLifetimeMin or 0.38,
		Config.SniperMuzzleHeatLifetimeMax or 0.78
	)
	local sp = Config.SniperMuzzleHeatSpreadAngle or 32
	e.SpreadAngle = Vector2.new(sp, sp)
	e.Drag = Config.SniperMuzzleHeatDrag or 4.2
	e.Acceleration = Vector3.new(0, Config.SniperMuzzleHeatAccelY or 10.5, 0)
	e.RotSpeed = NumberRange.new(-90, 90)
	e.Rotation = NumberRange.new(0, 360)
	e.Orientation = Enum.ParticleOrientation.VelocityParallel
	e.EmissionDirection = Enum.NormalId.Front
	e.LightEmission = Config.SniperMuzzleHeatLightEmission or 0.18
	e.LightInfluence = 0.55
	e.Speed = NumberRange.new(Config.SniperMuzzleHeatSpeedMin or 0.6, Config.SniperMuzzleHeatSpeedMax or 2.8)
	local hot = Config.SniperMuzzleHeatColorHot or Color3.fromRGB(255, 235, 210)
	local mid = Config.SniperMuzzleHeatColorMid or Color3.fromRGB(200, 195, 188)
	local cool = Config.SniperMuzzleHeatColorCool or Color3.fromRGB(140, 138, 145)
	e.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, hot),
		ColorSequenceKeypoint.new(0.35, mid),
		ColorSequenceKeypoint.new(0.75, cool),
		ColorSequenceKeypoint.new(1, cool:Lerp(Color3.fromRGB(90, 90, 95), 0.5)),
	})
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, Config.SniperMuzzleHeatSize0 or 0.06),
		NumberSequenceKeypoint.new(0.25, Config.SniperMuzzleHeatSize1 or 0.22),
		NumberSequenceKeypoint.new(0.65, Config.SniperMuzzleHeatSize2 or 0.55),
		NumberSequenceKeypoint.new(1, 0.35),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(0.25, 0.5),
		NumberSequenceKeypoint.new(0.65, 0.78),
		NumberSequenceKeypoint.new(1, 1),
	})
	return e
end

local function buildHeatLingerEmitter(): ParticleEmitter
	local e = buildHeatEmitter()
	e.Name = "MuzzleHeatLinger"
	e.Rate = Config.SniperMuzzleHeatLingerRate or 8
	e.Enabled = true
	e.LightEmission = math.clamp((Config.SniperMuzzleHeatLightEmission or 0.16) * 0.55, 0, 1)
	return e
end

local function spawnFlashAndCore(emitParent: Instance, flashCount: number)
	local flash = buildFlashEmitter()
	flash.Parent = emitParent
	flash:Emit(flashCount)

	local fireCore = buildFireCoreEmitter()
	fireCore.Parent = emitParent
	fireCore:Emit(math.clamp(math.floor(flashCount * 0.58 + 0.5), 10, 48))
end

local function spawnPointLight(lightParent: BasePart)
	local pl = Instance.new("PointLight")
	pl.Name = "MuzzleFlashLight"
	pl.Range = Config.SniperMuzzleFlashLightRange or 7.5
	pl.Brightness = Config.SniperMuzzleFlashLightBrightness or 10
	pl.Color = Config.SniperMuzzleFlashLightColor or Color3.fromRGB(255, 228, 190)
	pl.Shadows = false
	pl.Parent = lightParent

	local tweenDur = Config.SniperMuzzleFlashLightTweenSeconds or 0.1
	local tw = TweenService:Create(pl, TweenInfo.new(tweenDur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Brightness = 0,
		Range = (Config.SniperMuzzleFlashLightRange or 7.5) * 0.35,
	})
	tw:Play()
	tw.Completed:Connect(function()
		if pl.Parent then
			pl:Destroy()
		end
	end)
	return tweenDur
end

function SniperMuzzleSmoke.play(muzzleWorldCFrame: CFrame, followMuzzlePart: BasePart?)
	if Config.SniperMuzzleSmokeEnabled == false then
		return
	end

	local heatDelay = Config.SniperMuzzleHeatDelaySeconds or 0.038
	local heatCount = math.clamp(Config.SniperMuzzleHeatEmitCount or 26, 1, 120)
	local heatLifeMax = Config.SniperMuzzleHeatLifetimeMax or 1.55
	local heatMaxLife = heatLifeMax + heatDelay + 1.1
	local flashCount = math.clamp(Config.SniperMuzzleFlashEmitCount or 28, 1, 100)
	local tweenDur = Config.SniperMuzzleFlashLightTweenSeconds or 0.1

	local lingerSec = (Config.SniperMuzzleHeatLingerEnabled ~= false and followMuzzlePart) and (Config.SniperMuzzleHeatLingerSeconds or 2.35)
		or 0
	local debrisHold = math.max(heatMaxLife, tweenDur, (Config.SniperMuzzleFlashLifetimeMax or 0.13)) + 0.75
		if lingerSec > 0 then
			debrisHold = math.max(debrisHold, heatDelay + lingerSec + heatLifeMax + 0.9)
		end

	if followMuzzlePart and followMuzzlePart.Parent then
		local att = Instance.new("Attachment")
		att.Name = "SkyLeapMuzzleVfxAttachment"
		att.Parent = followMuzzlePart
		att.Position = Vector3.new(0, 0, 0)

		spawnFlashAndCore(att, flashCount)
		spawnPointLight(followMuzzlePart)

		task.delay(heatDelay, function()
			if not att.Parent then
				return
			end
			local heat = buildHeatEmitter()
			heat.Parent = att
			heat:Emit(heatCount)
			task.delay(heatLifeMax + 0.85, function()
				if heat.Parent then
					heat:Destroy()
				end
			end)
		end)

		if lingerSec > 0 then
			task.delay(heatDelay + 0.06, function()
				if not att.Parent then
					return
				end
				local linger = buildHeatLingerEmitter()
				linger.Parent = att
				task.delay(lingerSec, function()
					if linger.Parent then
						linger.Enabled = false
						linger.Rate = 0
						task.delay(heatLifeMax + 0.4, function()
							if linger.Parent then
								linger:Destroy()
							end
						end)
					end
				end)
			end)
		end

		Debris:AddItem(att, debrisHold)
		return
	end

	-- Fallback: no Muzzle instance — fixed world anchor (one shot only, no linger).
	local folder = Instance.new("Folder")
	folder.Name = "SkyLeapSniperMuzzleVFX"
	folder.Parent = Workspace

	local part = Instance.new("Part")
	part.Name = "MuzzleVfxAnchor"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(0.12, 0.12, 0.12)
	part.CFrame = muzzleWorldCFrame
	part.Parent = folder

	spawnFlashAndCore(part, flashCount)
	spawnPointLight(part)

	task.delay(heatDelay, function()
		if not folder.Parent then
			return
		end
		local heat = buildHeatEmitter()
		heat.Parent = part
		heat:Emit(heatCount)
		task.delay(heatLifeMax + 0.85, function()
			if heat.Parent then
				heat:Destroy()
			end
		end)
	end)

	Debris:AddItem(folder, debrisHold)
end

return SniperMuzzleSmoke
