-- Pulls server-built parkour attribute snapshots so client-side raycasts match server surface flags.
-- Uses InvokeServer so we never miss the snapshot if the player spawned before this script ran.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local getParkourLevelAttributes = Remotes:WaitForChild("GetParkourLevelAttributes")
local parkourLevelAttrsRemote = Remotes:WaitForChild("ParkourLevelAttributes")

local Movement = ReplicatedStorage:WaitForChild("Movement")
local ParkourAttributeReplication = require(Movement:WaitForChild("ParkourAttributeReplication"))

local function applyIfTable(snapshot)
	if type(snapshot) == "table" then
		ParkourAttributeReplication.applySnapshot(snapshot)
	end
end

local function pullSnapshot()
	local ok, snapshot = pcall(function()
		return getParkourLevelAttributes:InvokeServer()
	end)
	if ok then
		applyIfTable(snapshot)
	end
end

parkourLevelAttrsRemote.OnClientEvent:Connect(applyIfTable)

task.defer(pullSnapshot)
Players.LocalPlayer.CharacterAdded:Connect(pullSnapshot)
