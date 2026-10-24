#+build js
package tricksters

import "base:runtime"
import "core:fmt"
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
aiming: bool // T was pressed: the next direction key tosses a coin

restart :: proc() {
	aiming = false
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
	case " ":
		if game.status == .Won {
			level_index = (level_index + 1) % len(levels)
			restart()
			return
		}
		act = .Wait
	case:
		switch e.key.code {
		case "KeyW": act = .Move_Up
		case "KeyS": act = .Move_Down
		case "KeyA": act = .Move_Left
		case "KeyD": act = .Move_Right
		}
	}
	if a, ok := act.?; ok {
		if aiming && int(a) <= int(Action.Move_Right) {
			a = Action(int(a) + int(Action.Toss_Up))
		}
		aiming = false
		play(history, &game, a)
		js.event_prevent_default()
		return
	}
	aiming = false
	switch e.key.key {
	case "z", "Z": undo(history, &game)
	case "r", "R": restart()
	case "p", "P": play(history, &game, .Pickpocket)
	case "t", "T": aiming = game.coins > 0 && game.status == .Playing
	case "Enter":
		if game.status == .Won {
			level_index = (level_index + 1) % len(levels)
			restart()
		}
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
			case .Door:
				sprite(.Civilized, 4, 20, px, py, 0xc07030)
				sprite(.Tools, 2, 5, px, py, 0xffd060)
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
		gx := f32(GRID_X + gd.pos.x * TILE)
		gy := f32(GRID_Y + gd.pos.y * TILE)
		if gd.mode == .Investigate || gd.mode == .Stare {
			sprite(.UI, 0, 0, f32(GRID_X + gd.target.x * TILE), f32(GRID_Y + gd.target.y * TILE), 0xffd060)
			text("?", gx + 6, gy - 8, 8, 0xffd060)
		}
		sprite(.People, 3, 2, gx, gy, 0xff6060)
		if gd.has_key {
			sprite(.Tools, 0, 6, gx + 6, gy - 9, 0xffd060)
		}
	}
	if aiming {
		for d in Dir {
			if land, ok := coin_landing(&game, d); ok {
				fill_rect(f32(GRID_X + land.x * TILE), f32(GRID_Y + land.y * TILE), TILE, TILE, 1, 0.82, 0.38, 0.5)
			}
		}
	}
	sprite(.People, 0, 2, f32(GRID_X + game.player.x * TILE), f32(GRID_Y + game.player.y * TILE), 0xffffff)

	text(levels[level_index].name, 10, 270, 6, 0x7a6a9a)
	buf: [16]u8
	if game.coins > 0 || aiming {
		text(fmt.bprintf(buf[:], "COINS %d", game.coins), 330, 4, 8, 0xffd060)
	}
	if game.keys > 0 {
		text(fmt.bprintf(buf[:], "KEYS %d", game.keys), 330, 14, 8, 0xffd060)
	}
	switch game.status {
	case .Playing:
		if aiming {
			text("TOSS WHICH WAY? (ANY OTHER KEY CANCELS)", 10, 282, 6, 0xffd060)
		} else {
			text("ARROWS MOVE  SPACE WAIT  T COIN  P PICKPOCKET  Z UNDO  R RESTART", 10, 282, 6, 0xa090c0)
		}
	case .Caught:  text("SPOTTED!  Z TO UNDO, R TO RESTART", 10, 282, 8, 0xff6060)
	case .Won:     text("CURTAIN CALL!  SPACE FOR THE NEXT ACT", 10, 282, 8, 0x60d080)
	}
	return true
}

// QA hook: the page calls this for ?level=N (1-based).
@(export)
debug_level :: proc "c" (n: i32) {
	context = ctx
	if n >= 1 && int(n) <= len(levels) {
		level_index = int(n) - 1
		restart()
	}
}

main :: proc() {
	ctx = context
	history = new(History)
	restart()
	js.add_window_event_listener(.Key_Down, nil, on_key)
}
