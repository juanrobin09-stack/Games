class_name Shop
extends RefCounted
## Ports world/Shop.ts. All-static, like UpgradePool next to it — grouped
## under godot/progression/ rather than godot/world/ for the same "one
## cohesive domain" reason UpgradePool.gd's own header explains.

## A static func with a match, not a top-level const Dictionary keyed by
## UpgradeDefinition.Rarity — this project avoids top-level consts that
## evaluate another script's enum member at load time (a const's value must
## resolve before load order can guarantee UpgradeDefinition is ready); a
## match inside a function body only runs when called, well after every
## script is loaded, same proven-safe pattern as Palette.rarity_color().
static func _price_for_rarity(rarity: UpgradeDefinition.Rarity) -> int:
	match rarity:
		UpgradeDefinition.Rarity.COMMON: return 22
		UpgradeDefinition.Rarity.UNCOMMON: return 38
		UpgradeDefinition.Rarity.RARE: return 58
		UpgradeDefinition.Rarity.EPIC: return 88
		UpgradeDefinition.Rarity.LEGENDARY: return 145
		_: return 22

const REROLL_COST := 15
const HEAL_COST := 30
const HEAL_AMOUNT_RATIO := 0.35

static func generate_shop_offers(rng: RandomNumberGenerator, luck: float, unlocked_tiers: Dictionary, owned: Array[OwnedUpgrade], zone_index: int) -> Array[ShopOffer]:
	var upgrades := UpgradePool.roll_upgrade_choices(rng, 3, luck * 0.7, unlocked_tiers, owned, zone_index)
	var offers: Array[ShopOffer] = []
	for i in range(upgrades.size()):
		var u := upgrades[i]
		var offer := ShopOffer.new()
		offer.id = "upg-%d" % i
		offer.kind = ShopOffer.Kind.UPGRADE
		offer.upgrade = u
		offer.upgrade_level = UpgradePool.upcoming_upgrade_level(u.id, owned)
		offer.cost = _price_for_rarity(u.rarity)
		offers.append(offer)
	var heal_offer := ShopOffer.new()
	heal_offer.id = "heal"
	heal_offer.kind = ShopOffer.Kind.HEAL
	heal_offer.cost = HEAL_COST
	offers.append(heal_offer)
	return offers

static func make_shop_rng(run_seed: String, room_key: String, reroll_count: int) -> RandomNumberGenerator:
	return LevelGenerator.rng_from("%s:shop:%s:%d" % [run_seed, room_key, reroll_count])
