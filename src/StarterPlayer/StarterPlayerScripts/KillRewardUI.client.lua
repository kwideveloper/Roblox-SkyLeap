local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local killRewardEvent = remotes:WaitForChild("KillRewardEvent")

local gui = playerGui:FindFirstChild("KillRewardUI")
if not gui or not gui:IsA("ScreenGui") then
	gui = Instance.new("ScreenGui")
	gui.Name = "KillRewardUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 210
	gui.Parent = playerGui
end

local eventLabel = gui:FindFirstChild("EventLabel", true)
local pointsLabel = gui:FindFirstChild("PointsLabel", true)
if not eventLabel or not eventLabel:IsA("TextLabel") then
	eventLabel = Instance.new("TextLabel")
	eventLabel.Name = "EventLabel"
	eventLabel.BackgroundTransparency = 1
	eventLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	eventLabel.Position = UDim2.fromScale(0.5, 0.355)
	eventLabel.Size = UDim2.fromOffset(520, 56)
	eventLabel.Font = Enum.Font.GothamBlack
	eventLabel.TextScaled = false
	eventLabel.TextSize = 44
	eventLabel.TextColor3 = Color3.fromRGB(255, 215, 90)
	eventLabel.TextStrokeTransparency = 0.15
	eventLabel.TextStrokeColor3 = Color3.fromRGB(15, 15, 15)
	eventLabel.TextTransparency = 1
	eventLabel.Text = ""
	eventLabel.ZIndex = 40
	eventLabel.Parent = gui
end
if not pointsLabel or not pointsLabel:IsA("TextLabel") then
	pointsLabel = Instance.new("TextLabel")
	pointsLabel.Name = "PointsLabel"
	pointsLabel.BackgroundTransparency = 1
	pointsLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	pointsLabel.Position = UDim2.fromScale(0.5, 0.405)
	pointsLabel.Size = UDim2.fromOffset(420, 42)
	pointsLabel.Font = Enum.Font.GothamBold
	pointsLabel.TextScaled = false
	pointsLabel.TextSize = 28
	pointsLabel.TextColor3 = Color3.fromRGB(255, 252, 232)
	pointsLabel.TextStrokeTransparency = 0.2
	pointsLabel.TextStrokeColor3 = Color3.fromRGB(20, 20, 20)
	pointsLabel.TextTransparency = 1
	pointsLabel.Text = ""
	pointsLabel.ZIndex = 39
	pointsLabel.Parent = gui
end

local eventScale = eventLabel:FindFirstChildOfClass("UIScale")
if not eventScale then
	eventScale = Instance.new("UIScale")
	eventScale.Scale = 1
	eventScale.Parent = eventLabel
end
local pointsScale = pointsLabel:FindFirstChildOfClass("UIScale")
if not pointsScale then
	pointsScale = Instance.new("UIScale")
	pointsScale.Scale = 1
	pointsScale.Parent = pointsLabel
end

local activeEventToken = 0
local activePointsToken = 0

local function animateEventText(text: string)
	activeEventToken += 1
	local token = activeEventToken
	eventLabel.Text = text
	eventLabel.TextTransparency = 1
	eventScale.Scale = 1.7

	TweenService:Create(eventScale, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1.0 }):Play()
	TweenService:Create(eventLabel, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextTransparency = 0 }):Play()

	task.delay(0.55, function()
		if token ~= activeEventToken then
			return
		end
		TweenService:Create(
			eventScale,
			TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Scale = 0.68 }
		):Play()
	end)

	task.delay(0.78, function()
		if token ~= activeEventToken then
			return
		end
		TweenService:Create(
			eventLabel,
			TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ TextTransparency = 1 }
		):Play()
	end)
end

local function animatePointsText(text: string)
	activePointsToken += 1
	local token = activePointsToken
	pointsLabel.Text = text
	pointsLabel.TextTransparency = 1
	pointsScale.Scale = 1.3

	TweenService:Create(pointsScale, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1.0 }):Play()
	TweenService:Create(pointsLabel, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextTransparency = 0 }):Play()

	task.delay(0.95, function()
		if token ~= activePointsToken then
			return
		end
		TweenService:Create(
			pointsScale,
			TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Scale = 0.7 }
		):Play()
		TweenService:Create(
			pointsLabel,
			TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ TextTransparency = 1 }
		):Play()
	end)
end

local function buildEventHeadline(payload: any): string?
	if type(payload.collateralLabel) == "string" and payload.collateralLabel ~= "" then
		return payload.collateralLabel
	end
	if payload.isHeadshot == true then
		return "HEADSHOT"
	end
	if type(payload.multiKillLabel) == "string" and payload.multiKillLabel ~= "" then
		return payload.multiKillLabel
	end
	if type(payload.streakLabel) == "string" and payload.streakLabel ~= "" then
		return payload.streakLabel
	end
	return nil
end

killRewardEvent.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end
	local eventType = payload.eventType
	if eventType == "KillRegistered" then
		local headline = buildEventHeadline(payload)
		if headline then
			animateEventText(headline)
		end
		local gained = tonumber(payload.coinsGained) or 0
		local pending = tonumber(payload.pendingCoins) or 0
		local kills = tonumber(payload.killCount) or 1
		animatePointsText(string.format("+%d  (x%d)  bank: %d", gained, kills, pending))
	elseif eventType == "Collateral" then
		local headline = buildEventHeadline(payload) or "COLLATERAL"
		animateEventText(headline)
		local gained = tonumber(payload.coinsGained) or 0
		local pending = tonumber(payload.pendingCoins) or 0
		local cKills = tonumber(payload.collateralKills) or 2
		animatePointsText(string.format("+%d  (%d IN 1 SHOT)  bank: %d", gained, cKills, pending))
	elseif eventType == "Payout" then
		local awarded = tonumber(payload.awardedCoins) or 0
		animatePointsText(string.format("+%d COINS", awarded))
	end
end)
