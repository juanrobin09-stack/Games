class_name StatBlock
extends Resource
## Ports data/types.ts's StatBlock (createBaseStats' defaults, below) and
## data/stats.ts's applyModifiers/clampStats/freshStats. Every numeric knob
## on the player/enemy that upgrades and gear can modify.

@export var max_hp: float = 100.0
@export var hp_regen: float = 0.4
@export var move_speed: float = 190.0
@export var damage_mult: float = 1.0
@export var attack_speed_mult: float = 1.0
@export var range_mult: float = 1.0
@export var crit_chance: float = 0.05
@export var crit_damage: float = 1.5
@export var armor: float = 0.0
@export var stamina_max: float = 100.0
@export var energy_max: float = 100.0
@export var energy_regen: float = 6.0
@export var dodge_cooldown_mult: float = 1.0
@export var ability_damage_mult: float = 1.0
@export var ember_gain_mult: float = 1.0
@export var pickup_range: float = 70.0
@export var projectile_count: float = 0.0
@export var area_damage_mult: float = 1.0
@export var lifesteal: float = 0.0
@export var shield_max: float = 0.0
@export var burn_chance: float = 0.0
@export var ember_power: float = 1.0
@export var rarity_luck: float = 0.0

static func fresh() -> StatBlock:
	return StatBlock.new()

func duplicate_stats() -> StatBlock:
	return duplicate(true) as StatBlock

## Combines modifiers onto a DUPLICATE of this StatBlock (self is never
## mutated). 'flat' adds the raw amount; 'mult' multiplies the stat's
## CURRENT value by (1 + value) — this lets the *_mult fields (base 1.0)
## compound predictably and lets reduction fields (e.g. dodge_cooldown_mult)
## shrink toward zero safely via negative values. Order: all flats first (in
## the order given), then all mults — never interleaved.
func apply_modifiers(modifiers: Array[StatModifier]) -> StatBlock:
	var result := duplicate_stats()
	for mod in modifiers:
		if mod.mode == StatModifier.Mode.FLAT:
			result.set(mod.stat, float(result.get(mod.stat)) + mod.value)
	for mod in modifiers:
		if mod.mode == StatModifier.Mode.MULT:
			result.set(mod.stat, float(result.get(mod.stat)) * (1.0 + mod.value))
	return result.clamp_stats()

## Mutates and returns self — call on a duplicate (see apply_modifiers),
## never on a shared base StatBlock.
func clamp_stats() -> StatBlock:
	crit_chance = clampf(crit_chance, 0.0, 0.85)
	armor = clampf(armor, 0.0, 0.75)
	lifesteal = clampf(lifesteal, 0.0, 0.6)
	burn_chance = clampf(burn_chance, 0.0, 1.0)
	dodge_cooldown_mult = clampf(dodge_cooldown_mult, 0.3, 2.0)
	attack_speed_mult = clampf(attack_speed_mult, 0.35, 4.0)
	move_speed = maxf(60.0, move_speed)
	max_hp = clampf(max_hp, 10.0, 180.0)
	stamina_max = maxf(20.0, stamina_max)
	range_mult = maxf(0.4, range_mult)
	pickup_range = maxf(20.0, pickup_range)
	ember_gain_mult = maxf(0.1, ember_gain_mult)
	rarity_luck = clampf(rarity_luck, 0.0, 1.0)
	return self
