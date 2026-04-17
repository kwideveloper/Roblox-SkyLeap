-- Viewmodel layout: root Model (e.g. Sniper) contains CameraBone, arms rig, base weapon Model "Gun",
-- and optional Folder "Skins" with cosmetic weapon Models. Selected skin is cloned under Gun's mount part
-- and base Gun meshes are hidden so Motor6D / animation targets on Gun stay valid.

local Config = require(script.Parent.Config)

local SniperViewModelAppearance = {}

SniperViewModelAppearance.GunModelName = "Gun"
SniperViewModelAppearance.SkinsFolderName = "Skins"
SniperViewModelAppearance.SkinVisualModelName = "_SkyLeapSkinVisual"
SniperViewModelAppearance.HiddenForSkinAttribute = "_SkyLeapGunPartHiddenForSkin"

-- Replicated on Player from server (profile → attributes on join). UI can change via future Remote + server set.
SniperViewModelAppearance.AttributeViewModelTemplateId = "SkyLeapSniperViewModelId"
SniperViewModelAppearance.AttributeSkinId = "SkyLeapSniperSkinId"

local warnedMissingGun = false
local warnedMissingSkin = false

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

local function findSkinTemplate(skinsFolder: Folder, skinId: string): Model?
	local direct = skinsFolder:FindFirstChild(skinId)
	if direct and direct:IsA("Model") then
		return direct
	end
	local lower = string.lower(skinId)
	for _, c in ipairs(skinsFolder:GetChildren()) do
		if c:IsA("Model") and string.lower(c.Name) == lower then
			return c
		end
	end
	return nil
end

local function clearGunSkinState(gun: Model)
	local old = gun:FindFirstChild(SniperViewModelAppearance.SkinVisualModelName)
	if old then
		old:Destroy()
	end
	for _, d in ipairs(gun:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute(SniperViewModelAppearance.HiddenForSkinAttribute) == true then
			d.LocalTransparencyModifier = 0
			d:SetAttribute(SniperViewModelAppearance.HiddenForSkinAttribute, nil)
		end
	end
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

-- After cloning the full viewmodel: drop the entire Skins library from this clone (only ReplicatedStorage keeps templates).
-- Optional: one cloned skin under Gun mount; default skin leaves Gun visible only.
function SniperViewModelAppearance.applyGunSkinSwap(clone: Model, skinId: string): boolean
	local skinsFolder = clone:FindFirstChild(SniperViewModelAppearance.SkinsFolderName)
	local skinCloneFromTemplate: Model? = nil

	if skinId ~= "" then
		if not skinsFolder or not skinsFolder:IsA("Folder") then
			if not warnedMissingSkin then
				warnedMissingSkin = true
				warn(
					("[Sniper] ViewModel: skin %q requested but Folder %q is missing."):format(skinId, SniperViewModelAppearance.SkinsFolderName)
				)
			end
			if skinsFolder then
				skinsFolder:Destroy()
			end
			return false
		end
		local skinTemplate = findSkinTemplate(skinsFolder, skinId)
		if not skinTemplate then
			if not warnedMissingSkin then
				warnedMissingSkin = true
				warn(
					("[Sniper] ViewModel: skin Model %q not found under %q."):format(skinId, SniperViewModelAppearance.SkinsFolderName)
				)
			end
			skinsFolder:Destroy()
			return false
		end
		skinCloneFromTemplate = skinTemplate:Clone()
	end

	-- Never keep other skin meshes in the equipped clone (avoids double draw + extra cost).
	if skinsFolder and skinsFolder:IsA("Folder") then
		skinsFolder:Destroy()
	end

	local gun = clone:FindFirstChild(SniperViewModelAppearance.GunModelName)
	if not gun or not gun:IsA("Model") then
		if not warnedMissingGun then
			warnedMissingGun = true
			warn(
				("[Sniper] ViewModel %q: expected a Model %q as direct child for base weapon + skin swap."):format(
					clone.Name,
					SniperViewModelAppearance.GunModelName
				)
			)
		end
		if skinCloneFromTemplate then
			skinCloneFromTemplate:Destroy()
		end
		return skinId == ""
	end

	clearGunSkinState(gun)

	if skinId == "" then
		return true
	end

	if not skinCloneFromTemplate then
		return false
	end

	for _, d in ipairs(gun:GetDescendants()) do
		if d:IsA("BasePart") then
			d:SetAttribute(SniperViewModelAppearance.HiddenForSkinAttribute, true)
			d.LocalTransparencyModifier = 1
		end
	end

	local mount = gun.PrimaryPart or gun:FindFirstChildWhichIsA("BasePart", true)
	if not mount then
		skinCloneFromTemplate:Destroy()
		return false
	end

	skinCloneFromTemplate.Name = SniperViewModelAppearance.SkinVisualModelName
	skinCloneFromTemplate.Parent = mount
	skinCloneFromTemplate:PivotTo(mount.CFrame)
	applyPartPresentationForSubtree(skinCloneFromTemplate)
	return true
end

return SniperViewModelAppearance
