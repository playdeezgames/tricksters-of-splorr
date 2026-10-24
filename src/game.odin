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

Tile :: enum u8 {
	Floor,
	Wall,
	Prize,
	Exit,
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
}

// Plain data only (no pointers, slices or maps), so a copy is a snapshot.
Game :: struct {
	tiles:       [ROWS][COLS]Tile,
	player:      [2]int,
	guards:      [MAX_GUARDS]Guard,
	guard_count: int,
	has_prize:   bool,
	coins:       int,
	status:      Status,
	turn:        int,
}

History :: struct {
	states: [MAX_HISTORY]Game,
	count:  int,
}

Level :: struct {
	name:    string,
	coins:   int,
	rows:    [ROWS]string,
	patrols: [MAX_GUARDS]string, // one per guard, in reading order of the map
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

// Map glyphs: '#' wall, '$' prize, 'E' exit, '@' player start, '^' 'v' '<' '>' a guard facing that way.
game_load :: proc(g: ^Game, level: Level) {
	g^ = {}
	g.coins = level.coins
	for row, y in level.rows {
		for x in 0 ..< COLS {
			c := x < len(row) ? row[x] : ' '
			switch c {
			case '#': g.tiles[y][x] = .Wall
			case '$': g.tiles[y][x] = .Prize
			case 'E': g.tiles[y][x] = .Exit
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
		if !in_bounds(p) || g.tiles[p.y][p.x] == .Wall {
			break
		}
		out[n] = p
		n += 1
	}
	return n
}

// True if any guard sees p, or stands on it.
seen :: proc(g: ^Game, p: [2]int) -> bool {
	cone: [SIGHT_RANGE][2]int
	for i in 0 ..< g.guard_count {
		gd := g.guards[i]
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
			if !in_bounds(q) || g.tiles[q.y][q.x] == .Wall || dist[q.y][q.x] >= 0 {
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
		if in_bounds(q) && g.tiles[q.y][q.x] != .Wall && dist[q.y][q.x] == here - 1 && !guard_at(g, q) {
			return dd, true
		}
	}
	return
}

move_toward :: proc(g: ^Game, gd: ^Guard, to: [2]int) {
	if d, ok := path_step(g, gd.pos, to); ok {
		gd.facing = d
		gd.pos += dir_delta(d)
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
	if in_bounds(to) && g.tiles[to.y][to.x] != .Wall && !guard_at(g, to) {
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
		if !in_bounds(q) || g.tiles[q.y][q.x] == .Wall {
			break
		}
		land = q
		ok = true
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
		g.player = to
		if g.tiles[to.y][to.x] == .Prize {
			g.has_prize = true
			g.tiles[to.y][to.x] = .Floor
		}
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
GUARD_KEY_BYTES :: 11
State_Key :: [5 + MAX_GUARDS * GUARD_KEY_BYTES]u8

state_key :: proc(g: ^Game) -> (k: State_Key) {
	k[0] = u8(g.player.x)
	k[1] = u8(g.player.y)
	k[2] = u8(g.has_prize)
	k[3] = u8(g.status)
	k[4] = u8(g.coins)
	for i in 0 ..< g.guard_count {
		gd := g.guards[i]
		o := 5 + i * GUARD_KEY_BYTES
		k[o + 0] = u8(gd.pos.x)
		k[o + 1] = u8(gd.pos.y)
		k[o + 2] = u8(gd.facing)
		k[o + 3] = u8(gd.patrol_idx)
		k[o + 4] = u8(gd.mode)
		k[o + 5] = u8(gd.timer)
		k[o + 6] = u8(gd.target.x)
		k[o + 7] = u8(gd.target.y)
		k[o + 8] = u8(gd.home.x)
		k[o + 9] = u8(gd.home.y)
		k[o + 10] = u8(gd.home_facing)
	}
	return
}
