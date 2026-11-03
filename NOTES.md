# Sock Dimension notes

Engine: Godot 4.7.2 stable, Jolt Physics. Binary on this PC:
`C:\Users\Mike\Downloads\Last Dude Standing\Godot_v4.7.2-stable_win64.exe`

## Interfaces

Everything below is the contract between the work areas. Change it only by
editing this section. Only touch files you own; ask the owner for a change
elsewhere. Commit only your own paths (`git add <paths>`, never `git add -A`).

### Who owns what

| Area | Files |
|---|---|
| Scaffold, integration | `project.godot`, `scripts/autoload/config.gd`, `events.gd`, `game_state.gd`, `scripts/game.gd`, `scenes/game.tscn`, `data/modes.json`, `data/input.json`, `data/gameplay.json`, this section |
| Player, grab, throw, inspect | `scripts/player/`, `scenes/player.tscn`, `data/player.json` |
| Sock designs | `scripts/socks/` (`sock_mesh.gd`, `sock_set.gd`, `sock_catalog.gd`, display), `shaders/`, `data/socks.json` |
| Physics, pour, debug overlay | `scripts/physics/`, `scripts/dev/`, `scripts/ui/debug_overlay.gd`, `data/physics.json`, section Measurement below |
| Pairs, basket, end screen | `scripts/pairs/`, `scripts/ui/end_screen.gd`, `scenes/ui/end_screen.tscn` |
| Menus, settings, HUD | `scripts/ui/` (other files), `scenes/main_menu.tscn`, `scenes/ui/` (other files), `scripts/autoload/settings.gd` |
| Save and load | `scripts/autoload/save_manager.gd`, `scripts/save/` |
| Achievements and texts | `scripts/achievements/`, `data/achievements.json`, `i18n/game_text.csv` |
| Cellar and audio | `scripts/world/`, `scenes/cellar.tscn`, `scripts/autoload/sfx.gd`, `data/world.json` |

### Data

`Config` (autoload) loads `data/*.json`: `Config.modes`, `.mode(id)`,
`.physics`, `.player`, `.gameplay`, `.world`, `.achievements`. JSON numbers
arrive as floats; cast with `int()`. Add keys to your own file freely. Input
actions come from `data/input.json`:
`move_forward/back/left/right, jump, pair, inspect, pause, debug, grab, throw`.

All text keys live in `i18n/game_text.csv` (`keys,en`, later `de`), owned by the
texts work. Show text with `tr("KEY")`, placeholders are `{name}` with
`String.format`.

Physics layers: 1 world, 2 socks, 3 player, 4 floor socks (lone socks resting flat on the floor; the player walks through them, rays for grabbing use `SockField.ANY_SOCK`). Socks collide with world and socks,
not the player. The player collides with world and socks.

### Sock format

- `sock_id` is the index into `SockSet` (0 .. `sock_count() - 1`), not derived from
  `pair_id`. Index order is shuffled and doubles as the pour order.
- `pair_id = SockSet.pair_of(sock_id)`, two socks per pair.
- Traits per pair: `shape` (sneaker, sport, knee), `base_color`, design (`pattern` +
  `count`), `accent_color`, `heel_toe` (contrast heel and toe). The accent only counts
  where it is visible. Near pairs differ from another pair in exactly one visible trait.
- Patterns are known to `sock.gdshader` by position: keep the order in `data/socks.json`
  (`SockCatalog.PATTERN_ORDER`).

`SockSet` (scripts/socks/sock_set.gd):

- `SockSet.generate(seed, pair_count, near_share) -> SockSet` (null if the data cannot fit);
  `near_share` comes from the mode in `data/modes.json`. `seed_from_text(text)`.
- `sock_count()`, `pair_of(sock_id)`, `shape_of(sock_id)`, `is_match(a, b)`, `is_near_miss(a, b)`
- `sock_info(sock_id) -> {pair_id, base_color, accent_color, pattern, count, shape, heel_toe}`
- `custom_data(sock_id) -> Color` for the MultiMesh, `validate() -> PackedStringArray`

`SockMesh` (static): `get_mesh(shape, detailed := false)`, `get_material(shape)`, `collision_size(shape) -> Vector3`
(box size for that shape; a sock body uses `collision_size(socks.shape_of(sock_id))`).
Mesh origin is the center of its bounding box, so body and box share the origin.

`SockCatalog` (static, `data/socks.json`): `colors()`, `palette_size()`, `pattern_count()`,
`shape_count()`, `color_id(i)`, `pattern_id(i)`, `shape_id(i)`, `capacity()`.

`SockRenderer extends Node3D` draws every sock: per shape a cheap MultiMesh for the
pile and a detailed one for up to `detail_capacity` socks within `detail_radius` of the
camera (`data/socks.json`). It swaps socks between them on its own each frame.

- `setup(socks: SockSet, bounds: AABB, shadows := SHADOW_CASTING_SETTING_ON)`: all socks start hidden
- `set_sock_transform(sock_id, xform)` (world space; push only for awake bodies), `hide_sock(sock_id)`,
  `get_sock_transform(sock_id)`

### Socks in the world

`class_name Sock extends RigidBody3D` with `var sock_id: int`.

`class_name SockField extends Node3D` owns all bodies and `var renderer: SockRenderer`:

- `pour(socks: SockSet, mode: Dictionary)`: emits `Events.pile_progress`, then `Events.pile_ready`
- `restore(socks: SockSet, state: Dictionary)`: same signals, no pouring; socks come back asleep and frozen. An empty state (saved while pouring) pours fresh
- `capture() -> Dictionary`: saved under `world.socks`, binary friendly (`ids`, `positions`, `rotations` as packed arrays, quaternions xyzw), never includes paired socks, empty while pouring
- `sock_at(collider: Object) -> Sock`: null if it is not a sock
- `sock_by_id(sock_id: int) -> Sock`: null if gone or set aside
- `begin_hold(sock: Sock)`: makes it dynamic, weightless, and wakes its surroundings within `wake_radius`
- `end_hold(sock: Sock)`: normal physics again
- `throw_sock(sock: Sock, velocity: Vector3)`: ends the hold and tracks the flight; emits `Events.sock_landed`
- `wake_around(position: Vector3, radius: float)`
- `set_aside(sock: Sock)`: takes a matched sock out of physics at once, its transform stays in the renderer for the flight animation
- `remove_pair(a: Sock, b: Sock)`: removes both for good and wakes around them
- `surface_height() -> Vector3`: highest resting sock, refreshed over about 20 frames
- `set_aside(sock: Sock)`: takes a matched sock out of physics and out of
  `sock_entered_basket` (no collision, no body), but keeps it in `capture()`
  until `remove_pair()`, so a save during the flight to the basket loses nothing
- `renderer: SockRenderer`: the MultiMesh display; the pair flight moves and
  hides the two matched socks through it
- Emits `Events.socks_moving(count)` after the pile is ready when the count of socks faster than `moving_speed` changes noticeably (awake but still socks do not count)
- Debug values: `awake_count()`, `body_count()`, `moving_count`, `pour_seconds`, `script_usec`; the field is in group `sock_field`

### Cellar

`scenes/cellar.tscn`, root `class_name Cellar` (`scripts/world/cellar.gd`), with
`.basket: LaundryBasket`. The level is called Cellar everywhere; there is no Basement class.

- `player_spawn() -> Transform3D`
- `basket_mouth() -> Vector3`
- `signal sock_entered_basket(body: Node3D)`
- Floor, walls and basket walls are `StaticBody3D` on layer 1. Pile centre is the origin, floor at y = 0.
- `room_bounds() -> AABB`: inside of the room
- `basket: LaundryBasket`: `mouth()` (drop point above the rim), `receive_pair()` when a pair lands (pile grows, `signal pair_received(total)`), `set_pair_count(n)` after loading, `get_pile_top() -> Vector3`
- `sock_entered_basket` fires for anything on layer 2 inside the basket, so freeze or remove a rolled-up pair before it arrives, or it reads as a trick shot.

Layout, colours, lamps, windows, props and ambience are in `data/world.json`, shaders are
`shaders/cellar_*` (shared noise in `cellar_noise.gdshaderinc`). The look relies on
SSAO, SSIL, glow and light volumetric fog, all switchable in `world.json` → `environment`.
Only the centre lamp casts shadows; the side lamps and windows do not, to keep the
shadow pass cheap with the pile in view. If the 5,000 measurement is tight, turn off
`ssil` and `volumetric_fog` first.

### Audio

`Sfx` (autoload): `play(sound: String, position: Variant = null, volume_db := 0.0)`.
Sounds: `match`, `mismatch`, `throw`, `plop`, `grab`, `drip`, `pipe_knock`. Pass a `Vector3` for world sound, leave it out for flat sound.
Recipes are in `data/sfx.json`; a new sound is one more entry there. `throw`, `plop` and `grab` already play from `Events.sock_thrown`, `Events.sock_landed` and `Events.sock_grabbed`, so do not call those for that case.
`start_loop(loop, parent, position = null) -> Node` starts a seamless loop from `loops` in `sfx.json` as a child of `parent`; the cellar uses it for `room_tone` and `boiler_hum`.
Bus `SFX` is created on start if missing, sending to `Master`. World sounds and loops go through bus `Room` (soft cellar reverb, settings under `room`), which sends to `SFX`, so the effects volume covers them. Flat sounds stay dry on `SFX`.

### Player

`scenes/player.tscn`, root `class_name Player extends CharacterBody3D`:

- `setup(field: SockField)`
- `held_sock() -> Sock`, null if nothing is held: the active sock of the bundle
- Bundle: up to `carry_max` socks (data/player.json). `carried_socks()` and
  `carry_count()`. LMB on a sock grabs it into the hand (the old one goes under
  the arm), LMB on empty space drops the active sock, Q drops all, mouse wheel
  switches the active sock. Throw, pair, inspect and the cheat glow use the
  active sock; after a throw, drop or match the next one moves up. Carried socks
  stay ghosts (`SockField.carry`), so they never plough through the pile.
- `aimed_sock() -> Sock`: what the crosshair is on, excluding the held sock
- `release_held()`: drops the hold without physics changes, for a matched sock
- `wiggle_held()`: short shake for a wrong pair
- `capture() -> Dictionary` and `apply(state: Dictionary)`: `position, yaw, pitch, held` (sock_id or -1), `carried` (sock ids, may be missing in old saves)
- `place(spawn: Transform3D)`: feet position and facing
- To give back the held sock after loading it needs `SockField.sock_by_id(id) -> Sock` (physics, please add)
- Emits `Events.sock_grabbed(sock_id)` / `Events.sock_released(sock_id)`, and
  calls `GameState.register_throw(sock_id)` on every throw (that emits
  `Events.sock_thrown`, so do not emit it yourself)
- Emits `Events.summit_reached` once per run when standing on the floor within
  `Config.gameplay.summit_radius` (horizontal) of `field.surface_height()`

### Pairs

`class_name PairController extends Node`, child of the game scene:
`setup(player: Player, field: SockField, cellar: Cellar, socks: SockSet)`
(player, field and socks typed loosely in code until `SockField` exists).
Handles the `pair`
action and calls `GameState.register_match(pair_id, base_color, pattern_type)`
or `GameState.register_mismatch(near_miss)`. These emit
`Events.pair_matched(pair_id, base_color, pattern_type)` and
`Events.pair_mismatched(near_miss)`. A match counts on landing in the basket,
not on the key press. It emits `Events.sock_in_basket(sock_id)` when a single
thrown sock (thrown and not grabbed since) lands in the basket.

### Sock wall and room size

`SockWall` (`scripts/world/sock_wall.gd`), built by `game.gd` under the cellar,
values in `data/world.json` → `pair_wall`. Found pairs hang on peg rails on
wooden boards over all four walls up to the beams (six panels, kept clear of the
shelf, washer corner, clothesline and back windows). The rails read like a book,
panel by panel from the east wall round to the back wall: shape first (new row
plus a found/total label), then base colour (small gap between colours), then
pattern, count, accent and heel/toe. Every pair of the set has a fixed slot from
the start, so empty pegs show what is missing. Neighbouring pairs overlap a
little like in a sock shop (`overlap`). The layout picks the largest scale up to
1.0 (pile size) at which the whole set fits. One MultiMesh per shape (far mesh,
sock shader, no shadows) plus one for the rails. `Events.pair_matched` adds a
pair with a short pop; nothing extra is saved, the wall is rebuilt from `found`.

Mike wants every pair on the wall at pile size, so each mode has its own cellar
size in `data/modes.json` → `room_size`: Laundry Day 26 × 7.5 × 20 m, Sock
Dimension 46 × 12 × 36 m, both 1:1. `data/world.json` stays written for its own
18 × 14 × 6 m room; `Config.use_mode_room()` (called by `GameState._reset`)
stretches it: things near a wall move with the wall, things near the middle
stay, things in the upper half move with the ceiling, lamps hang lower and a
grid of extra side lamps fills a big floor (`lamp_spacing`, default 9 m). Spawn
and basket stay near the pile.
Screenshots: `scenes/dev/wall_shot.tscn -- <mode> <share> <png prefix>`.

### Game scene

`scenes/game.tscn` with `scripts/game.gd` builds the run: `Cellar`, `SockField`,
`Player`, `PairController`, and the UI scenes `scenes/ui/hud.tscn`,
`scenes/ui/pause_menu.tscn`, `scenes/ui/end_screen.tscn`,
`scenes/ui/loading_screen.tscn`, `scenes/ui/debug_overlay.tscn`. The field is loaded
from `scripts/physics/sock_field.gd`. Missing scenes
are skipped, so each area can land on its own. It sets
`GameState.world_provider` and `GameState.running`.

Each UI scene does its work from signals and `GameState`. The pause menu handles
`pause` itself and calls `SaveManager.save_current()` and
`GameState.to_main_menu()`.

### Starting and leaving a run

- `GameState.start_new(mode_id, seed_text)`
- Save slots: `Config.gameplay.save_slots` (3) files `user://saves/slot_<n>.save`; the live run writes to `GameState.slot`
- `SaveManager.continue_run(slot)` reads the file, then calls `GameState.start_loaded(data, slot)`
- `GameState.start_new(mode, seed_text, slot)`; New Game picks a slot (`SlotSelect`), then a mode; with no save at all it goes straight to slot 1
- `GameState.to_main_menu()`: does not save; callers save first
- `SaveManager.save_current() -> bool`: no-op until the pile is ready; emits `Events.game_saved`
- `SaveManager.save_and_quit()`: use for every Quit button instead of `get_tree().quit()`
- `SaveManager.has_save(slot)`, `has_any_save()`, `free_slot()`, `delete_slot(slot)`
- `SaveManager.latest_slot() -> int`: newest unfinished slot, or 0 (Continue shows only if > 0)
- `SaveManager.slot_info(slot) -> Dictionary`: `mode, completed, pairs_found,
  play_time, saved_at` (unix seconds), or `{}`. Reads the whole file, so cache it in menus.
- Old per-mode saves (`<mode>.save`) move into free slots on start, newest first, and are renamed to `.migrated`
- Autosave every `Config.gameplay.autosave_seconds`, once right after a fresh
  pour, when a run finishes, and on window close.
- `GameState.capture() -> Dictionary`: the full save payload, keys `mode, seed,
  play_time, mistakes, throws, completed, streak, near_misses, found, world`.
  `world` is `{socks: SockField.capture(), player: Player.capture()}`.
- `SafeFile.write(path, version, data) -> bool` and `SafeFile.read(path)` (returns
  `{version, data, from_backup}` or `{}`) in
  `scripts/save/safe_file.gd` do the safe `.tmp`/`.bak` writing for both save
  files and achievements.

Marathon uses `GameState.session_time`; Eagle Eye uses `GameState.streak`; So
Close uses `GameState.near_misses` (or `pair_mismatched(true)`).

### Menus, settings and HUD

- `Settings` (autoload) loads `user://settings.cfg` with defaults and ranges from
  `data/settings.json`, applies volume (buses `Master`, `SFX`), language,
  window mode and VSync, and sets the shared theme on the root window. Fields:
  `mouse_sensitivity, invert_mouse, fov, volume_master, volume_sfx, fullscreen,
  vsync, language`. Read them live (the player should read sensitivity, invert
  and FOV every frame or on `Settings.changed`).
- The HUD reads `held_sock()` and `aimed_sock()` from
  `GameState.world_provider.player` for the crosshair and the control hint.
- Mouse capture: the loading screen captures on `pile_ready`, the pause menu
  frees it on open and captures on resume. The end screen frees it.
- The pause menu opens on `pause` (and when the window loses focus) only while
  `GameState.running` is true and the tree is not paused.
- Sub screens (`ModeSelect`, `SettingsPanel`, `AchievementsMenu`) are full-screen
  Controls with `signal closed`; the opener frees them.
- `UiKit.format_time()` is the shared clock format.

## Tests

`godot --headless --path . --import` once, then
`godot --headless --path . res://tests/test_runner.tscn` (exit code 0 = passed).
It writes only under `user://tests/`. GitHub Actions runs the same on every push
(`.github/workflows/tests.yml`). Fakes for the player and field are in
`tests/fakes.gd`; replace them with the real scenes once those exist.

## Measurement

Headless timing in the cloud (Godot 4.7.2 Linux, Jolt, 4 threads of a shared
Xeon at 2.8 GHz, no rendering). Run it again with:

    godot --headless --fixed-fps 60 --path . res://scenes/dev/pour_benchmark.tscn -- sock_dimension [nofreeze]

`--fixed-fps 60` makes every frame exactly one physics step, so the numbers are
CPU cost per frame. **The real FPS check (with rendering of 10,000 socks) still
has to happen on Mike's PC**, with F1 open.

**Plain Jolt sleeping is not enough.** Jolt sleeps whole groups of touching
bodies, and a pile is one group. Without freezing (`nofreeze`), pouring the
5,000 mode kept all 9,000 socks awake for minutes at 200 to 250 ms per frame,
and in the laundry mode waking 512 socks at the summit cost about 40 ms per
frame until the pile slept again.

**Fallback in use: resting socks are frozen** (`freeze_settled` in
`data/physics.json`). A sock that has barely moved for `rest_seconds` is put to
sleep and frozen (static), so the pile is never one big group. Grabbing,
removing a pair or setting a sock aside unfreezes everything within
`wake_radius` (1.5 m). Socks faster than `chain_wake_speed` wake their direct
neighbours, so a slide spreads on its own. Pour waves wait while more than
`pour_max_awake` socks are moving. Set `freeze_settled` to false to compare.

5,000 mode (10,000 socks), with freezing:

| Phase | avg ms | median | p95 | max |
|---|---|---|---|---|
| Pour (558 frames, ready after 8.8 s, summit 2.4 m) | 15.9 | 15.9 | 30.7 | 43.5 |
| Idle pile, 300 frames | 1.4 | 0.8 | 7.3 | 15.0 |
| After waking 512 socks at the summit | 1.8 | 0.8 | 9.5 | 27.6 |
| First second after restore | 1.4 | 0.7 | 1.2 | 36.7 |

- Generating the set: 50 ms. `capture()`: 25 ms, 312 KB. Restore: 0.3 s.
- Laundry day (2,000 socks): pour ready after 2.8 s, idle 0.6 ms, waking 512 socks 1.5 ms average.
- Physics is the cost; the field's own script work stays under 0.7 ms per frame.

**Pile shape (Nov 3):** waves now land more often near the centre (`pour_cone_power`),
so the pile is a hill, not a drum with straight walls. Boxes hold the slope;
capsules (`sock_shape`) slid into a flat 0.6 m mound. Measured headless:
Laundry day summit 1.7 m, pour 6 s; 5,000 mode summit 4.6 m, 90 % of socks
within 3 m, pour 55 s at 33 ms per frame, idle 0.8 ms, waking the summit 4.8 ms.
The held sock leaves its collision layer, so it never pushes the player.

**Bigger pile (Nov 3, Mike: more and somewhat bigger socks):** socks are drawn
and collide at 1.3x life size (`scale` in `data/socks.json`), Laundry Day has
1,500 pairs, and pour noise (`pour_lumpiness`) makes humps and dips. Sock
Dimension stays at 5,000 pairs, because 7,500 at this size reached the spawn
point and the lamp in the 18 x 14 x 6 m cellar. Its pile is capped by
`pour_max_height`. Headless:
Laundry Day summit 3.0 m, pour 11 s, idle 0.9 ms; Sock Dimension summit 4.6 m,
pour 37 s at 25 ms per frame, idle 1.0 ms, waking 512 socks at the top 3.9 ms
avg with a 40 ms p95 for the first second while the top slides.

Open: these are CPU numbers only. The GPU side (one MultiMesh, 10,000
instances, shadows from the main lamp) is unmeasured until it runs on the PC.

## Final check (cloud, headless, Godot 4.7.2)

Run on 2026-11-03 against main, scripted through the real menus, game scene and
save files (no stubs):

| Step | Laundry Day | Sock Dimension |
|---|---|---|
| New game from the menu, pile ready | 2.8 s | 10.1 s |
| Grab, throw (throws counter) | ok | ok |
| Pair into basket (counter, basket pile) | ok | ok |
| Save while holding a sock, back to menu | ok | ok |
| Continue: counters, 2 socks gone, held sock back in hand, basket pile | ok | ok |

`tests/test_runner.tscn`: 102 checks, 0 failed. Fixed on the way: `remove_pair`
read the transform of a sock that was already out of the tree.

Not checked headless: how it looks and feels (mouse look, climbing, hold spring,
throws), audio, and the real FPS.

## Open points

- **FPS check on Mike's PC**: Sock Dimension mode, F1 open, idle, while
  pouring, and digging at the summit. Target 60 FPS. Write the numbers into
  Measurement above. If it misses, first lower `pour_max_awake`/shadows.
- Play both modes by hand once: tune `data/player.json` (speed, hold spring,
  throw speed) and climbing feel on the pile.
- German texts (`de` column in `i18n/game_text.csv`) are still to come.
- Steam: only `scripts/achievements/achievement_platform.gd` needs swapping.

- The project folder is on the Google Drive mount. Git works there, but Drive
  syncing a live `.git` folder can corrupt it. Push often, or move the checkout.
- Socks: the new knit shader and the three sock meshes were only checked in a
  software preview, not yet in Godot. First run on the PC: look for shader errors
  in the output, and check that the cuff opening is dark and the rib reads.
- FPS check on Mike's PC (Sock Dimension mode, 10,000 socks): the pile uses the far
  mesh (110 to 146 vertices, about 1.25 million in total), only socks within 2 m use
  the detailed one (236 to 340). Note FPS here. If it is short of 60: lower
  `far_sides` to 6, `detail_capacity`, or switch sock shadows off in `SockRenderer.setup`.
- Socks: a knee sock is a long L, so its box shape is mostly empty. If the pile looks
  too airy, try a smaller `collision_fit` for that shape.

## Intro, tutorial and starter pairs

- First new game shows five story beats (`scenes/ui/intro.tscn`) over the pour. Click/Space/Enter goes on, Esc skips. If the pile is ready first, the game stays paused until the story ends; the last beat fades to show the cellar.
- Then a tutorial card (`scenes/ui/tutorial.tscn`) walks through look, grab, inspect, throw and pair; each step waits for the action. Timings in `data/gameplay.json` → `tutorial`.
- Setting `show_intro` ("Story and tutorial on next new game") turns itself off after one showing; switch it on again in Settings to replay.
- A new run starts with only `starter_pairs` (data/gameplay.json, 3) whole pairs side by side on the washing machine lid (`SockField.prepare`). The washing machine is the tear into the Sock Dimension: once all starter pairs are found it shakes, bursts with a flash and foam (`scripts/world/washer_blast.gd`, data/world.json -> `washer_blast`) and throws every other sock on its own arc to a random spot across the whole room (`SockField.pour_rest` with a burst, then `Events.rain_finished`).
- Saves carry `rain_done`. Saved before the burst: the starters come back. Saved mid-burst: no stable snapshot, so it starts again from the starters (minus found pairs), and the burst follows at once if they are all found. Old saves count as done.

## Cellar atmosphere

- Sound: all background sound is synthesised at start (data/sfx.json "loops"). The washer churns in its corner (motor hum, sloshing drum, socks thumping in time with the drum), rain patters at both windows, plus the old room tone, drips and pipe knocks. A new "crackle" layer type in SoundSynth makes the drops and thumps. Background sounds run on their own "Ambience" bus with its own slider in Settings.
- Dust: GPUParticles3D under every lamp and along both moonbeams (amounts in data/world.json "dust" and per lamp/window). The shader only lights a mote where a lamp reaches it, so they sparkle in the cones.
- Windows: rain runs down the glass; the moonlight now points into the room (it pointed into the wall before).
- Graphics quality (Settings → Display): low / medium / high presets in data/world.json "quality" switch SSAO, SSIL, volumetric fog, SSAO detail, soft-shadow filter, shadow atlas and dust amount. Default high.
- Not yet measured on a real GPU: the cloud only has the Compatibility renderer (no fog, SSAO). Please check FPS with F1 on high and medium in Sock Dimension mode.

## Rare special designs

About 10 % of all pairs (`special_share` in data/socks.json) carry a rare
design: hearts, stars, zigzag, snowflakes, rainbow or paws, each in a small
and a large size. They are extra entries in `patterns` marked `"special"`, drawn
in sock.gdshader like the regular patterns (snapped to stitches, so they read
as knitted motifs). SockSet hands them out after all pairs exist, on its own
random stream, so pair ids and pour order are the same as before and older
saves still match. Only free-standing pairs get one; near pairs and their
sources keep their single-trait difference. On the wall each shape ends with
one group per special design, sorted by colour. Pattern Master still counts
the regular patterns; the hidden ACH_LUCKY_SOCK unlocks with the first special
pair. No extra glow or hints.
