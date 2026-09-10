extends Node
## Autoload: DataRegistry
##
## Loads every content Resource from res://resources/<category>/ at boot
## and exposes id-keyed lookups — the Godot equivalent of data/enemies.ts's
## `getEnemyDefinition(id)` and its siblings across every other data
## module. New content is added by dropping a new .tres file in the right
## folder, exactly like the Web build's "add a data entry, not new code"
## pattern (see GODOT_MIGRATION.md §11).

const CATEGORIES := {
	"enemies": "res://resources/enemies/",
	"weapons": "res://resources/weapons/",
	"abilities": "res://resources/abilities/",
	"upgrades": "res://resources/upgrades/",
	"zones": "res://resources/zones/",
	"events": "res://resources/events/",
	"permanent_upgrades": "res://resources/permanent_upgrades/",
	"unlocks": "res://resources/unlocks/",
	"synergies": "res://resources/synergies/",
	"status_effects": "res://resources/status_effects/",
}

var _by_category: Dictionary = {}

func _ready() -> void:
	for category in CATEGORIES.keys():
		_by_category[category] = _load_directory(CATEGORIES[category])

## How many resources loaded per category — a quick smoke-test surface for
## catching a bad/missing .tres file without opening every one by hand.
func counts() -> Dictionary:
	var out: Dictionary = {}
	for category in _by_category.keys():
		out[category] = _by_category[category].size()
	return out

func _load_directory(path: String) -> Dictionary:
	var out: Dictionary = {}
	var dir := DirAccess.open(path)
	if dir == null:
		push_warning("DataRegistry: could not open %s (err %d)" % [path, DirAccess.get_open_error()])
		return out
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var res: Resource = load(path + file_name)
			var id = res.get("id") if res != null else null
			if typeof(id) == TYPE_STRING and id != "":
				if out.has(id):
					push_warning("DataRegistry: duplicate id '%s' in %s (%s)" % [id, path, file_name])
				out[id] = res
			else:
				push_warning("DataRegistry: %s%s has no usable 'id' field" % [path, file_name])
		file_name = dir.get_next()
	dir.list_dir_end()
	return out

func get_by_id(category: String, id: String) -> Resource:
	return _by_category.get(category, {}).get(id, null)

func all(category: String) -> Array:
	return _by_category.get(category, {}).values()

func get_enemy(id: String) -> EnemyDefinition:
	return get_by_id("enemies", id) as EnemyDefinition

func get_weapon(id: String) -> WeaponDefinition:
	return get_by_id("weapons", id) as WeaponDefinition

func get_ability(id: String) -> AbilityDefinition:
	return get_by_id("abilities", id) as AbilityDefinition

func get_upgrade(id: String) -> UpgradeDefinition:
	return get_by_id("upgrades", id) as UpgradeDefinition

func get_zone(id: String) -> ZoneDefinition:
	return get_by_id("zones", id) as ZoneDefinition

func get_event(id: String) -> WorldEventDefinition:
	return get_by_id("events", id) as WorldEventDefinition

func get_permanent_upgrade(id: String) -> PermanentUpgradeDefinition:
	return get_by_id("permanent_upgrades", id) as PermanentUpgradeDefinition

func get_unlock(id: String) -> UnlockDefinition:
	return get_by_id("unlocks", id) as UnlockDefinition

func get_synergy(id: String) -> SynergyDefinition:
	return get_by_id("synergies", id) as SynergyDefinition

func get_status_effect(id: String) -> StatusEffectDefinition:
	return get_by_id("status_effects", id) as StatusEffectDefinition
