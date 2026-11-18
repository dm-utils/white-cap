extends Node2D
## Debug scene for art review: every animal and look, in every animation, side by side (scene=zoo, page=N).
## Each state retriggers every 1.2 s so a screenshot at any moment shows it. Labels are debug text, not tr().

const STATES := ["idle", "walk", "swim", "attack", "hit", "ko", "win", "special"]
const ROWS_PER_PAGE := 5
const COL_W := 205.0

var _cells: Array = []
var _t := 0.0


## Rows from data: every animal in the roster with its standard colours, then every look in palette.json.
static func rows() -> Array:
	var out: Array = []
	for id in Match.roster():
		out.append([id, ""])
	for look in Content.load_json("res://data/palette.json").looks:
		out.append([str(Content.load_json("res://data/palette.json").looks[look].animal), str(look)])
	return out


static func page_count() -> int:
	return (rows().size() + ROWS_PER_PAGE - 1) / ROWS_PER_PAGE


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("F2D49B")
	bg.size = Vector2(1920, 1080)
	bg.z_index = -100 # parts behind the body (limbs, tentacles) use negative z
	add_child(bg)
	var all := rows()
	var page := clampi(int(Boot.args.get("page", "0")), 0, page_count() - 1)
	for r in ROWS_PER_PAGE:
		var idx := page * ROWS_PER_PAGE + r
		if idx >= all.size():
			break
		var row: Array = all[idx]
		var special_kind := str(Content.animal(str(row[0])).get("special", {}).get("kind", ""))
		var guard := str(Content.animal(str(row[0])).get("special", {}).get("mech", "")) == "guard"
		_label(str(row[0]) + (" / " + str(row[1]) if row[1] != "" else ""), Vector2(20, 120 + r * 200))
		for s in STATES.size():
			if r == 0:
				_label(STATES[s], Vector2(240 + s * COL_W, 20))
			var c := Cutout.new()
			c.size_px = 130.0
			add_child(c)
			c.build(str(row[0]), str(row[1]))
			c.position = Vector2(310 + s * COL_W, 200 + r * 200)
			c.moving = STATES[s] == "walk"
			c.swimming = STATES[s] == "swim" and row[0] != "gull"
			if STATES[s] == "special" and guard:
				c.guard_kind = special_kind
			_cells.append([c, STATES[s]])


func _label(text: String, pos: Vector2) -> void:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_color_override("font_color", Color("2B3A4A"))
	l.add_theme_font_size_override("font_size", 28)
	add_child(l)


func _process(delta: float) -> void:
	var before := fmod(_t, 1.2)
	_t += delta
	if fmod(_t, 1.2) < before:
		for cell in _cells:
			var c: Cutout = cell[0]
			match str(cell[1]):
				"attack", "hit", "win":
					c.trigger(str(cell[1]))
				"special":
					c.trigger("attack")
				"ko":
					c.free_ko_restart()
