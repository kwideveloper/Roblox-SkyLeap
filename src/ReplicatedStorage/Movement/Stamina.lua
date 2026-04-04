-- Stamina handling utilities

local Config = require(game:GetService("ReplicatedStorage").Movement.Config)

local Stamina = {}

local function isSystemEnabled()
	return Config.StaminaEnabled == true
end

function Stamina.isSystemEnabled()
	return isSystemEnabled()
end

function Stamina.create()
	return {
		current = Config.StaminaMax,
		isSprinting = false,
	}
end

function Stamina.canStartSprint(stamina)
	if not isSystemEnabled() then
		return true
	end
	return stamina.current >= Config.SprintStartThreshold
end

function Stamina.setSprinting(stamina, enabled)
	if not isSystemEnabled() then
		stamina.isSprinting = enabled == true
		return stamina.isSprinting
	end
	stamina.isSprinting = enabled and Stamina.canStartSprint(stamina)
	return stamina.isSprinting
end

function Stamina.tick(stamina, dt)
	if not isSystemEnabled() then
		stamina.current = Config.StaminaMax
		return stamina.current, stamina.isSprinting
	end
	if stamina.isSprinting then
		stamina.current = stamina.current - (Config.SprintDrainPerSecond * dt)
		if stamina.current <= 0 then
			stamina.current = 0
			stamina.isSprinting = false
		end
	else
		stamina.current = stamina.current + (Config.StaminaRegenPerSecond * dt)
		if stamina.current > Config.StaminaMax then
			stamina.current = Config.StaminaMax
		end
	end
	return stamina.current, stamina.isSprinting
end

-- Tick with explicit control over whether regeneration is allowed.
-- Draining still occurs when sprinting, but regen only happens when allowRegen is true.
function Stamina.tickWithGate(stamina, dt, allowRegen, isMoving)
	if not isSystemEnabled() then
		stamina.current = Config.StaminaMax
		return stamina.current, stamina.isSprinting
	end
	if stamina.isSprinting and (isMoving ~= false) then
		stamina.current = stamina.current - (Config.SprintDrainPerSecond * dt)
		if stamina.current <= 0 then
			stamina.current = 0
			stamina.isSprinting = false
		end
	elseif allowRegen then
		stamina.current = stamina.current + (Config.StaminaRegenPerSecond * dt)
		if stamina.current > Config.StaminaMax then
			stamina.current = Config.StaminaMax
		end
	end
	return stamina.current, stamina.isSprinting
end

return Stamina
