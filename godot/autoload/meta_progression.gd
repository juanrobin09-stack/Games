extends Node
## Autoload: MetaProgression
##
## Ports progression/MetaProgression.ts + progression/SaveSystem.ts —
## permanent, cross-run state persisted to disk. Every mutation writes
## straight back to disk immediately (no batching, no dirty flag), matching
## the Web build's "every purchase is its own synchronous save" pattern.
## Unlike the rest of this scaffold, this autoload is genuinely complete,
## not a stub — save/load logic has no dependency on entities/rooms.

const SAVE_PATH: String = "user://save.json"
const SAVE_VERSION: int = 1

signal soul_ash_changed(new_total: int)
signal permanent_upgrade_purchased(id: String, new_level: int)
signal unlock_purchased(id: String)
signal settings_changed(patch: Dictionary)

var soul_ash: int = 0
## permanent-upgrade id (String) -> level purchased (int)
var permanent_levels: Dictionary = {}
## unlock id (String) -> true, for every purchased UnlockDefinition
var unlocks: Dictionary = {}
var lifetime_stats: Dictionary = {
	"runs_started": 0,
	"runs_won": 0,
	"total_kills": 0,
	"total_deaths": 0,
	"best_time_seconds": -1.0,
	"total_embers_collected": 0,
	"total_soul_ash_earned": 0,
}
## Ports SaveSystem.ts's SaveSettings. Most of these have no engine to act
## on yet in this port (see settings_ui.gd's own header for exactly which
## do and don't) — stored honestly either way, matching the save format the
## Settings screen needs, rather than omitting fields a future pass would
## just have to add back with a migration path.
var settings: Dictionary = {
	"master_volume": 1.0,
	"music_volume": 0.8,
	"sfx_volume": 0.9,
	"muted": false,
	"screen_shake": true,
	"particle_quality": "high",
	"graphics_quality": "high",
	"text_scale": 1.0,
	"high_contrast": false,
	"reduced_motion": false,
	"language": "en",
}
var hints_shown: Array[String] = []
var last_seed: String = ""

func _ready() -> void:
	load_save()

func add_soul_ash(amount: int) -> void:
	if amount <= 0:
		return
	soul_ash += amount
	lifetime_stats["total_soul_ash_earned"] = int(lifetime_stats["total_soul_ash_earned"]) + amount
	soul_ash_changed.emit(soul_ash)
	save()

func can_afford(cost: int) -> bool:
	return soul_ash >= cost

func get_permanent_level(id: String) -> int:
	return int(permanent_levels.get(id, 0))

## Ports MetaProgression.ts's getPermanentCost — null once maxed (matches
## the source's own `number | null`; Variant return lets this stay a real
## null rather than a magic sentinel int).
func get_permanent_cost(id: String) -> Variant:
	var def: PermanentUpgradeDefinition = DataRegistry.get_permanent_upgrade(id)
	if def == null:
		return null
	var level := get_permanent_level(id)
	if level >= def.max_level:
		return null
	return roundi(float(def.base_cost) * pow(def.cost_growth, level))

func can_purchase_permanent(id: String) -> bool:
	var def: PermanentUpgradeDefinition = DataRegistry.get_permanent_upgrade(id)
	if def == null:
		return false
	if def.requires != "" and get_permanent_level(def.requires) == 0:
		return false
	var cost = get_permanent_cost(id)
	return cost != null and soul_ash >= int(cost)

func purchase_permanent(id: String) -> bool:
	if not can_purchase_permanent(id):
		return false
	var cost = get_permanent_cost(id)
	if cost == null:
		return false
	soul_ash -= int(cost)
	var new_level := get_permanent_level(id) + 1
	permanent_levels[id] = new_level
	permanent_upgrade_purchased.emit(id, new_level)
	soul_ash_changed.emit(soul_ash)
	save()
	return true

## Ports MetaProgression.ts's getPermanentStatModifiers — the SAME
## modifiers array from a level-N upgrade is included N times (once per
## level owned, not once per upgrade), matching the source's own
## `for (i=0;i&lt;level;i++) mods.push(...def.modifiers)` exactly. Applied to a
## fresh StatBlock via StatBlock.apply_modifiers() at run start.
func get_permanent_stat_modifiers() -> Array[StatModifier]:
	var mods: Array[StatModifier] = []
	for def in DataRegistry.all("permanent_upgrades"):
		var upgrade_def := def as PermanentUpgradeDefinition
		var level := get_permanent_level(upgrade_def.id)
		for i in range(level):
			mods.append_array(upgrade_def.modifiers)
	return mods

func has_unlock(id: String) -> bool:
	return unlocks.get(id, false)

func can_purchase_unlock(id: String) -> bool:
	var def: UnlockDefinition = DataRegistry.get_unlock(id)
	if def == null:
		return false
	return not has_unlock(id) and soul_ash >= def.cost

func purchase_unlock(id: String) -> bool:
	if not can_purchase_unlock(id):
		return false
	var def: UnlockDefinition = DataRegistry.get_unlock(id)
	soul_ash -= def.cost
	unlocks[id] = true
	unlock_purchased.emit(id)
	soul_ash_changed.emit(soul_ash)
	save()
	return true

## Ports MetaProgression.ts's getUnlockedWeaponIds/getUnlockedAbilityIds —
## every purchased UnlockDefinition of the given kind, resolved to the
## WeaponDefinition/AbilityDefinition id it actually unlocks (ref_id), not
## the UnlockDefinition's own id.
func get_unlocked_weapon_ids() -> Array[String]:
	return _unlocked_ref_ids(UnlockDefinition.Kind.WEAPON)

func get_unlocked_ability_ids() -> Array[String]:
	return _unlocked_ref_ids(UnlockDefinition.Kind.ABILITY)

func _unlocked_ref_ids(kind: UnlockDefinition.Kind) -> Array[String]:
	var ids: Array[String] = []
	for def in DataRegistry.all("unlocks"):
		var unlock_def := def as UnlockDefinition
		if unlock_def.kind == kind and has_unlock(unlock_def.id):
			ids.append(unlock_def.ref_id)
	return ids

## Mirrors MetaProgression.ts's getUnlockedGateIds() — every UnlockDefinition
## id currently purchased. `unlocks` only ever holds true purchased ids (see
## purchase_unlock), so this is just its own keys; kept as a named method
## matching the TS source's own naming rather than inlining
## `MetaProgression.unlocks.keys()` at call sites (LevelFlow.current_gate_ids).
func get_unlocked_gate_ids() -> Array:
	return unlocks.keys()

## Ports MetaProgression.ts's recordRunEnd — call once per run, from
## LevelFlow.end_run(). best_time_seconds only updates on a WON run (a
## faster death isn't a "best time"), matching the source's own
## `if (opts.bossDefeated && ...)` gate exactly; -1.0 stands in for the
## source's `null` ("no time recorded yet") since Dictionary values here
## are typed loosely enough that a sentinel is simpler than a Variant field.
func record_run_end(kills: int, died: bool, boss_defeated: bool, time_seconds: float, embers_collected: int) -> void:
	lifetime_stats["runs_started"] = int(lifetime_stats["runs_started"]) + 1
	lifetime_stats["total_kills"] = int(lifetime_stats["total_kills"]) + kills
	if died:
		lifetime_stats["total_deaths"] = int(lifetime_stats["total_deaths"]) + 1
	if boss_defeated:
		lifetime_stats["runs_won"] = int(lifetime_stats["runs_won"]) + 1
	lifetime_stats["total_embers_collected"] = int(lifetime_stats["total_embers_collected"]) + embers_collected
	var best: float = float(lifetime_stats["best_time_seconds"])
	if boss_defeated and is_finite(time_seconds) and (best < 0.0 or time_seconds < best):
		lifetime_stats["best_time_seconds"] = time_seconds
	save()

func has_seen_hint(key: String) -> bool:
	return hints_shown.has(key)

func mark_hint_seen(key: String) -> void:
	if has_seen_hint(key):
		return
	hints_shown.append(key)
	save()

## Persists the current `settings` Dictionary — called by SettingsUI on
## every control change (matches the source's own persistSettings, which
## also writes on each SettingsMenu.onChange). Merges rather than replaces
## so a caller can hand over a partial patch.
func save_settings(patch: Dictionary) -> void:
	for key in patch.keys():
		settings[key] = patch[key]
	save()
	settings_changed.emit(patch)

func save() -> void:
	var data := {
		"version": SAVE_VERSION,
		"soul_ash": soul_ash,
		"permanent_levels": permanent_levels,
		"unlocks": unlocks,
		"lifetime_stats": lifetime_stats,
		"settings": settings,
		"hints_shown": hints_shown,
		"last_seed": last_seed,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("MetaProgression.save: could not open %s for writing (err %d)" % [SAVE_PATH, FileAccess.get_open_error()])
		return
	file.store_string(JSON.stringify(data))
	file.close()

## Ports SaveSystem.ts's own num()/bool() guards — TS's `typeof value ===
## 'number' && Number.isFinite(value)` check rejects anything that isn't a
## genuine finite number before ever using it. The GDScript equivalent
## isn't optional polish: confirmed via a real headless run, `int(null)`
## and `int({})` both abort with a hard "Invalid call. Nonexistent 'int'
## constructor" script error (there's no try/catch to fall back on here,
## unlike loadSave()'s own), and `int(NAN)`/`int(INF)` don't error at all
## — they silently return -9223372036854775808 (INT64_MIN), which every
## maxi(0, ...) call below happens to clamp back to a harmless 0, but a
## bare float field (settings, best_time_seconds) would carry a live NaN/
## Infinity straight into gameplay math with nothing to catch it. Every
## conversion below goes through one of these instead of a raw int()/
## float() on unchecked JSON, so a hand-edited or corrupted save is
## sanitized field-by-field, never a crash.
static func _safe_num(value: Variant, fallback: float) -> float:
	if (typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT) and is_finite(float(value)):
		return float(value)
	return fallback

static func _safe_int(value: Variant, fallback: int) -> int:
	return int(_safe_num(value, float(fallback)))

static func _safe_bool(value: Variant, fallback: bool) -> bool:
	return value if typeof(value) == TYPE_BOOL else fallback

## Every field is individually type/range-validated on load with a safe
## fallback rather than trusted — a corrupted or hand-edited save can never
## crash the game; it's silently replaced with (and immediately persisted
## as) a fresh default. Direct port of SaveSystem.ts's own validation rule.
func load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		save() # first run — persist the fresh default immediately
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("MetaProgression.load_save: could not open %s (err %d)" % [SAVE_PATH, FileAccess.get_open_error()])
		return
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("MetaProgression.load_save: save file was not a JSON object — resetting to default")
		save()
		return
	soul_ash = maxi(0, _safe_int(parsed.get("soul_ash", 0), 0))

	# Each entry validated individually rather than trusting the whole
	# Dictionary once it's confirmed to be one — ports migrateSave()'s own
	# per-entry `typeof value === 'number' && Number.isFinite(value) &&
	# value >= 0` filter exactly; a malformed single entry (a string, a
	# negative, a nested object) is dropped, not allowed to corrupt every
	# other real entry alongside it.
	var loaded_levels = parsed.get("permanent_levels", {})
	permanent_levels = {}
	if typeof(loaded_levels) == TYPE_DICTIONARY:
		for key in loaded_levels.keys():
			var v = loaded_levels[key]
			if (typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT) and is_finite(float(v)) and float(v) >= 0.0:
				permanent_levels[key] = int(floor(float(v)))

	# Same per-entry discipline for unlocks — this Dictionary only ever
	# holds id -> true (see purchase_unlock()); anything else in a
	# hand-edited save is dropped rather than trusted verbatim. The
	# typeof() check has to come first and short-circuit: GDScript's `==`
	# doesn't quietly return false comparing a bool to a number — a real
	# fixture (`"id": 1`) confirmed it hard-errors ("Invalid operands
	# 'float' and 'bool' in operator '=='") instead, so a raw `value ==
	# true` is exactly as unsafe here as the raw int()/float() calls above.
	var loaded_unlocks = parsed.get("unlocks", {})
	unlocks = {}
	if typeof(loaded_unlocks) == TYPE_DICTIONARY:
		for key in loaded_unlocks.keys():
			if typeof(loaded_unlocks[key]) == TYPE_BOOL and loaded_unlocks[key] == true:
				unlocks[key] = true

	var loaded_stats = parsed.get("lifetime_stats", {})
	if typeof(loaded_stats) == TYPE_DICTIONARY:
		for key in lifetime_stats.keys():
			# best_time_seconds is the one float (and the one that can be
			# legitimately negative — the "no time recorded yet" sentinel);
			# every other lifetime_stats key is a plain non-negative counter.
			if key == "best_time_seconds":
				lifetime_stats[key] = _safe_num(loaded_stats.get(key, -1.0), -1.0)
			else:
				lifetime_stats[key] = maxi(0, _safe_int(loaded_stats.get(key, 0), 0))

	# Ports sanitizeSettings() field-by-field: every numeric setting is
	# range-clamped (not just type-checked), and every enum-shaped string
	# setting is checked against its real allowed-value set — a raw
	# type match alone would let a hand-edited save through with e.g.
	# master_volume: 999 or graphics_quality: "ultra", neither of which
	# this port (or the source) ever offers as a real value.
	var loaded_settings = parsed.get("settings", {})
	if typeof(loaded_settings) == TYPE_DICTIONARY:
		if loaded_settings.has("master_volume"):
			settings["master_volume"] = clampf(_safe_num(loaded_settings["master_volume"], settings["master_volume"]), 0.0, 1.0)
		if loaded_settings.has("music_volume"):
			settings["music_volume"] = clampf(_safe_num(loaded_settings["music_volume"], settings["music_volume"]), 0.0, 1.0)
		if loaded_settings.has("sfx_volume"):
			settings["sfx_volume"] = clampf(_safe_num(loaded_settings["sfx_volume"], settings["sfx_volume"]), 0.0, 1.0)
		if loaded_settings.has("muted"):
			settings["muted"] = _safe_bool(loaded_settings["muted"], settings["muted"])
		if loaded_settings.has("screen_shake"):
			settings["screen_shake"] = _safe_bool(loaded_settings["screen_shake"], settings["screen_shake"])
		if loaded_settings.has("particle_quality") and typeof(loaded_settings["particle_quality"]) == TYPE_STRING and ["low", "medium", "high"].has(loaded_settings["particle_quality"]):
			settings["particle_quality"] = loaded_settings["particle_quality"]
		if loaded_settings.has("graphics_quality") and typeof(loaded_settings["graphics_quality"]) == TYPE_STRING and ["low", "medium", "high"].has(loaded_settings["graphics_quality"]):
			settings["graphics_quality"] = loaded_settings["graphics_quality"]
		if loaded_settings.has("text_scale"):
			settings["text_scale"] = clampf(_safe_num(loaded_settings["text_scale"], settings["text_scale"]), 0.85, 1.3)
		if loaded_settings.has("high_contrast"):
			settings["high_contrast"] = _safe_bool(loaded_settings["high_contrast"], settings["high_contrast"])
		if loaded_settings.has("reduced_motion"):
			settings["reduced_motion"] = _safe_bool(loaded_settings["reduced_motion"], settings["reduced_motion"])
		if loaded_settings.has("language") and typeof(loaded_settings["language"]) == TYPE_STRING and ["en", "fr"].has(loaded_settings["language"]):
			settings["language"] = loaded_settings["language"]
	hints_shown.clear()
	var loaded_hints = parsed.get("hints_shown", [])
	if typeof(loaded_hints) == TYPE_ARRAY:
		for h in loaded_hints:
			if typeof(h) == TYPE_STRING:
				hints_shown.append(h)
	var loaded_seed = parsed.get("last_seed", "")
	last_seed = loaded_seed if typeof(loaded_seed) == TYPE_STRING else ""
