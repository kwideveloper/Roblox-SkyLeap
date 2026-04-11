-- Bottom weapon slots (slot 1 = Sniper). Uses existing ScreenGui + Slot1 if present; otherwise builds a simple bar.
-- Replace: add a ScreenGui named Config.SniperWeaponBarScreenGuiName under PlayerGui with a GuiButton (or TextButton) named "Slot1".

local UserInputService = game:GetService("UserInputService")

local Config = require(script.Parent.Config)
local SniperLoadoutState = require(script.Parent.SniperLoadoutState)

local SniperWeaponBarClient = {}

local started = false
local slot1Button: GuiButton? = nil
local selectionStroke: UIStroke? = nil

local function findDescendantNamed(root: Instance, name: string): Instance?
	for _, d in ipairs(root:GetDescendants()) do
		if d.Name == name then
			return d
		end
	end
	return nil
end

local function asGuiButton(inst: Instance?): GuiButton?
	if inst and inst:IsA("GuiButton") then
		return inst :: GuiButton
	end
	return nil
end

local function applySlotVisual(selected: boolean)
	if not slot1Button then
		return
	end
	if selectionStroke then
		selectionStroke.Enabled = selected
	end
	if slot1Button:IsA("TextButton") then
		local tb = slot1Button :: TextButton
		if selected then
			tb.BackgroundColor3 = Color3.fromRGB(55, 95, 140)
		else
			tb.BackgroundColor3 = Color3.fromRGB(38, 42, 52)
		end
	end
end

local function refreshVisual()
	local on = SniperLoadoutState.getSelectedSlot() == 1
	applySlotVisual(on)
end

local function wireSlot1(btn: GuiButton)
	slot1Button = btn
	if not btn:FindFirstChild("SkyLeapSlotSelectionStroke") then
		local s = Instance.new("UIStroke")
		s.Name = "SkyLeapSlotSelectionStroke"
		s.Color = Color3.fromRGB(120, 200, 255)
		s.Thickness = 2
		s.Enabled = false
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Parent = btn
		selectionStroke = s
	else
		selectionStroke = btn:FindFirstChildWhichIsA("UIStroke")
	end

	btn.MouseButton1Click:Connect(function()
		SniperLoadoutState.toggleSlot1()
		refreshVisual()
	end)
	refreshVisual()
end

local function createDefaultBar(player: Player): ScreenGui
	local pg = player:WaitForChild("PlayerGui", 30) :: PlayerGui
	local gui = Instance.new("ScreenGui")
	gui.Name = Config.SniperWeaponBarScreenGuiName or "SkyLeapWeaponBar"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = Config.SniperWeaponBarDisplayOrder or 80
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = pg

	local root = Instance.new("Frame")
	root.Name = "BarRoot"
	root.AnchorPoint = Vector2.new(0.5, 1)
	root.Position = UDim2.new(0.5, 0, 1, -18)
	root.Size = UDim2.fromOffset(220, 56)
	root.BackgroundColor3 = Color3.fromRGB(22, 24, 30)
	root.BackgroundTransparency = 0.12
	root.BorderSizePixel = 0
	root.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = root

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(55, 62, 78)
	stroke.Thickness = 1
	stroke.Transparency = 0.35
	stroke.Parent = root

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.Parent = root

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 10)
	layout.Parent = root

	local slot = Instance.new("TextButton")
	slot.Name = "Slot1"
	slot.AutoButtonColor = true
	slot.Size = UDim2.fromOffset(72, 40)
	slot.BackgroundColor3 = Color3.fromRGB(38, 42, 52)
	slot.Text = "SNIPER"
	slot.TextColor3 = Color3.fromRGB(230, 235, 245)
	slot.TextSize = 14
	slot.Font = Enum.Font.GothamBold
	slot.BorderSizePixel = 0
	slot.Parent = root

	local sc = Instance.new("UICorner")
	sc.CornerRadius = UDim.new(0, 8)
	sc.Parent = slot

	local hint = Instance.new("TextLabel")
	hint.Name = "HotkeyHint"
	hint.BackgroundTransparency = 1
	hint.Size = UDim2.fromOffset(40, 16)
	hint.Position = UDim2.new(1, -44, 0, -2)
	hint.AnchorPoint = Vector2.new(0, 0)
	hint.Text = "[1]"
	hint.TextColor3 = Color3.fromRGB(160, 170, 190)
	hint.TextSize = 12
	hint.Font = Enum.Font.Gotham
	hint.Parent = slot

	return gui
end

local function resolveOrCreateGui(player: Player): (ScreenGui?, GuiButton?)
	local pg = player:WaitForChild("PlayerGui", 30) :: PlayerGui?
	if not pg then
		return nil, nil
	end
	local wantName = Config.SniperWeaponBarScreenGuiName or "SkyLeapWeaponBar"
	local existing = pg:FindFirstChild(wantName)
	if existing and existing:IsA("ScreenGui") then
		local slot = asGuiButton(findDescendantNamed(existing, "Slot1"))
		if slot then
			return existing, slot
		end
	end
	if Config.SniperWeaponBarCreateIfMissing == false then
		return nil, nil
	end
	local created = createDefaultBar(player)
	local slot = asGuiButton(findDescendantNamed(created, "Slot1"))
	return created, slot
end

local inputConn: RBXScriptConnection? = nil

local function onInputBegan(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if not Config.SniperVirtualInventoryEnabled then
		return
	end
	if input.KeyCode == Enum.KeyCode.One or input.KeyCode == Enum.KeyCode.KeypadOne then
		SniperLoadoutState.toggleSlot1()
		refreshVisual()
	end
end

function SniperWeaponBarClient.ensureStarted(player: Player)
	if not Config.SniperVirtualInventoryEnabled then
		return
	end
	if started then
		refreshVisual()
		return
	end
	started = true

	local gui, slot1 = resolveOrCreateGui(player)
	if gui and slot1 then
		wireSlot1(slot1)
	end

	if inputConn then
		inputConn:Disconnect()
	end
	inputConn = UserInputService.InputBegan:Connect(onInputBegan)

	player.CharacterRemoving:Connect(function()
		refreshVisual()
	end)
end

return SniperWeaponBarClient
