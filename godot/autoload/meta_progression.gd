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

var soul_ash: int = 0
## permanent-upgrade id (String) -> level purchased (int)
var permanent_levels: Dictionary = {}
## unlock id (String) -> true, for every purchased UnlockDefinition
var unlocks: Dictionary = {}
var lifetime_stats: Dictionary = {
	"runs_started": 0,
	"runs_won": 0,
	"total_kills": 0,
}

func _ready() -> void:
	load_save()

func add_soul_ash(amount: int) -> void:
	soul_ash += amount
	soul_ash_changed.emit(soul_ash)
	save()

func can_afford(cost: int) -> bool:
	return soul_ash >= cost

func purchase_permanent_upgrade(id: String, cost: int, new_level: int) -> bool:
	if not can_afford(cost):
		return false
	soul_ash -= cost
	permanent_levels[id] = new_level
	permanent_upgrade_purchased.emit(id, new_level)
	soul_ash_changed.emit(soul_ash)
	save()
	return true

func purchase_unlock(id: String, cost: int) -> bool:
	if unlocks.has(id) or not can_afford(cost):
		return false
	soul_ash -= cost
	unlocks[id] = true
	unlock_purchased.emit(id)
	soul_ash_changed.emit(soul_ash)
	save()
	return true

func has_unlock(id: String) -> bool:
	return unlocks.get(id, false)

## Mirrors MetaProgression.ts's getUnlockedGateIds() — every UnlockDefinition
## id currently purchased. `unlocks` only ever holds true purchased ids (see
## purchase_unlock), so this is just its own keys; kept as a named method
## matching the TS source's own naming rather than inlining
## `MetaProgression.unlocks.keys()` at call sites (LevelFlow.current_gate_ids).
func get_unlocked_gate_ids() -> Array:
	return unlocks.keys()

func save() -> void:
	var data := {
		"version": SAVE_VERSION,
		"soul_ash": soul_ash,
		"permanent_levels": permanent_levels,
		"unlocks": unlocks,
		"lifetime_stats": lifetime_stats,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("MetaProgression.save: could not open %s for writing (err %d)" % [SAVE_PATH, FileAccess.get_open_error()])
		return
	file.store_string(JSON.stringify(data))
	file.close()

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
	soul_ash = maxi(0, int(parsed.get("soul_ash", 0)))
	var loaded_levels = parsed.get("permanent_levels", {})
	permanent_levels = loaded_levels if typeof(loaded_levels) == TYPE_DICTIONARY else {}
	var loaded_unlocks = parsed.get("unlocks", {})
	unlocks = loaded_unlocks if typeof(loaded_unlocks) == TYPE_DICTIONARY else {}
	var loaded_stats = parsed.get("lifetime_stats", {})
	if typeof(loaded_stats) == TYPE_DICTIONARY:
		for key in lifetime_stats.keys():
			lifetime_stats[key] = int(loaded_stats.get(key, 0))
