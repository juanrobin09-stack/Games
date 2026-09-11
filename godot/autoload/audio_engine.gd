extends Node
## Autoload: AudioEngine
##
## Ports audio/AudioEngine.ts + audio/SoundFactory.ts — bus setup/settings
## from the former, every one of the latter's 51 SfxIds and its tone()/
## noise()/sub() primitives (the actual sample math lives in
## audio/audio_synth.gd; see that file's header for why this project
## synthesizes at trigger time rather than baking .ogg/.wav files: the
## same "procedurally generated, no external assets" identity this whole
## port has kept for every _draw() call, icon, wall texture and particle
## so far, not a new rule invented for audio specifically).
##
## Bus graph mirrors AudioEngine.ts's own masterGain <- {musicGain,
## sfxGain} fan-in, with a brickwall limiter on the summed bus (the
## source's own DynamicsCompressor at ratio 20:1 — its own comment calls
## it a "brickwall limiter" outright, so this uses Godot's dedicated
## AudioEffectLimiter rather than hand-tuning AudioEffectCompressor to
## chase parameters a Web-Audio-specific node doesn't have a Godot
## analog for; same "rewrite against the engine's own tools" call
## GODOT_MIGRATION.md §4 already made for particles/lighting).
##
## SFX playback is a fixed pool of pooled AudioStreamPlayer voices, each
## backed by an AudioStreamGenerator — Web Audio has no real polyphony
## limit (a new node graph per call), so a genuinely unbounded voice
## count would be the more literal port, but every real game engine caps
## simultaneous voices for exactly this reason; VOICE_POOL_SIZE is sized
## well above this game's actual simultaneous-hit counts (multi-target
## cleave, elite death + several impacts, a boss phase transition) so
## stealing should be rare in practice, not a real audible cap.

const MASTER_BUS := "Master"
const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"

const VOICE_POOL_SIZE := 24
## Comfortably above the longest SFX (zoneArrive's own noise burst, ~1.9s)
## with headroom — a voice's whole buffer is pushed in one push_buffer()
## call right after play(), so this just needs to be >= that duration.
const VOICE_BUFFER_LENGTH := 3.0
const DEFAULT_THROTTLE_MS := 25.0

var _voices: Array[AudioStreamPlayer] = []
var _voice_gen: Array[int] = []
var _next_voice: int = 0
var _last_play_ms: Dictionary = {}
var _players: Dictionary = {}

func _ready() -> void:
	_setup_buses()
	_setup_voice_pool()
	_build_players()
	_apply_settings()
	MetaProgression.settings_changed.connect(func(_patch): _apply_settings())

func _setup_buses() -> void:
	if AudioServer.get_bus_index(MUSIC_BUS) == -1:
		AudioServer.add_bus()
		var idx: int = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, MUSIC_BUS)
		AudioServer.set_bus_send(idx, MASTER_BUS)
	if AudioServer.get_bus_index(SFX_BUS) == -1:
		AudioServer.add_bus()
		var idx: int = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, SFX_BUS)
		AudioServer.set_bus_send(idx, MASTER_BUS)

	var master_idx: int = AudioServer.get_bus_index(MASTER_BUS)
	var has_limiter := false
	for i in range(AudioServer.get_bus_effect_count(master_idx)):
		if AudioServer.get_bus_effect(master_idx, i) is AudioEffectLimiter:
			has_limiter = true
			break
	if not has_limiter:
		var limiter := AudioEffectLimiter.new()
		limiter.ceiling_db = -0.3
		limiter.threshold_db = -6.0
		AudioServer.add_bus_effect(master_idx, limiter)

func _setup_voice_pool() -> void:
	var mix_rate: float = AudioServer.get_mix_rate()
	for i in range(VOICE_POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.bus = SFX_BUS
		var gen := AudioStreamGenerator.new()
		gen.mix_rate = mix_rate
		gen.buffer_length = VOICE_BUFFER_LENGTH
		player.stream = gen
		add_child(player)
		_voices.append(player)
		_voice_gen.append(0)

## Ports AudioEngine.ts's applySettings(): master's mute is a dedicated
## bus mute (true silence) rather than a 0.0 volume — a slider dragged to
## its own minimum still goes through the normal dB path below, floored
## just above 0 so linear_to_db never has to reason about an exact-zero
## input.
func _apply_settings() -> void:
	var settings: Dictionary = MetaProgression.settings
	AudioServer.set_bus_mute(AudioServer.get_bus_index(MASTER_BUS), bool(settings.get("muted", false)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(MASTER_BUS), linear_to_db(_floor01(settings.get("master_volume", 1.0))))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(MUSIC_BUS), linear_to_db(_floor01(settings.get("music_volume", 0.8))))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(SFX_BUS), linear_to_db(_floor01(settings.get("sfx_volume", 0.9))))

static func _floor01(v) -> float:
	return clampf(float(v), 0.0001, 1.0)

# ---------------------------------------------------------------- Voice pool

func _acquire_voice() -> int:
	for i in range(_voices.size()):
		if not _voices[i].playing:
			return i
	var idx: int = _next_voice
	_next_voice = (_next_voice + 1) % _voices.size()
	return idx

func _push_and_play(voice_idx: int, mono: PackedFloat32Array) -> void:
	if mono.is_empty():
		return
	var player: AudioStreamPlayer = _voices[voice_idx]
	_voice_gen[voice_idx] += 1
	var my_gen: int = _voice_gen[voice_idx]
	player.stop()
	player.play()
	var playback: AudioStreamGeneratorPlayback = player.get_stream_playback()
	var stereo := PackedVector2Array()
	stereo.resize(mono.size())
	for i in range(mono.size()):
		stereo[i] = Vector2(mono[i], mono[i])
	if not playback.push_buffer(stereo):
		push_warning("AudioEngine: SFX buffer (%d frames) didn't fit the voice's ring buffer" % mono.size())
	var voice_duration: float = mono.size() / AudioServer.get_mix_rate()
	get_tree().create_timer(voice_duration).timeout.connect(func():
		# A stale timer from a voice that's since been stolen and reused
		# must not stop the NEW sound playing on it — same "cancel the
		# stale callback" guard this project already uses for _run_ending.
		if is_instance_valid(player) and my_gen == _voice_gen[voice_idx]:
			player.stop()
	)

# ---------------------------------------------------------------- tone()/noise()/sub()

## Mirrors ToneOpts verbatim as Dictionary keys (freq, freq_end, type,
## duration, attack, decay, volume, delay, detune) so every call site
## below reads as a near-literal transcription of the TS object literal
## it ports — deliberately not a typed method signature; with 90+ call
## sites across 51 SFX, a positional-argument API of this many same-typed
## floats would be far easier to transpose by mistake than to catch by
## review.
func _tone(opts: Dictionary) -> void:
	var delay: float = opts.get("delay", 0.0)
	if delay > 0.0:
		get_tree().create_timer(delay).timeout.connect(func(): _emit_tone(opts))
	else:
		_emit_tone(opts)

func _emit_tone(opts: Dictionary) -> void:
	var buffer: PackedFloat32Array = AudioSynth.generate_tone(
		AudioServer.get_mix_rate(),
		opts["freq"], opts.get("freq_end"), opts.get("type", "sine"),
		opts["duration"], opts.get("attack", 0.008), opts.get("decay"),
		opts.get("volume", 0.5), opts.get("detune", 0.0)
	)
	_push_and_play(_acquire_voice(), buffer)

## Ports sub(): tone() forced to a sine wave, for bass/sub-bass layers.
func _sub(opts: Dictionary) -> void:
	var o: Dictionary = opts.duplicate()
	o["type"] = "sine"
	_tone(o)

## Mirrors NoiseOpts verbatim (freq, freq_end, filter_type, q, duration,
## volume, attack, delay) — same reasoning as _tone() above.
func _noise(opts: Dictionary) -> void:
	var delay: float = opts.get("delay", 0.0)
	if delay > 0.0:
		get_tree().create_timer(delay).timeout.connect(func(): _emit_noise(opts))
	else:
		_emit_noise(opts)

func _emit_noise(opts: Dictionary) -> void:
	var buffer: PackedFloat32Array = AudioSynth.generate_noise(
		AudioServer.get_mix_rate(),
		opts["freq"], opts.get("freq_end"), opts.get("filter_type", "bandpass"),
		opts.get("q", 1.0), opts["duration"], opts.get("volume", 0.4),
		opts.get("attack", 0.004)
	)
	_push_and_play(_acquire_voice(), buffer)

# ---------------------------------------------------------------- playSfx()

## Ports playSfx(): per-id throttling (default 25ms) so a rapid retrigger
## (a multi-hit combo, several simultaneous pickups) can't pile up voices
## faster than they're perceptible as distinct hits.
func play_sfx(id: String, throttle_ms: float = DEFAULT_THROTTLE_MS) -> void:
	var now: int = Time.get_ticks_msec()
	var last: int = _last_play_ms.get(id, -1000000)
	if now - last < throttle_ms:
		return
	_last_play_ms[id] = now
	var fn = _players.get(id)
	if fn == null:
		push_warning("AudioEngine: unknown SfxId '%s'" % id)
		return
	fn.call()

## Ports resetSfxThrottle().
func reset_sfx_throttle() -> void:
	_last_play_ms.clear()

func _build_players() -> void:
	_players = {
		"attackSwing": _sfx_attack_swing,
		"attackSwingHeavy": _sfx_attack_swing_heavy,
		"attackRanged": _sfx_attack_ranged,
		"impactLight": _sfx_impact_light,
		"impactCrit": _sfx_impact_crit,
		"dodge": _sfx_dodge,
		"perfectDodge": _sfx_perfect_dodge,
		"abilityEmberBurst": _sfx_ability_ember_burst,
		"abilityStormstep": _sfx_ability_stormstep,
		"abilityWardingSigil": _sfx_ability_warding_sigil,
		"synergyFormed": _sfx_synergy_formed,
		"pickupEmber": _sfx_pickup_ember,
		"pickupSoulAsh": _sfx_pickup_soul_ash,
		"pickupHeart": _sfx_pickup_heart,
		"chestOpenCommon": func(): _sfx_chest_open(1),
		"chestOpenRare": func(): _sfx_chest_open(2),
		"chestOpenEpic": func(): _sfx_chest_open(3),
		"chestOpenLegendary": func(): _sfx_chest_open(4),
		"uiClick": _sfx_ui_click,
		"uiHover": _sfx_ui_hover,
		"uiBack": _sfx_ui_back,
		"upgradeChoose": _sfx_upgrade_choose,
		"levelUp": _sfx_level_up,
		"enemyHit": _sfx_enemy_hit,
		"enemyDeath": _sfx_enemy_death,
		"eliteDeath": _sfx_elite_death,
		"bossHit": _sfx_boss_hit,
		"bossPhase": _sfx_boss_phase,
		"bossDeath": _sfx_boss_death,
		"bossRoar": _sfx_boss_roar,
		"playerHurt": _sfx_player_hurt,
		"playerDeath": _sfx_player_death,
		"shopBuy": _sfx_shop_buy,
		"shopError": _sfx_shop_error,
		"eventChoice": _sfx_event_choice,
		"doorOpen": _sfx_door_open,
		"shieldBreak": _sfx_shield_break,
		"shieldUp": _sfx_shield_up,
		"interact": _sfx_interact,
		"roomCleared": _sfx_room_cleared,
		"stairsDescend": _sfx_stairs_descend,
		"zoneArrive": _sfx_zone_arrive,
		"sealBreak": _sfx_seal_break,
		"sporeBurst": _sfx_spore_burst,
		"sporeHiss": _sfx_spore_hiss,
		"bloatSwell": _sfx_bloat_swell,
		"shieldClang": _sfx_shield_clang,
		"wardenBash": _sfx_warden_bash,
		"shieldShatter": _sfx_shield_shatter,
		"ritualCandle": _sfx_ritual_candle,
		"ritualComplete": _sfx_ritual_complete,
	}

# ---------------------------------------------------------------- SFX definitions
# Every function below is a direct transcription of SoundFactory.ts's own
# `players` record, in the same order, one function per SfxId.

func _sfx_attack_swing() -> void:
	_noise({"duration": 0.09, "filter_type": "highpass", "freq": 2200, "freq_end": 900, "volume": 0.18, "q": 0.6})
	_tone({"freq": 480, "freq_end": 220, "type": "triangle", "duration": 0.08, "volume": 0.14})

func _sfx_attack_swing_heavy() -> void:
	_noise({"duration": 0.16, "filter_type": "highpass", "freq": 1400, "freq_end": 500, "volume": 0.24, "q": 0.5})
	_sub({"freq": 160, "freq_end": 70, "duration": 0.18, "volume": 0.22})

func _sfx_attack_ranged() -> void:
	_tone({"freq": 900, "freq_end": 1500, "type": "sine", "duration": 0.1, "volume": 0.16})
	_noise({"duration": 0.08, "filter_type": "highpass", "freq": 3000, "volume": 0.08})

func _sfx_impact_light() -> void:
	_noise({"duration": 0.07, "filter_type": "bandpass", "freq": 1600, "freq_end": 600, "volume": 0.22, "q": 1.2})
	_sub({"freq": 140, "freq_end": 60, "duration": 0.1, "volume": 0.2})

func _sfx_impact_crit() -> void:
	_noise({"duration": 0.12, "filter_type": "bandpass", "freq": 2400, "freq_end": 500, "volume": 0.3, "q": 1.0})
	_tone({"freq": 1200, "freq_end": 300, "type": "square", "duration": 0.1, "volume": 0.14})
	_sub({"freq": 180, "freq_end": 50, "duration": 0.16, "volume": 0.26})

func _sfx_dodge() -> void:
	_noise({"duration": 0.18, "filter_type": "bandpass", "freq": 1800, "freq_end": 300, "volume": 0.16, "q": 0.8})
	_tone({"freq": 700, "freq_end": 260, "type": "sine", "duration": 0.15, "volume": 0.1})

func _sfx_perfect_dodge() -> void:
	_tone({"freq": 900, "freq_end": 1500, "type": "sine", "duration": 0.12, "volume": 0.14})
	_tone({"freq": 1500, "freq_end": 2100, "type": "sine", "duration": 0.14, "volume": 0.09, "delay": 0.04})
	_noise({"duration": 0.1, "filter_type": "highpass", "freq": 3000, "volume": 0.08})

func _sfx_ability_ember_burst() -> void:
	_noise({"duration": 0.4, "filter_type": "lowpass", "freq": 4000, "freq_end": 200, "volume": 0.35, "q": 0.7})
	_sub({"freq": 90, "freq_end": 40, "duration": 0.5, "volume": 0.4})
	_tone({"freq": 1600, "freq_end": 2600, "type": "sine", "duration": 0.25, "volume": 0.12, "delay": 0.02})

func _sfx_ability_stormstep() -> void:
	_tone({"freq": 300, "freq_end": 1400, "type": "sawtooth", "duration": 0.18, "volume": 0.14})
	_noise({"duration": 0.2, "filter_type": "highpass", "freq": 2000, "volume": 0.18})

func _sfx_ability_warding_sigil() -> void:
	_tone({"freq": 220, "freq_end": 440, "type": "sine", "duration": 0.5, "volume": 0.16})
	_tone({"freq": 330, "freq_end": 660, "type": "sine", "duration": 0.5, "volume": 0.1, "delay": 0.05})

func _sfx_synergy_formed() -> void:
	_tone({"freq": 392, "type": "sine", "duration": 0.5, "volume": 0.14})
	_tone({"freq": 587.33, "type": "sine", "duration": 0.55, "volume": 0.13, "delay": 0.09})
	_tone({"freq": 784, "type": "triangle", "duration": 0.7, "volume": 0.12, "delay": 0.18})
	_tone({"freq": 1568, "type": "sine", "duration": 0.5, "volume": 0.06, "delay": 0.22})

func _sfx_pickup_ember() -> void:
	_tone({"freq": 920, "type": "sine", "duration": 0.09, "volume": 0.16})
	_tone({"freq": 1380, "type": "sine", "duration": 0.12, "volume": 0.1, "delay": 0.03})

func _sfx_pickup_soul_ash() -> void:
	_tone({"freq": 500, "freq_end": 850, "type": "triangle", "duration": 0.16, "volume": 0.16})
	_tone({"freq": 750, "freq_end": 1200, "type": "sine", "duration": 0.2, "volume": 0.1, "delay": 0.04})

func _sfx_pickup_heart() -> void:
	_tone({"freq": 600, "freq_end": 500, "type": "sine", "duration": 0.18, "volume": 0.16})
	_tone({"freq": 900, "freq_end": 750, "type": "sine", "duration": 0.22, "volume": 0.1, "delay": 0.05})

## Ports chestOpen(tier): shared by the 4 chestOpen* ids, tier 1-4.
func _sfx_chest_open(tier: int) -> void:
	_noise({"duration": 0.3, "filter_type": "lowpass", "freq": 700, "freq_end": 1200, "volume": 0.16, "q": 0.6})
	var notes: Array[float] = [523.0, 659.0, 784.0, 988.0]
	var count: int = mini(tier + 1, notes.size())
	for i in range(count):
		_tone({"freq": notes[i], "type": "triangle", "duration": 0.28, "volume": 0.12, "delay": i * 0.07})

func _sfx_ui_click() -> void:
	_tone({"freq": 700, "freq_end": 500, "type": "square", "duration": 0.05, "volume": 0.08})

func _sfx_ui_hover() -> void:
	_tone({"freq": 900, "type": "sine", "duration": 0.04, "volume": 0.05})

func _sfx_ui_back() -> void:
	_tone({"freq": 500, "freq_end": 350, "type": "square", "duration": 0.06, "volume": 0.07})

func _sfx_upgrade_choose() -> void:
	var delays: Array[float] = [0.0, 0.06, 0.12]
	for i in range(delays.size()):
		_tone({"freq": 520.0 + i * 180.0, "type": "triangle", "duration": 0.18, "volume": 0.13, "delay": delays[i]})

func _sfx_level_up() -> void:
	var delays: Array[float] = [0.0, 0.08, 0.16, 0.26]
	for i in range(delays.size()):
		_tone({"freq": 440.0 * pow(1.2599, i), "type": "triangle", "duration": 0.3, "volume": 0.15, "delay": delays[i]})

func _sfx_enemy_hit() -> void:
	_noise({"duration": 0.06, "filter_type": "bandpass", "freq": 1200, "freq_end": 400, "volume": 0.16, "q": 1.0})

func _sfx_enemy_death() -> void:
	_tone({"freq": 340, "freq_end": 60, "type": "sawtooth", "duration": 0.3, "volume": 0.14})
	_noise({"duration": 0.25, "filter_type": "lowpass", "freq": 1200, "freq_end": 200, "volume": 0.14})

func _sfx_elite_death() -> void:
	_tone({"freq": 260, "freq_end": 40, "type": "sawtooth", "duration": 0.55, "volume": 0.2})
	_noise({"duration": 0.5, "filter_type": "lowpass", "freq": 1800, "freq_end": 150, "volume": 0.22})
	_sub({"freq": 100, "freq_end": 35, "duration": 0.6, "volume": 0.2, "delay": 0.05})

func _sfx_boss_hit() -> void:
	_noise({"duration": 0.16, "filter_type": "bandpass", "freq": 900, "freq_end": 300, "volume": 0.28, "q": 0.9})
	_sub({"freq": 130, "freq_end": 45, "duration": 0.22, "volume": 0.3})

func _sfx_boss_phase() -> void:
	_tone({"freq": 110, "freq_end": 70, "type": "sawtooth", "duration": 1.1, "volume": 0.28})
	_tone({"freq": 165, "freq_end": 90, "type": "sawtooth", "duration": 1.0, "volume": 0.18, "delay": 0.05})
	_noise({"duration": 0.8, "filter_type": "lowpass", "freq": 2000, "freq_end": 300, "volume": 0.2})

func _sfx_boss_death() -> void:
	_tone({"freq": 200, "freq_end": 30, "type": "sawtooth", "duration": 1.6, "volume": 0.3})
	_tone({"freq": 300, "freq_end": 40, "type": "sawtooth", "duration": 1.4, "volume": 0.2, "delay": 0.08})
	_noise({"duration": 1.5, "filter_type": "lowpass", "freq": 2500, "freq_end": 100, "volume": 0.26})

func _sfx_boss_roar() -> void:
	_tone({"freq": 90, "freq_end": 130, "type": "sawtooth", "duration": 0.6, "volume": 0.26})
	_noise({"duration": 0.5, "filter_type": "bandpass", "freq": 500, "freq_end": 900, "volume": 0.2, "q": 0.6})

func _sfx_player_hurt() -> void:
	_tone({"freq": 260, "freq_end": 140, "type": "sawtooth", "duration": 0.16, "volume": 0.2})
	_noise({"duration": 0.12, "filter_type": "highpass", "freq": 1000, "volume": 0.15})

func _sfx_player_death() -> void:
	_tone({"freq": 300, "freq_end": 50, "type": "sine", "duration": 1.4, "volume": 0.22})
	_tone({"freq": 200, "freq_end": 35, "type": "sine", "duration": 1.6, "volume": 0.16, "delay": 0.15})

func _sfx_shop_buy() -> void:
	_tone({"freq": 1100, "type": "sine", "duration": 0.07, "volume": 0.14})
	_tone({"freq": 1500, "type": "sine", "duration": 0.1, "volume": 0.1, "delay": 0.05})

func _sfx_shop_error() -> void:
	_tone({"freq": 220, "type": "square", "duration": 0.12, "volume": 0.12})

func _sfx_event_choice() -> void:
	_tone({"freq": 500, "freq_end": 700, "type": "sine", "duration": 0.3, "volume": 0.14})

func _sfx_door_open() -> void:
	_noise({"duration": 0.4, "filter_type": "lowpass", "freq": 500, "freq_end": 900, "volume": 0.14, "q": 0.5})

func _sfx_shield_break() -> void:
	_noise({"duration": 0.2, "filter_type": "highpass", "freq": 3500, "freq_end": 1200, "volume": 0.22, "q": 0.9})
	_tone({"freq": 1800, "freq_end": 400, "type": "triangle", "duration": 0.18, "volume": 0.12})

func _sfx_shield_up() -> void:
	_tone({"freq": 500, "freq_end": 900, "type": "sine", "duration": 0.2, "volume": 0.14})

func _sfx_interact() -> void:
	_tone({"freq": 640, "type": "sine", "duration": 0.06, "volume": 0.1})

func _sfx_room_cleared() -> void:
	_tone({"freq": 440, "type": "sine", "duration": 0.2, "volume": 0.1})
	_tone({"freq": 660, "type": "sine", "duration": 0.3, "volume": 0.12, "delay": 0.08})

## Four stone footfalls, each a little lower and further away, under a
## long cold draft — same as the source's own inline comment.
func _sfx_stairs_descend() -> void:
	var delays: Array[float] = [0.0, 0.28, 0.56, 0.84]
	for i in range(delays.size()):
		var d: float = delays[i]
		_noise({"duration": 0.09, "filter_type": "bandpass", "freq": 720.0 - i * 90.0, "freq_end": 280, "volume": 0.17 - i * 0.03, "q": 1.4, "delay": d})
		_sub({"freq": 118.0 - i * 12.0, "freq_end": 58, "duration": 0.12, "volume": 0.15 - i * 0.025, "delay": d})
	_noise({"duration": 1.7, "filter_type": "lowpass", "freq": 420, "freq_end": 130, "volume": 0.12, "attack": 0.35})

## Deep reverberant boom of arriving somewhere vast, then a thin cold hiss.
func _sfx_zone_arrive() -> void:
	_sub({"freq": 70, "freq_end": 32, "duration": 1.5, "volume": 0.34})
	_tone({"freq": 140, "freq_end": 55, "type": "triangle", "duration": 1.2, "volume": 0.11, "delay": 0.02})
	_noise({"duration": 1.9, "filter_type": "highpass", "freq": 2600, "freq_end": 900, "volume": 0.07, "attack": 0.5})

## The stairwell's stone lid grinding aside.
func _sfx_seal_break() -> void:
	_noise({"duration": 0.95, "filter_type": "bandpass", "freq": 240, "freq_end": 430, "volume": 0.21, "q": 2.0, "attack": 0.05})
	_sub({"freq": 55, "freq_end": 38, "duration": 0.85, "volume": 0.22})
	_tone({"freq": 1200, "freq_end": 1900, "type": "sine", "duration": 0.5, "volume": 0.05, "delay": 0.55})

## Wet pop, then the hiss of spores settling.
func _sfx_spore_burst() -> void:
	_tone({"freq": 320, "freq_end": 90, "type": "sine", "duration": 0.16, "volume": 0.22})
	_noise({"duration": 0.12, "filter_type": "lowpass", "freq": 1500, "freq_end": 300, "volume": 0.22})
	_noise({"duration": 0.7, "filter_type": "bandpass", "freq": 3200, "freq_end": 1800, "volume": 0.09, "q": 0.8, "attack": 0.05})

func _sfx_spore_hiss() -> void:
	_noise({"duration": 0.22, "filter_type": "bandpass", "freq": 2600, "freq_end": 1400, "volume": 0.12, "q": 1.1})
	_tone({"freq": 220, "freq_end": 160, "type": "triangle", "duration": 0.12, "volume": 0.06})

## A rising, straining tone under the swell — the "get away" cue.
func _sfx_bloat_swell() -> void:
	_tone({"freq": 90, "freq_end": 260, "type": "sine", "duration": 0.8, "volume": 0.12, "attack": 0.1})
	_noise({"duration": 0.8, "filter_type": "bandpass", "freq": 600, "freq_end": 1600, "volume": 0.06, "q": 1.5, "attack": 0.2})

func _sfx_shield_clang() -> void:
	_tone({"freq": 1500, "freq_end": 900, "type": "square", "duration": 0.07, "volume": 0.09})
	_noise({"duration": 0.09, "filter_type": "bandpass", "freq": 2800, "freq_end": 1200, "volume": 0.16, "q": 2.2})
	_tone({"freq": 420, "freq_end": 300, "type": "triangle", "duration": 0.12, "volume": 0.08})

func _sfx_warden_bash() -> void:
	_noise({"duration": 0.22, "filter_type": "lowpass", "freq": 1800, "freq_end": 400, "volume": 0.2})
	_sub({"freq": 110, "freq_end": 45, "duration": 0.24, "volume": 0.24})

func _sfx_shield_shatter() -> void:
	_noise({"duration": 0.5, "filter_type": "highpass", "freq": 1800, "freq_end": 500, "volume": 0.28, "q": 0.8})
	_tone({"freq": 900, "freq_end": 180, "type": "square", "duration": 0.3, "volume": 0.1})
	_sub({"freq": 90, "freq_end": 35, "duration": 0.6, "volume": 0.28})
	var delays: Array[float] = [0.08, 0.16, 0.27]
	for d in delays:
		_noise({"duration": 0.06, "filter_type": "bandpass", "freq": 1400, "volume": 0.1, "q": 2.0, "delay": d})

func _sfx_ritual_candle() -> void:
	_noise({"duration": 0.25, "filter_type": "bandpass", "freq": 1200, "freq_end": 2600, "volume": 0.1, "q": 1.0})
	_tone({"freq": 660, "type": "sine", "duration": 0.6, "volume": 0.09, "attack": 0.02})
	_tone({"freq": 990, "type": "sine", "duration": 0.7, "volume": 0.05, "delay": 0.05})

func _sfx_ritual_complete() -> void:
	var notes: Array[float] = [330.0, 440.0, 554.37, 659.25]
	for i in range(notes.size()):
		_tone({"freq": notes[i], "type": "triangle", "duration": 0.9, "volume": 0.12, "delay": i * 0.12})
	_sub({"freq": 82, "freq_end": 60, "duration": 1.2, "volume": 0.18})
