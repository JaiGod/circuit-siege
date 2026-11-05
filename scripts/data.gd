extends RefCounted
## Circuit Siege - all game data: towers, enemies, maps, waves, challenges.
## Pure data + a deterministic wave generator, so the sim can be tested headless.

const COLS := 16
const ROWS := 11
const CAMPAIGN_WAVES := 30

# ---------------------------------------------------------------- TOWERS
# kind: what the tower does. Stats: dmg, rate (shots/s), range (cells).
# Each tower has 3 upgrade branches; each branch goes to level 3, and a
# tower can hold at most MAX_UPGRADES levels in total, so you must specialise.
# Mod keys ending in "%" multiply the base stat; other keys are added.
const MAX_UPGRADES := 6
const WALL_COST := 6

const TOWERS := [
	{"id": "pulse", "name": "Pulse Node", "kind": "bullet", "cost": 40, "dmg": 9.0, "rate": 2.0, "range": 2.6,
	 "air": true, "ground": true, "col": Color("39ff88"), "key": "1",
	 "desc": "Reliable homing pulses. Hits air and ground.",
	 "branches": [
		{"name": "Overclock", "desc": "+30% fire rate", "mods": {"rate%": 0.30}},
		{"name": "Focus", "desc": "+40% damage", "mods": {"dmg%": 0.40}},
		{"name": "Longwire", "desc": "+0.5 range", "mods": {"range": 0.5}}]},
	{"id": "arc", "name": "Arc Coil", "kind": "chain", "cost": 70, "dmg": 12.0, "rate": 1.0, "range": 2.3,
	 "air": true, "ground": true, "col": Color("4dd2ff"), "key": "2", "chain": 2,
	 "desc": "Lightning chains between enemies. 2x vs shields.",
	 "branches": [
		{"name": "Fork", "desc": "+1 chain jump", "mods": {"chain": 1}},
		{"name": "Voltage", "desc": "+40% damage", "mods": {"dmg%": 0.40}},
		{"name": "Static", "desc": "+12% stun chance", "mods": {"stun": 0.12}}]},
	{"id": "laser", "name": "Laser Diode", "kind": "beam", "cost": 90, "dmg": 16.0, "rate": 1.0, "range": 2.4,
	 "air": true, "ground": true, "col": Color("ff3df0"), "key": "3",
	 "desc": "Beam ramps up on one target. Ignores armor.",
	 "branches": [
		{"name": "Amplifier", "desc": "+35% beam power", "mods": {"dmg%": 0.35}},
		{"name": "Lens", "desc": "+0.5 range", "mods": {"range": 0.5}},
		{"name": "Thermal", "desc": "Adds burn (6 dps)", "mods": {"burn": 6.0}}]},
	{"id": "bomb", "name": "Bomb Capacitor", "kind": "splash", "cost": 80, "dmg": 18.0, "rate": 0.7, "range": 2.4,
	 "air": false, "ground": true, "col": Color("ff9a3c"), "key": "4", "splash": 0.9,
	 "desc": "Lobbed charges with splash. Ground only.",
	 "branches": [
		{"name": "Radius", "desc": "+0.3 blast radius", "mods": {"splash": 0.3}},
		{"name": "Payload", "desc": "+40% damage", "mods": {"dmg%": 0.40}},
		{"name": "Fuse", "desc": "+25% fire rate", "mods": {"rate%": 0.25}}]},
	{"id": "cryo", "name": "Cryo Fan", "kind": "aura", "cost": 60, "dmg": 2.0, "rate": 2.0, "range": 1.6,
	 "air": true, "ground": true, "col": Color("9ff3ff"), "key": "5", "slow": 0.30,
	 "desc": "Chills everything nearby. Slows enemies.",
	 "branches": [
		{"name": "Chill", "desc": "+10% slow", "mods": {"slow": 0.10}},
		{"name": "Spread", "desc": "+0.4 range", "mods": {"range": 0.4}},
		{"name": "Shatter", "desc": "+5 frost damage", "mods": {"dmg": 5.0}}]},
	{"id": "rail", "name": "Railgun", "kind": "rail", "cost": 130, "dmg": 60.0, "rate": 0.4, "range": 4.2,
	 "air": true, "ground": true, "col": Color("ffffff"), "key": "6", "pierce": 3,
	 "desc": "Long-range slug that pierces a whole line.",
	 "branches": [
		{"name": "Slug", "desc": "+40% damage", "mods": {"dmg%": 0.40}},
		{"name": "Pierce", "desc": "+2 targets", "mods": {"pierce": 2}},
		{"name": "Capacitor", "desc": "+30% fire rate", "mods": {"rate%": 0.30}}]},
	{"id": "flak", "name": "Flak Array", "kind": "flak", "cost": 65, "dmg": 10.0, "rate": 2.5, "range": 3.2,
	 "air": true, "ground": false, "col": Color("b98cff"), "key": "7", "splash": 0.6,
	 "desc": "Anti-air bursts. Shreds drones. Air only.",
	 "branches": [
		{"name": "Autoloader", "desc": "+30% fire rate", "mods": {"rate%": 0.30}},
		{"name": "Burst", "desc": "+0.25 splash", "mods": {"splash": 0.25}},
		{"name": "Radar", "desc": "+0.6 range", "mods": {"range": 0.6}}]},
	{"id": "virus", "name": "Virus Injector", "kind": "virus", "cost": 75, "dmg": 4.0, "rate": 1.0, "range": 2.4,
	 "air": true, "ground": true, "col": Color("a6ff00"), "key": "8", "dot": 8.0, "dotdur": 3.0, "spread": 0.0,
	 "desc": "Infects enemies with damage over time.",
	 "branches": [
		{"name": "Potency", "desc": "+60% infection dps", "mods": {"dot%": 0.60}},
		{"name": "Contagion", "desc": "Spreads on death (+0.7)", "mods": {"spread": 0.7}},
		{"name": "Persist", "desc": "+1.5s duration", "mods": {"dotdur": 1.5}}]},
	{"id": "miner", "name": "Bit Miner", "kind": "miner", "cost": 90, "dmg": 0.0, "rate": 1.0, "range": 1.8,
	 "air": true, "ground": true, "col": Color("ffcf33"), "key": "9", "yield": 18.0,
	 "desc": "Mines credits each wave. Economy tower.",
	 "branches": [
		{"name": "Yield", "desc": "+12 credits per wave", "mods": {"yield": 12.0}},
		{"name": "Interest", "desc": "+2% of bank per wave", "mods": {"interest": 0.02}},
		{"name": "Sparks", "desc": "Zaps enemies (+8 dmg)", "mods": {"dmg": 8.0}}]},
	{"id": "relay", "name": "Relay Hub", "kind": "relay", "cost": 100, "dmg": 0.0, "rate": 1.0, "range": 1.0,
	 "air": false, "ground": false, "col": Color("ff4d6d"), "key": "0", "buff_dmg": 0.15, "buff_rate": 0.0, "reach": 1,
	 "desc": "Boosts adjacent towers. The heart of combos.",
	 "branches": [
		{"name": "Power", "desc": "+10% neighbour damage", "mods": {"buff_dmg": 0.10}},
		{"name": "Sync", "desc": "+10% neighbour fire rate", "mods": {"buff_rate": 0.10}},
		{"name": "Reach", "desc": "Boost radius 2 (lvl 1)", "mods": {"reach": 1}}]},
]

# Named adjacency combos (in addition to generic links).
const COMBOS := [
	{"a": "arc", "b": "cryo", "name": "Superconductor", "desc": "Arc Coil +30% damage"},
	{"a": "bomb", "b": "virus", "name": "Dirty Bomb", "desc": "Bombs infect"},
	{"a": "laser", "b": "rail", "name": "Focused Array", "desc": "+0.5 range to both"},
	{"a": "pulse", "b": "flak", "name": "Crossfire", "desc": "Pulse +25% rate"},
	{"a": "miner", "b": "relay", "name": "Overmine", "desc": "Miner +50% yield"},
]

# ---------------------------------------------------------------- ENEMIES
# spd in cells per second. armor = flat reduction. shield absorbs first.
const ENEMIES := {
	"pulse":    {"name": "Bitling",   "hp": 30.0, "spd": 1.25, "rew": 4, "col": Color("39ff88"), "shape": 0, "size": 0.26},
	"sprinter": {"name": "Sprinter",  "hp": 22.0, "spd": 2.3, "rew": 4, "col": Color("ffe14d"), "shape": 1, "size": 0.24},
	"ironclad": {"name": "Ironclad",  "hp": 70.0, "spd": 0.85, "rew": 8, "col": Color("aebfd4"), "shape": 2, "size": 0.30, "armor": 4.0},
	"aegis":    {"name": "Aegis",     "hp": 40.0, "spd": 1.05, "rew": 8, "col": Color("4dd2ff"), "shape": 3, "size": 0.28, "shield": 50.0},
	"swarm":    {"name": "Swarmlet",  "hp": 10.0, "spd": 1.9, "rew": 1, "col": Color("ff7ad9"), "shape": 0, "size": 0.16},
	"drone":    {"name": "Drone",     "hp": 35.0, "spd": 1.35, "rew": 6, "col": Color("b98cff"), "shape": 4, "size": 0.26, "fly": true},
	"splitter": {"name": "Splitter",  "hp": 60.0, "spd": 1.0, "rew": 6, "col": Color("ff9a3c"), "shape": 5, "size": 0.30, "split": 2},
	"blinker":  {"name": "Blinker",   "hp": 45.0, "spd": 1.15, "rew": 8, "col": Color("e8f4ff"), "shape": 6, "size": 0.26, "blink": 3.2},
	"medic":    {"name": "Patcher",   "hp": 55.0, "spd": 0.95, "rew": 9, "col": Color("7dffb0"), "shape": 7, "size": 0.28, "heal": 2.2},
	"hive":     {"name": "Hive Core", "hp": 120.0, "spd": 0.7, "rew": 12, "col": Color("ffcf33"), "shape": 8, "size": 0.34, "spawn": "swarm", "spawn_t": 2.6},
	# internal (children / bosses)
	"splitlet": {"name": "Splitlet",  "hp": 20.0, "spd": 1.6, "rew": 2, "col": Color("ffbb77"), "shape": 5, "size": 0.18},
	"firewall": {"name": "FIREWALL",  "hp": 1700.0, "spd": 0.5, "rew": 160, "col": Color("ff4d4d"), "shape": 9, "size": 0.46, "shield": 500.0, "boss": true},
	"kernel":   {"name": "KERNEL PANIC", "hp": 4600.0, "spd": 0.45, "rew": 260, "col": Color("ff3df0"), "shape": 9, "size": 0.48, "armor": 9.0, "spawn": "sprinter", "spawn_t": 2.0, "boss": true},
	"singular": {"name": "SINGULARITY", "hp": 10000.0, "spd": 0.5, "rew": 400, "col": Color("ffffff"), "shape": 9, "size": 0.5, "shield": 1800.0, "blink": 4.0, "heal": 3.0, "boss": true},
}
const ENEMY_ORDER := ["pulse", "sprinter", "ironclad", "aegis", "swarm", "drone", "splitter", "blinker", "medic", "hive"]
const BOSSES := ["firewall", "kernel", "singular"]
const GAP := {"swarm": 0.32, "sprinter": 0.5, "hive": 1.8, "ironclad": 1.0, "splitter": 1.0, "medic": 1.2}

# ---------------------------------------------------------------- MAPS
# '.' open  '#' fixed chip (can't build)  'S' spawn  'E' exit core
const MAPS := [
	{"name": "Motherboard", "desc": "Wide open board. Learn to maze.", "cash": 220, "rows": [
		"................",
		"................",
		"...#........#...",
		"................",
		"................",
		"S..............E",
		"................",
		"................",
		"...#........#...",
		"................",
		"................"]},
	{"name": "Twin Bus", "desc": "Two spawn lanes merge on one core.", "cash": 260, "rows": [
		"................",
		"S...............",
		"................",
		"......##........",
		"................",
		"...............E",
		"................",
		"......##........",
		"................",
		"S...............",
		"................"]},
	{"name": "Chip Socket", "desc": "A giant CPU blocks the middle.", "cash": 240, "rows": [
		".......S........",
		"................",
		"................",
		"................",
		"......####......",
		"......####......",
		"......####......",
		"................",
		"................",
		"................",
		"........E......."]},
	{"name": "Crossfire", "desc": "Enemies arrive from both sides.", "cash": 280, "rows": [
		"................",
		"................",
		"..#..........#..",
		"................",
		"................",
		"S..............S",
		"................",
		"................",
		"..#....##....#..",
		"................",
		".......E........"]},
	{"name": "Serpent Trace", "desc": "A pre-etched serpent. Extend it.", "cash": 200, "rows": [
		"S...............",
		"................",
		"................",
		"############....",
		"................",
		"................",
		"................",
		"....############",
		"................",
		"................",
		"...............E"]},
]

const CHALLENGES := [
	{"id": "iron", "name": "Iron Grid", "desc": "Every enemy +3 armor and +20% HP."},
	{"id": "nowall", "name": "No Walls", "desc": "Walls disabled. Towers cost 15% less."},
	{"id": "rush", "name": "Overclock Rush", "desc": "Enemies 35% faster. Double kill credits."},
	{"id": "glass", "name": "Glass Core", "desc": "One life. One mistake ends it."},
]

const MODES := ["Campaign", "Endless", "Sandbox", "Challenge"]


static func tower_index(id: String) -> int:
	for i in TOWERS.size():
		if TOWERS[i]["id"] == id:
			return i
	return -1


static func hp_scale(n: int) -> float:
	var k := float(n - 1)
	var s := 1.0 + 0.13 * k + 0.008 * k * k
	if n > CAMPAIGN_WAVES:
		s *= pow(1.07, n - CAMPAIGN_WAVES)
	return s


## Returns a list of groups: {"type", "count", "gap", "delay"} for wave n (1-based).
static func wave(n: int) -> Array:
	var g: Array = []
	var fixed := {
		1: [["pulse", 8]],
		2: [["pulse", 10], ["sprinter", 4]],
		3: [["swarm", 18]],
		4: [["pulse", 8], ["ironclad", 4]],
		5: [["drone", 6], ["pulse", 8]],
		6: [["sprinter", 10], ["ironclad", 5]],
		7: [["aegis", 6], ["pulse", 10]],
		8: [["splitter", 6], ["swarm", 14]],
		9: [["blinker", 6], ["drone", 6]],
		11: [["ironclad", 8], ["medic", 3]],
		12: [["sprinter", 8], ["hive", 3]],
		13: [["aegis", 10], ["drone", 8]],
		14: [["splitter", 10], ["medic", 3]],
		15: [["ironclad", 8], ["blinker", 10]],
	}
	if n % 10 == 0:
		var b: String = BOSSES[(n / 10 - 1) % BOSSES.size()]
		var escort: String = ENEMY_ORDER[(n / 10 * 3) % ENEMY_ORDER.size()]
		g.append({"type": escort, "count": 6 + n / 3, "gap": 0.6, "delay": 0.0})
		g.append({"type": b, "count": 1 + max(0, (n - 30) / 30), "gap": 4.0, "delay": 4.0})
		if n >= 20:
			g.append({"type": "medic", "count": 3, "gap": 1.2, "delay": 6.0})
		return g
	if fixed.has(n):
		var d := 0.0
		for e in fixed[n]:
			var gap: float = GAP.get(e[0], 0.75)
			g.append({"type": e[0], "count": e[1], "gap": gap, "delay": d})
			d += 1.5
		return g
	# generated mixes for later waves (and endless)
	var rng := RandomNumberGenerator.new()
	rng.seed = n * 7919 + 13
	var groups := 3 if n < 25 else 4
	var d2 := 0.0
	for i in groups:
		var t: String = ENEMY_ORDER[rng.randi_range(0, ENEMY_ORDER.size() - 1)]
		var base := 7
		match t:
			"swarm": base = 16
			"hive": base = 2
			"medic": base = 3
			"ironclad", "splitter", "aegis": base = 5
		var cnt := int(base * (1.0 + float(n) / 18.0))
		var gap2: float = GAP.get(t, 0.7) * (0.85 if n > 20 else 1.0)
		g.append({"type": t, "count": cnt, "gap": gap2, "delay": d2})
		d2 += 2.0 + rng.randf() * 3.0
	return g


static func wave_summary(n: int) -> String:
	var parts: Array = []
	for gr in wave(n):
		parts.append("%dx %s" % [gr["count"], ENEMIES[gr["type"]]["name"]])
	return ", ".join(parts)
