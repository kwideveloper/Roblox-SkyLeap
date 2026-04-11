-- Global player death ragdoll (all game modes / any cause of Humanoid death).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ragdoll = require(ReplicatedStorage:WaitForChild("Ragdoll"))

local function hookCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 20)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end

	humanoid.BreakJointsOnDeath = false

	humanoid.Died:Connect(function()
		if not character.Parent then
			return
		end
		Ragdoll.apply(character)
	end)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(hookCharacter)
	if player.Character then
		task.defer(hookCharacter, player.Character)
	end
end

for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
