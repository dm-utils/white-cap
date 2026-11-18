class_name TestPlayer
extends RefCounted
## Scripted stand-in for a human: reads the sim only (no rng), so replays and metrics are reproducible.


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
