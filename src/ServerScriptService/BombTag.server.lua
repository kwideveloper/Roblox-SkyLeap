local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local bombTagFolder = ReplicatedStorage:WaitForChild("BombTag")
local ConfigModule = bombTagFolder:WaitForChild("Config")
local Config = require(ConfigModule)

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local remotes = {
	GameStart = remotesFolder:WaitForChild("BombTagGameStart"),
	CountdownUpdate = remotesFolder:WaitForChild("BombTagCountdownUpdate"),
	BombAssigned = remotesFolder:WaitForChild("BombTagBombAssigned"),
	BombPassed = remotesFolder:WaitForChild("BombTagBombPassed"),
	BombTimerUpdate = remotesFolder:WaitForChild("BombTagBombTimerUpdate"),
	PlayerEliminated = remotesFolder:WaitForChild("BombTagPlayerEliminated"),
	GameEnd = remotesFolder:WaitForChild("BombTagGameEnd"),
	ScoreboardUpdate = remotesFolder:WaitForChild("BombTagScoreboardUpdate"),
	PlatformPrompt = remotesFolder:WaitForChild("BombTagPlatformPrompt"),
	ReadyStatus = remotesFolder:WaitForChild("BombTagReadyStatus"),
	ReadyWarning = remotesFolder:WaitForChild("BombTagReadyWarning"),
	ReadyToggle = remotesFolder:WaitForChild("BombTagReadyToggle"),
}
local currencyUpdatedRemote = remotesFolder:WaitForChild("CurrencyUpdated")

local BombMatchManager = require(bombTagFolder:WaitForChild("BombMatchManager"))
local PlayerProfile = require(ServerScriptService:WaitForChild("PlayerProfile"))

local levelModel = Workspace:FindFirstChild("BombLevel_1")
local lobbySpawner = Workspace:FindFirstChild("BombLobbySpawner")

local manager = BombMatchManager.init({
	remotes = remotes,
	config = ConfigModule,
	workspaceRefs = {
		level = levelModel,
		lobbySpawner = lobbySpawner,
	},
	callbacks = {},
})

local platformSlots = {
	Left = {},
	Right = {},
}

local playerSlotLookup = {}
local readyPlayers = {}
local matchParticipants = {}
local matchConnections = {}
local matchActive = false
local readyWarningTasks = {}
local lobbyCountdown = { task = nil, generation = 0, readyEntries = nil }
local evaluateLobbyCountdown -- forward declaration
local gatherReadyEntries -- forward declaration
local removePlayerFromSlot -- forward declaration

local PLATFORM_TOUCH_RADIUS = Config.PlatformTouchRadius or 12
local MAX_PLATFORM_HEIGHT_OFFSET = Config.PlatformHeightTolerance or 6
local PLATFORM_COLOR_WAITING = Color3.fromRGB(0, 170, 255)
local PLATFORM_COLOR_READY = Color3.fromRGB(0, 200, 0)
local PLATFORM_HIDDEN_SCALE = Config.PlatformHiddenScale or 0
local PLATFORM_HIDDEN_MIN_SIZE = Config.PlatformHiddenMinSize or 0
local PLATFORM_BOUNCE_TWEEN_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out)
local PLATFORM_HIDE_TWEEN_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local READY_TIMEOUT = Config.ReadyTimeout or 10

local function computeSurfaceCFrameForObject(object, offset)
	if not object then
		return nil
	end

	offset = offset or 0
	local totalOffset = offset + (Config.RespawnExtraHeight or 0)

	local baseCFrame
	local height

	if object:IsA("BasePart") then
		baseCFrame = object.CFrame
		height = object.Size.Y
	elseif object:IsA("Model") then
		local success, cf, size = pcall(object.GetBoundingBox, object)
		if not success then
			return nil
		end
		baseCFrame = cf
		height = size.Y
	else
		return nil
	end

	local topPosition = baseCFrame.Position + Vector3.new(0, height / 2, 0)
	local lookVector = baseCFrame.LookVector
	if lookVector.Magnitude < 0.001 then
		lookVector = Vector3.new(0, 0, -1)
	end

	return CFrame.new(topPosition + Vector3.new(0, totalOffset, 0), topPosition + lookVector)
end

local function iteratePlatformParts(instance, callback)
	if instance:IsA("BasePart") then
		callback(instance)
	else
		for _, descendant in ipairs(instance:GetDescendants()) do
			if descendant:IsA("BasePart") then
				callback(descendant)
			end
		end
	end

	evaluateLobbyCountdown()
end

local function capturePlatformAppearance(instance)
	local appearance = {}
	iteratePlatformParts(instance, function(part)
		table.insert(appearance, {
			part = part,
			color = part.Color,
			transparency = part.Transparency,
			size = part.Size,
			canTouch = part.CanTouch,
			canCollide = part.CanCollide,
		})
	end)
	return appearance
end

local function setSlotColor(slot, color)
	if not slot or not slot.originalAppearance then
		return
	end
	for _, state in ipairs(slot.originalAppearance) do
		local part = state.part
		if part and part.Parent then
			part.Color = color
		end
	end
end

local function restorePlatformAppearance(slot)
	if not slot or not slot.originalAppearance then
		return
	end
	for _, state in ipairs(slot.originalAppearance) do
		local part = state.part
		if part and part.Parent then
			part.Color = state.color
			part.Transparency = state.transparency
			part.Size = state.size
		end
	end
end

local function lockPlatform(slot)
	if not slot or slot.locked then
		return
	end
	slot.locked = true
	if slot.originalAppearance then
		for _, state in ipairs(slot.originalAppearance) do
			local part = state.part
			if part and part.Parent then
				part.CanTouch = false
				part.CanCollide = false
			end
		end
	end
end

local function unlockPlatform(slot)
	if not slot then
		return
	end
	slot.locked = false
	if slot.originalAppearance then
		for _, state in ipairs(slot.originalAppearance) do
			local part = state.part
			if part and part.Parent then
				part.CanTouch = true
				part.CanCollide = state.canCollide
			end
		end
	end
end

local function clearDictionary(dict)
	if not dict then
		return
	end
	for key in pairs(dict) do
		dict[key] = nil
	end
end

local function teleportPlayerToLobby(player)
	if not player or not player.Parent then
		return
	end

	local spawnObject = lobbySpawner or Workspace:FindFirstChild("BombLobbySpawner")
	if not spawnObject then
		warn("[BombTag] BombLobbySpawner not found; cannot teleport player to lobby.")
		return
	end

	local spawnCFrame = computeSurfaceCFrameForObject(spawnObject, Config.SpawnSurfaceOffset or 0.25)
	if not spawnCFrame then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = true
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
	end

	rootPart.CFrame = spawnCFrame
	rootPart.AssemblyLinearVelocity = Vector3.zero

	task.defer(function()
		if humanoid and humanoid.Parent then
			humanoid.PlatformStand = false
			humanoid.WalkSpeed = Config.PlayerDefaultWalkSpeed or 16
			humanoid.JumpPower = Config.PlayerDefaultJumpPower or 50
		end
	end)
end

local function computeHiddenSize(originalSize)
	local hiddenX = math.max(originalSize.X * PLATFORM_HIDDEN_SCALE, PLATFORM_HIDDEN_MIN_SIZE)
	local hiddenY = math.max(originalSize.Y * PLATFORM_HIDDEN_SCALE, PLATFORM_HIDDEN_MIN_SIZE)
	local hiddenZ = math.max(originalSize.Z * PLATFORM_HIDDEN_SCALE, PLATFORM_HIDDEN_MIN_SIZE)
	return Vector3.new(hiddenX, hiddenY, hiddenZ)
end

local function cancelActiveTweens(slot)
	if slot and slot.activeTweens then
		for _, tween in pairs(slot.activeTweens) do
			if tween then
				tween:Cancel()
			end
		end
		clearDictionary(slot.activeTweens)
	end
end

local function hidePlatform(slot)
	if not slot then
		return
	end

	cancelActiveTweens(slot)
	slot.visible = false
	lockPlatform(slot)
	slot.activeTweens = slot.activeTweens or {}

	if not slot.originalAppearance then
		return
	end

	for _, state in ipairs(slot.originalAppearance) do
		local part = state.part
		if part and part.Parent then
			local targetSize = computeHiddenSize(state.size)
			part.Transparency = 0
			part.Color = state.color

			if PLATFORM_HIDE_TWEEN_INFO.Time > 0 then
				local tween = TweenService:Create(part, PLATFORM_HIDE_TWEEN_INFO, {
					Size = targetSize,
				})
				slot.activeTweens[part] = tween
				tween.Completed:Connect(function()
					if slot.activeTweens then
						slot.activeTweens[part] = nil
					end
					if part.Parent then
						part.Size = targetSize
					end
				end)
				tween:Play()
			else
				part.Size = targetSize
			end
		end
	end

	clearDictionary(slot.touchCounts)
end

local function cancelReadyWarning(player, skipSignal)
	local record = readyWarningTasks[player]
	if not record then
		if not skipSignal then
			remotes.ReadyWarning:FireClient(player, { active = false, timeLeft = 0 })
		end
		return
	end

	record.cancelled = true
	readyWarningTasks[player] = nil

	if not skipSignal then
		remotes.ReadyWarning:FireClient(player, { active = false, timeLeft = 0 })
	end
end

local function startReadyWarning(player)
	cancelReadyWarning(player, true)

	local duration = READY_TIMEOUT
	if duration <= 0 then
		return
	end

	local record = { cancelled = false }
	readyWarningTasks[player] = record

	task.spawn(function()
		local remaining = duration
		while remaining > 0 and not record.cancelled do
			remotes.ReadyWarning:FireClient(player, {
				active = true,
				timeLeft = remaining,
			})
			task.wait(1)
			remaining -= 1
		end

		if record.cancelled then
			return
		end

		readyWarningTasks[player] = nil
		remotes.ReadyWarning:FireClient(player, { active = false, timeLeft = 0 })

		if not playerSlotLookup[player] then
			return
		end

		teleportPlayerToLobby(player)
		removePlayerFromSlot(player)
	end)
end

local function updateReadyWarnings()
	local leftReady = false
	local rightReady = false

	for player, slotInfo in pairs(playerSlotLookup) do
		if slotInfo.side == "Left" and readyPlayers[player] then
			leftReady = true
		elseif slotInfo.side == "Right" and readyPlayers[player] then
			rightReady = true
		end
	end

	for player, slotInfo in pairs(playerSlotLookup) do
		if slotInfo.side == "Left" then
			if rightReady and not readyPlayers[player] then
				startReadyWarning(player)
			else
				cancelReadyWarning(player)
			end
		else -- Right
			if leftReady and not readyPlayers[player] then
				startReadyWarning(player)
			else
				cancelReadyWarning(player)
			end
		end
	end
end

local function showPlatform(slot, shouldAnimate)
	if not slot then
		return
	end

	cancelActiveTweens(slot)
	slot.visible = true
	unlockPlatform(slot)
	slot.activeTweens = slot.activeTweens or {}

	if not slot.originalAppearance then
		return
	end

	for _, state in ipairs(slot.originalAppearance) do
		local part = state.part
		if part and part.Parent then
			if shouldAnimate then
				part.Size = computeHiddenSize(state.size)
				part.Transparency = 0
				part.Color = state.color
				local tween = TweenService:Create(part, PLATFORM_BOUNCE_TWEEN_INFO, {
					Size = state.size,
				})
				slot.activeTweens[part] = tween
				tween.Completed:Connect(function()
					if slot.activeTweens then
						slot.activeTweens[part] = nil
					end
				end)
				tween:Play()
			else
				part.Size = state.size
				part.Transparency = 0
				part.Color = state.color
			end
			part.CanTouch = true
			part.CanCollide = state.canCollide
		end
	end
end

local function incrementTouchCount(slot, player)
	if not slot or not player then
		return
	end
	slot.touchCounts = slot.touchCounts or {}
	slot.touchCounts[player] = (slot.touchCounts[player] or 0) + 1
end

local function canAssignToSlot(player, slot)
	if slot.index == 1 then
		return true
	end

	local sideSlots = platformSlots[slot.side]
	local previous = sideSlots and sideSlots[slot.index - 1]
	return previous ~= nil and previous.player ~= nil
end

local function decrementTouchCount(slot, player)
	if not slot or not player then
		return 0
	end
	local counts = slot.touchCounts
	if not counts then
		return 0
	end
	local current = counts[player]
	if not current then
		return 0
	end
	current -= 1
	if current <= 0 then
		counts[player] = nil
		return 0
	end
	counts[player] = current
	return current
end

local function refreshSideLocks(side)
	local sideSlots = platformSlots[side]
	if not sideSlots then
		return
	end

	for index, slot in ipairs(sideSlots) do
		local shouldShow = false
		if index == 1 then
			shouldShow = true
		else
			local previous = sideSlots[index - 1]
			if previous and previous.player then
				shouldShow = true
			end
		end

		if slot.player then
			shouldShow = true
			-- unlock next slot when this one is occupied
			local nextSlot = sideSlots[index + 1]
			if nextSlot then
				shouldShow = true
			end
		end

		if shouldShow then
			local animate = not slot.visible
			showPlatform(slot, animate)
			if slot.player then
				if readyPlayers[slot.player] then
					setSlotColor(slot, PLATFORM_COLOR_READY)
				else
					setSlotColor(slot, PLATFORM_COLOR_WAITING)
				end
			end
		else
			hidePlatform(slot)
		end
	end
end

local function sendHideUI(player)
	remotes.PlatformPrompt:FireClient(player, { action = "hide" })
	remotes.ReadyStatus:FireClient(player, false)
	remotes.ReadyWarning:FireClient(player, { active = false, timeLeft = 0 })
	remotes.ScoreboardUpdate:FireClient(player, {
		active = false,
		showReadiness = false,
		showPoints = false,
		scores = { Left = 0, Right = 0 },
		team1 = {},
		team2 = {},
	})
end

local function gatherSlots()
	for _, sideSlots in pairs(platformSlots) do
		for _, slot in ipairs(sideSlots) do
			if slot.touchConn then
				slot.touchConn:Disconnect()
			end
			if slot.touchEndedConn then
				slot.touchEndedConn:Disconnect()
			end
		end
	end

	platformSlots.Left = {}
	platformSlots.Right = {}

	if not levelModel then
		warn("[BombTag] BombLevel_1 not found; platforms unavailable.")
		return
	end

	local function registerSlot(part, side, number)
		local slot = {
			side = side,
			index = number,
			platform = part,
			player = nil,
			locked = true,
			originalAppearance = capturePlatformAppearance(part),
			activeTweens = {},
			touchCounts = {},
		}
		hidePlatform(slot)
		table.insert(platformSlots[side], slot)
	end

	local platformContainers = {}
	local platformsFolder = levelModel:FindFirstChild("Platforms")
	if platformsFolder then
		table.insert(platformContainers, platformsFolder)
	else
		table.insert(platformContainers, levelModel)
	end

	for _, container in ipairs(platformContainers) do
		for _, descendant in ipairs(container:GetDescendants()) do
			if descendant:IsA("BasePart") then
				local leftNumber = descendant.Name:match("^LeftPlatform(%d+)$")
				if leftNumber then
					registerSlot(descendant, "Left", tonumber(leftNumber))
				else
					local rightNumber = descendant.Name:match("^RightPlatform(%d+)$")
					if rightNumber then
						registerSlot(descendant, "Right", tonumber(rightNumber))
					end
				end
			end
		end
	end

	for side, sideSlots in pairs(platformSlots) do
		table.sort(sideSlots, function(a, b)
			return a.index < b.index
		end)
		for index, slot in ipairs(sideSlots) do
			slot.index = index
		end
		refreshSideLocks(side)
	end
end

local function collectLobbyEntries()
	local entries = {}
	for side, sideSlots in pairs(platformSlots) do
		for _, slot in ipairs(sideSlots) do
			if slot.player and slot.player.Parent then
				table.insert(entries, {
					player = slot.player,
					side = side,
				})
			end
		end
	end
	return entries
end

local function countPlayersPerSide()
	local leftCount, rightCount = 0, 0
	for side, sideSlots in pairs(platformSlots) do
		for _, slot in ipairs(sideSlots) do
			if slot.player and slot.player.Parent then
				if side == "Left" then
					leftCount += 1
				else
					rightCount += 1
				end
			end
		end
	end
	return leftCount, rightCount
end

local function cloneReadyEntries(entries)
	local cloned = {}
	for _, entry in ipairs(entries) do
		table.insert(cloned, {
			player = entry.player,
			side = entry.side,
			lobbySlot = entry.lobbySlot,
		})
	end
	return cloned
end

local function sendLobbyCountdown(value, phase, entries)
	entries = entries or lobbyCountdown.readyEntries
	if not entries then
		return
	end

	for _, entry in ipairs(entries) do
		local player = entry.player
		if player and player.Parent then
			remotes.CountdownUpdate:FireClient(player, value, phase)
		end
	end
end

local function publishLobbyScoreboard()
	local teamEntries = collectLobbyEntries()
	manager:publishLobbySnapshot(teamEntries, true)
end

local function stopLobbyCountdown(shouldBroadcast)
	local previousEntries = lobbyCountdown.readyEntries
	if lobbyCountdown.task then
		lobbyCountdown.generation += 1
		if coroutine.status(lobbyCountdown.task) ~= "dead" then
			local ok, err = pcall(task.cancel, lobbyCountdown.task)
			if not ok and err ~= "cannot cancel thread" then
				warn("[BombTag] Failed to cancel lobby countdown:", err)
			end
		end
		lobbyCountdown.task = nil
	end
	lobbyCountdown.readyEntries = nil
	if shouldBroadcast ~= false then
		sendLobbyCountdown(-1, "lobby", previousEntries)
	end
end

local function startLobbyCountdown(readyEntries)
	stopLobbyCountdown(false)

	lobbyCountdown.readyEntries = cloneReadyEntries(readyEntries)
	lobbyCountdown.generation += 1
	local generation = lobbyCountdown.generation
	local duration = Config.LobbyReadyCountdown or 5

	local countdownThread
	countdownThread = task.spawn(function()
		local countdown = duration
		while countdown > 0 do
			sendLobbyCountdown(countdown, "lobby")
			task.wait(1)
			if matchActive or lobbyCountdown.generation ~= generation then
				if lobbyCountdown.task == countdownThread then
					lobbyCountdown.task = nil
				end
				return
			end
			countdown -= 1
		end

		if matchActive or lobbyCountdown.generation ~= generation then
			if lobbyCountdown.task == countdownThread then
				lobbyCountdown.task = nil
			end
			return
		end

		sendLobbyCountdown(0, "lobby")

		local finalReadyEntries, leftReady, rightReady = gatherReadyEntries()
		local leftCount, rightCount = countPlayersPerSide()
		if
			matchActive
			or leftCount ~= rightCount
			or leftReady ~= leftCount
			or rightReady ~= rightCount
			or leftReady == 0
		then
			stopLobbyCountdown()
			return
		end

		local ok, err = manager:startMatch(finalReadyEntries)
		if not ok then
			warn("[BombTag] Failed to start match:", err)
			stopLobbyCountdown()
			return
		end

		if lobbyCountdown.task == countdownThread then
			lobbyCountdown.task = nil
		end
		lobbyCountdown.readyEntries = nil
	end)

	lobbyCountdown.task = countdownThread
end

evaluateLobbyCountdown = function()
	if matchActive then
		stopLobbyCountdown()
		return
	end

	local readyEntries, leftReady, rightReady = gatherReadyEntries()
	local leftCount, rightCount = countPlayersPerSide()

	if leftCount == 0 or rightCount == 0 then
		stopLobbyCountdown()
		return
	end

	if leftCount ~= rightCount then
		stopLobbyCountdown()
		return
	end

	if leftReady == leftCount and rightReady == rightCount and leftReady == rightReady and leftReady > 0 then
		if not lobbyCountdown.task then
			startLobbyCountdown(readyEntries)
		end
	else
		stopLobbyCountdown()
	end
end

local function releaseSlot(slot)
	if slot.player then
		sendHideUI(slot.player)
	end
	slot.player = nil
end

removePlayerFromSlot = function(player)
	local slotInfo = playerSlotLookup[player]
	if not slotInfo then
		return
	end

	cancelReadyWarning(player)

	local slot = platformSlots[slotInfo.side][slotInfo.index]
	if slot then
		releaseSlot(slot)
		restorePlatformAppearance(slot)
		clearDictionary(slot.touchCounts)
	end

	playerSlotLookup[player] = nil
	readyPlayers[player] = nil
	publishLobbyScoreboard()

	refreshSideLocks(slotInfo.side)
	updateReadyWarnings()
	evaluateLobbyCountdown()
end

local function clearAllSlots()
	for _, sideSlots in pairs(platformSlots) do
		for _, slot in ipairs(sideSlots) do
			releaseSlot(slot)
			restorePlatformAppearance(slot)
			clearDictionary(slot.touchCounts)
			hidePlatform(slot)
		end
	end
	playerSlotLookup = {}
	readyPlayers = {}
	for player in pairs(readyWarningTasks) do
		cancelReadyWarning(player)
	end
	publishLobbyScoreboard()

	refreshSideLocks("Left")
	refreshSideLocks("Right")
	updateReadyWarnings()
	stopLobbyCountdown()
end

local function isPlayerOnPlatform(player, platform)
	local character = player.Character
	if not character then
		return false
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end

	local pos = root.Position
	local platformPos = platform.Position
	local platformSize = platform.Size

	local withinX = math.abs(pos.X - platformPos.X) <= (platformSize.X / 2) + PLATFORM_TOUCH_RADIUS
	local withinZ = math.abs(pos.Z - platformPos.Z) <= (platformSize.Z / 2) + PLATFORM_TOUCH_RADIUS
	local heightDiff = math.abs(pos.Y - (platformPos.Y + platformSize.Y / 2))

	return withinX and withinZ and heightDiff <= MAX_PLATFORM_HEIGHT_OFFSET
end

local function assignPlayerToSlot(player, slot)
	if slot.player or matchActive then
		return
	end

	if not canAssignToSlot(player, slot) then
		return
	end

	if playerSlotLookup[player] then
		removePlayerFromSlot(player)
	end

	slot.player = player
	playerSlotLookup[player] = {
		side = slot.side,
		index = slot.index,
		platform = slot.platform,
	}
	readyPlayers[player] = false

	local function prompt()
		if player.Parent then
			warn(string.format("[BombTag][Server] Prompting %s for %s platform %d", player.Name, slot.side, slot.index))
			remotes.PlatformPrompt:FireClient(player, {
				action = "show",
				side = slot.side,
				platform = slot.index,
			})
			remotes.ReadyStatus:FireClient(player, false)
			remotes.ReadyWarning:FireClient(player, { active = false, timeLeft = 0 })
		end
	end
	-- fire immediately and once again shortly after to cope with replication delays
	prompt()
	task.delay(0.2, prompt)

	publishLobbyScoreboard()

	refreshSideLocks(slot.side)
	updateReadyWarnings()
	evaluateLobbyCountdown()
end

local function handleTouch(part, slot)
	local character = part.Parent
	if not character then
		return
	end
	local player = Players:GetPlayerFromCharacter(character)
	if not player or not player.Parent then
		return
	end

	if not isPlayerOnPlatform(player, slot.platform) then
		return
	end

	incrementTouchCount(slot, player)

	assignPlayerToSlot(player, slot)
end

local function handleTouchEnded(part, slot)
	local character = part.Parent
	if not character then
		return
	end
	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end

	local remaining = decrementTouchCount(slot, player)
	if remaining > 0 then
		return
	end

	if matchActive then
		return
	end

	local slotInfo = playerSlotLookup[player]
	if not slotInfo then
		return
	end

	local trackedSlot = platformSlots[slotInfo.side]
	if not trackedSlot then
		return
	end
	trackedSlot = trackedSlot[slotInfo.index]
	if trackedSlot ~= slot then
		return
	end

	removePlayerFromSlot(player)
end

local function connectTouchListeners()
	for _, sideSlots in pairs(platformSlots) do
		for _, slot in ipairs(sideSlots) do
			if slot.touchConn then
				slot.touchConn:Disconnect()
			end
			if slot.touchEndedConn then
				slot.touchEndedConn:Disconnect()
			end
			clearDictionary(slot.touchCounts)
			slot.touchConn = slot.platform.Touched:Connect(function(part)
				handleTouch(part, slot)
			end)
			slot.touchEndedConn = slot.platform.TouchEnded:Connect(function(part)
				handleTouchEnded(part, slot)
			end)
		end
	end
end

function gatherReadyEntries()
	local readyEntries = {}
	local leftReady, rightReady = 0, 0

	for player, slotInfo in pairs(playerSlotLookup) do
		if readyPlayers[player] and player.Parent then
			local slot = platformSlots[slotInfo.side] and platformSlots[slotInfo.side][slotInfo.index]
			local lobbyCFrame = nil
			if slot and slot.platform then
				lobbyCFrame = computeSurfaceCFrameForObject(slot.platform, Config.SpawnSurfaceOffset or 0.25)
				if lobbyCFrame and Config.RespawnExtraHeight then
					lobbyCFrame = lobbyCFrame * CFrame.new(0, Config.RespawnExtraHeight, 0)
				end
			end

			table.insert(readyEntries, {
				player = player,
				side = slotInfo.side,
				lobbySlot = {
					side = slotInfo.side,
					index = slotInfo.index,
					cframe = lobbyCFrame,
				},
			})
			if slotInfo.side == "Left" then
				leftReady += 1
			else
				rightReady += 1
			end
		end
	end

	return readyEntries, leftReady, rightReady
end

local function attachMatchSignals(player)
	local function bind(character)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end

		if matchConnections[player] and matchConnections[player].deathConn then
			matchConnections[player].deathConn:Disconnect()
		end

		matchConnections[player] = matchConnections[player] or {}
		matchConnections[player].deathConn = humanoid.Died:Connect(function()
			manager:handlePlayerDeath(player)
		end)
	end

	if matchConnections[player] and matchConnections[player].charConn then
		matchConnections[player].charConn:Disconnect()
	end

	matchConnections[player] = matchConnections[player] or {}
	matchConnections[player].charConn = player.CharacterAdded:Connect(bind)

	if player.Character then
		bind(player.Character)
	end
end

local function clearMatchSignals(player)
	local record = matchConnections[player]
	if record then
		if record.deathConn then
			record.deathConn:Disconnect()
		end
		if record.charConn then
			record.charConn:Disconnect()
		end
	end
	matchConnections[player] = nil
end

local function handleMatchWinners(context)
	if not context then
		return
	end

	local winners = context.players
	local coins = tonumber(context.coins) or 0
	if coins <= 0 or typeof(winners) ~= "table" then
		return
	end

	for _, player in ipairs(winners) do
		if player and player.Parent then
			local success, newCoins = pcall(PlayerProfile.addCoins, player.UserId, coins)
			if not success then
				warn(string.format("[BombTag] Failed to award coins to %s: %s", player.Name, tostring(newCoins)))
				newCoins = select(1, PlayerProfile.getBalances(player.UserId))
			end

			if currencyUpdatedRemote then
				local coinsBalance = typeof(newCoins) == "number" and newCoins
					or select(1, PlayerProfile.getBalances(player.UserId))
				currencyUpdatedRemote:FireClient(player, {
					Coins = coinsBalance,
					AwardedCoins = coins,
				})
			end
		end
	end
end

local function handleMatchStarted(context)
	stopLobbyCountdown()

	matchActive = true
	matchParticipants = {}

	for _, entry in ipairs(context.players) do
		matchParticipants[entry.player] = true
		attachMatchSignals(entry.player)
	end

	clearAllSlots()
end

local function handleMatchEnded()
	stopLobbyCountdown()

	matchActive = false
	matchParticipants = {}

	for player in pairs(matchConnections) do
		clearMatchSignals(player)
	end

	clearAllSlots()
end

manager._callbacks.onMatchStarted = handleMatchStarted
manager._callbacks.onMatchEnded = handleMatchEnded
manager._callbacks.onMatchWinners = handleMatchWinners

local function tryStartMatch()
	evaluateLobbyCountdown()
end

local function toggleReady(player)
	if matchActive then
		return
	end

	if not playerSlotLookup[player] then
		return
	end

	readyPlayers[player] = not readyPlayers[player]
	local slotInfo = playerSlotLookup[player]
	if slotInfo then
		refreshSideLocks(slotInfo.side)
	end
	remotes.ReadyStatus:FireClient(player, readyPlayers[player])
	publishLobbyScoreboard()
	updateReadyWarnings()
	tryStartMatch()
end

local function onPlayerRemoving(player)
	if matchParticipants[player] then
		manager:removePlayer(player)
	end
	clearMatchSignals(player)
	removePlayerFromSlot(player)
end

local function onCharacterRemoving(player)
	if matchActive and matchParticipants[player] then
		manager:handlePlayerDeath(player)
	end
	removePlayerFromSlot(player)
end

Players.PlayerRemoving:Connect(onPlayerRemoving)

local function setupPlayer(player)
	player.CharacterRemoving:Connect(function()
		onCharacterRemoving(player)
	end)
end

Players.PlayerAdded:Connect(setupPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	setupPlayer(player)
end

gatherSlots()
connectTouchListeners()
publishLobbyScoreboard()

remotes.ReadyToggle.OnServerEvent:Connect(function(player)
	toggleReady(player)
end)

RunService.Heartbeat:Connect(function()
	if matchActive then
		return
	end

	for player, slotInfo in pairs(playerSlotLookup) do
		if not player.Parent or not isPlayerOnPlatform(player, slotInfo.platform) then
			removePlayerFromSlot(player)
		end
	end
end)
