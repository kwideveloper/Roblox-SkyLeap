-- Global reward animation system for coins and diamonds
-- Can be used from any script to trigger reward bursts with automatic UI updates

local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local CurrencyConfig = require(script.Parent.Config)

local RewardAnimations = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Cache for original text colors to revert after animations
local baseTextColor = setmetatable({}, { __mode = "k" })

-- Track active tweens to prevent conflicts
local activeTweens = setmetatable({}, { __mode = "k" })

-- UI SFX helpers
local function getUiSfxTemplate(name)
	local ps = player:FindFirstChild("PlayerScripts") or player:WaitForChild("PlayerScripts")
	local root = ps and ps:FindFirstChild("Sounds")
	local sfx = root and root:FindFirstChild("SFX")
	local ui = sfx and sfx:FindFirstChild("UI")
	if not ui then
		return nil
	end
	local inst = ui:FindFirstChild(name)
	if inst and inst:IsA("Sound") then
		return inst
	end
	return nil
end

local function playUiSfx(name, speed)
	local tpl = getUiSfxTemplate(name)
	if not tpl then
		return
	end
	local clone = tpl:Clone()
	clone.Parent = tpl.Parent
	if speed then
		clone.Pitch = speed
	end
	clone:Play()
	clone.Ended:Connect(function()
		clone:Destroy()
	end)
end

-- Find target anchors for coins and diamonds
local function findTextLabel(container, predicate)
	if not container then
		return nil
	end

	for _, obj in ipairs(container:GetDescendants()) do
		if obj:IsA("TextLabel") and predicate(obj) then
			return obj
		end
	end
	return nil
end

local function ensureFallbackAnchor(name, parent, defaultPosition)
	parent = parent or playerGui
	if not parent then
		return nil
	end

	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Frame") then
		return existing
	end

	local anchor = Instance.new("Frame")
	anchor.Name = name
	anchor.BackgroundTransparency = 1
	anchor.Size = UDim2.fromOffset(1, 1)
	anchor.AnchorPoint = Vector2.new(0.5, 0.5)
	anchor.Position = defaultPosition or UDim2.fromScale(0.5, 0.42)
	anchor.Parent = parent
	return anchor
end

local function getCoinAnchor()
	local currencyGui = playerGui:FindFirstChild("Currency")
	-- Preferred: tagged label
	local anchor = findTextLabel(currencyGui, function(obj)
		return CollectionService:HasTag(obj, "Coin")
	end)
	if anchor then
		return anchor
	end

	-- Fallbacks: look for labels named/containing "coin"
	anchor = findTextLabel(currencyGui, function(obj)
		local name = string.lower(obj.Name)
		return name == "coin" or name == "coins" or string.find(name, "coin", 1, true) ~= nil
	end)
	if anchor then
		return anchor
	end

	anchor = findTextLabel(currencyGui, function(obj)
		local text = string.lower(tostring(obj.Text))
		return text ~= "" and string.find(text, "coin", 1, true) ~= nil
	end)
	if anchor then
		return anchor
	end

	-- Final fallback: create a hidden anchor near the top-left area
	return ensureFallbackAnchor("_CoinAnimationAnchor", currencyGui or playerGui, UDim2.new(0, 140, 0, 65))
end

local function getDiamondAnchor()
	local currencyGui = playerGui:FindFirstChild("Currency")
	-- Preferred: tagged label
	local anchor = findTextLabel(currencyGui, function(obj)
		return CollectionService:HasTag(obj, "Diamond")
	end)
	if anchor then
		return anchor
	end

	-- Fallback: look for labels named/containing "diamond"
	anchor = findTextLabel(currencyGui, function(obj)
		local name = string.lower(obj.Name)
		return name == "diamond" or name == "diamonds" or string.find(name, "diamond", 1, true) ~= nil
	end)
	if anchor then
		return anchor
	end

	anchor = findTextLabel(currencyGui, function(obj)
		local text = string.lower(tostring(obj.Text))
		return text ~= "" and string.find(text, "diamond", 1, true) ~= nil
	end)
	if anchor then
		return anchor
	end

	-- Final fallback: dedicated diamond anchor on the right side to avoid overlapping with coins
	return ensureFallbackAnchor("_DiamondAnimationAnchor", currencyGui or playerGui, UDim2.new(1, -140, 0, 65))
end

-- Events for communicating coin arrivals
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteEvents = ReplicatedStorage:WaitForChild("Remotes")

-- Create local communication events if they don't exist
local function getOrCreateEvent(name)
	local existing = script:FindFirstChild(name)
	if existing then
		return existing
	end
	local event = Instance.new("BindableEvent")
	event.Name = name
	event.Parent = script
	return event
end

local CoinArrived = getOrCreateEvent("CoinArrived")

-- Animate individual coin/diamond flying to target (like original CurrencyUI)
local function spawnCurrencyAt(parent, fromPos, toPos, baseSize, imageId, onArrive)
	local img = Instance.new("ImageLabel")
	img.Name = "CurrencyFly"
	img.BackgroundTransparency = 1
	img.Image = imageId
	img.AnchorPoint = Vector2.new(0.5, 0.5)
	img.Size = UDim2.fromOffset(baseSize, baseSize)
	img.Position = fromPos
	img.ImageTransparency = 1
	img.ZIndex = 20
	img.Parent = parent

	local scale = Instance.new("UIScale")
	scale.Scale = 0.4 + math.random() * 0.2
	scale.Parent = img

	-- Pop in animation
	local tIn = TweenInfo.new(0.12 + math.random() * 0.06, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local pop = 1.15 + math.random() * 0.2
	TweenService:Create(scale, tIn, { Scale = pop }):Play()
	TweenService:Create(img, tIn, { ImageTransparency = 0 }):Play()

	-- Curved flight path to target
	local tFly = TweenInfo.new(0.80 + math.random() * 0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	local mid = UDim2.fromOffset(
		(fromPos.X.Offset + toPos.X.Offset) * 0.5 + math.random(-40, 40),
		(fromPos.Y.Offset + toPos.Y.Offset) * 0.5 + math.random(-20, 30)
	)
	TweenService:Create(img, tFly, { Position = mid }):Play()

	-- Finish to target and fade
	task.delay(tFly.Time, function()
		local tOut = TweenInfo.new(0.25 + math.random() * 0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(img, tOut, { Position = toPos, ImageTransparency = 0.2 }):Play()
		task.delay(tOut.Time + 0.02, function()
			if type(onArrive) == "function" then
				onArrive()
			end
			img:Destroy()
		end)
	end)
end

-- Bump and color flash animation for target labels (subtle and consistent)
local function bumpCurrencyLabel(label, flashColor)
	if not label then
		return
	end

	-- Cancel any existing tweens for this label
	if activeTweens[label] then
		for _, tween in pairs(activeTweens[label]) do
			if tween then
				tween:Cancel()
			end
		end
		activeTweens[label] = nil
	end

	-- Store original values if not cached
	if not baseTextColor[label] then
		baseTextColor[label] = label.TextColor3
	end

	-- Get or create UIScale for consistent scaling
	local uiScale = label:FindFirstChildOfClass("UIScale")
	if not uiScale then
		uiScale = Instance.new("UIScale")
		uiScale.Scale = 1
		uiScale.Parent = label
	end

	-- No need to cancel UIScale tweens since we're tracking by label

	-- Reset to ensure clean state
	uiScale.Scale = 1

	-- SUBTLE scaling animation (1.0 → 1.1 → 1.0) and green flash
	local originalColor = baseTextColor[label]
	local greenColor = Color3.fromRGB(50, 255, 50)

	-- Immediately set to green and scale up subtly
	label.TextColor3 = greenColor

	local scaleUpTween = TweenService:Create(
		uiScale,
		TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1.1 }
	)

	-- Track this tween
	activeTweens[label] = { scaleUpTween }

	scaleUpTween:Play()

	-- After scale up completes, scale back down and fade color back
	scaleUpTween.Completed:Connect(function()
		local scaleDownTween = TweenService:Create(
			uiScale,
			TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Scale = 1.0 }
		)

		local colorTween = TweenService:Create(
			label,
			TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ TextColor3 = originalColor }
		)

		-- Update tracked tweens
		activeTweens[label] = { scaleDownTween, colorTween }

		scaleDownTween:Play()
		colorTween:Play()

		-- Clean up tracking when animations complete
		colorTween.Completed:Connect(function()
			activeTweens[label] = nil
		end)
	end)
end

-- Helper to find proper parent ScreenGui for currency animations
local function getTopScreenGui(inst)
	local cur = inst
	while cur and cur.Parent do
		if cur:IsA("ScreenGui") and cur:IsDescendantOf(playerGui) then
			return cur
		end
		cur = cur.Parent
	end
	return nil
end

-- Main function: spawn reward burst with animations (like original CurrencyUI)
function RewardAnimations.spawnRewardBurst(amount, rewardType, sourcePosition, sourceButton)
	local imageId = (rewardType == "Coins") and "rbxassetid://127484940327901" or "rbxassetid://134526683895571"
	local targetAnchor = (rewardType == "Coins") and getCoinAnchor() or getDiamondAnchor()
	local flashColor = (rewardType == "Coins") and Color3.fromRGB(50, 255, 50) or Color3.fromRGB(0, 255, 255)

	if not targetAnchor then
		return -- No target found
	end

	-- Find parent ScreenGui for animations
	local parent = getTopScreenGui(targetAnchor)
	if not parent then
		-- Create temporary ScreenGui as fallback
		parent = Instance.new("ScreenGui")
		parent.Name = "TempCurrencyParent"
		parent.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		parent.Parent = playerGui
	end

	-- Handle source position (use parent's coordinate system)
	local sz = parent.AbsoluteSize
	local centerX, centerY
	-- Offset the origin slightly based on reward type so text pops in distinct spots
	local defaultOffsetX = (rewardType == "Coins") and -80 or 80
	local defaultOffsetY = (rewardType == "Coins") and 0 or 32

	if sourceButton then
		local buttonPos = sourceButton.AbsolutePosition
		local buttonSize = sourceButton.AbsoluteSize
		centerX = buttonPos.X + buttonSize.X / 2 + defaultOffsetX
		centerY = buttonPos.Y + buttonSize.Y / 2 + defaultOffsetY
	elseif sourcePosition then
		centerX = sourcePosition.X + defaultOffsetX
		centerY = sourcePosition.Y + defaultOffsetY
	else
		-- Default to center of parent
		centerX = sz.X * 0.5 + defaultOffsetX
		centerY = sz.Y * 0.42 + defaultOffsetY
	end
	local center = UDim2.fromOffset(centerX, centerY)

	-- Play spawn sound
	playUiSfx("CoinSpawn", 1.0)

	-- Calculate target position
	local targetPos = targetAnchor.AbsolutePosition
	local targetSize = targetAnchor.AbsoluteSize
	local target = UDim2.fromOffset(targetPos.X + targetSize.X / 2, targetPos.Y + targetSize.Y / 2)

	-- Create count and distribution like original
	local count = math.clamp(math.min(amount, 18), 1, 18)
	local baseSize = 20

	-- Evenly distribute amount across currency items for dopaminic counting
	local per = math.floor(amount / count)
	local remainder = amount - (per * count)
	local arrived = 0

	-- Total popup under the burst origin; stays visible until all items arrive
	local txt = Instance.new("TextLabel")
	txt.Name = "CurrencyAwardText"
	txt.BackgroundTransparency = 1
	txt.Text = "+" .. tostring(amount)
	txt.Font = Enum.Font.GothamBlack
	txt.TextSize = 28
	txt.TextColor3 = (rewardType == "Coins") and Color3.fromRGB(255, 235, 120) or Color3.fromRGB(120, 235, 255)
	txt.AnchorPoint = Vector2.new(0.5, 0.5)
	local belowCenter = UDim2.fromOffset(centerX, centerY + ((rewardType == "Coins") and 48 or 16))
	txt.Position = belowCenter
	txt.ZIndex = 21
	txt.Parent = parent

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(40, 24, 8)
	stroke.Transparency = 0.15
	stroke.Parent = txt

	local s = Instance.new("UIScale")
	s.Scale = 0.8
	s.Parent = txt

	local tIn = TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(s, tIn, { Scale = 1.12 }):Play()

	local tOut = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	-- Spawn individual currency items with scatter pattern
	for i = 1, count do
		local spreadX = math.random(-120, 120)
		local spreadY = math.random(-80, 60)
		local from = UDim2.fromOffset(centerX + spreadX, centerY + spreadY)
		local addThis = per + ((i <= remainder) and 1 or 0)

		spawnCurrencyAt(parent, from, target, baseSize + math.random(-4, 8), imageId, function()
			playUiSfx("CoinArrive", 1.0)
			-- Always bump the label for visual feedback
			bumpCurrencyLabel(targetAnchor, flashColor)

			-- For coins, notify CurrencyUI that a coin arrived so it can increment numbers
			if rewardType == "Coins" then
				CoinArrived:Fire(addThis)
			end

			arrived = arrived + 1

			if arrived == count then
				-- Fade and cleanup popup when all items have arrived
				local endPos = UDim2.fromOffset(belowCenter.X.Offset, belowCenter.Y.Offset - 18)
				if txt and txt.Parent then
					TweenService:Create(txt, tOut, { TextTransparency = 1, Position = endPos }):Play()
				end
				if stroke and stroke.Parent then
					TweenService:Create(stroke, tOut, { Transparency = 1 }):Play()
				end
				task.delay(tOut.Time + 0.02, function()
					if txt and txt.Parent then
						txt:Destroy()
					end
				end)
			end
		end)
	end
end

-- Convenience functions for specific currency types
function RewardAnimations.spawnCoinBurst(amount, sourcePosition, sourceButton)
	return RewardAnimations.spawnRewardBurst(amount, "Coins", sourcePosition, sourceButton)
end

function RewardAnimations.spawnDiamondBurst(amount, sourcePosition, sourceButton)
	return RewardAnimations.spawnRewardBurst(amount, "Diamonds", sourcePosition, sourceButton)
end

return RewardAnimations
