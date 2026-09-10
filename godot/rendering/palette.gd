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
