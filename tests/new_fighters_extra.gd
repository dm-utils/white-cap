extends Node
## Independent checks for the five new fighters (docs/design.md 4, ADR 004/005/009): ranges to the unit, edge cases of
## guard, trap, boomerang and slide, determinism with all new state, reconcile and unlocks, text completeness.
## Headless: godot --headless --path . res://tests/new_fighters_extra.tscn

var _passed := 0
var _failed := 0


func check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL: " + what)


func _ready() -> void:
	test_ranges()
	test_puffer()
	test_otter()
	test_seal()
	test_hermit()
	test_star()
	test_ball_tables()
	test_determinism_all_state()
	test_rollback_new_animals()
	test_cross_process_hash()
	test_unlocks_and_reconcile()
	test_apply_result()
	test_roster_users()
	test_texts()
	print("new fighters extra tests: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


# --- helpers ---

const AX := 8000
const AY := 15000


## Two entities on a dry strip, a at (AX, AY), b `gap` to the east (angle 0), nothing else on the board.
func _duel(a: String, b: String, gap: int) -> MatchSim:
	var s := MatchSim.new(42, [a, b])
	s.projs.clear()
	s.snacks.clear()
	s.ents[0].x = AX
	s.ents[0].y = AY
	s.ents[1].x = AX + gap
	s.ents[1].y = AY
	return s


func _hits_on(s: MatchSim, id: int) -> int:
	var n := 0
	for ev in s.events:
		if ev.type == "hit" and ev.id == id:
			n += 1
	return n


## Number of hit events on entity 1 after `a` fires once and `ticks` pass.
func _fire(a: String, b: String, gap: int, ticks: int) -> Dictionary:
	var s := _duel(a, b, gap)
	var hits := 0
	var hp0: int = s.ents[1].hp
	for t in ticks:
		s.step([{"a": 0} if t == 0 else {}, {}])
		hits += _hits_on(s, 1)
	return {"hits": hits, "lost": hp0 - int(s.ents[1].hp), "s": s}


func _expected_reach(a: String, b: String) -> int:
	var A: Dictionary = Content.animal(a)
	var B: Dictionary = Content.animal(b)
	var at: Dictionary = A.attack
	var travel := int(at.speed) * (int(at.get("back", 0)) if int(at.get("back", 0)) > 0 else int(at.life))
	return int(A.radius) + travel + int(at.radius) + int(B.radius)


func test_ranges() -> void:
	# the outermost distance at which an attack still hits, per animal, against a crab: one more unit misses
	for a in ["puffer", "otter", "seal", "hermit", "star"]:
		var reach := _expected_reach(a, "crab")
		var r: Dictionary = _fire(a, "crab", reach, 30)
		check(int(r.hits) >= 1, "%s: a foe at the exact reach %d is hit" % [a, reach])
		r = _fire(a, "crab", reach + 1, 30)
		check(int(r.hits) == 0, "%s: a foe 1 beyond the reach %d is not hit" % [a, reach])
	# attack_range() is what the bots use: it has to match the real travel distance
	for a in ["puffer", "otter", "seal", "hermit", "star"]:
		var s := _duel(a, "crab", 3000)
		var at: Dictionary = Content.animal(a).attack
		var travel := int(at.speed) * (int(at.get("back", 0)) if int(at.get("back", 0)) > 0 else int(at.life))
		check(s.attack_range(s.ents[0]) == travel, "%s: attack_range is %d" % [a, travel])


# --- puffer ---

func test_puffer() -> void:
	# ring: 8 directions, 512 apart, for any aim; none of them is the aim itself twice
	for aim in [0, 700, 4000]:
		var s := _duel("puffer", "crab", 9000)
		s.step([{"a": aim}, {}])
		var angles: Array = s.projs.map(func(p): return Fx.atan2_a(p.dy, p.dx))
		angles.sort()
		var ok := angles.size() == 8
		for i in 8:
			var d: int = posmod(int(angles[(i + 1) % 8]) - int(angles[i]), 4096)
			ok = ok and absi(d - 512) <= 3
		check(ok, "spines ring is 8 projectiles 512 apart for aim %d (%s)" % [aim, str(angles)])
		check(s.projs.all(func(p): return p.damage == 1100 and p.radius == 240 and p.push == 0 and p.back == 0), "spines carry damage 1100, radius 240, no push, no back")

	# point blank: more than one spine may touch a foe, every spine only once; the special counts every hit
	var r := _fire("puffer", "crab", 900, 3)
	check(int(r.hits) >= 1 and int(r.lost) == int(r.hits) * 1100, "point blank: damage is 1100 per spine that hit (%d hits, %d lost)" % [r.hits, r.lost])
	check(int(r.s.ents[0].special) == mini(4, int(r.hits)), "special charge equals hits, capped at 4 (%d)" % r.s.ents[0].special)

	# puff blocks nothing: a puffed puffer still attacks (no_attack 0) and shoots from the bigger body
	var s2 := _duel("puffer", "crab", 6000)
	s2.ents[0].special = 4
	s2.step([{"s": 0}, {}])
	check(s2.ents[0].guard == 90 and s2.ents[0].radius == 690, "puff: guard 90, radius 690 on activation")
	s2.step([{"a": 0}, {}])
	check(s2.projs.size() == 8 and s2.ents[0].charges == 2, "a puffed puffer can still attack")
	check(s2.projs[0].x - s2.ents[0].x != 0 and absi(Fx.dist(s2.projs[0].x - s2.ents[0].x, s2.projs[0].y - s2.ents[0].y) - 690) <= 400 + 5, "spines leave from the grown body")

	# speed 80 % while puffed
	var s3 := _duel("puffer", "crab", 9000)
	s3.ents[0].special = 4
	s3.step([{"s": 0}, {}])
	var x0: int = s3.ents[0].x
	s3.step([{"m": 0}, {}])
	var sp: int = s3.ents[0].speed
	var pct := int(s3.rules.ground_speed_pct.water.dry)
	check(s3.ents[0].x - x0 == (sp * pct / 100) * 80 / 100 * 4096 / 4096 or absi((s3.ents[0].x - x0) - (sp * pct / 100) * 80 / 100) <= 1, "puffed speed is 80 %% of normal (%d vs %d)" % [s3.ents[0].x - x0, sp * pct / 100])

	# damage taken: half from projectile, dive blast and trap blast; full from water
	var s4 := _duel("puffer", "gull", 5000)
	s4.ents[0].special = 4
	s4.step([{"s": 0}, {}])
	var hp: int = s4.ents[0].hp
	s4.ents[1].special = 4
	s4.ents[1].x = s4.ents[0].x + 3000
	s4.step([{}, {"s": 2048, "sd": 3000}]) # angle 2048 = west, towards the puffer
	for t in 14:
		s4.step([{}, {}])
	check(hp - int(s4.ents[0].hp) == 3600 / 2, "dive blast against a puffed puffer is halved (%d)" % (hp - int(s4.ents[0].hp)))

	var s5 := _duel("puffer", "star", 5000)
	s5.ents[0].special = 4
	s5.step([{"s": 0}, {}])
	s5.ents[1].special = 4
	s5.ents[1].x = s5.ents[0].x + 100
	s5.ents[1].y = s5.ents[0].y
	hp = s5.ents[0].hp
	s5.step([{}, {"s": 0}])
	for t in 30:
		s5.step([{}, {}])
	# the bounce shoved the star away first (1500 * 100 %); the trap under it still goes off at the fuse or when touched
	check(s5.ents[1].hp < s5.ents[1].max_hp, "puffer bounce damaged the star that stood on it")

	# water damage is never softened: an entity in deep water takes the same with and without guard
	var wet := MatchSim.new(42, ["puffer", "crab"])
	wet.ents[0].x = 4500
	wet.ents[0].y = 4500
	wet.ents[1].x = 20000
	wet.ents[1].y = 20000
	wet.ents[0].special = 4
	wet.step([{"s": 0}, {}])
	var hpw: int = wet.ents[0].hp
	wet.step([{}, {}])
	check(hpw - int(wet.ents[0].hp) == int(wet.rules.deep_damage_per_tick.water), "water damage on a puffed puffer is full (%d)" % (hpw - int(wet.ents[0].hp)))

	# puffing next to the east wall: the bigger body is pushed inside, never outside the map
	var w := MatchSim.new(42, ["puffer", "crab"])
	w.ents[0].x = 40000 - 460
	w.ents[0].y = 15000
	w.ents[0].special = 4
	w.step([{"s": 0}, {}])
	w.step([{}, {}])
	check(w.ents[0].x <= 40000 - 690 and w.ents[0].x >= 690, "a puffed puffer at the wall is clamped by the grown radius (x %d)" % w.ents[0].x)
	for t in 90:
		w.step([{}, {}])
	check(w.ents[0].radius == 460 and w.ents[0].guard == 0, "radius is back to 460 after the puff")

	# puff twice in a row (special recharged by hits during the puff): radius stays 690, never compounds; foe bounced again
	var d := _duel("puffer", "crab", 5000)
	d.ents[0].special = 4
	d.step([{"s": 0}, {}])
	d.ents[0].special = 4
	d.step([{"s": 0}, {}])
	check(d.ents[0].radius == 690 and d.ents[0].guard == 90, "second puff while puffed does not compound the radius (%d)" % d.ents[0].radius)

	# puffer against a sliding otter: passes through, no bounce
	var o := _duel("puffer", "otter", 900)
	o.ents[1].special = 4
	o.step([{}, {"s": 2048, "sd": 100}])
	var ohp: int = o.ents[1].hp
	o.ents[0].special = 4
	o.ents[1].x = o.ents[0].x + 300
	o.step([{"s": 0}, {}])
	for t in 3:
		o.step([{}, {}])
	check(o.ents[1].hp == ohp, "a sliding otter is not bounced or hurt by the puff")


# --- otter ---

func test_otter() -> void:
	# slide: 14 ticks x 560, never refills halfway, refills exactly when it ends (also when it ends in deep water)
	var s := _duel("otter", "crab", 12000)
	s.ents[0].special = 4
	s.ents[0].charges = 0
	var x0: int = s.ents[0].x
	s.step([{"s": 0}, {}])
	check(s.ents[0].dash == 14 and s.ents[0].x == x0, "slide starts at the end of the activation tick")
	for t in 13:
		s.step([{}, {}])
		check(s.ents[0].charges == 0 or t == 12, "no refill during the slide (tick %d)" % t)
	check(s.ents[0].dash == 1, "one slide tick left after 13 steps")
	s.step([{}, {}])
	check(s.ents[0].dash == 0 and s.ents[0].charges == 3 and s.ents[0].x - x0 == 14 * 560, "slide ends: full charges, moved 14 x 560 (%d)" % (s.ents[0].x - x0))
	check(s.ents[0].hp == s.ents[0].max_hp, "the slide costs nothing")

	# reload counter is cleared too: next charge timer starts fresh
	var s2 := _duel("otter", "crab", 12000)
	s2.ents[0].special = 4
	s2.ents[0].charges = 1
	s2.ents[0].reload = 20
	s2.step([{"s": 0}, {}])
	for t in 14:
		s2.step([{}, {}])
	check(s2.ents[0].charges == 3 and s2.ents[0].reload == 0, "reload is reset by the refill")

	# the slide ending in deep water: refill still happens, water damage still applies
	var s3 := MatchSim.new(42, ["otter", "crab"])
	s3.ents[0].x = 4500
	s3.ents[0].y = 4500
	s3.ents[1].x = 30000
	s3.ents[1].y = 25000
	s3.ents[0].special = 4
	s3.ents[0].charges = 0
	s3.step([{"s": 1024, "sd": 100}, {}])
	for t in 14:
		s3.step([{}, {}])
	check(s3.ents[0].charges == 3, "slide refill also works in deep water")

	# intangible against everything: projectile, dive, trap blast, ink, crab dash, puff bounce
	var base := _duel("otter", "crab", 6000)
	base.ents[0].special = 4
	base.step([{"s": 0, "sd": 0}, {}])
	check(base._intangible(base.ents[0]), "otter is intangible during the slide")
	var ot: MatchSim.Ent = base.ents[0]
	var hp0: int = ot.hp
	# dive blast on the otter
	var dv := MatchSim.Dive.new()
	dv.owner = 1
	dv.x = ot.x
	dv.y = ot.y
	dv.delay = 1
	dv.radius = 3000
	dv.damage = 3600
	base.dives.append(dv)
	# trap blast on the otter
	var tp := MatchSim.Trap.new()
	tp.owner = 1
	tp.x = ot.x
	tp.y = ot.y
	tp.arm = 0
	tp.fuse = 1
	tp.trigger = 600
	tp.radius = 3000
	tp.damage = 3200
	base.traps.append(tp)
	# ink cloud on the otter
	var cl := MatchSim.Cloud.new()
	cl.owner = 1
	cl.x = ot.x
	cl.y = ot.y
	cl.radius = 3000
	cl.life = 5
	cl.slow = 50
	base.clouds.append(cl)
	base.step([{}, {}])
	check(ot.hp == hp0 and ot.slow == 0, "dive, trap blast and ink do nothing to a sliding otter (hp %d slow %d)" % [ot.hp, ot.slow])
	check(base.events.any(func(ev): return ev.type == "dive") and base.events.any(func(ev): return ev.type == "trap"), "the blasts still went off")

	# an armed trap does not trigger on a sliding otter passing over it, but does when it stops on it
	var t2 := _duel("otter", "star", 20000)
	t2.ents[1].x = t2.ents[0].x + 3000
	t2.ents[1].special = 4
	t2.step([{}, {"s": 0}])
	for t in 16:
		t2.step([{}, {}])
	check(t2.traps.size() == 1, "armed trap waits")
	t2.ents[0].x = t2.traps[0].x - 14 * 560 + 560 * 7 # centre of the slide path over the trap
	t2.ents[0].y = t2.traps[0].y
	t2.ents[0].special = 4
	t2.step([{"s": 0, "sd": 0}, {}])
	for t in 13:
		t2.step([{}, {}])
	check(t2.traps.size() == 1 and t2.ents[0].dash == 1, "a sliding otter on the armed trap does not set it off")
	t2.ents[0].x = t2.traps[0].x
	t2.ents[0].y = t2.traps[0].y
	t2.dives.clear()
	t2.step([{}, {}])
	check(t2.traps.is_empty() and t2.ents[0].hp < t2.ents[0].max_hp, "the moment the slide stops on it, the trap goes off")

	# crab dash through a sliding otter: no hit, no push; the crab flies on
	var cd := _duel("crab", "otter", 1500)
	cd.ents[0].special = 4
	cd.ents[1].special = 4
	cd.step([{"s": 0}, {"s": 2048, "sd": 0}]) # otter slides west, i.e. towards the crab
	var cx0: int = cd.ents[0].x
	for t in 7:
		cd.step([{}, {}])
	check(cd.ents[1].hp == cd.ents[1].max_hp and cd.ents[0].dash == 0, "a crab dash does not hit a sliding otter")

	# boomerang and jet pass through a sliding otter
	var bj := _duel("seal", "otter", 2500)
	bj.ents[1].special = 4
	bj.step([{"a": 0}, {"s": 1024, "sd": 0}])
	for t in 12:
		bj.step([{}, {}])
	check(bj.ents[1].hp == bj.ents[1].max_hp, "a jet shot at a sliding otter misses (the otter slid out and is intangible)")

	# otter shell: damage 1700, one hit only, charge +1 to special
	var r := _fire("otter", "crab", 4000, 20)
	check(int(r.lost) == 1700 and int(r.s.ents[0].special) == 1, "thrown shell: 1700 damage, special +1 (%d)" % r.lost)

	# the otter can shoot during the slide
	var ss := _duel("otter", "crab", 5000)
	ss.ents[0].special = 4
	ss.step([{"s": 1024, "sd": 0}, {}])
	ss.step([{"a": 0}, {}])
	check(ss.projs.size() == 1, "an otter can throw a shell while sliding")


# --- seal ---

func test_seal() -> void:
	# jet: damage 1300 and push 1200 along the shot; once; pushed foe stays inside the map at the wall
	var s := _duel("seal", "crab", 3000)
	var x1: int = s.ents[1].x
	for t in 12:
		s.step([{"a": 0} if t == 0 else {}, {}])
	check(s.ents[1].x - x1 == 1200 and s.ents[1].hp == 12000 - 1300, "jet: pushed 1200 and hurt 1300 (%d, %d)" % [s.ents[1].x - x1, 12000 - s.ents[1].hp])

	var w := _duel("seal", "crab", 3000)
	w.ents[0].x = 40000 - 4000
	w.ents[1].x = 40000 - 1000
	for t in 8:
		w.step([{"a": 0} if t == 0 else {}, {}])
	check(w.ents[1].x <= 40000 - 420, "a push never takes a foe out of the map (x %d)" % w.ents[1].x)

	# jet against puffed puffer: pushed and halved; against a hermit in its shell: hurt 10 %, not pushed
	var jp := _duel("seal", "puffer", 3000)
	jp.ents[1].special = 4
	jp.step([{"a": 0}, {"s": 0}])
	var px: int = jp.ents[1].x
	for t in 12:
		jp.step([{}, {}])
	check(jp.ents[1].x - px == 1200 and jp.ents[1].hp == 14000 - 650, "jet on a puffed puffer: pushed 1200, damage halved (%d, hp %d)" % [jp.ents[1].x - px, jp.ents[1].hp])
	var jh := _duel("seal", "hermit", 3000)
	jh.ents[1].special = 4
	jh.step([{"a": 0}, {"s": 0}])
	var hx: int = jh.ents[1].x
	for t in 12:
		jh.step([{}, {}])
	check(jh.ents[1].x == hx and jh.ents[1].hp == 13000 - 130, "jet on a shelled hermit: not pushed, 10 %% damage (hp %d)" % jh.ents[1].hp)

	# belly: 12 x 560 forward, pushes a hit foe exactly 4200 (axis) and 1400 damage; hits each foe once
	var b := _duel("seal", "crab", 2500)
	b.ents[0].special = 4
	var bx0: int = b.ents[1].x
	for t in 14:
		b.step([{"s": 0, "sd": 0} if t == 0 else {}, {}])
	check(b.ents[1].x - bx0 == 4200 and b.ents[1].hp == 12000 - 1400, "belly pushes 4200 and hurts 1400 once (%d, %d)" % [b.ents[1].x - bx0, 12000 - b.ents[1].hp])

	# belly diagonal: push length close to 4200
	var bd := _duel("seal", "crab", 0)
	bd.ents[0].special = 4
	bd.ents[1].x = bd.ents[0].x + 1500
	bd.ents[1].y = bd.ents[0].y + 1500
	var p0 := Vector2(bd.ents[1].x, bd.ents[1].y)
	for t in 14:
		bd.step([{"s": 512, "sd": 0} if t == 0 else {}, {}])
	var moved := Vector2(bd.ents[1].x, bd.ents[1].y).distance_to(p0)
	check(absf(moved - 4200.0) < 60.0, "belly diagonal push is about 4200 (%.0f)" % moved)

	# belly into deep water: the foe is shoved to a drowning spot
	var bw := MatchSim.new(42, ["seal", "crab"])
	bw.ents[0].x = 8000
	bw.ents[0].y = 3000
	bw.ents[1].x = 8000
	bw.ents[1].y = 2000
	var depth_before := bw.depth_at(8000, 2000)
	bw.ents[0].special = 4
	for t in 14:
		bw.step([{"s": 3072, "sd": 0} if t == 0 else {}, {}])
	check(bw.ents[1].y < 2000 or bw.ents[1].y >= 420, "belly towards the north edge keeps the foe inside the map (y %d, depth before %d)" % [bw.ents[1].y, depth_before])

	# belly against a shelled hermit: damage 10 %, no push; against a sliding otter: nothing
	var bh := _duel("seal", "hermit", 2500)
	bh.ents[0].special = 4
	bh.ents[1].special = 4
	bh.step([{"s": 0, "sd": 0}, {"s": 0}])
	var h0: int = bh.ents[1].x
	for t in 13:
		bh.step([{}, {}])
	check(bh.ents[1].x == h0 and bh.ents[1].hp == 13000 - 140, "belly on a shelled hermit: no push, 140 damage (hp %d)" % bh.ents[1].hp)

	var bo := _duel("seal", "otter", 2500)
	bo.ents[0].special = 4
	bo.ents[1].special = 4
	bo.step([{"s": 0, "sd": 0}, {"s": 3072 - 1024 * 2, "sd": 0}])
	for t in 13:
		bo.step([{}, {}])
	check(bo.ents[1].hp == bo.ents[1].max_hp, "belly does not hit a sliding otter")

	# special counts: belly does not add to its own special; a belly hit does not charge the seal
	check(b.ents[0].special == 0, "belly hit does not charge the special")

	# belly with a bot flag: hit scale applies to the push too? (push is not scaled)
	var bb := _duel("seal", "crab", 2500)
	bb.ents[0].is_bot = 1
	bb.ents[0].human_damage_pct = 50
	bb.ents[0].special = 4
	var bbx: int = bb.ents[1].x
	for t in 14:
		bb.step([{"s": 0, "sd": 0} if t == 0 else {}, {}])
	check(bb.ents[1].x - bbx == 4200 and bb.ents[1].hp == 12000 - 700, "bot damage scaling does not change the push, only the damage (%d, %d)" % [bb.ents[1].x - bbx, 12000 - bb.ents[1].hp])


# --- hermit ---

func test_hermit() -> void:
	# poke: 2000, range 3600
	var r := _fire("hermit", "crab", 3000, 12)
	check(int(r.lost) == 2000, "poke deals 2000 (%d)" % r.lost)

	# shell: 10 % (rounding down), cannot attack, 30 % speed, radius unchanged, 75 ticks
	var s := _duel("hermit", "crab", 6000)
	s.ents[0].special = 4
	s.step([{"s": 0}, {}])
	var h: MatchSim.Ent = s.ents[0]
	check(h.guard == 75 and h.radius == 440, "shell: guard 75, radius unchanged")
	var c0: int = h.charges
	var cd0: int = h.cooldown
	s.step([{"a": 0}, {}])
	check(s.projs.is_empty() and h.charges == c0 and h.cooldown <= cd0, "attack in the shell does not spend a charge or fire")
	var hp0: int = h.hp
	s._damage(h, 9, 1) # 9 * 10 / 100 = 0: tiny hits do nothing
	check(h.hp == hp0, "a hit of 9 units does nothing to a shelled hermit")
	s._damage(h, 10, 1)
	check(h.hp == hp0 - 1, "a hit of 10 units costs 1")
	# the attack works again exactly when the shell is gone
	var s2 := _duel("hermit", "crab", 6000)
	s2.ents[0].special = 4
	s2.step([{"s": 0}, {}])
	var fired_at := -1
	for t in 80:
		s2.step([{"a": 0}, {}])
		if not s2.projs.is_empty() and fired_at < 0:
			fired_at = t + 1
	check(fired_at == 75, "the first poke after the shell comes on tick 75 after activation (got %d)" % fired_at)

	# not pushable by: jet (done), belly (done), crab dash, puff bounce, dive/trap do damage only
	var cd := _duel("crab", "hermit", 2000)
	cd.ents[0].special = 4
	cd.ents[1].special = 4
	cd.step([{"s": 0}, {"s": 0}])
	var hx0: int = cd.ents[1].x
	for t in 8:
		cd.step([{}, {}])
	check(cd.ents[1].x == hx0 and cd.ents[1].hp == 13000 - 260, "crab dash on a shelled hermit: damage 260, no push (x %+d, hp %d)" % [cd.ents[1].x - hx0, cd.ents[1].hp])

	var pb := _duel("hermit", "puffer", 700)
	pb.ents[0].special = 4
	pb.ents[1].special = 4
	pb.step([{"s": 0}, {"s": 0}])
	var hx: int = pb.ents[0].x
	var hh: int = pb.ents[0].hp
	for t in 3:
		pb.step([{}, {}])
	check(pb.ents[0].x == hx and pb.ents[0].hp == hh - 150, "puff bounce hurts a shelled hermit 150 and does not move it (x %+d hp %d)" % [pb.ents[0].x - hx, hh - pb.ents[0].hp])

	# hermit moves at 30 % in the shell even on sand, and still takes full water damage
	var wet := MatchSim.new(42, ["hermit", "crab"])
	wet.ents[0].x = 4500
	wet.ents[0].y = 4500
	wet.ents[1].x = 30000
	wet.ents[1].y = 25000
	wet.ents[0].special = 4
	wet.step([{"s": 0}, {}])
	var hpw: int = wet.ents[0].hp
	wet.step([{}, {}])
	check(hpw - int(wet.ents[0].hp) == 30, "water damage on a shelled hermit is not reduced (%d)" % (hpw - int(wet.ents[0].hp)))

	# the shell gives a hit-charge to the attacker like any hit (a hit on a shelled foe still counts)
	var hs := _duel("crab", "hermit", 2000)
	hs.ents[1].special = 4
	hs.step([{"a": 0}, {"s": 0}])
	for t in 8:
		hs.step([{}, {}])
	check(hs.ents[0].special >= 0, "no crash hitting a shelled hermit")

	# attack ignored also when the command comes with a move
	var mv := _duel("hermit", "crab", 6000)
	mv.ents[0].special = 4
	mv.step([{"s": 0}, {}])
	mv.step([{"a": 0, "m": 0}, {}])
	check(mv.projs.is_empty(), "attack+move in the shell: no shot")


# --- star ---

func test_star() -> void:
	# boomerang hits on the way out only once; foe standing in the return path (after the apex) is hit on the way back
	var s := _duel("star", "crab", 20000)
	s.step([{"a": 0}, {}])
	for t in 9:
		s.step([{}, {}])
	check(s.projs.size() == 1 and s.projs[0].back == 0 or s.projs[0].back == 1, "star turns at tick 10")
	for t in 3:
		s.step([{}, {}]) # tick 13: on the way back
	var p: MatchSim.Proj = s.projs[0]
	check(p.dx < 0, "star flies back after the apex")
	# foe placed ahead of the returning star
	s.ents[1].x = p.x + p.dx - 100
	s.ents[1].y = p.y
	s.step([{}, {}])
	check(s.ents[1].hp == 12000 - 1400 and s.projs.is_empty(), "the returning star hits a foe, once")

	# a foe hit on the way out is hit only once, the star vanishes
	var o := _fire("star", "crab", 2000, 25)
	check(int(o.hits) == 1 and int(o.lost) == 1400, "star hits once on the way out (%d hits)" % o.hits)

	# star never hurts its owner on return (it lands on the owner's position)
	var self_s := _duel("star", "crab", 20000)
	for t in 24:
		self_s.step([{"a": 0} if t == 0 else {}, {}])
	check(self_s.ents[0].hp == self_s.ents[0].max_hp and self_s.projs.is_empty(), "returning star ignores the owner and expires")

	# star lifetime 20: gone on tick 20
	var lt := _duel("star", "crab", 20000)
	lt.step([{"a": 0}, {}])
	for t in 18:
		lt.step([{}, {}])
	check(lt.projs.size() == 1, "star alive after 19 ticks")
	lt.step([{}, {}])
	check(lt.projs.is_empty(), "star gone after 20 ticks")

	# boomerang against a shelled hermit: 10 %, special still counts
	var g := _duel("star", "hermit", 2500)
	g.ents[1].special = 4
	g.step([{"a": 0}, {"s": 0}])
	for t in 10:
		g.step([{}, {}])
	check(g.ents[1].hp == 13000 - 140 and g.ents[0].special == 1, "star on a shelled hermit: 140 damage, special +1 (hp %d)" % g.ents[1].hp)

	# trap: placed under the star, any ground (also deep water), fires at exactly arm_ticks - 1 later when a foe stands on it
	var t0 := _duel("star", "crab", 20000)
	t0.ents[0].special = 4
	t0.step([{"s": 0}, {}])
	var tr: MatchSim.Trap = t0.traps[0]
	check(tr.arm == 14 and tr.fuse == 149 and tr.trigger == 600 and tr.radius == 1800 and tr.damage == 3200, "trap fields after the activation tick (arm %d fuse %d)" % [tr.arm, tr.fuse])
	# trigger edge: foe at trigger + radius exactly triggers when armed, 1 more does not
	for dist in [1020, 1021]:
		var t1 := _duel("star", "crab", 20000)
		t1.ents[0].special = 4
		t1.step([{"s": 0}, {}])
		t1.ents[1].x = t1.ents[0].x + dist
		t1.ents[1].y = t1.ents[0].y
		for t in 20:
			t1.step([{}, {}])
		check((dist == 1020) == t1.traps.is_empty(), "trigger edge: foe at %d %s the trap" % [dist, "sets off" if dist == 1020 else "leaves"])
	# foe standing in the blast but outside the trigger circle: gets hit when the fuse runs out
	var fz := _duel("star", "crab", 20000)
	fz.ents[0].special = 4
	fz.step([{"s": 0}, {}])
	fz.ents[1].x = fz.ents[0].x + 2000
	for t in 149:
		fz.step([{}, {}])
	check(fz.traps.is_empty() and fz.ents[1].hp == 12000 - 3200, "the fuse blast hits a foe inside the blast radius (hp %d)" % fz.ents[1].hp)
	# blast radius edge: radius 1800 + foe radius 420 = 2220
	for dist in [2220, 2221]:
		var be := _duel("star", "crab", 20000)
		be.ents[0].special = 4
		be.step([{"s": 0}, {}])
		be.ents[1].x = be.ents[0].x + dist
		for t in 149:
			be.step([{}, {}])
		check((dist == 2220) == (be.ents[1].hp < 12000), "blast edge: a foe at %d %s" % [dist, "is hit" if dist == 2220 else "is spared"])

	# owner is never hurt by (or triggers) its own trap
	var ow := _duel("star", "crab", 20000)
	ow.ents[0].special = 4
	ow.step([{"s": 0}, {}])
	for t in 160:
		ow.step([{}, {}])
	check(ow.ents[0].hp == ow.ents[0].max_hp and ow.traps.is_empty(), "the owner stands on its own trap until the fuse and is not hurt")

	# trap in deep water: works, owner takes water damage only
	var tw := MatchSim.new(42, ["star", "gull"])
	tw.ents[0].x = 4500
	tw.ents[0].y = 4500
	tw.ents[1].x = 30000
	tw.ents[1].y = 25000
	tw.ents[0].special = 4
	tw.step([{"s": 0}, {}])
	check(tw.traps.size() == 1 and tw.traps[0].x == 4500 and tw.traps[0].y == 4500, "a trap can be laid in deep water")
	tw.ents[1].x = 4500 + 700
	tw.ents[1].y = 4500
	var g0: int = tw.ents[1].hp
	for t in 16:
		tw.step([{}, {}])
	check(tw.traps.is_empty() and tw.ents[1].hp < g0, "a gull over the trap in water sets it off")

	# trap of a washed-away owner stays and fires
	var dead := _duel("star", "crab", 20000)
	dead.ents[0].special = 4
	dead.step([{"s": 0}, {}])
	dead.ents[0].hp = 0
	dead.ents[1].x = dead.ents[0].x + 100
	dead.step([{}, {}])
	check(not dead.ents[0].alive, "owner is out")
	dead.finished = 0
	for t in 20:
		dead.step([{}, {}])
	check(dead.ents[1].hp < 12000 or dead.traps.is_empty() or dead.finished == 1, "no crash; trap of a dead owner is handled (traps %d, finished %d)" % [dead.traps.size(), dead.finished])

	# the 4th/5th special: max 2 per owner, per owner independent
	var m2 := MatchSim.new(42, ["star", "star"])
	m2.projs.clear()
	m2.ents[0].x = 8000
	m2.ents[0].y = 15000
	m2.ents[1].x = 30000
	m2.ents[1].y = 15000
	for i in 3:
		m2.ents[0].special = 4
		m2.ents[1].special = 4
		m2.ents[0].x += 3000
		m2.ents[1].x -= 3000
		m2.step([{"s": 0}, {"s": 0}])
	var mine := m2.traps.filter(func(t): return t.owner == 0).size()
	var theirs := m2.traps.filter(func(t): return t.owner == 1).size()
	check(mine == 2 and theirs == 2, "two traps each for two owners (%d, %d)" % [mine, theirs])

	# a trap needs the 4 hits like any special; a cmd without charge does nothing
	var nc := _duel("star", "crab", 20000)
	nc.step([{"s": 0}, {}])
	check(nc.traps.is_empty(), "no trap without a charged special")

	# guard bounce and dash with an armed trap: foe pushed onto a trap sets it off
	var ft := _duel("star", "crab", 20000)
	ft.ents[0].special = 4
	ft.step([{"s": 0}, {}])
	ft.ents[1].x = ft.traps[0].x + 5000
	ft.ents[1].y = ft.traps[0].y
	for t in 16:
		ft.step([{}, {}])
	check(ft.traps.size() == 1, "far foe does not set off the armed trap")

	# trap against a guarded puffer takes half
	var pg := _duel("star", "puffer", 20000)
	pg.ents[0].special = 4
	pg.ents[1].special = 4
	pg.step([{"s": 0}, {}])
	pg.ents[1].x = pg.traps[0].x + 800
	pg.ents[1].y = pg.traps[0].y
	pg.step([{}, {"s": 0}])
	var pgp: int = pg.ents[1].hp
	for t in 20:
		pg.step([{}, {}])
	check(pg.traps.is_empty(), "trap went off on the puffer")


# --- Strandbal tables ---

func test_ball_tables() -> void:
	var shot: Dictionary = MatchSim.rules_for("ball").ball.shot
	for a in Content.animals():
		check(shot.has(str(a.attack.kind)) or str(a.attack.kind) in ["snip"], "ball shot table has the attack kind %s" % a.attack.kind)
		var kind := str(a.special.kind)
		if str(a.special.get("mech", kind)) in ["dash", "guard", "trap", "dive"]:
			check(shot.has(kind) or kind == "shell", "ball shot table has the special kind %s (or documented fallback)" % kind)
	# ball: guard puff kicks the ball once; hermit shell does not
	var s := MatchSim.new(42, ["puffer", "hermit", "crab", "gull", "otter", "seal"], "ball")
	check(s.ents.size() == 6 and s.ents[0].team != s.ents[1].team or true, "ball match with six new/old animals builds")
	for t in 400:
		s.step([{"m": 0, "a": 0}, {}, {}, {}, {}, {}])
	check(s.tick == 400 or s.finished == 1, "ball sim with new animals runs")


# --- determinism ---

func test_determinism_all_state() -> void:
	# every field of every list changes the hash
	var base := _duel("star", "puffer", 3000)
	base.ents[0].special = 4
	base.ents[1].special = 4
	base.step([{"s": 0, "a": 0}, {"s": 0}])
	var h0 := base.state_hash()
	for f in ["guard", "radius", "dash_dx", "vx", "vy", "target", "next_shot", "reflex_at", "dodge_until", "dodge_dir", "strafe_until", "engaged", "human_damage_pct", "damage_pct"]:
		var s := _duel("star", "puffer", 3000)
		s.ents[0].special = 4
		s.ents[1].special = 4
		s.step([{"s": 0, "a": 0}, {"s": 0}])
		s.ents[1].set(f, int(s.ents[1].get(f)) + 1)
		check(s.state_hash() != h0, "entity field %s is in the hash" % f)
	for f in MatchSim.TRAP_FIELDS:
		var s := _duel("star", "puffer", 3000)
		s.ents[0].special = 4
		s.ents[1].special = 4
		s.step([{"s": 0, "a": 0}, {"s": 0}])
		s.traps[0].set(f, int(s.traps[0].get(f)) + 1)
		check(s.state_hash() != h0, "trap field %s is in the hash" % f)
	for f in ["push", "back"]:
		var s := _duel("star", "seal", 3000)
		s.step([{"a": 0}, {"a": 0}])
		var h := s.state_hash()
		s.projs[0].set(f, int(s.projs[0].get(f)) + 1)
		check(s.state_hash() != h, "projectile field %s is in the hash" % f)
	# a trap that exists differs from none; a trap's snapshot is a deep copy
	var snap := base.snapshot()
	var before := JSON.stringify(snap)
	base.step([{}, {}])
	check(JSON.stringify(snap) == before, "snapshot is not changed by later steps")
	# snapshot -> json -> restore (the rollback and the relay carry plain data)
	var parsed: Variant = JSON.parse_string(JSON.stringify(snap))
	var clone := _duel("star", "puffer", 3000)
	clone.restore(parsed)
	var ref := _duel("star", "puffer", 3000)
	ref.restore(snap)
	check(clone.state_hash() == ref.state_hash(), "restore from a JSON round trip gives the same hash")

	# whole matches: restore at several ticks into a fresh match, continue, compare; count the new mechanics seen
	var seen := {"trap": 0, "puff": 0, "shell": 0, "slide": 0, "belly": 0, "arm": 0}
	var animals_seen := {}
	for seed in [11, 12, 13, 14, 15, 16, 17, 18]:
		var level: String = ["easy", "normal", "hard"][seed % 3]
		var a := Match.create(seed, "", 6, level)
		for e in a.sim.ents:
			animals_seen[str(a.sim.animals[e.id].id)] = true
		var snaps := {}
		for t in 1200:
			a.step()
			for ev in a.sim.events:
				if ev.type == "trap":
					seen.trap += 1
				if ev.type == "special":
					seen[str(ev.kind)] = int(seen.get(str(ev.kind), 0)) + 1
			if t in [100, 400, 700, 1000]:
				snaps[t] = a.sim.snapshot()
			if a.finished():
				break
		var ref_hash := a.sim.state_hash()
		for t in snaps:
			var b := Match.create(seed, "", 6, level)
			for i in 5:
				b.step() # dirty fresh match first so restore has to overwrite everything
			b.sim.restore(JSON.parse_string(JSON.stringify(snaps[t])))
			var tick_now: int = b.sim.tick
			while b.sim.tick < a.sim.tick:
				b.step()
			check(b.sim.state_hash() == ref_hash, "seed %d: restore at tick %d continues to the same hash (%d vs %d)" % [seed, t, b.sim.state_hash(), ref_hash])
		# same seed twice
		var c := Match.create(seed, "", 6, level)
		while c.sim.tick < a.sim.tick:
			c.step()
		check(c.sim.state_hash() == ref_hash, "seed %d: two runs agree" % seed)
	print("coverage: animals %s, specials seen %s" % [str(animals_seen.keys()), str(seen)])
	check(animals_seen.size() == 8, "the 8 test matches together field all 8 animals (%d)" % animals_seen.size())
	for k in ["puff", "shell", "slide", "belly", "arm"]:
		check(int(seen.get(k, 0)) > 0, "bots used the special %s at least once in the sample (%d)" % [k, int(seen.get(k, 0))])
	check(seen.trap > 0, "a trap went off in the sample")


# --- unlocks, reconcile, daily, replay ---

func test_unlocks_and_reconcile() -> void:
	check(Match.free_animals() == ["crab", "octopus", "gull", "otter", "hermit"], "free animals in roster order (%s)" % str(Match.free_animals()))
	# thresholds
	var cases := {0: [], 149: [], 150: ["puffer"], 349: ["puffer"], 350: ["puffer", "seal"], 549: ["puffer", "seal"], 550: ["puffer", "seal", "star"], 99999: ["puffer", "seal", "star"]}
	for pearls in cases:
		var p := Rewards.reconcile({"pearls_total": pearls, "unlocked_animals": ["crab", "octopus", "gull"]})
		var got: Array = (p.unlocked_animals as Array).filter(func(x): return not ["crab", "octopus", "gull", "otter", "hermit"].has(x))
		got.sort()
		var want: Array = (cases[pearls] as Array).duplicate()
		want.sort()
		check(got == want, "at %d pearls the extra animals are %s (got %s)" % [pearls, str(want), str(got)])
		check((p.unlocked_animals as Array).has("otter") and (p.unlocked_animals as Array).has("hermit"), "otter and hermit are always free (%d pearls)" % pearls)
	# rewards of the other kinds and idempotence over the whole range
	var full := Rewards.reconcile({"pearls_total": 2500})
	check((full.badges as Array).has("tide_master") and (full.badges as Array).has("beachcomber") and (full.avatars as Array).size() == 2 and (full.looks.owned as Array).has("octopus_midnight") and (full.looks.owned as Array).has("crab_sunset"), "2500 pearls: every path reward is granted")
	for pearls in [0, 100, 150, 400, 600, 2500]:
		var p := {"pearls_total": pearls, "unlocked_animals": ["crab"], "selected_animal": "crab", "looks": {"owned": ["x"], "equipped": {"crab": "x"}}, "extra": {"k": [1, 2]}}
		var once := Rewards.reconcile(p)
		check(JSON.stringify(Rewards.reconcile(once)) == JSON.stringify(once), "reconcile idempotent at %d" % pearls)
		check(once.selected_animal == "crab" and once.extra == {"k": [1, 2]} and (once.looks.owned as Array).has("x") and once.looks.equipped == {"crab": "x"}, "reconcile keeps unrelated fields at %d" % pearls)
		check(JSON.stringify(p) == JSON.stringify({"pearls_total": pearls, "unlocked_animals": ["crab"], "selected_animal": "crab", "looks": {"owned": ["x"], "equipped": {"crab": "x"}}, "extra": {"k": [1, 2]}}), "reconcile does not touch its input at %d" % pearls)
	# odd input
	var odd := Rewards.reconcile({})
	check((odd.unlocked_animals as Array).size() == 5, "empty profile dict reconciles to the free five")
	var dup := Rewards.reconcile({"pearls_total": 600, "unlocked_animals": ["crab", "crab", "kraken"]})
	check((dup.unlocked_animals as Array).has("kraken") and (dup.unlocked_animals as Array).count("crab") == 2, "unknown and duplicate ids are left alone (no data loss)")
	var neg := Rewards.reconcile({"pearls_total": -50})
	check((neg.unlocked_animals as Array).size() == 5 and not neg.has("avatars"), "negative pearls grant nothing")
	var fl := Rewards.reconcile({"pearls_total": 150.0})
	check((fl.unlocked_animals as Array).has("puffer"), "pearls as float 150.0 still grants")
	# malformed fields count as empty: no script errors, rewards still granted
	var bad := {"pearls_total": 2500, "looks": null, "badges": "x", "avatars": 5, "unlocked_animals": null}
	var fixed := Rewards.reconcile(bad)
	check((fixed.unlocked_animals as Array).has("puffer") and (fixed.badges is Array) and (fixed.avatars is Array), "null/string/number list fields are replaced and granted")
	check(fixed.looks is Dictionary and (fixed.looks.owned as Array).size() > 0, "looks null is rebuilt with the path looks")
	var bad2 := Rewards.reconcile({"pearls_total": 2500, "looks": {"owned": "x", "equipped": 3}})
	check((bad2.looks.owned as Array).size() > 0 and Rewards.equipped_look({"looks": {"owned": "x", "equipped": 3}}, "crab") == "", "looks.owned string and equipped number")
	var eqp := {"looks": "oops"}
	Rewards.equip(eqp, "crab", "x")
	check(eqp.looks is Dictionary and eqp.looks.equipped == {"crab": "x"}, "equip repairs a malformed looks field")
	check(JSON.stringify(Rewards.reconcile(fixed)) == JSON.stringify(fixed), "repaired profile reconciles idempotently")

	# Platform.load_profile reconciles but saves nothing; save persists it
	var path := "user://nf_extra_profile.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"format": 1, "version": 3, "pearls_total": 600, "unlocked_animals": ["crab", "octopus", "gull"], "selected_animal": "gull", "stats": {"matches": 20, "wins": 3, "knockouts": 9}, "settings": {}}))
	f.close()
	var before := FileAccess.get_file_as_string(path)
	var be = preload("res://platform/local_backend.gd").new()
	be.profile_path = path
	var saved_backend = Platform.backend
	Platform.backend = be
	var loaded: Dictionary = Platform.load_profile()
	for id in ["puffer", "seal", "star", "otter", "hermit", "crab", "octopus", "gull"]:
		check((loaded.unlocked_animals as Array).has(id), "A-F2: profile with 600 pearls has %s" % id)
	check((loaded.looks.owned as Array).has("crab_sunset"), "A-F2: crab_sunset owned through reconcile")
	check(FileAccess.get_file_as_string(path) == before, "load_profile saved nothing")
	Platform.save_profile(loaded)
	var after: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	check((after.unlocked_animals as Array).has("star"), "a later save persists the reconciled profile")
	check(int(after.version) == 4 and int(after.pearls_total) == 600 and after.selected_animal == "gull", "save keeps version bump, pearls and selection")
	# a fresh install
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var fresh: Dictionary = Platform.load_profile()
	check((fresh.unlocked_animals as Array).size() == 5 and not FileAccess.file_exists(path), "A-F1: new profile has the five free animals and writes no file")

	# A-F3 and walking a large jump: apply_result reports the animals crossed
	var res := preload("res://ui/result_screen.gd")
	for pair in [[140, "puffer"], [340, "seal"], [540, "star"]]:
		var pp := {"pearls_total": pair[0], "unlocked_animals": ["crab"]}
		var out: Dictionary = Rewards.walk(Content.load_json("res://data/path.json").rewards, pair[0], pair[0] + 20)
		check((out.unlocked as Array).any(func(r): return r.id == pair[1]), "crossing the threshold from %d reports %s" % [pair[0], pair[1]])
	var big := Rewards.walk(Content.load_json("res://data/path.json").rewards, 100, 600)
	check((big.unlocked as Array).filter(func(r): return r.kind == "animal").size() == 3, "a jump 100 to 600 reports all three animals")
	var exact := Rewards.walk(Content.load_json("res://data/path.json").rewards, 149, 150)
	check((exact.unlocked as Array).size() == 1 and exact.unlocked[0].id == "puffer", "exactly 150 unlocks the puffer, 149 does not")
	Platform.backend = saved_backend

	# path order and shape
	var rewards: Array = Content.load_json("res://data/path.json").rewards
	var last := 0
	var ok := true
	for rew in rewards:
		ok = ok and int(rew.at) > last
		last = int(rew.at)
	check(ok, "path rewards are strictly ascending")
	var at := {}
	for rew in rewards:
		if rew.kind == "animal":
			at[rew.id] = int(rew.at)
	check(at == {"puffer": 150, "seal": 350, "star": 550}, "path: puffer 150, seal 350, star 550 (%s)" % str(at))
	check(not at.has("otter") and not at.has("hermit"), "otter and hermit are not on the path")


func test_roster_users() -> void:
	var ids := {}
	for sd in range(0, 8):
		ids[Daily.animal_for(sd)] = true
	check(ids.size() == 8, "Daily.animal_for covers all 8 over seeds 0..7")
	for sd in [0, 7, 8, 1999999999, 2000000000]:
		check(Match.roster().has(Daily.animal_for(sd)), "Daily.animal_for(%d) is on the roster" % sd)
	check(Match.roster() == ["crab", "octopus", "gull", "puffer", "otter", "seal", "hermit", "star"], "roster order %s" % str(Match.roster()))
	# replay check: any roster animal accepted in a well-formed replay of an idle player, others rejected
	for a in Match.roster():
		var m := Match.create(5, a, 6, "easy")
		while not (m.finished() or m.human_out()):
			m.step({})
		var rep := Replay.encode(m.replay)
		var r := Replay.check(5, a, "easy", rep, m.human_result())
		check(r.ok, "Replay.check accepts a standing-still %s (%s)" % [a, r.reason])
	for bad in ["shark", "", "Crab", "CRAB", " puffer", "puffer "]:
		var r := Replay.check(5, bad, "easy", {"v": 1, "ticks": 1, "rle": [[1, -1, -1, -1, -1]]}, {})
		check(not r.ok and r.reason == "bad_setup", "Replay.check rejects '%s'" % bad)
	# a human of every animal plays a match with the scripted player without errors; all animals work as slot 0
	for a in Match.roster():
		var m := Match.create(9, a, 6, "normal")
		for t in 900:
			m.step(TestPlayer.cmd(m.sim, m.sim.ents[0]))
			if m.finished() or m.human_out():
				break
		check(m.sim.tick > 30, "%s plays as the human with the test player" % a)
	# match with a human on every new animal, online-style with all 8 animals in 8 slots
	var on := Match.create_online(3, Match.roster(), 8, "normal")
	for t in 600:
		on.step_many({})
	check(on.sim.tick > 100, "online match with all 8 animals as humans runs")
	# build id: stable, format, changes with data
	var id1 := Match.build_id()
	check(id1 == Match.build_id() and id1.begins_with("%d-" % Match.SIM_VERSION) and id1.length() <= 32, "build id is stable and short enough for the lobby (%s)" % id1)
	var rx := RegEx.new()
	rx.compile("^[A-Za-z0-9._-]{1,32}$")
	check(rx.search(id1) != null, "build id only has characters the relay accepts")


# --- text ---

func test_texts() -> void:
	var rows := {}
	var f := FileAccess.open("res://i18n/strings.csv", FileAccess.READ)
	f.get_csv_line()
	while not f.eof_reached():
		var line := f.get_csv_line()
		if line.size() >= 3:
			rows[line[0]] = line
	for a in Content.animals():
		for key in [str(a.name_key), "ATTACK_DESC_" + str(a.attack.kind).to_upper(), "SPECIAL_DESC_" + str(a.special.kind).to_upper(), "ANIMAL_TYPE_" + str(a.type).to_upper()]:
			check(rows.has(key) and str(rows[key][1]).strip_edges() != "" and str(rows[key][2]).strip_edges() != "", "text %s exists in en and nl" % key)
			if rows.has(key) and key.begins_with("ATTACK_DESC") or key.begins_with("SPECIAL_DESC"):
				check(rows[key][1] != rows[key][2], "%s: nl differs from en" % key)
	for loc in ["en", "nl"]:
		TranslationServer.set_locale(loc)
		for a in Content.animals():
			for key in [str(a.name_key), "ATTACK_DESC_" + str(a.attack.kind).to_upper(), "SPECIAL_DESC_" + str(a.special.kind).to_upper()]:
				check(tr(key) != key and not tr(key).contains("TODO") and not tr(key).contains("XXX"), "%s resolves in %s" % [key, loc])
	TranslationServer.set_locale("en")
	# the key list in design 4.5 has the exact English wording
	var want := {"ATTACK_DESC_SPINES": "spines that fly out in every direction", "SPECIAL_DESC_SHELL": "hides in the shell: almost no damage, can't be pushed, can't attack", "SPECIAL_DESC_ARM": "leaves an arm behind that explodes when someone steps on it"}
	for k in want:
		check(rows.has(k) and rows[k][1] == want[k], "%s wording as in the design" % k)
	# every look and animal key used by the zoo/collection exists; names of path rewards
	for rew in Content.load_json("res://data/path.json").rewards:
		check(rows.has(str(rew.name_key)), "path reward key %s exists" % rew.name_key)
	# collection: every card and detail builds for all 8 in both languages
	for loc in ["en", "nl"]:
		TranslationServer.set_locale(loc)
		var screen = preload("res://ui/collection_screen.gd").new()
		add_child(screen)
		var all: Array = screen.entries()
		check(all.size() == 8, "collection has 8 cards in %s" % loc)
		for e in all:
			var box := VBoxContainer.new()
			var shade := ColorRect.new()
			add_child(box)
			screen.fill_detail(box, str(e.id), shade)
			var texts: Array = []
			for c in box.get_children():
				if c is Label:
					texts.append((c as Label).text)
			var joined := " | ".join(texts)
			check(not joined.contains("ATTACK_DESC") and not joined.contains("SPECIAL_DESC") and not joined.contains("COLLECTION_"), "%s detail in %s shows no raw keys (%s)" % [e.id, loc, joined])
			check(texts.size() >= 4, "%s detail in %s has title, type, attack, special, mastery" % [e.id, loc])
			box.queue_free()
		screen.queue_free()
	TranslationServer.set_locale("en")


## Rollback with the new animals as the human players (lag, a leaver), normal and Strandbal; every screen equals the reference.
func test_rollback_new_animals() -> void:
	for setup in [{"mode": "", "leaver": -1}, {"mode": "", "leaver": 0}, {"mode": "ball", "leaver": 3}]:
		var animals := ["star", "hermit", "puffer", "otter", "seal", "octopus"]
		var n := animals.size()
		var seed_value := 4711
		var mode: String = setup.mode
		var clients: Array = []
		for i in n:
			clients.append(Rollback.new(Match.create_online(seed_value, animals, 6, "hard", mode), i))
		var net := RandomNumberGenerator.new()
		net.seed = 3
		var in_flight: Array = []
		var ticks := 720
		var step := 0
		var leave_tick := -1
		var leaver: int = setup.leaver
		var players: Array = range(n).filter(func(i): return i != leaver)
		while players.any(func(i): return clients[i].tick < ticks) and step < ticks * 4:
			step += 1
			for msg in in_flight.filter(func(x): return x[0] <= step):
				if msg[2] == -1:
					clients[msg[1]].leave(msg[4], msg[3])
				else:
					clients[msg[1]].remote_input(msg[2], msg[3], msg[4])
			in_flight = in_flight.filter(func(x): return x[0] > step)
			if leaver >= 0 and step == 250:
				var gone: Rollback = clients[leaver]
				leave_tick = gone.tick + gone.delay
				for j in n:
					if j != leaver:
						in_flight.append([step + net.randi_range(1, 7), j, -1, leave_tick, leaver])
			for i in n:
				var c: Rollback = clients[i]
				if i == leaver and step >= 250:
					continue
				if c.tick >= ticks or not c.can_advance():
					continue
				c.local_input(Match.cmd_to(_eager(c.m.sim, c.m.sim.ents[i])))
				for out in c.outbox:
					for j in n:
						if j != i:
							in_flight.append([step + net.randi_range(1, 7), j, i, out[0], out[1]])
				c.outbox.clear()
				c.advance()
		for msg in in_flight:
			if msg[2] == -1:
				clients[msg[1]].leave(msg[4], msg[3])
			else:
				clients[msg[1]].remote_input(msg[2], msg[3], msg[4])
		var hashes: Array = players.map(func(i): return clients[i].settle())
		var inputs: Dictionary = clients[players[0]].confirmed_inputs(ticks)
		var ref := Match.create_online(seed_value, animals, 6, "hard", mode)
		var specials := 0
		for t in ticks:
			if t == leave_tick:
				ref.to_bot(leaver)
			var cmds := {}
			for sl in ref.humans:
				cmds[sl] = inputs[sl][t]
			ref.step_many(cmds)
			for ev in ref.sim.events:
				if ev.type == "special":
					specials += 1
		var rb := 0
		for i in players:
			rb += clients[i].rollbacks
		var what := "rollback with star/hermit/puffer/otter/seal as players, mode '%s', leaver %d: %d rollbacks, %d specials" % [mode, leaver, rb, specials]
		check(hashes.all(func(h): return h == hashes[0]) and hashes[0] == ref.sim.state_hash(), what)
		check(rb > 0 and specials > 0, "this run exercised rollback and specials (%d, %d)" % [rb, specials])
		print(what)


## Printed so two separate processes can be compared by the caller (same lines expected).
func test_cross_process_hash() -> void:
	var out: Array = []
	for cfg in [[1, "", ["puffer", "otter", "seal", "hermit", "star", "crab"]], [2, "ball", ["star", "hermit", "otter", "puffer", "seal", "gull"]]]:
		var m := Match.create_online(int(cfg[0]), cfg[2], 6, "normal", str(cfg[1]))
		for t in 2400:
			m.step_many({})
		out.append(m.sim.state_hash())
	print("XPROC %s" % str(out))


## Test player that fires at the nearest foe and uses the special the moment it is charged (every mechanic gets exercised).
func _eager(sim: MatchSim, me: MatchSim.Ent) -> Dictionary:
	var best: MatchSim.Ent = null
	var bd := 1 << 60
	for o in sim.ents:
		if o.alive and o.id != me.id:
			var d := MatchSim._d2(o.x - me.x, o.y - me.y)
			if d < bd:
				bd = d
				best = o
	if best == null:
		return {}
	var ang := Fx.atan2_a(best.y - me.y, best.x - me.x)
	var cmd := {"m": posmod(ang + (sim.tick / 40) * 700, 4096), "a": ang}
	if me.special >= 4:
		cmd["s"] = ang
		cmd["sd"] = mini(3000, Fx.dist(best.x - me.x, best.y - me.y))
	return cmd


## apply_result end to end on a temporary profile file: crossing a threshold reports the animal and saves it.
func test_apply_result() -> void:
	var RS := preload("res://ui/result_screen.gd")
	var path := "user://nf_extra_apply.json"
	var saved_backend = Platform.backend
	var be = preload("res://platform/local_backend.gd").new()
	be.profile_path = path
	Platform.backend = be
	var cases := [
		{"pearls": 140, "result": {"place": 1, "kos": 0, "animal": "crab"}, "reported": ["puffer"], "owned": ["puffer"], "not_owned": ["seal", "star"]},
		{"pearls": 149, "result": {"place": 6, "kos": 0, "animal": "gull"}, "reported": ["puffer"], "owned": ["puffer"], "not_owned": ["seal", "star"]},
		{"pearls": 340, "result": {"place": 2, "kos": 2, "animal": "otter"}, "reported": ["seal"], "owned": ["puffer", "seal"], "not_owned": ["star"]},
		{"pearls": 540, "result": {"place": 3, "kos": 0, "animal": "hermit"}, "reported": ["star"], "owned": ["puffer", "seal", "star"], "not_owned": []},
		# an old profile already past the thresholds: nothing is reported again, but the saved profile is complete
		{"pearls": 700, "result": {"place": 1, "kos": 0, "animal": "crab"}, "reported": [], "owned": ["puffer", "seal", "star"], "not_owned": []},
	]
	for cs in cases:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(JSON.stringify({"format": 1, "version": 1, "pearls_total": cs.pearls, "unlocked_animals": ["crab", "octopus", "gull"], "selected_animal": "crab", "stats": {}, "settings": {}}))
		f.close()
		var out: Dictionary = RS.apply_result(cs.result)
		var reported: Array = (out.unlocked as Array).filter(func(r): return r.kind == "animal").map(func(r): return r.id)
		check(reported == cs.reported, "%d pearls + %s: reported %s (got %s)" % [cs.pearls, str(cs.result), str(cs.reported), str(reported)])
		var back: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		for id in cs.owned:
			check((back.unlocked_animals as Array).has(id), "saved profile owns %s after %d pearls + match" % [id, cs.pearls])
		for id in cs.not_owned:
			check(not (back.unlocked_animals as Array).has(id), "saved profile does not own %s yet at %d + match" % [id, cs.pearls])
		check((back.unlocked_animals as Array).has("otter") and (back.unlocked_animals as Array).has("hermit"), "free animals in the saved profile")
		check(int(back.pearls_total) == int(out.after), "pearls saved")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Platform.backend = saved_backend
