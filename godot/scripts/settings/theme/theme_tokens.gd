class_name ThemeTokens

const PANEL_MARGIN := Vector4(8, 6, 8, 6)
const BUTTON_MARGIN := Vector4(10, 6, 10, 6)

## Embedded windows draw their border over the client rect only, so the frame has
## to expand outward to reach the title bar strip above it.
const WINDOW_BORDER_EXPAND := Vector4(8, 32, 8, 6)

const BUTTON_TYPES := ["Button", "MenuButton", "OptionButton", "CheckBox", "CheckButton"]

const ICON_SIZE := 16
const ICON_SUPERSAMPLE := 4
const ICON_STROKE := 1.6

## Custom theme types carrying the app's semantic colors, so widgets that paint
## themselves resolve them through normal theme propagation instead of holding
## their own literals.
const STATUS_TYPE := &"Status"
const RADIAL_TYPE := &"RadialMenu"

const STATUSBAR_TYPE := &"StatusBar"
const STATUSBAR_CARD_TYPE := &"StatusBarCard"
const BAR_BUTTON_TYPES := {&"StatusBarButton": &"Button", &"StatusBarMenuButton": &"MenuButton"}
const CARD_MARGIN := Vector4(12, 4, 12, 4)

const DOT_TILE := 24
const DOT_RADIUS := 5.0

## Signal colors, shared by every theme so a phase reads the same regardless of
## palette. The hues are the contract; `ColorMath.fit()` moves their lightness per
## theme so they survive a light or mid-luminance panel.
## so they survive a light or mid-luminance panel.
const STATUS_COLORS := {
	&"idle": Color(0.55, 0.75, 1.0),
	&"init": Color(0.4, 0.9, 0.4),
	&"running": Color(1, 0.3, 0.3),
	&"neutral": Color.WHITE,
	&"ok": Color.GREEN_YELLOW,
	&"warn": Color.ORANGE,
	&"connected": Color.GREEN_YELLOW,
	&"disconnected": Color.INDIAN_RED,
	&"endgame": Color.ORANGE_RED,
	&"slot1": Color.GREEN_YELLOW,
	&"slot2": Color.ORANGE,
}

const DEFAULT_RADIAL_COLORS := {
	&"slice": Color(0.16, 0.19, 0.24, 0.92),
	&"slice_disabled": Color(0.10, 0.11, 0.13, 0.92),
	&"slice_highlight": Color(0.20, 0.45, 0.60, 0.95),
	&"rim": Color(0.6, 0.75, 0.85, 0.5),
	&"center": Color(0.05, 0.06, 0.08, 0.9),
	&"label": Color(1, 1, 1),
	&"cursor": Color(1, 1, 1),
}
