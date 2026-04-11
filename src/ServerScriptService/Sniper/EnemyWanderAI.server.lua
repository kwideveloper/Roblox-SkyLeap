-- Enemy wander using PathfindingService when enabled (avoids obstacles, uses waypoints + jump hints).
-- Falls back to straight Humanoid:MoveTo if path fails. Walk/run visuals: server Animator when Config.EnemyLocomotionUseServerAnimator, else client ReplicatedStorage.AI.EnemyNpcLocomotion.

local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Sniper"):WaitForChild("Config"))

local ENEMY_TAG = Config.EnemyTag
local rng = Random.new()

local function getRoot(model: Model): BasePart?
	local r = model:FindFirstChild("HumanoidRootPart")
	if r and r:IsA("BasePart") then
		return r
	end
	if model.PrimaryPart then
		return model.PrimaryPart
	end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function groundPointNear(model: Model, origin: Vector3): Vector3
	local radius = Config.EnemyWanderRadius
	local dx = rng:NextNumber(-radius, radius)
	local dz = rng:NextNumber(-radius, radius)
	local from = origin + Vector3.new(dx, Config.EnemyWanderRaycastUp, dz)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { model }

	local hit = Workspace:Raycast(from, Vector3.new(0, -Config.EnemyWanderRaycastDown, 0), params)
	if hit then
		return hit.Position
	end
	return origin + Vector3.new(dx, 0, dz)
end

-- Cap how far each wander “leg” tries to go (path may be longer along the walkable route).
local function clampGoalDistance(origin: Vector3, dest: Vector3, maxDist: number): Vector3
	local delta = dest - origin
	local m = delta.Magnitude
	if m <= maxDist or m < 1e-4 then
		return dest
	end
	return origin + delta.Unit * maxDist
end

local function moveStraight(model: Model, humanoid: Humanoid, root: BasePart, target: Vector3)
	local moveDone = false
	local conn = humanoid.MoveToFinished:Connect(function()
		moveDone = true
	end)
	humanoid:MoveTo(target)
	local deadline = os.clock() + 14
	while model.Parent and humanoid.Health > 0 do
		if moveDone or os.clock() >= deadline then
			break
		end
		task.wait(0.2)
	end
	conn:Disconnect()
end

local function followPath(model: Model, humanoid: Humanoid, root: BasePart, goal: Vector3): boolean
	if not Config.EnemyPathfindingEnabled then
		return false
	end

	local path = PathfindingService:CreatePath({
		AgentRadius = Config.EnemyPathAgentRadius,
		AgentHeight = Config.EnemyPathAgentHeight,
		AgentCanJump = Config.EnemyPathAgentCanJump,
		AgentCanClimb = false,
	})

	local okCompute = pcall(function()
		path:ComputeAsync(root.Position, goal)
	end)
	if not okCompute or path.Status ~= Enum.PathStatus.Success then
		return false
	end

	local waypoints = path:GetWaypoints()
	if #waypoints == 0 then
		return false
	end

	local reachR = Config.EnemyPathWaypointReachedRadius
	local wpTimeout = Config.EnemyPathWaypointTimeoutSeconds
	local skipStartDist = math.min(reachR, 2)

	for i, wp in ipairs(waypoints) do
		if not model.Parent or humanoid.Health <= 0 or root.Anchored then
			return true
		end

		local skipFirst = i == 1 and (wp.Position - root.Position).Magnitude < skipStartDist
		if not skipFirst then
			if wp.Action == Enum.PathWaypointAction.Jump then
				humanoid.Jump = true
				task.wait(0.08)
			end

			local moveDone = false
			local conn = humanoid.MoveToFinished:Connect(function()
				moveDone = true
			end)
			humanoid:MoveTo(wp.Position)

			local t0 = os.clock()
			while model.Parent and humanoid.Health > 0 do
				if (root.Position - wp.Position).Magnitude <= reachR then
					break
				end
				if moveDone then
					break
				end
				if os.clock() - t0 > wpTimeout then
					break
				end
				task.wait(0.12)
			end
			conn:Disconnect()
		end
	end

	return true
end

local function runWanderLoop(model: Model, humanoid: Humanoid, root: BasePart)
	while model.Parent and humanoid.Health > 0 do
		local waitSec = rng:NextNumber(Config.EnemyWanderMinWaitSeconds, Config.EnemyWanderMaxWaitSeconds)
		task.wait(waitSec)
		if not model.Parent or humanoid.Health <= 0 then
			break
		end
		if root.Anchored then
			break
		end

		local rawGoal = groundPointNear(model, root.Position)
		local goal = clampGoalDistance(root.Position, rawGoal, Config.EnemyWanderMaxStepStuds)

		local pathOk = followPath(model, humanoid, root, goal)
		if not pathOk and Config.EnemyPathFallbackStraightLine then
			moveStraight(model, humanoid, root, goal)
		end
	end
end

local function tryStartWander(instance: Instance)
	if not Config.EnemyWanderEnabled then
		return
	end
	if not instance:IsA("Model") then
		return
	end
	if instance:GetAttribute("_EnemyWanderStarted") then
		return
	end

	task.defer(function()
		if not instance.Parent or not CollectionService:HasTag(instance, ENEMY_TAG) then
			return
		end

		local humanoid: Humanoid? = nil
		for _ = 1, 50 do
			humanoid = instance:FindFirstChildOfClass("Humanoid")
			if humanoid then
				break
			end
			task.wait(0.1)
		end
		if not humanoid then
			return
		end

		local root = getRoot(instance)
		if not root then
			return
		end

		instance:SetAttribute("_EnemyWanderStarted", true)
		humanoid.WalkSpeed = Config.EnemyWanderWalkSpeed
		humanoid.AutoRotate = true

		task.spawn(function()
			runWanderLoop(instance, humanoid, root)
		end)
	end)
end

for _, inst in ipairs(CollectionService:GetTagged(ENEMY_TAG)) do
	tryStartWander(inst)
end

CollectionService:GetInstanceAddedSignal(ENEMY_TAG):Connect(function(inst)
	tryStartWander(inst)
end)
