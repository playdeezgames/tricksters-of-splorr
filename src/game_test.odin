#+build !js
package tricksters

import "core:log"
import "core:testing"

// Run with: odin test src -define:ODIN_TEST_THREADS=1

room :: proc(rows: ..string) -> Level {
	l: Level
	for r, i in rows {
		l.rows[i] = r
	}
	return l
}

EMPTY :: "################"

@(test)
bump_changes_nothing :: proc(t: ^testing.T) {
	g: Game
	game_load(&g, room(EMPTY, "#@.............#"))
	before := g
	testing.expect(t, !take_turn(&g, .Move_Up))
	testing.expect(t, g == before)
}

@(test)
prize_then_exit_wins :: proc(t: ^testing.T) {
	g: Game
	game_load(&g, room(EMPTY, "#@$E...........#"))
	testing.expect(t, take_turn(&g, .Move_Right))
	testing.expect(t, g.has_prize)
	testing.expect_value(t, g.tiles[1][2], Tile.Floor)
	testing.expect_value(t, g.status, Status.Playing)
	take_turn(&g, .Move_Right)
	testing.expect_value(t, g.status, Status.Won)
}

@(test)
exit_without_prize_does_not_win :: proc(t: ^testing.T) {
	g: Game
	game_load(&g, room(EMPTY, "#@E.............#"))
	take_turn(&g, .Move_Right)
	testing.expect_value(t, g.status, Status.Playing)
}

@(test)
guard_patrols_and_loops :: proc(t: ^testing.T) {
	l := room(EMPTY, "#@.............#", "#.>............#")
	l.patrols[0] = "RL"
	g: Game
	game_load(&g, l)
	testing.expect_value(t, g.guard_count, 1)
	testing.expect_value(t, g.guards[0].pos, [2]int{2, 2})
	take_turn(&g, .Wait)
	testing.expect_value(t, g.guards[0].pos, [2]int{3, 2})
	testing.expect_value(t, g.guards[0].facing, Dir.Right)
	take_turn(&g, .Wait)
	testing.expect_value(t, g.guards[0].pos, [2]int{2, 2})
	testing.expect_value(t, g.guards[0].facing, Dir.Left)
	take_turn(&g, .Wait)
	testing.expect_value(t, g.guards[0].pos, [2]int{3, 2})
}

@(test)
guard_is_stopped_by_walls :: proc(t: ^testing.T) {
	l := room("################")
	l.rows[1] = "#@>#............"
	l.patrols[0] = "R"
	g: Game
	game_load(&g, l)
	take_turn(&g, .Wait)
	testing.expect_value(t, g.guards[0].pos, [2]int{2, 1}) // blocked, but still faces right
	testing.expect_value(t, g.guards[0].facing, Dir.Right)
}

@(test)
cone_has_range_and_stops_at_walls :: proc(t: ^testing.T) {
	l := room(EMPTY)
	l.rows[1] = "#>....#........."
	l.rows[2] = "#>.#............"
	g: Game
	game_load(&g, l)
	cone: [SIGHT_RANGE][2]int
	n := cone_cells(&g, g.guards[0], &cone)
	testing.expect_value(t, n, SIGHT_RANGE)
	testing.expect_value(t, cone[0], [2]int{2, 1})
	testing.expect_value(t, cone[2], [2]int{4, 1})
	n = cone_cells(&g, g.guards[1], &cone)
	testing.expect_value(t, n, 1) // wall at x=3 blocks the rest
}

@(test)
walking_into_cone_gets_you_caught :: proc(t: ^testing.T) {
	l := room(EMPTY)
	l.rows[1] = "#.>.............#"
	l.rows[2] = "#@..............#"
	g: Game
	game_load(&g, l)
	// The guard has no patrol, faces right, and sees (3,1) (4,1) (5,1).
	testing.expect(t, take_turn(&g, .Move_Right))
	testing.expect_value(t, g.status, Status.Playing)
	take_turn(&g, .Move_Right)
	take_turn(&g, .Move_Right)
	take_turn(&g, .Move_Up)
	testing.expect_value(t, g.status, Status.Caught)
	testing.expect(t, !take_turn(&g, .Wait)) // over until undone
}

@(test)
guard_walking_onto_you_catches_you :: proc(t: ^testing.T) {
	l := room(EMPTY)
	l.rows[1] = "#@>.............#"
	l.patrols[0] = "L"
	g: Game
	game_load(&g, l)
	// Guard steps left onto the player's tile; its own tile counts as seen.
	take_turn(&g, .Wait)
	testing.expect_value(t, g.status, Status.Caught)
}

@(test)
undo_restores_exactly :: proc(t: ^testing.T) {
	h := new(History)
	defer free(h)
	g: Game
	game_load(&g, levels[0])
	start := g
	testing.expect(t, !undo(h, &g))
	testing.expect(t, play(h, &g, .Move_Right))
	testing.expect(t, play(h, &g, .Wait))
	testing.expect(t, undo(h, &g))
	testing.expect(t, undo(h, &g))
	testing.expect(t, g == start)
}

@(test)
bump_is_not_recorded_in_history :: proc(t: ^testing.T) {
	h := new(History)
	defer free(h)
	g: Game
	game_load(&g, levels[0])
	testing.expect(t, !play(h, &g, .Move_Up))
	testing.expect_value(t, h.count, 0)
}

@(test)
undo_after_caught_resumes_play :: proc(t: ^testing.T) {
	h := new(History)
	defer free(h)
	l := room(EMPTY, "#@..<...........#", "#..............#")
	g: Game
	game_load(&g, l)
	// The guard at (4,1) faces left and sees (3,1) (2,1) (1,1); the player starts at (1,1),
	// so waiting is already fatal, and moving down escapes.
	testing.expect(t, play(h, &g, .Wait))
	testing.expect_value(t, g.status, Status.Caught)
	testing.expect(t, undo(h, &g))
	testing.expect_value(t, g.status, Status.Playing)
	testing.expect(t, play(h, &g, .Move_Down))
	testing.expect_value(t, g.status, Status.Playing)
}

// Breadth-first search over real turns. Returns the fewest turns to win, or -1.
solve :: proc(level: Level) -> int {
	start: Game
	game_load(&start, level)
	visited := make(map[State_Key]struct{})
	defer delete(visited)
	cur := make([dynamic]Game)
	next := make([dynamic]Game)
	defer delete(cur)
	defer delete(next)
	append(&cur, start)
	visited[state_key(&start)] = {}
	for len(cur) > 0 {
		clear(&next)
		for s in cur {
			for a in Action {
				n := s
				if !take_turn(&n, a) {
					continue
				}
				if n.status == .Won {
					return n.turn
				}
				if n.status != .Playing {
					continue
				}
				k := state_key(&n)
				if k in visited {
					continue
				}
				visited[k] = {}
				append(&next, n)
			}
		}
		cur, next = next, cur
	}
	return -1
}

@(test)
every_level_is_solvable :: proc(t: ^testing.T) {
	for l in levels {
		par := solve(l)
		testing.expectf(t, par > 0, "level %q cannot be solved", l.name)
		log.infof("level %q par %d", l.name, par)
	}
}

@(test)
solver_reports_unsolvable :: proc(t: ^testing.T) {
	l := room(EMPTY, "#@#$E..........#", EMPTY) // walls seal the player in
	testing.expect_value(t, solve(l), -1)
}
