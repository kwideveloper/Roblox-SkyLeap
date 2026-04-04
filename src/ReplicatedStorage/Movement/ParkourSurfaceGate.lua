-- Per-surface parkour: behavior is driven by Config.ParkourOptInSurfaces (see Movement/Config).
-- Opt-in mode (true): nothing allowed unless EnableAll = true or the mechanic attribute = true.
--   Exception: LedgeHang allows geometry-detected hang without tags (opt out with LedgeHang = false).
-- Opt-out mode (false): allow each mechanic unless that attribute is explicitly false on the chain.
-- Inheritance walks from the hit part up through parents but STOPS at Workspace.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local ANCESTOR_DEPTH = 16

local movementConfigCache

local function getMovementConfig()
	if movementConfigCache ~= nil then
		return movementConfigCache
	end
	local movementFolder = ReplicatedStorage:FindFirstChild("Movement")
	local configMod = movementFolder and movementFolder:FindFirstChild("Config")
	if configMod then
		local ok, cfg = pcall(require, configMod)
		if ok and type(cfg) == "table" then
			movementConfigCache = cfg
			return cfg
		end
	end
	movementConfigCache = {}
	return movementConfigCache
end

local replicationModule
local function getInheritedAttribute(inst, attrName)
	if not replicationModule then
		local movementFolder = ReplicatedStorage:FindFirstChild("Movement")
		local modScript = movementFolder and movementFolder:FindFirstChild("ParkourAttributeReplication")
		if modScript then
			local ok, mod = pcall(require, modScript)
			if ok and type(mod) == "table" and mod.getInheritedAttribute then
				replicationModule = mod
			end
		end
	end
	if replicationModule then
		return replicationModule.getInheritedAttribute(inst, attrName)
	end
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
		if cur == Workspace then
			break
		end
		cur = cur.Parent
	end
	return nil
end

-- Legacy: allow parkour everywhere except surfaces that set Mechanic = false
local function legacyAllowUnlessExplicitFalse(inst, mechanicAttrName)
	if not inst or typeof(inst.GetAttribute) ~= "function" then
		return true
	end
	if getInheritedAttribute(inst, mechanicAttrName) == false then
		return false
	end
	return true
end

local ParkourSurfaceGate = {}

--- @param inst Instance hit by raycast (BasePart, etc.)
--- @param mechanicAttrName string e.g. "WallJump", "WallRun", "VerticalClimb", "Mantle", "LedgeHang", "Climb"
function ParkourSurfaceGate.isMechanicAllowed(inst, mechanicAttrName)
	local cfg = getMovementConfig()
	if cfg.ParkourOptInSurfaces == false then
		return legacyAllowUnlessExplicitFalse(inst, mechanicAttrName)
	end

	if not inst or typeof(inst.GetAttribute) ~= "function" then
		return false
	end

	if getInheritedAttribute(inst, "EnableAll") == true then
		return getInheritedAttribute(inst, mechanicAttrName) ~= false
	end

	-- LedgeHang: geometry-based hang (low ceiling / no mantle space) and tagged auto-ledges do not require
	-- LedgeHang = true; only LedgeHang = false opts out.
	if mechanicAttrName == "LedgeHang" then
		return getInheritedAttribute(inst, "LedgeHang") ~= false
	end

	return getInheritedAttribute(inst, mechanicAttrName) == true
end

--- Mantle at the top of a Climbable wall: normal mantle rays require Mantle = true on the part, which climb walls often omit.
--- Allow finishing mantle when Mantle is not explicitly false and the surface is a tagged Climbable you could climb, or Mantle = true.
function ParkourSurfaceGate.isMantleAllowedWhenFinishingClimb(inst)
	local cfg = getMovementConfig()
	if cfg.ParkourOptInSurfaces == false then
		return legacyAllowUnlessExplicitFalse(inst, "Mantle")
	end
	if not inst or typeof(inst.GetAttribute) ~= "function" then
		return false
	end
	if getInheritedAttribute(inst, "Mantle") == false then
		return false
	end
	if CollectionService:HasTag(inst, "Climbable") and ParkourSurfaceGate.isClimbAllowedForTaggedClimbable(inst) then
		return true
	end
	return getInheritedAttribute(inst, "Mantle") == true
end

--- Call only when the instance already has the CollectionService "Climbable" tag.
--- The tag is the opt-in for climb; you do not need Climb = true. Set Climb = false to block on a tagged surface.
function ParkourSurfaceGate.isClimbAllowedForTaggedClimbable(inst)
	if not inst or typeof(inst.GetAttribute) ~= "function" then
		return false
	end
	local cfg = getMovementConfig()
	if cfg.ParkourOptInSurfaces == false then
		return legacyAllowUnlessExplicitFalse(inst, "Climb")
	end
	if getInheritedAttribute(inst, "Climb") == false then
		return false
	end
	return true
end

return ParkourSurfaceGate
