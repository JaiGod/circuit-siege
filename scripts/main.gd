extends Node2D
## Circuit Siege - view, input and menus. Everything is drawn in code with
## _draw(): neon circuit-board art, immediate-mode buttons, particles.

const D := preload("res://scripts/data.gd")
const Sim := preload("res://scripts/sim.gd")
const Sfx := preload("res://scripts/sfx.gd")
const Art := preload("res://scripts/art.gd")
const SAVE_PATH := "user://circuit_siege.json"

const C_BG := Color("050a12")
const C_PCB := Color("071a1f")
const C_TRACE := Color("0f3b3a")
const C_INK := Color("e6fbff")
const C_DIM := Color("7fa6b3")
const C_CYAN := Color("27f3ff")
const C_MAG := Color("ff3df0")
const C_GOLD := Color("ffcf33")
const C_RED := Color("ff4d6d")
const C_GREEN := Color("39ff88")

var sim: Sim
var sfx: Sfx
var art: Art
var font: Font
var state := "title"          # title, select, howto, play
var paused := false
var speed := 1
var sel_build := 0            # -1 wall, 0..9 tower, -2 nothing
var sel_cell := Vector2i(-1, -1)
var hover := Vector2i(-1, -1)
var hover_ok := ""
var mouse := Vector2.ZERO
var dragging := false
var drag_cell := Vector2i(-1, -1)
var buttons: Array = []
var t := 0.0
var shake := 0.0
var toast := ""
var toast_t := 0.0
var banner := ""
var banner_sub := ""
var banner_t := 0.0
var core_flash := 0.0
var particles: Array = []
var rings: Array = []
var bolts: Array = []
var floats: Array = []
var traces: Array = []        # procedural background traces (cell units)
var portrait := false
var origin := Vector2.ZERO
var cell := 48.0
var panel := Rect2()
var vs := Vector2(1280, 720)
var sel_mode := 0
var sel_map := 0
var sel_chal := 0
var save := {"sound": true, "best": {}, "stars": {}}
var result_shown := false
var audio_started := false


func _ready() -> void:
	font = ThemeDB.fallback_font
	sfx = Sfx.new()
	add_child(sfx)
	art = Art.new()
	art.host = self
	_load()
	sfx.enabled = save["sound"]
	get_tree().root.size_changed.connect(_on_resize)
	_on_resize()
	sim = Sim.new()
	sim.setup(0, 0)
	_make_traces(0)


func _on_resize() -> void:
	var w := get_tree().root.size
	var want := Vector2i(540, 960) if w.y > w.x * 1.05 else Vector2i(1280, 720)
	if get_tree().root.content_scale_size != want:
		get_tree().root.content_scale_size = want


# ------------------------------------------------------------ save

func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if data is Dictionary:
		for k in ["sound", "best", "stars"]:
			if data.has(k):
				save[k] = data[k]


func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(save))


func _key(m: int, mo: int, ch: String) -> String:
	return "%d_%d_%s" % [m, mo, ch]


func _record() -> void:
	var k := _key(sim.map_idx, sim.mode, sim.challenge)
	if sim.mode == 2:
		return
	if sim.wave_num > int(save["best"].get(k, 0)):
		save["best"][k] = sim.wave_num
	if sim.stars() > int(save["stars"].get(k, 0)):
		save["stars"][k] = sim.stars()
	_save()


# ------------------------------------------------------------ game flow

func start_game() -> void:
	sim = Sim.new()
	var ch := ""
	if sel_mode == 3:
		ch = D.CHALLENGES[sel_chal]["id"]
	sim.setup(sel_map, sel_mode, ch)
	_make_traces(sel_map)
	state = "play"
	paused = false
	speed = 1
	sel_build = 0
	sel_cell = Vector2i(-1, -1)
	particles.clear()
	rings.clear()
	bolts.clear()
	floats.clear()
	result_shown = false
	_banner(D.MAPS[sel_map]["name"].to_upper(), D.MODES[sel_mode] + ("" if ch == "" else " - " + D.CHALLENGES[sel_chal]["name"]))


func _make_traces(m: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242 + m * 97
	traces.clear()
	for i in 34:
		var p := Vector2(rng.randi_range(0, D.COLS), rng.randi_range(0, D.ROWS)) + Vector2(0.5, 0.5) * float(rng.randi_range(0, 1))
		var pts := PackedVector2Array([p])
		var dir := Vector2([1, -1][rng.randi_range(0, 1)], 0) if rng.randf() < 0.5 else Vector2(0, [1, -1][rng.randi_range(0, 1)])
		for s in rng.randi_range(2, 4):
			var ln := rng.randf_range(1.0, 4.0)
			p += dir * ln
			pts.append(p)
			if rng.randf() < 0.7:
				var nd := dir.rotated(PI / 4 * [1, -1][rng.randi_range(0, 1)])
				dir = nd.normalized()
				if absf(dir.x) > 0.1 and absf(dir.y) > 0.1:
					dir = Vector2(signf(dir.x), signf(dir.y))
		traces.append(pts)


func action(id: String) -> void:
	if not audio_started:
		audio_started = true
		sfx.set_enabled(save["sound"])
	sfx.play("click", 0.02)
	match id:
		"play":
			state = "select"
		"howto":
			state = "howto"
		"back":
			state = "title"
		"sound":
			save["sound"] = not save["sound"]
			sfx.set_enabled(save["sound"])
			_save()
		"start":
			start_game()
		"pause":
			paused = not paused
		"resume":
			paused = false
		"restart":
			start_game()
		"menu":
			if state == "play":
				_record()
			state = "select"
			paused = false
		"speed":
			speed = speed % 3 + 1
		"wave":
			sim.start_wave()
		"sell":
			if sel_cell.x >= 0:
				sim.sell(sel_cell)
				sel_cell = Vector2i(-1, -1)
		"target":
			sim.cycle_target(sel_cell)
		"swave-":
			sim.sandbox_wave = maxi(1, sim.sandbox_wave - 1)
		"swave+":
			sim.sandbox_wave = mini(99, sim.sandbox_wave + 1)
		"endless":
			sel_mode = 1
			start_game()
		_:
			if id.begins_with("mode"):
				sel_mode = int(id.substr(4))
			elif id.begins_with("map"):
				sel_map = int(id.substr(3))
			elif id.begins_with("chal"):
				sel_chal = int(id.substr(4))
			elif id.begins_with("build"):
				var b := int(id.substr(5))
				sel_build = -2 if sel_build == b else b
				sel_cell = Vector2i(-1, -1)
			elif id.begins_with("up"):
				sim.upgrade(sel_cell, int(id.substr(2)))


func _banner(a: String, b := "") -> void:
	banner = a
	banner_sub = b
	banner_t = 2.2


func _toast(s: String) -> void:
	toast = s
	toast_t = 1.8


# ------------------------------------------------------------ loop

func _process(delta: float) -> void:
	t += delta
	var dt := minf(delta, 0.05)
	vs = get_viewport_rect().size
	_layout()
	if state == "play" and not paused:
		for i in speed:
			sim.update(dt)
		_handle_events()
		if sim.over and not result_shown:
			result_shown = true
			_record()
	_update_fx(dt * (speed if state == "play" and not paused else 1))
	shake = maxf(0.0, shake - delta * 30.0)
	toast_t -= delta
	banner_t -= delta
	core_flash = maxf(0.0, core_flash - delta * 2.0)
	queue_redraw()


func _layout() -> void:
	portrait = vs.y > vs.x
	var top := 64.0
	if portrait:
		cell = floorf(minf((vs.x - 16.0) / D.COLS, (vs.y * 0.42) / D.ROWS))
		origin = Vector2(floorf((vs.x - cell * D.COLS) / 2.0), top + 30.0)
		var py := origin.y + cell * D.ROWS + 10.0
		panel = Rect2(8, py, vs.x - 16, vs.y - py - 8)
	else:
		var pw := 340.0
		var aw := vs.x - pw - 24.0
		var ah := vs.y - top - 40.0
		cell = floorf(minf(aw / D.COLS, ah / D.ROWS))
		origin = Vector2(floorf(12 + (aw - cell * D.COLS) / 2.0), top + 30.0 + floorf((ah - cell * D.ROWS) / 2.0))
		panel = Rect2(vs.x - pw - 8, top + 4, pw, vs.y - top - 12)


func to_px(p: Vector2) -> Vector2:
	return origin + p * cell


func to_cell(px: Vector2) -> Vector2i:
	var c := (px - origin) / cell
	return Vector2i(int(floor(c.x)), int(floor(c.y)))


func _handle_events() -> void:
	for ev in sim.events:
		match ev["t"]:
			"fire":
				sfx.play(ev["kind"] if ev["kind"] != "bomb" else "bomb", 0.12, 0.06)
			"hit":
				_sparks(ev["pos"], ev["col"], 3, 1.5)
			"kill":
				_sparks(ev["pos"], ev["col"], 16 if not ev["boss"] else 70, 3.0 if not ev["boss"] else 6.0)
				rings.append({"p": ev["pos"], "r0": 0.1, "r1": 0.7 if not ev["boss"] else 3.0, "life": 0.35, "max": 0.35, "col": ev["col"]})
				if sim.mode != 2:
					floats.append({"p": ev["pos"], "s": "+%d" % ev["rew"], "life": 0.8, "col": C_GOLD})
				if ev["boss"]:
					shake = 18.0
					sfx.play("bossdie", 0.0)
					_banner("BOSS DELETED", "+%d credits" % ev["rew"])
				else:
					sfx.play("kill", 0.2, 0.04)
			"leak":
				shake = maxf(shake, 7.0 * ev["dmg"] / 2.0 + 4.0)
				core_flash = 1.0
				sfx.play("leak", 0.05, 0.1)
				floats.append({"p": Vector2(sim.exit_cell) + Vector2(0.5, 0.0), "s": "-%d CORE" % ev["dmg"], "life": 1.0, "col": C_RED})
			"chain":
				bolts.append({"pts": ev["pts"], "life": 0.16, "max": 0.16, "col": ev["col"], "jag": true})
				sfx.play("zap", 0.15, 0.06)
			"rail":
				bolts.append({"pts": [ev["from"], ev["to"]], "life": 0.25, "max": 0.25, "col": ev["col"], "jag": false})
				shake = maxf(shake, 3.0)
				sfx.play("rail", 0.08, 0.05)
			"boom":
				rings.append({"p": ev["pos"], "r0": 0.1, "r1": ev["r"], "life": 0.3, "max": 0.3, "col": ev["col"]})
				_sparks(ev["pos"], ev["col"], 6 if ev.get("small", false) else 12, 2.5)
				if not ev.get("small", false):
					shake = maxf(shake, 2.5)
					sfx.play("boom", 0.15, 0.06)
				else:
					sfx.play("flak", 0.2, 0.05)
			"aura":
				rings.append({"p": ev["pos"], "r0": 0.3, "r1": ev["r"], "life": 0.45, "max": 0.45, "col": ev["col"]})
			"blink":
				_sparks(ev["from"], ev["col"], 8, 2.0)
				_sparks(ev["to"], ev["col"], 8, 2.0)
				sfx.play("blink", 0.1, 0.08)
			"heal":
				rings.append({"p": ev["pos"], "r0": 0.2, "r1": 1.7, "life": 0.5, "max": 0.5, "col": Color("7dffb0")})
			"spread":
				rings.append({"p": ev["pos"], "r0": 0.1, "r1": ev["r"], "life": 0.4, "max": 0.4, "col": Color("a6ff00")})
			"shieldbreak":
				_sparks(ev["pos"], Color("4dd2ff"), 10, 2.5)
				sfx.play("shield", 0.1, 0.08)
			"build":
				var cp := Vector2(ev["cell"]) + Vector2(0.5, 0.5)
				rings.append({"p": cp, "r0": 0.2, "r1": 0.9, "life": 0.3, "max": 0.3, "col": C_CYAN})
				sfx.play("wall" if ev["tower"] < 0 else "build", 0.08)
			"sell":
				floats.append({"p": Vector2(ev["cell"]) + Vector2(0.5, 0.3), "s": "+%d" % ev["amount"], "life": 0.9, "col": C_GOLD})
				sfx.play("sell")
			"upgrade":
				_sparks(Vector2(ev["cell"]) + Vector2(0.5, 0.5), C_GOLD, 14, 2.0)
				sfx.play("upgrade", 0.02)
			"deny":
				_toast(ev["msg"])
				sfx.play("deny", 0.0, 0.25)
			"wave":
				if ev["boss"]:
					_banner("WAVE %d" % ev["n"], "!! BOSS INBOUND !!")
					sfx.play("boss", 0.0)
					shake = 8.0
				else:
					_banner("WAVE %d" % ev["n"], D.wave_summary(ev["n"]))
					sfx.play("wave", 0.0)
			"clear":
				if ev["bonus"] > 0:
					floats.append({"p": Vector2(D.COLS / 2.0, D.ROWS / 2.0), "s": "WAVE CLEAR  +%d" % ev["bonus"], "life": 1.6, "col": C_GREEN, "big": true})
				sfx.play("clear", 0.0)
				_record()
			"money":
				floats.append({"p": ev["pos"], "s": "EARLY +%d" % ev["amount"], "life": 1.2, "col": C_GOLD})
			"win":
				sfx.play("win", 0.0)
			"lose":
				sfx.play("lose", 0.0)
				shake = 20.0
	sim.events.clear()


func _sparks(p: Vector2, col: Color, n: int, spd: float) -> void:
	if particles.size() > 700:
		return
	for i in n:
		var a := randf() * TAU
		var v := Vector2(cos(a), sin(a)) * randf_range(0.3, 1.0) * spd
		var life := randf_range(0.25, 0.6)
		particles.append({"p": p, "v": v, "life": life, "max": life, "col": col, "s": randf_range(0.04, 0.09)})


func _update_fx(dt: float) -> void:
	for p in particles:
		p["life"] -= dt
		p["p"] += p["v"] * dt
		p["v"] *= 0.9
	particles = particles.filter(func(p): return p["life"] > 0.0)
	for r in rings:
		r["life"] -= dt
	rings = rings.filter(func(r): return r["life"] > 0.0)
	for b in bolts:
		b["life"] -= dt
	bolts = bolts.filter(func(b): return b["life"] > 0.0)
	for f in floats:
		f["life"] -= dt
		f["p"].y -= dt * 0.8
	floats = floats.filter(func(f): return f["life"] > 0.0)


# ------------------------------------------------------------ input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse = event.position
		_update_hover()
		if dragging and state == "play" and not paused and sel_build == -1 and hover != drag_cell:
			drag_cell = hover
			if sim.in_bounds(hover) and sim.can_place(hover, -1) == "":
				sim.place(hover, -1)
	elif event is InputEventMouseButton:
		mouse = event.position
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_click(event.position)
			else:
				dragging = false
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			sel_build = -2
			sel_cell = Vector2i(-1, -1)
	elif event is InputEventKey and event.pressed and not event.echo:
		_key_input(event.keycode)


func _update_hover() -> void:
	var c := to_cell(mouse)
	if c != hover:
		hover = c
		hover_ok = sim.can_place(c, sel_build) if (state == "play" and sel_build >= -1 and sim.in_bounds(c)) else "x"


func _click(pos: Vector2) -> void:
	for i in range(buttons.size() - 1, -1, -1):
		var b: Dictionary = buttons[i]
		if b["r"].has_point(pos):
			if b["on"]:
				action(b["id"])
			else:
				sfx.play("deny", 0.0, 0.2)
			return
	if state != "play" or paused or sim.over:
		return
	var c := to_cell(pos)
	hover = c
	if not sim.in_bounds(c):
		return
	var st := sim.cell_state(c)
	if st == 2 or st == 3:
		sel_cell = c
		return
	sel_cell = Vector2i(-1, -1)
	if sel_build >= -1:
		var why := sim.place(c, sel_build)
		if sel_build == -1:
			dragging = true
			drag_cell = c
		if why == "" and sel_build >= 0:
			sel_cell = c
		hover_ok = sim.can_place(c, sel_build)


func _key_input(k: int) -> void:
	if state != "play":
		if k == KEY_ENTER or k == KEY_SPACE:
			action("play" if state == "title" else "start" if state == "select" else "back")
		elif k == KEY_ESCAPE and state != "title":
			action("back")
		elif k == KEY_M:
			action("sound")
		return
	match k:
		KEY_P, KEY_ESCAPE:
			if not sim.over:
				action("pause")
		KEY_SPACE, KEY_ENTER:
			if not paused and sim.can_start_wave():
				action("wave")
		KEY_F:
			action("speed")
		KEY_M:
			action("sound")
		KEY_W:
			action("build-1")
		KEY_S, KEY_DELETE, KEY_BACKSPACE:
			action("sell")
		KEY_T:
			action("target")
		KEY_R:
			if sim.over:
				action("restart")
		KEY_Q, KEY_E, KEY_Z:
			if sel_cell.x >= 0 and sim.towers.has(sel_cell):
				action("up%d" % {KEY_Q: 0, KEY_E: 1, KEY_Z: 2}[k])
		_:
			if k >= KEY_0 and k <= KEY_9:
				var n := k - KEY_0
				action("build%d" % (9 if n == 0 else n - 1))


# ------------------------------------------------------------ draw

func _draw() -> void:
	buttons.clear()
	draw_rect(Rect2(Vector2.ZERO, vs), C_BG)
	match state:
		"title":
			art.draw_title()
		"select":
			art.draw_select()
		"howto":
			art.draw_howto()
		"play":
			art.draw_game()


## Immediate-mode button: draws and registers a hit-rect.
func button(r: Rect2, label: String, id: String, on := true, col := C_CYAN, size := 20, active := false) -> void:
	var hov := r.has_point(mouse)
	var c := col if on else Color(0.35, 0.45, 0.5)
	var fill := Color(c, 0.22 if active else (0.14 if hov else 0.07))
	draw_rect(r, fill)
	draw_rect(r.grow(2), Color(c, 0.12), false, 4.0)
	draw_rect(r, Color(c, 0.95 if (hov or active) else 0.7), false, 2.0)
	if label != "":
		text(Vector2(r.position.x, r.position.y + r.size.y / 2 + size * 0.36), label, size, C_INK if on else C_DIM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	buttons.append({"r": r, "id": id, "on": on})


func text(p: Vector2, s: String, size := 18, col := C_INK, align := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
	draw_string(font, p, s, align, w, size, col)


func glow_text(p: Vector2, s: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_CENTER, w := -1.0) -> void:
	for o in [Vector2(-2, 0), Vector2(2, 0), Vector2(0, -2), Vector2(0, 2)]:
		draw_string(font, p + o, s, align, w, size, Color(col, 0.22))
	draw_string(font, p, s, align, w, size, col)


func glow_line(a: Vector2, b: Vector2, col: Color, w := 2.0) -> void:
	draw_line(a, b, Color(col, 0.12), w * 4.0)
	draw_line(a, b, Color(col, 0.3), w * 2.0)
	draw_line(a, b, col, w)
