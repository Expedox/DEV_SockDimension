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

- `pair_id`: 0 to pairs-1. `sock_id = pair_id * 2 + side` (side 0 or 1).
- Pair of a sock: `sock_id / 2`. Partner: `sock_id ^ 1`.
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

`scenes/cellar.tscn`, root `class_name Cellar extends Node3D`:

- `player_spawn() -> Transform3D`
- `basket_mouth() -> Vector3`
- `signal sock_entered_basket(body: Node3D)`
- Floor, walls and basket walls are `StaticBody3D` on layer 1. Pile centre is the origin, floor at y = 0.

### Player

`scenes/player.tscn`, root `class_name Player extends CharacterBody3D`:

- `setup(field: SockField)`
- `held_sock() -> Sock`, null if nothing is held
- `aimed_sock() -> Sock`: what the crosshair is on, excluding the held sock
- `release_held()`: drops the hold without physics changes, for a matched sock
- `wiggle_held()`: short shake for a wrong pair
- `capture() -> Dictionary` and `apply(state: Dictionary)`: `position, yaw, pitch, held` (sock_id or -1)

### Pairs

`class_name PairController extends Node`, child of the game scene:
`setup(player: Player, field: SockField, cellar: Cellar)`. Handles the `pair`
action and calls `GameState.register_match(pair_id, base_color, pattern_type)`
or `GameState.register_mismatch(near_miss)`. These emit
`Events.pair_matched(pair_id, base_color, pattern_type)` and
`Events.pair_mismatched(near_miss)`. It also emits `Events.sock_in_basket`.

### Game scene

`scenes/game.tscn` with `scripts/game.gd` builds the run: `Cellar`, `SockField`,
`Player`, `PairController`, and the UI scenes `scenes/ui/hud.tscn`,
`scenes/ui/pause_menu.tscn`, `scenes/ui/end_screen.tscn`,
`scenes/ui/loading_screen.tscn`, `scenes/ui/debug_overlay.tscn`. Missing scenes
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

## Measurement

(5,000 mode results go here.)

## Open points

- The project folder is on the Google Drive mount. Git works there, but Drive
  syncing a live `.git` folder can corrupt it. Push often, or move the checkout.
