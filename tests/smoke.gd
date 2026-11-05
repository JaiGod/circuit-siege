extends Node
## Headless smoke test: a greedy bot mazes + builds + upgrades and plays every
## board in every mode, then the real Main scene is driven through its menus.
## Prints "SMOKE OK" when everything passed.

const D := preload("res://scripts/data.gd")
const Sim := preload("res://scripts/sim.gd")
var fails := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		fails += 1
		print("FAIL: ", msg)


func path_len(s: Sim) -> int:
	var n := 0
	for p in s.paths:
		n += p.size()
	return n


func bot_build(s: Sim, rng: RandomNumberGenerator) -> void:
	# 1) walls that lengthen the path most (keep a reserve for towers)
	var reserve := 60 + s.wave_num * 6
	var guard := 0
	while s.challenge != "nowall" and s.cash > reserve + D.WALL_COST and guard < 30:
		guard += 1
		var best := Vector2i(-1, -1)
		var bl := path_len(s)
		for y in D.ROWS:
			for x in D.COLS:
				var c := Vector2i(x, y)
				if s.cell_state(c) != 0 or s.can_place(c, -1) != "":
					continue
				s.astar.set_point_solid(c, true)
				var l := 0
				for sp in s.spawns:
					l += s.astar.get_id_path(sp, s.exit_cell).size()
				s.astar.set_point_solid(c, false)
				if l > bl:
					bl = l
					best = c
		if best.x < 0:
			break
		s.place(best, -1)
	# 2) towers next to the path, weighted by path coverage
	var picks := ["pulse", "arc", "laser", "bomb", "cryo", "rail", "flak", "virus", "miner", "relay"]
	guard = 0
	while guard < 12:
		guard += 1
		var good := ["pulse", "arc", "laser", "bomb", "cryo", "rail", "virus", "laser", "bomb", "rail"]
		var want: String = good[rng.randi_range(0, good.size() - 1)] if s.wave_num > 2 else "pulse"
		if s.wave_num >= 5 and rng.randf() < 0.25:
			want = "flak"
		var ti := D.tower_index(want)
		if s.cash < s.cost_of(ti):
			break
		var best := Vector2i(-1, -1)
		var bscore := 0
		var rng_c: float = D.TOWERS[ti]["range"]
		for y in D.ROWS:
			for x in D.COLS:
				var c := Vector2i(x, y)
				if s.cell_state(c) != 0:
					continue
				var score := 0
				for p in s.paths:
					for pc in p:
						if Vector2(pc).distance_to(Vector2(c)) <= rng_c:
							score += 1
				if score > bscore and s.can_place(c, ti) == "":
					bscore = score
					best = c
		if best.x < 0:
			break
		s.place(best, ti)
	# 3) upgrades
	for c in s.towers:
		var tw: Dictionary = s.towers[c]
		var b := rng.randi_range(0, 2)
		if s.can_upgrade(tw, b) == "" and s.cash > s.upgrade_cost(tw, b) + 40:
			s.upgrade(c, b)


func play(map_i: int, mode: int, chal: String, max_wave: int) -> Sim:
	var s := Sim.new()
	s.setup(map_i, mode, chal)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99 + map_i
	check(s.paths.size() == s.spawns.size() and not s.paths[0].is_empty(), "map %d has a path" % map_i)
	var steps := 0
	while not s.over and s.wave_num < max_wave and steps < 400000:
		if not s.wave_live:
			bot_build(s, rng)
			if mode == 2:
				s.sandbox_wave = s.wave_num + 1
			s.start_wave()
		s.update(0.05)
		s.events.clear()
		steps += 1
		# a wall mid-wave must never break the path or strand anyone
		if steps % 400 == 0 and s.challenge != "nowall":
			var c := Vector2i(rng.randi_range(0, D.COLS - 1), rng.randi_range(0, D.ROWS - 1))
			if s.can_place(c, -1) == "":
				s.place(c, -1)
			for p in s.paths:
				check(not p.is_empty(), "path stays open")
	# let the last wave finish
	var extra := 0
	while s.wave_live and not s.over and extra < 40000:
		s.update(0.05)
		s.events.clear()
		extra += 1
	check(steps < 400000, "map %d mode %d finished in time" % [map_i, mode])
	return s


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	# full-block rule
	var s := Sim.new()
	s.setup(0, 0)
	s.cash = 9999
	for y in D.ROWS:
		if y != 5:
			s.place(Vector2i(8, y), -1)
	check(s.can_place(Vector2i(8, 5), -1) != "", "cannot fully block")
	check(s.paths[0].size() > 0, "path exists after wall line")
	check(s.place(Vector2i(0, 5), 0) != "", "spawn cell protected")
	# upgrades + cap + sell
	var tc := Vector2i(3, 3)
	check(s.place(tc, D.tower_index("pulse")) == "", "place pulse")
	for i in 3:
		s.upgrade(tc, 0)
	for i in 3:
		s.upgrade(tc, 1)
	check(s.upgrade(tc, 2) != "", "upgrade cap enforced")
	check(s.total_levels(s.towers[tc]) == 6, "6 levels")
	s.place(tc + Vector2i(1, 0), D.tower_index("relay"))
	check(s.towers[tc]["syn"]["dmg"] > 1.1, "relay + link synergy")
	s.place(Vector2i(5, 8), D.tower_index("arc"))
	s.place(Vector2i(6, 8), D.tower_index("cryo"))
	check(s.towers[Vector2i(5, 8)]["syn"]["combos"].has("Superconductor"), "combo detected")
	var before := s.cash
	s.sell(tc)
	check(s.cash > before, "sell refunds")
	# every wave defines enemies; every enemy type valid
	for n in range(1, 61):
		var w := D.wave(n)
		check(w.size() > 0, "wave %d not empty" % n)
		for g in w:
			check(D.ENEMIES.has(g["type"]), "enemy type %s" % g["type"])
	# bot plays every board
	var summary: Array = []
	for m in D.MAPS.size():
		var r := play(m, 0, "", 30)
		summary.append("%s: %s wave %d lives %d kills %d" % [D.MAPS[m]["name"], r.result if r.result != "" else "-", r.wave_num, r.lives, r.kills])
	var e := play(0, 1, "", 34)
	summary.append("Endless: wave %d lives %d" % [e.wave_num, e.lives])
	var sb := play(1, 2, "", 12)
	summary.append("Sandbox: wave %d lives %d" % [sb.wave_num, sb.lives])
	for ch in D.CHALLENGES:
		var r2 := play(2, 3, ch["id"], 12)
		summary.append("Challenge %s: wave %d lives %d %s" % [ch["id"], r2.wave_num, r2.lives, r2.result])
	for l in summary:
		print("  ", l)
	print("sim time: %d ms" % (Time.get_ticks_msec() - t0))
	# drive the real scene
	await get_tree().process_frame
	var main: Node = load("res://main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	main.action("play")
	main.action("mode3")
	main.action("chal1")
	main.action("map4")
	main.action("start")
	check(main.state == "play" and main.sim.challenge == "nowall", "challenge started")
	main.action("mode0")
	main.sel_mode = 0
	main.action("start")
	main.action("build0")
	main.sim.place(Vector2i(4, 4), 0)
	main.sel_cell = Vector2i(4, 4)
	main.action("up0")
	main.action("target")
	main.action("speed")
	main.action("speed")
	main.action("wave")
	for i in 240:
		await get_tree().process_frame
	check(main.sim.wave_num == 1, "wave started from UI")
	main.action("pause")
	await get_tree().process_frame
	main.action("resume")
	main.action("sell")
	main.sim.lives = 1
	main.sim._leak({"boss": false, "alive": true, "pos": Vector2.ZERO})
	for i in 10:
		await get_tree().process_frame
	check(main.sim.over and main.sim.result == "lose", "lose state")
	main.action("restart")
	check(not main.sim.over, "restart works")
	main.action("menu")
	main.action("howto")
	await get_tree().process_frame
	main.action("back")
	await get_tree().process_frame
	print("draws ok, total %d ms" % (Time.get_ticks_msec() - t0))
	if fails == 0:
		print("SMOKE OK")
	else:
		print("SMOKE FAILED: %d" % fails)
	get_tree().quit(0 if fails == 0 else 1)
