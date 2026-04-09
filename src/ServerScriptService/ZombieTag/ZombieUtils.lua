local ZombieUtils = {}

function ZombieUtils.computeSurfaceCFrameForObject(object, offset, config)
	if not object then
		return nil
	end

	offset = offset or 0
	local extraHeight = (config and config.RespawnExtraHeight) or 0

	local baseCFrame
	local size

	if object:IsA("BasePart") then
		baseCFrame = object.CFrame
		size = object.Size
	elseif object:IsA("Model") then
		local success, cf, boundsSize = pcall(object.GetBoundingBox, object)
		if not success then
			return nil
		end
		baseCFrame = cf
		size = boundsSize
	else
		return nil
	end

	local up = baseCFrame.UpVector.Unit
	local position = baseCFrame.Position + up * ((size.Y / 2) + offset + extraHeight)
	return CFrame.fromMatrix(position, baseCFrame.XVector, baseCFrame.YVector, baseCFrame.ZVector)
end

function ZombieUtils.findFirstDescendant(instance, predicate)
	if not instance then
		return nil
	end
	if predicate(instance) then
		return instance
	end
	for _, descendant in ipairs(instance:GetDescendants()) do
		if predicate(descendant) then
			return descendant
		end
	end
	return nil
end

function ZombieUtils.gatherDescendants(instance, predicate)
	local results = {}
	if not instance then
		return results
	end
	if predicate(instance) then
		table.insert(results, instance)
	end
	for _, descendant in ipairs(instance:GetDescendants()) do
		if predicate(descendant) then
			table.insert(results, descendant)
		end
	end
	return results
end

function ZombieUtils.teleportCharacterToCFrame(character: Model?, targetCFrame: CFrame?, config: table?)
	if not character or not targetCFrame then
		return false
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not rootPart then
		return false
	end

	humanoid.PlatformStand = true
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0

	rootPart.CFrame = targetCFrame
	rootPart.AssemblyLinearVelocity = Vector3.zero

	task.defer(function()
		if humanoid.Parent then
			humanoid.PlatformStand = false
			humanoid.WalkSpeed = (config and config.PlayerDefaultWalkSpeed) or 16
			humanoid.JumpPower = (config and config.PlayerDefaultJumpPower) or 50
		end
	end)

	return true
end

return ZombieUtils

