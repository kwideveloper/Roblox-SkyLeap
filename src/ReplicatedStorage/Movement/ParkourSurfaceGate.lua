-- Central rules for per-surface parkour: DisableAll + per-mechanic opt-in/out.
-- When DisableAll is true on the instance or an ancestor, every mechanic is off
-- unless that mechanic's attribute is explicitly true on the same inheritance chain.

local ANCESTOR_DEPTH = 8

local function getInheritedAttribute(inst, attrName)
	local cur = inst
	for _ = 1, ANCESTOR_DEPTH do
		if not cur then
			break
		end
		if typeof(cur.GetAttribute) == "function" then
			local v = cur:GetAttribute(attrName)
			if v ~= nil then
				return v
			end
		end
		cur = cur.Parent
	end
	return nil
end

local ParkourSurfaceGate = {}

--- @param inst Instance hit by raycast (BasePart, etc.)
--- @param mechanicAttrName string e.g. "WallJump", "WallRun", "VerticalClimb", "Mantle", "LedgeHang", "Climb"
function ParkourSurfaceGate.isMechanicAllowed(inst, mechanicAttrName)
	if not inst or typeof(inst.GetAttribute) ~= "function" then
		return true
	end
	if getInheritedAttribute(inst, "DisableAll") == true then
		return getInheritedAttribute(inst, mechanicAttrName) == true
	end
	if getInheritedAttribute(inst, mechanicAttrName) == false then
		return false
	end
	return true
end

return ParkourSurfaceGate
