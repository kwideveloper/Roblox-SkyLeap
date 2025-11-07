-- Client-side parkour controller (module-style to be loaded from StarterCharacterScripts)

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage.Movement.Config)
local Animations = require(ReplicatedStorage.Movement.Animations)
local Momentum = require(ReplicatedStorage.Movement.Momentum)
local Stamina = require(ReplicatedStorage.Movement.Stamina)
local Abilities = require(ReplicatedStorage.Movement.Abilities)
local DashVfx = require(ReplicatedStorage.Movement.DashVfx)
local WallRun = require(ReplicatedStorage.Movement.WallRun)
local WallJump = require(ReplicatedStorage.Movement.WallJump)
local WallMemory = require(ReplicatedStorage.Movement.WallMemory)
local Climb = require(ReplicatedStorage.Movement.Climb)
local Zipline = require(ReplicatedStorage.Movement.Zipline)
local BunnyHop = require(ReplicatedStorage.Movement.BunnyHop)
local AirControl = require(ReplicatedStorage.Movement.AirControl)
local Style = require(ReplicatedStorage.Movement.Style)
local Grapple = require(ReplicatedStorage.Movement.Grapple)
local VerticalClimb = require(ReplicatedStorage.Movement.VerticalClimb)
local LedgeHang = require(ReplicatedStorage.Movement.LedgeHang)
local FX = require(ReplicatedStorage.Movement.FX)
local Fly = require(ReplicatedStorage.Movement.Fly)

-- One-shot FX helper: plays ReplicatedStorage/FX/<name> once at character position
local function playOneShotFx(character, fxName, customPosition)
	local root = character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)
	if not root then
		return
	end
	local fxFolder = ReplicatedStorage:FindFirstChild("FX")
	local template = fxFolder and fxFolder:FindFirstChild(fxName)
	if not template then
		return
	end

	-- For double jump, position at character's feet
	local fxPosition = customPosition
	if not fxPosition and fxName == "DoubleJump" then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local feetOffset = humanoid and humanoid.HipHeight or 3
		fxPosition = root.Position - Vector3.new(0, feetOffset, 0)
	end

	if fxPosition then
		-- Create invisible anchor part for precise positioning
		local fxAnchor = Instance.new("Part")
		fxAnchor.Name = "FXAnchor_" .. fxName
		fxAnchor.Size = Vector3.new(0.1, 0.1, 0.1)
		fxAnchor.Transparency = 1
		fxAnchor.CanCollide = false
		fxAnchor.Anchored = true
		fxAnchor.Position = fxPosition
		fxAnchor.Parent = workspace

		local inst = template:Clone()
		inst.Name = "OneShot_" .. fxName
		inst.Parent = fxAnchor

		-- Debug: Print FX info
		print("[FX DEBUG] Creating FX:", fxName, "at position:", fxPosition)
		print("[FX DEBUG] Template found:", template.Name, "with children:", #template:GetDescendants())

		-- Emit particles once and play sounds
		for _, d in ipairs(inst:GetDescendants()) do
			if d:IsA("ParticleEmitter") then
				print("[FX DEBUG] Found ParticleEmitter:", d.Name, "Enabled:", d.Enabled)
				local burst = tonumber(d:GetAttribute("Burst") or 30)
				-- Enable the emitter first, then emit
				d.Enabled = true
				pcall(function()
					d:Emit(burst)
					print("[FX DEBUG] Emitted", burst, "particles from", d.Name)
				end)
			elseif d:IsA("Sound") then
				print("[FX DEBUG] Found Sound:", d.Name, "Volume:", d.Volume)
				pcall(function()
					d:Play()
					print("[FX DEBUG] Playing sound:", d.Name)
				end)
			elseif d:IsA("Attachment") then
				print("[FX DEBUG] Found Attachment:", d.Name)
			else
				print("[FX DEBUG] Found other:", d.Name, d.ClassName)
			end
		end

		-- Cleanup after a longer lifetime to see if FX appears
		task.delay(5, function()
			if fxAnchor then
				print("[FX DEBUG] Destroying FX anchor for:", fxName)
				fxAnchor:Destroy()
			end
		end)
	else
		-- Fallback to attaching to character root
		local inst = template:Clone()
		inst.Name = "OneShot_" .. fxName
		inst.Parent = root

		-- Debug fallback FX
		print("[FX DEBUG] Using fallback: attaching to character root")

		for _, d in ipairs(inst:GetDescendants()) do
			if d:IsA("ParticleEmitter") then
				print("[FX DEBUG] Fallback ParticleEmitter:", d.Name, "Enabled:", d.Enabled)
				local burst = tonumber(d:GetAttribute("Burst") or 30)
				d.Enabled = true
				pcall(function()
					d:Emit(burst)
					print("[FX DEBUG] Fallback emitted", burst, "particles from", d.Name)
				end)
			elseif d:IsA("Sound") then
				print("[FX DEBUG] Fallback Sound:", d.Name)
				pcall(function()
					d:Play()
				end)
			end
		end

		task.delay(2, function()
			if inst then
				inst:Destroy()
			end
		end)
	end
end

-- Helper function to check clearance above ledge - improved version
local function hasEnoughClearanceAbove(root, ledgeY, forwardDirection, hitPoint)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { root.Parent }
	params.IgnoreWater = true

	local requiredHeight = Config.LedgeHangMinClearance or 3.5 -- Use same clearance as Abilities module
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
						"[Clearance] Point %d: obstacle at %.2f studs above ledge (required: %.2f)",
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
			print(string.format("[Clearance] Point %d: no obstacle found, clearance OK", i))
		end
	end

	if Config.DebugLedgeHang then
		print("[Clearance] All points clear, sufficient space for mantle")
	end
	return true
end
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local StyleCommit = Remotes:WaitForChild("StyleCommit")
local MaxComboReport = Remotes:WaitForChild("MaxComboReport")
local PadTriggered = Remotes:WaitForChild("PadTriggered")
local PowerupActivatedEvt = Remotes:WaitForChild("PowerupActivated")

local player = Players.LocalPlayer

local state = {
	momentum = Momentum.create(),
	stamina = Stamina.create(),
	sliding = false,
	slideEnd = nil,
	crawling = false,
	shouldActivateCrawl = false,
	sprintHeld = false,
	keys = { W = false, A = false, S = false, D = false },
	clientStateFolder = nil,
	staminaValue = nil,
	speedValue = nil,
	momentumValue = nil,
	bunnyHopStacksValue = nil,
	bunnyHopFlashValue = nil,
	style = Style.create(),
	styleScoreValue = nil,
	styleComboValue = nil,
	styleMultiplierValue = nil,
	styleLastMult = 1,

	maxComboSession = 0,
	styleCommitFlashValue = nil,
	styleCommitAmountValue = nil,
	pendingPadTick = nil,
	wallAttachLockedUntil = nil,
	_airDashResetDone = false,
	doubleJumpCharges = 0,
	_groundedSince = nil,
	_groundResetDone = false,
	_lastMantleTime = 0,
	_lastLedgeHangTime = 0,
	-- Climb animation state
	climbAnimationTrack = nil,
	lastClimbDirection = Vector3.new(0, 0, 0),
	climbAnimationStartTime = 0,
	-- Air animation state
	airAnimationTrack = nil,
	lastAirState = "neutral",
	airAnimationStartTime = 0,
}

local function setProxyWorldY(proxy, targetY)
	if not proxy then
		return
	end
	if proxy:IsA("Attachment") then
		local p = proxy.Position
		-- only raise, never push down
		if p.Y < targetY then
			proxy.Position = Vector3.new(p.X, targetY, p.Z)
		end
		return
	end
	if proxy:IsA("BasePart") then
		-- Keep the bottom of the part at Y=targetY regardless of its size
		local halfY = proxy.Size.Y * 0.5
		local desiredCenterY = targetY + halfY
		local currentCenterY = proxy.Position.Y
		local deltaY = desiredCenterY - currentCenterY
		if math.abs(deltaY) > 1e-3 then
			proxy.CFrame = proxy.CFrame + Vector3.new(0, deltaY, 0)
		end
	end
end

local function setProxyFollowRootAtY(character, proxy, targetBottomY)
	if not (character and proxy and proxy:IsA("BasePart")) then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local rx, ry, rz = root.CFrame:ToOrientation()
	local halfY = proxy.Size.Y * 0.5
	local desiredCenterY = targetBottomY + halfY
	local pos = Vector3.new(root.Position.X, desiredCenterY, root.Position.Z)
	proxy.CFrame = CFrame.new(pos) * CFrame.fromOrientation(rx, ry, rz)
end

local function disableProxyWelds(proxy)
	if not (proxy and proxy:IsA("BasePart")) then
		return {}
	end
	local disabled = {}
	for _, ch in ipairs(proxy:GetChildren()) do
		if ch:IsA("WeldConstraint") then
			if ch.Enabled then
				ch.Enabled = false
				table.insert(disabled, ch)
			end
		end
	end
	return disabled
end

local function restoreProxyWelds(list)
	if not list then
		return
	end
	for _, w in ipairs(list) do
		if w and w.Parent and w:IsA("WeldConstraint") then
			w.Enabled = true
		end
	end
end

-- Per-wall chain anti-abuse: track consecutive chain actions on the same wall
local wallChain = { currentWall = nil, count = 0 }
local function resetWallChain()
	wallChain.currentWall = nil
	wallChain.count = 0
end

-- Reset chain when grounded
RunService.RenderStepped:Connect(function()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.FloorMaterial ~= Enum.Material.Air then
		resetWallChain()
	end
end)

local function getNearbyWallInstance()
	local character = player.Character
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true
	local dirs = { root.CFrame.RightVector, -root.CFrame.RightVector, root.CFrame.LookVector, -root.CFrame.LookVector }
	for _, d in ipairs(dirs) do
		local r = workspace:Raycast(root.Position, d * (Config.WallSlideDetectionDistance or 4), params)
		if r and r.Instance and r.Instance.CanCollide then
			return r.Instance
		end
	end
	return nil
end

local function maybeConsumePadThenBump(eventName)
	-- Skip WallSlide events entirely
	if eventName == "WallSlide" then
		return
	end

	local chainWin = Config.ComboChainWindowSeconds or 3
	if state.pendingPadTick and (os.clock() - state.pendingPadTick) <= chainWin then
		Style.addEvent(state.style, "Pad", 1)
		state.pendingPadTick = nil
	end
	-- Enforce per-wall chain cap
	local maxPerWall = Config.MaxWallChainPerSurface or 3
	if eventName == "WallJump" or eventName == "WallRun" then
		local wall = getNearbyWallInstance()
		if wall then
			if wallChain.currentWall == wall then
				wallChain.count = wallChain.count + 1
			else
				wallChain.currentWall = wall
				wallChain.count = 1
			end
			if wallChain.count > maxPerWall then
				return -- suppress further combo bumps on this wall until reset by ground
			end
		end
	end
	Style.addEvent(state.style, eventName, 1)
end

local function getCharacter()
	local character = player.Character or player.CharacterAdded:Wait()
	return character
end

local function getHumanoid(character)
	return character:WaitForChild("Humanoid")
end

local function setupCharacter(character)
	local humanoid = getHumanoid(character)
	humanoid.WalkSpeed = Config.BaseWalkSpeed
	-- Preload configured animations on character spawn to avoid first-play hitches
	task.spawn(function()
		Animations.preload()
	end)

	-- Hook fall detection for landing roll
	local humanoid = getHumanoid(character)
	local lastAirY = nil
	local minRollDrop = Config.MinRollDrop or 25 -- studs; can be moved to Config later if needed
	local rollPending = false
	local jumpLoopTrack = nil
	humanoid.StateChanged:Connect(function(old, new)
		-- Don't interfere with flying state
		if Fly.isActive(character) and new ~= Enum.HumanoidStateType.Physics then
			-- Prevent state changes while flying
			if humanoid:GetState() ~= Enum.HumanoidStateType.Physics then
				humanoid:ChangeState(Enum.HumanoidStateType.Physics)
			end
			return
		end
		if new == Enum.HumanoidStateType.Freefall then
			local root = character:FindFirstChild("HumanoidRootPart")
			-- Track peak height during this airborne phase for reliable roll on high launches
			local y = root and root.Position.Y or nil
			lastAirY = y
			state._peakAirY = y
			rollPending = true
			-- Start jump loop while airborne if configured (only if no vault/mantle/wallrun/slide/zipline)
			local allowJumpLoop = not (state.isVaultingValue and state.isVaultingValue.Value)
			local jumpAnim = allowJumpLoop and Animations and Animations.get and Animations.get("Jump") or nil
			if jumpAnim then
				local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
				animator.Parent = humanoid
				if not jumpLoopTrack then
					pcall(function()
						jumpLoopTrack = animator:LoadAnimation(jumpAnim)
					end)
				end
				if jumpLoopTrack then
					jumpLoopTrack.Priority = Enum.AnimationPriority.Movement
					jumpLoopTrack.Looped = true
					-- Use consistent animation speed from config
					local jumpSpeed = Config.AirAnimationSpeed.Jump or Config.AirAnimationSpeed.Default
					local playbackSpeed = 1.0 / jumpSpeed
					if not jumpLoopTrack.IsPlaying then
						jumpLoopTrack:Play(0.05, 1, playbackSpeed)
					end
				end
			end
			-- If any action blocks air loop, stop it
			if (state.isVaultingValue and state.isVaultingValue.Value) and jumpLoopTrack then
				pcall(function()
					jumpLoopTrack:Stop(0.05)
				end)
				jumpLoopTrack = nil
			end
			-- Reset air dash charges once per airtime
			-- No longer refilling dash/double jump on airtime; reset only on ground contact
		elseif new == Enum.HumanoidStateType.Jumping then
			-- Play jump FX
			FX.playJump(character)
			-- Play one-shot JumpStart, then transition to Jump loop (unless blocked)
			local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
			animator.Parent = humanoid
			local startAnim = Animations and Animations.get and Animations.get("JumpStart")
			local loopAllowed = not (state.isVaultingValue and state.isVaultingValue.Value)
			local loopAnim = loopAllowed and Animations and Animations.get and Animations.get("Jump") or nil
			local startTrack
			-- Carry part of slide momentum into jump (extra vertical and horizontal)
			do
				local root = character:FindFirstChild("HumanoidRootPart")
				if root then
					local v = root.AssemblyLinearVelocity
					local horiz = Vector3.new(v.X, 0, v.Z)
					local spd = horiz.Magnitude
					local upGain = (Config.SlideJumpVerticalPercent or 0.30) * spd
					local fwdGain = (Config.SlideJumpHorizontalPercent or 0.15) * spd
					local dir = nil
					if spd > 0.05 then
						dir = horiz.Unit
					else
						dir = Vector3.new(
							character.PrimaryPart.CFrame.LookVector.X,
							0,
							character.PrimaryPart.CFrame.LookVector.Z
						)
						if dir.Magnitude > 0.01 then
							dir = dir.Unit
						end
					end
					-- One-frame injection to shape jump start
					local vy = v.Y + upGain
					local vxz = dir * (Vector3.new(v.X, 0, v.Z).Magnitude + fwdGain)
					root.AssemblyLinearVelocity = Vector3.new(vxz.X, vy, vxz.Z)
				end
			end
			if startAnim then
				pcall(function()
					startTrack = animator:LoadAnimation(startAnim)
				end)
			end
			if startTrack then
				startTrack.Priority = Enum.AnimationPriority.Action
				startTrack.Looped = false
				startTrack:Play(0.05, 1, 1.0)
				startTrack.Stopped:Connect(function()
					if humanoid.FloorMaterial == Enum.Material.Air and loopAllowed and loopAnim then
						if not jumpLoopTrack then
							pcall(function()
								jumpLoopTrack = animator:LoadAnimation(loopAnim)
							end)
						end
						if jumpLoopTrack then
							jumpLoopTrack.Priority = Enum.AnimationPriority.Movement
							jumpLoopTrack.Looped = true
							-- Use consistent animation speed from config
							local jumpSpeed = Config.AirAnimationSpeed.Jump or Config.AirAnimationSpeed.Default
							local playbackSpeed = 1.0 / jumpSpeed
							if not jumpLoopTrack.IsPlaying then
								jumpLoopTrack:Play(0.05, 1, playbackSpeed)
							end
						end
					end
				end)
			else
				if loopAllowed and loopAnim then
					if not jumpLoopTrack then
						pcall(function()
							jumpLoopTrack = animator:LoadAnimation(loopAnim)
						end)
					end
					if jumpLoopTrack then
						jumpLoopTrack.Priority = Enum.AnimationPriority.Movement
						jumpLoopTrack.Looped = true
						-- Use consistent animation speed from config
						local jumpSpeed = Config.AirAnimationSpeed.Jump or Config.AirAnimationSpeed.Default
						local playbackSpeed = 1.0 / jumpSpeed
						if not jumpLoopTrack.IsPlaying then
							jumpLoopTrack:Play(0.05, 1, playbackSpeed)
						end
					end
				end
			end
		elseif new == Enum.HumanoidStateType.Landed or new == Enum.HumanoidStateType.Running then
			-- Check if player is connecting to a parkour action instead of actually landing
			local isConnectingToParkour = (
				Climb.isActive(character)
				or WallRun.isActive(character)
				or Zipline.isActive(character)
				or VerticalClimb.isActive(character)
				or LedgeHang.isActive(character)
				or (WallJump.isWallSliding and WallJump.isWallSliding(character))
			)

			-- Only process landing if not connecting to parkour action
			if not isConnectingToParkour then
				-- Mark grounded time; actual reset is handled by dwell check in RenderStepped
				state._groundedSince = os.clock()
				state._groundResetDone = false
				local root = character:FindFirstChild("HumanoidRootPart")
				if rollPending and root and lastAirY then
					local peakY = state._peakAirY or lastAirY
					local drop = math.max(0, (peakY - root.Position.Y))
					local cfgDbg = require(ReplicatedStorage.Movement.Config).DebugLandingRoll
					if cfgDbg then
						print(
							string.format(
								"[LandingRoll] peakY=%.2f y=%.2f drop=%.2f threshold=%d",
								peakY,
								root.Position.Y,
								drop,
								20
							)
						)
					end
					if drop >= minRollDrop then
						-- Play landing FX for high fall + roll
						FX.playRoll(character)
						FX.playLanding(character, true) -- hard landing
						-- Play LandRoll animation if configured
						local anim = Animations and Animations.get and Animations.get("LandRoll")
						if anim then
							local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
							animator.Parent = humanoid
							local track
							pcall(function()
								track = animator:LoadAnimation(anim)
							end)
							if track then
								track.Priority = Enum.AnimationPriority.Action
								track.Looped = false
								track:Play(0.05, 1, 1.0)
							end
						end
					else
						-- Normal landing FX
						FX.playLanding(character, false)
					end
				else
					-- Normal landing FX (no fall)
					FX.playLanding(character, false)
				end
				rollPending = false
				state._peakAirY = nil
				lastAirY = nil
				-- Stop jump loop on landing/running
				if jumpLoopTrack then
					pcall(function()
						jumpLoopTrack:Stop(0.1)
					end)
					jumpLoopTrack = nil
				end
			else
				-- Player connected to parkour action, reset pending states without landing
				rollPending = false
				state._peakAirY = nil
				lastAirY = nil
				-- Still stop jump loop when connecting to parkour
				if jumpLoopTrack then
					pcall(function()
						jumpLoopTrack:Stop(0.1)
					end)
					jumpLoopTrack = nil
				end
			end
		end
	end)
	-- Setup stamina touch tracking for parts with attribute Stamina=true (works even for CanQuery=false when CanTouch is true)
	state.staminaTouched = {}
	state.staminaTouchCount = 0
	if state.touchConns then
		for _, c in ipairs(state.touchConns) do
			if c then
				c:Disconnect()
			end
		end
	end
	state.touchConns = {}

	local function onTouched(other)
		if other and other:IsA("BasePart") then
			local CollectionService = game:GetService("CollectionService")
			if CollectionService:HasTag(other, "Stamina") then
				if not state.staminaTouched[other] then
					state.staminaTouched[other] = 1
					state.staminaTouchCount = state.staminaTouchCount + 1
				end
			end
		end
		-- Publish last collidable touch for vault fallback detection (handles CanQuery=false parts)
		if other and other:IsA("BasePart") and other.CanCollide then
			local folder = state.clientStateFolder
			if folder then
				local partVal = folder:FindFirstChild("VaultTouchPart")
				if not partVal then
					partVal = Instance.new("ObjectValue")
					partVal.Name = "VaultTouchPart"
					partVal.Parent = folder
				end
				local timeVal = folder:FindFirstChild("VaultTouchTime")
				if not timeVal then
					timeVal = Instance.new("NumberValue")
					timeVal.Name = "VaultTouchTime"
					timeVal.Parent = folder
				end
				local posVal = folder:FindFirstChild("VaultTouchPos")
				if not posVal then
					posVal = Instance.new("Vector3Value")
					posVal.Name = "VaultTouchPos"
					posVal.Parent = folder
				end
				partVal.Value = other
				timeVal.Value = os.clock()
				posVal.Value = other.Position
			end
		end
	end
	local function onTouchEnded(other)
		if other and state.staminaTouched[other] then
			state.staminaTouched[other] = nil
			state.staminaTouchCount = math.max(0, state.staminaTouchCount - 1)
		end
	end

	local function hookPart(part)
		if not part:IsA("BasePart") then
			return
		end
		table.insert(state.touchConns, part.Touched:Connect(onTouched))
		if part.TouchEnded then
			table.insert(state.touchConns, part.TouchEnded:Connect(onTouchEnded))
		end
	end

	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("BasePart") then
			hookPart(d)
		end
	end
	character.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then
			hookPart(d)
		end
	end)

	-- Reset transient state on spawn and publish clean HUD states
	state.sprintHeld = false
	if state.stamina then
		state.stamina.current = Config.StaminaMax
		state.stamina.isSprinting = false
	end
	if state.staminaValue then
		state.staminaValue.Value = state.stamina.current
	end
	if state.isSprintingValue then
		state.isSprintingValue.Value = false
	end
	if state.isSlidingValue then
		state.isSlidingValue.Value = false
	end
	if state.isCrawlingValue then
		state.isCrawlingValue.Value = false
	end
	if state.shouldActivateCrawlValue then
		state.shouldActivateCrawlValue.Value = false
	end
	if state.slideOriginalSizeValue then
		state.slideOriginalSizeValue.Value = Vector3.new(2, 4, 1) -- Default size
	end
	if state.isAirborneValue then
		state.isAirborneValue.Value = false
	end
	if state.isWallRunningValue then
		state.isWallRunningValue.Value = false
	end
	if state.isClimbingValue then
		state.isClimbingValue.Value = false
	end
	-- Initialize bunny hop listener for this character
	BunnyHop.setup(character)

	-- Audio managed by AudioManager.client.lua
end

-- Handles air state animations (jump, fall, rise) based on vertical velocity
local function updateAirAnimation(character)
	local humanoid = getHumanoid(character)
	if not humanoid then
		return
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	-- Stop air animations when not airborne or when grounded
	if
		humanoid.FloorMaterial ~= Enum.Material.Air
		or humanoid:GetState() == Enum.HumanoidStateType.Running
		or humanoid:GetState() == Enum.HumanoidStateType.Landed
	then
		-- Stop any playing air animation
		if state.airAnimationTrack and state.airAnimationTrack.IsPlaying then
			pcall(function()
				state.airAnimationTrack:Stop(0.1)
			end)
		end
		state.airAnimationTrack = nil
		state.lastAirState = "neutral"
		state.airAnimationStartTime = 0
		return
	end

	local velocity = root.AssemblyLinearVelocity
	local verticalSpeed = velocity.Y

	-- Determine air state with more precise thresholds
	local isRising = verticalSpeed > 1 -- Going up
	local isFalling = verticalSpeed < -1 -- Going down
	local isNeutral = verticalSpeed >= -1 and verticalSpeed <= 1 -- Floating/neutral

	-- Get appropriate animation
	local airAnim = nil
	local animationSpeed = 1.0
	local currentState = "neutral"

	if isRising then
		currentState = "rising"
		-- Use Rise animation if available, otherwise use Jump
		local riseAnim = Animations.get("Rise")
		if riseAnim then
			airAnim = riseAnim
			animationSpeed = Config.AirAnimationSpeed.Rise or Config.AirAnimationSpeed.Default
		else
			airAnim = Animations.get("Jump")
			animationSpeed = Config.AirAnimationSpeed.Jump or Config.AirAnimationSpeed.Default
		end
	elseif isFalling then
		currentState = "falling"
		-- Use Fall animation if available, otherwise use Jump
		local fallAnim = Animations.get("Fall")
		if fallAnim then
			airAnim = fallAnim
			animationSpeed = Config.AirAnimationSpeed.Fall or Config.AirAnimationSpeed.Default
		else
			airAnim = Animations.get("Jump")
			animationSpeed = Config.AirAnimationSpeed.Jump or Config.AirAnimationSpeed.Default
		end
	else
		currentState = "neutral"
		-- Neutral/float state - use Jump animation
		airAnim = Animations.get("Jump")
		animationSpeed = Config.AirAnimationSpeed.Jump or Config.AirAnimationSpeed.Default
	end

	-- Check if we need to change animation
	local needsChange = false
	if not state.airAnimationTrack then
		needsChange = true
	elseif not state.airAnimationTrack.IsPlaying then
		needsChange = true
	elseif state.lastAirState ~= currentState then
		needsChange = true
	end

	-- Force change if we've been in the same state for too long (fallback)
	if not needsChange and state.airAnimationTrack then
		local timeInState = os.clock() - (state.airAnimationStartTime or 0)
		if timeInState > 5.0 then -- 5 seconds max in same animation
			needsChange = true
		end
	end

	if needsChange and airAnim then
		-- Stop current air animation if it exists
		if state.airAnimationTrack and state.airAnimationTrack.IsPlaying then
			pcall(function()
				state.airAnimationTrack:Stop(0.1)
			end)
		end

		-- Stop conflicting animations (run/walk, etc.)
		local playingTracks = animator:GetPlayingAnimationTracks()
		for _, track in ipairs(playingTracks) do
			-- Stop animations with lower priority that might conflict
			if track.Priority.Value < Enum.AnimationPriority.Action.Value then
				if not (state.climbAnimationTrack and track == state.climbAnimationTrack) then
					pcall(function()
						track:Stop(0.1)
					end)
				end
			end
		end

		-- Play the new air animation
		local track
		pcall(function()
			track = animator:LoadAnimation(airAnim)
		end)

		if track then
			track.Priority = Enum.AnimationPriority.Action
			track.Looped = true
			local playbackSpeed = 1.0 / animationSpeed
			track:Play(0.1, 1, playbackSpeed)
			state.airAnimationTrack = track
			state.lastAirState = currentState
			state.airAnimationStartTime = os.clock()
		end
	end
end

-- Handles climb animation switching based on movement direction
local function updateClimbAnimation(character, moveDirection)
	local humanoid = getHumanoid(character)
	if not humanoid then
		return
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end

	-- Stop current climb animation if direction changed significantly
	local directionChanged = (moveDirection - state.lastClimbDirection).Magnitude > 0.1

	if state.climbAnimationTrack and (directionChanged or not Climb.isActive(character)) then
		pcall(function()
			state.climbAnimationTrack:Stop(0.1)
		end)
		state.climbAnimationTrack = nil
	end

	-- Don't play new animation if climbing stopped
	if not Climb.isActive(character) then
		state.lastClimbDirection = Vector3.new(0, 0, 0)
		return
	end

	-- Get appropriate animation for current direction with speed
	local climbAnim, animationSpeed = Animations.getClimbAnimationWithSpeed(moveDirection)
	if not climbAnim then
		-- Fallback to default climb loop
		climbAnim = Animations.get("ClimbLoop")
		if climbAnim then
			local Config = require(game:GetService("ReplicatedStorage").Movement.Config)
			animationSpeed = Config.ClimbAnimationSpeed.Default
		end
	end

	if not climbAnim then
		return
	end

	-- Only change animation if it's different or direction changed significantly
	if not state.climbAnimationTrack or directionChanged then
		pcall(function()
			local track = animator:LoadAnimation(climbAnim)
			track.Priority = Enum.AnimationPriority.Action
			track.Looped = true
			-- Use the configured animation speed to control playback rate
			-- Speed = 1.0 means normal speed, higher values make it faster, lower values slower
			local playbackSpeed = 1.0 / animationSpeed
			track:Play(0.1, 1, playbackSpeed)
			state.climbAnimationTrack = track
			state.climbAnimationStartTime = os.clock()
		end)
	end

	state.lastClimbDirection = moveDirection
end

-- Cleanup climb animation when climbing stops
local function cleanupClimbAnimation(character)
	if state.climbAnimationTrack then
		pcall(function()
			state.climbAnimationTrack:Stop(0.1)
		end)
		state.climbAnimationTrack = nil
	end
	state.lastClimbDirection = Vector3.new(0, 0, 0)
	state.climbAnimationStartTime = 0
end

-- Stop conflicting animations when entering specific movement states
local function stopConflictingAnimations(character, newState)
	local humanoid = getHumanoid(character)
	if not humanoid then
		return
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end

	-- Stop jump/fall animations when entering climbing, wallrun, zipline, wall sliding, ledge hanging, or vertical climbing
	if
		newState == "climbing"
		or newState == "wallrun"
		or newState == "zipline"
		or newState == "wallslide"
		or newState == "ledgehang"
		or newState == "verticalclimb"
	then
		-- Stop all playing animation tracks that might conflict
		local playingTracks = animator:GetPlayingAnimationTracks()
		for _, track in ipairs(playingTracks) do
			-- Stop jump/fall animations that have lower priority than action animations
			-- Also stop any animation that might be interfering with the new state
			if track.Priority.Value <= Enum.AnimationPriority.Movement.Value then
				-- Check if this track is not our climbing or air animation
				if
					not (state.climbAnimationTrack and track == state.climbAnimationTrack)
					and not (state.airAnimationTrack and track == state.airAnimationTrack)
				then
					pcall(function()
						track:Stop(0.05)
					end)
				end
			end
		end

		-- Stop air animation track if it's playing
		if state.airAnimationTrack and state.airAnimationTrack.IsPlaying then
			pcall(function()
				state.airAnimationTrack:Stop(0.05)
			end)
			state.airAnimationTrack = nil
			state.lastAirState = "neutral"
			state.airAnimationStartTime = 0
		end
	end
end

local function ensureClientState()
	local folder = ReplicatedStorage:FindFirstChild("ClientState")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "ClientState"
		folder.Parent = ReplicatedStorage
	end
	state.clientStateFolder = folder

	local staminaValue = folder:FindFirstChild("Stamina")
	if not staminaValue then
		staminaValue = Instance.new("NumberValue")
		staminaValue.Name = "Stamina"
		staminaValue.Parent = folder
	end
	state.staminaValue = staminaValue

	-- Max stamina value for powerup percentage calculations
	local maxStaminaValue = folder:FindFirstChild("MaxStamina")
	if not maxStaminaValue then
		maxStaminaValue = Instance.new("NumberValue")
		maxStaminaValue.Name = "MaxStamina"
		maxStaminaValue.Value = Config.StaminaMax
		maxStaminaValue.Parent = folder
	end
	state.maxStaminaValue = maxStaminaValue

	-- Double jump charges for powerup restoration
	local doubleJumpCharges = folder:FindFirstChild("DoubleJumpCharges")
	if not doubleJumpCharges then
		doubleJumpCharges = Instance.new("IntValue")
		doubleJumpCharges.Name = "DoubleJumpCharges"
		doubleJumpCharges.Value = Config.DoubleJumpMax or 1
		doubleJumpCharges.Parent = folder
	end
	state.doubleJumpChargesValue = doubleJumpCharges

	-- Air dash charges for powerup restoration
	local airDashCharges = folder:FindFirstChild("AirDashCharges")
	if not airDashCharges then
		airDashCharges = Instance.new("IntValue")
		airDashCharges.Name = "AirDashCharges"
		airDashCharges.Value = Config.DashAirChargesMax or Config.DashAirChargesDefault or 1
		airDashCharges.Parent = folder
	end
	state.airDashChargesValue = airDashCharges

	local speedValue = folder:FindFirstChild("Speed")
	if not speedValue then
		speedValue = Instance.new("NumberValue")
		speedValue.Name = "Speed"
		speedValue.Parent = folder
	end
	state.speedValue = speedValue

	local momentumValue = folder:FindFirstChild("Momentum")
	if not momentumValue then
		momentumValue = Instance.new("NumberValue")
		momentumValue.Name = "Momentum"
		momentumValue.Parent = folder
	end
	state.momentumValue = momentumValue

	local isSprinting = folder:FindFirstChild("IsSprinting")
	if not isSprinting then
		isSprinting = Instance.new("BoolValue")
		isSprinting.Name = "IsSprinting"
		isSprinting.Parent = folder
	end
	state.isSprintingValue = isSprinting

	local isSliding = folder:FindFirstChild("IsSliding")
	if not isSliding then
		isSliding = Instance.new("BoolValue")
		isSliding.Name = "IsSliding"
		isSliding.Parent = folder
	end
	state.isSlidingValue = isSliding

	-- Ensure IsDashing exists for audio/events
	local isDashing = folder:FindFirstChild("IsDashing")
	if not isDashing then
		isDashing = Instance.new("BoolValue")
		isDashing.Name = "IsDashing"
		isDashing.Parent = folder
	end

	local isCrawling = folder:FindFirstChild("IsCrawling")
	if not isCrawling then
		isCrawling = Instance.new("BoolValue")
		isCrawling.Name = "IsCrawling"
		isCrawling.Parent = folder
	end
	state.isCrawlingValue = isCrawling

	local shouldActivateCrawl = folder:FindFirstChild("ShouldActivateCrawl")
	if not shouldActivateCrawl then
		shouldActivateCrawl = Instance.new("BoolValue")
		shouldActivateCrawl.Name = "ShouldActivateCrawl"
		shouldActivateCrawl.Parent = folder
	end
	state.shouldActivateCrawlValue = shouldActivateCrawl

	local slideOriginalSize = folder:FindFirstChild("SlideOriginalSize")
	if not slideOriginalSize then
		slideOriginalSize = Instance.new("Vector3Value")
		slideOriginalSize.Name = "SlideOriginalSize"
		slideOriginalSize.Parent = folder
	end
	state.slideOriginalSizeValue = slideOriginalSize

	local isAirborne = folder:FindFirstChild("IsAirborne")
	if not isAirborne then
		isAirborne = Instance.new("BoolValue")
		isAirborne.Name = "IsAirborne"
		isAirborne.Parent = folder
	end
	state.isAirborneValue = isAirborne

	local isWallRunning = folder:FindFirstChild("IsWallRunning")
	if not isWallRunning then
		isWallRunning = Instance.new("BoolValue")
		isWallRunning.Name = "IsWallRunning"
		isWallRunning.Parent = folder
	end
	state.isWallRunningValue = isWallRunning

	local isWallSliding = folder:FindFirstChild("IsWallSliding")
	if not isWallSliding then
		isWallSliding = Instance.new("BoolValue")
		isWallSliding.Name = "IsWallSliding"
		isWallSliding.Parent = folder
	end
	state.isWallSlidingValue = isWallSliding

	local isMantling = folder:FindFirstChild("IsMantling")
	if not isMantling then
		isMantling = Instance.new("BoolValue")
		isMantling.Name = "IsMantling"
		isMantling.Value = false
		isMantling.Parent = folder
	end
	state.isMantlingValue = isMantling

	local isClimbing = folder:FindFirstChild("IsClimbing")
	if not isClimbing then
		isClimbing = Instance.new("BoolValue")
		isClimbing.Name = "IsClimbing"
		isClimbing.Parent = folder
	end
	state.isClimbingValue = isClimbing

	local isZiplining = folder:FindFirstChild("IsZiplining")
	if not isZiplining then
		isZiplining = Instance.new("BoolValue")
		isZiplining.Name = "IsZiplining"
		isZiplining.Parent = folder
	end
	state.isZipliningValue = isZiplining

	local isLedgeHanging = folder:FindFirstChild("IsLedgeHanging")
	if not isLedgeHanging then
		isLedgeHanging = Instance.new("BoolValue")
		isLedgeHanging.Name = "IsLedgeHanging"
		isLedgeHanging.Value = false
		isLedgeHanging.Parent = folder
	end
	state.isLedgeHangingValue = isLedgeHanging

	local isVaulting = folder:FindFirstChild("IsVaulting")
	if not isVaulting then
		isVaulting = Instance.new("BoolValue")
		isVaulting.Name = "IsVaulting"
		isVaulting.Parent = folder
	end
	state.isVaultingValue = isVaulting

	local climbPrompt = folder:FindFirstChild("ClimbPrompt")
	if not climbPrompt then
		climbPrompt = Instance.new("StringValue")
		climbPrompt.Name = "ClimbPrompt"
		climbPrompt.Value = ""
		climbPrompt.Parent = folder
	end
	state.climbPromptValue = climbPrompt

	-- Bunny hop HUD bindings
	local bhStacks = folder:FindFirstChild("BunnyHopStacks")
	if not bhStacks then
		bhStacks = Instance.new("NumberValue")
		bhStacks.Name = "BunnyHopStacks"
		bhStacks.Value = 0
		bhStacks.Parent = folder
	end
	state.bunnyHopStacksValue = bhStacks

	local bhFlash = folder:FindFirstChild("BunnyHopFlash")
	if not bhFlash then
		bhFlash = Instance.new("BoolValue")
		bhFlash.Name = "BunnyHopFlash"
		bhFlash.Value = false
		bhFlash.Parent = folder
	end
	state.bunnyHopFlashValue = bhFlash

	-- Style HUD values
	local styleScore = folder:FindFirstChild("StyleScore")
	if not styleScore then
		styleScore = Instance.new("NumberValue")
		styleScore.Name = "StyleScore"
		styleScore.Value = 0
		styleScore.Parent = folder
	end
	state.styleScoreValue = styleScore

	local styleCombo = folder:FindFirstChild("StyleCombo")
	if not styleCombo then
		styleCombo = Instance.new("NumberValue")
		styleCombo.Name = "StyleCombo"
		styleCombo.Value = 0
		styleCombo.Parent = folder
	end
	state.styleComboValue = styleCombo

	local styleMult = folder:FindFirstChild("StyleMultiplier")
	if not styleMult then
		styleMult = Instance.new("NumberValue")
		styleMult.Name = "StyleMultiplier"
		styleMult.Value = 1
		styleMult.Parent = folder
	end
	state.styleMultiplierValue = styleMult

	-- Style commit UI signals
	local styleCommitAmount = folder:FindFirstChild("StyleCommittedAmount")
	if not styleCommitAmount then
		styleCommitAmount = Instance.new("NumberValue")
		styleCommitAmount.Name = "StyleCommittedAmount"
		styleCommitAmount.Value = 0
		styleCommitAmount.Parent = folder
	end
	state.styleCommitAmountValue = styleCommitAmount

	local styleCommitFlash = folder:FindFirstChild("StyleCommittedFlash")
	if not styleCommitFlash then
		styleCommitFlash = Instance.new("BoolValue")
		styleCommitFlash.Name = "StyleCommittedFlash"
		styleCommitFlash.Value = false
		styleCommitFlash.Parent = folder
	end
	state.styleCommitFlashValue = styleCommitFlash

	-- Combo timeout HUD bindings
	local comboRemain = folder:FindFirstChild("StyleComboTimeRemaining")
	if not comboRemain then
		comboRemain = Instance.new("NumberValue")
		comboRemain.Name = "StyleComboTimeRemaining"
		comboRemain.Value = Config.StyleBreakTimeoutSeconds or 3
		comboRemain.Parent = folder
	end
	state.styleComboTimeRemaining = comboRemain

	local comboMax = folder:FindFirstChild("StyleComboTimeMax")
	if not comboMax then
		comboMax = Instance.new("NumberValue")
		comboMax.Name = "StyleComboTimeMax"
		comboMax.Value = Config.StyleBreakTimeoutSeconds or 3
		comboMax.Parent = folder
	end
	state.styleComboTimeMax = comboMax

	-- New: IsDoubleJumping for audio
	local isDoubleJumping = folder:FindFirstChild("IsDoubleJumping")
	if not isDoubleJumping then
		isDoubleJumping = Instance.new("BoolValue")
		isDoubleJumping.Name = "IsDoubleJumping"
		isDoubleJumping.Value = false
		isDoubleJumping.Parent = folder
	end
	state.isDoubleJumpingValue = isDoubleJumping
end

ensureClientState()

-- Apply powerup effects to authoritative local state so HUD doesn't revert
PowerupActivatedEvt.OnClientEvent:Connect(function(powerupTag, success, partName, quantity, partPosition)
	local q = tonumber(quantity)
	if powerupTag == "AddStamina" then
		local maxStam = (state.maxStaminaValue and state.maxStaminaValue.Value) or Config.StaminaMax
		local pct = q or (Config.PowerupStaminaPercentDefault or 25)
		local add = (pct / 100) * maxStam
		state.stamina.current = math.min(maxStam, (state.stamina.current or 0) + add)
		if state.staminaValue then
			state.staminaValue.Value = state.stamina.current
		end
	elseif powerupTag == "AddJump" then
		if (state.doubleJumpCharges or 0) <= 0 then
			local maxDJ = Config.DoubleJumpMax or 1
			local want = q or (Config.PowerupJumpCountDefault or 1)
			state.doubleJumpCharges = math.min(maxDJ, want)
			if state.doubleJumpChargesValue then
				state.doubleJumpChargesValue.Value = state.doubleJumpCharges
			end
		end
	elseif powerupTag == "AddAllSkills" then
		-- full stamina and reset double jump; dash handled in Powerups.lua via Abilities
		state.stamina.current = Config.StaminaMax
		if state.staminaValue then
			state.staminaValue.Value = state.stamina.current
		end
		local maxDJ = Config.DoubleJumpMax or 1
		state.doubleJumpCharges = maxDJ
		if state.doubleJumpChargesValue then
			state.doubleJumpChargesValue.Value = maxDJ
		end
	end
end)

player.CharacterAdded:Connect(setupCharacter)
if player.Character then
	setupCharacter(player.Character)
end
player.CharacterAdded:Connect(function()
	-- Reset style session state hard on respawn to avoid zero-point commit visuals
	state.style = Style.create()
	if state.styleScoreValue then
		state.styleScoreValue.Value = 0
	end
	if state.styleComboValue then
		state.styleComboValue.Value = 0
	end
	if state.styleMultiplierValue then
		state.styleMultiplierValue.Value = 1
	end
end)
player.CharacterRemoving:Connect(function(char)
	BunnyHop.teardown(char)
	if Fly.isActive(char) then
		Fly.stop(char)
	end
end)

-- Ensure camera align caches base motors on spawn
-- (Removed CameraAlign setup; head tracking handled by HeadTracking.client.lua)

-- Inputs
UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then
		return
	end

	local character = getCharacter()

	if input.KeyCode == Enum.KeyCode.Q then
		-- Dash: only spend stamina if dash actually triggers (respects cooldown)
		if state.stamina.current >= Config.DashStaminaCost then
			local character = getCharacter()
			if not character then
				return
			end
			-- Disable dash during wall slide, wall run, vault, mantle
			if WallJump.isWallSliding and WallJump.isWallSliding(character) then
				return
			end
			if WallRun.isActive(character) then
				return
			end
			local cs = ReplicatedStorage:FindFirstChild("ClientState")
			local isVaulting = cs and cs:FindFirstChild("IsVaulting")
			local isMantling = cs and cs:FindFirstChild("IsMantling")
			if (isVaulting and isVaulting.Value) or (isMantling and isMantling.Value) then
				return
			end
			local humanoid = getHumanoid(character)
			local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
			local didDash = Abilities.tryDash(character)
			if didDash then
				state.stamina.current = math.max(0, state.stamina.current - Config.DashStaminaCost)
				DashVfx.playFor(character, Config.DashVfxDuration)
				-- Play FX based on dash type
				FX.playDash(character, not grounded) -- true for air dash
			end
		end
	elseif input.KeyCode == Enum.KeyCode.LeftShift then
		state.sprintHeld = true
	elseif input.KeyCode == Enum.KeyCode.C then
		local character = getCharacter()
		if character then
			-- PRIORITY 1: LedgeHang release (highest priority)
			if LedgeHang.isActive(character) then
				LedgeHang.stop(character, true) -- true = manual release
				return -- Don't process other C key functions
			end

			-- PRIORITY 2: Wallslide toggle/reactivation
			if WallJump.isWallSliding and WallJump.isWallSliding(character) then
				-- Currently wallsliding - toggle OFF
				local success = WallJump.toggleWallslide(character)
				return -- Don't process other C key functions
			elseif WallJump.isWallslideDisabled and WallJump.isWallslideDisabled(character) then
				-- Wallslide is disabled - try to reactivate manually during fall
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				local isAirborne = humanoid and (humanoid.FloorMaterial == Enum.Material.Air)
				if isAirborne then
					local success = WallJump.tryManualReactivate(character)
					return -- Only block other C key functions if we're airborne
				end
				-- If we're grounded, allow normal ground slide to continue
			end

			-- PRIORITY 3: Ground slide (existing functionality)
			if not (Zipline.isActive(character) or Climb.isActive(character) or WallRun.isActive(character)) then
				if not (WallJump.isWallSliding and WallJump.isWallSliding(character)) then
					local Abilities = require(ReplicatedStorage.Movement.Abilities)
					local humanoid = getHumanoid(character)
					local isMoving = humanoid and humanoid.MoveDirection and humanoid.MoveDirection.Magnitude > 0
					local grounded = humanoid and (humanoid.FloorMaterial ~= Enum.Material.Air)
					local sprinting = state.stamina.isSprinting and state.sprintHeld and isMoving
					if
						grounded
						and not state.sliding
						and ((Config.SlideRequireSprint ~= false and sprinting) or (Config.SlideRequireSprint == false and isMoving))
						and Abilities.isSlideReady()
					then
						-- Consume stamina for slide
						local staminaCost = Config.SlideStaminaCost or 12
						state.stamina.current = math.max(0, state.stamina.current - staminaCost)

						local endFn = Abilities.slide(character)
						if type(endFn) == "function" then
							-- Add to Style/Combo system
							if state.style then
								local Style = require(ReplicatedStorage.Movement.Style)
								Style.addEvent(state.style, "GroundSlide", 1)
							end

							state.sliding = true
							state.slideEnd = function()
								state.sliding = false
								pcall(endFn)
							end
							-- Auto-clear after the slide duration (cooldown is separate and handled by Abilities.isSlideReady)
							task.delay((Config.SlideDurationSeconds or 0.5), function()
								if state.sliding and state.slideEnd then
									state.slideEnd()
									state.slideEnd = nil
								end
							end)
						end
					end
				end
			end
		end
	elseif input.KeyCode == Enum.KeyCode.E then
		-- PRIORITY 1: Flying (highest priority - check first)
		if Fly.isActive(character) then
			print("[Fly] Stopping flight")
			Fly.stop(character)
		else
			-- Check if user wants to start flying (hold Shift+E or just E when not near zipline/climbable)
			local shouldFly = true
			
			-- Don't start flying if near zipline or actively climbing
			if Zipline.isActive(character) or Zipline.isNear(character) then
				shouldFly = false
			end
			
			if shouldFly then
				print("[Fly] Starting flight")
				-- Stop other movement systems that might interfere
				if Climb.isActive(character) then
					Climb.stop(character)
					cleanupClimbAnimation(character)
				end
				if WallRun.isActive(character) then
					WallRun.stop(character)
				end
				if Zipline.isActive(character) then
					Zipline.stop(character)
				end
				if LedgeHang.isActive(character) then
					LedgeHang.stop(character, true)
				end
				if Grapple.isActive(character) then
					Grapple.stop(character)
				end
				if WallJump.isWallSliding and WallJump.isWallSliding(character) then
					WallJump.stopSlide(character)
				end
				-- Ensure humanoid is ready
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				if humanoid then
					local success = Fly.start(character)
					if success then
						print("[Fly] Flight started successfully")
					else
						print("[Fly] Failed to start flight")
					end
				else
					print("[Fly] No humanoid found")
				end
				return -- Exit early, don't process zipline/climb
			end
		end
		
		-- PRIORITY 2: Zipline takes priority when near a rope
		if Zipline.isActive(character) then
			Zipline.stop(character)
		elseif Zipline.isNear(character) then
			-- stop incompatible states
			if Climb.isActive(character) then
				Climb.stop(character)
				cleanupClimbAnimation(character)
			end
			if WallRun.isActive(character) then
				WallRun.stop(character)
			end
			if WallJump.isWallSliding and WallJump.isWallSliding(character) then
				WallJump.stopSlide(character)
			end
			state.sliding = false
			state.sprintHeld = false
			-- Stop conflicting animations before starting zipline
			stopConflictingAnimations(character, "zipline")
			Zipline.tryStart(character)
		else
			-- PRIORITY 3: Toggle climb on climbable walls
			if Climb.isActive(character) then
				Climb.stop(character)
				cleanupClimbAnimation(character)
			else
				if state.stamina.current >= Config.ClimbMinStamina then
					-- stop any wall slide to allow climbing to take over immediately
					if WallJump.isWallSliding and WallJump.isWallSliding(character) then
						WallJump.stopSlide(character)
					end
					-- Stop conflicting animations before starting climbing
					stopConflictingAnimations(character, "climbing")
					if Climb.tryStart(character) then
						-- start draining immediately on start tick
						state.stamina.current = state.stamina.current - (Config.ClimbStaminaDrainPerSecond * 0.1)
						if state.stamina.current < 0 then
							state.stamina.current = 0
						end
					end
				end
			end
		end
	elseif input.KeyCode == Enum.KeyCode.R then
		-- Grapple/Hook toggle
		local cam = workspace.CurrentCamera
		if cam then
			if Grapple.isActive(character) then
				Grapple.stop(character)
			else
				-- Stop flying if active before using hook
				if Fly.isActive(character) then
					Fly.stop(character)
				end
				Grapple.tryFire(character, cam.CFrame)
			end
		end
	elseif input.KeyCode == Enum.KeyCode.T then
		-- Respawn at checkpoint
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		local respawnRemote = remotes and remotes:FindFirstChild("RespawnAtCheckpoint")
		if respawnRemote then
			respawnRemote:FireServer()
		end
	elseif input.KeyCode == Enum.KeyCode.Space then
		local humanoid = getHumanoid(character)
		-- Block jump while crawling
		do
			local cs = ReplicatedStorage:FindFirstChild("ClientState")
			local isCrawlingVal = cs and cs:FindFirstChild("IsCrawling")
			if isCrawlingVal and isCrawlingVal.Value == true then
				return
			end
		end

		-- Handle ledge hanging input FIRST (highest priority)
		if LedgeHang.isActive(character) then
			-- Check for directional input combinations
			local userInputService = game:GetService("UserInputService")
			local wPressed = userInputService:IsKeyDown(Enum.KeyCode.W)
			local aPressed = userInputService:IsKeyDown(Enum.KeyCode.A)
			local sPressed = userInputService:IsKeyDown(Enum.KeyCode.S)
			local dPressed = userInputService:IsKeyDown(Enum.KeyCode.D)

			local didDirectionalJump = false

			-- Priority order: W > A/D > S > default mantle
			if wPressed then
				didDirectionalJump = LedgeHang.tryDirectionalJump(character, "up")
				if didDirectionalJump then
					state.stamina.current = math.max(0, state.stamina.current - (Config.LedgeHangJumpStaminaCost or 10))
					Style.addEvent(state.style, "LedgeJump", 1)
					-- Update HUD values immediately
					if state.styleScoreValue then
						state.styleScoreValue.Value = math.floor(state.style.score + 0.5)
					end
					if state.styleComboValue then
						state.styleComboValue.Value = state.style.combo or 0
					end
				end
			elseif aPressed then
				didDirectionalJump = LedgeHang.tryDirectionalJump(character, "left")
				if didDirectionalJump then
					state.stamina.current = math.max(0, state.stamina.current - (Config.LedgeHangJumpStaminaCost or 10))
					Style.addEvent(state.style, "LedgeJump", 1)
					-- Update HUD values immediately
					if state.styleScoreValue then
						state.styleScoreValue.Value = math.floor(state.style.score + 0.5)
					end
					if state.styleComboValue then
						state.styleComboValue.Value = state.style.combo or 0
					end
				end
			elseif dPressed then
				didDirectionalJump = LedgeHang.tryDirectionalJump(character, "right")
				if didDirectionalJump then
					state.stamina.current = math.max(0, state.stamina.current - (Config.LedgeHangJumpStaminaCost or 10))
					Style.addEvent(state.style, "LedgeJump", 1)
					-- Update HUD values immediately
					if state.styleScoreValue then
						state.styleScoreValue.Value = math.floor(state.style.score + 0.5)
					end
					if state.styleComboValue then
						state.styleComboValue.Value = state.style.combo or 0
					end
				end
			elseif sPressed then
				didDirectionalJump = LedgeHang.tryDirectionalJump(character, "back")
				if didDirectionalJump then
					state.stamina.current = math.max(0, state.stamina.current - (Config.LedgeHangJumpStaminaCost or 10))
					Style.addEvent(state.style, "LedgeJump", 1)
					-- Update HUD values immediately
					if state.styleScoreValue then
						state.styleScoreValue.Value = math.floor(state.style.score + 0.5)
					end
					if state.styleComboValue then
						state.styleComboValue.Value = state.style.combo or 0
					end
				end
			else
				-- No directional input, treat Space alone as W+Space (upward jump)
				didDirectionalJump = LedgeHang.tryDirectionalJump(character, "up")
				if didDirectionalJump then
					state.stamina.current = math.max(0, state.stamina.current - (Config.LedgeHangJumpStaminaCost or 10))
					Style.addEvent(state.style, "LedgeJump", 1)
					-- Update HUD values immediately
					if state.styleScoreValue then
						state.styleScoreValue.Value = math.floor(state.style.score + 0.5)
					end
					if state.styleComboValue then
						state.styleComboValue.Value = state.style.combo or 0
					end
				end
			end

			return -- Important: exit early to prevent other Space handling
		end
		-- JumpStart now plays on Humanoid.StateChanged (Jumping)
		-- If dashing or sliding, cancel those states to avoid animation overlap
		pcall(function()
			local Abilities = require(ReplicatedStorage.Movement.Abilities)
			if Abilities and Abilities.cancelDash then
				Abilities.cancelDash(character)
			end
		end)
		if state.sliding and state.slideEnd then
			state.sliding = false
			state.slideEnd()
			state.slideEnd = nil
		end
		if Zipline.isActive(character) then
			-- Jump off the zipline. Force a jump frame after detaching
			Zipline.stop(character)
			humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
			task.defer(function()
				if humanoid and humanoid.Parent then
					humanoid.Jump = true
				end
			end)
		elseif Climb.isActive(character) then
			if state.stamina.current >= Config.WallJumpStaminaCost then
				if Climb.tryHop(character) then
					state.stamina.current = math.max(0, state.stamina.current - Config.WallJumpStaminaCost)
				end
			end
		elseif VerticalClimb.isActive(character) then
			-- Handle wall jump during vertical climb - same logic as wall slide/run
			if state.stamina.current >= Config.WallJumpStaminaCost then
				-- Stop vertical climb first to prevent conflicts
				VerticalClimb.stop(character)

				-- Execute wall jump using the same system as wall slide/run
				-- Use resetMomentum=true to completely reset velocity before wall jump
				if WallJump.tryJump(character, true) then
					state.stamina.current = math.max(0, state.stamina.current - Config.WallJumpStaminaCost)
					FX.play("WallJump", character)
					-- Suppress air control briefly to prevent immediate input from reducing away impulse
					state._suppressAirControlUntil = os.clock() + (Config.WallJumpAirControlSuppressSeconds or 0.2)
				end
			end
		elseif WallRun.isActive(character) or (WallJump.isWallSliding and WallJump.isWallSliding(character)) then
			-- Hop off the wall and stop sticking
			if state.stamina.current >= Config.WallJumpStaminaCost then
				local isWallSliding = WallJump.isWallSliding and WallJump.isWallSliding(character)
				local isWallRunning = WallRun.isActive(character)

				-- If wall slide is active, use WallJump.tryJump (it handles both cases)
				if isWallSliding then
					-- Use resetMomentum=true to ensure clean wall jump from wall slide
					if WallJump.tryJump(character, true) then
						state.stamina.current = math.max(0, state.stamina.current - Config.WallJumpStaminaCost)
						FX.play("WallJump", character)
					end
				elseif isWallRunning then
					-- Only use WallRun.tryHop if not wall sliding
					if WallRun.tryHop(character) then
						state.stamina.current = math.max(0, state.stamina.current - Config.WallJumpStaminaCost)
						FX.play("WallJump", character)
						-- Suppress air control briefly to prevent immediate input from reducing away impulse
						state._suppressAirControlUntil = os.clock() + (Config.WallJumpAirControlSuppressSeconds or 0.2)
					end
				end
			end
		else
			-- Attempt vault if a low obstacle is in front
			local didVault = Abilities.tryVault(character)
			if didVault then
				FX.play("Vault", character)
				return
			end
			-- (Mantle is now automatic; Space remains reserved for walljump/vault)
			local airborne = (humanoid.FloorMaterial == Enum.Material.Air)
			if airborne then
				-- Airborne: if near wall and can enter slide immediately, prefer starting slide first and block jump until pose snaps
				if state.stamina.current >= Config.WallJumpStaminaCost then
					if WallJump.isNearWall(character) then
						-- isNearWall will start slide; rely on WallJump.tryJump to enforce animReady gating on next press
						return
					else
						-- Use resetMomentum=true to ensure clean wall jump
						if WallJump.tryJump(character, true) then
							state.stamina.current = math.max(0, state.stamina.current - Config.WallJumpStaminaCost)
							return
						end
					end
				end
				-- Double Jump: if enabled and charges remain, consume one and apply impulse
				if Config.DoubleJumpEnabled and (state.doubleJumpCharges or 0) > 0 then
					if state.stamina.current >= (Config.DoubleJumpStaminaCost or 0) then
						-- Disallow double jump during zipline/climb/active wallrun/slide
						if
							not Zipline.isActive(character)
							and not Climb.isActive(character)
							and not WallRun.isActive(character)
							and not (WallJump.isWallSliding and WallJump.isWallSliding(character))
						then
							-- Velocity: keep horizontal, set vertical to desired impulse
							local v = character.HumanoidRootPart.AssemblyLinearVelocity
							local horiz = Vector3.new(v.X, 0, v.Z)
							local vy = math.max(Config.DoubleJumpImpulse or 50, 0)
							character.HumanoidRootPart.AssemblyLinearVelocity = Vector3.new(horiz.X, vy, horiz.Z)
							-- Play optional double jump animation
							local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
							animator.Parent = humanoid
							local djAnim = Animations
								and Animations.get
								and (Animations.get("DoubleJump") or Animations.get("Jump"))
							if djAnim then
								pcall(function()
									local tr = animator:LoadAnimation(djAnim)
									if tr then
										tr.Priority = Enum.AnimationPriority.Action
										tr.Looped = false
										tr:Play(0.05, 1, 1.0)
									end
								end)
							end
							-- One-shot VFX for double jump using new FX system
							FX.playDoubleJump(character)
							-- Spend resources
							state.doubleJumpCharges = math.max(0, (state.doubleJumpCharges or 0) - 1)
							state.stamina.current =
								math.max(0, state.stamina.current - (Config.DoubleJumpStaminaCost or 0))
							-- Update style (treat as Jump event)
							Style.addEvent(state.style, "DoubleJump", 1)
							-- Signal double jump for audio
							pcall(function()
								local cs = ReplicatedStorage:FindFirstChild("ClientState")
								if not cs then
									cs = Instance.new("Folder")
									cs.Name = "ClientState"
									cs.Parent = ReplicatedStorage
								end
								local dj = cs:FindFirstChild("IsDoubleJumping")
								if not dj then
									dj = Instance.new("BoolValue")
									dj.Name = "IsDoubleJumping"
									dj.Value = false
									dj.Parent = cs
								end
								dj.Value = true
								task.delay(0.05, function()
									if dj then
										dj.Value = false
									end
								end)
							end)
							return
						end
					end
				end
			end
			-- OPTIMIZED: Bunny hop with flexible sprint requirement
			if not airborne then
				-- Check if bunny hop is allowed (with or without sprint based on config)
				local canBunnyHop = true
				if Config.BunnyHopRequireSprint ~= false then
					canBunnyHop = state.stamina.isSprinting
				end

				if canBunnyHop then
					local stacks = BunnyHop.tryApplyOnJump(character, state.momentum, state.stamina.isSprinting)
					if type(stacks) == "number" and stacks > 0 then
						Style.addEvent(state.style, "BunnyHop", stacks)
						if state.styleScoreValue then
							state.styleScoreValue.Value = math.floor(state.style.score + 0.5)
						end
						if state.styleComboValue then
							state.styleComboValue.Value = state.style.combo or 0
						end
					end
				end
			end
		end
	end

	-- Track movement keys for climb independent of camera
	if input.KeyCode == Enum.KeyCode.W then
		state.keys.W = true
	end
	if input.KeyCode == Enum.KeyCode.A then
		state.keys.A = true
	end
	if input.KeyCode == Enum.KeyCode.S then
		state.keys.S = true
	end
	if input.KeyCode == Enum.KeyCode.D then
		state.keys.D = true
	end
end)

UserInputService.InputEnded:Connect(function(input, gpe)
	if gpe then
		return
	end
	if input.KeyCode == Enum.KeyCode.LeftShift then
		state.sprintHeld = false
	end
	if input.KeyCode == Enum.KeyCode.W then
		state.keys.W = false
	end
	if input.KeyCode == Enum.KeyCode.A then
		state.keys.A = false
	end
	if input.KeyCode == Enum.KeyCode.S then
		state.keys.S = false
	end
	if input.KeyCode == Enum.KeyCode.D then
		state.keys.D = false
	end
end)

-- Continuous updates
RunService.RenderStepped:Connect(function(dt)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then
		return
	end

	-- Maintain flying state if active (prevent other systems from interfering)
	if Fly.isActive(character) then
		-- Ensure humanoid stays in physics state
		if humanoid:GetState() ~= Enum.HumanoidStateType.Physics then
			humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		end
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		humanoid.AutoRotate = false
	end

	local speed = root.AssemblyLinearVelocity.Magnitude
	if humanoid.MoveDirection.Magnitude > 0 then
		Momentum.addFromSpeed(state.momentum, speed)
	else
		Momentum.decay(state.momentum, dt)
	end

	-- Track peak height while airborne to trigger landing roll reliably (e.g., after LaunchPads)
	if humanoid.FloorMaterial == Enum.Material.Air then
		local y = root.Position.Y
		if state._peakAirY == nil or y > (state._peakAirY or -math.huge) then
			state._peakAirY = y
		end
	end

	-- Always update air animations to handle both starting and stopping
	local isInParkourAction = (
		Fly.isActive(character)
		or Climb.isActive(character)
		or WallRun.isActive(character)
		or Zipline.isActive(character)
		or VerticalClimb.isActive(character)
		or LedgeHang.isActive(character)
		or (WallJump.isWallSliding and WallJump.isWallSliding(character))
	)

	if not isInParkourAction then
		updateAirAnimation(character)
	end

	-- Style/Combo tick
	local styleCtx = {
		dt = dt,
		speed = speed,
		airborne = (humanoid.FloorMaterial == Enum.Material.Air),
		wallRun = WallRun.isActive(character),
		sliding = state.sliding,
		climbing = Climb.isActive(character),
	}

	-- Gate style by sprint requirement
	local sprintGate = true
	if Config.StyleRequireSprint then
		sprintGate = state.stamina.isSprinting == true
	end
	if sprintGate then
		Style.tick(state.style, styleCtx)
	end
	if state.styleScoreValue then
		local s = state.style.score or 0
		state.styleScoreValue.Value = math.floor((s * 100) + 0.5) / 100
	end
	if state.styleComboValue then
		state.styleComboValue.Value = state.style.combo or 0
	end
	-- Track session max combo and report when it increases
	local comboNow = state.style.combo or 0
	if comboNow > (state.maxComboSession or 0) then
		state.maxComboSession = comboNow
		pcall(function()
			MaxComboReport:FireServer(state.maxComboSession)
		end)
	end

	-- Count chained per-event actions into the combo system
	-- Dash chained into something else
	if Abilities.isDashReady and not Abilities.isDashReady() then
		-- dash just used recently, Style.addEvent("Dash") is handled when input triggers; ensure we set lastEventTick
	end
	if state.styleMultiplierValue then
		local mul = state.style.multiplier or 1
		-- Round to 2 decimals for cleaner UI/inspectors
		state.styleMultiplierValue.Value = math.floor((mul * 100) + 0.5) / 100
	end

	-- Detect multiplier break to commit and reset Style
	local prevMult = state.styleLastMult or 1
	local curMult = state.style.multiplier or 1

	-- Also commit if no style input for X seconds (inactivity), but only if a combo existed
	local commitByInactivity = false
	local timeout = Config.StyleCommitInactivitySeconds or 1.0
	if timeout > 0 and (os.clock() - (state.style.lastActiveTick or 0)) >= timeout then
		commitByInactivity = (state.style.combo or 0) > 0
	end

	if (prevMult > 1.01 and curMult <= 1.01) or commitByInactivity then
		local commitAmount = math.floor(((state.style.score or 0) * 100) + 0.5) / 100
		if commitAmount > 0 then
			pcall(function()
				StyleCommit:FireServer(commitAmount)
			end)
			-- Pulse UI signal for animation
			if state.styleCommitAmountValue then
				state.styleCommitAmountValue.Value = commitAmount
			end
			if state.styleCommitFlashValue then
				state.styleCommitFlashValue.Value = true
				task.delay(0.05, function()
					if state.styleCommitFlashValue then
						state.styleCommitFlashValue.Value = false
					end
				end)
			end
		end
		-- Reset session style
		state.style.score = 0
		state.style.combo = 0
		state.style.multiplier = 1
		state.style.flowTime = 0
		if state.styleScoreValue then
			state.styleScoreValue.Value = 0
		end
		if state.styleComboValue then
			state.styleComboValue.Value = 0
		end
		if state.styleMultiplierValue then
			state.styleMultiplierValue.Value = 1
		end
	end
	state.styleLastMult = curMult

	-- Sprinting and stamina updates (do not override WalkSpeed while sliding or crawling; Slide/Crawl manage it)
	local isCrawlingNow = (state.isCrawlingValue and state.isCrawlingValue.Value) or false
	if isCrawlingNow then
		-- Ensure sprint state is fully disabled while crawling to prevent speed ramp from fighting crawl speeds
		if state.stamina.isSprinting then
			Stamina.setSprinting(state.stamina, false)
			state._sprintRampT0 = nil
			state._sprintDecelT0 = nil
			state._sprintBaseSpeed = nil
		end
		-- Skip any WalkSpeed overrides while crawling
	end
	if not state.sliding and not isCrawlingNow then
		local isMoving = (humanoid.MoveDirection and humanoid.MoveDirection.Magnitude > 0) or false
		if state.sprintHeld and isMoving then
			if not state.stamina.isSprinting then
				if Stamina.setSprinting(state.stamina, true) then
					-- start ramp towards sprint speed
					state._sprintRampT0 = os.clock()
					state._sprintBaseSpeed = humanoid.WalkSpeed
				end
			else
				-- ramp up while holding sprint
				local t0 = state._sprintRampT0 or os.clock()
				local base = state._sprintBaseSpeed or Config.BaseWalkSpeed
				local dur = math.max(0.01, Config.SprintAccelSeconds or 0.3)
				local alpha = math.clamp((os.clock() - t0) / dur, 0, 1)
				humanoid.WalkSpeed = base + (Config.SprintWalkSpeed - base) * alpha
			end
		else
			if state.stamina.isSprinting then
				-- ramp down to base speed
				local t0 = state._sprintDecelT0 or os.clock()
				state._sprintDecelT0 = t0
				local cur = humanoid.WalkSpeed
				local dur = math.max(0.01, Config.SprintDecelSeconds or 0.2)
				local alpha = math.clamp((os.clock() - t0) / dur, 0, 1)
				humanoid.WalkSpeed = cur + (Config.BaseWalkSpeed - cur) * alpha
				if alpha >= 1 then
					Stamina.setSprinting(state.stamina, false)
					state._sprintRampT0 = nil
					state._sprintDecelT0 = nil
					state._sprintBaseSpeed = nil
				end
			else
				-- ensure at base
				humanoid.WalkSpeed = Config.BaseWalkSpeed
				state._sprintRampT0 = nil
				state._sprintDecelT0 = nil
				state._sprintBaseSpeed = nil
			end
		end
	end

	-- Stamina gate: regen when on ground OR touching any part with attribute Stamina=true (collidable or not)
	local allowRegen = (humanoid.FloorMaterial ~= Enum.Material.Air)
	if state.staminaTouchCount and state.staminaTouchCount > 0 then
		allowRegen = true
	else
		local root = character:FindFirstChild("HumanoidRootPart")
		if root then
			local overlapParams = OverlapParams.new()
			overlapParams.FilterType = Enum.RaycastFilterType.Exclude
			overlapParams.FilterDescendantsInstances = { character }
			overlapParams.RespectCanCollide = false
			local expand = Vector3.new(2, 3, 2)
			local parts =
				workspace:GetPartBoundsInBox(root.CFrame, (root.Size or Vector3.new(2, 2, 1)) + expand, overlapParams)
			local CollectionService = game:GetService("CollectionService")
			for _, p in ipairs(parts) do
				if p and p:IsA("BasePart") and CollectionService:HasTag(p, "Stamina") then
					allowRegen = true
					break
				end
			end
		end
	end
	local stillSprinting
	do
		local _cur, s = Stamina.tickWithGate(
			state.stamina,
			dt,
			allowRegen,
			(humanoid.MoveDirection and humanoid.MoveDirection.Magnitude > 0)
		)
		stillSprinting = s
	end
	if not state.sliding and not isCrawlingNow then
		if not stillSprinting and humanoid.WalkSpeed ~= Config.BaseWalkSpeed then
			humanoid.WalkSpeed = Config.BaseWalkSpeed
		end
	end

	-- Audio managed by AudioManager.client.lua

	-- Wall slide stamina drain (half sprint rate) while active
	if WallJump.isWallSliding and WallJump.isWallSliding(character) then
		local drain = (Config.WallSlideDrainPerSecond or (Config.SprintDrainPerSecond * 0.5)) * dt
		state.stamina.current = math.max(0, state.stamina.current - drain)
		if state.stamina.current <= 0 then
			-- stop slide when out of stamina
			if WallJump.stopSlide then
				WallJump.stopSlide(character)
			end
		end
	end

	-- Publish client state for HUD
	if state.staminaValue then
		state.staminaValue.Value = state.stamina.current
	end
	if state.speedValue then
		state.speedValue.Value = speed
	end
	if state.momentumValue then
		state.momentumValue.Value = state.momentum.value or 0
	end
	if state.isSprintingValue then
		state.isSprintingValue.Value = state.stamina.isSprinting
	end
	if state.isSlidingValue then
		state.isSlidingValue.Value = state.sliding
	end
	-- Do not overwrite IsCrawling here; Crawl system manages this BoolValue

	-- Check if crawl should be activated automatically (e.g., after slide with no clearance)
	if state.shouldActivateCrawlValue and state.shouldActivateCrawlValue.Value then
		state.shouldActivateCrawlValue.Value = false
		if not state.crawling then
			-- Activate crawl mode automatically
			state.crawling = true
			-- Also trigger the crawl system if available
			-- Note: Crawl is a local script, not a module, so we can't require it directly
			-- The crawl state is already set to true, which should trigger the crawl system
		end
	end
	if state.isAirborneValue then
		state.isAirborneValue.Value = (humanoid.FloorMaterial == Enum.Material.Air)
	end
	if state.isWallRunningValue then
		state.isWallRunningValue.Value = WallRun.isActive(character)
	end
	if state.isWallSlidingValue then
		state.isWallSlidingValue.Value = (WallJump.isWallSliding and WallJump.isWallSliding(character)) or false
	end
	if state.isClimbingValue then
		state.isClimbingValue.Value = Climb.isActive(character)
	end
	if state.isZipliningValue then
		state.isZipliningValue.Value = Zipline.isActive(character)
	end
	if state.isLedgeHangingValue then
		state.isLedgeHangingValue.Value = LedgeHang.isActive(character)
	end

	-- Note: Powerup system effects are automatically reflected in the local ClientState values

	-- Publish combo timeout progress for HUD
	if state.styleComboValue and state.styleComboTimeRemaining and state.styleComboTimeMax then
		local timeout = Config.StyleBreakTimeoutSeconds or 3
		state.styleComboTimeMax.Value = timeout
		local combo = state.style.combo or 0
		if combo > 0 then
			local remain = math.max(0, timeout - (os.clock() - (state.style.lastActiveTick or 0)))
			state.styleComboTimeRemaining.Value = remain
		else
			state.styleComboTimeRemaining.Value = 0
		end
	end

	-- (Head/camera alignment handled by HeadTracking.client.lua)
	-- Show climb prompt when near climbable and with enough stamina
	if state.climbPromptValue then
		local show = ""
		if (not Zipline.isActive(character)) and Zipline.isNear(character) then
			show = "Press E to Zipline"
		else
			local nearClimbable = (not Climb.isActive(character)) and Climb.isNearClimbable(character)
			if nearClimbable and state.stamina.current >= Config.ClimbMinStamina then
				show = "Press E to Climb"
			end
		end
		if show ~= "" then
			state.climbPromptValue.Value = show
		else
			state.climbPromptValue.Value = ""
		end
	end
	-- Climb state and stamina drain
	local move = { h = 0, v = 0 }
	if Climb.isActive(character) then
		-- WASD strictly by keys, relative to character orientation but not camera
		move.h = (state.keys.D and 1 or 0) - (state.keys.A and 1 or 0)
		move.v = (state.keys.W and 1 or 0) - (state.keys.S and 1 or 0)

		-- Update climb animation based on movement direction
		local moveDirection = Vector3.new(move.h, move.v, 0)
		updateClimbAnimation(character, moveDirection)

		local ok = Climb.maintain(character, move)
		-- Drain stamina every frame while active (even without movement)
		state.stamina.current = state.stamina.current - (Config.ClimbStaminaDrainPerSecond * dt)
		if state.stamina.current <= 0 then
			state.stamina.current = 0
			Climb.stop(character)
			cleanupClimbAnimation(character)
		end
		-- Disable sprint while climbing
		if state.stamina.isSprinting then
			Stamina.setSprinting(state.stamina, false)
			humanoid.WalkSpeed = Config.BaseWalkSpeed
		end
	end

	-- Vertical climb: sprinting straight into a wall grants a brief upward run
	if humanoid.FloorMaterial == Enum.Material.Air and state.sprintHeld and state.stamina.isSprinting then
		if VerticalClimb.isActive(character) then
			-- Check if other abilities are active before maintaining vertical climb
			local cs = ReplicatedStorage:FindFirstChild("ClientState")
			local isVaulting = cs and cs:FindFirstChild("IsVaulting") and cs:FindFirstChild("IsVaulting").Value
			local isMantling = cs and cs:FindFirstChild("IsMantling") and cs:FindFirstChild("IsMantling").Value

			-- Don't maintain vertical climb if other abilities are active
			if
				not (
					isVaulting
					or isMantling
					or LedgeHang.isActive(character)
					or Climb.isActive(character)
					or WallRun.isActive(character)
					or Grapple.isActive(character)
				)
			then
				VerticalClimb.maintain(character, dt)
			else
				-- Stop vertical climb if other abilities are active
				VerticalClimb.stop(character)
			end
		else
			-- Stop conflicting animations before starting vertical climb
			stopConflictingAnimations(character, "verticalclimb")
			VerticalClimb.tryStart(character)
		end
	end

	-- Wall run requires sprint, movement, stamina, airborne, and no climb. Do not break wall slide unless wallrun actually starts.
	local wantWallRun = (
		not Zipline.isActive(character)
		and state.sprintHeld
		and state.stamina.isSprinting
		and (humanoid.MoveDirection and humanoid.MoveDirection.Magnitude > 0)
		and state.stamina.current > 0
		and humanoid.FloorMaterial == Enum.Material.Air
		and not Climb.isActive(character)
	)
	if wantWallRun then
		if WallRun.isActive(character) then
			WallRun.maintain(character)
		else
			-- Stop conflicting animations before starting wallrun
			stopConflictingAnimations(character, "wallrun")
			local started = WallRun.tryStart(character)
			if started and (WallJump.isWallSliding and WallJump.isWallSliding(character)) then
				WallJump.stopSlide(character)
			end
		end
	else
		if WallRun.isActive(character) then
			WallRun.stop(character)
		end
		-- Reset wall jump memory on ground so player can reuse same wall after landing
		if humanoid.FloorMaterial ~= Enum.Material.Air then
			WallMemory.clear(character)
		end
	end

	-- Maintain Ledge Hanging
	if LedgeHang.isActive(character) then
		-- Handle stamina drain
		local drainRate = Config.LedgeHangStaminaDrainPerSecond or 5
		state.stamina.current = math.max(0, state.stamina.current - drainRate * dt)

		-- Auto-release if no stamina
		if state.stamina.current <= 0 then
			LedgeHang.stop(character, false) -- false = stamina depletion release
			-- Set a temporary cooldown to prevent immediate re-hang due to stamina depletion
			state._staminaDepletedHangCooldown = os.clock() + (Config.LedgeHangStaminaDepletionCooldown or 2.0)
		else
			-- Maintain hanging position with horizontal movement
			LedgeHang.maintain(character, humanoid.MoveDirection)
		end
	end

	-- Auto-detect tagged ledges nearby and start hang when close
	-- But only if we have sufficient stamina (prevent infinite loops when stamina is depleted)
	local canAutoHang = state.stamina.current >= (Config.LedgeHangMinStamina or 10)
	local hasStaminaCooldown = state._staminaDepletedHangCooldown and os.clock() < state._staminaDepletedHangCooldown

	if Config.LedgeTagAutoEnabled and not LedgeHang.isActive(character) and canAutoHang and not hasStaminaCooldown then
		local root = character:FindFirstChild("HumanoidRootPart")
		if root then
			local range = Config.LedgeTagAutoHangRange or 3.5
			local vertRange = Config.LedgeTagAutoVerticalRange or 4.0
			local nearest, nearestDist, nearestTopY

			-- Pre-check: avoid processing ledges that are likely on cooldown
			local recentLedgeCooldowns = {}
			pcall(function()
				local rs = game:GetService("ReplicatedStorage")
				local cs = rs:FindFirstChild("ClientState")
				if cs then
					-- This is a simplified check - we'll let LedgeHang module handle the detailed cooldown logic
					local lastHangTime = cs:FindFirstChild("LastLedgeHangTime")
					if lastHangTime and lastHangTime.Value > os.clock() then
						-- If we just released a ledge, reduce detection frequency
						local timeSinceRelease = os.clock() - (lastHangTime.Value - 0.3)
						if timeSinceRelease < 0.1 then -- Only check every 0.1 seconds for first 0.1 seconds after release
							return
						end
					end
				end
			end)

			for _, inst in ipairs(CollectionService:GetTagged(Config.LedgeTagName or "Ledge")) do
				if inst:IsA("BasePart") and inst.Parent then
					-- Create expanded AABB around the part
					local partMin = inst.Position - inst.Size * 0.5
					local partMax = inst.Position + inst.Size * 0.5
					-- Expand by detection range (except Y which uses separate vertical range)
					local expandedMin = Vector3.new(partMin.X - range, partMin.Y - vertRange, partMin.Z - range)
					local expandedMax = Vector3.new(partMax.X + range, partMax.Y + vertRange, partMax.Z + range)

					-- Check if player is within expanded zone
					local playerPos = root.Position
					local withinZone = (
						playerPos.X >= expandedMin.X
						and playerPos.X <= expandedMax.X
						and playerPos.Y >= expandedMin.Y
						and playerPos.Y <= expandedMax.Y
						and playerPos.Z >= expandedMin.Z
						and playerPos.Z <= expandedMax.Z
					)

					if withinZone then
						-- Calculate distance from player to part surface (not center)
						local clampedX = math.clamp(playerPos.X, partMin.X, partMax.X)
						local clampedY = math.clamp(playerPos.Y, partMin.Y, partMax.Y)
						local clampedZ = math.clamp(playerPos.Z, partMin.Z, partMax.Z)
						local surfacePoint = Vector3.new(clampedX, clampedY, clampedZ)
						local distToSurface = (playerPos - surfacePoint).Magnitude

						-- Use top Y for ledge attachment
						local topY = (inst.Position + inst.CFrame.UpVector * (inst.Size.Y * 0.5)).Y

						if (not nearestDist) or distToSurface < nearestDist then
							nearest, nearestDist, nearestTopY = inst, distToSurface, topY
						end
					end
				end
			end
			if nearest then
				local faceAttr = (typeof(nearest.GetAttribute) == "function") and nearest:GetAttribute("LedgeFace")
					or nil
				local fakeHit
				if type(faceAttr) == "string" then
					local lv = nearest.CFrame.LookVector
					local rv = nearest.CFrame.RightVector
					local normal
					local half
					local f = string.lower(faceAttr)
					if f == "front" then
						normal = -lv
						half = (nearest.Size.Z or 0) * 0.5
					elseif f == "back" then
						normal = lv
						half = (nearest.Size.Z or 0) * 0.5
					elseif f == "left" then
						normal = -rv
						half = (nearest.Size.X or 0) * 0.5
					elseif f == "right" then
						normal = rv
						half = (nearest.Size.X or 0) * 0.5
					end
					if normal and half then
						local p = nearest.Position + normal * half
						fakeHit = { Position = Vector3.new(p.X, nearestTopY, p.Z), Normal = normal, Instance = nearest }
					end
				end
				if not fakeHit then
					local toPlayer = (root.Position - nearest.Position)
					local toPlayerDir = (toPlayer.Magnitude > 0) and toPlayer.Unit or nearest.CFrame.LookVector
					local right = nearest.CFrame.RightVector
					local look = nearest.CFrame.LookVector
					local candidates = {
						{ n = right, half = (nearest.Size.X or 0) * 0.5, axis = "X" },
						{ n = -right, half = (nearest.Size.X or 0) * 0.5, axis = "X" },
						{ n = look, half = (nearest.Size.Z or 0) * 0.5, axis = "Z" },
						{ n = -look, half = (nearest.Size.Z or 0) * 0.5, axis = "Z" },
					}
					local best = candidates[1]
					local bestDot = -1e9
					for _, c in ipairs(candidates) do
						local d = c.n:Dot(toPlayerDir)
						local lateralPenalty = 0
						if c.axis == "X" then
							local dz = math.abs(nearest.Position.Z - root.Position.Z)
							if dz > (Config.LedgeTagFaceLateralMargin or 0.75) then
								lateralPenalty = -0.25
							end
						else
							local dx = math.abs(nearest.Position.X - root.Position.X)
							if dx > (Config.LedgeTagFaceLateralMargin or 0.75) then
								lateralPenalty = -0.25
							end
						end
						local score = d + lateralPenalty
						if score > bestDot then
							bestDot = score
							best = c
						end
					end
					local facePoint = nearest.Position + best.n * best.half
					fakeHit = {
						Position = Vector3.new(facePoint.X, nearestTopY, facePoint.Z),
						Normal = best.n,
						Instance = nearest,
					}
				end
				-- Check stamina before attempting tagged ledge hang
				local ok = false
				if
					state.stamina.current >= (Config.LedgeHangMinStamina or 10)
					and not (state._staminaDepletedHangCooldown and os.clock() < state._staminaDepletedHangCooldown)
				then
					-- Stop conflicting animations before starting ledge hang
					stopConflictingAnimations(character, "ledgehang")
					ok = LedgeHang.tryStartFromMantleData(character, fakeHit, nearestTopY)
				end
				if Config.DebugLedgeHang then
					print(
						string.format(
							"[AutoLedge] candidate='%s' dist=%.2f topY=%.2f ok=%s (faceAttr=%s)",
							nearest.Name,
							nearestDist or -1,
							nearestTopY or -1,
							tostring(ok),
							tostring(faceAttr)
						)
					)
				end
			end
		end
	end

	-- Check if wallslide is suppressed (e.g., during ledge hang side jumps)
	local wallslideSuppressed = false
	pcall(function()
		local cs = ReplicatedStorage:FindFirstChild("ClientState")
		local suppressFlag = cs and cs:FindFirstChild("SuppressWallSlide")
		local suppressUntil = cs and cs:FindFirstChild("SuppressWallSlideUntil")
		if (suppressFlag and suppressFlag.Value) or (suppressUntil and suppressUntil.Value > os.clock()) then
			wallslideSuppressed = true
			-- Stop any active wallslide immediately
			if WallJump.isWallSliding and WallJump.isWallSliding(character) then
				WallJump.stopSlide(character)
			end
		end
	end)

	-- Maintain Wall Slide when airborne near walls (independent of sprint)
	if
		humanoid.FloorMaterial == Enum.Material.Air
		and not Zipline.isActive(character)
		and not Climb.isActive(character)
		and not LedgeHang.isActive(character)
		and not (state.isMantlingValue and state.isMantlingValue.Value)
		and not wallslideSuppressed
	then
		-- Do not start slide if sprinting (wallrun has priority) or if out of stamina
		local suppressUntil = state.wallSlideSuppressUntil or 0
		local suppressedFlag = (state.wallSlideSuppressed == true)
		local canStartSlide = (not suppressedFlag) and (os.clock() >= suppressUntil)
		-- Extra gating: only attempt slide proximity if there is no mantle candidate ahead
		local blockByMantleCandidate = false
		if Abilities.isMantleCandidate then
			blockByMantleCandidate = Abilities.isMantleCandidate(character) == true
		end
		-- Extra: while mantling or within a small window after, completely disable isNearWall to avoid edge flickers on curved surfaces
		if not state.sprintHeld and state.stamina.current > 0 and canStartSlide and not blockByMantleCandidate then
			-- Proximity check will internally start/stop slide as needed
			local wasSliding = WallJump.isWallSliding and WallJump.isWallSliding(character)
			WallJump.isNearWall(character)
			local isNowSliding = WallJump.isWallSliding and WallJump.isWallSliding(character)

			-- Stop conflicting animations if wallslide just started
			if not wasSliding and isNowSliding then
				stopConflictingAnimations(character, "wallslide")
			end
		end
		-- If slide is active, maintain physics only if we have stamina; otherwise stop
		if WallJump.isWallSliding and WallJump.isWallSliding(character) then
			if state.stamina.current > 0 then
				WallJump.updateWallSlide(character, dt)
			else
				WallJump.stopSlide(character)
			end
		end
	end

	-- Update wallslide state (re-enable when touching ground) - MOVED OUTSIDE airborne condition
	WallJump.updateWallslideState(character)

	-- Apply Quake/CS-style air control after other airborne logic
	local acUnlock = (
		state.wallAttachLockedUntil
		and (
			state.wallAttachLockedUntil
			- (Config.WallRunLockAfterWallJumpSeconds or 0.35)
			+ (Config.AirControlUnlockAfterWallJumpSeconds or 0.12)
		)
	) or 0
	if (not state.wallAttachLockedUntil) or (os.clock() >= acUnlock) then
		local allowAC = true
		-- Don't apply air control if flying
		if Fly.isActive(character) then
			allowAC = false
		elseif state._suppressAirControlUntil and os.clock() < state._suppressAirControlUntil then
			allowAC = false
		end
		if allowAC then
			AirControl.apply(character, dt)
		end
	end

	-- Global unfreeze/cleanup watchdog: ensure AutoRotate and animations aren't left frozen after actions
	local anyActionActive = false
	if WallRun.isActive(character) then
		anyActionActive = true
	end
	if WallJump.isWallSliding and WallJump.isWallSliding(character) then
		anyActionActive = true
	end
	if Climb.isActive(character) then
		anyActionActive = true
	end
	if Zipline.isActive(character) then
		anyActionActive = true
	end
	if state.isMantlingValue and state.isMantlingValue.Value then
		anyActionActive = true
	end
	if not anyActionActive then
		-- Don't restore state if flying is active
		if Fly.isActive(character) then
			-- Keep flying state intact
		else
			-- Safety: ensure collisions are restored after any action that might have disabled them
			pcall(function()
				local Abilities = require(ReplicatedStorage.Movement.Abilities)
				if Abilities and Abilities.ensureCollisions then
					Abilities.ensureCollisions(character)
				end
			end)
			-- Restore autorotate if disabled by previous action
			if humanoid.AutoRotate == false then
				humanoid.AutoRotate = true
			end
			-- Restore safe humanoid state from RunningNoPhysics if not in any action
			local hs = humanoid:GetState()
			if hs == Enum.HumanoidStateType.RunningNoPhysics then
				if humanoid.FloorMaterial == Enum.Material.Air then
					humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
				else
					humanoid:ChangeState(Enum.HumanoidStateType.Running)
				end
			end
		end
		-- Stop frozen zero-speed tracks if any
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			local tracks = animator:GetPlayingAnimationTracks()
			for _, tr in ipairs(tracks) do
				local ok, spd = pcall(function()
					return tr.Speed
				end)
				if ok and (spd == 0) then
					pcall(function()
						tr:Stop(0.1)
					end)
				end
			end
		end
	end

	-- Auto-vault while sprinting towards low obstacle
	if Config.VaultEnabled ~= false then
		local isMovingForward = humanoid.MoveDirection.Magnitude > 0.1
		local isGrounded = (humanoid.FloorMaterial ~= Enum.Material.Air)
		local notWallRunning = not WallRun.isActive(character)
		if isGrounded and isMovingForward and state.stamina.isSprinting and notWallRunning then
			if Abilities.tryVault(character) then
				Style.addEvent(state.style, "Vault", 1)
			end
		elseif WallRun.isActive(character) then
			-- Debug: Vault blocked due to wallrun
			-- print("[ParkourController] Vault blocked - currently wallrunning")
		end
	end

	-- Auto-mantle: when airborne, moving forward (by input or velocity), near a ledge at mantle height
	if Config.MantleEnabled ~= false then
		local airborne = (humanoid.FloorMaterial == Enum.Material.Air)
		local movingForward = humanoid.MoveDirection.Magnitude > 0.1
		-- Allow mantle to trigger purely from velocity (e.g., after walljumps without input)
		local movingByVelocity = false
		do
			local root = character:FindFirstChild("HumanoidRootPart")
			if root then
				local v = root.AssemblyLinearVelocity
				local horiz = Vector3.new(v.X, 0, v.Z)
				if horiz.Magnitude > 2 then
					local fwd = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
					if fwd.Magnitude > 0.01 then
						movingByVelocity = (fwd.Unit:Dot(horiz.Unit) > 0.3)
					end
				end
			end
		end
		local movingAny = movingForward or movingByVelocity
		-- Do not mantle during incompatible states
		if
			airborne
			and movingAny
			and (not Zipline.isActive(character))
			and (not Climb.isActive(character))
			and (not LedgeHang.isActive(character))
			and (not WallRun.isActive(character))
		then
			if state.stamina.current >= (Config.MantleStaminaCost or 0) then
				local didMantle = false
				local didHang = false

				-- Avoid conflicting with recent successful mantles (ledge hang has its own per-wall cooldown)
				local mantleCooldown = Config.MantleLedgeHangCooldown or 0.5
				local timeSinceMantle = os.clock() - state._lastMantleTime

				-- Check for minimum global cooldown after directional jumps (prevents immediate re-hang)
				local hasMinimumGlobalCooldown = false
				pcall(function()
					local rs = game:GetService("ReplicatedStorage")
					local cs = rs:FindFirstChild("ClientState")
					if cs then
						local lastHangTimeValue = cs:FindFirstChild("LastLedgeHangTime")
						if lastHangTimeValue and lastHangTimeValue.Value > os.clock() then
							hasMinimumGlobalCooldown = true
						end
					end
				end)

				-- Only check mantle cooldown and minimum global cooldown (per-wall cooldown handled in LedgeHang.lua)
				if timeSinceMantle >= mantleCooldown and not hasMinimumGlobalCooldown then
					local root = character:FindFirstChild("HumanoidRootPart")
					if root and Abilities.detectLedgeForMantle then
						local ledgeOk, hitRes, topY = Abilities.detectLedgeForMantle(root)
						if ledgeOk then
							-- Determine if we should mantle or hang based on clearance
							local toWall = (hitRes.Position - root.Position)
							local forwardDir = Vector3.new(toWall.X, 0, toWall.Z)
							if forwardDir.Magnitude > 0.01 then
								forwardDir = forwardDir.Unit
							else
								forwardDir = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
							end

							-- Check clearance to decide between mantle and hang
							local hasClearance = hasEnoughClearanceAbove(root, topY, forwardDir, hitRes.Position)

							-- Always try mantle first regardless of clearance
							-- This ensures proper velocity/facing/approach checks
							didMantle = Abilities.tryMantle(character)

							-- If mantle failed AND there's insufficient clearance, try ledge hang
							-- But only if we have enough stamina to sustain the hang and no recent stamina depletion
							local minStaminaForHang = Config.LedgeHangMinStamina or 10
							local hasStaminaDepletionCooldown = state._staminaDepletedHangCooldown
								and os.clock() < state._staminaDepletedHangCooldown
							local hasEnoughStamina = state.stamina.current >= minStaminaForHang

							if
								not didMantle
								and Config.LedgeHangEnabled
								and not hasClearance
								and hasEnoughStamina
								and not hasStaminaDepletionCooldown
							then
								-- Stop conflicting animations before starting ledge hang
								stopConflictingAnimations(character, "ledgehang")
								didHang = LedgeHang.tryStartFromMantleData(character, hitRes, topY)
								if didHang then
									state._lastLedgeHangTime = os.clock()
								end
							end

							-- If mantle failed for other reasons, mark time to prevent spam
							if not didMantle and not didHang then
								state._lastMantleTime = os.clock()
							end
						end
					end
				end

				if didMantle then
					state._lastMantleTime = os.clock()
					state.stamina.current = math.max(0, state.stamina.current - (Config.MantleStaminaCost or 0))
					Style.addEvent(state.style, "Mantle", 1)
					-- Suppress wall slide immediately and for an extra window; clear after grounded confirm
					state.wallSlideSuppressed = true
					state.wallSlideSuppressUntil = os.clock() + (Config.MantleWallSlideSuppressSeconds or 0.6)
					-- Stop any current wall slide / wall run to avoid conflicts
					if WallJump.isWallSliding and WallJump.isWallSliding(character) then
						WallJump.stopSlide(character)
					end
					if WallRun.isActive(character) then
						WallRun.stop(character)
					end
					-- HUD flag (optional)
					if state.isMantlingValue then
						state.isMantlingValue.Value = true
					end
				elseif didHang then
					-- Minimal stamina cost for hanging
					local hangCost = Config.LedgeHangStaminaCost or 5
					state.stamina.current = math.max(0, state.stamina.current - hangCost)
					-- Stop conflicting movements
					if WallJump.isWallSliding and WallJump.isWallSliding(character) then
						WallJump.stopSlide(character)
					end
					if WallRun.isActive(character) then
						WallRun.stop(character)
					end
				end
			end
		elseif WallRun.isActive(character) then
			-- Debug: Mantle blocked due to wallrun
			-- print("[ParkourController] Mantle blocked - currently wallrunning")
		end
	end
end)

-- Per-frame updates for added systems

RunService.RenderStepped:Connect(function(dt)
	local character = player.Character
	if character then
		Grapple.update(character, dt)
		-- (rope swing removed)
	end
end)
-- Chain-sensitive action events to Style
local function onWallRunStart()
	Style.addEvent(state.style, "WallRun", 1)
end

-- Hook wallrun transitions by polling state change
do
	local wasActive = false
	RunService.RenderStepped:Connect(function()
		local character = player.Character
		if not character then
			return
		end
		if state.wallAttachLockedUntil and os.clock() < state.wallAttachLockedUntil then
			wasActive = false
			return
		end
		local nowActive = WallRun.isActive(character)
		if nowActive and not wasActive then
			maybeConsumePadThenBump("WallRun")
		end
		wasActive = nowActive
	end)
end

-- Dash is fired in InputBegan when Abilities.tryDash succeeds; count it as chained
-- We emit the Style event immediately after a successful dash
do
	local oldTryDash = Abilities.tryDash
	Abilities.tryDash = function(character)
		local ok = oldTryDash(character)
		if ok then
			maybeConsumePadThenBump("Dash")
		end
		return ok
	end
end

-- Wall jump: count each successful tryJump
do
	local oldTryJump = WallJump.tryJump
	if oldTryJump then
		WallJump.tryJump = function(character)
			local ok = oldTryJump(character)
			if ok then
				-- Lock wall attach for a short window to preserve jump impulse when still facing the wall
				state.wallAttachLockedUntil = os.clock() + (Config.WallRunLockAfterWallJumpSeconds or 0.25)
				-- Removed camera nudge on walljump per request
				maybeConsumePadThenBump("WallJump")
				-- Suppress air control briefly to prevent immediate input from reducing away impulse
				state._suppressAirControlUntil = os.clock() + (Config.WallJumpAirControlSuppressSeconds or 0.2)
			end
			return ok
		end
	end
end

-- During lock window prevent wallrun/wallslide from being started
RunService.RenderStepped:Connect(function()
	if state.wallAttachLockedUntil and os.clock() < state.wallAttachLockedUntil then
		-- Stop active wallrun
		local character = player.Character
		if character and WallRun.isActive and WallRun.isActive(character) then
			WallRun.stop(character)
		end
		-- Optionally suppress air control override for a brief moment after walljump
		local lock = (Config.WallRunLockAfterWallJumpSeconds or 0.35)
		if lock > 0 then
			-- NOP: AirControl.apply uses MoveDirection/camera; we rely on our short lock and fixed velocity to dominate initial frames
		end
	end
	-- Mantle grounded confirmation: only clear suppression after being grounded for X seconds
	local groundedConfirm = Config.MantleGroundedConfirmSeconds or 0.2
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local airborne = (humanoid.FloorMaterial == Enum.Material.Air)
		if not airborne then
			-- Start or continue grounded timer
			state._mantleGroundedSince = state._mantleGroundedSince or os.clock()
			local okToClear = (os.clock() - (state._mantleGroundedSince or 0)) >= groundedConfirm
			if okToClear then
				state.wallSlideSuppressUntil = 0
				state.wallSlideSuppressed = false
			end
		else
			-- Reset timer while airborne
			state._mantleGroundedSince = nil
		end
	end
end)

-- Grounded dwell confirmation for refilling double jump and air dash
RunService.RenderStepped:Connect(function()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then
		return
	end
	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
	local inSpecial = false
	do
		local cs = ReplicatedStorage:FindFirstChild("ClientState")
		local isMantling = cs and cs:FindFirstChild("IsMantling")
		local isVaulting = cs and cs:FindFirstChild("IsVaulting")
		inSpecial = (
			WallRun.isActive(character)
			or (WallJump.isWallSliding and WallJump.isWallSliding(character))
			or Climb.isActive(character)
			or Zipline.isActive(character)
			or (isMantling and isMantling.Value)
			or (isVaulting and isVaulting.Value)
		)
	end
	if grounded and not inSpecial then
		-- Track when we first touched ground and our landing velocity
		if not state._groundedSince then
			state._groundedSince = os.clock()
			-- Capture velocity when we first touch ground to detect legitimate falls
			local velocity = root.AssemblyLinearVelocity
			state._landingVelocityY = velocity.Y
		end

		-- Determine appropriate dwell time based on landing conditions
		local baseDwell = Config.GroundedRefillDwellSeconds or 0.01
		local fastDwell = Config.GroundedRefillFastDwellSeconds or 0.01
		local minFallSpeed = Config.GroundedRefillMinFallSpeed or 5

		-- Use fast reset if we had significant downward velocity when landing (legitimate fall)
		local hadSignificantFall = (state._landingVelocityY or 0) <= -minFallSpeed
		local dwellTime = hadSignificantFall and fastDwell or baseDwell

		if not state._groundResetDone and (os.clock() - (state._groundedSince or 0)) >= dwellTime then
			local Abilities = require(ReplicatedStorage.Movement.Abilities)
			if Abilities and Abilities.resetAirDashCharges then
				Abilities.resetAirDashCharges(character)
			end
			local maxDJ = Config.DoubleJumpMax or 0
			if Config.DoubleJumpEnabled and maxDJ > 0 then
				state.doubleJumpCharges = maxDJ
			else
				state.doubleJumpCharges = 0
			end
			state._groundResetDone = true
		end
	else
		state._groundedSince = nil
		state._groundResetDone = false
		state._landingVelocityY = nil
	end
end)

-- Wall slide counts only when chained; we signal start when sliding becomes active
do
	if WallJump.isWallSliding then
		local prev = false
		local nudgeT0 = 0
		RunService.RenderStepped:Connect(function()
			local character = player.Character
			if not character then
				return
			end
			if state.wallAttachLockedUntil and os.clock() < state.wallAttachLockedUntil then
				prev = false
				return
			end
			local active = WallJump.isWallSliding(character) or false
			if active and not prev then
				nudgeT0 = os.clock()
			end
			-- (camera nudge during wall slide removed)
			prev = active
		end)
	end
end

-- Pad trigger from server; do NOT bump combo immediately. Only make it eligible for chaining.
PadTriggered.OnClientEvent:Connect(function(newVel)
	-- Client-side application to ensure impulse even if Touched misses a frame
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root and typeof(newVel) == "Vector3" then
		if humanoid then
			pcall(function()
				humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
			end)
		end
		pcall(function()
			root.CFrame = root.CFrame + Vector3.new(0, 0.05, 0)
		end)
		root.AssemblyLinearVelocity = newVel
	end
	-- Mark as eligible for chaining
	state.pendingPadTick = os.clock()
end)

-- Apply climb and fly velocities before physics integrates gravity
RunService.Stepped:Connect(function(_time, dt)
	local character = player.Character
	if not character then
		return
	end
	
	-- Apply flying first (highest priority)
	if Fly.isActive(character) then
		Fly.update(character, dt)
		return
	end
	
	-- Apply zipline/ climb velocities before physics
	if Zipline.isActive(character) then
		Zipline.maintain(character, dt)
		return
	end
	if not Climb.isActive(character) then
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return
	end

	local move = { h = 0, v = 0 }
	move.h = (state.keys.D and 1 or 0) - (state.keys.A and 1 or 0)
	move.v = (state.keys.W and 1 or 0) - (state.keys.S and 1 or 0)
	Climb.maintain(character, move)
end)
