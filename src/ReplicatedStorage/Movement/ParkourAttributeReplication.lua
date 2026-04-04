-- Server builds a snapshot of parkour-related attributes under the current level and sends it to the client.
-- Some Studio / replication setups do not show custom attributes on the client immediately; raycasts use the
-- client instance, so ParkourSurfaceGate reads this cache first (client only), then falls back to GetAttribute.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ATTR_NAMES = {
	"EnableAll",
	"WallJump",
	"WallRun",
	"VerticalClimb",
	"Mantle",
	"LedgeHang",
	"LedgeFace",
	"Climb",
	"Vault",
}

local cache = {} -- [fullName: string] = { [attr: string] = any }

local M = {}

M.ATTR_NAMES = ATTR_NAMES

function M.applySnapshot(map)
	if not RunService:IsClient() then
		return
	end
	for k in pairs(cache) do
		cache[k] = nil
	end
	if type(map) ~= "table" then
		return
	end
	for fullName, attrs in pairs(map) do
		if type(fullName) == "string" and type(attrs) == "table" then
			cache[fullName] = attrs
		end
	end
end

--- Walk instance -> Workspace; on client prefer replicated snapshot per instance, then GetAttribute.
function M.getInheritedAttribute(inst, attrName)
	if not inst then
		return nil
	end
	local cur = inst
	for _ = 1, 16 do
		if not cur then
			break
		end
		if RunService:IsClient() then
			local row = cache[cur:GetFullName()]
			if row and row[attrName] ~= nil then
				return row[attrName]
			end
		end
		if typeof(cur.GetAttribute) == "function" then
			local v = cur:GetAttribute(attrName)
			if v ~= nil then
				return v
			end
		end
		if cur == Workspace then
			break
		end
		cur = cur.Parent
	end
	return nil
end

--- Server-only: collect attributes for all instances under levelRoot that matter for parkour gating.
function M.buildSnapshotForLevel(levelRoot)
	if not levelRoot then
		return {}
	end
	local map = {}
	for _, d in ipairs(levelRoot:GetDescendants()) do
		if d:IsA("BasePart") or d:IsA("Model") or d:IsA("Folder") then
			local row = nil
			for _, attr in ipairs(ATTR_NAMES) do
				local v = d:GetAttribute(attr)
				if v ~= nil then
					if not row then
						row = {}
					end
					row[attr] = v
				end
			end
			if row then
				map[d:GetFullName()] = row
			end
		end
	end
	return map
end

return M
