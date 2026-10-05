class_name CurrencyManager
extends RefCounted

static func can_afford(profile: Dictionary, currency: String, amount: int) -> bool:
	return amount >= 0 and int(profile.get(currency, 0)) >= amount

static func spend(profile: Dictionary, currency: String, amount: int) -> bool:
	if not can_afford(profile, currency, amount):
		return false
	profile[currency] = int(profile.get(currency, 0)) - amount
	return true

static func grant(profile: Dictionary, currency: String, amount: int) -> void:
	profile[currency] = maxi(int(profile.get(currency, 0)) + amount, 0)
