-- Client: weapon viewmodels parented to CurrentCamera when the Sniper is equipped and the camera is close enough (first-person style).
-- Templates live in ReplicatedStorage under ViewModelsFolderName (Studio Models only; no scripts in that folder).

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent.Config)
local SniperWeaponPartResolve = require(script.Parent.SniperWeaponPartResolve)
local SniperPointerSuppress = require(script.Parent.SniperPointerSuppress)
local SniperFirstPersonGate = require(script.Parent.SniperFirstPersonGate)
local SniperLoadoutState = require(script.Parent.SniperLoadoutState)
local RigHelper = require(script.Parent.ViewModelAnimationRigHelper)
local SniperViewModelAnimator = require(script.Parent.SniperViewModelAnimator)
local SniperViewModelAppearance = require(script.Parent.SniperViewModelAppearance)

local RENDER_STEP_NAME = "SkyLeapSniperViewModel"

local warnedMissingTemplate = false
-- Rigid pivot→CameraBone relation captured once per clone (before Parent = camera).
local camBoneRelCache: { [Model]: CFrame } = {}
local warnedViewModelNotAlongWorldZ: { [string]: boolean } = {}

-- Convention: template Model pivot (PrimaryPart) LookVector should lie along ±World Z (Studio blue axis).
local function warnIfViewmodelNotFacingWorldZ(clone: Model, modelName: string)
	if Config.SniperViewModelWarnIfNotFacingWorldZ == false then
		return
	end
	if warnedViewModelNotAlongWorldZ[modelName] then
		return
	end
	local lv = clone:GetPivot().LookVector
	if math.abs(lv:Dot(Vector3.zAxis)) < 0.9 then
		warnedViewModelNotAlongWorldZ[modelName] = true
		warn(
			("[Sniper] ViewModel %q: orient the template so PrimaryPart LookVector aligns with World ±Z (blue axis). Current LookVector=%s"):format(
				modelName,
				tostring(lv)
			)
		)
	end
end

local function findViewModelsFolder(): Instance?
	local want = Config.ViewModelsFolderName or "ViewModels"
	if want == "" then
		return ReplicatedStorage
	end
	local direct = ReplicatedStorage:FindFirstChild(want)
	if direct then
		return direct
	end
	local lowerWant = string.lower(want)
	for _, child in ipairs(ReplicatedStorage:GetChildren()) do
		if string.lower(child.Name) == lowerWant then
			return child
		end
	end
	return nil
end

local function resolveTemplateModel(root: Instance, modelName: string): Model?
	local t = root:FindFirstChild(modelName)
	if not t then
		local lower = string.lower(modelName)
		for _, child in ipairs(root:GetChildren()) do
			if child:IsA("Model") and string.lower(child.Name) == lower then
				return child
			end
			if child:IsA("Folder") and string.lower(child.Name) == lower then
				local m = child:FindFirstChildWhichIsA("Model", true)
				if m then
					return m
				end
			end
		end
		return nil
	end
	if t:IsA("Model") then
		return t
	end
	if t:IsA("Folder") then
		local m = t:FindFirstChildWhichIsA("Model", true)
		if m then
			return m
		end
	end
	return nil
end

local function ensurePrimaryPart(model: Model): BasePart?
	if model.PrimaryPart then
		return model.PrimaryPart
	end
	local preferredNames = { "CameraBone", "HumanoidRootPart", "Main" }
	for _, name in ipairs(preferredNames) do
		local p = model:FindFirstChild(name, true)
		if p and p:IsA("BasePart") then
			model.PrimaryPart = p
			return p
		end
	end
	local p = model:FindFirstChildWhichIsA("BasePart", true)
	if p then
		model.PrimaryPart = p
		return p
	end
	return nil
end

local function stripViewmodelClone(clone: Model)
	if not Config.SniperViewModelStripWorldInteractables then
		return
	end
	local snapshot = clone:GetDescendants()
	for _, d in ipairs(snapshot) do
		if d:IsA("ClickDetector") or d:IsA("DragDetector") then
			pcall(function()
				d:Destroy()
			end)
		elseif d:IsA("ProximityPrompt") then
			pcall(function()
				d.Enabled = false
				d:Destroy()
			end)
		elseif d:IsA("Tool") then
			pcall(function()
				d:Destroy()
			end)
		end
	end
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then
			pcall(function()
				d.CanTouch = false
			end)
		end
	end
end

local function suppressWorldArmsForSniperViewmodel(char: Model)
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") and d:FindFirstAncestorOfClass("Accessory") == nil then
			local n = d.Name
			if string.find(n, "Arm") ~= nil or string.find(n, "Hand") ~= nil then
				d.LocalTransparencyModifier = 1
			end
		end
	end
end

local function sortedRootModels(folder: Instance): { Model }
	local t: { Model } = {}
	for _, c in ipairs(folder:GetChildren()) do
		if c:IsA("Model") then
			table.insert(t, c)
		end
	end
	table.sort(t, function(a, b)
		return a.Name < b.Name
	end)
	return t
end

-- 1) attach() override 2) player attribute 3) first Model under folder (alphabetical) 4) Config.SniperViewModelName.
local function resolveViewModelTemplateForPlayer(folder: Instance, player: Player, attachOverride: string?): (string, Model?)
	if type(attachOverride) == "string" and attachOverride ~= "" then
		local m = resolveTemplateModel(folder, attachOverride)
		if m then
			return attachOverride, m
		end
	end
	local attrId = SniperViewModelAppearance.normalizeId(player:GetAttribute(SniperViewModelAppearance.AttributeViewModelTemplateId))
	if attrId ~= "" then
		local m = resolveTemplateModel(folder, attrId)
		if m then
			return attrId, m
		end
	end
	local roots = sortedRootModels(folder)
	if #roots > 0 then
		return roots[1].Name, roots[1]
	end
	local cfgName = Config.SniperViewModelName
	if type(cfgName) == "string" and cfgName ~= "" then
		local m = resolveTemplateModel(folder, cfgName)
		if m then
			return cfgName, m
		end
	end
	return "", nil
end

-- Spectator / no Player: explicit template id, then first root Model, then Config.
local function resolveViewModelTemplateExplicit(folder: Instance, templateId: string?): (string, Model?)
	local id = SniperViewModelAppearance.normalizeId(templateId)
	if id ~= "" then
		local m = resolveTemplateModel(folder, id)
		if m then
			return id, m
		end
	end
	local roots = sortedRootModels(folder)
	if #roots > 0 then
		return roots[1].Name, roots[1]
	end
	local cfgName = Config.SniperViewModelName
	if type(cfgName) == "string" and cfgName ~= "" then
		local m = resolveTemplateModel(folder, cfgName)
		if m then
			return cfgName, m
		end
	end
	return "", nil
end

local function prepareClone(clone: Model, skinId: string)
	stripViewmodelClone(clone)
	if not ensurePrimaryPart(clone) then
		return false
	end
	local primary = clone.PrimaryPart :: BasePart
	local useAnimatedRig = SniperViewModelAnimator.hasConfiguredAnimations()
	if useAnimatedRig then
		RigHelper.applyAnchorStrategyForAnimation(clone, primary)
	else
		RigHelper.applyStaticAnchors(clone)
	end
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = 0
			if Config.SniperViewModelCastShadow == false then
				d.CastShadow = false
			end
		end
	end
	SniperViewModelAppearance.applyGunSkinSwap(clone, skinId)
	if useAnimatedRig then
		RigHelper.applyAnchorStrategyForAnimation(clone, primary)
	else
		RigHelper.applyStaticAnchors(clone)
	end
	return true
end

local function buildCameraBoneTargetCFrame(camCf: CFrame, offset: CFrame): CFrame
	if Config.SniperViewModelCameraBoneMatchCameraBasis == false then
		return camCf * offset
	end
	local pos = (camCf * offset).Position
	local look = camCf.LookVector
	local upRef = camCf.UpVector
	local cf = CFrame.lookAt(pos, pos + look, upRef)
	local rollDeg = tonumber(Config.SniperViewModelCameraBoneRollDegrees) or 0
	if math.abs(rollDeg) > 1e-4 then
		cf = cf * CFrame.Angles(0, 0, math.rad(rollDeg))
	end
	return cf
end

-- Model pivot CFrame so CameraBone matches target (see buildCameraBoneTargetCFrame).
local function solveViewmodelWorldPivot(clone: Model, camCf: CFrame, offset: CFrame): CFrame
	if Config.SniperViewModelPivotUsesCameraBone == false then
		return camCf * offset
	end
	local boneName = Config.SniperViewModelCameraBoneName or "CameraBone"
	local bone = clone:FindFirstChild(boneName, true)
	if not bone or not bone:IsA("BasePart") then
		return buildCameraBoneTargetCFrame(camCf, offset)
	end
	local target = buildCameraBoneTargetCFrame(camCf, offset)
	local rel = camBoneRelCache[clone]
	if not rel then
		rel = clone:GetPivot():ToObjectSpace(bone.CFrame)
	end
	return target * rel:Inverse()
end

local function setSniperViewmodelAttr(ch: Model?, on: boolean)
	if not ch then
		return
	end
	if on then
		ch:SetAttribute("SkyLeapSniperViewModelActive", true)
	else
		ch:SetAttribute("SkyLeapSniperViewModelActive", nil)
	end
end

local states: {
	[Tool]: {
		tool: Tool,
		player: Player,
		attachTemplateOverride: string?,
		clone: Model?,
		animHandle: SniperViewModelAnimator.AnimatorHandle?,
		pointerSuppressActive: boolean?,
		savedMouseTargetFilter: Instance?,
		mouseFilterApplied: boolean?,
		_visualKey: string?,
		attrConns: { RBXScriptConnection }?,
	},
} = {}

local renderBound = false

local function clearMouseTargetFilter(state: { player: Player, clone: Model?, savedMouseTargetFilter: Instance?, mouseFilterApplied: boolean? })
	if not Config.SniperViewModelSetMouseTargetFilter then
		return
	end
	if not state.mouseFilterApplied then
		return
	end
	local mouse = state.player:GetMouse()
	if mouse then
		mouse.TargetFilter = state.savedMouseTargetFilter
	end
	state.savedMouseTargetFilter = nil
	state.mouseFilterApplied = false
end

local function applyMouseTargetFilter(state: { player: Player, clone: Model?, savedMouseTargetFilter: Instance?, mouseFilterApplied: boolean? })
	if not Config.SniperViewModelSetMouseTargetFilter then
		return
	end
	local clone = state.clone
	if not clone then
		return
	end
	local mouse = state.player:GetMouse()
	if not mouse then
		return
	end
	if not state.mouseFilterApplied then
		state.savedMouseTargetFilter = mouse.TargetFilter
		state.mouseFilterApplied = true
	end
	mouse.TargetFilter = clone
end

local function destroyClone(state: { clone: Model?, animHandle: SniperViewModelAnimator.AnimatorHandle?, player: Player, pointerSuppressActive: boolean?, savedMouseTargetFilter: Instance?, mouseFilterApplied: boolean? })
	if state.pointerSuppressActive then
		state.pointerSuppressActive = false
		SniperPointerSuppress.pop()
	end
	clearMouseTargetFilter(state)
	if state.animHandle then
		state.animHandle:destroy()
		state.animHandle = nil
	end
	if state.clone then
		camBoneRelCache[state.clone] = nil
		state.clone:Destroy()
		state.clone = nil
	end
	setSniperViewmodelAttr(state.player.Character, false)
end

local function shouldShowViewmodel(state: { tool: Tool, player: Player }): boolean
	local tool = state.tool
	local plr = state.player
	local ch = plr.Character
	if not ch then
		return false
	end
	if Config.SniperVirtualInventoryEnabled then
		if tool.Parent ~= plr:FindFirstChildOfClass("Backpack") then
			return false
		end
		if not SniperLoadoutState.isSniperActive(tool) then
			return false
		end
		return SniperFirstPersonGate.isCameraCloseForFirstPerson(plr)
	end
	local parent = tool.Parent
	if parent ~= ch then
		return false
	end
	return SniperFirstPersonGate.isCameraCloseForFirstPerson(plr)
end

local function updateOne(state: {
	tool: Tool,
	player: Player,
	attachTemplateOverride: string?,
	clone: Model?,
	animHandle: SniperViewModelAnimator.AnimatorHandle?,
	pointerSuppressActive: boolean?,
	savedMouseTargetFilter: Instance?,
	mouseFilterApplied: boolean?,
	_visualKey: string?,
	attrConns: { RBXScriptConnection }?,
})
	if not shouldShowViewmodel(state) then
		destroyClone(state)
		return
	end

	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end

	local folder = findViewModelsFolder()
	if not folder then
		destroyClone(state)
		return
	end

	local resolvedName, template = resolveViewModelTemplateForPlayer(folder, state.player, state.attachTemplateOverride)
	local desiredSkin = SniperViewModelAppearance.normalizeId(state.player:GetAttribute(SniperViewModelAppearance.AttributeSkinId))
	local overrideKey = state.attachTemplateOverride or ""
	local visualKey = resolvedName .. "\0" .. desiredSkin .. "\0" .. overrideKey

	if not template then
		if not warnedMissingTemplate then
			warnedMissingTemplate = true
			warn(
				("[Sniper] ViewModel: no template Model under ReplicatedStorage.%s (set attribute %s, Config.SniperViewModelName, or add a Model child)."):format(
					Config.ViewModelsFolderName or "ViewModels",
					SniperViewModelAppearance.AttributeViewModelTemplateId
				)
			)
		end
		destroyClone(state)
		return
	end

	if state.clone then
		if not state.clone.Parent or state._visualKey ~= visualKey then
			destroyClone(state)
		end
	end

	if not state.clone or not state.clone.Parent then
		destroyClone(state)
		local clone = template:Clone()
		clone.Name = "SniperViewModelActive"
		if not prepareClone(clone, desiredSkin) then
			clone:Destroy()
			return
		end
		state._visualKey = visualKey
		warnIfViewmodelNotFacingWorldZ(clone, resolvedName)
		if Config.SniperViewModelPivotUsesCameraBone ~= false then
			local bn = Config.SniperViewModelCameraBoneName or "CameraBone"
			local b = clone:FindFirstChild(bn, true)
			if b and b:IsA("BasePart") then
				camBoneRelCache[clone] = clone:GetPivot():ToObjectSpace(b.CFrame)
			end
		end
		clone.Parent = cam
		state.clone = clone
		if not state.pointerSuppressActive then
			state.pointerSuppressActive = true
			SniperPointerSuppress.push()
		end
		state.animHandle = SniperViewModelAnimator.attachToClone(clone, state.player)
		if SniperViewModelAnimator.hasConfiguredAnimations() and not state.animHandle then
			RigHelper.applyStaticAnchors(clone)
		end
	end

	setSniperViewmodelAttr(state.player.Character, true)
	local ch = state.player.Character
	if ch then
		suppressWorldArmsForSniperViewmodel(ch)
	end

	local offset = Config.SniperViewModelCameraCFrame or CFrame.new(0.1, -0.2, -0.75)
	if state.animHandle then
		state.animHandle:step(cam, offset)
	else
		state.clone:PivotTo(cam.CFrame * offset)
	end
	applyMouseTargetFilter(state)
end

local function tickAll()
	for tool, state in pairs(states) do
		if not tool.Parent then
			destroyClone(state)
			states[tool] = nil
		else
			updateOne(state)
		end
	end
	if next(states) == nil then
		pcall(function()
			RunService:UnbindFromRenderStep(RENDER_STEP_NAME)
		end)
		renderBound = false
	end
end

local function bindRenderStep()
	if renderBound then
		return
	end
	renderBound = true
	local priority = Enum.RenderPriority.Camera.Value + 1
	local okLast, lastVal = pcall(function()
		return Enum.RenderPriority.Last.Value
	end)
	if okLast and type(lastVal) == "number" then
		-- Run before sniper crosshair (Last) so clone teardown + pointer pop happen before crosshair hide pop in the same frame.
		priority = math.max(Enum.RenderPriority.Camera.Value + 1, lastVal - 1)
	end
	RunService:BindToRenderStep(RENDER_STEP_NAME, priority, tickAll)
end

local ViewModelClient = {}

-- World CFrame of a named BasePart on the active viewmodel clone (camera-parented), if visible this frame.
function ViewModelClient.getViewModelPartWorldCFrame(tool: Tool, partName: string): CFrame?
	if partName == nil or partName == "" then
		return nil
	end
	local state = states[tool]
	if not state or not state.clone or state.clone.Parent == nil then
		return nil
	end
	if not shouldShowViewmodel(state) then
		return nil
	end
	local p = SniperWeaponPartResolve.findFirstBasePartNamed(state.clone, partName)
	if p then
		return p.CFrame
	end
	return nil
end

function ViewModelClient.getViewModelPart(tool: Tool, partName: string): BasePart?
	if partName == nil or partName == "" then
		return nil
	end
	local state = states[tool]
	if not state or not state.clone or state.clone.Parent == nil then
		return nil
	end
	if not shouldShowViewmodel(state) then
		return nil
	end
	return SniperWeaponPartResolve.findFirstBasePartNamed(state.clone, partName)
end

-- Backward-compatible alias: fire origin uses FireOriginPartName.
function ViewModelClient.getViewModelBarrelWorldCFrame(tool: Tool): CFrame?
	return ViewModelClient.getViewModelPartWorldCFrame(tool, Config.FireOriginPartName or "Barrel")
end

-- Prepared clone for another client’s camera (e.g. death spectate): same mesh/strip/anchors as local viewmodel, no tool state.
-- Same pivot rule as the equipped viewmodel (CameraBone at camera * offset when enabled).
function ViewModelClient.solveViewmodelWorldPivot(clone: Model, camCf: CFrame, offset: CFrame): CFrame
	return solveViewmodelWorldPivot(clone, camCf, offset)
end

-- viewModelTemplateId: ReplicatedStorage ViewModels child Model name, or nil to use Config / first Model. skinId: optional cosmetic under template.Skins.
function ViewModelClient.createSpectatorViewModelClone(viewModelTemplateId: string?, skinId: string?): Model?
	local folder = findViewModelsFolder()
	if not folder then
		return nil
	end
	local resolvedName, template = resolveViewModelTemplateExplicit(folder, viewModelTemplateId)
	if not template then
		return nil
	end
	local skin = SniperViewModelAppearance.normalizeId(skinId)
	local clone = template:Clone()
	clone.Name = "SniperViewModelSpectator"
	if not prepareClone(clone, skin) then
		clone:Destroy()
		return nil
	end
	if Config.SniperViewModelPivotUsesCameraBone ~= false then
		local bn = Config.SniperViewModelCameraBoneName or "CameraBone"
		local b = clone:FindFirstChild(bn, true)
		if b and b:IsA("BasePart") then
			camBoneRelCache[clone] = clone:GetPivot():ToObjectSpace(b.CFrame)
		end
	end
	warnIfViewmodelNotFacingWorldZ(clone, resolvedName)
	return clone
end

function ViewModelClient.forgetViewmodelClone(clone: Model?)
	if clone then
		camBoneRelCache[clone] = nil
	end
end

-- viewModelName: optional Studio template name override (highest priority). Otherwise Player attributes + Config + first ViewModels child.
function ViewModelClient.attach(tool: Tool, player: Player, viewModelName: string?)
	if tool:GetAttribute("_SniperViewModelAttached") then
		return
	end
	tool:SetAttribute("_SniperViewModelAttached", true)

	local override: string? = nil
	if type(viewModelName) == "string" and viewModelName ~= "" then
		override = viewModelName
	end

	local state = {
		tool = tool,
		player = player,
		attachTemplateOverride = override,
		clone = nil,
		animHandle = nil,
		pointerSuppressActive = false,
		savedMouseTargetFilter = nil,
		mouseFilterApplied = false,
		_visualKey = nil,
		attrConns = {},
	}
	states[tool] = state

	local function invalidateVisualKey()
		state._visualKey = nil
	end
	table.insert(state.attrConns, player:GetAttributeChangedSignal(SniperViewModelAppearance.AttributeSkinId):Connect(invalidateVisualKey))
	table.insert(state.attrConns, player:GetAttributeChangedSignal(SniperViewModelAppearance.AttributeViewModelTemplateId):Connect(invalidateVisualKey))

	bindRenderStep()

	tool.Destroying:Connect(function()
		if state.attrConns then
			for _, c in ipairs(state.attrConns) do
				pcall(function()
					c:Disconnect()
				end)
			end
			state.attrConns = nil
		end
		destroyClone(state)
		states[tool] = nil
		if next(states) == nil then
			pcall(function()
				RunService:UnbindFromRenderStep(RENDER_STEP_NAME)
			end)
			renderBound = false
		end
	end)
end

return ViewModelClient
