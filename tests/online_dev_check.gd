extends Node
## Manual check against the dev relay (needs network): two clients of the same build queue together, play a match with
## the real relay and rollback, one leaves; hashes must agree and no desync message may arrive.
##   godot --headless --path . res://tests/online_dev_check.tscn -- [--base=wss://st33f-pvp-dev.st33fd3v.workers.dev] [--animals=star,hermit]
## Not part of run_tests (no network in CI).

var base := "wss://st33f-pvp-dev.st33fd3v.workers.dev"
var animals: Array = ["star", "hermit"]
var room: Array = []
var infos: Array = [null, null]
var rbs: Array = [null, null]
var started := [false, false]
var desync := [0, 0]
var leave_msg := {}
var hashes: Array = [{}, {}]
var next_hash := [Rollback.HASH_EVERY - 1, Rollback.HASH_EVERY - 1]
var ticks_goal := 900
var leave_at := 400
var gone := false
var t_start := 0
var done := false
var _passed := 0
var _failed := 0


func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if ok:
		_passed += 1
	else:
		_failed += 1


var info_path := ""


func _ready() -> void:
	var args := Boot.parse(OS.get_cmdline_user_args())
	base = str(args.get("base", base))
	info_path = str(args.get("info", ""))
	t_start = Time.get_ticks_msec()
	print("waiting for the two match messages in ", info_path)


## The lobby closes its socket right after the match message; WebSocketPeer drops packets that arrive together with the
## close frame, so a native client loses it. The match messages come from a Node script that joined the lobby (info file).
func _poll_info() -> void:
	if not FileAccess.file_exists(info_path):
		return
	var msgs: Variant = JSON.parse_string(FileAccess.get_file_as_string(info_path))
	if not msgs is Array or msgs.size() != 2:
		return
	for i in 2:
		var msg: Dictionary = msgs[i]
		infos[i] = msg
		var c := OnlineClient.new()
		add_child(c)
		c.message.connect(_on_room.bind(i))
		c.open("%s/v1/games/white-cap/pvp/room/%s?slot=%d&key=%s" % [base, msg.room, int(msg.slot), msg.key])
		room.append(c)
		var m := Match.create_online(int(msg.seed), msg.animals, 6, "normal", str(msg.get("mode", "")))
		m.human = int(msg.slot)
		rbs[i] = Rollback.new(m, m.human, int(msg.get("delay", 2)))
		print("client %d: match animals %s slot %d" % [i, str(msg.animals), int(msg.slot)])
	DirAccess.remove_absolute(info_path)
	t_start = Time.get_ticks_msec()


func _on_room(msg: Dictionary, i: int) -> void:
	match OnlineClient.apply(rbs[i], msg):
		"start":
			started[i] = true
		"desync":
			desync[i] += 1
		"leave":
			leave_msg = msg


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


func _process(_d: float) -> void:
	if done:
		return
	if rbs[0] == null:
		_poll_info()
		return
	if Time.get_ticks_msec() - t_start > 150000:
		check(false, "timeout (started %s, ticks %s)" % [str(started), str([rbs[0].tick if rbs[0] else -1, rbs[1].tick if rbs[1] else -1])])
		_finish()
		return
	for i in 2:
		if not started[i] or (gone and i == 1):
			continue
		var rb: Rollback = rbs[i]
		if rb.tick >= ticks_goal or not rb.can_advance():
			continue
		rb.local_input(Match.cmd_to(_eager(rb.m.sim, rb.m.sim.ents[i])))
		for out in OnlineClient.batch(rb.outbox):
			room[i].send(out)
		rb.outbox.clear()
		rb.advance()
		while rb.settled_hash(next_hash[i]) != -1:
			hashes[i][next_hash[i]] = rb.settled_hash(next_hash[i])
			room[i].send({"type": "hash", "t": next_hash[i], "h": rb.settled_hash(next_hash[i])})
			next_hash[i] += Rollback.HASH_EVERY
	if started[0] and started[1] and not gone and rbs[1].tick >= leave_at:
		gone = true
		room[1].close()
		print("client 1 left at tick ", rbs[1].tick)
	if gone and rbs[0] != null and rbs[0].tick >= ticks_goal:
		_finish()


func _finish() -> void:
	done = true
	var a: Rollback = rbs[0]
	var b: Rollback = rbs[1]
	check(desync[0] == 0 and desync[1] == 0, "no desync message from the relay (%s)" % str(desync))
	var same := 0
	var diff := 0
	for t in hashes[0]:
		if hashes[1].has(t):
			if hashes[0][t] == hashes[1][t]:
				same += 1
			else:
				diff += 1
	check(same > 0 and diff == 0, "settled hashes of both clients agree before the leave (%d same, %d different)" % [same, diff])
	check(not leave_msg.is_empty(), "client 0 was told about the leave: %s" % str(leave_msg))
	if a != null and a.tick >= ticks_goal and not leave_msg.is_empty():
		var hash_a: int = a.settle()
		var inputs: Dictionary = a.confirmed_inputs(ticks_goal)
		var ref := Match.create_online(int(infos[0].seed), infos[0].animals, 6, "normal", str(infos[0].get("mode", "")))
		var leave_tick := int(leave_msg.t)
		for t in ticks_goal:
			if t == leave_tick:
				ref.to_bot(1)
			var cmds := {}
			for s in ref.humans:
				cmds[s] = inputs[s][t]
			ref.step_many(cmds)
		check(hash_a == ref.sim.state_hash(), "client 0 equals a reference run with the leaver turned into a bot at tick %d (%d vs %d)" % [leave_tick, hash_a, ref.sim.state_hash()])
		print("rollbacks client 0: ", a.rollbacks, ", ticks ", a.tick)
	print("online dev check: %d passed, %d failed, %.1f s" % [_passed, _failed, (Time.get_ticks_msec() - t_start) / 1000.0])
	get_tree().quit(1 if _failed > 0 else 0)
