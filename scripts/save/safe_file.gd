class_name SafeFile
extends RefCounted
## Crash-safe binary files for anything under user://.
##
## Layout: magic, version, store_var payload, end marker. The end marker makes
## a truncated file detectable. A write goes to <path>.tmp first, the old file
## becomes <path>.bak, then the .tmp is renamed into place, so a crash at any
## point leaves at least one readable copy.

const TMP_SUFFIX := ".tmp"
const BAK_SUFFIX := ".bak"
const MAGIC := 0x4B434F53 # "SOCK"
const END_MARKER := 0x444E4553 # "SEND"
const HEADER_SIZE := 8
const FOOTER_SIZE := 4


## Writes data safely. version is the caller's own schema version.
static func write(path: String, version: int, data: Variant) -> bool:
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
		return false

	var tmp_path := path + TMP_SUFFIX
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_32(MAGIC)
	file.store_32(version)
	var stored := file.store_var(data)
	file.store_32(END_MARKER)
	file.flush()
	stored = stored and file.get_error() == OK
	file.close()
	if not stored or not _has_valid_frame(tmp_path):
		DirAccess.remove_absolute(tmp_path)
		return false

	var bak_path := path + BAK_SUFFIX
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(bak_path):
			DirAccess.remove_absolute(bak_path)
		if DirAccess.rename_absolute(path, bak_path) != OK:
			DirAccess.remove_absolute(tmp_path)
			return false
	return DirAccess.rename_absolute(tmp_path, path) == OK


## Returns {"version", "data", "from_backup"}, or {} when neither the file nor
## its .bak copy is usable.
static func read(path: String) -> Dictionary:
	var result := _read_one(path)
	if not result.is_empty():
		return result
	result = _read_one(path + BAK_SUFFIX)
	if not result.is_empty():
		result.from_backup = true
	return result


## True if read() would find a file, without loading its payload.
static func exists(path: String) -> bool:
	return _has_valid_frame(path) or _has_valid_frame(path + BAK_SUFFIX)


## Deletes the file and its .tmp and .bak companions.
static func remove(path: String) -> void:
	for candidate: String in [path, path + TMP_SUFFIX, path + BAK_SUFFIX]:
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)


static func _read_one(path: String) -> Dictionary:
	if not _has_valid_frame(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	file.seek(4)
	var version := file.get_32()
	var data: Variant = file.get_var()
	if file.get_error() != OK or file.get_position() != file.get_length() - FOOTER_SIZE:
		return {}
	return {"version": version, "data": data, "from_backup": false}


static func _has_valid_frame(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < HEADER_SIZE + FOOTER_SIZE:
		return false
	if file.get_32() != MAGIC:
		return false
	file.seek(file.get_length() - FOOTER_SIZE)
	return file.get_32() == END_MARKER
