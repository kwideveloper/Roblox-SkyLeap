-- Bunny hop mechanic: perfect jump right after landing grants speed and momentum boost
-- PostSimulation reinforcement: Roblox Humanoid/controller often overwrites horizontal velocity
-- on the jump frame; reapplying after physics matches common fixes (see devforum bhop threads).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Movement.Config)
local Momentum = require(ReplicatedStorage.Movement.Momentum)

local BunnyHop = {}

local perCharacter = {}

local function getParts(character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return root, humanoid
end

local function ensureState(character)
	perCharacter[character] = perCharacter[character]
		or { stacks = 0, lastLandTick = 0, conn = nil, landWindowActive = false, postAssistConn = nil }
	return perCharacter[character]
end

local function stopPostAssist(state)
	if state.postAssistConn then
		state.postAssistConn:Disconnect()
		state.postAssistConn = nil
	end
end

local function wasAirborneState(old)
	return old == Enum.HumanoidStateType.Freefall
		or old == Enum.HumanoidStateType.Jumping
		or old == Enum.HumanoidStateType.FallingDown
end

local function shouldOpenLandWindow(old, new)
	if not wasAirborneState(old) then
		return false
	end
	return new == Enum.HumanoidStateType.Landed or new == Enum.HumanoidStateType.Running
end

local function openLandWindow(state, character)
	state.lastLandTick = os.clock()
	state.landWindowActive = true
	local thisLand = state.lastLandTick
	task.delay((Config.BunnyHopWindowSeconds or 0.12) + 0.02, function()
		if state and perCharacter[character] and state.lastLandTick == thisLand and state.landWindowActive then
			state.stacks = 0
			state.landWindowActive = false
		end
	end)
end

function BunnyHop.setup(character)
	local state = ensureState(character)
	local _root, humanoid = getParts(character)
	if not humanoid then
		return
	end
	if state.conn then
		state.conn:Disconnect()
		state.conn = nil
	end
	stopPostAssist(state)
	state.stacks = 0
	state.lastLandTick = 0
	state.landWindowActive = false
	state.conn = humanoid.StateChanged:Connect(function(old, new)
		if shouldOpenLandWindow(old, new) then
			openLandWindow(state, character)
		end
	end)
	-- First grounded frame: treat as a fresh landing so the first timed jump can start a chain (spawn / reset).
	task.defer(function()
		if not character.Parent then
			return
		end
		local s = perCharacter[character]
		local _, hum = getParts(character)
		if s and hum and hum.FloorMaterial ~= Enum.Material.Air then
			openLandWindow(s, character)
		end
	end)
end

function BunnyHop.teardown(character)
	local state = perCharacter[character]
	if not state then
		return
	end
	if state.conn then
		state.conn:Disconnect()
		state.conn = nil
	end
	stopPostAssist(state)
	perCharacter[character] = nil
end

function BunnyHop.resetStacks(character)
	local state = ensureState(character)
	state.stacks = 0
end

-- Call on Space pressed while grounded; applies boost if within timing window
function BunnyHop.tryApplyOnJump(character, momentumState, isSprinting)
	local state = ensureState(character)
	local root, humanoid = getParts(character)
	if not root or not humanoid then
		return 0
	end
	-- Only consider when actually grounded
	if humanoid.FloorMaterial == Enum.Material.Air then
		return 0
	end

	-- Check sprint requirement if enabled
	local sprintRequired = Config.BunnyHopRequireSprint ~= false -- default true if not set
	if sprintRequired and not isSprinting then
		state.stacks = 0
		return 0
	end

	local now = os.clock()
	local withinWindow = state.landWindowActive
		and ((now - (state.lastLandTick or 0)) <= (Config.BunnyHopWindowSeconds or 0.18))
	if not withinWindow then
		-- Not a perfect hop: chain breaks
		state.stacks = 0
		return 0
	end

	-- Compute next stack
	local maxStacks = Config.BunnyHopMaxStacks or 3
	state.stacks = math.clamp((state.stacks or 0) + 1, 1, maxStacks)

	local vel = root.AssemblyLinearVelocity
	local horiz = Vector3.new(vel.X, 0, vel.Z)
	local horizMag = horiz.Magnitude
	local travelDir = (horizMag > 0.05) and horiz.Unit or Vector3.new(0, 0, 0)

	local coastOn = Config.BunnyHopCoastEnabled ~= false
	local inputEps = Config.BunnyHopCoastInputEpsilon or 0.08
	local moveFromInput = humanoid.MoveDirection.Magnitude > inputEps
	local coastMinStacks = Config.BunnyHopCoastMinStacks or 2
	local isCoasting = coastOn and state.stacks >= coastMinStacks
	local coastMinSpeed = Config.BunnyHopCoastMinSpeed or 1.2

	-- moveDir: keyboard intent. When coasting with no WASD, leave zero so boost follows velocity (+ optional camera).
	local moveDir
	if moveFromInput then
		moveDir = humanoid.MoveDirection
		moveDir = Vector3.new(moveDir.X, 0, moveDir.Z)
		if moveDir.Magnitude > 0 then
			moveDir = moveDir.Unit
		else
			moveDir = Vector3.new(0, 0, 0)
		end
	elseif isCoasting and horizMag >= coastMinSpeed then
		moveDir = Vector3.new(0, 0, 0)
	else
		moveDir = root.CFrame.LookVector
		moveDir = Vector3.new(moveDir.X, 0, moveDir.Z)
		if moveDir.Magnitude > 0 then
			moveDir = moveDir.Unit
		else
			moveDir = Vector3.new(0, 0, 0)
		end
	end

	if horizMag < 0.05 and moveDir.Magnitude == 0 then
		state.stacks = math.max(0, state.stacks - 1)
		return 0
	end

	local carry = math.clamp((Config.BunnyHopDirectionCarry or 0.75), 0, 1)
	if isCoasting and moveFromInput then
		local addCarry = Config.BunnyHopCoastStrafeExtraCarry or 0.12
		carry = math.clamp(carry + addCarry, 0, 0.92)
	end

	local blended
	if isCoasting and not moveFromInput and horizMag >= coastMinSpeed then
		blended = travelDir
		local mix = Config.BunnyHopCoastCameraSteerMix or 0
		if mix > 1e-4 then
			local cam = workspace.CurrentCamera
			if cam then
				local ch = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z)
				if ch.Magnitude > 0.05 then
					ch = ch.Unit
					blended = travelDir * (1 - mix) + ch * mix
					if blended.Magnitude > 0.01 then
						blended = blended.Unit
					else
						blended = travelDir
					end
				end
			end
		end
	else
		blended = (travelDir * carry) + (moveDir * (1 - carry))
		if blended.Magnitude > 0 then
			blended = blended.Unit
		else
			blended = if moveDir.Magnitude > 0 then moveDir else travelDir
		end
	end

	local newHoriz
	if Config.BunnyHopReorientHard then
		-- Hard reorientation: keep magnitude, replace direction with intent (or blended if no input)
		local baseDir = (moveDir.Magnitude > 0.01) and moveDir or blended
		if baseDir.Magnitude > 0 then
			newHoriz = baseDir.Unit * horizMag
		else
			newHoriz = horiz
		end
	else
		-- Soft redirection (previous logic)
		if moveDir.Magnitude > 0.01 and horizMag > 0.01 then
			local intentDot = moveDir:Dot(horiz.Unit)
			if intentDot < -0.2 then
				local perp = horiz - (horiz.Unit:Dot(moveDir) * moveDir * horizMag)
				local perpDamp = math.clamp(Config.BunnyHopPerpDampOnFlip or 0.4, 0, 1)
				local desiredMag = horizMag
				newHoriz = moveDir * desiredMag + perp * (1 - perpDamp)
			else
				local oppositeCancel = math.clamp(Config.BunnyHopOppositeCancel or 0.6, 0, 1)
				local backDot = (-moveDir):Dot(horiz.Unit)
				if backDot > 0 then
					local cancelMag = backDot * horizMag * oppositeCancel
					horiz = horiz + (moveDir * cancelMag)
				end
				newHoriz = horiz
			end
		else
			newHoriz = horiz
		end
	end

	-- Additive impulse along blended direction with sprint bonus and velocity preservation
	local bonus = (Config.BunnyHopBaseBoost or 6) + (Config.BunnyHopPerStackBoost or 3) * (state.stacks - 1)

	-- Apply sprint bonus if sprinting (even when not required)
	if isSprinting and Config.BunnyHopSprintBonus then
		bonus = bonus * Config.BunnyHopSprintBonus
	end

	-- Strafe reward: extra impulse when wish direction is clearly lateral to current travel (CS-style input).
	if horizMag > 0.05 and moveDir.Magnitude > 0.01 then
		local lateral = 1 - math.abs(horiz.Unit:Dot(moveDir))
		local strafeT = math.clamp(lateral / 0.55, 0, 1)
		local strafeMul = 1 + ((Config.BunnyHopStrafeBonus or 0.22) * strafeT)
		bonus = bonus * strafeMul
	end

	-- VELOCITY PRESERVATION: Scale bonus based on current speed to maintain momentum (BALANCED)
	local currentSpeed = newHoriz.Magnitude
	local speedScale = math.max(1.1, currentSpeed / 40) -- BALANCED: Gradual scaling that builds up nicely to cap
	bonus = bonus * speedScale

	local delta = blended * bonus
	local maxAdd = Config.BunnyHopMaxAddPerHop
	if type(maxAdd) == "number" and maxAdd > 0 and delta.Magnitude > maxAdd then
		delta = delta.Unit * maxAdd
	end
	newHoriz = newHoriz + delta

	-- Clamp total horizontal speed
	local cap = (Config.BunnyHopTotalSpeedCap or Config.AirControlTotalSpeedCap or 999)
	local nhMag = Vector3.new(newHoriz.X, 0, newHoriz.Z).Magnitude
	if nhMag > cap then
		newHoriz = newHoriz.Unit * cap
	end
	local savedHoriz = Vector3.new(newHoriz.X, 0, newHoriz.Z)
	root.AssemblyLinearVelocity = Vector3.new(savedHoriz.X, vel.Y, savedHoriz.Z)

	-- Same-frame tail + PostSimulation: Humanoid often adjusts velocity after our input callback.
	task.defer(function()
		if not (root and root.Parent and character.Parent) then
			return
		end
		local curV = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(savedHoriz.X, curV.Y, savedHoriz.Z)
	end)

	stopPostAssist(state)
	local assistSteps = Config.BunnyHopPostAssistSteps
	if assistSteps == nil then
		assistSteps = math.clamp(math.floor((Config.BunnyHopLockSeconds or 0.12) * 70 + 0.5), 4, 14)
	end
	assistSteps = math.clamp(assistSteps, 2, 18)
	local remaining = assistSteps
	state.postAssistConn = RunService.PostSimulation:Connect(function()
		if not (root and root.Parent and character.Parent) then
			stopPostAssist(state)
			return
		end
		local curV = root.AssemblyLinearVelocity
		local xz = Vector3.new(curV.X, 0, curV.Z)
		local sm = savedHoriz.Magnitude
		if sm > 0.05 then
			local keepDot = Config.BunnyHopPostAssistMinAlignDot
			if keepDot == nil then
				keepDot = 0.78
			end
			local magRatio = if sm > 1e-4 then xz.Magnitude / sm else 1
			local align = if xz.Magnitude > 0.05 then xz.Unit:Dot(savedHoriz.Unit) else 0
			if magRatio < 0.9 or align < keepDot then
				root.AssemblyLinearVelocity = Vector3.new(savedHoriz.X, curV.Y, savedHoriz.Z)
			end
		end
		remaining -= 1
		if remaining <= 0 then
			stopPostAssist(state)
		end
	end)

	-- Momentum bonus with sprint consideration and velocity scaling
	if momentumState and Momentum.addBonus then
		local mBonus = (Config.BunnyHopMomentumBonusBase or 4)
			+ (Config.BunnyHopMomentumBonusPerStack or 2) * (state.stacks - 1)

		-- Apply sprint bonus to momentum too
		if isSprinting and Config.BunnyHopSprintBonus then
			mBonus = mBonus * (Config.BunnyHopSprintBonus * 0.8) -- Slightly less for momentum
		end

		-- VELOCITY SCALING: Scale momentum bonus with current velocity for constant acceleration (BALANCED)
		local velocityScale = math.max(1.1, currentSpeed / 35) -- BALANCED: Gradual momentum scaling for smooth progression
		mBonus = mBonus * velocityScale

		Momentum.addBonus(momentumState, mBonus)
	end

	-- Consume this landing window
	state.landWindowActive = false

	-- Publish HUD signals if present
	local rs = game:GetService("ReplicatedStorage")
	local folder = rs:FindFirstChild("ClientState")
	if folder then
		local stacksVal = folder:FindFirstChild("BunnyHopStacks")
		local flashVal = folder:FindFirstChild("BunnyHopFlash")
		local styleScore = folder:FindFirstChild("StyleScore")
		local styleCombo = folder:FindFirstChild("StyleCombo")
		if stacksVal then
			stacksVal.Value = state.stacks
		end
		if flashVal then
			flashVal.Value = true
			task.delay(0.05, function()
				if flashVal and flashVal.Parent then
					flashVal.Value = false
				end
			end)
		end
	end

	return state.stacks or 1
end

return BunnyHop
