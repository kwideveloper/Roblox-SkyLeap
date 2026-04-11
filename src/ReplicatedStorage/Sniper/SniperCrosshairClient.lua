-- Client: sniper crosshair only while the tool is equipped AND the camera is in first-person aim (same rule as viewmodel).
-- Roblox may show hand / I-beam cursors over GuiObjects (MouseIcon is ignored on hover); we never enable crosshair in third person so we do not fight that state.

local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(script.Parent.Config)
local SniperFirstPersonGate = require(script.Parent.SniperFirstPersonGate)
local SniperPointerSuppress = require(script.Parent.SniperPointerSuppress)
local SniperLoadoutState = require(script.Parent.SniperLoadoutState)

local GUI_NAME = "SkyLeapSniperCrosshair"

local function toolIsSniper(tool: Tool): boolean
	return tool.Name == Config.ToolName
end

local function normalizeMouseIconContent(raw: string): string
	if raw == nil then
		return ""
	end
	local s = string.gsub(string.gsub(raw, "^%s+", ""), "%s+$", "")
	if s == "" then
		return ""
	end
	if string.find(s, "rbxassetid://", 1, true) or string.find(s, "rbxasset://", 1, true) or string.find(s, "rbxthumb://", 1, true) then
		return s
	end
	local num = string.match(s, "^(%d+)$")
	if num then
		return "rbxassetid://" .. num
	end
	return s
end

local function setMouseIconContent(content: string)
	pcall(function()
		UserInputService.MouseIcon = content
	end)
	local plr = Players.LocalPlayer
	if plr then
		local mouse = plr:GetMouse()
		if mouse then
			mouse.Icon = content
		end
	end
end

local function getMouseIconContent(): string
	local ok, v = pcall(function()
		return UserInputService.MouseIcon
	end)
	if ok and type(v) == "string" then
		return v
	end
	local plr = Players.LocalPlayer
	if plr then
		local mouse = plr:GetMouse()
		if mouse and type(mouse.Icon) == "string" then
			return mouse.Icon
		end
	end
	return ""
end

local function clearGuiFocus()
	pcall(function()
		GuiService.SelectedObject = nil
	end)
end

local SniperCrosshairClient = {}

function SniperCrosshairClient.attach(tool: Tool, plr: Player)
	if not toolIsSniper(tool) then
		return
	end
	if tool:GetAttribute("_SniperCrosshairAttached") then
		return
	end
	tool:SetAttribute("_SniperCrosshairAttached", true)

	local stepName = "SkyLeapSniperCrosshair_" .. HttpService:GenerateGUID(false)
	local gui: ScreenGui? = nil
	local savedMouseIcon: string? = nil
	local savedMouseIconEnabled: boolean? = nil
	local savedMouseBehavior: Enum.MouseBehavior? = nil
	local visualsActive = false

	local function destroyGui()
		if gui then
			gui:Destroy()
			gui = nil
		end
	end

	local function createCenterCrosshairGui(): ScreenGui?
		destroyGui()

		local thickness = math.clamp(math.floor(Config.SniperCrosshairGuiThicknessPx or 2), 1, 8)
		local gap = math.clamp(math.floor(Config.SniperCrosshairGuiGapPx or 4), 0, 32)
		local arm = math.clamp(math.floor(Config.SniperCrosshairGuiArmLengthPx or 14), 6, 48)
		local dot = math.clamp(math.floor(Config.SniperCrosshairGuiDotPx or 3), 0, 10)
		local col = Config.SniperCrosshairGuiColor or Color3.fromRGB(255, 255, 255)
		local alpha = Config.SniperCrosshairGuiTransparency
		if type(alpha) ~= "number" then
			alpha = 0.05
		end
		alpha = math.clamp(alpha, 0, 1)

		local pg = plr:WaitForChild("PlayerGui", 30)
		if not pg then
			return nil
		end
		local old = pg:FindFirstChild(GUI_NAME)
		if old then
			old:Destroy()
		end

		local screen = Instance.new("ScreenGui")
		screen.Name = GUI_NAME
		screen.ResetOnSpawn = false
		screen.IgnoreGuiInset = true
		screen.Enabled = true
		screen.DisplayOrder = Config.SniperCrosshairGuiDisplayOrder or 100000
		screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		pcall(function()
			(screen :: any).Active = false
		end)
		pcall(function()
			(screen :: any).ScreenInsets = Enum.ScreenInsets.None
		end)
		screen.Parent = pg

		local root = Instance.new("Frame")
		root.Name = "Root"
		root.BackgroundTransparency = 1
		root.Size = UDim2.fromScale(1, 1)
		root.Active = false
		root.Selectable = false
		root.Interactable = false
		root.ZIndex = 1
		root.Parent = screen

		local holder = Instance.new("Frame")
		holder.Name = "Cross"
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Position = UDim2.fromScale(0.5, 0.5)
		holder.Size = UDim2.fromOffset(arm * 2 + gap * 2 + thickness * 2, arm * 2 + gap * 2 + thickness * 2)
		holder.BackgroundTransparency = 1
		holder.Active = false
		holder.Selectable = false
		holder.Interactable = false
		holder.ZIndex = 2
		holder.Parent = root

		local function bar(name: string, size: UDim2, pos: UDim2)
			local f = Instance.new("Frame")
			f.Name = name
			f.BackgroundColor3 = col
			f.BackgroundTransparency = alpha
			f.BorderSizePixel = 0
			f.Size = size
			f.Position = pos
			f.AnchorPoint = Vector2.new(0.5, 0.5)
			f.Active = false
			f.Selectable = false
			f.Interactable = false
			f.ZIndex = 10
			f.Parent = holder
			if Config.SniperCrosshairGuiStrokeEnabled then
				local s = Instance.new("UIStroke")
				s.Color = Color3.fromRGB(0, 0, 0)
				s.Thickness = 2
				s.Transparency = 0.35
				s.LineJoinMode = Enum.LineJoinMode.Miter
				s.Parent = f
			end
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0, 1)
			c.Parent = f
		end

		local half = gap + arm * 0.5 + thickness * 0.5
		bar("Top", UDim2.fromOffset(thickness, arm), UDim2.new(0.5, 0, 0.5, -half))
		bar("Bottom", UDim2.fromOffset(thickness, arm), UDim2.new(0.5, 0, 0.5, half))
		bar("Left", UDim2.fromOffset(arm, thickness), UDim2.new(0.5, -half, 0.5, 0))
		bar("Right", UDim2.fromOffset(arm, thickness), UDim2.new(0.5, half, 0.5, 0))

		if dot > 0 then
			local d = Instance.new("Frame")
			d.Name = "Dot"
			d.AnchorPoint = Vector2.new(0.5, 0.5)
			d.Position = UDim2.fromScale(0.5, 0.5)
			d.Size = UDim2.fromOffset(dot, dot)
			d.BackgroundColor3 = col
			d.BackgroundTransparency = math.clamp(alpha - 0.02, 0, 1)
			d.BorderSizePixel = 0
			d.Active = false
			d.Selectable = false
			d.Interactable = false
			d.ZIndex = 11
			d.Parent = holder
			local cd = Instance.new("UICorner")
			cd.CornerRadius = UDim.new(1, 0)
			cd.Parent = d
			if Config.SniperCrosshairGuiStrokeEnabled then
				local st = Instance.new("UIStroke")
				st.Color = Color3.fromRGB(0, 0, 0)
				st.Thickness = 2
				st.Transparency = 0.4
				st.Parent = d
			end
		end

		gui = screen
		return screen
	end

	local function showVisuals()
		if visualsActive or not Config.SniperCrosshairEnabled then
			return
		end
		visualsActive = true
		SniperPointerSuppress.push()

		if savedMouseIcon == nil then
			savedMouseIcon = getMouseIconContent()
		end
		if savedMouseIconEnabled == nil then
			savedMouseIconEnabled = UserInputService.MouseIconEnabled
		end

		local lockCenter = Config.SniperCrosshairLockMouseCenterWhileAiming ~= false
		if lockCenter then
			if savedMouseBehavior == nil then
				savedMouseBehavior = UserInputService.MouseBehavior
			end
			pcall(function()
				UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
			end)
			setMouseIconContent("")
			if Config.SniperCrosshairCenterGuiEnabled and Config.SniperCrosshairHideDefaultMouseWithCenterGui then
				UserInputService.MouseIconEnabled = false
			end
		else
			local icon = normalizeMouseIconContent(Config.SniperCrosshairMouseIcon or "")
			if icon ~= "" then
				setMouseIconContent(icon)
			end
			if Config.SniperCrosshairCenterGuiEnabled then
				local created = createCenterCrosshairGui()
				if created and Config.SniperCrosshairHideDefaultMouseWithCenterGui then
					task.defer(function()
						if visualsActive and gui and gui.Parent then
							UserInputService.MouseIconEnabled = false
						end
					end)
				end
			end
			return
		end

		if Config.SniperCrosshairCenterGuiEnabled then
			createCenterCrosshairGui()
		end
	end

	local function hideVisuals()
		if not visualsActive then
			return
		end
		visualsActive = false

		destroyGui()

		if savedMouseBehavior ~= nil then
			local restore = savedMouseBehavior
			savedMouseBehavior = nil
			pcall(function()
				UserInputService.MouseBehavior = restore
			end)
		end

		if savedMouseIcon ~= nil then
			setMouseIconContent(savedMouseIcon)
			savedMouseIcon = nil
		else
			setMouseIconContent("")
		end
		if savedMouseIconEnabled ~= nil then
			UserInputService.MouseIconEnabled = savedMouseIconEnabled
			savedMouseIconEnabled = nil
		else
			UserInputService.MouseIconEnabled = true
		end

		clearGuiFocus()
		SniperPointerSuppress.pop()
	end

	local function tick()
		if not Config.SniperCrosshairEnabled then
			if visualsActive then
				hideVisuals()
			end
			return
		end

		local ch = plr.Character
		local equipped = false
		if ch then
			if Config.SniperVirtualInventoryEnabled then
				local bp = plr:FindFirstChildOfClass("Backpack")
				equipped = bp ~= nil and tool.Parent == bp and SniperLoadoutState.isSniperActive(tool)
			else
				equipped = tool.Parent == ch
			end
		end
		local fp = equipped and SniperFirstPersonGate.isCameraCloseForFirstPerson(plr)

		if equipped and fp then
			showVisuals()
		else
			hideVisuals()
		end

		if visualsActive then
			local lockCenter = Config.SniperCrosshairLockMouseCenterWhileAiming ~= false
			if lockCenter then
				pcall(function()
					UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
				end)
			end
			if Config.SniperCrosshairCenterGuiEnabled and Config.SniperCrosshairHideDefaultMouseWithCenterGui then
				UserInputService.MouseIconEnabled = false
			end
			pcall(function()
				UserInputService.AutoPointerEnabled = false
			end)
		end
	end

	local crosshairPriority = Enum.RenderPriority.Camera.Value + 2
	local okLast, lastVal = pcall(function()
		return Enum.RenderPriority.Last.Value
	end)
	if okLast and type(lastVal) == "number" then
		crosshairPriority = lastVal
	end
	RunService:BindToRenderStep(stepName, crosshairPriority, tick)

	local function stopAll()
		pcall(function()
			RunService:UnbindFromRenderStep(stepName)
		end)
		hideVisuals()
	end

	tool.Destroying:Connect(stopAll)

	tool:GetPropertyChangedSignal("Parent"):Connect(function()
		if not tool.Parent then
			stopAll()
		end
	end)
end

return SniperCrosshairClient
