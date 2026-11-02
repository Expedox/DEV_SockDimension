class_name SafeFile
extends RefCounted
## Crash-safe binary files for anything under user://.
##
## Layout: magic, format version, store_var payload, end marker. The end marker
## makes a truncated file detectable. A write goes to <path>.tmp first, the old
## file becomes <path>.bak, then the .tmp is renamed into place, so a crash at
## any point leaves at least one readable copy.

const TMP_SUFFIX := ".tmp"
const BAK_SUFFIX := ".bak"
const MAGIC := 0x4B434F53 # "SOCK"
const END_MARKER := 0x444E4553 # "SEND"
const HEADER_SIZE := 8
const FOOTER_SIZE := 4


## Writes data safely. version is the caller's own schema version.
static func write_var(path: String, data: Variant, version: int) -> Error:
	var dir_err := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if dir_err != OK:
		return dir_err

	var tmp_path := path + TMP_SUFFIX
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_32(MAGIC)
	file.store_32(version)
	if not file.store_var(data):
		file.close()
		DirAccess.remove_absolute(tmp_path)
		return ERR_FILE_CANT_WRITE
	file.store_32(END_MARKER)
	file.flush()
	var write_err := file.get_error()
	file.close()
	if write_err != OK or not _has_valid_frame(tmp_path):
		DirAccess.remove_absolute(tmp_path)
		return ERR_FILE_CANT_WRITE

	var bak_path := path + BAK_SUFFIX
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(bak_path):
			DirAccess.remove_absolute(bak_path)
		var bak_err := DirAccess.rename_absolute(path, bak_path)
		if bak_err != OK:
			DirAccess.remove_absolute(tmp_path)
			return bak_err
	return DirAccess.rename_absolute(tmp_path, path)


## Reads path, falling back to the .bak copy if the main file is missing or
## damaged. Result keys: ok, version, data, from_backup.
static func read_var(path: String) -> Dictionary:
	var result := _read_single(path)
	if result.ok:
		return result
	result = _read_single(path + BAK_SUFFIX)
	result.from_backup = result.ok
	return result


## True if read_var would find a file, without loading its payload.
static func exists(path: String) -> bool:
	return _has_valid_frame(path) or _has_valid_frame(path + BAK_SUFFIX)


## Deletes the file and its .tmp and .bak companions.
static func remove(path: String) -> void:
	for candidate: String in [path, path + TMP_SUFFIX, path + BAK_SUFFIX]:
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(candidate)


static func _read_single(path: String) -> Dictionary:
	var result := {"ok": false, "version": 0, "data": null, "from_backup": false}
	if not _has_valid_frame(path):
		return result
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return result
	file.seek(4)
	result.version = file.get_32()
	result.data = file.get_var()
	result.ok = file.get_error() == OK and file.get_position() == file.get_length() - FOOTER_SIZE
	return result


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
