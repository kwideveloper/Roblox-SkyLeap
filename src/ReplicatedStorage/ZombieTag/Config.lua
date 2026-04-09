-- Zombie infection mode — tune all gameplay here.
-- Level setup: tag the map model with "ZombieLevel" (CollectionService).
-- Same layout expectations as Bomb FFA: child named "Platform" for join, parts named "Spawn" / "Spawn1"… for arena spawns.
-- Optional: "BombLobbySpawner" / "LobbySpawner" / "LobbySpawn" on the level, else Workspace.BombLobbySpawner for exit.

local Config = {}

-- Round length in seconds (humans win if any human survives until this hits zero).
Config.RoundDurationSeconds = 300

-- Lobby: countdown before the first infection round starts once enough players are present.
Config.LobbyCountdownSeconds = 3

-- Countdown after teleporting to arena, right before infection round starts.
Config.PrepareCountdownSeconds = 3

-- Players required to start a round; at least this many must be in the match.
Config.MinPlayersToStart = 2

-- Hard cap on players in the match (join platform ignores extras).
Config.MaxPlayers = 20

-- Initial infected count = max(MinInitialZombies, floor(playerCount * InitialInfectedRatio)), capped so at least 1 human remains.
Config.MinInitialZombies = 1
Config.InitialInfectedRatio = 0.15

-- Late join: become zombie if current zombies are below this fraction of lobby size (with a small buffer).
Config.LateJoinZombieRatio = 0.15
Config.LateJoinZombieRatioBuffer = 0.05

-- Distance between HumanoidRootParts for a bite to register (studs).
Config.InfectionTouchDistance = 5

-- Seconds after spawn / late join during which humans cannot be infected.
Config.HumanSpawnImmunitySeconds = 2.5

-- Zombie movement buffs (applied on the client while ZombieTagActive + ZombieIsInfected).
Config.ZombieSpeedMultiplier = 1.1
Config.ZombieStaminaMaxMultiplier = 1.2

-- Infection rewards.
Config.InfectionKillCoins = 5

-- Server: green highlight on infected characters (DepthMode Occluded = hidden behind walls).
Config.ZombieHighlightFillColor = Color3.fromRGB(45, 210, 95)
Config.ZombieHighlightOutlineColor = Color3.fromRGB(25, 120, 55)
Config.ZombieHighlightFillTransparency = 0.5
Config.ZombieHighlightOutlineTransparency = 0.3

-- Server: red highlight on survivors (DepthMode Occluded).
Config.SurvivorHighlightEnabled = true
Config.SurvivorHighlightFillColor = Color3.fromRGB(230, 70, 70)
Config.SurvivorHighlightOutlineColor = Color3.fromRGB(130, 25, 25)
Config.SurvivorHighlightFillTransparency = 0.55
Config.SurvivorHighlightOutlineTransparency = 0.25

-- Seconds before survivors respawn after death (same team).
Config.RespawnDelay = 3

-- Teleport / humanoid restore (matches BombTag Config when present).
Config.SpawnSurfaceOffset = 0
Config.RespawnExtraHeight = 0
Config.PlayerDefaultWalkSpeed = 16
Config.PlayerDefaultJumpPower = 50

-- How often clients get a full state sync (server may send more often on role changes).
Config.StateBroadcastInterval = 0.5

-- After a round ends, wait this long before auto-starting another lobby countdown (if still enough players).
Config.IntermissionSeconds = 6

return Config
