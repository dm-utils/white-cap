class_name BotBrain
extends RefCounted
## Layered utility AI (docs/design.md 3.5). Runs inside the sim tick with the sim's RNG and keeps all memory on the
## entity, so bots are part of the deterministic state: same seed -> same match.
## Layers: reflex (dodge, every tick), plan (target, goal spot, special; on think ticks), move and fire (every tick).
## Animal differences come from data/bots.json styles; difficulty from the levels.

const DODGE_TICKS := 8
const DODGE_STEP := 2000 # sidestep must not end in deep water this far out
const THREAT_TICKS := 12 # look-ahead of the threat scan
const THREAT_MARGIN := 150
const MAX_THREAT_PROJS := 24 # cost cap per scan

static var _levels: Dictionary = {}
static var _styles: Dictionary = {}
static var _default_style: Dictionary = {}


static func _load() -> void:
	if not _levels.is_empty():
		return
	var d: Dictionary = Content.load_json("res://data/bots.json")
	_levels = d.levels
	_styles = d.styles
	_default_style = d.default_style


static func level_config(name: String) -> Dictionary:
	_load()
	return _levels.get(name, _levels.easy)


## Bot damage multipliers as (against bots, against humans), level value scaled per animal by the style
## (docs/design.md 3.9). Strandbal uses the ball_* keys when present.
static func damage_pcts(cfg: Dictionary, animal: String, mode: String) -> Vector2i:
	_load()
	var style: Dictionary = _styles.get(animal, _default_style)
	var vs_bot := int(cfg.damage_pct)
	var vs_human := int(cfg.get("human_damage_pct", vs_bot))
	if mode == "ball":
		vs_bot = int(cfg.get("ball_damage_pct", vs_bot))
		vs_human = int(cfg.get("ball_human_damage_pct", vs_human))
	return Vector2i(vs_bot * int(style.get("damage_pct", 100)) / 100, vs_human * int(style.get("human_damage_pct", 100)) / 100)


static func style_of(sim: MatchSim, e: MatchSim.Ent) -> Dictionary:
	_load()
	return _styles.get(str(sim.animals[e.id].id), _default_style)


static func think(sim: MatchSim, e: MatchSim.Ent, cfg: Dictionary) -> Dictionary:
	if sim.mode == "ball":
		return BallBrain.think(sim, e, cfg)
	var cmd := {"m": -1, "a": -1, "s": -1}
	var style := style_of(sim, e)
	reflex(sim, e, cfg)
	if sim.tick >= e.next_think:
		_plan(sim, e, cfg, style, cmd)
	_move(sim, e, style, cmd)
	_fire(sim, e, cfg, cmd)
	return cmd


# --- layer 1: reflex ---

## Every `reaction_ticks`: look for threats and maybe start a sidestep (e.dodge_until / e.dodge_dir).
static func reflex(sim: MatchSim, e: MatchSim.Ent, cfg: Dictionary) -> void:
	if sim.tick < e.reflex_at:
		return
	e.reflex_at = sim.tick + int(cfg.reaction_ticks)
	if sim.tick < e.dodge_until:
		return
	var th := incoming_threat(sim, e)
	if th.is_empty() or sim.rng.range_i(100) >= int(cfg.dodge_pct):
		return
	# th.dx/dy: direction the threat travels (or points away from its centre for blasts); step to the side e is on
	var left := Fx.atan2_a(th.dy, th.dx) + Fx.QUARTER
	var cross: int = (e.x - th.x) * -th.dy + (e.y - th.y) * th.dx
	var side := left if cross > 0 or (cross == 0 and e.id % 2 == 0) else left + Fx.ANGLES / 2
	if th.get("radial", false):
		side = Fx.atan2_a(e.y - th.y, e.x - th.x)
	var px: int = e.x + Fx.cos_a(side) * DODGE_STEP / Fx.ONE
	var py: int = e.y + Fx.sin_a(side) * DODGE_STEP / Fx.ONE
	if sim.depth_at(px, py) >= 2:
		side += Fx.ANGLES / 2
	e.dodge_dir = posmod(side, Fx.ANGLES)
	e.dodge_until = sim.tick + DODGE_TICKS


## First threat found, as {x, y, dx, dy[, radial]} (a point on its line and its direction), or {} for none.
## Projectiles, dive blasts about to land, dashes heading at e.
static func incoming_threat(sim: MatchSim, e: MatchSim.Ent) -> Dictionary:
	var seen := 0
	for p in sim.projs:
		if p.owner == e.id or not sim._foe(sim.ents[p.owner], e):
			continue
		seen += 1
		if seen > MAX_THREAT_PROJS:
			break
		var v2: int = p.dx * p.dx + p.dy * p.dy
		if v2 == 0:
			continue
		var hit: int = e.radius + p.radius + THREAT_MARGIN
		var leg := mini(THREAT_TICKS, p.life)
		if p.back > 0:
			leg = mini(leg, p.back) # first leg of a boomerang
		if _passes(p.x, p.y, p.dx, p.dy, leg, e, hit):
			return {"x": p.x, "y": p.y, "dx": p.dx, "dy": p.dy}
		if p.back > 0 and p.back <= THREAT_TICKS and p.life > p.back:
			# return leg: starts at the turning point, flies the other way
			var tx: int = p.x + p.dx * p.back
			var ty: int = p.y + p.dy * p.back
			if _passes(tx, ty, -p.dx, -p.dy, mini(THREAT_TICKS - p.back, p.life - p.back), e, hit):
				return {"x": tx, "y": ty, "dx": -p.dx, "dy": -p.dy}
	for v in sim.dives:
		if v.owner != e.id and sim._foe(sim.ents[v.owner], e) and v.delay <= 10:
			var hit: int = v.radius + e.radius
			if MatchSim._d2(e.x - v.x, e.y - v.y) <= hit * hit:
				return {"x": v.x, "y": v.y, "dx": 0, "dy": 0, "radial": true}
	for tp in sim.traps:
		if tp.owner == e.id or not sim._foe(sim.ents[tp.owner], e):
			continue
		var d := Fx.dist(e.x - tp.x, e.y - tp.y)
		if (tp.arm == 0 and d <= tp.trigger + e.radius + 1000) or (tp.fuse <= 10 and d <= tp.radius + e.radius):
			return {"x": tp.x, "y": tp.y, "dx": 0, "dy": 0, "radial": true}
	for o in sim.ents:
		if o.alive and o.dash > 0 and o.id != e.id and sim._foe(o, e) and _dash_hurts(sim, o):
			var v2: int = o.dash_dx * o.dash_dx + o.dash_dy * o.dash_dy
			if v2 == 0:
				continue
			var rx: int = e.x - o.x
			var ry: int = e.y - o.y
			var t := clampi((rx * o.dash_dx + ry * o.dash_dy) / v2, 0, o.dash)
			var hit: int = e.radius + o.radius
			if MatchSim._d2(rx - o.dash_dx * t, ry - o.dash_dy * t) <= hit * hit:
				return {"x": o.x, "y": o.y, "dx": o.dash_dx, "dy": o.dash_dy}
	return {}


## Closest approach of a straight path (start, step per tick, `ticks` long) to e is within `hit`.
static func _passes(px: int, py: int, dx: int, dy: int, ticks: int, e: MatchSim.Ent, hit: int) -> bool:
	var v2: int = dx * dx + dy * dy
	if v2 == 0 or ticks <= 0:
		return false
	var rx: int = e.x - px
	var ry: int = e.y - py
	var t := clampi((rx * dx + ry * dy) / v2, 0, ticks)
	return MatchSim._d2(rx - dx * t, ry - dy * t) <= hit * hit


## A dash that harms (the otter's slide does not).
static func _dash_hurts(sim: MatchSim, o: MatchSim.Ent) -> bool:
	var sp: Dictionary = sim.animals[o.id].special
	return int(sp.get("damage", 0)) > 0 or int(sp.get("push", 0)) > 0


## Where to aim at `t` so a shot of `speed` per tick meets it; lead_pct 0 = at its position, 100 = full lead.
static func lead_point(sim: MatchSim, e: MatchSim.Ent, t: MatchSim.Ent, speed: int, lead_pct: int) -> Vector2i:
	var flight := Fx.dist(t.x - e.x, t.y - e.y) / maxi(1, speed)
	return Vector2i(
		clampi(t.x + t.vx * flight * lead_pct / 100, 0, sim.width * MatchSim.TILE - 1),
		clampi(t.y + t.vy * flight * lead_pct / 100, 0, sim.height * MatchSim.TILE - 1))


## Tide level that counts for safety: the next one when it is about to rise (hard bots look further ahead).
static func safe_level(sim: MatchSim, cfg: Dictionary) -> int:
	var tide: Dictionary = sim.rules.tide
	if sim.level < int(tide.max_level) and sim.phase_left <= int(tide.warn_ticks) + int(cfg.tide_lookahead_ticks):
		return sim.level + 1
	return sim.level


# --- layer 2: plan ---

static func _plan(sim: MatchSim, e: MatchSim.Ent, cfg: Dictionary, style: Dictionary, cmd: Dictionary) -> void:
	var rules := sim.rules
	var tick := sim.tick
	e.next_think = tick + int(cfg.think_ticks) + sim.rng.range_i(4)
	var lv := safe_level(sim, cfg)
	var span := maxi(1, int(rules.tide.max_level) - int(rules.tide.start_level))
	var urgency := sim.level - int(rules.tide.start_level)
	var water := sim.type_of(e) == "water"
	var danger := lv - sim.height_at(e.x, e.y)
	var hp_pct := e.hp * 100 / e.max_hp
	var atk_range := sim.attack_range(e)
	var done := false

	# 1 tide: leave water that is deep (or about to be); land animals also leave shallows when dry ground is near
	if danger >= 2 or (not water and danger == 1):
		var s := _safety_spot(sim, e, cfg, lv, span, urgency, water)
		if danger >= 2 or s.danger <= 0:
			e.goal_x = s.x
			e.goal_y = s.y
			e.engaged = 0
			done = true
	if not done:
		# 2 target
		var t: MatchSim.Ent = sim.ents[e.target] if e.target >= 0 else null
		if t == null or not t.alive or tick >= e.target_until:
			_pick_target(sim, e, cfg)
			e.target_until = tick + 60 + sim.rng.range_i(60)
			t = sim.ents[e.target] if e.target >= 0 else null
		var dist := Fx.dist(t.x - e.x, t.y - e.y) if t != null else 0
		if t != null and hp_pct < int(style.flee_hp_pct) and dist > atk_range * 40 / 100:
			# 3 hurt: away from trouble, towards snacks
			var s := _safety_spot(sim, e, cfg, lv, span, urgency, water)
			e.goal_x = s.x
			e.goal_y = s.y
			e.engaged = 0
		else:
			# 4 engage or reposition
			e.engaged = 1 if t != null and sim.rng.range_i(100) < mini(100, int(cfg.aggression_pct) + 10 * urgency / span) else 0
			if e.engaged == 1:
				var f := _fight_spot(sim, e, cfg, style, t, lv, water)
				e.goal_x = f.x
				e.goal_y = f.y
			else:
				var s := _safety_spot(sim, e, cfg, lv, span, urgency, water)
				e.goal_x = s.x
				e.goal_y = s.y
		if tick >= e.strafe_until:
			e.strafe = 1 if sim.rng.range_i(2) == 0 else -1
			e.strafe_until = tick + 30 + sim.rng.range_i(45)
	# 5 special
	if e.special >= int(rules.attack.special_hits) and tick >= int(rules.calm_start_ticks) and sim.rng.range_i(100) < int(cfg.special_pct):
		_use_special(sim, e, cfg, lv, cmd)


## Committed target: near, weak, revenge, in range; spread over the bots; nothing depends on who is human.
static func _pick_target(sim: MatchSim, e: MatchSim.Ent, cfg: Dictionary) -> void:
	var atk_range := sim.attack_range(e)
	var best := -(1 << 40)
	e.target = -1
	for o in sim.ents:
		if not o.alive or o.id == e.id or not sim._foe(e, o):
			continue
		var d := Fx.dist(o.x - e.x, o.y - e.y)
		var score: int = -d / 10 + (100 - o.hp * 100 / o.max_hp) * 2
		if e.last_hit_by == o.id and sim.tick - e.last_hit_tick < 90:
			score += 200
		if d <= atk_range:
			score += 100
		var on := 0
		for b in sim.ents:
			if b.alive and b.is_bot == 1 and b.id != e.id and b.target == o.id:
				on += 1
		if on >= int(cfg.max_on_target):
			score -= 300
		score += sim.rng.range_i(60)
		if score > best:
			best = score
			e.target = o.id


## Spot at the preferred range from the target, turned round it by the strafe side; samples around it.
static func _fight_spot(sim: MatchSim, e: MatchSim.Ent, cfg: Dictionary, style: Dictionary, t: MatchSim.Ent, lv: int, water: bool) -> Vector2i:
	var away := Fx.atan2_a(e.y - t.y, e.x - t.x) + e.strafe * 300
	var ideal := sim.attack_range(e) * int(style.range_pct) / 100
	var ix := clampi(t.x + Fx.cos_a(away) * ideal / Fx.ONE, 500, sim.width * MatchSim.TILE - 500)
	var iy := clampi(t.y + Fx.sin_a(away) * ideal / Fx.ONE, 500, sim.height * MatchSim.TILE - 500)
	var best := Vector2i(ix, iy)
	var best_score := -(1 << 40)
	for k in int(cfg.samples):
		var px := ix
		var py := iy
		if k > 0:
			var ang := sim.rng.range_i(Fx.ANGLES)
			var r := sim.rng.range_i(2 * MatchSim.TILE)
			px = clampi(ix + Fx.cos_a(ang) * r / Fx.ONE, 500, sim.width * MatchSim.TILE - 500)
			py = clampi(iy + Fx.sin_a(ang) * r / Fx.ONE, 500, sim.height * MatchSim.TILE - 500)
		var danger := lv - sim.height_at(px, py)
		var score := -danger * 120 - Fx.dist(px - ix, py - iy) / 50
		if danger >= 2:
			score -= 400
		if water and danger == 1:
			score += 80
		if score > best_score:
			best_score = score
			best = Vector2i(px, py)
	return best


## Safe spot as before (high ground, snacks when hurt, towards the centre as the tide rises), but judged on the
## coming tide level, without pushing away from other animals; only hurt bots keep clear of foes.
static func _safety_spot(sim: MatchSim, e: MatchSim.Ent, cfg: Dictionary, lv: int, span: int, urgency: int, water: bool) -> Dictionary:
	var cx := sim.width * MatchSim.TILE / 2
	var cy := sim.height * MatchSim.TILE / 2
	var hurt := e.hp * 2 < e.max_hp
	var look := int(cfg.look_tiles) * MatchSim.TILE
	var best_score := -(1 << 40)
	var best := {"x": e.x, "y": e.y, "danger": lv - sim.height_at(e.x, e.y)}
	for k in int(cfg.samples):
		var px := e.x
		var py := e.y
		var r := 0
		if k > 0:
			var ang := sim.rng.range_i(Fx.ANGLES)
			r = MatchSim.TILE + sim.rng.range_i(look)
			px = clampi(e.x + Fx.cos_a(ang) * r / Fx.ONE, 500, sim.width * MatchSim.TILE - 500)
			py = clampi(e.y + Fx.sin_a(ang) * r / Fx.ONE, 500, sim.height * MatchSim.TILE - 500)
		var danger := lv - sim.height_at(px, py)
		var score := -danger * 120 - r / 100
		if k == 0:
			score -= 40 # keep moving
		if danger >= 2:
			score -= 400
		if water and danger == 1:
			score += 80
		if hurt:
			for s in sim.snacks:
				if MatchSim._d2(s[0] - px, s[1] - py) < 2000 * 2000:
					score += 150
			for o in sim.ents:
				if o.alive and o.id != e.id:
					var od := Fx.dist(o.x - px, o.y - py)
					if od < 4000:
						score -= (4000 - od) / 40
		score -= Fx.dist(px - cx, py - cy) / 100 * urgency / span
		if score > best_score:
			best_score = score
			best = {"x": px, "y": py, "danger": danger}
	return best


# --- special use (3.6) ---

static func _use_special(sim: MatchSim, e: MatchSim.Ent, cfg: Dictionary, lv: int, cmd: Dictionary) -> void:
	var sp: Dictionary = sim.animals[e.id].special
	var t: MatchSim.Ent = sim.ents[e.target] if e.target >= 0 else null
	if t != null and not t.alive:
		t = null
	match str(sp.kind):
		"dash":
			var reach := int(sp.ticks) * int(sp.speed) * 85 / 100
			var in_deep := lv - sim.height_at(e.x, e.y) >= 2
			if _dash_escape(sim, e, cfg, lv, reach, cmd):
				return
			if t != null:
				var d := Fx.dist(t.x - e.x, t.y - e.y)
				if d <= reach and d > 1000:
					var p := lead_point(sim, e, t, int(sp.speed), 100)
					var ang := Fx.atan2_a(p.y - e.y, p.x - e.x)
					var ex: int = e.x + Fx.cos_a(ang) * int(sp.ticks) * int(sp.speed) / Fx.ONE
					var ey: int = e.y + Fx.sin_a(ang) * int(sp.ticks) * int(sp.speed) / Fx.ONE
					if in_deep or lv - sim.height_at(ex, ey) < 2:
						cmd.s = ang
						cmd["sd"] = d
		"belly":
			if t == null:
				return
			var reach := int(sp.ticks) * int(sp.speed) * 85 / 100
			var d := Fx.dist(t.x - e.x, t.y - e.y)
			if d > reach or d <= 1000:
				return
			var p := lead_point(sim, e, t, int(sp.speed), 100)
			var ang := Fx.atan2_a(p.y - e.y, p.x - e.x)
			var sunk := sim.depth_at(t.x + Fx.cos_a(ang) * int(sp.push) / Fx.ONE, t.y + Fx.sin_a(ang) * int(sp.push) / Fx.ONE) >= 2
			if sunk or sim.rng.range_i(2) == 0:
				cmd.s = ang
				cmd["sd"] = d
		"slide":
			var reach := int(sp.ticks) * int(sp.speed) * 85 / 100
			var foe := _nearest_foe(sim, e)
			var hurt := e.hp * 100 / e.max_hp < int(style_of(sim, e).flee_hp_pct)
			if _dash_escape(sim, e, cfg, lv, reach, cmd):
				return
			var ang := -1
			if hurt and foe != null and Fx.dist(foe.x - e.x, foe.y - e.y) <= 5000:
				# away from the foe, towards the safest sample when that lies roughly the same way
				var away := Fx.atan2_a(e.y - foe.y, e.x - foe.x)
				var span := maxi(1, int(sim.rules.tide.max_level) - int(sim.rules.tide.start_level))
				var s := _safety_spot(sim, e, cfg, lv, span, sim.level - int(sim.rules.tide.start_level), sim.type_of(e) == "water")
				var to_s := Fx.atan2_a(s.y - e.y, s.x - e.x)
				ang = to_s if absi(Fx.angle_diff(to_s, away)) < Fx.QUARTER else away
			elif e.charges == 0 and t != null and Fx.dist(t.x - e.x, t.y - e.y) <= sim.attack_range(e):
				ang = posmod(Fx.atan2_a(t.y - e.y, t.x - e.x) + Fx.QUARTER * e.strafe, Fx.ANGLES) # sidestep that refills
			if ang >= 0:
				var ex: int = e.x + Fx.cos_a(ang) * int(sp.ticks) * int(sp.speed) / Fx.ONE
				var ey: int = e.y + Fx.sin_a(ang) * int(sp.ticks) * int(sp.speed) / Fx.ONE
				if lv - sim.height_at(ex, ey) < 2:
					cmd.s = ang
					cmd["sd"] = reach
		"puff":
			var near := 0
			var close := false
			var reach := int(sim.animals[e.id].radius) * int(sp.grow_pct) / 100 + 800
			var nearest: MatchSim.Ent = null
			var nd := 1 << 40
			for o in sim.ents:
				if o.alive and o.id != e.id and sim._foe(e, o):
					var d := Fx.dist(o.x - e.x, o.y - e.y)
					if d <= reach:
						close = true
					if d <= 3000:
						near += 1
					if d < nd:
						nd = d
						nearest = o
			var threat := e.hp * 2 < e.max_hp and not incoming_threat(sim, e).is_empty()
			if close or near >= 2 or threat:
				cmd.s = Fx.atan2_a(nearest.y - e.y, nearest.x - e.x) if nearest != null else 0
		"shell":
			var hp := e.hp * 100 / e.max_hp
			var go := hp < 60 and not incoming_threat(sim, e).is_empty()
			for o in sim.ents:
				if go or not o.alive or o.id == e.id or not sim._foe(e, o):
					continue
				var d := Fx.dist(o.x - e.x, o.y - e.y)
				if d > 3000:
					continue
				if hp < 35 or (o.dash > 0 and _dash_hurts(sim, o) and o.dash_dx * (e.x - o.x) + o.dash_dy * (e.y - o.y) > 0):
					go = true
			if go:
				cmd.s = 0
		"arm":
			var foe := _nearest_foe(sim, e)
			if foe == null:
				return
			var d := Fx.dist(foe.x - e.x, foe.y - e.y)
			var closing: bool = d <= 3000 and foe.vx * (e.x - foe.x) + foe.vy * (e.y - foe.y) > 0
			var on_snack := false
			for sn in sim.snacks:
				if MatchSim._d2(sn[0] - e.x, sn[1] - e.y) <= 1500 * 1500:
					on_snack = true
			if closing or (on_snack and d <= 6000):
				cmd.s = Fx.atan2_a(e.y - foe.y, e.x - foe.x)
		"ink":
			var near_foe: MatchSim.Ent = null
			var nd := 1 << 40
			for o in sim.ents:
				if o.alive and o.id != e.id and sim._foe(e, o):
					var d := Fx.dist(o.x - e.x, o.y - e.y)
					if d < nd:
						nd = d
						near_foe = o
			var hurt := e.hp * 100 / e.max_hp < int(BotBrain.style_of(sim, e).flee_hp_pct)
			var reach := int(sp.offset) + int(sp.radius)
			if t != null and Fx.dist(t.x - e.x, t.y - e.y) <= reach:
				cmd.s = Fx.atan2_a(t.y - e.y, t.x - e.x)
			elif hurt and near_foe != null and nd <= 4000:
				cmd.s = Fx.atan2_a(near_foe.y - e.y, near_foe.x - e.x)
		"dive":
			var best_n := 0
			var best_p := Vector2i.ZERO
			var delay := int(sp.delay)
			var cover := int(sp.radius) - 250
			for c in sim.ents:
				if not c.alive or c.id == e.id or not sim._foe(e, c):
					continue
				var p := Vector2i(c.x + c.vx * delay, c.y + c.vy * delay)
				if Fx.dist(p.x - e.x, p.y - e.y) > int(sp.range):
					continue
				var n := 0
				for o in sim.ents:
					if o.alive and o.id != e.id and sim._foe(e, o):
						if Fx.dist(o.x + o.vx * delay - p.x, o.y + o.vy * delay - p.y) <= cover:
							n += 1
				if n > best_n or (n == best_n and n > 0 and t != null and c.id == t.id):
					best_n = n
					best_p = p
			if best_n > 0:
				cmd.s = Fx.atan2_a(best_p.y - e.y, best_p.x - e.x)
				cmd["sd"] = Fx.dist(best_p.x - e.x, best_p.y - e.y)


## Escape from deep water by a dash to a dry sample within reach; true when the command was set.
static func _dash_escape(sim: MatchSim, e: MatchSim.Ent, cfg: Dictionary, lv: int, reach: int, cmd: Dictionary) -> bool:
	if lv - sim.height_at(e.x, e.y) < 2:
		return false
	var span := maxi(1, int(sim.rules.tide.max_level) - int(sim.rules.tide.start_level))
	var s := _safety_spot(sim, e, cfg, lv, span, sim.level - int(sim.rules.tide.start_level), sim.type_of(e) == "water")
	var d := Fx.dist(s.x - e.x, s.y - e.y)
	if s.danger <= 0 and d > 1000 and d <= reach:
		cmd.s = Fx.atan2_a(s.y - e.y, s.x - e.x)
		cmd["sd"] = d
		return true
	return false


static func _nearest_foe(sim: MatchSim, e: MatchSim.Ent) -> MatchSim.Ent:
	var best: MatchSim.Ent = null
	var bd := 1 << 40
	for o in sim.ents:
		if o.alive and o.id != e.id and sim._foe(e, o):
			var d := Fx.dist(o.x - e.x, o.y - e.y)
			if d < bd:
				bd = d
				best = o
	return best


# --- layer 3: move ---

static func _move(sim: MatchSim, e: MatchSim.Ent, style: Dictionary, cmd: Dictionary) -> void:
	if sim.tick < e.dodge_until:
		cmd.m = e.dodge_dir
		return
	var vx := 0
	var vy := 0
	var gx := e.goal_x - e.x
	var gy := e.goal_y - e.y
	var gd := Fx.dist(gx, gy)
	if gd > 300:
		vx = gx * Fx.ONE / gd
		vy = gy * Fx.ONE / gd
	var t: MatchSim.Ent = sim.ents[e.target] if e.target >= 0 else null
	if e.engaged == 1 and t != null and t.alive:
		var d := Fx.dist(t.x - e.x, t.y - e.y)
		var to := Fx.atan2_a(t.y - e.y, t.x - e.x)
		var atk_range := sim.attack_range(e)
		var ideal := atk_range * int(style.range_pct) / 100
		var side := to + Fx.QUARTER * e.strafe
		vx += Fx.cos_a(side) * 6 / 10
		vy += Fx.sin_a(side) * 6 / 10
		if d < atk_range * int(style.min_pct) / 100:
			vx -= Fx.cos_a(to) * 8 / 10
			vy -= Fx.sin_a(to) * 8 / 10
		elif d > ideal * 13 / 10:
			vx += Fx.cos_a(to) * 6 / 10
			vy += Fx.sin_a(to) * 6 / 10
	elif vx == 0 and vy == 0:
		var side := Fx.atan2_a(gy, gx) + Fx.QUARTER * e.strafe
		vx = Fx.cos_a(side) * 4 / 10
		vy = Fx.sin_a(side) * 4 / 10
	if vx == 0 and vy == 0:
		return
	var m := Fx.atan2_a(vy, vx)
	# never step from safe ground into deep water; turn to the side with the lower depth
	if sim.depth_at(e.x, e.y) < 2 and _depth_ahead(sim, e, m) >= 2:
		var a := _depth_ahead(sim, e, m + Fx.QUARTER)
		var b := _depth_ahead(sim, e, m - Fx.QUARTER)
		m += Fx.QUARTER if a <= b else -Fx.QUARTER
	cmd.m = posmod(m, Fx.ANGLES)


static func _depth_ahead(sim: MatchSim, e: MatchSim.Ent, ang: int) -> int:
	return sim.depth_at(e.x + Fx.cos_a(ang) * e.speed * 6 / Fx.ONE, e.y + Fx.sin_a(ang) * e.speed * 6 / Fx.ONE)


# --- layer 4: fire ---

static func _fire(sim: MatchSim, e: MatchSim.Ent, cfg: Dictionary, cmd: Dictionary) -> void:
	var rules := sim.rules
	if sim.tick < int(rules.calm_start_ticks) or e.cooldown > 0 or e.charges <= 0 or sim.tick < e.next_shot:
		return
	var at: Dictionary = sim.animals[e.id].attack
	if e.guard > 0 and int(sim.animals[e.id].special.get("no_attack", 0)) == 1:
		return
	var atk_range := sim.attack_range(e)
	var t: MatchSim.Ent = sim.ents[e.target] if e.target >= 0 else null
	if t != null and not t.alive:
		t = null
	var reserve := int(cfg.keep_charges)
	if t != null:
		var d := Fx.dist(t.x - e.x, t.y - e.y)
		if t.hp * 100 / t.max_hp < 30 or d < atk_range * 40 / 100:
			reserve = 0
	if e.charges <= reserve:
		return
	if int(at.count) * int(at.spread) >= Fx.ANGLES:
		# ring attack: direction does not matter, fire when any foe is in reach
		var foe := _nearest_foe(sim, e)
		if foe != null and Fx.dist(foe.x - e.x, foe.y - e.y) <= atk_range * 95 / 100:
			cmd.a = Fx.atan2_a(foe.y - e.y, foe.x - e.x)
			e.next_shot = sim.tick + int(cfg.fire_gap_ticks) + sim.rng.range_i(int(cfg.fire_gap_ticks) + 1)
		return
	if t == null or Fx.dist(t.x - e.x, t.y - e.y) > atk_range * 95 / 100:
		# target out of range: the nearest foe within 60 % of range will do
		var near_foe: MatchSim.Ent = null
		var nd := atk_range * 60 / 100
		for o in sim.ents:
			if o.alive and o.id != e.id and sim._foe(e, o):
				var d := Fx.dist(o.x - e.x, o.y - e.y)
				if d <= nd:
					nd = d
					near_foe = o
		t = near_foe
	if t == null:
		return
	var p := lead_point(sim, e, t, int(at.speed), int(cfg.lead_pct))
	if Fx.dist(p.x - e.x, p.y - e.y) <= atk_range * 95 / 100:
		var err := int(cfg.aim_error)
		cmd.a = posmod(Fx.atan2_a(p.y - e.y, p.x - e.x) + sim.rng.between(-err, err), Fx.ANGLES)
		e.next_shot = sim.tick + int(cfg.fire_gap_ticks) + sim.rng.range_i(int(cfg.fire_gap_ticks) + 1)
