package tricksters

// Each level is ROWS strings of up to COLS characters (see game_load).
// Declared with := because Odin cannot index a constant array with a runtime value.
levels := [?][ROWS]string {
	{
		"################",
		"#@.............#",
		"#.####.#####.#.#",
		"#.#....#...#.#.#",
		"#.#.####.#.#.#.#",
		"#.#......#...#.#",
		"#.########.###.#",
		"#..........#...#",
		"#.########.#.###",
		"#.#......#.#..$#",
		"#.#.####.#.###.#",
		"#E..#....#.....#",
	},
}
