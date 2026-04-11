-- Wires the Sniper Tool wherever it appears (StarterPack-only tools are in Backpack at join).
-- With SniperVirtualInventoryEnabled, the Tool never stays on the character — only Backpack + viewmodel.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Sniper"):WaitForChild("Config"))
local SniperClient = require(ReplicatedStorage:WaitForChild("Sniper"):WaitForChild("SniperClient"))
local SniperRobloxCompanionClient = require(ReplicatedStorage:WaitForChild("Sniper"):WaitForChild("SniperRobloxCompanionClient"))

local localPlayer = Players.LocalPlayer

local function tryMoveSniperToBackpack(inst: Instance)
	if not Config.SniperVirtualInventoryEnabled then
		return
	end
	if not inst:IsA("Tool") or inst.Name ~= Config.ToolName then
		return
	end
	task.defer(function()
		if inst.Parent == localPlayer.Character then
			local bp = localPlayer:FindFirstChildOfClass("Backpack")
			if bp then
				inst.Parent = bp
			end
		end
	end)
end

local function tryBind(tool: Instance)
	if tool:IsA("Tool") then
		SniperClient.bindTool(tool, { LocalPlayer = localPlayer })
	end
end

local function scan(container: Instance)
	for _, child in container:GetChildren() do
		tryBind(child)
	end
end

local function hookContainer(container: Instance?)
	if not container then
		return
	end
	container.ChildAdded:Connect(tryBind)
	scan(container)
end

local function onCharacter(character: Model)
	for _, child in ipairs(character:GetChildren()) do
		tryMoveSniperToBackpack(child)
	end
	character.ChildAdded:Connect(tryMoveSniperToBackpack)
	hookContainer(localPlayer.Backpack)
	hookContainer(character)
end

if localPlayer.Character then
	onCharacter(localPlayer.Character)
end
localPlayer.CharacterAdded:Connect(onCharacter)

task.defer(function()
	SniperRobloxCompanionClient.start(localPlayer)
end)
