-- Dash and slide abilities

local Config = require(game:GetService("ReplicatedStorage").Movement.Config)
local Animations = require(game:GetService("ReplicatedStorage").Movement.Animations)
local SharedUtils = require(game:GetService("ReplicatedStorage").SharedUtils)
local ParkourSurfaceGate = require(game:GetService("ReplicatedStorage").Movement.ParkourSurfaceGate)
local RunService = game:GetService("RunService")
local OverlapParams = OverlapParams

local Abilities = {}

local lastDashTick = 0
local lastSlideTick = 0
local lastVaultTick = 0
local lastMantleTick = 0
local originalPhysByPart = {}
local dashActive = {}
local airDashCharges = {} -- [character]=currentCharges

-- Helper function to check if a state is active
local function isStateActive(stateName)
	local cs = game:GetService("ReplicatedStorage"):FindFirstChild("ClientState")
	local state = cs and cs:FindFirstChild(stateName)
	return state and state.Value or false
end

-- Check if there's enough clearance above for a full mantle
-- Uses same logic as ParkourController to ensure consistency
local function hasEnoughClearanceAbove(root, ledgeY, forwardDirection, hitPoint)
	local params = SharedUtils.createParkourRaycastParams(root.Parent)

	local requiredHeight = Config.LedgeHangMinClearance or 5.0
	local inwardDistance = 1.5 -- How far inward from edge to check

	-- Calculate positions on the ledge edge, then move inward
	local ledgeEdge = Vector3.new(hitPoint.X, ledgeY, hitPoint.Z)
	local inwardOffset = forwardDirection * inwardDistance

	-- Check multiple points along the ledge, moving inward from the edge
	local checkPoints = {
		ledgeEdge + inwardOffset, -- center inward
		ledgeEdge + inwardOffset + Vector3.new(0.8, 0, 0), -- left inward
		ledgeEdge + inwardOffset + Vector3.new(-0.8, 0, 0), -- right inward
		ledgeEdge + inwardOffset * 0.5, -- halfway inward
	}

	for i, checkPos in ipairs(checkPoints) do
		-- Raycast upward from just above the ledge
		local rayStart = Vector3.new(checkPos.X, ledgeY + 0.1, checkPos.Z)
		local rayEnd = Vector3.new(0, requiredHeight, 0)

		local hit = workspace:Raycast(rayStart, rayEnd, params)
		if hit then
			local obstacleHeight = hit.Position.Y - ledgeY
			if Config.DebugLedgeHang then
				print(
					string.format(
						"[Abilities Clearance] Point %d: obstacle at %.2f studs above ledge (required: %.2f)",
						i,
						obstacleHeight,
						requiredHeight
					)
				)
			end
			if obstacleHeight < requiredHeight then
				return false -- Insufficient clearance
			end
		elseif Config.DebugLedgeHang then
			print(string.format("[Abilities Clearance] Point %d: no obstacle found, clearance OK", i))
		end
	end

	if Config.DebugLedgeHang then
		print("[Abilities Clearance] All points clear, sufficient space for mantle")
	end
	return true
end

local function getCharacterParts(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return root, humanoid
end

local function setCharacterFriction(character, friction, frictionWeight)
	originalPhysByPart[character] = originalPhysByPart[character] or {}
	local store = originalPhysByPart[character]
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			if store[part] == nil then
				store[part] = part.CustomPhysicalProperties
			end
			local current = part.CustomPhysicalProperties
			local density = current and current.Density or 1
			local elasticity = current and current.Elasticity or 0
			local elasticityWeight = current and current.ElasticityWeight or 0
			part.CustomPhysicalProperties =
				PhysicalProperties.new(density, friction, elasticity, frictionWeight, elasticityWeight)
		end
	end
end

local function restoreCharacterFriction(character)
	local store = originalPhysByPart[character]
	if not store then
		return
	end
	for part, phys in pairs(store) do
		if part and part:IsA("BasePart") then
			part.CustomPhysicalProperties = phys
		end
	end
	originalPhysByPart[character] = nil
end

function Abilities.isDashReady()
	local now = os.clock()
	return (now - lastDashTick) >= Config.DashCooldownSeconds
end

-- Full availability check for dash (cooldown + airborne + remaining air charges)
function Abilities.isDashAvailable(character)
	local now = os.clock()
	if (now - lastDashTick) < (Config.DashCooldownSeconds or 0) then
		return false
	end
	local rootPart, humanoid = getCharacterParts(character)
	if not rootPart or not humanoid then
		return false
	end
	if humanoid.FloorMaterial ~= Enum.Material.Air then
		return false
	end
	local charges = airDashCharges[character] or 0
	return charges > 0
end

function Abilities.isSlideReady()
	local now = os.clock()
	local slideCooldown = math.max(0.001, Config.SlideCooldownSeconds or 0.5)
	return (now - lastSlideTick) >= slideCooldown
end

-- Vault helpers
local function raycastForward(root, distance)
	local params = SharedUtils.createParkourRaycastParams(root.Parent)
	local origin = root.Position + Vector3.new(0, (root.Size and root.Size.Y or 2) * 0.25, 0)
	return workspace:Raycast(origin, root.CFrame.LookVector * distance, params)
end

-- Public safeguard: ensure collisions are restored for a character (no-op now)
function Abilities.ensureCollisions(character)
	-- _collisionDisableCount[character] = nil -- deprecated
end

-- Disabled: No per-part mask changes for slide
local function setSlideCollisionMask(character)
	return
end

function Abilities.tryDash(character)
	local now = os.clock()
	if now - lastDashTick < Config.DashCooldownSeconds then
		return false
	end

	local rootPart, humanoid = getCharacterParts(character)
	if not rootPart or not humanoid then
		return false
	end

	-- Prevent dash during climb
	if not Config.DashAllowedDuringClimb and isStateActive("IsClimbing") then
		if Config.DebugDash then
			print("[Dash] Blocked during climb")
		end
		return false
	end

	-- Prevent dash during zipline
	if not Config.DashAllowedDuringZipline and isStateActive("IsZiplining") then
		if Config.DebugDash then
			print("[Dash] Blocked during zipline")
		end
		return false
	end

	-- Prevent dash during vault
	if not Config.DashAllowedDuringVault and isStateActive("IsVaulting") then
		if Config.DebugDash then
			print("[Dash] Blocked during vault")
		end
		return false
	end

	-- Prevent dash during mantle
	if not Config.DashAllowedDuringMantle and isStateActive("IsMantling") then
		if Config.DebugDash then
			print("[Dash] Blocked during mantle")
		end
		return false
	end

	lastDashTick = now

	-- Only allow dash while airborne
	if humanoid.FloorMaterial ~= Enum.Material.Air then
		return false
	end

	-- Enforce per-airtime dash charges (must be explicitly granted on ground or via powerup)
	local charges = airDashCharges[character]
	if charges == nil then
		return false
	end
	if (charges or 0) <= 0 then
		return false
	end

	-- Fixed-distance dash: set a constant horizontal velocity and zero vertical velocity
	local moveDir = (humanoid.MoveDirection.Magnitude > 0.05) and humanoid.MoveDirection or rootPart.CFrame.LookVector
	moveDir = Vector3.new(moveDir.X, 0, moveDir.Z)
	if moveDir.Magnitude < 0.05 then
		moveDir = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z)
	end
	if moveDir.Magnitude > 0 then
		moveDir = moveDir.Unit
	end
	local dashDur = Config.DashDurationSeconds or 0.18
	local desiredSpeed = (Config.DashSpeed or 70)

	-- Completely horizontal, without vertical component (ignoring gravity)
	local desiredHorizontal = moveDir * desiredSpeed
	local desiredVel = Vector3.new(desiredHorizontal.X, 0, desiredHorizontal.Z)
	rootPart.AssemblyLinearVelocity = desiredVel

	-- Play dash animation if available (uses preloaded cache if present)
	local dashTrack = nil
	do
		local animInst = Animations and Animations.get and Animations.get("Dash")
		if humanoid and animInst then
			local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
			animator.Parent = humanoid
			pcall(function()
				dashTrack = animator:LoadAnimation(animInst)
			end)
			if dashTrack then
				dashTrack.Priority = Enum.AnimationPriority.Action
				-- Match animation playback to dash duration if possible
				local playbackSpeed = 1.0
				local dashDur = Config.DashDurationSeconds or 0
				local length = 0
				pcall(function()
					length = dashTrack.Length or 0
				end)
				if dashDur > 0 and length > 0 then
					playbackSpeed = length / dashDur
				end
				dashTrack.Looped = false
				dashTrack.TimePosition = 0
				dashTrack:Play(0.05, 1, playbackSpeed)
			end
		end
	end

	-- Save the original status of physics properties and configure the character
	local originalAutoRotate = humanoid.AutoRotate
	-- Temporarily reduce friction to 0 on all character parts to achieve consistent ground dash
	setCharacterFriction(character, 0, 0)
	humanoid.AutoRotate = false

	-- Temporarily disable gravity by configuring a special state for humans
	local originalState = humanoid:GetState()
	humanoid:ChangeState(Enum.HumanoidStateType.Physics) -- This state allows us to have complete control over physics

	local stillValid = true
	-- Publish dashing flag
	pcall(function()
		local rs = game:GetService("ReplicatedStorage")
		local cs = rs:FindFirstChild("ClientState") or Instance.new("Folder")
		if not cs.Parent then
			cs.Name = "ClientState"
			cs.Parent = rs
		end
		local flag = cs:FindFirstChild("IsDashing")
		if not flag then
			flag = Instance.new("BoolValue")
			flag.Name = "IsDashing"
			flag.Value = false
			flag.Parent = cs
		end
		flag.Value = true
	end)

	local function endDash()
		if not stillValid then
			return
		end
		stillValid = false
		humanoid.AutoRotate = originalAutoRotate
		restoreCharacterFriction(character)
		pcall(function()
			if dashTrack then
				dashTrack:Stop(0.1)
			end
		end)
		-- Restore normal behavior of gravity after Dash
		if humanoid and humanoid.Parent then
			humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		end
		-- Clear flag
		pcall(function()
			local rs = game:GetService("ReplicatedStorage")
			local cs = rs:FindFirstChild("ClientState")
			local flag = cs and cs:FindFirstChild("IsDashing")
			if flag then
				flag.Value = false
			end
		end)
		dashActive[character] = nil
	end

	task.delay(Config.DashDurationSeconds, endDash)
	-- Expose cancel handle
	dashActive[character] = { endDash = endDash }

	-- Constantly update the speed during the Dash to maintain the perfectly horizontal movement
	task.spawn(function()
		local t0 = os.clock()
		while stillValid and (os.clock() - t0) < Config.DashDurationSeconds do
			rootPart.AssemblyLinearVelocity = desiredVel -- Maintain constant horizontal speed without vertical component
			task.wait()
		end
	end)

	-- Decrement charge (after dash is started)
	airDashCharges[character] = math.max(0, (airDashCharges[character] or 0) - 1)

	return true
end

function Abilities.cancelDash(character)
	local data = dashActive[character]
	if data and data.endDash then
		data.endDash()
	end
end

function Abilities.slide(character)
	local now = os.clock()
	-- Enforce cooldown based on SlideCooldownSeconds to prevent spam
	local slideCooldown = math.max(0.001, Config.SlideCooldownSeconds or 0.5)
	if (now - lastSlideTick) < slideCooldown then
		return function() end
	end
	local rootPart, humanoid = getCharacterParts(character)
	if not rootPart or not humanoid then
		return function() end
	end
	-- Require grounded
	if humanoid.FloorMaterial == Enum.Material.Air then
		return function() end
	end

	-- Prevent slide while already sliding
	local cs = game:GetService("ReplicatedStorage"):FindFirstChild("ClientState")
	local isSliding = cs and cs:FindFirstChild("IsSliding")
	if isSliding and isSliding.Value == true then
		return function() end
	end
	-- Require sprinting and minimum speed to start slide
	if Config.SlideRequireSprint ~= false then
		local cs = game:GetService("ReplicatedStorage"):FindFirstChild("ClientState")
		local isSprinting = cs and cs:FindFirstChild("IsSprinting")
		if not (isSprinting and isSprinting.Value == true) then
			return function() end
		end
	end
	local curVelForGate = rootPart.AssemblyLinearVelocity
	local horizForGate = Vector3.new(curVelForGate.X, 0, curVelForGate.Z)
	local speedForGate = horizForGate.Magnitude
	local minReq = (Config.SlideMinSpeedFractionOfSprint or 0.5) * (Config.SprintWalkSpeed or 50)
	if speedForGate < minReq then
		return function() end
	end

	-- Check stamina cost - we'll let the ParkourController handle the actual consumption
	-- to avoid conflicts with the local stamina system
	if Config.StaminaEnabled == true then
		local staminaCost = Config.SlideStaminaCost or 12
		local cs = game:GetService("ReplicatedStorage"):FindFirstChild("ClientState")
		local staminaValue = cs and cs:FindFirstChild("Stamina")
		if staminaValue and staminaValue.Value < staminaCost then
			return function() end
		end
	end

	local originalWalkSpeed = humanoid.WalkSpeed
	local originalCameraOffset = humanoid.CameraOffset
	local cameraTweenToken = {}
	-- humanoid.HipHeight untouched; movement will be applied as velocity, not WalkSpeed
	-- Limit collisions to torso only during slide to prevent limbs snagging
	setSlideCollisionMask(character)
	-- Temporarily adjust the character CollisionPart similar to crawl but milder
	local collisionPart = character:FindFirstChild("CollisionPart")
	local origSize = collisionPart and collisionPart.Size
	-- Store the original size before any modifications to preserve it
	local originalSize = origSize
	local chosenJoint
	local origC0, origC1
	if collisionPart and origSize then
		-- Reduce height
		local newH = math.max(Config.SlideColliderHeight or (origSize.Y * 0.7), 0.5)
		collisionPart.Size = Vector3.new(origSize.X, newH, origSize.Z)
		-- Nudge up via joint to avoid scraping floor
		for _, d in ipairs(character:GetDescendants()) do
			if d:IsA("Weld") or d:IsA("Motor6D") then
				if d.Part0 == collisionPart or d.Part1 == collisionPart then
					chosenJoint = d
					local other = (d.Part0 == collisionPart) and d.Part1 or d.Part0
					if other == rootPart then
						break
					end
				end
			end
		end
		if chosenJoint then
			origC0 = chosenJoint.C0
			origC1 = chosenJoint.C1
			local up = math.max(Config.SlideJointOffsetUp or 0.5, 0)
			if chosenJoint.Part0 == collisionPart then
				chosenJoint.C0 = chosenJoint.C0 * CFrame.new(0, up, 0)
			else
				chosenJoint.C1 = chosenJoint.C1 * CFrame.new(0, up, 0)
			end
		end
	end

	-- We previously created a collider; now we avoid any extra collider to prevent floor conflicts
	local endCollider = nil

	-- Optional slide animations: Start -> Loop -> End
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = humanoid
	local startId = Animations and Animations.SlideStart or ""
	local loopId = Animations and Animations.SlideLoop or ""
	local endId = Animations and Animations.SlideEnd or ""
	local startTrack, loopTrack

	local function playTrack(id, looped, desiredDurationSeconds)
		if not id or id == "" then
			return nil
		end
		local anim
		if Animations and Animations.get then
			-- Find the configured key that matches this id to reuse cached instances
			for key, value in pairs(Animations) do
				if type(value) == "string" and value == id then
					anim = Animations.get(key)
					break
				end
			end
		end
		if not anim then
			anim = Instance.new("Animation")
			anim.AnimationId = id
		end
		local track
		pcall(function()
			track = animator:LoadAnimation(anim)
		end)
		-- Always reset TimePosition so it restarts cleanly when spam-triggered
		if track then
			track.TimePosition = 0
		end
		if not track then
			return nil
		end
		track.Priority = Enum.AnimationPriority.Movement
		track.Looped = looped and true or false
		-- Time-scale playback to fit a desired duration when provided (e.g., ground slide)
		local speed = 1.0
		if desiredDurationSeconds and desiredDurationSeconds > 0 then
			local length = 0
			pcall(function()
				length = track.Length or 0
			end)
			if length > 0 then
				-- Play the entire authored clip within the desired window
				speed = length / desiredDurationSeconds
			end
		end
		track:Play(0.05, 1, speed)
		return track
	end

	-- Play Start then Loop (if provided). If only Start exists, it will play once.
	if startId ~= "" then
		-- If there is no loop, compress/expand the start clip to the slide duration so it fully plays
		local desired = (loopId == "") and (Config.SlideDurationSeconds or 0) or nil
		startTrack = playTrack(startId, false, desired)
		if startTrack and loopId ~= "" then
			-- When start ends, begin loop
			startTrack.Stopped:Connect(function()
				if loopTrack == nil then
					loopTrack = playTrack(loopId, true, nil)
				end
			end)
		end
	elseif loopId ~= "" then
		loopTrack = playTrack(loopId, true, nil)
	end

	-- Fixed-distance slide: maintain a constant horizontal velocity for the slide duration
	local desiredDistance = Config.SlideDistanceStuds or 0
	local slideDuration = math.max(0.001, Config.SlideDurationSeconds or 0.5)
	local moveDir = (humanoid.MoveDirection.Magnitude > 0.05) and humanoid.MoveDirection or rootPart.CFrame.LookVector
	moveDir = Vector3.new(moveDir.X, 0, moveDir.Z)
	if moveDir.Magnitude < 0.05 then
		moveDir = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z)
	end
	if moveDir.Magnitude > 0 then
		moveDir = moveDir.Unit
	end
	local minSlideSpeed = (desiredDistance > 0) and (desiredDistance / slideDuration) or 0

	-- Impulse-based slide: inject a horizontal boost that decays over slideDuration
	local v0 = rootPart.AssemblyLinearVelocity
	local horiz0 = Vector3.new(v0.X, 0, v0.Z)
	local slideDir = moveDir
	local origAlong0 = horiz0:Dot(slideDir)
	local baseBoost = Config.SlideForwardImpulse
	if (not baseBoost) or baseBoost <= 0 then
		baseBoost = minSlideSpeed
	end
	-- Initial one-frame injection preserves vertical
	local injected = horiz0 + (slideDir * baseBoost)
	rootPart.AssemblyLinearVelocity = Vector3.new(injected.X, v0.Y, injected.Z)
	local impulseWindow = slideDuration
	local baselineMag = math.max(horiz0.Magnitude, minSlideSpeed)

	-- Reduce friction and hand control to physics for the duration (dash-like behavior)
	local originalAutoRotate = humanoid.AutoRotate
	setCharacterFriction(character, 0, 0)
	humanoid.AutoRotate = false
	local jumpConn = nil

	-- Control flag for movement loop; set to false on early cancel or natural end
	local stillSliding = true

	-- Check if there's enough clearance to stand up after slide
	local function hasStandClearance()
		local root = character:FindFirstChild("HumanoidRootPart")
		local cp = collisionPart
		if not root or not cp then
			return true
		end

		local currentHeight = (cp and cp.Size and cp.Size.Y) or 1.4
		local standHeight = originalSize and originalSize.Y or 2
		local extra = math.max(0, standHeight - currentHeight)

		if extra <= 0.05 then
			return true
		end

		local side = (root.Size and root.Size.X) or 1
		local forward = 0.25
		local up = root.CFrame.UpVector
		local right = root.CFrame.RightVector
		local look = root.CFrame.LookVector
		local center = root.Position + up * (currentHeight * 0.5 + extra * 0.5) + look * (forward * 0.5)
		local boxCFrame = CFrame.fromMatrix(center, right, up, look)
		local size = Vector3.new(side, extra, forward)

		local params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character }
		params.RespectCanCollide = true

		local parts = workspace:GetPartBoundsInBox(boxCFrame, size, params)
		local hasClearance = #parts == 0

		return hasClearance
	end

	local endSlide = function()
		-- Stop movement loop immediately
		stillSliding = false

		-- Clear sliding state
		local cs = game:GetService("ReplicatedStorage"):FindFirstChild("ClientState")
		local isSliding = cs and cs:FindFirstChild("IsSliding")
		if isSliding then
			isSliding.Value = false
		end
		if humanoid and humanoid.Parent then
			humanoid.WalkSpeed = originalWalkSpeed
			-- Smooth camera offset back
			local start = humanoid.CameraOffset
			local target = originalCameraOffset or Vector3.new()
			local dur = math.max(0, Config.SlideCameraLerpSeconds or 0.1)
			local token = {}
			cameraTweenToken = token
			task.spawn(function()
				local t0 = os.clock()
				while os.clock() - t0 < dur do
					if cameraTweenToken ~= token then
						return
					end
					local alpha = (os.clock() - t0) / math.max(dur, 0.001)
					alpha = math.clamp(alpha, 0, 1)
					local y = start.Y + (target.Y - start.Y) * alpha
					humanoid.CameraOffset = Vector3.new(0, y, 0)
					RunService.Heartbeat:Wait()
				end
				if cameraTweenToken == token then
					humanoid.CameraOffset = target
				end
			end)
		end
		-- Check clearance BEFORE restoring CollisionPart size
		if collisionPart and originalSize then
			-- Check clearance while still in slide size (smaller CollisionPart)
			if not hasStandClearance() then
				-- No clearance - keep the small size and activate crawl

				-- Store the original size in ClientState so crawl can use it
				local cs = game:GetService("ReplicatedStorage"):FindFirstChild("ClientState")
				local originalSizeValue = cs and cs:FindFirstChild("SlideOriginalSize")
				if originalSizeValue then
					originalSizeValue.Value = originalSize
				end

				-- Signal to ParkourController that crawl should be activated
				local shouldCrawl = cs and cs:FindFirstChild("ShouldActivateCrawl")
				if shouldCrawl then
					shouldCrawl.Value = true
				end
			else
				-- Safe to restore normal size
				pcall(function()
					collisionPart.Size = originalSize
				end)
			end
		end
		if chosenJoint then
			pcall(function()
				if origC0 then
					chosenJoint.C0 = origC0
				end
				if origC1 then
					chosenJoint.C1 = origC1
				end
			end)
		end
		if endCollider then
			endCollider()
		end
		-- Character collisions remain enabled throughout slide
		-- Restore friction/autorotate
		humanoid.AutoRotate = originalAutoRotate
		restoreCharacterFriction(character)
		if jumpConn then
			pcall(function()
				jumpConn:Disconnect()
			end)
			jumpConn = nil
		end
		-- Stop loop and optionally play end
		if startTrack then
			pcall(function()
				startTrack:Stop(0.05)
			end)
		end
		if loopTrack then
			pcall(function()
				loopTrack:Stop(0.05)
			end)
			loopTrack = nil
		end
		if endId ~= "" then
			playTrack(endId, false, nil)
		end
	end

	lastSlideTick = now

	-- Set sliding state
	local cs = game:GetService("ReplicatedStorage"):FindFirstChild("ClientState")
	local isSliding = cs and cs:FindFirstChild("IsSliding")
	if isSliding then
		isSliding.Value = true
	end

	-- Smooth camera offset tween into slide
	do
		local target = Vector3.new(0, Config.SlideCameraOffsetY or 0, 0)
		local start = humanoid.CameraOffset
		local dur = math.max(0, Config.SlideCameraLerpSeconds or 0.1)
		local token = {}
		cameraTweenToken = token
		task.spawn(function()
			local t0 = os.clock()
			while os.clock() - t0 < dur do
				if cameraTweenToken ~= token then
					return
				end
				local alpha = (os.clock() - t0) / math.max(dur, 0.001)
				alpha = math.clamp(alpha, 0, 1)
				local y = start.Y + (target.Y - start.Y) * alpha
				humanoid.CameraOffset = Vector3.new(0, y, 0)
				RunService.Heartbeat:Wait()
			end
			if cameraTweenToken == token then
				humanoid.CameraOffset = target
			end
		end)
	end

	-- Maintain horizontal velocity for the duration while preserving vertical component
	task.delay(slideDuration, function()
		stillSliding = false
		endSlide()
	end)

	task.spawn(function()
		local t0 = os.clock()
		local steerDir = moveDir
		while stillSliding and (os.clock() - t0) < slideDuration do
			-- Decay factor 1 -> 0 over the slide duration
			local elapsed = os.clock() - t0
			local alpha = math.clamp(elapsed / math.max(0.001, slideDuration), 0, 1)
			local decay = 1 - alpha
			-- Steering direction from input
			local input = humanoid.MoveDirection
			local dir = nil
			if input.Magnitude > 0.05 then
				dir = Vector3.new(input.X, 0, input.Z)
				if dir.Magnitude > 0.01 then
					dir = dir.Unit
				end
			end
			if dir then
				steerDir = dir
			end
			-- Project current horizontal velocity onto steerDir and apply decayed boost toward minSlideSpeed
			local vcur = rootPart.AssemblyLinearVelocity
			local curH = Vector3.new(vcur.X, 0, vcur.Z)
			local along = curH:Dot(steerDir)
			local perp = curH - steerDir * along
			local targetAlong = math.max(minSlideSpeed, baselineMag)
			local newAlong = targetAlong + (math.max(0, along - targetAlong) * decay)
			local newH = perp + steerDir * newAlong
			rootPart.AssemblyLinearVelocity = Vector3.new(newH.X, vcur.Y, newH.Z)
			task.wait()
		end
	end)

	-- Immediately end slide when a jump begins so vertical physics from jump are not overridden
	jumpConn = humanoid.StateChanged:Connect(function(_old, new)
		if new == Enum.HumanoidStateType.Jumping then
			endSlide()
		end
	end)

	return endSlide
end

local function getParts(character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return root, humanoid
end

-- Compute the world-space top Y of an obstacle (single part or model) using its bounding box
local function computeObstacleTopY(inst)
	if inst and inst:IsA("BasePart") then
		local cf = inst.CFrame
		local size = inst.Size
		local topWorld = cf.Position + (cf.UpVector * (size.Y * 0.5))
		return topWorld.Y
	end
	-- Fallback: if not a BasePart, use position Y
	return (inst and inst.Position and inst.Position.Y) or 0
end

-- Forward declarations for helper detectors used by mantle and vault
local sampleObstacleTopY
local detectObstacleWithThreeRays
local boxDetectFrontTopY

-- Mantle helpers
local function detectLedgeForMantle(root)
	local distance = Config.MantleDetectionDistance or 4.5
	-- Reuse three-ray detector to find a front obstacle and estimate its top
	local topY, res = detectObstacleWithThreeRays(root, distance)
	if not res or not res.Instance or not topY then
		-- Try widened sampling fan
		topY, res = sampleObstacleTopY(root, distance)
		if not res or not res.Instance or not topY then
			-- Fallback: small box overlap in front
			local topY2, res2 = boxDetectFrontTopY(root, distance)
			if not res2 or not res2.Instance or not topY2 then
				-- Extended yaw sweep based on horizontal velocity or facing; helpful after walljump
				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				params.FilterDescendantsInstances = { root.Parent }
				params.IgnoreWater = true
				local halfH = (root.Size and root.Size.Y or 2) * 0.5
				local baseDir
				do
					local vel = root.AssemblyLinearVelocity
					local horiz = Vector3.new(vel.X, 0, vel.Z)
					if horiz.Magnitude > 1.0 then
						baseDir = horiz.Unit
					else
						baseDir = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
						if baseDir.Magnitude < 0.01 then
							baseDir = Vector3.new(0, 0, 1)
						else
							baseDir = baseDir.Unit
						end
					end
				end
				local yawList = {
					0,
					math.rad(15),
					-math.rad(15),
					math.rad(30),
					-math.rad(30),
					math.rad(45),
					-math.rad(45),
					math.rad(60),
					-math.rad(60),
					math.rad(80),
					-math.rad(80),
				}
				local bestY, bestRes = nil, nil
				for _, yaw in ipairs(yawList) do
					local dir = (
						CFrame.fromMatrix(Vector3.new(), root.CFrame.XVector, root.CFrame.YVector, baseDir)
						* CFrame.Angles(0, yaw, 0)
					).LookVector
					local back = -dir
					local points = {
						root.Position + Vector3.new(0, -halfH + 0.1, 0),
						root.Position,
						root.Position + Vector3.new(0, halfH - 0.1, 0),
					}
					for _, p in ipairs(points) do
						local origin = p + back * 0.6
						local r = workspace:Raycast(origin, dir * (distance + 0.6), params)
						if r and r.Instance then
							local ty = computeObstacleTopY(r.Instance)
							if (not bestY) or (ty > bestY) then
								bestY = ty
								bestRes = r
							end
						end
					end
				end
				if bestRes and bestY then
					topY, res = bestY, bestRes
				else
					return false
				end
			else
				topY, res = topY2, res2
			end
		end
	end
	-- Require a solid, collidable surface
	if not res.Instance.CanCollide then
		return false
	end
	-- Verticality filter: near-vertical surfaces only (normal close to horizontal)
	local n = res.Normal
	local verticalDot = math.abs(n:Dot(Vector3.yAxis))
	local allowedDot = (Config.SurfaceVerticalDotMax or Config.SurfaceVerticalDotMin or 0.2)
	if verticalDot > allowedDot then
		return false
	end
	-- Obstacle ahead is used for mantle and for automatic ledge-hang (low ceiling). Mantle still
	-- requires Mantle = true in tryMantle; hang only needs LedgeHang not false (see ParkourSurfaceGate).
	if
		not ParkourSurfaceGate.isMechanicAllowed(res.Instance, "Mantle")
		and not ParkourSurfaceGate.isMechanicAllowed(res.Instance, "LedgeHang")
	then
		return false
	end
	-- Check ledge height within window above waist (root center)
	local waistY = root.Position.Y
	local aboveWaist = topY - waistY
	local minH = Config.MantleMinAboveWaist or 0
	local maxH = Config.MantleMaxAboveWaist or 10
	if aboveWaist < minH or aboveWaist > maxH then
		return false
	end
	return true, res, topY
end

function Abilities.isMantleCandidate(character)
	local root, humanoid = getParts(character)
	if not root or not humanoid then
		return false
	end
	-- Consider mantle candidate if ledge is detectable ahead even without input (use extended sweep)
	local distance = Config.MantleDetectionDistance or 4.5
	local ok, hitRes = detectLedgeForMantle(root)
	if ok == true and hitRes and ParkourSurfaceGate.isMechanicAllowed(hitRes.Instance, "Mantle") then
		return true
	end
	-- Fallback: quick velocity-facing sweep like in detectLedgeForMantle extended branch
	local params = SharedUtils.createParkourRaycastParams(root.Parent)
	local halfH = (root.Size and root.Size.Y or 2) * 0.5
	local baseDir
	local vel = root.AssemblyLinearVelocity
	local horiz = Vector3.new(vel.X, 0, vel.Z)
	if horiz.Magnitude > 1.0 then
		baseDir = horiz.Unit
	else
		baseDir = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
		if baseDir.Magnitude < 0.01 then
			baseDir = Vector3.new(0, 0, 1)
		else
			baseDir = baseDir.Unit
		end
	end
	local yawList = { 0, math.rad(20), -math.rad(20), math.rad(40), -math.rad(40) }
	for _, yaw in ipairs(yawList) do
		local dir = (
			CFrame.fromMatrix(Vector3.new(), root.CFrame.XVector, root.CFrame.YVector, root.CFrame.ZVector)
			* CFrame.Angles(0, yaw, 0)
		).LookVector
		local back = -dir
		local points = {
			root.Position + Vector3.new(0, -halfH + 0.1, 0),
			root.Position,
			root.Position + Vector3.new(0, halfH - 0.1, 0),
		}
		for _, p in ipairs(points) do
			local origin = p + back * 0.6
			local r = workspace:Raycast(origin, dir * (distance + 0.6), params)
			if r and r.Instance and r.Instance.CanCollide then
				if ParkourSurfaceGate.isMechanicAllowed(r.Instance, "Mantle") then
					local topY = computeObstacleTopY(r.Instance)
					local waistY = root.Position.Y
					local above = topY - waistY
					local minH = Config.MantleMinAboveWaist or 0
					local maxH = Config.MantleMaxAboveWaist or 10
					if above >= minH and above <= maxH then
						return true
					end
				end
			end
		end
	end
	return false
end

-- options.climbFinish + options.hitRes + options.topY: skip ray detect and approach-speed gating (used when ending climb on Climbable top).
function Abilities.tryMantle(character, options)
	options = options or {}
	local climbFinish = options.climbFinish == true
	local forcedHitRes = options.hitRes
	local forcedTopY = options.topY

	if not (Config.MantleEnabled ~= false) then
		return false
	end
	local now = os.clock()
	if (now - lastMantleTick) < (Config.MantleCooldownSeconds or 0.35) then
		return false
	end
	local root, humanoid = getParts(character)
	if not root or not humanoid then
		return false
	end

	local ok, hitRes, topY
	if climbFinish and forcedHitRes and forcedHitRes.Instance and typeof(forcedTopY) == "number" then
		if not ParkourSurfaceGate.isMantleAllowedWhenFinishingClimb(forcedHitRes.Instance) then
			return false
		end
		ok, hitRes, topY = true, forcedHitRes, forcedTopY
	else
		ok, hitRes, topY = detectLedgeForMantle(root)
		if not ok then
			return false
		end
	end

	-- Horizontal direction from player toward the obstacle (clearance + approach)
	local toWallVec = (hitRes.Position - root.Position)
	local toWallHoriz = Vector3.new(toWallVec.X, 0, toWallVec.Z)
	if toWallHoriz.Magnitude < 0.05 then
		local n = hitRes.Normal
		toWallHoriz = Vector3.new(-n.X, 0, -n.Z)
	end
	if toWallHoriz.Magnitude < 0.05 then
		toWallHoriz = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	end
	if toWallHoriz.Magnitude < 0.05 then
		return false
	end
	local towards = toWallHoriz.Unit

	-- Approach gating: require facing and velocity towards the wall (skipped when pulling up from climb)
	if not climbFinish then
		local forward = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
		local faceDot = (forward.Magnitude > 0.01) and forward.Unit:Dot(towards) or -1
		local vel = root.AssemblyLinearVelocity
		local horiz = Vector3.new(vel.X, 0, vel.Z)
		local speed = horiz.Magnitude
		local approachDot = (horiz.Magnitude > 0.01) and horiz.Unit:Dot(towards) or -1
		local minFace = Config.MantleFacingDotMin or 0.35
		local minApproach = Config.MantleApproachDotMin or 0.35
		local minSpeed = Config.MantleApproachSpeedMin or 6
		if Config.MantleUseMoveDirFallback then
			local hum = humanoid
			if hum then
				local md = hum.MoveDirection
				if md.Magnitude > 0.01 and horiz.Magnitude < 1.0 then
					local mdHoriz = Vector3.new(md.X, 0, md.Z).Unit
					approachDot = mdHoriz:Dot(towards)
					speed = math.max(speed, hum.WalkSpeed * 0.35)
				end
			end
			local relaxFace = Config.MantleSpeedRelaxDot or 0.9
			local relaxFactor = Config.MantleSpeedRelaxFactor or 0.4
			if faceDot >= relaxFace then
				minApproach = math.min(minApproach, minApproach * relaxFactor)
				minSpeed = math.min(minSpeed, minSpeed * relaxFactor)
			end
		end
		if (faceDot < minFace) or (approachDot < minApproach) or (speed < minSpeed) then
			return false
		end
	end

	-- Final clearance check before starting mantle animation
	-- Only check if we're going to proceed with mantle
	if Config.LedgeHangEnabled then
		local forwardDir = Vector3.new(towards.X, 0, towards.Z).Unit
		local hasClearance = hasEnoughClearanceAbove(root, topY, forwardDir, hitRes.Position)
		if Config.DebugLedgeHang then
			print(
				string.format(
					"[Mantle] Final clearance check: %s (ledgeY=%.2f, required=%.2f)",
					tostring(hasClearance),
					topY,
					Config.LedgeHangMinClearance or 5.0
				)
			)
		end
		if not hasClearance then
			if Config.DebugLedgeHang then
				print("[Mantle] Insufficient clearance, aborting mantle")
			end
			return false -- insufficient clearance, should try ledge hang instead
		end
	end

	if not ParkourSurfaceGate.isMechanicAllowed(hitRes.Instance, "Mantle") then
		return false
	end

	lastMantleTick = now

	-- Log successful mantle execution
	if Config.DebugMantle then
		print("[Mantle] Starting mantle execution for character:", character.Name)
	end
	-- Publish mantling flag (for UI/gating) at start
	pcall(function()
		local rs = game:GetService("ReplicatedStorage")
		local cs = rs:FindFirstChild("ClientState") or Instance.new("Folder")
		if not cs.Parent then
			cs.Name = "ClientState"
			cs.Parent = rs
		end
		local flag = cs:FindFirstChild("IsMantling")
		if not flag then
			flag = Instance.new("BoolValue")
			flag.Name = "IsMantling"
			flag.Value = false
			flag.Parent = cs
		end
		flag.Value = true
	end)

	-- Compute two-phase positions: lift vertically first, then move forward onto platform
	local halfH = (root.Size and root.Size.Y or 2) * 0.5
	local surfaceNormal = hitRes.Normal or -root.CFrame.LookVector
	local intoPlatform = -surfaceNormal
	intoPlatform = Vector3.new(intoPlatform.X, 0, intoPlatform.Z)
	if intoPlatform.Magnitude < 0.05 then
		intoPlatform = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	end
	intoPlatform = intoPlatform.Unit
	local fwdOff = Config.MantleForwardOffset or 1.2
	local upClear = Config.MantleUpClearance or 1.5

	-- Phase 1: pure vertical lift to just above the ledge (align XZ with hit point for curved surfaces)
	local liftY = topY + halfH + upClear
	local contactXZ = Vector3.new(
		(hitRes.Position and hitRes.Position.X) or root.Position.X,
		0,
		(hitRes.Position and hitRes.Position.Z) or root.Position.Z
	)
	local liftPos = Vector3.new(contactXZ.X, liftY, contactXZ.Z)

	-- Phase 2: robust landing for curved surfaces
	local function findLanding()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { root.Parent }
		params.IgnoreWater = true
		-- 1) Try exact top cap solve if part top is horizontal (cylinder, wedge top, etc.)
		do
			local part = hitRes.Instance
			if part and part:IsA("BasePart") then
				local cf = part.CFrame
				local up = cf.UpVector
				if math.abs(up:Dot(Vector3.yAxis)) >= 0.9 then
					local size = part.Size
					local topCenter = cf.Position + (up * (size.Y * 0.5))
					local rxDir = cf.RightVector
					local rzDir = cf.LookVector
					local rX = math.max(0.1, (size.X * 0.5) - 0.05)
					local rZ = math.max(0.1, (size.Z * 0.5) - 0.05)
					-- Vector from top center to our contact XZ
					local toEdge = Vector3.new(contactXZ.X - topCenter.X, 0, contactXZ.Z - topCenter.Z)
					local u = toEdge:Dot(rxDir)
					local v = toEdge:Dot(rzDir)
					-- Clamp inside ellipse
					local denom = (u * u) / (rX * rX) + (v * v) / (rZ * rZ)
					if denom > 1 then
						local scale = 1 / math.sqrt(denom)
						u = u * scale
						v = v * scale
					end
					-- Step inward slightly along inward vector to avoid side lip
					local inward = -toEdge
					local inwardLen = math.max(0.0001, inward.Magnitude)
					local step = math.min(Config.MantleForwardOffset or 1.2, inwardLen - 0.02)
					local iu = (inward:Dot(rxDir) / inwardLen) * step
					local iv = (inward:Dot(rzDir) / inwardLen) * step
					u = u - iu
					v = v - iv
					local px = topCenter.X + rxDir.X * u + rzDir.X * v
					local pz = topCenter.Z + rxDir.Z * u + rzDir.Z * v
					local y = topCenter.Y + halfH + 0.05
					return Vector3.new(px, 0, pz), y
				end
			end
		end
		-- 2) Fallback search: step forward along (possibly re-sampled) inward and require an upward-facing hit
		local maxDist = math.max(0.6, (Config.MantleForwardOffset or 1.2) * 2.0)
		local steps = 12
		local angleSteps = { 0, math.rad(12), -math.rad(12), math.rad(22), -math.rad(22) }
		for _, ang in ipairs(angleSteps) do
			for i = 1, steps do
				local d = (maxDist * i) / steps
				local dir = (CFrame.Angles(0, ang, 0) * CFrame.fromMatrix(
					Vector3.new(),
					Vector3.xAxis,
					Vector3.yAxis,
					intoPlatform
				)).ZVector
				-- Build a world-space direction from rotated frame (fallback if above math yields zero)
				local into = Vector3.new(dir.X, 0, dir.Z)
				if into.Magnitude < 0.01 then
					into = intoPlatform
				end
				into = into.Unit
				local testXZ = Vector3.new(contactXZ.X + into.X * d, 0, contactXZ.Z + into.Z * d)
				local dropOrigin = Vector3.new(testXZ.X, liftY + 6, testXZ.Z)
				local down = workspace:Raycast(dropOrigin, Vector3.new(0, -18, 0), params)
				if down and down.Instance and down.Position and down.Normal then
					-- Accept only upward-facing surfaces (avoid side hits)
					if down.Normal:Dot(Vector3.yAxis) >= 0.8 then
						return testXZ, down.Position.Y
					end
				end
			end
		end
		-- 3) Last resort: straight inward by offset; height remains liftY
		return Vector3.new(
			contactXZ.X + intoPlatform.X * (Config.MantleForwardOffset or 1.2),
			0,
			contactXZ.Z + intoPlatform.Z * (Config.MantleForwardOffset or 1.2)
		),
			liftY
	end
	local finalXZ, groundY = findLanding()
	local finalY = (groundY and (groundY + halfH + 0.05)) or liftY
	local finalPos = Vector3.new(finalXZ.X, finalY, finalXZ.Z)

	-- Optional mantle animation
	local animInst = Animations and Animations.get and Animations.get("Mantle") or nil
	local track = nil
	if animInst then
		local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
		animator.Parent = humanoid
		pcall(function()
			track = animator:LoadAnimation(animInst)
		end)
		if track then
			track.Priority = Enum.AnimationPriority.Action
			-- Stop lower-priority movement/idle tracks so vault dominates fully (prevents Jump loop interfering)
			pcall(function()
				for _, tr in ipairs(animator:GetPlayingAnimationTracks()) do
					local ok, pr = pcall(function()
						return tr.Priority
					end)
					if
						ok
						and (
							pr == Enum.AnimationPriority.Movement
							or pr == Enum.AnimationPriority.Idle
							or pr == Enum.AnimationPriority.Core
						)
					then
						pcall(function()
							tr:Stop(0.05)
						end)
					end
				end
			end)
			-- IK hands marker-driven (Grab, Pass, Release)
			local ikL, ikR
			local targetFolder = workspace:FindFirstChild("MantleTargets") or Instance.new("Folder")
			targetFolder.Name = "MantleTargets"
			targetFolder.Parent = workspace
			local function makeTarget(name, pos)
				local p = Instance.new("Part")
				p.Name = name
				p.Size = Vector3.new(0.2, 0.2, 0.2)
				p.Transparency = 1
				p.CanCollide = false
				p.Anchored = true
				p.CFrame = CFrame.new(pos)
				p.Parent = targetFolder
				local a = Instance.new("Attachment")
				a.Name = "Attach"
				a.Parent = p
				return p, a
			end
			local hitPos = hitRes.Position
			local normal = hitRes.Normal
			local tangent = Vector3.yAxis:Cross(normal)
			if tangent.Magnitude < 0.05 then
				tangent = Vector3.xAxis:Cross(normal)
			end
			tangent = tangent.Unit
			local topYAdj = topY + 0.05
			local center = Vector3.new(hitPos.X, topYAdj, hitPos.Z) - (normal * 0.15)
			local handOffset = 0.5
			local leftPos = center - (tangent * handOffset)
			local rightPos = center + (tangent * handOffset)
			local leftPart, leftAttach = makeTarget("MantleHandL", leftPos)
			local rightPart, rightAttach = makeTarget("MantleHandR", rightPos)
			local function setupIK(side, chainRootName, endEffName, attach)
				local ik = Instance.new("IKControl")
				ik.Name = "IK_Mantle_" .. side
				ik.Type = Enum.IKControlType.Position
				ik.ChainRoot = humanoid.Parent:FindFirstChild(chainRootName)
				ik.EndEffector = humanoid.Parent:FindFirstChild(endEffName)
				ik.Target = attach
				pcall(function()
					ik.Priority = Enum.IKPriority.Body
				end)
				ik.Enabled = false
				ik.Weight = 0
				ik.Parent = humanoid
				return ik
			end
			ikL = setupIK("L", "LeftUpperArm", "LeftHand", leftAttach)
			ikR = setupIK("R", "RightUpperArm", "RightHand", rightAttach)
			local function cleanupIK()
				pcall(function()
					if ikL then
						ikL.Enabled = false
						ikL:Destroy()
					end
				end)
				pcall(function()
					if ikR then
						ikR.Enabled = false
						ikR:Destroy()
					end
				end)
				pcall(function()
					if leftPart then
						leftPart:Destroy()
					end
				end)
				pcall(function()
					if rightPart then
						rightPart:Destroy()
					end
				end)
			end
			local hasMarkers = false
			pcall(function()
				if track:GetMarkerReachedSignal("Grab") then
					hasMarkers = true
				end
			end)
			if hasMarkers then
				track:GetMarkerReachedSignal("Grab"):Connect(function()
					ikL.Enabled = true
					ikR.Enabled = true
					ikL.Weight = 1
					ikR.Weight = 1
				end)
				track:GetMarkerReachedSignal("Pass"):Connect(function()
					ikL.Weight = 0.6
					ikR.Weight = 0.6
				end)
				track:GetMarkerReachedSignal("Release"):Connect(function()
					ikL.Weight = 0
					ikR.Weight = 0
					ikL.Enabled = false
					ikR.Enabled = false
					cleanupIK()
				end)
			else
				-- basic fallback timing
				task.delay(0.08, function()
					ikL.Enabled = true
					ikR.Enabled = true
					ikL.Weight = 1
					ikR.Weight = 1
				end)
				task.delay(0.26, function()
					ikL.Weight = 0.6
					ikR.Weight = 0.6
				end)
				task.delay(0.38, function()
					ikL.Weight = 0
					ikR.Weight = 0
					ikL.Enabled = false
					ikR.Enabled = false
					cleanupIK()
				end)
			end

			-- Try to match playback to mantle duration
			local dur = Config.MantleDurationSeconds or 0.22
			local length = 0
			pcall(function()
				length = track.Length or 0
			end)
			local speed = 1.0
			if dur > 0 and length > 0 then
				speed = length / dur
			end
			track.Looped = false
			track:Play(0.05, 1, speed)
		end
	end

	-- Character collisions remain enabled - only disable obstacle collisions for clean mantle
	local obstaclePrevByPart = {}
	do
		local obstaclePart = hitRes.Instance
		local obstacleParts = {}
		local function gather(inst)
			local node = inst
			local model = nil
			for _ = 1, 5 do
				if not node then
					break
				end
				if node:IsA("Model") then
					model = node
					break
				end
				node = node.Parent
			end
			if model then
				for _, d in ipairs(model:GetDescendants()) do
					if d:IsA("BasePart") then
						table.insert(obstacleParts, d)
					end
				end
			else
				if inst and inst:IsA("BasePart") then
					table.insert(obstacleParts, inst)
				end
			end
		end
		gather(obstaclePart)
		pcall(function()
			if Config.MantleDisableObstacleLocal ~= false then
				for _, p in ipairs(obstacleParts) do
					obstaclePrevByPart[p] = { collide = p.CanCollide, touch = p.CanTouch }
					p.CanCollide = false
					p.CanTouch = false
				end
			end
		end)
	end

	-- Blend in two phases: vertical first, then forward onto platform, with live forward-clear detection
	local startCF = root.CFrame
	local liftCF = CFrame.new(liftPos, liftPos + intoPlatform)
	local finalCF = CFrame.new(finalPos, finalPos + intoPlatform)
	local finalCFCurrent = finalCF
	local total = Config.MantleDurationSeconds or 0.22
	local tLift = math.max(0.05, total * 0.65)
	local tFwd = math.max(0.05, total - tLift)
	local active = true
	local prevAutoRotate = humanoid.AutoRotate
	local prevState = humanoid:GetState()
	local prevWalkSpeed = humanoid.WalkSpeed
	humanoid.AutoRotate = false
	humanoid:ChangeState(Enum.HumanoidStateType.RunningNoPhysics)
	local probeParams = RaycastParams.new()
	probeParams.FilterType = Enum.RaycastFilterType.Exclude
	probeParams.FilterDescendantsInstances = { root.Parent }
	probeParams.IgnoreWater = true
	local preserveSpeed = Config.MantlePreserveSpeed
	local minHz = Config.MantleMinHorizontalSpeed or 0
	task.spawn(function()
		-- Phase 1: vertical lift with edge detection (do not break early)
		local t0 = os.clock()
		local edgeDetected = false
		while active do
			local alpha = math.clamp((os.clock() - t0) / math.max(0.001, tLift), 0, 1)
			-- maintain horizontal speed if requested
			if preserveSpeed then
				local v = root.AssemblyLinearVelocity
				local horiz = Vector3.new(v.X, 0, v.Z)
				local dir = (horiz.Magnitude > 0.01) and horiz.Unit
					or Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
				local spd = math.max(horiz.Magnitude, minHz)
				root.AssemblyLinearVelocity = Vector3.new(dir.X * spd, 0, dir.Z * spd)
			else
				root.AssemblyLinearVelocity = Vector3.new()
			end
			root.CFrame = startCF:Lerp(liftCF, alpha)
			-- Detect edge: when forward ray stops hitting, precompute landing exactly at MantleForwardOffset from contact
			if not edgeDetected then
				local curPos = root.CFrame.Position
				local forwardBlocked =
					workspace:Raycast(curPos, intoPlatform * math.max(1.0, (fwdOff or 1.0)), probeParams)
				if not forwardBlocked then
					local aheadXZ = Vector3.new(
						contactXZ.X + intoPlatform.X * (fwdOff or 1.0),
						0,
						contactXZ.Z + intoPlatform.Z * (fwdOff or 1.0)
					)
					local dropOrigin = Vector3.new(aheadXZ.X, liftY + 12, aheadXZ.Z)
					local down = workspace:Raycast(dropOrigin, Vector3.new(0, -36, 0), probeParams)
					if down and down.Position and down.Normal and (down.Normal:Dot(Vector3.yAxis) >= 0.7) then
						local landY = down.Position.Y
						local posY = math.max(liftY, landY + halfH + 0.05)
						local pos = Vector3.new(aheadXZ.X, posY, aheadXZ.Z)
						finalCFCurrent = CFrame.new(pos, pos + intoPlatform)
						edgeDetected = true
					end
				end
			end
			if alpha >= 1 then
				break
			end
			task.wait()
		end
		-- Phase 2: forward motion to the dynamically chosen target (always from lift top)
		local t1 = os.clock()
		while active do
			local alpha = math.clamp((os.clock() - t1) / math.max(0.001, tFwd), 0, 1)
			if preserveSpeed then
				local v = root.AssemblyLinearVelocity
				local horiz = Vector3.new(v.X, 0, v.Z)
				local dir = (horiz.Magnitude > 0.01) and horiz.Unit or intoPlatform
				local spd = math.max(horiz.Magnitude, minHz)
				root.AssemblyLinearVelocity = Vector3.new(dir.X * spd, 0, dir.Z * spd)
			else
				root.AssemblyLinearVelocity = Vector3.new()
			end
			root.CFrame = liftCF:Lerp(finalCFCurrent, alpha)
			if alpha >= 1 then
				break
			end
			task.wait()
		end
		-- Done: hand control back to physics (character collisions remain enabled)
		active = false
		-- Restore obstacle collision/touch locally
		for part, prev in pairs(obstaclePrevByPart) do
			if part and part.Parent then
				if prev.collide ~= nil then
					part.CanCollide = prev.collide
				end
				if prev.touch ~= nil then
					part.CanTouch = prev.touch
				end
			end
		end
		-- Restore previous state as safely as possible
		humanoid.AutoRotate = prevAutoRotate
		local grounded = (humanoid.FloorMaterial ~= Enum.Material.Air)
		if grounded then
			humanoid:ChangeState(Enum.HumanoidStateType.Running)
			if typeof(prevWalkSpeed) == "number" and prevWalkSpeed > 0 then
				humanoid.WalkSpeed = prevWalkSpeed
			end
		else
			humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		end
		-- Stop mantle track shortly after
		if track then
			task.delay(0.1, function()
				pcall(function()
					track:Stop(0.1)
				end)
			end)
		end
		-- Clear mantling flag at end
		pcall(function()
			local rs = game:GetService("ReplicatedStorage")
			local cs = rs:FindFirstChild("ClientState")
			local flag = cs and cs:FindFirstChild("IsMantling")
			if flag then
				flag.Value = false
			end
		end)

		-- Log successful mantle completion
		if Config.DebugMantle then
			print("[Mantle] Mantle execution completed successfully for character:", character.Name)
		end
	end)

	-- Hard failsafe: ensure cleanup runs even if animations/events are interrupted
	task.delay((Config.MantleDurationSeconds or 0.22) + 0.6, function()
		-- Character collisions remain enabled (only restore obstacle collisions if needed)
		for part, prev in pairs(obstaclePrevByPart) do
			if part and part.Parent then
				if prev.collide ~= nil then
					part.CanCollide = prev.collide
				end
				if prev.touch ~= nil then
					part.CanTouch = prev.touch
				end
			end
		end
		pcall(function()
			local rs = game:GetService("ReplicatedStorage")
			local cs = rs:FindFirstChild("ClientState")
			local flag = cs and cs:FindFirstChild("IsMantling")
			if flag then
				flag.Value = false
			end
		end)

		-- Log failsafe cleanup completion
		if Config.DebugMantle then
			print("[Mantle] Failsafe cleanup completed for character:", character.Name)
		end
	end)

	-- CRITICAL: If player is currently climbing, stop the climb state immediately
	-- This ensures clean transition from climb to mantle without conflicts
	if Config.ClimbMantleIntegrationEnabled then
		local Climb = require(game:GetService("ReplicatedStorage").Movement.Climb)
		if Climb and Climb.isActive and Climb.isActive(character) then
			if Config.DebugMantle then
				print("[Mantle] Stopping climb state before mantle execution")
			end
			Climb.stop(character)

			-- Also cleanup any climb animations that might be running
			pcall(function()
				local rs = game:GetService("ReplicatedStorage")
				local cs = rs:FindFirstChild("ClientState")
				local isClimbingVal = cs and cs:FindFirstChild("IsClimbing")
				if isClimbingVal then
					isClimbingVal.Value = false
				end
			end)

			-- Force cleanup of any climb-related animations
			pcall(function()
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				if humanoid then
					local animator = humanoid:FindFirstChildOfClass("Animator")
					if animator then
						-- Stop any climb animations that might be running
						local stoppedCount = 0
						for _, track in pairs(animator:GetPlayingAnimationTracks()) do
							if track.Animation and track.Animation.AnimationId then
								local animId = tostring(track.Animation.AnimationId)
								if
									string.find(animId, "Climb")
									or string.find(animId, "climb")
									or string.find(animId, "Climbing")
									or string.find(animId, "climbing")
									or string.find(animId, "Wall")
									or string.find(animId, "wall")
								then
									track:Stop(0.05)
									stoppedCount = stoppedCount + 1
									if Config.DebugMantle then
										print("[Mantle] Stopped climb animation:", animId)
									end
								end
							end
						end

						-- Force stop all animations if no specific ones were found
						if stoppedCount == 0 then
							for _, track in pairs(animator:GetPlayingAnimationTracks()) do
								track:Stop(0.05)
								if Config.DebugMantle then
									print(
										"[Mantle] Force stopped animation:",
										track.Animation and track.Animation.Name or "Unknown"
									)
								end
							end
						end

						if Config.DebugMantle then
							print("[Mantle] Animation cleanup completed - stopped", stoppedCount, "animations")
						end
					end
				end
			end)
		end
	end

	return true
end

sampleObstacleTopY = function(root, distance)
	local params = SharedUtils.createParkourRaycastParams(root.Parent)
	local samples = Config.VaultSampleHeights or { 0.15, 0.35, 0.55, 0.75, 0.9 }
	local bestY = nil
	local bestRes = nil
	-- Try a fan of yaw offsets to be tolerant to small aim misalignments
	local yawOffsets = { 0, math.rad(12), -math.rad(12), math.rad(22), -math.rad(22) }
	for _, frac in ipairs(samples) do
		for _, yaw in ipairs(yawOffsets) do
			local dir = (
				CFrame.fromMatrix(Vector3.new(), root.CFrame.XVector, root.CFrame.YVector, root.CFrame.ZVector)
				* CFrame.Angles(0, yaw, 0)
			).LookVector
			-- If player is too close, ray from slightly behind the root to avoid starting inside the obstacle
			local backOffset = dir * -0.8
			local origin = root.Position + Vector3.new(0, (root.Size and root.Size.Y or 2) * frac, 0) + backOffset
			local res = workspace:Raycast(origin, dir * (distance + 0.8), params)
			if res and res.Instance then
				local topY = computeObstacleTopY(res.Instance)
				if (not bestY) or (topY > bestY) then
					bestY = topY
					bestRes = res
				end
			end
		end
	end
	return bestY, bestRes
end

-- Three-ray detector: feet, mid, and head
detectObstacleWithThreeRays = function(root, distance)
	local params = SharedUtils.createParkourRaycastParams(root.Parent)

	local halfH = (root.Size and root.Size.Y or 2) * 0.5
	local look = root.CFrame.LookVector
	local back = -look

	local points = {
		{ name = "feet", pos = root.Position + Vector3.new(0, -halfH + 0.1, 0) },
		{ name = "mid", pos = root.Position },
		{ name = "head", pos = root.Position + Vector3.new(0, halfH - 0.1, 0) },
	}

	for _, p in ipairs(points) do
		local origin = p.pos + back * 0.6
		local res = workspace:Raycast(origin, look * (distance + 0.6), params)
		if res and res.Instance then
			local topY = computeObstacleTopY(res.Instance)
			return topY, res
		end
	end

	return nil, nil
end

-- Fallback detection using a box overlap directly in front of the root (helps when rays start inside the wall)
boxDetectFrontTopY = function(root, distance)
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = SharedUtils.createParkourRaycastParams(root.Parent).FilterDescendantsInstances
	overlap.RespectCanCollide = false
	local forward = root.CFrame.LookVector
	local height = (root.Size and root.Size.Y or 2)
	local center = root.CFrame * CFrame.new(0, 0, math.clamp(distance * 0.5, 0.75, distance))
	local size = Vector3.new(3.0, height * 1.3, math.max(2.0, distance + 0.5))
	local parts = workspace:GetPartBoundsInBox(center, size, overlap)
	local bestY, bestPart = nil, nil
	for _, p in ipairs(parts) do
		if p then
			-- Keep only parts that are generally in front of us
			local toPart = (p.Position - root.Position)
			if toPart:Dot(forward) > 0 then
				local topY = computeObstacleTopY(p)
				if (not bestY) or (topY > bestY) then
					bestY = topY
					bestPart = p
				end
			end
		end
	end
	if bestPart then
		return bestY, { Instance = bestPart, Position = bestPart.Position, Normal = -forward }
	end
	return nil, nil
end

local function isVaultCandidate(root, humanoid)
	if not (Config.VaultEnabled ~= false) then
		return false
	end
	if humanoid.WalkSpeed < (Config.VaultMinSpeed or 24) then
		return false
	end
	-- Primary detector: explicit feet/mid/head rays
	local topY, res = detectObstacleWithThreeRays(root, Config.VaultDetectionDistance or 4.5)
	if not res or not res.Instance or not topY then
		-- Secondary: widen with multi-sample ray fan
		topY, res = sampleObstacleTopY(root, Config.VaultDetectionDistance or 4.5)
	end
	if not res or not res.Instance or not topY then
		-- Fallback: box overlap front detection
		local topY2, res2 = boxDetectFrontTopY(root, Config.VaultDetectionDistance or 4.5)
		if not res2 or not res2.Instance or not topY2 then
			-- Fallback 2: recent touched collidable part from client state (handles CanQuery=false)
			local folder = game:GetService("ReplicatedStorage"):FindFirstChild("ClientState")
			local partVal = folder and folder:FindFirstChild("VaultTouchPart")
			local timeVal = folder and folder:FindFirstChild("VaultTouchTime")
			local posVal = folder and folder:FindFirstChild("VaultTouchPos")
			local touchedPart = partVal and partVal.Value or nil
			local touchedWhen = timeVal and timeVal.Value or 0
			local touchedPos = posVal and posVal.Value or nil
			local recent = touchedPart and ((os.clock() - touchedWhen) < 0.35)
			if recent and touchedPart and touchedPart.Parent and touchedPart.CanCollide then
				local topY3 = computeObstacleTopY(touchedPart)
				local res3 = {
					Instance = touchedPart,
					Position = touchedPos or touchedPart.Position,
					Normal = -root.CFrame.LookVector,
				}
				topY, res = topY3, res3
			else
				return false
			end
		else
			topY, res = topY2, res2
		end
	end
	local hit = res.Instance
	-- Approach gating: require facing/motion toward the obstacle to prevent triggering when moving away/off edges
	local toObstacle = (res.Position - root.Position)
	local toObstacleHoriz = Vector3.new(toObstacle.X, 0, toObstacle.Z)
	if toObstacleHoriz.Magnitude < 0.05 then
		return false
	end
	local towards = toObstacleHoriz.Unit
	local forward = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	local faceDot = (forward.Magnitude > 0.01) and forward.Unit:Dot(towards) or -1
	local vel = root.AssemblyLinearVelocity
	local horiz = Vector3.new(vel.X, 0, vel.Z)
	local speed = horiz.Magnitude
	local approachDot = (horiz.Magnitude > 0.01) and horiz.Unit:Dot(towards) or -1
	local minFace = Config.VaultFacingDotMin or 0.35
	local minApproach = Config.VaultApproachDotMin or 0.35
	local minSpeed = Config.VaultApproachSpeedMin or 6
	if (faceDot < minFace) or (approachDot < minApproach) or (speed < minSpeed) then
		return false
	end
	-- Attribute check: only block if attribute explicitly set to false; missing or true are allowed
	local function getVaultAttr(inst)
		local cur = inst
		for _ = 1, 4 do
			if not cur then
				break
			end
			if typeof(cur.GetAttribute) == "function" then
				local val = cur:GetAttribute("Vault")
				if val ~= nil then
					return val
				end
			end
			cur = cur.Parent
		end
		return nil
	end
	local vattr = getVaultAttr(hit)
	if vattr == false then
		return false
	end
	if not hit.CanCollide then
		return false
	end
	local feetY
	if Config.VaultUseGroundHeight then
		local downParams = RaycastParams.new()
		downParams.FilterType = Enum.RaycastFilterType.Exclude
		downParams.FilterDescendantsInstances = { root.Parent }
		downParams.IgnoreWater = true
		local start = root.Position + Vector3.new(0, (root.Size and root.Size.Y or 2) * 0.5, 0)
		local down = workspace:Raycast(start, Vector3.new(0, -40, 0), downParams)
		local groundY = down and down.Position and down.Position.Y
			or (root.Position.Y - ((root.Size and root.Size.Y or 2) * 0.5))
		feetY = groundY
	else
		feetY = root.Position.Y - ((root.Size and root.Size.Y or 2) * 0.5)
	end
	local h = topY - feetY
	local minH = Config.VaultMinHeight or 1.0
	local maxH = Config.VaultMaxHeight or 4.0
	if h < minH or h > maxH then
		return false
	end
	-- Always log a concise candidate line for troubleshooting high obstacles
	local spd = humanoid and humanoid.WalkSpeed or 0
	return true, res, topY
end

local function pickVaultAnimation()
	-- Use the new vault animation system for random selection
	if Animations and Animations.getRandomVaultAnimation then
		local animInst, animName = Animations.getRandomVaultAnimation()
		if animInst then
			-- Debug logging (disabled for production)
			-- print("[Vault] Selected animation:", animName)
			return animInst
		end
	end

	-- Fallback to old system if new system not available
	local keys = Config.VaultAnimationKeys or {}
	if #keys == 0 then
		return nil
	end
	local idx = math.random(1, #keys)
	local key = keys[idx]
	return Animations and Animations.get and Animations.get(key) or nil
end

function Abilities.tryVault(character)
	local now = os.clock()
	if (now - lastVaultTick) < (Config.VaultCooldownSeconds or 0.6) then
		return false
	end
	local root, humanoid = getParts(character)
	if not root or not humanoid then
		return false
	end
	local ok, res, topY = isVaultCandidate(root, humanoid)
	if not ok then
		return false
	end
	lastVaultTick = now

	-- Dynamic clearance: compute Y velocity so that current position will rise above topY + clearance
	local clearance = Config.VaultClearanceStuds or 1.5
	local desiredY = topY + clearance
	local curY = root.Position.Y
	local needUp = math.max(0, desiredY - curY)
	-- Physics-based vertical speed: v = sqrt(2 * g * height)
	local g = workspace and workspace.Gravity or 196.2
	local requiredUp = math.sqrt(math.max(0, 2 * g * needUp))
	local upMin = Config.VaultUpMin or 8
	local upMax = Config.VaultUpMax -- optional cap
	local upV = math.max(requiredUp, upMin)
	-- If a cap exists but is below the physics requirement, prefer the requirement to ensure clearance
	local forwardBase = (Config.VaultForwardBoost or 26)
	local forwardGain = 0
	if Config.VaultForwardUseHeight then
		forwardGain = (Config.VaultForwardGainPerHeight or 2.5) * needUp
	end
	local forward = root.CFrame.LookVector * (forwardBase + forwardGain)
	if Config.VaultPreserveSpeed then
		local v = root.AssemblyLinearVelocity
		local horiz = Vector3.new(v.X, 0, v.Z)
		local cur = horiz.Magnitude
		local dir = (horiz.Magnitude > 0.01) and horiz.Unit
			or Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
		local target = math.max(cur, (forwardBase + forwardGain))
		forward = dir * target
	end
	local up = Vector3.new(0, upV, 0)
	root.AssemblyLinearVelocity = Vector3.new(forward.X, up.Y, forward.Z)
	humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	-- Character collisions remain enabled - only disable obstacle collisions for smooth vault

	-- Also disable collision/touch on the obstacle locally so this client never collides during vault
	local obstaclePart = res.Instance
	local obstaclePrevCanCollide
	local obstaclePrevCanTouch
	local obstaclePrevByPart = {}
	local obstacleParts = {}
	local function gatherObstacleParts(inst)
		local node = inst
		local model = nil
		for _ = 1, 5 do
			if not node then
				break
			end
			if node:IsA("Model") then
				model = node
				break
			end
			node = node.Parent
		end
		if model then
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					table.insert(obstacleParts, d)
				end
			end
		else
			if inst and inst:IsA("BasePart") then
				table.insert(obstacleParts, inst)
			end
		end
	end
	gatherObstacleParts(obstaclePart)
	pcall(function()
		-- Keep single-part fields for backward compatibility
		if obstaclePart then
			obstaclePrevCanCollide = obstaclePart.CanCollide
			obstaclePrevCanTouch = obstaclePart.CanTouch
		end
		if Config.VaultDisableObstacleLocal ~= false then
			for _, p in ipairs(obstacleParts) do
				obstaclePrevByPart[p] = { collide = p.CanCollide, touch = p.CanTouch }
				p.CanCollide = false
				p.CanTouch = false
			end
		end
	end)

	-- Maintain a consistent horizontal velocity during the vault to guarantee clearing the obstacle
	local horizontalVel = Vector3.new(forward.X, 0, forward.Z)
	local stillVaulting = true
	task.spawn(function()
		local t0 = os.clock()
		local dur = Config.VaultDurationSeconds or 0.35
		while stillVaulting and (os.clock() - t0) < dur do
			-- keep horizontal speed; let vertical be driven by physics/retargeting
			local vy = root.AssemblyLinearVelocity.Y
			root.AssemblyLinearVelocity = Vector3.new(horizontalVel.X, vy, horizontalVel.Z)
			task.wait()
		end
	end)

	-- Set vaulting flag to gate other mechanics on the client
	local rs = game:GetService("ReplicatedStorage")
	local cs = rs:FindFirstChild("ClientState")
	if cs then
		local v = cs:FindFirstChild("IsVaulting")
		if not v then
			v = Instance.new("BoolValue")
			v.Name = "IsVaulting"
			v.Value = false
			v.Parent = cs
		end
		v.Value = true
	end

	-- Align root height to retarget authored 3-stud motion to current obstacle height
	do
		local canon = Config.VaultCanonicalHeightStuds or 3.0
		local alignBlend = Config.VaultAlignBlendSeconds or 0.12
		local alignHold = Config.VaultAlignHoldSeconds or 0.08
		-- Compute feet height at animation start
		local halfH = (root.Size and root.Size.Y or 2) * 0.5
		local feetY0 = root.Position.Y - halfH
		-- World Y where the authored 3-stud top would be
		local canonicalTopWorldY = feetY0 + canon
		-- Desired top world Y (real obstacle top + clearance)
		local desiredTopWorldY = topY + (Config.VaultClearanceStuds or 1.5)
		-- Delta we need to shift the whole pose by to match authored motion to real top
		local deltaY = desiredTopWorldY - canonicalTopWorldY
		local startCF = root.CFrame
		local targetCF = startCF + Vector3.new(0, deltaY, 0)
		local releasedHeight = false
		local t0 = os.clock()
		task.spawn(function()
			-- Blend a small vertical CF offset, then hold briefly
			while (os.clock() - t0) < alignBlend do
				local alpha = math.clamp((os.clock() - t0) / alignBlend, 0, 1)
				root.CFrame = startCF:Lerp(targetCF, alpha)
				task.wait()
			end
			-- Hold Y at or above target for a short window, or until released
			local holdUntil = os.clock() + alignHold
			while stillVaulting and not releasedHeight and os.clock() < holdUntil do
				root.CFrame = CFrame.new(root.Position.X, math.max(root.Position.Y, targetCF.Y), root.Position.Z)
					* CFrame.fromMatrix(Vector3.new(), root.CFrame.XVector, root.CFrame.YVector, root.CFrame.ZVector)
				task.wait()
			end
			-- Extra guard: if no markers, keep floor on Y for part of the vault duration
			local guardUntil = os.clock() + (Config.VaultDurationSeconds or 0.35) * 0.6
			while stillVaulting and not releasedHeight and os.clock() < guardUntil do
				root.CFrame = CFrame.new(root.Position.X, math.max(root.Position.Y, targetCF.Y), root.Position.Z)
					* CFrame.fromMatrix(Vector3.new(), root.CFrame.XVector, root.CFrame.YVector, root.CFrame.ZVector)
				task.wait()
			end
		end)
	end

	-- Use the new vault animation system for guaranteed completion
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = humanoid

	local track, errorMsg
	if Animations and Animations.playRandomVaultAnimationWithDuration then
		-- Use new system for guaranteed animation completion
		track, errorMsg = Animations.playRandomVaultAnimationWithDuration(animator, {
			priority = Enum.AnimationPriority.Action,
			onComplete = function(actualDuration, targetDuration)
				-- Animation completed successfully
				if Config.DebugVault then
					print("[Vault] Animation completed in", string.format("%.3f", actualDuration), "s")
				end
			end,
			debug = Config.DebugVault,
		})

		if not track and errorMsg then
			print("[Vault] Animation error:", errorMsg)
		end
	end

	-- Fallback to old system if new system not available
	if not track then
		local animInst = pickVaultAnimation()
		if animInst then
			pcall(function()
				track = animator:LoadAnimation(animInst)
			end)
			if track then
				track.Priority = Enum.AnimationPriority.Action
				track:Play(0.05, 1, 1)
			end
		end
	end

	if track then
		-- Hand IK setup (simple target holders)
		local targetsFolder = workspace:FindFirstChild("VaultTargets") or Instance.new("Folder")
		targetsFolder.Name = "VaultTargets"
		targetsFolder.Parent = workspace
		local function makeTarget(name, pos)
			local p = Instance.new("Part")
			p.Name = name
			p.Size = Vector3.new(0.2, 0.2, 0.2)
			p.Transparency = 1
			p.CanCollide = false
			p.Anchored = true
			p.CFrame = CFrame.new(pos)
			p.Parent = targetsFolder
			local a = Instance.new("Attachment")
			a.Name = "Attach"
			a.Parent = p
			return p, a
		end
		-- Compute two hand points along the obstacle top edge
		local hitPos = res.Position
		local normal = res.Normal
		local tangent = Vector3.yAxis:Cross(normal)
		if tangent.Magnitude < 0.05 then
			tangent = Vector3.xAxis:Cross(normal)
		end
		tangent = tangent.Unit
		local topYAdj = topY + 0.05
		local center = Vector3.new(hitPos.X, topYAdj, hitPos.Z) - (normal * 0.15)
		local handOffset = 0.5
		local leftPos = center - (tangent * handOffset)
		local rightPos = center + (tangent * handOffset)
		local leftPart, leftAttach = makeTarget("VaultHandL", leftPos)
		local rightPart, rightAttach = makeTarget("VaultHandR", rightPos)

		local function setupIK(side, chainRootName, endEffName, attach)
			local ik = Instance.new("IKControl")
			ik.Name = "IK_Vault_" .. side
			ik.Type = Enum.IKControlType.Position
			ik.ChainRoot = humanoid.Parent:FindFirstChild(chainRootName)
			ik.EndEffector = humanoid.Parent:FindFirstChild(endEffName)
			ik.Target = attach
			pcall(function()
				ik.Priority = Enum.IKPriority.Body
			end)
			ik.Enabled = false
			ik.Weight = 0
			ik.Parent = humanoid
			return ik
		end
		local ikL = setupIK("L", "LeftUpperArm", "LeftHand", leftAttach)
		local ikR = setupIK("R", "RightUpperArm", "RightHand", rightAttach)

		local function cleanupIK()
			pcall(function()
				ikL.Enabled = false
				ikL:Destroy()
			end)
			pcall(function()
				ikR.Enabled = false
				ikR:Destroy()
			end)
			pcall(function()
				leftPart:Destroy()
			end)
			pcall(function()
				rightPart:Destroy()
			end)
		end

		local ended = false
		local function endVault()
			if ended then
				return
			end
			ended = true
			stillVaulting = false
			cleanupIK()
			-- Character collisions remain enabled
			-- Restore obstacle collision/touch locally
			for part, prev in pairs(obstaclePrevByPart) do
				if part and part.Parent then
					if prev.collide ~= nil then
						part.CanCollide = prev.collide
					end
					if prev.touch ~= nil then
						part.CanTouch = prev.touch
					end
				end
			end
			-- Clear vaulting flag
			local cs2 = game:GetService("ReplicatedStorage"):FindFirstChild("ClientState")
			local v2 = cs2 and cs2:FindFirstChild("IsVaulting")
			if v2 then
				v2.Value = false
			end
		end

		-- Marker-driven if present; else time-based fallback
		local hasMarkers = false
		pcall(function()
			if track:GetMarkerReachedSignal("Grab") then
				hasMarkers = true
			end
		end)
		if hasMarkers then
			track:GetMarkerReachedSignal("Grab"):Connect(function()
				ikL.Enabled = true
				ikR.Enabled = true
				ikL.Weight = 1
				ikR.Weight = 1
			end)
			track:GetMarkerReachedSignal("Pass"):Connect(function()
				ikL.Weight = 0.6
				ikR.Weight = 0.6
				releasedHeight = true
			end)
			track:GetMarkerReachedSignal("Release"):Connect(function()
				ikL.Weight = 0
				ikR.Weight = 0
				ikL.Enabled = false
				ikR.Enabled = false
				cleanupIK()
				releasedHeight = true
				endVault()
			end)
		else
			-- Fallback timeline: enable/hold/disable
			task.delay(0.08, function()
				ikL.Enabled = true
				ikR.Enabled = true
				ikL.Weight = 1
				ikR.Weight = 1
				task.delay(0.18, function()
					ikL.Weight = 0.6
					ikR.Weight = 0.6
					releasedHeight = true
					task.delay(0.12, function()
						ikL.Weight = 0
						ikR.Weight = 0
						ikL.Enabled = false
						ikR.Enabled = false
						cleanupIK()
						endVault()
					end)
				end)
			end)
		end

		local vaultEnded = false

		if Config.VaultAnimationIndependentDuration then
			-- Animation completes independently of vault physics
			-- Only end vault physics when the vault duration is reached
			task.delay(Config.VaultDurationSeconds or 0.35, function()
				if not vaultEnded then
					vaultEnded = true
					-- End vault physics but let animation continue
					endVault()
				end
			end)

			-- Stop animation only when it naturally completes or on error
			track.Stopped:Connect(function()
				if not vaultEnded then
					vaultEnded = true
					endVault()
				end
			end)
		else
			-- Original behavior: stop animation when vault ends
			track.Stopped:Connect(function()
				endVault()
			end)
			task.delay(Config.VaultDurationSeconds or 0.35, function()
				pcall(function()
					track:Stop(0.1)
				end)
				endVault()
			end)
		end
	else
		-- No animation: still restore collisions after duration
		local ended = false
		local function endVaultNoAnim()
			if ended then
				return
			end
			ended = true
			stillVaulting = false
			-- Character collisions remain enabled
			-- Restore obstacle collision/touch locally
			for part, prev in pairs(obstaclePrevByPart) do
				if part and part.Parent then
					if prev.collide ~= nil then
						part.CanCollide = prev.collide
					end
					if prev.touch ~= nil then
						part.CanTouch = prev.touch
					end
				end
			end
			local cs2 = game:GetService("ReplicatedStorage"):FindFirstChild("ClientState")
			local v2 = cs2 and cs2:FindFirstChild("IsVaulting")
			if v2 then
				v2.Value = false
			end
		end
		task.delay(Config.VaultDurationSeconds or 0.35, function()
			endVaultNoAnim()
		end)
	end

	-- Hard failsafe for vault: ensure flags restored even if interrupted (character collisions remain enabled)
	task.delay((Config.VaultDurationSeconds or 0.35) + 0.6, function()
		for part, prev in pairs(obstaclePrevByPart) do
			if part and part.Parent then
				if prev.collide ~= nil then
					part.CanCollide = prev.collide
				end
				if prev.touch ~= nil then
					part.CanTouch = prev.touch
				end
			end
		end
		pcall(function()
			local cs2 = game:GetService("ReplicatedStorage"):FindFirstChild("ClientState")
			local v2 = cs2 and cs2:FindFirstChild("IsVaulting")
			if v2 then
				v2.Value = false
			end
		end)
	end)
	return true
end

function Abilities.resetAirDashCharges(character)
	airDashCharges[character] = Config.DashAirChargesDefault or 1
end

function Abilities.addAirDashCharge(character, amount)
	local cur = airDashCharges[character] or 0
	local maxC = Config.DashAirChargesMax or (Config.DashAirChargesDefault or 1)
	airDashCharges[character] = math.min(maxC, cur + (amount or 1))
end

-- Export mantle detection for ledge hang system
function Abilities.detectLedgeForMantle(root)
	return detectLedgeForMantle(root)
end

return Abilities
