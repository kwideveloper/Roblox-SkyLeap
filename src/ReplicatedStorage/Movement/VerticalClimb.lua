-- Vertical wall climb: short upward run when sprinting straight into a wall

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Movement.Config)
local Animations = require(ReplicatedStorage.Movement.Animations)
local SharedUtils = require(ReplicatedStorage.SharedUtils)
local ParkourSurfaceGate = require(ReplicatedStorage.Movement.ParkourSurfaceGate)

local VerticalClimb = {}

local active = {}
local cooldownUntil = setmetatable({}, { __mode = "k" })

local function getParts(character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return root, humanoid
end

local function stopVerticalClimbAnimation(character)
	local st = active[character]
	if st and st.animTrack then
		st.animTrack:Stop()
		st.animTrack = nil
	end
end

local function findFrontWall(root)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = SharedUtils.createParkourRaycastParams(root.Parent).FilterDescendantsInstances
	params.IgnoreWater = Config.RaycastIgnoreWater
	local dist = Config.VerticalClimbDetectionDistance or 3.5
	local look = root.CFrame.LookVector
	local origins = {
		root.Position,
		root.Position + Vector3.new(0, 1.4, 0),
		root.Position + Vector3.new(0, -1.0, 0),
		root.Position + (root.CFrame.RightVector * 0.6),
		root.Position - (root.CFrame.RightVector * 0.6),
	}
	local best
	for _, o in ipairs(origins) do
		local h = workspace:Raycast(o, look * dist, params)
		if h and h.Instance and h.Instance.CanCollide then
			if ParkourSurfaceGate.isMechanicAllowed(h.Instance, "VerticalClimb") then
				best = h
				break
			end
		end
	end
	if not best then
		return nil
	end
	-- Require facing mostly toward wall to avoid side taps
	local facing = look:Dot(-best.Normal)
	if facing < 0.5 then
		return nil
	end
	return best
end

function VerticalClimb.isActive(character)
	return active[character] ~= nil
end

function VerticalClimb.stop(character)
	local st = active[character]
	if st then
		stopVerticalClimbAnimation(character)
		active[character] = nil
		cooldownUntil[character] = os.clock() + (Config.VerticalClimbCooldownSeconds or 0.6)
		return true
	end
	return false
end

function VerticalClimb.tryStart(character)
	if not (Config.VerticalClimbEnabled ~= false) then
		return false
	end
	local root, humanoid = getParts(character)
	if not root or not humanoid then
		return false
	end
	if cooldownUntil[character] and os.clock() < cooldownUntil[character] then
		return false
	end

	-- Check if other parkour abilities are active to prevent conflicts
	local Abilities = require(ReplicatedStorage.Movement.Abilities)
	local LedgeHang = require(ReplicatedStorage.Movement.LedgeHang)
	local Climb = require(ReplicatedStorage.Movement.Climb)
	local WallRun = require(ReplicatedStorage.Movement.WallRun)
	local Grapple = require(ReplicatedStorage.Movement.Grapple)

	-- Don't start vertical climb if other abilities are active
	if
		(Abilities and Abilities.isVaulting and Abilities.isVaulting(character))
		or (Abilities and Abilities.isMantling and Abilities.isMantling(character))
		or (LedgeHang and LedgeHang.isActive and LedgeHang.isActive(character))
		or (Climb and Climb.isActive and Climb.isActive(character))
		or (WallRun and WallRun.isActive and WallRun.isActive(character))
		or (Grapple and Grapple.isActive and Grapple.isActive(character))
	then
		return false
	end

	-- Check ClientState for additional conflicts
	local cs = ReplicatedStorage:FindFirstChild("ClientState")
	if cs then
		local isVaulting = cs:FindFirstChild("IsVaulting")
		local isMantling = cs:FindFirstChild("IsMantling")
		if (isVaulting and isVaulting.Value) or (isMantling and isMantling.Value) then
			return false
		end
	end

	local speed = root.AssemblyLinearVelocity.Magnitude
	if speed < (Config.VerticalClimbMinSpeed or 18) then
		return false
	end
	local hit = findFrontWall(root)
	if not hit then
		return false
	end
	-- Start vertical climb animation
	local animator = humanoid:FindFirstChild("Animator")
	if animator then
		local verticalClimbAnim = Animations.get("VerticalClimb")
		if verticalClimbAnim then
			local animTrack = animator:LoadAnimation(verticalClimbAnim)
			animTrack.Looped = false
			animTrack.Priority = Enum.AnimationPriority.Action

			-- Set animation speed based on config
			local animSpeed = Config.VerticalClimbAnimationSpeed or 1.0
			animTrack:AdjustSpeed(animSpeed)

			-- Temporarily suppress default animations to prevent Fall animation from interrupting
			local originalAnim = humanoid:GetPlayingAnimationTracks()
			for _, track in ipairs(originalAnim) do
				if track.Animation and track.Animation.AnimationId then
					local animId = string.lower(track.Animation.AnimationId)
					if animId:find("fall") or animId:find("jump") or animId:find("land") then
						track:Stop(0.1)
					end
				end
			end

			animTrack:Play()

			-- Store animation track for cleanup
			active[character] = {
				t0 = os.clock(),
				dir = root.CFrame.LookVector,
				normal = hit.Normal,
				animTrack = animTrack,
			}
		else
			active[character] = {
				t0 = os.clock(),
				dir = root.CFrame.LookVector,
				normal = hit.Normal,
			}
		end
	else
		active[character] = {
			t0 = os.clock(),
			dir = root.CFrame.LookVector,
			normal = hit.Normal,
		}
	end
	return true
end

function VerticalClimb.maintain(character, dt)
	local st = active[character]
	if not st then
		return false
	end
	local root, humanoid = getParts(character)
	if not root or not humanoid then
		stopVerticalClimbAnimation(character)
		active[character] = nil
		return false
	end
	-- stop if grounded or time exceeded
	if humanoid.FloorMaterial ~= Enum.Material.Air then
		stopVerticalClimbAnimation(character)
		active[character] = nil
		cooldownUntil[character] = os.clock() + (Config.VerticalClimbCooldownSeconds or 0.6)
		return false
	end
	local dur = Config.VerticalClimbDurationSeconds or 0.45
	if (os.clock() - st.t0) > dur then
		stopVerticalClimbAnimation(character)
		active[character] = nil
		cooldownUntil[character] = os.clock() + (Config.VerticalClimbCooldownSeconds or 0.6)
		return false
	end
	-- re-confirm wall and refresh normal for stability
	local hit = findFrontWall(root)
	if not hit then
		stopVerticalClimbAnimation(character)
		active[character] = nil
		cooldownUntil[character] = os.clock() + (Config.VerticalClimbCooldownSeconds or 0.6)
		return false
	end
	-- Double-check that wall still allows climbing (in case attribute changed)
	if not ParkourSurfaceGate.isMechanicAllowed(hit.Instance, "VerticalClimb") then
		stopVerticalClimbAnimation(character)
		active[character] = nil
		cooldownUntil[character] = os.clock() + (Config.VerticalClimbCooldownSeconds or 0.6)
		return false
	end
	st.normal = hit.Normal
	-- stick lightly to wall and add upward velocity
	local up = Vector3.new(0, Config.VerticalClimbUpSpeed or 28, 0)
	local stick = -st.normal * (Config.VerticalClimbStickVelocity or 6)
	local v = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(stick.X, math.max(v.Y, up.Y), stick.Z)
	-- opportunistic mantle when reachable
	local Abilities = require(ReplicatedStorage.Movement.Abilities)
	if Abilities and Abilities.isMantleCandidate and Abilities.tryMantle then
		if Abilities.isMantleCandidate(character) then
			if Abilities.tryMantle(character) then
				stopVerticalClimbAnimation(character)
				active[character] = nil
				cooldownUntil[character] = os.clock() + (Config.VerticalClimbCooldownSeconds or 0.6)
				return false
			end
		end
	end
	return true
end

-- Clean up all active vertical climb animations (useful for cleanup)
function VerticalClimb.cleanupAll()
	for character, _ in pairs(active) do
		stopVerticalClimbAnimation(character)
	end
	active = {}
end

return VerticalClimb
