extends RefCounted
## Circuit Siege - the simulation. No rendering here: positions are in grid
## cell units (cell (x,y) spans x..x+1), so the view can scale freely and the
## smoke test can play whole campaigns headless.

const D := preload("res://scripts/data.gd")
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const TARGET_MODES := ["First", "Strong", "Close"]

var map_idx := 0
var mode := 0            # index into D.MODES
var challenge := ""      # challenge id when mode == 3
var grid: Array = []     # [y][x] -> 0 open, 1 chip, 2 wall, 3 tower
var towers := {}         # Vector2i -> tower dict
var enemies: Array = []
var born: Array = []     # enemies spawned mid-update, merged at the end
var shots: Array = []
var events: Array = []   # drained by the view (sound / particles / shake)
var spawns: Array = []   # Array of Vector2i
var exit_cell := Vector2i.ZERO
var paths: Array = []    # current A* path per spawn (Array of Vector2i arrays)
var astar := AStarGrid2D.new()

var cash := 0
var lives := 25
var wave_num := 0        # last wave started
var queue: Array = []    # pending spawns {t, type, sp, n}
var clock := 0.0
var spawn_rr := 0
var over := false
var result := ""         # "", "win", "lose"
var kills := 0
var leaks := 0
var built := 0
var next_id := 1
var sandbox_wave := 1
var wave_live := false   # any wave still spawning or alive
var boss: Dictionary = {}


func setup(p_map: int, p_mode: int, p_chal := "") -> void:
	map_idx = p_map
	mode = p_mode
	challenge = p_chal if p_mode == 3 else ""
	var m: Dictionary = D.MAPS[map_idx]
	grid = []
	spawns = []
	for y in D.ROWS:
		var row: Array = []
		var s: String = m["rows"][y]
		for x in D.COLS:
			var ch := s[x]
			row.append(1 if ch == "#" else 0)
			if ch == "S":
				spawns.append(Vector2i(x, y))
			elif ch == "E":
				exit_cell = Vector2i(x, y)
		grid.append(row)
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, D.COLS, D.ROWS)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	astar.update()
	for y in D.ROWS:
		for x in D.COLS:
			if grid[y][x] != 0:
				astar.set_point_solid(Vector2i(x, y), true)
	towers.clear()
	enemies.clear()
	born.clear()
	shots.clear()
	events.clear()
	queue.clear()
	cash = int(m["cash"])
	lives = 25
	if challenge == "glass":
		lives = 1
	if mode == 2:
		cash = 99999
		lives = 999
	wave_num = 0
	clock = 0.0
	over = false
	result = ""
	kills = 0
	leaks = 0
	built = 0
	wave_live = false
	boss = {}
	_recompute_paths()


# ------------------------------------------------------------ building

func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < D.COLS and c.y < D.ROWS


func cell_state(c: Vector2i) -> int:
	return grid[c.y][c.x] if in_bounds(c) else 1


func cost_of(t: int) -> int:
	if t < 0:
		return D.WALL_COST
	var c: int = D.TOWERS[t]["cost"]
	if challenge == "nowall":
		c = int(round(c * 0.85))
	return c


## Returns "" when placing type t (-1 = wall) at c is legal, else a reason.
func can_place(c: Vector2i, t: int) -> String:
	if not in_bounds(c):
		return "Off the board"
	if t < 0 and challenge == "nowall":
		return "Walls disabled in this challenge"
	if grid[c.y][c.x] != 0:
		return "Cell occupied"
	if c == exit_cell or spawns.has(c):
		return "Keep the ports clear"
	if cash < cost_of(t):
		return "Not enough credits"
	for e in enemies:
		if not e["fly"] and Vector2i(e["pos"].floor()) == c:
			return "Enemy in the way"
	astar.set_point_solid(c, true)
	var ok := true
	for s in spawns:
		if astar.get_id_path(s, exit_cell).is_empty():
			ok = false
			break
	if ok:
		for e in enemies:
			if not e["fly"]:
				var from := _enemy_cell(e)
				if from != c and astar.get_id_path(from, exit_cell).is_empty():
					ok = false
					break
	astar.set_point_solid(c, false)
	return "" if ok else "Can't fully block the path!"


func place(c: Vector2i, t: int) -> String:
	var why := can_place(c, t)
	if why != "":
		events.append({"t": "deny", "cell": c, "msg": why})
		return why
	var cost := cost_of(t)
	if mode != 2:
		cash -= cost
	astar.set_point_solid(c, true)
	if t < 0:
		grid[c.y][c.x] = 2
	else:
		grid[c.y][c.x] = 3
		var tw := {"type": t, "id": D.TOWERS[t]["id"], "cell": c, "lv": [0, 0, 0], "cd": 0.3,
			"ang": -PI / 2, "target": null, "spent": cost, "fresh": true, "mode": 0,
			"kills": 0, "dmg": 0.0, "ramp": 1.0, "st": {}, "syn": {}, "pop": 0.0, "flash": 0.0}
		towers[c] = tw
		built += 1
	_after_maze_change()
	events.append({"t": "build", "cell": c, "tower": t})
	return ""


func sell(c: Vector2i) -> int:
	if not in_bounds(c):
		return 0
	var st: int = grid[c.y][c.x]
	if st != 2 and st != 3:
		return 0
	var refund := 0
	if st == 2:
		refund = D.WALL_COST
	else:
		var tw: Dictionary = towers[c]
		refund = tw["spent"] if tw["fresh"] else int(tw["spent"] * 0.7)
		towers.erase(c)
	if mode != 2:
		cash += refund
	grid[c.y][c.x] = 0
	astar.set_point_solid(c, false)
	_after_maze_change()
	events.append({"t": "sell", "cell": c, "amount": refund})
	return refund


func upgrade_cost(tw: Dictionary, b: int) -> int:
	var lvl: int = tw["lv"][b]
	var base: int = D.TOWERS[tw["type"]]["cost"]
	return int(round(base * [0.6, 0.95, 1.4][min(lvl, 2)] / 5.0)) * 5


func total_levels(tw: Dictionary) -> int:
	return tw["lv"][0] + tw["lv"][1] + tw["lv"][2]


func can_upgrade(tw: Dictionary, b: int) -> String:
	if tw["lv"][b] >= 3:
		return "Branch maxed"
	if total_levels(tw) >= D.MAX_UPGRADES:
		return "Upgrade cap reached"
	if mode != 2 and cash < upgrade_cost(tw, b):
		return "Not enough credits"
	return ""


func upgrade(c: Vector2i, b: int) -> String:
	if not towers.has(c):
		return "No tower"
	var tw: Dictionary = towers[c]
	var why := can_upgrade(tw, b)
	if why != "":
		events.append({"t": "deny", "cell": c, "msg": why})
		return why
	var cost := upgrade_cost(tw, b)
	if mode != 2:
		cash -= cost
	tw["spent"] += cost
	tw["lv"][b] += 1
	tw["pop"] = 1.0
	_recompute_stats()
	events.append({"t": "upgrade", "cell": c})
	return ""


func cycle_target(c: Vector2i) -> void:
	if towers.has(c):
		towers[c]["mode"] = (towers[c]["mode"] + 1) % TARGET_MODES.size()


func _after_maze_change() -> void:
	_recompute_paths()
	for e in enemies:
		if not e["fly"]:
			_repath(e)
	_recompute_stats()


func _recompute_paths() -> void:
	paths = []
	for s in spawns:
		paths.append(astar.get_id_path(s, exit_cell))


func _enemy_cell(e: Dictionary) -> Vector2i:
	var c := Vector2i(e["pos"].floor())
	c.x = clampi(c.x, 0, D.COLS - 1)
	c.y = clampi(c.y, 0, D.ROWS - 1)
	if astar.is_point_solid(c) and e["idx"] > 0 and e["idx"] - 1 < e["path"].size():
		c = e["path"][e["idx"] - 1]
	return c


func _repath(e: Dictionary) -> void:
	var from := _enemy_cell(e)
	var p := astar.get_id_path(from, exit_cell)
	if p.is_empty():
		return
	e["path"] = p
	e["idx"] = 0
	if p.size() > 1:
		var c0 := Vector2(p[0]) + Vector2(0.5, 0.5)
		var c1 := Vector2(p[1]) + Vector2(0.5, 0.5)
		if (c1 - c0).dot(e["pos"] - c0) >= 0.0:
			e["idx"] = 1


# ------------------------------------------------------------ stats & synergy

func _base_stats(tw: Dictionary) -> Dictionary:
	var d: Dictionary = D.TOWERS[tw["type"]]
	var s := {"dmg": d["dmg"], "rate": d["rate"], "range": d["range"]}
	for k in ["chain", "stun", "burn", "splash", "slow", "pierce", "dot", "dotdur", "spread",
			"yield", "interest", "buff_dmg", "buff_rate", "reach"]:
		s[k] = float(d.get(k, 0.0))
	var mult := {}
	for b in 3:
		var lvl: int = tw["lv"][b]
		if lvl == 0:
			continue
		var mods: Dictionary = d["branches"][b]["mods"]
		for key in mods:
			if key.ends_with("%"):
				var k2: String = key.trim_suffix("%")
				mult[k2] = mult.get(k2, 0.0) + mods[key] * lvl
			else:
				s[key] += mods[key] * lvl
	for k in mult:
		s[k] *= 1.0 + mult[k]
	s["reach"] = minf(s["reach"], 2.0)
	return s


func _recompute_stats() -> void:
	for c in towers:
		towers[c]["base"] = _base_stats(towers[c])
	for c in towers:
		var tw: Dictionary = towers[c]
		var dm := 1.0
		var rm := 1.0
		var ra := 0.0
		var links := 0
		var combos: Array = []
		var flags := {}
		for dv in DIRS:
			var n: Vector2i = c + dv
			if not towers.has(n):
				continue
			var o: Dictionary = towers[n]
			links += 1
			if o["id"] != tw["id"]:
				dm += 0.06
			else:
				rm += 0.05
			for cb in D.COMBOS:
				if (cb["a"] == tw["id"] and cb["b"] == o["id"]) or (cb["b"] == tw["id"] and cb["a"] == o["id"]):
					if not combos.has(cb["name"]):
						combos.append(cb["name"])
		# relay hubs in reach (Chebyshev distance)
		if tw["id"] != "relay":
			for c2 in towers:
				var r: Dictionary = towers[c2]
				if r["id"] != "relay":
					continue
				var dist: int = max(abs(c2.x - c.x), abs(c2.y - c.y))
				if dist >= 1 and dist <= int(r["base"]["reach"]):
					dm += r["base"]["buff_dmg"]
					rm += r["base"]["buff_rate"]
					flags["relayed"] = true
		for nm in combos:
			match nm:
				"Superconductor":
					if tw["id"] == "arc":
						dm += 0.30
				"Dirty Bomb":
					flags["infect"] = true
				"Focused Array":
					ra += 0.5
				"Crossfire":
					if tw["id"] == "pulse":
						rm += 0.25
				"Overmine":
					flags["overmine"] = true
		tw["syn"] = {"dmg": dm, "rate": rm, "range": ra, "links": links, "combos": combos, "flags": flags}
		var s: Dictionary = tw["base"].duplicate()
		s["dmg"] *= dm
		s["dot"] *= dm
		s["rate"] *= rm
		s["range"] += ra
		if flags.has("overmine"):
			s["yield"] *= 1.5
		tw["st"] = s


# ------------------------------------------------------------ waves

func can_start_wave() -> bool:
	if over:
		return false
	if mode == 2:
		return true
	if mode == 1:
		return true
	return wave_num < D.CAMPAIGN_WAVES


func start_wave() -> void:
	if not can_start_wave():
		return
	var n := wave_num + 1
	if mode == 2:
		n = sandbox_wave
	if wave_live and mode != 2:
		var bonus := 5 + wave_num
		cash += bonus
		events.append({"t": "money", "pos": Vector2(exit_cell) + Vector2(0.5, 0.5), "amount": bonus})
	wave_num = n if mode != 2 else max(wave_num, n)
	if mode == 2:
		sandbox_wave = mini(sandbox_wave + 1, 99)
	for tw in towers.values():
		tw["fresh"] = false
	var base_t := clock
	if not queue.is_empty():
		base_t = maxf(clock, queue[queue.size() - 1]["t"] + 1.0)
	for gr in D.wave(n):
		for i in gr["count"]:
			queue.append({"t": base_t + gr["delay"] + i * gr["gap"], "type": gr["type"], "sp": spawn_rr, "n": n})
			spawn_rr = (spawn_rr + 1) % max(1, spawns.size())
	queue.sort_custom(func(a, b): return a["t"] < b["t"])
	wave_live = true
	events.append({"t": "wave", "n": n, "boss": n % 10 == 0})


func _spawn(type: String, sp: int, n: int, at: Dictionary = {}) -> Dictionary:
	var d: Dictionary = D.ENEMIES[type]
	var hp: float = d["hp"]
	var sh: float = d.get("shield", 0.0)
	if d.get("boss", false):
		var k: float = maxf(1.0, D.hp_scale(n) / D.hp_scale(30)) if n > 30 else 1.0
		hp *= k
		sh *= k
	else:
		var sc := D.hp_scale(n)
		hp *= sc
		sh *= sc
	var armor: float = d.get("armor", 0.0) + floorf(n / 12.0) * (1.0 if d.has("armor") else 0.0)
	var spd: float = d["spd"]
	if challenge == "iron":
		armor += 3.0
		hp *= 1.2
	if challenge == "rush":
		spd *= 1.35
	var e := {"type": type, "id": next_id, "hp": hp, "maxhp": hp, "shield": sh, "maxshield": sh, "armor": armor,
		"spd": spd, "fly": d.get("fly", false), "alive": true, "slow": 0.0, "slow_t": 0.0, "stun_t": 0.0,
		"dot": 0.0, "dot_t": 0.0, "spread": 0.0, "burn": 0.0, "burn_t": 0.0, "blink_t": d.get("blink", 0.0),
		"heal_t": d.get("heal", 0.0), "spawn_t": d.get("spawn_t", 0.0), "quiet": 0.0, "boss": d.get("boss", false),
		"flash": 0.0, "rew": d["rew"], "n": n, "path": [], "idx": 0, "pos": Vector2.ZERO, "wob": randf() * TAU}
	next_id += 1
	if at.is_empty():
		var s: Vector2i = spawns[sp % spawns.size()]
		e["pos"] = Vector2(s) + Vector2(0.5, 0.5)
		if not e["fly"]:
			e["path"] = paths[sp % paths.size()]
			e["idx"] = 1
	else:
		e["pos"] = at["pos"] + Vector2(randf_range(-0.15, 0.15), randf_range(-0.15, 0.15))
		e["path"] = at["path"]
		e["idx"] = at["idx"]
	born.append(e)
	if e["boss"]:
		boss = e
		events.append({"t": "boss", "name": d["name"]})
	return e


func progress(e: Dictionary) -> float:
	# lower = closer to the core
	if e["fly"]:
		return e["pos"].distance_to(Vector2(exit_cell) + Vector2(0.5, 0.5))
	var rem: float = e["path"].size() - e["idx"]
	if e["idx"] < e["path"].size():
		rem += e["pos"].distance_to(Vector2(e["path"][e["idx"]]) + Vector2(0.5, 0.5))
	return rem


# ------------------------------------------------------------ update

func update(dt: float) -> void:
	if over:
		return
	clock += dt
	while not queue.is_empty() and queue[0]["t"] <= clock:
		var q: Dictionary = queue.pop_front()
		_spawn(q["type"], q["sp"], q["n"])
	_update_enemies(dt)
	_update_towers(dt)
	_update_shots(dt)
	enemies.append_array(born)
	born.clear()
	enemies = enemies.filter(func(e): return e["alive"])
	if not boss.is_empty() and not boss["alive"]:
		boss = {}
	if wave_live and queue.is_empty() and enemies.is_empty():
		_wave_cleared()


func _wave_cleared() -> void:
	wave_live = false
	if mode == 2:
		events.append({"t": "clear", "n": wave_num, "bonus": 0})
		return
	var bonus := 20 + wave_num * 3
	for tw in towers.values():
		if tw["id"] == "miner":
			bonus += int(tw["st"]["yield"])
			bonus += int(min(cash * tw["st"]["interest"], 150.0))
	cash += bonus
	events.append({"t": "clear", "n": wave_num, "bonus": bonus})
	if (mode == 0 or mode == 3) and wave_num >= D.CAMPAIGN_WAVES:
		over = true
		result = "win"
		events.append({"t": "win"})


func stars() -> int:
	if result != "win":
		return 0
	if challenge == "glass" or lives >= 20:
		return 3
	return 2 if lives >= 10 else 1


func _update_enemies(dt: float) -> void:
	var core := Vector2(exit_cell) + Vector2(0.5, 0.5)
	for e in enemies:
		if not e["alive"]:
			continue
		e["flash"] = maxf(0.0, e["flash"] - dt * 5.0)
		e["wob"] += dt * 4.0
		e["quiet"] += dt
		# status effects
		if e["slow_t"] > 0.0:
			e["slow_t"] -= dt
			if e["slow_t"] <= 0.0:
				e["slow"] = 0.0
		if e["dot_t"] > 0.0:
			e["dot_t"] -= dt
			_hurt(e, e["dot"] * dt, null, true, 1.0, false)
			if not e["alive"]:
				continue
		if e["burn_t"] > 0.0:
			e["burn_t"] -= dt
			_hurt(e, e["burn"] * dt, null, true, 1.0, false)
			if not e["alive"]:
				continue
		if e["maxshield"] > 0.0 and e["quiet"] > 2.5 and e["shield"] < e["maxshield"]:
			e["shield"] = minf(e["maxshield"], e["shield"] + e["maxshield"] * 0.12 * dt)
		var d: Dictionary = D.ENEMIES[e["type"]]
		if d.has("heal"):
			e["heal_t"] -= dt
			if e["heal_t"] <= 0.0:
				e["heal_t"] = d["heal"]
				for o in enemies:
					if o["alive"] and o["pos"].distance_to(e["pos"]) < 1.7:
						o["hp"] = minf(o["maxhp"], o["hp"] + o["maxhp"] * (0.04 if o["boss"] else 0.12))
				events.append({"t": "heal", "pos": e["pos"]})
		if d.has("spawn"):
			e["spawn_t"] -= dt
			if e["spawn_t"] <= 0.0:
				e["spawn_t"] = d["spawn_t"]
				_spawn(d["spawn"], 0, e["n"], e)
		if d.has("blink") and not e["fly"]:
			e["blink_t"] -= dt
			if e["blink_t"] <= 0.0 and e["stun_t"] <= 0.0:
				e["blink_t"] = d["blink"]
				var jump := mini(e["idx"] + 3, e["path"].size() - 1)
				if jump > e["idx"]:
					var from: Vector2 = e["pos"]
					e["idx"] = jump
					e["pos"] = Vector2(e["path"][jump - 1]) + Vector2(0.5, 0.5)
					events.append({"t": "blink", "from": from, "to": e["pos"], "col": d["col"]})
		# movement
		if e["stun_t"] > 0.0:
			e["stun_t"] -= dt
			continue
		var mv: float = e["spd"] * (1.0 - e["slow"]) * dt
		if e["fly"]:
			var to: Vector2 = core - e["pos"]
			if to.length() <= mv:
				_leak(e)
			else:
				e["pos"] += to.normalized() * mv
			continue
		while mv > 0.0 and e["idx"] < e["path"].size():
			var tgt := Vector2(e["path"][e["idx"]]) + Vector2(0.5, 0.5)
			var v: Vector2 = tgt - e["pos"]
			var dist := v.length()
			if dist <= mv:
				e["pos"] = tgt
				mv -= dist
				e["idx"] += 1
			else:
				e["pos"] += v / dist * mv
				mv = 0.0
		if e["idx"] >= e["path"].size():
			_leak(e)


func _leak(e: Dictionary) -> void:
	e["alive"] = false
	var dmg := 10 if e["boss"] else 1
	leaks += 1
	if mode != 2:
		lives -= dmg
	events.append({"t": "leak", "pos": e["pos"], "dmg": dmg})
	if lives <= 0 and not over:
		lives = 0
		over = true
		result = "lose"
		events.append({"t": "lose"})


## amount of damage; tw = source tower (or null); pierce ignores armor;
## smult multiplies damage against shields.
func _hurt(e: Dictionary, amount: float, tw, pierce: bool, smult: float, show := true) -> void:
	if not e["alive"] or amount <= 0.0:
		return
	var a := amount
	if e["shield"] > 0.0:
		var sd := a * smult
		if sd <= e["shield"]:
			e["shield"] -= sd
			a = 0.0
		else:
			a = (sd - e["shield"]) / smult
			e["shield"] = 0.0
			events.append({"t": "shieldbreak", "pos": e["pos"]})
	if a > 0.0 and not pierce and e["armor"] > 0.0:
		a = maxf(a * 0.2, a - e["armor"])
	e["hp"] -= a
	e["quiet"] = 0.0
	if show:
		e["flash"] = 1.0
	if tw != null:
		tw["dmg"] += amount
	if e["hp"] <= 0.0:
		_kill(e, tw)


func _kill(e: Dictionary, tw) -> void:
	e["alive"] = false
	kills += 1
	var rew: int = e["rew"]
	if challenge == "rush":
		rew *= 2
	if mode != 2:
		cash += rew
	if tw != null:
		tw["kills"] += 1
	var d: Dictionary = D.ENEMIES[e["type"]]
	events.append({"t": "kill", "pos": e["pos"], "col": d["col"], "boss": e["boss"], "rew": rew, "fly": e["fly"]})
	if d.has("split"):
		for i in d["split"]:
			_spawn("splitlet", 0, e["n"], e)
	if e["dot_t"] > 0.0 and e["spread"] > 0.0:
		for o in enemies:
			if o["alive"] and not is_same(o, e) and o["pos"].distance_to(e["pos"]) <= e["spread"] + 0.3:
				o["dot"] = maxf(o["dot"], e["dot"])
				o["dot_t"] = maxf(o["dot_t"], 2.0)
				o["spread"] = e["spread"]
		events.append({"t": "spread", "pos": e["pos"], "r": e["spread"] + 0.3})


func _can_hit(tw: Dictionary, e: Dictionary) -> bool:
	var d: Dictionary = D.TOWERS[tw["type"]]
	return d["air"] if e["fly"] else d["ground"]


func _pick_target(tw: Dictionary, center: Vector2, rng: float):
	var best = null
	var bv := INF
	for e in enemies:
		if not e["alive"] or not _can_hit(tw, e):
			continue
		var dist: float = e["pos"].distance_to(center)
		if dist > rng:
			continue
		var v := 0.0
		match tw["mode"]:
			0: v = progress(e)
			1: v = -(e["hp"] + e["shield"])
			_: v = dist
		if v < bv:
			bv = v
			best = e
	return best


func _update_towers(dt: float) -> void:
	for c in towers:
		var tw: Dictionary = towers[c]
		var s: Dictionary = tw["st"]
		tw["pop"] = maxf(0.0, tw["pop"] - dt * 3.0)
		tw["flash"] = maxf(0.0, tw["flash"] - dt * 6.0)
		var center := Vector2(c) + Vector2(0.5, 0.5)
		var kind: String = D.TOWERS[tw["type"]]["kind"]
		tw["cd"] -= dt
		if kind == "relay":
			continue
		if kind == "miner" and s["dmg"] <= 0.0:
			continue
		if kind == "aura":
			if tw["cd"] <= 0.0:
				var hit := false
				for e in enemies:
					if e["alive"] and e["pos"].distance_to(center) <= s["range"]:
						var sl: float = minf(0.75, s["slow"]) * (0.5 if e["boss"] else 1.0)
						e["slow"] = maxf(e["slow"], sl)
						e["slow_t"] = 0.8
						_hurt(e, s["dmg"], tw, false, 1.0, false)
						hit = true
				if hit:
					tw["cd"] = 1.0 / s["rate"]
					tw["flash"] = 1.0
					events.append({"t": "aura", "pos": center, "r": s["range"], "col": D.TOWERS[tw["type"]]["col"]})
			continue
		if kind == "beam":
			var bt = tw["target"]
			if bt == null or not bt["alive"] or bt["pos"].distance_to(center) > s["range"]:
				bt = _pick_target(tw, center, s["range"])
				tw["ramp"] = 1.0
				tw["target"] = bt
			if bt != null:
				tw["ramp"] = minf(2.5, tw["ramp"] + dt * 0.6)
				tw["ang"] = (bt["pos"] - center).angle()
				_hurt(bt, s["dmg"] * tw["ramp"] * dt, tw, true, 1.0, false)
				bt["flash"] = maxf(bt["flash"], 0.4)
				if s["burn"] > 0.0:
					bt["burn"] = maxf(bt["burn"], s["burn"] * (s["dmg"] / 16.0))
					bt["burn_t"] = 2.0
			continue
		if tw["cd"] > 0.0:
			continue
		var t = _pick_target(tw, center, s["range"])
		tw["target"] = t
		if t == null:
			continue
		tw["cd"] = 1.0 / maxf(0.05, s["rate"])
		tw["ang"] = (t["pos"] - center).angle()
		tw["flash"] = 1.0
		var col: Color = D.TOWERS[tw["type"]]["col"]
		match kind:
			"bullet", "virus", "flak":
				shots.append({"pos": center, "target": t, "spd": 9.0, "dmg": s["dmg"], "kind": kind, "tw": tw, "col": col,
					"splash": s["splash"], "dot": s["dot"], "dotdur": s["dotdur"], "spread": s["spread"], "life": 2.0})
				events.append({"t": "fire", "kind": kind})
			"splash":
				shots.append({"pos": center, "from": center, "dest": t["pos"], "target": null, "spd": 0.0, "dmg": s["dmg"],
					"kind": "bomb", "tw": tw, "col": col, "splash": s["splash"], "life": 0.55, "dur": 0.55,
					"infect": tw["syn"]["flags"].has("infect")})
				events.append({"t": "fire", "kind": "bomb"})
			"chain", "miner":
				var pts: Array = [center]
				var hitlist: Array = []
				var cur = t
				var dmg: float = s["dmg"]
				var jumps: int = int(s["chain"]) + 1
				for j in jumps:
					if cur == null:
						break
					hitlist.append(cur["id"])
					pts.append(cur["pos"])
					_hurt(cur, dmg, tw, false, 2.0 if kind == "chain" else 1.0)
					if s["stun"] > 0.0 and randf() < s["stun"]:
						cur["stun_t"] = 0.15 if cur["boss"] else 0.6
					dmg *= 0.8
					var nxt = null
					var nd := 1.8
					for o in enemies:
						if o["alive"] and not hitlist.has(o["id"]) and _can_hit(tw, o):
							var dd: float = o["pos"].distance_to(cur["pos"])
							if dd < nd:
								nd = dd
								nxt = o
					cur = nxt
				events.append({"t": "chain", "pts": pts, "col": col, "kind": kind})
			"rail":
				var dir: Vector2 = (t["pos"] - center).normalized()
				var end: Vector2 = center + dir * float(s["range"])
				var hits: Array = []
				for e in enemies:
					if not e["alive"] or not _can_hit(tw, e):
						continue
					var rel: Vector2 = e["pos"] - center
					var along := rel.dot(dir)
					if along < 0.0 or along > s["range"]:
						continue
					if absf(rel.cross(dir)) < 0.42:
						hits.append([along, e])
				hits.sort_custom(func(a, b): return a[0] < b[0])
				var n := 0
				for h in hits:
					if n >= int(s["pierce"]):
						break
					_hurt(h[1], s["dmg"], tw, false, 1.0)
					n += 1
				events.append({"t": "rail", "from": center, "to": end, "col": col})


func _update_shots(dt: float) -> void:
	var keep: Array = []
	for p in shots:
		p["life"] -= dt
		if p["kind"] == "bomb":
			var k: float = 1.0 - p["life"] / p["dur"]
			p["pos"] = p["from"].lerp(p["dest"], clampf(k, 0.0, 1.0))
			if p["life"] <= 0.0:
				for e in enemies:
					if e["alive"] and not e["fly"] and e["pos"].distance_to(p["dest"]) <= p["splash"]:
						_hurt(e, p["dmg"], p["tw"], false, 1.0)
						if p["infect"]:
							e["dot"] = maxf(e["dot"], p["dmg"] * 0.3)
							e["dot_t"] = 2.5
				events.append({"t": "boom", "pos": p["dest"], "r": p["splash"], "col": p["col"]})
			else:
				keep.append(p)
			continue
		var t = p["target"]
		if t == null or not t["alive"] or p["life"] <= 0.0:
			continue
		var v: Vector2 = t["pos"] - p["pos"]
		var step: float = p["spd"] * dt
		if v.length() <= step + 0.1:
			match p["kind"]:
				"flak":
					for e in enemies:
						if e["alive"] and e["fly"] and e["pos"].distance_to(t["pos"]) <= p["splash"]:
							_hurt(e, p["dmg"], p["tw"], false, 1.0)
					events.append({"t": "boom", "pos": t["pos"], "r": p["splash"], "col": p["col"], "small": true})
				"virus":
					_hurt(t, p["dmg"], p["tw"], false, 1.0)
					if t["alive"]:
						t["dot"] = maxf(t["dot"], p["dot"])
						t["dot_t"] = maxf(t["dot_t"], p["dotdur"])
						t["spread"] = maxf(t["spread"], p["spread"])
				_:
					_hurt(t, p["dmg"], p["tw"], false, 1.0)
			events.append({"t": "hit", "pos": t["pos"], "col": p["col"]})
		else:
			p["pos"] += v.normalized() * step
			keep.append(p)
	shots = keep
