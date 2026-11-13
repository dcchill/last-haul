class_name ArmoryAudio
extends RefCounted

# Original procedural substitutes for Minecraft's unavailable sound events.
static func make_sound(kind: String) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	var duration := 0.65 if kind == "explosion" else 0.18
	var samples := int(duration * stream.mix_rate)
	var data := PackedByteArray()
	data.resize(samples * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 312
	for index in range(samples):
		var time := float(index) / stream.mix_rate
		var envelope := exp(-time * (9 if kind == "explosion" else 24))
		var value := (rng.randf_range(-1, 1) * 0.6 + sin(time * TAU * (65 if kind == "explosion" else 220)) * 0.4) * envelope
		data.encode_s16(index * 2, int(value * 14000))
	stream.data = data
	return stream
