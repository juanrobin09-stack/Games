class_name LootRarity
extends RefCounted
## Central rarity scale for the loot/upgrades system (items, chest classes,
## loot tables) — one place so no id/label/color/order gets duplicated
## across scripts. Named LootRarity rather than the shorter "Rarity" (my
## first attempt) specifically to avoid colliding with the unrelated,
## pre-existing UpgradeDefinition.Rarity enum: both are global identifiers
## once class_name registers this class, so unqualified "Rarity" inside
## upgrade_definition.gd's own @export var rarity: Rarity = Rarity.COMMON
## started resolving to THIS class instead of its own nested enum the
## moment that file was added, breaking every script that already
## depended on it — caught immediately by a real import-error run, not
## assumed.
##
## Deliberately a SEPARATE scale from UpgradeDefinition.Rarity
## (COMMON..LEGENDARY): that enum already drives real gameplay logic today
## (shop pricing, UpgradePool weighting, the existing 5-tier chest-room
## system) across 28 authored upgrades — remapping its 5 values onto a
## 7-tier letter scale would touch every one of them for no gameplay
## reason. from_upgrade_rarity() below bridges the two for display instead,
## so an existing upgrade still reads a sensible letter grade without
## migrating any authored data.
##
## Tier is ordered low -> high on purpose: comparisons (a >= b) and sorted
## UI listings both fall out of the enum's own ordinal for free.

enum Tier { E, D, C, B, A, S, SS }

const ORDER: Array[Tier] = [Tier.E, Tier.D, Tier.C, Tier.B, Tier.A, Tier.S, Tier.SS]

const LABELS := {
	Tier.E: "E", Tier.D: "D", Tier.C: "C", Tier.B: "B",
	Tier.A: "A", Tier.S: "S", Tier.SS: "SS",
}

static func label(tier: Tier) -> String:
	return LABELS.get(tier, "?")

## String -> Tier, for data-driven fields authored as plain text (e.g. a
## LootEntryDefinition's ref_id lookups elsewhere never need this, but a
## human editing .tres files by hand benefits from a forgiving parser).
static func from_label(text: String) -> Tier:
	var upper := text.strip_edges().to_upper()
	for t in ORDER:
		if LABELS[t] == upper:
			return t
	return Tier.C

## Bridges the existing upgrade rarity scale to this one for DISPLAY only —
## see the class comment. Every upgrade gets a sensible new-scale label for
## free, with zero changes to the 28 existing .tres entries or to the
## shop/pool logic that reads UpgradeDefinition.rarity directly.
static func from_upgrade_rarity(old: UpgradeDefinition.Rarity) -> Tier:
	match old:
		UpgradeDefinition.Rarity.COMMON: return Tier.D
		UpgradeDefinition.Rarity.UNCOMMON: return Tier.C
		UpgradeDefinition.Rarity.RARE: return Tier.B
		UpgradeDefinition.Rarity.EPIC: return Tier.A
		UpgradeDefinition.Rarity.LEGENDARY: return Tier.S
		_: return Tier.C
