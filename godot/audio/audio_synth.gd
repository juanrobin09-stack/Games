class_name AudioSynth
extends RefCounted
## Ports audio/SoundFactory.ts's tone()/noise() — the two procedural
## synthesis primitives every one of AudioEngine's SFX definitions is
## built from. Unlike the TS source (which schedules each call as its own
## live Web Audio node graph, torn down via onended), each call here
## synthesizes its ENTIRE buffer up front, in one pass, before playback —
## every SFX in this game is short (well under 2s), so there's no need for
## the streaming/ring-buffer refill GODOT_MIGRATION.md's own §4 flags as
## the real cost of a live-synthesis path; AudioEngine just pushes the
## finished buffer to an AudioStreamGeneratorPlayback in one push_buffer()
## call and lets it drain — "render once per trigger", not "stream
## forever". Every envelope/frequency ramp is computed as one pow() call
## up front plus a per-sample multiply (not a pow() call per sample) —
## the exponential-ramp math is identical, just reassociated to be cheap
## enough to run synchronously on the main thread without a frame hitch,
## even for the ~2s worst-case sounds (bossDeath, zoneArrive).
##
## The noise() filter (bandpass/highpass/lowpass, with a sweeping cutoff)
## is a textbook RBJ "Audio EQ Cookbook" biquad — the same formulas the
## Web Audio spec itself defines BiquadFilterNode against, so this isn't
## an approximation of the source's filtering, it's the same math.
## Coefficients are recomputed every COEFF_BLOCK samples rather than every
## sample as the cutoff sweeps — inaudibly coarse at audio rate, and cuts
## the trig-heavy coefficient recompute by 64x.
##
## Every generated buffer is fresh white/oscillator noise per call, not a
## slice of one shared pre-baked buffer like the source's own noiseBuffer
## — indistinguishable for a short filtered burst, and avoids AudioEngine
## needing to own long-lived shared sample state for no perceptible gain.

## The floor every exponentialRampToValueAtTime(...) call in the source
## ramps down to — Web Audio's exponential ramps can never target exactly
## 0, and the source picks this same near-silent floor everywhere.
const ENV_FLOOR := 0.0008
const TAIL_SECONDS := 0.05
const COEFF_BLOCK := 64

static func _waveform(wave_type: String, phase: float) -> float:
	match wave_type:
		"sine":
			return sin(phase)
		"square":
			return 1.0 if sin(phase) >= 0.0 else -1.0
		"sawtooth":
			var frac: float = phase / TAU
			return 2.0 * (frac - floor(frac + 0.5))
		"triangle":
			var frac: float = phase / TAU
			var saw: float = 2.0 * (frac - floor(frac + 0.5))
			return 2.0 * absf(saw) - 1.0
		_:
			return sin(phase)

## Public entry point for callers (MusicEngine's continuous drone refill)
## that need a single raw waveform sample without going through
## generate_tone()'s envelope/buffer machinery.
static func waveform_sample(wave_type: String, phase: float) -> float:
	return _waveform(wave_type, phase)

## Ports tone(). `freq_end`/`decay` are Variant so callers can pass null
## for the source's own optional freqEnd/decay (decay defaults to
## `duration` exactly like every TS call site that omits it).
static func generate_tone(sample_rate: float, freq: float, freq_end: Variant, wave_type: String, duration: float, attack: float, decay: Variant, volume: float, detune: float = 0.0) -> PackedFloat32Array:
	var eff_decay: float = float(decay) if decay != null else duration
	var detune_mult: float = pow(2.0, detune / 1200.0) if detune != 0.0 else 1.0
	var f0: float = freq * detune_mult
	var has_end: bool = freq_end != null
	var f1: float = maxf(1.0, float(freq_end)) * detune_mult if has_end else f0

	var dt: float = 1.0 / sample_rate
	var attack_samples: int = maxi(0, int(round(attack * sample_rate)))
	var decay_samples: int = maxi(1, int(round(eff_decay * sample_rate)))
	var end_samples: int = attack_samples + decay_samples
	var n: int = end_samples + maxi(1, int(round(TAIL_SECONDS * sample_rate)))
	var ramp_samples: int = (maxi(1, int(round(duration * sample_rate))) if has_end else n)

	var out := PackedFloat32Array()
	out.resize(n)

	var freq_now := f0
	var freq_step: float = (pow(f1 / f0, 1.0 / ramp_samples) if (has_end and f0 > 0.0) else 1.0)
	var decay_rate: float = pow(ENV_FLOOR / volume, 1.0 / decay_samples)
	var attack_step: float = (volume / attack_samples if attack_samples > 0 else 0.0)

	var phase := 0.0
	var env := 0.0
	for i in range(n):
		if i < attack_samples:
			env = attack_step * i
		elif i == attack_samples:
			env = volume
		elif i < end_samples:
			env *= decay_rate
		# else: hold at the floor for the trailing pad, same as a Web
		# Audio ramp holding its last scheduled value past the target time.

		phase += TAU * freq_now * dt
		if has_end and i < ramp_samples:
			freq_now *= freq_step

		out[i] = _waveform(wave_type, phase) * env
	return out

## Ports noise(). noise()'s own decay ramps across the FULL `duration`
## from t=0 (there's no separate decay param, unlike tone()).
static func generate_noise(sample_rate: float, freq: float, freq_end: Variant, filter_type: String, q: float, duration: float, volume: float, attack: float = 0.004) -> PackedFloat32Array:
	var has_end: bool = freq_end != null
	var f1: float = (maxf(1.0, float(freq_end)) if has_end else freq)

	var dt: float = 1.0 / sample_rate
	var attack_samples: int = maxi(0, int(round(attack * sample_rate)))
	var duration_samples: int = maxi(attack_samples + 1, int(round(duration * sample_rate)))
	var n: int = duration_samples + maxi(1, int(round(TAIL_SECONDS * sample_rate)))
	var ramp_samples: int = (duration_samples if has_end else n)

	var raw := PackedFloat32Array()
	raw.resize(n)
	for i in range(n):
		raw[i] = randf_range(-1.0, 1.0)

	var decay_samples: int = duration_samples - attack_samples
	var decay_rate: float = pow(ENV_FLOOR / volume, 1.0 / decay_samples)
	var attack_step: float = (volume / attack_samples if attack_samples > 0 else 0.0)

	var cutoff := freq
	var cutoff_step: float = (pow(f1 / freq, float(COEFF_BLOCK) / ramp_samples) if (has_end and freq > 0.0) else 1.0)

	var out := PackedFloat32Array()
	out.resize(n)
	var b0 := 0.0
	var b1 := 0.0
	var b2 := 0.0
	var a1 := 0.0
	var a2 := 0.0
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	var env := 0.0

	for i in range(n):
		if i % COEFF_BLOCK == 0:
			var coeffs := _biquad_coeffs(filter_type, maxf(20.0, cutoff), q, sample_rate)
			b0 = coeffs[0]
			b1 = coeffs[1]
			b2 = coeffs[2]
			a1 = coeffs[3]
			a2 = coeffs[4]
			if has_end and i < ramp_samples:
				cutoff *= cutoff_step

		if i < attack_samples:
			env = attack_step * i
		elif i == attack_samples:
			env = volume
		elif i < duration_samples:
			env *= decay_rate

		var x0: float = raw[i]
		var y0: float = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x0
		y2 = y1
		y1 = y0

		out[i] = y0 * env
	return out

## RBJ "Audio EQ Cookbook" biquad coefficients (the same reference the Web
## Audio spec cites for BiquadFilterNode). Returns [b0, b1, b2, a1, a2],
## already normalized by a0. Only the 3 filter types SoundFactory.ts
## actually uses are implemented; anything else falls back to bandpass.
static func _biquad_coeffs(filter_type: String, cutoff: float, q: float, sample_rate: float) -> PackedFloat32Array:
	var w0: float = clampf(TAU * cutoff / sample_rate, 0.0001, PI - 0.0001)
	var cos_w0: float = cos(w0)
	var alpha: float = sin(w0) / (2.0 * maxf(0.0001, q))
	var b0 := 0.0
	var b1 := 0.0
	var b2 := 0.0
	var a0 := 1.0 + alpha
	var a1 := -2.0 * cos_w0
	var a2 := 1.0 - alpha
	match filter_type:
		"highpass":
			b0 = (1.0 + cos_w0) / 2.0
			b1 = -(1.0 + cos_w0)
			b2 = (1.0 + cos_w0) / 2.0
		"lowpass":
			b0 = (1.0 - cos_w0) / 2.0
			b1 = 1.0 - cos_w0
			b2 = (1.0 - cos_w0) / 2.0
		_: # bandpass (constant 0 dB peak gain)
			b0 = alpha
			b1 = 0.0
			b2 = -alpha
	return PackedFloat32Array([b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0])
