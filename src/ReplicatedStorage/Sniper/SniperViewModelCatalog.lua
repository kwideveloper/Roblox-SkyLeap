-- Shared discovery / validation for ReplicatedStorage viewmodel templates (server + client).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent.Config)
local Appearance = require(script.Parent.SniperViewModelAppearance)

local Catalog = {}

function Catalog.findViewModelsFolder(): Instance?
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

function Catalog.resolveTemplate(root: Instance?, templateId: string): Model?
	if root == nil or templateId == nil or templateId == "" then
		return nil
	end
	local t = root:FindFirstChild(templateId)
	if not t then
		local lower = string.lower(templateId)
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

function Catalog.getSortedRootTemplates(): { Model }
	local folder = Catalog.findViewModelsFolder()
	if not folder then
		return {}
	end
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

function Catalog.getSortedSkinNames(template: Model): { string }
	local skinsFolder = template:FindFirstChild(Appearance.SkinsFolderName)
	if not skinsFolder or not skinsFolder:IsA("Folder") then
		return {}
	end
	local t: { string } = {}
	for _, c in ipairs(skinsFolder:GetChildren()) do
		if c:IsA("Model") then
			table.insert(t, c.Name)
		end
	end
	table.sort(t)
	return t
end

-- Returns success, normalized template name, normalized skin id ("" = base Gun).
function Catalog.validateAndNormalize(templateId: string, skinId: string): (boolean, string?, string?)
	if type(templateId) ~= "string" or templateId == "" then
		return false, nil, nil
	end
	if type(skinId) ~= "string" then
		skinId = ""
	end
	skinId = Appearance.normalizeId(skinId)

	local folder = Catalog.findViewModelsFolder()
	if not folder then
		return false, nil, nil
	end
	local template = Catalog.resolveTemplate(folder, templateId)
	if not template then
		return false, nil, nil
	end
	local normT = template.Name
	if skinId == "" then
		return true, normT, ""
	end
	local skinsFolder = template:FindFirstChild(Appearance.SkinsFolderName)
	if not skinsFolder or not skinsFolder:IsA("Folder") then
		return false, nil, nil
	end
	for _, c in ipairs(skinsFolder:GetChildren()) do
		if c:IsA("Model") and (c.Name == skinId or string.lower(c.Name) == string.lower(skinId)) then
			return true, normT, c.Name
		end
	end
	return false, nil, nil
end

-- Model to clone for a 3D preview: skin model, else Gun, else full template.
function Catalog.getPreviewSourceModel(template: Model, skinId: string): Model?
	if skinId ~= nil and skinId ~= "" then
		local skinsFolder = template:FindFirstChild(Appearance.SkinsFolderName)
		if skinsFolder and skinsFolder:IsA("Folder") then
			for _, c in ipairs(skinsFolder:GetChildren()) do
				if c:IsA("Model") and (c.Name == skinId or string.lower(c.Name) == string.lower(skinId)) then
					return c
				end
			end
		end
	end
	local gun = template:FindFirstChild(Appearance.GunModelName)
	if gun and gun:IsA("Model") then
		return gun
	end
	return template
end

return Catalog
