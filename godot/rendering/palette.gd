class_name Palette
extends RefCounted
## Ports rendering/Palette.ts's named color tokens verbatim (build-order
## step 7). Kept as plain hex STRINGS, not pre-built Color objects — a
## top-level const Color(...) call is still a function call evaluated at
## this script's own load time, and there's no reason to risk that when
## every call site can just wrap the string in Color(...) itself, exactly
## as enemy.gd already does today with EnemyDefinition.color.

const VOID := "#07060a"
const BG0 := "#0b0a10"
const BG1 := "#14121a"
const BG2 := "#1d1a24"
const BG3 := "#29242f"

const EMBER1 := "#3a1608"
const EMBER2 := "#8a2e10"
const EMBER3 := "#e8542a"
const EMBER4 := "#ff7b3d"
const EMBER5 := "#ffab54"
const EMBER6 := "#ffd9a0"

const GOLD := "#d4af6a"
const GOLD_DIM := "#8a7248"
const GOLD_BRIGHT := "#f2d38f"

const BLOOD := "#c0392b"
const BLOOD_BRIGHT := "#e74c3c"

const SOUL := "#9b7ed9"
const SOUL_DIM := "#6a5596"
const SOUL_BRIGHT := "#c4b0f0"

const FROST := "#6fc3d9"
const TOXIC := "#7dd35a"
const SHADOW := "#4a3d63"

## The Hollow Ruins' living light — cold fungal bioluminescence, the
## deliberate opposite of the Warden's warm ember glow.
const FUNGUS := "#6fe3c4"
const FUNGUS_DIM := "#2f6e5c"
const FUNGUS_BRIGHT := "#b9f5e2"

const TEXT_WARM := "#ece3d2"

const SHADOW_COLOR := VOID

## ---------------------------------------------------------------- UI tokens
## Ports style.css's :root custom properties (build-order step 9) not
## already covered by a rendering token above — TEXT_WARM already matches
## --c-text exactly, and every --c-ember/gold/blood/soul/frost/toxic value
## above is the same token CSS and this file both draw from, so this block
## only adds what UI screens need that gameplay rendering never did: panel/
## border chrome and the two dimmer text tones. PANEL is 8-digit ARGB-in-hex
## (style.css's own #16141dee, includes an alpha byte) — Godot's Color(String)
## constructor reads the trailing 2 hex digits as alpha the same way.
const PANEL := "#16141dee"
const PANEL_SOLID := "#17151f"
const BORDER := "#3a3244"
const BORDER_LIT := "#6b5a3f"
const TEXT_DIM := "#a89a84"
const TEXT_FAINT := "#6e6459"

## Ports data/types.ts's RARITY_COLORS — chest_node.gd's own _tier_color()
## (build-order step 7) already carries this exact table locally since
## lighting/rendering needed it before this UI pass existed; kept here too,
## as the canonical copy every UI screen reads, rather than reaching into a
## world-node script for a color table that belongs in the shared palette.
const RARITY_COMMON := "#b9b3a6"
const RARITY_UNCOMMON := "#6fd17a"
const RARITY_RARE := "#5aa9e6"
const RARITY_EPIC := "#b06de0"
const RARITY_LEGENDARY := "#f2b53d"

static func rarity_color(rarity: UpgradeDefinition.Rarity) -> String:
	match rarity:
		UpgradeDefinition.Rarity.COMMON: return RARITY_COMMON
		UpgradeDefinition.Rarity.UNCOMMON: return RARITY_UNCOMMON
		UpgradeDefinition.Rarity.RARE: return RARITY_RARE
		UpgradeDefinition.Rarity.EPIC: return RARITY_EPIC
		UpgradeDefinition.Rarity.LEGENDARY: return RARITY_LEGENDARY
		_: return "#ffffff"
