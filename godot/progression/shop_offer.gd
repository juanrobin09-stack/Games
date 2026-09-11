class_name ShopOffer
extends RefCounted
## Ports world/Shop.ts's ShopOffer interface — one purchasable row in a
## ShopUI listing (build-order step 9's UI pass still owns actually
## displaying these; Shop.generate_shop_offers() just produces the data).

enum Kind { UPGRADE, HEAL }

var id: String = ""
var kind: Kind = Kind.UPGRADE
## Only set when kind == UPGRADE.
var upgrade: UpgradeDefinition = null
## The level the upgrade would become if bought (current stacks + 1). Only
## set when kind == UPGRADE.
var upgrade_level: int = 0
var cost: int = 0
var purchased: bool = false
