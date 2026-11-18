class_name TestPlayer
extends RefCounted
## Scripted stand-ins for a human, reading the sim only (never sim.rng), so replays and metrics are reproducible.
## `legacy` (static cmd): perfect-aim turret, used by golden data. `casual` and `skilled` bracket a real player
## (docs/design.md 3.9.4); one instance per match, memory in the fields.

var profile := "legacy"
var next_shot := 0
var dodge_until := 0
var dodge_dir := 0
var react_at := 0
var circle := 1
var flip_at := 0


func _init(p_profile := "legacy") -> void:
	profile = p_profile


## Deterministic noise 0..n-1 from the match state; salt keeps the uses apart.
static func noise(sim: MatchSim, me: MatchSim.Ent, salt: int, n: int) -> int:
	var h := ((sim.seed_value * 73856093) ^ (sim.tick * 19349663) ^ (me.id * 83492791) ^ (salt * 2654435761)) & 0xFFFFFFFF
	h ^= (h << 13) & 0xFFFFFFFF
	h ^= h >> 17
	h ^= (h << 5) & 0xFFFFFFFF
	return (h & 0x7FFFFFFF) % n


func next(sim: MatchSim, me: MatchSim.Ent) -> Dictionary:
	if profile == "legacy":
		return TestPlayer.cmd(sim, me)
	var t := _nearest(sim, me)
	var cmd := TestPlayer.cmd(sim, me) if profile == "casual" else {"m": -1, "a": -1, "s": -1}
	cmd.a = -1
	cmd.s = -1
	if t == null:
		return cmd
	var reach := sim.attack_range(me)
	var d := Fx.dist(t.x - me.x, t.y - me.y)
	var ready := me.special >= int(sim.rules.attack.special_hits)
	var speed := int(sim.animals[me.id].attack.speed)
	if profile == "casual":
		var err := noise(sim, me, 1, 901) - 450
		if d <= reach and sim.tick >= next_shot:
			cmd.a = posmod(Fx.atan2_a(t.y - me.y, t.x - me.x) + err, Fx.ANGLES)
			next_shot = sim.tick + 20
		if ready and d <= 6000:
			cmd.s = Fx.atan2_a(t.y - me.y, t.x - me.x)
			cmd["sd"] = d
		return cmd
	# skilled
	if d <= reach * 95 / 100:
		var p := BotBrain.lead_point(sim, me, t, speed, 60)
		cmd.a = posmod(Fx.atan2_a(p.y - me.y, p.x - me.x) + noise(sim, me, 1, 301) - 150, Fx.ANGLES)
	if ready and d <= reach * 70 / 100:
		var p := BotBrain.lead_point(sim, me, t, int(sim.animals[me.id].special.get("speed", speed)), 100)
		cmd.s = Fx.atan2_a(p.y - me.y, p.x - me.x)
		cmd["sd"] = d
	if sim.tick >= react_at:
		react_at = sim.tick + 6
		if sim.tick >= dodge_until:
			var th := BotBrain.incoming_threat(sim, me)
			if not th.is_empty() and noise(sim, me, 2, 100) < 60:
				_sidestep(sim, me, th)
	if sim.tick < dodge_until:
		cmd.m = dodge_dir
		return cmd
	var depth := sim.depth_at(me.x, me.y)
	if depth >= 2 or (depth == 1 and sim.type_of(me) == "land"):
		var best := -1
		var best_h := -1
		for k in 8:
			var ang := k * Fx.ANGLES / 8
			var h := sim.height_at(me.x + Fx.cos_a(ang) * 3000 / Fx.ONE, me.y + Fx.sin_a(ang) * 3000 / Fx.ONE)
			if h > best_h:
				best_h = h
				best = ang
		cmd.m = best
		return cmd
	var to := Fx.atan2_a(t.y - me.y, t.x - me.x)
	if d < reach * 50 / 100:
		cmd.m = posmod(to + Fx.ANGLES / 2, Fx.ANGLES)
	elif d > reach * 90 / 100:
		cmd.m = to
	else:
		if sim.tick >= flip_at:
			flip_at = sim.tick + 60
			circle = 1 if noise(sim, me, 3, 2) == 0 else -1
		cmd.m = posmod(to + Fx.QUARTER * circle, Fx.ANGLES)
	return cmd


func _sidestep(sim: MatchSim, me: MatchSim.Ent, th: Dictionary) -> void:
	var left := Fx.atan2_a(th.dy, th.dx) + Fx.QUARTER
	var cross: int = (me.x - th.x) * -th.dy + (me.y - th.y) * th.dx
	var side := left if cross > 0 or (cross == 0 and me.id % 2 == 0) else left + Fx.ANGLES / 2
	if th.get("radial", false):
		side = Fx.atan2_a(me.y - th.y, me.x - th.x)
	if sim.depth_at(me.x + Fx.cos_a(side) * 2000 / Fx.ONE, me.y + Fx.sin_a(side) * 2000 / Fx.ONE) >= 2:
		side += Fx.ANGLES / 2
	dodge_dir = posmod(side, Fx.ANGLES)
	dodge_until = sim.tick + 8


func _nearest(sim: MatchSim, me: MatchSim.Ent) -> MatchSim.Ent:
	var best: MatchSim.Ent = null
	var bd := 1 << 40
	for e in sim.ents:
		if e.alive and e.id != me.id and sim._foe(me, e):
			var d := MatchSim._d2(e.x - me.x, e.y - me.y)
			if d < bd:
				bd = d
				best = e
	return best


## Test player: heads for the middle of the island, attacks the nearest animal, uses the special now and then.
static func cmd(sim: MatchSim, me: MatchSim.Ent) -> Dictionary:
	var target: MatchSim.Ent = null
	var best := 1 << 40
	for e in sim.ents:
		if e.alive and e.id != me.id:
			var d: int = (e.x - me.x) * (e.x - me.x) + (e.y - me.y) * (e.y - me.y)
			if d < best:
				best = d
				target = e
	var cx := sim.width * MatchSim.TILE / 2
	var cy := sim.height * MatchSim.TILE / 2
	var cmd := {"m": Fx.atan2_a(cy - me.y, cx - me.x) if absi(cx - me.x) + absi(cy - me.y) > 3000 else (sim.tick * 7) % Fx.ANGLES, "a": -1, "s": -1}
	if target != null:
		var aim := Fx.atan2_a(target.y - me.y, target.x - me.x)
		cmd.a = aim
		if sim.tick % 240 == 0:
			cmd.s = aim
			cmd["sd"] = Fx.dist(target.x - me.x, target.y - me.y)
	return cmd
