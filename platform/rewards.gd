class_name Rewards
extends RefCounted
## Granting rewards from any path (Treasure Path, season path) into the profile. One place, so every kind is kept:
##   animal -> unlocked_animals · look -> looks.owned · badge -> badges · avatar -> avatars
## Looks, badges and avatars are for show only; nothing here gives power (FO §7).


## Profile number to int: numbers, bools and numeric strings convert, anything else (null, containers, vectors) is
## the fallback. int() on those types is a script error.
static func num(v: Variant, fallback: int = 0) -> int:
	match typeof(v):
		TYPE_INT, TYPE_FLOAT, TYPE_BOOL, TYPE_STRING, TYPE_STRING_NAME:
			return int(v)
	return fallback


static func grant(profile: Dictionary, rew: Dictionary) -> void:
	var id := str(rew.get("id", ""))
	match str(rew.get("kind", "")):
		"animal":
			_add(profile, "unlocked_animals", id)
		"look":
			var looks := _dict(profile.get("looks"))
			var owned := _array(looks.get("owned"))
			if not owned.has(id):
				owned.append(id)
			looks["owned"] = owned
			profile["looks"] = looks
		"badge":
			_add(profile, "badges", id)
		"avatar":
			_add(profile, "avatars", id)


static func _add(profile: Dictionary, key: String, id: String) -> void:
	var list := _array(profile.get(key))
	if not list.has(id):
		list.append(id)
	profile[key] = list


# malformed profile fields (hand-edited, damaged) count as empty
static func _array(v: Variant) -> Array:
	return v if v is Array else []


static func _dict(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}


## Walks a path's rewards for a pearl count going from before to after: {unlocked, next, prev_at}.
static func walk(rewards: Array, before: int, after: int) -> Dictionary:
	var unlocked: Array = []
	var next: Dictionary = {}
	var prev_at := 0
	for rew in rewards:
		if int(rew.at) > before and int(rew.at) <= after:
			unlocked.append(rew)
		if int(rew.at) <= after:
			prev_at = int(rew.at)
		elif next.is_empty():
			next = rew
	return {"unlocked": unlocked, "next": next, "prev_at": prev_at}


## The profile it should be: free animals unlocked and every Treasure Path reward up to the pearls collected
## granted (animals that moved earlier on the path, new rewards). Pure and idempotent; the next save persists it.
static func reconcile(profile: Dictionary) -> Dictionary:
	var p := profile.duplicate(true)
	for id in Match.free_animals():
		_add(p, "unlocked_animals", str(id))
	var pearls := num(p.get("pearls_total"))
	for rew in Content.load_json("res://data/path.json").rewards:
		if int(rew.at) <= pearls:
			grant(p, rew)
	return p


## Looks: which look an animal wears (equipped and owned), "" = the standard colours.
static func equipped_look(profile: Dictionary, animal: String) -> String:
	var looks := _dict(profile.get("looks"))
	var look := str(_dict(looks.get("equipped")).get(animal, ""))
	return look if _array(looks.get("owned")).has(look) else ""


static func equip(profile: Dictionary, animal: String, look: String) -> void:
	var looks := _dict(profile.get("looks"))
	var eq := _dict(looks.get("equipped"))
	if look == "":
		eq.erase(animal)
	else:
		eq[animal] = look
	looks["equipped"] = eq
	profile["looks"] = looks
