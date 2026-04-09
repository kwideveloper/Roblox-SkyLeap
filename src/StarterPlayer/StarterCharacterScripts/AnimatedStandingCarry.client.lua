-- Standing carry for CollectionService tag "Animated". Applies on the client (HumanoidRootPart is client-simulated).
-- Uses the replicated CFrame of the Start root each PreSimulation — not Instance attributes (those replicate too slowly
-- and the player only receives a fraction of per-step motion).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local RAY_DOWN = 12

local lastRootCFByModel = {}
local previousCarryModel = nil

local function isTruthyAttribute(value)
	if value == true then
		return true
	end
	if type(value) == "string" then
		local l = string.lower(value)
		return l == "true" or l == "1" or l == "yes"
	end
	return false
end

local function findTaggedAnimatedAncestor(instance)
	local current = instance
	while current do
		if current:IsA("Model") and CollectionService:HasTag(current, "Animated") then
			return current
		end
		current = current.Parent
	end
	return nil
end

-- Match AnimatedSystem: first descendant named "Start", same root resolution as getAnimatedPart().
local function findFirstStartObject(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d.Name == "Start" then
			return d
		end
	end
	return nil
end

local function getCarryRootPart(animModel)
	local startObj = findFirstStartObject(animModel)
	if not startObj then
		return nil
	end
	if startObj:IsA("BasePart") then
		return startObj
	end
	if startObj:IsA("Model") then
		local primaryPart = startObj.PrimaryPart
		if primaryPart then
			return primaryPart
		end
		for _, d in ipairs(startObj:GetDescendants()) do
			if d:IsA("BasePart") then
				return d
			end
		end
	end
	return nil
end

player.CharacterAdded:Connect(function()
	table.clear(lastRootCFByModel)
	previousCarryModel = nil
end)

RunService.PreSimulation:Connect(function()
	local character = player.Character
	if not character or not character.Parent then
		previousCarryModel = nil
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not hrp or not hrp:IsA("BasePart") then
		return
	end
	if humanoid.Health <= 0 or humanoid.Sit then
		if previousCarryModel then
			lastRootCFByModel[previousCarryModel] = nil
			previousCarryModel = nil
		end
		return
	end

	local origin = (hrp.CFrame * CFrame.new(0, -2.5, 0)).Position
	local dir = -hrp.CFrame.UpVector * RAY_DOWN

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }

	local hit = workspace:Raycast(origin, dir, params)

	local animModel = nil
	if hit and hit.Instance then
		animModel = findTaggedAnimatedAncestor(hit.Instance)
		if animModel and isTruthyAttribute(animModel:GetAttribute("DisableStandingCarry")) then
			animModel = nil
		end
	end

	if animModel ~= previousCarryModel then
		if previousCarryModel then
			lastRootCFByModel[previousCarryModel] = nil
		end
		previousCarryModel = animModel
	end

	if not animModel then
		return
	end

	local rootPart = getCarryRootPart(animModel)
	if not rootPart or not rootPart.Parent then
		return
	end

	local nowCF = rootPart.CFrame
	local lastCF = lastRootCFByModel[animModel]
	if lastCF then
		local rigidRotation = isTruthyAttribute(animModel:GetAttribute("StandingCarryIncludesRotation"))
		if rigidRotation then
			local deltaCF = nowCF * lastCF:Inverse()
			hrp.CFrame = deltaCF * hrp.CFrame
		else
			local dp = nowCF.Position - lastCF.Position
			if dp.Magnitude >= 1e-9 then
				hrp.CFrame = hrp.CFrame + dp
			end
		end
	end

	lastRootCFByModel[animModel] = nowCF
end)
