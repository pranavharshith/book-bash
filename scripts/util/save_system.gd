class_name SaveSystem
extends RefCounted
## Versioned JSON persistence with rollback-safe replacement. The old profile is
## retained as a backup until the new temp file has become the primary profile.

const SAVE_PATH := "user://book_bash_profile.json"
const TEMP_PATH := "user://book_bash_profile.tmp"
const BACKUP_PATH := "user://book_bash_profile.bak"

static func load_profile(default_profile: Dictionary) -> Dictionary:
	var path := SAVE_PATH
	if not FileAccess.file_exists(path) and FileAccess.file_exists(BACKUP_PATH):
		path = BACKUP_PATH
	if not FileAccess.file_exists(path):
		return default_profile.duplicate(true)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return default_profile.duplicate(true)
	var parsed = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		backup_corrupt_save(path)
		return default_profile.duplicate(true)
	return _merge_defaults(parsed, default_profile)

static func save_profile(profile: Dictionary) -> bool:
	var temp_file := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	if temp_file == null:
		return false
	temp_file.store_string(JSON.stringify(profile, "\t"))
	temp_file.flush()
	temp_file.close()

	var save_absolute := ProjectSettings.globalize_path(SAVE_PATH)
	var temp_absolute := ProjectSettings.globalize_path(TEMP_PATH)
	var backup_absolute := ProjectSettings.globalize_path(BACKUP_PATH)
	if FileAccess.file_exists(BACKUP_PATH):
		DirAccess.remove_absolute(backup_absolute)
	var had_primary := FileAccess.file_exists(SAVE_PATH)
	if had_primary and DirAccess.rename_absolute(save_absolute, backup_absolute) != OK:
		return false
	if DirAccess.rename_absolute(temp_absolute, save_absolute) == OK:
		if FileAccess.file_exists(BACKUP_PATH):
			DirAccess.remove_absolute(backup_absolute)
		return true
	if had_primary and FileAccess.file_exists(BACKUP_PATH):
		DirAccess.rename_absolute(backup_absolute, save_absolute)
	return false

static func backup_corrupt_save(path: String = SAVE_PATH) -> void:
	if not FileAccess.file_exists(path):
		return
	var backup := "user://book_bash_profile_corrupt_%d.json" % Time.get_unix_time_from_system()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(backup))

static func _merge_defaults(value: Dictionary, defaults: Dictionary) -> Dictionary:
	var merged := defaults.duplicate(true)
	for key in value:
		if defaults.has(key) and defaults[key] is Dictionary and value[key] is Dictionary:
			merged[key] = _merge_defaults(value[key], defaults[key])
		else:
			merged[key] = value[key]
	return merged
