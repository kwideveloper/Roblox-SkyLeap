-- Ref-counted suppression of UserInputService.AutoPointerEnabled (stops the "hand / click" cursor over GuiObjects while sniping).

local UserInputService = game:GetService("UserInputService")

local Config = require(script.Parent.Config)

local depth = 0
local savedAutoPointer: boolean? = nil

local SniperPointerSuppress = {}

function SniperPointerSuppress.push()
	if not Config.SniperSuppressAutoPointerEnabled then
		return
	end
	depth = depth + 1
	if depth ~= 1 then
		return
	end
	local ok, v = pcall(function()
		return UserInputService.AutoPointerEnabled
	end)
	if ok and type(v) == "boolean" then
		savedAutoPointer = v
	else
		savedAutoPointer = true
	end
	pcall(function()
		UserInputService.AutoPointerEnabled = false
	end)
end

function SniperPointerSuppress.pop()
	if not Config.SniperSuppressAutoPointerEnabled then
		return
	end
	if depth <= 0 then
		return
	end
	depth = depth - 1
	if depth ~= 0 then
		return
	end
	local restore = savedAutoPointer
	savedAutoPointer = nil
	if type(restore) == "boolean" then
		pcall(function()
			UserInputService.AutoPointerEnabled = restore
		end)
	end
end

return SniperPointerSuppress
