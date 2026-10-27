#+build !js
package tricksters

import "core:log"
import "core:slice"
import "core:strings"
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

SOLVER_NODE_CAP :: 1_000_000

solve_from :: proc(start: Game) -> int {
	turns, _ := solve_with_path(start)
	return turns
}

// Breadth-first search; also returns the winning actions as text (U D L R . for moves and wait,
// u d l r for coin tosses, p for a pickpocket, ^ v < > for Look over there) so a human can replay the level.
solve_with_path :: proc(start: Game) -> (turns: int, path: string) {
	// Only the frontier keeps whole games; every state ever seen keeps just its parent and action.
	Meta :: struct {
		parent: int,
		action: Action,
	}
	Entry :: struct {
		game: Game,
		meta: int,
	}
	metas := make([dynamic]Meta)
	defer delete(metas)
	visited := make(map[State_Key]struct{})
	defer delete(visited)
	cur := make([dynamic]Entry)
	next := make([dynamic]Entry)
	defer delete(cur)
	defer delete(next)
	start := start
	append(&metas, Meta{parent = -1})
	append(&cur, Entry{game = start, meta = 0})
	visited[state_key(&start)] = {}
	glyph := [Action]u8{
		.Move_Up = 'U', .Move_Down = 'D', .Move_Left = 'L', .Move_Right = 'R', .Wait = '.',
		.Toss_Up = 'u', .Toss_Down = 'd', .Toss_Left = 'l', .Toss_Right = 'r', .Pickpocket = 'p',
		.Point_Up = '^', .Point_Down = 'v', .Point_Left = '<', .Point_Right = '>',
	}
	for len(cur) > 0 {
		if len(metas) > SOLVER_NODE_CAP {
			return -2, "" // gave up: the state space is too big
		}
		clear(&next)
		for entry in cur {
			for a in Action {
				n := entry.game
				if !take_turn(&n, a) {
					continue
				}
				if n.status == .Won {
					buf := make([dynamic]u8, context.temp_allocator)
					append(&buf, glyph[a])
					for i := entry.meta; metas[i].parent >= 0; i = metas[i].parent {
						append(&buf, glyph[metas[i].action])
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
				append(&metas, Meta{parent = entry.meta, action = a})
				append(&next, Entry{game = n, meta = len(metas) - 1})
			}
		}
		cur, next = next, cur
	}
	return -1, ""
}

@(test)
every_level_is_solvable :: proc(t: ^testing.T) {
	for l in levels {
		par := solve(l)
		testing.expectf(t, par > 0, "level %q cannot be solved", l.name)
		testing.expectf(t, par == l.par, "level %q: par field is %d but the solver says %d", l.name, l.par, par)
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

@(test)
red_hat_fools_red_guards_but_not_blue :: proc(t: ^testing.T) {
	// Red guard at (4,1) sees (3,1) (2,1) (1,1); blue guard at (8,1) sees (7,1) (6,1) (5,1).
	l := room(EMPTY, "#...<...<.......#", "#..............#")
	l.blue[1] = true
	g: Game
	game_load(&g, l)
	g.disguise = .Red
	g.disguise_turns = 3
	testing.expect(t, !seen(&g, {2, 1})) // in the red cone, in a red hat
	testing.expect(t, seen(&g, {6, 1}))  // in the blue cone, in a red hat
	g.disguise = .Blue
	testing.expect(t, seen(&g, {2, 1}))  // a blue hat does not fool the red guard
	testing.expect(t, !seen(&g, {6, 1}))
	g.disguise_turns = 0
	testing.expect(t, seen(&g, {2, 1}))  // the hat has run out
}

@(test)
hat_is_picked_up_and_counts_down :: proc(t: ^testing.T) {
	g: Game
	game_load(&g, room(EMPTY, "#@h.............#"))
	testing.expect(t, take_turn(&g, .Move_Right))
	testing.expect_value(t, g.disguise, Faction.Red)
	testing.expect_value(t, g.disguise_turns, HAT_TURNS - 1) // the pickup turn used one
	testing.expect_value(t, g.tiles[1][2], Tile.Floor)
	for _ in 0 ..< HAT_TURNS - 1 {
		take_turn(&g, .Wait)
	}
	testing.expect_value(t, g.disguise_turns, 0)
	take_turn(&g, .Wait)
	testing.expect_value(t, g.disguise_turns, 0)
}

@(test)
disguise_runs_out_in_the_cone_and_you_are_caught :: proc(t: ^testing.T) {
	l := room(EMPTY, "#@h..<...........#")
	g: Game
	game_load(&g, l)
	// The red guard at (5,1) faces left: (4,1) (3,1) (2,1) are watched. Take the hat, then wait it out.
	testing.expect(t, take_turn(&g, .Move_Right))
	testing.expect_value(t, g.status, Status.Playing) // fooled
	for _ in 0 ..< HAT_TURNS - 1 {
		take_turn(&g, .Wait)
		testing.expect_value(t, g.status, Status.Playing)
	}
	take_turn(&g, .Wait)
	testing.expect_value(t, g.status, Status.Caught)
}

@(test)
a_second_hat_replaces_the_first :: proc(t: ^testing.T) {
	g: Game
	game_load(&g, room(EMPTY, "#@hH............#"))
	take_turn(&g, .Move_Right)
	take_turn(&g, .Move_Right)
	testing.expect_value(t, g.disguise, Faction.Blue)
	testing.expect_value(t, g.disguise_turns, HAT_TURNS - 1)
}

@(test)
guards_are_solid :: proc(t: ^testing.T) {
	g: Game
	game_load(&g, room(EMPTY, "#@>..............#"))
	g.disguise = .Red
	g.disguise_turns = 3
	before := g
	testing.expect(t, !take_turn(&g, .Move_Right))
	testing.expect(t, g == before)
}

@(test)
fooled_guard_does_not_step_onto_the_player :: proc(t: ^testing.T) {
	l := room(EMPTY, "#@<..............#")
	l.patrols[0] = "L"
	g: Game
	game_load(&g, l)
	g.disguise = .Red
	g.disguise_turns = 3
	take_turn(&g, .Wait)
	testing.expect_value(t, g.guards[0].pos, [2]int{2, 1})
	testing.expect_value(t, g.status, Status.Playing)
}

@(test)
hat_level_needs_the_hat :: proc(t: ^testing.T) {
	l := levels[4]
	testing.expect(t, solve(l) > 0)
	l.rows[5] = "#..........<...#" // the same row without the hat
	testing.expect_value(t, solve(l), -1)
}

@(test)
hat_is_undoable :: proc(t: ^testing.T) {
	h := new(History)
	defer free(h)
	g: Game
	game_load(&g, room(EMPTY, "#@h.............#"))
	start := g
	testing.expect(t, play(h, &g, .Move_Right))
	testing.expect(t, undo(h, &g))
	testing.expect(t, g == start)
}

// Runs one action the way the page does and describes it.
event_of :: proc(g: ^Game, a: Action) -> Event {
	before := g^
	ok := take_turn(g, a)
	return describe_turn(&before, g, a, ok)
}

@(test)
events_describe_each_kind_of_turn :: proc(t: ^testing.T) {
	g: Game
	game_load(&g, room(EMPTY, "#@..............#"))
	testing.expect_value(t, event_of(&g, .Move_Up), Event.Bump)
	testing.expect_value(t, event_of(&g, .Move_Right), Event.Step)
	testing.expect_value(t, event_of(&g, .Wait), Event.Wait)

	game_load(&g, room(EMPTY, "#@E$............#"))
	testing.expect_value(t, event_of(&g, .Move_Right), Event.No_Prize)

	l := room(EMPTY, "#@h$E>...........#")
	l.coins = 1
	game_load(&g, l)
	testing.expect_value(t, event_of(&g, .Toss_Right), Event.Coin_Toss)
	testing.expect_value(t, event_of(&g, .Move_Right), Event.Hat)
	testing.expect_value(t, event_of(&g, .Move_Right), Event.Prize)
	testing.expect_value(t, event_of(&g, .Move_Right), Event.Won)
}

@(test)
events_describe_tricks_and_catches :: proc(t: ^testing.T) {
	l := room(EMPTY, "#@>.D...........#")
	l.keyed[0] = true
	l.points = 1
	g: Game
	game_load(&g, l)
	testing.expect_value(t, event_of(&g, .Pickpocket), Event.Pickpocket)
	g.player = {3, 1}
	testing.expect_value(t, event_of(&g, .Point_Left), Event.Point)
	g.guards[0].stun = 0
	g.guards[0].turned = false
	g.guards[0].pos = {9, 1}
	g.player = {3, 1}
	testing.expect_value(t, event_of(&g, .Move_Right), Event.Door_Open)

	game_load(&g, room(EMPTY, "#@.<............#"))
	testing.expect_value(t, event_of(&g, .Wait), Event.Caught)
}

@(test)
every_event_has_short_lines_and_every_level_has_patter :: proc(t: ^testing.T) {
	for e in Event {
		testing.expectf(t, len(NARRATION[e]) > 0, "no lines for %v", e)
		for line in NARRATION[e] {
			testing.expectf(t, len(line) <= LINE_MAX, "line too long (%d): %q", len(line), line)
		}
	}
	prev_act := 0
	for l in levels {
		testing.expectf(t, len(l.intro) > 0 && len(l.intro) <= LINE_MAX, "bad intro for %q", l.name)
		testing.expectf(t, l.act >= prev_act && l.act >= 1 && l.act < len(ACT_TITLES), "bad act for %q", l.name)
		prev_act = l.act
	}
}

// Design aid: tools/test.sh -define:LEVEL=7 -define:ODIN_TEST_NAMES=tricksters.solve_one_level
LEVEL :: #config(LEVEL, 1)

@(test)
solve_one_level :: proc(t: ^testing.T) {
	if LEVEL < 1 || LEVEL > len(levels) {
		return
	}
	l := levels[LEVEL - 1]
	turns, path := solve_with_path(start_of(l))
	log.infof("LEVEL %d %q: turns %d (-1 unsolvable, -2 gave up) solution %s", LEVEL, l.name, turns, path)
}

// A copy of the level with every hat tile turned into plain floor.
without_hats :: proc(l: Level) -> Level {
	l := l
	for &row in l.rows {
		r, _ := strings.replace_all(row, "h", ".", context.temp_allocator)
		r, _ = strings.replace_all(r, "H", ".", context.temp_allocator)
		row = r
	}
	return l
}

@(test)
pickpocket_from_the_front_works_in_the_right_hat :: proc(t: ^testing.T) {
	l := room(EMPTY, "#@<.............#")
	l.keyed[0] = true
	g: Game
	game_load(&g, l)
	testing.expect(t, !take_turn(&g, .Pickpocket)) // in its cone: refused
	g.disguise = .Red
	g.disguise_turns = 3
	testing.expect(t, take_turn(&g, .Pickpocket)) // fooled: allowed
	testing.expect_value(t, g.keys, 1)
	g.disguise = .Blue // a hat of the wrong colour would not do
	game_load(&g, l)
	g.disguise = .Blue
	g.disguise_turns = 3
	testing.expect(t, !take_turn(&g, .Pickpocket))
}

@(test)
keys_and_coins_needs_both :: proc(t: ^testing.T) {
	l := levels[5]
	testing.expect(t, solve(l) > 0)
	c := l
	c.coins = 0
	testing.expect_value(t, solve(c), -1)
	k := l
	k.keyed = {}
	testing.expect_value(t, solve(k), -1)
}

@(test)
right_place_right_hat_needs_both :: proc(t: ^testing.T) {
	l := levels[6]
	testing.expect(t, solve(l) > 0)
	p := l
	p.points = 0
	testing.expect_value(t, solve(p), -1)
	testing.expect_value(t, solve(without_hats(l)), -1)
}

@(test)
face_to_face_needs_the_hat :: proc(t: ^testing.T) {
	l := levels[7]
	testing.expect(t, solve(l) > 0)
	testing.expect_value(t, solve(without_hats(l)), -1)
}

@(test)
grand_illusion_needs_all_three :: proc(t: ^testing.T) {
	l := levels[8]
	testing.expect(t, solve(l) > 0)
	p := l
	p.points = 0
	testing.expect_value(t, solve(p), -1)
	k := l
	k.keyed = {}
	testing.expect_value(t, solve(k), -1)
	testing.expect_value(t, solve(without_hats(l)), -1)
}

@(test)
the_finale_needs_every_trick :: proc(t: ^testing.T) {
	l := levels[9]
	testing.expect(t, solve(l) > 0)
	c := l
	c.coins = 0
	testing.expect_value(t, solve(c), -1)
	p := l
	p.points = 0
	testing.expect_value(t, solve(p), -1)
	k := l
	k.keyed = {}
	testing.expect_value(t, solve(k), -1)
	testing.expect_value(t, solve(without_hats(l)), -1)
}

@(test)
only_the_last_level_is_the_finale :: proc(t: ^testing.T) {
	for l, i in levels {
		testing.expect_value(t, l.finale, i == len(levels) - 1)
	}
}
