-- Authoritative sniper: cooldown, raycast from server Barrel (FireOriginPartName), instant kill Humanoids, Enemy tag cleanup.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Sniper"):WaitForChild("Config"))

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local requestFire = remotesFolder:WaitForChild("SniperRequestFire")
local laserFx = remotesFolder:WaitForChild("SniperLaserFx")
local audioFeedback = remotesFolder:WaitForChild("SniperAudioFeedback")
local padTriggered = remotesFolder:WaitForChild("PadTriggered")

local lastShotClock: { [Player]: number } = {}
local airBoostProbeByPlayer: { [Player]: BasePart } = {}
-- After a successful air down-boost, true until Humanoid touches ground (one boost per airborne stint).
local airDownBoostConsumedUntilGround: { [Player]: boolean } = {}
local ENEMY_TAG = Config.EnemyTag

local function getAirBoostProbeFolder(): Folder
	local f = Workspace:FindFirstChild("SniperAirDownBoostProbes")
	if f and f:IsA("Folder") then
		return f
	end
	local folder = Instance.new("Folder")
	folder.Name = "SniperAirDownBoostProbes"
	folder.Parent = Workspace
	return folder
end

local function parkAirBoostProbe(player: Player)
	local p = airBoostProbeByPlayer[player]
	if p and p.Parent then
		p.CFrame = CFrame.new(0, -1e5, 0)
	end
end

local function destroyAirBoostProbe(player: Player)
	local p = airBoostProbeByPlayer[player]
	if p then
		p:Destroy()
		airBoostProbeByPlayer[player] = nil
	end
end

local function getOrCreateAirBoostProbe(player: Player): BasePart
	local existing = airBoostProbeByPlayer[player]
	if existing and existing.Parent then
		return existing
	end
	local part = Instance.new("Part")
	part.Name = "SniperAirDownBoostProbe"
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = true
	part.Transparency = 1
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Size = Vector3.new(
		Config.SniperAirDownBoostProbeSizeX or 9,
		Config.SniperAirDownBoostProbeThickness or 0.35,
		Config.SniperAirDownBoostProbeSizeZ or 9
	)
	part:SetAttribute("SniperAirDownBoostProbe", true)
	part:SetAttribute("OwnerUserId", player.UserId)
	part.Parent = getAirBoostProbeFolder()
	airBoostProbeByPlayer[player] = part
	return part
end

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

-- Places the hitscan plate under the player’s feet only when airborne + sniper; otherwise parks far away.
local function syncAirDownBoostProbe(player: Player, character: Model?)
	if Config.SniperAirDownBoostEnabled == false then
		parkAirBoostProbe(player)
		return
	end
	if not character then
		parkAirBoostProbe(player)
		return
	end
	if not getSniperToolForFire(player) then
		parkAirBoostProbe(player)
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		parkAirBoostProbe(player)
		return
	end
	if humanoid.FloorMaterial ~= Enum.Material.Air then
		airDownBoostConsumedUntilGround[player] = false
		parkAirBoostProbe(player)
		return
	end
	if Config.SniperAirDownBoostOncePerAir ~= false and airDownBoostConsumedUntilGround[player] == true then
		parkAirBoostProbe(player)
		return
	end
	local probe = getOrCreateAirBoostProbe(player)
	local dy = Config.SniperAirDownBoostProbeCenterBelowHrp or 3.6
	probe.CFrame = CFrame.new(root.Position - Vector3.new(0, dy, 0))
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
local function isCharacterModelPart(hitPart: BasePart): boolean
	local model = hitPart:FindFirstAncestorOfClass("Model")
	return model ~= nil and model:FindFirstChildOfClass("Humanoid") ~= nil
end

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

local function resolveBulletHoleTextureId(): string
	local v = Config.SniperBulletHoleTextureId
	if type(v) == "number" then
		return "rbxassetid://" .. tostring(v)
	end
	if type(v) == "string" and v ~= "" then
		if string.sub(v, 1, 13) == "rbxassetid://" then
			return v
		end
		return "rbxassetid://" .. v
	end
	return "rbxassetid://4804824547"
end

-- World / prop impact only (not called when applyHit damages a character or Enemy tag).
local function trySpawnBulletHole(hitPart: BasePart, hitPosition: Vector3, hitNormal: Vector3)
	if hitPart:GetAttribute("SniperAirDownBoostProbe") == true then
		return
	end
	if Config.SniperBulletHoleEnabled == false then
		return
	end
	local n = hitNormal.Magnitude > 1e-4 and hitNormal.Unit or Vector3.new(0, 1, 0)
	local size = Config.SniperBulletHoleSizeStuds or 0.38
	local depth = 0.05
	local offset = Config.SniperBulletHoleNormalOffsetStuds or 0.045

	local hole = Instance.new("Part")
	hole.Name = "SniperBulletHole"
	hole.Size = Vector3.new(size, size, depth)
	hole.Transparency = 1
	hole.CanCollide = false
	hole.CanQuery = false
	hole.CastShadow = false
	hole.Massless = true

	local eye = hitPosition + n * offset
	hole.CFrame = CFrame.lookAt(eye, eye + n)

	local decal = Instance.new("Decal")
	decal.Name = "BulletHole"
	decal.Texture = resolveBulletHoleTextureId()
	decal.Face = Enum.NormalId.Front
	decal.Color3 = Color3.new(1, 1, 1)
	decal.Transparency = 0
	decal.Parent = hole

	if hitPart:IsA("Terrain") then
		hole.Anchored = true
		hole.Parent = Workspace
	else
		hole.Anchored = false
		hole.Parent = hitPart.Parent or Workspace
		local w = Instance.new("WeldConstraint")
		w.Part0 = hitPart
		w.Part1 = hole
		w.Parent = hole
	end

	local life = Config.SniperBulletHoleLifetimeSeconds
	if type(life) == "number" and life > 0 then
		Debris:AddItem(hole, life)
	end
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

	local headPart = head :: BasePart
	local useViewportRay = Config.SniperHitscanUseViewportRayOrigin ~= false

	local origin: Vector3

	if useViewportRay then
		if (claimedOrigin - headPart.Position).Magnitude > Config.SniperMaxFireOriginFromHeadStuds then
			return
		end
		if not useClaimedOrigin then
			local barrelName = Config.FireOriginPartName
			local barrel = tool:FindFirstChild(barrelName)
			if not barrel or not barrel:IsA("BasePart") then
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
		origin = claimedOrigin
	else
		local rayFromHead = Config.SniperHitscanRayFromHead ~= false
		local forwardNudge = Config.SniperHitscanHeadForwardOffset or 0.35

		if useClaimedOrigin then
			if (claimedOrigin - headPart.Position).Magnitude > Config.SniperMaxFireOriginFromHeadStuds then
				return
			end
		else
			local barrelName = Config.FireOriginPartName
			local barrel = tool:FindFirstChild(barrelName)
			if not barrel or not barrel:IsA("BasePart") then
				return
			end
			if (barrel.Position - claimedOrigin).Magnitude > Config.MaxOriginDriftStuds then
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

		if rayFromHead then
			origin = headPart.Position + dir * forwardNudge
		else
			if useClaimedOrigin then
				origin = claimedOrigin
			else
				local barrelName = Config.FireOriginPartName
				local barrel = tool:FindFirstChild(barrelName)
				if not barrel or not barrel:IsA("BasePart") then
					return
				end
				origin = barrel.Position
			end
		end
	end

	syncAirDownBoostProbe(player, character)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }

	local result = Workspace:Raycast(origin, dir * Config.MaxRange, params)

	-- Viewport/camera ray can miss the air-boost plate (camera forward offset vs probe under HRP). Stomp: world-down from root when aiming mostly down and not shooting a character.
	local function rayIsOwnAirProbe(r: RaycastResult?): boolean
		if not r then
			return false
		end
		local inst = r.Instance
		if not inst or not inst:IsA("BasePart") then
			return false
		end
		return inst:GetAttribute("SniperAirDownBoostProbe") == true and inst:GetAttribute("OwnerUserId") == player.UserId
	end
	if Config.SniperAirDownBoostFeetStompEnabled ~= false and Config.SniperAirDownBoostEnabled ~= false then
		if not rayIsOwnAirProbe(result) then
			local primaryPart = result and result.Instance
			local primaryHitsHumanoidChar = false
			if primaryPart and primaryPart:IsA("BasePart") and isCharacterModelPart(primaryPart) then
				primaryHitsHumanoidChar = true
			end
			if not primaryHitsHumanoidChar then
				local minDot = Config.SniperAirDownBoostFeetStompMinDownDot
				if type(minDot) ~= "number" then
					minDot = 0.68
				end
				-- worldDown = (0,-1,0); for unit dir, dot(dir, worldDown) = -dir.Y
				if -dir.Y >= minDot then
					local hum = character:FindFirstChildOfClass("Humanoid")
					local root = character:FindFirstChild("HumanoidRootPart")
					if hum and root and root:IsA("BasePart") and hum.FloorMaterial == Enum.Material.Air then
						local consumed = Config.SniperAirDownBoostOncePerAir ~= false and airDownBoostConsumedUntilGround[player] == true
						if not consumed then
							local stompDist = Config.SniperAirDownBoostFeetStompRayStuds
							if type(stompDist) ~= "number" or stompDist <= 0 then
								stompDist = (Config.SniperAirDownBoostProbeCenterBelowHrp or 3.6) + 3.5
							end
							local stomp = Workspace:Raycast(root.Position + Vector3.new(0, 0.25, 0), Vector3.new(0, -1, 0) * stompDist, params)
							if rayIsOwnAirProbe(stomp) then
								result = stomp
							end
						end
					end
				end
			end
		end
	end

	local endPos: Vector3
	local hitKind: string? = nil
	local victimPlayer: Player? = nil
	if result then
		endPos = result.Position
		local inst = result.Instance
		if inst and inst:IsA("BasePart") then
			local probeAttr = inst:GetAttribute("SniperAirDownBoostProbe")
			local ownerAttr = inst:GetAttribute("OwnerUserId")
			local isOwnAirProbe = probeAttr == true and ownerAttr == player.UserId
			if isOwnAirProbe then
				if Config.SniperAirDownBoostEnabled ~= false then
					local hum = character:FindFirstChildOfClass("Humanoid")
					if hum and hum.FloorMaterial == Enum.Material.Air then
						local root = character:FindFirstChild("HumanoidRootPart")
						if root and root:IsA("BasePart") then
							local v = root.AssemblyLinearVelocity
							local upSpeed = Config.SniperAirDownBoostUpSpeed
								or Config.SniperAirDownBoostVelocityY
								or 165
							local newVel: Vector3
							if Config.SniperAirDownBoostZeroHorizontalVelocity ~= false then
								newVel = Vector3.new(0, upSpeed, 0)
							else
								local carry = math.clamp(Config.SniperAirDownBoostCarryHorizontal or 0, 0, 1)
								local horiz = Vector3.new(v.X, 0, v.Z) * carry
								newVel = Vector3.new(horiz.X, upSpeed, horiz.Z)
							end
							local cap = Config.SniperAirDownBoostMaxUpSpeed
								or Config.SniperAirDownBoostMaxResultVelocityY
							if type(cap) == "number" and cap > 0 then
								newVel = Vector3.new(newVel.X, math.min(newVel.Y, cap), newVel.Z)
							end
							root.AssemblyLinearVelocity = newVel
							pcall(function()
								hum:ChangeState(Enum.HumanoidStateType.Freefall)
							end)
							local slowFallOpts: any = nil
							local slowSec = Config.SniperAirDownBoostSlowFallSeconds
							if type(slowSec) == "number" and slowSec > 0 then
								local maxDn = Config.SniperAirDownBoostSlowFallMaxDownStudsPerSec
								if type(maxDn) == "number" and maxDn > 0 then
									slowFallOpts = {
										slowFallSeconds = slowSec,
										slowFallMaxDown = maxDn,
									}
								end
							end
							pcall(function()
								padTriggered:FireClient(player, newVel, slowFallOpts)
							end)
							if Config.SniperAirDownBoostOncePerAir ~= false then
								airDownBoostConsumedUntilGround[player] = true
								parkAirBoostProbe(player)
							end
						end
					end
				end
			elseif probeAttr == true then
				-- Another player’s air probe; no damage / hole
			else
				hitKind, victimPlayer = applyHit(player, inst)
				if hitKind == nil and not isCharacterModelPart(inst) then
					trySpawnBulletHole(inst, result.Position, result.Normal)
				end
			end
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

RunService.Heartbeat:Connect(function()
	if Config.SniperAirDownBoostEnabled == false then
		return
	end
	for _, plr in Players:GetPlayers() do
		syncAirDownBoostProbe(plr, plr.Character)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	lastShotClock[player] = nil
	airDownBoostConsumedUntilGround[player] = nil
	destroyAirBoostProbe(player)
end)
