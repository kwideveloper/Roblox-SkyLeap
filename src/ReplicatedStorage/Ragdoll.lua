-- Server-side ragdoll: Motor6D -> BallSocketConstraint (BreakJointsOnDeath = false).
-- Attachment CFrames match Motor6D C0/C1 on Part0/Part1; BallSocket uses limits + twist (stable limbs vs fully loose sockets).
-- See: https://devforum.roblox.com/t/humanoidbreakjointsondeath/252053

local Ragdoll = {}

local DEFAULTS = {
	LimitsEnabled = true,
	TwistLimitsEnabled = true,
	UpperAngle = 90,
}

local function stopAnimator(humanoid: Humanoid)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end
	for _, track in animator:GetPlayingAnimationTracks() do
		pcall(function()
			track:Stop(0.05)
		end)
	end
end

function Ragdoll.apply(
	character: Model,
	options: { LimitsEnabled: boolean?, TwistLimitsEnabled: boolean?, UpperAngle: number? }?
)
	if character:GetAttribute("_SkyLeapRagdollApplied") then
		return
	end
	character:SetAttribute("_SkyLeapRagdollApplied", true)

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local opt = options or DEFAULTS
	local limitsOn = if opt.LimitsEnabled ~= nil then opt.LimitsEnabled else DEFAULTS.LimitsEnabled
	local twistOn = if opt.TwistLimitsEnabled ~= nil then opt.TwistLimitsEnabled else DEFAULTS.TwistLimitsEnabled
	local upperAngle = if opt.UpperAngle ~= nil then opt.UpperAngle else DEFAULTS.UpperAngle

	if humanoid then
		humanoid.BreakJointsOnDeath = false
		stopAnimator(humanoid)
		humanoid.AutoRotate = false
	end

	local motors = {}
	for _, d in character:GetDescendants() do
		if d:IsA("Motor6D") and d.Part0 and d.Part1 then
			table.insert(motors, d)
		end
	end

	if #motors == 0 then
		-- Constraint-only rigs (no Motor6D): fall back to classic joint break
		pcall(function()
			character:BreakJoints()
		end)
		if humanoid then
			pcall(function()
				humanoid:ChangeState(Enum.HumanoidStateType.Physics)
			end)
		end
		return
	end

	for _, motor in ipairs(motors) do
		local p0 = motor.Part0
		local p1 = motor.Part1
		if p0 and p1 then
			local a0 = Instance.new("Attachment")
			a0.Name = "RagdollA0"
			a0.Parent = p0
			a0.CFrame = motor.C0

			local a1 = Instance.new("Attachment")
			a1.Name = "RagdollA1"
			a1.Parent = p1
			a1.CFrame = motor.C1

			local socket = Instance.new("BallSocketConstraint")
			socket.Name = "Ragdoll_" .. motor.Name
			socket.Attachment0 = a0
			socket.Attachment1 = a1
			socket.LimitsEnabled = limitsOn
			socket.TwistLimitsEnabled = twistOn
			if limitsOn then
				socket.UpperAngle = upperAngle
			end

			local socketParent: Instance = motor.Parent or p0
			if not socketParent:IsA("BasePart") then
				socketParent = p0
			end
			socket.Parent = socketParent

			motor:Destroy()
		end
	end

	for _, inst in character:GetDescendants() do
		if inst:IsA("BasePart") then
			inst.Anchored = false
			pcall(function()
				inst:SetNetworkOwner(nil)
			end)
		end
	end

	if humanoid then
		pcall(function()
			humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		end)
	end
end

return Ragdoll
