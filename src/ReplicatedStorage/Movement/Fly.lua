-- Flying system: allows player to fly when activated
-- Controlled by movement keys (WASD) and camera direction

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Movement.Config)

local Fly = {}

-- Configuration
local FLY_SPEED = 80 -- studs per second (increased from 50)
local FLY_ACCELERATION = 120 -- acceleration rate (increased from 100)
local FLY_BRAKE_FACTOR = 0.85 -- deceleration when no input

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

	-- Get camera vectors
	local cameraCFrame = camera.CFrame
	local forward = cameraCFrame.LookVector
	local right = cameraCFrame.RightVector
	local up = Vector3.new(0, 1, 0)

	-- Calculate desired direction based on input (use UserInputService directly)
	local desiredDirection = Vector3.new(0, 0, 0)

	-- Forward/backward (W/S)
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then
		desiredDirection = desiredDirection + forward
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then
		desiredDirection = desiredDirection - forward
	end

	-- Left/right (A/D)
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then
		desiredDirection = desiredDirection + right
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then
		desiredDirection = desiredDirection - right
	end

	-- Up/down (Space/Shift)
	if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
		desiredDirection = desiredDirection + up
	elseif UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
		desiredDirection = desiredDirection - up
	end

	-- Normalize direction
	if desiredDirection.Magnitude > 0.1 then
		desiredDirection = desiredDirection.Unit
	end

	-- Calculate target velocity
	local targetVelocity = desiredDirection * FLY_SPEED

	-- Smoothly interpolate current velocity towards target
	local currentVel = state.velocity
	local newVelocity = currentVel

	if desiredDirection.Magnitude > 0.1 then
		-- Accelerate towards target
		local accel = FLY_ACCELERATION * dt
		local direction = (targetVelocity - currentVel)
		if direction.Magnitude > accel then
			direction = direction.Unit * accel
		end
		newVelocity = currentVel + direction

		-- Clamp to max speed
		if newVelocity.Magnitude > FLY_SPEED then
			newVelocity = newVelocity.Unit * FLY_SPEED
		end
	else
		-- Brake when no input
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
