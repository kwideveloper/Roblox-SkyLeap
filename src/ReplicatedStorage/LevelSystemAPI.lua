-- LevelSystemAPI
-- Shared module that exposes LevelSystem functions to other scripts
-- This allows Scripts to access LevelSystem functionality without requiring it

local LevelSystemAPI = {}

-- These will be set by LevelSystem.server.lua when it loads
LevelSystemAPI.getPlayerLevel = nil
LevelSystemAPI.getAllLevels = nil
LevelSystemAPI.getLevelMetadata = nil
LevelSystemAPI.isLevelUnlocked = nil
LevelSystemAPI.spawnPlayerAtLevel = nil

-- Function to register LevelSystem functions (called by LevelSystem.server.lua)
function LevelSystemAPI.register(api)
	LevelSystemAPI.getPlayerLevel = api.getPlayerLevel
	LevelSystemAPI.getAllLevels = api.getAllLevels
	LevelSystemAPI.getLevelMetadata = api.getLevelMetadata
	LevelSystemAPI.isLevelUnlocked = api.isLevelUnlocked
	LevelSystemAPI.spawnPlayerAtLevel = api.spawnPlayerAtLevel
	print("[LevelSystemAPI] Functions registered")
end

-- Helper function to check if API is ready
function LevelSystemAPI.isReady()
	return LevelSystemAPI.getPlayerLevel ~= nil
end

return LevelSystemAPI

