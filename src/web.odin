#+build js
package tricksters

import "base:runtime"
import "core:sys/wasm/js"

// Logical canvas size; the page scales it by a whole number.
VIEW_W :: 400
VIEW_H :: 300
TILE   :: 20 // drawn size of a 10 px sprite (2x)
GRID_X :: (VIEW_W - COLS * TILE) / 2
GRID_Y :: 20

// Sheet ids; the order must match SHEETS in web/index.html.
Sheet :: enum i32 {
	People,
	Creatures,
	Tools,
	UI,
	Clothing,
	Jewelry,
	Food,
	Misc,
	Civilized,
}

foreign import canvas "canvas"
@(default_calling_convention = "contextless")
foreign canvas {
	clear_canvas :: proc(r, g, b: f32) ---
	fill_rect    :: proc(x, y, w, h: f32, r, g, b, a: f32) ---
	// col, row are 10 px cells in the sheet; color is 0xRRGGBB (sheets are white ink, tinted by the page).
	draw_sprite  :: proc(sheet: i32, col, row: i32, x, y, size: f32, color: u32) ---
	draw_text    :: proc(text: [^]u8, len: i32, x, y, size: f32, color: u32) ---
}

ctx: runtime.Context
game: Game
history: ^History
level_index: int

restart :: proc() {
	game_load(&game, levels[level_index])
	history.count = 0
}

text :: proc(s: string, x, y, size: f32, color: u32) {
	str := s
	draw_text(raw_data(str), i32(len(str)), x, y, size, color)
}

sprite :: proc(sheet: Sheet, col, row: i32, x, y: f32, color: u32 = 0xffffff) {
	draw_sprite(i32(sheet), col, row, x, y, TILE, color)
}

on_key :: proc(e: js.Event) {
	context = ctx
	// Logical e.key first, e.code as fallback (remote desktops send wrong codes).
	act: Maybe(Action)
	switch e.key.key {
	case "ArrowUp":    act = .Move_Up
	case "ArrowDown":  act = .Move_Down
	case "ArrowLeft":  act = .Move_Left
	case "ArrowRight": act = .Move_Right
	case " ":          act = .Wait
	case:
		switch e.key.code {
		case "KeyW": act = .Move_Up
		case "KeyS": act = .Move_Down
		case "KeyA": act = .Move_Left
		case "KeyD": act = .Move_Right
		}
	}
	if a, ok := act.?; ok {
		play(history, &game, a)
		js.event_prevent_default()
		return
	}
	switch e.key.key {
	case "z", "Z": undo(history, &game)
	case "r", "R": restart()
	}
}

@(export)
step :: proc(dt: f64, c: runtime.Context) -> bool {
	context = ctx
	clear_canvas(0.05, 0.03, 0.08)
	text("TRICKSTERS OF SPLORR!!", 10, 4, 8, 0xffd060)

	fill_rect(GRID_X, GRID_Y, COLS * TILE, ROWS * TILE, 0.16, 0.12, 0.2, 1)
	for y in 0 ..< ROWS {
		for x in 0 ..< COLS {
			px := f32(GRID_X + x * TILE)
			py := f32(GRID_Y + y * TILE)
			switch game.tiles[y][x] {
			case .Floor:
			case .Wall:  sprite(.Civilized, 4, 20, px, py, 0x6a5a8a)
			case .Prize: sprite(.Jewelry, 0, 0, px, py, 0xffd060)
			case .Exit:  sprite(.Civilized, 6, 1, px, py, 0x60d080)
			}
		}
	}

	cone: [SIGHT_RANGE][2]int
	for i in 0 ..< game.guard_count {
		gd := game.guards[i]
		n := cone_cells(&game, gd, &cone)
		for c in cone[:n] {
			fill_rect(f32(GRID_X + c.x * TILE), f32(GRID_Y + c.y * TILE), TILE, TILE, 0.9, 0.2, 0.2, 0.35)
		}
	}
	for i in 0 ..< game.guard_count {
		gd := game.guards[i]
		sprite(.People, 3, 2, f32(GRID_X + gd.pos.x * TILE), f32(GRID_Y + gd.pos.y * TILE), 0xff6060)
	}
	sprite(.People, 0, 2, f32(GRID_X + game.player.x * TILE), f32(GRID_Y + game.player.y * TILE), 0xffffff)

	switch game.status {
	case .Playing: text("ARROWS/WASD MOVE  SPACE WAIT  Z UNDO  R RESTART", 10, 270, 6, 0xa090c0)
	case .Caught:  text("SPOTTED!  Z TO UNDO, R TO RESTART", 10, 270, 8, 0xff6060)
	case .Won:     text("CURTAIN CALL!  R TO PLAY AGAIN", 10, 270, 8, 0x60d080)
	}
	return true
}

main :: proc() {
	ctx = context
	history = new(History)
	restart()
	js.add_window_event_listener(.Key_Down, nil, on_key)
}
