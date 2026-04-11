-- Client: hide Roblox default hotbar when the sniper Tool exists in Backpack (virtual loadout),
-- and force first person while the sniper slot is active.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local Config = require(script.Parent.Config)
local SniperLoadoutState = require(script.Parent.SniperLoadoutState)

local SniperRobloxCompanionClient = {}

local started = false
local backpackHiddenByUs = false
local forcingFirstPerson = false
local savedCameraMode: Enum.CameraMode? = nil
local savedMinZoom: number? = nil
local savedMaxZoom: number? = nil

local function setBackpackCoreGui(enabled: boolean)
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, enabled)
	end)
end

local function refreshBackpackGui(player: Player)
	if not Config.SniperVirtualInventoryEnabled or not Config.SniperHideRobloxDefaultBackpack then
		if backpackHiddenByUs then
			setBackpackCoreGui(true)
			backpackHiddenByUs = false
		end
		return
	end
	local bp = player:FindFirstChildOfClass("Backpack")
	local hasSniper = bp and bp:FindFirstChild(Config.ToolName) ~= nil
	if hasSniper then
		setBackpackCoreGui(false)
		backpackHiddenByUs = true
	else
		setBackpackCoreGui(true)
		backpackHiddenByUs = false
	end
end

local function releaseFirstPersonLock(player: Player)
	if not forcingFirstPerson then
		return
	end
	forcingFirstPerson = false
	if savedCameraMode ~= nil then
		pcall(function()
			player.CameraMode = savedCameraMode :: Enum.CameraMode
		end)
	end
	if savedMinZoom ~= nil then
		pcall(function()
			player.CameraMinZoomDistance = savedMinZoom :: number
		end)
	end
	if savedMaxZoom ~= nil then
		pcall(function()
			player.CameraMaxZoomDistance = savedMaxZoom :: number
		end)
	end
	savedCameraMode = nil
	savedMinZoom = nil
	savedMaxZoom = nil
end

local function applyFirstPersonLock(player: Player)
	if not forcingFirstPerson then
		savedCameraMode = player.CameraMode
		savedMinZoom = player.CameraMinZoomDistance
		savedMaxZoom = player.CameraMaxZoomDistance
		forcingFirstPerson = true
	end
	pcall(function()
		player.CameraMode = Enum.CameraMode.LockFirstPerson
	end)
end

local function refreshFirstPersonLock(player: Player)
	if not Config.SniperVirtualInventoryEnabled or not Config.SniperForceFirstPersonWhileSniperActive then
		releaseFirstPersonLock(player)
		return
	end
	local t = SniperLoadoutState.getSniperTool()
	local want = t ~= nil and SniperLoadoutState.isSniperActive(t)
	if want then
		applyFirstPersonLock(player)
		if player.CameraMode ~= Enum.CameraMode.LockFirstPerson then
			pcall(function()
				player.CameraMode = Enum.CameraMode.LockFirstPerson
			end)
		end
	else
		releaseFirstPersonLock(player)
	end
end

function SniperRobloxCompanionClient.start(player: Player)
	if started then
		refreshBackpackGui(player)
		refreshFirstPersonLock(player)
		return
	end
	started = true

	local bp = player:WaitForChild("Backpack", 30)
	if bp then
		bp.ChildAdded:Connect(function(child)
			if child.Name == Config.ToolName then
				refreshBackpackGui(player)
			end
		end)
		bp.ChildRemoved:Connect(function(child)
			if child.Name == Config.ToolName then
				refreshBackpackGui(player)
			end
		end)
	end

	player.CharacterAdded:Connect(function()
		task.defer(function()
			refreshFirstPersonLock(player)
		end)
	end)

	RunService.Heartbeat:Connect(function()
		refreshBackpackGui(player)
		refreshFirstPersonLock(player)
	end)

	refreshBackpackGui(player)
	refreshFirstPersonLock(player)
end

return SniperRobloxCompanionClient
