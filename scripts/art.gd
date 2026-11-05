extends RefCounted
## Circuit Siege - all drawing: board, towers, enemies, FX, HUD and menus.
## Called from main._draw(), so every draw_* call goes to the host CanvasItem.

const D := preload("res://scripts/data.gd")
var host  # main.gd node

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


# ------------------------------------------------------------ shapes

func poly(n: int, r: float, rot := 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := rot + TAU * i / n
		pts.append(Vector2(cos(a), sin(a)) * r)
	return pts


func star(n: int, r1: float, r2: float, rot := 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n * 2:
		var a := rot + PI * i / n
		pts.append(Vector2(cos(a), sin(a)) * (r1 if i % 2 == 0 else r2))
	return pts


func shift(pts: PackedVector2Array, o: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p + o)
	return out


func neon_shape(pts: PackedVector2Array, o: Vector2, col: Color, fill := 0.25, w := 2.0) -> void:
	var s := shift(pts, o)
	host.draw_colored_polygon(s, Color(col, fill))
	var loop := s.duplicate()
	loop.append(s[0])
	host.draw_polyline(loop, Color(col, 0.25), w * 3.0)
	host.draw_polyline(loop, col, w)


func ring(c: Vector2, r: float, col: Color, w := 2.0) -> void:
	host.draw_arc(c, r, 0, TAU, 40, Color(col, 0.25), w * 3.0)
	host.draw_arc(c, r, 0, TAU, 40, col, w)


# ------------------------------------------------------------ board

func draw_board_bg() -> void:
	var h = host
	var o: Vector2 = h.origin
	var cs: float = h.cell
	var size := Vector2(D.COLS, D.ROWS) * cs
	h.draw_rect(Rect2(o - Vector2(10, 10), size + Vector2(20, 20)), Color("0a2a2e"))
	h.draw_rect(Rect2(o, size), C_PCB)
	for tr in h.traces:
		var pts := PackedVector2Array()
		for p in tr:
			pts.append(o + p.clamp(Vector2.ZERO, Vector2(D.COLS, D.ROWS)) * cs)
		h.draw_polyline(pts, C_TRACE, maxf(2.0, cs * 0.07))
		h.draw_circle(pts[0], cs * 0.09, C_TRACE)
		h.draw_circle(pts[pts.size() - 1], cs * 0.09, C_TRACE)
	# grid dots
	for y in D.ROWS + 1:
		for x in D.COLS + 1:
			h.draw_rect(Rect2(o + Vector2(x, y) * cs - Vector2(1, 1), Vector2(2, 2)), Color("1d5a5c"))
	h.draw_rect(Rect2(o, size), Color(C_CYAN, 0.35), false, 2.0)


func draw_chip(c: Vector2i, fixed: bool) -> void:
	var h = host
	var cs: float = h.cell
	var p: Vector2 = h.to_px(Vector2(c))
	var inset := cs * (0.06 if fixed else 0.12)
	var r := Rect2(p + Vector2(inset, inset), Vector2(cs, cs) - Vector2(inset, inset) * 2)
	# pins
	var pc := Color("2f6f73") if fixed else Color("3fa3a8")
	for i in 3:
		var k := (i + 1) / 4.0
		h.draw_line(Vector2(r.position.x + r.size.x * k, r.position.y), Vector2(r.position.x + r.size.x * k, r.position.y - inset), pc, 2.0)
		h.draw_line(Vector2(r.position.x + r.size.x * k, r.end.y), Vector2(r.position.x + r.size.x * k, r.end.y + inset), pc, 2.0)
	h.draw_rect(r, Color("0c1418") if fixed else Color("10262b"))
	h.draw_rect(r, Color("2a4f56") if fixed else Color(C_CYAN, 0.55), false, 2.0)
	if not fixed:
		h.draw_circle(r.position + Vector2(cs * 0.14, cs * 0.14), cs * 0.04, Color(C_CYAN, 0.6))


func draw_ports() -> void:
	var h = host
	var sim = h.sim
	var cs: float = h.cell
	var tt: float = h.t
	for s in sim.spawns:
		var p: Vector2 = h.to_px(Vector2(s) + Vector2(0.5, 0.5))
		for i in 3:
			var k := fmod(tt * 0.8 + i / 3.0, 1.0)
			h.draw_arc(p, cs * (0.15 + k * 0.4), 0, TAU, 24, Color(C_MAG, 1.0 - k), 2.0)
		neon_shape(poly(4, cs * 0.3, tt), p, C_MAG, 0.3)
	var e: Vector2 = h.to_px(Vector2(sim.exit_cell) + Vector2(0.5, 0.5))
	var cf: float = h.core_flash
	var col := C_CYAN.lerp(C_RED, cf)
	h.draw_circle(e, cs * (0.55 + 0.05 * sin(tt * 4.0)), Color(col, 0.12))
	neon_shape(poly(6, cs * 0.38, tt * 0.5), e, col, 0.25)
	neon_shape(poly(6, cs * 0.2, -tt), e, col, 0.6)


func draw_paths() -> void:
	var h = host
	var sim = h.sim
	var cs: float = h.cell
	var tt: float = h.t
	var core: Vector2 = h.to_px(Vector2(sim.exit_cell) + Vector2(0.5, 0.5))
	for i in sim.paths.size():
		var path: Array = sim.paths[i]
		if path.size() < 2:
			continue
		var pts := PackedVector2Array()
		for c in path:
			pts.append(h.to_px(Vector2(c) + Vector2(0.5, 0.5)))
		h.draw_polyline(pts, Color(C_MAG, 0.10), cs * 0.32)
		h.draw_polyline(pts, Color(C_MAG, 0.35), 2.0)
		# current flowing along the trace
		var total := float(pts.size() - 1)
		var k := 0.0
		while k < total:
			var u := fmod(k + tt * 2.0, total)
			var a := int(u)
			var p: Vector2 = pts[a].lerp(pts[mini(a + 1, pts.size() - 1)], u - a)
			h.draw_circle(p, cs * 0.06, Color(C_MAG, 0.85))
			k += 1.5
		# flying route (straight line)
		var sp: Vector2 = pts[0]
		var dl := sp.distance_to(core)
		var d := fmod(tt * 40.0, 24.0)
		while d < dl:
			h.draw_line(sp.lerp(core, d / dl), sp.lerp(core, minf(1.0, (d + 8) / dl)), Color("b98cff", 0.18), 2.0)
			d += 24.0


func draw_tower(tw: Dictionary, preview := false, alpha := 1.0) -> void:
	var h = host
	var cs: float = h.cell
	var c: Vector2i = tw["cell"]
	var p: Vector2 = h.to_px(Vector2(c) + Vector2(0.5, 0.5))
	var d: Dictionary = D.TOWERS[tw["type"]]
	var col: Color = d["col"]
	col.a = alpha
	var pop: float = tw.get("pop", 0.0)
	var sc := cs * (1.0 + 0.18 * sin(pop * PI))
	var r := sc * 0.42
	# base plate
	h.draw_rect(Rect2(p - Vector2(r, r), Vector2(r, r) * 2), Color(0.03, 0.08, 0.1, alpha))
	h.draw_rect(Rect2(p - Vector2(r, r), Vector2(r, r) * 2), Color(col, 0.75 * alpha), false, 2.0)
	var fl: float = tw.get("flash", 0.0)
	var ang: float = tw.get("ang", -PI / 2)
	var tt: float = h.t
	var bar := Vector2(cos(ang), sin(ang))
	match d["id"]:
		"pulse":
			host.draw_line(p, p + bar * r * 0.95, col, sc * 0.12)
			neon_shape(poly(20, r * 0.45), p, col, 0.35 + fl * 0.4)
		"arc":
			neon_shape(star(6, r * 0.7, r * 0.35, tt * 2.0), p, col, 0.3 + fl * 0.5)
			ring(p, r * 0.25, col, 1.5)
		"laser":
			host.draw_line(p, p + bar * r * 1.05, col, sc * 0.06)
			neon_shape(poly(4, r * 0.55, ang), p, col, 0.35)
		"bomb":
			neon_shape(poly(8, r * 0.6, PI / 8), p, col, 0.3 + fl * 0.4)
			host.draw_circle(p, r * 0.22, col)
		"cryo":
			for i in 3:
				var a := tt * 1.5 + i * PI / 3
				var v := Vector2(cos(a), sin(a)) * r * 0.75
				host.draw_line(p - v, p + v, col, 2.5)
			ring(p, r * 0.3, col, 1.5)
		"rail":
			var n := Vector2(-bar.y, bar.x) * r * 0.2
			host.draw_line(p + n - bar * r * 0.5, p + n + bar * r * 1.1, col, 3.0)
			host.draw_line(p - n - bar * r * 0.5, p - n + bar * r * 1.1, col, 3.0)
			neon_shape(poly(4, r * 0.35, PI / 4), p, col, 0.4 + fl * 0.4)
		"flak":
			for i in 3:
				var o := Vector2(-bar.y, bar.x) * r * (i - 1) * 0.32
				host.draw_line(p + o, p + o + bar * r * 0.85, col, 2.5)
			neon_shape(poly(3, r * 0.5, ang), p, col, 0.3 + fl * 0.3)
		"virus":
			neon_shape(poly(12, r * 0.42), p, col, 0.3)
			for i in 6:
				var a := TAU * i / 6 + tt
				var v := Vector2(cos(a), sin(a))
				host.draw_line(p + v * r * 0.42, p + v * r * 0.72, col, 2.0)
				host.draw_circle(p + v * r * 0.75, r * 0.08, col)
		"miner":
			neon_shape(poly(6, r * 0.62, tt * 0.7), p, col, 0.25)
			h.text(p + Vector2(-r, r * 0.3), "$", int(r * 0.95), col, HORIZONTAL_ALIGNMENT_CENTER, r * 2)
		"relay":
			ring(p, r * 0.5 + sin(tt * 5.0) * r * 0.06, col, 2.0)
			for i in 4:
				var v := Vector2.RIGHT.rotated(i * PI / 2) * r
				host.draw_line(p + v * 0.55, p + v * 0.98, col, 3.0)
			host.draw_circle(p, r * 0.18, col)
	if preview:
		return
	# upgrade pips (one column per branch)
	for b in 3:
		for l in tw["lv"][b]:
			var pp := p + Vector2(-r + 4 + b * 6, r - 5 - l * 6)
			h.draw_rect(Rect2(pp, Vector2(4, 4)), C_GOLD)


func draw_enemy(e: Dictionary) -> void:
	var h = host
	var cs: float = h.cell
	var d: Dictionary = D.ENEMIES[e["type"]]
	var col: Color = d["col"]
	var p: Vector2 = h.to_px(e["pos"])
	var r: float = d["size"] * cs
	var tt: float = h.t
	if e["fly"]:
		h.draw_circle(p + Vector2(0, r * 0.9), r * 0.6, Color(0, 0, 0, 0.35))
		p.y -= r * 0.5 + sin(e["wob"]) * 2.0
	if e["flash"] > 0.0:
		col = col.lerp(Color.WHITE, e["flash"] * 0.7)
	if e["slow"] > 0.0:
		col = col.lerp(Color("9ff3ff"), 0.4)
	var shape: int = d["shape"]
	match shape:
		0: neon_shape(poly(14, r), p, col, 0.3)
		1:
			var dir := 0.0
			if not e["fly"] and e["idx"] < e["path"].size():
				dir = (Vector2(e["path"][e["idx"]]) + Vector2(0.5, 0.5) - e["pos"]).angle()
			neon_shape(poly(3, r, dir), p, col, 0.35)
		2: neon_shape(poly(4, r * 1.2, PI / 4), p, col, 0.35, 3.0)
		3: neon_shape(poly(6, r, tt), p, col, 0.3)
		4:
			neon_shape(poly(4, r, 0), p, col, 0.35)
			for i in 4:
				var v := Vector2.RIGHT.rotated(PI / 4 + i * PI / 2) * r * 1.1
				h.draw_arc(p + v, r * 0.35, 0, TAU, 10, Color(col, 0.7), 1.5)
		5: neon_shape(poly(5, r, -PI / 2), p, col, 0.3)
		6: neon_shape(star(4, r * 1.2, r * 0.45, tt * 3.0), p, col, 0.4)
		7:
			var w := r * 0.4
			h.draw_rect(Rect2(p - Vector2(r, w), Vector2(r * 2, w * 2)), Color(col, 0.6))
			h.draw_rect(Rect2(p - Vector2(w, r), Vector2(w * 2, r * 2)), Color(col, 0.6))
			ring(p, r, col, 1.5)
		8:
			neon_shape(poly(8, r, tt * 0.5), p, col, 0.25)
			h.draw_circle(p, r * 0.4 * (1.0 + 0.2 * sin(tt * 6.0)), Color(col, 0.7))
		_:
			neon_shape(star(8, r * 1.15, r * 0.75, tt * 0.6), p, col, 0.25, 3.0)
			neon_shape(poly(6, r * 0.5, -tt), p, col, 0.6)
	if e["shield"] > 0.0:
		h.draw_arc(p, r * 1.35, 0, TAU * e["shield"] / maxf(1.0, e["maxshield"]), 24, Color("4dd2ff"), 2.0)
	if e["armor"] > 0.0 and shape != 2:
		h.draw_arc(p, r * 1.15, 0, TAU, 16, Color("aebfd4", 0.6), 1.0)
	if e["dot_t"] > 0.0:
		h.draw_circle(p + Vector2(r * 0.8, -r * 0.8), 3.0, Color("a6ff00"))
	if e["stun_t"] > 0.0:
		h.draw_arc(p, r * 1.5, tt * 8.0, tt * 8.0 + 2.0, 8, C_CYAN, 2.0)
	if e["hp"] < e["maxhp"] and not e["boss"]:
		var bw := maxf(16.0, r * 2.0)
		var bp := p + Vector2(-bw / 2, -r - 9)
		h.draw_rect(Rect2(bp, Vector2(bw, 3)), Color(0, 0, 0, 0.7))
		h.draw_rect(Rect2(bp, Vector2(bw * maxf(0.0, e["hp"] / e["maxhp"]), 3)), C_GREEN.lerp(C_RED, 1.0 - e["hp"] / e["maxhp"]))


func draw_fx() -> void:
	var h = host
	var cs: float = h.cell
	for b in h.bolts:
		var k: float = b["life"] / b["max"]
		var pts := PackedVector2Array()
		var src: Array = b["pts"]
		for i in src.size():
			var p: Vector2 = h.to_px(src[i])
			pts.append(p)
			if b["jag"] and i < src.size() - 1:
				var q: Vector2 = h.to_px(src[i + 1])
				for j in 3:
					var m := p.lerp(q, (j + 1) / 4.0)
					var n := (q - p).orthogonal().normalized() * randf_range(-cs * 0.15, cs * 0.15)
					pts.append(m + n)
		var col: Color = b["col"]
		h.draw_polyline(pts, Color(col, 0.25 * k), 9.0 if not b["jag"] else 6.0)
		h.draw_polyline(pts, Color(col, k), 3.0 if not b["jag"] else 2.0)
		if not b["jag"]:
			h.draw_polyline(pts, Color(1, 1, 1, k), 1.5)
	for r in h.rings:
		var k: float = 1.0 - r["life"] / r["max"]
		var rad: float = lerpf(r["r0"], r["r1"], 1.0 - pow(1.0 - k, 3.0)) * cs
		h.draw_arc(h.to_px(r["p"]), rad, 0, TAU, 32, Color(r["col"], 1.0 - k), 2.5)
	for p in h.particles:
		var k: float = p["life"] / p["max"]
		var s: float = p["s"] * cs * (0.5 + k)
		h.draw_rect(Rect2(h.to_px(p["p"]) - Vector2(s, s) / 2, Vector2(s, s)), Color(p["col"], k))
	for f in h.floats:
		var k: float = clampf(f["life"] * 2.0, 0.0, 1.0)
		var big: bool = f.get("big", false)
		var sz := 34 if big else 16
		var w := 600.0 if big else 120.0
		h.glow_text(h.to_px(f["p"]) - Vector2(w / 2, 0), f["s"], sz, Color(f["col"], k), HORIZONTAL_ALIGNMENT_CENTER, w)


func draw_shots() -> void:
	var h = host
	var cs: float = h.cell
	for s in h.sim.shots:
		var p: Vector2 = h.to_px(s["pos"])
		var col: Color = s["col"]
		if s["kind"] == "bomb":
			var k: float = 1.0 - s["life"] / s["dur"]
			p.y -= sin(k * PI) * cs * 0.9
			h.draw_circle(p, cs * 0.14, Color(col, 0.3))
			h.draw_circle(p, cs * 0.08, col)
		else:
			h.draw_circle(p, cs * 0.11, Color(col, 0.25))
			h.draw_circle(p, cs * 0.05, Color.WHITE.lerp(col, 0.4))


func draw_beams() -> void:
	var h = host
	for c in h.sim.towers:
		var tw: Dictionary = h.sim.towers[c]
		if D.TOWERS[tw["type"]]["kind"] != "beam":
			continue
		var bt = tw["target"]
		if bt == null or not bt["alive"]:
			continue
		var a: Vector2 = h.to_px(Vector2(c) + Vector2(0.5, 0.5))
		var b: Vector2 = h.to_px(bt["pos"])
		var col: Color = D.TOWERS[tw["type"]]["col"]
		var w: float = 1.5 + tw["ramp"] * 1.5 + sin(h.t * 40.0)
		h.draw_line(a, b, Color(col, 0.2), w * 4.0)
		h.draw_line(a, b, col, w)
		h.draw_line(a, b, Color.WHITE, maxf(1.0, w * 0.35))
		h.draw_circle(b, w * 1.6, Color(col, 0.5))


func draw_game() -> void:
	var h = host
	var sim = h.sim
	var cs: float = h.cell
	var off := Vector2.ZERO
	if h.shake > 0.0:
		off = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * h.shake * 0.6
	host.draw_set_transform(off)
	draw_board_bg()
	draw_paths()
	for y in D.ROWS:
		for x in D.COLS:
			var st: int = sim.grid[y][x]
			if st == 1 or st == 2:
				draw_chip(Vector2i(x, y), st == 1)
	draw_ports()
	# synergy links
	for c in sim.towers:
		var tw: Dictionary = sim.towers[c]
		for dv in [Vector2i(1, 0), Vector2i(0, 1)]:
			if sim.towers.has(c + dv):
				var a: Vector2 = h.to_px(Vector2(c) + Vector2(0.5, 0.5))
				var b: Vector2 = h.to_px(Vector2(c + dv) + Vector2(0.5, 0.5))
				var pulse := 0.5 + 0.5 * sin(h.t * 4.0 + c.x + c.y)
				h.draw_line(a, b, Color(C_GOLD, 0.15 + 0.25 * pulse), cs * 0.16)
	for c in sim.towers:
		draw_tower(sim.towers[c])
	# selection / range
	if h.sel_cell.x >= 0 and sim.in_bounds(h.sel_cell) and sim.cell_state(h.sel_cell) >= 2:
		var sp: Vector2 = h.to_px(Vector2(h.sel_cell) + Vector2(0.5, 0.5))
		if sim.towers.has(h.sel_cell):
			var tw2: Dictionary = sim.towers[h.sel_cell]
			var rr: float = tw2["st"]["range"] * cs
			if tw2["id"] == "relay":
				rr = (tw2["st"]["reach"] + 0.5) * cs
			h.draw_circle(sp, rr, Color(C_CYAN, 0.06))
			h.draw_arc(sp, rr, 0, TAU, 48, Color(C_CYAN, 0.6), 1.5)
		h.draw_rect(Rect2(sp - Vector2(cs, cs) / 2, Vector2(cs, cs)), Color(C_INK, 0.8 + 0.2 * sin(h.t * 8.0)), false, 2.0)
	for e in sim.enemies:
		if not e["fly"]:
			draw_enemy(e)
	draw_beams()
	for e in sim.enemies:
		if e["fly"]:
			draw_enemy(e)
	draw_shots()
	# build ghost
	if not sim.over and not h.paused and sim.in_bounds(h.hover) and h.sel_build >= -1 and sim.cell_state(h.hover) == 0:
		var ok: bool = h.hover_ok == ""
		var gp: Vector2 = h.to_px(Vector2(h.hover))
		h.draw_rect(Rect2(gp, Vector2(cs, cs)), Color(C_GREEN if ok else C_RED, 0.18))
		h.draw_rect(Rect2(gp, Vector2(cs, cs)), Color(C_GREEN if ok else C_RED, 0.8), false, 2.0)
		if h.sel_build >= 0:
			var ghost := {"type": h.sel_build, "cell": h.hover, "lv": [0, 0, 0]}
			draw_tower(ghost, true, 0.55)
			var rg: float = D.TOWERS[h.sel_build]["range"] * cs
			h.draw_arc(gp + Vector2(cs, cs) / 2, rg, 0, TAU, 48, Color(C_INK, 0.35), 1.0)
	draw_fx()
	host.draw_set_transform(Vector2.ZERO)
	draw_hud()
	draw_panel()
	if h.banner_t > 0.0:
		var k: float = clampf(h.banner_t, 0.0, 1.0)
		var mid: Vector2 = h.origin + Vector2(D.COLS, D.ROWS) * cs * 0.5
		var w: float = D.COLS * cs
		h.draw_rect(Rect2(Vector2(h.origin.x, mid.y - 52), Vector2(w, 90)), Color(0, 0, 0, 0.45 * k))
		h.glow_text(Vector2(h.origin.x, mid.y), h.banner, 46, Color(C_CYAN, k), HORIZONTAL_ALIGNMENT_CENTER, w)
		h.text(Vector2(h.origin.x, mid.y + 28), h.banner_sub, 18, Color(C_INK, k), HORIZONTAL_ALIGNMENT_CENTER, w)
	if h.toast_t > 0.0:
		var k2: float = clampf(h.toast_t * 2.0, 0.0, 1.0)
		var w2 := 420.0
		var tp := Vector2(h.origin.x + D.COLS * cs / 2 - w2 / 2, h.origin.y + D.ROWS * cs - 56)
		h.draw_rect(Rect2(tp, Vector2(w2, 40)), Color(0.2, 0.02, 0.06, 0.85 * k2))
		h.draw_rect(Rect2(tp, Vector2(w2, 40)), Color(C_RED, k2), false, 2.0)
		h.text(tp + Vector2(0, 27), h.toast, 19, Color(C_INK, k2), HORIZONTAL_ALIGNMENT_CENTER, w2)
	if h.paused:
		draw_pause()
	elif sim.over:
		draw_result()


func draw_hud() -> void:
	var h = host
	var sim = h.sim
	var vs: Vector2 = h.vs
	h.draw_rect(Rect2(0, 0, vs.x, 60), Color("08141b"))
	h.draw_line(Vector2(0, 60), Vector2(vs.x, 60), Color(C_CYAN, 0.4), 2.0)
	var compact: bool = h.portrait
	var x := 14.0
	var cash_s := "INF" if sim.mode == 2 else str(sim.cash)
	var lives_s := "INF" if sim.mode == 2 else str(sim.lives)
	var wave_s := "%d/%d" % [sim.wave_num, D.CAMPAIGN_WAVES] if (sim.mode == 0 or sim.mode == 3) else str(sim.wave_num)
	for item in [["CR", cash_s, C_GOLD], ["CORE", lives_s, C_RED], ["WAVE", wave_s, C_CYAN]]:
		h.text(Vector2(x, 24), item[0], 13, C_DIM)
		h.glow_text(Vector2(x, 50), item[1], 24, item[2], HORIZONTAL_ALIGNMENT_LEFT)
		x += 104.0 if compact else 140.0
	if not compact:
		h.text(Vector2(x, 24), D.MAPS[sim.map_idx]["name"].to_upper(), 13, C_DIM)
		h.text(Vector2(x, 48), D.MODES[sim.mode] + ("" if sim.challenge == "" else " - " + sim.challenge.to_upper()), 18, C_INK)
	var bx: float = vs.x - 10.0
	for b in [["sound", "SND" if h.save["sound"] else "MUTE", 74.0], ["pause", "II", 54.0], ["speed", "%dx" % h.speed, 60.0]]:
		bx -= b[2]
		h.button(Rect2(bx, 8, b[2] - 6, 44), b[1], b[0], true, C_CYAN, 20, b[0] == "speed" and h.speed > 1)
	# boss bar
	if not sim.boss.is_empty():
		var bs: Dictionary = sim.boss
		var w: float = D.COLS * h.cell
		var bp := Vector2(h.origin.x, h.origin.y - 24)
		h.draw_rect(Rect2(bp, Vector2(w, 14)), Color(0, 0, 0, 0.8))
		h.draw_rect(Rect2(bp, Vector2(w * maxf(0.0, bs["hp"] / bs["maxhp"]), 14)), C_RED)
		if bs["maxshield"] > 0.0:
			h.draw_rect(Rect2(bp + Vector2(0, 10), Vector2(w * bs["shield"] / bs["maxshield"], 4)), Color("4dd2ff"))
		h.text(bp + Vector2(0, 12), D.ENEMIES[bs["type"]]["name"], 13, C_INK, HORIZONTAL_ALIGNMENT_CENTER, w)
	else:
		var nx: int = sim.wave_num + 1 if sim.mode != 2 else sim.sandbox_wave
		if sim.can_start_wave():
			h.text(Vector2(h.origin.x, h.origin.y - 10), "NEXT: " + D.wave_summary(nx) + ("   [BOSS]" if nx % 10 == 0 else ""), 15, C_DIM, HORIZONTAL_ALIGNMENT_LEFT, D.COLS * h.cell)


func draw_panel() -> void:
	var h = host
	var sim = h.sim
	var pr: Rect2 = h.panel
	h.draw_rect(pr, Color("08141b"))
	h.draw_rect(pr, Color(C_CYAN, 0.3), false, 2.0)
	var cols := 6 if h.portrait else 3
	var gap := 6.0
	var bw: float = (pr.size.x - 16 - gap * (cols - 1)) / cols
	var bh := 64.0 if h.portrait else 58.0
	var y: float = pr.position.y + 8
	var items := [-1]
	for i in D.TOWERS.size():
		items.append(i)
	for i in items.size():
		var it: int = items[i]
		var r := Rect2(pr.position.x + 8 + (i % cols) * (bw + gap), y + (i / cols) * (bh + gap), bw, bh)
		var cost: int = sim.cost_of(it)
		var afford: bool = sim.mode == 2 or sim.cash >= cost
		var col: Color = C_CYAN if it < 0 else D.TOWERS[it]["col"]
		var on: bool = afford and not (it < 0 and sim.challenge == "nowall")
		h.button(r, "", "build%d" % it, true, col, 16, h.sel_build == it)
		if it < 0:
			var cr := Rect2(r.position + Vector2(bw / 2 - 12, 8), Vector2(24, 24))
			h.draw_rect(cr, Color("10262b"))
			h.draw_rect(cr, Color(C_CYAN, 0.7), false, 2.0)
		else:
			var save_cell: float = h.cell
			var save_org: Vector2 = h.origin
			h.cell = 34.0
			h.origin = r.position + Vector2(bw / 2 - 17, 2)
			draw_tower({"type": it, "cell": Vector2i.ZERO, "lv": [0, 0, 0], "ang": -PI / 4}, true, 1.0 if on else 0.4)
			h.cell = save_cell
			h.origin = save_org
		var nm: String = "Wall" if it < 0 else D.TOWERS[it]["name"].split(" ")[0]
		h.text(Vector2(r.position.x + 4, r.end.y - 6), nm, 12, C_INK if on else C_DIM)
		h.text(Vector2(r.position.x, r.end.y - 6), str(cost), 13, C_GOLD if on else C_DIM, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 4)
	var rows: int = int(ceil(items.size() / float(cols)))
	y += rows * (bh + gap) + 6
	var info_bottom: float = pr.end.y - 84
	draw_info(Rect2(pr.position.x + 8, y, pr.size.x - 16, info_bottom - y))
	# wave controls
	var wr := Rect2(pr.position.x + 8, pr.end.y - 74, pr.size.x - 16, 64)
	if sim.mode == 2:
		h.button(Rect2(wr.position, Vector2(56, 64)), "-", "swave-", true, C_CYAN, 28)
		h.button(Rect2(wr.position + Vector2(62, 0), Vector2(56, 64)), "+", "swave+", true, C_CYAN, 28)
		h.button(Rect2(wr.position + Vector2(124, 0), Vector2(wr.size.x - 124, 64)), "SPAWN WAVE %d" % sim.sandbox_wave, "wave", true, C_GREEN, 22)
	else:
		var lbl := "START WAVE %d" % (sim.wave_num + 1)
		if sim.wave_live:
			lbl = "CALL EARLY  +%d" % (5 + sim.wave_num)
		if not sim.can_start_wave():
			lbl = "FINAL WAVE" if sim.wave_live else "DONE"
		h.button(wr, lbl, "wave", sim.can_start_wave(), C_GREEN, 24, not sim.wave_live and sim.can_start_wave() and fmod(h.t, 1.0) < 0.5)


func draw_info(r: Rect2) -> void:
	var h = host
	var sim = h.sim
	var x := r.position.x
	var y := r.position.y
	var w := r.size.x
	h.draw_line(Vector2(x, y - 4), Vector2(x + w, y - 4), Color(C_CYAN, 0.25), 1.0)
	if h.sel_cell.x >= 0 and sim.in_bounds(h.sel_cell) and sim.cell_state(h.sel_cell) == 2:
		h.glow_text(Vector2(x, y + 24), "CIRCUIT WALL", 22, C_CYAN, HORIZONTAL_ALIGNMENT_LEFT)
		h.text(Vector2(x, y + 50), "Blocks the path. Enemies re-route with A*.", 15, C_DIM)
		h.button(Rect2(x, y + 64, 150, 42), "SELL +%d" % D.WALL_COST, "sell", true, C_GOLD, 18)
		return
	if h.sel_cell.x >= 0 and sim.towers.has(h.sel_cell):
		var tw: Dictionary = sim.towers[h.sel_cell]
		var d: Dictionary = D.TOWERS[tw["type"]]
		var s: Dictionary = tw["st"]
		h.glow_text(Vector2(x, y + 22), d["name"].to_upper(), 22, d["col"], HORIZONTAL_ALIGNMENT_LEFT)
		var line := ""
		match d["kind"]:
			"relay": line = "Boost +%d%% dmg  +%d%% rate  reach %d" % [s["buff_dmg"] * 100, s["buff_rate"] * 100, s["reach"]]
			"miner": line = "Yield %d/wave  interest %d%%  zap %d" % [s["yield"], s["interest"] * 100, s["dmg"]]
			"aura": line = "Slow %d%%  dmg %.1f  range %.1f" % [minf(0.75, s["slow"]) * 100, s["dmg"], s["range"]]
			"virus": line = "Infect %.0f dps x%.1fs  range %.1f" % [s["dot"], s["dotdur"], s["range"]]
			_: line = "DMG %.0f  RATE %.1f/s  RNG %.1f" % [s["dmg"], s["rate"], s["range"]]
		h.text(Vector2(x, y + 44), line, 15, C_INK)
		var syn: Dictionary = tw["syn"]
		var sl := "Links %d  (x%.2f dmg, x%.2f rate)" % [syn["links"], syn["dmg"], syn["rate"]]
		if syn["combos"].size() > 0:
			sl = "COMBO: " + ", ".join(syn["combos"])
		h.text(Vector2(x, y + 64), sl, 14, C_GOLD if syn["combos"].size() > 0 else C_DIM)
		h.text(Vector2(x, y + 82), "Kills %d   Damage %d   Lv %d/%d" % [tw["kills"], tw["dmg"], sim.total_levels(tw), D.MAX_UPGRADES], 13, C_DIM)
		var by := y + 90
		var bh: float = clampf((r.size.y - 140) / 3.0, 38.0, 56.0)
		for b in 3:
			var br: Dictionary = d["branches"][b]
			var why: String = sim.can_upgrade(tw, b)
			var rr := Rect2(x, by + b * (bh + 5), w, bh)
			var lv: int = tw["lv"][b]
			h.button(rr, "", "up%d" % b, why == "", d["col"], 16)
			h.text(rr.position + Vector2(8, 20), "%s  %s" % [["Q", "E", "Z"][b], br["name"]], 16, C_INK if why == "" else C_DIM)
			h.text(rr.position + Vector2(8, bh - 8), br["desc"], 13, C_DIM)
			for l in 3:
				h.draw_rect(Rect2(rr.end - Vector2(96 - l * 12, bh - 10), Vector2(9, 9)), C_GOLD if l < lv else Color(C_DIM, 0.4))
			var cs_txt := "MAX" if lv >= 3 else ("CAP" if why == "Upgrade cap reached" else str(sim.upgrade_cost(tw, b)))
			h.text(Vector2(rr.position.x, rr.position.y + 22), cs_txt, 16, C_GOLD, HORIZONTAL_ALIGNMENT_RIGHT, w - 8)
		var yy := by + 3 * (bh + 5) + 2
		var refund: int = tw["spent"] if tw["fresh"] else int(tw["spent"] * 0.7)
		h.button(Rect2(x, yy, w * 0.48, 40), "SELL +%d" % refund, "sell", true, C_GOLD, 17)
		h.button(Rect2(x + w * 0.52, yy, w * 0.48, 40), "TARGET: " + sim.TARGET_MODES[tw["mode"]], "target", d["kind"] != "relay" and d["kind"] != "aura", C_CYAN, 15)
		return
	if h.sel_build >= 0:
		var d2: Dictionary = D.TOWERS[h.sel_build]
		h.glow_text(Vector2(x, y + 22), d2["name"].to_upper(), 22, d2["col"], HORIZONTAL_ALIGNMENT_LEFT)
		h.text(Vector2(x, y + 46), d2["desc"], 15, C_INK, HORIZONTAL_ALIGNMENT_LEFT, w)
		var tgt := "Air + Ground" if d2["air"] and d2["ground"] else ("Air only" if d2["air"] else ("Ground only" if d2["ground"] else "Support"))
		h.text(Vector2(x, y + 68), "Cost %d   %s   Key %s" % [sim.cost_of(h.sel_build), tgt, d2["key"]], 14, C_DIM)
		var yy2 := y + 92
		for b in 3:
			h.text(Vector2(x, yy2), "- %s: %s" % [d2["branches"][b]["name"], d2["branches"][b]["desc"]], 14, C_DIM)
			yy2 += 20
		for cb in D.COMBOS:
			if cb["a"] == d2["id"] or cb["b"] == d2["id"]:
				var other: String = cb["b"] if cb["a"] == d2["id"] else cb["a"]
				h.text(Vector2(x, yy2 + 4), "Combo + %s: %s" % [D.TOWERS[D.tower_index(other)]["name"], cb["name"]], 14, C_GOLD)
				yy2 += 20
		h.text(Vector2(x, yy2 + 8), "Tap the board to build. Adjacent towers link.", 13, C_DIM)
		return
	if h.sel_build == -1:
		h.glow_text(Vector2(x, y + 22), "CIRCUIT WALL", 22, C_CYAN, HORIZONTAL_ALIGNMENT_LEFT)
		h.text(Vector2(x, y + 46), "Cheap blocker. Drag to draw a maze.", 15, C_INK)
		h.text(Vector2(x, y + 68), "You can never fully block the path.", 14, C_DIM)
		h.text(Vector2(x, y + 88), "Flyers ignore the maze - bring Flak.", 14, C_DIM)
		return
	h.text(Vector2(x, y + 24), "Pick a part above, then tap the board.", 15, C_DIM)
	h.text(Vector2(x, y + 46), "Tap a tower to upgrade or sell it.", 15, C_DIM)


func _overlay(title: String, col: Color, lines: Array, btns: Array) -> void:
	var h = host
	h.buttons.clear()
	var vs: Vector2 = h.vs
	h.draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0.02, 0.04, 0.78))
	var w := minf(520.0, vs.x - 32)
	var hh := 150.0 + lines.size() * 28 + btns.size() * 62
	var p := Vector2((vs.x - w) / 2, (vs.y - hh) / 2)
	h.draw_rect(Rect2(p, Vector2(w, hh)), Color("08141b"))
	h.draw_rect(Rect2(p, Vector2(w, hh)), col, false, 3.0)
	h.glow_text(p + Vector2(0, 64), title, 44, col, HORIZONTAL_ALIGNMENT_CENTER, w)
	var y := p.y + 104
	for l in lines:
		h.text(Vector2(p.x, y), l, 19, C_INK, HORIZONTAL_ALIGNMENT_CENTER, w)
		y += 28
	y += 10
	for b in btns:
		h.button(Rect2(p.x + 40, y, w - 80, 52), b[0], b[1], true, b[2], 22)
		y += 62


func draw_pause() -> void:
	var h = host
	_overlay("PAUSED", C_CYAN, ["Space: wave   F: speed   1-0 / W: build", "Q / E / Z: upgrade   S: sell   T: target"],
		[["RESUME", "resume", C_GREEN], ["RESTART", "restart", C_GOLD], ["SOUND: " + ("ON" if h.save["sound"] else "OFF"), "sound", C_CYAN], ["MAIN MENU", "menu", C_MAG]])


func draw_result() -> void:
	var h = host
	var sim = h.sim
	var win: bool = sim.result == "win"
	var k: String = h._key(sim.map_idx, sim.mode, sim.challenge)
	var lines := ["Waves survived: %d" % (sim.wave_num if win else maxi(0, sim.wave_num - 1)),
		"Enemies deleted: %d   Parts built: %d" % [sim.kills, sim.built],
		"Best on this board: wave %d" % int(h.save["best"].get(k, 0))]
	if win:
		lines.append("Rating: " + "*".repeat(sim.stars()) + "-".repeat(3 - sim.stars()) + "  (%d core left)" % sim.lives)
	var btns := [["RETRY", "restart", C_GOLD], ["MAIN MENU", "menu", C_MAG]]
	if win and sim.mode == 0:
		btns.push_front(["ENDLESS ON THIS BOARD", "endless", C_GREEN])
	_overlay("CORE SECURED" if win else "CORE BREACHED", C_GREEN if win else C_RED, lines, btns)


# ------------------------------------------------------------ menus

func draw_menu_bg() -> void:
	var h = host
	var vs: Vector2 = h.vs
	var tt: float = h.t
	var cs := 64.0
	var save_cell: float = h.cell
	var save_org: Vector2 = h.origin
	h.cell = cs
	h.origin = Vector2(vs.x / 2 - D.COLS * cs / 2, vs.y / 2 - D.ROWS * cs / 2)
	for tr in h.traces:
		var pts := PackedVector2Array()
		for p in tr:
			pts.append(h.to_px(p))
		h.draw_polyline(pts, Color(C_TRACE, 1.0), 3.0)
		var total := float(pts.size() - 1)
		var u := fmod(tt * 0.9 + pts[0].x * 0.01, total)
		var a := int(u)
		var pp: Vector2 = pts[a].lerp(pts[mini(a + 1, pts.size() - 1)], u - a)
		h.draw_circle(pp, 4.0, Color(C_CYAN, 0.8))
		h.draw_circle(pp, 9.0, Color(C_CYAN, 0.15))
	h.cell = save_cell
	h.origin = save_org


func draw_title() -> void:
	var h = host
	var vs: Vector2 = h.vs
	var tt: float = h.t
	draw_menu_bg()
	var cy := vs.y * 0.3
	var tsz := 92 if vs.x > 900 else 70
	h.glow_text(Vector2(0, cy), "CIRCUIT", tsz, C_CYAN, HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	h.glow_text(Vector2(0, cy + tsz * 0.95), "SIEGE", tsz, C_MAG, HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	h.text(Vector2(0, cy + tsz * 1.5), "Build the maze. Wire the towers. Hold the core.", 22, C_INK, HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	var p := Vector2(vs.x / 2, cy - tsz * 1.3)
	neon_shape(poly(6, 34, tt * 0.5), p, C_CYAN, 0.25)
	neon_shape(poly(6, 18, -tt), p, C_MAG, 0.5)
	var bw := minf(380.0, vs.x - 60)
	var by := cy + tsz * 1.5 + 50
	h.button(Rect2(vs.x / 2 - bw / 2, by, bw, 66), "PLAY", "play", true, C_GREEN, 30, fmod(tt, 1.2) < 0.6)
	h.button(Rect2(vs.x / 2 - bw / 2, by + 80, bw, 56), "HOW TO PLAY", "howto", true, C_CYAN, 22)
	h.button(Rect2(vs.x / 2 - bw / 2, by + 150, bw, 56), "SOUND: " + ("ON" if h.save["sound"] else "OFF"), "sound", true, C_GOLD, 22)
	h.text(Vector2(0, vs.y - 22), "Made by Jaineil Rana (JaKing)  -  JaiGod", 15, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, vs.x)


func draw_select() -> void:
	var h = host
	var vs: Vector2 = h.vs
	draw_menu_bg()
	h.draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.45))
	h.glow_text(Vector2(0, 58), "SELECT BOARD", 40, C_CYAN, HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	var mw := minf(220.0, (vs.x - 40) / 4.0 - 8)
	var mx := vs.x / 2 - (mw + 8) * 2 + 4
	for i in D.MODES.size():
		h.button(Rect2(mx + i * (mw + 8), 84, mw, 48), D.MODES[i].to_upper(), "mode%d" % i, true, [C_GREEN, C_MAG, C_GOLD, C_RED][i], 18, h.sel_mode == i)
	var desc: String = ["30 waves, bosses on 10/20/30. Earn up to 3 stars.", "No end. How deep can you go?",
		"Infinite credits & core. Test any wave and build.", "30 waves with a brutal rule twist."][h.sel_mode]
	h.text(Vector2(0, 160), desc, 17, C_DIM, HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	var y := 180.0
	if h.sel_mode == 3:
		var cw := minf(260.0, (vs.x - 40) / 2.0 - 8)
		var cols := 4 if vs.x > 1100 else 2
		cw = minf(280.0, (vs.x - 40) / cols - 8)
		var cx := vs.x / 2 - (cw + 8) * cols / 2.0 + 4
		for i in D.CHALLENGES.size():
			var r := Rect2(cx + (i % cols) * (cw + 8), y + (i / cols) * 70, cw, 62)
			var ch: Dictionary = D.CHALLENGES[i]
			h.button(r, "", "chal%d" % i, true, C_RED, 16, h.sel_chal == i)
			h.text(r.position + Vector2(10, 24), ch["name"], 18, C_INK)
			h.text(r.position + Vector2(10, 48), ch["desc"], 12, C_DIM, HORIZONTAL_ALIGNMENT_LEFT, cw - 16)
		y += 70 * ceil(D.CHALLENGES.size() / float(cols)) + 6
	# map cards
	var ncol := 5 if vs.x > 1100 else 2
	var gap := 10.0
	var cwid := minf(236.0, (vs.x - 32 - gap * (ncol - 1)) / ncol)
	var chgt := cwid * 0.72 + 70
	var ox := vs.x / 2 - (cwid * ncol + gap * (ncol - 1)) / 2
	for i in D.MAPS.size():
		var r := Rect2(ox + (i % ncol) * (cwid + gap), y + (i / ncol) * (chgt + gap), cwid, chgt)
		var m: Dictionary = D.MAPS[i]
		h.button(r, "", "map%d" % i, true, C_CYAN, 16, h.sel_map == i)
		var ms := (cwid - 20) / D.COLS
		var mo: Vector2 = r.position + Vector2(10, 10)
		h.draw_rect(Rect2(mo, Vector2(D.COLS, D.ROWS) * ms), C_PCB)
		for yy in D.ROWS:
			for xx in D.COLS:
				var ch2: String = m["rows"][yy][xx]
				if ch2 == "#":
					h.draw_rect(Rect2(mo + Vector2(xx, yy) * ms, Vector2(ms, ms) - Vector2(1, 1)), Color("2a4f56"))
				elif ch2 == "S":
					h.draw_rect(Rect2(mo + Vector2(xx, yy) * ms, Vector2(ms, ms)), C_MAG)
				elif ch2 == "E":
					h.draw_rect(Rect2(mo + Vector2(xx, yy) * ms, Vector2(ms, ms)), C_CYAN)
		var ty := mo.y + D.ROWS * ms + 22
		h.text(Vector2(r.position.x + 10, ty), m["name"], 18, C_INK)
		h.text(Vector2(r.position.x + 10, ty + 20), m["desc"], 12, C_DIM, HORIZONTAL_ALIGNMENT_LEFT, cwid - 20)
		var ch_id: String = D.CHALLENGES[h.sel_chal]["id"] if h.sel_mode == 3 else ""
		var k: String = h._key(i, h.sel_mode, ch_id)
		var best := int(h.save["best"].get(k, 0))
		var st := int(h.save["stars"].get(k, 0))
		var tag := ""
		if h.sel_mode == 0 or h.sel_mode == 3:
			tag = "*".repeat(st) + "-".repeat(3 - st)
		if best > 0:
			tag += "  best W%d" % best
		h.text(Vector2(r.position.x, ty), tag, 14, C_GOLD, HORIZONTAL_ALIGNMENT_RIGHT, cwid - 10)
	var rows := ceili(D.MAPS.size() / float(ncol))
	var by := minf(vs.y - 76, y + rows * (chgt + gap) + 10)
	var bw := minf(300.0, (vs.x - 48) / 2)
	h.button(Rect2(vs.x / 2 - bw - 8, by, bw, 60), "BACK", "back", true, C_DIM, 22)
	h.button(Rect2(vs.x / 2 + 8, by, bw, 60), "START", "start", true, C_GREEN, 26, fmod(h.t, 1.2) < 0.6)


func draw_howto() -> void:
	var h = host
	var vs: Vector2 = h.vs
	draw_menu_bg()
	h.draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.6))
	h.glow_text(Vector2(0, 64), "HOW TO PLAY", 42, C_CYAN, HORIZONTAL_ALIGNMENT_CENTER, vs.x)
	var lines := [
		[C_MAG, "Enemies leave the magenta ports and run to your cyan CORE."],
		[C_CYAN, "Place WALLS and TOWERS on the grid to build a maze."],
		[C_CYAN, "Their path is re-planned live with A*. You can never fully block it."],
		[C_GOLD, "Adjacent towers LINK: +6% damage per different neighbour,"],
		[C_GOLD, "+5% rate per matching one. Some pairs unlock named COMBOS."],
		[C_GREEN, "Each tower has 3 upgrade branches (max 6 levels total)."],
		[Color("b98cff"), "Drones FLY over the maze. Armor, shields, splitters and blinkers too."],
		[C_RED, "A boss attacks every 10 waves. Leaks cost core integrity."],
		[C_INK, "Mouse/touch: tap a part, tap the board. Drag walls. Right-click cancels."],
		[C_INK, "Keys: 1-0 towers, W wall, Space wave, F speed, P pause, M mute."],
	]
	var y := 120.0
	var sz := 19 if vs.x > 900 else 17
	for l in lines:
		h.draw_rect(Rect2(24, y - 12, 8, 8), l[0])
		var lw: float = vs.x - 66
		h.draw_multiline_string(h.font, Vector2(42, y), l[1], HORIZONTAL_ALIGNMENT_LEFT, lw, sz, -1, C_INK)
		y += h.font.get_multiline_string_size(l[1], HORIZONTAL_ALIGNMENT_LEFT, lw, sz).y + 10
	var bw := minf(300.0, vs.x - 48)
	h.button(Rect2(vs.x / 2 - bw / 2, minf(vs.y - 80, y + 20), bw, 60), "BACK", "back", true, C_CYAN, 22)
