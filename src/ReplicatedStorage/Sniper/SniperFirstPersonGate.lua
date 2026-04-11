-- Shared client check: camera close enough to count as first-person aim (same rule as sniper viewmodel).

local Workspace = game:GetService("Workspace")

local Config = require(script.Parent.Config)

local SniperFirstPersonGate = {}

function SniperFirstPersonGate.isCameraCloseForFirstPerson(player: Player): boolean
	local camera = Workspace.CurrentCamera
	if not camera or not player then
		return false
	end
	-- LockFirstPerson does not always keep (Focus - Camera) within the zoom-distance heuristic; treat as first person anyway.
	if player.CameraMode == Enum.CameraMode.LockFirstPerson then
		return true
	end
	local distance = (camera.Focus.Position - camera.CFrame.Position).Magnitude
	local strict = (player.CameraMinZoomDistance or 0.5) + 0.15
	if distance <= strict then
		return true
	end
	local relaxed = Config.SniperViewModelMaxOrbitDistance
	if type(relaxed) == "number" and relaxed > strict and distance <= relaxed then
		return true
	end
	return false
end

return SniperFirstPersonGate
