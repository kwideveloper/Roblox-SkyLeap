-- Wall climbing on parts with Attribute 'climbable' == true

local Config = require(game:GetService("ReplicatedStorage").Movement.Config)
local WallMemory = require(game:GetService("ReplicatedStorage").Movement.WallMemory)
local SharedUtils = require(game:GetService("ReplicatedStorage").SharedUtils)
local ParkourSurfaceGate = require(game:GetService("ReplicatedStorage").Movement.ParkourSurfaceGate)
local RunService = game:GetService("RunService")

local Climb = {}

local active = {}
local lastClimbStopAt = {} -- [character] = os.clock() when Climb.stop ran

local function shouldClimbTrace()
	if Config.DebugClimb or Config.ClimbTraceEnabled then
		return true
	end
	if Config.ClimbTraceInStudio == false then
		return false
	end
	return RunService:IsStudio()
end

local function cleanupClimbAnimations(character)
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
						-- Check for various climb-related animation names
						if
							string.find(animId, "Climb")
							or string.find(animId, "climb")
							or string.find(animId, "Climbing")
							or string.find(animId, "climbing")
							or string.find(animId, "Wall")
							or string.find(animId, "wall")
						then
							track:Stop(0.05) -- Stop immediately
							stoppedCount = stoppedCount + 1
							if Config.DebugClimb then
								print("[Climb] Stopped animation:", animId)
							end
						end
					end
				end

				-- Also try to stop any animations by name that might be running
				if stoppedCount == 0 then
					-- Force stop all animations if no specific ones were found
					for _, track in pairs(animator:GetPlayingAnimationTracks()) do
						track:Stop(0.05)
						if Config.DebugClimb then
							print(
								"[Climb] Force stopped animation:",
								track.Animation and track.Animation.Name or "Unknown"
							)
						end
					end
				end

				if Config.DebugClimb then
					print("[Climb] Cleanup completed - stopped", stoppedCount, "animations")
				end
			end
		end
	end)
end

local function getParts(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return root, humanoid
end

local function findClimbable(root)
	local params = SharedUtils.createParkourRaycastParams(root.Parent)

	local directions = {
		root.CFrame.RightVector,
		-root.CFrame.RightVector,
		root.CFrame.LookVector,
		-root.CFrame.LookVector,
	}

	for _, dir in ipairs(directions) do
		local result = workspace:Raycast(root.Position, dir * Config.ClimbDetectionDistance, params)
		if result and result.Instance then
			local CollectionService = game:GetService("CollectionService")
			if CollectionService:HasTag(result.Instance, "Climbable") then
				if ParkourSurfaceGate.isClimbAllowedForTaggedClimbable(result.Instance) then
					return result
				end
			end
		end
	end
	return nil
end

-- Find ground level below the player using raycast
-- World-space highest Y of the part's oriented box (UpVector*size/2 is wrong when wall height is along X or Z)
local function computeClimbedPartTopY(inst)
	if inst and inst:IsA("BasePart") then
		local cf = inst.CFrame
		local s = inst.Size
		local hx, hy, hz = s.X * 0.5, s.Y * 0.5, s.Z * 0.5
		local r = cf.RightVector
		local u = cf.UpVector
		local l = cf.LookVector
		local p = cf.Position
		local extentY = math.abs(u.Y) * hy + math.abs(r.Y) * hx + math.abs(l.Y) * hz
		return p.Y + extentY
	end
	return nil
end

local function isRootNearClimbedWallTop(root, climbedPart)
	if not root or not climbedPart then
		return false
	end
	if Config.ClimbMantleRequireNearClimbedWallTop == false then
		return true
	end
	local wallTopY = computeClimbedPartTopY(climbedPart)
	if not wallTopY then
		return false
	end
	local clearance = wallTopY - root.Position.Y
	local minC = Config.ClimbMantleMinClearanceBelowWallTop or -2
	local maxC = Config.ClimbMantleMaxClearanceBelowWallTop or 3.25
	return clearance >= minC and clearance <= maxC
end

-- Tight lip band + optional match of detector topY to this part's top (blocks false ledges mid-wall)
local function climbFinishLipAllowsHandoff(wallPart, clearanceBelowTop, detectorTopY)
	if not wallPart or clearanceBelowTop == nil then
		return false
	end
	local mn = Config.ClimbFinishMantleClearanceMin or -0.5
	local mx = Config.ClimbFinishMantleClearanceMax or 1.35
	if clearanceBelowTop < mn or clearanceBelowTop > mx then
		return false
	end
	if detectorTopY ~= nil then
		local wTop = computeClimbedPartTopY(wallPart)
		if not wTop then
			return false
		end
		local tol = Config.ClimbFinishMantleTopYTolerance or 1.25
		if math.abs(detectorTopY - wTop) > tol then
			return false
		end
	end
	return true
end

local function findGroundLevel(root)
	local params = SharedUtils.createParkourRaycastParams(root.Parent)

	-- Cast ray downward to find ground
	local raycastDistance = 10 -- Maximum distance to search for ground
	local result = workspace:Raycast(root.Position, Vector3.new(0, -raycastDistance, 0), params)

	if result then
		-- Check if the hit surface is actually ground (horizontal)
		local normal = result.Normal
		local groundNormalThreshold = Config.ClimbGroundNormalThreshold or 0.7
		local isHorizontal = math.abs(normal:Dot(Vector3.yAxis)) > groundNormalThreshold

		if isHorizontal then
			return result.Position.Y
		end
	end

	return nil
end

function Climb.tryStart(character)
	if active[character] then
		return false
	end
	local root, humanoid = getParts(character)
	if not root or not humanoid then
		return false
	end

	-- Check if player is on ground and wants to climb
	local isOnGround = humanoid.FloorMaterial ~= Enum.Material.Air

	if isOnGround then
		local hit = findClimbable(root)
		if hit then
			local shouldAutoAdjust = false

			if Config.ClimbAutoGroundAdjustAlways then
				-- Always auto-adjust when on ground, regardless of distance
				shouldAutoAdjust = true
				if Config.DebugClimb then
					print("[Climb] Auto-adjust always enabled when on ground")
				end
			else
				-- Only auto-adjust when very close to wall (original behavior)
				local toWall = (hit.Position - root.Position)
				local toWallHoriz = Vector3.new(toWall.X, 0, toWall.Z)
				local distanceToWall = toWallHoriz.Magnitude
				local minWallDistance = Config.ClimbMinGroundDistance or 2.0

				shouldAutoAdjust = distanceToWall < minWallDistance

				if Config.DebugClimb then
					print(
						"[Climb] Distance-based auto-adjust - distance:",
						distanceToWall,
						"threshold:",
						minWallDistance,
						"will adjust:",
						shouldAutoAdjust
					)
				end
			end

			-- Execute auto-adjustment if enabled
			if shouldAutoAdjust and Config.ClimbAutoGroundAdjust then
				-- Simple approach: just add 2.5 studs to Y position
				local currentHeight = root.Position.Y
				local targetHeight = currentHeight + (Config.ClimbAutoGroundAdjustHeight or 2.5)

				if Config.DebugClimb then
					print(
						"[Climb] Auto-adjusting position - current height:",
						currentHeight,
						"target height:",
						targetHeight,
						"adjustment: +2.5 studs"
					)
				end

				-- Move player up by 2.5 studs
				local newPosition = Vector3.new(root.Position.X, targetHeight, root.Position.Z)
				root.CFrame = CFrame.new(newPosition)

				-- Force update the position to ensure it sticks
				root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)

				if Config.DebugClimb then
					print("[Climb] Position updated to:", newPosition)
				end
			end
		else
			-- No climbable surface found
			if Config.DebugClimb then
				print("[Climb] No climbable surface found when on ground")
			end
			return false
		end
	end

	local hit = findClimbable(root)
	if not hit then
		return false
	end

	-- Store previous state for proper restoration
	local prevState = humanoid:GetState()
	local prevWalkSpeed = humanoid.WalkSpeed
	local prevJumpPower = humanoid.JumpPower
	local prevAutoRotate = humanoid.AutoRotate

	humanoid:ChangeState(Enum.HumanoidStateType.RunningNoPhysics)
	humanoid.AutoRotate = false
	active[character] = {
		normal = hit.Normal,
		instance = hit.Instance,
		antiGravity = nil,
		attachment = nil,
		prevState = prevState,
		prevWalkSpeed = prevWalkSpeed,
		prevJumpPower = prevJumpPower,
		prevAutoRotate = prevAutoRotate,
	}
	-- Freeze in place until input provided; prevent gravity drift
	root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	-- Add anti-gravity to eliminate slow vertical drift
	local attach = Instance.new("Attachment")
	attach.Name = "ClimbAttach"
	attach.Parent = root
	local vf = Instance.new("VectorForce")
	vf.Name = "ClimbAntiGravity"
	vf.Attachment0 = attach
	vf.RelativeTo = Enum.ActuatorRelativeTo.World
	vf.Force = Vector3.new(0, root.AssemblyMass * workspace.Gravity, 0)
	vf.Parent = root
	active[character].attachment = attach
	active[character].antiGravity = vf

	-- No need for complex auto-adjust flags with simple approach

	if Config.DebugClimb then
		print("[Climb] tryStart on", tostring(hit.Instance), "normal", hit.Normal, "from ground:", isOnGround)
	end
	if shouldClimbTrace() then
		local topY = computeClimbedPartTopY(hit.Instance)
		print(
			string.format(
				"[Climb:trace] START wall=%s topY(worldAABB)=%s normal=%s",
				hit.Instance:GetFullName(),
				topY and string.format("%.2f", topY) or "nil",
				tostring(hit.Normal)
			)
		)
	end
	return true
end

function Climb.getTimeSinceLastClimbStop(character)
	if not character then
		return math.huge
	end
	local t = lastClimbStopAt[character]
	if not t then
		return math.huge
	end
	return os.clock() - t
end

function Climb.stop(character)
	local data = active[character]
	if not data then
		return
	end
	lastClimbStopAt[character] = os.clock()
	local root, humanoid = getParts(character)
	if humanoid then
		-- Restore all previous states properly
		humanoid.AutoRotate = data.prevAutoRotate or true
		humanoid.WalkSpeed = data.prevWalkSpeed or 16
		humanoid.JumpPower = data.prevJumpPower or 50

		-- Force restore normal physics state
		humanoid:ChangeState(Enum.HumanoidStateType.Running)

		-- Ensure physics are properly enabled
		if root then
			root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
			-- Small delay to ensure state change is processed
			task.spawn(function()
				task.wait(0.1)
				if humanoid and humanoid.Parent then
					-- Force a physics update
					humanoid:ChangeState(Enum.HumanoidStateType.Running)
					if Config.DebugClimb then
						print("[Climb] Physics state restored for character:", character.Name)
					end
				end
			end)
		end
	end

	-- Clean up physics objects
	if data and data.antiGravity then
		data.antiGravity:Destroy()
	end
	if data and data.attachment then
		data.attachment:Destroy()
	end

	-- Clean up any climb animations
	cleanupClimbAnimations(character)

	-- Clear the data reference AFTER cleanup
	active[character] = nil

	if Config.DebugClimb then
		print("[Climb] stop - all states restored")
	end
end

function Climb.isActive(character)
	return active[character] ~= nil
end

function Climb.isNearClimbable(character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	local hit = findClimbable(root)
	return hit ~= nil
end

function Climb.maintain(character, input)
	local data = active[character]
	if not data then
		return false
	end
	local root, humanoid = getParts(character)
	if not root or not humanoid then
		Climb.stop(character)
		return false
	end

	-- Recheck the wall and stick to it
	local hit = findClimbable(root)
	if not hit or hit.Instance ~= data.instance then
		Climb.stop(character)
		return false
	end
	data.normal = hit.Normal

	-- Check if player is too close to ground level
	local isTooCloseToGround = false
	if Config.ClimbGroundProximityCheck then
		-- Only check ground proximity when moving downward or if explicitly enabled
		local shouldCheckGround = true
		local inputV = 0
		if typeof(input) == "table" then
			inputV = input.v or 0
		end

		if Config.ClimbAlwaysCheckGround then
			shouldCheckGround = true -- Always check ground proximity
		elseif
			Config.ClimbGroundCheckOnlyWhenDescending
			and not Config.ClimbForceGroundDetection
			and not Config.ClimbGroundDetectionAggressive
		then
			shouldCheckGround = inputV < 0 -- Only check when moving down
		end

		if Config.DebugClimb then
			print(
				"[Climb] Ground check - shouldCheck:",
				shouldCheckGround,
				"inputV:",
				inputV,
				"forceDetection:",
				Config.ClimbForceGroundDetection
			)
		end

		if shouldCheckGround then
			pcall(function()
				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				params.FilterDescendantsInstances = { root.Parent }
				params.IgnoreWater = true

				-- Use a more intelligent ground detection that considers the climbing context
				local raycastDistance = Config.ClimbGroundDetectionRaycastDistance or 5.0

				-- Cast ray from the feet position, not the center of the character
				local feetPosition
				if Config.ClimbUseHumanoidHipHeight and humanoid then
					-- Use Humanoid's HipHeight for more accurate feet position
					feetPosition = root.Position - Vector3.new(0, humanoid.HipHeight, 0)
				else
					-- Fallback to size-based calculation
					local feetOffsetMultiplier = Config.ClimbFeetOffsetMultiplier or 0.5
					feetPosition = root.Position - Vector3.new(0, root.Size.Y * feetOffsetMultiplier, 0)
				end
				local groundCheck = workspace:Raycast(feetPosition, Vector3.new(0, -raycastDistance, 0), params)
				if groundCheck then
					-- Calculate distance from feet to ground, not from center to ground
					local feetPosition
					if Config.ClimbUseHumanoidHipHeight and humanoid then
						-- Use Humanoid's HipHeight for more accurate feet position
						feetPosition = root.Position - Vector3.new(0, humanoid.HipHeight, 0)
					else
						-- Fallback to size-based calculation
						local feetOffsetMultiplier = Config.ClimbFeetOffsetMultiplier or 0.5
						feetPosition = root.Position - Vector3.new(0, root.Size.Y * feetOffsetMultiplier, 0)
					end
					local distanceToGround = feetPosition.Y - groundCheck.Position.Y
					local minGroundDistance = Config.ClimbMinGroundDistance or 2.0

					if Config.DebugClimb then
						print(
							"[Climb] Ground detection - center pos:",
							root.Position.Y,
							"feet pos:",
							feetPosition.Y,
							"ground pos:",
							groundCheck.Position.Y,
							"distance from feet:",
							distanceToGround,
							"surface:",
							groundCheck.Instance.Name
						)
					end

					-- Additional validation: check if we're actually hitting the real ground
					-- and not just a wall or obstacle below us
					local isRealGround = false
					if groundCheck.Instance then
						-- Check if the hit surface is actually ground-like
						local normal = groundCheck.Normal
						local groundNormalThreshold = Config.ClimbGroundNormalThreshold or 0.7
						local isHorizontal = math.abs(normal:Dot(Vector3.yAxis)) > groundNormalThreshold

						-- Also check if we're not hitting the same wall we're climbing
						local excludeClimbingWall = Config.ClimbGroundExcludeClimbingWall ~= false
						local isNotClimbingWall = true
						if excludeClimbingWall then
							isNotClimbingWall = groundCheck.Instance ~= data.instance
						end

						isRealGround = isHorizontal and isNotClimbingWall

						if Config.DebugClimb then
							print(
								"[Climb] Ground validation - isHorizontal:",
								isHorizontal,
								"isNotClimbingWall:",
								isNotClimbingWall,
								"isRealGround:",
								isRealGround
							)
						end
					end

					-- Only consider it "too close to ground" if it's actually ground and we're close
					if distanceToGround < minGroundDistance and isRealGround then
						isTooCloseToGround = true

						-- Check if we should auto-disable climb when too close to ground
						if Config.ClimbAutoDisableAtGround then
							local autoDisableThreshold = Config.ClimbAutoDisableGroundThreshold or 3.5
							local onlyWhenDescending = Config.ClimbAutoDisableOnlyWhenDescending

							if Config.DebugClimb then
								print(
									"[Climb] Auto-disable check - distance:",
									distanceToGround,
									distanceToGround < autoDisableThreshold and "BELOW" or "ABOVE",
									"threshold:",
									autoDisableThreshold,
									"onlyWhenDescending:",
									onlyWhenDescending,
									"inputV:",
									inputV,
									"willAutoDisable:",
									distanceToGround < autoDisableThreshold and (not onlyWhenDescending or inputV < 0)
								)
							end

							-- Auto-disable if we're below threshold and either always or only when descending
							-- But consider if we just auto-adjusted (to prevent immediate deactivation)
							local shouldAutoDisable = distanceToGround < autoDisableThreshold
								and (not onlyWhenDescending or inputV < 0)

							-- If we don't want immediate auto-disable after adjustment, add a small delay
							if not Config.ClimbAutoDisableImmediateAfterAdjust then
								-- Add a small delay to prevent immediate auto-disable after auto-adjustment
								shouldAutoDisable = false
								if Config.DebugClimb then
									print("[Climb] Skipping auto-disable - just auto-adjusted from ground")
								end
							end

							if shouldAutoDisable then
								if Config.DebugClimb then
									print(
										"[Climb] Auto-disabling climb - too close to ground, distance:",
										distanceToGround,
										"threshold:",
										autoDisableThreshold,
										"input v:",
										inputV
									)
								end
								Climb.stop(character)
								return false
							end
						end

						if Config.DebugClimb then
							print(
								"[Climb] Too close to ground, distance:",
								distanceToGround,
								"min required:",
								minGroundDistance,
								"surface:",
								groundCheck.Instance.Name
							)
						end
					elseif Config.DebugClimb and distanceToGround < minGroundDistance then
						-- Log when we're close to something but it's not ground
						print(
							"[Climb] Close to surface but not ground - distance:",
							distanceToGround,
							"surface:",
							groundCheck.Instance.Name,
							"isGround:",
							isRealGround
						)
					end
				end
			end)
		end
	end

	-- Mantle/ledge helpers use rays and box overlap; mid-wall false positives are common (trims, gaps, CanQuery=false obstacles).
	-- Only treat mantle integration as valid when the root is near the real top of the *climbed* part.
	local nearWallTopForMantle = isRootNearClimbedWallTop(root, data.instance)
	if Config.DebugClimb then
		local wt = computeClimbedPartTopY(data.instance)
		if wt then
			print(
				string.format(
					"[Climb] mantleGate part=%s wallTopY=%.3f rootY=%.3f clearance=%.3f nearTop=%s",
					data.instance.Name,
					wt,
					root.Position.Y,
					wt - root.Position.Y,
					tostring(nearWallTopForMantle)
				)
			)
		end
	end

	-- Check if player is very close to a ledge edge during climb
	-- This prevents automatic mantle execution while still allowing manual input
	local isNearLedgeEdge = false
	local shouldLimitMovement = false
	local shouldStopAndMantle = false

	local hEarly, vEarly = 0, 0
	if typeof(input) == "table" then
		hEarly = input.h or 0
		vEarly = input.v or 0
	end

	local wallTopYForFinish = computeClimbedPartTopY(data.instance)
	local clearanceToTop = wallTopYForFinish and (wallTopYForFinish - root.Position.Y) or nil
	local lipOkNoDetector = climbFinishLipAllowsHandoff(data.instance, clearanceToTop, nil)

	-- Ray-based mantle: must also pass lip band + topY match (otherwise false ledges stop climb mid-wall)
	if Config.ClimbMantleIntegrationEnabled and nearWallTopForMantle and Config.ClimbAutoDisableForMantle then
		pcall(function()
			local Abilities = require(game:GetService("ReplicatedStorage").Movement.Abilities)
			if Abilities and Abilities.detectLedgeForMantle then
				local ledgeOk, hitRes, topY = Abilities.detectLedgeForMantle(root)
				if Config.DebugClimb then
					print(
						"[Climb] detectLedgeForMantle ledgeOk=",
						tostring(ledgeOk),
						"hit=",
						hitRes and hitRes.Instance and hitRes.Instance.Name or "nil",
						"topY=",
						topY
					)
				end
				if ledgeOk and topY then
					local toWall = (hitRes.Position - root.Position)
					local toWallHoriz = Vector3.new(toWall.X, 0, toWall.Z)
					local distanceToLedge = toWallHoriz.Magnitude
					local ledgeHeightDiff = topY - root.Position.Y
					local mantleDetectionDistance = Config.MantleDetectionDistance or 4.0
					local mantleMaxAboveWaist = Config.MantleAboveWaistWhileClimbing or 5.0
					local lipAndTopOk = climbFinishLipAllowsHandoff(data.instance, clearanceToTop, topY)
					if
						distanceToLedge <= mantleDetectionDistance
						and ledgeHeightDiff <= mantleMaxAboveWaist
						and lipAndTopOk
					then
						shouldStopAndMantle = true
						if Config.DebugClimb then
							print(
								"[Climb] Auto-disable for mantle (ledge detect + lip) - distance:",
								distanceToLedge,
								"height diff:",
								ledgeHeightDiff,
								"lipOk:",
								lipAndTopOk
							)
						end
					elseif Config.DebugClimb and ledgeOk then
						print(
							"[Climb] Ledge detect ignored (not at climbed part lip / top mismatch) lipAndTopOk=",
							tostring(lipAndTopOk),
							"clearance=",
							clearanceToTop
						)
					end
				end
			end
		end)
	end

	if
		not shouldStopAndMantle
		and Config.ClimbMantleIntegrationEnabled
		and Config.ClimbAutoMantleAtWallTop ~= false
		and nearWallTopForMantle
		and lipOkNoDetector
		and vEarly >= -0.01
	then
		shouldStopAndMantle = true
		if Config.DebugClimb then
			print(
				"[Climb] Auto mantle at Climbable lip | clearance=",
				clearanceToTop,
				"band=[",
				Config.ClimbFinishMantleClearanceMin,
				",",
				Config.ClimbFinishMantleClearanceMax,
				"]"
			)
		end
	end

	if shouldClimbTrace() then
		local now = os.clock()
		data._climbTraceLast = data._climbTraceLast or 0
		local intv = Config.ClimbTraceIntervalSeconds or 0.12
		if now - data._climbTraceLast >= intv then
			data._climbTraceLast = now
			print(
				string.format(
					"[Climb:trace] clear=%.2f lip=%s stopMantle=%s rootY=%.2f wallTop=%.2f v=%.2f nearTopZone=%s wall=%s",
					clearanceToTop or -1,
					tostring(lipOkNoDetector),
					tostring(shouldStopAndMantle),
					root.Position.Y,
					wallTopYForFinish or -1,
					vEarly,
					tostring(nearWallTopForMantle),
					data.instance.Name
				)
			)
		end
	end

	if shouldStopAndMantle then
		local wallPart = data.instance
		local wallNormal = data.normal
		local contactPos = hit.Position
		local topYWorld = computeClimbedPartTopY(wallPart)
		local charRef = character
		if Config.DebugClimb then
			print("[Climb] Stopping climb and invoking climb-finish mantle")
		end
		Climb.stop(character)
		task.defer(function()
			if not charRef.Parent then
				return
			end
			local Abilities = require(game:GetService("ReplicatedStorage").Movement.Abilities)
			if Abilities and Abilities.tryMantle then
				local syntheticHit = {
					Instance = wallPart,
					Position = contactPos,
					Normal = wallNormal,
				}
				local ok = Abilities.tryMantle(charRef, {
					climbFinish = true,
					hitRes = syntheticHit,
					topY = topYWorld,
				})
				if Config.DebugClimb and not ok then
					print("[Climb] climb-finish tryMantle returned false (clearance/gate/cooldown)")
				end
			end
		end)
		return
	end

	-- Then check for ledge edge detection (if enabled)
	if
		Config.ClimbMantleIntegrationEnabled
		and Config.ClimbLedgeEdgeDetectionEnabled
		and not Config.ClimbLedgeEdgeDetectionCompletelyDisabled
		and nearWallTopForMantle
	then
		pcall(function()
			local Abilities = require(game:GetService("ReplicatedStorage").Movement.Abilities)
			if Abilities and Abilities.detectLedgeForMantle then
				local ledgeOk, hitRes, topY = Abilities.detectLedgeForMantle(root)
				if ledgeOk then
					-- Check if the ledge is very close and at appropriate height for mantle
					local toWall = (hitRes.Position - root.Position)
					local toWallHoriz = Vector3.new(toWall.X, 0, toWall.Z)
					local distanceToLedge = toWallHoriz.Magnitude
					local ledgeHeightDiff = topY - root.Position.Y

					-- Use configuration values for edge detection
					local edgeDistance = Config.ClimbLedgeEdgeDetectionDistance or 1.5
					local edgeHeightRange = Config.ClimbLedgeEdgeHeightRange or { 0, 3 }
					local restrictiveDistance = Config.ClimbLedgeEdgeRestrictiveDistance or 0.2
					local movementLimitThreshold = Config.ClimbLedgeEdgeMovementLimitThreshold or 0.3

					-- Mark as near edge if within detection range
					if
						distanceToLedge < edgeDistance
						and ledgeHeightDiff >= edgeHeightRange[1]
						and ledgeHeightDiff <= edgeHeightRange[2]
					then
						isNearLedgeEdge = true

						-- Only limit movement if extremely close (more restrictive)
						if distanceToLedge < movementLimitThreshold then
							shouldLimitMovement = true
						end

						if Config.DebugClimb then
							print(
								"[Climb] Near ledge edge detected - distance:",
								distanceToLedge,
								"height diff:",
								ledgeHeightDiff,
								"detection threshold:",
								edgeDistance,
								"movement limit threshold:",
								movementLimitThreshold,
								"will limit movement:",
								shouldLimitMovement
							)
						end
					end
				end
			end
		end)
	end

	-- Movement axes relative to character orientation but constrained to wall plane
	local n = data.normal
	local right = root.CFrame.RightVector
	right = (right - n * right:Dot(n))
	if right.Magnitude > 0.001 then
		right = right.Unit
	else
		right = (n:Cross(Vector3.yAxis)).Magnitude > 0.01 and n:Cross(Vector3.yAxis).Unit or n:Cross(Vector3.xAxis).Unit
	end

	-- Vertical axis should be world up to ensure W is always upward
	local up = Vector3.yAxis

	local h = 0
	local v = 0
	if typeof(input) == "table" then
		h = input.h or 0
		v = input.v or 0
	end

	-- If too close to ground, limit downward movement
	if isTooCloseToGround and v < 0 then
		local groundMovementLimit = Config.ClimbGroundMovementLimit or 0.2
		v = math.max(v, -groundMovementLimit) -- Allow slight downward movement but not much
		if Config.DebugClimb then
			print("[Climb] Limiting downward movement near ground to:", groundMovementLimit)
		end
	end

	-- If near ledge edge, limit upward movement to prevent automatic mantle
	if shouldLimitMovement and v > 0 then
		local movementLimit = Config.ClimbLedgeEdgeMovementLimit or 0.3
		v = math.min(v, movementLimit) -- Reduce upward movement when near ledge edge
		if Config.DebugClimb then
			print("[Climb] Limiting upward movement near ledge edge to:", movementLimit)
		end
	end

	local desired = (right * h + up * v) * Config.ClimbSpeed
	-- Only apply stick if we are further than a small threshold from the wall
	local stick = Vector3.new(0, 0, 0)
	do
		local offset = (hit.Position - root.Position)
		local dist = offset.Magnitude
		if dist > 1 then
			stick = -n * Config.ClimbStickVelocity
		end
	end

	-- Keep position when no input: if no keys pressed, zero desired movement
	if math.abs(h) < 0.01 and math.abs(v) < 0.01 then
		desired = Vector3.new(0, 0, 0)
	end
	-- Prevent gravity from pulling down by overwriting vertical component when no vertical input
	if math.abs(v) < 0.01 then
		desired = Vector3.new(desired.X, 0, desired.Z)
	end
	local newVel = Vector3.new(desired.X + stick.X, desired.Y + stick.Y, desired.Z + stick.Z)
	root.AssemblyLinearVelocity = newVel
	if Config.DebugClimb then
		print(string.format("[Climb] v=%.2f h=%.2f vel=(%.2f, %.2f, %.2f)", v, h, newVel.X, newVel.Y, newVel.Z))
	end

	-- Orient character to face the wall
	root.CFrame = CFrame.lookAt(root.Position, root.Position - n, Vector3.yAxis)

	-- Drain stamina; if depleted, stop climbing immediately
	if Config.StaminaEnabled == true then
		do
			local folder = game:GetService("ReplicatedStorage"):FindFirstChild("ClientState")
			local staminaValue = folder and folder:FindFirstChild("Stamina")
			if staminaValue then
				-- Approximate dt using Heartbeat delta from RunService if not passed here
				local hb = game:GetService("RunService").Heartbeat:Wait()
				local delta = typeof(hb) == "number" and hb or 0.016
				staminaValue.Value = math.max(0, staminaValue.Value - (Config.ClimbStaminaDrainPerSecond * delta))
				if staminaValue.Value <= 0 then
					Climb.stop(character)
					return false
				end
			end
		end
	end
	return true
end

function Climb.tryHop(character)
	local data = active[character]
	if not data then
		return false
	end
	local root, humanoid = getParts(character)
	if not root or not humanoid then
		return false
	end

	-- Check if we should execute a full walljump or just a simple hop
	if Config.ClimbSpaceExecutesWallJump then
		-- Simulate a Space press after stopping climb to trigger normal walljump
		-- This ensures we use the exact same logic as the normal walljump

		-- First, stop the climb state
		Climb.stop(character)

		-- Then simulate a Space press to trigger walljump
		-- Use a small delay to ensure climb is fully stopped
		task.defer(function()
			-- Simulate Space key press by calling the walljump logic directly
			local WallJump = require(game:GetService("ReplicatedStorage").Movement.WallJump)
			if WallJump and WallJump.tryJump then
				-- Check if we have enough stamina for walljump
				local folder = game:GetService("ReplicatedStorage"):FindFirstChild("ClientState")
				local staminaValue = folder and folder:FindFirstChild("Stamina")
				local staminaCost = Config.ClimbWallJumpStaminaCost or 0
				local stamOn = Config.StaminaEnabled == true
				local hasStamina = not stamOn or staminaCost == 0 or (staminaValue and staminaValue.Value >= staminaCost)

				if hasStamina then
					-- Execute walljump using the normal system
					wait()
					WallJump.tryJump(character)

					-- Consume stamina if configured
					if stamOn and staminaCost > 0 and staminaValue then
						staminaValue.Value = math.max(0, staminaValue.Value - staminaCost)
					end
				end
			end
		end)

		return true
	else
		-- Original simple hop behavior
		local normal = data.normal or root.CFrame.RightVector

		-- Use camera facing projected away from the wall for forward boost
		local camera = workspace.CurrentCamera
		local camForward = camera and camera.CFrame.LookVector or root.CFrame.LookVector
		local projectedForward = camForward - (camForward:Dot(normal)) * normal
		if projectedForward.Magnitude < 0.05 then
			projectedForward = root.CFrame.LookVector - (root.CFrame.LookVector:Dot(normal)) * normal
		end
		projectedForward = projectedForward.Magnitude > 0 and projectedForward.Unit or root.CFrame.LookVector

		-- Compose impulse
		local away = normal * Config.WallJumpImpulseAway
		local forwardBoost = projectedForward * Config.WallHopForwardBoost
		local upBoost = Vector3.new(0, Config.WallJumpImpulseUp * 0.6, 0)

		local vel = root.AssemblyLinearVelocity
		vel = Vector3.new(vel.X, 0, vel.Z)
		root.AssemblyLinearVelocity = vel + away + forwardBoost + upBoost

		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)

		-- Mark this wall so we cannot hop again from the exact same instance mid-air
		if data.instance then
			WallMemory.setLast(character, data.instance)
		end

		-- Stop climb state after executing the hop
		Climb.stop(character)

		return true
	end
end

return Climb
