-- Killer spectate: smooth transition into killer first-person, hold, ease out; server respawns after total duration.
-- Locally hides killer (and victim) world rigs; only the sniper viewmodel clone follows the spectate camera.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("DeathSpectate"):WaitForChild("Config"))
local SniperConfig = require(ReplicatedStorage:WaitForChild("Sniper"):WaitForChild("Config"))
local ViewModelClient = require(ReplicatedStorage:WaitForChild("Sniper"):WaitForChild("ViewModelClient"))

local player = Players.LocalPlayer

local function ensureClientStateFolder(): Folder
	local cs = ReplicatedStorage:FindFirstChild("ClientState")
	if not cs or not cs:IsA("Folder") then
		cs = Instance.new("Folder")
		cs.Name = "ClientState"
		cs.Parent = ReplicatedStorage
	end
	return cs
end

local function setDeathSpectateCameraBlock(on: boolean)
	local cs = ensureClientStateFolder()
	local b = cs:FindFirstChild("DeathSpectateActive")
	if not b then
		b = Instance.new("BoolValue")
		b.Name = "DeathSpectateActive"
		b.Parent = cs
	end
	if b:IsA("BoolValue") then
		b.Value = on
	end
end

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local deathSpectatePayload = remotes:WaitForChild("DeathSpectatePayload")

local BIND = "DeathSpectate_Camera"

local active = false
local charConn: RBXScriptConnection? = nil
local vignetteGui: Instance? = nil
local baseFov = 70

-- Spectate-only: local hide + viewmodel (cleaned in cleanupCamera).
local spectateVmClone: Model? = nil
local spectateUnhideKiller: (() -> ())? = nil
local spectateUnhideVictim: (() -> ())? = nil
local spectateLastHiddenKillerChar: Model? = nil

local function applyLocalFullHide(char: Model): () -> ()
	local savedParts: { [BasePart]: number } = {}
	local savedGuiEnabled: { [Instance]: boolean } = {}
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") then
			savedParts[d] = d.LocalTransparencyModifier
			d.LocalTransparencyModifier = 1
		elseif d:IsA("BillboardGui") or d:IsA("SurfaceGui") then
			savedGuiEnabled[d] = d.Enabled
			d.Enabled = false
		end
	end
	return function()
		for part, prev in pairs(savedParts) do
			if part.Parent and part:IsA("BasePart") then
				part.LocalTransparencyModifier = prev
			end
		end
		for gui, wasOn in pairs(savedGuiEnabled) do
			if gui.Parent and (gui:IsA("BillboardGui") or gui:IsA("SurfaceGui")) then
				gui.Enabled = wasOn
			end
		end
	end
end

local function clearSpectateVisuals()
	if spectateUnhideKiller then
		spectateUnhideKiller()
		spectateUnhideKiller = nil
	end
	spectateLastHiddenKillerChar = nil
	if spectateUnhideVictim then
		spectateUnhideVictim()
		spectateUnhideVictim = nil
	end
	if spectateVmClone then
		ViewModelClient.forgetViewmodelClone(spectateVmClone)
		spectateVmClone:Destroy()
		spectateVmClone = nil
	end
end

local function smoothstep(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function killerEyeCFrame(killerChar: Model): CFrame?
	local head = killerChar:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return nil
	end
	local look = head.CFrame.LookVector
	local up = head.CFrame.UpVector
	local fwd = Config.EyeForwardStuds or 0.42
	local rise = Config.EyeUpStuds or 0.07
	local pos = head.Position + look * fwd + up * rise
	local worldUp = Vector3.yAxis
	if math.abs(look:Dot(worldUp)) > 0.92 then
		worldUp = Vector3.zAxis
	end
	return CFrame.lookAt(pos, pos + look, worldUp)
end

local function easeOutCubic(t: number): number
	t = math.clamp(t, 0, 1)
	local inv = 1 - t
	return 1 - inv * inv * inv
end

local function destroyVignette()
	if vignetteGui and vignetteGui.Parent then
		vignetteGui:Destroy()
	end
	vignetteGui = nil
end

local function cleanupCamera()
	RunService:UnbindFromRenderStep(BIND)
	local cam = workspace.CurrentCamera
	if cam then
		cam.CameraType = Enum.CameraType.Custom
		local ch = player.Character
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		if hum then
			cam.CameraSubject = hum
		end
		cam.FieldOfView = baseFov
	end
	if charConn then
		charConn:Disconnect()
		charConn = nil
	end
	clearSpectateVisuals()
	destroyVignette()
	setDeathSpectateCameraBlock(false)
	active = false
end

local function beginSpectate(payload: any)
	if active or Config.Enabled == false then
		return
	end
	if typeof(payload) ~= "table" then
		return
	end
	local killerUserId = payload.killerUserId
	if typeof(killerUserId) ~= "number" then
		return
	end

	local killer = Players:GetPlayerByUserId(killerUserId)
	if not killer then
		return
	end

	-- Brief wait so killer POV exists (virtual inventory / late replication).
	local waitUntil = os.clock() + 1.6
	while os.clock() < waitUntil do
		local ch = killer.Character
		if ch and ch:FindFirstChild("Head") then
			break
		end
		task.wait(0.04)
	end

	local tIn = tonumber(payload.transitionInSec) or 0.34
	local tHold = tonumber(payload.spectateHoldSec) or 2
	local tOut = tonumber(payload.transitionOutSec) or 0.26
	local pullBack = Config.TransitionOutPullBackStuds or 1.35

	active = true
	clearSpectateVisuals()
	setDeathSpectateCameraBlock(true)
	local cam = workspace.CurrentCamera
	if cam then
		baseFov = cam.FieldOfView
		cam.CameraType = Enum.CameraType.Scriptable
		local vm = ViewModelClient.createSpectatorViewModelClone(SniperConfig.SniperViewModelName)
		if vm then
			vm.Parent = cam
			spectateVmClone = vm
		end
	end
	if player.Character then
		spectateUnhideVictim = applyLocalFullHide(player.Character)
	end

	local startCF = (cam and cam.CFrame) or CFrame.new()
	local fovBonus = Config.FovHoldBonus or 6
	local vignetteMax = Config.VignetteMaxTransparency or 0.78

	local gui = Instance.new("ScreenGui")
	gui.Name = "DeathSpectateVignette"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 1000
	gui.Parent = player:WaitForChild("PlayerGui")
	vignetteGui = gui
	local dim = Instance.new("Frame")
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BorderSizePixel = 0
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundTransparency = 1
	dim.Parent = gui

	local t0 = os.clock()
	local phase = "IN"
	local lastKillerCF: CFrame? = nil
	local spectateStartCharacter = player.Character

	if charConn then
		charConn:Disconnect()
	end
	charConn = player:GetPropertyChangedSignal("Character"):Connect(function()
		if not active then
			return
		end
		if player.Character ~= spectateStartCharacter then
			cleanupCamera()
		end
	end)

	local function setVignette(strength: number)
		dim.BackgroundTransparency = 1 - vignetteMax * math.clamp(strength, 0, 1)
	end

	local camPriority = 31000
	pcall(function()
		camPriority = Enum.RenderPriority.Last.Value
	end)
	RunService:BindToRenderStep(BIND, camPriority, function()
		local camera = workspace.CurrentCamera
		if not camera or not active then
			return
		end

		local now = os.clock()
		local elapsed = now - t0
		local killerChar = killer.Character

		if killerChar then
			if spectateLastHiddenKillerChar ~= killerChar then
				if spectateUnhideKiller then
					spectateUnhideKiller()
					spectateUnhideKiller = nil
				end
				spectateLastHiddenKillerChar = killerChar
				spectateUnhideKiller = applyLocalFullHide(killerChar)
			end
			local kcf = killerEyeCFrame(killerChar)
			if kcf then
				lastKillerCF = kcf
			end
		end

		local vm = spectateVmClone
		if vm and vm.Parent == camera then
			local offset = SniperConfig.SniperViewModelCameraCFrame or CFrame.new(0.1, -0.2, -0.75)
			vm:PivotTo(ViewModelClient.solveViewmodelWorldPivot(vm, camera.CFrame, offset))
		end

		if phase == "IN" then
			local denom = math.max(tIn, 1e-4)
			local alpha = smoothstep(elapsed / denom)
			local target = lastKillerCF or startCF
			camera.CFrame = startCF:Lerp(target, alpha)
			camera.FieldOfView = baseFov + fovBonus * smoothstep(alpha)
			setVignette(alpha * 0.5)
			if elapsed >= tIn then
				phase = "HOLD"
				t0 = now
			end
			return
		end

		if phase == "HOLD" then
			if lastKillerCF then
				camera.CFrame = lastKillerCF
			end
			camera.FieldOfView = baseFov + fovBonus
			setVignette(0.88)
			if elapsed >= tHold then
				phase = "OUT"
				t0 = now
			end
			return
		end

		if phase == "OUT" then
			local denom = math.max(tOut, 1e-4)
			local u = easeOutCubic(elapsed / denom)
			local fromCF = lastKillerCF or camera.CFrame
			-- Local +Z on camera CFrame is behind the lens in Roblox (pull out of killer POV).
			local easedBack = fromCF * CFrame.new(0, 0.05 * u, pullBack * u)
			camera.CFrame = fromCF:Lerp(easedBack, u)
			local fStart = baseFov + fovBonus
			camera.FieldOfView = fStart + (baseFov - fStart) * u
			setVignette(0.88 * (1 - u))
			if elapsed >= tOut then
				setVignette(0)
				cleanupCamera()
			end
		end
	end)
end

deathSpectatePayload.OnClientEvent:Connect(beginSpectate)
