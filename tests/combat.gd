extends Node3D
## Real production scenes, deterministic process stepping, no replacement weapon logic.
var results: Array = []
var p
var w
var actors: Array = []
var failed := 0
var active_id := ""
var only := ""
var report_path := ""
var started := 0

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="): only = arg.trim_prefix("--only=")
		if arg.begins_with("--report="): report_path = arg.trim_prefix("--report=")
	call_deferred("run")

func check(condition: bool, expected, actual) -> void:
	var row := {"id": active_id, "passed": condition, "expected": expected, "actual": actual}
	results.append(row)
	if not condition: failed += 1
	print("QA_CHECK ", JSON.stringify(row))

func fresh(ids: Array = ["rifle", "shotgun", "pistol"]) -> void:
	for node in actors:
		if is_instance_valid(node): node.free()
	actors.clear()
	Game.config = {"mode": Game.Mode.DEATHMATCH, "frag_limit": 9999, "time_limit": 600, "bot_count": 0}
	Game.match_active = false
	Game.reset_scores()
	seed(20261113)
	p = load("res://scenes/player.tscn").instantiate()
	p.name = "Shooter"
	p.combatant_id = 1
	p.team = 0
	add_child(p)
	actors.append(p)
	p.set_physics_process(false)
	p.set_process(false)
	w = p.weapons
	w.set_process(false)
	w.set_loadout(ids)
	Game.register_combatant(1, "Shooter", false, 0)
	await get_tree().physics_frame
	await get_tree().physics_frame

func tick(dt: float) -> void:
	w._process(dt)

func pull() -> void:
	w.set_trigger(true)
	tick(0.001)
	w.set_trigger(false)

func finish() -> void:
	# Step the real reload state machine, rather than calling a reimplemented formula.
	tick(float(w._current()["reload_time"]) + 0.001)

func bot(at: Vector3, team_id: int = 1):
	var b = load("res://scenes/bot.tscn").instantiate()
	b.name = "Target" + str(actors.size())
	b.combatant_id = -actors.size()
	b.team = team_id
	b.respawns = false
	b.position = at
	add_child(b)
	b.set_physics_process(false)
	b.set_process(false)
	actors.append(b)
	Game.register_combatant(b.combatant_id, b.name, true, team_id)
	await get_tree().physics_frame
	await get_tree().physics_frame
	return b

func aim(b, part: String = "Torso") -> void:
	var target: Vector3 = b.get_node("Hitboxes/" + part + "/Shape").global_position
	# Arrange a horizontal shot at the chosen volume; avoid the torso occluding an uphill head ray.
	p.camera.global_position.y = target.y
	p.camera.look_at(target, Vector3.UP)
	w.set_aiming(true)

func run() -> void:
	started = Time.get_ticks_msec()
	var cases := [
		["W01", "reload_partial"], ["W02", "reload_shortage"], ["W03", "reload_zero"],
		["W04", "reload_full"], ["W05", "empty_trigger"], ["W06", "reload_blocks_fire"],
		["W07", "switch_interrupt"], ["W08", "reload_repeat"], ["W09", "automatic_hold"],
		["W10", "semi_hold"], ["W11", "cooldown_switch"], ["W12", "unarmed"],
		["W13", "infinite_pistol"], ["W14", "remove_during_reload"], ["W15", "empty_slot_switch"],
		["W16", "respawn_refill"], ["D01", "base_damage"], ["D02", "head_damage"],
		["D03", "leg_damage"], ["D04", "obstacle"], ["D05", "friendly_occlusion"],
		["D06", "shotgun"], ["D07", "range_boundary"], ["D08", "bot_death"],
		["D09", "dead_shooter"]]
	for entry in cases:
		active_id = entry[0]
		if only != "" and active_id != only: continue
		print("QA_BEGIN ", active_id, " ", entry[1])
		await call(entry[1])
	for node in actors:
		if is_instance_valid(node): node.free()
	actors.clear()
	# Let production FX coroutines complete before freeing their scene nodes.
	await get_tree().create_timer(1.0).timeout
	for child in get_children(): child.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	var summary := {"suite": "combat", "checks": results.size(), "failed": failed, "results": results, "duration_ms": Time.get_ticks_msec()-started}
	if report_path != "":
		var f := FileAccess.open(report_path, FileAccess.WRITE)
		if f == null:
			push_error("QA report could not be written: " + report_path)
			get_tree().quit(2)
			return
		f.store_string(JSON.stringify(summary, "\t"))
	print("QA_SUMMARY ", JSON.stringify(summary))
	get_tree().quit(1 if failed > 0 else 0)

func reload_partial() -> void:
	await fresh()
	w.ammo.rifle = {"mag": 11, "reserve": 40}
	w.reload()
	var pending: bool = w._reloading and w.ammo.rifle.mag == 11
	finish()
	check(pending and w.ammo.rifle == {"mag": 30, "reserve": 21} and not w._reloading, "reload 11+40 -> 30+21, transfer only on completion", w.ammo.rifle)

func reload_shortage() -> void:
	await fresh()
	w.ammo.rifle = {"mag": 2, "reserve": 3}
	w.reload(); finish()
	check(w.ammo.rifle == {"mag": 5, "reserve": 0}, {"mag": 5, "reserve": 0}, w.ammo.rifle)

func reload_zero() -> void:
	await fresh()
	w.ammo.rifle = {"mag": 2, "reserve": 0}
	w.reload(); tick(2.0)
	check(not w._reloading and w.ammo.rifle == {"mag": 2, "reserve": 0}, "no reserve: reject reload", w.ammo.rifle)

func reload_full() -> void:
	await fresh()
	w.reload(); tick(2.0)
	check(not w._reloading and w.ammo.rifle == {"mag": 30, "reserve": 120}, "full magazine: reject reload", w.ammo.rifle)

func empty_trigger() -> void:
	await fresh()
	w.ammo.rifle = {"mag": 0, "reserve": 7}
	pull()
	var pending: bool = w._reloading and p.shots_fired == 0
	finish()
	check(pending and w.ammo.rifle == {"mag": 7, "reserve": 0}, "empty trigger starts reload without firing", {"ammo": w.ammo.rifle, "shots": p.shots_fired})

func reload_blocks_fire() -> void:
	await fresh()
	w.ammo.rifle = {"mag": 5, "reserve": 20}
	w.reload(); w.set_trigger(true); tick(0.2); w.set_trigger(false)
	check(w._reloading and w.ammo.rifle.mag == 5 and p.shots_fired == 0, "reload blocks trigger before completion", {"mag": w.ammo.rifle.mag, "shots": p.shots_fired, "pending": w._reloading})

func switch_interrupt() -> void:
	await fresh()
	w.ammo.rifle = {"mag": 5, "reserve": 20}
	w.reload(); tick(0.2); w.switch_to(1); tick(2.0); w.switch_to(0)
	check(not w._reloading and w.ammo.rifle == {"mag": 5, "reserve": 20} and w.ammo.shotgun.mag == 6, "switch cancels reload without transferring either gun's ammo", {"rifle": w.ammo.rifle, "shotgun": w.ammo.shotgun})

func reload_repeat() -> void:
	await fresh()
	w.ammo.rifle = {"mag": 5, "reserve": 40}
	w.reload(); tick(0.4)
	var left: float = w._reload_left
	for i in 20: w.reload()
	var same: bool = is_equal_approx(left, w._reload_left)
	finish()
	check(same and w.ammo.rifle == {"mag": 30, "reserve": 15}, "20 repeated reloads do not restart timer or duplicate ammo", {"timer_unchanged": same, "ammo": w.ammo.rifle})

func automatic_hold() -> void:
	await fresh()
	w.set_trigger(true); tick(0.001); tick(0.05)
	var before_cd: int = w.ammo.rifle.mag
	tick(0.07); w.set_trigger(false)
	check(before_cd == 29 and w.ammo.rifle.mag == 28 and p.shots_fired == 2, "held auto: second shot only after 1/9s cooldown", {"before_cooldown": before_cd, "mag": w.ammo.rifle.mag, "shots": p.shots_fired})

func semi_hold() -> void:
	await fresh(["pistol"])
	w.set_trigger(true); tick(0.001); tick(0.25)
	var held: int = w.ammo.pistol.mag
	w.set_trigger(false); pull()
	check(held == 11 and w.ammo.pistol.mag == 10, "held semi fires once; release and press permits next shot", {"held": held, "repressed": w.ammo.pistol.mag})

func cooldown_switch() -> void:
	await fresh()
	pull(); w.switch_to(1); pull()
	var blocked: int = w.ammo.shotgun.mag
	tick(0.12); pull()
	check(blocked == 6 and w.ammo.shotgun.mag == 5, "switch preserves shared cooldown until elapsed", {"blocked": blocked, "after": w.ammo.shotgun.mag})

func unarmed() -> void:
	await fresh([])
	pull(); w.reload(); tick(3.0)
	check(w.ammo.is_empty() and not w._reloading and p.shots_fired == 0, "unarmed: input safe, no ammo or shots", {"ammo": w.ammo, "shots": p.shots_fired})

func infinite_pistol() -> void:
	await fresh(["pistol"])
	w.ammo.pistol = {"mag": 0, "reserve": 0}
	w.reload(); finish(); pull(); tick(0.21); w.reload(); finish()
	check(w.ammo.pistol == {"mag": 12, "reserve": 0} and p.shots_fired == 1, "infinite reserve refills at zero; magazine still consumes a bullet", {"ammo": w.ammo.pistol, "shots": p.shots_fired})

func remove_during_reload() -> void:
	await fresh(["rifle"])
	w.ammo.rifle = {"mag": 1, "reserve": 10}
	w.reload(); p.unequip("gun1")
	var canceled: bool = not w._reloading
	tick(2.0)
	check(canceled and not w._reloading and w.ammo.is_empty(), "removing last gun cancels pending reload safely", {"canceled_immediately": canceled, "ammo": w.ammo})

func empty_slot_switch() -> void:
	await fresh(["rifle", "", "pistol"])
	w.ammo.rifle.mag = 5
	w.reload(); w.switch_to(1); w.switch_to(-1); w.switch_to(3)
	check(w.current_index == 0 and w._reloading, "invalid or empty switch leaves current gun and reload intact", {"index": w.current_index, "reloading": w._reloading})

func respawn_refill() -> void:
	await fresh()
	w.ammo.rifle = {"mag": 0, "reserve": 0}
	p.receive_damage(200.0, 2)
	var died: bool = p.dead and p.sync_health == 0
	p.respawn(Transform3D.IDENTITY)
	check(died and not p.dead and p.sync_health == 100 and w.ammo.rifle == {"mag": 30, "reserve": 120}, "lethal PvP hit then deathmatch respawn restores health and finite ammo", {"died": died, "dead": p.dead, "hp": p.sync_health, "ammo": w.ammo.rifle})

func base_damage() -> void:
	var observed := {}
	var good := true
	for pair in [["rifle", 17.0], ["smg", 12.0], ["pistol", 24.0], ["sniper", 95.0]]:
		await fresh([pair[0]])
		var b = await bot(Vector3(0,0,-2))
		aim(b); pull()
		observed[pair[0]] = 100.0 - b.sync_health
		good = good and is_equal_approx(float(observed[pair[0]]), pair[1])
	check(good, {"rifle": 17, "smg": 12, "pistol": 24, "sniper": 95}, observed)

func head_damage() -> void:
	await fresh()
	var b = await bot(Vector3(0,0,-2)); aim(b, "Head"); pull()
	check(is_equal_approx(b.sync_health, 57.5), "rifle head 17 x 2.5 = 42.5", {"health": b.sync_health})

func leg_damage() -> void:
	await fresh()
	var b = await bot(Vector3(0,0,-2)); aim(b, "Legs"); pull()
	check(is_equal_approx(b.sync_health, 87.25), "rifle legs 17 x 0.75 = 12.75", {"health": b.sync_health})

func obstacle() -> void:
	await fresh()
	var b = await bot(Vector3(0,0,-4)); aim(b)
	var wall := StaticBody3D.new(); wall.collision_layer = 1
	var cs := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size = Vector3(4,4,0.2)
	cs.shape = box; wall.add_child(cs); add_child(wall); actors.append(wall); wall.position = Vector3(0,1,-2)
	await get_tree().physics_frame; await get_tree().physics_frame
	pull()
	check(b.sync_health == 100 and w.ammo.rifle.mag == 29, "world collision blocks damage, shot consumes ammo", {"hp": b.sync_health, "mag": w.ammo.rifle.mag})

func friendly_occlusion() -> void:
	await fresh()
	var enemy = await bot(Vector3(0,0,-4))
	var friend = await bot(Vector3(0,0,-2), 0); aim(friend); pull()
	check(friend.sync_health == 100 and enemy.sync_health == 100 and w.ammo.rifle.mag == 29, "same-team target takes no damage and does not allow penetration", {"friend_hp": friend.sync_health, "enemy_hp": enemy.sync_health, "mag": w.ammo.rifle.mag})

func shotgun() -> void:
	await fresh(["shotgun"])
	var b = await bot(Vector3(0,0,-2)); aim(b); pull()
	check(is_equal_approx(b.sync_health, 19.0) and w.ammo.shotgun.mag == 5 and p.shots_fired == 1, "seeded close torso shot: 9 pellets x 9 damage, one shell", {"hp": b.sync_health, "mag": w.ammo.shotgun.mag, "shots": p.shots_fired})

func range_boundary() -> void:
	var observed := []
	for dist in [299.0, 301.0]:
		await fresh(["sniper"])
		var b = await bot(Vector3(0,0,-dist)); aim(b); pull(); observed.append(b.sync_health)
	check(observed == [5.0,100.0], "sniper range 300m: torso at 299 hits, 301 misses (runtime torso half-depth 0.6m)", observed)

func bot_death() -> void:
	await fresh(["sniper"])
	var b = await bot(Vector3(0,0,-2)); aim(b, "Head"); pull()
	var dead_once: bool = b.dead and b.sync_health == 0 and Game.scores[1].kills == 1
	b.receive_damage(95.0, 1)
	var layers_off := true
	for hb in b.get_node("Hitboxes").get_children(): layers_off = layers_off and hb.collision_layer == 0
	check(dead_once and layers_off and b.sync_health == 0 and Game.scores[1].kills == 1, "death clamps HP, removes hitboxes; repeat damage does not rescore", {"dead": b.dead, "hp": b.sync_health, "kills": Game.scores[1].kills, "hitboxes_off": layers_off})

func dead_shooter() -> void:
	await fresh()
	p.receive_damage(200, 2); pull()
	check(p.dead and w.ammo.rifle.mag == 30 and p.shots_fired == 0, "dead player trigger cannot fire", {"dead": p.dead, "mag": w.ammo.rifle.mag, "shots": p.shots_fired})
