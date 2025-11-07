-- Grapple/Hook system: raycast to target and attach a rope; allows pulling and swinging

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage.Movement.Config)
local Animations = require(ReplicatedStorage.Movement.Animations)

local Grapple = {}

local characterState = {}
local partCooldownUntil = {} -- strong refs to avoid GC clearing cooldowns
local findAutoTarget -- forward declaration

local function logDebug(...)
	if Config.DebugHookCooldownLogs then
		print("[HookCD]", ...)
	end
end

local function isPlayerDescendant(instance)
	while instance do
		if instance:IsA("Model") and instance:FindFirstChildOfClass("Humanoid") then
			return game:GetService("Players"):GetPlayerFromCharacter(instance) ~= nil
		end
		instance = instance.Parent
	end
	return false
end

local function stopHookAnimation(character)
	local st = characterState[character]
	if st and st.animTrack then
		if st.animTrack.IsPlaying then
			st.animTrack:Stop()
		end
		st.animTrack = nil
	end
end

local function ensureRootAttachment(character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	local a = root:FindFirstChild("GrappleA")
	if not a then
		a = Instance.new("Attachment")
		a.Name = "GrappleA"
		a.Position = Vector3.new(0, 0.5, -0.2)
		a.Parent = root
	end
	return a
end

local function createAnchorAt(position)
	local p = Instance.new("Part")
	p.Name = "GrappleAnchor"
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Position = position
	p.Parent = workspace
	local attach = Instance.new("Attachment")
	attach.Name = "GrappleB"
	attach.Parent = p
	return p, attach
end

local function cleanup(char)
	local st = characterState[char]
	if not st then
		return
	end

	-- Prevent multiple cleanup calls for the same character
	if st.isCleaningUp then
		return
	end
	st.isCleaningUp = true

	-- Stop current animation if still playing
	if st.animTrack and st.animTrack.IsPlaying then
		st.animTrack:Stop()
	end
	st.animTrack = nil

	-- Clean up rope and force
	if st.rope then
		st.rope:Destroy()
	end
	if st.anchor and st.anchor.Parent == workspace then
		st.anchor:Destroy()
	end
	if st.force then
		st.force:Destroy()
	end

	characterState[char] = nil
end

local function setPartCooldown(part, duration)
	if not (part and duration and duration > 0) then
		return
	end
	local untilTime = time() + duration
	partCooldownUntil[part] = untilTime
	logDebug("Set cooldown", part:GetFullName(), string.format("%.2fs", duration), "until", untilTime)
	-- Cleanup when part is removed
	task.spawn(function()
		part.AncestryChanged:Wait()
		if not part:IsDescendantOf(workspace) then
			partCooldownUntil[part] = nil
		end
	end)
end

-- This function is now handled by the new Grapple.stop() implementation above

function Grapple.isActive(character)
	local st = characterState[character]
	return st ~= nil and not st.isExiting
end

-- Returns remaining cooldown seconds for the currently targeted (visible) hookable part (> 0 when on cooldown), or 0 if ready
function Grapple.getCooldownRemaining(character)
	if not character then
		return 0
	end
	local st = characterState[character]
	local targetPart
	if st and st.targetPart then
		targetPart = st.targetPart
	else
		local _, candidatePart = findAutoTarget(character)
		targetPart = candidatePart
	end
	if not targetPart then
		return 0
	end
	local untilTime = partCooldownUntil[targetPart]
	if not untilTime then
		return 0
	end
	local remaining = untilTime - time()
	return remaining > 0 and remaining or 0
end

-- Returns remaining cooldown seconds for a specific Hookable part, or 0 if ready/not tracked
function Grapple.getPartCooldownRemaining(part)
	if not part then
		return 0
	end
	local untilTime = partCooldownUntil[part]
	if not untilTime then
		return 0
	end
	local remaining = untilTime - time()
	return remaining > 0 and remaining or 0
end

local function validHit(hit)
	if not hit or not hit.Instance then
		return false
	end
	local inst = hit.Instance
	if isPlayerDescendant(inst) then
		return false
	end
	if CollectionService:HasTag(inst, "NoGrapple") then
		return false
	end
	if
		CollectionService:HasTag(inst, (Config.HookTag or "Hookable"))
		or CollectionService:HasTag(inst, "GrapplePoint")
	then
		return true
	end
	return inst:IsA("BasePart") and (inst.CanCollide or inst.CanQuery)
end

local function findTaggedAncestor(inst, tag)
	local current = inst
	while current do
		if current:IsA("BasePart") and CollectionService:HasTag(current, tag) then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function buildRaycastParamsForLOS(character)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	local ignore = { character }
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Character and plr.Character ~= character then
			table.insert(ignore, plr.Character)
		end
	end
	local ignoreTag = Config.HookIgnoreTag or "HookIgnoreLOS"
	for _, inst in ipairs(CollectionService:GetTagged(ignoreTag)) do
		table.insert(ignore, inst)
	end
	params.FilterDescendantsInstances = ignore
	return params
end

local function hasClearLineOfSight(character, fromPos, targetPart)
	if not (character and fromPos and targetPart and targetPart:IsDescendantOf(workspace)) then
		return false
	end
	local dir = targetPart.Position - fromPos
	if dir.Magnitude < 0.1 then
		return true
	end
	local params = buildRaycastParamsForLOS(character)
	local hit = workspace:Raycast(fromPos, dir, params)
	if not hit then
		return true
	end
	-- Clear if we hit the target part (or its ancestors)
	local h = hit.Instance
	while h do
		if h == targetPart then
			return true
		end
		h = h.Parent
	end
	return false
end

function findAutoTarget(character)
	local player = Players.LocalPlayer
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil, nil, nil
	end
	local tag = Config.HookTag or "Hookable"
	local candidate, candDist -- nearest visible ignoring cooldown (for UI)
	local ready, readyDist -- nearest visible that is not on cooldown (usable)
	for _, inst in ipairs(CollectionService:GetTagged(tag)) do
		if inst and inst:IsA("BasePart") and inst:IsDescendantOf(workspace) then
			-- Read HookRange attribute from each individual hookable part
			local range = (inst and tonumber(inst:GetAttribute("HookRange"))) or (Config.HookDefaultRange or 90)
			local d = (inst.Position - root.Position).Magnitude
			if d <= range then
				local requireLOS = (Config.HookRequireLineOfSight ~= false)
				local losOk = (not requireLOS) or hasClearLineOfSight(character, root.Position, inst)
				if losOk then
					if not candDist or d < candDist then
						candidate, candDist = inst, d
					end
					local untilTime = partCooldownUntil[inst]
					local now = time()
					local cdOk = (not untilTime) or (now >= untilTime)
					if untilTime and now < untilTime then
						logDebug(
							"Target cooldown active",
							inst:GetFullName(),
							string.format("remaining=%.2fs", untilTime - now)
						)
					end
					if cdOk then
						if not readyDist or d < readyDist then
							ready, readyDist = inst, d
						end
					end
				end
			end
		end
	end
	if player and player.PlayerGui then
		local ui = player.PlayerGui:FindFirstChild("HookUI")
		if ui then
			ui.Enabled = candidate ~= nil
		end
	end
	if candidate then
		return CFrame.lookAt(root.Position, candidate.Position), candidate, ready
	end
	return nil, nil, nil
end

function Grapple.tryFire(character, cameraCFrame)
	if not (Config.GrappleEnabled ~= false) then
		return false
	end
	if Grapple.isActive(character) then
		return false
	end
	
	-- Stop flying if active before using hook
	local Fly = require(ReplicatedStorage.Movement.Fly)
	if Fly and Fly.isActive and Fly.isActive(character) then
		Fly.stop(character)
	end
	
	-- CRITICAL: If player is currently climbing, stop the climb state immediately
	-- This ensures clean transition from climb to hook without conflicts
	if Config.ClimbMantleIntegrationEnabled then
		local Climb = require(game:GetService("ReplicatedStorage").Movement.Climb)
		if Climb and Climb.isActive and Climb.isActive(character) then
			if Config.DebugClimb then
				print("[Hook] Stopping climb state before hook execution")
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
									if Config.DebugClimb then
										print("[Hook] Stopped climb animation:", animId)
									end
								end
							end
						end

						-- Force stop all animations if no specific ones were found
						if stoppedCount == 0 then
							for _, track in pairs(animator:GetPlayingAnimationTracks()) do
								track:Stop(0.05)
								if Config.DebugClimb then
									print(
										"[Hook] Force stopped animation:",
										track.Animation and track.Animation.Name or "Unknown"
									)
								end
							end
						end

						if Config.DebugClimb then
							print("[Hook] Animation cleanup completed - stopped", stoppedCount, "animations")
						end
					end
				end
			end)
		end
	end
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	local params = buildRaycastParamsForLOS(character)
	local maxDist = Config.GrappleMaxDistance or 120
	-- Use the currently visible candidate; block if it has cooldown
	local autoCam, candidatePart = findAutoTarget(character)
	if not (autoCam and candidatePart) then
		return false
	end
	if Grapple.getPartCooldownRemaining(candidatePart) > 0 then
		return false
	end

	-- Log successful hook execution
	if Config.DebugHookCooldownLogs then
		print("[Hook] Starting hook execution for character:", character.Name, "target:", candidatePart:GetFullName())
	end

	-- Since we already found a valid candidate in range, use it directly
	-- No need for additional raycast - just use the candidate's position
	local attachA = ensureRootAttachment(character)
	if not attachA then
		return false
	end

	-- Use the candidate part's position directly for the anchor
	local anchor, attachB = createAnchorAt(candidatePart.Position)
	local rope = Instance.new("RopeConstraint")
	rope.Attachment0 = attachA
	rope.Attachment1 = attachB
	rope.Visible = Config.GrappleRopeVisible or false
	rope.Restitution = 0
	rope.WinchEnabled = false
	rope.Visible = Config.GrappleRopeVisible or false
	rope.Length = (attachA.WorldPosition - attachB.WorldPosition).Magnitude
	rope.Thickness = Config.GrappleRopeThickness or 0.06
	rope.Parent = anchor
	local force = Instance.new("VectorForce")
	force.Force = Vector3.new()
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.Attachment0 = attachA
	force.Parent = attachA
	local maxApproachSpeed = (candidatePart and tonumber(candidatePart:GetAttribute("HookMaxApproachSpeed")))
	if not maxApproachSpeed or maxApproachSpeed <= 0 then
		maxApproachSpeed = Config.HookMaxApproachSpeed or 120
	end
	local autoDetachDistance = (candidatePart and tonumber(candidatePart:GetAttribute("HookAutoDetachDistance")))
	if not autoDetachDistance or autoDetachDistance <= 0 then
		autoDetachDistance = Config.HookAutoDetachDistance or 10
	end
	-- Start hook animation using the new global function
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChild("Animator")
	if animator then
		local animTrack, errorMsg =
			Animations.playWithDuration(animator, "HookStart", Config.HookStartDurationSeconds or 1.0, {
				debug = false,
				onComplete = function(actualDuration, expectedDuration)
					-- Debug logging (disabled for production)
					-- print(
					-- 	"[Hook] HookStart - Animation completed in",
					-- 	actualDuration,
					-- 	"seconds (expected:",
					-- 	expectedDuration,
					-- 	"seconds)"
					-- )
				end,
			})

		if animTrack then
			-- Store animation track for cleanup
			characterState[character] = {
				anchor = anchor,
				rope = rope,
				force = force,
				reel = 0,
				targetPart = candidatePart,
				maxApproachSpeed = maxApproachSpeed,
				autoDetachDistance = autoDetachDistance,
				animTrack = animTrack,
				startAnimationPlayed = true, -- Mark start animation as played
			}
		else
			print("[Hook] HookStart - ERROR:", errorMsg)
			-- Store state without animation track
			characterState[character] = {
				anchor = anchor,
				rope = rope,
				force = force,
				reel = 0,
				targetPart = candidatePart,
				maxApproachSpeed = maxApproachSpeed,
				autoDetachDistance = autoDetachDistance,
				startAnimationPlayed = true, -- Mark start animation as played
			}
		end
	else
		characterState[character] = {
			anchor = anchor,
			rope = rope,
			force = force,
			reel = 0,
			targetPart = candidatePart,
			maxApproachSpeed = maxApproachSpeed,
			autoDetachDistance = autoDetachDistance,
			startAnimationPlayed = true, -- Mark start animation as played
		}
	end
	local player = Players.LocalPlayer
	if player and player.PlayerGui then
		local ui = player.PlayerGui:FindFirstChild("HookUI")
		if ui then
			ui.Enabled = true
		end
	end

	return true
end

function Grapple.update(character, dt)
	local st = characterState[character]
	if not st then
		findAutoTarget(character)
		return
	end

	-- If we're in exit state, don't process movement
	if st.isExiting then
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not (root and hum and st.rope and st.anchor) then
		-- Prevent multiple cleanup calls
		if not st.isCleaningUp then
			cleanup(character)
		end
		return
	end

	-- Handle animation transitions

	-- Handle hook animation transitions
	if st.animTrack and st.animTrack.IsPlaying then
		-- Check if HookStart animation has finished (non-looped animation)
		if not st.animTrack.Looped and st.animTrack.TimePosition >= st.animTrack.Length - 0.1 then
			-- HookStart animation finished, start HookLoop
			st.animTrack:Stop()
			st.animTrack = nil

			-- Use the new global animation function for HookLoop
			local loopTrack, errorMsg = Animations.playWithDuration(
				hum:FindFirstChild("Animator"),
				"HookLoop",
				1.0, -- No duration control needed for loop
				{
					looped = true,
					debug = false, -- No debug needed for loop
				}
			)

			if loopTrack then
				st.animTrack = loopTrack
			elseif errorMsg then
				-- Only show error if it's a real error, not just unconfigured animation
				print("[Hook] HookLoop - ERROR:", errorMsg)
			else
				-- Animation not configured, fallback to Roblox defaults (no error)
				-- Debug logging (disabled for production)
				-- print("[Hook] HookLoop - No loop animation configured, using Roblox defaults")
			end
		end
	end
	local pullStrength = Config.GrapplePullForce or 6000
	local reelSpeed = Config.GrappleReelSpeed or 28
	local desiredLen = (st.force.Attachment0.WorldPosition - st.anchor.Position).Magnitude
	if st.reel ~= 0 then
		desiredLen = math.max(2, desiredLen + (st.reel * reelSpeed * -dt))
	end
	st.rope.Length = math.max(0.5, desiredLen - 0.05)
	local toAnchor = (st.anchor.Position - root.Position)
	local dist = toAnchor.Magnitude
	local autoDetachDistance = (st.autoDetachDistance or Config.HookAutoDetachDistance or 10)
	if dist <= autoDetachDistance then
		-- Prevent multiple stop calls
		if not st.isStopping then
			st.isStopping = true
			Grapple.stop(character)
		end
		return
	end
	local dir = toAnchor.Unit
	local currentVel = root.AssemblyLinearVelocity
	local speedAlong = dir:Dot(currentVel)
	local maxApproachSpeed = (st.maxApproachSpeed or Config.HookMaxApproachSpeed or 120)
	if speedAlong >= maxApproachSpeed then
		st.force.Force = Vector3.new()
	else
		st.force.Force = dir * pullStrength
	end
end

function Grapple.setReel(character, direction)
	local st = characterState[character]
	if not st then
		return
	end
	st.reel = direction -- -1 reel in, +1 reel out, 0 none
end

-- Stop hook and play finish animation after rope detaches
function Grapple.stop(character)
	local st = characterState[character]
	if not st then
		return
	end

	-- Check if we're already in exit state
	if st.isExiting then
		return
	end

	-- Mark as exiting to prevent multiple calls
	st.isExiting = true
	-- Debug logging (disabled for production)
	-- print("[Hook] Starting exit sequence for character")

	-- Immediately detach the rope (maintain original logic)
	if st.rope then
		st.rope:Destroy()
		st.rope = nil
	end
	if st.force then
		st.force:Destroy()
		st.force = nil
	end

	-- Handle UI and cooldown logic immediately
	local player = Players.LocalPlayer
	if player then
		local ui = player:FindFirstChildOfClass("PlayerGui") and player.PlayerGui:FindFirstChild("HookUI")
		if ui then
			ui.Enabled = false
		end
	end

	-- Part-level cooldown (per hookable), not per character
	if st and st.targetPart and st.targetPart:IsDescendantOf(workspace) then
		local duration = Config.HookCooldownSeconds or 0
		local attr = st.targetPart:GetAttribute("HookCooldownSeconds")
		if typeof(attr) == "number" then
			duration = attr
		end
		setPartCooldown(st.targetPart, duration)
	end

	-- Now play hook finish animation
	local hum = character:FindFirstChildOfClass("Humanoid")
	if hum then
		local animator = hum:FindFirstChild("Animator")
		if animator then
			local finishTrack, errorMsg =
				Animations.playWithDuration(animator, "HookFinish", Config.HookFinishDurationSeconds or 0.5, {
					debug = false,
					onComplete = function(actualDuration, expectedDuration)
						-- Debug logging (disabled for production)
						-- print(
						-- 	"[Hook] HookFinish - Animation completed in",
						-- 	actualDuration,
						-- 	"seconds (expected:",
						-- 	expectedDuration,
						-- 	"seconds)"
						-- )
						-- Animation complete, now cleanup the state
						Grapple.cleanup(character)
					end,
				})

			if not finishTrack then
				if errorMsg then
					print("[Hook] HookFinish - ERROR:", errorMsg)
				else
					print("[Hook] HookFinish - Animation not configured, proceeding with cleanup")
				end
				-- If no finish animation, cleanup immediately
				Grapple.cleanup(character)
			end
		else
			-- No animator, cleanup immediately
			Grapple.cleanup(character)
		end
	else
		-- No humanoid, cleanup immediately
		Grapple.cleanup(character)
	end
end

-- Separate cleanup function that actually removes the hook state
function Grapple.cleanup(character)
	local st = characterState[character]
	if not st then
		return
	end

	-- Stop current animation if still playing
	if st.animTrack and st.animTrack.IsPlaying then
		st.animTrack:Stop()
	end
	st.animTrack = nil

	-- Clear the data (rope and force already destroyed in stop())
	characterState[character] = nil
	-- Debug logging (disabled for production)
	-- print("[Hook] Cleanup completed for character")
end

Players.PlayerRemoving:Connect(function(plr)
	if plr.Character then
		cleanup(plr.Character)
	end
end)

-- Clean up all active hook animations (useful for cleanup)
function Grapple.cleanupAll()
	for character, _ in pairs(characterState) do
		Grapple.cleanup(character)
	end
	characterState = {}
end

return Grapple
