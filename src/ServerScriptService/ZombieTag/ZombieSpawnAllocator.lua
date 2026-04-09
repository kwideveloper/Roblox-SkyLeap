local ZombieSpawnAllocator = {}

local function shuffle(list)
	for i = #list, 2, -1 do
		local j = math.random(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

local function countZombies(playersMap, zombiesMap)
	local n = 0
	for player in pairs(zombiesMap) do
		if playersMap[player] and player.Parent then
			n += 1
		end
	end
	return n
end

local function countHumans(playersMap, zombiesMap)
	local total = 0
	for player in pairs(playersMap) do
		if player.Parent then
			total += 1
		end
	end
	return total - countZombies(playersMap, zombiesMap)
end

function ZombieSpawnAllocator.buildRoleSpawnPools(spawns, playersMap, zombiesMap)
	local valid = {}
	for _, spawnObject in ipairs(spawns or {}) do
		if spawnObject and spawnObject.Parent then
			table.insert(valid, spawnObject)
		end
	end

	local zombiePool = {}
	local humanPool = {}
	local totalSpawns = #valid
	local zombieCount = countZombies(playersMap, zombiesMap)
	local humanCount = countHumans(playersMap, zombiesMap)
	local totalPlayers = zombieCount + humanCount

	if totalSpawns <= 0 then
		return zombiePool, humanPool, {
			totalSpawns = 0,
			zombieCount = zombieCount,
			humanCount = humanCount,
		}
	end

	if zombieCount <= 0 then
		humanPool = valid
		return zombiePool, humanPool, {
			totalSpawns = totalSpawns,
			zombieCount = zombieCount,
			humanCount = humanCount,
		}
	end
	if humanCount <= 0 then
		zombiePool = valid
		return zombiePool, humanPool, {
			totalSpawns = totalSpawns,
			zombieCount = zombieCount,
			humanCount = humanCount,
		}
	end

	if totalSpawns == 1 then
		zombiePool = valid
		humanPool = valid
		return zombiePool, humanPool, {
			totalSpawns = totalSpawns,
			zombieCount = zombieCount,
			humanCount = humanCount,
			sharedSingleSpawn = true,
		}
	end

	shuffle(valid)
	local zombieRatio = zombieCount / math.max(1, totalPlayers)
	local zombieSpawnCount = math.floor((totalSpawns * zombieRatio) + 0.5)
	zombieSpawnCount = math.clamp(zombieSpawnCount, 1, totalSpawns - 1)

	for index, spawnObject in ipairs(valid) do
		if index <= zombieSpawnCount then
			table.insert(zombiePool, spawnObject)
		else
			table.insert(humanPool, spawnObject)
		end
	end

	return zombiePool, humanPool, {
		totalSpawns = totalSpawns,
		zombieCount = zombieCount,
		humanCount = humanCount,
	}
end

return ZombieSpawnAllocator

