-- Basic wall running helper

local Config = require(game:GetService("ReplicatedStorage").Movement.Config)
local WallMemory = require(game:GetService("ReplicatedStorage").Movement.WallMemory)
local Animations = require(game:GetService("ReplicatedStorage").Movement.Animations)
local ParkourSurfaceGate = require(game:GetService("ReplicatedStorage").Movement.ParkourSurfaceGate)

local WallRun = {}
local active = {}
local cooldownUntil = {}
local WallMemory = require(game:GetService("ReplicatedStorage").Movement.WallMemory)

-- Animation management
local wallrunAnimationTracks = {} -- Track wallrun animations per character

local function getCharacterParts(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return root, humanoid
end

local function findWall(rootPart)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { rootPart.Parent }
	params.IgnoreWater = Config.RaycastIgnoreWater

	-- Improved wall detection with better side determination
	local wallDistance = Config.WallDetectionDistance or 5
	local leftRayOrigin = rootPart.Position
	local leftRayDirection = rootPart.CFrame:VectorToWorldSpace(Vector3.new(-wallDistance, 0, 0))

	local rightRayOrigin = rootPart.Position
	local rightRayDirection = rootPart.CFrame:VectorToWorldSpace(Vector3.new(wallDistance, 0, 0))

	-- Cast rays to both sides
	local leftResult = workspace:Raycast(leftRayOrigin, leftRayDirection, params)
	local rightResult = workspace:Raycast(rightRayOrigin, rightRayDirection, params)

	-- Check left side first
	if leftResult and leftResult.Instance and leftResult.Instance.CanCollide then
		local n = leftResult.Normal
		local verticalDot = math.abs(n:Dot(Vector3.yAxis))
		local allowedDot = (Config.SurfaceVerticalDotMax or Config.SurfaceVerticalDotMin or 0.2)
		if verticalDot <= allowedDot then
			local inst = leftResult.Instance
			local CollectionService = game:GetService("CollectionService")
			local isClimbable = CollectionService:HasTag(inst, "Climbable")
			if ParkourSurfaceGate.isMechanicAllowed(inst, "WallRun") then
				local mult = inst:GetAttribute("WallRunSpeedMultiplier")
				mult = (type(mult) == "number" and mult > 0) and mult or 1
				return {
					normal = leftResult.Normal,
					position = leftResult.Position,
					instance = inst,
					speedMult = mult,
					side = "left", -- Wall is on the left side of the character
				}
			end
		end
	end

	-- Check right side
	if rightResult and rightResult.Instance and rightResult.Instance.CanCollide then
		local n = rightResult.Normal
		local verticalDot = math.abs(n:Dot(Vector3.yAxis))
		local allowedDot = (Config.SurfaceVerticalDotMax or Config.SurfaceVerticalDotMin or 0.2)
		if verticalDot <= allowedDot then
			local inst = rightResult.Instance
			local CollectionService = game:GetService("CollectionService")
			local isClimbable = CollectionService:HasTag(inst, "Climbable")
			if ParkourSurfaceGate.isMechanicAllowed(inst, "WallRun") then
				local mult = inst:GetAttribute("WallRunSpeedMultiplier")
				mult = (type(mult) == "number" and mult > 0) and mult or 1
				return {
					normal = rightResult.Normal,
					position = rightResult.Position,
					instance = inst,
					speedMult = mult,
					side = "right", -- Wall is on the right side of the character
				}
			end
		end
	end

	return nil
end

-- Determine which side of the character the wall is on
local function getWallDirection(rootPart, wallNormal)
	local rightVector = rootPart.CFrame.RightVector
	local dotProduct = rightVector:Dot(wallNormal)

	-- If dot product is positive, wall normal points toward right side of character
	-- This means the wall is on the LEFT side of the character
	-- If dot product is negative, wall normal points toward left side of character
	-- This means the wall is on the RIGHT side of the character
	if dotProduct > 0 then
		return "left" -- Wall is on the left side
	else
		return "right" -- Wall is on the right side
	end
end

-- Play appropriate wallrun animation based on wall direction and movement
local function playWallrunAnimation(character, wallData, forceChange)
	local rootPart, humanoid = getCharacterParts(character)
	if not rootPart or not humanoid then
		return
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	-- Use the side information directly from wall detection if available
	local direction = wallData.side
	if not direction then
		-- Fallback to the old calculation method if side is not available
		local wallNormal = wallData.normal
		local function getEffectiveWallDirection(rootPart, wallNormal, moveDirection)
			-- Project movement direction onto the wall plane
			local projectedMove = moveDirection - (moveDirection:Dot(wallNormal)) * wallNormal
			if projectedMove.Magnitude < 0.05 then
				projectedMove = rootPart.CFrame.LookVector - (rootPart.CFrame.LookVector:Dot(wallNormal)) * wallNormal
			end
			if projectedMove.Magnitude < 0.05 then
				projectedMove = wallNormal:Cross(Vector3.yAxis)
			end
			projectedMove = projectedMove.Unit

			-- Determine which side of the character the movement is going
			local rightVector = rootPart.CFrame.RightVector
			local dotProduct = rightVector:Dot(projectedMove)

			-- If dot product is positive, movement is toward right side of character
			-- This means the wall is on the LEFT side of the character
			-- If dot product is negative, movement is toward left side of character
			-- This means the wall is on the RIGHT side of the character
			if dotProduct > 0 then
				return "left" -- Wall is on the left side
			else
				return "right" -- Wall is on the right side
			end
		end

		-- Determine effective wall direction based on current movement
		local moveDirection = humanoid.MoveDirection
		if moveDirection.Magnitude < 0.05 then
			moveDirection = rootPart.CFrame.LookVector
		end

		direction = getEffectiveWallDirection(rootPart, wallNormal, moveDirection)
	end

	local animationName = direction == "right" and "WallRunRight" or "WallRunLeft"

	-- Check if we're already playing the correct animation
	local currentTrack = wallrunAnimationTracks[character]
	if currentTrack and currentTrack.IsPlaying and not forceChange then
		-- Check if the current animation matches the desired direction
		local currentAnimId = currentTrack.Animation and currentTrack.Animation.AnimationId or ""
		local desiredAnimId = ""

		local desiredAnimInst = Animations.get(animationName) or Animations.get("WallRunLoop")
		if desiredAnimInst then
			desiredAnimId = desiredAnimInst.AnimationId
		end

		-- If we're already playing the correct animation, don't change it
		if currentAnimId == desiredAnimId then
			return
		end
	end

	-- Stop any existing wallrun animation
	if currentTrack then
		pcall(function()
			currentTrack:Stop(0.1)
		end)
		wallrunAnimationTracks[character] = nil
	end

	-- Try to get the directional animation first, fallback to general WallRunLoop
	local animInst = Animations.get(animationName) or Animations.get("WallRunLoop")
	if not animInst then
		return -- No animation configured
	end

	-- Load and play the animation
	local track = animator:LoadAnimation(animInst)
	if track then
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = true
		track:Play(0.1, 1, 1.0)
		wallrunAnimationTracks[character] = track
	end
end

-- Stop wallrun animation
local function stopWallrunAnimation(character)
	if wallrunAnimationTracks[character] then
		pcall(function()
			wallrunAnimationTracks[character]:Stop(0.1)
		end)
		wallrunAnimationTracks[character] = nil
	end
end

function WallRun.tryStart(character)
	local now = os.clock()
	local untilTime = cooldownUntil[character]
	if untilTime and now < untilTime then
		return false
	end
	if active[character] then
		return false
	end
	local rootPart, humanoid = getCharacterParts(character)
	if not rootPart or not humanoid then
		return false
	end

	if humanoid.MoveDirection.Magnitude < 0.1 then
		return false
	end

	local currentSpeed = rootPart.AssemblyLinearVelocity.Magnitude
	if currentSpeed < Config.WallRunMinSpeed then
		return false
	end

	-- Require stamina to start wallrun
	if Config.StaminaEnabled == true then
		local folder = game:GetService("ReplicatedStorage"):FindFirstChild("ClientState")
		local staminaValue = folder and folder:FindFirstChild("Stamina")
		if staminaValue and staminaValue.Value <= 0 then
			return false
		end
	end

	local hit = findWall(rootPart)
	if not hit then
		return false
	end

	humanoid:ChangeState(Enum.HumanoidStateType.RunningNoPhysics)
	local originalWalkSpeed = humanoid.WalkSpeed
	local originalJumpPower = humanoid.JumpPower
	local originalAutoRotate = humanoid.AutoRotate
	humanoid.WalkSpeed = Config.WallRunSpeed
	humanoid.AutoRotate = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	local token = {}
	-- One-time target speed based on current horizontal momentum and per-wall multiplier
	local vel0 = rootPart.AssemblyLinearVelocity
	local horiz0 = Vector3.new(vel0.X, 0, vel0.Z)
	local baseSpeed0 = horiz0.Magnitude
	if baseSpeed0 < (Config.WallRunMinSpeed or 25) then
		baseSpeed0 = (Config.WallRunMinSpeed or 25)
	end
	local mult0 = hit.speedMult or 1
	local cap0 = (Config.AirControlTotalSpeedCap or 999)
	local targetSpeed = math.min(baseSpeed0 * mult0, cap0)
	active[character] = {
		humanoid = humanoid,
		originalWalkSpeed = originalWalkSpeed,
		originalJumpPower = originalJumpPower,
		originalAutoRotate = originalAutoRotate,
		token = token,
		lastWallNormal = hit.normal,
		lastWallSide = hit.side,
		lastMoveDirection = humanoid.MoveDirection,
		wallInstance = hit.instance,
		speedMult = hit.speedMult or 1,
		targetSpeed = targetSpeed,
	}

	-- Play appropriate wallrun animation based on wall direction
	playWallrunAnimation(character, hit, true) -- Force change on start

	task.delay(Config.WallRunMaxDurationSeconds, function()
		local data = active[character]
		if data and data.token == token then
			if data.humanoid and data.humanoid.Parent then
				data.humanoid.WalkSpeed = data.originalWalkSpeed or Config.BaseWalkSpeed
				data.humanoid.JumpPower = data.originalJumpPower or 50
				data.humanoid.AutoRotate = data.originalAutoRotate ~= nil and data.originalAutoRotate or true
				data.humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
			end
			active[character] = nil
		end
	end)

	return true
end

function WallRun.stop(character)
	local data = active[character]
	if not data then
		return
	end
	if data.humanoid and data.humanoid.Parent then
		data.humanoid.WalkSpeed = data.originalWalkSpeed or Config.BaseWalkSpeed
		data.humanoid.JumpPower = data.originalJumpPower or 50
		data.humanoid.AutoRotate = data.originalAutoRotate ~= nil and data.originalAutoRotate or true
		data.humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
	end

	-- Stop wallrun animation
	stopWallrunAnimation(character)

	active[character] = nil
end

function WallRun.isActive(character)
	return active[character] ~= nil
end

function WallRun.maintain(character)
	local data = active[character]
	if not data then
		return false
	end
	local rootPart, humanoid = getCharacterParts(character)
	if not rootPart or not humanoid then
		WallRun.stop(character)
		return false
	end
	if humanoid.FloorMaterial ~= Enum.Material.Air then
		WallRun.stop(character)
		WallMemory.clear(character)
		return false
	end
	if humanoid.MoveDirection.Magnitude < 0.1 then
		WallRun.stop(character)
		return false
	end
	local hit = findWall(rootPart)
	if not hit then
		WallRun.stop(character)
		return false
	end
	-- Double-check that wall still allows wallrun (in case attribute changed)
	if not ParkourSurfaceGate.isMechanicAllowed(hit.instance, "WallRun") then
		WallRun.stop(character)
		return false
	end
	-- Check if wall direction changed and update animation if needed
	local previousNormal = data.lastWallNormal
	local previousSide = data.lastWallSide
	data.lastWallNormal = hit.normal
	data.lastWallSide = hit.side

	-- Check if player movement direction changed (same wall, different movement direction)
	local previousMoveDirection = data.lastMoveDirection
	local currentMoveDirection = humanoid.MoveDirection
	data.lastMoveDirection = currentMoveDirection

	-- Check if we need to update animation
	local shouldUpdateAnimation = false

	-- Check if wall changed (different wall or different side)
	if previousNormal then
		local normalDifference = (previousNormal - hit.normal).Magnitude
		local sideChanged = previousSide ~= hit.side

		if sideChanged or normalDifference > 0.05 then
			shouldUpdateAnimation = true
		end
	end

	-- Update animation if needed
	if shouldUpdateAnimation then
		playWallrunAnimation(character, hit, false) -- Don't force, let it check if change is needed
	end

	-- Compute tangent along the wall to move forward while sticking slightly and falling slowly
	local normal = hit.normal
	local move = humanoid.MoveDirection
	if move.Magnitude < 0.05 then
		move = rootPart.CFrame.LookVector
	end
	local projected = move - (move:Dot(normal)) * normal
	if projected.Magnitude < 0.05 then
		local fallback = normal:Cross(Vector3.yAxis)
		if fallback.Magnitude < 0.05 then
			fallback = normal:Cross(Vector3.xAxis)
		end
		projected = fallback
	end
	local tangent = projected.Unit

	-- Orientation along the wall direction
	local up = Vector3.yAxis
	local look = tangent
	rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + look, up)

	-- Dynamic wallrun speed based on current horizontal speed and optional per-wall multiplier
	local vel = rootPart.AssemblyLinearVelocity
	local horiz = Vector3.new(vel.X, 0, vel.Z)
	local desiredSpeed = data.targetSpeed or (Config.WallRunMinSpeed or 25)

	local horizontal = tangent * desiredSpeed + (-normal * Config.WallStickVelocity)
	local newVel = Vector3.new(horizontal.X, -Config.WallRunDownSpeed, horizontal.Z)
	local cap = (Config.AirControlTotalSpeedCap or 0)
	if cap and cap > 0 then
		local nh = Vector3.new(newVel.X, 0, newVel.Z)
		local m = nh.Magnitude
		if m > cap then
			newVel = Vector3.new(nh.Unit.X * cap, newVel.Y, nh.Unit.Z * cap)
		end
	end
	rootPart.AssemblyLinearVelocity = newVel
	return true
end

function WallRun.tryHop(character)
	local data = active[character]
	if not data then
		return false
	end
	local rootPart, humanoid = getCharacterParts(character)
	if not rootPart or not humanoid then
		return false
	end
	local normal = data.lastWallNormal or rootPart.CFrame.RightVector

	-- Log initial state
	local currentVel = rootPart.AssemblyLinearVelocity

	-- Calculate away direction more robustly (same logic as WallJump.tryJump)
	-- Ensure we always push away from the wall by using the vector from wall to player
	local wallToPlayer = (rootPart.Position - (rootPart.Position - normal * 2)).Unit
	local wallNormal = normal.Unit

	-- Choose the direction that points away from the wall toward the player
	-- If the wall normal points toward the player, use it; otherwise use the inverse
	local awayDirection
	if wallNormal:Dot(wallToPlayer) > 0 then
		-- Wall normal points toward player (away from wall) - use it
		awayDirection = wallNormal
	else
		-- Wall normal points into wall - use the inverse
		awayDirection = -wallNormal
	end

	local away = awayDirection * Config.WallJumpImpulseAway
	local up = Vector3.new(0, Config.WallJumpImpulseUp, 0)

	-- Preserve horizontal momentum from wallrun if enabled
	local finalVelocity = away + up
	if Config.WallJumpPreserveMomentum then
		-- Get current horizontal velocity (excluding Y component)
		local horizontalVel = Vector3.new(currentVel.X, 0, currentVel.Z)
		local horizontalSpeed = horizontalVel.Magnitude

		-- Only preserve momentum if speed is above minimum threshold
		if horizontalSpeed >= (Config.WallJumpMinMomentumSpeed or 20) then
			-- Project horizontal velocity onto the wall plane (perpendicular to wall normal)
			local projectedVel = horizontalVel - (horizontalVel:Dot(normal)) * normal

			-- Apply momentum multiplier and add to final velocity
			local preservedMomentum = projectedVel * (Config.WallJumpMomentumMultiplier or 0.8)
			finalVelocity = finalVelocity + preservedMomentum
		end
	end

	-- Apply the final velocity
	rootPart.AssemblyLinearVelocity = finalVelocity

	-- Monitor velocity changes in the next few frames
	local monitorFrames = 0
	local maxFrames = 10
	local function monitorVelocity()
		monitorFrames = monitorFrames + 1
		if monitorFrames <= maxFrames and rootPart and rootPart.Parent then
			local currentVel = rootPart.AssemblyLinearVelocity
			task.wait()
			monitorVelocity()
		end
	end
	task.spawn(monitorVelocity)

	humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	WallRun.stop(character)
	-- mark this wall as used so the next hop must be from a different wall
	local wallInstance = nil
	do
		-- Try to recast to get the instance we hopped from
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { rootPart.Parent }
		params.IgnoreWater = Config.RaycastIgnoreWater
		local result = workspace:Raycast(rootPart.Position - normal, normal * 2, params)
		wallInstance = result and result.Instance or nil
	end
	if wallInstance then
		WallMemory.setLast(character, wallInstance)
	end
	cooldownUntil[character] = os.clock() + 0.45
	return true
end

function WallRun.isNearWall(character)
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return false
	end
	local hit = findWall(rootPart)
	return hit ~= nil
end

return WallRun
