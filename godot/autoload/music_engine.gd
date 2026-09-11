extends Node
## Autoload: MusicEngine
##
## Ports audio/MusicEngine.ts — the fully procedural, self-looping ambient
## score: a continuous detuned drone gliding between chords, sparse "ember
## chime" plucks and a tension-noise pulse that fade in during combat/boss
## states, and (Hollow Ruins only) irregular water-drip ambience.
##
## Unlike SFX (step 10's first two slices — every sound is short enough to
## render as one complete buffer up front), the drone is genuinely
## continuous and needs real per-frame generation: three persistent
## AudioStreamGeneratorPlayback voices (two detuned sawtooths + a sine
## sub, mirroring droneOscA/droneOscB/droneSub) are topped up every
## `_process()` tick from a phase accumulator that's never reset, so the
## waveform never clicks across a refill boundary. Every "glide to a new
## value over N seconds" the source expresses as
## `AudioParam.setTargetAtTime(target, t, tau)` — the drone filter cutoff,
## the tension bus's own volume, and each drone oscillator's frequency —
## ports as the same exponential-approach recurrence Web Audio's own
## setTargetAtTime implements: `v += (target - v) * (1 - exp(-dt/tau))`,
## computed once per frame (see _approach()).
##
## Bus graph: "Drone" (new) carries the one shared lowpass filter the
## source's own droneFilter is — sends to "Music". "Tension" (new) carries
## plucks and the intensity-2 noise pulse, its own bus VOLUME animated
## every frame to stand in for the source's own tensionGain node (every
## one-shot note routed through a live gain node is scaled by whatever
## that node's value is the instant it plays — a bus's live volume
## reproduces exactly that, without needing per-voice envelopes) — sends
## to "Music". Water drips route straight to "Music" (the source's own
## ambienceGain is a STATIC 0.3 multiplier, never animated, so it's baked
## directly into each drip's own volume parameter instead of needing a
## fourth bus for a value that never changes).

const CHORD_DURATION := 7.0
const MOOD_GLIDE_TAU := 1.6
const CHORD_GLIDE_TAU := 2.2
const FILTER_GLIDE_TAU := 0.6
const TENSION_GLIDE_TAU := 1.2

const DRONE_BUS := "Drone"
const TENSION_BUS := "Tension"
const MUSIC_BUS := "Music"

const VOICE_POOL_SIZE := 8
const VOICE_BUFFER_LENGTH := 3.0

## chord = {root, fifth}. The Hollow Ruins' set: a semitone down, one
## chord carrying a lowered fifth (a tritone) so the drone never quite
## settles — colder, unresolved.
const CHORDS: Array[Dictionary] = [
	{"root": 110.0, "fifth": 164.81},
	{"root": 87.31, "fifth": 130.81},
	{"root": 130.81, "fifth": 196.0},
	{"root": 98.0, "fifth": 146.83},
]
const RUINS_CHORDS: Array[Dictionary] = [
	{"root": 103.83, "fifth": 155.56},
	{"root": 82.41, "fifth": 116.54},
	{"root": 116.54, "fifth": 174.61},
	{"root": 92.5, "fifth": 138.59},
]

const PLUCK_SCALE: Array[float] = [220.0, 246.94, 261.63, 293.66, 329.63, 349.23, 392.0, 440.0]
## G# natural minor for the ruins — same sparse plucks, darker ground.
const RUINS_PLUCK_SCALE: Array[float] = [207.65, 233.08, 246.94, 277.18, 311.13, 329.63, 369.99, 415.3]

var _started: bool = false
var _intensity: int = 0
## Which zone's chord set / pluck scale / ambience is playing (0 = Ashen Woods).
var _mood: int = 0
var _chord_timer: float = 0.0
var _chord_index: int = 0
var _glide_tau: float = CHORD_GLIDE_TAU
var _pluck_timer: float = 2.0
var _pulse_timer: float = 0.0
var _drip_timer: float = 3.0
var _lfo_phase: float = 0.0

var _filter: AudioEffectLowPassFilter = null
var _filter_cutoff: float = 900.0

var _tension_gain: float = 0.0

# Drone voices: phase never resets (continuity across refills), freq
# glides toward target every frame via _approach().
var _osc_a_player: AudioStreamPlayer = null
var _osc_a_playback: AudioStreamGeneratorPlayback = null
var _osc_a_phase: float = 0.0
var _osc_a_freq: float = 110.0
var _osc_a_target: float = 110.0

var _osc_b_player: AudioStreamPlayer = null
var _osc_b_playback: AudioStreamGeneratorPlayback = null
var _osc_b_phase: float = 0.0
var _osc_b_freq: float = 164.81
var _osc_b_target: float = 164.81

var _sub_player: AudioStreamPlayer = null
var _sub_playback: AudioStreamGeneratorPlayback = null
var _sub_phase: float = 0.0
var _sub_freq: float = 55.0
var _sub_target: float = 55.0

var _voices: Array[AudioStreamPlayer] = []
var _voice_gen: Array[int] = []
var _next_voice: int = 0

func _ready() -> void:
	# Music keeps playing while the game is paused (a modal, PauseMenu) —
	# ports Game.ts's own update(): music.update(dt) runs unconditionally,
	# before the pause-state early-out that gates everything else.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	_setup_voice_pool()

func _setup_buses() -> void:
	if AudioServer.get_bus_index(DRONE_BUS) == -1:
		AudioServer.add_bus()
		var idx: int = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, DRONE_BUS)
		AudioServer.set_bus_send(idx, MUSIC_BUS)
	if AudioServer.get_bus_index(TENSION_BUS) == -1:
		AudioServer.add_bus()
		var idx: int = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, TENSION_BUS)
		AudioServer.set_bus_send(idx, MUSIC_BUS)

	var drone_idx: int = AudioServer.get_bus_index(DRONE_BUS)
	for i in range(AudioServer.get_bus_effect_count(drone_idx)):
		var fx := AudioServer.get_bus_effect(drone_idx, i)
		if fx is AudioEffectLowPassFilter:
			_filter = fx
			break
	if _filter == null:
		_filter = AudioEffectLowPassFilter.new()
		_filter.cutoff_hz = _filter_cutoff
		_filter.resonance = 0.0
		AudioServer.add_bus_effect(drone_idx, _filter)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(TENSION_BUS), linear_to_db(0.0001))

func _setup_voice_pool() -> void:
	var mix_rate: float = AudioServer.get_mix_rate()
	# Playback objects are NOT fetched here — an AudioStreamGenerator's
	# AudioStreamGeneratorPlayback only becomes valid once its player is
	# actually play()-ing (get_stream_playback() on an inactive player
	# logs "Player is inactive" and returns null); start() fetches all 3
	# right after its own play() calls instead, and re-fetches on every
	# start() (including a stop()-then-start() restart), since a fresh
	# play() call hands back a fresh playback object each time.
	_osc_a_player = _make_continuous_voice(mix_rate, DRONE_BUS)
	_osc_b_player = _make_continuous_voice(mix_rate, DRONE_BUS)
	_sub_player = _make_continuous_voice(mix_rate, DRONE_BUS)

	for i in range(VOICE_POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.bus = TENSION_BUS
		var gen := AudioStreamGenerator.new()
		gen.mix_rate = mix_rate
		gen.buffer_length = VOICE_BUFFER_LENGTH
		player.stream = gen
		add_child(player)
		_voices.append(player)
		_voice_gen.append(0)

func _make_continuous_voice(mix_rate: float, bus: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = bus
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = mix_rate
	gen.buffer_length = 0.5
	player.stream = gen
	add_child(player)
	return player

static func _approach(current: float, target: float, delta: float, tau: float) -> float:
	return current + (target - current) * (1.0 - exp(-delta / maxf(0.0001, tau)))

func _chords() -> Array[Dictionary]:
	return RUINS_CHORDS if _mood == 1 else CHORDS

func _pluck_scale() -> Array[float]:
	return RUINS_PLUCK_SCALE if _mood == 1 else PLUCK_SCALE

## Detune is a constant pitch offset baked directly into the target
## frequency (matches the source's own osc.detune, set once and never
## animated) rather than modeled as a separate glide-able parameter.
func _retarget_chord(chord: Dictionary, tau: float) -> void:
	_osc_a_target = float(chord["root"]) * pow(2.0, -6.0 / 1200.0)
	_osc_b_target = float(chord["fifth"]) * pow(2.0, 5.0 / 1200.0)
	_sub_target = float(chord["root"]) / 2.0
	_glide_tau = tau

func start() -> void:
	if _started:
		return
	_started = true
	var chord: Dictionary = _chords()[0]
	_osc_a_freq = float(chord["root"]) * pow(2.0, -6.0 / 1200.0)
	_osc_b_freq = float(chord["fifth"]) * pow(2.0, 5.0 / 1200.0)
	_sub_freq = float(chord["root"]) / 2.0
	_osc_a_target = _osc_a_freq
	_osc_b_target = _osc_b_freq
	_sub_target = _sub_freq
	_osc_a_player.play()
	_osc_b_player.play()
	_sub_player.play()
	_osc_a_playback = _osc_a_player.get_stream_playback()
	_osc_b_playback = _osc_b_player.get_stream_playback()
	_sub_playback = _sub_player.get_stream_playback()

func stop() -> void:
	if not _started:
		return
	_started = false
	_osc_a_player.stop()
	_osc_b_player.stop()
	_sub_player.stop()

func set_intensity(level: int) -> void:
	_intensity = clampi(level, 0, 2)

## Glides the drone to the new mood's own current chord over MOOD_GLIDE_TAU
## rather than cutting — matches the source's own setMood exactly.
func set_mood(zone_index: int) -> void:
	var next: int = clampi(zone_index, 0, 2)
	if next == _mood:
		return
	_mood = next
	_chord_index = 0
	_chord_timer = 0.0
	if _started:
		_retarget_chord(_chords()[0], MOOD_GLIDE_TAU)

func _process(delta: float) -> void:
	if not _started:
		return

	_lfo_phase += delta

	# Drone filter cutoff: same formula as the source's own update(), the
	# ruins sitting under a lower ceiling (moodCut) and intensity opening
	# it up, gently animated by a slow LFO.
	var mood_cut: float = -140.0 if _mood == 1 else 0.0
	var target_cutoff: float = 700.0 + mood_cut + _intensity * 350.0 + sin(_lfo_phase * 0.15) * 180.0
	_filter_cutoff = _approach(_filter_cutoff, target_cutoff, delta, FILTER_GLIDE_TAU)
	if _filter != null:
		_filter.cutoff_hz = _filter_cutoff

	# Tension bus volume stands in for the source's own tensionGain node —
	# every pluck/pulse voice routed through the Tension bus is scaled by
	# whatever this is at the moment it plays, same as a live Web Audio
	# gain node would.
	var target_tension: float = 0.0
	if _intensity >= 1:
		target_tension = 0.16 if _intensity == 2 else 0.09
	_tension_gain = _approach(_tension_gain, target_tension, delta, TENSION_GLIDE_TAU)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(TENSION_BUS), linear_to_db(maxf(0.0001, _tension_gain)))

	_chord_timer += delta
	if _chord_timer >= CHORD_DURATION:
		_chord_timer = 0.0
		var chords: Array[Dictionary] = _chords()
		_chord_index = (_chord_index + 1) % chords.size()
		_retarget_chord(chords[_chord_index], CHORD_GLIDE_TAU)

	_osc_a_freq = _approach(_osc_a_freq, _osc_a_target, delta, _glide_tau)
	_osc_b_freq = _approach(_osc_b_freq, _osc_b_target, delta, _glide_tau)
	_sub_freq = _approach(_sub_freq, _sub_target, delta, _glide_tau)
	_osc_a_phase = _refill_continuous(_osc_a_playback, _osc_a_phase, _osc_a_freq, "sawtooth", 0.5 * 0.22)
	_osc_b_phase = _refill_continuous(_osc_b_playback, _osc_b_phase, _osc_b_freq, "sawtooth", 0.32 * 0.22)
	_sub_phase = _refill_continuous(_sub_playback, _sub_phase, _sub_freq, "sine", 0.55 * 0.22)

	if _mood == 1:
		_drip_timer -= delta
		if _drip_timer <= 0.0:
			_drip_timer = 2.2 + randf() * 4.5
			var freq: float = 1500.0 + randf() * 900.0
			_play_drip(freq, 0.0)
			if randf() < 0.4:
				_play_drip(freq * 1.18, 0.16 + randf() * 0.2)

	_pluck_timer -= delta
	if _pluck_timer <= 0.0:
		var base_interval: float = 1.6 if _intensity == 2 else (2.4 if _intensity == 1 else 3.6)
		_pluck_timer = base_interval * (1.35 if _mood == 1 else 1.0) + randf() * 2.5
		if randf() < 0.85:
			var scale: Array[float] = _pluck_scale()
			var note: float = scale[randi() % scale.size()]
			_play_pluck(note)

	if _intensity == 2:
		_pulse_timer -= delta
		if _pulse_timer <= 0.0:
			_pulse_timer = 0.85
			_play_pulse()

## Advances `phase` and tops up whatever ring-buffer space the voice has
## freed since the last frame — a persistent phase accumulator (never
## reset) is what keeps the waveform continuous across refills, the same
## reason AudioSynth's own one-shot generation accumulates phase per
## sample rather than computing it from `t` directly.
func _refill_continuous(playback: AudioStreamGeneratorPlayback, phase: float, freq: float, wave_type: String, gain: float) -> float:
	if playback == null:
		return phase
	var frames: int = playback.get_frames_available()
	if frames <= 0:
		return phase
	var mix_rate: float = AudioServer.get_mix_rate()
	var dt: float = 1.0 / mix_rate
	var buf := PackedVector2Array()
	buf.resize(frames)
	for i in range(frames):
		phase += TAU * freq * dt
		var s: float = AudioSynth.waveform_sample(wave_type, phase) * gain
		buf[i] = Vector2(s, s)
	playback.push_buffer(buf)
	return phase

# ---------------------------------------------------------------- one-shot layers

func _acquire_voice() -> int:
	for i in range(_voices.size()):
		if not _voices[i].playing:
			return i
	var idx: int = _next_voice
	_next_voice = (_next_voice + 1) % _voices.size()
	return idx

func _push_and_play(voice_idx: int, mono: PackedFloat32Array, bus: String) -> void:
	if mono.is_empty():
		return
	var player: AudioStreamPlayer = _voices[voice_idx]
	player.bus = bus
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
		push_warning("MusicEngine: buffer (%d frames) didn't fit the voice's ring buffer" % mono.size())
	var voice_duration: float = mono.size() / AudioServer.get_mix_rate()
	get_tree().create_timer(voice_duration).timeout.connect(func():
		if is_instance_valid(player) and my_gen == _voice_gen[voice_idx]:
			player.stop()
	)

## Ports the source's own sparse "ember chime" pluck: `tone(this.tensionGain,
## {freq: note, type: 'sine', duration: 1.4, attack: 0.05, decay: 1.3,
## volume: 0.5})` — the Tension bus itself (see _process()) supplies the
## tensionGain scaling the source gets from routing to that GainNode.
func _play_pluck(freq: float) -> void:
	var buffer: PackedFloat32Array = AudioSynth.generate_tone(AudioServer.get_mix_rate(), freq, null, "sine", 1.4, 0.05, 1.3, 0.5, 0.0)
	_push_and_play(_acquire_voice(), buffer, TENSION_BUS)

## Ports the source's own drip: a tiny bright blip, `tone(ambienceGain,
## {freq, freqEnd: freq*0.7, type:'sine', duration:0.09, attack:0.003,
## volume:0.35})` — ambienceGain (0.3, never animated) is baked directly
## into the volume passed here (0.35*0.3) rather than needing a bus of
## its own for a value that never changes; plays on Music directly, not
## Tension (the source's own ambienceGain is a separate, always-on node,
## not gated by combat intensity the way tensionGain is).
func _play_drip(freq: float, delay: float) -> void:
	var fire := func():
		var buffer: PackedFloat32Array = AudioSynth.generate_tone(AudioServer.get_mix_rate(), freq, freq * 0.7, "sine", 0.09, 0.003, null, 0.35 * 0.3, 0.0)
		_push_and_play(_acquire_voice(), buffer, MUSIC_BUS)
	if delay > 0.0:
		get_tree().create_timer(delay).timeout.connect(fire)
	else:
		fire.call()

## Ports the source's own intensity-2 tension pulse: `noise(this.tensionGain,
## {duration:0.3, filterType:'lowpass', freq:220, volume:0.4})`.
func _play_pulse() -> void:
	var buffer: PackedFloat32Array = AudioSynth.generate_noise(AudioServer.get_mix_rate(), 220.0, null, "lowpass", 1.0, 0.3, 0.4, 0.004)
	_push_and_play(_acquire_voice(), buffer, TENSION_BUS)
