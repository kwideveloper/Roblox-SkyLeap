# ViewModel Skin Animation Guide

This guide explains how to create static and animated skins for weapon viewmodels.

## Folder structure

Base path:

- `ReplicatedStorage/ViewModels/<WeaponViewModel>/Skins/<SkinName>/`

Two supported layouts (you can mix them in the same skin):

### Flat (recommended)

Put each layer template **directly under** `<SkinName>`:

- `Skins/MySkin/BodySkin` (UnionOperation, MeshPart, Part, or Model)
- `Skins/MySkin/BarrelSkin`
- `Skins/MySkin/MuzzleSkin`  
  …

The name **must** be `<LayerName>Skin` (e.g. `Body` → `BodySkin`). That maps to `Gun/BodySkin` on the viewmodel.

### Nested (legacy)

Optional intermediate folders:

- `Body`, `Barrel`, `Scope`, `Handle`, `Mount`, `Heel`, `Magazine`, `Muzzle`, …

If a **folder** named `Body` exists (and its name does **not** end with `Skin`), the system maps it to `Gun/BodySkin` and looks for a template **inside** that folder.

## Skin block (recommended)

**Flat:** the `BodySkin` / `BarrelSkin` instance **is** the template root (appearance + child `Texture` / `Decal`).

**Nested:** inside each layer folder, add one **template** instance:

- Prefer **`<LayerName>Skin`** (e.g. `BodySkin` inside folder `Body`).
- If that name is missing, the first child **Part / UnionOperation / Model** whose name **ends with `Skin`** is used (one-off layouts).

From that template, the game **copies only visual properties** onto the real `Gun` mount’s **BasePart** (the part you parent surfaces to):

**Appearance (copied to every `BasePart` under the real `Gun/<Layer>Skin` mount, matching the skin template’s main *Skin part):**  
`BrickColor`, `CastShadow`, `Color`, `DoubleSided` (if applicable), `Material`, `MaterialVariant`, `Reflectance`, `RenderFidelity`, `SmoothingAngle`, `Transparency`, and **Data** `UsePartColor`.  
Unknown or invalid properties for a part type are safely skipped (e.g. `DoubleSided` on a plain `Part`).

If the real gun uses a **Model** for `BodySkin` with a `Union` / `MeshPart` child, the game picks that child as the **parent** for `Texture` / `Decal` / `SurfaceAppearance` clones, and the same look is applied to **all** `BasePart` descendants of that `BodySkin` model.

**SurfaceAppearance** children under the template `*Skin` are also cloned onto that parent part (in addition to `Texture` / `Decal`).

**Opacity / transparency:** the template *Skin’s* `Transparency` is now copied to the real parts so the result matches the skin definition. If your ReplicatedStorage block was invisible in Studio, set its transparency in the skin to what you want on the final gun (e.g. `0`).

Then every `Texture` and `Decal` **under that template** (descendants) is **cloned** and parented **into** the real `BodySkin` / `BarrelSkin` part on the gun.

Example layouts:

- Flat: `Skins/MySkin/BarrelSkin` (UnionOperation) with child `Texture` objects.
- Nested: `Skins/MySkin/Barrel/BarrelSkin` (UnionOperation) with child `Texture` objects.

At runtime: the template `BarrelSkin` donates appearance → real `Gun/BarrelSkin`; textures are cloned as children of the real part.

## Legacy layout (no `*Skin` part)

If the layer folder has **no** `*Skin` template, the old behavior still works: any `Texture` / `Decal` **anywhere** in that layer folder is cloned onto the mount (no property copy).

If a mount does not exist, that layer is skipped (no crash).

## What can be inside a skin `*Skin` block

Supported surface objects (cloned to the real gun part):

- `Texture`
- `Decal`

## Texture scroll animation (synchronized per `*Skin` mount)

All `Texture` objects parented to the same gun part (e.g. all children of `Gun/BodySkin`) **scroll together** with the same offset when animation is configured from the skin data (see priority below). That keeps emissive / detail layers aligned.

**Note:** only `Texture` instances get UV scroll (`OffsetStudsU` / `OffsetStudsV`). `Decal` is not driven by this animator.

On **`UnionOperation`** mounts, static skins often convert `Texture` → `Decal` so the image is visible. If this layer (or the skin root) has **any** of the three animation attributes, that conversion is **skipped** so `Texture` objects remain and the animator can run (trade-off: on some unions tiled `Texture` may still be hard to see — a `MeshPart` / `Part` `*Skin` mount is more reliable for both visibility and scroll).

### Where to put `Animation`, `AnimationSpeedU`, `AnimationSpeedV`

Attributes are read from **one** source per layer, in this **priority order** (first match wins):

1. **Layer config root** — nested: attributes on the **layer folder** `Skins/MySkin/Body`. Flat: attributes on the **template part** `Skins/MySkin/BodySkin` (the Union / Model / etc.). That config applies **only** to `Gun/BodySkin` for that layer.
2. **`<LayerName>Part`** — nested: `BodyPart` inside `Skins/MySkin/Body`. Flat: `BodyPart` as a **sibling** next to `BodySkin` under `Skins/MySkin` (same names as nested).
3. **The skin root folder** — e.g. `Skins/MySkin`. If a layer has **no** animation attributes on (1) or (2), it **falls back** to the skin root so one set of attributes can drive **every** layer’s `Gun/*Skin` mount that did not define its own.

Attribute names (on the Folder or `*Part` instance):

- `Animation` (boolean) — `true` / `false` to force on or off
- `AnimationSpeedU` (number) — studs/second for `OffsetStudsU` (shared by all `Texture` children on that mount)
- `AnimationSpeedV` (number) — studs/second for `OffsetStudsV` (shared)

On runtime, these attributes are **copied onto the real** `Gun/<Layer>Skin` **BasePart**; the client animator reads them from that part.

If `Animation` is omitted, animation turns on when at least one of `AnimationSpeedU` or `AnimationSpeedV` is set on the chosen source.

## Animated skin textures (implementation)

Animation is applied to cloned `Texture` instances by updating:

- `OffsetStudsU`
- `OffsetStudsV`

### Legacy: per-Texture attributes (no layer / skin / `*Part` config)

If the mount **BasePart** (`BodySkin` on the gun) has **none** of the three attributes after the copy step, you can still set them on each `Texture` (each texture can animate independently, old behavior).

### Optional per-texture attributes

- `Animation` (`bool`)
  - `true`: force enable animation
  - `false`: force disable animation
- `AnimationSpeedU` (`number`)
  - U axis scroll speed in studs/second
- `AnimationSpeedV` (`number`)
  - V axis scroll speed in studs/second

## Global defaults (`Config.lua`)

These defaults apply when a texture does not override with attributes:

- `SniperViewModelSkinTextureAnimationEnabled` (default `true`)
- `SniperViewModelSkinAnimDefaultSpeedU` (default `0`)
- `SniperViewModelSkinAnimDefaultSpeedV` (default `0`)

Recommended pattern:

- Keep `Config` default speeds at `0`.
- Put scroll speeds on the **layer Folder** (per mount) or on the **skin root Folder** (all mounts), or override per `Texture` only when needed.

## Quick recipes

Slow horizontal flow on **Body only** (attrs on folder `Skins/MySkin/Body`):

- `Animation = true`
- `AnimationSpeedU = 0.35`
- `AnimationSpeedV = 0`

Same motion on **every layer** that has a `*Skin` mount (attrs on folder `Skins/MySkin`):

- Same three attributes on the **skin root** folder; leave layer folders without animation attrs (unless you want a layer to override — then set attrs on that layer folder and it wins for that mount only).

Vertical energy pulse:

- `Animation = true`
- `AnimationSpeedU = 0`
- `AnimationSpeedV = 0.7`

Diagonal movement:

- `Animation = true`
- `AnimationSpeedU = 0.45`
- `AnimationSpeedV = -0.2`
