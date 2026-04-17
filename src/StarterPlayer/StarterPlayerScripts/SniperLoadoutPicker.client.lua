-- Bottom-right armory: pick viewmodel template + skin (3D rotating ViewportFrames). Testing: server accepts any valid combo.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local SniperConfig = require(ReplicatedStorage:WaitForChild("Sniper"):WaitForChild("Config"))
local Appearance = require(ReplicatedStorage:WaitForChild("Sniper"):WaitForChild("SniperViewModelAppearance"))
local Catalog = require(ReplicatedStorage:WaitForChild("Sniper"):WaitForChild("SniperViewModelCatalog"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local setLoadoutRemote = remotes:WaitForChild("SetSniperViewModelLoadout")

local COL_BG = Color3.fromRGB(16, 19, 26)
local COL_PANEL = Color3.fromRGB(24, 28, 38)
local COL_STROKE = Color3.fromRGB(48, 56, 72)
local COL_ACCENT = Color3.fromRGB(232, 158, 68)
local COL_TEXT = Color3.fromRGB(228, 232, 240)
local COL_MUTED = Color3.fromRGB(140, 148, 168)
local COL_VP_BG = Color3.fromRGB(10, 12, 18)

local PREVIEW_HEIGHT = 76
local VIEWPORT_WIDTH = 112
local ROW_HEIGHT = PREVIEW_HEIGHT + 10

-- Rotating previews (shared stepped)
local rotationEntries: { { model: Model, basePivot: CFrame, speed: number, dead: boolean } } = {}
local rotationConn: RBXScriptConnection? = nil

local function killRotationEntry(entry: { model: Model, basePivot: CFrame, speed: number, dead: boolean })
	entry.dead = true
end

local function pushRotationEntry(model: Model, basePivot: CFrame, speed: number)
	local entry = { model = model, basePivot = basePivot, speed = speed, dead = false }
	table.insert(rotationEntries, entry)
	if not rotationConn then
		rotationConn = RunService.RenderStepped:Connect(function()
			local t = os.clock()
			for i = #rotationEntries, 1, -1 do
				local e = rotationEntries[i]
				if e.dead or not e.model.Parent then
					table.remove(rotationEntries, i)
				else
					-- Yaw only: rotate around world Y through the model pivot (horizontal spin, no pitch/roll).
					local pos = e.basePivot.Position
					local angle = -t * e.speed
					local rotWorldY = CFrame.new(pos) * CFrame.Angles(0, angle, 0) * CFrame.new(-pos)
					e.model:PivotTo(rotWorldY * e.basePivot)
				end
			end
			if #rotationEntries == 0 and rotationConn then
				rotationConn:Disconnect()
				rotationConn = nil
			end
		end)
	end
	return entry
end

local function preparePreviewClone(clone: Model)
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BaseScript") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
		end
	end
	if clone.PrimaryPart == nil then
		local pp = clone:FindFirstChildWhichIsA("BasePart", true)
		if pp then
			clone.PrimaryPart = pp
		end
	end
end

local function fillViewport(viewport: ViewportFrame, source: Model): any
	local worldModel = Instance.new("WorldModel")
	worldModel.Parent = viewport

	local cam = Instance.new("Camera")
	cam.FieldOfView = 38
	cam.Parent = viewport
	viewport.CurrentCamera = cam

	local clone = source:Clone()
	preparePreviewClone(clone)
	clone.Parent = worldModel

	local basePivot = clone:GetPivot()
	local pos = basePivot.Position
	local _, size = clone:GetBoundingBox()
	local extent = math.max(size.X, size.Y, size.Z) * 0.5
	local dist = math.clamp(extent * 2.75, 1.25, 9)
	local camDir = (Vector3.new(1, 0.5, 1)).Unit
	cam.CFrame = CFrame.lookAt(pos + camDir * dist, pos)

	return pushRotationEntry(clone, basePivot, 0.42)
end

local function createViewportFrame(): ViewportFrame
	local vp = Instance.new("ViewportFrame")
	vp.BackgroundColor3 = COL_VP_BG
	vp.BorderSizePixel = 0
	vp.Ambient = Color3.fromRGB(85, 92, 108)
	vp.LightColor = Color3.fromRGB(220, 228, 245)
	vp.LightDirection = Vector3.new(-0.35, -1, -0.4)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 7)
	c.Parent = vp
	return vp
end

local function textLabel(parent: Instance, text: string, size: number, color: Color3, font: Enum.Font): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextColor3 = color
	l.TextSize = size
	l.Font = font
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Size = UDim2.new(1, 0, 0, 0)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.Parent = parent
	return l
end

local function pillButton(parent: Instance, label: string): TextButton
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.Text = label
	b.TextColor3 = COL_BG
	b.TextSize = 13
	b.Font = Enum.Font.GothamBold
	b.BackgroundColor3 = COL_ACCENT
	b.Size = UDim2.new(0, 72, 0, 30)
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(0, 6)
	bc.Parent = b
	b.MouseEnter:Connect(function()
		b.BackgroundColor3 = Color3.fromRGB(255, 186, 96)
	end)
	b.MouseLeave:Connect(function()
		b.BackgroundColor3 = COL_ACCENT
	end)
	b.Parent = parent
	return b
end

local screenGui: ScreenGui
local weaponsScroll: ScrollingFrame
local skinsScroll: ScrollingFrame
local subtitleWeapon: TextLabel

local selectedTemplateName: string = ""
local weaponRows: { Frame } = {}
local skinRows: { Frame } = {}

local function currentEquippedTemplate(): string
	return Appearance.normalizeId(player:GetAttribute(Appearance.AttributeViewModelTemplateId))
end

local function currentEquippedSkin(): string
	return Appearance.normalizeId(player:GetAttribute(Appearance.AttributeSkinId))
end

local function fireLoadout(templateId: string, skinId: string)
	setLoadoutRemote:FireServer({
		templateId = templateId,
		skinId = skinId,
	})
end

local function clearChildrenExceptLayout(inst: Instance)
	for _, c in ipairs(inst:GetChildren()) do
		if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then
			c:Destroy()
		end
	end
end

local function setRowSelected(row: Frame, on: boolean)
	local stroke = row:FindFirstChildOfClass("UIStroke")
	if not stroke then
		stroke = Instance.new("UIStroke")
		stroke.Name = "SelectStroke"
		stroke.Parent = row
	end
	stroke.Thickness = on and 2 or 0
	stroke.Color = COL_ACCENT
	stroke.Transparency = on and 0 or 1
	row.BackgroundColor3 = on and Color3.fromRGB(32, 38, 52) or COL_PANEL
end

local function rebuildSkinsList(template: Model)
	clearChildrenExceptLayout(skinsScroll)
	table.clear(skinRows)

	local layout = skinsScroll:FindFirstChildOfClass("UIListLayout")
	if not layout then
		layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 6)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = skinsScroll
	end

	-- Default (base Gun)
	do
		local row = Instance.new("Frame")
		row.BackgroundColor3 = COL_PANEL
		row.Size = UDim2.new(1, -8, 0, ROW_HEIGHT)
		row.BorderSizePixel = 0
		local rc = Instance.new("UICorner")
		rc.CornerRadius = UDim.new(0, 8)
		rc.Parent = row

		local vp = createViewportFrame()
		vp.Size = UDim2.new(0, VIEWPORT_WIDTH, 0, PREVIEW_HEIGHT)
		vp.Position = UDim2.new(0, 6, 0, (ROW_HEIGHT - PREVIEW_HEIGHT) / 2)
		vp.Parent = row

		local source = Catalog.getPreviewSourceModel(template, "")
		if source then
			local entry = fillViewport(vp, source)
			row.Destroying:Connect(function()
				killRotationEntry(entry)
			end)
		end

		local right = Instance.new("Frame")
		right.BackgroundTransparency = 1
		right.Position = UDim2.new(0, VIEWPORT_WIDTH + 14, 0, 0)
		right.Size = UDim2.new(1, -(VIEWPORT_WIDTH + 90), 1, 0)
		right.Parent = row

		textLabel(right, "Default", 15, COL_TEXT, Enum.Font.GothamBold)
		textLabel(right, "Base weapon mesh", 12, COL_MUTED, Enum.Font.Gotham)

		local equip = pillButton(row, "Equip")
		equip.Position = UDim2.new(1, -78, 0.5, -15)
		equip.AnchorPoint = Vector2.new(0, 0.5)
		equip.Parent = row

		equip.MouseButton1Click:Connect(function()
			fireLoadout(template.Name, "")
		end)

		row:SetAttribute("SkinKey", "")
		row.Parent = skinsScroll
		table.insert(skinRows, row)
	end

	for _, skinName in ipairs(Catalog.getSortedSkinNames(template)) do
		local row = Instance.new("Frame")
		row.BackgroundColor3 = COL_PANEL
		row.Size = UDim2.new(1, -8, 0, ROW_HEIGHT)
		row.BorderSizePixel = 0
		local rc = Instance.new("UICorner")
		rc.CornerRadius = UDim.new(0, 8)
		rc.Parent = row

		local vp = createViewportFrame()
		vp.Size = UDim2.new(0, VIEWPORT_WIDTH, 0, PREVIEW_HEIGHT)
		vp.Position = UDim2.new(0, 6, 0, (ROW_HEIGHT - PREVIEW_HEIGHT) / 2)
		vp.Parent = row

		local source = Catalog.getPreviewSourceModel(template, skinName)
		if source then
			local entry = fillViewport(vp, source)
			row.Destroying:Connect(function()
				killRotationEntry(entry)
			end)
		end

		local right = Instance.new("Frame")
		right.BackgroundTransparency = 1
		right.Position = UDim2.new(0, VIEWPORT_WIDTH + 14, 0, 0)
		right.Size = UDim2.new(1, -(VIEWPORT_WIDTH + 90), 1, 0)
		right.Parent = row

		textLabel(right, skinName, 15, COL_TEXT, Enum.Font.GothamBold)

		local equip = pillButton(row, "Equip")
		equip.Position = UDim2.new(1, -78, 0.5, -15)
		equip.AnchorPoint = Vector2.new(0, 0.5)
		equip.Parent = row

		equip.MouseButton1Click:Connect(function()
			fireLoadout(template.Name, skinName)
		end)

		row:SetAttribute("SkinKey", skinName)
		row.Parent = skinsScroll
		table.insert(skinRows, row)
	end

end

local function refreshSelectionHighlights()
	local eqT = currentEquippedTemplate()
	local eqS = currentEquippedSkin()
	for _, row in ipairs(weaponRows) do
		local name = row:GetAttribute("TemplateName")
		if type(name) == "string" then
			setRowSelected(row, eqT == name)
		end
	end
	for _, row in ipairs(skinRows) do
		local sk = row:GetAttribute("SkinKey")
		if type(sk) == "string" and eqT == selectedTemplateName then
			if sk == "" then
				setRowSelected(row, eqS == "")
			else
				setRowSelected(row, string.lower(eqS) == string.lower(sk))
			end
		else
			setRowSelected(row, false)
		end
	end
end

local function rebuildWeaponsList()
	clearChildrenExceptLayout(weaponsScroll)
	table.clear(weaponRows)

	local layout = weaponsScroll:FindFirstChildOfClass("UIListLayout")
	if not layout then
		layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 6)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = weaponsScroll
	end

	local templates = Catalog.getSortedRootTemplates()
	if #templates == 0 then
		local empty = textLabel(weaponsScroll, "No models in ViewModels folder.", 14, COL_MUTED, Enum.Font.Gotham)
		empty.TextXAlignment = Enum.TextXAlignment.Center
		empty.Size = UDim2.new(1, -12, 0, 40)
		return
	end

	local vmFolder = Catalog.findViewModelsFolder()
	if
		selectedTemplateName == ""
		or vmFolder == nil
		or Catalog.resolveTemplate(vmFolder, selectedTemplateName) == nil
	then
		selectedTemplateName = templates[1].Name
	end

	local eqTemplate = currentEquippedTemplate()
	if eqTemplate ~= "" and vmFolder and Catalog.resolveTemplate(vmFolder, eqTemplate) then
		selectedTemplateName = eqTemplate
	end

	for _, template in ipairs(templates) do
		local row = Instance.new("Frame")
		row:SetAttribute("TemplateName", template.Name)
		row.BackgroundColor3 = COL_PANEL
		row.Size = UDim2.new(1, -8, 0, ROW_HEIGHT)
		row.BorderSizePixel = 0
		local rc = Instance.new("UICorner")
		rc.CornerRadius = UDim.new(0, 8)
		rc.Parent = row

		local vp = createViewportFrame()
		vp.Size = UDim2.new(0, VIEWPORT_WIDTH, 0, PREVIEW_HEIGHT)
		vp.Position = UDim2.new(0, 6, 0, (ROW_HEIGHT - PREVIEW_HEIGHT) / 2)
		vp.Parent = row

		local source = Catalog.getPreviewSourceModel(template, "")
		if source then
			local entry = fillViewport(vp, source)
			row.Destroying:Connect(function()
				killRotationEntry(entry)
			end)
		end

		local right = Instance.new("Frame")
		right.BackgroundTransparency = 1
		right.Position = UDim2.new(0, VIEWPORT_WIDTH + 14, 0, 0)
		right.Size = UDim2.new(1, -(VIEWPORT_WIDTH + 160), 1, 0)
		right.Parent = row

		textLabel(right, template.Name, 15, COL_TEXT, Enum.Font.GothamBold)

		local pick = pillButton(row, "Skins")
		pick.Size = UDim2.new(0, 64, 0, 30)
		pick.Position = UDim2.new(1, -150, 0.5, -15)
		pick.AnchorPoint = Vector2.new(0, 0.5)
		pick.BackgroundColor3 = Color3.fromRGB(55, 64, 84)
		pick.TextColor3 = COL_TEXT
		pick.MouseEnter:Connect(function()
			pick.BackgroundColor3 = Color3.fromRGB(68, 78, 102)
		end)
		pick.MouseLeave:Connect(function()
			pick.BackgroundColor3 = Color3.fromRGB(55, 64, 84)
		end)
		pick.Parent = row
		pick.MouseButton1Click:Connect(function()
			selectedTemplateName = template.Name
			subtitleWeapon.Text = "Skins — " .. template.Name
			rebuildSkinsList(template)
			refreshSelectionHighlights()
		end)

		local equip = pillButton(row, "Equip")
		equip.Position = UDim2.new(1, -78, 0.5, -15)
		equip.AnchorPoint = Vector2.new(0, 0.5)
		equip.Parent = row
		equip.MouseButton1Click:Connect(function()
			selectedTemplateName = template.Name
			subtitleWeapon.Text = "Skins — " .. template.Name
			rebuildSkinsList(template)
			fireLoadout(template.Name, "")
		end)

		row.Parent = weaponsScroll
		table.insert(weaponRows, row)
	end

	local folder2 = Catalog.findViewModelsFolder()
	local tm = folder2 and Catalog.resolveTemplate(folder2, selectedTemplateName)
	if tm then
		subtitleWeapon.Text = "Skins — " .. tm.Name
		rebuildSkinsList(tm)
	end

	refreshSelectionHighlights()
end

local function buildGui()
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "SkyLeapSniperLoadoutPicker"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = false
	screenGui.DisplayOrder = 42
	screenGui.Parent = playerGui

	local root = Instance.new("Frame")
	root.Name = "ArmoryPanel"
	root.AnchorPoint = Vector2.new(1, 1)
	root.Position = UDim2.new(1, -14, 1, -14)
	root.Size = UDim2.fromOffset(312, 438)
	root.BackgroundColor3 = COL_BG
	root.BorderSizePixel = 0
	root.Parent = screenGui

	local rootCorner = Instance.new("UICorner")
	rootCorner.CornerRadius = UDim.new(0, 12)
	rootCorner.Parent = root

	local rootStroke = Instance.new("UIStroke")
	rootStroke.Color = COL_STROKE
	rootStroke.Thickness = 1
	rootStroke.Transparency = 0.35
	rootStroke.Parent = root

	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 12)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = root

	local header = Instance.new("Frame")
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, 36)
	header.Parent = root

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 18
	title.TextColor3 = COL_TEXT
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "ARMORY"
	title.Size = UDim2.new(1, -40, 1, 0)
	title.Parent = header

	local hint = Instance.new("TextLabel")
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.Gotham
	hint.TextSize = 11
	hint.TextColor3 = COL_MUTED
	hint.TextXAlignment = Enum.TextXAlignment.Right
	hint.Text = "[RightShift] hide"
	hint.Size = UDim2.new(0, 120, 1, 0)
	hint.Position = UDim2.new(1, 0, 0, 0)
	hint.AnchorPoint = Vector2.new(1, 0)
	hint.Parent = header

	local secWeapons = textLabel(root, "Weapons", 13, COL_ACCENT, Enum.Font.GothamBold)
	secWeapons.Position = UDim2.new(0, 0, 0, 40)
	secWeapons.Parent = root

	weaponsScroll = Instance.new("ScrollingFrame")
	weaponsScroll.Name = "WeaponsScroll"
	weaponsScroll.BackgroundTransparency = 1
	weaponsScroll.BorderSizePixel = 0
	weaponsScroll.ScrollBarThickness = 4
	weaponsScroll.ScrollBarImageColor3 = COL_STROKE
	weaponsScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	weaponsScroll.CanvasSize = UDim2.new()
	weaponsScroll.Size = UDim2.new(1, 0, 0, 168)
	weaponsScroll.Position = UDim2.new(0, 0, 0, 62)
	weaponsScroll.Parent = root

	local wl = Instance.new("UIListLayout")
	wl.Padding = UDim.new(0, 6)
	wl.SortOrder = Enum.SortOrder.LayoutOrder
	wl.Parent = weaponsScroll

	subtitleWeapon = textLabel(root, "Skins", 13, COL_ACCENT, Enum.Font.GothamBold)
	subtitleWeapon.Position = UDim2.new(0, 0, 0, 234)
	subtitleWeapon.Parent = root

	skinsScroll = Instance.new("ScrollingFrame")
	skinsScroll.Name = "SkinsScroll"
	skinsScroll.BackgroundTransparency = 1
	skinsScroll.BorderSizePixel = 0
	skinsScroll.ScrollBarThickness = 4
	skinsScroll.ScrollBarImageColor3 = COL_STROKE
	skinsScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	skinsScroll.CanvasSize = UDim2.new()
	skinsScroll.Size = UDim2.new(1, 0, 0, 178)
	skinsScroll.Position = UDim2.new(0, 0, 0, 256)
	skinsScroll.Parent = root

	local sl = Instance.new("UIListLayout")
	sl.Padding = UDim.new(0, 6)
	sl.SortOrder = Enum.SortOrder.LayoutOrder
	sl.Parent = skinsScroll

	local footer = Instance.new("TextLabel")
	footer.BackgroundTransparency = 1
	footer.Font = Enum.Font.Gotham
	footer.TextSize = 10
	footer.TextColor3 = Color3.fromRGB(100, 108, 128)
	footer.TextWrapped = true
	footer.TextXAlignment = Enum.TextXAlignment.Left
	footer.Text = "Preview uses Gun / skin mesh. Equip updates first-person viewmodel after profile sync."
	footer.Size = UDim2.new(1, 0, 0, 28)
	footer.Position = UDim2.new(0, 0, 1, -28)
	footer.Parent = root

	if not SniperConfig.SniperViewModelEnabled then
		root.Visible = false
	end
end

local panelVisible = true

local function setPanelVisible(v: boolean)
	panelVisible = v
	local root = screenGui and screenGui:FindFirstChild("ArmoryPanel")
	if root then
		(root :: Frame).Visible = v
	end
end

buildGui()
rebuildWeaponsList()

player:GetAttributeChangedSignal(Appearance.AttributeViewModelTemplateId):Connect(function()
	refreshSelectionHighlights()
end)
player:GetAttributeChangedSignal(Appearance.AttributeSkinId):Connect(function()
	refreshSelectionHighlights()
end)

UserInputService.InputBegan:Connect(function(input, gp)
	if gp then
		return
	end
	if input.KeyCode == Enum.KeyCode.RightShift then
		setPanelVisible(not panelVisible)
	end
end)

-- If ViewModels stream in late (rare), retry once
task.delay(2, function()
	if #Catalog.getSortedRootTemplates() > 0 and #weaponRows == 0 then
		rebuildWeaponsList()
	end
end)
