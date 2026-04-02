-- Flying system: allows player to fly when activated
-- Controlled by movement keys (WASD) and camera direction

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Movement.Config)

local Fly = {}

-- Configuration
local FLY_SPEED = 80 -- studs per second (baseline horizontal when not ramping W)
local FLY_ACCELERATION = 120 -- how fast velocity catches the target
local FLY_BRAKE_FACTOR = 0.85 -- deceleration when no input

-- W held: horizontal speed ramps from 1x to max over RAMP seconds; resets when W is released
local FLY_FORWARD_RAMP_SECONDS = 3.5
local FLY_FORWARD_MAX_MULTIPLIER = 2.75

-- Space held: upward speed ramps from 1x to max over RAMP seconds; resets when Space is released
local FLY_UP_RAMP_SECONDS = 2.75
local FLY_UP_MAX_MULTIPLIER = 2.5

-- Active flying state per character
local activeFlying = {}

local function getParts(character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return root, humanoid
end

-- Start flying for a character
function Fly.start(character)
	local root, humanoid = getParts(character)
	if not root or not humanoid then
		return false
	end

	-- Store original state
	if not activeFlying[character] then
		activeFlying[character] = {
			originalGravity = workspace.Gravity,
			velocity = Vector3.new(0, 0, 0),
			forwardHoldTime = 0,
			upHoldTime = 0,
		}
	end

	-- Disable gravity for the character
	pcall(function()
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Running, false)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.RunningNoPhysics, false)
	end)

	-- Set physics state to allow full control
	pcall(function()
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	end)

	-- Disable auto-rotate so we can control orientation
	humanoid.AutoRotate = false

	-- Reset velocity to current velocity to maintain momentum
	local currentVel = root.AssemblyLinearVelocity
	activeFlying[character].velocity = currentVel

	print("[Fly] Flying activated for character")
	return true
end

-- Stop flying for a character
function Fly.stop(character)
	local root, humanoid = getParts(character)
	if not root or not humanoid then
		return
	end

	local state = activeFlying[character]
	if not state then
		return
	end

	-- Re-enable all humanoid states
	pcall(function()
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, true)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Running, true)
		humanoid:SetStateEnabled(Enum.HumanoidStateType.RunningNoPhysics, true)
	end)

	-- Re-enable auto-rotate
	humanoid.AutoRotate = true

	-- Restore appropriate humanoid state based on whether grounded
	local grounded = (humanoid.FloorMaterial ~= Enum.Material.Air)
	pcall(function()
		if grounded then
			-- If on ground, set to Running so walking animations work
			humanoid:ChangeState(Enum.HumanoidStateType.Running)
		else
			-- If in air, set to Freefall so jumping and falling work
			humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		end
	end)

	print("[Fly] Flying deactivated, state restored")

	-- Clear flying state
	activeFlying[character] = nil
end

-- Check if character is currently flying
function Fly.isActive(character)
	return activeFlying[character] ~= nil
end

-- Update flying movement (called every frame)
function Fly.update(character, dt)
	local state = activeFlying[character]
	if not state then
		return
	end

	local root, humanoid = getParts(character)
	if not root or not humanoid then
		Fly.stop(character)
		return
	end

	-- Ensure humanoid stays in physics state and gravity is disabled
	-- (Other systems might try to change this)
	if humanoid:GetState() ~= Enum.HumanoidStateType.Physics then
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	end
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	humanoid.AutoRotate = false

	-- Get camera direction for movement reference
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	-- Camera vectors; movement on horizontal plane (WASD) separate from world vertical (Space/Shift)
	local cameraCFrame = camera.CFrame
	local forward = cameraCFrame.LookVector
	local right = cameraCFrame.RightVector
	local forwardFlat = Vector3.new(forward.X, 0, forward.Z)
	if forwardFlat.Magnitude > 0.01 then
		forwardFlat = forwardFlat.Unit
	else
		forwardFlat = Vector3.new(0, 0, -1)
	end
	local rightFlat = Vector3.new(right.X, 0, right.Z)
	if rightFlat.Magnitude > 0.01 then
		rightFlat = rightFlat.Unit
	else
		rightFlat = Vector3.new(1, 0, 0)
	end

	local wDown = UserInputService:IsKeyDown(Enum.KeyCode.W)
	local spaceDown = UserInputService:IsKeyDown(Enum.KeyCode.Space)

	state.forwardHoldTime = state.forwardHoldTime or 0
	state.upHoldTime = state.upHoldTime or 0

	-- Ramp timers: only increase while key held; instant reset to baseline when released
	if wDown then
		state.forwardHoldTime = math.min(state.forwardHoldTime + dt, FLY_FORWARD_RAMP_SECONDS)
	else
		state.forwardHoldTime = 0
	end
	if spaceDown then
		state.upHoldTime = math.min(state.upHoldTime + dt, FLY_UP_RAMP_SECONDS)
	else
		state.upHoldTime = 0
	end

	local forwardT = FLY_FORWARD_RAMP_SECONDS > 0 and (state.forwardHoldTime / FLY_FORWARD_RAMP_SECONDS) or 0
	forwardT = math.clamp(forwardT, 0, 1)
	local forwardMult = 1 + (FLY_FORWARD_MAX_MULTIPLIER - 1) * forwardT

	local upT = FLY_UP_RAMP_SECONDS > 0 and (state.upHoldTime / FLY_UP_RAMP_SECONDS) or 0
	upT = math.clamp(upT, 0, 1)
	local upMult = 1 + (FLY_UP_MAX_MULTIPLIER - 1) * upT

	local flatMove = Vector3.zero
	if wDown then
		flatMove = flatMove + forwardFlat
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then
		flatMove = flatMove - forwardFlat
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then
		flatMove = flatMove + rightFlat
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then
		flatMove = flatMove - rightFlat
	end

	local flatSpeed = FLY_SPEED
	if wDown then
		flatSpeed = FLY_SPEED * forwardMult
	end

	local targetFlat = Vector3.zero
	if flatMove.Magnitude > 0.01 then
		targetFlat = flatMove.Unit * flatSpeed
	end

	local targetY = 0
	if spaceDown then
		targetY = FLY_SPEED * upMult
	elseif UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
		targetY = -FLY_SPEED
	end

	local targetVelocity = Vector3.new(targetFlat.X, targetY, targetFlat.Z)

	local currentVel = state.velocity
	local newVelocity = currentVel

	local hasInput = flatMove.Magnitude > 0.01 or spaceDown or UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
	if hasInput then
		local accel = FLY_ACCELERATION * dt
		local delta = targetVelocity - currentVel
		if delta.Magnitude > accel then
			delta = delta.Unit * accel
		end
		newVelocity = currentVel + delta
	else
		newVelocity = currentVel * FLY_BRAKE_FACTOR
	end

	-- Apply velocity - use pcall for safety
	state.velocity = newVelocity
	pcall(function()
		root.AssemblyLinearVelocity = newVelocity
	end)

	-- Keep character upright (only rotate around Y axis)
	local currentCFrame = root.CFrame
	local lookDirection = forward
	lookDirection = Vector3.new(lookDirection.X, 0, lookDirection.Z).Unit
	if lookDirection.Magnitude > 0.1 then
		pcall(function()
			root.CFrame = CFrame.lookAt(root.Position, root.Position + lookDirection)
		end)
	end
end

-- Cleanup on character removal
local function cleanupCharacter(character)
	if activeFlying[character] then
		Fly.stop(character)
	end
end

-- Auto-cleanup when character is removed
local Players = game:GetService("Players")

-- Handle existing players
for _, player in ipairs(Players:GetPlayers()) do
	player.CharacterRemoving:Connect(function(character)
		cleanupCharacter(character)
	end)
end

-- Handle new players
Players.PlayerAdded:Connect(function(player)
	player.CharacterRemoving:Connect(function(character)
		cleanupCharacter(character)
	end)
end)

return Fly
