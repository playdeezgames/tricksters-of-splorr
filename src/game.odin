package tricksters

// Pure rules: no browser imports, so this compiles and tests natively.

COLS :: 16
ROWS :: 12

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

Action :: enum {
	Move_Up,
	Move_Down,
	Move_Left,
	Move_Right,
	Wait,
}

Game :: struct {
	tiles:       [ROWS][COLS]Tile,
	player:      [2]int, // x, y
	has_prize:   bool,
	turn:        int,
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

// '#' wall, '.' floor, '$' prize, 'E' exit, '@' player start.
game_load :: proc(g: ^Game, rows: [ROWS]string) {
	g^ = {}
	for row, y in rows {
		for x in 0 ..< COLS {
			c := x < len(row) ? row[x] : ' '
			switch c {
			case '#': g.tiles[y][x] = .Wall
			case '$': g.tiles[y][x] = .Prize
			case 'E': g.tiles[y][x] = .Exit
			case '@': g.player = {x, y}
			}
		}
	}
}

in_bounds :: proc(p: [2]int) -> bool {
	return p.x >= 0 && p.x < COLS && p.y >= 0 && p.y < ROWS
}

// Runs one whole turn. Returns false if the action did nothing (a bump).
take_turn :: proc(g: ^Game, a: Action) -> bool {
	switch a {
	case .Wait:
	case .Move_Up, .Move_Down, .Move_Left, .Move_Right:
		d := Dir(int(a))
		to := g.player + dir_delta(d)
		if !in_bounds(to) || g.tiles[to.y][to.x] == .Wall {
			return false
		}
		g.player = to
		if g.tiles[to.y][to.x] == .Prize {
			g.has_prize = true
			g.tiles[to.y][to.x] = .Floor
		}
	}
	g.turn += 1
	return true
}
