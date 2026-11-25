# Source and modifications

SparkleBoost is distributed under GPL-3.0-or-later. The full license is in `LICENSE`.

`Engine.lua` adapts target discovery, cursor/quest classification, state smoothing,
and pause/recovery logic from:

- N3zr0k, `ForeverLootSparkles_Coloring/ Sparkles.lua`, blob
  `52d93bfc9484e9b8f8fd37e6d2a93996b82d2eba`, read 2026-11-16:
  https://github.com/N3zr0k/ForeverLootSparkles_Coloring/blob/main/ForeverLootSparkles_Coloring/Sparkles.lua
- That source credits Forever Loot Sparkles 1.3.1 (`SoftTarget.lua`) and Lueur.
  Forever Loot Sparkles is maintained by Sven / svengabr / conoar:
  https://github.com/svengabr/ForeverLootSparkles

SparkleBoost changes, by Sola, 2026:

- A standalone addon with no required addon dependency.
- Separate opt-in enhancement, Chinese controls and a live UI preview.
- New adjustable glint, beacon and ring renderer with generated TGA assets.
- Per-character CVar ownership journal; conditional restoration preserves later edits.
- CVar allowlist, interface 16001 guard, conflict detection and combat deferral.
- No writes to global outline or self-highlight settings.
- Matching a fallback nameplate to the current interaction target, and releasing
  cached nameplates after the game has removed their lookup entry.
- Regression scenarios and packaging checks in the accompanying repository.

The separate native sparkle toggle was informed by reading the original addon;
SparkleBoost implements its own lifecycle and ownership handling.

SparkleBoost 0.1.1-test changes, by Solazhu, 2026-11-16:

- A minimap settings button with draggable, per-character position persistence.
- Regression coverage for clicks, scaled dragging, saved positions and drag cleanup.

Primary implementation references:

- https://www.curseforge.com/wow/addons/forever-loot-sparkles
- https://www.curseforge.com/wow/addons/forever-loot-sparkles-herbs-ores
- https://www.curseforge.com/wow/addons/lueur
- https://github.com/Gethe/wow-ui-source/tree/forever/Interface/AddOns/Blizzard_NamePlates
