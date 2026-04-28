-- Magazine + reload HUD for the Sniper (client only).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(script.Parent.Config)
local SniperGunStats = require(script.Parent.SniperGunStats)
local SniperLoadoutState = require(script.Parent.SniperLoadoutState)
local ViewModelClient = require(script.Parent.ViewModelClient)

local SniperAmmoHudClient = {}

local started = false
local trackedTool: Tool? = nil
local gui: ScreenGui? = nil
local ammoLabel: TextLabel? = nil
local reloadRing: Frame? = nil
local reloadFillBar: Frame? = nil
local reloadBackdrop: UIStroke? = nil
local connRender: RBXScriptConnection? = nil
local connToolAttr: { RBXScriptConnection }? = nil

local function disconnectToolAttrs()
	if connToolAttr then
		for _, c in ipairs(connToolAttr) do
			pcall(function()
				c:Disconnect()
			end)
		end
		connToolAttr = nil
	end
end

local function setReloadVisual(progress: number, active: boolean)
	if not reloadRing or not reloadFillBar or not reloadBackdrop then
		return
	end
	reloadRing.Visible = active
	if active then
		local p = math.clamp(progress, 0, 1)
		reloadFillBar.Size = UDim2.new(p, 0, 1, 0)
		reloadBackdrop.Transparency = 0.15 + (1 - p) * 0.35
	end
end

local function updateAmmoText(tool: Tool?)
	if not ammoLabel then
		return
	end
	if not tool then
		ammoLabel.Text = "—"
		return
	end
	local cur = tool:GetAttribute(SniperGunStats.ToolAttrAmmo)
	local mag = tool:GetAttribute(SniperGunStats.ToolAttrMagSize)
	if type(cur) ~= "number" or type(mag) ~= "number" then
		ammoLabel.Text = "·"
		return
	end
	ammoLabel.Text = string.format("%d  %d", math.max(0, math.floor(cur)), math.max(1, math.floor(mag)))
end

local function hookTool(tool: Tool?)
	disconnectToolAttrs()
	trackedTool = tool
	if not tool then
		updateAmmoText(nil)
		setReloadVisual(0, false)
		return
	end
	connToolAttr = {}
	table.insert(connToolAttr, tool:GetAttributeChangedSignal(SniperGunStats.ToolAttrAmmo):Connect(function()
		updateAmmoText(tool)
	end))
	table.insert(connToolAttr, tool:GetAttributeChangedSignal(SniperGunStats.ToolAttrMagSize):Connect(function()
		updateAmmoText(tool)
	end))
	table.insert(connToolAttr, tool:GetAttributeChangedSignal(SniperGunStats.ToolAttrReloadEndsAt):Connect(function()
		updateAmmoText(tool)
	end))
	table.insert(connToolAttr, tool.Destroying:Connect(function()
		if trackedTool == tool then
			hookTool(nil)
		end
	end))
	updateAmmoText(tool)
end

local function shouldShowHud(player: Player): boolean
	if Config.SniperAmmoHudEnabled == false then
		return false
	end
	local tool = SniperLoadoutState.getSniperTool()
	if not tool or tool ~= trackedTool then
		return false
	end
	if Config.SniperVirtualInventoryEnabled then
		return SniperLoadoutState.isSniperActive(tool) and SniperLoadoutState.isVirtualSniperHeld()
	else
		return tool.Parent == player.Character
	end
end

local function buildGui(player: Player): ScreenGui
	local pg = player:WaitForChild("PlayerGui", 60) :: PlayerGui
	local screen = Instance.new("ScreenGui")
	screen.Name = "SkyLeapSniperAmmoHud"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = false
	screen.DisplayOrder = Config.SniperAmmoHudDisplayOrder or 78
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Parent = pg

	local root = Instance.new("Frame")
	root.Name = "AmmoRoot"
	root.AnchorPoint = Vector2.new(1, 0.5)
	root.Position = UDim2.new(1, -28, 0.52, 0)
	root.Size = UDim2.fromOffset(168, 92)
	root.BackgroundColor3 = Color3.fromRGB(12, 14, 22)
	root.BackgroundTransparency = 0.18
	root.BorderSizePixel = 0
	root.Parent = screen

	local rootCorner = Instance.new("UICorner")
	rootCorner.CornerRadius = UDim.new(0, 14)
	rootCorner.Parent = root

	local rootStroke = Instance.new("UIStroke")
	rootStroke.Color = Color3.fromRGB(72, 140, 220)
	rootStroke.Thickness = 1.2
	rootStroke.Transparency = 0.45
	rootStroke.Parent = root

	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(28, 36, 58)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(18, 22, 34)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(22, 30, 48)),
	})
	grad.Rotation = 115
	grad.Parent = root

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.Parent = root

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 16)
	title.Font = Enum.Font.GothamMedium
	title.TextSize = 11
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.fromRGB(130, 170, 220)
	title.TextTransparency = 0.12
	title.Text = "MAG"
	title.Parent = root

	local ammo = Instance.new("TextLabel")
	ammo.Name = "AmmoCount"
	ammo.BackgroundTransparency = 1
	ammo.Position = UDim2.fromOffset(0, 18)
	ammo.Size = UDim2.new(1, 0, 0, 44)
	ammo.Font = Enum.Font.GothamBold
	ammo.TextSize = 36
	ammo.TextXAlignment = Enum.TextXAlignment.Left
	ammo.TextColor3 = Color3.fromRGB(235, 245, 255)
	ammo.Text = "·"
	ammo.Parent = root

	local sub = Instance.new("TextLabel")
	sub.Name = "Hint"
	sub.BackgroundTransparency = 1
	sub.Position = UDim2.new(0, 0, 1, -18)
	sub.Size = UDim2.new(1, 0, 0, 14)
	sub.Font = Enum.Font.Gotham
	sub.TextSize = 11
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.TextColor3 = Color3.fromRGB(160, 168, 188)
	sub.TextTransparency = 0.2
	sub.Text = "current / capacity"
	sub.Parent = root

	local ringHolder = Instance.new("Frame")
	ringHolder.Name = "ReloadRing"
	ringHolder.AnchorPoint = Vector2.new(0.5, 0.5)
	ringHolder.Position = UDim2.new(0, -6, 0.5, 0)
	ringHolder.Size = UDim2.fromOffset(56, 56)
	ringHolder.BackgroundTransparency = 1
	ringHolder.Visible = false
	ringHolder.Parent = root

	local ringBg = Instance.new("Frame")
	ringBg.Name = "RingBg"
	ringBg.AnchorPoint = Vector2.new(0.5, 0.5)
	ringBg.Position = UDim2.fromScale(0.5, 0.5)
	ringBg.Size = UDim2.fromScale(1, 1)
	ringBg.BackgroundColor3 = Color3.fromRGB(30, 38, 54)
	ringBg.BackgroundTransparency = 0.25
	ringBg.BorderSizePixel = 0
	ringBg.Parent = ringHolder

	local ringBgCorner = Instance.new("UICorner")
	ringBgCorner.CornerRadius = UDim.new(1, 0)
	ringBgCorner.Parent = ringBg

	local ringStroke = Instance.new("UIStroke")
	ringStroke.Color = Color3.fromRGB(90, 150, 255)
	ringStroke.Thickness = 2
	ringStroke.Transparency = 0.35
	ringStroke.Parent = ringBg

	local ringFill = Instance.new("Frame")
	ringFill.Name = "RingFill"
	ringFill.AnchorPoint = Vector2.new(0, 0.5)
	ringFill.Position = UDim2.new(0, 0, 0.5, 0)
	ringFill.Size = UDim2.new(0, 0, 1, 0)
	ringFill.BackgroundColor3 = Color3.fromRGB(64, 160, 255)
	ringFill.BorderSizePixel = 0
	ringFill.ClipsDescendants = true
	ringFill.Parent = ringBg

	local ringFillCorner = Instance.new("UICorner")
	ringFillCorner.CornerRadius = UDim.new(1, 0)
	ringFillCorner.Parent = ringFill

	local fillGrad = Instance.new("UIGradient")
	fillGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(120, 210, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 90, 220)),
	})
	fillGrad.Rotation = 90
	fillGrad.Parent = ringFill

	reloadRing = ringHolder
	reloadFillBar = ringFill
	reloadBackdrop = ringStroke
	ammoLabel = ammo
	return screen
end

local function onRenderStep()
	local player = Players.LocalPlayer
	if not player or not gui then
		return
	end
	local show = shouldShowHud(player)
	gui.Enabled = show
	if not show then
		setReloadVisual(0, false)
		return
	end

	local tool = trackedTool
	if not tool then
		setReloadVisual(0, false)
		return
	end

	local endsAt = tool:GetAttribute(SniperGunStats.ToolAttrReloadEndsAt)
	local now = Workspace:GetServerTimeNow()
	if type(endsAt) == "number" and endsAt > now then
		local gun = ViewModelClient.getGunModelForTool(tool)
		local stats = SniperGunStats.readForClientLocal(tool, player, gun)
		local span = math.max(0.05, stats.reloadDuration)
		local startedApprox = endsAt - span
		local elapsed = math.clamp(now - startedApprox, 0, span)
		setReloadVisual(elapsed / span, true)
	else
		setReloadVisual(0, false)
	end
end

function SniperAmmoHudClient.setTrackedTool(tool: Tool?)
	if trackedTool == tool then
		return
	end
	hookTool(tool)
end

function SniperAmmoHudClient.ensureStarted(player: Player)
	if started then
		return
	end
	if Config.SniperAmmoHudEnabled == false then
		return
	end
	started = true
	gui = buildGui(player)
	connRender = RunService.RenderStepped:Connect(onRenderStep)
end

return SniperAmmoHudClient