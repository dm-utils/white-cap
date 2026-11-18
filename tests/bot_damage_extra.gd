extends Node
## Independent checks for the bot damage split (docs/design.md 3.9) and the tagline (ADR 007), plus Strandbal
## survival of a scripted human. Headless: godot --headless --path . res://tests/bot_damage_extra.tscn

var _passed := 0
var _failed := 0


func check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL: " + what)


func _ready() -> void:
	test_tagline()
	test_split_via_match()
	test_leaver_in_flight()
	test_determinism_with_leaver_and_profiles()
	test_ball_human_values()
	print("extra tests: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func test_tagline() -> void:
	for loc in ["en", "nl"]:
		TranslationServer.set_locale(loc)
		check(tr("BOOT_TAGLINE") == "Survival of the driest!", "tagline in %s (got '%s')" % [loc, tr("BOOT_TAGLINE")])
		check(tr("TITLE") == "WHITE CAP", "title in %s" % loc)
		var screen: Control = load("res://ui/boot_screen.gd").new()
		add_child(screen)
		var texts: Array = []
		var stack: Array = [screen]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n is Label:
				texts.append(n.text)
			stack.append_array(n.get_children())
		check(texts.has("Survival of the driest!") and texts.has("WHITE CAP"), "boot screen shows title and tagline in %s %s" % [loc, str(texts)])
		check(not texts.any(func(t): return str(t).to_lower().contains("working") or str(t).to_lower().contains("werktitel")), "no working title on boot screen in %s" % loc)
		screen.queue_free()
	var f := FileAccess.open("res://i18n/strings.csv", FileAccess.READ)
	var csv := f.get_as_text().to_lower()
	check(not csv.contains("working title") and not csv.contains("werktitel") and not csv.contains("boot_working"), "csv has no working title")
	TranslationServer.set_locale("en")


## Match with 2 humans (animals chosen), flip slots to bots with make_bot, measure HP lost from one hit each.
func _loss(atk: String, vic: String, atk_bot: bool, vic_bot: bool, cmd: Dictionary, ticks: int, level := "hard") -> int:
	var m := Match.create_online(42, [atk, vic], 2, level)
	var s := m.sim
	s.projs.clear()
	s.snacks.clear()
	s.ents[0].x = 14500
	s.ents[0].y = 12500
	s.ents[1].x = 14500
	s.ents[1].y = 14500
	if atk_bot:
		m.make_bot(0)
	if vic_bot:
		m.make_bot(1)
	if cmd.has("s"):
		s.ents[0].special = int(s.rules.attack.special_hits)
	var hp := int(s.ents[1].hp)
	for t in ticks:
		s.step([cmd if t == 0 else {}, {}])
	return hp - int(s.ents[1].hp)


func test_split_via_match() -> void:
	var shot := {"a": 1024}
	var dash := {"s": 1024, "sd": 2000}
	for level in ["easy", "normal", "hard"]:
		var cfg := BotBrain.level_config(level)
		for pair in [["crab", "crab", shot, 6, 0], ["crab", "crab", dash, 10, 1], ["gull", "crab", dash, 14, 2], ["octopus", "gull", shot, 8, 0]]:
			var atk: String = pair[0]
			var d := BotBrain.damage_pcts(cfg, atk, "")
			var cmd: Dictionary = pair[2]
			var ticks: int = pair[3]
			var base := _loss(atk, str(pair[1]), false, false, cmd, ticks, level)
			var vs_human := _loss(atk, str(pair[1]), true, false, cmd, ticks, level)
			var vs_bot := _loss(atk, str(pair[1]), true, true, cmd, ticks, level)
			var human_vs_bot := _loss(atk, str(pair[1]), false, true, cmd, ticks, level)
			var tag := "%s %s %s" % [level, atk, str(cmd.keys())]
			check(base > 0, "%s: base damage lands (%d)" % [tag, base])
			var tol := 1 if atk == "octopus" else 0 # multi-hit shot: rounding per hit
			check(absi(vs_human - base * d.y / 100) <= tol, "%s: bot vs human = base x %d (%d vs %d)" % [tag, d.y, vs_human, base * d.y / 100])
			check(absi(vs_bot - base * d.x / 100) <= tol, "%s: bot vs bot = base x %d (%d vs %d)" % [tag, d.x, vs_bot, base * d.x / 100])
			check(human_vs_bot == base, "%s: human vs bot = base (%d vs %d)" % [tag, human_vs_bot, base])
	# water: unscaled, same on easy and hard, also for a bot victim of either kind
	var w := []
	for level in ["easy", "hard"]:
		for bot in [false, true]:
			var m := Match.create_online(42, ["crab", "gull"], 2, level)
			if bot:
				m.make_bot(0)
			m.sim.ents[0].x = 4500
			m.sim.ents[0].y = 4500
			var hp := int(m.sim.ents[0].hp)
			for t in 5:
				m.sim.step([{}, {}])
			w.append(hp - int(m.sim.ents[0].hp))
	check(w.all(func(x): return x == w[0]) and w[0] > 0, "water damage identical for every level and victim kind %s" % str(w))
	# idempotent make_bot
	var m2 := Match.create(5, "crab", 6, "hard")
	var before := m2.sim.state_hash()
	for e in m2.sim.ents.slice(1):
		m2.make_bot(e.id)
	check(before == m2.sim.state_hash(), "make_bot is idempotent")


## Bot shot in flight, victim leaves (becomes a bot) before impact: impact uses the victim's state at impact.
func test_leaver_in_flight() -> void:
	var m := Match.create_online(42, ["crab", "crab"], 2, "hard")
	var s := m.sim
	s.projs.clear()
	s.snacks.clear()
	s.ents[0].x = 14500
	s.ents[0].y = 12500
	s.ents[1].x = 14500
	s.ents[1].y = 14500
	m.make_bot(0)
	var hp := int(s.ents[1].hp)
	s.step([{"a": 1024}, {}])
	check(s.projs.size() == 1 and int(s.projs[0].damage) == int(s.animals[0].attack.damage), "projectile carries base damage (%s)" % str(s.projs.size()))
	m.to_bot(1)
	for t in 8:
		s.step([{}, {}])
	var d := BotBrain.damage_pcts(BotBrain.level_config("hard"), "crab", "")
	var lost := hp - int(s.ents[1].hp)
	check(lost == int(s.animals[0].attack.damage) * d.x / 100, "shot in flight hits the leaver at bot-vs-bot rate (%d)" % lost)


func _run(seed_value: int, level: String, mode: String, leave_at: int, profile: String, ticks: int) -> int:
	var m: Match
	var tp: TestPlayer = null
	if profile == "":
		m = Match.create_online(seed_value, ["crab", "gull"], 6, level, mode)
	else:
		m = Match.create(seed_value, "crab", 6, level, mode)
		tp = TestPlayer.new(profile)
	for t in ticks:
		if leave_at >= 0 and t == leave_at:
			m.to_bot(1)
		if tp != null:
			m.step(tp.next(m.sim, m.sim.ents[0]) if m.sim.ents[0].alive else {})
		else:
			m.step_many({})
	return m.sim.state_hash()


func test_determinism_with_leaver_and_profiles() -> void:
	for level in ["easy", "normal", "hard"]:
		var a := _run(11, level, "", 200, "", 1500)
		var b := _run(11, level, "", 200, "", 1500)
		var c := _run(12, level, "", 200, "", 1500)
		var d := _run(11, level, "", 400, "", 1500)
		check(a == b, "%s: online with leaver twice -> same hash" % level)
		check(a != c and a != d, "%s: other seed or other leave tick -> other hash" % level)
		for p in ["casual", "skilled", "legacy"]:
			check(_run(21, level, "", -1, p, 1200) == _run(21, level, "", -1, p, 1200), "%s %s: same seed -> same hash" % [level, p])
	check(_run(31, "normal", "ball", 300, "", 1800) == _run(31, "normal", "ball", 300, "", 1800), "ball online with leaver twice -> same hash")


func test_ball_human_values() -> void:
	var m := Match.create(3, "crab", 6, "normal", "ball")
	var b: MatchSim.Ent = m.sim.ents[1]
	print("ball normal: human ", m.sim.ents[0].damage_pct, "/", m.sim.ents[0].human_damage_pct, " bot ", b.damage_pct, "/", b.human_damage_pct,
		" rules.ball.damage_pct ", m.sim.rules.ball.get("damage_pct", "none"))
	# KOs taken by the scripted human in slot 0 versus the mean of the five bots, Strandbal normal
	for profile in ["casual", "skilled"]:
		var human_kos := 0
		var bot_kos := 0
		var n := 12
		for i in n:
			var mm := Match.create(100 + i * 13, "crab", 6, "normal", "ball")
			var tp := TestPlayer.new(profile)
			while not mm.finished():
				mm.step(tp.next(mm.sim, mm.sim.ents[0]) if mm.sim.ents[0].alive else {})
				for ev in mm.sim.events:
					if ev.type == "ko":
						if int(ev.id) == 0:
							human_kos += 1
						else:
							bot_kos += 1
		print("ball normal %s: human KOs taken per match %.2f, mean per bot %.2f (%d matches)" % [profile, float(human_kos) / n, float(bot_kos) / n / 5.0, n])
