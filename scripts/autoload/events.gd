extends Node
## Signal bus between gameplay, achievements, audio and UI.

# Gameplay facts
signal pair_matched(pair_id: int, base_color: int, pattern_type: int)
signal pair_mismatched(near_miss: bool)
signal sock_grabbed(sock_id: int)
signal sock_released(sock_id: int)
signal sock_thrown(sock_id: int)
signal sock_landed(sock_id: int, distance: float)
signal sock_in_basket(sock_id: int)
signal socks_moving(count: int)
signal summit_reached

# Run lifecycle
signal pile_progress(done: int, total: int)
signal pile_ready
## The washer bursts (started) and the scattered socks have settled (finished).
signal rain_started
signal rain_finished
signal run_started(mode_id: String)
signal run_finished(mode_id: String)

# Persistence and meta
signal game_saved
signal achievement_unlocked(id: String)
