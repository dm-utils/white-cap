extends Node
## Rewards.reconcile / equip / equipped_look with malformed profile fields (null, string, number, wrong container):
## no script errors, rewards still granted, result idempotent. Headless:
##   godot --headless --path . res://tests/rewards_malformed.tscn

var _passed := 0
var _failed := 0


func check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL: " + what)


func _ready() -> void:
	var junk: Array = [null, "x", "", 5, 2.5, true, [], {}, [1, null, {}], {"a": 1}, Vector2(1, 2)]
	var clean := Rewards.reconcile({"pearls_total": 2500})
	var want_animals: Array = clean.unlocked_animals
	for field in ["looks", "badges", "avatars", "unlocked_animals"]:
		for j in junk:
			var p := {"pearls_total": 2500}
			p[field] = j
			var r := Rewards.reconcile(p)
			var tag := "%s = %s" % [field, str(j)]
			check(not r.is_empty(), "reconcile returns a profile: " + tag)
			check(r.get("unlocked_animals") is Array and r.get("badges") is Array and r.get("avatars") is Array and r.get("looks") is Dictionary, "field types repaired: " + tag)
			for a in want_animals:
				check((r.get("unlocked_animals") as Array).has(a), "animal %s granted: %s" % [a, tag])
			check(field == "looks" or ((r.looks as Dictionary).get("owned") is Array and ((r.looks as Dictionary).owned as Array).size() == (clean.looks.owned as Array).size()), "looks.owned complete: " + tag)
			check((r.badges as Array).size() >= (clean.badges as Array).size(), "badges granted: " + tag)
			check(JSON.stringify(Rewards.reconcile(r)) == JSON.stringify(r), "idempotent: " + tag)
	# nested looks
	for o in junk:
		for e in junk:
			var p2 := {"pearls_total": 2500, "looks": {"owned": o, "equipped": e}}
			var r2 := Rewards.reconcile(p2)
			check(r2.looks.owned is Array and (r2.looks.owned as Array).size() >= (clean.looks.owned as Array).size(), "nested owned=%s equipped=%s" % [str(o), str(e)])
			var animal_look := Rewards.equipped_look(p2, "crab")
			check(animal_look is String, "equipped_look ok: owned=%s equipped=%s" % [str(o), str(e)])
			Rewards.equip(p2, "crab", "x")
			check(p2.looks is Dictionary and (p2.looks.equipped as Dictionary).get("crab") == "x", "equip repairs: owned=%s equipped=%s" % [str(o), str(e)])
			Rewards.equip(p2, "crab", "")
			check(not (p2.looks.equipped as Dictionary).has("crab"), "unequip ok")
	# valid owned entries are kept next to junk
	var keep := Rewards.reconcile({"pearls_total": 0, "looks": {"owned": ["mine"], "equipped": {"crab": "mine"}}})
	check((keep.looks.owned as Array).has("mine") and Rewards.equipped_look(keep, "crab") == "mine", "valid looks untouched")
	# pearls_total malformed
	for pj in junk:
		var r3 := Rewards.reconcile({"pearls_total": pj})
		check(r3.get("unlocked_animals") is Array and (r3.unlocked_animals as Array).has("crab"), "pearls_total=%s: free animals" % str(pj))
	# whole profile fields of other types untouched
	var r4 := Rewards.reconcile({"pearls_total": 150, "name": 5, "extra": [1, 2]})
	check(r4.name == 5 and r4.extra == [1, 2], "other fields untouched")
	# grant with malformed reward dictionaries
	var g := {}
	Rewards.grant(g, {})
	Rewards.grant(g, {"kind": "animal"})
	Rewards.grant(g, {"kind": 5, "id": null})
	check(true, "grant with empty/odd rewards does not crash")
	print("rewards malformed: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)
