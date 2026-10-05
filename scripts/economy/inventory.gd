class_name Inventory
extends RefCounted

static func owns(profile: Dictionary, item_id: String) -> bool:
	return item_id in profile.get("inventory", [])

static func unlock(profile: Dictionary, item_id: String) -> bool:
	var items: Array = profile.get("inventory", [])
	if item_id in items:
		return false
	items.append(item_id)
	profile["inventory"] = items
	return true

static func equip(profile: Dictionary, category: String, item_id: String) -> bool:
	if not owns(profile, item_id):
		return false
	var equipped: Dictionary = profile.get("equipped", {})
	equipped[category] = item_id
	profile["equipped"] = equipped
	return true
