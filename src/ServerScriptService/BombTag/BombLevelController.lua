local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local PlayerProfile = require(ServerScriptService:WaitForChild("PlayerProfile"))

local BombMatchManager = require(ReplicatedStorage:WaitForChild("BombTag"):WaitForChild("BombMatchManager"))

local BombLevelController = {}
BombLevelController.__index = BombLevelController

type Callbacks = {
	onPlayerAssigned: ((Player, string, number, any) -> ())?,
	onPlayerRemoved: ((Player, string?, number?, any) -> ())?,
	onMatchStateChanged: ((any, boolean) -> ())?,
	onMatchStarted: ((any, any) -> ())?,
	onMatchEnded: ((any) -> ())?,
}

type ControllerArgs = {
	level: Model | Folder,
	lobbySpawner: BasePart | Model?,
	remotes: {
		GameStart: RemoteEvent,
		CountdownUpdate: RemoteEvent,
		BombAssigned: RemoteEvent,
		BombPassed: RemoteEvent,
		BombTimerUpdate: RemoteEvent,
		PlayerEliminated: RemoteEvent,
		GameEnd: RemoteEvent,
		ScoreboardUpdate: RemoteEvent,
		PlatformPrompt: RemoteEvent,
		ReadyStatus: RemoteEvent,
		ReadyWarning: RemoteEvent,
		ReadyToggle: RemoteEvent,
	},
	currencyRemote: RemoteEvent?,
	configModule: ModuleScript,
	config: table,
	levelId: string?,
	levelName: string?,
	callbacks: Callbacks?,
}

local function computeSurfaceCFrameForObject(object, offset, config)
	if not object then
		return nil
	end

	offset = offset or 0
	local totalOffset = offset + (config.RespawnExtraHeight or 0)

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

local function clearDictionary(dict)
	if not dict then
		return
	end
	for key in pairs(dict) do
		dict[key] = nil
	end
end

local function capturePlatformAppearance(instance)
	local appearance = {}

	local function record(part)
		table.insert(appearance, {
			part = part,
			color = part.Color,
			transparency = part.Transparency,
			visibleTransparency = part:GetAttribute("BombPlatformVisibleTransparency"),
			hiddenTransparency = part:GetAttribute("BombPlatformHiddenTransparency"),
			visibleColor = part:GetAttribute("BombPlatformVisibleColor"),
			hiddenColor = part:GetAttribute("BombPlatformHiddenColor"),
			size = part.Size,
			canTouch = part.CanTouch,
			canCollide = part.CanCollide,
			material = part.Material,
			visibleCanCollide = part:GetAttribute("BombPlatformVisibleCanCollide"),
			hiddenCanCollide = part:GetAttribute("BombPlatformHiddenCanCollide"),
			visibleCanTouch = part:GetAttribute("BombPlatformVisibleCanTouch"),
			hiddenCanTouch = part:GetAttribute("BombPlatformHiddenCanTouch"),
			visibleMaterial = part:GetAttribute("BombPlatformVisibleMaterial"),
			hiddenMaterial = part:GetAttribute("BombPlatformHiddenMaterial"),
		})
	end

	if instance:IsA("BasePart") then
		record(instance)
	end

	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			record(descendant)
		end
	end

	return appearance
end

local PLATFORM_HIDDEN_SCALE_DEFAULT = 0
local PLATFORM_HIDDEN_MIN_SIZE_DEFAULT = 0

local PLATFORM_COLOR_WAITING_DEFAULT = Color3.fromRGB(0, 170, 255)
local PLATFORM_COLOR_READY_DEFAULT = Color3.fromRGB(0, 200, 0)

local function getOppositeSide(side)
	if side == "Left" then
		return "Right"
	elseif side == "Right" then
		return "Left"
	end
	return nil
end

local function getNextSlot(collection, index)
	if not collection then
		return nil
	end
	return collection[index + 1]
end

local function isPrimarySlot(slot)
	if not slot then
		return false
	end
	return slot.index == 1
end

local function shouldKeepSlotVisible(slot, matchActive)
	if matchActive then
		return false
	end
	return isPrimarySlot(slot)
end

local function describeSlot(slot)
	if not slot then
		return "nil"
	end
	return string.format(
		"%s/%d visible=%s locked=%s player=%s",
		tostring(slot.side),
		tonumber(slot.index) or -1,
		tostring(slot.visible),
		tostring(slot.locked),
		slot.player and slot.player.Name or "nil"
	)
end

local function formatExtra(extra)
	if not extra then
		return ""
	end
	local items = {}
	for key, value in pairs(extra) do
		table.insert(items, string.format("%s=%s", tostring(key), tostring(value)))
	end
	table.sort(items)
	if #items == 0 then
		return ""
	end
	return " [" .. table.concat(items, " ") .. "]"
end

function BombLevelController.new(args: ControllerArgs)
	local self = setmetatable({}, BombLevelController)

	self._level = args.level
	self._lobbySpawner = args.lobbySpawner
	self._remotes = args.remotes
	self._configModule = args.configModule
	self._config = args.config
	self._levelId = args.levelId or (self._level and self._level.Name) or "BombLevel"
	self._levelName = args.levelName or self._levelId
	self._callbacks = args.callbacks or {}
	self._currencyUpdatedRemote = args.currencyRemote

	self._platformSlots = {
		Left = {},
		Right = {},
	}
	self._playerSlotLookup = {}
	self._readyPlayers = {}
	self._matchParticipants = {}
	self._matchConnections = {}
	self._matchActive = false
	self._readyWarningTasks = {}
	self._lobbyCountdown = { task = nil, generation = 0, readyEntries = nil }
	self._pendingWinnerReward = nil
	self._platformDebugLogging = true

	self._PLATFORM_TOUCH_RADIUS = self._config.PlatformTouchRadius or 12
	self._MAX_PLATFORM_HEIGHT_OFFSET = self._config.PlatformHeightTolerance or 6
	self._PLATFORM_HORIZONTAL_TOLERANCE = self._config.PlatformHorizontalTolerance or 1.5
	self._PLATFORM_RAYCAST_DISTANCE = self._config.PlatformRaycastDistance or 8
	self._PLATFORM_COLOR_WAITING = self._config.PlatformColorWaiting or PLATFORM_COLOR_WAITING_DEFAULT
	self._PLATFORM_COLOR_READY = self._config.PlatformColorReady or PLATFORM_COLOR_READY_DEFAULT
	self._PLATFORM_HIDDEN_SCALE = 0
	self._PLATFORM_HIDDEN_MIN_SIZE = self._config.PlatformHiddenMinSize or PLATFORM_HIDDEN_MIN_SIZE_DEFAULT
	self._PLATFORM_BOUNCE_TWEEN_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out)
	self._PLATFORM_HIDE_TWEEN_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	self._READY_TIMEOUT = self._config.ReadyTimeout or 10

	self._manager = BombMatchManager.new({
		remotes = self._remotes,
		config = self._configModule,
		workspaceRefs = {
			level = self._level,
			lobbySpawner = self._lobbySpawner,
		},
		metadata = {
			levelId = self._levelId,
			levelName = self._levelName,
		},
	})

	self._manager._callbacks.onMatchStarted = function(context)
		self:_handleMatchStarted(context)
	end
	self._manager._callbacks.onMatchEnded = function()
		self:_handleMatchEnded()
	end
	self._manager._callbacks.onMatchWinners = function(context)
		self:_handleMatchWinners(context)
	end
	self._manager._callbacks.onPlayersTeleported = function(players)
		self:_handlePlayersTeleported(players)
	end

	self:_gatherSlots()
	self:_connectTouchListeners()
	self:_publishLobbyScoreboard()

	self._heartbeatConn = RunService.Heartbeat:Connect(function()
		self:_onHeartbeat()
	end)

	return self
end

function BombLevelController:getLevel()
	return self._level
end

function BombLevelController:getLevelId()
	return self._levelId
end

function BombLevelController:setLobbySpawner(spawner)
	self._lobbySpawner = spawner
	self._manager:updateWorkspaceRefs({
		level = self._level,
		lobbySpawner = self._lobbySpawner,
	})
end

function BombLevelController:updateLevel(level)
	self._level = level
	self._manager:updateWorkspaceRefs({
		level = self._level,
		lobbySpawner = self._lobbySpawner,
	})
	self:_gatherSlots()
	self:_connectTouchListeners()
	self:_publishLobbyScoreboard()
end

function BombLevelController:destroy()
	if self._heartbeatConn then
		self._heartbeatConn:Disconnect()
		self._heartbeatConn = nil
	end

	for _, sideSlots in pairs(self._platformSlots) do
		for _, slot in ipairs(sideSlots) do
			if slot.touchConn then
				slot.touchConn:Disconnect()
				slot.touchConn = nil
			end
			if slot.touchEndedConn then
				slot.touchEndedConn:Disconnect()
				slot.touchEndedConn = nil
			end
		end
	end

	self:_clearAllSlots(true)
end

function BombLevelController:ownsPlayer(player)
	if self._playerSlotLookup[player] then
		return true
	end
	if self._matchParticipants[player] then
		return true
	end
	return false
end

function BombLevelController:handleReadyToggle(player)
	self:_toggleReady(player)
end

function BombLevelController:onPlayerRemoving(player)
	if self._matchParticipants[player] then
		self._manager:removePlayer(player)
	end
	self:_clearMatchSignals(player)
	self:_removePlayerFromSlot(player)
end

function BombLevelController:onCharacterRemoving(player)
	if self._matchActive and self._matchParticipants[player] then
		self._manager:handlePlayerDeath(player)
	end
	self:_removePlayerFromSlot(player)
end

function BombLevelController:getManager()
	return self._manager
end

-- Internal logic ------------------------------------------------------------------------

function BombLevelController:_iteratePlatformParts(instance, callback)
	if instance:IsA("BasePart") then
		callback(instance)
	else
		for _, descendant in ipairs(instance:GetDescendants()) do
			if descendant:IsA("BasePart") then
				callback(descendant)
			end
		end
	end

	self:_evaluateLobbyCountdown()
end

function BombLevelController:_setSlotColor(slot, color)
	if not slot or not slot.originalAppearance then
		return
	end
	for _, state in ipairs(slot.originalAppearance) do
		local part = state.part
		if part and part.Parent then
			part.Color = color
			local ok, brickColor = pcall(BrickColor.new, color)
			if ok then
				part.BrickColor = brickColor
			end
		end
	end
	if slot.platform and slot.platform.Parent then
		slot.platform.Color = color
		local ok, brickColor = pcall(BrickColor.new, color)
		if ok then
			slot.platform.BrickColor = brickColor
		end
	end
end

function BombLevelController:_applySlotVisualState(slot)
	if not slot then
		return
	end
	local occupant = slot.player
	if occupant then
		local isReady = self._readyPlayers[occupant] and true or false
		local targetColor = isReady and self._PLATFORM_COLOR_READY or self._PLATFORM_COLOR_WAITING
		self:_setSlotColor(slot, targetColor)
	else
		if slot.visible then
			self:_applyDefaultAppearance(slot)
		end
	end
end

function BombLevelController:_restorePlatformAppearance(slot)
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

function BombLevelController:_applyDefaultAppearance(slot)
	if not slot or not slot.originalAppearance then
		return
	end

	for _, state in ipairs(slot.originalAppearance) do
		local part = state.part
		if part and part.Parent then
			local transparency = state.visibleTransparency
			if transparency == nil then
				transparency = self._config.PlatformVisibleTransparency
			end
			if transparency == nil then
				transparency = 0
			end
			part.Transparency = transparency

			local color = state.visibleColor or state.color
			if color then
				part.Color = color
				local ok, brickColor = pcall(BrickColor.new, color)
				if ok then
					part.BrickColor = brickColor
				end
			end

			if state.visibleCanCollide ~= nil then
				part.CanCollide = state.visibleCanCollide
			else
				part.CanCollide = state.canCollide
			end

			if state.visibleCanTouch ~= nil then
				part.CanTouch = state.visibleCanTouch
			else
				part.CanTouch = state.canTouch
			end

			if state.visibleMaterial ~= nil then
				part.Material = state.visibleMaterial
			else
				part.Material = state.material
			end
		end
	end
end

function BombLevelController:_lockPlatform(slot)
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

function BombLevelController:_unlockPlatform(slot)
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

function BombLevelController:_computeHiddenSize(originalSize)
	return Vector3.new(
		math.max(self._PLATFORM_HIDDEN_MIN_SIZE, 0),
		math.max(self._PLATFORM_HIDDEN_MIN_SIZE, 0),
		math.max(self._PLATFORM_HIDDEN_MIN_SIZE, 0)
	)
end

function BombLevelController:_cancelActiveTweens(slot)
	if slot and slot.activeTweens then
		for _, tween in pairs(slot.activeTweens) do
			if tween then
				tween:Cancel()
			end
		end
		clearDictionary(slot.activeTweens)
	end
end

function BombLevelController:_hidePlatform(slot, shouldAnimate)
	if not slot then
		return
	end

	self:_cancelActiveTweens(slot)
	slot.visible = false
	self:_lockPlatform(slot)
	slot.activeTweens = slot.activeTweens or {}

	if not slot.originalAppearance then
		return
	end

	for _, state in ipairs(slot.originalAppearance) do
		local part = state.part
		if part and part.Parent then
			local hiddenTransparency = state.hiddenTransparency
			if hiddenTransparency == nil then
				hiddenTransparency = self._config.PlatformHiddenTransparency
			end
			if hiddenTransparency == nil then
				hiddenTransparency = 1
			end
			local hiddenColor = state.hiddenColor or state.color
			if hiddenColor then
				part.Color = hiddenColor
				local ok, brickColor = pcall(BrickColor.new, hiddenColor)
				if ok then
					part.BrickColor = brickColor
				end
			end

			part.Size = state.size

			if state.hiddenCanCollide ~= nil then
				part.CanCollide = state.hiddenCanCollide
			else
				part.CanCollide = false
			end
			if state.hiddenCanTouch ~= nil then
				part.CanTouch = state.hiddenCanTouch
			else
				part.CanTouch = false
			end
			if state.hiddenMaterial ~= nil then
				part.Material = state.hiddenMaterial
			else
				part.Material = state.material
			end

			local targetSize = self:_computeHiddenSize(state.size)
			local tweenProps = {
				Size = targetSize,
			}
			if part.Transparency ~= hiddenTransparency then
				tweenProps.Transparency = hiddenTransparency
			end

			if shouldAnimate and self._PLATFORM_HIDE_TWEEN_INFO.Time > 0 then
				part.Size = state.size
				local tween = TweenService:Create(part, self._PLATFORM_HIDE_TWEEN_INFO, tweenProps)
				slot.activeTweens = slot.activeTweens or {}
				slot.activeTweens[part] = tween
				tween.Completed:Connect(function()
					if slot.activeTweens then
						slot.activeTweens[part] = nil
					end
					if part.Parent then
						part.Size = targetSize
						if tweenProps.Transparency then
							part.Transparency = hiddenTransparency
						end
					end
				end)
				tween:Play()
			else
				part.Size = targetSize
				if tweenProps.Transparency then
					part.Transparency = hiddenTransparency
				end
			end
		end
	end

	clearDictionary(slot.touchCounts)

	self:_logPlatform("hide", slot)
end

function BombLevelController:_showPlatform(slot, shouldAnimate)
	if not slot then
		return
	end

	self:_cancelActiveTweens(slot)
	slot.visible = true
	self:_unlockPlatform(slot)

	if not slot.originalAppearance then
		return
	end

	for _, state in ipairs(slot.originalAppearance) do
		local part = state.part
		if part and part.Parent then
			local visibleTransparency = state.visibleTransparency
			if visibleTransparency == nil then
				visibleTransparency = self._config.PlatformVisibleTransparency
			end
			if visibleTransparency == nil then
				visibleTransparency = 0
			end
			part.Transparency = visibleTransparency

			local visibleColor = state.visibleColor or state.color
			if visibleColor then
				part.Color = visibleColor
				local ok, brickColor = pcall(BrickColor.new, visibleColor)
				if ok then
					part.BrickColor = brickColor
				end
			end

			local visibleSize = state.size
			local hiddenSize = self:_computeHiddenSize(state.size)
			local hiddenTransparency = state.hiddenTransparency
			if hiddenTransparency == nil then
				hiddenTransparency = self._config.PlatformHiddenTransparency
			end
			if hiddenTransparency == nil then
				hiddenTransparency = 1
			end

			if shouldAnimate and self._PLATFORM_HIDE_TWEEN_INFO.Time > 0 then
				part.Size = hiddenSize
				part.Transparency = hiddenTransparency

				local tweenProps = {
					Size = visibleSize,
				}
				if visibleTransparency ~= hiddenTransparency then
					tweenProps.Transparency = visibleTransparency
				end

				local tween = TweenService:Create(part, self._PLATFORM_HIDE_TWEEN_INFO, tweenProps)
				slot.activeTweens = slot.activeTweens or {}
				slot.activeTweens[part] = tween
				tween.Completed:Connect(function()
					if slot.activeTweens then
						slot.activeTweens[part] = nil
					end
					if part.Parent then
						part.Size = visibleSize
						part.Transparency = visibleTransparency
					end
				end)
				tween:Play()
			else
				part.Size = visibleSize
				part.Transparency = visibleTransparency
			end
			if state.visibleCanCollide ~= nil then
				part.CanCollide = state.visibleCanCollide
			else
				part.CanCollide = state.canCollide
			end
			if state.visibleCanTouch ~= nil then
				part.CanTouch = state.visibleCanTouch
			else
				part.CanTouch = state.canTouch
			end
			if state.visibleMaterial ~= nil then
				part.Material = state.visibleMaterial
			else
				part.Material = state.material
			end
		end
	end

	self:_applySlotVisualState(slot)

	self:_logPlatform("show", slot, { animate = shouldAnimate })
end

function BombLevelController:_resetSlotState(slot)
	if not slot then
		return
	end
	slot.player = nil
	slot.currentColor = nil
	self:_restorePlatformAppearance(slot)
end

function BombLevelController:_resetLobbyPlatforms()
	for side, sideSlots in pairs(self._platformSlots) do
		for index, slot in ipairs(sideSlots) do
			if index == 1 then
				slot.visible = true
				slot.locked = false
				self:_unlockPlatform(slot)
				self:_showPlatform(slot, false)
			else
				slot.visible = false
				slot.locked = true
				self:_hidePlatform(slot, false)
			end
		end
	end
end

function BombLevelController:_setSlotReady(slot, isReady)
	if not slot then
		return
	end
	self:_applySlotVisualState(slot)
end

function BombLevelController:_setReadyState(player, isReady)
	self._readyPlayers[player] = isReady and true or false
	local slotInfo = self._playerSlotLookup[player]
	if not slotInfo then
		return
	end
	local slot = self._platformSlots[slotInfo.side] and self._platformSlots[slotInfo.side][slotInfo.index]
	if slot then
		self:_setSlotReady(slot, isReady)
	end
end

function BombLevelController:_gatherSlots()
	for _, sideSlots in pairs(self._platformSlots) do
		for _, slot in ipairs(sideSlots) do
			if slot.touchConn then
				slot.touchConn:Disconnect()
			end
			if slot.touchEndedConn then
				slot.touchEndedConn:Disconnect()
			end
		end
	end

	self._platformSlots.Left = {}
	self._platformSlots.Right = {}

	if not self._level then
		warn(string.format("[BombTag] BombLevel '%s' not found; platforms unavailable.", tostring(self._levelId)))
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
			touchConn = nil,
			touchEndedConn = nil,
		}
		table.insert(self._platformSlots[side], slot)
	end

	local platformContainers = {}
	local platformsFolder = self._level:FindFirstChild("Platforms")
	if platformsFolder then
		table.insert(platformContainers, platformsFolder)
	else
		table.insert(platformContainers, self._level)
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

	for side, sideSlots in pairs(self._platformSlots) do
		table.sort(sideSlots, function(a, b)
			return a.index < b.index
		end)
		for index, slot in ipairs(sideSlots) do
			slot.index = index
			if index == 1 then
				slot.visible = true
				slot.locked = false
				self:_showPlatform(slot, false)
			else
				slot.visible = false
				slot.locked = true
				self:_hidePlatform(slot, false)
			end
		end
		self:_refreshSideLocks(side)
	end
end

function BombLevelController:_connectTouchListeners()
	for _, sideSlots in pairs(self._platformSlots) do
		for _, slot in ipairs(sideSlots) do
			if slot.touchConn then
				slot.touchConn:Disconnect()
			end
			if slot.touchEndedConn then
				slot.touchEndedConn:Disconnect()
			end
			clearDictionary(slot.touchCounts)
			slot.touchConn = slot.platform.Touched:Connect(function(part)
				self:_handleTouch(part, slot)
			end)
			slot.touchEndedConn = slot.platform.TouchEnded:Connect(function(part)
				self:_handleTouchEnded(part, slot)
			end)
		end
	end
end

function BombLevelController:_publishLobbyScoreboard()
	local teamEntries = self:_collectLobbyEntries()
	self._manager:publishLobbySnapshot(teamEntries, true)
end

function BombLevelController:_teleportPlayerToLobby(player)
	if not player or not player.Parent then
		return
	end

	local spawnObject = self._lobbySpawner or Workspace:FindFirstChild("BombLobbySpawner")
	if not spawnObject then
		warn("[BombTag] BombLobbySpawner not found; cannot teleport player to lobby.")
		return
	end

	local spawnCFrame = computeSurfaceCFrameForObject(
		spawnObject,
		self._config.SpawnSurfaceOffset or 0.25,
		self._config
	)
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
			humanoid.WalkSpeed = self._config.PlayerDefaultWalkSpeed or 16
			humanoid.JumpPower = self._config.PlayerDefaultJumpPower or 50
		end
	end)
end

function BombLevelController:_cancelReadyWarning(player, skipSignal)
	local record = self._readyWarningTasks[player]
	if not record then
		if not skipSignal then
			self._remotes.ReadyWarning:FireClient(player, { active = false, timeLeft = 0 })
		end
		return
	end

	record.cancelled = true
	self._readyWarningTasks[player] = nil

	if not skipSignal then
		self._remotes.ReadyWarning:FireClient(player, { active = false, timeLeft = 0 })
	end
end

function BombLevelController:_startReadyWarning(player)
	self:_cancelReadyWarning(player, true)

	local duration = self._READY_TIMEOUT
	if duration <= 0 then
		return
	end

	local record = { cancelled = false }
	self._readyWarningTasks[player] = record

	task.spawn(function()
		local remaining = duration
		while remaining > 0 and not record.cancelled do
			self._remotes.ReadyWarning:FireClient(player, {
				active = true,
				timeLeft = remaining,
			})
			task.wait(1)
			remaining -= 1
		end

		if record.cancelled then
			return
		end

		self._readyWarningTasks[player] = nil
		self._remotes.ReadyWarning:FireClient(player, { active = false, timeLeft = 0 })

		if not self._playerSlotLookup[player] then
			return
		end

		self:_teleportPlayerToLobby(player)
		self:_removePlayerFromSlot(player)
	end)
end

function BombLevelController:_updateReadyWarnings()
	local leftReady = false
	local rightReady = false

	for player, slotInfo in pairs(self._playerSlotLookup) do
		if slotInfo.side == "Left" and self._readyPlayers[player] then
			leftReady = true
		elseif slotInfo.side == "Right" and self._readyPlayers[player] then
			rightReady = true
		end
	end

	for player, slotInfo in pairs(self._playerSlotLookup) do
		if slotInfo.side == "Left" then
			if rightReady and not self._readyPlayers[player] then
				self:_startReadyWarning(player)
			else
				self:_cancelReadyWarning(player)
			end
		else -- Right
			if leftReady and not self._readyPlayers[player] then
				self:_startReadyWarning(player)
			else
				self:_cancelReadyWarning(player)
			end
		end
	end
end

function BombLevelController:_collectLobbyEntries()
	local entries = {}
	for side, sideSlots in pairs(self._platformSlots) do
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

function BombLevelController:_countPlayersPerSide()
	local leftCount, rightCount = 0, 0
	for side, sideSlots in pairs(self._platformSlots) do
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

function BombLevelController:_cloneReadyEntries(entries)
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

function BombLevelController:_sendLobbyCountdown(value, phase, entries)
	entries = entries or self._lobbyCountdown.readyEntries
	if not entries then
		return
	end

	for _, entry in ipairs(entries) do
		local player = entry.player
		if player and player.Parent then
			self._remotes.CountdownUpdate:FireClient(player, value, phase)
		end
	end
end

function BombLevelController:_stopLobbyCountdown(shouldBroadcast)
	local previousEntries = self._lobbyCountdown.readyEntries
	if self._lobbyCountdown.task then
		self._lobbyCountdown.generation += 1
		if coroutine.status(self._lobbyCountdown.task) ~= "dead" then
			local ok, err = pcall(task.cancel, self._lobbyCountdown.task)
			if not ok and err ~= "cannot cancel thread" then
				warn("[BombTag] Failed to cancel lobby countdown:", err)
			end
		end
		self._lobbyCountdown.task = nil
	end
	self._lobbyCountdown.readyEntries = nil
	if shouldBroadcast ~= false then
		self:_sendLobbyCountdown(-1, "lobby", previousEntries)
	end
end

function BombLevelController:_startLobbyCountdown(readyEntries)
	self:_stopLobbyCountdown(false)

	self._lobbyCountdown.readyEntries = self:_cloneReadyEntries(readyEntries)
	self._lobbyCountdown.generation += 1
	local generation = self._lobbyCountdown.generation
	local duration = self._config.LobbyReadyCountdown or 5

	local countdownThread
	countdownThread = task.spawn(function()
		local countdown = duration
		while countdown > 0 do
			self:_sendLobbyCountdown(countdown, "lobby")
			task.wait(1)
			if self._matchActive or self._lobbyCountdown.generation ~= generation then
				if self._lobbyCountdown.task == countdownThread then
					self._lobbyCountdown.task = nil
				end
				return
			end
			countdown -= 1
		end

		if self._matchActive or self._lobbyCountdown.generation ~= generation then
			if self._lobbyCountdown.task == countdownThread then
				self._lobbyCountdown.task = nil
			end
			return
		end

		self:_sendLobbyCountdown(0, "lobby")

		local finalReadyEntries, leftReady, rightReady = self:_gatherReadyEntries()
		local leftCount, rightCount = self:_countPlayersPerSide()
		if
			self._matchActive
			or leftCount ~= rightCount
			or leftReady ~= leftCount
			or rightReady ~= rightCount
			or leftReady == 0
		then
			if self._lobbyCountdown.task == countdownThread then
				self._lobbyCountdown.task = nil
				self._lobbyCountdown.readyEntries = nil
			end
			return
		end

		local ok, err = self._manager:startMatch(finalReadyEntries)
		if not ok then
			warn("[BombTag] Failed to start match:", err)
			self:_stopLobbyCountdown()
			return
		end

		if self._lobbyCountdown.task == countdownThread then
			self._lobbyCountdown.task = nil
		end
		self._lobbyCountdown.readyEntries = nil
	end)

	self._lobbyCountdown.task = countdownThread
end

function BombLevelController:_evaluateLobbyCountdown()
	if self._matchActive then
		self:_stopLobbyCountdown()
		return
	end

	local readyEntries, leftReady, rightReady = self:_gatherReadyEntries()
	local leftCount, rightCount = self:_countPlayersPerSide()

	if leftCount == 0 or rightCount == 0 then
		self:_stopLobbyCountdown()
		return
	end

	if leftCount ~= rightCount then
		self:_stopLobbyCountdown()
		return
	end

	if leftReady == leftCount and rightReady == rightCount and leftReady == rightReady and leftReady > 0 then
		if not self._lobbyCountdown.task then
			self:_startLobbyCountdown(readyEntries)
		end
	else
		self:_stopLobbyCountdown()
	end
end

function BombLevelController:_releaseSlot(slot, suppressGui)
	if slot.player and not suppressGui then
		self:_sendHideUI(slot.player)
		self:_sendClearScoreboard(slot.player)
	end
	slot.player = nil
end

function BombLevelController:_removePlayerFromSlot(player)
	local slotInfo = self._playerSlotLookup[player]
	if not slotInfo then
		return
	end

	self:_cancelReadyWarning(player)

	local sideSlots = self._platformSlots[slotInfo.side]
	local currentSlot = self._platformSlots[slotInfo.side] and self._platformSlots[slotInfo.side][slotInfo.index]
	local previousSlot = nil
	if slotInfo.index > 1 and sideSlots then
		previousSlot = sideSlots[slotInfo.index - 1]
	end
	local keepCurrentVisible = shouldKeepSlotVisible(currentSlot, self._matchActive)
	if previousSlot and previousSlot.player then
		keepCurrentVisible = true
	end

	if currentSlot then
		self:_releaseSlot(currentSlot)
		clearDictionary(currentSlot.touchCounts)
		if keepCurrentVisible then
			currentSlot.visible = true
			currentSlot.locked = false
			self:_unlockPlatform(currentSlot)
			self:_showPlatform(currentSlot, false)
		else
			currentSlot.visible = false
			currentSlot.locked = true
			self:_hidePlatform(currentSlot, true)
		end
		self:_logPlatform("removed-player", currentSlot, {
			player = player.Name,
			matchActive = self._matchActive,
		})
	end

	local nextSlot = getNextSlot(self._platformSlots[slotInfo.side], slotInfo.index)
	if nextSlot and not nextSlot.player then
		nextSlot.visible = false
		nextSlot.locked = true
		self:_hidePlatform(nextSlot, true)
	end

	local oppositeSide = getOppositeSide(slotInfo.side)
	if oppositeSide then
		local oppositeSlots = self._platformSlots[oppositeSide]
		if oppositeSlots then
			local counterpart = oppositeSlots[slotInfo.index] or oppositeSlots[#oppositeSlots]
			if counterpart and not counterpart.player then
				self:_maybeSyncCounterpart(slotInfo.side, slotInfo.index, "player-removed")
			end
		end
	end

	self._playerSlotLookup[player] = nil
	self._readyPlayers[player] = nil
	self:_publishLobbyScoreboard()

	self:_refreshSideLocks(slotInfo.side)
	if oppositeSide then
		self:_refreshSideLocks(oppositeSide)
	end
	self:_updateReadyWarnings()
	self:_evaluateLobbyCountdown()

	if self._callbacks.onPlayerRemoved then
		self._callbacks.onPlayerRemoved(player, slotInfo.side, slotInfo.index, self)
	end
end

function BombLevelController:_clearAllSlots(suppressGui)
	for _, sideSlots in pairs(self._platformSlots) do
		for _, slot in ipairs(sideSlots) do
			self:_releaseSlot(slot, suppressGui)
			self:_restorePlatformAppearance(slot)
			clearDictionary(slot.touchCounts)
			self:_hidePlatform(slot, false)
		end
	end
	self._playerSlotLookup = {}
	self._readyPlayers = {}
	for player in pairs(self._readyWarningTasks) do
		self:_cancelReadyWarning(player)
	end
	self:_publishLobbyScoreboard()

	self:_resetLobbyPlatforms()
	self:_refreshSideLocks("Left")
	self:_refreshSideLocks("Right")
	self:_updateReadyWarnings()
	self:_stopLobbyCountdown()
end

function BombLevelController:_isPlayerOnPlatform(player, platform)
	local character = player.Character
	if not character then
		return false
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end

	local rayDistance = self._PLATFORM_RAYCAST_DISTANCE
	if not rayDistance or rayDistance <= 0 then
		rayDistance = (platform.Size.Y / 2) + self._MAX_PLATFORM_HEIGHT_OFFSET + 5
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.RespectCanCollide = false

	local origin = root.Position + Vector3.new(0, self._MAX_PLATFORM_HEIGHT_OFFSET, 0)
	local result = Workspace:Raycast(origin, Vector3.new(0, -rayDistance, 0), params)
	if result and result.Instance then
		local hit = result.Instance
		if hit == platform or hit:IsDescendantOf(platform) then
			return true
		end
	end

	-- Fallback bounding check with tighter tolerances
	local pos = root.Position
	local platformPos = platform.Position
	local platformSize = platform.Size
	local horizontalTolerance = math.max(self._PLATFORM_HORIZONTAL_TOLERANCE or 0, 0)

	local withinX = math.abs(pos.X - platformPos.X) <= (platformSize.X / 2) + horizontalTolerance
	local withinZ = math.abs(pos.Z - platformPos.Z) <= (platformSize.Z / 2) + horizontalTolerance
	if not (withinX and withinZ) then
		return false
	end

	local platformTopY = platformPos.Y + platformSize.Y / 2
	local heightDiff = math.abs(pos.Y - platformTopY)
	return heightDiff <= self._MAX_PLATFORM_HEIGHT_OFFSET
end

function BombLevelController:_incrementTouchCount(slot, player)
	slot.touchCounts[player] = (slot.touchCounts[player] or 0) + 1
	return slot.touchCounts[player]
end

function BombLevelController:_decrementTouchCount(slot, player)
	local current = slot.touchCounts[player]
	if not current then
		return 0
	end

	current -= 1
	if current <= 0 then
		slot.touchCounts[player] = nil
		return 0
	end

	slot.touchCounts[player] = current
	return current
end

function BombLevelController:_refreshSideLocks(side, bypassOccupancy)
	local sideSlots = self._platformSlots[side]
	if not sideSlots then
		return
	end

	local anyOccupied = false
	for _, slot in ipairs(sideSlots) do
		if slot.player then
			anyOccupied = true
			break
		end
	end

	for _, slot in ipairs(sideSlots) do
		if slot.player then
			if not slot.visible then
				self:_showPlatform(slot, true)
			end
			self:_applySlotVisualState(slot)
			continue
		end

		if slot.visible then
			self:_unlockPlatform(slot)
			if not (bypassOccupancy or anyOccupied) then
				self:_applyDefaultAppearance(slot)
			end
		else
			self:_lockPlatform(slot)
			local hasActiveTween = slot.activeTweens and next(slot.activeTweens) ~= nil
			if not hasActiveTween then
				self:_hidePlatform(slot, false)
			end
		end
	end
end

function BombLevelController:_sendHideUI(player)
	if not player then
		return
	end
	self._remotes.PlatformPrompt:FireClient(player, {
		action = "hide",
		levelId = self._levelId,
	})
	self._remotes.ReadyStatus:FireClient(player, false)
	self._remotes.ReadyWarning:FireClient(player, { active = false, timeLeft = 0 })
	self._remotes.ReadyToggle:FireClient(player, { enabled = false, reason = "release" })
end

function BombLevelController:_sendClearScoreboard(player)
	if not player or not player.Parent then
		return
	end

	local payload = {
		active = false,
		showReadiness = true,
		showPoints = true,
		scores = {
			Left = 0,
			Right = 0,
		},
		team1 = {},
		team2 = {},
	}

	local metadata = self._manager.getMetadata and self._manager:getMetadata()
	if metadata then
		payload.levelId = metadata.levelId
		payload.levelName = metadata.levelName
	end

	self._remotes.ScoreboardUpdate:FireClient(player, payload)
end

function BombLevelController:_assignPlayerToSlot(player, slot)
	if slot.player or self._matchActive then
		return
	end

	if not self:_canAssignToSlot(player, slot) then
		return
	end

	if self._playerSlotLookup[player] then
		self:_removePlayerFromSlot(player)
	end

	slot.player = player
	self._playerSlotLookup[player] = {
		side = slot.side,
		index = slot.index,
		platform = slot.platform,
	}
	self._readyPlayers[player] = false
	self:_applySlotVisualState(slot)

	local function prompt()
		if player.Parent then
			self._remotes.PlatformPrompt:FireClient(player, {
				action = "show",
				side = slot.side,
				platform = slot.index,
				levelId = self._levelId,
			})
			self._remotes.ReadyStatus:FireClient(player, false)
			self._remotes.ReadyWarning:FireClient(player, { active = false, timeLeft = 0 })
			self._remotes.ReadyToggle:FireClient(player, { enabled = true, reason = "enter" })
		end
	end
	-- fire immediately and once again shortly after to cope with replication delays
	prompt()
	task.delay(0.2, prompt)
	task.delay(0.4, prompt)

	self:_logPlatform("assigned-player", slot, { player = player.Name })

	self:_publishLobbyScoreboard()

	self:_refreshSideLocks(slot.side)
	local oppositeSide = getOppositeSide(slot.side)
	if oppositeSide then
		self:_refreshSideLocks(oppositeSide)
	end
	self:_unlockNextSlot(slot.side, slot.index, "player-assigned")
	self:_updateReadyWarnings()
	self:_evaluateLobbyCountdown()

	if self._callbacks.onPlayerAssigned then
		self._callbacks.onPlayerAssigned(player, slot.side, slot.index, self)
	end
end

function BombLevelController:_canAssignToSlot(player, slot)
	if not slot or slot.locked or slot.player then
		return false
	end
	return true
end

function BombLevelController:_handleTouch(part, slot)
	local character = part.Parent
	if not character then
		return
	end
	local player = Players:GetPlayerFromCharacter(character)
	if not player or not player.Parent then
		return
	end

	if not self:_isPlayerOnPlatform(player, slot.platform) then
		return
	end

	self:_incrementTouchCount(slot, player)

	self:_logPlatform("touch-began", slot, { player = player.Name, count = slot.touchCounts[player] })

	self:_assignPlayerToSlot(player, slot)
end

function BombLevelController:_handleTouchEnded(part, slot)
	local character = part.Parent
	if not character then
		return
	end
	local player = Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end

	local remaining = self:_decrementTouchCount(slot, player)
	if remaining > 0 then
		return
	end

	self:_logPlatform("touch-ended", slot, {
		player = player.Name,
		remaining = remaining,
		stillOnPlatform = tostring(self:_isPlayerOnPlatform(player, slot.platform)),
	})

	if self:_isPlayerOnPlatform(player, slot.platform) then
		return
	end

	if self._matchActive then
		return
	end

	local slotInfo = self._playerSlotLookup[player]
	if not slotInfo then
		return
	end

	local trackedSlot = self._platformSlots[slotInfo.side]
	if not trackedSlot then
		return
	end
	trackedSlot = trackedSlot[slotInfo.index]
	if trackedSlot ~= slot then
		return
	end

	self:_removePlayerFromSlot(player)
end

function BombLevelController:_maybeSyncCounterpart(sourceSide, targetIndex, reason)
	local oppositeSide = getOppositeSide(sourceSide)
	if not oppositeSide then
		return
	end

	local oppositeSlots = self._platformSlots[oppositeSide]
	if not oppositeSlots then
		return
	end

	local counterpart = oppositeSlots[targetIndex]
	if not counterpart then
		return
	end

	local sourceSlots = self._platformSlots[sourceSide]

	if reason == "player-assigned" then
		-- Only mirror when the counterpart already has an occupant.
		if counterpart.player then
			self:_unlockPlatform(counterpart)
			self:_showPlatform(counterpart, true)
			self:_logPlatform("sync-counterpart-occupied", counterpart, {
				reason = reason,
				sourceSide = sourceSide,
				targetIndex = targetIndex,
			})
		end
		return
	end

	if reason == "player-removed" then
		if sourceSide ~= oppositeSide and sourceSlots and targetIndex > 1 then
			local previous = sourceSlots[targetIndex - 1]
			if previous and previous.player then
				self:_logPlatform("skip-hide-counterpart", counterpart, {
					reason = reason,
					sourceSide = sourceSide,
					targetIndex = targetIndex,
					prevOccupied = previous.player.Name,
				})
				return
			end
		end

		clearDictionary(counterpart.touchCounts)
		if shouldKeepSlotVisible(counterpart, self._matchActive) then
			self:_unlockPlatform(counterpart)
			self:_showPlatform(counterpart, false)
		else
			self:_hidePlatform(counterpart, true)
		end
		self:_logPlatform("sync-counterpart-after-removal", counterpart, {
			reason = reason,
			sourceSide = sourceSide,
			targetIndex = targetIndex,
		})
	end
end

function BombLevelController:_unlockNextSlot(side, index, reason)
	local sideSlots = self._platformSlots[side]
	if not sideSlots then
		return
	end

	local nextSlot = getNextSlot(sideSlots, index)
	if not nextSlot then
		self:_logPlatform("no-next-slot", nil, { side = side, index = index, reason = reason })
		return
	end

	self:_unlockPlatform(nextSlot)
	self:_showPlatform(nextSlot, true)
	local primaryState = nextSlot.originalAppearance and nextSlot.originalAppearance[1]
	local debugInfo = {
		side = side,
		index = index,
		reason = reason,
		part = nextSlot.platform and nextSlot.platform:GetFullName() or "nil",
		size = nextSlot.platform and tostring(nextSlot.platform.Size) or "nil",
		transparency = nextSlot.platform and tostring(nextSlot.platform.Transparency) or "nil",
		canCollide = nextSlot.platform and tostring(nextSlot.platform.CanCollide) or "nil",
		originalTransparency = primaryState and tostring(primaryState.transparency) or "nil",
		originalSize = primaryState and tostring(primaryState.size) or "nil",
	}
	self:_logPlatform("unlock-next-slot", nextSlot, debugInfo)
	task.defer(function()
		if nextSlot.platform and nextSlot.platform.Parent then
			self:_logPlatform("post-unlock-state", nextSlot, {
				size = tostring(nextSlot.platform.Size),
				transparency = tostring(nextSlot.platform.Transparency),
				canCollide = tostring(nextSlot.platform.CanCollide),
				anchored = tostring(nextSlot.platform.Anchored),
			})
		else
			self:_logPlatform("post-unlock-missing", nextSlot, { part = "destroyed" })
		end
	end)

	self:_maybeSyncCounterpart(side, nextSlot.index, reason)
end

function BombLevelController:_logPlatform(action, slot, extra)
	if not self._platformDebugLogging then
		return
	end

	local slotDescription = describeSlot(slot)
	local message = string.format("[BombTag][Server][Platforms] %s: %s%s", action, slotDescription, formatExtra(extra))
	print(message)
end

function BombLevelController:_gatherReadyEntries()
	local readyEntries = {}
	local leftReady, rightReady = 0, 0

	for player, slotInfo in pairs(self._playerSlotLookup) do
		if self._readyPlayers[player] and player.Parent then
			local slot = self._platformSlots[slotInfo.side] and self._platformSlots[slotInfo.side][slotInfo.index]
			local lobbyCFrame = nil
			if slot and slot.platform then
				lobbyCFrame = computeSurfaceCFrameForObject(
					slot.platform,
					self._config.SpawnSurfaceOffset or 0.25,
					self._config
				)
				if lobbyCFrame and self._config.RespawnExtraHeight then
					lobbyCFrame = lobbyCFrame * CFrame.new(0, self._config.RespawnExtraHeight, 0)
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

function BombLevelController:_attachMatchSignals(player)
	local function bind(character)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end

		if self._matchConnections[player] and self._matchConnections[player].deathConn then
			self._matchConnections[player].deathConn:Disconnect()
		end

		self._matchConnections[player] = self._matchConnections[player] or {}
		self._matchConnections[player].deathConn = humanoid.Died:Connect(function()
			self._manager:handlePlayerDeath(player)
		end)
	end

	if self._matchConnections[player] and self._matchConnections[player].charConn then
		self._matchConnections[player].charConn:Disconnect()
	end

	self._matchConnections[player] = self._matchConnections[player] or {}
	self._matchConnections[player].charConn = player.CharacterAdded:Connect(bind)

	if player.Character then
		bind(player.Character)
	end
end

function BombLevelController:_clearMatchSignals(player)
	local record = self._matchConnections[player]
	if record then
		if record.deathConn then
			record.deathConn:Disconnect()
		end
		if record.charConn then
			record.charConn:Disconnect()
		end
	end
	self._matchConnections[player] = nil
end

function BombLevelController:_awardCoinsToPlayers(players, coins)
	if coins <= 0 or not players then
		return
	end

	local currencyUpdatedRemote = self._currencyUpdatedRemote

	for _, player in ipairs(players) do
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

function BombLevelController:_awardPendingWinnerReward()
	local reward = self._pendingWinnerReward
	if not reward then
		return
	end

	self._pendingWinnerReward = nil
	self:_awardCoinsToPlayers(reward.players, reward.coins or 0)
end

function BombLevelController:_handlePlayersTeleported(_players)
	if self._matchActive then
		return
	end

	if not self._pendingWinnerReward then
		return
	end

	self:_awardPendingWinnerReward()
	self:_resetLobbyPlatforms()
	self:_refreshSideLocks("Left")
	self:_refreshSideLocks("Right")
end

function BombLevelController:_handleMatchWinners(context)
	if not context then
		return
	end

	local winners = context.players
	local coins = tonumber(context.coins) or 0
	if typeof(winners) ~= "table" or coins <= 0 then
		self._pendingWinnerReward = nil
		return
	end

	local normalized = {}
	for _, player in ipairs(winners) do
		if player then
			table.insert(normalized, player)
		end
	end

	if #normalized == 0 then
		self._pendingWinnerReward = nil
		return
	end

	self._pendingWinnerReward = {
		players = normalized,
		coins = coins,
	}
end

function BombLevelController:_handleMatchStarted(context)
	self:_stopLobbyCountdown()

	self._matchActive = true
	self._matchParticipants = {}

	for _, entry in ipairs(context.players) do
		self._matchParticipants[entry.player] = true
		self:_attachMatchSignals(entry.player)
	end

	self:_clearAllSlots()

	if self._callbacks.onMatchStarted then
		self._callbacks.onMatchStarted(self, context)
	end
	if self._callbacks.onMatchStateChanged then
		self._callbacks.onMatchStateChanged(self, true)
	end
end

function BombLevelController:_handleMatchEnded()
	self:_stopLobbyCountdown()

	self._matchActive = false
	self._matchParticipants = {}

	for player in pairs(self._matchConnections) do
		self:_clearMatchSignals(player)
	end

	self:_clearAllSlots()

	if self._callbacks.onMatchEnded then
		self._callbacks.onMatchEnded(self)
	end
	if self._callbacks.onMatchStateChanged then
		self._callbacks.onMatchStateChanged(self, false)
	end
end

function BombLevelController:_toggleReady(player)
	if self._matchActive then
		return
	end

	if not self._playerSlotLookup[player] then
		return
	end

	self._readyPlayers[player] = not self._readyPlayers[player]
	local slotInfo = self._playerSlotLookup[player]
	if slotInfo then
		local slot = self._platformSlots[slotInfo.side] and self._platformSlots[slotInfo.side][slotInfo.index]
		if slot then
			self:_applySlotVisualState(slot)
		end
		self:_refreshSideLocks(slotInfo.side)
	end
	self._remotes.ReadyStatus:FireClient(player, self._readyPlayers[player])
	self:_publishLobbyScoreboard()
	self:_updateReadyWarnings()
	self:_evaluateLobbyCountdown()
end

function BombLevelController:_onHeartbeat()
	if self._matchActive then
		return
	end

	for player, slotInfo in pairs(self._playerSlotLookup) do
		if not player.Parent or not self:_isPlayerOnPlatform(player, slotInfo.platform) then
			self:_removePlayerFromSlot(player)
		end
	end
end

return BombLevelController

