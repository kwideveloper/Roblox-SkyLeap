-- Bomb Tag System Configuration
-- All values are configurable here

return {
	-- Initial countdown before game starts (in seconds)
	-- Note: This is now used for both waiting countdown and game start countdown (both 3 seconds)
	InitialCountdown = 3,
	-- Bomb countdown timer (in seconds)
	-- BombCountdown = 20,
	BombCountdown = 15,
	-- Coins awarded to the winner
	WinnerCoins = 500,
	-- Minimum players required to start the game
	MinPlayers = 2,
	-- Rounds system
	RoundsToWin = 1,
	RoundRespawnDelay = 2.5,
	RoundCooldown = 2.5,
	RespawnDelay = 2.5,
	LobbyReadyCountdown = 5,
	BombPassCooldown = 1,
	RespawnExtraHeight = 0.75,
	SpawnSurfaceOffset = 0,
	-- Bomb icon configuration
	BombIcon = {
		-- Icon ID (you can change this to any image ID)
		ImageId = "http://www.roblox.com/asset/?id=489938484",
		-- Size of the icon
		Size = UDim2.new(0, 32, 0, 32),
		-- Offset above player's head
		Offset = Vector3.new(0, 5, 0),
	},

	-- UI configuration
	UI = {
		-- Countdown text color
		CountdownColor = Color3.fromRGB(255, 100, 100),
		-- Bomb timer text color
		BombTimerColor = Color3.fromRGB(255, 50, 50),
		-- Winner text color
		WinnerColor = Color3.fromRGB(100, 255, 100),
	},

	-- Bomb holder speed boost (multiplier, e.g., 1.05 = 5% faster)
	BombHolderSpeedMultiplier = 1.05,

	-- Seconds an unready player has once the opposing side is ready
	ReadyTimeout = 10,
}
