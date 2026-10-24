package tricksters

// What a turn did, worked out from the state before and after. The page uses it to pick the
// narrator's line and the sound; keeping it here makes it testable natively.

Event :: enum {
	Step,
	Wait,
	Bump, // the action did nothing
	Coin_Toss,
	Pickpocket,
	Door_Open,
	Point,
	Hat,
	Prize,
	Caught,
	Won,
}

describe_turn :: proc(before, after: ^Game, a: Action, ok: bool) -> Event {
	switch {
	case !ok:                                       return .Bump
	case after.status == .Won:                      return .Won
	case after.status == .Caught:                   return .Caught
	case after.keys > before.keys:                  return .Pickpocket
	case after.keys < before.keys:                  return .Door_Open
	case after.coins < before.coins:                return .Coin_Toss
	case after.points < before.points:              return .Point
	case after.has_prize && !before.has_prize:      return .Prize
	case after.disguise_turns > before.disguise_turns: return .Hat
	case a == .Wait:                                return .Wait
	}
	return .Step
}

// The trickster's patter. Each line fits one row of the stage (44 characters at the text size used).
LINE_MAX :: 44

NARRATION := [Event][]string {
	.Step = {
		"Nothing up my sleeve.",
		"Walk like you belong here.",
		"Smile. Nobody checks a smile.",
		"Eyes front, hands busy.",
	},
	.Wait = {
		"Patience is half the trick.",
		"Let them look the other way.",
		"Timing is everything, darling.",
	},
	.Bump = {
		"That's a wall. Walls never fall for it.",
		"Not that way, maestro.",
	},
	.Coin_Toss = {
		"Ooh, shiny! Go on, have a look.",
		"A little noise goes a long way.",
	},
	.Pickpocket = {
		"Light fingers, lighter conscience.",
		"You'll never miss it, friend.",
	},
	.Door_Open = {
		"Every lock wants to be opened.",
		"Open sesame. Well, open key.",
	},
	.Point = {
		"Look over there! No, THERE!",
		"Is that a pigeon? Probably.",
	},
	.Hat = {
		"A new hat, a new person.",
		"The hat makes the con.",
	},
	.Prize = {
		"Got it! Now stroll out like it's yours.",
		"Ours now. Don't run. Never run.",
	},
	.Caught = {
		"Spotted! Press Z, the crowd forgives.",
		"Caught! Rewind and try the patter again.",
	},
	.Won = {
		"And for my next trick: the exit!",
		"Ta-da! The curtain falls.",
	},
}

// Said when the finale is cleared: the guards were the audience all along.
FINALE_LINE :: "They were the audience all along. Bravo!"

// n is a running counter; the same event cycles through its lines.
narrate :: proc(e: Event, n: int) -> string {
	lines := NARRATION[e]
	return lines[n % len(lines)]
}

ACT_ROMAN := [?]string{"", "I", "II", "III", "IV", "V"}
ACT_TITLES := [?]string{"", "THE WARM-UP", "STICKY FINGERS", "IN DISGUISE", "DOUBLE ACTS", "THE FINALE"}
