package tricksters

// Pure rules: no browser imports, so this compiles and tests natively.
// Turn order: the player acts, then every guard acts, then the status is judged.

COLS :: 16
ROWS :: 12

MAX_GUARDS  :: 6
MAX_PATROL  :: 24
SIGHT_RANGE :: 3
MAX_HISTORY :: 512

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

// The first four match Dir, so Dir(int(action)) is a move.
Action :: enum {
	Move_Up,
	Move_Down,
	Move_Left,
	Move_Right,
	Wait,
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
}

// Plain data only (no pointers, slices or maps), so a copy is a snapshot.
Game :: struct {
	tiles:       [ROWS][COLS]Tile,
	player:      [2]int,
	guards:      [MAX_GUARDS]Guard,
	guard_count: int,
	has_prize:   bool,
	status:      Status,
	turn:        int,
}

History :: struct {
	states: [MAX_HISTORY]Game,
	count:  int,
}

Level :: struct {
	name:    string,
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

step_guards :: proc(g: ^Game) {
	for i in 0 ..< g.guard_count {
		gd := &g.guards[i]
		if gd.patrol_len == 0 {
			continue
		}
		step := gd.patrol[gd.patrol_idx]
		gd.patrol_idx = (gd.patrol_idx + 1) % gd.patrol_len
		d: Dir
		switch step {
		case 'U': d = .Up
		case 'D': d = .Down
		case 'L': d = .Left
		case 'R': d = .Right
		case: continue
		}
		gd.facing = d
		to := gd.pos + dir_delta(d)
		if in_bounds(to) && g.tiles[to.y][to.x] != .Wall && !guard_at(g, to) {
			gd.pos = to
		}
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
State_Key :: [4 + MAX_GUARDS * 4]u8

state_key :: proc(g: ^Game) -> (k: State_Key) {
	k[0] = u8(g.player.x)
	k[1] = u8(g.player.y)
	k[2] = u8(g.has_prize)
	k[3] = u8(g.status)
	for i in 0 ..< g.guard_count {
		gd := g.guards[i]
		k[4 + i * 4 + 0] = u8(gd.pos.x)
		k[4 + i * 4 + 1] = u8(gd.pos.y)
		k[4 + i * 4 + 2] = u8(gd.facing)
		k[4 + i * 4 + 3] = u8(gd.patrol_idx)
	}
	return
}
