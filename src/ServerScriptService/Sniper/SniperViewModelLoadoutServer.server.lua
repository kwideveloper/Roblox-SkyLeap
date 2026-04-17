-- Applies sniper viewmodel + skin from client (testing: no ownership checks yet).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Catalog = require(ReplicatedStorage:WaitForChild("Sniper"):WaitForChild("SniperViewModelCatalog"))
local PlayerProfile = require(ServerScriptService:WaitForChild("PlayerProfile"))

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local setLoadout = remotes:WaitForChild("SetSniperViewModelLoadout")

setLoadout.OnServerEvent:Connect(function(player, payload)
	if typeof(payload) ~= "table" then
		return
	end
	local tid = payload.templateId
	local sid = payload.skinId
	if typeof(tid) ~= "string" then
		return
	end
	if typeof(sid) ~= "string" then
		sid = ""
	end

	local ok, normT, normS = Catalog.validateAndNormalize(tid, sid)
	if not ok or normT == nil or normS == nil then
		return
	end

	PlayerProfile.setSniperViewModelCosmetics(player.UserId, normT, normS)
end)
