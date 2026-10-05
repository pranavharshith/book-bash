class_name BattlePass
extends RefCounted

const XP_PER_TIER := 250
const MAX_TIER := 20

static func tier_for_xp(xp: int) -> int:
	return clampi(xp / XP_PER_TIER + 1, 1, MAX_TIER)

static func progress_in_tier(xp: int) -> int:
	return xp % XP_PER_TIER

static func reward_for_tier(tier: int, premium: bool) -> Dictionary:
	if premium:
		return {"gems": 15 if tier % 5 == 0 else 5, "coins": 75}
	return {"coins": 100 + tier * 10, "gems": 5 if tier % 5 == 0 else 0}

static func claim(profile: Dictionary, tier: int, premium_lane: bool = false) -> bool:
	if tier < 1 or tier > tier_for_xp(int(profile.get("battle_xp", 0))):
		return false
	if premium_lane and not bool(profile.get("battle_pass_premium", false)):
		return false
	var key := "%s_%d" % ["premium" if premium_lane else "free", tier]
	var claimed: Array = profile.get("claimed_pass_rewards", [])
	if key in claimed:
		return false
	var reward := reward_for_tier(tier, premium_lane)
	CurrencyManager.grant(profile, "coins", reward.get("coins", 0))
	CurrencyManager.grant(profile, "gems", reward.get("gems", 0))
	claimed.append(key)
	profile["claimed_pass_rewards"] = claimed
	return true
