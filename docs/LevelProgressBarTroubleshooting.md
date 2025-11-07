# Level Progress Bar - Troubleshooting Guide

## Problemas Comunes y Soluciones

### 1. No se muestra la barra de progreso

**Síntomas:** No ves la barra de progreso cuando estás en un nivel.

**Soluciones:**
1. **Verifica que los scripts estén en los lugares correctos:**
   - `LevelSystem.server.lua` debe estar en `ServerScriptService`
   - `LevelProgressTracker.server.lua` debe estar en `ServerScriptService`
   - `LevelProgressUI.client.lua` debe estar en `StarterPlayer/StarterPlayerScripts`

2. **Verifica la estructura del nivel:**
   - Asegúrate de que existe `workspace.Levels/Level_1/`
   - Debe haber una parte llamada `Spawn` (o con tag `LevelSpawn`)
   - Debe haber una parte llamada `Finish` (o con tag `LevelFinish`)

3. **Revisa la consola de Output:**
   - Busca mensajes que empiecen con `[LevelSystem]` o `[LevelProgressTracker]`
   - Deberías ver: `"Started tracking player [Nombre] in level Level_1"`
   - Si ves warnings, lee el mensaje para entender el problema

4. **Verifica que el RemoteEvent existe:**
   - En `ReplicatedStorage/Remotes` debe existir `LevelProgressUpdate`
   - Si no existe, se crea automáticamente, pero verifica que esté ahí

### 2. El Finish no funciona (no te lleva al siguiente nivel)

**Síntomas:** Tocar la parte Finish no completa el nivel.

**Soluciones:**
1. **Verifica el nombre de la parte:**
   - La parte debe llamarse exactamente `"Finish"` (case-sensitive)
   - O debe tener el tag `LevelFinish` usando CollectionService

2. **Verifica que la parte tenga CanTouch = true:**
   - Selecciona la parte Finish
   - En Properties, verifica que `CanTouch` esté marcado

3. **Verifica que estés tocando la parte correcta:**
   - Asegúrate de que tu personaje está realmente tocando la parte Finish
   - Puedes hacer la parte más grande para facilitar el contacto

4. **Revisa la consola:**
   - Deberías ver: `"[LevelSystem] Player [Nombre] touched finish for level: Level_1"`
   - Si no ves este mensaje, el finish no se está detectando

5. **Verifica los atributos del nivel:**
   - El nivel debe tener `LevelId = "Level_1"`
   - El nivel debe tener `LevelNumber = 1`

### 3. No hay teleportación automática al siguiente nivel

**Síntomas:** Completes el nivel pero no te teleporta automáticamente.

**Soluciones:**
1. **Verifica que existe un siguiente nivel:**
   - Debe existir `Level_2` con `LevelNumber = 2`
   - El siguiente nivel debe estar desbloqueado (Level 1 completado)

2. **Espera 2 segundos:**
   - Hay un delay de 2 segundos antes de teleportar
   - Esto es para mostrar el mensaje de completación

3. **Verifica en la consola:**
   - Deberías ver: `"[LevelSystem] Auto-teleported [Nombre] to next level: Level_2"`

### 4. Los avatares de otros jugadores no aparecen

**Síntomas:** Solo ves tu propio avatar en la barra de progreso.

**Soluciones:**
1. **Verifica que hay otros jugadores en el mismo nivel:**
   - Todos los jugadores deben estar en el mismo nivel para verse
   - La barra solo muestra jugadores en tu nivel actual

2. **Verifica que el RemoteEvent esté funcionando:**
   - Todos los jugadores deben recibir actualizaciones del servidor
   - Revisa que no haya errores en la consola

### 5. La barra de progreso muestra posiciones incorrectas

**Síntomas:** Tu posición en la barra no coincide con tu posición real.

**Soluciones:**
1. **Verifica que Spawn y Finish estén bien posicionados:**
   - El sistema calcula el progreso basándose en la línea desde Spawn a Finish
   - Si te desvías mucho de esta línea, el progreso puede ser incorrecto

2. **Verifica que las posiciones estén bien:**
   - Spawn y Finish deben estar en posiciones válidas
   - No deben estar en el mismo lugar

## Estructura Requerida

```
Workspace/
  Levels/ (Folder)
    Level_1/ (Folder o Model)
      Attributes:
        - LevelId = "Level_1"
        - LevelName = "First Level"
        - LevelNumber = 1
        - CoinsReward = 500
        - DiamondsReward = 10
        - Difficulty = "Easy"
      
      Spawn/ (BasePart) - Nombre exacto "Spawn"
        - CanTouch = true
        - Position = (tu posición de spawn)
      
      Finish/ (BasePart) - Nombre exacto "Finish"
        - CanTouch = true
        - Position = (tu posición de finish)
```

## Mensajes de Debug

Busca estos mensajes en la consola de Output:

### Mensajes exitosos:
- `[LevelSystem] Initializing X levels...`
- `[LevelSystem] Found finish for level: Level_1`
- `[LevelSystem] Player [Nombre] spawned at level: First Level (Level_1)`
- `[LevelProgressTracker] Started tracking player [Nombre] in level Level_1`
- `[LevelSystem] Player [Nombre] touched finish for level: Level_1`
- `[LevelSystem] Player [Nombre] completed level: First Level in X seconds`
- `[LevelSystem] Auto-teleported [Nombre] to next level: Level_2`

### Mensajes de error/warning:
- `[LevelSystem] Levels folder 'Levels' not found in workspace` - Crea la carpeta Levels
- `[LevelSystem] No spawn point found for level: Level_1` - Falta la parte Spawn
- `[LevelSystem] No finish point found for level: Level_1` - Falta la parte Finish
- `[LevelProgressTracker] Could not find spawn or finish` - Verifica nombres/posiciones

## Checklist Rápido

- [ ] Existe `workspace.Levels/Level_1/`
- [ ] El nivel tiene los atributos requeridos (LevelId, LevelName, LevelNumber)
- [ ] Existe una parte `Spawn` dentro de `Level_1`
- [ ] Existe una parte `Finish` dentro de `Level_1`
- [ ] Las partes Spawn y Finish tienen `CanTouch = true`
- [ ] Los scripts están en los lugares correctos
- [ ] No hay errores en la consola de Output
- [ ] Si hay Level_2, tiene `LevelNumber = 2`

