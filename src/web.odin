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

// Sound ids; the order must match SOUNDS in web/index.html.
Sound :: enum i32 {
	Step,
	Wait,
	Bump,
	Coin,
	Pickpocket,
	Door,
	Point,
	Hat,
	Prize,
	Caught,
	Won,
	Undo,
	Restart,
	Select,
	Curtain,
}

foreign import audio "audio"
@(default_calling_convention = "contextless")
foreign audio {
	play_sound :: proc(id: i32) ---
}

sfx :: proc(s: Sound) {
	play_sound(i32(s))
}

Screen :: enum {
	Title,
	Act,   // a card announcing a new act
	Play,
	End,
}

ctx: runtime.Context
game: Game
history: ^History
level_index: int
screen: Screen
curtain: f32        // 0 open, 1 closed
curtain_target: f32
clock: f64          // seconds, for flicker and blinking
narration: string
narr_count: int     // running counter so repeated events cycle through their lines
results: [len(levels)]int // fewest turns used per cleared level; 0 = not cleared
Aim :: enum {
	None,
	Coin,  // T was pressed: the next direction key tosses a coin
	Point, // L was pressed: the next direction key points ("Look over there!")
}
aiming: Aim

restart :: proc() {
	aiming = .None
	game_load(&game, levels[level_index])
	history.count = 0
	narration = levels[level_index].intro
}

// Begins level i, with an act card first if it opens a new act.
start_level :: proc(i: int) {
	level_index = i
	restart()
	if i == 0 || levels[i].act != levels[i - 1].act {
		screen = .Act
	} else {
		screen = .Play
	}
}

sound_for_event :: proc(e: Event) -> Sound {
	switch e {
	case .Step:       return .Step
	case .Wait:       return .Wait
	case .Bump:       return .Bump
	case .Coin_Toss:  return .Coin
	case .Pickpocket: return .Pickpocket
	case .Door_Open:  return .Door
	case .Point:      return .Point
	case .Hat:        return .Hat
	case .Prize:      return .Prize
	case .Caught:     return .Caught
	case .Won:        return .Won
	}
	return .Step
}

// Plays an action through the undo history, then narrates and sounds what happened.
do_action :: proc(a: Action) {
	before := game
	ok := play(history, &game, a)
	e := describe_turn(&before, &game, a, ok)
	narration = narrate(e, narr_count)
	if e == .Won && levels[level_index].finale {
		narration = FINALE_LINE
	}
	narr_count += 1
	sfx(sound_for_event(e))
}

advance_level :: proc() {
	if results[level_index] == 0 || game.turn < results[level_index] {
		results[level_index] = game.turn
	}
	if level_index + 1 >= len(levels) {
		screen = .End
		curtain_target = 1
		sfx(.Curtain)
	} else {
		start_level(level_index + 1)
		sfx(.Select)
	}
}

text :: proc(s: string, x, y, size: f32, color: u32) {
	str := s
	draw_text(raw_data(str), i32(len(str)), x, y, size, color)
}

// Public Pixel is monospaced with an advance equal to its size.
text_c :: proc(s: string, y, size: f32, color: u32) {
	text(s, (VIEW_W - f32(len(s)) * size) / 2, y, size, color)
}

text_shadow :: proc(s: string, x, y, size: f32, color: u32) {
	text(s, x + 1, y + 1, size, 0x000000)
	text(s, x, y, size, color)
}

text_c_shadow :: proc(s: string, y, size: f32, color: u32) {
	text_c(s, y + 1, size, 0x000000)
	text_c(s, y, size, color)
}

sprite :: proc(sheet: Sheet, col, row: i32, x, y: f32, color: u32 = 0xffffff) {
	draw_sprite(i32(sheet), col, row, x, y, TILE, color)
}

append_string :: proc(buf: ^[dynamic]u8, s: string) {
	append(buf, ..transmute([]u8)s)
}

is_confirm :: proc(e: js.Event) -> bool {
	return e.key.key == " " || e.key.key == "Enter"
}

on_key :: proc(e: js.Event) {
	context = ctx
	switch screen {
	case .Title:
		if is_confirm(e) {
			js.event_prevent_default()
			curtain_target = 0
			sfx(.Curtain)
			start_level(0)
		}
		return
	case .Act:
		if is_confirm(e) {
			js.event_prevent_default()
			screen = .Play
			sfx(.Select)
		}
		return
	case .End:
		if is_confirm(e) {
			js.event_prevent_default()
			screen = .Title
			curtain_target = 1
			sfx(.Select)
		}
		return
	case .Play:
	}

	if game.status == .Won && is_confirm(e) {
		js.event_prevent_default()
		advance_level()
		return
	}

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
		if int(a) <= int(Action.Move_Right) {
			switch aiming {
			case .None:
			case .Coin:  a = Action(int(a) + int(Action.Toss_Up))
			case .Point: a = Action(int(a) + int(Action.Point_Up))
			}
		}
		aiming = .None
		do_action(a)
		js.event_prevent_default()
		return
	}
	aiming = .None
	switch e.key.key {
	case "z", "Z":
		if undo(history, &game) {
			narration = "Rewind! The crowd saw nothing."
			sfx(.Undo)
		}
	case "r", "R":
		restart()
		sfx(.Restart)
	case "p", "P": do_action(.Pickpocket)
	case "t", "T":
		if game.coins > 0 && game.status == .Playing {
			aiming = .Coin
			narration = "Which way does the coin fly?"
		}
	case "l", "L":
		if game.points > 0 && game.status == .Playing {
			aiming = .Point
			narration = "Which way do you point?"
		}
	}
}

// Both side curtains and the valance; amount 0 leaves only the stage frame, 1 closes the stage.
draw_curtains :: proc(amount: f32) {
	side := 40 + (VIEW_W / 2 - 40) * amount
	for panel in 0 ..< 2 {
		x0: f32 = panel == 0 ? 0 : VIEW_W - side
		fill_rect(x0, 0, side, VIEW_H, 0.42, 0.04, 0.08, 1)
		// Folds: lighter stripes every 10 px, mirrored so the pattern is symmetric.
		for fx: f32 = 0; fx < side; fx += 10 {
			fill_rect(x0 + fx + 2, 0, 4, VIEW_H, 0.58, 0.08, 0.12, 1)
			fill_rect(x0 + fx + 6, 0, 1, VIEW_H, 0.28, 0.02, 0.05, 1)
		}
		edge: f32 = panel == 0 ? side - 2 : x0
		if amount < 0.99 {
			fill_rect(edge, 0, 2, VIEW_H, 1, 0.78, 0.25, 1) // gold trim
		}
	}
	// Valance with a scalloped, fringed lower edge.
	fill_rect(0, 0, VIEW_W, 16, 0.5, 0.05, 0.1, 1)
	for sx: f32 = 0; sx < VIEW_W; sx += 16 {
		fill_rect(sx + 1, 16, 14, 2, 0.5, 0.05, 0.1, 1)
		fill_rect(sx + 3, 18, 10, 2, 0.5, 0.05, 0.1, 1)
		fill_rect(sx + 5, 20, 6, 1, 0.5, 0.05, 0.1, 1)
		fill_rect(sx + 1, 15, 14, 1, 1, 0.78, 0.25, 1)
	}
}

draw_footlights :: proc() {
	for i in 0 ..< 20 {
		flicker: f32 = 0.75 + 0.25 * f32(i % 3 == 0 ? (int(clock * 6) % 2) : 1)
		fill_rect(f32(GRID_X + i * 16 + 4), GRID_Y + ROWS * TILE + 2, 8, 3, 1 * flicker, 0.85 * flicker, 0.4 * flicker, 1)
	}
}

draw_stage :: proc() {
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
			case .Hat_Red:  sprite(.Clothing, 2, 0, px, py, 0xff6060)
			case .Hat_Blue: sprite(.Clothing, 2, 0, px, py, 0x6090ff)
			case .Door:
				sprite(.Civilized, 4, 20, px, py, 0xc07030)
				sprite(.Tools, 2, 5, px, py, 0xffd060)
			}
		}
	}

	applause := levels[level_index].finale && game.status == .Won
	cone: [SIGHT_RANGE][2]int
	for i in 0 ..< game.guard_count {
		gd := game.guards[i]
		if applause {
			continue
		}
		n := cone_cells(&game, gd, &cone)
		for c in cone[:n] {
			alpha: f32 = fooled(&game, gd) ? 0.1 : 0.35
			if gd.faction == .Red {
				fill_rect(f32(GRID_X + c.x * TILE), f32(GRID_Y + c.y * TILE), TILE, TILE, 0.9, 0.2, 0.2, alpha)
			} else {
				fill_rect(f32(GRID_X + c.x * TILE), f32(GRID_Y + c.y * TILE), TILE, TILE, 0.25, 0.4, 0.95, alpha)
			}
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
		sprite(.People, 3, 2, gx, gy, gd.faction == .Red ? 0xff6060 : 0x6090ff)
		if gd.turned {
			text("!", gx + 7, gy - 8, 8, 0x60c0ff)
		}
		if applause {
			bounce: f32 = f32(int(clock * 4 + f64(i)) % 2) * 2
			sprite(.UI, 9, 9, gx, gy - 12 - bounce, 0xff6080)
		}
		if gd.has_key {
			sprite(.Tools, 0, 6, gx + 6, gy - 9, 0xffd060)
		}
	}
	for d in Dir {
		land: [2]int
		ok: bool
		switch aiming {
		case .None: continue
		case .Coin: land, ok = coin_landing(&game, d)
		case .Point:
			if gi, found := look_target(&game, d); found {
				land, ok = game.guards[gi].pos, true
			}
		}
		if ok {
			fill_rect(f32(GRID_X + land.x * TILE), f32(GRID_Y + land.y * TILE), TILE, TILE, 1, 0.82, 0.38, 0.5)
		}
	}
	px := f32(GRID_X + game.player.x * TILE)
	py := f32(GRID_Y + game.player.y * TILE)
	sprite(.People, 0, 2, px, py, 0xffffff)
	if game.disguise_turns > 0 {
		sprite(.Clothing, 2, 0, px, py - 7, game.disguise == .Red ? 0xff6060 : 0x6090ff)
	}
}

// Counters on the left curtain (the right one stays clear).
draw_counters :: proc() {
	buf: [16]u8
	y: f32 = 28
	row :: proc(label: string, n: int, color: u32, y: ^f32, buf: []u8) {
		text_shadow(label, 2, y^, 6, color)
		text_shadow(fmt.bprintf(buf, "%d", n), 2, y^ + 8, 8, 0xffffff)
		y^ += 24
	}
	if game.coins > 0 {
		row("COINS", game.coins, 0xffd060, &y, buf[:])
	}
	if game.points > 0 {
		row("LOOKS", game.points, 0x60c0ff, &y, buf[:])
	}
	if game.keys > 0 {
		row("KEYS", game.keys, 0xffd060, &y, buf[:])
	}
	if game.disguise_turns > 0 {
		row("HAT", game.disguise_turns, game.disguise == .Red ? 0xff8080 : 0x80a0ff, &y, buf[:])
	}
	text_shadow("TURN", 362, 28, 6, 0xc0b0e0)
	text_shadow(fmt.bprintf(buf[:], "%d", game.turn), 362, 36, 8, 0xffffff)
	text_shadow("PAR", 362, 52, 6, 0xc0b0e0)
	text_shadow(fmt.bprintf(buf[:], "%d", levels[level_index].par), 362, 60, 8, 0xffffff)
}

draw_play :: proc() {
	draw_stage()
	draw_footlights()
	draw_curtains(curtain)
	l := levels[level_index]
	label_buf: [64]u8
	text_shadow(fmt.bprintf(label_buf[:], "ACT %s  %s", ACT_ROMAN[l.act], l.name), 6, 4, 8, 0xffd060)
	draw_counters()

	narr_color: u32 = 0xf0e6c8
	if game.status == .Caught { narr_color = 0xff8080 }
	if game.status == .Won { narr_color = 0x90ffb0 }
	text_c(narration, 272, 8, narr_color)

	status_buf: [64]u8
	switch game.status {
	case .Playing:
		switch aiming {
		case .Coin:  text_c("PRESS A DIRECTION  (ANY OTHER KEY CANCELS)", 288, 6, 0xffd060)
		case .Point: text_c("PRESS A DIRECTION  (ANY OTHER KEY CANCELS)", 288, 6, 0x60c0ff)
		case .None:
			hint := make([dynamic]u8, context.temp_allocator)
			append_string(&hint, "ARROWS MOVE  SPACE WAIT")
			if game.coins > 0 { append_string(&hint, "  T COIN") }
			if game.points > 0 { append_string(&hint, "  L LOOK") }
			append_string(&hint, "  P PICK  Z UNDO  R RESTART")
			text_c(string(hint[:]), 288, 6, 0x8070a0)
		}
	case .Caught:
		text_c("Z UNDO   R RESTART", 288, 6, 0xff8080)
	case .Won:
		text_c(fmt.bprintf(status_buf[:], "CLEARED IN %d TURNS (PAR %d)   SPACE: CONTINUE", game.turn, l.par), 288, 6, 0x90ffb0)
	}
}

draw_title :: proc() {
	fill_rect(0, 0, VIEW_W, VIEW_H, 0.05, 0.03, 0.08, 1)
	draw_curtains(1)
	text_c_shadow("TRICKSTERS", 70, 32, 0xffd060)
	text_c_shadow("OF SPLORR!!", 108, 16, 0xffc040)
	draw_sprite(i32(Sheet.People), 0, 2, 180, 150, 40, 0xffffff)
	draw_sprite(i32(Sheet.Clothing), 2, 0, 180, 134, 40, 0xffd060)
	text_c_shadow("A SMALL SHOW OF SLEIGHT AND NERVE", 200, 8, 0xf0e6c8)
	if int(clock * 2) % 2 == 0 {
		text_c_shadow("PRESS SPACE TO RAISE THE CURTAIN", 240, 8, 0xffffff)
	}
	text_c_shadow("M MUTES THE SOUND", 270, 6, 0xc0a0a0)
}

draw_act :: proc() {
	l := levels[level_index]
	fill_rect(0, 0, VIEW_W, VIEW_H, 0.05, 0.03, 0.08, 1)
	fill_rect(GRID_X, GRID_Y, COLS * TILE, ROWS * TILE, 0.1, 0.07, 0.14, 1)
	draw_footlights()
	draw_curtains(curtain)
	text_c_shadow("ACT", 70, 16, 0xc0b0e0)
	text_c_shadow(ACT_ROMAN[l.act], 96, 32, 0xffd060)
	text_c_shadow(ACT_TITLES[l.act], 148, 12, 0xffffff)
	text_c_shadow(l.name, 180, 8, 0xf0e6c8)
	text_c(l.intro, 212, 6, 0xc8c0a8)
	if int(clock * 2) % 2 == 0 {
		text_c_shadow("PRESS SPACE", 244, 8, 0xffffff)
	}
}

draw_end :: proc() {
	fill_rect(0, 0, VIEW_W, VIEW_H, 0.05, 0.03, 0.08, 1)
	draw_curtains(curtain)
	text_c_shadow("THE END", 56, 24, 0xffd060)
	text_c_shadow("THE GUARDS WERE THE AUDIENCE ALL ALONG", 92, 8, 0xf0e6c8)
	row_buf: [64]u8
	y: f32 = 120
	total, par_total := 0, 0
	for l, i in levels {
		if results[i] > 0 {
			total += results[i]
		}
		par_total += l.par
		line := fmt.bprintf(row_buf[:], "%-22s %s%d / %s%d", l.name, results[i] < 100 ? " " : "", results[i], l.par < 100 ? " " : "", l.par)
		text(line, (VIEW_W - 6 * 33) / 2, y, 6, results[i] > 0 && results[i] <= l.par ? 0x90ffb0 : 0xf0e6c8)
		y += 10
	}
	line := fmt.bprintf(row_buf[:], "TOTAL %d TURNS (PAR %d)", total, par_total)
	text_c_shadow(line, y + 8, 8, 0xffd060)
	if int(clock * 2) % 2 == 0 {
		text_c_shadow("PRESS SPACE", 262, 8, 0xffffff)
	}
}

@(export)
step :: proc(dt: f64, c: runtime.Context) -> bool {
	context = ctx
	clock += dt
	free_all(context.temp_allocator)
	// Slide the curtains toward their target (about two thirds of a second end to end).
	speed := f32(dt) * 1.5
	if curtain < curtain_target {
		curtain = min(curtain + speed, curtain_target)
	} else if curtain > curtain_target {
		curtain = max(curtain - speed, curtain_target)
	}
	clear_canvas(0.05, 0.03, 0.08)
	switch screen {
	case .Title: draw_title()
	case .Act:   draw_act()
	case .Play:  draw_play()
	case .End:   draw_end()
	}
	return true
}

// QA hook: the page calls this for ?level=N (1-based) and skips straight to play.
@(export)
debug_level :: proc "c" (n: i32) {
	context = ctx
	if n >= 1 && int(n) <= len(levels) {
		level_index = int(n) - 1
		restart()
		screen = .Play
		curtain, curtain_target = 0, 0
	}
}

main :: proc() {
	ctx = context
	history = new(History)
	curtain, curtain_target = 1, 1
	screen = .Title
	restart()
	js.add_window_event_listener(.Key_Down, nil, on_key)
}
