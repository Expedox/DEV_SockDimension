class_name AchievementPlatform
extends RefCounted
## Bridge to a storefront's achievement API. This is the one file to replace
## for Steam: the local service stays the source of truth and calls these
## methods with the same IDs, so nothing else changes.
##
## This default build has no storefront, so every call is a no-op.


func is_available() -> bool:
	return false


## IDs the storefront already knows as unlocked, merged in at startup.
func get_unlocked_ids() -> PackedStringArray:
	return PackedStringArray()


func unlock(_id: String) -> void:
	pass


func set_progress(_id: String, _current: int, _target: int) -> void:
	pass


## Pushes pending changes to the storefront.
func store() -> void:
	pass


## Called every frame while the game runs, for APIs that need pumping.
func poll() -> void:
	pass
