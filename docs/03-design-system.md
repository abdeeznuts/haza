# Haza — Design System

**Idea:** Apple's language (system components, SF Pro, restraint) with an editorial accent borrowed from luxury houses: a serif for the numbers that matter, monochrome surfaces, hairlines instead of boxes, one semantic color at a time. Nothing decorative; every mark encodes state.

## Color (tokens in `ios/Haza/Resources/Assets.xcassets` and the prototype's CSS)

| Token | Dark (default) | Light | Use |
|---|---|---|---|
| Bg | #0B0B0C | #F6F4EE | page ground (asphalt / ivory) |
| Surface | #151517 | #FFFFFF | sheets, cards |
| Surface2 | #1E1E21 | #EEECE5 | glyph tiles, tracks |
| Ink | #F4F2EC | #111111 | text, primary buttons |
| Muted | #8E8E89 | #77776F | secondary text, eyebrows |
| Hair | Ink @ 14% | Ink @ 14% | dividers, outlines |
| Live | #30D158 | #1F9D48 | *only* talk-on / joined / transmitting |
| Alert | #FF453A | #D62B22 | *only* radar alerts |

The brand has no accent color. Green means "someone can hear you", red means "radar". If a screen needs a third color, the design is wrong.

## Type

- Display: **New York** (`Font.system(design: .serif)`), regular weight, tight leading. Speed readouts, headlines, stat values, the Hold button. Tabular numerals everywhere digits change.
- Text: **SF Pro** (system). 16/15/13/12 sizes; medium for row titles, regular for body.
- Labels: SF Pro semibold 11, uppercase, +0.12em tracking ("Eyebrow").
- V1 panel: SF Mono in LED red on true black — a faithful front panel, not a skin.

## Layout

- 20 pt margins, 14 pt row padding, 16 pt card radius (continuous), 14 pt buttons, capsule chips.
- Lists are hairline-separated rows (glyph · title/subtitle · trailing state). Cards are reserved for the few things that are objects: a plan, the referral card, the V1 panel, a stat block.
- Map is full-bleed; controls float in `.ultraThinMaterial` capsules; the sheet is a surface with a hairline top.
- One primary action per screen. The Talk screen has exactly one object: the button.

## Motion

- Hold-to-talk: 120 ms press scale (0.94), 1.1 s expanding ring while transmitting, none with Reduce Motion.
- Sheet: spring 0.35. Everything else is default SwiftUI.

## Voice (copy)

Short, second person, no exclamation marks. Controls say what happens ("Set home here", "Go live"). Privacy sentences state the rule, not a reassurance ("Inside 150 m of home, friends see the pin, never your exact spot"). Speed is a readout, never a score.

## Surfaces

- CarPlay widget (systemSmall): channel eyebrow, speed now + predicted, Talk toggle. Background removable so CarPlay draws its own.
- Live Activity: title, cars, distance, radar summary, big speed. Same small family on Watch Smart Stack and CarPlay Dashboard.
- Watch: one green circle. Hold = talk. Name in the circle when someone else is talking.
- Control: mic glyph, "Talk", On/Off.
