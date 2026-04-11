-- CollectionService "Enemy":
--   BasePart → wrap as a playable NPC (Model + Humanoid + HumanoidRootPart), tag moves to Model
--   Model    → ensure Humanoid + HumanoidRootPart + overhead UI

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Sniper"):WaitForChild("Config"))
local Ragdoll = require(ReplicatedStorage:WaitForChild("Ragdoll"))
local Animations = require(ReplicatedStorage:WaitForChild("Movement"):WaitForChild("Animations"))

local ENEMY_TAG = Config.EnemyTag
local DEFAULT_HP = Config.EnemyDefaultHealth

local function modelAdornee(model: Model): BasePart?
	if model.PrimaryPart then
		return model.PrimaryPart
	end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function setHealthBarFill(barFill: Frame, ratio: number)
	local r = math.clamp(ratio, 0, 1)
	barFill.Size = UDim2.new(r, 0, 1, 0)
end

local function createEnemyHumanoid(model: Model): Humanoid
	local humanoid = Instance.new("Humanoid")
	humanoid.Name = "EnemyHumanoid"
	humanoid.MaxHealth = DEFAULT_HP
	humanoid.Health = DEFAULT_HP
	humanoid.WalkSpeed = Config.EnemyWanderWalkSpeed
	humanoid.JumpPower = 50
	humanoid.AutoRotate = true
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HipHeight = 0
	humanoid.UseJumpPower = true
	humanoid.BreakJointsOnDeath = false
	humanoid.Parent = model
	local animator = Instance.new("Animator")
	animator.Parent = humanoid
	return humanoid
end

local function hookEnemyDeathRagdoll(model: Model)
	if model:GetAttribute("_EnemyRagdollHooked") then
		return
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	model:SetAttribute("_EnemyRagdollHooked", true)
	humanoid.BreakJointsOnDeath = false
	humanoid.Died:Connect(function()
		task.defer(function()
			if not model.Parent then
				return
			end
			local h = model:FindFirstChildOfClass("Humanoid")
			if h then
				h.BreakJointsOnDeath = false
			end
			Ragdoll.apply(model)
		end)
	end)
end

local function ensureHumanoidRootPart(model: Model, part: BasePart)
	if part.Name == "HumanoidRootPart" then
		model.PrimaryPart = part
		return
	end
	local existing = model:FindFirstChild("HumanoidRootPart")
	if existing and existing:IsA("BasePart") and existing ~= part then
		existing.Name = "EnemyAux_" .. existing.Name
	end
	part.Name = "HumanoidRootPart"
	model.PrimaryPart = part
end

-- Turn a tagged BasePart into a character-like rig so Humanoid:MoveTo works (same as players).
local function promotePartToEnemyCharacter(part: BasePart)
	if part:GetAttribute("_EnemyPartWrapped") then
		return
	end
	if not CollectionService:HasTag(part, ENEMY_TAG) then
		return
	end

	part.Anchored = false
	part:SetAttribute("_EnemyPartWrapped", true)

	local parent = part.Parent
	local model: Model

	if parent and parent:IsA("Model") and not Players:GetPlayerFromCharacter(parent) then
		model = parent
		ensureHumanoidRootPart(model, part)
		if not model:FindFirstChildOfClass("Humanoid") then
			createEnemyHumanoid(model)
		end
	else
		model = Instance.new("Model")
		model.Name = "Enemy"
		model.Parent = parent
		part.Parent = model
		ensureHumanoidRootPart(model, part)
		createEnemyHumanoid(model)
	end

	CollectionService:RemoveTag(part, ENEMY_TAG)
	CollectionService:AddTag(model, ENEMY_TAG)
end

local function stripDefaultAnimateForNpc(model: Model)
	local a = model:FindFirstChild("Animate")
	if a and a:IsA("LocalScript") then
		a:Destroy()
	end
end

local function ensureAnimatorOnHumanoid(humanoid: Humanoid): Animator
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	return animator
end

local function startEnemyServerLocomotion(model: Model)
	if model:GetAttribute("_EnemyServerLocomotionStarted") then
		return
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end

	model:SetAttribute("_EnemyServerLocomotionStarted", true)

	pcall(function()
		Animations.preload()
	end)

	local animator = ensureAnimatorOnHumanoid(humanoid)
	local walkAnim = Animations.get("Walk")
	local runAnim = Animations.get("Run")
	local walkTrack: AnimationTrack? = nil
	local runTrack: AnimationTrack? = nil

	local function loadWalk(): AnimationTrack?
		if walkTrack then
			return walkTrack
		end
		if not walkAnim then
			return nil
		end
		local ok, tr = pcall(function()
			return animator:LoadAnimation(walkAnim)
		end)
		if ok and tr then
			tr.Looped = true
			tr.Priority = Enum.AnimationPriority.Movement
			walkTrack = tr
		end
		return walkTrack
	end

	local function loadRun(): AnimationTrack?
		if runTrack then
			return runTrack
		end
		if not runAnim then
			return nil
		end
		local ok, tr = pcall(function()
			return animator:LoadAnimation(runAnim)
		end)
		if ok and tr then
			tr.Looped = true
			tr.Priority = Enum.AnimationPriority.Movement
			runTrack = tr
		end
		return runTrack
	end

	local th = Config.EnemyLocomotionRunSpeedThreshold
	local minSpeed = 0.35

	local conn: RBXScriptConnection?
	conn = RunService.Heartbeat:Connect(function()
		if not model.Parent or humanoid.Health <= 0 then
			if conn then
				conn:Disconnect()
			end
			pcall(function()
				if walkTrack and walkTrack.IsPlaying then
					walkTrack:Stop(0.1)
				end
				if runTrack and runTrack.IsPlaying then
					runTrack:Stop(0.1)
				end
			end)
			return
		end
		local r = model:FindFirstChild("HumanoidRootPart")
		if not r or not r:IsA("BasePart") then
			return
		end
		local v = r.AssemblyLinearVelocity
		local spd = Vector3.new(v.X, 0, v.Z).Magnitude

		if spd < minSpeed then
			pcall(function()
				if walkTrack and walkTrack.IsPlaying then
					walkTrack:Stop(0.12)
				end
				if runTrack and runTrack.IsPlaying then
					runTrack:Stop(0.12)
				end
			end)
		elseif runAnim and spd >= th then
			local rt = loadRun()
			pcall(function()
				if walkTrack and walkTrack.IsPlaying then
					walkTrack:Stop(0.1)
				end
				if rt and not rt.IsPlaying then
					rt:Play(0.15)
				end
			end)
		elseif walkAnim then
			local wt = loadWalk()
			pcall(function()
				if runTrack and runTrack.IsPlaying then
					runTrack:Stop(0.1)
				end
				if wt and not wt.IsPlaying then
					wt:Play(0.15)
				end
			end)
		end
	end)

	humanoid.Died:Connect(function()
		if conn then
			conn:Disconnect()
		end
		pcall(function()
			if walkTrack then
				walkTrack:Stop(0.05)
			end
			if runTrack then
				runTrack:Stop(0.05)
			end
		end)
	end)
end

local function injectEnemyLocomotion(model: Model)
	if not Config.EnemyLocomotionEnabled then
		return
	end
	stripDefaultAnimateForNpc(model)
	if Config.EnemyLocomotionUseServerAnimator then
		startEnemyServerLocomotion(model)
		return
	end
	if model:FindFirstChild("EnemyNpcLocomotion") then
		return
	end
	local aiFolder = ReplicatedStorage:FindFirstChild("AI")
	local tmpl = aiFolder and aiFolder:FindFirstChild("EnemyNpcLocomotion")
	if not tmpl or not tmpl:IsA("LocalScript") then
		return
	end
	local clone = tmpl:Clone()
	clone.Name = "EnemyNpcLocomotion"
	clone.Parent = model
end

local function attachOverheadUI(adornee: BasePart, humanoid: Humanoid?, attributeHost: Instance?)
	if adornee:FindFirstChild("EnemyOverheadBillboard") then
		return
	end

	local sz = Config.EnemyBillboardSizePx

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "EnemyOverheadBillboard"
	billboard.Adornee = adornee
	billboard.Size = UDim2.fromOffset(sz.X, sz.Y)
	billboard.StudsOffset = Config.EnemyBillboardStudsOffset
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = Config.EnemyBillboardMaxDistance
	billboard.LightInfluence = 0
	billboard.Parent = adornee

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "EnemyNameLabel"
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.new(1, 0, 0, 16)
	nameLabel.Position = UDim2.new(0, 0, 0, 0)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 14
	nameLabel.TextColor3 = Config.EnemyNameTextColor
	nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	nameLabel.TextStrokeTransparency = 0.65
	nameLabel.Text = Config.EnemyDisplayName
	nameLabel.Parent = billboard

	local barBg = Instance.new("Frame")
	barBg.Name = "HealthBarBackground"
	barBg.AnchorPoint = Vector2.new(0.5, 0)
	barBg.Position = UDim2.new(0.5, 0, 0, 20)
	barBg.Size = UDim2.new(1, -8, 0, 10)
	barBg.BackgroundColor3 = Config.EnemyHealthBarBackgroundColor
	barBg.BorderSizePixel = 0
	barBg.Parent = billboard

	local cornerBg = Instance.new("UICorner")
	cornerBg.CornerRadius = UDim.new(0, 3)
	cornerBg.Parent = barBg

	local barFill = Instance.new("Frame")
	barFill.Name = "HealthBarFill"
	barFill.AnchorPoint = Vector2.new(0, 0.5)
	barFill.Position = UDim2.new(0, 0, 0.5, 0)
	barFill.Size = UDim2.new(1, 0, 1, 0)
	barFill.BackgroundColor3 = Config.EnemyHealthBarFillColor
	barFill.BorderSizePixel = 0
	barFill.Parent = barBg

	local cornerFill = Instance.new("UICorner")
	cornerFill.CornerRadius = UDim.new(0, 3)
	cornerFill.Parent = barFill

	local function applyRatio(ratio: number)
		setHealthBarFill(barFill, ratio)
	end

	if humanoid then
		local function syncHumanoid()
			local maxH = humanoid.MaxHealth
			if maxH <= 0 then
				applyRatio(0)
				return
			end
			applyRatio(humanoid.Health / maxH)
		end
		syncHumanoid()
		humanoid.HealthChanged:Connect(syncHumanoid)
		humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(syncHumanoid)
	elseif attributeHost then
		local function syncAttributes()
			local hp = tonumber(attributeHost:GetAttribute("EnemyHealth")) or 0
			local maxHp = tonumber(attributeHost:GetAttribute("EnemyMaxHealth")) or 1
			if maxHp <= 0 then
				applyRatio(0)
				return
			end
			applyRatio(hp / maxHp)
		end
		syncAttributes()
		attributeHost:GetAttributeChangedSignal("EnemyHealth"):Connect(syncAttributes)
		attributeHost:GetAttributeChangedSignal("EnemyMaxHealth"):Connect(syncAttributes)
	else
		applyRatio(1)
	end
end

local function setupEnemy(instance: Instance)
	if instance:GetAttribute("_EnemyDummySetup") then
		return
	end

	local humanoid: Humanoid? = nil
	local adornee: BasePart? = nil
	local attrHost: Instance? = nil

	if instance:IsA("BasePart") then
		if instance:GetAttribute("_EnemyPartWrapped") then
			return
		end
		promotePartToEnemyCharacter(instance)
		return
	elseif instance:IsA("Model") then
		humanoid = instance:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			humanoid = createEnemyHumanoid(instance)
		else
			humanoid.WalkSpeed = Config.EnemyWanderWalkSpeed
			humanoid.BreakJointsOnDeath = false
		end

		local hrpCheck = instance:FindFirstChild("HumanoidRootPart")
		if not hrpCheck or not hrpCheck:IsA("BasePart") then
			local p = modelAdornee(instance)
			if p then
				ensureHumanoidRootPart(instance, p)
			end
		end

		local hrpFinal = instance:FindFirstChild("HumanoidRootPart")
		if hrpFinal and hrpFinal:IsA("BasePart") then
			adornee = hrpFinal
		else
			adornee = modelAdornee(instance)
		end
		attrHost = nil
		instance:SetAttribute("_EnemyDummySetup", true)
	else
		return
	end

	if adornee then
		attachOverheadUI(adornee, humanoid, attrHost)
	end

	injectEnemyLocomotion(instance)

	if instance:IsA("Model") then
		hookEnemyDeathRagdoll(instance)
	end
end

local function onTagged(instance: Instance)
	task.defer(function()
		if instance.Parent then
			setupEnemy(instance)
		end
	end)
end

for _, inst in ipairs(CollectionService:GetTagged(ENEMY_TAG)) do
	onTagged(inst)
end

CollectionService:GetInstanceAddedSignal(ENEMY_TAG):Connect(onTagged)
