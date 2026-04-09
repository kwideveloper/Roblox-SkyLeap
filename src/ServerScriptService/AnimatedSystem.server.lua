-- Handles models with CollectionService "Animated" tag
-- Animates objects named "Start" towards the position/rotation of objects named "Finish"
-- Moves the whole rigid assembly (Start + parts connected via WeldConstraint / welds), not only the root part.
-- Attributes:
--   AnimationStyle (string) - Easing style: Linear, Quad, Cubic, Quart, Quint, Sine, Elastic, Back, Bounce (default: "Quad")
--   Duration (number) - Animation duration in seconds (default: 1)
--   Loop (bool) - Ping-pong forever Start<->Finish (default: false). Set true only for endless loop motion.
--   ReturnAfterSeconds (number, optional) - When Loop is false: after reaching Finish, wait this many seconds then animate back to Start (e.g. doors close). Ignored when Loop is true.
--   Delay (number, optional) - Delay before starting animation in seconds (default: 0)
--   WaitForTrigger (bool, optional) - If true, animation does not run until a trigger fires (default: false = immediate)
--   TriggerGroup (string, optional) - Links external trigger parts (same tag + same group) anywhere in the workspace
-- Trigger parts: CollectionService tag "AnimationTrigger" on a BasePart
--   DisableTouchTrigger (bool) - Skip .Touched (default: false)
--   DisableProximityTrigger (bool) - Skip ProximityPrompt under the part (default: false)
--   TriggerDebounce (number) - Seconds between valid fires on that part (default: 0.5)
--   TriggerGroup (string) - Must match the Animated model when the part is NOT inside that model
--   AllowRetrigger (bool, optional) - If WaitForTrigger: allow firing again after a run (default: false = one activation only)
--   MaxTriggerActivations (number, optional) - With AllowRetrigger: max total runs from triggers; omit = unlimited
--   (With ReturnAfterSeconds + WaitForTrigger + not AllowRetrigger + no MaxTriggerActivations: one activation is refunded when the return completes so the door can open again.)
--   DisableStandingCarry (bool, optional) - If true, players standing on the animated assembly are not moved with it (default: false = carry standing players).
--   StandingCarryIncludesRotation (bool, optional) - If true, standing riders use full rigid CFrame delta (rotation + translation), like being welded. Default false: only the platform's translation is applied so characters keep their facing and can walk freely on the surface.
-- Standing carry is applied on the client (AnimatedStandingCarry.client.lua) from the replicated Start root CFrame — no per-tick attributes (replication is too slow for full platform speed).

local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

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
local DEFAULT_LOOP = false
local DEFAULT_STYLE = "Quad"
local DEFAULT_DIRECTION = "Out"

local animatedCleanups = setmetatable({}, { __mode = "k" })

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

	-- PreSimulation runs before physics so translation carry composes with Humanoid walking instead of fighting render-step CFrame snaps.
	local simConn = RunService.PreSimulation:Connect(function()
		applyAtAlpha(progress.Value)
	end)

	local function cleanup()
		if simConn then
			simConn:Disconnect()
			simConn = nil
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

local TRIGGER_TAG = "AnimationTrigger"
local DEFAULT_TRIGGER_DEBOUNCE = 0.5
local DEFAULT_MODEL_TRIGGER_DEBOUNCE = 0.35

local function normalizeTriggerGroup(model)
	local g = model:GetAttribute("TriggerGroup")
	if type(g) ~= "string" or g == "" then
		return nil
	end
	return g
end

local function wireTriggerPart(part, onTriggered, allConnections)
	if not part or not part:IsA("BasePart") then
		return
	end

	local debounce = tonumber(part:GetAttribute("TriggerDebounce")) or DEFAULT_TRIGGER_DEBOUNCE
	local disableTouch = part:GetAttribute("DisableTouchTrigger") == true
		or isTruthyAttribute(part:GetAttribute("DisableTouchTrigger"))
	local disablePrompt = part:GetAttribute("DisableProximityTrigger") == true
		or isTruthyAttribute(part:GetAttribute("DisableProximityTrigger"))

	local lastFire = 0
	local function tryFire()
		local now = os.clock()
		if now - lastFire < debounce then
			return
		end
		lastFire = now
		onTriggered()
	end

	local touchConn = nil
	if not disableTouch then
		touchConn = part.Touched:Connect(function(hit)
			local ch = hit and hit.Parent
			if not ch then
				return
			end
			local hum = ch:FindFirstChildOfClass("Humanoid")
			if not hum then
				return
			end
			local plr = Players:GetPlayerFromCharacter(ch)
			if not plr then
				return
			end
			tryFire()
		end)
		table.insert(allConnections, touchConn)
	end

	local prompt = part:FindFirstChildOfClass("ProximityPrompt")
	if not disablePrompt and prompt then
		local prConn = prompt.Triggered:Connect(function()
			tryFire()
		end)
		table.insert(allConnections, prConn)
	end

	if not touchConn and (disablePrompt or not prompt) then
		warn(
			string.format(
				"[AnimatedSystem] AnimationTrigger part %s has no active input: enable touch or add a ProximityPrompt (and ensure it is not disabled via attributes).",
				part:GetFullName()
			)
		)
	end
end

-- Setup animation for a model
local function setupAnimated(model)
	if not model or not model:IsA("Model") then
		return
	end

	if model:GetAttribute("_AnimatedWired") then
		return
	end

	local startObj, finishObj = findStartAndFinish(model)

	if not startObj then
		warn("[AnimatedSystem] Could not find 'Start' object in", model:GetFullName())
		return
	end

	if not finishObj then
		warn("[AnimatedSystem] Could not find 'Finish' object in", model:GetFullName())
		return
	end

	local animatedPart = getAnimatedPart(startObj)
	if not animatedPart then
		warn("[AnimatedSystem] Could not find part to animate in", startObj:GetFullName())
		return
	end

	model:SetAttribute("_AnimatedWired", true)

	local duration = tonumber(getAttributeOrDefault(model, "Duration", DEFAULT_DURATION)) or DEFAULT_DURATION
	local shouldLoop = getAttributeOrDefault(model, "Loop", DEFAULT_LOOP)
	local styleName = tostring(getAttributeOrDefault(model, "AnimationStyle", DEFAULT_STYLE))
	local delay = tonumber(getAttributeOrDefault(model, "Delay", 0)) or 0
	local waitForTrigger = isTruthyAttribute(model:GetAttribute("WaitForTrigger"))
	local triggerGroup = normalizeTriggerGroup(model)
	local modelTriggerDebounce = tonumber(model:GetAttribute("TriggerDebounce")) or DEFAULT_MODEL_TRIGGER_DEBOUNCE
	local allowRetrigger = isTruthyAttribute(model:GetAttribute("AllowRetrigger"))
	local maxTriggerActivations = tonumber(model:GetAttribute("MaxTriggerActivations"))
	if maxTriggerActivations and maxTriggerActivations <= 0 then
		maxTriggerActivations = nil
	end

	local returnAfterSeconds = tonumber(model:GetAttribute("ReturnAfterSeconds"))
	if returnAfterSeconds and returnAfterSeconds <= 0 then
		returnAfterSeconds = nil
	end
	if shouldLoop and returnAfterSeconds then
		returnAfterSeconds = nil
	end

	local easingStyle = EASING_STYLES[styleName] or EASING_STYLES[DEFAULT_STYLE]

	local targetProperties = getTargetProperties(finishObj)
	local startProperties = getStartProperties(startObj)

	local originalPosition = animatedPart.Position
	local originalRotation = animatedPart.Rotation
	startProperties.Position = originalPosition
	startProperties.Rotation = originalRotation

	local connections = {}
	local lastModelTrigger = 0
	local triggeredLoopRunning = false
	local oneShotBusy = false
	local triggerActivationCount = 0
	local countNextForwardAsTriggerActivation = false
	local returnSequenceId = 0

	local function disconnectAll()
		animatedCleanups[model] = nil
		for _, c in ipairs(connections) do
			if typeof(c) == "RBXScriptConnection" then
				c:Disconnect()
			elseif type(c) == "function" then
				pcall(c)
			end
		end
		table.clear(connections)
	end

	animatedCleanups[model] = disconnectAll

	model.Destroying:Connect(function()
		disconnectAll()
	end)

	local function refreshStartPropertiesFromOriginal()
		startProperties.Position = originalPosition
		startProperties.Rotation = originalRotation
	end

	local function playBackwardToStart(onComplete)
		if not startObj or not startObj.Parent or not finishObj or not finishObj.Parent then
			if type(onComplete) == "function" then
				task.defer(onComplete)
			end
			return
		end

		refreshStartPropertiesFromOriginal()

		local backwardTweenInfo = TweenInfo.new(
			duration,
			easingStyle,
			Enum.EasingDirection[DEFAULT_DIRECTION],
			0,
			false,
			0
		)

		local backwardTween = createRigidAssemblyAnimation(startObj, startProperties, backwardTweenInfo)
		if not backwardTween then
			local rootPart = getAnimatedPart(startObj)
			if rootPart then
				snapRigidAssemblyToRootCFrame(
					rootPart,
					cframeFromPositionRotation(originalPosition, originalRotation)
				)
			end
			if type(onComplete) == "function" then
				task.defer(onComplete)
			end
			return
		end

		backwardTween:Play()
		backwardTween.Completed:Connect(function()
			if type(onComplete) == "function" then
				onComplete()
			end
		end)
	end

	local playForwardAnimation

	playForwardAnimation = function()
		if not startObj or not startObj.Parent or not finishObj or not finishObj.Parent then
			if waitForTrigger and not shouldLoop then
				oneShotBusy = false
			end
			countNextForwardAsTriggerActivation = false
			return
		end

		local currentAnimatedPart = getAnimatedPart(startObj)
		if not currentAnimatedPart then
			if waitForTrigger and not shouldLoop then
				oneShotBusy = false
			end
			countNextForwardAsTriggerActivation = false
			return
		end

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
			if waitForTrigger and not shouldLoop then
				oneShotBusy = false
			end
			countNextForwardAsTriggerActivation = false
			return
		end

		if countNextForwardAsTriggerActivation then
			triggerActivationCount = triggerActivationCount + 1
			countNextForwardAsTriggerActivation = false
		end

		returnSequenceId = returnSequenceId + 1
		local forwardReturnId = returnSequenceId

		forwardTween:Play()

		forwardTween.Completed:Connect(function()
			if not startObj or not startObj.Parent then
				return
			end

			if shouldLoop then
				local currentAnimatedPart2 = getAnimatedPart(startObj)
				if not currentAnimatedPart2 then
					return
				end

				playBackwardToStart(function()
					task.wait(0.05)
					if forwardReturnId == returnSequenceId then
						playForwardAnimation()
					end
				end)
			elseif returnAfterSeconds then
				task.delay(returnAfterSeconds, function()
					if not model.Parent or forwardReturnId ~= returnSequenceId then
						return
					end
					playBackwardToStart(function()
						refreshStartPropertiesFromOriginal()
						if waitForTrigger and not shouldLoop then
							oneShotBusy = false
						end
						if
							waitForTrigger
							and not allowRetrigger
							and not maxTriggerActivations
							and returnAfterSeconds
						then
							triggerActivationCount = math.max(0, triggerActivationCount - 1)
						end
					end)
				end)
			elseif waitForTrigger then
				oneShotBusy = false
			end
		end)
	end

	local function beginPlayback()
		if not model.Parent then
			return
		end

		if waitForTrigger then
			if not allowRetrigger and triggerActivationCount >= 1 then
				return
			end
			if allowRetrigger and maxTriggerActivations and triggerActivationCount >= maxTriggerActivations then
				return
			end
		end

		local now = os.clock()
		if now - lastModelTrigger < modelTriggerDebounce then
			return
		end
		lastModelTrigger = now

		if waitForTrigger then
			if shouldLoop then
				if triggeredLoopRunning then
					return
				end
				triggeredLoopRunning = true
			else
				if oneShotBusy then
					return
				end
				oneShotBusy = true
				local rootNow = getAnimatedPart(startObj)
				if rootNow then
					snapRigidAssemblyToRootCFrame(
						rootNow,
						cframeFromPositionRotation(originalPosition, originalRotation)
					)
				end
				refreshStartPropertiesFromOriginal()
			end
		end

		local function run()
			if not model.Parent then
				if waitForTrigger and not shouldLoop then
					oneShotBusy = false
				end
				countNextForwardAsTriggerActivation = false
				return
			end
			if waitForTrigger then
				countNextForwardAsTriggerActivation = true
			end
			playForwardAnimation()
		end

		if delay > 0 then
			task.delay(delay, run)
		else
			task.defer(run)
		end
	end

	if waitForTrigger then
		local wiredTriggers = {}
		local wiredAny = false

		local function tryWireTriggerPart(part)
			if wiredTriggers[part] then
				return
			end
			wiredTriggers[part] = true
			wireTriggerPart(part, beginPlayback, connections)
			wiredAny = true
		end

		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and CollectionService:HasTag(d, TRIGGER_TAG) then
				tryWireTriggerPart(d)
			end
		end

		if triggerGroup then
			for _, inst in ipairs(CollectionService:GetTagged(TRIGGER_TAG)) do
				if inst:IsA("BasePart") and not inst:IsDescendantOf(model) then
					local g = inst:GetAttribute("TriggerGroup")
					if type(g) == "string" and g == triggerGroup then
						tryWireTriggerPart(inst)
					end
				end
			end
		end

		local tagAddedCon = CollectionService:GetInstanceAddedSignal(TRIGGER_TAG):Connect(function(inst)
			if not model.Parent then
				return
			end
			if not inst:IsA("BasePart") then
				return
			end
			if inst:IsDescendantOf(model) then
				tryWireTriggerPart(inst)
				return
			end
			if triggerGroup then
				local g = inst:GetAttribute("TriggerGroup")
				if type(g) == "string" and g == triggerGroup then
					tryWireTriggerPart(inst)
				end
			end
		end)
		table.insert(connections, tagAddedCon)

		if not wiredAny then
			warn(
				string.format(
					"[AnimatedSystem] WaitForTrigger is true on %s but no triggers were found. Add tag %q to a BasePart inside the model, or set TriggerGroup on the model and matching trigger parts outside it.",
					model:GetFullName(),
					TRIGGER_TAG
				)
			)
		end
	else
		if delay > 0 then
			task.delay(delay, playForwardAnimation)
		else
			playForwardAnimation()
		end
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

CollectionService:GetInstanceRemovedSignal("Animated"):Connect(function(m)
	if m:IsA("Model") then
		local fn = animatedCleanups[m]
		if fn then
			fn()
		end
		m:SetAttribute("_AnimatedWired", nil)
	end
end)

-- Initialize existing Animated models
setupExistingAnimated()

