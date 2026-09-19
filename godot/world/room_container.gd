class_name RoomContainer
extends Node2D
## Ports world/Room.ts. Unlike the Web build (every room sharing one JS
## object graph, swapped by reference), every generated room in Godot is a
## real, permanent Node2D — created once when its zone's layout generates,
## never freed or regenerated, sitting at local origin (0,0) in the same
## shared 0..1000,0..620 rectangle Room.ts itself uses. Only the room the
## player currently occupies is ever active; see set_active().
##
## Why nodes stay alive instead of being cleared/rebuilt (GODOT_MIGRATION.md
## §6 generically recommends queue_free()-based clearing over "just hidden"):
## RunState.ts's own retreatZone() comment is explicit that "every room
## object (visited/cleared/chest/enemy state) is untouched by a zone switch
## either direction, so nothing needs to be saved or restored" — leaving a
## combat room mid-fight and returning later finds the same survivors where
## you left them, because populateRoomContent's spawnedContent guard means
## content is only ever generated once and then simply not re-ticked while
## you're elsewhere. Keeping the actual Nodes alive (hidden + process-
## disabled) is the direct Godot equivalent of that guarantee; discarding
## and regenerating them would lose it.
##
## set_active(false) is not enough on its own to stop a hidden room's walls
## and enemies from physically blocking the ACTIVE room sitting at the same
## coordinates — Godot keeps a CollisionObject2D's shapes live in the
## physics world regardless of process_mode. Every wall/obstacle/enemy this
## room owns is tracked in _physics_bodies specifically so set_active() can
## also zero out collision_layer/collision_mask on all of them.

enum Direction { N, S, E, W }
enum Type { START, COMBAT, ELITE, HEART, BOSS, CHEST, SHOP, EVENT, REST, SANCTUM }

const ROOM_WIDTH := 1000.0
const ROOM_HEIGHT := 620.0
const WALL_THICKNESS := 46.0
const DOOR_WIDTH := 120.0

const OPPOSITE := {
	Direction.N: Direction.S, Direction.S: Direction.N,
	Direction.E: Direction.W, Direction.W: Direction.E,
}
const DIRECTION_DELTA := {
	Direction.N: Vector2i(0, -1), Direction.S: Vector2i(0, 1),
	Direction.E: Vector2i(1, 0), Direction.W: Vector2i(-1, 0),
}

## Set by LevelGenerator right after creation — which zone this room
## belongs to, so _draw() can use that zone's own palette (build-order
## step 7) instead of one fixed color for every room in every zone.
var zone: ZoneDefinition = null

var grid_x: int = 0
var grid_y: int = 0
var key: String = ""
var type: Type = Type.COMBAT
var doors: Array[int] = []
var visited: bool = false
var cleared: bool = false
var reward_granted: bool = false
var distance_from_start: int = 0
var spawned_content: bool = false
var rest_used: bool = false

## Sanctum rite only (see LevelFlow.begin_rite/update_rite).
var ritual_active: bool = false
var ritual_wave: int = 0
var ritual_wave_timer: float = 0.0

## Event room only — which WorldEventDefinition rolled for this room, and
## whether it's already been resolved. Event *interaction* itself (the
## actual choice UI) is step 9; the room still needs to remember which
## event id it rolled so a later step doesn't need to re-roll it.
var event_id: String = ""
var event_resolved: bool = false

## Live children — populated once by LevelGenerator.populate_room_content(),
## then left exactly as combat/pickups/interaction leave them.
var enemies: Array[EnemyCharacter] = []
var obstacles: Array[ObstacleNode] = []
var pickups: Array[Node2D] = []
var chest: ChestNode = null

var _is_active: bool = false
var _physics_bodies: Array[CollisionObject2D] = []
var _wall_bodies: Array[StaticBody2D] = []

## Walls aren't built here — doors keep growing on a room throughout zone
## generation (see LevelGenerator), so wall geometry is only meaningful
## once every room's doors are final. LevelGenerator calls refresh_walls()
## once per room right after generation finishes.
func init_grid(gx: int, gy: int, p_type: Type) -> void:
	grid_x = gx
	grid_y = gy
	type = p_type
	key = "%d,%d" % [gx, gy]
	# Every RoomContainer is a sibling of Player/DebugLabel/LiveLabel under
	# Main, added AFTER them (LevelFlow.start_new_run runs post-spawn) — 2D
	# canvas siblings draw in add-order, so without this, _draw()'s own
	# opaque floor rect (below) would paint over the player and every debug
	# label the instant a room activates. Obstacle/Chest/Pickup counter
	# this back to z_index 0 in their own _ready() so they don't inherit
	# it and vanish behind the floor themselves.
	z_index = -10
	set_active(false)

## Warden shield-bearer, elite, heart guardian and boss rooms lock their
## doors until cleared; the sanctum locks only while its rite is running.
func is_locked() -> bool:
	if cleared:
		return false
	if type == Type.SANCTUM:
		return ritual_active
	return type == Type.COMBAT or type == Type.ELITE or type == Type.HEART or type == Type.BOSS

func requires_clearing() -> bool:
	if type == Type.SANCTUM:
		return ritual_active
	return type == Type.COMBAT or type == Type.ELITE or type == Type.HEART or type == Type.BOSS

func check_cleared() -> bool:
	if cleared:
		return true
	if not requires_clearing():
		_mark_cleared()
		return true
	if spawned_content and enemies.size() > 0:
		var any_alive := false
		for e in enemies:
			if e.alive:
				any_alive = true
				break
		if not any_alive:
			_mark_cleared()
			return true
	return false

## refresh_walls() right here (not left to whoever called check_cleared())
## is what actually unseals the door the instant a room clears — is_locked()
## reads `cleared`, and get_walls() only fills the door gap back in while
## is_locked() is true, so the wall geometry has to be rebuilt the moment
## that flips or the (now unlocked) room stays physically sealed regardless.
func _mark_cleared() -> void:
	cleared = true
	refresh_walls()

func has_door(dir: int) -> bool:
	return doors.has(dir)

func add_door(dir: int) -> void:
	if not doors.has(dir):
		doors.append(dir)

func door_center(dir: int) -> Vector2:
	match dir:
		Direction.N: return Vector2(ROOM_WIDTH / 2.0, WALL_THICKNESS / 2.0)
		Direction.S: return Vector2(ROOM_WIDTH / 2.0, ROOM_HEIGHT - WALL_THICKNESS / 2.0)
		Direction.W: return Vector2(WALL_THICKNESS / 2.0, ROOM_HEIGHT / 2.0)
		Direction.E: return Vector2(ROOM_WIDTH - WALL_THICKNESS / 2.0, ROOM_HEIGHT / 2.0)
		_: return Vector2(ROOM_WIDTH / 2.0, ROOM_HEIGHT / 2.0)

func spawn_point_from(dir: int) -> Vector2:
	var inset := WALL_THICKNESS + 60.0
	match dir:
		Direction.N: return Vector2(ROOM_WIDTH / 2.0, inset)
		Direction.S: return Vector2(ROOM_WIDTH / 2.0, ROOM_HEIGHT - inset)
		Direction.W: return Vector2(inset, ROOM_HEIGHT / 2.0)
		Direction.E: return Vector2(ROOM_WIDTH - inset, ROOM_HEIGHT / 2.0)
		_: return Vector2(ROOM_WIDTH / 2.0, ROOM_HEIGHT / 2.0)

## Wall segments as Rect2 (local space). include_door_barriers=true fills the
## door gaps back in with a wall — what a locked room actually uses to keep
## the player from ever reaching a door-crossing check in the first place.
func get_walls(include_door_barriers: bool) -> Array[Rect2]:
	var walls: Array[Rect2] = []
	var t := WALL_THICKNESS
	var half := DOOR_WIDTH / 2.0
	var has_n := has_door(Direction.N)
	var has_s := has_door(Direction.S)
	var has_w := has_door(Direction.W)
	var has_e := has_door(Direction.E)

	if has_n:
		walls.append(Rect2(0.0, 0.0, ROOM_WIDTH / 2.0 - half, t))
		walls.append(Rect2(ROOM_WIDTH / 2.0 + half, 0.0, ROOM_WIDTH / 2.0 - half, t))
		if include_door_barriers:
			walls.append(Rect2(ROOM_WIDTH / 2.0 - half, 0.0, DOOR_WIDTH, t))
	else:
		walls.append(Rect2(0.0, 0.0, ROOM_WIDTH, t))

	if has_s:
		walls.append(Rect2(0.0, ROOM_HEIGHT - t, ROOM_WIDTH / 2.0 - half, t))
		walls.append(Rect2(ROOM_WIDTH / 2.0 + half, ROOM_HEIGHT - t, ROOM_WIDTH / 2.0 - half, t))
		if include_door_barriers:
			walls.append(Rect2(ROOM_WIDTH / 2.0 - half, ROOM_HEIGHT - t, DOOR_WIDTH, t))
	else:
		walls.append(Rect2(0.0, ROOM_HEIGHT - t, ROOM_WIDTH, t))

	if has_w:
		walls.append(Rect2(0.0, 0.0, t, ROOM_HEIGHT / 2.0 - half))
		walls.append(Rect2(0.0, ROOM_HEIGHT / 2.0 + half, t, ROOM_HEIGHT / 2.0 - half))
		if include_door_barriers:
			walls.append(Rect2(0.0, ROOM_HEIGHT / 2.0 - half, t, DOOR_WIDTH))
	else:
		walls.append(Rect2(0.0, 0.0, t, ROOM_HEIGHT))

	if has_e:
		walls.append(Rect2(ROOM_WIDTH - t, 0.0, t, ROOM_HEIGHT / 2.0 - half))
		walls.append(Rect2(ROOM_WIDTH - t, ROOM_HEIGHT / 2.0 + half, t, ROOM_HEIGHT / 2.0 - half))
		if include_door_barriers:
			walls.append(Rect2(ROOM_WIDTH - t, ROOM_HEIGHT / 2.0 - half, t, DOOR_WIDTH))
	else:
		walls.append(Rect2(ROOM_WIDTH - t, 0.0, t, ROOM_HEIGHT))

	return walls

func _rebuild_walls() -> void:
	for body in _wall_bodies:
		if is_instance_valid(body):
			_physics_bodies.erase(body)
			body.queue_free()
	_wall_bodies.clear()
	for rect in get_walls(is_locked()):
		var body := StaticBody2D.new()
		var shape := CollisionShape2D.new()
		var rect_shape := RectangleShape2D.new()
		rect_shape.size = rect.size
		shape.shape = rect_shape
		shape.position = rect.position + rect.size / 2.0
		body.add_child(shape)
		add_child(body)
		_wall_bodies.append(body)
		_physics_bodies.append(body)
		_set_body_collision_enabled(body, _is_active)
	queue_redraw()

## Call once a room's `cleared` (or ritual_active) flips while it's the
## active room, so its door-barrier walls actually open/seal to match.
func refresh_walls() -> void:
	_rebuild_walls()

func add_enemy(enemy: EnemyCharacter) -> void:
	add_child(enemy)
	enemies.append(enemy)
	_physics_bodies.append(enemy)
	_set_body_collision_enabled(enemy, _is_active)
	if _is_active:
		enemy.add_to_group("enemies")
	else:
		enemy.remove_from_group("enemies")

## obstacles holds landmarks (stairs, merchant stall, shrine, brazier) as
## well as plain scatter — anything Obstacle.ts would push onto room.obstacles.
func add_obstacle(obstacle: ObstacleNode) -> void:
	add_child(obstacle)
	obstacles.append(obstacle)
	_physics_bodies.append(obstacle)
	_set_body_collision_enabled(obstacle, _is_active)

func add_pickup(pickup: Node2D) -> void:
	add_child(pickup)
	pickups.append(pickup)

func set_chest_node(c: ChestNode) -> void:
	add_child(c)
	chest = c

func _set_body_collision_enabled(body: CollisionObject2D, enabled: bool) -> void:
	body.collision_layer = 1 if enabled else 0
	body.collision_mask = 1 if enabled else 0

## The only room ever visible/simulating is the one the player is in.
## Toggles rendering, ALL processing of this room's whole subtree (Godot
## propagates process_mode to descendants, so one line stops every enemy's
## own _physics_process too), physics collision on every tracked body (see
## this file's header for why process_mode alone isn't enough), and the
## "enemies" group membership that combat/projectile code queries — without
## that last part, a hidden room's enemies would still be valid melee/
## projectile targets purely by sharing the same 0..1000,0..620 coordinates.
func set_active(active: bool) -> void:
	_is_active = active
	visible = active
	process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	for body in _physics_bodies:
		if is_instance_valid(body):
			_set_body_collision_enabled(body, active)
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		if active:
			enemy.add_to_group("enemies")
		else:
			enemy.remove_from_group("enemies")

## A real floor TEXTURE (a supplied stone-flagstone image) replaces the
## flat zone-tinted floor rect this drew at build-order step 7. Stretched
## to fill the room rect exactly rather than tiled — the source has its
## own baked-in directional lighting (a warm highlight sweeping across it),
## so repeating it across a room would show seams and repeated hot spots;
## a single non-uniform stretch to 1000x620 has neither, at the cost of a
## slight aspect distortion from the source's own square 1254x1254, which
## is what the image was supplied for (its own construction assumes
## whatever stretch a target rect needs). One shared texture for every
## zone/room, not a per-zone set — only one image was supplied — so
## zone.palette_floor no longer has a floor rect to tint, and neither does
## palette_wall below now that the walls are a real texture too — see
## _draw_walls()'s own comment for why that one couldn't just be stretched
## the same simple way.
## Sol fourni par l'utilisateur (1672x941). D'abord etire en un seul
## draw_texture_rect sur toute la salle (comme floor_stone.png l'etait), ce
## qui deformait l'image de ~10-15% (son rapport 1,78 contre 1,61 pour la
## salle). Verifie ensuite que l'image se reboucle proprement sur elle-meme --
## assemblage 2x2 zoome pile sur le point de jonction des 4 tuiles, aucune
## ligne de coupure, aucun motif qui se repete -- donc plus besoin d'etirer :
## FLOOR_TILE_SCALE fixe combien d'unites-monde vaut un pixel de la texture,
## et draw_texture_rect(..., true) la reboucle nativement pour remplir le
## rectangle donne, sans distorsion et sans code de tuilage a la main (les
## tuiles de bord, partielles, sont decoupees par le moteur lui-meme).
const FLOOR_TEXTURE := preload("res://assets/textures/floor_ember_crust.png")
const FLOOR_TILE_SCALE := 0.16

func _draw() -> void:
	# draw_set_transform doit etre remis a l'identite avant _draw_walls() --
	# meme convention que enemy.gd, un transform laisse actif fuiterait dans
	# tous les draw_* suivants de ce _draw().
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(FLOOR_TILE_SCALE, FLOOR_TILE_SCALE))
	draw_texture_rect(FLOOR_TEXTURE,
		Rect2(0.0, 0.0, ROOM_WIDTH / FLOOR_TILE_SCALE, ROOM_HEIGHT / FLOOR_TILE_SCALE), true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_walls()

## Real WALL textures — a supplied sprite sheet of separately pre-cut
## horizontal and vertical stone-wall strips at several lengths each,
## already alpha-cut clean (a straight brightness-scan-outward check on
## the raw sheet found literally zero border alpha on the horizontal
## piece and single-digit/255 residue on the vertical one — negligible,
## no feathering needed) — replace both WALL_TEXTURE (the earlier supplied
## closed-frame image) and the proportional-crop-with-corner-margin
## machinery that image needed. That machinery existed only because the
## frame was ONE picture of all four walls at once with no door gaps
## drawn in and a rounded, non-square outer corner, so a piece run through
## a naive proportional map into a shared border band could sample past
## the corner post into the frame's own black interior; picking the
## longest horizontal and longest vertical piece off this new sheet
## instead (cropped tight to content — originally WALL_HORIZONTAL 949x48
## and WALL_VERTICAL 48x325; both were later replaced with a higher-
## resolution recrop, currently 1592x157 and 163x795, without changing
## anything below) gives each piece its own dedicated, fully self-
## contained texture with nothing beyond its edges to sample past, so a
## piece is just stretched to fill its destination the same simple way
## FLOOR_TEXTURE already is — no shared crop, no corner math, no
## interior to accidentally reach. Door gaps and locked-room barriers
## still need real per-piece geometry, though (a closed door reading as
## open would be a navigation-clarity bug, not a cosmetic one) — so the
## same has_door()/is_locked() branching get_walls() itself uses for
## collision is still reproduced here, once per side. get_walls()'s
## Rect2-only return doesn't carry which side each rect came from and
## can't grow that without disturbing its other two callers
## (_setup_physics_bodies's collision geometry and projectile.gd's own
## wall check), which is why this stays a separate function rather than
## a change to get_walls() itself.
## Murs fournis par l'utilisateur (meme lot que floor_ember_crust.png). La
## piece horizontale (1256x326) est une bande complete, murs+piliers+bannieres,
## etiree une fois sur toute la largeur -- exactement comme WALL_TEXTURE_H
## l'etait deja, aucun changement de mecanisme.
## La piece verticale d'origine (238x873, chapiteau + banniere + base a
## decombres) ne boucle pas : ses bords haut/bas ne se raccordent pas, et
## _draw_wall_v_tiled() la repete verticalement sur toute la hauteur du mur.
## wall_ember_v.png est donc un decoupage de 160px pris DANS la portion
## generique du fut (aucune banniere, aucun chapiteau), les deux bords choisis
## sur un joint de pierre pour que la repetition se lise comme un joint de
## plus et non comme une coupure -- verifie en pile de 3 avant integration.
const WALL_TEXTURE_H := preload("res://assets/textures/wall_ember_h.png")
const WALL_TEXTURE_V := preload("res://assets/textures/wall_ember_v.png")

## Stretching a wall piece's whole texture across its destination in one
## draw_texture_rect call works fine everywhere else — every other piece
## stretches by at most ~1.05x, matching WALL_TEXTURE_H's own full-width
## case — but the full, undoored W/E wall stretches WALL_TEXTURE_V's
## 325px height to ROOM_HEIGHT's 620, a ~1.9x upscale a real screenshot
## showed visibly soft next to every other piece's near-native sharpness
## (a direct report of "the image quality" after that screenshot went
## out, not a guess). Splitting it into evenly-sized tiles, each
## stretched by no more than WALL_V_MAX_STRETCH, keeps every tile close
## to 1:1. The source isn't built to tile seamlessly, so the seam between
## tiles repeats the same joint pattern rather than hiding it, but that
## reads far better than the blur it replaces — confirmed the same way,
## with another real screenshot after the change, not assumed from the
## math alone.
##
## That original fix compared tex_h to h in world-units only — it never
## knew about entities/player.tscn's Camera2D.zoom = Vector2(1.5, 1.5),
## which magnifies every world-space draw (this one included) by another
## 1.5x before it ever reaches the screen. The godot/README.md texture-
## audit entry found this the hard way: with the current (higher-res)
## WALL_TEXTURE_V, h / (tex_h * WALL_V_MAX_STRETCH) alone judges the full
## undoored span safe at 1 tile (620 / (795*1.1) < 1), but the real on-
## screen texel density at that tile count is ~0.85 texel/px once the
## 1.5x zoom is included — a ~17% oversize confirmed on a real screenshot,
## not just the math. CAMERA_ZOOM folds that factor into the same
## comparison so the tile count this function picks matches what's
## actually shown on screen instead of only the pre-zoom world geometry.
## Window/stretch resolution presets (project.godot) add a further,
## variable factor on top of this that no world-space draw call can ever
## see or correct for — CAMERA_ZOOM only closes the gap this function can
## actually reach.
const CAMERA_ZOOM := 1.5
const WALL_V_MAX_STRETCH := 1.1

func _draw_wall_v_tiled(x: float, y: float, w: float, h: float) -> void:
	var tex_h := float(WALL_TEXTURE_V.get_height())
	var tile_count := maxi(1, ceili((h * CAMERA_ZOOM) / (tex_h * WALL_V_MAX_STRETCH)))
	var tile_h := h / float(tile_count)
	for i in range(tile_count):
		draw_texture_rect(WALL_TEXTURE_V, Rect2(x, y + i * tile_h, w, tile_h), false)

## Repete WALL_TEXTURE_H sur la largeur sans jamais deformer ses proportions.
## _draw_wall_v_tiled ci-dessus fixe la LARGEUR (l'epaisseur du mur) et choisit
## la hauteur de chaque tuile pour viser une nettete d'affichage correcte,
## sans chercher a egaler le ratio de la source -- c'est defendable la, car
## l'axe qu'il ne fixe pas (la hauteur) n'est pas celui qui posait probleme.
## Pour Nord/Sud c'est l'inverse : chaque draw_texture_rect(WALL_TEXTURE_H,
## Rect2(x,y,w,t), false) etirait la source (1256x326) dans un rectangle de
## hauteur t=WALL_THICKNESS=46 ET de largeur w (jusqu'a ROOM_WIDTH=1000 sans
## porte) -- deux facteurs d'echelle tres differents sur les deux axes
## (~46/326=0.14 en hauteur contre ~1000/1256=0.80 en largeur), exactement la
## deformation verticale des briques que Nord montrait. Ici l'axe fixe est la
## HAUTEUR -- l'epaisseur du mur ne bouge jamais -- et UN SEUL facteur
## d'echelle (scale = h / tex_h) s'applique aux deux axes a la fois : chaque
## brique garde exactement son ratio d'origine. tile=true reboucle la texture
## pour couvrir toute la largeur demandee et decoupe lui-meme la derniere
## tuile partielle en bord de segment, sans code de comptage de tuiles a la
## main -- meme mecanisme deja verifie sur le sol (FLOOR_TILE_SCALE). Nord et
## Sud appellent tous les deux cette meme fonction, avec ou sans porte,
## verrouillee ou non : c'est ce qui les rend visuellement identiques l'un a
## l'autre et a la meme logique de repetition que les murs lateraux.
func _draw_wall_h_tiled(x: float, y: float, w: float, h: float) -> void:
	var tex_h := float(WALL_TEXTURE_H.get_height())
	var scale := h / tex_h
	draw_set_transform(Vector2(x, y), 0.0, Vector2(scale, scale))
	draw_texture_rect(WALL_TEXTURE_H, Rect2(0.0, 0.0, w / scale, h / scale), true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_walls() -> void:
	var t := WALL_THICKNESS
	var half := DOOR_WIDTH / 2.0
	var locked := is_locked()

	if has_door(Direction.N):
		var span := ROOM_WIDTH / 2.0 - half
		_draw_wall_h_tiled(0.0, 0.0, span, t)
		_draw_wall_h_tiled(ROOM_WIDTH / 2.0 + half, 0.0, span, t)
		if locked:
			_draw_wall_h_tiled(ROOM_WIDTH / 2.0 - half, 0.0, DOOR_WIDTH, t)
	else:
		_draw_wall_h_tiled(0.0, 0.0, ROOM_WIDTH, t)

	if has_door(Direction.S):
		var span := ROOM_WIDTH / 2.0 - half
		_draw_wall_h_tiled(0.0, ROOM_HEIGHT - t, span, t)
		_draw_wall_h_tiled(ROOM_WIDTH / 2.0 + half, ROOM_HEIGHT - t, span, t)
		if locked:
			_draw_wall_h_tiled(ROOM_WIDTH / 2.0 - half, ROOM_HEIGHT - t, DOOR_WIDTH, t)
	else:
		_draw_wall_h_tiled(0.0, ROOM_HEIGHT - t, ROOM_WIDTH, t)

	if has_door(Direction.W):
		var span := ROOM_HEIGHT / 2.0 - half
		draw_texture_rect(WALL_TEXTURE_V, Rect2(0.0, 0.0, t, span), false)
		draw_texture_rect(WALL_TEXTURE_V, Rect2(0.0, ROOM_HEIGHT / 2.0 + half, t, span), false)
		if locked:
			draw_texture_rect(WALL_TEXTURE_V, Rect2(0.0, ROOM_HEIGHT / 2.0 - half, t, DOOR_WIDTH), false)
	else:
		_draw_wall_v_tiled(0.0, 0.0, t, ROOM_HEIGHT)

	if has_door(Direction.E):
		var span := ROOM_HEIGHT / 2.0 - half
		draw_texture_rect(WALL_TEXTURE_V, Rect2(ROOM_WIDTH - t, 0.0, t, span), false)
		draw_texture_rect(WALL_TEXTURE_V, Rect2(ROOM_WIDTH - t, ROOM_HEIGHT / 2.0 + half, t, span), false)
		if locked:
			draw_texture_rect(WALL_TEXTURE_V, Rect2(ROOM_WIDTH - t, ROOM_HEIGHT / 2.0 - half, t, DOOR_WIDTH), false)
	else:
		_draw_wall_v_tiled(ROOM_WIDTH - t, 0.0, t, ROOM_HEIGHT)
