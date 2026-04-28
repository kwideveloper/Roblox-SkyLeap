-- Viewmodel layout: root Model (e.g. Sniper) contains CameraBone, arms rig, Model "Gun", and optional Folder "Skins".
--
-- Folder skins (two layouts):
--   Flat: Skins/<SkinName>/<Layer>Skin (BasePart/Union/Model) e.g. BodySkin, BarrelSkin — textures/appearance from that instance.
--   Nested: Skins/<SkinName>/<Layer>/<Layer>Skin/ … (legacy) — same as before.
--   Copy Appearance + UsePartColor from template *Skin to Gun.<Layer>Skin; clone Texture/Decal under template into gun mount.
--   Optional animation attrs on layer Folder, or <Layer>Part, or skin root Folder — see resolveSkinAnimConfigSource (copied to Gun.<Layer>Skin).
-- Legacy: same <Layer> folder with Decals|Textures at any depth but no *Skin part → only surfaces are cloned (old layout).
-- Legacy: Skins/<SkinName> as a Model → clone under Gun mount; base Gun meshes hidden (Motor6D targets stay on Gun).

local Config = require(script.Parent.Config)
local ContentProvider = game:GetService("ContentProvider")

local SniperViewModelAppearance = {}

SniperViewModelAppearance.GunModelName = "Gun"
SniperViewModelAppearance.SkinsFolderName = "Skins"
SniperViewModelAppearance.SkinVisualModelName = "_SkyLeapSkinVisual"
SniperViewModelAppearance.HiddenForSkinAttribute = "_SkyLeapGunPartHiddenForSkin"
SniperViewModelAppearance.SkinSurfaceAssetAttribute = "_SkyLeapSkinSurfaceAsset"
-- Layer folder "Barrel" under Skins/<Skin>/ maps to direct Gun child "Barrel" .. SkinLayerSuffix
SniperViewModelAppearance.SkinLayerSuffix = "Skin"
-- Skins/<Skin>/<Layer>/BodyPart (etc.): template instance holds texture-scroll settings applied to Gun/<Layer>Skin.
SniperViewModelAppearance.SkinLayerPartSuffix = "Part"
SniperViewModelAppearance.SkinTextureAnimAttributeEnabled = "Animation"
SniperViewModelAppearance.SkinTextureAnimAttributeSpeedU = "AnimationSpeedU"
SniperViewModelAppearance.SkinTextureAnimAttributeSpeedV = "AnimationSpeedV"

-- Replicated on Player from server (profile → attributes on join). UI can change via future Remote + server set.
SniperViewModelAppearance.AttributeViewModelTemplateId = "SkyLeapSniperViewModelId"
SniperViewModelAppearance.AttributeSkinId = "SkyLeapSniperSkinId"

local warnedMissingGun = false
local warnedMissingSkin = false
local warnedMissingSkinSlot = false
local warnedMissingGunPiece = false

local function dbg(fmt: string, ...): ()
	if Config.SniperViewModelSkinDebug ~= true then
		return
	end
	print(("[SniperSkin] " .. fmt):format(...))
end

local function instancePath(inst: Instance?): string
	if not inst then
		return "<nil>"
	end
	local ok, p = pcall(function()
		return inst:GetFullName()
	end)
	if ok and type(p) == "string" then
		return p
	end
	return inst.Name
end

local function describePart(p: BasePart?): string
	if not p then
		return "<nil>"
	end
	local material, reflectance, transparency, color
	pcall(function()
		material = tostring(p.Material)
	end)
	pcall(function()
		reflectance = p.Reflectance
	end)
	pcall(function()
		transparency = p.Transparency
	end)
	pcall(function()
		color = tostring(p.Color)
	end)
	return string.format(
		"%s[%s] Material=%s Reflectance=%s Transparency=%s Color=%s",
		p.Name,
		p.ClassName,
		tostring(material),
		tostring(reflectance),
		tostring(transparency),
		tostring(color)
	)
end

local function describeAsset(a: Instance): string
	local id: string? = nil
	if a:IsA("Texture") or a:IsA("Decal") then
		id = (a :: any).Texture
	elseif a:IsA("SurfaceAppearance") then
		id = (a :: any).ColorMap
	end
	return string.format("%s[%s] id=%s", a.Name, a.ClassName, tostring(id))
end

-- Legacy Studio URLs sometimes stay as http(s)://www.roblox.com/asset/?id=... ; runtime prefers rbxassetid:// for reliable streaming.
local function normalizeRobloxContentUri(s: string): string
	if type(s) ~= "string" or s == "" then
		return s
	end
	local lower = string.lower(s)
	if string.find(lower, "rbxassetid://", 1, true) or string.find(lower, "rbxthumb://", 1, true) then
		return s
	end
	if string.find(lower, "rbxasset://", 1, true) then
		return s
	end
	local id = string.match(s, "[?&]id=(%d+)")
	if id then
		return "rbxassetid://" .. id
	end
	return s
end

local function textureOnUnionShouldBecomeDecal(textureParent: BasePart, src: Texture, layerHasScrollAnimConfig: boolean): boolean
	if layerHasScrollAnimConfig then
		dbg("    · keeping Texture on Union (layer/skin has Animation attrs — Decals cannot UV-scroll)")
		return false
	end
	if Config.SniperViewModelSkinPreferDecalOnUnion == false then
		return false
	end
	if not textureParent:IsA("UnionOperation") then
		return false
	end
	local a = SniperViewModelAppearance
	local speedU = src:GetAttribute(a.SkinTextureAnimAttributeSpeedU)
	local speedV = src:GetAttribute(a.SkinTextureAnimAttributeSpeedV)
	local wantsScroll = src:GetAttribute(a.SkinTextureAnimAttributeEnabled) == true
		or (type(speedU) == "number" and math.abs(speedU) > 1e-6)
		or (type(speedV) == "number" and math.abs(speedV) > 1e-6)
	if wantsScroll and Config.SniperViewModelSkinTextureAnimationEnabled == true then
		dbg(
			"    · keeping Texture on Union (animation on texture); tiled UV scroll is unreliable on CSG — use MeshPart/Part for *Skin mount if it does not show"
		)
		return false
	end
	return true
end

local function decalFromTextureTemplate(src: Texture): Decal
	local d = Instance.new("Decal")
	d.Name = src.Name
	for _, prop in ipairs({
		"Face",
		"Texture",
		"Transparency",
		"Color3",
		"ZIndex",
		"LightInfluence",
		"LocalTransparencyModifier",
	}) do
		pcall(function()
			(d :: any)[prop] = (src :: any)[prop]
		end)
	end
	for n, v in src:GetAttributes() do
		d:SetAttribute(n, v)
	end
	return d
end

local function instantiateSkinSurfaceFromTemplate(asset: Instance, textureParent: BasePart, layerHasScrollAnimConfig: boolean): Instance
	if asset:IsA("Texture") and textureOnUnionShouldBecomeDecal(textureParent, asset :: Texture, layerHasScrollAnimConfig == true) then
		dbg("    · applying as Decal (Union CSG — Texture tiled UVs often do not render on unions)")
		return decalFromTextureTemplate(asset :: Texture)
	end
	if asset:IsA("Texture") or asset:IsA("Decal") then
		return asset:Clone()
	end
	return asset:Clone()
end

local function applyNormalizedContentToClonedSurface(inst: Instance)
	if inst:IsA("Texture") or inst:IsA("Decal") then
		local t = (inst :: any).Texture
		if type(t) == "string" and t ~= "" then
			local n = normalizeRobloxContentUri(t)
			if n ~= t then
				(inst :: any).Texture = n
				dbg("    · normalized %s.Texture: %s -> %s", inst.Name, t, n)
			end
		end
	elseif inst:IsA("SurfaceAppearance") then
		local sa = inst :: SurfaceAppearance
		for _, prop in ipairs({ "ColorMap", "NormalMap", "RoughnessMap", "MetalnessMap" }) do
			pcall(function()
				local v = (sa :: any)[prop]
				if type(v) == "string" and v ~= "" then
					local n = normalizeRobloxContentUri(v)
					if n ~= v then
						(sa :: any)[prop] = n
						dbg("    · normalized SurfaceAppearance.%s", prop)
					end
				end
			end)
		end
	end
end

local function trim(s: string): string
	s = string.gsub(s, "^%s+", "")
	s = string.gsub(s, "%s+$", "")
	return s
end

function SniperViewModelAppearance.normalizeId(v: any): string
	if type(v) ~= "string" then
		return ""
	end
	return trim(v)
end

function SniperViewModelAppearance.findSkinRootUnderSkins(skinsFolder: Folder, skinId: string): Instance?
	if not skinsFolder or not skinsFolder:IsA("Folder") or skinId == "" then
		return nil
	end
	local direct = skinsFolder:FindFirstChild(skinId)
	if direct then
		return direct
	end
	local lower = string.lower(skinId)
	for _, c in ipairs(skinsFolder:GetChildren()) do
		if string.lower(c.Name) == lower then
			return c
		end
	end
	return nil
end

local function applyPartPresentationForSubtree(root: Instance)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = 0
			if Config.SniperViewModelCastShadow == false then
				d.CastShadow = false
			end
		end
	end
end

-- Skins/<Skin>/Body/... → Gun:FindFirstChild("Body" .. SkinLayerSuffix), e.g. BodySkin
local function findGunSkinMount(gun: Model, layerFolderName: string): Instance?
	local mountName = layerFolderName .. SniperViewModelAppearance.SkinLayerSuffix
	local direct = gun:FindFirstChild(mountName)
	if direct then
		return direct
	end
	local lower = string.lower(mountName)
	for _, c in ipairs(gun:GetChildren()) do
		if string.lower(c.Name) == lower then
			return c
		end
	end
	return nil
end

-- Part that receives child Textures, Decals, and SurfaceAppearance (prefer visible mesh on the real Gun).
local function resolveSkinTextureParent(mount: Instance): BasePart?
	if mount:IsA("BasePart") then
		return mount
	end
	if mount:IsA("Model") then
		for _, c in mount:GetChildren() do
			if c:IsA("UnionOperation") or c:IsA("MeshPart") then
				return c
			end
		end
		for _, c in mount:GetDescendants() do
			if c:IsA("UnionOperation") or c:IsA("MeshPart") then
				return c
			end
		end
		if mount.PrimaryPart and mount.PrimaryPart:IsA("BasePart") then
			return mount.PrimaryPart
		end
		local p = mount:FindFirstChildWhichIsA("BasePart", true)
		if p and p:IsA("BasePart") then
			return p
		end
		return nil
	end
	if mount:IsA("Folder") then
		local p = mount:FindFirstChildWhichIsA("BasePart", true)
		if p and p:IsA("BasePart") then
			return p
		end
	end
	return nil
end

local function clearTextureAnimAttributesOnSkinMounts(gun: Model)
	local a = SniperViewModelAppearance
	for _, c in ipairs(gun:GetChildren()) do
		local m = c.Name
		if string.len(m) >= 4 and string.sub(m, -4) == "Skin" then
			local p = resolveSkinTextureParent(c)
			if p then
				p:SetAttribute(a.SkinTextureAnimAttributeEnabled, nil)
				p:SetAttribute(a.SkinTextureAnimAttributeSpeedU, nil)
				p:SetAttribute(a.SkinTextureAnimAttributeSpeedV, nil)
			end
		end
	end
end

local function clearGunSkinState(gun: Model)
	local old = gun:FindFirstChild(SniperViewModelAppearance.SkinVisualModelName)
	if old then
		old:Destroy()
	end
	clearTextureAnimAttributesOnSkinMounts(gun)
	for _, d in ipairs(gun:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute(SniperViewModelAppearance.HiddenForSkinAttribute) == true then
			d.LocalTransparencyModifier = 0
			d:SetAttribute(SniperViewModelAppearance.HiddenForSkinAttribute, nil)
		end
		if
			(d:IsA("Decal") or d:IsA("Texture") or d:IsA("SurfaceAppearance"))
			and d:GetAttribute(SniperViewModelAppearance.SkinSurfaceAssetAttribute) == true
		then
			d:Destroy()
		end
	end
end

local function collectDecalsAndTextures(container: Instance): { Instance }
	local out: { Instance } = {}
	for _, d in ipairs(container:GetDescendants()) do
		if d:IsA("Decal") or d:IsA("Texture") then
			table.insert(out, d)
		end
	end
	return out
end

-- Only surfaces under a skin block (e.g. Union "BodySkin"), not the block itself.
local function collectDecalsAndTexturesUnderSkinBlock(skinBlock: Instance): { Instance }
	local out: { Instance } = {}
	for _, d in ipairs(skinBlock:GetDescendants()) do
		if d:IsA("Decal") or d:IsA("Texture") then
			table.insert(out, d)
		end
	end
	return out
end

local function collectSurfaceAppearancesUnderSkinBlock(skinBlock: Instance): { SurfaceAppearance }
	local out: { SurfaceAppearance } = {}
	for _, d in ipairs(skinBlock:GetDescendants()) do
		if d:IsA("SurfaceAppearance") then
			table.insert(out, d)
		end
	end
	return out
end

local function findChildIgnoreCase(parent: Instance, name: string): Instance?
	if name == "" then
		return nil
	end
	local want = string.lower(name)
	for _, c in ipairs(parent:GetChildren()) do
		if string.lower(c.Name) == want then
			return c
		end
	end
	return nil
end

-- <Layer>Part: under nested layer folder, or sibling under skin root when using flat *Skin layout.
local function findLayerAnimConfigPart(skinRoot: Folder, nestedLayerFolder: Instance?, layerName: string): Instance?
	local n = layerName .. SniperViewModelAppearance.SkinLayerPartSuffix
	if nestedLayerFolder and nestedLayerFolder:IsA("Folder") then
		local lf = nestedLayerFolder :: Folder
		return lf:FindFirstChild(n) or findChildIgnoreCase(lf, n)
	end
	return skinRoot:FindFirstChild(n) or findChildIgnoreCase(skinRoot, n)
end

local function instanceDefinesSkinAnimAttrs(inst: Instance): boolean
	local a = SniperViewModelAppearance
	return inst:GetAttribute(a.SkinTextureAnimAttributeEnabled) ~= nil
		or inst:GetAttribute(a.SkinTextureAnimAttributeSpeedU) ~= nil
		or inst:GetAttribute(a.SkinTextureAnimAttributeSpeedV) ~= nil
end

-- Priority: layer attr root (nested Body folder OR flat BodySkin part) → <Layer>Part → skin root Folder.
local function resolveSkinAnimConfigSource(
	layerAttrRoot: Instance,
	layerName: string,
	skinRootFolder: Folder,
	nestedLayerFolder: Instance?
)
	if instanceDefinesSkinAnimAttrs(layerAttrRoot) then
		return layerAttrRoot
	end
	local partInst = findLayerAnimConfigPart(skinRootFolder, nestedLayerFolder, layerName)
	if partInst and instanceDefinesSkinAnimAttrs(partInst) then
		return partInst
	end
	if instanceDefinesSkinAnimAttrs(skinRootFolder) then
		return skinRootFolder
	end
	return nil
end

local function copySkinLayerAnimConfigFromPartTemplate(template: Instance, targetBase: BasePart)
	local a = SniperViewModelAppearance
	local e = template:GetAttribute(a.SkinTextureAnimAttributeEnabled)
	local u = template:GetAttribute(a.SkinTextureAnimAttributeSpeedU)
	local v2 = template:GetAttribute(a.SkinTextureAnimAttributeSpeedV)
	if e ~= nil then
		targetBase:SetAttribute(a.SkinTextureAnimAttributeEnabled, e)
	end
	if u ~= nil then
		targetBase:SetAttribute(a.SkinTextureAnimAttributeSpeedU, u)
	end
	if v2 ~= nil then
		targetBase:SetAttribute(a.SkinTextureAnimAttributeSpeedV, v2)
	end
end

local function layerNameFromFlatSkinTemplateName(name: string): string?
	if string.len(name) < 5 then
		return nil
	end
	if string.lower(string.sub(name, -4)) ~= "skin" then
		return nil
	end
	return string.sub(name, 1, -5)
end

-- Nested: layer folder contains *Skin. Flat: layerRoot is BodySkin / BarrelSkin (BasePart or Model) under skin root.
local function findLayerSkinBlock(layerRoot: Instance, layerName: string): Instance?
	if layerRoot:IsA("BasePart") or layerRoot:IsA("Model") then
		local want = string.lower(layerName .. SniperViewModelAppearance.SkinLayerSuffix)
		if string.lower(layerRoot.Name) == want then
			return layerRoot
		end
		return nil
	end
	if not layerRoot:IsA("Folder") then
		return nil
	end
	local exactName = layerName .. SniperViewModelAppearance.SkinLayerSuffix
	local a = layerRoot:FindFirstChild(exactName) or findChildIgnoreCase(layerRoot, exactName)
	if a and (a:IsA("Model") or a:IsA("BasePart")) then
		return a
	end
	for _, c in ipairs(layerRoot:GetChildren()) do
		if c:IsA("Model") or c:IsA("BasePart") then
			local n = c.Name
			if string.len(n) >= 4 and string.sub(n, -4) == "Skin" then
				return c
			end
		end
	end
	return nil
end

local function resolveSkinBlockBase(skinBlock: Instance): BasePart?
	if skinBlock:IsA("BasePart") then
		return skinBlock
	end
	if skinBlock:IsA("Model") then
		if skinBlock.PrimaryPart and skinBlock.PrimaryPart:IsA("BasePart") then
			return skinBlock.PrimaryPart
		end
		local p = skinBlock:FindFirstChildWhichIsA("BasePart", true)
		if p and p:IsA("BasePart") then
			return p
		end
	end
	return nil
end

-- Studio “Appearance” on the skin template Union → each BasePart in the real Gun *Skin mount (Model or single part).
-- pcall: MeshPart/Union/Part differ; missing props are skipped.
local SKIN_APPEARANCE_PROPS: { string } = {
	"BrickColor",
	"CastShadow",
	"Color",
	"DoubleSided",
	"Material",
	"MaterialVariant",
	"Reflectance",
	"RenderFidelity",
	"SmoothingAngle",
	"Transparency",
	"UsePartColor",
}

local function getBasePartsInSkinMount(mount: Instance): { BasePart }
	if mount:IsA("BasePart") then
		return { mount }
	end
	if mount:IsA("Model") or mount:IsA("Folder") then
		local t: { BasePart } = {}
		for _, d in mount:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(t, d)
			end
		end
		if #t == 0 and mount:IsA("Model") and mount.PrimaryPart and mount.PrimaryPart:IsA("BasePart") then
			return { mount.PrimaryPart }
		end
		return t
	end
	return {}
end

-- Threshold above which the template Transparency is treated as a Studio authoring hint (invisible in editor)
-- and NOT copied. Below it the value is applied normally (so 0, 0.5, etc. are respected).
local SKIN_TEMPLATE_INVISIBLE_TRANSPARENCY_THRESHOLD = 0.95

local function copySkinVisualPropertiesToTarget(source: BasePart, target: BasePart)
	for _, prop in ipairs(SKIN_APPEARANCE_PROPS) do
		if prop == "Transparency" then
			local ok, val = pcall(function()
				return (source :: any).Transparency
			end)
			if ok and type(val) == "number" and val < SKIN_TEMPLATE_INVISIBLE_TRANSPARENCY_THRESHOLD then
				pcall(function()
					(target :: any).Transparency = val
				end)
			end
		else
			pcall(function()
				(target :: any)[prop] = (source :: any)[prop]
			end)
		end
	end
	if Config.SniperViewModelCastShadow == false then
		target.CastShadow = false
	end
end

-- SurfaceAppearance on the real gun part overrides any Texture child. Remove any non-skin SurfaceAppearance so cloned Textures can be seen.
local function removePreexistingSurfaceAppearances(parts: { BasePart })
	for _, p in parts do
		for _, c in p:GetChildren() do
			if
				c:IsA("SurfaceAppearance")
				and c:GetAttribute(SniperViewModelAppearance.SkinSurfaceAssetAttribute) ~= true
			then
				dbg("  • removing preexisting SurfaceAppearance on %s -> %s", p.Name, describeAsset(c))
				c:Destroy()
			end
		end
	end
end

-- Base viewmodel Gun.*Skin often ships with author Textures/Decals/SurfaceAppearance. Those stay on the clone and stack
-- with skin clones (same Face / empty id), so the skin never reads as "loaded". Strip only direct children not from this system.
local function clearNonSkinSurfaceGraphicsDirectChildren(part: BasePart)
	for _, c in part:GetChildren() do
		if
			(c:IsA("Texture") or c:IsA("Decal") or c:IsA("SurfaceAppearance"))
			and c:GetAttribute(SniperViewModelAppearance.SkinSurfaceAssetAttribute) ~= true
		then
			dbg("  • removing base mount surface %s from %s", describeAsset(c), part.Name)
			c:Destroy()
		end
	end
end

local SKIN_TEXTURE_DEFAULT_STUDS_PER_TILE = 10

local function finalizeClonedSkinTextureOrDecal(inst: Instance)
	if inst:IsA("Texture") then
		local t = inst :: Texture
		if t.StudsPerTileU <= 0 then
			t.StudsPerTileU = SKIN_TEXTURE_DEFAULT_STUDS_PER_TILE
			dbg("    · fixed %s.StudsPerTileU (was <=0) -> %d", t.Name, SKIN_TEXTURE_DEFAULT_STUDS_PER_TILE)
		end
		if t.StudsPerTileV <= 0 then
			t.StudsPerTileV = SKIN_TEXTURE_DEFAULT_STUDS_PER_TILE
			dbg("    · fixed %s.StudsPerTileV (was <=0) -> %d", t.Name, SKIN_TEXTURE_DEFAULT_STUDS_PER_TILE)
		end
	end
end

local function preferPreciseUnionRender(part: BasePart)
	if not part:IsA("UnionOperation") then
		return
	end
	pcall(function()
		(part :: UnionOperation).RenderFidelity = Enum.RenderFidelity.Precise
	end)
end

local function copySkinVisualFromTemplateToMount(source: BasePart, mount: Instance)
	local parts = getBasePartsInSkinMount(mount)
	dbg("  • copying appearance from %s to %d part(s) under %s", describePart(source), #parts, instancePath(mount))
	removePreexistingSurfaceAppearances(parts)
	for _, p in parts do
		dbg("    - before: %s", describePart(p))
		copySkinVisualPropertiesToTarget(source, p)
		dbg("    -  after: %s", describePart(p))
	end
end

local function preloadSkinSurfaceAssets(gun: Model)
	local list: { Instance } = {}
	for _, d in ipairs(gun:GetDescendants()) do
		if
			(d:IsA("Texture") or d:IsA("Decal") or d:IsA("SurfaceAppearance"))
			and d:GetAttribute(SniperViewModelAppearance.SkinSurfaceAssetAttribute) == true
		then
			table.insert(list, d)
		end
	end
	dbg("preloadSkinSurfaceAssets: %d asset(s) flagged for preload", #list)
	if #list == 0 then
		return
	end
	for _, a in list do
		dbg("  - %s under %s", describeAsset(a), instancePath(a.Parent))
	end
	task.defer(function()
		local ok, err = pcall(function()
			ContentProvider:PreloadAsync(list)
		end)
		if ok then
			dbg("PreloadAsync: done (%d asset(s))", #list)
		else
			dbg("PreloadAsync: FAILED -> %s", tostring(err))
		end
	end)
end

local function applyFolderSkinToGun(gun: Model, skinDefinition: Folder): boolean
	local wantedLayers = false
	local appliedLayers = 0

	dbg("applyFolderSkinToGun: skin=%q gun=%s", skinDefinition.Name, instancePath(gun))

	for _, child in ipairs(skinDefinition:GetChildren()) do
		local layerName: string
		local nestedLayerFolder: Instance? = nil
		local layerContentRoot: Instance

		local flatLayer = (child:IsA("BasePart") or child:IsA("Model")) and layerNameFromFlatSkinTemplateName(child.Name) or nil
		if flatLayer and flatLayer ~= "" then
			layerName = flatLayer
			layerContentRoot = child
			nestedLayerFolder = nil
		elseif child:IsA("Folder") and layerNameFromFlatSkinTemplateName(child.Name) == nil then
			layerName = child.Name
			layerContentRoot = child
			nestedLayerFolder = child :: Folder
		else
			continue
		end

		dbg("layer %q: scanning...", layerName)
		local mount = findGunSkinMount(gun, layerName)
		if not mount then
			dbg("  ! no Gun.%q%s mount — skipping layer", layerName, SniperViewModelAppearance.SkinLayerSuffix)
			continue
		end
		dbg("  mount resolved: %s (%s)", instancePath(mount), mount.ClassName)

		local textureParent = resolveSkinTextureParent(mount)
		if not textureParent then
			if not warnedMissingSkinSlot then
				warnedMissingSkinSlot = true
				warn(
					("[Sniper] ViewModel skin: Gun.%q is not a usable skin mount (BasePart / Model with PrimaryPart / Folder with a part). Skipping layer %q."):format(
						mount.Name,
						child.Name
					)
				)
			end
			dbg("  ! no usable BasePart inside mount — skipping layer")
			continue
		end
		dbg("  textureParent resolved: %s", describePart(textureParent))

		local skinBlock = findLayerSkinBlock(layerContentRoot, layerName)
		if skinBlock then
			dbg("  skin block found: %s (%s)", instancePath(skinBlock), skinBlock.ClassName)
			wantedLayers = true
			local underSkin = collectDecalsAndTexturesUnderSkinBlock(skinBlock)
			local underSurface = collectSurfaceAppearancesUnderSkinBlock(skinBlock)
			dbg("    decals/textures: %d, SurfaceAppearance: %d", #underSkin, #underSurface)
			if #underSkin > 0 or #underSurface > 0 then
				clearNonSkinSurfaceGraphicsDirectChildren(textureParent)
			end
			local sourceBase = resolveSkinBlockBase(skinBlock)
			if not sourceBase then
				if not warnedMissingSkinSlot then
					warnedMissingSkinSlot = true
					warn(
						("[Sniper] ViewModel skin: layer %q in skin %q has a skin block %q with no BasePart. Skipping appearance (textures may still apply)."):format(
							layerName,
							skinDefinition.Name,
							skinBlock.Name
						)
					)
				end
				dbg("  ! skin block has no BasePart for appearance copy")
			else
				dbg("  sourceBase for appearance: %s", describePart(sourceBase))
				copySkinVisualFromTemplateToMount(sourceBase, mount)
			end
			local animSourceForScroll = resolveSkinAnimConfigSource(layerContentRoot, layerName, skinDefinition, nestedLayerFolder)
			local layerWantsTextureScroll = animSourceForScroll ~= nil and instanceDefinesSkinAnimAttrs(animSourceForScroll)
			for _, asset in ipairs(underSkin) do
				local cl = instantiateSkinSurfaceFromTemplate(asset, textureParent, layerWantsTextureScroll)
				cl:SetAttribute(SniperViewModelAppearance.SkinSurfaceAssetAttribute, true)
				applyNormalizedContentToClonedSurface(cl)
				if cl:IsA("Texture") then
					finalizeClonedSkinTextureOrDecal(cl)
				end
				cl.Parent = textureParent
				dbg("    + cloned %s -> %s", describeAsset(cl), instancePath(textureParent))
			end
			for _, sa in ipairs(underSurface) do
				local cl = sa:Clone()
				cl:SetAttribute(SniperViewModelAppearance.SkinSurfaceAssetAttribute, true)
				applyNormalizedContentToClonedSurface(cl)
				finalizeClonedSkinTextureOrDecal(cl)
				cl.Parent = textureParent
				dbg("    + cloned %s -> %s", describeAsset(cl), instancePath(textureParent))
			end
			if #underSkin > 0 or #underSurface > 0 then
				preferPreciseUnionRender(textureParent)
			end
			if animSourceForScroll then
				copySkinLayerAnimConfigFromPartTemplate(animSourceForScroll, textureParent)
				dbg("    • anim cfg copied from %s -> %s", instancePath(animSourceForScroll), instancePath(textureParent))
			end
			if sourceBase or #underSkin > 0 or #underSurface > 0 then
				appliedLayers = appliedLayers + 1
			end
		else
			dbg(
				"  (no *Skin block — add %q (flat) or nested folder with *Skin; legacy: loose Textures/Decals in layer folder)",
				layerName .. SniperViewModelAppearance.SkinLayerSuffix
			)
			local assets = collectDecalsAndTextures(layerContentRoot)
			if #assets == 0 then
				dbg(
					"  ! no Textures/Decals under %q — add %s template or loose surfaces in layer folder",
					child.Name,
					layerName .. SniperViewModelAppearance.SkinLayerSuffix
				)
				continue
			end
			wantedLayers = true
			clearNonSkinSurfaceGraphicsDirectChildren(textureParent)
			removePreexistingSurfaceAppearances({ textureParent })
			local animSourceForScrollLegacy =
				resolveSkinAnimConfigSource(layerContentRoot, layerName, skinDefinition, nestedLayerFolder)
			local layerWantsTextureScrollLegacy = animSourceForScrollLegacy ~= nil
				and instanceDefinesSkinAnimAttrs(animSourceForScrollLegacy)
			for _, asset in ipairs(assets) do
				local cl = instantiateSkinSurfaceFromTemplate(asset, textureParent, layerWantsTextureScrollLegacy)
				cl:SetAttribute(SniperViewModelAppearance.SkinSurfaceAssetAttribute, true)
				applyNormalizedContentToClonedSurface(cl)
				if cl:IsA("Texture") then
					finalizeClonedSkinTextureOrDecal(cl)
				end
				cl.Parent = textureParent
				dbg("    + cloned (legacy) %s -> %s", describeAsset(cl), instancePath(textureParent))
			end
			preferPreciseUnionRender(textureParent)
			if animSourceForScrollLegacy then
				copySkinLayerAnimConfigFromPartTemplate(animSourceForScrollLegacy, textureParent)
				dbg("    • anim cfg copied from %s -> %s", instancePath(animSourceForScrollLegacy), instancePath(textureParent))
			end
			appliedLayers = appliedLayers + 1
		end
	end

	dbg("applyFolderSkinToGun done: wantedLayers=%s appliedLayers=%d", tostring(wantedLayers), appliedLayers)

	if wantedLayers and appliedLayers == 0 then
		return false
	end
	preloadSkinSurfaceAssets(gun)
	return true
end

local function applyLegacyModelSkinToGun(gun: Model, skinClone: Model)
	clearGunSkinState(gun)

	for _, d in ipairs(gun:GetDescendants()) do
		if d:IsA("BasePart") then
			d:SetAttribute(SniperViewModelAppearance.HiddenForSkinAttribute, true)
			d.LocalTransparencyModifier = 1
		end
	end

	local mount = gun.PrimaryPart or gun:FindFirstChildWhichIsA("BasePart", true)
	if not mount then
		skinClone:Destroy()
		return false
	end

	skinClone.Name = SniperViewModelAppearance.SkinVisualModelName
	skinClone.Parent = mount
	skinClone:PivotTo(mount.CFrame)
	applyPartPresentationForSubtree(skinClone)
	return true
end

local function destroySkinsFolderIfAny(clone: Model, skinsFolder: Instance?)
	if skinsFolder and skinsFolder:IsA("Folder") and skinsFolder.Parent == clone then
		skinsFolder:Destroy()
	end
end

-- After cloning the full viewmodel: remove Skins from this clone (ReplicatedStorage keeps templates).
-- skinId "" = base Gun only (clears applied surface skins + legacy visual).
function SniperViewModelAppearance.applyGunSkinSwap(clone: Model, skinId: string): boolean
	local skinsFolder = clone:FindFirstChild(SniperViewModelAppearance.SkinsFolderName)
	local gun = clone:FindFirstChild(SniperViewModelAppearance.GunModelName)

	dbg(
		"applyGunSkinSwap: skinId=%q clone=%s gun=%s skins=%s",
		skinId,
		clone.Name,
		gun and gun.Name or "<none>",
		skinsFolder and skinsFolder.Name or "<none>"
	)

	if gun and gun:IsA("Model") then
		clearGunSkinState(gun)
	end

	if skinId == "" then
		dbg("  (no skin requested — base Gun only)")
		destroySkinsFolderIfAny(clone, skinsFolder)
		if not gun or not gun:IsA("Model") then
			return true
		end
		return true
	end

	if not skinsFolder or not skinsFolder:IsA("Folder") then
		if not warnedMissingSkin then
			warnedMissingSkin = true
			warn(
				("[Sniper] ViewModel: skin %q requested but Folder %q is missing."):format(
					skinId,
					SniperViewModelAppearance.SkinsFolderName
				)
			)
		end
		destroySkinsFolderIfAny(clone, skinsFolder)
		return false
	end

	local skinRoot = SniperViewModelAppearance.findSkinRootUnderSkins(skinsFolder, skinId)
	if not skinRoot then
		if not warnedMissingSkin then
			warnedMissingSkin = true
			warn(
				("[Sniper] ViewModel: skin %q not found under %q."):format(
					skinId,
					SniperViewModelAppearance.SkinsFolderName
				)
			)
		end
		destroySkinsFolderIfAny(clone, skinsFolder)
		return false
	end

	if not gun or not gun:IsA("Model") then
		if not warnedMissingGun then
			warnedMissingGun = true
			warn(
				("[Sniper] ViewModel %q: expected a Model %q for skin application."):format(
					clone.Name,
					SniperViewModelAppearance.GunModelName
				)
			)
		end
		destroySkinsFolderIfAny(clone, skinsFolder)
		return false
	end

	local ok = true
	if skinRoot:IsA("Folder") then
		dbg("  skinRoot=%s (Folder layout)", instancePath(skinRoot))
		ok = applyFolderSkinToGun(gun, skinRoot)
	elseif skinRoot:IsA("Model") then
		dbg("  skinRoot=%s (legacy Model layout)", instancePath(skinRoot))
		local legacyClone = skinRoot:Clone()
		destroySkinsFolderIfAny(clone, skinsFolder)
		return applyLegacyModelSkinToGun(gun, legacyClone)
	else
		warn(
			("[Sniper] ViewModel: skin %q must be a Folder (decal layout) or Model (legacy mesh). Got %s."):format(
				skinId,
				skinRoot.ClassName
			)
		)
		ok = false
	end

	if skinsFolder.Parent then
		destroySkinsFolderIfAny(clone, skinsFolder)
	end

	dbg("applyGunSkinSwap result: %s", tostring(ok))
	return ok
end

return SniperViewModelAppearance
