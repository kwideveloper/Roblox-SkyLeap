local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Sniper"):WaitForChild("Config"))
local SniperFirstPersonGate = require(ReplicatedStorage:WaitForChild("Sniper"):WaitForChild("SniperFirstPersonGate"))
local SniperLoadoutState = require(ReplicatedStorage:WaitForChild("Sniper"):WaitForChild("SniperLoadoutState"))

if Config.EnemyTargetHighlightEnabled == false then
	return
end

local LOCAL_PLAYER = Players.LocalPlayer
local ENEMY_TAG = Config.EnemyTag or "Enemy"
local HIGHLIGHT_NAME = "EnemyTargetHighlight"

local activeHighlights: { [Instance]: Highlight } = {}
local playerAddedConns: { [Player]: RBXScriptConnection } = {}
local playerRemovingConns: { [Player]: RBXScriptConnection } = {}
local trackedTargets: { [Instance]: boolean } = {}
local highlightsVisible = false

local function toTransparency(value: any, fallback: number): number
	if type(value) ~= "number" then
		return fallback
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	return math.clamp(value, 0, 1)
end

local function canHighlightTarget(target: Instance): boolean
	if target == nil then
		return false
	end
	if target == LOCAL_PLAYER.Character then
		return false
	end
	return target:IsA("Model") or target:IsA("BasePart")
end

local function isAnyToolEquippedOnCharacter(): boolean
	local character = LOCAL_PLAYER.Character
	if not character then
		return false
	end
	return character:FindFirstChildOfClass("Tool") ~= nil
end

local function shouldShowHighlights(): boolean
	local inFirstPerson = SniperFirstPersonGate.isCameraCloseForFirstPerson(LOCAL_PLAYER)
	if inFirstPerson then
		return true
	end
	-- Normal tool flow (tool parented to Character) + virtual sniper inventory flow.
	if isAnyToolEquippedOnCharacter() or SniperLoadoutState.isVirtualSniperHeld() then
		return true
	end
	return false
end

local function removeHighlight(target: Instance)
	local existing = activeHighlights[target]
	if existing then
		activeHighlights[target] = nil
		pcall(function()
			existing:Destroy()
		end)
	end
end

local function createHighlight(target: Instance)
	local h = Instance.new("Highlight")
	h.Name = HIGHLIGHT_NAME
	h.DepthMode = Config.EnemyTargetHighlightDepthMode or Enum.HighlightDepthMode.Occluded
	h.OutlineColor = Config.EnemyTargetHighlightOutlineColor or Color3.fromRGB(170, 170, 170)
	h.FillColor = Config.EnemyTargetHighlightFillColor or Color3.fromRGB(255, 45, 45)
	h.OutlineTransparency = toTransparency(Config.EnemyTargetHighlightOutlineTransparency, 0.18)
	h.FillTransparency = toTransparency(Config.EnemyTargetHighlightFillTransparency, 0.9)
	h.Adornee = target
	h.Parent = target
	activeHighlights[target] = h
end

local function ensureHighlight(target: Instance)
	if not canHighlightTarget(target) then
		return
	end
	if not highlightsVisible then
		return
	end

	local existing = activeHighlights[target]
	if existing and existing.Parent then
		return
	end
	if existing and not existing.Parent then
		activeHighlights[target] = nil
	end

	local found = target:FindFirstChild(HIGHLIGHT_NAME)
	if found and found:IsA("Highlight") then
		found.DepthMode = Config.EnemyTargetHighlightDepthMode or Enum.HighlightDepthMode.Occluded
		found.OutlineColor = Config.EnemyTargetHighlightOutlineColor or Color3.fromRGB(170, 170, 170)
		found.FillColor = Config.EnemyTargetHighlightFillColor or Color3.fromRGB(255, 45, 45)
		found.OutlineTransparency = toTransparency(Config.EnemyTargetHighlightOutlineTransparency, 0.18)
		found.FillTransparency = toTransparency(Config.EnemyTargetHighlightFillTransparency, 0.9)
		found.Adornee = target
		activeHighlights[target] = found
		return
	end

	createHighlight(target)
end

local function refreshAllHighlights()
	for target in pairs(trackedTargets) do
		if highlightsVisible then
			ensureHighlight(target)
		else
			removeHighlight(target)
		end
	end
end

local function trackOtherPlayer(player: Player)
	if player == LOCAL_PLAYER then
		return
	end

	if player.Character then
		trackedTargets[player.Character] = true
		ensureHighlight(player.Character)
	end

	playerAddedConns[player] = player.CharacterAdded:Connect(function(character)
		trackedTargets[character] = true
		ensureHighlight(character)
	end)
	playerRemovingConns[player] = player.CharacterRemoving:Connect(function(character)
		trackedTargets[character] = nil
		removeHighlight(character)
	end)
end

local function untrackOtherPlayer(player: Player)
	local c1 = playerAddedConns[player]
	if c1 then
		c1:Disconnect()
		playerAddedConns[player] = nil
	end
	local c2 = playerRemovingConns[player]
	if c2 then
		c2:Disconnect()
		playerRemovingConns[player] = nil
	end
	if player.Character then
		trackedTargets[player.Character] = nil
		removeHighlight(player.Character)
	end
end

for _, player in ipairs(Players:GetPlayers()) do
	trackOtherPlayer(player)
end

Players.PlayerAdded:Connect(trackOtherPlayer)
Players.PlayerRemoving:Connect(untrackOtherPlayer)

local function onEnemyTagged(instance: Instance)
	trackedTargets[instance] = true
	ensureHighlight(instance)
end

local function onEnemyUntagged(instance: Instance)
	trackedTargets[instance] = nil
	removeHighlight(instance)
end

for _, tagged in ipairs(CollectionService:GetTagged(ENEMY_TAG)) do
	onEnemyTagged(tagged)
end

CollectionService:GetInstanceAddedSignal(ENEMY_TAG):Connect(onEnemyTagged)
CollectionService:GetInstanceRemovedSignal(ENEMY_TAG):Connect(onEnemyUntagged)

RunService.RenderStepped:Connect(function()
	local want = shouldShowHighlights()
	if want == highlightsVisible then
		return
	end
	highlightsVisible = want
	refreshAllHighlights()
end)
