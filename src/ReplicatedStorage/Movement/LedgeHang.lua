-- Ledge Hanging system: allows player to hang from edges and move horizontally
-- Triggered when mantle fails due to insufficient clearance above

local Config = require(game:GetService("ReplicatedStorage").Movement.Config)
local Animations = require(game:GetService("ReplicatedStorage").Movement.Animations)
local SharedUtils = require(game:GetService("ReplicatedStorage").SharedUtils)
local ParkourSurfaceGate = require(game:GetService("ReplicatedStorage").Movement.ParkourSurfaceGate)
local RunService = game:GetService("RunService")

-- Get remotes for server synchronization
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local LedgeHangStart = Remotes:WaitForChild("LedgeHangStart")
local LedgeHangMove = Remotes:WaitForChild("LedgeHangMove")
local LedgeHangStop = Remotes:WaitForChild("LedgeHangStop")

local LedgeHang = {}

local activeHangs = {} -- [character] = hangData
local otherPlayersHangs = {} -- [player] = hangData (for other players' ledge hangs)

-- Ledge-specific cooldown system
local ledgeCooldowns = {} -- [character][ledgeInstance] = cooldownTime

-- Clean up old cooldowns for ledges that are far away
local function cleanupOldCooldowns(character)
	if not ledgeCooldowns[character] then
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	local currentTime = os.clock()
	local cleanupDistance = 20 -- studs

	for ledgeInstance, cooldownTime in pairs(ledgeCooldowns[character]) do
		-- Clean up if cooldown expired or ledge is far away
		if
			cooldownTime < currentTime
			or (ledgeInstance.Parent and (root.Position - ledgeInstance.Position).Magnitude > cleanupDistance)
		then
			ledgeCooldowns[character][ledgeInstance] = nil
		end
	end
end

-- Handle other players' ledge hang synchronization
local function handleOtherPlayerHangStart(player, hangPosition, ledgeY, forwardDirection, surfaceNormal)
	local character = player.Character
	if not character then
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return
	end

	-- Store other player's hang data
	otherPlayersHangs[player] = {
		character = character,
		hangPosition = hangPosition,
		ledgeY = ledgeY,
		forwardDirection = forwardDirection,
		surfaceNormal = surfaceNormal,
		startTime = os.clock(),
	}

	-- Set character state for other players
	humanoid.AutoRotate = false
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)

	-- Position character
	root.CFrame = CFrame.lookAt(hangPosition, hangPosition + forwardDirection)
	root.AssemblyLinearVelocity = Vector3.new()
	root.Anchored = true

	-- Disable collisions for other parts
	for _, part in ipairs(character:GetChildren()) do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			part.CanCollide = false
		end
	end

	if Config.DebugLedgeHang then
		print("[LedgeHang] Other player", player.Name, "started ledge hang")
	end
end

local function handleOtherPlayerHangMove(player, newPosition, forwardDirection)
	local hangData = otherPlayersHangs[player]
	if not hangData then
		return
	end

	local character = hangData.character
	if not character then
		otherPlayersHangs[player] = nil
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		otherPlayersHangs[player] = nil
		return
	end

	-- Update hang data
	hangData.hangPosition = newPosition
	hangData.forwardDirection = forwardDirection

	-- Update character position
	root.CFrame = CFrame.lookAt(newPosition, newPosition + forwardDirection)
end

local function handleOtherPlayerHangStop(player, isManualRelease)
	-- Check if this is the local player being released by server
	local localPlayer = game:GetService("Players").LocalPlayer
	if player == localPlayer then
		-- This is the local player being released by server (e.g., stamina depletion)
		-- Force stop the local hang
		LedgeHang.stop(localPlayer.Character, isManualRelease)
		return
	end

	local hangData = otherPlayersHangs[player]
	if not hangData then
		return
	end

	local character = hangData.character
	if not character then
		otherPlayersHangs[player] = nil
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		otherPlayersHangs[player] = nil
		return
	end

	-- Restore character state
	humanoid.AutoRotate = true
	root.Anchored = false

	-- Restore collisions
	for _, part in ipairs(character:GetChildren()) do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			part.CanCollide = true
		end
	end

	-- Clear hang data
	otherPlayersHangs[player] = nil

	if Config.DebugLedgeHang then
		print("[LedgeHang] Other player", player.Name, "stopped ledge hang")
	end
end

-- Connect to remote events for other players' synchronization
LedgeHangStart.OnClientEvent:Connect(handleOtherPlayerHangStart)
LedgeHangMove.OnClientEvent:Connect(handleOtherPlayerHangMove)
LedgeHangStop.OnClientEvent:Connect(handleOtherPlayerHangStop)

local function getCharacterParts(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return root, humanoid
end

-- Check if there's enough clearance above for a full mantle
local function hasEnoughClearanceAbove(root, ledgeY, forwardDirection)
	local params = SharedUtils.createParkourRaycastParams(root.Parent)

	local halfHeight = (root.Size and root.Size.Y or 2) * 0.5
	local requiredClearance = Config.LedgeHangMinClearance or 3.5 -- studs above ledge
	local checkHeight = ledgeY + requiredClearance

	-- Check multiple points above the ledge for obstacles
	local checkPoints = {
		Vector3.new(0, 0, 0), -- center
		Vector3.new(0.8, 0, 0), -- left
		Vector3.new(-0.8, 0, 0), -- right
		forwardDirection * 0.5, -- slightly forward
	}

	for _, offset in ipairs(checkPoints) do
		local checkPos = Vector3.new(root.Position.X + offset.X, checkHeight, root.Position.Z + offset.Z)
		local hit = workspace:Raycast(checkPos, Vector3.new(0, -requiredClearance, 0), params)
		if hit and hit.Position.Y > ledgeY + 0.5 then
			return false -- obstacle found above
		end
	end

	return true
end

-- Detect ledge for hanging (similar to mantle detection but with clearance check)
function LedgeHang.detectLedgeForHang(character)
	local root, humanoid = getCharacterParts(character)
	if not root or not humanoid then
		return false
	end

	-- Use similar detection as mantle but check clearance
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = SharedUtils.createParkourRaycastParams(character).FilterDescendantsInstances
	params.IgnoreWater = Config.RaycastIgnoreWater

	local origin = root.Position
	local forward = root.CFrame.LookVector
	local distance = Config.LedgeHangDetectionDistance or 3.5

	local hit = workspace:Raycast(origin, forward * distance, params)
	if not hit or not hit.Instance or not hit.Instance.CanCollide then
		return false
	end
	if not ParkourSurfaceGate.isMechanicAllowed(hit.Instance, "LedgeHang") then
		return false
	end

	-- Find top of the obstacle
	local topY = nil
	local checkOrigin = Vector3.new(hit.Position.X, hit.Position.Y + 5, hit.Position.Z)
	local downRay = workspace:Raycast(checkOrigin, Vector3.new(0, -10, 0), params)
	if downRay then
		topY = downRay.Position.Y
	end

	if not topY then
		return false
	end

	-- Check if ledge is at appropriate height
	local waistY = root.Position.Y
	local aboveWaist = topY - waistY
	local minH = Config.LedgeHangMinHeight or 1.5
	local maxH = Config.LedgeHangMaxHeight or 4.0

	if aboveWaist < minH or aboveWaist > maxH then
		return false
	end

	-- Check if there's insufficient clearance above (this makes it a hang candidate)
	local forwardDir = Vector3.new(forward.X, 0, forward.Z).Unit
	local hasClearance = hasEnoughClearanceAbove(root, topY, forwardDir)

	if hasClearance then
		-- Enough clearance, try mantle instead
		if Config.DebugLedgeHang then
			print("[LedgeHang] Sufficient clearance detected, attempting mantle instead of hang")
		end

		-- Try mantle first
		local Abilities = require(game:GetService("ReplicatedStorage").Movement.Abilities)
		if Abilities and Abilities.tryMantle then
			local mantleResult = Abilities.tryMantle(character)
			if mantleResult then
				return false -- Mantle succeeded, don't do ledge hang
			end
		end

		-- If mantle failed, still return false to avoid ledge hang
		return false
	end

	return true, hit, topY, forwardDir
end

-- Alternative tryStart that uses mantle detection data (more reliable)
function LedgeHang.tryStartFromMantleData(character, hitRes, ledgeY)
	if activeHangs[character] then
		return false
	end

	-- Global cooldown gate
	local globalCooldownActive = false
	pcall(function()
		local rs = game:GetService("ReplicatedStorage")
		local cs = rs:FindFirstChild("ClientState")
		local lastHangTime = cs and cs:FindFirstChild("LastLedgeHangTime")
		if lastHangTime and lastHangTime.Value > os.clock() then
			globalCooldownActive = true
			if Config.DebugLedgeHang then
				local remaining = lastHangTime.Value - os.clock()
				print(
					string.format(
						"[LedgeHang] Global cooldown active in tryStartFromMantleData: %.2fs remaining",
						remaining
					)
				)
			end
		end
	end)
	if globalCooldownActive then
		return false
	end

	-- Clean up old cooldowns
	cleanupOldCooldowns(character)

	-- Check ledge-specific cooldown
	local ledgeInstance = hitRes.Instance
	if ledgeInstance then
		-- Initialize character cooldowns if needed
		if not ledgeCooldowns[character] then
			ledgeCooldowns[character] = {}
		end

		-- Check if this specific ledge is on cooldown
		local cooldownTime = ledgeCooldowns[character][ledgeInstance]
		if cooldownTime and cooldownTime > os.clock() then
			-- Don't spam debug logs for cooldown checks
			return false
		end
	end

	-- Check wall-specific cooldown
	local wallInstance = hitRes and hitRes.Instance
	if wallInstance and hasWallCooldown(character, wallInstance) then
		return false
	end

	if hitRes and hitRes.Instance and not ParkourSurfaceGate.isMechanicAllowed(hitRes.Instance, "LedgeHang") then
		return false
	end

	local root, humanoid = getCharacterParts(character)
	if not root or not humanoid then
		return false
	end

	-- Calculate forward direction from hit normal (for proper wall facing)
	local forwardDir
	if hitRes.Normal then
		-- Use the hit normal to determine proper facing direction
		-- The character should face opposite to the wall normal
		forwardDir = Vector3.new(-hitRes.Normal.X, 0, -hitRes.Normal.Z)
		if forwardDir.Magnitude > 0.01 then
			forwardDir = forwardDir.Unit
		else
			-- Fallback to position-based calculation
			local toWall = (hitRes.Position - root.Position)
			forwardDir = Vector3.new(toWall.X, 0, toWall.Z)
			if forwardDir.Magnitude > 0.01 then
				forwardDir = forwardDir.Unit
			else
				forwardDir = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
			end
		end
	else
		-- Fallback to position-based calculation
		local toWall = (hitRes.Position - root.Position)
		forwardDir = Vector3.new(toWall.X, 0, toWall.Z)
		if forwardDir.Magnitude > 0.01 then
			forwardDir = forwardDir.Unit
		else
			forwardDir = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
		end
	end

	return LedgeHang.startHang(character, hitRes, ledgeY, forwardDir)
end

function LedgeHang.tryStart(character)
	if activeHangs[character] then
		return false
	end

	-- Check global cooldown (especially for manual releases)
	local globalCooldownActive = false
	pcall(function()
		local rs = game:GetService("ReplicatedStorage")
		local cs = rs:FindFirstChild("ClientState")
		local lastHangTime = cs and cs:FindFirstChild("LastLedgeHangTime")
		if lastHangTime and lastHangTime.Value > os.clock() then
			globalCooldownActive = true
			if Config.DebugLedgeHang then
				local remaining = lastHangTime.Value - os.clock()
				print(string.format("[LedgeHang] Global cooldown active: %.2fs remaining", remaining))
			end
		end
	end)

	if globalCooldownActive then
		return false
	end

	-- Clean up old cooldowns
	cleanupOldCooldowns(character)

	local ok, hitRes, ledgeY, forwardDir = LedgeHang.detectLedgeForHang(character)
	if not ok then
		return false
	end

	-- Check ledge-specific cooldown
	local ledgeInstance = hitRes.Instance
	if ledgeInstance then
		-- Initialize character cooldowns if needed
		if not ledgeCooldowns[character] then
			ledgeCooldowns[character] = {}
		end

		-- Check if this specific ledge is on cooldown
		local cooldownTime = ledgeCooldowns[character][ledgeInstance]
		if cooldownTime and cooldownTime > os.clock() then
			-- Don't spam debug logs for cooldown checks
			return false
		end
	end

	-- Check wall-specific cooldown
	local wallInstance = hitRes and hitRes.Instance
	if wallInstance and hasWallCooldown(character, wallInstance) then
		return false
	end

	return LedgeHang.startHang(character, hitRes, ledgeY, forwardDir)
end

-- Check if there's space above the ledge for movement
local function checkLedgeSpace(ledgePos, normal, raycastParams)
	local spaceCheck = workspace:Raycast(ledgePos + normal * 1, Vector3.new(0, 3, 0), raycastParams)
	return spaceCheck == nil -- Return true if there's space above
end

-- Check for corner movement (left/right)
local function checkCornerMovement(character, direction, raycastParams)
	local head = character:FindFirstChild("Head")
	if not head then
		return false
	end

	local moveRay = workspace:Raycast(
		head.CFrame.Position,
		head.CFrame.RightVector * direction + head.CFrame.LookVector * 8,
		raycastParams
	)
	if moveRay and moveRay.Instance then
		-- Check if there's space above this new ledge
		local localPos = moveRay.Instance.CFrame:PointToObjectSpace(moveRay.Position)
		local localLedgePos = Vector3.new(localPos.X, moveRay.Instance.Size.Y / 2, localPos.Z)
		local newLedgePos = moveRay.Instance.CFrame:PointToWorldSpace(localLedgePos)

		if checkLedgeSpace(newLedgePos, moveRay.Normal, raycastParams) then
			return true, moveRay, newLedgePos
		end
	else
		-- Check for turn around corner
		local turnRay = workspace:Raycast(
			head.CFrame.Position + Vector3.new(0, -1, 0) + head.CFrame.RightVector * direction,
			head.CFrame.RightVector * -direction + head.CFrame.LookVector * 2,
			raycastParams
		)
		if turnRay and turnRay.Instance then
			local localPos = turnRay.Instance.CFrame:PointToObjectSpace(turnRay.Position)
			local localLedgePos = Vector3.new(localPos.X, turnRay.Instance.Size.Y / 2, localPos.Z)
			local newLedgePos = turnRay.Instance.CFrame:PointToWorldSpace(localLedgePos)

			if checkLedgeSpace(newLedgePos, turnRay.Normal, raycastParams) then
				return true, turnRay, newLedgePos
			end
		end
	end

	return false
end

-- Setup IK for hands positioning on ledge
local function setupLedgeHandIK(character, hitRes, ledgeY)
	-- Check if IK is enabled
	if not Config.LedgeHangIKEnabled then
		return nil, nil, nil, nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil, nil, nil, nil
	end

	-- Create target folder for ledge hand targets
	local targetFolder = workspace:FindFirstChild("LedgeTargets") or Instance.new("Folder")
	targetFolder.Name = "LedgeTargets"
	targetFolder.Parent = workspace

	-- Function to create target parts for IK
	local function makeTarget(name, pos)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = Vector3.new(0.2, 0.2, 0.2)
		p.Transparency = 1
		p.CanCollide = false
		p.Anchored = true
		p.CFrame = CFrame.new(pos)
		p.Parent = targetFolder
		local a = Instance.new("Attachment")
		a.Name = "Attach"
		a.Parent = p
		return p, a
	end

	-- Calculate hand positions on the ledge
	local hitPos = hitRes.Position
	local normal = hitRes.Normal
	-- Calculate tangent for hand spacing (perpendicular to normal and up)
	local tangent = Vector3.yAxis:Cross(normal)
	if tangent.Magnitude < 0.05 then
		tangent = Vector3.xAxis:Cross(normal)
	end
	tangent = tangent.Unit

	-- Position hands using config values
	local heightOffset = Config.LedgeHangIKHeightOffset or 0.05
	local backOffset = Config.LedgeHangIKBackOffset or 0.1
	local handOffset = Config.LedgeHangIKHandOffset or 0.6

	local topYAdj = ledgeY + heightOffset
	local center = Vector3.new(hitPos.X, topYAdj, hitPos.Z) - (normal * backOffset)
	local leftPos = center - (tangent * handOffset)
	local rightPos = center + (tangent * handOffset)

	-- Create target parts
	local leftPart, leftAttach = makeTarget("LedgeHandL", leftPos)
	local rightPart, rightAttach = makeTarget("LedgeHandR", rightPos)

	-- Setup IK controls
	local function setupIK(side, chainRootName, endEffName, attach)
		local ik = Instance.new("IKControl")
		ik.Name = "IK_Ledge_" .. side
		ik.Type = Enum.IKControlType.Position
		ik.ChainRoot = character:FindFirstChild(chainRootName)
		ik.EndEffector = character:FindFirstChild(endEffName)
		ik.Target = attach
		pcall(function()
			ik.Priority = Enum.IKPriority.Body
		end)
		ik.Enabled = true
		ik.Weight = Config.LedgeHangIKWeight or 1.0
		ik.Parent = humanoid
		return ik
	end

	local ikL = setupIK("L", "LeftUpperArm", "LeftHand", leftAttach)
	local ikR = setupIK("R", "RightUpperArm", "RightHand", rightAttach)

	if Config.DebugLedgeHang then
		print(
			string.format(
				"[LedgeHang] IK Setup - Left: (%.2f,%.2f,%.2f), Right: (%.2f,%.2f,%.2f)",
				leftPos.X,
				leftPos.Y,
				leftPos.Z,
				rightPos.X,
				rightPos.Y,
				rightPos.Z
			)
		)
	end

	return ikL, ikR, leftPart, rightPart
end

-- Common hang start logic
function LedgeHang.startHang(character, hitRes, ledgeY, forwardDir)
	local Config = require(game:GetService("ReplicatedStorage").Movement.Config)
	local root, humanoid = getCharacterParts(character)
	if not root or not humanoid then
		return false
	end

	if Config.DebugLedgeHang then
		print(string.format("[LedgeHang] Starting hang at ledgeY=%.2f", ledgeY))
	end

	-- Calculate precise ledge edge position using the character's approach position
	-- This ensures the character grabs exactly at the edge where they reached the ledge
	local characterHalfHeight = (root.Size and root.Size.Y or 2) * 0.5
	-- Use the ledgeY passed as parameter (already calculated correctly in detection)
	-- Don't recalculate as it might use wall position instead of ledge position

	local characterPos = root.Position
	local ledgeSize = hitRes.Instance.Size
	local ledgeCFrame = hitRes.Instance.CFrame

	-- Calculate ledge edge position based on LedgeFace attribute
	local hangPos = Vector3.new(characterPos.X, characterPos.Y, characterPos.Z)
	local ledgeFace = hitRes.Instance:GetAttribute("LedgeFace")

	if ledgeFace then
		local localPos = ledgeCFrame:PointToObjectSpace(characterPos)
		local localLedgePos

		if ledgeFace == "Front" then
			localLedgePos = Vector3.new(localPos.X, ledgeSize.Y / 2, ledgeSize.Z / 2)
		elseif ledgeFace == "Back" then
			localLedgePos = Vector3.new(localPos.X, ledgeSize.Y / 2, -ledgeSize.Z / 2)
		elseif ledgeFace == "Left" then
			localLedgePos = Vector3.new(-ledgeSize.X / 2, ledgeSize.Y / 2, localPos.Z)
		elseif ledgeFace == "Right" then
			localLedgePos = Vector3.new(ledgeSize.X / 2, ledgeSize.Y / 2, localPos.Z)
		else
			localLedgePos = Vector3.new(localPos.X, ledgeSize.Y / 2, localPos.Z)
		end

		local ledgePos = ledgeCFrame:PointToWorldSpace(localLedgePos)
		-- Apply LedgeHangDistance to move away from wall and LedgeHangDropDistance to position below ledge
		local hangDistance = Config.LedgeHangDistance or 1.2
		local dropDistance = Config.LedgeHangDropDistance or 0.8
		local awayFromWall = hitRes.Normal * hangDistance
		hangPos = Vector3.new(
			ledgePos.X + awayFromWall.X,
			ledgeY - characterHalfHeight - dropDistance,
			ledgePos.Z + awayFromWall.Z
		)
	else
		-- Fallback: use hit position if no LedgeFace attribute
		local localPos = ledgeCFrame:PointToObjectSpace(hitRes.Position)
		local localLedgePos = Vector3.new(localPos.X, ledgeSize.Y / 2, localPos.Z)
		local ledgePos = ledgeCFrame:PointToWorldSpace(localLedgePos)
		-- Apply LedgeHangDistance to move away from wall and LedgeHangDropDistance to position below ledge
		local hangDistance = Config.LedgeHangDistance or 1.2
		local dropDistance = Config.LedgeHangDropDistance or 0.8
		local awayFromWall = hitRes.Normal * hangDistance
		hangPos = Vector3.new(
			ledgePos.X + awayFromWall.X,
			ledgeY - characterHalfHeight - dropDistance,
			ledgePos.Z + awayFromWall.Z
		)
	end

	-- Calculate ledge offset for proper orientation
	local ledgeOffset = CFrame.lookAt(hangPos, hangPos - hitRes.Normal)

	-- Store original collision settings
	local originalCanCollide = {}
	for _, part in ipairs(character:GetChildren()) do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			originalCanCollide[part] = part.CanCollide
			part.CanCollide = false -- Disable collisions to prevent being pushed away from wall
		end
	end

	-- Create invisible ledge part for smooth movement tracking
	local ledgePart = Instance.new("Part")
	ledgePart.Name = "LedgePart_" .. character.Name
	ledgePart.Parent = workspace
	ledgePart.Anchored = true
	ledgePart.Size = Vector3.one
	ledgePart.CFrame = ledgeOffset + Vector3.new(0, -2, 0) + ledgeOffset.LookVector * -1
	ledgePart.CanQuery = false
	ledgePart.CanCollide = false
	ledgePart.CanTouch = false
	ledgePart.Transparency = 1

	-- No IK system - only animations are used
	local ikL, ikR, leftPart, rightPart = nil, nil, nil, nil

	-- Create hang state (use normalized forward direction for consistency)
	local normalizedForwardDir = Vector3.new(forwardDir.X, 0, forwardDir.Z).Unit
	local hangData = {
		ledgePosition = hitRes.Position,
		ledgeY = ledgeY,
		forwardDirection = normalizedForwardDir, -- Use normalized direction
		surfaceNormal = hitRes.Normal,
		originalAutoRotate = humanoid.AutoRotate,
		originalWalkSpeed = humanoid.WalkSpeed,
		originalCanCollide = originalCanCollide,
		startTime = os.clock(),
		ledgeInstance = hitRes.Instance, -- Store the ledge part for boundary checking
		ledgePart = ledgePart, -- Store the invisible ledge part for movement tracking
		ledgeOffset = ledgeOffset, -- Store the ledge offset for positioning
	}

	activeHangs[character] = hangData

	-- Stop any active wallslide that might interfere with positioning
	pcall(function()
		local WallJump = require(game:GetService("ReplicatedStorage").Movement.WallJump)
		if WallJump.isWallSliding and WallJump.isWallSliding(character) then
			WallJump.stopSlide(character)
			if Config.DebugLedgeHang then
				print("[LedgeHang] Stopping wallslide before hang positioning")
			end
		end
	end)

	-- Set character state
	humanoid.AutoRotate = false
	humanoid:ChangeState(Enum.HumanoidStateType.Physics) -- Use Physics state to prevent automatic movement

	-- Ensure proper alignment with wall - use normalized forward direction
	local properCFrame = CFrame.lookAt(hangPos, hangPos + normalizedForwardDir)

	if Config.DebugLedgeHang then
		print("=== LEDGE HANG START DEBUG ===")
		print(
			string.format("[LedgeHang] Original forwardDir: (%.2f,%.2f,%.2f)", forwardDir.X, forwardDir.Y, forwardDir.Z)
		)
		print(
			string.format(
				"[LedgeHang] Normalized forwardDir: (%.2f,%.2f,%.2f)",
				normalizedForwardDir.X,
				normalizedForwardDir.Y,
				normalizedForwardDir.Z
			)
		)
		print(string.format("[LedgeHang] Hang position: (%.2f,%.2f,%.2f)", hangPos.X, hangPos.Y, hangPos.Z))
		print(
			string.format(
				"[LedgeHang] Character CFrame LookVector: (%.2f,%.2f,%.2f)",
				properCFrame.LookVector.X,
				properCFrame.LookVector.Y,
				properCFrame.LookVector.Z
			)
		)
		print(
			string.format(
				"[LedgeHang] Hit position: (%.2f,%.2f,%.2f)",
				hitRes.Position.X,
				hitRes.Position.Y,
				hitRes.Position.Z
			)
		)
		print(
			string.format("[LedgeHang] Hit normal: (%.2f,%.2f,%.2f)", hitRes.Normal.X, hitRes.Normal.Y, hitRes.Normal.Z)
		)
		print("=== END LEDGE HANG START DEBUG ===")
	end

	root.CFrame = properCFrame
	root.AssemblyLinearVelocity = Vector3.new()

	-- Anchor the root part to prevent physics interference
	root.Anchored = true

	-- Play ledge hang start animation
	local startTrack = nil
	local loopTrack = nil
	pcall(function()
		local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
		animator.Parent = humanoid

		-- Stop any conflicting animations that might be playing
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			if
				track.Name
				and (
					string.find(track.Name:lower(), "mantle")
					or string.find(track.Name:lower(), "wallslide")
					or string.find(track.Name:lower(), "wallrun")
					or string.find(track.Name:lower(), "climb")
				)
			then
				track:Stop(0.1)
			end
		end

		-- Play hang start animation
		local startAnim = Animations.get("LedgeHangStart")
		if startAnim then
			startTrack = animator:LoadAnimation(startAnim)
			if startTrack then
				startTrack.Priority = Enum.AnimationPriority.Action2 -- Maximum priority
				startTrack.Looped = false
				startTrack:Play()

				-- Adjust animation speed based on configured duration
				local desiredDuration = Config.LedgeHangStartAnimationDuration or 0.5
				local originalDuration = startTrack.Length
				if originalDuration > 0 then
					local speedMultiplier = originalDuration / desiredDuration
					startTrack:AdjustSpeed(speedMultiplier)

					if Config.DebugLedgeHang then
						print(
							string.format(
								"[LedgeHang] LedgeHangStart - Original: %.2fs, Desired: %.2fs, Speed: %.2fx",
								originalDuration,
								desiredDuration,
								speedMultiplier
							)
						)
					end
				end

				-- When start ends, play loop animation (use configured duration for timing)
				task.delay(desiredDuration, function()
					if activeHangs[character] then
						local loopAnim = Animations.get("LedgeHangLoop")
						if loopAnim then
							loopTrack = animator:LoadAnimation(loopAnim)
							if loopTrack then
								loopTrack.Priority = Enum.AnimationPriority.Action2 -- Maximum priority
								loopTrack.Looped = true
								loopTrack:Play()
							end
						end
					end
				end)
			end
		else
			-- Fallback to loop animation if no start animation
			local loopAnim = Animations.get("LedgeHangLoop")
			if loopAnim then
				loopTrack = animator:LoadAnimation(loopAnim)
				if loopTrack then
					loopTrack.Priority = Enum.AnimationPriority.Action
					loopTrack.Looped = true
					loopTrack:Play()
				end
			end
		end

		-- Store animation tracks in hang data for cleanup
		hangData.startTrack = startTrack
		hangData.loopTrack = loopTrack
	end)

	-- Mark hang time for cooldown
	LedgeHang.markHangTime(character)

	-- Set hang flag for other systems
	pcall(function()
		local rs = game:GetService("ReplicatedStorage")
		local cs = rs:FindFirstChild("ClientState") or Instance.new("Folder")
		if not cs.Parent then
			cs.Name = "ClientState"
			cs.Parent = rs
		end
		local flag = cs:FindFirstChild("IsLedgeHanging")
		if not flag then
			flag = Instance.new("BoolValue")
			flag.Name = "IsLedgeHanging"
			flag.Value = false
			flag.Parent = cs
		end
		flag.Value = true
	end)

	-- Notify server about ledge hang start
	pcall(function()
		LedgeHangStart:FireServer(hangPos, ledgeY, normalizedForwardDir, hitRes.Normal, hitRes.Instance)
	end)

	return true
end

function LedgeHang.stop(character, isManualRelease)
	local hangData = activeHangs[character]
	if not hangData then
		if Config.DebugLedgeHang then
			print("[LedgeHang] STOP called but no hang data found")
		end
		return
	end

	if Config.DebugLedgeHang then
		print("=== LEDGE HANG STOP DEBUG ===")
		print(string.format("[LedgeHang] Stopping ledge hang (manual release: %s)", tostring(isManualRelease)))
	end

	-- Capture ledge instance before clearing hang data
	local ledgeInstance = nil
	if isManualRelease and hangData and hangData.ledgeInstance then
		ledgeInstance = hangData.ledgeInstance
	end

	-- Proactively clear active state so maintain() won't run next frame
	activeHangs[character] = nil

	-- If this is a manual release (C key), set ledge-specific cooldown
	if isManualRelease and ledgeInstance then
		-- Initialize character cooldowns if needed
		if not ledgeCooldowns[character] then
			ledgeCooldowns[character] = {}
		end

		-- Set cooldown for this specific ledge
		ledgeCooldowns[character][ledgeInstance] = os.clock() + (Config.LedgeHangCooldown or 0.5)

		if Config.DebugLedgeHang then
			print(
				string.format(
					"[LedgeHang] Set cooldown for ledge '%s' (%.1fs)",
					ledgeInstance.Name or "Unknown",
					Config.LedgeHangCooldown or 0.5
				)
			)
		end
	end

	-- If this is a manual release (C key), set a shorter cooldown to allow auto-detection of lower ledges
	if isManualRelease then
		pcall(function()
			local rs = game:GetService("ReplicatedStorage")
			local cs = rs:FindFirstChild("ClientState") or Instance.new("Folder")
			if not cs.Parent then
				cs.Name = "ClientState"
				cs.Parent = rs
			end
			local lastHangTime = cs:FindFirstChild("LastLedgeHangTime")
			if not lastHangTime then
				lastHangTime = Instance.new("NumberValue")
				lastHangTime.Name = "LastLedgeHangTime"
				lastHangTime.Value = 0
				lastHangTime.Parent = cs
			end
			-- Set a shorter cooldown for manual releases to allow auto-detection of lower ledges
			lastHangTime.Value = os.clock() + 0.3

			-- Also suppress wall slide globally for a configurable window
			local suppressFlag = cs:FindFirstChild("SuppressWallSlide")
			if not suppressFlag then
				suppressFlag = Instance.new("BoolValue")
				suppressFlag.Name = "SuppressWallSlide"
				suppressFlag.Value = false
				suppressFlag.Parent = cs
			end
			suppressFlag.Value = true

			local suppressUntil = cs:FindFirstChild("SuppressWallSlideUntil")
			if not suppressUntil then
				suppressUntil = Instance.new("NumberValue")
				suppressUntil.Name = "SuppressWallSlideUntil"
				suppressUntil.Value = 0
				suppressUntil.Parent = cs
			end
			suppressUntil.Value = os.clock() + (Config.WallSlideSuppressAfterLedgeReleaseSeconds or 0.6)
			if Config.DebugLedgeHang then
				print(
					string.format(
						"[LedgeHang] Wallslide suppressed for %.2fs after release",
						(Config.WallSlideSuppressAfterLedgeReleaseSeconds or 0.6)
					)
				)
			end

			-- Auto-clear the flag after the window
			task.delay((Config.WallSlideSuppressAfterLedgeReleaseSeconds or 0.6), function()
				if suppressFlag and suppressFlag.Parent then
					suppressFlag.Value = false
					if Config.DebugLedgeHang then
						print("[LedgeHang] Wallslide suppression window ended")
					end
				end
			end)
			if Config.DebugLedgeHang then
				print("[LedgeHang] Set 1.5s cooldown after manual release")
			end
		end)
	end

	local root, humanoid = getCharacterParts(character)

	-- First: Unanchor and clear ALL physics to prevent any impulses
	if root then
		root.Anchored = false

		-- Completely zero out all velocities FIRST
		root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)

		-- For manual releases, apply slight downward velocity to ensure falling
		if isManualRelease then
			root.AssemblyLinearVelocity = Vector3.new(0, -2, 0) -- Small downward velocity
			if Config.DebugLedgeHang then
				print("[LedgeHang] Applied small downward velocity for manual release")
			end
		end
	end

	-- Restore collision settings
	if hangData.originalCanCollide then
		for part, originalValue in pairs(hangData.originalCanCollide) do
			if part and part.Parent then
				part.CanCollide = originalValue
			end
		end
	end

	-- Cleanup ledge part
	if hangData.ledgePart then
		pcall(function()
			hangData.ledgePart:Destroy()
		end)
	end

	-- No IK system to clean up - only animations are used

	-- Restore humanoid settings without changing state immediately
	if humanoid then
		humanoid.AutoRotate = hangData.originalAutoRotate
		humanoid.WalkSpeed = hangData.originalWalkSpeed or Config.BaseWalkSpeed
		-- Ensure Jump is not firing on release
		humanoid.Jump = false

		-- Only change state after a brief delay to prevent interference (skip for manual release)
		if not isManualRelease then
			task.delay(0.1, function()
				if humanoid and humanoid.Parent then
					humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
					if Config.DebugLedgeHang then
						print("[LedgeHang] Delayed humanoid state change to Freefall")
					end
				end
			end)
		end
	end

	if Config.DebugLedgeHang then
		print("[LedgeHang] Completed clean release sequence")
	end

	-- Stop all hang animations
	pcall(function()
		if hangData.startTrack then
			hangData.startTrack:Stop(0.1)
		end
		if hangData.loopTrack then
			hangData.loopTrack:Stop(0.1)
		end
		if hangData.moveTrack then
			hangData.moveTrack:Stop(0.1)
		end

		-- Don't stop jump animations immediately - let them play during transition
		-- if hangData.jumpTrack then
		--     hangData.jumpTrack:Stop(0.1)
		-- end

		-- Also stop any ledge hang animations that might be playing
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			local animator = humanoid:FindFirstChildOfClass("Animator")
			if animator then
				for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
					if
						track.Name
						and (string.find(track.Name:lower(), "ledgehang") or string.find(track.Name:lower(), "hang"))
					then
						-- Don't stop jump animations (LedgeHangUp, LedgeHangLeft, LedgeHangRight) immediately
						-- Let them finish naturally
						local isJumpAnim = false

						-- Check if this is the current jump animation by comparing animation IDs
						local hangData = activeHangs[character]
						if hangData and hangData.jumpAnimationId and track.Animation then
							isJumpAnim = track.Animation.AnimationId == hangData.jumpAnimationId
						end

						-- Fallback: check by name pattern
						if not isJumpAnim and track.Name then
							local trackNameLower = track.Name:lower()
							isJumpAnim = string.find(trackNameLower, "ledgehangup")
								or string.find(trackNameLower, "ledgehangleft")
								or string.find(trackNameLower, "ledgehangright")
						end

						if Config.DebugLedgeHang then
							print(
								string.format(
									"[LedgeHang] Checking track '%s', isJumpAnim: %s",
									track.Name or "No Name",
									tostring(isJumpAnim)
								)
							)
							if track.Animation then
								print(string.format("[LedgeHang] Track AnimationId: %s", track.Animation.AnimationId))
							end
						end

						if not isJumpAnim then
							track:Stop(0.1)
						else
							if Config.DebugLedgeHang then
								print(
									string.format("[LedgeHang] Preserving jump animation: %s", track.Name or "No Name")
								)
							end
						end
					end
				end

				-- Force return to normal animations asynchronously
				task.delay(0.1, function()
					if not animator or not animator.Parent then
						return
					end

					-- Stop all custom animations to reset to default state, except jump animations
					for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
						if
							track.Priority == Enum.AnimationPriority.Action
							or track.Priority == Enum.AnimationPriority.Action2
						then
							-- Don't stop jump animations - let them finish
							local isJumpAnim = false

							-- Check by animation ID first (more reliable)
							if track.Animation then
								local jumpAnimIds = {
									[Animations.LedgeHangUp] = true,
									[Animations.LedgeHangLeft] = true,
									[Animations.LedgeHangRight] = true,
								}
								isJumpAnim = jumpAnimIds[track.Animation.AnimationId] == true
							end

							-- Fallback: check by name pattern
							if not isJumpAnim and track.Name then
								local trackNameLower = track.Name:lower()
								isJumpAnim = string.find(trackNameLower, "ledgehangup")
									or string.find(trackNameLower, "ledgehangleft")
									or string.find(trackNameLower, "ledgehangright")
							end

							if not isJumpAnim then
								track:Stop(0.1)
							else
								if Config.DebugLedgeHang then
									print(
										string.format(
											"[LedgeHang] Preserving jump animation during reset: %s",
											track.Name or "No Name"
										)
									)
								end
							end
						end
					end

					-- Force humanoid state change to trigger default animations
					local currentHumanoid = animator.Parent
					if currentHumanoid and currentHumanoid:IsA("Humanoid") then
						local currentState = currentHumanoid:GetState()
						-- Briefly change to a different state, then back to trigger animation reset
						if currentState ~= Enum.HumanoidStateType.Jumping then
							currentHumanoid:ChangeState(Enum.HumanoidStateType.Jumping)
						end

						task.delay(0.05, function()
							if currentHumanoid and currentHumanoid.Parent then
								currentHumanoid:ChangeState(Enum.HumanoidStateType.Freefall)

								-- Additional failsafe: Check if animations are playing after state change
								task.delay(0.2, function()
									if currentHumanoid and currentHumanoid.Parent and animator and animator.Parent then
										local playingTracks = animator:GetPlayingAnimationTracks()
										local hasDefaultAnimation = false

										-- Check if any default/core animations are playing
										for _, track in ipairs(playingTracks) do
											if track.Priority == Enum.AnimationPriority.Core then
												hasDefaultAnimation = true
												break
											end
										end

										-- If no default animations are playing, force idle state
										if not hasDefaultAnimation then
											if Config.DebugLedgeHang then
												print("[LedgeHang] No default animations detected, forcing idle state")
											end
											currentHumanoid:ChangeState(Enum.HumanoidStateType.Running)
											task.delay(0.1, function()
												if currentHumanoid and currentHumanoid.Parent then
													currentHumanoid:ChangeState(Enum.HumanoidStateType.Standing)
												end
											end)
										end
									end
								end)
							end
						end)
					end
				end)
			end
		end
	end)

	-- activeHangs already cleared above; keep this as a safeguard
	activeHangs[character] = nil

	-- Clear hang flag
	pcall(function()
		local rs = game:GetService("ReplicatedStorage")
		local cs = rs:FindFirstChild("ClientState")
		local flag = cs and cs:FindFirstChild("IsLedgeHanging")
		if flag then
			flag.Value = false
		end
	end)

	-- Anti-bounce: clamp any accidental upward velocity for a short window after manual release
	if isManualRelease and root and root.Parent then
		local endTime = os.clock() + 0.25
		local conn
		conn = RunService.Stepped:Connect(function()
			if not root or not root.Parent or os.clock() > endTime then
				if conn then
					conn:Disconnect()
				end
				return
			end
			local v = root.AssemblyLinearVelocity
			if v.Y > 0 then
				root.AssemblyLinearVelocity = Vector3.new(v.X, 0, v.Z)
			end
		end)
		if Config.DebugLedgeHang then
			print("[LedgeHang] Engaged anti-bounce clamp for 0.25s")
		end
	end

	-- Notify server about ledge hang stop
	pcall(function()
		LedgeHangStop:FireServer(isManualRelease)
	end)
end

function LedgeHang.isActive(character)
	return activeHangs[character] ~= nil
end

-- Update hanging position and handle horizontal movement
function LedgeHang.maintain(character, moveDirection)
	local hangData = activeHangs[character]
	if not hangData then
		return false
	end

	local root, humanoid = getCharacterParts(character)
	if not root or not humanoid then
		LedgeHang.stop(character)
		return false
	end

	-- Timeout check removed - only stamina controls hang duration

	-- Handle horizontal movement along the ledge
	local rightVector = hangData.forwardDirection:Cross(Vector3.yAxis)
	local horizontalInput = Vector3.new()
	local isMoving = false

	if moveDirection and moveDirection.Magnitude > 0.1 then
		-- Project input onto ledge-relative directions
		local rightDot = moveDirection:Dot(rightVector)
		horizontalInput = rightVector * rightDot
		isMoving = math.abs(rightDot) > 0.1
	end

	-- Handle movement animation
	pcall(function()
		if isMoving and not hangData.isPlayingMoveAnim then
			-- Start move animation
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				local animator = humanoid:FindFirstChildOfClass("Animator")
				if animator and hangData.loopTrack then
					hangData.loopTrack:Stop(0.1)
				end

				-- Determine direction and play appropriate animation
				local rightDot = moveDirection and moveDirection:Dot(rightVector) or 0
				local animName = "LedgeHangMove" -- fallback

				if rightDot > 0.1 then
					animName = "LedgeHangRight"
				elseif rightDot < -0.1 then
					animName = "LedgeHangLeft"
				end

				local moveAnim = Animations.get(animName)
				if moveAnim and animator then
					hangData.moveTrack = animator:LoadAnimation(moveAnim)
					if hangData.moveTrack then
						hangData.moveTrack.Priority = Enum.AnimationPriority.Action2 -- Maximum priority
						hangData.moveTrack.Looped = true
						hangData.moveTrack:Play()
						hangData.isPlayingMoveAnim = true
						hangData.currentMoveDirection = animName

						if Config.DebugLedgeHang then
							print(string.format("[LedgeHang] Playing movement animation: %s", animName))
						end
					end
				else
					-- Fallback to generic move animation
					local fallbackAnim = Animations.get("LedgeHangMove")
					if fallbackAnim and animator then
						hangData.moveTrack = animator:LoadAnimation(fallbackAnim)
						if hangData.moveTrack then
							hangData.moveTrack.Priority = Enum.AnimationPriority.Action2 -- Maximum priority
							hangData.moveTrack.Looped = true
							hangData.moveTrack:Play()
							hangData.isPlayingMoveAnim = true
							hangData.currentMoveDirection = "LedgeHangMove"
						end
					end
				end
			end
		elseif not isMoving and hangData.isPlayingMoveAnim then
			-- Stop move animation, resume loop
			if hangData.moveTrack then
				hangData.moveTrack:Stop(0.1)
				hangData.moveTrack = nil
			end
			hangData.isPlayingMoveAnim = false
			hangData.currentMoveDirection = nil

			if Config.DebugLedgeHang then
				print("[LedgeHang] Returning to idle animation")
			end

			-- Resume loop animation
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				local animator = humanoid:FindFirstChildOfClass("Animator")
				local loopAnim = Animations.get("LedgeHangLoop")
				if loopAnim and animator then
					hangData.loopTrack = animator:LoadAnimation(loopAnim)
					if hangData.loopTrack then
						hangData.loopTrack.Priority = Enum.AnimationPriority.Action
						hangData.loopTrack.Looped = true
						hangData.loopTrack:Play()
					end
				end
			end
		elseif isMoving and hangData.isPlayingMoveAnim then
			-- Check if direction changed while moving
			local rightDot = moveDirection and moveDirection:Dot(rightVector) or 0
			local newAnimName = "LedgeHangMove" -- fallback

			if rightDot > 0.1 then
				newAnimName = "LedgeHangRight"
			elseif rightDot < -0.1 then
				newAnimName = "LedgeHangLeft"
			end

			-- If direction changed, switch animation
			if hangData.currentMoveDirection ~= newAnimName then
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				if humanoid then
					local animator = humanoid:FindFirstChildOfClass("Animator")
					if animator and hangData.moveTrack then
						hangData.moveTrack:Stop(0.1)

						local moveAnim = Animations.get(newAnimName)
						if moveAnim then
							hangData.moveTrack = animator:LoadAnimation(moveAnim)
							if hangData.moveTrack then
								hangData.moveTrack.Priority = Enum.AnimationPriority.Action
								hangData.moveTrack.Looped = true
								hangData.moveTrack:Play()
								hangData.currentMoveDirection = newAnimName

								if Config.DebugLedgeHang then
									print(string.format("[LedgeHang] Switched to animation: %s", newAnimName))
								end
							end
						end
					end
				end
			end
		end
	end)

	-- Move along the ledge
	local moveSpeed = Config.LedgeHangMoveSpeed or 8
	local currentPos = root.Position
	local proposedNewPos = currentPos + horizontalInput * moveSpeed * (1 / 60) -- assume 60fps for now

	-- Check if proposed movement is within ledge bounds
	local finalNewPos = proposedNewPos
	if hangData.ledgeInstance and horizontalInput.Magnitude > 0.01 then
		local ledge = hangData.ledgeInstance

		-- Calculate the surface position that corresponds to the movement
		-- We need to project the movement along the ledge surface, not constrain to the part volume
		local rightVector = hangData.forwardDirection:Cross(Vector3.yAxis)
		local movementDot = horizontalInput:Dot(rightVector)

		-- Calculate the range of movement along the right vector on the ledge surface
		local ledgeHalfSize = ledge.Size * 0.5
		local ledgeToCurrentPos = currentPos - ledge.Position

		-- Project current position onto the right vector to find our position along the ledge
		local currentAlongLedge = ledgeToCurrentPos:Dot(rightVector)

		-- Calculate the maximum extent we can move in each direction
		-- This depends on the orientation of the ledge relative to our right vector
		local maxMovement = 0

		-- Calculate maximum movement by checking which dimension of the ledge aligns with our movement
		local rightDotX = math.abs(rightVector.X)
		local rightDotZ = math.abs(rightVector.Z)

		if rightDotX > rightDotZ then
			-- Movement is primarily along X axis
			maxMovement = ledgeHalfSize.X
		else
			-- Movement is primarily along Z axis
			maxMovement = ledgeHalfSize.Z
		end

		-- Add buffer to prevent edge-of-edge issues
		local buffer = 0.5
		maxMovement = math.max(0, maxMovement - buffer)

		-- Clamp the movement along the ledge
		local clampedMovement =
			math.clamp(currentAlongLedge + movementDot * moveSpeed * (1 / 60), -maxMovement, maxMovement)
		local actualMovementDelta = clampedMovement - currentAlongLedge

		-- Apply the clamped movement
		finalNewPos = currentPos + rightVector * actualMovementDelta

		-- Debug boundary checks
		if Config.DebugLedgeHang and math.abs(actualMovementDelta - movementDot * moveSpeed * (1 / 60)) > 0.01 then
			print(
				string.format(
					"[LedgeHang] Movement clamped along ledge - requested: %.2f, applied: %.2f, max range: ±%.2f",
					movementDot * moveSpeed * (1 / 60),
					actualMovementDelta,
					maxMovement
				)
			)
		end
	end

	-- Keep at consistent distance from wall and height
	local halfHeight = (root.Size and root.Size.Y or 2) * 0.5
	local hangDistance = Config.LedgeHangDistance or 1.2
	local hangY = hangData.ledgeY - halfHeight - (Config.LedgeHangDropDistance or 0.8)

	local wallPos = Vector3.new(
		finalNewPos.X + hangData.forwardDirection.X * hangDistance,
		hangData.ledgeY,
		finalNewPos.Z + hangData.forwardDirection.Z * hangDistance
	)

	local newPos = Vector3.new(finalNewPos.X, hangY, finalNewPos.Z)

	-- Update position (character is anchored, so we use CFrame directly)
	-- Maintain proper orientation during horizontal movement
	local properCFrame = CFrame.lookAt(newPos, newPos + hangData.forwardDirection)
	root.CFrame = properCFrame
	root.AssemblyLinearVelocity = Vector3.new()

	-- Notify server about movement (only if actually moving)
	if horizontalInput.Magnitude > 0.01 then
		pcall(function()
			LedgeHangMove:FireServer(newPos, hangData.forwardDirection)
		end)
	end

	-- No IK system - only animations are used for hand positioning

	if Config.DebugLedgeHang and horizontalInput.Magnitude > 0.1 then
		print(
			string.format(
				"[LedgeHang] Moving - pos: (%.2f,%.2f,%.2f), lookDir: (%.2f,%.2f,%.2f)",
				newPos.X,
				newPos.Y,
				newPos.Z,
				hangData.forwardDirection.X,
				hangData.forwardDirection.Y,
				hangData.forwardDirection.Z
			)
		)
	end

	return true
end

-- Try to mantle up from hanging position
function LedgeHang.tryMantleUp(character)
	if Config.DebugLedgeHang then
		print("[LedgeHang] Attempting mantle up from hang")
	end

	local hangData = activeHangs[character]
	if not hangData then
		if Config.DebugLedgeHang then
			print("[LedgeHang] No hang data for mantle up")
		end
		return false
	end

	local root = getCharacterParts(character)
	if not root then
		if Config.DebugLedgeHang then
			print("[LedgeHang] No root part for mantle up")
		end
		return false
	end

	-- Check if there's now enough clearance above
	local hasClearance = hasEnoughClearanceAbove(root, hangData.ledgeY, hangData.forwardDirection)
	if Config.DebugLedgeHang then
		print(string.format("[LedgeHang] Clearance check for mantle up: %s", tostring(hasClearance)))
	end

	if hasClearance then
		-- Mark the hang time for cooldown purposes
		LedgeHang.markHangTime(character)

		-- Unanchor before mantle
		if root then
			root.Anchored = false
		end

		LedgeHang.stop(character)

		-- Ensure Abilities module is properly loaded
		local Abilities = require(game:GetService("ReplicatedStorage").Movement.Abilities)
		if not Abilities or not Abilities.tryMantle then
			if Config.DebugLedgeHang then
				print("[LedgeHang] Warning: Abilities.tryMantle not available")
			end
			return false
		end

		-- Trigger normal mantle
		local mantleResult = Abilities.tryMantle(character)
		if Config.DebugLedgeHang then
			print(string.format("[LedgeHang] Mantle up result: %s", tostring(mantleResult)))
		end
		return mantleResult
	else
		if Config.DebugLedgeHang then
			print("[LedgeHang] Insufficient clearance for mantle up")
		end

		-- NEW: Try to chain to a higher ledge directly above
		if Config.LedgeHangChainEnabled ~= false then
			local chainUp = Config.LedgeHangChainMaxUpSearch or 6.0
			local root, humanoid = getCharacterParts(character)
			if root then
				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				params.FilterDescendantsInstances =
					SharedUtils.createParkourRaycastParams(character).FilterDescendantsInstances
				params.IgnoreWater = true
				-- Cast straight up from current ledge x/z
				local start = Vector3.new(root.Position.X, hangData.ledgeY + 0.1, root.Position.Z)
				local upHit = workspace:Raycast(start, Vector3.new(0, chainUp, 0), params)
				if upHit and upHit.Instance and upHit.Instance:IsA("BasePart") then
					-- Validate alignment with current wall (normal close to forwardDirection)
					local n = upHit.Normal
					local dot = n:Dot(-hangData.forwardDirection) -- surface normal points opposite to forward
					local okNormal = dot >= (Config.LedgeHangChainNormalDotMin or 0.8)
					-- Validate horizontal offset small
					local horizDelta =
						Vector3.new(upHit.Position.X - root.Position.X, 0, upHit.Position.Z - root.Position.Z)
					local okHoriz = (horizDelta.Magnitude <= (Config.LedgeHangChainMaxHorizontal or 1.5))

					if okNormal and okHoriz then
						if Config.DebugLedgeHang then
							print(
								string.format(
									"[LedgeHang] Found chain ledge above: dot=%.2f horiz=%.2f",
									dot,
									horizDelta.Magnitude
								)
							)
						end
						-- Stop current hang and start a new one at the higher ledge top
						local newTopY = upHit.Position.Y
						LedgeHang.stop(character)
						return LedgeHang.startHang(character, upHit, newTopY, hangData.forwardDirection)
					end
				end
			end
		end
	end

	return false
end

-- Directional jump from ledge hang
function LedgeHang.tryDirectionalJump(character, direction)
	local hangData = activeHangs[character]
	if not hangData then
		if Config.DebugLedgeHang then
			print("[LedgeHang] No hang data found for directional jump")
		end
		return false
	end

	if Config.DebugLedgeHang then
		print(string.format("[LedgeHang] Starting directional jump: %s", direction))
	end

	local root, humanoid = getCharacterParts(character)
	if not root or not humanoid then
		return false
	end

	-- Check stamina cost - simplified for now, we'll integrate with ParkourController stamina later
	local jumpCost = Config.LedgeHangJumpStaminaCost or 10

	-- Ensure ClientState is properly initialized on first use
	pcall(function()
		local rs = game:GetService("ReplicatedStorage")
		local cs = rs:FindFirstChild("ClientState")
		if not cs then
			cs = Instance.new("Folder")
			cs.Name = "ClientState"
			cs.Parent = rs
			if Config.DebugLedgeHang then
				print("[LedgeHang] Created ClientState folder on first use")
			end
		end

		-- Ensure LastLedgeHangTime exists and is properly initialized
		local lastHangTime = cs:FindFirstChild("LastLedgeHangTime")
		if not lastHangTime then
			lastHangTime = Instance.new("NumberValue")
			lastHangTime.Name = "LastLedgeHangTime"
			lastHangTime.Value = 0
			lastHangTime.Parent = cs
			if Config.DebugLedgeHang then
				print("[LedgeHang] Initialized LastLedgeHangTime on first use")
			end
		end
	end)

	if Config.DebugLedgeHang then
		print(string.format("[LedgeHang] Attempting directional jump: %s, cost: %d", direction, jumpCost))
		print(
			string.format(
				"[LedgeHang] Config values - Up:%s, Side:%s, Back:%s, WallSep:%s",
				tostring(Config.LedgeHangJumpUpForce),
				tostring(Config.LedgeHangJumpSideForce),
				tostring(Config.LedgeHangJumpBackForce),
				tostring(Config.LedgeHangWallSeparationForce)
			)
		)
	end

	-- Calculate impulse direction and force
	local impulseDirection = Vector3.new()
	local force = 0

	-- Use player's current facing direction for lateral movement (more intuitive)
	local playerForward = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
	local playerRight = playerForward:Cross(Vector3.yAxis).Unit

	-- For forward/back, use the hang orientation (wall direction)
	local hangForward = hangData.forwardDirection

	if direction == "up" then
		-- W + Space: Jump straight up with slight forward momentum relative to wall
		impulseDirection = Vector3.new(hangForward.X * 0.3, 1.0, hangForward.Z * 0.3)
		force = Config.LedgeHangJumpUpForce or 120
		if Config.DebugLedgeHang then
			print(
				string.format("[LedgeHang] UP force: Config=%s, final=%d", tostring(Config.LedgeHangJumpUpForce), force)
			)
		end
	elseif direction == "left" then
		-- A + Space: Jump left + slightly backward (combines lateral + back movement)
		local leftComponent = Vector3.new(-playerRight.X * 0.8, 0.3, -playerRight.Z * 0.8)
		local backComponent = Vector3.new(-hangForward.X * 0.3, 0, -hangForward.Z * 0.3)
		impulseDirection = leftComponent + backComponent
		force = Config.LedgeHangJumpSideForce or 120
		if Config.DebugLedgeHang then
			print(
				string.format(
					"[LedgeHang] LEFT force: Config=%s, final=%d",
					tostring(Config.LedgeHangJumpSideForce),
					force
				)
			)
			print(
				string.format(
					"[LedgeHang] LEFT components - lateral:(%.2f,%.2f,%.2f) + back:(%.2f,%.2f,%.2f)",
					leftComponent.X,
					leftComponent.Y,
					leftComponent.Z,
					backComponent.X,
					backComponent.Y,
					backComponent.Z
				)
			)
		end
	elseif direction == "right" then
		-- D + Space: Jump right + slightly backward (combines lateral + back movement)
		local rightComponent = Vector3.new(playerRight.X * 0.8, 0.3, playerRight.Z * 0.8)
		local backComponent = Vector3.new(-hangForward.X * 0.3, 0, -hangForward.Z * 0.3)
		impulseDirection = rightComponent + backComponent
		force = Config.LedgeHangJumpSideForce or 120
		if Config.DebugLedgeHang then
			print(
				string.format(
					"[LedgeHang] RIGHT force: Config=%s, final=%d",
					tostring(Config.LedgeHangJumpSideForce),
					force
				)
			)
			print(
				string.format(
					"[LedgeHang] RIGHT components - lateral:(%.2f,%.2f,%.2f) + back:(%.2f,%.2f,%.2f)",
					rightComponent.X,
					rightComponent.Y,
					rightComponent.Z,
					backComponent.X,
					backComponent.Y,
					backComponent.Z
				)
			)
		end
	elseif direction == "back" then
		-- S + Space: Jump backward from wall
		impulseDirection = Vector3.new(-hangForward.X * 0.8, 0.3, -hangForward.Z * 0.8)
		force = Config.LedgeHangJumpBackForce or 120
		if Config.DebugLedgeHang then
			print("=== BACK JUMP DEBUG ===")
			print(
				string.format(
					"[LedgeHang] BACK force: Config=%s, final=%d",
					tostring(Config.LedgeHangJumpBackForce),
					force
				)
			)
			print(
				string.format("[LedgeHang] hangForward: (%.2f,%.2f,%.2f)", hangForward.X, hangForward.Y, hangForward.Z)
			)
			print(
				string.format(
					"[LedgeHang] Raw impulseDirection: (%.2f,%.2f,%.2f)",
					impulseDirection.X,
					impulseDirection.Y,
					impulseDirection.Z
				)
			)
			print("=== END BACK JUMP DEBUG ===")
		end
	else
		return false -- invalid direction
	end

	-- Normalize the direction but keep reasonable magnitude
	if impulseDirection.Magnitude > 0 then
		impulseDirection = impulseDirection.Unit
	else
		return false
	end

	if Config.DebugLedgeHang then
		print(
			string.format(
				"[LedgeHang] Direction calc - playerForward:(%.2f,%.2f,%.2f), playerRight:(%.2f,%.2f,%.2f)",
				playerForward.X,
				playerForward.Y,
				playerForward.Z,
				playerRight.X,
				playerRight.Y,
				playerRight.Z
			)
		)
		print(string.format("[LedgeHang] hangForward:(%.2f,%.2f,%.2f)", hangForward.X, hangForward.Y, hangForward.Z))
		print(
			string.format(
				"[LedgeHang] Raw impulse direction before normalize:(%.2f,%.2f,%.2f)",
				impulseDirection.X,
				impulseDirection.Y,
				impulseDirection.Z
			)
		)
		print(
			string.format(
				"[LedgeHang] Final impulse direction: (%.2f,%.2f,%.2f)",
				impulseDirection.X,
				impulseDirection.Y,
				impulseDirection.Z
			)
		)
	end

	-- Play directional jump animation before jumping
	pcall(function()
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			local animator = humanoid:FindFirstChildOfClass("Animator")
			if animator then
				-- Stop any current ledge hang animations
				local hangData = activeHangs[character]
				if hangData then
					if hangData.loopTrack then
						hangData.loopTrack:Stop(0.1)
					end
					if hangData.moveTrack then
						hangData.moveTrack:Stop(0.1)
					end
				end

				-- Play directional jump animation
				local jumpAnimName = ""
				if direction == "up" then
					jumpAnimName = "LedgeHangUp"
				elseif direction == "left" then
					jumpAnimName = "LedgeHangLeft"
				elseif direction == "right" then
					jumpAnimName = "LedgeHangRight"
				elseif direction == "back" then
					jumpAnimName = "LedgeHangMove" -- or create LedgeHangBack
				end

				if jumpAnimName ~= "" then
					local jumpAnim = Animations.get(jumpAnimName)
					if jumpAnim then
						local jumpTrack = animator:LoadAnimation(jumpAnim)
						if jumpTrack then
							jumpTrack.Priority = Enum.AnimationPriority.Action2 -- Higher priority to avoid interruption
							jumpTrack.Looped = false
							jumpTrack:Play()

							-- Adjust animation speed based on configured duration
							local desiredDuration = nil
							if jumpAnimName == "LedgeHangUp" then
								desiredDuration = Config.LedgeHangUpAnimationDuration or 0.4
							elseif jumpAnimName == "LedgeHangLeft" then
								desiredDuration = Config.LedgeHangLeftAnimationDuration or 0.3
							elseif jumpAnimName == "LedgeHangRight" then
								desiredDuration = Config.LedgeHangRightAnimationDuration or 0.3
							end

							if desiredDuration then
								local originalDuration = jumpTrack.Length
								if originalDuration > 0 then
									local speedMultiplier = originalDuration / desiredDuration
									jumpTrack:AdjustSpeed(speedMultiplier)

									if Config.DebugLedgeHang then
										print(
											string.format(
												"[LedgeHang] %s - Original: %.2fs, Desired: %.2fs, Speed: %.2fx",
												jumpAnimName,
												originalDuration,
												desiredDuration,
												speedMultiplier
											)
										)
									end
								end
							end

							if Config.DebugLedgeHang then
								print(
									string.format("[LedgeHang] Successfully playing jump animation: %s", jumpAnimName)
								)
								print(
									string.format("[LedgeHang] Animation track name: %s", jumpTrack.Name or "No Name")
								)
								print(string.format("[LedgeHang] Animation priority: %s", tostring(jumpTrack.Priority)))
								print(string.format("[LedgeHang] Animation length: %s", tostring(jumpTrack.Length)))
								if desiredDuration then
									print(string.format("[LedgeHang] Configured duration: %.2fs", desiredDuration))
								end
							end

							-- Store track reference to prevent it from being stopped immediately
							hangData.jumpTrack = jumpTrack
							hangData.jumpAnimationId = jumpAnim.AnimationId -- Store the animation ID for comparison
						else
							if Config.DebugLedgeHang then
								print(string.format("[LedgeHang] Failed to load animation track for: %s", jumpAnimName))
							end
						end
					else
						if Config.DebugLedgeHang then
							print(string.format("[LedgeHang] Failed to get animation for: %s", jumpAnimName))
						end
					end
				end
			end
		end
	end)

	-- Mark hang time and stop hanging
	LedgeHang.markHangTime(character)

	-- ALWAYS set a minimum global cooldown after directional jumps to prevent immediate re-hang
	pcall(function()
		local rs = game:GetService("ReplicatedStorage")
		local cs = rs:FindFirstChild("ClientState") or Instance.new("Folder")
		if not cs.Parent then
			cs.Name = "ClientState"
			cs.Parent = rs
		end
		local lastHangTime = cs:FindFirstChild("LastLedgeHangTime")
		if not lastHangTime then
			lastHangTime = Instance.new("NumberValue")
			lastHangTime.Name = "LastLedgeHangTime"
			lastHangTime.Value = 0
			lastHangTime.Parent = cs
		end
		-- Set minimum 0.5s global cooldown regardless of wall identification
		lastHangTime.Value = os.clock() + 0.5
		if Config.DebugLedgeHang then
			print(string.format("[LedgeHang] Set 0.5s global cooldown after %s jump", direction))
		end
	end)

	-- Unanchor before applying velocity (must be done before LedgeHang.stop to ensure velocity works)
	if root then
		root.Anchored = false
	end

	-- Store the jump animation reference before stopping hang
	local jumpAnimTrack = hangData and hangData.jumpTrack

	if Config.DebugLedgeHang then
		print(string.format("[LedgeHang] Before stop - jumpAnimTrack exists: %s", tostring(jumpAnimTrack ~= nil)))
		if jumpAnimTrack then
			print(
				string.format(
					"[LedgeHang] Jump track name: %s, IsPlaying: %s",
					jumpAnimTrack.Name or "No Name",
					tostring(jumpAnimTrack.IsPlaying)
				)
			)
		end
	end

	LedgeHang.stop(character)

	-- Restore jump animation after cleanup if it exists - ONLY for UP direction
	-- For lateral jumps (left/right), we want immediate transition to jump animation instead
	if jumpAnimTrack and jumpAnimTrack.IsPlaying and direction == "up" then
		-- Use configured duration for LedgeHangUp only
		local preserveDuration = Config.LedgeHangUpAnimationDuration or 0.4

		if Config.DebugLedgeHang then
			print(
				string.format(
					"[LedgeHang] Preserving UP jump animation for %.2fs: %s",
					preserveDuration,
					jumpAnimTrack.Name or "No Name"
				)
			)
		end
		-- Give it time to play, then stop it naturally
		task.delay(preserveDuration, function()
			if jumpAnimTrack and jumpAnimTrack.IsPlaying then
				if Config.DebugLedgeHang then
					print(
						string.format(
							"[LedgeHang] Stopping UP jump animation after delay: %s",
							jumpAnimTrack.Name or "No Name"
						)
					)
				end
				jumpAnimTrack:Stop(0.2) -- Fade out over 0.2 seconds
			end
		end)
	elseif jumpAnimTrack and direction ~= "up" then
		if Config.DebugLedgeHang then
			print(
				string.format(
					"[LedgeHang] Skipping animation preservation for %s direction (will use jump animation instead)",
					direction
				)
			)
		end
	else
		if Config.DebugLedgeHang then
			print("[LedgeHang] No jump animation track to preserve or direction is not UP")
		end
	end

	-- Simple physics setup (same as S+Space)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		if Config.DebugLedgeHang then
			print(string.format("[LedgeHang] Setting humanoid to Freefall state for %s jump", direction))
		end
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)

		-- Ensure the state change took effect
		task.wait(0.01)
		if Config.DebugLedgeHang then
			print(string.format("[LedgeHang] Humanoid state after change: %s", tostring(humanoid:GetState())))
		end
	end

	-- Calculate wall separation force (push away from wall)
	local wallSeparationForce = Vector3.new(0, 0, 0)
	if hangData and hangData.forwardDirection then
		-- For side jumps, disable wall separation since we use backward component instead
		local separationMagnitude = Config.LedgeHangWallSeparationForce or 30
		if direction == "left" or direction == "right" then
			separationMagnitude = 0 -- No wall separation for side jumps (backward component handles separation)
		elseif direction == "up" then
			separationMagnitude = separationMagnitude * 1.5 -- Increased separation for up jumps to prevent immediate re-hang
		end
		wallSeparationForce = hangData.forwardDirection * separationMagnitude

		if Config.DebugLedgeHang then
			print(
				string.format(
					"[LedgeHang] Wall separation: Config=%s, final=%.1f",
					tostring(Config.LedgeHangWallSeparationForce),
					separationMagnitude
				)
			)
			print(
				string.format(
					"[LedgeHang] Wall separation force vector: (%.2f,%.2f,%.2f)",
					wallSeparationForce.X,
					wallSeparationForce.Y,
					wallSeparationForce.Z
				)
			)
		end
	end

	-- For side jumps, disable wallslide for 0.25 seconds to allow separation
	if direction == "left" or direction == "right" then
		pcall(function()
			local WallJump = require(game:GetService("ReplicatedStorage").Movement.WallJump)

			-- Stop current wallslide
			if WallJump.isWallSliding and WallJump.isWallSliding(character) then
				WallJump.stopSlide(character)
				if Config.DebugLedgeHang then
					print("[LedgeHang] Stopping wallslide for side jump")
				end
			end

			-- Set wallslide suppression flag for 0.25 seconds
			local rs = game:GetService("ReplicatedStorage")
			local cs = rs:FindFirstChild("ClientState") or Instance.new("Folder")
			if not cs.Parent then
				cs.Name = "ClientState"
				cs.Parent = rs
			end

			local suppressFlag = cs:FindFirstChild("SuppressWallSlide")
			if not suppressFlag then
				suppressFlag = Instance.new("BoolValue")
				suppressFlag.Name = "SuppressWallSlide"
				suppressFlag.Value = false
				suppressFlag.Parent = cs
			end

			suppressFlag.Value = true
			if Config.DebugLedgeHang then
				print("[LedgeHang] Wallslide DISABLED immediately for side jump")
			end

			-- Re-enable wallslide after 0.25 seconds
			task.delay(0.25, function()
				if suppressFlag and suppressFlag.Parent then
					suppressFlag.Value = false
					if Config.DebugLedgeHang then
						print("[LedgeHang] Wallslide RE-ENABLED after 0.25s")
					end
				end
			end)
		end)
	end

	-- Apply impulse with wall separation (simple method like S+Space)
	local baseVelocity = impulseDirection * force
	local finalVelocity = baseVelocity + wallSeparationForce

	if Config.DebugLedgeHang then
		print("=== VELOCITY APPLICATION DEBUG ===")
		print(
			string.format(
				"[LedgeHang] Base velocity: (%.2f,%.2f,%.2f), magnitude: %.2f",
				baseVelocity.X,
				baseVelocity.Y,
				baseVelocity.Z,
				baseVelocity.Magnitude
			)
		)
		print(
			string.format(
				"[LedgeHang] Wall separation: (%.2f,%.2f,%.2f), magnitude: %.2f",
				wallSeparationForce.X,
				wallSeparationForce.Y,
				wallSeparationForce.Z,
				wallSeparationForce.Magnitude
			)
		)
		print(
			string.format(
				"[LedgeHang] Final velocity: (%.2f,%.2f,%.2f), magnitude: %.2f",
				finalVelocity.X,
				finalVelocity.Y,
				finalVelocity.Z,
				finalVelocity.Magnitude
			)
		)
		print(string.format("[LedgeHang] Root anchored: %s", tostring(root.Anchored)))
		print("=== END VELOCITY APPLICATION DEBUG ===")
	end

	root.AssemblyLinearVelocity = finalVelocity

	-- For lateral jumps (left/right), immediately start jump animation to replace ledge hang animation
	if direction == "left" or direction == "right" then
		task.defer(function()
			pcall(function()
				local humanoid = character:FindFirstChildOfClass("Humanoid")
				if humanoid then
					local animator = humanoid:FindFirstChildOfClass("Animator")
					if animator then
						-- Stop any remaining ledge hang animations immediately
						if jumpAnimTrack and jumpAnimTrack.IsPlaying then
							jumpAnimTrack:Stop(0.05) -- Quick fade out
						end

						-- Start jump animation immediately for lateral movements
						local jumpAnim = Animations.get("Jump") or Animations.get("JumpStart")
						if jumpAnim then
							local jumpTrack = animator:LoadAnimation(jumpAnim)
							if jumpTrack then
								jumpTrack.Priority = Enum.AnimationPriority.Action
								jumpTrack.Looped = (jumpAnim == Animations.get("Jump")) -- Loop if it's the main Jump animation
								jumpTrack:Play(0.05, 1, 1.0)

								if Config.DebugLedgeHang then
									print(
										string.format(
											"[LedgeHang] Started jump animation for %s lateral jump",
											direction
										)
									)
								end
							end
						end
					end
				end
			end)
		end)
	end

	-- Apply multiple times aggressively to counteract velocity reduction
	task.wait()
	root.AssemblyLinearVelocity = finalVelocity

	-- Apply every 0.05 seconds for the first 0.2 seconds to maintain horizontal momentum
	for i = 1, 4 do
		task.delay(i * 0.05, function()
			if root and root.Parent then
				-- Only reapply if velocity has been significantly reduced
				local currentVel = root.AssemblyLinearVelocity
				if currentVel.Magnitude < finalVelocity.Magnitude * 0.7 then
					if Config.DebugLedgeHang then
						print(
							string.format(
								"[LedgeHang] Reapplying velocity at %.2fs - was %.1f, applying %.1f",
								i * 0.05,
								currentVel.Magnitude,
								finalVelocity.Magnitude
							)
						)
					end
					root.AssemblyLinearVelocity = finalVelocity
				end
			end
		end)
	end

	task.delay(0.1, function()
		if root and root.Parent then
			-- Boost the impulse if velocity was reduced
			local currentVel = root.AssemblyLinearVelocity
			if currentVel.Magnitude < finalVelocity.Magnitude * 0.5 then
				if Config.DebugLedgeHang then
					print(
						string.format(
							"[LedgeHang] Velocity was reduced to %.2f, re-applying boost",
							currentVel.Magnitude
						)
					)
				end
				root.AssemblyLinearVelocity = finalVelocity
			end
		end
	end)

	-- Note: Stamina deduction will be handled by ParkourController

	if Config.DebugLedgeHang then
		print(string.format("[LedgeHang] Directional jump: %s, force: %.1f", direction, force))
		print(
			string.format(
				"[LedgeHang] Final velocity applied: (%.2f,%.2f,%.2f), magnitude: %.2f",
				finalVelocity.X,
				finalVelocity.Y,
				finalVelocity.Z,
				finalVelocity.Magnitude
			)
		)

		-- Monitor velocity after a short delay to see if something is interfering
		task.delay(0.2, function()
			if root and root.Parent then
				local currentVel = root.AssemblyLinearVelocity
				print(
					string.format(
						"[LedgeHang] Velocity after 0.2s: (%.2f,%.2f,%.2f), magnitude: %.2f",
						currentVel.X,
						currentVel.Y,
						currentVel.Z,
						currentVel.Magnitude
					)
				)
			end
		end)
	end

	return true
end

-- Wall-specific cooldown system
local wallCooldowns = {} -- [character][wallInstance] = cooldownTime

-- Get wall instance from current hang position
local function getWallInstanceFromHang(character)
	local hangData = activeHangs[character]
	if not hangData or not hangData.ledgePosition or not hangData.forwardDirection then
		if Config.DebugLedgeHang then
			print("[LedgeHang] No hang data available for wall identification")
		end
		return nil
	end

	-- Try multiple approaches to find the wall
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = SharedUtils.createParkourRaycastParams(character).FilterDescendantsInstances
	params.IgnoreWater = true

	-- Method 1: Cast from player position toward ledge
	local root = character:FindFirstChild("HumanoidRootPart")
	if root then
		local toWall = (hangData.ledgePosition - root.Position).Unit
		local hit = workspace:Raycast(root.Position, toWall * 5.0, params)
		if hit and hit.Instance and hit.Instance.CanCollide then
			if Config.DebugLedgeHang then
				print(string.format("[LedgeHang] Found wall instance (method 1): '%s'", hit.Instance.Name or "Unknown"))
			end
			return hit.Instance
		end
	end

	-- Method 2: Cast from ledge into wall using forwardDirection
	local rayDirection = -hangData.forwardDirection * 2.0
	local hit = workspace:Raycast(hangData.ledgePosition, rayDirection, params)
	if hit and hit.Instance and hit.Instance.CanCollide then
		if Config.DebugLedgeHang then
			print(string.format("[LedgeHang] Found wall instance (method 2): '%s'", hit.Instance.Name or "Unknown"))
		end
		return hit.Instance
	end

	-- Method 3: Cast downward from ledge to find surface
	local downHit = workspace:Raycast(hangData.ledgePosition, Vector3.new(0, -2, 0), params)
	if downHit and downHit.Instance and downHit.Instance.CanCollide then
		if Config.DebugLedgeHang then
			print(string.format("[LedgeHang] Found wall instance (method 3): '%s'", downHit.Instance.Name or "Unknown"))
		end
		return downHit.Instance
	end

	if Config.DebugLedgeHang then
		print(
			string.format(
				"[LedgeHang] All wall identification methods failed. Forward: (%.2f,%.2f,%.2f)",
				hangData.forwardDirection.X,
				hangData.forwardDirection.Y,
				hangData.forwardDirection.Z
			)
		)
	end

	return nil
end

-- Check if a specific wall has cooldown
function hasWallCooldown(character, wallInstance)
	if not wallInstance then
		return false
	end

	local charCooldowns = wallCooldowns[character]
	if not charCooldowns then
		return false
	end

	local wallCooldownTime = charCooldowns[wallInstance]
	if not wallCooldownTime then
		return false
	end

	local cooldownDuration = Config.LedgeHangCooldown or 3.0
	local timeRemaining = cooldownDuration - (os.clock() - wallCooldownTime)

	if timeRemaining <= 0 then
		-- Cooldown expired, clean it up
		charCooldowns[wallInstance] = nil
		return false
	end

	if Config.DebugLedgeHang then
		print(
			string.format(
				"[LedgeHang] Wall '%s' cooldown: %.1fs remaining",
				wallInstance.Name or "Unknown",
				timeRemaining
			)
		)
	end

	return true
end

-- Set cooldown for current wall
local function setWallCooldown(character)
	local wallInstance = getWallInstanceFromHang(character)
	if not wallInstance then
		if Config.DebugLedgeHang then
			print("[LedgeHang] Could not identify wall for cooldown")
		end
		return
	end

	-- Initialize character cooldowns if needed
	if not wallCooldowns[character] then
		wallCooldowns[character] = {}
	end

	-- Set cooldown for this wall
	wallCooldowns[character][wallInstance] = os.clock()

	if Config.DebugLedgeHang then
		print(string.format("[LedgeHang] Set cooldown for wall '%s'", wallInstance.Name or "Unknown"))
	end
end

-- Mark hang time in ParkourController state for cooldown
function LedgeHang.markHangTime(character)
	-- Set wall-specific cooldown
	setWallCooldown(character)

	-- Also set global cooldown in ClientState (for existing logic)
	pcall(function()
		local rs = game:GetService("ReplicatedStorage")
		local cs = rs:FindFirstChild("ClientState")
		if cs then
			local lastHangTime = cs:FindFirstChild("LastLedgeHangTime")
			if not lastHangTime then
				lastHangTime = Instance.new("NumberValue")
				lastHangTime.Name = "LastLedgeHangTime"
				lastHangTime.Value = 0
				lastHangTime.Parent = cs
			end
			lastHangTime.Value = os.clock()
		end
	end)
end

-- Clean up cooldowns when player leaves
game.Players.PlayerRemoving:Connect(function(player)
	if player.Character then
		wallCooldowns[player.Character] = nil
	end
end)

-- Clean up when character is removed
game.Players.PlayerAdded:Connect(function(player)
	player.CharacterRemoving:Connect(function(character)
		wallCooldowns[character] = nil
		activeHangs[character] = nil
	end)
end)

return LedgeHang
