extends Node
## Two OS processes; RPC snapshots contain each process's own observed game state.
var role := "host"
var scenario := "combat"
var port := 28191
var report := ""
var rows: Array = []
var failed := 0
var client_id := 0
var remote: Dictionary = {}
var remote_stage := ""
var leaving := false
var disconnected := false

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="): role = arg.trim_prefix("--role=")
		if arg.begins_with("--scenario="): scenario = arg.trim_prefix("--scenario=")
		if arg.begins_with("--port="): port = int(arg.trim_prefix("--port="))
		if arg.begins_with("--report="): report = arg.trim_prefix("--report=")
	Net.match_started.connect(load_world)
	Net.server_disconnected.connect(func(): disconnected = true)
	call_deferred("run")

func wait_for(predicate: Callable, seconds: float = 8.0) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < end:
		if predicate.call(): return true
		await get_tree().create_timer(0.05).timeout
	return predicate.call()

func record(id: String, good: bool, expected, actual) -> void:
	var row := {"id": id, "passed": good, "expected": expected, "actual": actual}
	rows.append(row)
	if not good: failed += 1
	print("QA_CHECK ", JSON.stringify(row))

func finish() -> void:
	# Drain outstanding production UI/FX callbacks before process shutdown.
	await get_tree().create_timer(0.9).timeout
	for world in get_tree().get_nodes_in_group("world"): world.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	Music.stop()
	await get_tree().create_timer(0.15).timeout
	var result := {"suite": "network", "role": role, "scenario": scenario, "checks": rows.size(), "failed": failed, "results": rows}
	if report != "":
		var f := FileAccess.open(report, FileAccess.WRITE)
		if f == null:
			push_error("QA report write failed"); get_tree().quit(2); return
		f.store_string(JSON.stringify(result, "\t"))
	print("QA_SUMMARY ", JSON.stringify(result))
	get_tree().quit(1 if failed > 0 else 0)

func load_world() -> void:
	await get_tree().process_frame
	get_tree().root.add_child(load("res://scenes/world.tscn").instantiate())

func players() -> Array:
	return get_tree().get_nodes_in_group("player")

func player(id: int):
	for node in players():
		if int(node.combatant_id) == id: return node
	return null

func snapshot() -> Dictionary:
	var observed := {}
	for node in players():
		observed[str(node.combatant_id)] = {"authority": node.get_multiplayer_authority(), "team": node.team, "name": node.display_name, "hp": node.sync_health, "weapon": node.sync_weapon_index}
	var names := {}
	for id in Net.players: names[str(id)] = Net.players[id].name
	return {"config": Game.config.duplicate(true), "names": names, "players": observed, "scores": Game.scores.keys()}

@rpc("authority", "reliable")
func request_snapshot(stage: String) -> void:
	send_snapshot.rpc_id(1, stage, snapshot())

@rpc("any_peer", "reliable")
func send_snapshot(stage: String, data: Dictionary) -> void:
	if multiplayer.get_remote_sender_id() != client_id: return
	remote = data
	remote_stage = stage

func collect(stage: String) -> bool:
	remote_stage = ""
	request_snapshot.rpc_id(client_id, stage)
	return await wait_for(func(): return remote_stage == stage)

@rpc("authority", "reliable")
func command(action: String) -> void:
	if action == "switch":
		var me = player(Net.local_id())
		if me: me.weapons.switch_to(2)
	elif action == "damage_host":
		var target = player(1)
		if target: target.hit(17.0, Net.local_id())
	elif action == "leave":
		leaving = true
		# Client fixture tears down its scene before removing its multiplayer peer.
		for world in get_tree().get_nodes_in_group("world"): world.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		Net.disconnect_net()
		await get_tree().create_timer(0.2).timeout
		finish()

func state_is(id: int, key: String, value) -> bool:
	var local = player(id)
	return local != null and local.get(key) == value

func run() -> void:
	Game.player_name = "QAHost" if role == "host" else "QAClient"
	if role == "client":
		var ok := Net.join_game("127.0.0.1", port)
		if not ok: record("N-CONNECT", false, "join initiated", false); finish(); return
		if scenario == "server-drop":
			var gone := await wait_for(func(): return disconnected, 15.0)
			record("N07", gone and Net.players.is_empty() and Net.peer == null and multiplayer.multiplayer_peer == null, "server disconnect signal clears client peer and roster", {"signal": gone, "roster": Net.players.size(), "peer_null": Net.peer == null})
			finish()
		else:
			await wait_for(func(): return leaving, 35.0)
			if not leaving:
				record("N-TIMEOUT", false, "host commanded clean leave", "deadline"); finish()
		return
	Game.config = {"mode": Game.Mode.DEATHMATCH, "map": "res://maps/arena.tscn", "mission_id": "", "bot_count": 0, "bot_skill": 1.0, "frag_limit": 77, "time_limit": 600}
	if not Net.host_game(port): record("N-HOST", false, "host created", false); finish(); return
	print("QA_HOST_READY port=", port)
	if not await wait_for(func(): return Net.players.size() == 2, 12.0):
		record("N01", false, "two connected players", Net.players.size()); finish(); return
	for id in Net.players:
		if int(id) != 1: client_id = int(id)
	if scenario == "server-drop":
		await get_tree().create_timer(0.3).timeout
		Net.disconnect_net()
		await get_tree().create_timer(0.2).timeout
		finish(); return
	var got := await collect("lobby")
	var own := snapshot()
	record("N01", got and own.names == remote.get("names", {}) and own.config == remote.get("config", {}) and remote.names.get(str(client_id)) == "QAClient", "same peer ids, names and exact config on both processes", {"host": own, "client": remote})
	Net.start_match()
	var spawned := await wait_for(func(): return players().size() == 2)
	var client_spawned := false
	for attempt in 40:
		await collect("spawn")
		if remote.get("players", {}).size() == 2: client_spawned = true; break
		await get_tree().create_timer(0.05).timeout
	own = snapshot()
	var metadata_ok := true
	for id in [1, client_id]:
		var key := str(id)
		if not own.players.has(key) or not remote.get("players", {}).has(key): metadata_ok = false; continue
		var h: Dictionary = own.players[key]; var c: Dictionary = remote.players[key]
		metadata_ok = metadata_ok and h == c and int(h.authority) == id and int(h.team) == id
	record("N02", spawned and client_spawned and metadata_ok, "two actual spawned players, matching authority/team/name/HP/weapon", {"host": own.players, "client": remote.get("players", {})})
	command.rpc_id(client_id, "switch")
	var switched := await wait_for(func(): return state_is(client_id, "sync_weapon_index", 2))
	await collect("weapon")
	record("N03", switched and remote.get("players", {}).get(str(client_id), {}).get("weapon") == 2, "client pistol switch replicated to host", {"host": snapshot().players, "client": remote.get("players", {})})
	var victim = player(client_id)
	if victim: victim.hit(24.0, 1)
	var damaged := await wait_for(func(): return state_is(client_id, "sync_health", 76.0))
	await collect("client_damage")
	record("N04", damaged and remote.get("players", {}).get(str(client_id), {}).get("hp") == 76, "host hit routes to client authority and 76 HP returns to host", {"host": snapshot().players, "client": remote.get("players", {})})
	command.rpc_id(client_id, "damage_host")
	damaged = await wait_for(func(): return state_is(1, "sync_health", 83.0))
	# Wait for replication, rather than accepting a single premature snapshot.
	var converged := false
	for attempt in 40:
		await collect("host_damage")
		if remote.get("players", {}).get("1", {}).get("hp") == 83: converged = true; break
		await get_tree().create_timer(0.05).timeout
	record("N05", damaged and converged, "client hit routes to host authority and 83 HP reaches client", {"host": snapshot().players, "client": remote.get("players", {})})
	command.rpc_id(client_id, "leave")
	var cleaned := await wait_for(func(): return Net.players.size() == 1 and players().size() == 1 and not Game.scores.has(client_id), 3.0)
	record("N06", cleaned, "departed client removed from Net roster, world and scoreboard", {"roster_count": Net.players.size(), "world_count": players().size(), "scores": Game.scores.keys(), "departed": client_id})
	finish()
