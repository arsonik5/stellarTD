extends SceneTree

## Trait lab (stage 1): seeds x body kinds -> trait mix -> palette -> harmony check, no planet loaded.
##     godot --headless --path . --script res://scripts/dev/trait_lab.gd [-- seeds=20]
## Prints one TRAIT line per planet, a summary of how often each trait leads / joins, and writes the 64 px swatches
## (one row per planet) to art_src/ingame/trait_lab_<kind>.png for the eye check.
const KINDS := {
	"small_airless":  {"radius_m": 900.0, "air_density": 0.0, "temperature": 0.45, "atmosphere": false, "water": false, "geologically_active": false},
	"cold_moon":      {"radius_m": 2200.0, "air_density": 0.0, "temperature": 0.15, "atmosphere": false, "water": false, "geologically_active": true},
	"temperate_air":  {"radius_m": 20000.0, "air_density": 1.2, "temperature": 0.5, "atmosphere": true, "water": true, "geologically_active": true},
	"hot_active":     {"radius_m": 9000.0, "air_density": 0.4, "temperature": 0.82, "atmosphere": true, "water": false, "geologically_active": true},
	"icy_big":        {"radius_m": 12000.0, "air_density": 0.05, "temperature": 0.08, "atmosphere": true, "water": false, "geologically_active": true},
}

func _init() -> void:
	var seeds := 20
	for a in OS.get_cmdline_user_args():
		if a.begins_with("seeds="):
			seeds = int(a.substr(6))
		elif a.begins_with("body="):
			# one real body: its facts, its mix, its palette, its harmony
			var body := load(a.substr(5)) as CelestialBody
			var f := TraitMixer.facts_for(body)
			var m := TraitMixer.of(body) if (body.generate_traits or not body.trait_override.is_empty()) else TraitMixer.mix(body.seed, f)
			var pal := PaletteBuilder.build(m)
			print("BODY %s facts %s" % [body.display_name, f])
			print("BODY mix %s" % TraitMixer.describe(m))
			for idx in pal.roles:
				var c: Vector3 = pal.report.oklch.get(idx, Vector3.ZERO)
				print("BODY slot %2d %-26s L %.2f C %.3f h %3.0f" % [idx, pal.roles[idx], c.x, c.y, c.z])
			print("BODY harmony ", "ok" if pal.report.ok else pal.report.warnings)
			print("BODY dbg ", PaletteBuilder.displayed_colour(pal.styles[0]), " ", PaletteBuilder.oklch(Color(0.5, 0.3, 0.2)), " ", SurfacePalette.surface_file((pal.styles[0] as SurfaceStyle).texture_name, ".json"))
			PaletteBuilder.swatch(pal.styles, 64).save_png(ProjectSettings.globalize_path("res://art_src/ingame/trait_body_%s.png" % body.display_name.to_lower()))
			quit(0)
			return
	var lead := {}
	var joins := {}
	var fails := 0
	var total := 0
	for kind: String in KINDS:
		var facts: Dictionary = KINDS[kind]
		var rows: Array[Image] = []
		for s in range(1, seeds + 1):
			var m := TraitMixer.mix(s * 7919 + kind.hash(), facts)
			var pal := PaletteBuilder.build(m)
			var rep: Dictionary = pal.report
			total += 1
			if not rep.ok:
				fails += 1
			var dom := String((m[0].trait as PlanetTrait).id) if not m.is_empty() else "-"
			lead[dom] = int(lead.get(dom, 0)) + 1
			for i in range(1, m.size()):
				var id := String((m[i].trait as PlanetTrait).id)
				joins[id] = int(joins.get(id, 0)) + 1
			print("TRAIT %-13s seed %2d  %-48s %s" % [kind, s, TraitMixer.describe(m), "ok" if rep.ok else "WARN " + "; ".join(rep.warnings)])
			rows.append(PaletteBuilder.swatch(pal.styles, 32))
		var w := 0
		for r in rows:
			w = maxi(w, r.get_width())
		var sheet := Image.create_empty(w, 32 * rows.size(), false, Image.FORMAT_RGB8)
		for i in rows.size():
			sheet.blit_rect(rows[i], Rect2i(0, 0, rows[i].get_width(), 32), Vector2i(0, i * 32))
		sheet.save_png(ProjectSettings.globalize_path("res://art_src/ingame/trait_lab_%s.png" % kind))
	print("TRAITLAB leads ", lead, " joins ", joins)
	print("TRAITLAB_DONE planets=%d harmony_fails=%d" % [total, fails])
	quit(0)
