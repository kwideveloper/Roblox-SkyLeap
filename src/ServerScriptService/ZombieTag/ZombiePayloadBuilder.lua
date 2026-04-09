local ZombiePayloadBuilder = {}

function ZombiePayloadBuilder.buildForPlayer(player: Player, playersMap, zombiesMap, state)
	local players = {}
	local humans = 0
	local zombies = 0

	for plr in pairs(playersMap) do
		if plr.Parent then
			local isZombie = zombiesMap[plr] == true
			table.insert(players, {
				UserId = plr.UserId,
				Name = plr.Name,
				IsZombie = isZombie,
			})
			if isZombie then
				zombies += 1
			else
				humans += 1
			end
		end
	end

	local isLocalZombie = zombiesMap[player] == true
	return {
		mode = "Zombie",
		phase = state.phase,
		roundTimeLeft = state.roundTimeLeft,
		lobbyCountdownLeft = state.lobbyCountdownLeft,
		prepareCountdownLeft = state.prepareCountdownLeft,
		humans = humans,
		zombies = zombies,
		yourRole = isLocalZombie and "zombie" or "human",
		yourRoleLabel = isLocalZombie and "Zombie" or "Superviviente",
		matchStarted = state.matchStarted,
		players = players,
	}
end

return ZombiePayloadBuilder

