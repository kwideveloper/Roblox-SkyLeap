-- Head tracking: rotate only the neck based on camera direction (no body rotation)

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local root = character:WaitForChild("HumanoidRootPart")

-- Find the Neck Motor6D (R15/R6 compatible search)
local function findNeck(char)
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("Motor6D") and d.Name == "Neck" then
			return d
		end
	end
	-- fallback: Motor6D whose Part1 is Head
	local head = char:FindFirstChild("Head")
	if head then
		for _, d in ipairs(char:GetDescendants()) do
			if d:IsA("Motor6D") and d.Part1 == head then
				return d
			end
		end
	end
	return nil
end

local neck = findNeck(character)
local waist
for _, d in ipairs(character:GetDescendants()) do
	if d:IsA("Motor6D") and d.Name == "Waist" then
		waist = d
		break
	end
end
if not neck then
	return
end

local camera = workspace.CurrentCamera
local baseC0 = neck.C0
local baseWaistC0 = waist and waist.C0 or nil

-- Limits
local maxYaw = math.rad(60)
local maxPitch = math.rad(30)

RunService.RenderStepped:Connect(function(dt)
	if not character or not character.Parent then
		return
	end
	if not neck or not neck.Parent then
		return
	end

	-- Check if ledge hanging - during ledge hang, allow head tracking but disable torso rotation
	local isLedgeHanging = false
	pcall(function()
		local cs = ReplicatedStorage:FindFirstChild("ClientState")
		local hangFlag = cs and cs:FindFirstChild("IsLedgeHanging")
		isLedgeHanging = hangFlag and hangFlag.Value == true
	end)

	local yaw = 0
	if isLedgeHanging then
		-- Sliding on a ledge moves/animates the torso; camera-relative head IK reads as camera shake — hold neutral
		local settle = 1 - math.exp(-(14 * (dt or 0)))
		neck.C0 = neck.C0:Lerp(baseC0, settle)
	else
		local camCF = camera.CFrame
		-- Camera direction in neck.Part0 local space
		local lookLocal
		if neck.Part0 then
			-- Use the direction AWAY from the camera so the head looks where the camera is looking, not at the camera
			lookLocal = neck.Part0.CFrame:VectorToObjectSpace(-camCF.LookVector)
		else
			-- fallback to root frame if Part0 missing
			lookLocal = root.CFrame:VectorToObjectSpace(-camCF.LookVector)
		end

		-- Compute yaw (left/right) and pitch (up/down) like reference snippet
		-- Use asin on local X/Y so signs match typical Roblox rigs
		yaw = math.asin(math.clamp(lookLocal.X, -1, 1))
		local pitch = -math.asin(math.clamp(lookLocal.Y, -1, 1))

		-- Clamp
		yaw = math.clamp(yaw, -maxYaw, maxYaw)
		pitch = math.clamp(pitch, -maxPitch, maxPitch)

		-- Smooth blend (delta-time based), apply yaw then pitch (order matters)
		local headSpeed = 8 -- higher = snappier, lower = smoother
		local headAlpha = 1 - math.exp(-(headSpeed * (dt or 0)))
		local target = baseC0 * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
		neck.C0 = neck.C0:Lerp(target, headAlpha)
	end

	-- Torso/waist rotation when looking far to the sides/back
	-- Skip torso rotation if ledge hanging, but allow head tracking
	if waist and baseWaistC0 and not isLedgeHanging then
		local yawDeg = math.deg(math.abs(yaw))
		local threshold = 50 -- start rotating torso after this yaw
		if yawDeg > threshold then
			local maxTorsoYaw = math.rad(25)
			local t = math.clamp((yawDeg - threshold) / (60 - threshold), 0, 1)
			local applyYaw = math.clamp(yaw * 0.5 * t, -maxTorsoYaw, maxTorsoYaw)
			local torsoTarget = baseWaistC0 * CFrame.Angles(0, applyYaw, 0)
			local waistSpeed = 6
			local waistAlpha = 1 - math.exp(-(waistSpeed * (dt or 0)))
			waist.C0 = waist.C0:Lerp(torsoTarget, waistAlpha)
		else
			local waistReturnSpeed = 5
			local waistAlphaBack = 1 - math.exp(-(waistReturnSpeed * (dt or 0)))
			waist.C0 = waist.C0:Lerp(baseWaistC0, waistAlphaBack)
		end
	elseif waist and baseWaistC0 and isLedgeHanging then
		-- During ledge hang, keep torso in neutral position
		local waistReturnSpeed = 8
		local waistAlpha = 1 - math.exp(-(waistReturnSpeed * (dt or 0)))
		waist.C0 = waist.C0:Lerp(baseWaistC0, waistAlpha)
	end
end)
