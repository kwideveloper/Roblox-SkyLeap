-- Cloned into Enemy-tagged character models. Plays Walk/Run from ReplicatedStorage.Movement.Animations (same as players).
-- Template lives under ReplicatedStorage.AI (see EnemyDummySetup.server.lua).

local character = script.Parent
if not character:IsA("Model") then
	return
end

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local humanoid = character:WaitForChild("Humanoid", 12)
if not humanoid then
	return
end

local Config = require(ReplicatedStorage:WaitForChild("Sniper"):WaitForChild("Config"))
local Animations = require(ReplicatedStorage:WaitForChild("Movement"):WaitForChild("Animations"))

pcall(function()
	Animations.preload()
end)

local animator = humanoid:FindFirstChildOfClass("Animator")
if not animator then
	animator = Instance.new("Animator")
	animator.Parent = humanoid
end

local walkAnim = Animations.get("Walk")
local runAnim = Animations.get("Run")

local walkTrack = nil
local runTrack = nil

local function ensureWalkTrack()
	if walkTrack then
		return walkTrack
	end
	if not walkAnim then
		return nil
	end
	walkTrack = animator:LoadAnimation(walkAnim)
	walkTrack.Priority = Enum.AnimationPriority.Movement
	walkTrack.Looped = true
	return walkTrack
end

local function ensureRunTrack()
	if runTrack then
		return runTrack
	end
	if not runAnim then
		return nil
	end
	runTrack = animator:LoadAnimation(runAnim)
	runTrack.Priority = Enum.AnimationPriority.Movement
	runTrack.Looped = true
	return runTrack
end

local function stopLocomotion(fade: number?)
	local f = fade or 0.12
	if walkTrack and walkTrack.IsPlaying then
		walkTrack:Stop(f)
	end
	if runTrack and runTrack.IsPlaying then
		runTrack:Stop(f)
	end
end

local lastRunningSpeed = 0
humanoid.Running:Connect(function(speed)
	lastRunningSpeed = speed
end)

local threshold = Config.EnemyLocomotionRunSpeedThreshold or 12

local function isLocomotingOnGround(): boolean
	local s = humanoid:GetState()
	return s == Enum.HumanoidStateType.Running
		or s == Enum.HumanoidStateType.Walking
		or s == Enum.HumanoidStateType.Landed
end

RunService.Heartbeat:Connect(function()
	if humanoid.Health <= 0 then
		stopLocomotion(0.05)
		return
	end

	if not isLocomotingOnGround() then
		stopLocomotion(0.1)
		return
	end

	local md = humanoid.MoveDirection
	local moveScalar = md.Magnitude
	local estimatedSpeed = moveScalar * humanoid.WalkSpeed
	local speed = math.max(lastRunningSpeed, estimatedSpeed)

	if moveScalar < 0.08 and speed < 0.75 then
		stopLocomotion(0.15)
		return
	end

	if runAnim and speed >= threshold then
		local rt = ensureRunTrack()
		if rt then
			if walkTrack and walkTrack.IsPlaying then
				walkTrack:Stop(0.12)
			end
			if not rt.IsPlaying then
				rt:Play(0.18, 1, 1)
			end
		end
	elseif walkAnim then
		local wt = ensureWalkTrack()
		if wt then
			if runTrack and runTrack.IsPlaying then
				runTrack:Stop(0.12)
			end
			if not wt.IsPlaying then
				wt:Play(0.18, 1, 1)
			end
		end
	else
		stopLocomotion(0.15)
	end
end)

humanoid.Died:Connect(function()
	stopLocomotion(0.05)
end)
