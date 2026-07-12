# Controls

Every input on the Steam Deck, and what it does. The robot only ever sees
(xinput); everything that manages the driver station lives on the Deck's
extra inputs (back grips, trackpads, touchscreen). See `README.md` for the
Steam Input mapping.

## Passed to the robot (F310 contract)

| Deck input | F310 control |
|---|---|
| A/B/X/Y, D-pad | same |
| L/R sticks + L3/R3 clicks | same |
| L1/R1 bumpers, L2/R2 analog triggers | same |
| ☰ (Menu) | Start |
| ⧉ (View) | Back |

Packets advertise `GamepadType::LogitechF310` (set in `robocol_godot`).

## Desktop keyboard/mouse (non-Deck)

Off the Deck (`SteamDeck` env var unset) there's no privileged controller, so
each robot slot is claimed by the device itself:

- **Controller** — `Start + A` claims slot 1, `Start + B` claims slot 2
  (same chord as the FTC Driver Station). A new claimant bumps the current owner.
- **Keyboard** — `*[*` claims slot 1, `]` claims slot 2; ignored while a
  text field is focused.

Claims persist by device name across launches and re-resolve on
hot-plug (a reconnected pad reclaims its slot even under a new id). The status
bar shows both slots: `D` = Deck's own pad, `C` = other controller, `K` =
keyboard, `—` = unclaimed. The keyboard emulates a gamepad,
and only while no text field has focus.

Keyboard keymap:

| F310 control | Key(s) |
|---|---|
| Left stick | `Q W E` / `A S D` / `Z X C` — 8 headings; two adjacent keys average out, center `S` for 50% amplitude |
| Right stick | `U I O` / `J K L` / `M , .` — same shape, center `K` for 50% |
| D-pad | Arrow keys |
| A / B | Space / Shift |
| X / Y | F / H |
| L1 / R1 bumpers | 1 / 2 |
| L2 / R2 triggers | 3 / 4 (digital 0.0/1.0) |
| L3 / R3 stick clicks | Ctrl / Alt |
| Start / Back | Enter / Backspace |

## Driver-station controls (back grips)

| Input | Action |
|---|---|
| **F3** (R4) tap | E-STOP — inits `$Stop$Robot$`. Any page, any phase. |
| **F3** (R4) hold | While held, the gamepad drives the UI instead of the robot (the robot gets a fully neutral packet for the whole hold): both `sticks + d-pad` move focus, `L2 / R2 triggers` step the page tabs left / right; confirm with `A`. cancel with `X`. |
| **F1** (L4) tap/hold / **F2** (L5) tap/hold | Page-contextual — see **L4 / L5 by page** below. |
| **F4** (R5) tap | Swap gamepad slots (Only on Deck). |
| **F4** (R5) hold | **Slot-swap radial**: "1" left, "2" right. On swap the vacated slot gets one neutral packet so nothing sticks. |

The F-keys drive the real input. Grips reach the app via Steam Input, reccomened mappings are: L4->F1, L5->F2, R4->F3, R5->F4.

### L4 / L5 by page

| Page | F1 (L4) | F2 (L5) |
|---|---|---|
| **Drive** | Left pane — tap steps its source (webcam -> Limelight -> graphs -> telemetry, no skipping); hold opens its **source radial**. Landing on the other pane's source fullscreens it. | Right pane — same, for the right pane. |
| **Graphs** | Tap: shrink the graph's time window one step. | Tap: grow the time window one step. |
| **OpModes** | Tap: advance the run phase (INIT -> START -> STOP), same as the bottom action button. | Tap: cycle the group filter; hold: **group radial** (each group plus **All**). |
| **Config** | Tap: select the previous config in the list. | Tap: select the next config. |

## Pointer & other inputs

| Input | Action |
|---|---|
| **Trackpads** | Both drive the cursor. Both trackpad click-downs are left-clicks. |
| **Touchscreen** | Full interaction everywhere, every phase. |
| **Gyro** | Off. No role in v1. |
| **Steam / QAM (…)** | OS-reserved, untouched. |

## Radial behavior (all radials)

Hold to keep open, drive with the trackpad (cursor starts at center,
bounded to the radius). Release is the only terminal event: over a slice
-> select; over the center -> dismiss.
