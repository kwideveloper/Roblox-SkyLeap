-- Ensures an Animator exists on the viewmodel clone (Humanoid or AnimationController).
-- When animating, only the model primary part stays anchored so Motor6D poses can update.

local Config = require(script.Parent.Config)

local ViewModelAnimationRigHelper = {}

local function buildJointAdjacency(model: Model): { [BasePart]: { BasePart } }
	local adjacency: { [BasePart]: { BasePart } } = {}

	local function addEdge(a: BasePart?, b: BasePart?)
		if not a or not b then
			return
		end
		if not a:IsDescendantOf(model) or not b:IsDescendantOf(model) then
			return
		end
		if adjacency[a] == nil then
			adjacency[a] = {}
		end
		if adjacency[b] == nil then
			adjacency[b] = {}
		end
		table.insert(adjacency[a], b)
		table.insert(adjacency[b], a)
	end

	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("JointInstance") then
			addEdge(d.Part0, d.Part1)
		elseif d:IsA("WeldConstraint") then
			addEdge(d.Part0, d.Part1)
		end
	end

	return adjacency
end

local function collectJointReachableParts(model: Model, primary: BasePart): { [BasePart]: boolean }
	local reachable: { [BasePart]: boolean } = {}
	reachable[primary] = true

	local adjacency = buildJointAdjacency(model)
	local queue: { BasePart } = { primary }
	local head = 1

	while head <= #queue do
		local current = queue[head]
		head += 1
		local neighbors = adjacency[current]
		if neighbors then
			for _, nextPart in ipairs(neighbors) do
				if not reachable[nextPart] then
					reachable[nextPart] = true
					table.insert(queue, nextPart)
				end
			end
		end
	end

	return reachable
end

local function shouldStayAnchored(part: BasePart, primary: BasePart): boolean
	if part == primary then
		return true
	end
	-- Many FPS rigs use a secondary root named "Main" as Motor6D Part0 for arms/gun.
	-- Keep it anchored so the full rig does not drift away from CameraBone.
	if part.Name == "Main" or part.Name == "HumanoidRootPart" then
		return true
	end
	return false
end

function ViewModelAnimationRigHelper.getAnimator(model: Model): (Animator?, Instance?)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = humanoid
		end
		return animator, humanoid
	end
	local ac = model:FindFirstChildOfClass("AnimationController")
	if not ac then
		ac = Instance.new("AnimationController")
		ac.Name = "SkyLeapViewModelAnimationController"
		ac.Parent = model
	end
	local animator = ac:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = ac
	end
	return animator, ac
end

function ViewModelAnimationRigHelper.applyAnchorStrategyForAnimation(model: Model, primary: BasePart)
	local connected = collectJointReachableParts(model, primary)

	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			-- Keep loose, non-jointed parts anchored to avoid visual "falling down" when a template has extra pieces.
			-- Parts joined by Motor6D/Weld/WeldConstraint to the primary chain remain unanchored so animation is visible.
			if shouldStayAnchored(d, primary) then
				d.Anchored = true
			elseif connected[d] then
				d.Anchored = false
			else
				d.Anchored = true
			end
			d.CanCollide = false
			d.CanQuery = false
			d.Massless = true
			pcall(function()
				d.CanTouch = false
			end)
		end
	end

	-- Motor6D targets MUST be unanchored for animation to visually apply.
	-- If reachability BFS missed a joint chain (e.g. joint authored without weld to primary),
	-- force Part0/Part1 of every JointInstance in the model to be unanchored
	-- except intentionally anchored roots (CameraBone/Main/HumanoidRootPart).
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("JointInstance") then
			local p0 = d.Part0
			local p1 = d.Part1
			if p0 and p0:IsA("BasePart") and not shouldStayAnchored(p0, primary) then
				p0.Anchored = false
			end
			if p1 and p1:IsA("BasePart") and not shouldStayAnchored(p1, primary) then
				p1.Anchored = false
			end
		end
	end
end

function ViewModelAnimationRigHelper.applyStaticAnchors(model: Model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.Massless = false
			pcall(function()
				d.CanTouch = false
			end)
		end
	end
end

function ViewModelAnimationRigHelper.shouldUseAnimatedAnchors(): boolean
	return Config.SniperViewModelAnimationsEnabled == true
end

return ViewModelAnimationRigHelper
