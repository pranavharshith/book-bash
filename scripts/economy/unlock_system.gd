class_name UnlockSystem
extends RefCounted

static func purchase(profile: Dictionary, item: Dictionary) -> String:
	var item_id: String = item.get("id", "")
	if item_id == "":
		return "Invalid item"
	if Inventory.owns(profile, item_id):
		return "Already owned"
	var currency: String = item.get("currency", "coins")
	var price: int = item.get("price", 0)
	if not CurrencyManager.spend(profile, currency, price):
		return "Not enough %s" % currency
	Inventory.unlock(profile, item_id)
	return "Purchased %s" % item.get("name", item_id)
