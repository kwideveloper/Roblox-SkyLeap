# Sniper `Gun` Attributes Guide

This document explains the supported attributes on the `Gun` model used by the sniper system.

## Where to set them

- Template path: `ReplicatedStorage/ViewModels/<YourViewModel>/Gun`
- Type: all attributes are `Number` attributes.
- Scope: optional. If missing, the system uses defaults from `src/ReplicatedStorage/Sniper/Config.lua`.

## Supported attributes

- `MagazineSize`
  - Meaning: rounds per magazine.
  - Default: `Config.SniperDefaultMagazineSize` (default project value: `1`).
  - Validation: rounded to nearest integer and clamped to minimum `1`.

- `ReloadDuration`
  - Meaning: reload duration in seconds.
  - Default: if missing, uses `ReloadTime`; if both are missing, uses `Config.ReloadSeconds` (default project value: `1.2`).
  - Validation: clamped to minimum `0.05`.

- `ReloadTime`
  - Meaning: legacy alias for reload duration.
  - Default: only used when `ReloadDuration` is not provided.
  - Validation: same as `ReloadDuration`.

- `ShotCooldown`
  - Meaning: time between accepted shots in seconds.
  - Priority: highest for fire cadence. If `ShotCooldown > 0`, it overrides `FireRate`.
  - Default: computed from `FireRate` when `ShotCooldown` is missing/invalid; otherwise fallback logic is used.
  - Validation: clamped to minimum `0.02`.

- `FireRate`
  - Meaning: rounds per second.
  - Used when: `ShotCooldown` is not set or is `<= 0`.
  - Conversion: `shotCooldown = 1 / FireRate`.
  - Fallback: if both `ShotCooldown` and `FireRate` are not usable, cooldown falls back to:
    - `1 / Config.SniperDefaultFireRate` if `SniperDefaultFireRate > 0`
    - otherwise `reloadDuration`.

- `Damage`
  - Meaning: damage per hit.
  - Default: `0`.
  - Special behavior:
    - `Damage <= 0` means instant lethal hit (sets humanoid health to `0`).
    - `Damage > 0` subtracts exact amount from current health.
  - Validation: negative values are normalized to `0` (lethal behavior).

## Resolution order and fallbacks

The system reads stats from the live local viewmodel `Gun` (client-side when available) or from the template/tool-resolved `Gun` model.

For fire cadence:

1. `ShotCooldown` (if `> 0`)
2. `FireRate` (if `> 0`, converted to cooldown)
3. `Config.SniperDefaultFireRate` (if `> 0`, converted to cooldown)
4. `reloadDuration` fallback

For reload duration:

1. `ReloadDuration`
2. `ReloadTime`
3. `Config.ReloadSeconds`

## Tool replicated runtime attributes (read-only from gameplay perspective)

These are set by the server on the sniper `Tool` for HUD/state sync. Do not author them manually on `Gun`.

- `SniperAmmo`
- `SniperMagSize`
- `SniperReloadEndsAtServer`
- `SniperNextShotAtServer`

## Example presets

## Bolt-action style

- `MagazineSize = 1`
- `ReloadDuration = 1.2`
- `ShotCooldown = 1.0`
- `Damage = 0` (lethal)

## Fast sniper style

- `MagazineSize = 5`
- `ReloadDuration = 1.8`
- `FireRate = 1.6`
- `Damage = 65`

## Precision slow heavy

- `MagazineSize = 3`
- `ReloadDuration = 2.4`
- `ShotCooldown = 1.4`
- `Damage = 100`

## Notes

- Keep all values numeric and finite.
- If a value is invalid (`NaN`, infinite, wrong type), the system silently uses fallback defaults.
- `ReloadDuration` is the preferred modern name; keep `ReloadTime` only for backward compatibility.
