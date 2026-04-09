local Players = game:GetService("Players")

local ZombiePlatformTracker = {}
ZombiePlatformTracker.__index = ZombiePlatformTracker

local function resolvePlayerFromTouchedPart(part: BasePart?)
	if not part then
		return nil
	end
	local candidate = part.Parent
	if not candidate then
		return nil
	end

	-- Direct character part.
	local player = Players:GetPlayerFromCharacter(candidate)
	if player then
		return player
	end

	-- Accessory/tools often report nested parts; walk up to model.
	local model = candidate:FindFirstAncestorOfClass("Model")
	if model then
		player = Players:GetPlayerFromCharacter(model)
		if player then
			return player
		end
	end

	return nil
end

function ZombiePlatformTracker.new(platform: BasePart?)
	local self = setmetatable({}, ZombiePlatformTracker)
	self._platform = platform
	self._readyPlayers = {}
	self._touchCounts = {}
	return self
end

function ZombiePlatformTracker:isPlayerOnPlatform(player: Player): boolean
	if not self._platform or not player or not player.Parent then
		return false
	end

	local touches = self._touchCounts[player]
	if touches and touches > 0 then
		return true
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end

	local localPos = self._platform.CFrame:PointToObjectSpace(root.Position)
	local half = self._platform.Size * 0.5
	local margin = Vector3.new(1.25, 6, 1.25)
	return math.abs(localPos.X) <= (half.X + margin.X)
		and math.abs(localPos.Z) <= (half.Z + margin.Z)
		and math.abs(localPos.Y) <= (half.Y + margin.Y)
end

function ZombiePlatformTracker:refreshReadyStates(playersMap)
	for player in pairs(playersMap) do
		self._readyPlayers[player] = self:isPlayerOnPlatform(player)
	end
end

function ZombiePlatformTracker:countReady(playersMap): number
	local n = 0
	for player, ready in pairs(self._readyPlayers) do
		if ready and playersMap[player] and player.Parent then
			n += 1
		end
	end
	return n
end

function ZombiePlatformTracker:onTouched(part: BasePart)
	local player = resolvePlayerFromTouchedPart(part)
	if not player then
		return nil
	end
	self._touchCounts[player] = (self._touchCounts[player] or 0) + 1
	self._readyPlayers[player] = true
	return player
end

function ZombiePlatformTracker:onTouchEnded(part: BasePart)
	local player = resolvePlayerFromTouchedPart(part)
	if not player then
		return nil
	end

	local count = (self._touchCounts[player] or 0) - 1
	if count <= 0 then
		self._touchCounts[player] = nil
		self._readyPlayers[player] = self:isPlayerOnPlatform(player)
	else
		self._touchCounts[player] = count
	end
	return player
end

function ZombiePlatformTracker:removePlayer(player: Player)
	self._readyPlayers[player] = nil
	self._touchCounts[player] = nil
end

return ZombiePlatformTracker

