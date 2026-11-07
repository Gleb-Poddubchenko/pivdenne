--!strict
-- ShopCatalogs: what each kind of shop sells. A Shop model points to one of these
-- with its "Catalog" attribute. Price = nil uses the item's base price.
-- The server always prices from here, never from the client.

export type Entry = { ItemId: string, Price: number? }

local ShopCatalogs: { [string]: { Entry } } = {
	Grocery = {
		{ ItemId = "bread" },
		{ ItemId = "baton" },
		{ ItemId = "milk" },
		{ ItemId = "kefir" },
		{ ItemId = "eggs" },
		{ ItemId = "sausage" },
		{ ItemId = "salo" },
		{ ItemId = "buckwheat" },
		{ ItemId = "oil" },
		{ ItemId = "tea" },
		{ ItemId = "candy" },
		{ ItemId = "water" },
		{ ItemId = "juice" },
		{ ItemId = "bulb" },
		{ ItemId = "soap" },
		{ ItemId = "matches" },
	},
	-- Street kiosk: fewer items, slightly dearer.
	Kiosk = {
		{ ItemId = "icecream" },
		{ ItemId = "water", Price = 25 },
		{ ItemId = "kvass", Price = 32 },
		{ ItemId = "candy", Price = 45 },
		{ ItemId = "matches", Price = 7 },
	},
	Pharmacy = {
		{ ItemId = "bandage" },
		{ ItemId = "valerian" },
		{ ItemId = "vitamins" },
		{ ItemId = "water" },
	},
}

return ShopCatalogs
