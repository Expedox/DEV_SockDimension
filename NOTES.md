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

Physics layers: 1 world, 2 socks, 3 player. Socks collide with world and socks,
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

`SockMesh` (static): `get_mesh(shape)`, `get_material(shape)`, `collision_size(shape) -> Vector3`
(box size for that shape; a sock body uses `collision_size(socks.shape_of(sock_id))`).
Mesh origin is the center of its bounding box, so body and box share the origin.

`SockCatalog` (static, `data/socks.json`): `colors()`, `palette_size()`, `pattern_count()`,
`shape_count()`, `color_id(i)`, `pattern_id(i)`, `shape_id(i)`, `capacity()`.

`SockRenderer extends Node3D` draws every sock, one MultiMesh per shape:

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
- `held_sock() -> Sock`, null if nothing is held
- `aimed_sock() -> Sock`: what the crosshair is on, excluding the held sock
- `release_held()`: drops the hold without physics changes, for a matched sock
- `wiggle_held()`: short shake for a wrong pair
- `capture() -> Dictionary` and `apply(state: Dictionary)`: `position, yaw, pitch, held` (sock_id or -1)
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
- `SaveManager.continue_run(mode_id)` reads the file, then calls `GameState.start_loaded(data)`
- `GameState.to_main_menu()`: does not save; callers save first
- `SaveManager.save_current() -> bool`: no-op until the pile is ready; emits `Events.game_saved`
- `SaveManager.save_and_quit()`: use for every Quit button instead of `get_tree().quit()`
- `SaveManager.has_save(mode_id) -> bool`: any save, finished or not (for "Overwrite?")
- `SaveManager.latest_save() -> String`: newest unfinished save's mode, or "" (Continue shows only if not "")
- `SaveManager.save_info(mode_id) -> Dictionary`: `mode, completed, pairs_found,
  play_time, saved_at` (unix seconds), or `{}`. Reads the whole file, so cache it in menus.
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

Open: these are CPU numbers only. The GPU side (one MultiMesh, 10,000
instances, shadows from the main lamp) is unmeasured until it runs on the PC.

## Open points

- The project folder is on the Google Drive mount. Git works there, but Drive
  syncing a live `.git` folder can corrupt it. Push often, or move the checkout.
- Socks: the new knit shader and the three sock meshes were only checked in a
  software preview, not yet in Godot. First run on the PC: look for shader errors
  in the output, and check that the cuff opening is dark and the rib reads.
- Socks: one sock is 236 (sneaker) to 340 (knee) vertices, so 10,000 socks are about
  2.8 million vertices, more with lamp shadows. Measure; if it is too much, drop
  `sides` in `data/socks.json` to 10 or switch sock shadows off in `SockRenderer.setup`.
- Socks: a knee sock is a long L, so its box shape is mostly empty. If the pile looks
  too airy, try a smaller `collision_fit` for that shape.
