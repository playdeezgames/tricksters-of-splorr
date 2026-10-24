package tricksters

// Pure rules: no browser imports, so this compiles and tests natively.
// Turn order: the player acts, then every guard acts, then the status is judged.

COLS :: 16
ROWS :: 12

MAX_GUARDS  :: 6
MAX_PATROL  :: 24
SIGHT_RANGE :: 3
MAX_HISTORY :: 512

COIN_RANGE  :: 4 // a tossed coin flies this far in a straight line, or until a wall
HEARING     :: 5 // guards this close (in tiles, Manhattan) to where the coin lands go and look
STARE_TURNS :: 2 // turns a guard stays at the coin before walking home
LOOK_RANGE  :: 3 // "Look over there!" reaches the first guard this close in a straight line
HAT_TURNS   :: 6 // end-of-turn checks a hat covers, the turn you pick it up included
LOOK_TURNS  :: 3 // the guard faces the way you pointed for this many turns, the pointing turn included

Tile :: enum u8 {
	Floor,
	Wall,
	Prize,
	Exit,
	Hat_Red,  // picking one up disguises you as that faction
	Hat_Blue,
	Door, // locked: blocks movement and sight until the player walks into it holding a key
}

Dir :: enum {
	Up,
	Down,
	Left,
	Right,
}

// Move_* and Toss_* are in Dir order, so Dir(int(a)) and Dir(int(a) - int(Action.Toss_Up)) convert.
Action :: enum {
	Move_Up,
	Move_Down,
	Move_Left,
	Move_Right,
	Wait,
	Toss_Up,
	Toss_Down,
	Toss_Left,
	Toss_Right,
	Pickpocket, // lift the key from an adjacent guard who cannot see you
	Point_Up, // "Look over there!": the nearest guard in line that way turns to face that way
	Point_Down,
	Point_Left,
	Point_Right,
}

// A disguise hides the player from guards of the same faction only.
Faction :: enum u8 {
	Red,
	Blue,
}

// Patrol follows the patrol string. A coin sends the guard to Investigate its landing tile,
// Stare at it, then Return to the tile it left (home) and resume the patrol where it stopped.
Guard_Mode :: enum u8 {
	Patrol,
	Investigate,
	Stare,
	Return,
}

Status :: enum {
	Playing,
	Caught,
	Won,
}

Guard :: struct {
	pos:        [2]int,
	facing:     Dir,
	patrol:     [MAX_PATROL]u8, // 'U' 'D' 'L' 'R' step and face that way, '.' hold
	patrol_len: int,
	patrol_idx: int,
	mode:       Guard_Mode,
	target:     [2]int, // the coin
	timer:      int,
	home:       [2]int,
	home_facing: Dir,
	has_key:    bool,
	faction:    Faction,
	stun:       int,  // turns left of being made to look away
	turned:     bool, // facing is overridden; pre_look is restored when the stun ends
	pre_look:   Dir,
}

// Plain data only (no pointers, slices or maps), so a copy is a snapshot.
Game :: struct {
	tiles:       [ROWS][COLS]Tile,
	player:      [2]int,
	guards:      [MAX_GUARDS]Guard,
	guard_count: int,
	has_prize:   bool,
	coins:       int,
	keys:        int,
	points:      int,
	disguise:    Faction, // meaningful while disguise_turns > 0
	disguise_turns: int,
	status:      Status,
	turn:        int,
}

History :: struct {
	states: [MAX_HISTORY]Game,
	count:  int,
}

Level :: struct {
	name:    string,
	intro:   string, // the trickster's patter when the level starts
	act:     int,    // index into ACT_TITLES; a change of act shows an act card
	par:     int,    // the solver's shortest winning run (a test keeps this honest)
	coins:   int,
	points:  int, // uses of "Look over there!"
	rows:    [ROWS]string,
	patrols: [MAX_GUARDS]string, // one per guard, in reading order of the map
	keyed:   [MAX_GUARDS]bool,   // which guards carry a key
	blue:    [MAX_GUARDS]bool,   // which guards are Blue (the rest are Red)
}

// Walls and locked doors stop guards, sight and coins.
blocks :: proc(t: Tile) -> bool {
	return t == .Wall || t == .Door
}

dir_delta :: proc(d: Dir) -> [2]int {
	switch d {
	case .Up:    return {0, -1}
	case .Down:  return {0, 1}
	case .Left:  return {-1, 0}
	case .Right: return {1, 0}
	}
	return {}
}

in_bounds :: proc(p: [2]int) -> bool {
	return p.x >= 0 && p.x < COLS && p.y >= 0 && p.y < ROWS
}

// Map glyphs: 'h' red hat, 'H' blue hat, '#' wall, 'D' locked door, '$' prize, 'E' exit, '@' player start, '^' 'v' '<' '>' a guard facing that way.
game_load :: proc(g: ^Game, level: Level) {
	g^ = {}
	g.coins = level.coins
	g.points = level.points
	for row, y in level.rows {
		for x in 0 ..< COLS {
			c := x < len(row) ? row[x] : ' '
			switch c {
			case '#': g.tiles[y][x] = .Wall
			case '$': g.tiles[y][x] = .Prize
			case 'E': g.tiles[y][x] = .Exit
			case 'D': g.tiles[y][x] = .Door
			case 'h': g.tiles[y][x] = .Hat_Red
			case 'H': g.tiles[y][x] = .Hat_Blue
			case '@': g.player = {x, y}
			case '^', 'v', '<', '>':
				if g.guard_count < MAX_GUARDS {
					gd := &g.guards[g.guard_count]
					gd.pos = {x, y}
					switch c {
					case '^': gd.facing = .Up
					case 'v': gd.facing = .Down
					case '<': gd.facing = .Left
					case '>': gd.facing = .Right
					}
					patrol := level.patrols[g.guard_count]
					for i in 0 ..< min(len(patrol), MAX_PATROL) {
						gd.patrol[i] = patrol[i]
					}
					gd.patrol_len = min(len(patrol), MAX_PATROL)
					gd.has_key = level.keyed[g.guard_count]
					gd.faction = level.blue[g.guard_count] ? .Blue : .Red
					g.guard_count += 1
				}
			}
		}
	}
}

guard_at :: proc(g: ^Game, p: [2]int) -> bool {
	for i in 0 ..< g.guard_count {
		if g.guards[i].pos == p {
			return true
		}
	}
	return false
}

// Fills out with the tiles the guard sees (straight ahead, stopped by walls) and returns how many.
cone_cells :: proc(g: ^Game, gd: Guard, out: ^[SIGHT_RANGE][2]int) -> int {
	n := 0
	d := dir_delta(gd.facing)
	p := gd.pos
	for _ in 0 ..< SIGHT_RANGE {
		p += d
		if !in_bounds(p) || blocks(g.tiles[p.y][p.x]) {
			break
		}
		out[n] = p
		n += 1
	}
	return n
}

// A guard is fooled while the player wears a hat of its own faction.
fooled :: proc(g: ^Game, gd: Guard) -> bool {
	return g.disguise_turns > 0 && g.disguise == gd.faction
}

// True if any guard that is not fooled sees p, or stands on it.
seen :: proc(g: ^Game, p: [2]int) -> bool {
	cone: [SIGHT_RANGE][2]int
	for i in 0 ..< g.guard_count {
		gd := g.guards[i]
		if fooled(g, gd) {
			continue
		}
		if gd.pos == p {
			return true
		}
		n := cone_cells(g, gd, &cone)
		for c in cone[:n] {
			if c == p {
				return true
			}
		}
	}
	return false
}

// Next step of a shortest path from one tile to another, walking around walls and other guards.
path_step :: proc(g: ^Game, from, to: [2]int) -> (d: Dir, ok: bool) {
	dist: [ROWS][COLS]int
	for y in 0 ..< ROWS {
		for x in 0 ..< COLS {
			dist[y][x] = -1
		}
	}
	queue: [ROWS * COLS][2]int
	head, tail := 0, 0
	dist[to.y][to.x] = 0
	queue[tail] = to
	tail += 1
	for head < tail {
		p := queue[head]
		head += 1
		for dd in Dir {
			q := p + dir_delta(dd)
			if !in_bounds(q) || blocks(g.tiles[q.y][q.x]) || dist[q.y][q.x] >= 0 {
				continue
			}
			dist[q.y][q.x] = dist[p.y][p.x] + 1
			queue[tail] = q
			tail += 1
		}
	}
	here := dist[from.y][from.x]
	if here <= 0 {
		return // unreachable, or already there
	}
	for dd in Dir {
		q := from + dir_delta(dd)
		if in_bounds(q) && !blocks(g.tiles[q.y][q.x]) && dist[q.y][q.x] == here - 1 && !guard_at(g, q) {
			return dd, true
		}
	}
	return
}

move_toward :: proc(g: ^Game, gd: ^Guard, to: [2]int) {
	if d, ok := path_step(g, gd.pos, to); ok {
		gd.facing = d
		if !(fooled(g, gd^) && gd.pos + dir_delta(d) == g.player) {
			gd.pos += dir_delta(d)
		}
	}
}

patrol_step :: proc(g: ^Game, gd: ^Guard) {
	if gd.patrol_len == 0 {
		return
	}
	step := gd.patrol[gd.patrol_idx]
	gd.patrol_idx = (gd.patrol_idx + 1) % gd.patrol_len
	d: Dir
	switch step {
	case 'U': d = .Up
	case 'D': d = .Down
	case 'L': d = .Left
	case 'R': d = .Right
	case: return
	}
	gd.facing = d
	to := gd.pos + dir_delta(d)
	if in_bounds(to) && !blocks(g.tiles[to.y][to.x]) && !guard_at(g, to) && !(fooled(g, gd^) && to == g.player) {
		gd.pos = to
	}
}

return_step :: proc(g: ^Game, gd: ^Guard) {
	move_toward(g, gd, gd.home)
	if gd.pos == gd.home {
		gd.mode = .Patrol
		gd.facing = gd.home_facing
	}
}

step_guards :: proc(g: ^Game) {
	for i in 0 ..< g.guard_count {
		gd := &g.guards[i]
		if gd.stun > 0 {
			gd.stun -= 1
			continue
		}
		if gd.turned {
			gd.facing = gd.pre_look
			gd.turned = false
		}
		switch gd.mode {
		case .Patrol:
			patrol_step(g, gd)
		case .Investigate:
			move_toward(g, gd, gd.target)
			if gd.pos == gd.target {
				gd.mode = .Stare
				gd.timer = STARE_TURNS
			}
		case .Stare:
			gd.timer -= 1
			if gd.timer <= 0 {
				gd.mode = .Return
				return_step(g, gd)
			}
		case .Return:
			return_step(g, gd)
		}
	}
}

// Where a coin tossed from the player's tile in direction d lands (the last open tile in range).
coin_landing :: proc(g: ^Game, d: Dir) -> (land: [2]int, ok: bool) {
	for i in 1 ..= COIN_RANGE {
		q := g.player + dir_delta(d) * i
		if !in_bounds(q) || blocks(g.tiles[q.y][q.x]) {
			break
		}
		land = q
		ok = true
	}
	return
}

// Takes the key from the first adjacent guard that has one and is not looking at the player.
pick_pocket :: proc(g: ^Game) -> bool {
	cone: [SIGHT_RANGE][2]int
	for i in 0 ..< g.guard_count {
		gd := &g.guards[i]
		if !gd.has_key || abs_int(gd.pos.x - g.player.x) + abs_int(gd.pos.y - g.player.y) != 1 {
			continue
		}
		n := cone_cells(g, gd^, &cone)
		watched := false
		for c in cone[:n] {
			watched ||= c == g.player
		}
		if watched {
			continue
		}
		gd.has_key = false
		g.keys += 1
		return true
	}
	return false
}

// The first guard in a straight line from the player in direction d, within LOOK_RANGE.
look_target :: proc(g: ^Game, d: Dir) -> (index: int, ok: bool) {
	for i in 1 ..= LOOK_RANGE {
		q := g.player + dir_delta(d) * i
		if !in_bounds(q) || blocks(g.tiles[q.y][q.x]) {
			return
		}
		for gi in 0 ..< g.guard_count {
			if g.guards[gi].pos == q {
				return gi, true
			}
		}
	}
	return
}

abs_int :: proc(n: int) -> int {
	return n < 0 ? -n : n
}

distract_guards :: proc(g: ^Game, land: [2]int) {
	for i in 0 ..< g.guard_count {
		gd := &g.guards[i]
		if abs_int(land.x - gd.pos.x) + abs_int(land.y - gd.pos.y) > HEARING {
			continue
		}
		if gd.mode == .Patrol {
			gd.home = gd.pos
			gd.home_facing = gd.facing
		}
		gd.mode = .Investigate
		gd.target = land
	}
}

// Runs one whole turn. Returns false, changing nothing, if the action did nothing
// (a bump into a wall, or the level is already over).
take_turn :: proc(g: ^Game, a: Action) -> bool {
	if g.status != .Playing {
		return false
	}
	switch a {
	case .Wait:
	case .Move_Up, .Move_Down, .Move_Left, .Move_Right:
		to := g.player + dir_delta(Dir(int(a)))
		if !in_bounds(to) || g.tiles[to.y][to.x] == .Wall {
			return false
		}
		if guard_at(g, to) {
			return false // guards are solid, disguised or not
		}
		if g.tiles[to.y][to.x] == .Door {
			if g.keys <= 0 {
				return false
			}
			g.keys -= 1
			g.tiles[to.y][to.x] = .Floor
		}
		g.player = to
		switch g.tiles[to.y][to.x] {
		case .Prize:
			g.has_prize = true
			g.tiles[to.y][to.x] = .Floor
		case .Hat_Red, .Hat_Blue:
			g.disguise = g.tiles[to.y][to.x] == .Hat_Red ? .Red : .Blue
			g.disguise_turns = HAT_TURNS
			g.tiles[to.y][to.x] = .Floor
		case .Floor, .Wall, .Exit, .Door:
		}
	case .Pickpocket:
		if !pick_pocket(g) {
			return false
		}
	case .Point_Up, .Point_Down, .Point_Left, .Point_Right:
		d := Dir(int(a) - int(Action.Point_Up))
		gi, ok := look_target(g, d)
		if g.points <= 0 || !ok {
			return false
		}
		g.points -= 1
		gd := &g.guards[gi]
		if !gd.turned {
			gd.pre_look = gd.facing
			gd.turned = true
		}
		gd.facing = d
		gd.stun = LOOK_TURNS
	case .Toss_Up, .Toss_Down, .Toss_Left, .Toss_Right:
		if g.coins <= 0 {
			return false
		}
		land, ok := coin_landing(g, Dir(int(a) - int(Action.Toss_Up)))
		if !ok {
			return false
		}
		g.coins -= 1
		distract_guards(g, land)
	}
	step_guards(g)
	g.turn += 1
	if seen(g, g.player) {
		g.status = .Caught
	} else if g.has_prize && g.tiles[g.player.y][g.player.x] == .Exit {
		g.status = .Won
	}
	if g.disguise_turns > 0 {
		g.disguise_turns -= 1
	}
	return true
}

// take_turn with an undo snapshot taken first.
play :: proc(h: ^History, g: ^Game, a: Action) -> bool {
	before := g^
	if !take_turn(g, a) {
		return false
	}
	if h.count == MAX_HISTORY {
		copy(h.states[:MAX_HISTORY - 1], h.states[1:])
		h.count -= 1
	}
	h.states[h.count] = before
	h.count += 1
	return true
}

undo :: proc(h: ^History, g: ^Game) -> bool {
	if h.count == 0 {
		return false
	}
	h.count -= 1
	g^ = h.states[h.count]
	return true
}

// Everything that distinguishes two states for the solver (the turn counter is left out).
GUARD_KEY_BYTES :: 16
HEADER_KEY_BYTES :: 9
DOOR_KEY_BYTES  :: (ROWS * COLS + 7) / 8
State_Key :: [HEADER_KEY_BYTES + MAX_GUARDS * GUARD_KEY_BYTES + 2 * DOOR_KEY_BYTES]u8

state_key :: proc(g: ^Game) -> (k: State_Key) {
	n := 0
	put :: proc(k: ^State_Key, n: ^int, v: int) {
		k[n^] = u8(v)
		n^ += 1
	}
	put(&k, &n, g.player.x)
	put(&k, &n, g.player.y)
	put(&k, &n, int(g.has_prize))
	put(&k, &n, int(g.status))
	put(&k, &n, g.coins)
	put(&k, &n, g.keys)
	put(&k, &n, g.points)
	put(&k, &n, int(g.disguise))
	put(&k, &n, g.disguise_turns)
	for i in 0 ..< MAX_GUARDS {
		if i >= g.guard_count {
			n += GUARD_KEY_BYTES
			continue
		}
		gd := g.guards[i]
		put(&k, &n, gd.pos.x)
		put(&k, &n, gd.pos.y)
		put(&k, &n, int(gd.facing))
		put(&k, &n, gd.patrol_idx)
		put(&k, &n, int(gd.mode))
		put(&k, &n, gd.timer)
		put(&k, &n, gd.target.x)
		put(&k, &n, gd.target.y)
		put(&k, &n, gd.home.x)
		put(&k, &n, gd.home.y)
		put(&k, &n, int(gd.home_facing))
		put(&k, &n, int(gd.has_key))
		put(&k, &n, gd.stun)
		put(&k, &n, int(gd.turned))
		put(&k, &n, int(gd.pre_look))
		put(&k, &n, int(gd.faction))
	}
	// Which doors are still locked, then which hats are still on the floor.
	for y in 0 ..< ROWS {
		for x in 0 ..< COLS {
			bit := y * COLS + x
			#partial switch g.tiles[y][x] {
			case .Door:
				k[n + bit / 8] |= 1 << uint(bit % 8)
			case .Hat_Red, .Hat_Blue:
				k[n + DOOR_KEY_BYTES + bit / 8] |= 1 << uint(bit % 8)
			}
		}
	}
	return
}
