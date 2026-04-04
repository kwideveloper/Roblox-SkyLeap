-- Handles models with CollectionService "Animated" tag
-- Animates objects named "Start" towards the position/rotation of objects named "Finish"
-- Moves the whole rigid assembly (Start + parts connected via WeldConstraint / welds), not only the root part.
-- Attributes:
--   AnimationStyle (string) - Easing style: Linear, Quad, Cubic, Quart, Quint, Sine, Elastic, Back, Bounce (default: "Quad")
--   Duration (number) - Animation duration in seconds (default: 1)
--   Loop (bool) - Whether to return to start position after reaching finish (default: true)
--   Delay (number, optional) - Delay before starting animation in seconds (default: 0)

local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

-- Easing style mapping
local EASING_STYLES = {
	Linear = Enum.EasingStyle.Linear,
	Quad = Enum.EasingStyle.Quad,
	Cubic = Enum.EasingStyle.Cubic,
	Quart = Enum.EasingStyle.Quart,
	Quint = Enum.EasingStyle.Quint,
	Sine = Enum.EasingStyle.Sine,
	Elastic = Enum.EasingStyle.Elastic,
	Back = Enum.EasingStyle.Back,
	Bounce = Enum.EasingStyle.Bounce,
}

-- Default values
local DEFAULT_DURATION = 1
local DEFAULT_LOOP = true
local DEFAULT_STYLE = "Quad"
local DEFAULT_DIRECTION = "Out"

-- Helper to get attribute or default
local function getAttributeOrDefault(obj, attrName, defaultValue)
	if not obj then
		return defaultValue
	end
	local value = obj:GetAttribute(attrName)
	if value == nil then
		return defaultValue
	end
	return value
end

-- Find Start and Finish objects within a model
local function findStartAndFinish(model)
	if not model or not model:IsA("Model") then
		return nil, nil
	end
	
	local startObj = nil
	local finishObj = nil
	
	for _, descendant in ipairs(model:GetDescendants()) do
		local name = descendant.Name
		
		if name == "Start" then
			if not startObj then
				startObj = descendant
			end
		elseif name == "Finish" then
			if not finishObj then
				finishObj = descendant
			end
		end
	end
	
	return startObj, finishObj
end

local function cframeFromPositionRotation(pos, rotDeg)
	if not pos then
		return CFrame.new()
	end
	local r = rotDeg or Vector3.zero
	return CFrame.new(pos) * CFrame.Angles(math.rad(r.X), math.rad(r.Y), math.rad(r.Z))
end

-- All BaseParts rigidly connected to root (WeldConstraint, Weld, etc.) so they move together
local function getRigidAssemblyParts(rootPart)
	if not rootPart or not rootPart:IsA("BasePart") then
		return {}
	end
	local seen = {}
	local list = {}
	local function add(p)
		if p and p:IsA("BasePart") and not seen[p] then
			seen[p] = true
			table.insert(list, p)
		end
	end
	add(rootPart)
	local ok, connected = pcall(function()
		return rootPart:GetConnectedParts(true)
	end)
	if ok and type(connected) == "table" then
		for _, p in ipairs(connected) do
			add(p)
		end
	end
	return list
end

local function snapRigidAssemblyToRootCFrame(rootPart, worldRootCF)
	if not rootPart or not worldRootCF then
		return
	end
	local assembly = getRigidAssemblyParts(rootPart)
	if #assembly == 0 then
		return
	end
	local curRoot = rootPart.CFrame
	local rel = {}
	for _, p in ipairs(assembly) do
		rel[p] = curRoot:ToObjectSpace(p.CFrame)
	end
	for _, p in ipairs(assembly) do
		if p.Parent then
			p.CFrame = worldRootCF * rel[p]
		end
	end
end

-- Get target properties (position, rotation, etc.) from Finish object
local function getTargetProperties(finishObj)
	local properties = {}
	
	if finishObj:IsA("BasePart") then
		properties.Position = finishObj.Position
		properties.Rotation = finishObj.Rotation
		properties.Size = finishObj.Size
	elseif finishObj:IsA("Model") then
		-- For models, get primary part or first part
		local primaryPart = finishObj.PrimaryPart
		if not primaryPart then
			-- Try to find first BasePart
			for _, descendant in ipairs(finishObj:GetDescendants()) do
				if descendant:IsA("BasePart") then
					primaryPart = descendant
					break
				end
			end
		end
		
		if primaryPart then
			properties.Position = primaryPart.Position
			properties.Rotation = primaryPart.Rotation
			properties.Size = primaryPart.Size
		end
	end
	
	return properties
end

-- Get start properties (to return to original position)
local function getStartProperties(startObj)
	local properties = {}
	
	if startObj:IsA("BasePart") then
		properties.Position = startObj.Position
		properties.Rotation = startObj.Rotation
		properties.Size = startObj.Size
	elseif startObj:IsA("Model") then
		local primaryPart = startObj.PrimaryPart
		if not primaryPart then
			for _, descendant in ipairs(startObj:GetDescendants()) do
				if descendant:IsA("BasePart") then
					primaryPart = descendant
					break
				end
			end
		end
		
		if primaryPart then
			properties.Position = primaryPart.Position
			properties.Rotation = primaryPart.Rotation
			properties.Size = primaryPart.Size
		end
	end
	
	return properties
end

-- Get the part to animate from Start object
local function getAnimatedPart(startObj)
	if startObj:IsA("BasePart") then
		return startObj
	elseif startObj:IsA("Model") then
		-- For models, use primary part or first part
		local primaryPart = startObj.PrimaryPart
		if not primaryPart then
			for _, descendant in ipairs(startObj:GetDescendants()) do
				if descendant:IsA("BasePart") then
					primaryPart = descendant
					break
				end
			end
		end
		return primaryPart
	end
	return nil
end

-- Tween root CFrame and apply same rigid transform to every welded/connected part
local function createRigidAssemblyAnimation(startObj, targetProperties, tweenInfo)
	if not startObj or not targetProperties or not targetProperties.Position then
		return nil
	end

	local rootPart = getAnimatedPart(startObj)
	if not rootPart then
		warn("[AnimatedSystem] Could not find target instance to animate in", startObj:GetFullName())
		return nil
	end

	local targetCF = cframeFromPositionRotation(targetProperties.Position, targetProperties.Rotation)
	local assembly = getRigidAssemblyParts(rootPart)
	if #assembly == 0 then
		return nil
	end

	local startCF = rootPart.CFrame
	local rel = {}
	for _, p in ipairs(assembly) do
		rel[p] = startCF:ToObjectSpace(p.CFrame)
	end

	local progress = Instance.new("NumberValue")
	progress.Name = "_AnimatedAssemblyTween"
	progress.Value = 0
	progress.Parent = rootPart

	local tween = TweenService:Create(progress, tweenInfo, { Value = 1 })

	local function applyAtAlpha(alpha)
		local cur = startCF:Lerp(targetCF, alpha)
		for _, p in ipairs(assembly) do
			if p.Parent then
				p.CFrame = cur * rel[p]
			end
		end
	end

	local hb = RunService.Heartbeat:Connect(function()
		applyAtAlpha(progress.Value)
	end)

	local function cleanup()
		if hb then
			hb:Disconnect()
			hb = nil
		end
		if progress and progress.Parent then
			progress:Destroy()
		end
	end

	tween.Completed:Connect(function()
		applyAtAlpha(1)
		cleanup()
	end)

	return tween
end

-- Setup animation for a model
local function setupAnimated(model)
	if not model or not model:IsA("Model") then
		return
	end
	
	-- Skip if already wired
	if model:GetAttribute("_AnimatedWired") then
		return
	end
	
	model:SetAttribute("_AnimatedWired", true)
	
	-- Find Start and Finish
	local startObj, finishObj = findStartAndFinish(model)
	
	if not startObj then
		warn("[AnimatedSystem] Could not find 'Start' object in", model:GetFullName())
		return
	end
	
	if not finishObj then
		warn("[AnimatedSystem] Could not find 'Finish' object in", model:GetFullName())
		return
	end
	
	-- Get animation attributes from the model
	local duration = tonumber(getAttributeOrDefault(model, "Duration", DEFAULT_DURATION)) or DEFAULT_DURATION
	local shouldLoop = getAttributeOrDefault(model, "Loop", DEFAULT_LOOP)
	local styleName = tostring(getAttributeOrDefault(model, "AnimationStyle", DEFAULT_STYLE))
	local delay = tonumber(getAttributeOrDefault(model, "Delay", 0)) or 0
	
	-- Get easing style
	local easingStyle = EASING_STYLES[styleName] or EASING_STYLES[DEFAULT_STYLE]
	
	-- Get target and start properties
	local targetProperties = getTargetProperties(finishObj)
	local startProperties = getStartProperties(startObj)
	
	-- Get the part that will be animated
	local animatedPart = getAnimatedPart(startObj)
	if not animatedPart then
		warn("[AnimatedSystem] Could not find part to animate in", startObj:GetFullName())
		return
	end
	
	-- Save original properties from the animated part (not from startProperties which might be stale)
	local originalPosition = animatedPart.Position
	local originalRotation = animatedPart.Rotation
	
	-- Update startProperties to match current position (in case Start object was moved)
	startProperties.Position = originalPosition
	startProperties.Rotation = originalRotation
	
	-- Create animation function
	local function playForwardAnimation()
		if not startObj or not startObj.Parent or not finishObj or not finishObj.Parent then
			return
		end
		
		-- Get current animated part (in case it changed)
		local currentAnimatedPart = getAnimatedPart(startObj)
		if not currentAnimatedPart then
			return
		end
		
		-- Create forward animation (Start -> Finish)
		local forwardTweenInfo = TweenInfo.new(
			duration,
			easingStyle,
			Enum.EasingDirection[DEFAULT_DIRECTION],
			0,
			false,
			0
		)
		
		local forwardTween = createRigidAssemblyAnimation(startObj, targetProperties, forwardTweenInfo)
		if not forwardTween then
			return
		end
		
		-- Play forward animation
		forwardTween:Play()
		
		-- Handle completion
		forwardTween.Completed:Connect(function()
			if not startObj or not startObj.Parent then
				return
			end
			
			-- If loop is enabled, return to start
			if shouldLoop then
				-- Get current animated part again
				local currentAnimatedPart2 = getAnimatedPart(startObj)
				if not currentAnimatedPart2 then
					return
				end
				
				-- Create backward animation (Finish -> Start)
				local backwardTweenInfo = TweenInfo.new(
					duration,
					easingStyle,
					Enum.EasingDirection[DEFAULT_DIRECTION],
					0,
					false,
					0
				)
				
				local backwardTween = createRigidAssemblyAnimation(startObj, startProperties, backwardTweenInfo)
				if backwardTween then
					backwardTween:Play()
					backwardTween.Completed:Connect(function()
						-- Loop back to forward animation
						task.wait(0.05) -- Small delay between loops
						playForwardAnimation()
					end)
				else
					-- If backward animation fails, restore whole assembly and retry
					snapRigidAssemblyToRootCFrame(
						currentAnimatedPart2,
						cframeFromPositionRotation(originalPosition, originalRotation)
					)
					task.delay(0.1, playForwardAnimation)
				end
			end
		end)
	end
	
	-- Wait for delay if specified, then start animation
	if delay > 0 then
		task.delay(delay, playForwardAnimation)
	else
		playForwardAnimation()
	end
end

-- Setup existing Animated models
local function setupExistingAnimated()
	local animatedModels = CollectionService:GetTagged("Animated")
	for _, model in ipairs(animatedModels) do
		if model:IsA("Model") then
			setupAnimated(model)
		end
	end
end

-- Connect to CollectionService events for dynamic tag management
CollectionService:GetInstanceAddedSignal("Animated"):Connect(function(model)
	if model:IsA("Model") then
		setupAnimated(model)
	end
end)

CollectionService:GetInstanceRemovedSignal("Animated"):Connect(function(model)
	-- Clean up wiring attribute when tag is removed
	if model:IsA("Model") then
		model:SetAttribute("_AnimatedWired", nil)
	end
end)

-- Initialize existing Animated models
setupExistingAnimated()

