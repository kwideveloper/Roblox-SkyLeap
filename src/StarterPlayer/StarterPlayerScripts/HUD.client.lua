-- Simple HUD for stamina and speed, adjusted to existing UI

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- UI bindings (rebound after respawn if ScreenGui has ResetOnSpawn=true)
local screenGui
local container
local barBg
local speedText
local barLabel
local barFill
local costsText
local iconsFrame
local dashIcon
local slideIcon
local wallIcon
local bhFrame
local bhLabel

local function bindUi()
	-- Attempt to (re)bind all references; do not create UI elements
	local sg = playerGui:FindFirstChild("Stamina") or playerGui:WaitForChild("Stamina")
	screenGui = sg
	container = screenGui:FindFirstChild("Container") or screenGui:WaitForChild("Container")
	barBg = container:FindFirstChild("StaminaBg") or container:WaitForChild("StaminaBg")
	speedText = container:FindFirstChild("SpeedText") or container:WaitForChild("SpeedText")
	barLabel = container:FindFirstChild("StaminaLabel") or container:WaitForChild("StaminaLabel")
	barFill = barBg:FindFirstChild("StaminaFill") -- must exist in UI
	costsText = container:FindFirstChild("CostsText") -- optional
	iconsFrame = container:FindFirstChild("ActionIcons") -- optional
	dashIcon = iconsFrame and iconsFrame:FindFirstChild("Dash") or nil
	slideIcon = iconsFrame and iconsFrame:FindFirstChild("Slide") or nil
	wallIcon = iconsFrame and iconsFrame:FindFirstChild("Wall") or nil

	-- Create a minimal BunnyHop indicator if not present
	bhFrame = container:FindFirstChild("BunnyHop")
	if not bhFrame then
		bhFrame = Instance.new("Frame")
		bhFrame.Name = "BunnyHop"
		bhFrame.Size = UDim2.new(0, 140, 0, 28)
		bhFrame.Position = UDim2.new(1, -150, 1, -34)
		bhFrame.AnchorPoint = Vector2.new(0, 0)
		bhFrame.BackgroundTransparency = 0.25
		bhFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
		bhFrame.BorderSizePixel = 0
		bhFrame.Parent = container
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = bhFrame
	end
	bhLabel = bhFrame:FindFirstChild("Text")
	if not bhLabel then
		bhLabel = Instance.new("TextLabel")
		bhLabel.Name = "Text"
		bhLabel.Size = UDim2.new(1, -10, 1, 0)
		bhLabel.Position = UDim2.new(0, 5, 0, 0)
		bhLabel.BackgroundTransparency = 1
		bhLabel.TextScaled = true
		bhLabel.Font = Enum.Font.GothamBold
		bhLabel.TextColor3 = Color3.fromRGB(200, 235, 255)
		bhLabel.Text = "BH: 0"
		bhLabel.Parent = bhFrame
	end

	-- Minimal style HUD removed: rely on StarterGui/StyleUI instead

	-- Rebind again if ScreenGui gets replaced on next spawn
	screenGui.AncestryChanged:Connect(function()
		if not screenGui:IsDescendantOf(playerGui) then
			task.defer(bindUi)
		end
	end)
end

bindUi()

-- Rebind when a new Stamina gui is added (covers ResetOnSpawn=true)
playerGui.ChildAdded:Connect(function(child)
	if child.Name == "Stamina" then
		bindUi()
	end
end)

local function formatCosts()
	local C = require(ReplicatedStorage.Movement.Config)
	return string.format(
		"Q Dash:%d  C Slide:%d  Space Wall:%d",
		C.DashStaminaCost or 0,
		C.SlideStaminaCost or 0,
		C.WallJumpStaminaCost or 0
	)
end

local function flashBar(color)
	if not barFill then
		return
	end
	local original = barFill.BackgroundColor3
	barFill.BackgroundColor3 = color
	TweenService:Create(barFill, TweenInfo.new(0.4), { BackgroundColor3 = original }):Play()
end

local function colorForStaminaRatio(r)
	-- Green (high) > Yellow (mid) > Orange (low) > Red (very low)
	if r >= 0.7 then
		return Color3.fromRGB(0, 85, 255)
	elseif r >= 0.45 then
		return Color3.fromRGB(235, 200, 60)
	elseif r >= 0.25 then
		return Color3.fromRGB(255, 140, 0)
	else
		return Color3.fromRGB(220, 60, 60)
	end
end

local function getClientState()
	local folder = ReplicatedStorage:FindFirstChild("ClientState")
	return folder,
		folder and folder:FindFirstChild("Stamina") or nil,
		folder and folder:FindFirstChild("Speed") or nil,
		folder and folder:FindFirstChild("IsSprinting") or nil,
		folder and folder:FindFirstChild("IsSliding") or nil,
		folder and folder:FindFirstChild("IsAirborne") or nil,
		folder and folder:FindFirstChild("IsWallRunning") or nil,
		folder and folder:FindFirstChild("IsWallSliding") or nil,
		folder and folder:FindFirstChild("IsVaulting") or nil,
		folder and folder:FindFirstChild("IsMantling") or nil,
		folder and folder:FindFirstChild("IsClimbing") or nil,
		folder and folder:FindFirstChild("IsZiplining") or nil,
		folder and folder:FindFirstChild("BunnyHopStacks") or nil,
		folder and folder:FindFirstChild("BunnyHopFlash") or nil
end

-- Action icons (UI elements) - use existing UI only
-- Preserve original frame BG configured in Studio; toggle frame BG color per availability
local frameDefaults = {}
local function captureFrameDefaults(frame)
	frameDefaults[frame] = frame.BackgroundColor3
	return frameDefaults[frame]
end

local function setIconState(frame, enabled)
	if typeof(frame) ~= "Instance" then
		return
	end
	local defaultBg = frameDefaults[frame] or captureFrameDefaults(frame)
	if enabled then
		frame.BackgroundTransparency = 0
	else
		frame.BackgroundTransparency = 0.7
	end
end

local function update()
	if not screenGui or not container or not barBg or not speedText or not barLabel then
		return
	end
	local C = require(ReplicatedStorage.Movement.Config)
	local zombieTagActive = player:GetAttribute("ZombieTagActive") == true
	local staminaSystemOn = C.StaminaEnabled == true or zombieTagActive
	barBg.Visible = staminaSystemOn
	barLabel.Visible = staminaSystemOn
	if costsText then
		costsText.Visible = staminaSystemOn
	end
	if staminaSystemOn then
		if not barFill then
			barFill = barBg:FindFirstChild("StaminaFill")
			if not barFill then
				return
			end
		end
	else
		if not barFill then
			barFill = barBg:FindFirstChild("StaminaFill")
		end
	end

	local folder, staminaValue, speedValue, isSprinting, isSliding, isAirborne, isWallRunning, isWallSliding, isVaulting, isMantling, isClimbing, isZiplining, bhStacks, bhFlash =
		getClientState()
	if not folder then
		return
	end
	local staminaCurrent = staminaValue and staminaValue.Value or 0
	if not staminaSystemOn then
		staminaCurrent = C.StaminaMax
	end
	local maxStamInst = folder:FindFirstChild("MaxStamina")
	local staminaMax = C.StaminaMax
	if maxStamInst and typeof(maxStamInst.Value) == "number" and maxStamInst.Value > 0 then
		staminaMax = maxStamInst.Value
	end
	local ratio = 0
	if staminaMax > 0 then
		ratio = math.clamp(staminaCurrent / staminaMax, 0, 1)
	end
	if staminaSystemOn and barFill then
		barFill.Size = UDim2.new(ratio, 0, 1, 0)
		barFill.BackgroundColor3 = colorForStaminaRatio(ratio)
	end
	speedText.Text = string.format("Speed: %d", speedValue and math.floor(speedValue.Value + 0.5) or 0)
	if staminaSystemOn and costsText then
		costsText.Text = formatCosts()
	end

	if staminaSystemOn then
		local minCost = math.min(C.DashStaminaCost or 0, C.SlideStaminaCost or 0, C.WallJumpStaminaCost or 0)
		if staminaCurrent < minCost then
			flashBar(Color3.fromRGB(220, 80, 80))
		end
	end

	-- Icons enabled/disabled based on stamina, state, and cooldowns
	local Abilities = require(ReplicatedStorage.Movement.Abilities)
	local canDash = false
	do
		local character = game:GetService("Players").LocalPlayer.Character
		if character and staminaCurrent >= (C.DashStaminaCost or 0) then
			local blocked = false
			if (isWallRunning and isWallRunning.Value) or (isWallSliding and isWallSliding.Value) then
				blocked = true
			end
			if (isVaulting and isVaulting.Value) or (isMantling and isMantling.Value) then
				blocked = true
			end
			if (isClimbing and isClimbing.Value) or (isZiplining and isZiplining.Value) then
				blocked = true
			end
			if (not blocked) and Abilities.isDashAvailable and Abilities.isDashAvailable(character) then
				canDash = true
			end
		end
	end
	local canSlide = (isSprinting and isSprinting.Value)
		and staminaCurrent >= (C.SlideStaminaCost or 0)
		and Abilities.isSlideReady()
		and not (isWallRunning and isWallRunning.Value)
		and not (isWallSliding and isWallSliding.Value)
		and not (isAirborne and isAirborne.Value)
	-- Wall jump/hop icon: enabled only when action is truly available
	local canWall = false
	do
		local WallRun = require(ReplicatedStorage.Movement.WallRun)
		local WallJump = require(ReplicatedStorage.Movement.WallJump)
		local player = game:GetService("Players").LocalPlayer
		local character = player.Character
		if character then
			local readyBySlide = WallJump.canWallJump(character)
			local readyByRun = WallRun.isActive(character)
			local near = WallRun.isNearWall(character) or WallJump.isNearWall(character)
			-- Enforce stamina and memory rule
			local ok = (staminaCurrent >= (C.WallJumpStaminaCost or 0)) and near and (readyBySlide or readyByRun)
			local WallMemory = require(ReplicatedStorage.Movement.WallMemory)
			local last = WallMemory.getLast(character)
			local currentWall = WallJump.getNearbyWall(character)
			if last and currentWall and last == currentWall then
				ok = false
			end
			canWall = ok
		end
	end
	if dashIcon then
		setIconState(dashIcon, canDash)
	end
	if slideIcon then
		setIconState(slideIcon, canSlide)
	end
	if wallIcon then
		setIconState(wallIcon, canWall)
	end

	-- BunnyHop indicator
	if bhLabel then
		local stacks = (bhStacks and bhStacks.Value) or 0
		bhLabel.Text = string.format("BH: %d", stacks)
		if bhFlash and bhFlash.Value == true then
			flashBar(Color3.fromRGB(80, 200, 255))
			-- also briefly flash the BunnyHop frame
			bhFrame.BackgroundColor3 = Color3.fromRGB(40, 120, 255)
			TweenService:Create(bhFrame, TweenInfo.new(0.25), { BackgroundColor3 = Color3.fromRGB(30, 30, 30) }):Play()
		end
	end

	-- Style HUD is handled by StarterGui/StyleUI
end

-- Heartbeat-driven update for snappy UI
game:GetService("RunService").RenderStepped:Connect(update)
