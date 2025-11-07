# Level Management System

This document explains how to set up and use the level management system in SkyLeap.

## Overview

The Level Management System handles:
- **Level Organization**: Structured level folders in Workspace
- **Player Progression**: Tracks completed levels and best times
- **Level Unlocking**: Unlocks levels based on completion requirements
- **Rewards**: Awards coins, diamonds, and XP on level completion
- **Spawn Management**: Automatically spawns players at the correct level

## Best Practices for Roblox Obstacle Course Games

Based on industry standards and Roblox best practices:

1. **Organized Structure**: Use a clear folder hierarchy for levels
2. **Metadata System**: Store level information in attributes (no hardcoding)
3. **Progression Tracking**: Save completion data to DataStore
4. **Unlock System**: Gate levels behind completion requirements
5. **Performance**: Use tags for efficient detection instead of name-based searches
6. **Modularity**: Keep level-specific logic separate from core systems

## Setup Instructions

### 1. Create Levels Folder Structure

In Roblox Studio, create the following structure in Workspace:

```
Workspace/
  Levels/ (Folder)
    Level_1/ (Model or Folder) ✅ Both work!
      Spawn/ (BasePart or Model)
      Finish/ (BasePart or Model)
      [Level geometry, obstacles, checkpoints, etc.]
    Level_2/ (Model or Folder)
      ...
```

**Important**: 
- The folder must be named exactly `Levels` (case-sensitive).
- Level containers can be either **Model** or **Folder** - both work perfectly!
  - **Folder**: Simpler, lighter weight, just for organization
  - **Model**: Has PrimaryPart feature (useful if you need to move/position the entire level, but not required)

### 2. Configure Level Attributes

For each level (the Model or Folder), set the following attributes:

#### Required Attributes:
- **LevelId** (string): Unique identifier (e.g., "Level_1", "Desert_Temple")
- **LevelName** (string): Display name shown to players (e.g., "The Beginning", "Desert Temple")
- **LevelNumber** (number): Sequential number for unlocking (1, 2, 3, ...)

#### Optional Attributes:
- **Difficulty** (string): "Easy", "Medium", "Hard", "Extreme" (default: "Easy")
- **RequiredLevel** (number): Minimum completed level number to unlock this level
  - If not set, defaults to previous level (Level 2 requires Level 1, etc.)
  - Level 1 is always unlocked
- **CoinsReward** (number): Coins awarded on first completion (default: 0)
- **DiamondsReward** (number): Diamonds awarded on first completion (default: 0)
- **XPReward** (number): XP awarded on first completion (default: 0)

**Example Setup in Studio:**
1. Select your level Model/Folder
2. Open Properties window
3. Add Attributes:
   - `LevelId` = "Level_1"
   - `LevelName` = "The Beginning"
   - `LevelNumber` = 1
   - `Difficulty` = "Easy"
   - `CoinsReward` = 100
   - `DiamondsReward` = 5

### 3. Set Up Spawn Points

Each level needs a spawn point where players start. Two methods:

#### Method 1: Using CollectionService Tag (Recommended)
1. Create a BasePart or Model named "Spawn" (or any name)
2. Add the `LevelSpawn` tag using CollectionService
3. Position it where players should spawn

#### Method 2: Using Named Child
1. Create a BasePart or Model named exactly "Spawn"
2. Place it as a child of the level folder
3. The system will automatically detect it

**Spawn Position:**
- For BasePart: Uses the part's Position
- For Model: Uses PrimaryPart Position, or first BasePart found

### 4. Set Up Finish Points

Each level needs a finish point where players complete the level. Two methods:

#### Method 1: Using CollectionService Tag (Recommended)
1. Create a BasePart or Model named "Finish" (or any name)
2. Add the `LevelFinish` tag using CollectionService
3. Position it at the end of the level

#### Method 2: Using Named Child
1. Create a BasePart or Model named exactly "Finish"
2. Place it as a child of the level folder
3. The system will automatically detect it

**Finish Detection:**
- When a player's character touches the finish, the level is completed
- Completion time is tracked and saved as best time
- Rewards are awarded on first completion only

### 5. Integration with Checkpoints

The Level System works seamlessly with the existing Checkpoint System:
- Checkpoints within levels work as normal
- Players respawn at their last checkpoint within the current level
- Level completion requires reaching the Finish point

## Level Structure Example

Here's a complete example of a properly configured level:

```
Workspace/
  Levels/
    Level_1/ (Model or Folder - both work!)
      Attributes:
        - LevelId = "Level_1"
        - LevelName = "The Beginning"
        - LevelNumber = 1
        - Difficulty = "Easy"
        - CoinsReward = 100
        - DiamondsReward = 5
      
      Spawn/ (BasePart with "LevelSpawn" tag)
        Position: (0, 5, 0)
      
      Finish/ (BasePart with "LevelFinish" tag)
        Position: (100, 5, 0)
      
      Checkpoint_1/ (Model with "Checkpoint" tag)
        Position: (30, 5, 0)
      
      Checkpoint_2/ (Model with "Checkpoint" tag)
        Position: (60, 5, 0)
      
      [Level geometry, obstacles, etc.]
```

**Note**: Level containers can be either **Folder** (recommended) or **Model**. Both work identically - use Folder for simple organization, or Model if you need PrimaryPart functionality.

## Player Progression

### Data Storage

Level progression is saved in the player's profile:
```lua
profile.progression = {
    completedLevels = {
        ["1"] = true,  -- Level 1 completed
        ["2"] = true,  -- Level 2 completed
    },
    levelTimes = {
        ["1"] = 45,  -- Best time for Level 1: 45 seconds
        ["2"] = 120, -- Best time for Level 2: 120 seconds
    },
}
```

### Unlocking System

Levels unlock based on:
1. **Level 1**: Always unlocked
2. **Subsequent Levels**: 
   - If `RequiredLevel` attribute is set, that level must be completed
   - Otherwise, previous level must be completed (Level 2 requires Level 1, etc.)

### Completion Rewards

- **First Completion**: Awards coins, diamonds, and XP
- **Subsequent Completions**: No rewards, but best time is still tracked
- **Best Time**: Only updated if new completion time is faster

## Usage in Code

### Server-Side

```lua
local LevelSystem = require(ServerScriptService.LevelSystem)

-- Get player's current level
local currentLevel = LevelSystem.getPlayerLevel(player)

-- Get all levels
local allLevels = LevelSystem.getAllLevels()

-- Get level metadata
local metadata = LevelSystem.getLevelMetadata("Level_1")
-- Returns: { id, name, number, difficulty, requiredLevel, coinsReward, etc. }

-- Check if level is unlocked
local isUnlocked = LevelSystem.isLevelUnlocked(player, "Level_1")

-- Spawn player at level
LevelSystem.spawnPlayerAtLevel(player, "Level_1")
```

### Client-Side (RemoteEvents)

The system creates RemoteEvents that can be used from the client:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Select a level (fires to server)
local levelSelect = Remotes:WaitForChild("SelectLevel")
levelSelect:FireServer("Level_1")

-- Listen for level completion
local levelComplete = Remotes:WaitForChild("LevelComplete")
levelComplete.OnClientEvent:Connect(function(completionData)
    print("Completed level:", completionData.levelName)
    print("Time:", completionData.completionTime, "seconds")
    print("Best time:", completionData.bestTime, "seconds")
    print("Rewards:", completionData.coinsReward, "coins")
end)
```

## Player Flow

1. **Player Joins**: Automatically spawns at Level 1 (first level)
2. **Level Selection**: Players can select unlocked levels via RemoteEvent
3. **Playing**: Player navigates through level, hitting checkpoints
4. **Completion**: When player touches Finish, level completes
5. **Rewards**: First completion awards coins/diamonds/XP
6. **Unlock**: Next level unlocks automatically
7. **Respawn**: Player can press R to respawn at last checkpoint

## Advanced Features

### Custom Unlock Requirements

You can set custom unlock requirements using the `RequiredLevel` attribute:

```
Level_5:
  RequiredLevel = 3  -- Requires Level 3 completion, not Level 4
```

This allows for non-linear progression (branches, shortcuts, etc.).

### Multiple Spawn Points

If a level has multiple spawn points (e.g., after checkpoints), you can:
1. Use the Checkpoint System for respawning
2. Create multiple Spawn points and select one based on progress
3. The system uses the first spawn found, so organize accordingly

### Level-Specific Rewards

Different levels can award different amounts:

```
Level_1: CoinsReward = 100, DiamondsReward = 5
Level_2: CoinsReward = 150, DiamondsReward = 7
Level_3: CoinsReward = 200, DiamondsReward = 10
```

## Troubleshooting

### Level Not Found
- Ensure the `Levels` folder exists in Workspace
- Check that level folders are Models or Folders (not other types)
- Verify `LevelId` attribute matches what you're using in code

### Spawn Not Working
- Verify spawn point has `LevelSpawn` tag or is named "Spawn"
- Check that spawn is a child of the level folder
- Ensure spawn has a valid Position (BasePart) or PrimaryPart (Model)

### Finish Not Detecting
- Verify finish point has `LevelFinish` tag or is named "Finish"
- Check that finish is a child of the level folder
- Ensure finish parts have CanTouch = true
- Verify player's character is touching the finish part

### Level Not Unlocking
- Check `RequiredLevel` attribute (if set)
- Verify previous level is completed in player's profile
- Level 1 is always unlocked (no requirements)

### Rewards Not Awarding
- Rewards only awarded on **first completion**
- Check attribute values (CoinsReward, DiamondsReward, etc.)
- Verify PlayerProfile save is working
- Check server output for error messages

## Performance Considerations

1. **Level Loading**: Levels are loaded on server start (no runtime loading)
2. **Finish Detection**: Uses efficient CollectionService tags
3. **DataStore**: Level progression saved efficiently in batches
4. **Memory**: Player level state cleared on disconnect

## Future Enhancements

Potential improvements for the system:
- Level selection UI
- Level preview/minimap
- Leaderboards per level
- Level difficulty balancing
- Seasonal/event levels
- Level editor tools

## Integration with Other Systems

The Level System integrates with:
- **CheckpointSystem**: Respawn at checkpoints within levels
- **PlayerProfile**: Saves level progression
- **Currency System**: Awards coins/diamonds on completion
- **KillerSystem**: Death resets to checkpoint (within level)
- **Movement Systems**: All movement abilities work within levels

## Best Practices Summary

1. ✅ Use clear, consistent naming: `Level_1`, `Level_2`, etc.
2. ✅ Set all required attributes for each level
3. ✅ Use CollectionService tags for spawn/finish (recommended)
4. ✅ Test unlock requirements thoroughly
5. ✅ Balance rewards with level difficulty
6. ✅ Keep level geometry organized in the level folder
7. ✅ Test spawn and finish detection in play mode
8. ✅ Verify progression saves correctly

