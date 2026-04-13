-- Quake/CS-style air control: accelerate in air along input/facing, redirecting momentum smoothly

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Movement.Config)

local AirControl = {}

local function getParts(character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return root, humanoid
end

-- Projects a vector onto the horizontal plane (Y=0)
local function horizontal(v)
	return Vector3.new(v.X, 0, v.Z)
end

function AirControl.apply(character, dt)
	if not (Config.AirControlEnabled ~= false) then
		return
	end
	local root, humanoid = getParts(character)
	if not root or not humanoid then
		return
	end
	if humanoid.FloorMaterial ~= Enum.Material.Air then
		return
	end

	-- Log air control application
	local velBefore = root.AssemblyLinearVelocity

	-- Build wish direction from MoveDirection or camera facing if configured
	local wish = horizontal(humanoid.MoveDirection)
	if wish.Magnitude < 0.05 then
		if Config.AirControlUseCameraFacing then
			local cam = workspace.CurrentCamera
			if cam then
				wish = horizontal(cam.CFrame.LookVector)
			end
		end
	end
	if wish.Magnitude < 0.05 then
		return
	end
	wish = wish.Unit

	local vel = root.AssemblyLinearVelocity
	local horiz = horizontal(vel)
	local currentAlong = horiz:Dot(wish)

	local wishSpeed = (Config.AirControlMaxWishSpeed or 35)
	-- Optional cap per tick to prevent huge bursts
	local maxAddPerTick = (Config.AirControlMaxAddPerTick or (wishSpeed * 0.5))

	-- How much speed we still can gain along wish direction
	local addSpeed = wishSpeed - currentAlong
	if addSpeed <= 0 then
		return
	end
	local accel = (Config.AirControlAccelerate or 150)
	-- Subtle wish-speed scaling (keeps same units as legacy accel*dt; avoids over-boosting low dt).
	local wishScale = math.clamp(wishSpeed / 35, 0.65, 1.35)
	local accelSpeed = math.min(addSpeed, accel * wishScale * dt, maxAddPerTick)

	-- Strafe curve: more acceleration when wish is lateral to velocity (smooth CS/Quake-style air strafe).
	local horizMag = horiz.Magnitude
	if horizMag > 0.05 then
		local strafeFactor = 1 - math.abs(horiz.Unit:Dot(wish))
		strafeFactor = math.clamp(strafeFactor, 0, 1)
		local strafeBonus = (Config.AirStrafeAccelerate or 50) * dt * strafeFactor
		accelSpeed = math.min(addSpeed, accelSpeed + strafeBonus)
	end

	local newHoriz = horiz + (wish * accelSpeed)
	-- Optional total air speed cap
	local cap = Config.AirControlTotalSpeedCap
	if cap and cap > 0 then
		local mag = newHoriz.Magnitude
		if mag > cap then
			newHoriz = newHoriz.Unit * cap
		end
	end

	local finalVel = Vector3.new(newHoriz.X, vel.Y, newHoriz.Z)
	root.AssemblyLinearVelocity = finalVel
end

return AirControl
