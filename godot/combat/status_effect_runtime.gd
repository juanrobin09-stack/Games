class_name StatusEffectRuntime
extends RefCounted
## New for Godot — see GODOT_MIGRATION.md §7/§12. The shared component every
## Character (Player and Enemy both) processes each physics tick: applies
## damage through CombatManager, expires instances, is the generalization
## of the Web build's single hardcoded `Enemy.burn` field. Both `apply()`
## and `process()` operate on `target.status_effects: Array`, added
## directly to PlayerCharacter/EnemyCharacter rather than a shared base
## class (GDScript has no multiple inheritance; duplicating one field and
## two calls is cheaper than inventing a common ancestor for two otherwise
## quite different classes).
##
## `target` is deliberately typed as the generic `Node` and accessed only
## via get()/call() dynamic dispatch throughout this file — Player and
## Enemy share no common typed base here, so static dot-access on a
## `Node`-typed parameter would reference properties/methods Node doesn't
## declare.
##
## Every damage_formula variant is treated as a PER-SECOND rate; the actual
## per-tick amount is always `rate * tick_interval`. This is what makes
## Bleed's spec ("2% of max HP, per tick, every 1.0s" -> damage_value=0.02)
## and Burn's ("16% of the hit, as a per-second rate, ticking every 0.5s")
## resolve consistently through the same formula.

## Applies `definition` to `target` (a PlayerCharacter or EnemyCharacter),
## honoring its stack_rule. `resolved_dps` is required (and only meaningful)
## for PERCENT_TRIGGERING_HIT — the fraction of a specific hit's damage,
## computed once by the caller at the moment of the triggering event, not
## re-derivable later from a live stat the way the other formulas are.
static func apply(target: Node, definition: StatusEffectDefinition, source: Node, resolved_dps: float = -1.0) -> void:
	var list: Array = target.get("status_effects")
	if list == null:
		return
	var existing_index := -1
	for i in range(list.size()):
		var inst: StatusEffectInstance = list[i]
		if inst.definition.id == definition.id:
			existing_index = i
			break

	match definition.stack_rule:
		StatusEffectDefinition.StackRule.STACK_INDEPENDENT:
			var inst := StatusEffectInstance.new(definition, definition.duration, source)
			inst.resolved_dps = resolved_dps
			list.append(inst)
		StatusEffectDefinition.StackRule.STACK_INTENSITY:
			if existing_index >= 0:
				var inst: StatusEffectInstance = list[existing_index]
				inst.stacks = mini(inst.stacks + 1, maxi(1, definition.max_stacks))
				inst.remaining_duration = definition.duration
				inst.resolved_dps = resolved_dps
			else:
				var inst := StatusEffectInstance.new(definition, definition.duration, source)
				inst.resolved_dps = resolved_dps
				list.append(inst)
		_:
			# NONE / REFRESH: a single active instance. Burn's own "newest
			# only wins if at least as strong" nuance is intentionally
			# approximated here as "newest always wins" — see
			# status_effect_definition.gd's stack_rule comment.
			if existing_index >= 0:
				var inst: StatusEffectInstance = list[existing_index]
				inst.remaining_duration = definition.duration
				inst.resolved_dps = resolved_dps
				inst.source = source
			else:
				var inst := StatusEffectInstance.new(definition, definition.duration, source)
				inst.resolved_dps = resolved_dps
				list.append(inst)

## Call once per physics tick from the Character's own _physics_process.
static func process(target: Node, dt: float) -> void:
	var list: Array = target.get("status_effects")
	if list == null:
		return
	var i := 0
	while i < list.size():
		var inst: StatusEffectInstance = list[i]
		inst.remaining_duration -= dt
		inst.tick_timer -= dt
		if inst.tick_timer <= 0.0:
			inst.tick_timer += inst.definition.tick_interval
			_apply_tick(target, inst)
		if inst.remaining_duration <= 0.0 or not _target_alive(target):
			list.remove_at(i)
		else:
			i += 1

static func _target_alive(target: Node) -> bool:
	var v = target.get("alive")
	return v if typeof(v) == TYPE_BOOL else true

static func _apply_tick(target: Node, inst: StatusEffectInstance) -> void:
	var def := inst.definition
	if def.category != StatusEffectDefinition.Category.DOT:
		return
	var rate: float = 0.0
	match def.damage_formula:
		StatusEffectDefinition.DamageFormula.FLAT:
			rate = def.damage_value
		StatusEffectDefinition.DamageFormula.PERCENT_TARGET_MAX_HP:
			rate = _max_hp(target) * def.damage_value
		StatusEffectDefinition.DamageFormula.PERCENT_TARGET_CURRENT_HP:
			rate = _current_hp(target) * def.damage_value
		StatusEffectDefinition.DamageFormula.PERCENT_SOURCE_STAT:
			if inst.source != null:
				var source_stats = inst.source.get("stats")
				if source_stats != null:
					rate = float(source_stats.get(def.source_stat)) * def.damage_value
		StatusEffectDefinition.DamageFormula.PERCENT_TRIGGERING_HIT:
			rate = inst.resolved_dps if inst.resolved_dps >= 0.0 else 0.0
	var tick_damage: float = rate * def.tick_interval * float(inst.stacks)
	if tick_damage <= 0.0:
		return
	CombatManager.apply_status_tick_damage(target, tick_damage)

static func _max_hp(target: Node) -> float:
	var stats = target.get("stats")
	if stats != null:
		var v = stats.get("max_hp")
		if v != null:
			return float(v)
	var mh = target.get("max_hp")
	return float(mh) if mh != null else 0.0

static func _current_hp(target: Node) -> float:
	var v = target.get("hp")
	return float(v) if v != null else 0.0
