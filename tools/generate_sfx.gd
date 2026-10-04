extends SceneTree
## Inspect (and optionally export) the procedural sound effects.
## godot --headless --path . --script res://tools/generate_sfx.gd [-- --out=C:/some/dir]

const SynthAudio = preload("res://audio/synth_audio.gd")


func _init() -> void:
	var out_dir: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.substr(6)
	var failed: bool = false
	for kind: String in ["flap", "blast", "channel", "charge"]:
		var s: PackedFloat32Array = SynthAudio.samples_for(kind)
		var peak: float = 0.0
		var sq: float = 0.0
		for v: float in s:
			peak = maxf(peak, absf(v))
			sq += v * v
		var rms: float = sqrt(sq / maxf(s.size(), 1.0))
		var line: String = "%s: %d samples (%.2fs) peak=%.3f rms=%.3f" % [kind, s.size(), s.size() / float(SynthAudio.MIX_RATE), peak, rms]
		if kind == "channel":
			var seam: float = absf(s[0] - s[s.size() - 1])
			var typical: float = 0.0
			for i in range(1, s.size()):
				typical += absf(s[i] - s[i - 1])
			typical /= s.size() - 1
			line += " seam_step=%.4f typical_step=%.4f" % [seam, typical]
			if seam > typical * 6.0:
				failed = true
		print(line)
		if peak < 0.2 or peak > 1.0 or rms < 0.02:
			failed = true
		if SynthAudio.stream(kind) != SynthAudio.stream(kind):
			failed = true
		if out_dir != "":
			DirAccess.make_dir_recursive_absolute(out_dir)
			SynthAudio.stream(kind).save_to_wav(out_dir.path_join(kind + ".wav"))
	print("generate_sfx: ", "FAILED" if failed else "OK")
	quit(1 if failed else 0)
