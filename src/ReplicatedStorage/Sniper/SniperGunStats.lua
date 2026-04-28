-- Authoritative weapon tuning from the viewmodel / template Model "Gun" (NumberAttributes).
-- Studio: select Model "Gun" under your viewmodel template and add attributes there.

local Config = require(script.Parent.Config)
local Appearance = require(script.Parent.SniperViewModelAppearance)
local Catalog = require(script.Parent.SniperViewModelCatalog)

export type GunStats = {
	magazineSize: number,
	reloadDuration: number,
	shotCooldown: number,
	damage: number,
}

local M = {}

-- Replicated on Tool by server for HUD (read-only on client).
M.ToolAttrAmmo = "SniperAmmo"
M.ToolAttrMagSize = "SniperMagSize"
M.ToolAttrReloadEndsAt = "SniperReloadEndsAtServer"
M.ToolAttrNextShotAt = "SniperNextShotAtServer"

-- Attributes on Model "Gun" (all optional; sane defaults from Config).
M.GunAttrMagazineSize = "MagazineSize"
M.GunAttrReloadDuration = "ReloadDuration"
M.GunAttrReloadTime = "ReloadTime"
M.GunAttrDamage = "Damage"
M.GunAttrFireRate = "FireRate"
M.GunAttrShotCooldown = "ShotCooldown"

local function numAttr(inst: Instance, name: string, default: number): number
	local v = inst:GetAttribute(name)
	if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then
		return v
	end
	return default
end

function M.findGunOnTemplate(template: Model): Model?
	local g = template:FindFirstChild(Appearance.GunModelName)
	if g and g:IsA("Model") then
		return g
	end
	return nil
end

function M.resolveGunModel(player: Player, tool: Tool): Model?
	local direct = tool:FindFirstChild(Appearance.GunModelName)
	if direct and direct:IsA("Model") then
		return direct
	end
	local folder = Catalog.findViewModelsFolder()
	if not folder then
		return nil
	end
	local templateId = Appearance.normalizeId(player:GetAttribute(Appearance.AttributeViewModelTemplateId))
	if templateId == "" then
		local roots = Catalog.getSortedRootTemplates()
		if #roots > 0 then
			templateId = roots[1].Name
		else
			return nil
		end
	end
	local template = Catalog.resolveTemplate(folder, templateId)
	if not template then
		return nil
	end
	return M.findGunOnTemplate(template)
end

function M.readFromGunModel(gun: Instance?): GunStats
	local magDefault = (Config.SniperDefaultMagazineSize or 1) :: number
	local reloadDefault = (Config.ReloadSeconds or 1.2) :: number
	if not gun then
		local shotCd = reloadDefault
		if (Config.SniperDefaultFireRate or 0) > 0 then
			shotCd = 1 / (Config.SniperDefaultFireRate :: number)
		end
		return {
			magazineSize = math.max(1, math.floor(magDefault + 0.5)),
			reloadDuration = math.max(0.05, reloadDefault),
			shotCooldown = math.max(0.02, shotCd),
			damage = 0,
		}
	end

	local magSize = math.max(1, math.floor(numAttr(gun, M.GunAttrMagazineSize, magDefault) + 0.5))
	local reloadDur = numAttr(gun, M.GunAttrReloadDuration, -1)
	if reloadDur < 0 then
		reloadDur = numAttr(gun, M.GunAttrReloadTime, reloadDefault)
	end
	reloadDur = math.max(0.05, reloadDur)

	local shotCdAttr = numAttr(gun, M.GunAttrShotCooldown, -1)
	local fireRate = numAttr(gun, M.GunAttrFireRate, 0)
	local shotCd: number
	if shotCdAttr > 0 then
		shotCd = shotCdAttr
	elseif fireRate > 0 then
		shotCd = 1 / fireRate
	else
		shotCd = reloadDur
		if (Config.SniperDefaultFireRate or 0) > 0 then
			shotCd = 1 / (Config.SniperDefaultFireRate :: number)
		end
	end
	shotCd = math.max(0.02, shotCd)

	local damage = numAttr(gun, M.GunAttrDamage, 0)
	if damage < 0 then
		damage = 0
	end

	return {
		magazineSize = magSize,
		reloadDuration = reloadDur,
		shotCooldown = shotCd,
		damage = damage,
	}
end

function M.readForPlayerTool(player: Player, tool: Tool): GunStats
	local gun = M.resolveGunModel(player, tool)
	return M.readFromGunModel(gun)
end

-- Client: prefer live viewmodel clone under camera when available.
function M.readForClientLocal(tool: Tool, player: Player, gunFromViewmodel: Model?): GunStats
	if gunFromViewmodel and gunFromViewmodel:IsA("Model") then
		return M.readFromGunModel(gunFromViewmodel)
	end
	return M.readForPlayerTool(player, tool)
end

return M
