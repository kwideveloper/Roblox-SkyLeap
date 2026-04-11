-- Authoritative sniper: cooldown, raycast from server Barrel (FireOriginPartName), instant kill Humanoids, Enemy tag cleanup.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Sniper"):WaitForChild("Config"))

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local requestFire = remotesFolder:WaitForChild("SniperRequestFire")
local laserFx = remotesFolder:WaitForChild("SniperLaserFx")
local audioFeedback = remotesFolder:WaitForChild("SniperAudioFeedback")

local lastShotClock: { [Player]: number } = {}
local ENEMY_TAG = Config.EnemyTag

local function getEquippedSniper(character: Model): Tool?
	for _, child in character:GetChildren() do
		if child:IsA("Tool") and child.Name == Config.ToolName then
			return child
		end
	end
	return nil
end

local function getSniperToolForFire(player: Player): Tool?
	if Config.SniperVirtualInventoryEnabled then
		local bp = player:FindFirstChildOfClass("Backpack")
		if bp then
			local t = bp:FindFirstChild(Config.ToolName)
			if t and t:IsA("Tool") then
				return t
			end
		end
		return nil
	end
	local ch = player.Character
	if ch then
		local t = getEquippedSniper(ch)
		if t then
			return t
		end
	end
	local bp = player:FindFirstChildOfClass("Backpack")
	if bp then
		local t = bp:FindFirstChild(Config.ToolName)
		if t and t:IsA("Tool") then
			return t
		end
	end
	return nil
end

local function findEnemyRoot(instance: Instance): Instance?
	local current: Instance? = instance
	while current and current ~= Workspace do
		if CollectionService:HasTag(current, ENEMY_TAG) then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function destroyEnemyRoot(root: Instance)
	if root:IsA("Model") then
		local humanoid = root:FindFirstChildOfClass("Humanoid")
		if humanoid then
			if humanoid.Health > 0 then
				humanoid.Health = 0
			end
			-- Keep the model in Workspace so Died -> ragdoll can run and the body can stay visible.
			return
		end
		root:Destroy()
	elseif root:IsA("BasePart") then
		root:SetAttribute("EnemyHealth", 0)
		root:Destroy()
	end
end

-- Returns: hitKind ("player" | "npc" | "enemy"), victimPlayer (if a Roblox player died)
local function applyHit(shooter: Player, hitPart: BasePart): (string?, Player?)
	local model = hitPart:FindFirstAncestorOfClass("Model")
	if model then
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			local victim = Players:GetPlayerFromCharacter(model)
			if victim == shooter then
				return nil, nil
			end
			humanoid.Health = 0
			if victim then
				return "player", victim
			end
			return "npc", nil
		end
	end

	local enemyRoot = findEnemyRoot(hitPart)
	if enemyRoot then
		destroyEnemyRoot(enemyRoot)
		return "enemy", nil
	end
	return nil, nil
end

local function broadcastLaser(shooter: Player, from: Vector3, to: Vector3)
	for _, plr in Players:GetPlayers() do
		if plr ~= shooter then
			laserFx:FireClient(plr, shooter.UserId, from, to)
		end
	end
end

local function normalizeDirection(v: Vector3): Vector3?
	if v.Magnitude < 1e-5 then
		return nil
	end
	return v.Unit
end

requestFire.OnServerEvent:Connect(function(player: Player, claimedOrigin: Vector3, claimedDirection: Vector3)
	if typeof(claimedOrigin) ~= "Vector3" or typeof(claimedDirection) ~= "Vector3" then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	local tool = getSniperToolForFire(player)
	if not tool then
		return
	end

	local now = os.clock()
	local last = lastShotClock[player]
	if last and (now - last) < Config.ReloadSeconds then
		return
	end

	local dir = normalizeDirection(claimedDirection)
	if not dir then
		return
	end

	local head = character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end

	local parent = tool.Parent
	local useClaimedOrigin = Config.SniperVirtualInventoryEnabled or (parent ~= nil and parent:IsA("Backpack"))

	local origin: Vector3
	if useClaimedOrigin then
		if (claimedOrigin - head.Position).Magnitude > Config.SniperMaxFireOriginFromHeadStuds then
			return
		end
		origin = claimedOrigin
	else
		local barrelName = Config.FireOriginPartName
		local barrel = tool:FindFirstChild(barrelName)
		if not barrel or not barrel:IsA("BasePart") then
			return
		end
		origin = barrel.Position
		if (origin - claimedOrigin).Magnitude > Config.MaxOriginDriftStuds then
			return
		end
		if Config.UseMuzzleDirectionCheck then
			local barrelLook = barrel.CFrame.LookVector
			local dot = math.clamp(barrelLook:Dot(dir), -1, 1)
			local deg = math.deg(math.acos(dot))
			if deg > Config.MaxAimVsMuzzleDegrees then
				return
			end
		end
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }

	local result = Workspace:Raycast(origin, dir * Config.MaxRange, params)
	local endPos: Vector3
	local hitKind: string? = nil
	local victimPlayer: Player? = nil
	if result then
		endPos = result.Position
		if result.Instance and result.Instance:IsA("BasePart") then
			hitKind, victimPlayer = applyHit(player, result.Instance)
		end
	else
		endPos = origin + dir * Config.MaxRange
	end

	lastShotClock[player] = now
	broadcastLaser(player, origin, endPos)

	if hitKind and Config.KillConfirmSoundId ~= "" then
		audioFeedback:FireClient(player, "KillConfirm")
	end
	if victimPlayer and Config.VictimDeathSoundId ~= "" then
		audioFeedback:FireClient(victimPlayer, "VictimDeath")
	end
end)

Players.PlayerRemoving:Connect(function(player)
	lastShotClock[player] = nil
end)
