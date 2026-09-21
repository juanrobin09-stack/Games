extends Node2D
## Loot/upgrades system test suite (rarities, classified chests/keys, the
## Dungeon Level 1 chest probabilities, Hemorrhage, enemy drops). Not a
## disposable debug harness — kept in the repo, rerun with:
##   godot --headless --path godot res://tests/loot_system_tests.tscn
## Prints one PASS/FAIL line per check plus a final summary, and exits
## nonzero if anything failed (see _finish()).

var _results: Array = []
var _player: PlayerCharacter
var _enemy_seq := 0

func _check(condition: bool, description: String) -> void:
	_results.append({"ok": condition, "desc": description})
	print(("PASS  " if condition else "FAIL  ") + description)

func _make_enemy(def: EnemyDefinition) -> EnemyCharacter:
	var e: EnemyCharacter = LevelGenerator.ENEMY_SCENE.instantiate()
	add_child(e)
	e.setup(def, Vector2(9999.0 + _enemy_seq * 40.0, 9999.0), 1.0, 1.0)
	_enemy_seq += 1
	return e

func _ready() -> void:
	_player = (load("res://entities/player.tscn") as PackedScene).instantiate()
	add_child(_player)
	LevelFlow.start_new_run("loot-system-tests", _player, self)
	for i in range(5):
		await get_tree().process_frame

	_test_rarity()
	_test_chest_key_matching()
	_test_dungeon_level1_probabilities()
	await _test_hemorrhage()
	_test_enemy_drop()

	_finish()

# ---------------------------------------------------------------- Rarity

func _test_rarity() -> void:
	print("\n-- Rarity --")
	var expected := ["E", "D", "C", "B", "A", "S", "SS"]
	_check(LootRarity.ORDER.size() == 7, "LootRarity has exactly 7 tiers")
	for i in range(expected.size()):
		_check(LootRarity.label(LootRarity.ORDER[i]) == expected[i],
			"tier %d labels as '%s'" % [i, expected[i]])
	_check(LootRarity.Tier.E < LootRarity.Tier.SS, "E orders below SS")
	_check(LootRarity.from_label("ss") == LootRarity.Tier.SS, "from_label is case-insensitive")

# ---------------------------------------------------------------- Chests & keys

func _test_chest_key_matching() -> void:
	print("\n-- Chests & keys --")
	for code in ["chestC", "chestB", "chestA", "chestS", "chestSS"]:
		var chest_class: ChestClassDefinition = DataRegistry.get_chest_class(code)
		_check(chest_class != null, "%s definition loads" % code)
		if chest_class == null:
			continue
		var key: ItemDefinition = DataRegistry.get_item(chest_class.required_key_item_id)
		_check(key != null and key.item_type == ItemDefinition.ItemType.KEY and key.key_tier == chest_class.tier,
			"%s's required key (%s) is a KEY item of the matching tier" % [code, chest_class.required_key_item_id])

	# Functional open attempt: wrong key must fail, right key must succeed.
	_player.items.clear()
	var target_tier := LootRarity.Tier.C
	_check(not _player.has_key(target_tier), "player starts without Key C")
	_player.add_item("keyB", 1)
	_check(not _player.consume_key(target_tier), "holding Key B does not open a Chest C")
	_check(_player.item_count("keyB") == 1, "the mismatched key is not consumed by the failed attempt")
	_player.add_item("keyC", 1)
	_check(_player.consume_key(target_tier), "holding Key C opens a Chest C")
	_check(_player.item_count("keyC") == 0, "Key C is consumed on a successful open")
	_check(not _player.consume_key(target_tier), "the same Key C cannot open a second chest")

# ---------------------------------------------------------------- Probabilities

func _test_dungeon_level1_probabilities() -> void:
	print("\n-- Dungeon Level 1 chest probabilities --")
	var configs := DataRegistry.dungeon_chest_configs_for_zone(0)
	var by_class: Dictionary = {}
	for c in configs:
		by_class[c.chest_class_id] = c.spawn_chance
	var expected := {"chestC": 0.15, "chestB": 0.03, "chestA": 0.005, "chestS": 0.002, "chestSS": 0.001}
	for id in expected:
		_check(is_equal_approx(by_class.get(id, -1.0), expected[id]),
			"%s spawn_chance is exactly %s (not normalized)" % [id, expected[id]])
	var total_configured := 0.0
	for v in expected.values():
		total_configured += v
	_check(is_equal_approx(total_configured, 0.188), "configured chances sum to 18.8% total chest chance")

	# Statistical check, large N -- wide tolerance (this is a sanity check for
	# a badly wired probability, e.g. two tiers swapped or one normalized
	# away, not a check that RNG hits the exact float).
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var trials := 200000
	var hits: Dictionary = {"chestC": 0, "chestB": 0, "chestA": 0, "chestS": 0, "chestSS": 0}
	var any_chest := 0
	for i in range(trials):
		var rolled := ClassifiedChestRules.roll_spawns(rng, 0)
		if not rolled.is_empty():
			any_chest += 1
		for c in rolled:
			hits[c.chest_class_id] = hits.get(c.chest_class_id, 0) + 1
	for id in expected:
		var rate: float = float(hits[id]) / float(trials)
		var tolerance: float = maxf(0.003, expected[id] * 0.35)
		_check(absf(rate - expected[id]) < tolerance,
			"%s measured rate %.4f close to configured %.4f (+/- %.4f, n=%d)" % [id, rate, expected[id], tolerance, trials])
	var any_rate := float(any_chest) / float(trials)
	_check(absf(any_rate - 0.188) < 0.01, "measured 'any chest' rate %.4f close to 18.8%%" % any_rate)
	_check(absf((1.0 - any_rate) - 0.812) < 0.01, "measured 'no chest' rate close to 81.2%%")

# ---------------------------------------------------------------- Hemorrhage

func _test_hemorrhage() -> void:
	print("\n-- Hemorrhage --")
	var def: StatusEffectDefinition = DataRegistry.get_status_effect("hemorrhage")
	_check(def != null, "hemorrhage StatusEffectDefinition loads")
	if def == null:
		return
	_check(def.category == StatusEffectDefinition.Category.DOT, "category is DOT")
	_check(def.damage_formula == StatusEffectDefinition.DamageFormula.FLAT, "damage_formula is FLAT (X is a flat rate)")
	_check(def.stack_rule == StatusEffectDefinition.StackRule.STACK_INTENSITY, "stack_rule is STACK_INTENSITY (documented: stacks up to max_stacks)")

	var enemy_def: EnemyDefinition = DataRegistry.get_enemy("ashCrawler")

	# 1) application + one tick of damage, at the definition's own X.
	var e1 := _make_enemy(enemy_def)
	var hp_before: float = e1.hp
	StatusEffectRuntime.apply(e1, def, null)
	_check(e1.status_effects.size() == 1, "applying hemorrhage adds one status effect")
	StatusEffectRuntime.process(e1, def.tick_interval)
	var expected_tick: float = def.damage_value * def.tick_interval
	_check(is_equal_approx(e1.hp, hp_before - expected_tick),
		"one tick deals exactly X*tick_interval = %.1f damage" % expected_tick)

	# 2) X is read from the data, not hardcoded -- a differently-configured
	# copy of the definition must deal a different amount.
	var custom_def: StatusEffectDefinition = def.duplicate()
	custom_def.damage_value = 17.0
	var e2 := _make_enemy(enemy_def)
	var hp2_before: float = e2.hp
	StatusEffectRuntime.apply(e2, custom_def, null)
	StatusEffectRuntime.process(e2, custom_def.tick_interval)
	_check(is_equal_approx(e2.hp, hp2_before - 17.0 * custom_def.tick_interval),
		"a differently-configured X (17.0) changes the tick damage accordingly")

	# 3) stacking behavior, documented as STACK_INTENSITY up to max_stacks,
	# each stack adding its own full X to the tick.
	var e3 := _make_enemy(enemy_def)
	var hp3_before: float = e3.hp
	for i in range(5):
		StatusEffectRuntime.apply(e3, def, null)
	_check(e3.status_effects.size() == 1, "repeated applications stay a single status entry")
	_check((e3.status_effects[0] as StatusEffectInstance).stacks == def.max_stacks,
		"stacks cap at max_stacks (%d) even after 5 applications" % def.max_stacks)
	StatusEffectRuntime.process(e3, def.tick_interval)
	_check(is_equal_approx(e3.hp, hp3_before - def.damage_value * def.tick_interval * def.max_stacks),
		"a tick at max stacks deals X * tick_interval * stacks")

	# 4) duration + removal.
	var e4 := _make_enemy(enemy_def)
	StatusEffectRuntime.apply(e4, def, null)
	var elapsed := 0.0
	while elapsed < def.duration + def.tick_interval:
		StatusEffectRuntime.process(e4, def.tick_interval)
		elapsed += def.tick_interval
	_check(e4.status_effects.is_empty(), "the status effect is removed once its duration elapses")

	# 5) end-to-end: the Hemorrhage UPGRADE actually procs through real combat,
	# not just StatusEffectRuntime called directly.
	var upgrade: UpgradeDefinition = DataRegistry.get_upgrade("hemorrhage")
	_check(upgrade != null, "hemorrhage UpgradeDefinition loads")
	_check(upgrade != null and not upgrade.triggered_effects.is_empty(), "the upgrade carries a triggered_effects entry")
	if upgrade != null:
		_player.upgrades.clear()
		_player.add_upgrade(upgrade)
		var e5 := _make_enemy(enemy_def)
		CombatManager.damage_player_to_enemy(_player, e5, 10.0, false)
		_check(e5.status_effects.size() == 1 and (e5.status_effects[0] as StatusEffectInstance).definition.id == "hemorrhage",
			"owning the Hemorrhage upgrade applies it to an enemy hit through CombatManager.damage_player_to_enemy")
	await get_tree().process_frame

# ---------------------------------------------------------------- Enemy drops

func _test_enemy_drop() -> void:
	print("\n-- Enemy drops --")
	var table: LootTableDefinition = DataRegistry.get_loot_table("enemyCommonZ0")
	_check(table != null, "enemyCommonZ0 loot table loads")

	var base_def: EnemyDefinition = DataRegistry.get_enemy("ashCrawler")
	_check(base_def.loot_table_id == "enemyCommonZ0", "ashCrawler is configured with a loot table (opt-in, per-enemy)")

	var undropping_def: EnemyDefinition = DataRegistry.get_enemy("hollow")
	_check(undropping_def != null and undropping_def.loot_table_id == "",
		"an unconfigured enemy (hollow) has no loot table -- drops are opt-in, not default-on")

	# Deterministic drop: 100% chance, single guaranteed entry.
	var drop_def: EnemyDefinition = EnemyDefinition.new()
	drop_def.id = "testDropper"
	drop_def.name = "Test Dropper"
	drop_def.base_hp = 10.0
	drop_def.color = "#3d3229"
	drop_def.accent_color = "#ff7b3d"
	drop_def.loot_table_id = "enemyCommonZ0"
	drop_def.drop_chance = 1.0
	var e := _make_enemy(drop_def)
	var before: int = _player.item_count("emberShard")
	CombatManager.on_enemy_death(_player, e)
	_check(_player.item_count("emberShard") > before,
		"an enemy configured with a loot table actually grants its loot on death")

# ---------------------------------------------------------------- Summary

func _finish() -> void:
	var total := _results.size()
	var failed := 0
	for r in _results:
		if not r["ok"]:
			failed += 1
	print("\n==================================================")
	print("Loot system tests: %d/%d passed" % [total - failed, total])
	if failed > 0:
		print("FAILED (%d):" % failed)
		for r in _results:
			if not r["ok"]:
				print("  - " + r["desc"])
	print("==================================================")
	get_tree().quit(1 if failed > 0 else 0)
