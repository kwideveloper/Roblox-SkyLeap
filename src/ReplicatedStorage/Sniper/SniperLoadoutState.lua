-- Shared client state: sniper stays in Backpack (never Character) when virtual inventory is on.
-- Selected slot drives viewmodel / crosshair / fire eligibility.

local Config = require(script.Parent.Config)

local sniperToolRef: Tool? = nil
local selectedSlot: number? = nil

local SniperLoadoutState = {}

function SniperLoadoutState.registerSniperTool(tool: Tool?)
	sniperToolRef = tool
	if not Config.SniperVirtualInventoryEnabled then
		return
	end
	if tool and Config.SniperVirtualInventoryAutoSelectSlot1 ~= false and selectedSlot == nil then
		selectedSlot = 1
	end
end

function SniperLoadoutState.clearSniperTool(tool: Tool?)
	if sniperToolRef == tool then
		sniperToolRef = nil
		selectedSlot = nil
	end
end

function SniperLoadoutState.getSniperTool(): Tool?
	return sniperToolRef
end

function SniperLoadoutState.getSelectedSlot(): number?
	return selectedSlot
end

function SniperLoadoutState.setSelectedSlot(slot: number?)
	selectedSlot = slot
end

function SniperLoadoutState.toggleSlot1()
	if selectedSlot == 1 then
		selectedSlot = nil
	else
		selectedSlot = 1
	end
end

function SniperLoadoutState.isSniperActive(tool: Tool): boolean
	if not Config.SniperVirtualInventoryEnabled then
		return false
	end
	return sniperToolRef == tool and selectedSlot == 1
end

function SniperLoadoutState.isVirtualSniperHeld(): boolean
	if not Config.SniperVirtualInventoryEnabled then
		return false
	end
	return sniperToolRef ~= nil and selectedSlot == 1
end

return SniperLoadoutState
