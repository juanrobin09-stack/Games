class_name HazardNode
extends Node2D
## Ports combat/CombatSystem.ts's Hazard interface (spore clouds — the
## only kind so far, 'spores') + rendering/draw/drawHazard.ts's
## drawHazards(). One self-contained node per active hazard rather than a
## flat array ticked centrally (TS's own this.hazards[]): matches this
## port's established convention for every other transient world entity
## (pickup_node.gd/chest_node.gd/obstacle_node.gd/floating_text.gd) —
## spawn(), tick itself in _process(), free itself on expiry. MAX_HAZARDS
## (TS's hard cap so a bloat-heavy fight can't pile up clouds without
## bound) has no equivalent here on purpose: each hazard is already a
## cheap, self-freeing node, so the cap was only ever needed to bound the
## one shared array TS ticks every frame.
##
## Two spawn sites: CombatManager.detonate_bloat() (a Blightbloat's burst,
## using its EnemyDefinition's cloud_radius/cloud_duration) and
## CombatManager.consume_pending_cloud() (a phase-2 Sunken Warden's bash
## landing, fixed 3.5s duration — see enemy.gd's own pending_cloud_radius
## field comment). Both were the one disclosed "hazards aren't ported this
## pass" gap this whole file's header used to name.

const HAZARD_TICK_INTERVAL := 0.6
const EMIT_INTERVAL := 0.07

var radius: float = 80.0
var duration: float = 5.0
var tick_damage: float = 5.0
var timer: float = 0.0
## Ports CombatSystem.ts's own hazard.tickTimer starting value — the first
## tick lands sooner (0.35s) than every subsequent one (HAZARD_TICK_INTERVAL,
## 0.6s), so a hazard that only grazes the player briefly still gets a
## real chance to tick once.
var tick_timer: float = 0.35
var emit_timer: float = 0.0
var seed_value: float = 0.0

static func spawn(parent: Node, world_pos: Vector2, p_radius: float, p_duration: float, p_tick_damage: float) -> HazardNode:
	var h: HazardNode = preload("res://world/hazard_node.tscn").instantiate()
	h.radius = p_radius
	h.duration = p_duration
	h.tick_damage = p_tick_damage
	h.seed_value = randf() * 100.0
	parent.add_child(h)
	h.global_position = world_pos
	return h

func _ready() -> void:
	($Glow as PointLight2D).texture = DrawUtils.glow_texture()

## Gameplay timing (expiry, tick damage, mote cadence) lives here rather
## than _process(), matching every other gameplay timer in this codebase
## (status effects, cooldowns, ability timers) — a fixed-rate, pause-aware
## tick, unlike _process()'s variable per-rendered-frame delta. _draw()'s
## own breathing/pulse animation below is the one thing here that
## deliberately uses real time instead (Time.get_ticks_msec(), same
## convention as obstacle_node.gd's cosmetic flicker/sway).
func _physics_process(delta: float) -> void:
	timer += delta
	if timer >= duration:
		queue_free()
		return
	emit_timer -= delta
	if emit_timer <= 0.0:
		emit_timer = EMIT_INTERVAL
		var parent := get_parent()
		if parent != null:
			var angle: float = randf() * TAU
			var r: float = sqrt(randf()) * radius * 0.9
			VfxPresets.spore_mote(parent, global_position + Vector2(cos(angle), sin(angle)) * r)
	tick_timer -= delta
	if tick_timer <= 0.0:
		tick_timer = HAZARD_TICK_INTERVAL
		var player := get_tree().get_first_node_in_group("player") as PlayerCharacter
		if player != null and player.alive and global_position.distance_to(player.global_position) <= radius + player.radius * 0.5:
			CombatManager.damage_enemy_to_player(player, tick_damage, {"hazard": true})
	_update_light()
	queue_redraw()

## Ports Game.ts's own per-hazard lighting.add() call (radius*1.15,
## Palette.fungusDim, 0.4*fade) — same fade curve _draw() uses below, just
## fed to a real PointLight2D instead of a manual per-frame accumulator
## (this port's established substitution — see obstacle_node.gd's own
## _update_light()).
func _update_light() -> void:
	var glow: PointLight2D = $Glow
	var fade: float = _fade()
	if fade <= 0.004:
		glow.enabled = false
		return
	glow.enabled = true
	glow.texture_scale = (radius * 1.15) / 128.0
	glow.color = Color(Palette.FUNGUS_DIM)
	glow.energy = 0.4 * fade

func _fade() -> float:
	var fade_in: float = minf(1.0, timer / 0.3)
	var fade_out: float = clampf((duration - timer) / 0.8, 0.0, 1.0)
	return fade_in * fade_out

## Ports rendering/draw/drawHazard.ts's drawHazards() body for one hazard:
## 3 soft offset lobes breathing around the centre, a dark heart, and a
## pulsing dashed rim marking the actual damage boundary. Canvas2D's radial
## gradients have no immediate-mode equivalent — approximated the same way
## every other soft-blob glow in this port is (DrawUtils.draw_glow_circle's
## own header). Drawn in local/world units throughout, same as every other
## _draw() in this port — Camera2D handles screen-space scaling, so there's
## no manual `* zoom` the way the source's raw-canvas version needs.
func _draw() -> void:
	var alpha: float = _fade()
	if alpha <= 0.01:
		return
	var time: float = Time.get_ticks_msec() / 1000.0
	var r: float = radius * (0.85 + minf(1.0, timer / 0.3) * 0.15)
	for i in range(3):
		var phase: float = time * 0.7 + seed_value + float(i) * 2.1
		var ox: float = cos(phase) * r * 0.18
		var oy: float = sin(phase * 1.3) * r * 0.14
		var lr: float = r * (0.72 + DrawUtils.hash_jitter(seed_value, float(i)) * 0.2)
		DrawUtils.draw_glow_circle(self, ox, oy, lr, Palette.FUNGUS_DIM, 0.55 * alpha)
	DrawUtils.draw_glow_circle(self, 0.0, 0.0, r * 0.5, "#0a1e1a", 0.35 * alpha)
	var pulse: float = 0.75 + sin(time * 3.0 + seed_value) * 0.25
	var rim_color := Color(Palette.FUNGUS_BRIGHT)
	rim_color.a = 0.5 * alpha * pulse
	_draw_dashed_ring(r, rim_color, 2.2, 7.0, 5.0, -time * 24.0)

## Same technique as enemy.gd's own _draw_dashed_circle, extended with a
## rotating start `offset` (world units, same convention as `dash`/`gap`)
## — ports the source's animated `ctx.lineDashOffset = -time * 24`, which
## that helper has no equivalent for.
func _draw_dashed_ring(circle_radius: float, color: Color, width: float, dash: float, gap: float, offset: float) -> void:
	if circle_radius <= 0.5:
		return
	var dash_angle: float = dash / circle_radius
	var gap_angle: float = gap / circle_radius
	var angle: float = fposmod(offset / circle_radius, dash_angle + gap_angle)
	while angle < TAU:
		var end_angle: float = minf(angle + dash_angle, TAU)
		draw_arc(Vector2.ZERO, circle_radius, angle, end_angle, 6, color, width, true)
		angle += dash_angle + gap_angle
