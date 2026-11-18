class_name BotMetrics
extends Node
## Bot behaviour metrics: many matches headless, then the figures of docs/design.md 7.2. Reads state and events only,
## so it also works on any brain (a1 baseline).
##   godot --headless --path . res://tests/bot_metrics.tscn -- --matches=200 --level=normal --seed=1
##     [--human=1] [--check=1] [--out=user://bot_metrics.json] [--ms_max=<limit per 1000 ticks>]
## --human=1: slot 0 is the scripted test player. --check=1: exit 1 when a target of 7.2 is missed.
## The JSON holds no wall-clock figures, so the same command twice gives byte-identical output.

const MIN_ALIVE_MIN := 0.5 # bots that died earlier are too noisy for per-minute medians
const SETTLE_TICKS := 30
const TARGETS := {
	"easy": {"apm": [10.0, 40.0], "hpa": [0.15, 0.45], "spm": 0.4, "lag": 8.0, "idle": 12.0, "idle_max": 25.0, "fight": 35.0,
		"drown": 45.0, "focus": 35.0, "dur": [100.0, 190.0], "dur_min": 45.0},
	"normal": {"apm": [18.0, 50.0], "hpa": [0.25, 0.55], "spm": 0.8, "lag": 4.0, "idle": 8.0, "idle_max": 20.0, "fight": 50.0,
		"drown": 30.0, "focus": 35.0, "dur": [90.0, 180.0], "dur_min": 40.0},
	"hard": {"apm": [25.0, 60.0], "hpa": [0.35, 0.70], "spm": 1.2, "lag": 2.0, "idle": 6.0, "idle_max": 15.0, "fight": 60.0,
		"drown": 15.0, "focus": 40.0, "dur": [80.0, 170.0], "dur_min": 35.0},
}


func _ready() -> void:
	var args := Boot.parse(OS.get_cmdline_user_args())
	var level := str(args.get("level", "normal"))
	var r := run(int(args.get("matches", "100")), level, int(args.get("seed", "1")), args.get("human", "") == "1")
	for line in r.lines:
		print(line)
	var out := str(args.get("out", ""))
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string(JSON.stringify(r.data, "  ", true, true) + "\n")
		f.close()
	var ok := true
	if args.get("check", "") == "1":
		var misses := check(r.data, level)
		if args.has("ms_max") and float(r.ms_per_1000) > float(args.ms_max):
			misses.append("ms_per_1000_ticks %.2f > %s" % [r.ms_per_1000, args.ms_max])
		for m in misses:
			print("bot metrics: MISSED ", m)
		ok = misses.is_empty()
		print("bot metrics: %s" % ("targets met" if ok else "targets MISSED"))
	get_tree().quit(0 if ok else 1)


static func run(matches: int, level: String, base_seed: int, human: bool) -> Dictionary:
	var bots: Array = [] # one row per bot entry
	var animal_stat := {}
	var lags: Array = []
	var durations: Array = []
	var kos_all := 0
	var kos_fight := 0
	var bot_kos := 0
	var bot_drown := 0
	var hits_on_human := 0
	var bot_hits := 0
	var places: Array = []
	var total_ticks := 0
	var step_us := 0
	for i in matches:
		var seed_value := base_seed + i * 7919
		var m := Match.create(seed_value, Match.SLICE_ANIMALS[i % Match.SLICE_ANIMALS.size()] if human else "", 6, level)
		var sim := m.sim
		var hits_needed := int(sim.rules.attack.special_hits)
		var credit := int(sim.rules.knockout_credit_ticks)
		var rows: Array = []
		for e in sim.ents:
			rows.append({"animal": str(sim.animals[e.id].id), "single": int(sim.animals[e.id].attack.count) == 1, "alive": 0, "idle": 0,
				"settled": 0, "attacks": 0, "hits": 0, "specials": 0, "ready_at": -1, "bot": e.id != m.human})
		while not m.finished():
			var before: Array = []
			for e in sim.ents:
				before.append([e.x, e.y, e.alive, e.dash])
			var t0 := Time.get_ticks_usec()
			m.step(TestPlayer.cmd(sim, sim.ents[0]) if human else {})
			step_us += Time.get_ticks_usec() - t0
			for e in sim.ents:
				var b: Array = before[e.id]
				var row: Dictionary = rows[e.id]
				if b[2] == 1:
					row.alive += 1
					if sim.tick > SETTLE_TICKS:
						row.settled += 1
						if e.x == b[0] and e.y == b[1] and b[3] == 0 and e.dash == 0:
							row.idle += 1
				if e.alive == 1 and e.special >= hits_needed and row.ready_at < 0:
					row.ready_at = sim.tick
			for ev in sim.events:
				match str(ev.type):
					"attack":
						rows[ev.id].attacks += 1
					"hit":
						rows[ev.by].hits += 1
						if rows[ev.by].bot:
							bot_hits += 1
							if human and ev.id == 0:
								hits_on_human += 1
					"special":
						var row: Dictionary = rows[ev.id]
						row.specials += 1
						if row.ready_at >= 0:
							lags.append((sim.tick - row.ready_at) / 30.0)
						row.ready_at = -1
					"ko":
						var victim: MatchSim.Ent = sim.ents[ev.id]
						var credited: bool = int(ev.by) >= 0 and sim.tick - victim.last_hit_tick <= credit
						kos_all += 1
						if credited:
							kos_fight += 1
						if rows[ev.id].bot:
							bot_kos += 1
							if not credited and sim.level < int(sim.rules.tide.max_level):
								bot_drown += 1
		total_ticks += sim.tick
		durations.append(sim.tick / 30.0)
		if human:
			places.append(sim.ents[0].place)
		for r in sim.result():
			var st: Dictionary = animal_stat.get(r.animal, {"entries": 0, "wins": 0, "kos": 0})
			st.entries += 1
			st.kos += int(r.kos)
			if r.place == 1:
				st.wins += 1
			animal_stat[r.animal] = st
		for row in rows:
			if row.bot:
				bots.append(row)

	var apm: Array = []
	var spm: Array = []
	var idle_pct: Array = []
	var single_attacks := 0
	var single_hits := 0
	var by_animal := {}
	for row in bots:
		var mins: float = row.alive / 1800.0
		if mins >= MIN_ALIVE_MIN:
			apm.append(row.attacks / mins)
			spm.append(row.specials / mins)
			idle_pct.append(100.0 * row.idle / maxi(1, row.settled))
		if row.single:
			single_attacks += row.attacks
			single_hits += row.hits
		var a: Dictionary = by_animal.get(row.animal, {"alive": 0, "attacks": 0, "hits": 0, "specials": 0})
		a.alive += row.alive
		a.attacks += row.attacks
		a.hits += row.hits
		a.specials += row.specials
		by_animal[row.animal] = a
	var d := {
		"matches": matches, "level": level, "seed": base_seed, "human": human,
		"bots_counted": apm.size(),
		"attacks_per_min_median": _round(_median(apm)),
		"hits_per_attack_single": _round(float(single_hits) / maxi(1, single_attacks), 3),
		"specials_per_min_median": _round(_median(spm)),
		"special_lag_s_avg": _round(_avg(lags)),
		"special_lag_samples": lags.size(),
		"idle_pct_avg": _round(_avg(idle_pct)),
		"idle_pct_worst": _round(idle_pct.max() if not idle_pct.is_empty() else 0.0),
		"fight_ko_pct": _round(100.0 * kos_fight / maxi(1, kos_all)),
		"avoidable_drown_pct": _round(100.0 * bot_drown / maxi(1, bot_kos)),
		"duration_s_avg": _round(_avg(durations)),
		"duration_s_min": _round(durations.min() if not durations.is_empty() else 0.0),
		"duration_s_max": _round(durations.max() if not durations.is_empty() else 0.0),
		"animals": {},
	}
	if human:
		d["human_focus_pct"] = _round(100.0 * hits_on_human / maxi(1, bot_hits))
		d["human_place_avg"] = _round(_avg(places), 3)
	var names: Array = animal_stat.keys()
	names.sort()
	for n in names:
		var st: Dictionary = animal_stat[n]
		var a: Dictionary = by_animal.get(n, {"alive": 0, "attacks": 0, "hits": 0, "specials": 0})
		var mins: float = maxf(0.001, a.alive / 1800.0)
		d.animals[n] = {"entries": st.entries, "wins": st.wins, "win_pct": _round(100.0 * st.wins / maxi(1, st.entries)),
			"kos_per_entry": _round(float(st.kos) / maxi(1, st.entries)), "attacks_per_min": _round(a.attacks / mins),
			"hits_per_attack": _round(float(a.hits) / maxi(1, a.attacks), 3), "specials_per_min": _round(a.specials / mins)}
	var ms := step_us / 1000.0
	var ms_per_1000 := ms * 1000.0 / maxf(1.0, total_ticks)
	var lines: Array = []
	lines.append("bot metrics: %d matches, level %s, seed %d, human %s, %.1f s in sim, %.2f ms per 1000 ticks" % [
		matches, level, base_seed, str(human), ms / 1000.0, ms_per_1000])
	lines.append("bot metrics: attacks/min median %.1f | hits/attack (single) %.2f | specials/min median %.2f | special lag %.1f s (%d)" % [
		d.attacks_per_min_median, d.hits_per_attack_single, d.specials_per_min_median, d.special_lag_s_avg, lags.size()])
	lines.append("bot metrics: idle %% avg %.1f worst %.1f | fight KOs %.0f %% | avoidable drowning %.0f %% | duration avg %.0f s min %.0f s max %.0f s" % [
		d.idle_pct_avg, d.idle_pct_worst, d.fight_ko_pct, d.avoidable_drown_pct, d.duration_s_avg, d.duration_s_min, d.duration_s_max])
	if human:
		lines.append("bot metrics: human focus %.1f %% | test player average place %.2f" % [d.human_focus_pct, d.human_place_avg])
	for n in names:
		var a: Dictionary = d.animals[n]
		lines.append("bot metrics: %-8s entries %4d  win %% %5.1f  KOs/entry %.2f  attacks/min %5.1f  hits/attack %.2f  specials/min %.2f" % [
			n, a.entries, a.win_pct, a.kos_per_entry, a.attacks_per_min, a.hits_per_attack, a.specials_per_min])
	return {"data": d, "lines": lines, "ms_per_1000": ms_per_1000}


## Targets of 7.2 that are missed (empty = all met).
static func check(d: Dictionary, level: String) -> Array:
	var t: Dictionary = TARGETS.get(level, TARGETS.normal)
	var out: Array = []
	_range(out, "attacks per min", d.attacks_per_min_median, t.apm)
	_range(out, "hits per attack", d.hits_per_attack_single, t.hpa)
	if d.specials_per_min_median < t.spm:
		out.append("specials per min %.2f < %.2f" % [d.specials_per_min_median, t.spm])
	if d.special_lag_s_avg > t.lag:
		out.append("special lag %.1f s > %.1f" % [d.special_lag_s_avg, t.lag])
	if d.idle_pct_avg > t.idle:
		out.append("idle avg %.1f > %.1f" % [d.idle_pct_avg, t.idle])
	if d.idle_pct_worst > t.idle_max:
		out.append("idle worst %.1f > %.1f" % [d.idle_pct_worst, t.idle_max])
	if d.fight_ko_pct < t.fight:
		out.append("fight KOs %.0f %% < %.0f" % [d.fight_ko_pct, t.fight])
	if d.avoidable_drown_pct > t.drown:
		out.append("avoidable drowning %.0f %% > %.0f" % [d.avoidable_drown_pct, t.drown])
	_range(out, "duration avg", d.duration_s_avg, t.dur)
	if d.duration_s_min < t.dur_min:
		out.append("shortest match %.0f s < %.0f" % [d.duration_s_min, t.dur_min])
	if d.has("human_focus_pct") and d.human_focus_pct > t.focus:
		out.append("human focus %.1f %% > %.0f" % [d.human_focus_pct, t.focus])
	return out


static func _range(out: Array, what: String, v: float, r: Array) -> void:
	if v < r[0] or v > r[1]:
		out.append("%s %.2f outside %s-%s" % [what, v, str(r[0]), str(r[1])])


static func _round(v: float, digits := 2) -> float:
	return snappedf(v, pow(10.0, -digits))


static func _avg(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += v
	return s / a.size()


static func _median(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	var n := s.size()
	return float(s[n / 2]) if n % 2 == 1 else (float(s[n / 2 - 1]) + float(s[n / 2])) / 2.0
