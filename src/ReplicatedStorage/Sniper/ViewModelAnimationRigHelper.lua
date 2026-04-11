-- Ensures an Animator exists on the viewmodel clone (Humanoid or AnimationController).
-- When animating, only the model primary part stays anchored so Motor6D poses can update.

local Config = require(script.Parent.Config)

local ViewModelAnimationRigHelper = {}

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
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = d == primary
			d.CanCollide = false
			d.CanQuery = false
			d.Massless = true
			pcall(function()
				d.CanTouch = false
			end)
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
