-- Wall jumping helper

local Config = require(game:GetService("ReplicatedStorage").Movement.Config)
local WallMemory = require(game:GetService("ReplicatedStorage").Movement.WallMemory)
local Animations = require(game:GetService("ReplicatedStorage").Movement.Animations)
local WallRun = require(game:GetService("ReplicatedStorage").Movement.WallRun)
local Climb = require(game:GetService("ReplicatedStorage").Movement.Climb)
local ParkourSurfaceGate = require(game:GetService("ReplicatedStorage").Movement.ParkourSurfaceGate)

local WallJump = {}

local lastJumpTick = 0
local activeAnimationTracks = {} -- To follow character active by character
local activeWallSlides = {} -- To follow characters that are on Wall Slide
local stopWallSlide -- forward declaration
local slideCooldownUntil = {} -- Cooldown to prevent immediate re-entering slide after jumping
local cachedSlideTrackByHumanoid = setmetatable({}, { __mode = "k" }) -- weak keys: humanoid -> AnimationTrack

-- Wallslide toggle system
local wallslideDisabled = {} -- [character] = true if wallslide is temporarily disabled

-- Configurable parameters for the wall slide
local WALL_SLIDE_FALL_SPEED = Config.WallSlideFallSpeed -- Fall speed during the wall slide
local WALL_STICK_VELOCITY = Config.WallSlideStickVelocity -- Force with which the character sticks to the wall
local WALL_SLIDE_MAX_DURATION = Config.WallSlideMaxDurationSeconds -- Maximum duration of Wall Slide

local function getCharacterParts(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return root, humanoid
end

local function isCharacterAirborne(character)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false
	end

	return humanoid.FloorMaterial == Enum.Material.Air
end

-- Modified function to verify if a wall is appropriate for wall slide
-- (It should not be climbable and should allow Wall Jump)
local function findNearbyWallForSlide(rootPart)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { rootPart.Parent }
	params.IgnoreWater = Config.RaycastIgnoreWater

	local offsets = {
		rootPart.CFrame.RightVector,
		-rootPart.CFrame.RightVector,
		rootPart.CFrame.LookVector,
		-rootPart.CFrame.LookVector,
	}

	for _, dir in ipairs(offsets) do
		local result = workspace:Raycast(rootPart.Position, dir * (Config.WallSlideDetectionDistance or 4), params)
		if result and result.Instance and result.Instance.CanCollide then
			-- Verticality filter: accept only near-vertical surfaces (normal close to horizontal)
			local n = result.Normal
			local verticalDot = math.abs(n:Dot(Vector3.yAxis))
			local allowedDot = (Config.SurfaceVerticalDotMax or Config.SurfaceVerticalDotMin or 0.2)
			if verticalDot <= allowedDot then
				local inst = result.Instance
				if ParkourSurfaceGate.isMechanicAllowed(inst, "WallJump") then
					return result
				end
			end
		end
	end

	return nil
end

-- The original Findarbywall function remains for other functionalities
local function findNearbyWall(rootPart)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { rootPart.Parent }
	params.IgnoreWater = Config.RaycastIgnoreWater

	-- Use multiple raycast origins like VerticalClimb for better detection
	local origins = {
		rootPart.Position,
		rootPart.Position + Vector3.new(0, 1.4, 0),
		rootPart.Position + Vector3.new(0, -1.0, 0),
		rootPart.Position + (rootPart.CFrame.RightVector * 0.6),
		rootPart.Position - (rootPart.CFrame.RightVector * 0.6),
	}

	local offsets = {
		rootPart.CFrame.RightVector,
		-rootPart.CFrame.RightVector,
		rootPart.CFrame.LookVector,
		-rootPart.CFrame.LookVector,
	}

	local bestResult = nil
	local bestDistance = math.huge

	for _, origin in ipairs(origins) do
		for _, dir in ipairs(offsets) do
			local result = workspace:Raycast(origin, dir * (Config.WallSlideDetectionDistance or 4), params)
			if result and result.Instance and result.Instance.CanCollide then
				-- Verticality filter: accept only near-vertical surfaces (normal close to horizontal)
				local n = result.Normal
				local verticalDot = math.abs(n:Dot(Vector3.yAxis))
				-- Use a more lenient threshold for wall jump detection
				local allowedDot = 0.5 -- More lenient than Config.SurfaceVerticalDotMax (0.1)
				if verticalDot <= allowedDot then
					local inst = result.Instance
					if ParkourSurfaceGate.isMechanicAllowed(inst, "WallJump") then
						-- Choose the closest wall for better accuracy
						local distance = (result.Position - origin).Magnitude
						if distance < bestDistance then
							bestDistance = distance
							bestResult = result
						end
					end
				end
			end
		end
	end

	return bestResult
end

-- Function to reproduce Walljump animation
local function playWallJumpAnimation(character)
	if not character then
		return nil
	end

	-- Stop any previous animation of Wall Jump
	if activeAnimationTracks[character] then
		pcall(function()
			activeAnimationTracks[character]:Stop(0.1)
		end)
		activeAnimationTracks[character] = nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end

	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = humanoid

	-- Reuse prewarmed track if available for instant readiness
	local track = cachedSlideTrackByHumanoid[humanoid]
	if not track then
		local animInst = Animations.get("WallJump")
		if not animInst then
			return nil
		end
		pcall(function()
			track = animator:LoadAnimation(animInst)
		end)
		if track then
			cachedSlideTrackByHumanoid[humanoid] = track
		end
	end

	if track then
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = true
		-- Play paused and seek to the last frame to hold pose
		track:Play(0, 1, 0)
		local function snapToLastFrame()
			local len = track.Length or 0
			if len and len > 0 then
				local epsilon = 1 / 30
				pcall(function()
					track.TimePosition = math.max(0, len - epsilon)
					track:AdjustSpeed(0)
				end)
				return true
			end
			return false
		end
		if not snapToLastFrame() then
			-- Fallback if length not ready yet
			local conn
			conn = track:GetPropertyChangedSignal("Length"):Connect(function()
				if snapToLastFrame() and conn then
					conn:Disconnect()
					conn = nil
				end
			end)
			task.delay(0.2, function()
				if conn then
					conn:Disconnect()
					conn = nil
					snapToLastFrame()
				end
			end)
		end
		activeAnimationTracks[character] = track
		return track
	end

	return nil
end

-- Verify if we must activate the wall slide
local function shouldActivateWallSlide(character)
	-- Just activate the wall slide if the character is in the air and near an appropriate wall
	if not character then
		return false
	end

	-- Check if wallslide is manually disabled
	if wallslideDisabled[character] then
		return false
	end

	-- If there are active co -procown, not activate
	local now = os.clock()
	local untilT = slideCooldownUntil[character]
	if untilT and now < untilT then
		return false
	end

	-- If the wallrun is active, we do not activate the wall slide
	if WallRun.isActive(character) then
		return false
	end

	-- If the Climb is active, we do not activate the wall slide (but we do allow close to climbable)
	if Climb.isActive(character) then
		return false
	end

	-- Verify if it is in the air
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false
	end

	local isAirborne = isCharacterAirborne(character)
	if not isAirborne then
		return false
	end

	--Verify if it is close to an appropriate wall for wall slide
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end

	local hit = findNearbyWallForSlide(root)
	return hit ~= nil
end

-- Start the wall slide for a character (following a pattern similar to wallrun)
local function startWallSlide(character, hitResult)
	if not character or not hitResult then
		return
	end

	local root, humanoid = getCharacterParts(character)
	if not root or not humanoid then
		return
	end

	-- Change to a controlled state early
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)

	-- Save original values
	local originalGravity = workspace.Gravity
	local token = {} -- Token to identify this Wall Slide session

	-- Save information from the Wall Slide
	activeWallSlides[character] = {
		wallNormal = hitResult.Normal,
		startTime = os.clock(),
		hitInstance = hitResult.Instance,
		token = token,
		humanoid = humanoid,
		animReady = false,
	}

	-- Play slide animation pose and only after it is ready, allow slide state to be considered fully active
	-- Play immediately using cached track (instant snap)
	local track = playWallJumpAnimation(character)
	if track then
		local data = activeWallSlides[character]
		if data then
			-- Mark ready immediately; we force TimePosition below
			data.animReady = true
		end
		-- Force to last frame instantly to avoid any blend delay
		local len = track.Length or 0
		local epsilon = 1 / 30
		pcall(function()
			track.TimePosition = (len > 0) and math.max(0, len - epsilon) or 0
			track:AdjustSpeed(0)
		end)
	end

	-- Configure a maximum timer for the wall slide
	task.delay(WALL_SLIDE_MAX_DURATION, function()
		local data = activeWallSlides[character]
		if data and data.token == token then
			stopWallSlide(character)
		end
	end)
end

-- Stop the Wall Slide for a character
stopWallSlide = function(character)
	if not character then
		return
	end

	local data = activeWallSlides[character]
	if not data then
		return
	end

	-- Restore humanoid state and clear residual slide velocity
	local humanoid = data.humanoid
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Parent then
		local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
		if root then
			local vel = root.AssemblyLinearVelocity
			if grounded then
				root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
				-- ensure we resume normal locomotion on ground
				humanoid:ChangeState(Enum.HumanoidStateType.Running)
			else
				-- in air: drop horizontal stick so we don't keep sliding along wall
				root.AssemblyLinearVelocity = Vector3.new(0, vel.Y, 0)
				-- freefall for natural gravity
				humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
			end
		else
			-- fallback: set to freefall if no root
			humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		end
	end

	-- Clean
	activeWallSlides[character] = nil

	-- Stop animation
	if activeAnimationTracks[character] then
		pcall(function()
			activeAnimationTracks[character]:Stop(0.1)
		end)
		activeAnimationTracks[character] = nil
	end
end

-- Updates the Physics of the Wall Slide (similar to the Mainintin of Wallrun)
function WallJump.updateWallSlide(character, dt)
	if not character or not activeWallSlides[character] then
		return
	end

	-- If the wallrun is active, we stop the wall slide
	if WallRun.isActive(character) then
		stopWallSlide(character)
		return
	end

	-- If the climb is active, we stop the wall slide (we allow close to climate)
	if Climb.isActive(character) then
		stopWallSlide(character)
		return
	end

	local root, humanoid = getCharacterParts(character)
	if not root or not humanoid then
		stopWallSlide(character)
		return
	end

	-- Stamina drain handled centrally in ParkourController; only react to stop when controller cuts stamina

	-- If player initiated a jump, immediately stop sliding (ignore Jump held flag)
	local state = humanoid:GetState()
	if state == Enum.HumanoidStateType.Jumping then
		stopWallSlide(character)
		return false
	end

	-- Verify if you are still in the air
	if humanoid.FloorMaterial ~= Enum.Material.Air then
		-- zero velocity before stopping to avoid horizontal drift
		local root = character:FindFirstChild("HumanoidRootPart")
		if root then
			root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		end
		stopWallSlide(character)
		return false
	end

	-- Verify if it is still close to an appropriate wall for wall slide
	local hit = findNearbyWallForSlide(root)
	if not hit then
		stopWallSlide(character)
		return false
	end

	local data = activeWallSlides[character]

	-- Update the normal wall
	local normal = hit.Normal
	data.wallNormal = normal

	-- Calculate the stick towards the wall (similar to wallrun)
	local stickForce = -normal * WALL_STICK_VELOCITY

	-- Calculate the new speed with controlled drop and stick to the wall, but if the player presses Space, avoid strong glue
	local newVelocity = Vector3.new(stickForce.X, -WALL_SLIDE_FALL_SPEED, stickForce.Z)

	-- Early exit based on ground proximity (<= 2 studs from feet)
	do
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character }
		params.IgnoreWater = Config.RaycastIgnoreWater
		local rayDist = 4
		local ground = workspace:Raycast(root.Position, Vector3.new(0, -rayDist, 0), params)
		if ground then
			local halfHeight = (root.Size and root.Size.Y or 2) * 0.5
			local feetY = root.Position.Y - halfHeight
			local verticalGap = feetY - ground.Position.Y
			local threshold = Config.WallSlideGroundProximityStuds or 2.0
			if verticalGap <= threshold then
				-- Kill horizontal drift and add a short cooldown to avoid re-entering slide before landing
				root.AssemblyLinearVelocity = Vector3.new(0, math.min(root.AssemblyLinearVelocity.Y, 0), 0)
				slideCooldownUntil[character] = os.clock() + 0.5
				stopWallSlide(character)
				return false
			end
		end
	end

	-- Apply the new speed (only while airborne). Clamp downward speed, don't force extra downward when upward momentum exists.
	if humanoid.FloorMaterial == Enum.Material.Air then
		local v = root.AssemblyLinearVelocity
		local vy = math.max(-WALL_SLIDE_FALL_SPEED, v.Y)
		root.AssemblyLinearVelocity = Vector3.new(newVelocity.X, vy, newVelocity.Z)
	end

	-- Orient character to face the wall (stable up axis)
	local lookDir = -normal
	root.CFrame = CFrame.lookAt(root.Position, root.Position + lookDir, Vector3.yAxis)

	return true
end

function WallJump.isNearWall(character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	local hit = findNearbyWall(root)

	-- For the Slide Wall, we use the specialized function that now allows weather walls
	local hitForSlide = findNearbyWallForSlide(root)

	-- Verify if we must activate the wall slide (require stamina > 0)
	local staminaOk = true
	do
		local folder = game:GetService("ReplicatedStorage"):FindFirstChild("ClientState")
		local staminaValue = folder and folder:FindFirstChild("Stamina")
		if staminaValue and staminaValue.Value <= 0 then
			staminaOk = false
		end
	end
	local shouldActivate = staminaOk and shouldActivateWallSlide(character)

	-- If it must be activated and is not active, start it
	if shouldActivate and not activeWallSlides[character] and hitForSlide then
		startWallSlide(character, hitForSlide)
	-- If it should not be activated but it is active, stop it
	elseif not shouldActivate and activeWallSlides[character] then
		stopWallSlide(character)
	end

	return hit ~= nil
end

function WallJump.isWallSliding(character)
	return activeWallSlides[character] ~= nil
end

function WallJump.stopSlide(character)
	stopWallSlide(character)
end

function WallJump.canWallJump(character)
	-- True if slide is active and animation pose is ready, or if wall run is active (hop)
	local data = activeWallSlides[character]
	if data and data.animReady == true then
		return true
	end
	if require(game:GetService("ReplicatedStorage").Movement.WallRun).isActive(character) then
		return true
	end
	return false
end

function WallJump.getNearbyWall(character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	local hit = findNearbyWall(root)
	return hit and hit.Instance or nil
end

function WallJump.tryJump(character, resetMomentum)
	local now = os.clock()
	if now - lastJumpTick < Config.WallJumpCooldownSeconds then
		return false
	end

	local rootPart, humanoid = getCharacterParts(character)
	if not rootPart or not humanoid then
		return false
	end

	local hit = findNearbyWall(rootPart)
	if not hit then
		return false
	end
	-- Allow repeated wall jumps on the same wall: remove last-wall restriction

	lastJumpTick = now

	-- If wall slide is active, require animation to be ready before allowing jump
	local slideData = activeWallSlides[character]
	if slideData then
		if slideData.animReady ~= true then
			return false
		end
		-- Stop wall slide first so our Jumping state is not overridden
		stopWallSlide(character)
	else
		-- If slide is eligible right now, start it instantly and block this jump so pose can snap first
		local canSlideNow = shouldActivateWallSlide(character)
		if canSlideNow then
			local maybeHit = findNearbyWallForSlide(rootPart)
			if maybeHit then
				startWallSlide(character, maybeHit)
				return false
			end
		end
	end

	-- Per-wall multipliers (optional): read up to a few ancestors
	local function getAttrNum(inst, name)
		local cur = inst
		for _ = 1, 5 do
			if not cur then
				break
			end
			if typeof(cur.GetAttribute) == "function" then
				local v = cur:GetAttribute(name)
				if type(v) == "number" then
					return v
				end
			end
			cur = cur.Parent
		end
		return nil
	end
	local upMul = getAttrNum(hit.Instance, "WallJumpUpMultiplier") or 1
	local awayMul = getAttrNum(hit.Instance, "WallJumpAwayMultiplier") or 1

	-- Calculate away direction more robustly
	-- Ensure we always push away from the wall by using the vector from wall to player
	local wallToPlayer = (rootPart.Position - hit.Position).Unit
	local wallNormal = hit.Normal.Unit

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

	local away = awayDirection * ((Config.WallJumpImpulseAway or 120) * awayMul)
	local up = Vector3.new(0, (Config.WallJumpImpulseUp or 45) * upMul, 0)

	-- Force a clean eject: ignore prior velocity so camera/facing or slide residue cannot reduce jump power
	-- If resetMomentum is true, completely reset all velocity before applying wall jump impulse
	if resetMomentum then
		-- Completely reset all velocity to zero for a microsecond before applying wall jump
		rootPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		-- Apply wall jump impulse immediately after reset
		rootPart.AssemblyLinearVelocity = away + up
	else
		-- Normal behavior: just set the velocity directly
		rootPart.AssemblyLinearVelocity = away + up
	end

	-- Reorient the character to face away from the wall so movement inputs reinforce the jump direction
	local oldAuto = humanoid.AutoRotate
	humanoid.AutoRotate = false
	local awayHoriz = Vector3.new(away.X, 0, away.Z)
	if awayHoriz.Magnitude < 0.01 then
		-- Use the calculated away direction for consistent orientation
		awayHoriz = Vector3.new(awayDirection.X, 0, awayDirection.Z)
	end

	-- Check if this walljump is coming from wallslide (not wallrun)
	local isFromWallSlide = slideData ~= nil
	local isFromWallRun = false -- WallRun.tryHop is called separately, not through WallJump.tryJump

	if awayHoriz.Magnitude > 0 then
		if isFromWallSlide then
			-- For walljump from wallslide: orient to face the direction of the jump (away from wall)
			-- Character was looking at wall, now look in jump direction
			rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + awayHoriz.Unit, Vector3.yAxis)
		elseif not isFromWallRun then
			-- For walljump from VerticalClimb or other sources: orient to face the direction of the jump
			-- Character was looking at wall, now look in jump direction
			rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + awayHoriz.Unit, Vector3.yAxis)
		else
			-- For walljump from wallrun: use normal orientation (facing away from wall)
			rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + awayHoriz.Unit, Vector3.yAxis)
		end
	else
		-- Fallback: if awayHoriz is too small, use the calculated awayDirection
		if not isFromWallRun then
			-- For VerticalClimb/WallSlide: face jump direction (away from wall)
			rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + awayDirection, Vector3.yAxis)
			print("Fallback: Using awayDirection to face jump direction")
		else
			-- For WallRun: face away from wall
			rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + awayDirection, Vector3.yAxis)
			print("Fallback: Using awayDirection for WallRun")
		end
	end
	local lockSecs = Config.WallRunLockAfterWallJumpSeconds or 0.35
	task.delay(math.max(0.18, lockSecs), function()
		if humanoid and humanoid.Parent then
			humanoid.AutoRotate = oldAuto
		end
	end)

	humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	-- Do not track last wall so subsequent jumps on the same wall are permitted

	-- Prevent immediate re-entering wall slide after jumping
	slideCooldownUntil[character] = os.clock() + ((Config.WallJumpCooldownSeconds or 0.2) + 0.2)

	return true
end

-- Wallslide toggle functions
function WallJump.toggleWallslide(character)
	if not character then
		return false
	end

	-- Only allow toggle if currently wallsliding
	if not activeWallSlides[character] then
		return false
	end

	-- Disable wallslide until touching ground
	wallslideDisabled[character] = true
	stopWallSlide(character)

	-- Don't apply cooldown when manually disabled - we want immediate reactivation when appropriate
	slideCooldownUntil[character] = nil
	return true
end

function WallJump.isWallslideDisabled(character)
	return wallslideDisabled[character] == true
end

function WallJump.tryManualReactivate(character)
	if not character then
		return false
	end

	-- Only allow if wallslide is currently disabled
	if not wallslideDisabled[character] then
		return false
	end

	-- Check if near a wall while airborne
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return false
	end

	-- Must be airborne
	local isAirborne = humanoid.FloorMaterial == Enum.Material.Air
	if not isAirborne then
		return false
	end

	-- Check if near a wall suitable for wallslide
	local hit = findNearbyWallForSlide(root)
	if hit then
		wallslideDisabled[character] = nil
		-- Clear any existing cooldown to allow immediate wallslide
		slideCooldownUntil[character] = nil
		return true
	end

	return false
end

-- Auto re-enable when doing any parkour action
function WallJump.updateWallslideState(character)
	if not character then
		return
	end

	-- Skip if wallslide is not disabled
	if not wallslideDisabled[character] then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local shouldReactivate = false
	local reason = ""

	-- 1. Touching ground
	local isGrounded = humanoid.FloorMaterial ~= Enum.Material.Air
	if isGrounded then
		shouldReactivate = true
		reason = "touched ground"
	end

	-- 2. WallRun active
	local WallRun = require(script.Parent.WallRun)
	if WallRun.isActive(character) then
		shouldReactivate = true
		reason = "started wallrun"
	end

	-- 3. Climbing active
	local Climb = require(script.Parent.Climb)
	if Climb.isActive(character) then
		shouldReactivate = true
		reason = "started climbing"
	end

	-- 4. LedgeHang active
	local LedgeHang = require(script.Parent.LedgeHang)
	if LedgeHang.isActive(character) then
		shouldReactivate = true
		reason = "started ledgehang"
	end

	-- 5. Zipline active
	local Zipline = require(script.Parent.Zipline)
	if Zipline.isActive(character) then
		shouldReactivate = true
		reason = "started zipline"
	end

	-- 6. Grapple active
	local Grapple = require(script.Parent.Grapple)
	if Grapple.isActive(character) then
		shouldReactivate = true
		reason = "started grapple"
	end

	-- 7. Jumping (any jump including walljump)
	local humanoidState = humanoid:GetState()
	if humanoidState == Enum.HumanoidStateType.Jumping then
		shouldReactivate = true
		reason = "jumped"
	end

	-- 8. Check for Mantling or Vaulting via ClientState
	pcall(function()
		local rs = game:GetService("ReplicatedStorage")
		local cs = rs:FindFirstChild("ClientState")
		if cs then
			local isMantling = cs:FindFirstChild("IsMantling")
			local isVaulting = cs:FindFirstChild("IsVaulting")
			local isSliding = cs:FindFirstChild("IsSliding")

			if isMantling and isMantling.Value then
				shouldReactivate = true
				reason = "started mantling"
			elseif isVaulting and isVaulting.Value then
				shouldReactivate = true
				reason = "started vaulting"
			elseif isSliding and isSliding.Value then
				shouldReactivate = true
				reason = "started sliding"
			end
		end
	end)

	-- Reactivate wallslide
	if shouldReactivate then
		wallslideDisabled[character] = nil
		-- Clear any existing cooldown to allow immediate wallslide
		slideCooldownUntil[character] = nil
	end
end

return WallJump
