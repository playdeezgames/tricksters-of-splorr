#+build !js
package tricksters

import "core:log"
import "core:slice"
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
	return solve_from(start)
}

start_of :: proc(level: Level) -> Game {
	g: Game
	game_load(&g, level)
	return g
}

solve_unguarded :: proc(level: Level) -> int {
	start: Game
	game_load(&start, level)
	start.guard_count = 0
	return solve_from(start)
}

solve_from :: proc(start: Game) -> int {
	turns, _ := solve_with_path(start)
	return turns
}

// Breadth-first search; also returns the winning actions as text (U D L R . for moves and wait,
// u d l r for coin tosses, p for a pickpocket, ^ v < > for Look over there) so a human can replay the level.
solve_with_path :: proc(start: Game) -> (turns: int, path: string) {
	Node :: struct {
		game:   Game,
		parent: int,
		action: Action,
	}
	nodes := make([dynamic]Node)
	defer delete(nodes)
	visited := make(map[State_Key]struct{})
	defer delete(visited)
	append(&nodes, Node{game = start, parent = -1})
	visited[state_key(&nodes[0].game)] = {}
	glyph := [Action]u8{
		.Move_Up = 'U', .Move_Down = 'D', .Move_Left = 'L', .Move_Right = 'R', .Wait = '.',
		.Toss_Up = 'u', .Toss_Down = 'd', .Toss_Left = 'l', .Toss_Right = 'r', .Pickpocket = 'p',
		.Point_Up = '^', .Point_Down = 'v', .Point_Left = '<', .Point_Right = '>',
	}
	for head := 0; head < len(nodes); head += 1 {
		for a in Action {
			n := nodes[head].game
			if !take_turn(&n, a) {
				continue
			}
			if n.status == .Won {
				buf := make([dynamic]u8, context.temp_allocator)
				append(&buf, glyph[a])
				for i := head; nodes[i].parent >= 0; i = nodes[i].parent {
					append(&buf, glyph[nodes[i].action])
				}
				slice.reverse(buf[:])
				return n.turn, string(buf[:])
			}
			if n.status != .Playing {
				continue
			}
			k := state_key(&n)
			if k in visited {
				continue
			}
			visited[k] = {}
			append(&nodes, Node{game = n, parent = head, action = a})
		}
	}
	return -1, ""
}

@(test)
every_level_is_solvable :: proc(t: ^testing.T) {
	for l in levels {
		par := solve(l)
		testing.expectf(t, par > 0, "level %q cannot be solved", l.name)
		_, path := solve_with_path(start_of(l))
		log.infof("level %q par %d, with no guards %d, solution %s", l.name, par, solve_unguarded(l), path)
	}
}

// The first level must make the guard matter: the par beats the walk with no guards.
@(test)
first_level_forces_timing :: proc(t: ^testing.T) {
	par := solve(levels[0])
	open := solve_unguarded(levels[0])
	testing.expectf(t, par > open, "par %d is not longer than the unguarded walk %d", par, open)
}

@(test)
coin_level_needs_the_coin :: proc(t: ^testing.T) {
	l := levels[1]
	testing.expect(t, solve(l) > 0)
	l.coins = 0
	testing.expect_value(t, solve(l), -1)
}

@(test)
solver_reports_unsolvable :: proc(t: ^testing.T) {
	l := room(EMPTY, "#@#$E..........#", EMPTY) // walls seal the player in
	testing.expect_value(t, solve(l), -1)
}

@(test)
toss_with_no_coins_does_nothing :: proc(t: ^testing.T) {
	g: Game
	game_load(&g, room(EMPTY, "#@.............#"))
	before := g
	testing.expect(t, !take_turn(&g, .Toss_Right))
	testing.expect(t, g == before)
}

@(test)
toss_into_adjacent_wall_does_nothing :: proc(t: ^testing.T) {
	l := room(EMPTY, "#@.............#")
	l.coins = 1
	g: Game
	game_load(&g, l)
	testing.expect(t, !take_turn(&g, .Toss_Left))
	testing.expect_value(t, g.coins, 1)
}

@(test)
coin_flies_four_tiles_or_to_the_wall :: proc(t: ^testing.T) {
	l := room(EMPTY, "#@....#........#")
	l.coins = 2
	g: Game
	game_load(&g, l)
	land, ok := coin_landing(&g, .Right)
	testing.expect(t, ok)
	testing.expect_value(t, land, [2]int{5, 1}) // range 4 runs to x=5, one short of the wall at 6
	g.player = {3, 1}
	land, ok = coin_landing(&g, .Right)
	testing.expect_value(t, land, [2]int{5, 1}) // stopped by the wall
	testing.expect(t, take_turn(&g, .Toss_Right))
	testing.expect_value(t, g.coins, 1)
}

@(test)
coin_pulls_a_guard_away_and_it_comes_home :: proc(t: ^testing.T) {
	l := room(EMPTY, "#@.......<......#")
	l.coins = 1
	g: Game
	game_load(&g, l)
	home := g.guards[0].pos
	testing.expect(t, take_turn(&g, .Toss_Right)) // lands at (5,1); the guard hears it
	gd := &g.guards[0]
	testing.expect_value(t, gd.mode, Guard_Mode.Investigate)
	testing.expect_value(t, gd.pos, [2]int{8, 1})
	for expected in ([?]int{7, 6, 5}) {
		take_turn(&g, .Wait)
		testing.expect_value(t, gd.pos.x, expected)
	}
	testing.expect_value(t, gd.mode, Guard_Mode.Stare)
	take_turn(&g, .Wait) // still staring
	testing.expect_value(t, gd.pos.x, 5)
	take_turn(&g, .Wait) // stare over, first step home
	testing.expect_value(t, gd.mode, Guard_Mode.Return)
	testing.expect_value(t, gd.pos.x, 6)
	take_turn(&g, .Wait)
	take_turn(&g, .Wait)
	take_turn(&g, .Wait)
	testing.expect_value(t, gd.pos, home)
	testing.expect_value(t, gd.mode, Guard_Mode.Patrol)
	testing.expect_value(t, gd.facing, Dir.Left)
	testing.expect_value(t, g.status, Status.Playing)
}

@(test)
guard_out_of_earshot_ignores_the_coin :: proc(t: ^testing.T) {
	l := room(EMPTY, "#@............<#")
	l.coins = 1
	g: Game
	game_load(&g, l)
	testing.expect(t, take_turn(&g, .Toss_Right)) // lands at (5,1), nine tiles from the guard
	testing.expect_value(t, g.guards[0].mode, Guard_Mode.Patrol)
	testing.expect_value(t, g.guards[0].pos.x, 14)
}

@(test)
distracted_guard_resumes_patrol_where_it_left :: proc(t: ^testing.T) {
	l := room(EMPTY, "#@.......>.......#")
	l.coins = 1
	l.patrols[0] = "RRLL"
	g: Game
	game_load(&g, l)
	take_turn(&g, .Wait) // patrol step 1 -> (9,1)
	testing.expect_value(t, g.guards[0].patrol_idx, 1)
	take_turn(&g, .Toss_Right)
	testing.expect_value(t, g.guards[0].patrol_idx, 1) // patrol is paused, not advanced
	for _ in 0 ..< 20 {
		take_turn(&g, .Wait)
	}
	testing.expect_value(t, g.guards[0].mode, Guard_Mode.Patrol)
}

@(test)
toss_is_undoable :: proc(t: ^testing.T) {
	h := new(History)
	defer free(h)
	l := room(EMPTY, "#@.......<......#")
	l.coins = 1
	g: Game
	game_load(&g, l)
	start := g
	testing.expect(t, play(h, &g, .Toss_Right))
	testing.expect(t, undo(h, &g))
	testing.expect(t, g == start)
}

@(test)
door_needs_a_key_and_the_key_is_spent :: proc(t: ^testing.T) {
	g: Game
	game_load(&g, room(EMPTY, "#@D.............#"))
	before := g
	testing.expect(t, !take_turn(&g, .Move_Right))
	testing.expect(t, g == before)
	g.keys = 1
	testing.expect(t, take_turn(&g, .Move_Right))
	testing.expect_value(t, g.player, [2]int{2, 1})
	testing.expect_value(t, g.keys, 0)
	testing.expect_value(t, g.tiles[1][2], Tile.Floor)
}

@(test)
doors_block_sight_coins_and_guards :: proc(t: ^testing.T) {
	g: Game
	game_load(&g, room(EMPTY, "#>.D............#", EMPTY))
	cone: [SIGHT_RANGE][2]int
	testing.expect_value(t, cone_cells(&g, g.guards[0], &cone), 1) // only (2,1); the door stops the rest
	g.player = {4, 1}
	_, ok := coin_landing(&g, .Left) // the first tile that way is the door's
	testing.expect(t, !ok) // (4,1)->(3,1) is the door: nothing to land on
	_, reachable := path_step(&g, g.guards[0].pos, [2]int{5, 1})
	testing.expect(t, !reachable) // the corridor is sealed
}

@(test)
pickpocket_from_behind_takes_the_key :: proc(t: ^testing.T) {
	l := room(EMPTY, "#@>.............#")
	l.keyed[0] = true
	g: Game
	game_load(&g, l)
	testing.expect(t, take_turn(&g, .Pickpocket))
	testing.expect_value(t, g.keys, 1)
	testing.expect(t, !g.guards[0].has_key)
	testing.expect_value(t, g.turn, 1)
	testing.expect_value(t, g.status, Status.Playing)
	testing.expect(t, !take_turn(&g, .Pickpocket)) // nothing left to take
}

@(test)
pickpocket_fails_in_front_of_the_guard :: proc(t: ^testing.T) {
	l := room(EMPTY, "#@<.............#")
	l.keyed[0] = true
	g: Game
	game_load(&g, l)
	// The guard faces left, straight at the adjacent player.
	before := g
	testing.expect(t, !take_turn(&g, .Pickpocket))
	testing.expect(t, g == before)
}

@(test)
pickpocket_from_the_side_works_and_needs_adjacency_and_a_key :: proc(t: ^testing.T) {
	l := room(EMPTY, "#@..>............#", "#...............#")
	l.keyed[0] = true
	g: Game
	game_load(&g, l)
	testing.expect(t, !take_turn(&g, .Pickpocket)) // not adjacent
	g.player = {4, 2} // directly below a guard facing right
	testing.expect(t, take_turn(&g, .Pickpocket))
	l.keyed[0] = false
	game_load(&g, l)
	g.player = {4, 2}
	testing.expect(t, !take_turn(&g, .Pickpocket)) // no key to take
}

@(test)
key_level_needs_the_pickpocket :: proc(t: ^testing.T) {
	l := levels[2]
	testing.expect(t, solve(l) > 0)
	l.keyed = {}
	testing.expect_value(t, solve(l), -1)
}

@(test)
pickpocket_is_undoable :: proc(t: ^testing.T) {
	h := new(History)
	defer free(h)
	l := room(EMPTY, "#@>.............#")
	l.keyed[0] = true
	g: Game
	game_load(&g, l)
	start := g
	testing.expect(t, play(h, &g, .Pickpocket))
	testing.expect(t, undo(h, &g))
	testing.expect(t, g == start)
}

@(test)
pointing_turns_the_nearest_guard_then_it_turns_back :: proc(t: ^testing.T) {
	l := room(EMPTY, "#@.v............#")
	l.points = 1
	g: Game
	game_load(&g, l)
	testing.expect_value(t, g.guards[0].facing, Dir.Down)
	testing.expect(t, take_turn(&g, .Point_Right))
	testing.expect_value(t, g.points, 0)
	testing.expect_value(t, g.guards[0].facing, Dir.Right)
	take_turn(&g, .Wait)
	take_turn(&g, .Wait)
	testing.expect_value(t, g.guards[0].facing, Dir.Right) // three end-of-turn states in all
	take_turn(&g, .Wait)
	testing.expect_value(t, g.guards[0].facing, Dir.Down)
	testing.expect_value(t, g.guards[0].pos, [2]int{3, 1})
}

@(test)
pointing_needs_a_guard_in_line_in_range_with_clear_sight :: proc(t: ^testing.T) {
	l := room(EMPTY, "#@...v...........#", "#...............#")
	l.points = 3
	g: Game
	game_load(&g, l)
	testing.expect(t, !take_turn(&g, .Point_Right)) // guard four tiles away
	testing.expect(t, !take_turn(&g, .Point_Down)) // nobody that way
	g.player = {3, 1}
	g.tiles[1][4] = .Wall
	testing.expect(t, !take_turn(&g, .Point_Right)) // a wall in between
	testing.expect_value(t, g.points, 3) // nothing was spent
	g.tiles[1][4] = .Floor
	testing.expect(t, take_turn(&g, .Point_Right))
}

@(test)
pointing_without_uses_does_nothing :: proc(t: ^testing.T) {
	g: Game
	game_load(&g, room(EMPTY, "#@.v............#"))
	before := g
	testing.expect(t, !take_turn(&g, .Point_Right))
	testing.expect(t, g == before)
}

@(test)
pointed_patrol_guard_pauses_and_resumes :: proc(t: ^testing.T) {
	l := room(EMPTY, "#@>..............#")
	l.points = 1
	l.patrols[0] = "RRLL"
	g: Game
	game_load(&g, l)
	testing.expect(t, take_turn(&g, .Point_Right))
	for _ in 0 ..< 2 {
		take_turn(&g, .Wait)
	}
	testing.expect_value(t, g.guards[0].pos, [2]int{2, 1}) // frozen for the three turns
	testing.expect_value(t, g.guards[0].patrol_idx, 0)
	take_turn(&g, .Wait)
	testing.expect_value(t, g.guards[0].pos, [2]int{3, 1}) // the patrol carries on from its first step
}

@(test)
look_level_needs_the_point :: proc(t: ^testing.T) {
	l := levels[3]
	testing.expect(t, solve(l) > 0)
	l.points = 0
	testing.expect_value(t, solve(l), -1)
}

@(test)
point_is_undoable :: proc(t: ^testing.T) {
	h := new(History)
	defer free(h)
	l := room(EMPTY, "#@.v............#")
	l.points = 1
	g: Game
	game_load(&g, l)
	start := g
	testing.expect(t, play(h, &g, .Point_Right))
	testing.expect(t, undo(h, &g))
	testing.expect(t, g == start)
}
