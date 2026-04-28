local Config = require(script.Parent.Config)
local SniperViewModelAppearance = require(script.Parent.SniperViewModelAppearance)

export type SkinAnimatorHandle = {
	step: (self: SkinAnimatorHandle, dt: number) -> (),
	destroy: (self: SkinAnimatorHandle) -> (),
}

type Entry = {
	texture: Texture,
	baseU: number,
	baseV: number,
}

type AnimGroup = {
	entries: { Entry },
	speedU: number,
	speedV: number,
	enabled: boolean,
	sharedU: number,
	sharedV: number,
}

local SniperViewModelSkinAnimator = {}

local Handle = {}
Handle.__index = Handle

local function parseFiniteNumber(value: any): number?
	if type(value) ~= "number" then
		return nil
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	return value
end

local function mountHasTextureAnimConfig(mount: BasePart): boolean
	local a = SniperViewModelAppearance
	return mount:GetAttribute(a.SkinTextureAnimAttributeEnabled) ~= nil
		or mount:GetAttribute(a.SkinTextureAnimAttributeSpeedU) ~= nil
		or mount:GetAttribute(a.SkinTextureAnimAttributeSpeedV) ~= nil
end

-- Sync mode: all attrs on the same BasePart (Gun/<Layer>Skin, set from <Layer>Part in template).
local function shouldAnimateFromMount(
	mount: BasePart,
	defaultSpeedU: number,
	defaultSpeedV: number
): (boolean, number, number)
	local a = SniperViewModelAppearance
	local speedU = parseFiniteNumber(mount:GetAttribute(a.SkinTextureAnimAttributeSpeedU)) or defaultSpeedU
	local speedV = parseFiniteNumber(mount:GetAttribute(a.SkinTextureAnimAttributeSpeedV)) or defaultSpeedV
	local explicitEnabled = mount:GetAttribute(a.SkinTextureAnimAttributeEnabled)
	if type(explicitEnabled) == "boolean" then
		return explicitEnabled, speedU, speedV
	end
	local hasSpeedAttr = mount:GetAttribute(a.SkinTextureAnimAttributeSpeedU) ~= nil
		or mount:GetAttribute(a.SkinTextureAnimAttributeSpeedV) ~= nil
	return hasSpeedAttr, speedU, speedV
end

-- Legacy: attrs on each Texture (only used when the mount has no *Part-driven config).
local function shouldAnimateFromTexture(
	texture: Texture,
	defaultSpeedU: number,
	defaultSpeedV: number
): (boolean, number, number)
	local a = SniperViewModelAppearance
	local speedU = parseFiniteNumber(texture:GetAttribute(a.SkinTextureAnimAttributeSpeedU)) or defaultSpeedU
	local speedV = parseFiniteNumber(texture:GetAttribute(a.SkinTextureAnimAttributeSpeedV)) or defaultSpeedV
	local explicitEnabled = texture:GetAttribute(a.SkinTextureAnimAttributeEnabled)
	if type(explicitEnabled) == "boolean" then
		return explicitEnabled, speedU, speedV
	end
	local hasSpeedAttr = texture:GetAttribute(a.SkinTextureAnimAttributeSpeedU) ~= nil
		or texture:GetAttribute(a.SkinTextureAnimAttributeSpeedV) ~= nil
	return hasSpeedAttr, speedU, speedV
end

local function buildGroups(clone: Model): { AnimGroup }
	local defaultSpeedU = parseFiniteNumber(Config.SniperViewModelSkinAnimDefaultSpeedU) or 0
	local defaultSpeedV = parseFiniteNumber(Config.SniperViewModelSkinAnimDefaultSpeedV) or 0

	-- All Textures on the same mount *Skin share one scroll if that BasePart has Animation / Speed attrs (from <Layer>Part in skin).
	local mountEntryLists: { [BasePart]: { Entry } } = {}
	local legacyOneTexture: { { texture: Texture, baseU: number, baseV: number, parent: BasePart } } = {}

	for _, d in ipairs(clone:GetDescendants()) do
		if not d:IsA("Texture") or d:GetAttribute(SniperViewModelAppearance.SkinSurfaceAssetAttribute) ~= true then
			continue
		end
		local parent = d.Parent
		if not parent or not parent:IsA("BasePart") then
			continue
		end
		local mount = parent :: BasePart
		local e: Entry = { texture = d, baseU = d.OffsetStudsU, baseV = d.OffsetStudsV }
		if mountHasTextureAnimConfig(mount) then
			local list = mountEntryLists[mount]
			if not list then
				list = {}
				mountEntryLists[mount] = list
			end
			table.insert(list, e)
		else
			table.insert(legacyOneTexture, { texture = d, baseU = e.baseU, baseV = e.baseV, parent = mount })
		end
	end

	local groups: { AnimGroup } = {}

	for mount, entries in mountEntryLists do
		if #entries == 0 then
			continue
		end
		local enabled, speedU, speedV = shouldAnimateFromMount(mount, defaultSpeedU, defaultSpeedV)
		if not enabled or (math.abs(speedU) <= 1e-6 and math.abs(speedV) <= 1e-6) then
			continue
		end
		table.insert(groups, {
			entries = entries,
			speedU = speedU,
			speedV = speedV,
			enabled = true,
			sharedU = 0,
			sharedV = 0,
		} :: any)
	end

	for _, row in legacyOneTexture do
		local enabled, speedU, speedV = shouldAnimateFromTexture(row.texture, defaultSpeedU, defaultSpeedV)
		if not enabled or (math.abs(speedU) <= 1e-6 and math.abs(speedV) <= 1e-6) then
			continue
		end
		table.insert(groups, {
			entries = { { texture = row.texture, baseU = row.baseU, baseV = row.baseV } },
			speedU = speedU,
			speedV = speedV,
			enabled = true,
			sharedU = 0,
			sharedV = 0,
		} :: any)
	end

	return groups
end

function Handle:step(dt: number)
	if self._gone then
		return
	end
	if type(dt) ~= "number" or dt <= 0 then
		return
	end
	for _, group in self._groups :: { AnimGroup } do
		if not group.enabled then
			continue
		end
		group.sharedU += group.speedU * dt
		group.sharedV += group.speedV * dt
		for _, e in group.entries do
			local t = e.texture
			if t.Parent then
				t.OffsetStudsU = e.baseU + group.sharedU
				t.OffsetStudsV = e.baseV + group.sharedV
			end
		end
	end
end

function Handle:destroy()
	if self._gone then
		return
	end
	self._gone = true
	self._groups = {}
end

function SniperViewModelSkinAnimator.attachToClone(clone: Model): SkinAnimatorHandle?
	if Config.SniperViewModelSkinTextureAnimationEnabled == false then
		return nil
	end
	local groups = buildGroups(clone)
	if #groups == 0 then
		return nil
	end
	local self = setmetatable({
		_gone = false,
		_groups = groups,
	}, Handle)
	return (self :: any) :: SkinAnimatorHandle
end

return SniperViewModelSkinAnimator
