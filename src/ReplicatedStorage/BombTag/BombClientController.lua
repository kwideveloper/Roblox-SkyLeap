local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local BombClientController = {}
BombClientController.__index = BombClientController

type RemoteMap = {
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
}

type StateValues = {
	isActive: BoolValue?,
	bombHolder: StringValue?,
}

local READY_COLOR = Color3.fromRGB(0, 204, 102)
local WAITING_COLOR = Color3.fromRGB(0, 170, 255)
local LOCKED_COLOR = Color3.fromRGB(255, 170, 0)
local TEAM_HIGHLIGHT_COLOR = Color3.fromRGB(50, 255, 120)

local function getThumbnail(userId: number?)
	local id = tonumber(userId) or 0
	if id <= 0 then
		local localPlayer = Players.LocalPlayer
		if localPlayer then
			id = localPlayer.UserId
		end
	end

	return string.format(
		"https://www.roblox.com/headshot-thumbnail/image?userId=%d&width=150&height=150&format=png",
		id
	)
end

local function cloneTemplate(
	frame: Frame?,
	template: Frame?,
	playersData: { [number]: { UserId: number?, Name: string? } }?
)
	if not frame or not template then
		return
	end

	for _, child in ipairs(frame:GetChildren()) do
		if child ~= template and child:IsA("Frame") then
			child:Destroy()
		end
	end

	for index, entry in ipairs(playersData or {}) do
		local clone = template:Clone()
		clone.Visible = true
		clone.Name = entry.Name or clone.Name
		clone.LayoutOrder = index

		local imageLabel = clone:FindFirstChildWhichIsA("ImageLabel", true)
		if imageLabel then
			imageLabel.Image = getThumbnail(entry.UserId)
			imageLabel.ImageTransparency = 0
		end

		local nameLabel = clone:FindFirstChildWhichIsA("TextLabel", true)
		if nameLabel and entry.Name then
			nameLabel.Text = entry.Name
		end

		clone.Parent = frame
	end

	template.Visible = false
end

local function createHighlight(character: Model)
	if not character then
		return
	end

	local existing = character:FindFirstChild("BombHighlight")
	if existing then
		existing:Destroy()
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "BombHighlight"
	highlight.FillColor = Color3.fromRGB(255, 0, 0)
	highlight.FillTransparency = 0.9
	highlight.OutlineColor = Color3.fromRGB(255, 0, 0)
	highlight.OutlineTransparency = 0
	highlight.Adornee = character
	highlight.Parent = character
end

local function removeHighlight(character: Model?)
	if not character then
		return
	end
	local highlight = character:FindFirstChild("BombHighlight")
	if highlight then
		highlight:Destroy()
	end
end

local function applyTeamHighlight(character: Model, color: Color3)
	if not character then
		return
	end
	local highlight = character:FindFirstChild("TeamHighlight")
	if not highlight then
		highlight = Instance.new("Highlight")
		highlight.Name = "TeamHighlight"
		highlight.FillTransparency = 0.8
		highlight.OutlineTransparency = 0
		highlight.Parent = character
	end
	highlight.FillColor = color
	highlight.OutlineColor = color
	highlight.Adornee = character
end

local function removeTeamHighlight(character: Model?)
	if not character then
		return
	end
	local highlight = character:FindFirstChild("TeamHighlight")
	if highlight then
		highlight:Destroy()
	end
end

local function createBombIcon(targetPlayer: Player, countdown: number?)
	local character = targetPlayer.Character
	if not character then
		return
	end

	local head = character:FindFirstChild("Head")
	if not head then
		return
	end

	local existing = head:FindFirstChild("BombIcon")
	if existing then
		existing:Destroy()
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "BombIcon"
	billboard.Size = UDim2.new(0, 64, 0, 64)
	billboard.Adornee = head
	billboard.AlwaysOnTop = true
	billboard.ExtentsOffsetWorldSpace = Vector3.new(0, 2.8, 0)
	billboard.Parent = head

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.new(0.6, 0, 0.6, 0)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.new(0.5, 0, 0.6, 0)
	icon.Image = "rbxassetid://489938484"
	icon.Parent = billboard

	local timerLabel = Instance.new("TextLabel")
	timerLabel.Name = "TimerLabel"
	timerLabel.BackgroundTransparency = 1
	timerLabel.Size = UDim2.new(1, 0, 0.3, 0)
	timerLabel.Position = UDim2.new(0, 0, 0.05, 0)
	timerLabel.Font = Enum.Font.GothamBold
	timerLabel.TextScaled = true
	timerLabel.TextColor3 = Color3.new(1, 1, 1)
	timerLabel.TextStrokeTransparency = 0.5
	timerLabel.Text = countdown and tostring(countdown) or ""
	timerLabel.Parent = billboard
end

function BombClientController.new(args: {
	player: Player,
	playerGui: PlayerGui,
	config: table,
	remotes: RemoteMap,
	stateValues: StateValues?,
})
	local self = setmetatable({}, BombClientController)

	self.player = args.player
	self.playerGui = args.playerGui
	self.config = args.config or {}
	self.remotes = args.remotes or {} :: RemoteMap
	self.stateValues = args.stateValues or {}
	self._activeLevelId = nil
	self.connections = {}
	self.bombIconConnections = {}
	self.bombHolder = nil
	self.pointsLockedVisible = false
	self._readyUiActive = false
	self._promptVisible = false
	self._readyState = false
	self._playerSides = {}
	self._localSide = nil
	self.teamHighlightConnections = {}
	self.teamHighlightTargets = {}
	self._winnerClones = {}
	self._winnerHideTask = nil

	self.ui = {
		root = nil :: Frame?,
		countdown = nil :: Frame?,
		counterLabel = nil :: TextLabel?,
		startingLabel = nil :: TextLabel?,
		moveMessageLabel = nil :: TextLabel?,
		readyButton = nil :: TextButton?,
		pointsContainer = nil :: Frame?,
		pointsRed = nil :: TextLabel?,
		pointsBlue = nil :: TextLabel?,
		winnersFrame = nil :: Frame?,
		winnersText = nil :: TextLabel?,
		winnersImages = nil :: Frame?,
		winnersTemplate = nil :: ImageLabel?,
		teamFrames = {
			Left = nil :: Frame?,
			Right = nil :: Frame?,
		},
		teamTemplates = {
			Left = nil :: Frame?,
			Right = nil :: Frame?,
		},
	}

	self:_locateUi(args.playerGui)
	self:_hookRemotes()
	self:_updateStaminaUI()

	return self
end

local function waitForChildRecursive(parent: Instance, childName: string, yieldDuration: number?)
	local child = parent:FindFirstChild(childName)
	local elapsed = 0
	while not child do
		local timeout = yieldDuration or 1
		child = parent:WaitForChild(childName, timeout)
		if child then
			break
		end
		elapsed += timeout
		if elapsed >= 30 then
			warn(string.format("[BombTag][Client] Still waiting for %s after %.1fs.", childName, elapsed))
		end
	end
	return child
end

function BombClientController:_locateUi(playerGui: PlayerGui)
	if not playerGui then
		warn("[BombTag][Client] playerGui missing.")
		return
	end

	local bombGui = waitForChildRecursive(playerGui, "BombGui", 2)
	if not bombGui then
		warn("[BombTag][Client] BombGui missing in PlayerGui.")
		return
	end

	if bombGui:IsA("ScreenGui") then
		bombGui.Enabled = true
	end

	self.ui.root = waitForChildRecursive(bombGui, "Root", 2)
	if not self.ui.root then
		warn("[BombTag][Client] Root frame missing inside BombGui.")
		return
	end

	self.ui.countdown = self.ui.root:FindFirstChild("Countdown") or waitForChildRecursive(self.ui.root, "Countdown", 2)
	if self.ui.countdown then
		self.ui.counterLabel = self.ui.countdown:FindFirstChild("Counter")
			or waitForChildRecursive(self.ui.countdown, "Counter", 2) :: TextLabel?
		self.ui.startingLabel = self.ui.countdown:FindFirstChild("Starting")
			or waitForChildRecursive(self.ui.countdown, "Starting", 2) :: TextLabel?

		self.ui.readyMessageLabel = self.ui.countdown:FindFirstChild("ReadyMessage")
		if not self.ui.readyMessageLabel then
			self.ui.readyMessageLabel = self.ui.countdown:FindFirstChild("MoveMessage")
		end
		if not self.ui.readyMessageLabel then
			self.ui.readyMessageLabel = waitForChildRecursive(self.ui.countdown, "ReadyMessage", 1)
		end
		if not self.ui.readyMessageLabel then
			self.ui.readyMessageLabel = waitForChildRecursive(self.ui.countdown, "MoveMessage", 1)
		end
		if not self.ui.readyMessageLabel then
			warn("[BombTag][Client] ReadyMessage / MoveMessage label not found inside Countdown.")
		end
	end

	self.ui.readyButton = self.ui.root:FindFirstChild("TextButton")
		or waitForChildRecursive(self.ui.root, "TextButton", 2) :: TextButton?
	if self.ui.readyButton and self.remotes.ReadyToggle then
		self.ui.readyButton.MouseButton1Click:Connect(function()
			if not self.ui.readyButton.Active then
				return
			end

			local nextState = not self._readyState
			self:_setReadyButtonState(nextState)
			self.remotes.ReadyToggle:FireServer()
		end)
	end

	self.ui.pointsContainer = self.ui.root:FindFirstChild("Points")
		or waitForChildRecursive(self.ui.root, "Points", 2) :: Frame?
	if self.ui.pointsContainer then
		self.ui.pointsRed = self.ui.pointsContainer:FindFirstChild("Red", true)
		self.ui.pointsBlue = self.ui.pointsContainer:FindFirstChild("Blue", true)

		self.ui.teamFrames.Left = self.ui.pointsContainer:FindFirstChild("Team1", true)
		self.ui.teamFrames.Right = self.ui.pointsContainer:FindFirstChild("Team2", true)

		if self.ui.teamFrames.Left then
			self.ui.teamTemplates.Left = self.ui.teamFrames.Left:FindFirstChild("Player")
			if self.ui.teamTemplates.Left then
				self.ui.teamTemplates.Left.Visible = false
			end
		end

		if self.ui.teamFrames.Right then
			self.ui.teamTemplates.Right = self.ui.teamFrames.Right:FindFirstChild("Player")
			if self.ui.teamTemplates.Right then
				self.ui.teamTemplates.Right.Visible = false
			end
		end
	end

	if self.ui.root then
		local winnersFrame = self.ui.root:FindFirstChild("Winners")
		if winnersFrame and winnersFrame:IsA("Frame") then
			self.ui.winnersFrame = winnersFrame
			self.ui.winnersText = winnersFrame:FindFirstChildWhichIsA("TextLabel")
			self.ui.winnersImages = winnersFrame:FindFirstChild("Images")
			if self.ui.winnersImages then
				local template = self.ui.winnersImages:FindFirstChild("Player")
				if template and template:IsA("ImageLabel") then
					self.ui.winnersTemplate = template
					template.Visible = false
				end
			end
			winnersFrame.Visible = false
		end
	end

	self:_setCountdownVisible(false)
	self:_setReadyButtonVisible(false)
	if self.ui.root then
		self.ui.root.Visible = false
	end
	if self.ui.pointsContainer then
		self.ui.pointsContainer.Visible = false
	end
	if self.ui.readyMessageLabel then
		self.ui.readyMessageLabel.Visible = false
	end
end

function BombClientController:_extractLevelId(metadata): string?
	if metadata == nil then
		return nil
	end
	local metadataType = typeof(metadata)
	if metadataType == "string" then
		return metadata
	elseif metadataType == "table" then
		return metadata.levelId or metadata.LevelId or metadata.id or metadata.levelID
	end
	return nil
end

function BombClientController:_shouldProcessEvent(metadata): boolean
	local levelId = self:_extractLevelId(metadata)
	if not levelId then
		return true
	end
	if self._activeLevelId == nil then
		self._activeLevelId = levelId
		return true
	end
	return self._activeLevelId == levelId
end

function BombClientController:_clearLevelContext()
	self._activeLevelId = nil
end

function BombClientController:_hookRemotes()
	local function connect(remoteName, handler)
		local remote = self.remotes[remoteName]
		if not remote then
			warn(string.format("[BombTag][Client] Remote '%s' missing.", tostring(remoteName)))
			return
		end
		table.insert(self.connections, remote.OnClientEvent:Connect(handler))
	end

	connect("GameStart", function(payload)
		if self:_shouldProcessEvent(payload) then
			self:_onGameStart(payload)
		end
	end)
	connect("CountdownUpdate", function(value, phase, metadata)
		if self:_shouldProcessEvent(metadata) then
			self:_onCountdownUpdate(value, phase)
		end
	end)
	connect("ScoreboardUpdate", function(data)
		if self:_shouldProcessEvent(data) then
			self:_onScoreboardUpdate(data)
		end
	end)
	connect("PlatformPrompt", function(data)
		if self:_shouldProcessEvent(data) then
			self:_onPlatformPrompt(data)
		end
	end)
	connect("ReadyStatus", function(isReady)
		self:_onReadyStatus(isReady)
	end)
	connect("ReadyWarning", function(data)
		self:_onReadyWarning(data)
	end)
	connect("BombAssigned", function(playerName, timerValue, metadata)
		if self:_shouldProcessEvent(metadata) then
			self:_onBombAssigned(playerName, timerValue)
		end
	end)
	connect("BombPassed", function(fromPlayer, toPlayer, timerValue, metadata)
		if self:_shouldProcessEvent(metadata) then
			self:_onBombPassed(fromPlayer, toPlayer, timerValue)
		end
	end)
	connect("BombTimerUpdate", function(timerValue, metadata)
		if self:_shouldProcessEvent(metadata) then
			self:_onBombTimerUpdate(timerValue)
		end
	end)
	connect("PlayerEliminated", function(playerName, metadata)
		if self:_shouldProcessEvent(metadata) then
			self:_onPlayerEliminated(playerName)
		end
	end)
	connect("GameEnd", function(payload)
		if self:_shouldProcessEvent(payload) then
			self:_onGameEnd(payload)
		else
			self:_clearLevelContext()
		end
	end)
	connect("ReadyToggle", function(data)
		self:_onReadyToggle(data)
	end)

	local isActiveValue = self.stateValues.isActive
	if isActiveValue then
		table.insert(
			self.connections,
			isActiveValue:GetPropertyChangedSignal("Value"):Connect(function()
				self:_updateStaminaUI()
			end)
		)
	end
end

function BombClientController:_updateStaminaUI()
	local isActive = false
	if self.stateValues.isActive then
		isActive = self.stateValues.isActive.Value
	end

	local staminaGui = self.player.PlayerGui:FindFirstChild("Stamina")
	if not staminaGui then
		return
	end

	local container = staminaGui:FindFirstChild("Container")
	if not container then
		return
	end

	local staminaBg = container:FindFirstChild("StaminaBg")
	if staminaBg then
		staminaBg.Visible = not isActive
	end

	local staminaLabel = container:FindFirstChild("StaminaLabel")
	if staminaLabel then
		staminaLabel.Visible = not isActive
	end
end

function BombClientController:_setCountdownVisible(visible: boolean)
	if not self.ui.countdown then
		return
	end
	for _, child in ipairs(self.ui.countdown:GetChildren()) do
		if child:IsA("TextLabel") then
			child.Visible = visible
		end
	end
	self:_refreshRootVisibility()
end

function BombClientController:_setReadyButtonVisible(visible: boolean)
	if not self.ui.readyButton then
		warn(string.format("[BombTag][Client] Ready button missing when setting visible=%s", tostring(visible)))
		return
	end

	self.ui.readyButton.Visible = visible
	print(string.format("[BombTag][Client] ReadyButton.Visible -> %s", tostring(visible)))

	if not visible then
		self:_setReadyButtonState(false)
		self.ui.readyButton.Active = false
	end
	self:_refreshRootVisibility()
end

function BombClientController:_refreshRootVisibility()
	if not self.ui.root then
		return
	end

	local show = false
	if self.ui.readyButton and self.ui.readyButton.Visible then
		show = true
	end

	if not show and self.ui.countdown then
		for _, child in ipairs(self.ui.countdown:GetChildren()) do
			if child:IsA("TextLabel") and child.Visible then
				show = true
				break
			end
		end
	end

	if not show and self.ui.pointsContainer and self.ui.pointsContainer.Visible then
		show = true
	end

	if not show and self.ui.winnersFrame and self.ui.winnersFrame.Visible then
		show = true
	end

	if not show and self.ui.moveMessageLabel and self.ui.moveMessageLabel.Visible then
		show = true
	end

	self.ui.root.Visible = show
end

function BombClientController:_setTeamHighlights(
	team1: { { UserId: number?, Name: string? } },
	team2: { { UserId: number?, Name: string? } }
)
	local localId = self.player.UserId
	local newSides: { [number]: string } = {}
	local localSide = nil

	for _, entry in ipairs(team1 or {}) do
		if entry.UserId then
			newSides[entry.UserId] = "Left"
			if entry.UserId == localId then
				localSide = "Left"
			end
		end
	end

	for _, entry in ipairs(team2 or {}) do
		if entry.UserId then
			newSides[entry.UserId] = "Right"
			if entry.UserId == localId then
				localSide = "Right"
			end
		end
	end

	self._playerSides = newSides
	self._localSide = localSide

	if not localSide then
		self:_clearTeamHighlights()
		return
	end

	local keep: { [Player]: boolean } = {}
	for userId, side in pairs(self._playerSides) do
		if side == localSide and userId ~= localId then
			local teammate = Players:GetPlayerByUserId(userId)
			if teammate and teammate.Parent then
				keep[teammate] = true
				self:_ensureTeamHighlightForPlayer(teammate, TEAM_HIGHLIGHT_COLOR)
			end
		end
	end

	for player in pairs(self.teamHighlightConnections) do
		if not keep[player] then
			self:_removeTeamHighlightForPlayer(player)
		end
	end
end

function BombClientController:_setReadyButtonState(isReady: boolean)
	if not self.ui.readyButton then
		return
	end

	self._readyState = isReady and true or false
	self.ui.readyButton.Active = true
	self.ui.readyButton.AutoButtonColor = true

	if isReady then
		self.ui.readyButton.Text = "Not Ready"
		self.ui.readyButton.BackgroundColor3 = READY_COLOR
	else
		self.ui.readyButton.Text = "Ready"
		self.ui.readyButton.BackgroundColor3 = WAITING_COLOR
	end
end

function BombClientController:_setBombGuiEnabled(enabled: boolean)
	local playerGui = self.playerGui
	if not playerGui then
		return
	end
	local bombGui = playerGui:FindFirstChild("BombGui")
	if bombGui and bombGui:IsA("ScreenGui") then
		bombGui.Enabled = enabled
	end
end

function BombClientController:_onReadyToggle(payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	local enabled = payload.enabled
	if enabled == nil then
		return
	end
	local reason = payload.reason
	local shouldEnable = enabled and true or false
	self:_setBombGuiEnabled(shouldEnable)
	if shouldEnable then
		if self._promptVisible then
			self:_setReadyButtonVisible(true)
		end
	else
		self:_setReadyButtonVisible(false)
		self:_clearTeamHighlights()
	end
end

function BombClientController:_lockReadyButton(message: string?)
	if not self.ui.readyButton then
		return
	end
	self.ui.readyButton.Active = false
	self.ui.readyButton.AutoButtonColor = false
	self.ui.readyButton.BackgroundColor3 = LOCKED_COLOR
	self.ui.readyButton.Text = message or "WAIT..."
end

function BombClientController:_onGameStart(payload)
	local kind = nil
	local countdown = nil

	if typeof(payload) == "table" then
		kind = payload.kind
		countdown = payload.countdown
	else
		countdown = payload
	end

	if self.stateValues.isActive then
		self.stateValues.isActive.Value = true
	end
	self:_updateStaminaUI()

	if self.ui.pointsContainer then
		self.pointsLockedVisible = true
		self.ui.pointsContainer.Visible = true
	end

	self:_cancelWinnerHideTask()
	if self.ui.winnersFrame then
		self.ui.winnersFrame.Visible = false
		self:_clearWinnerImages()
	end

	if kind == "waiting" or kind == "prepare" then
		if self.ui.startingLabel then
			if kind == "waiting" then
				self.ui.startingLabel.Text = "Players ready! Teleporting soon..."
			else
				self.ui.startingLabel.Text = "Round starting!"
			end
			self.ui.startingLabel.Visible = true
		end
		if self.ui.counterLabel then
			self.ui.counterLabel.Visible = true
			self.ui.counterLabel.Text = tostring(countdown or 3)
		end
		if self.ui.moveMessageLabel then
			self.ui.moveMessageLabel.Visible = false
		end
	else
		self:_setCountdownVisible(false)
	end

	self:_setReadyButtonVisible(false)
	self:_refreshRootVisibility()
end

function BombClientController:_onCountdownUpdate(value, phase)
	self:_setBombGuiEnabled(true)
	if not self.ui.counterLabel then
		return
	end

	if phase == "lobby" then
		if self.ui.counterLabel then
			self.ui.counterLabel.Visible = false
		end
		if self.ui.startingLabel then
			if typeof(value) == "number" and value >= 0 then
				if value > 0 then
					self.ui.startingLabel.Text = string.format("Starting in %d", value)
				else
					self.ui.startingLabel.Text = "Starting..."
				end
				self.ui.startingLabel.Visible = true
			else
				self.ui.startingLabel.Visible = false
			end
		end
		self:_refreshRootVisibility()
		return
	end

	if value == nil then
		return
	end

	if value >= 0 then
		self.ui.counterLabel.Text = tostring(value)
		self.ui.counterLabel.Visible = true
	else
		self.ui.counterLabel.Visible = false
	end

	if self.ui.startingLabel then
		if phase == "prepare" then
			if value > 0 then
				self.ui.startingLabel.Visible = true
			elseif value == 0 then
				self.ui.startingLabel.Text = "GO!"
				self.ui.startingLabel.Visible = true
			else
				self.ui.startingLabel.Visible = false
			end
		else
			self.ui.startingLabel.Visible = false
		end
	end

	self:_refreshRootVisibility()
end

function BombClientController:_onScoreboardUpdate(data)
	if not self.ui.pointsContainer then
		return
	end

	local scores = data and data.scores or {}
	local leftScore = scores.Left or scores.Team1 or 0
	local rightScore = scores.Right or scores.Team2 or 0
	local team1 = data and data.team1 or {}
	local team2 = data and data.team2 or {}

	if data and data.showPoints ~= nil then
		self.pointsLockedVisible = data.showPoints
	end

	local showPoints = self.pointsLockedVisible or (data and data.active ~= false)
	self.ui.pointsContainer.Visible = showPoints

	if self.ui.pointsRed then
		self.ui.pointsRed.Text = tostring(leftScore)
	end
	if self.ui.pointsBlue then
		self.ui.pointsBlue.Text = tostring(rightScore)
	end

	cloneTemplate(self.ui.teamFrames.Left, self.ui.teamTemplates.Left, team1)
	cloneTemplate(self.ui.teamFrames.Right, self.ui.teamTemplates.Right, team2)

	local localPlayer = self.player
	local userId = localPlayer and localPlayer.UserId or 0
	local inMatch = false

	if userId > 0 then
		for _, info in ipairs(team1) do
			if info.UserId == userId then
				inMatch = true
				break
			end
		end
		if not inMatch then
			for _, info in ipairs(team2) do
				if info.UserId == userId then
					inMatch = true
					break
				end
			end
		end
	end

	self:_refreshRootVisibility()
	if team1 or team2 then
		self:_setTeamHighlights(team1 or {}, team2 or {})
	else
		self:_clearTeamHighlights()
	end

	self:_refreshRootVisibility()
end

function BombClientController:_onPlatformPrompt(payload)
	if typeof(payload) ~= "table" then
		return
	end

	local action = payload.action
	local side = payload.side
	local platform = payload.platform
	local levelId = self:_extractLevelId(payload)
	if levelId then
		self._activeLevelId = levelId
	end

	print(
		string.format(
			"[BombTag][Client] PlatformPrompt action=%s side=%s platform=%s",
			tostring(action),
			tostring(side),
			tostring(platform)
		)
	)

	if action == "show" then
		if self.ui.startingLabel then
			self.ui.startingLabel.Visible = false
		end
		self._promptVisible = true
		self:_setReadyButtonVisible(true)
		self:_setReadyButtonState(self._readyState)
		print("[BombTag][Client] Ready button set visible via PlatformPrompt")
	elseif action == "hide" then
		self._promptVisible = false
		self:_setReadyButtonVisible(false)
		self:_setCountdownVisible(false)
		self:_clearLevelContext()
	elseif action == "lock" then
		self:_lockReadyButton()
	elseif action == "unlock" then
		self._promptVisible = true
		self:_setReadyButtonState(false)
	end

	self:_refreshRootVisibility()
end

function BombClientController:_onReadyStatus(isReady: boolean)
	self:_setReadyButtonState(isReady)
end

function BombClientController:_onReadyWarning(payload)
	if not self.ui.readyMessageLabel then
		return
	end

	if typeof(payload) ~= "table" then
		self.ui.readyMessageLabel.Visible = false
		return
	end

	if payload.active then
		local seconds = math.max(0, tonumber(payload.timeLeft) or 0)
		self.ui.readyMessageLabel.Text =
			string.format("If you don't get ready in %d seconds, you will be teleported to the spawn.", seconds)
		self.ui.readyMessageLabel.Visible = true
	else
		self.ui.readyMessageLabel.Visible = false
	end

	self:_refreshRootVisibility()
end

function BombClientController:_updateBombIconTimer(targetPlayer: Player, timerValue: number)
	local character = targetPlayer.Character
	if not character then
		return
	end
	local head = character:FindFirstChild("Head")
	if not head then
		return
	end
	local billboard = head:FindFirstChild("BombIcon")
	if not billboard then
		return
	end
	local timerLabel = billboard:FindFirstChild("TimerLabel")
	if timerLabel and timerLabel:IsA("TextLabel") then
		timerLabel.Text = tostring(math.max(0, math.floor(timerValue)))
	end
end

function BombClientController:_attachIcon(player: Player, timerValue: number?)
	if self.bombIconConnections[player] then
		self.bombIconConnections[player]:Disconnect()
		self.bombIconConnections[player] = nil
	end

	local function attach()
		if player.Character then
			createBombIcon(player, timerValue or self.config.BombCountdown or 20)
			local isTeammate = false
			local isLocal = player == self.player
			if self._localSide and player.UserId then
				local targetSide = self._playerSides[player.UserId]
				if targetSide and targetSide == self._localSide then
					isTeammate = true
				end
			end

			if isTeammate and not isLocal then
				applyTeamHighlight(player.Character, TEAM_HIGHLIGHT_COLOR)
			elseif not isTeammate then
				createHighlight(player.Character)
			end
			if timerValue then
				self:_updateBombIconTimer(player, timerValue)
			end
		end
	end

	if player.Character then
		attach()
	end

	self.bombIconConnections[player] = player.CharacterAdded:Connect(function()
		task.defer(attach)
	end)
end

function BombClientController:_removeIcon(player: Player?)
	if not player then
		return
	end
	if self.bombIconConnections[player] then
		self.bombIconConnections[player]:Disconnect()
		self.bombIconConnections[player] = nil
	end

	local character = player.Character
	if not character then
		return
	end

	local head = character:FindFirstChild("Head")
	if head then
		local icon = head:FindFirstChild("BombIcon")
		if icon then
			icon:Destroy()
		end
	end

	removeHighlight(character)
end

function BombClientController:_removeTeamHighlightForPlayer(player: Player)
	if self.teamHighlightConnections[player] then
		if self.teamHighlightConnections[player].conn then
			self.teamHighlightConnections[player].conn:Disconnect()
		end
		self.teamHighlightConnections[player] = nil
	end
	self.teamHighlightTargets[player] = nil
	removeTeamHighlight(player.Character)
end

function BombClientController:_clearTeamHighlights()
	for player in pairs(self.teamHighlightConnections) do
		self:_removeTeamHighlightForPlayer(player)
	end
	self._playerSides = {}
	self._localSide = nil
end

function BombClientController:_cancelWinnerHideTask()
	if self._winnerHideTask then
		pcall(task.cancel, self._winnerHideTask)
		self._winnerHideTask = nil
	end
end

function BombClientController:_hideWinnerDisplay()
	if self.ui.winnersFrame then
		self.ui.winnersFrame.Visible = false
	end
	self:_clearWinnerImages()
	if self.ui.moveMessageLabel then
		self.ui.moveMessageLabel.Visible = false
	end
end

function BombClientController:_clearWinnerImages()
	if not self.ui.winnersImages then
		return
	end

	for _, child in ipairs(self.ui.winnersImages:GetChildren()) do
		if child ~= self.ui.winnersTemplate then
			child:Destroy()
		end
	end

	table.clear(self._winnerClones)
end

function BombClientController:_showWinners(
	winners: { { [string]: any } }?,
	winningSide: string?,
	coinsAwarded: number?,
	localIsWinner: boolean?
)
	if not self.ui.winnersFrame then
		return
	end

	self:_cancelWinnerHideTask()
	self.ui.winnersFrame.Visible = true

	local totalWinners = winners and #winners or 0
	local textLabel = self.ui.winnersText
	if textLabel then
		if localIsWinner and (coinsAwarded or 0) > 0 then
			textLabel.Text = string.format("You won! +%d coins", coinsAwarded)
		elseif totalWinners == 1 and winners then
			local info = winners[1]
			local winnerName = info and (info.DisplayName or info.Name) or "Winner"
			if coinsAwarded and coinsAwarded > 0 then
				textLabel.Text = string.format("%s wins! +%d coins", winnerName, coinsAwarded)
			else
				textLabel.Text = string.format("%s wins!", winnerName)
			end
		else
			local message = "Match concluded!"
			if winningSide == "Left" then
				message = coinsAwarded and coinsAwarded > 0 and string.format("Red Team Wins! +%d coins", coinsAwarded)
					or "Red Team Wins!"
			elseif winningSide == "Right" then
				message = coinsAwarded and coinsAwarded > 0 and string.format("Blue Team Wins! +%d coins", coinsAwarded)
					or "Blue Team Wins!"
			elseif totalWinners > 1 then
				message = "Winners!"
			end
			textLabel.Text = message
		end
	end

	if not self.ui.winnersTemplate or not self.ui.winnersImages then
		return
	end

	self:_clearWinnerImages()

	if totalWinners == 0 or not winners then
		return
	end

	for _, info in ipairs(winners) do
		local clone = self.ui.winnersTemplate:Clone()
		clone.Visible = true
		clone.Name = tostring(info.Name or info.UserId or "Winner")
		if typeof(info.UserId) == "number" then
			clone.Image = getThumbnail(info.UserId)
		else
			clone.Image = self.ui.winnersTemplate.Image
		end
		clone.Parent = self.ui.winnersImages
		table.insert(self._winnerClones, clone)
	end

	self._winnerHideTask = task.delay(5, function()
		self._winnerHideTask = nil
		self:_hideWinnerDisplay()
	end)
end

function BombClientController:_ensureTeamHighlightForPlayer(player: Player, color: Color3)
	if not player or not player.Parent then
		return
	end

	local record = self.teamHighlightConnections[player]
	if record and record.color == color then
		-- ensure highlight still exists
		if player.Character then
			applyTeamHighlight(player.Character, color)
		end
		return
	elseif record then
		self:_removeTeamHighlightForPlayer(player)
	end

	local function attach()
		if player.Character then
			applyTeamHighlight(player.Character, color)
		end
	end

	attach()
	local conn = player.CharacterAdded:Connect(function()
		task.defer(attach)
	end)

	self.teamHighlightConnections[player] = { conn = conn, color = color }
	self.teamHighlightTargets[player] = true
end

function BombClientController:_onBombAssigned(playerName: string?, timerValue: number?)
	if self.bombHolder then
		self:_removeIcon(self.bombHolder)
	end

	local target = playerName and Players:FindFirstChild(playerName) or nil
	if target then
		self.bombHolder = target
		self:_attachIcon(target, timerValue)
		if self.stateValues.bombHolder then
			self.stateValues.bombHolder.Value = target.Name
		end

		if self.ui.moveMessageLabel then
			self.ui.moveMessageLabel.Text = string.format("%s holds the bomb!", target.Name)
			self.ui.moveMessageLabel.Visible = true
		end
	else
		self.bombHolder = nil
		if self.stateValues.bombHolder then
			self.stateValues.bombHolder.Value = ""
		end
	end

	self:_refreshRootVisibility()
end

function BombClientController:_onBombPassed(fromPlayer: string?, toPlayer: string?, timerValue: number?)
	if fromPlayer then
		local fromObj = Players:FindFirstChild(fromPlayer)
		if fromObj then
			self:_removeIcon(fromObj)
		end
	end

	if toPlayer then
		local target = Players:FindFirstChild(toPlayer)
		if target then
			self.bombHolder = target
			self:_attachIcon(target, timerValue)
			if self.stateValues.bombHolder then
				self.stateValues.bombHolder.Value = target.Name
			end

			if self.ui.moveMessageLabel then
				self.ui.moveMessageLabel.Text = string.format("Bomb passed to %s!", target.Name)
				self.ui.moveMessageLabel.Visible = true
			end
		end
	end

	self:_refreshRootVisibility()
end

function BombClientController:_onBombTimerUpdate(timerValue: number)
	if self.bombHolder then
		self:_updateBombIconTimer(self.bombHolder, timerValue)
	end

	if self.ui.moveMessageLabel then
		if timerValue >= 0 then
			self.ui.moveMessageLabel.Text =
				string.format("Bomb explodes in %d seconds!", math.max(0, math.floor(timerValue)))
			self.ui.moveMessageLabel.Visible = true
		else
			self.ui.moveMessageLabel.Visible = false
		end
	end

	self:_refreshRootVisibility()
end

function BombClientController:_onPlayerEliminated(playerName: string?)
	if not playerName then
		return
	end

	local player = Players:FindFirstChild(playerName)
	if player then
		self:_removeIcon(player)
		if self.bombHolder == player then
			self.bombHolder = nil
			if self.stateValues.bombHolder then
				self.stateValues.bombHolder.Value = ""
			end
		end
	end
end

function BombClientController:_onGameEnd(payload: any)
	if self.stateValues.isActive then
		self.stateValues.isActive.Value = false
	end
	self:_updateStaminaUI()
	self:_clearLevelContext()

	local winningSide: string? = nil
	local winners = {}
	local coins = 0
	local teamLabel: string? = nil
	local localIsWinner = false
	local localPlayer = self.player

	if typeof(payload) == "table" then
		if payload.teamSide then
			winningSide = payload.teamSide
		end
		if payload.winners then
			winners = payload.winners
			if localPlayer and localPlayer.UserId then
				for _, info in ipairs(winners) do
					if tonumber(info.UserId) == localPlayer.UserId then
						localIsWinner = true
						break
					end
				end
			end
		end
		if payload.coins ~= nil then
			coins = tonumber(payload.coins) or coins
		end
		teamLabel = payload.teamName
	else
		teamLabel = payload
	end
	localIsWinner = localIsWinner or false

	self.pointsLockedVisible = false
	if self.ui.pointsContainer then
		self.ui.pointsContainer.Visible = false
	end
	self:_setReadyButtonVisible(false)
	self:_setCountdownVisible(false)
	self:_clearTeamHighlights()

	if self.ui.moveMessageLabel then
		if teamLabel or winningSide then
			local message: string
			local formattedCoins = (coins > 0 and localIsWinner) and string.format("You earned +%d coins!", coins)
				or nil

			if localIsWinner and formattedCoins then
				message = formattedCoins
			elseif winners and #winners == 1 then
				local info = winners[1]
				local winnerName = info and (info.DisplayName or info.Name) or teamLabel or "Winner"
				if coins > 0 and #winners == 1 then
					message = string.format("%s wins!", winnerName)
				else
					message = string.format("%s wins!", winnerName)
				end
			elseif winningSide == "Left" then
				message = "Red Team Wins!"
			elseif winningSide == "Right" then
				message = "Blue Team Wins!"
			elseif teamLabel then
				message = teamLabel
			else
				message = "Match concluded!"
			end

			self.ui.moveMessageLabel.Text = message
			self.ui.moveMessageLabel.Visible = true
			if formattedCoins and not localIsWinner then
				-- Append coin info for spectators/non-winners
				self.ui.moveMessageLabel.Text = string.format("%s %s", message, formattedCoins)
			end
		else
			self.ui.moveMessageLabel.Visible = false
		end
	end

	if self.ui.winnersFrame then
		self:_showWinners(winners, winningSide, coins, localIsWinner)
	end
	if not self._winnerHideTask then
		self._winnerHideTask = task.delay(5, function()
			self:_hideWinnerDisplay()
		end)
	end

	self:_refreshRootVisibility()
end

function BombClientController.cleanup(self)
	if not self then
		return
	end

	self:_clearLevelContext()

	for _, connection in ipairs(self.connections) do
		connection:Disconnect()
	end
	self.connections = {}

	for player, connection in pairs(self.bombIconConnections) do
		connection:Disconnect()
		self:_removeIcon(player)
	end
	self.bombIconConnections = {}
	self:_clearTeamHighlights()
	if self.ui and self.ui.winnersFrame then
		self:_cancelWinnerHideTask()
		self:_clearWinnerImages()
		self.ui.winnersFrame.Visible = false
	end
end

function BombClientController.init(args)
	return BombClientController.new(args)
end

return BombClientController
