--!strict
-- Equipment: things you own permanently and choose to carry (the loadout).
-- Tools appear in the Roblox hotbar; "Passive" items work just by being carried.

export type EquipmentDef = {
	Id: string,
	Name: string,
	Description: string,
	Price: number,
	Kind: string, -- "Tool" | "Passive"
}

local list: { EquipmentDef } = {
	{ Id = "phone", Name = "Мобільний телефон", Description = "Годинник, гроші та пошук адреси по всьому місту.", Price = 150, Kind = "Tool" },
	{ Id = "flashlight", Name = "Ліхтарик", Description = "Для темних під'їздів, коли лампочку знову викрутили.", Price = 60, Kind = "Tool" },
	{ Id = "umbrella", Name = "Парасолька", Description = "Розкрити / скласти.", Price = 40, Kind = "Tool" },
	{ Id = "fishingrod", Name = "Вудка", Description = "Ловіть бичків біля води й продавайте на ринку.", Price = 120, Kind = "Tool" },
	{ Id = "backpack", Name = "Рюкзак", Description = "+15 видів речей і +10 у кожній купці в інвентарі.", Price = 200, Kind = "Passive" },
}

local Defs: { [string]: EquipmentDef } = {}
local order: { string } = {}
for _, def in list do
	Defs[def.Id] = def
	table.insert(order, def.Id)
end

return {
	Defs = Defs,
	Order = order,
}
