package tricksters

// Declared with := because Odin cannot index a constant array with a runtime value.
levels := [?]Level {
	{
		name = "Opening Night",
		rows = {
			"################",
			"#@.............#",
			"#..............#",
			"#...##....##...#",
			"#...#......#...#",
			"#.>.........$..#",
			"#...#......#...#",
			"#...##....##...#",
			"#..............#",
			"#..............#",
			"#.............E#",
			"################",
		},
		patrols = {0 = "RRRRRRRRLLLLLLLL"},
	},
}
