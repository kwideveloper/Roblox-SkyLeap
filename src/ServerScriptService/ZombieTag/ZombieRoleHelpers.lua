local ZombieRoleHelpers = {}

function ZombieRoleHelpers.countListedPlayers(playersMap)
	local n = 0
	for player in pairs(playersMap) do
		if player.Parent then
			n += 1
		end
	end
	return n
end

function ZombieRoleHelpers.countZombies(playersMap, zombiesMap)
	local n = 0
	for player in pairs(zombiesMap) do
		if playersMap[player] and player.Parent then
			n += 1
		end
	end
	return n
end

function ZombieRoleHelpers.countHumans(playersMap, zombiesMap)
	return ZombieRoleHelpers.countListedPlayers(playersMap) - ZombieRoleHelpers.countZombies(playersMap, zombiesMap)
end

function ZombieRoleHelpers.desiredZombieCount(totalPlayers, config)
	local ratio = config.InitialInfectedRatio or 0.15
	local minZ = config.MinInitialZombies or 1
	local count = math.max(minZ, math.floor(totalPlayers * ratio))
	count = math.min(count, math.max(0, totalPlayers - 1))
	return math.max(1, count)
end

function ZombieRoleHelpers.shouldAssignLateJoinAsZombie(totalPlayers, zombieCount, config)
	if totalPlayers <= 1 then
		return false
	end
	local humans = totalPlayers - zombieCount
	if humans <= 0 then
		return false
	end
	local targetRatio = (config.LateJoinZombieRatio or 0.15) + (config.LateJoinZombieRatioBuffer or 0)
	local desiredZ = math.max(config.MinInitialZombies or 1, math.floor(totalPlayers * targetRatio))
	return zombieCount < desiredZ
end

function ZombieRoleHelpers.collectActivePlayers(playersMap)
	local players = {}
	for player in pairs(playersMap) do
		if player.Parent then
			table.insert(players, player)
		end
	end
	return players
end

function ZombieRoleHelpers.pickInitialZombies(playersMap, config)
	local activePlayers = ZombieRoleHelpers.collectActivePlayers(playersMap)
	local total = #activePlayers
	if total < (config.MinPlayersToStart or 3) then
		return {}, activePlayers
	end

	local needed = ZombieRoleHelpers.desiredZombieCount(total, config)
	local humans = table.clone(activePlayers)
	local zombies = {}

	for _ = 1, needed do
		if #humans == 0 then
			break
		end
		local idx = math.random(1, #humans)
		local selected = table.remove(humans, idx)
		table.insert(zombies, selected)
	end

	return zombies, humans
end

return ZombieRoleHelpers

