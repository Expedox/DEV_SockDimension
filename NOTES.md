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

- `sock_id` is the index into `SockSet`, not derived from `pair_id`.
- The generator, mesh and display API is written by the sock designs work:
  `SockSet.generate(seed, pair_count, near_share)`, `sock_count()`,
  `custom_data(i)`, `SockMesh.get_mesh()`, `make_material()`, `collision_size()`.
  `near_share` comes from the mode in `data/modes.json`.

### Socks in the world

`class_name Sock extends RigidBody3D` with `var sock_id: int`.

`class_name SockField extends Node3D` owns all bodies and a `SockDisplay`:

- `pour(socks: SockSet, mode: Dictionary)`: emits `Events.pile_progress`, then `Events.pile_ready`
- `restore(socks: SockSet, state: Dictionary)`: same signals, no pouring
- `capture() -> Dictionary`: saved under `world.socks`, binary friendly (packed arrays), never includes paired socks
- `sock_at(collider: Object) -> Sock`: null if it is not a sock
- `begin_hold(sock: Sock)`: makes it dynamic, weightless, and wakes its surroundings within `wake_radius`
- `end_hold(sock: Sock)`: normal physics again
- `throw_sock(sock: Sock, velocity: Vector3)`: ends the hold and tracks the flight; emits `Events.sock_landed`
- `wake_around(position: Vector3, radius: float)`
- `remove_pair(a: Sock, b: Sock)`: removes both for good and wakes around them
- `surface_height() -> Vector3`: highest point of the pile right now
- Emits `Events.socks_moving(count)` when the count changes noticeably

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

Layout, colours and lamps are in `data/world.json`, shaders are `shaders/cellar_*`.

### Audio

`Sfx` (autoload): `play(sound: String, position: Variant = null, volume_db := 0.0)`.
Sounds: `match`, `mismatch`, `throw`, `plop`. Pass a `Vector3` for world sound, leave it out for flat sound.
Recipes are in `data/sfx.json`; a new sound is one more entry there. `throw` and `plop` already play from `Events.sock_thrown` and `Events.sock_landed`, so do not call those two for that case.
Bus `SFX` is created on start if missing, sending to `Master`.

### Player

`scenes/player.tscn`, root `class_name Player extends CharacterBody3D`:

- `setup(field: SockField)`
- `held_sock() -> Sock`, null if nothing is held
- `aimed_sock() -> Sock`: what the crosshair is on, excluding the held sock
- `release_held()`: drops the hold without physics changes, for a matched sock
- `wiggle_held()`: short shake for a wrong pair
- `capture() -> Dictionary` and `apply(state: Dictionary)`: `position, yaw, pitch, held` (sock_id or -1)
- `place(spawn: Transform3D)`: feet position and facing
- Emits `Events.summit_reached` once per run, `sock_grabbed`, `sock_released`; calls `GameState.register_throw`
- To give back the held sock after loading it needs `SockField.sock_by_id(id) -> Sock` (physics, please add)

### Pairs

`class_name PairController extends Node`, child of the game scene:
`setup(player: Player, field: SockField, cellar: Cellar, socks: SockSet)`.
The player calls `GameState.register_throw(sock_id)` on every throw. Handles the `pair`
action and calls `GameState.register_match(pair_id, base_color, pattern_type)`
or `GameState.register_mismatch(near_miss)`. These emit
`Events.pair_matched(pair_id, base_color, pattern_type)` and
`Events.pair_mismatched(near_miss)`. It also emits `Events.sock_in_basket`.

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
- `GameState.to_main_menu()`
- `GameState.capture() -> Dictionary`: the full save payload, keys `mode, seed,
  play_time, mistakes, throws, completed, streak, near_misses, found, world`.
  `world` is `{socks: SockField.capture(), player: Player.capture()}`.
- `SafeFile.write(path, version, data)` and `SafeFile.read(path)` in
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

## Measurement

(5,000 mode results go here.)

## Open points

- The project folder is on the Google Drive mount. Git works there, but Drive
  syncing a live `.git` folder can corrupt it. Push often, or move the checkout.
