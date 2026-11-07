--!strict
-- Items: every item that can sit in an inventory or a fridge.
-- Prices here are the base price; shop catalogues may override them.
-- Brands are generic on purpose (no real trademarks).

export type ItemUse = {
	Heal: number?, -- restores Humanoid health
	Message: string,
}

export type Item = {
	Id: string,
	Name: string,
	Price: number,
	Category: string,
	Color: Color3, -- icon / product colour
	Use: ItemUse?, -- nil = cannot be used directly
}

local list: { Item } = {
	-- Groceries
	{ Id = "bread", Name = "Хліб «Український»", Price = 18, Category = "Продукти", Color = Color3.fromRGB(176, 120, 60), Use = { Heal = 10, Message = "Свіжий хліб. Смачно!" } },
	{ Id = "baton", Name = "Батон нарізний", Price = 22, Category = "Продукти", Color = Color3.fromRGB(214, 170, 100), Use = { Heal = 10, Message = "Хрумкий батон." } },
	{ Id = "milk", Name = "Молоко 2,5%", Price = 34, Category = "Продукти", Color = Color3.fromRGB(240, 240, 235), Use = { Heal = 8, Message = "Холодне молоко." } },
	{ Id = "kefir", Name = "Кефір", Price = 36, Category = "Продукти", Color = Color3.fromRGB(230, 235, 245), Use = { Heal = 8, Message = "Кефір — для здоров'я." } },
	{ Id = "sausage", Name = "Ковбаса «Лікарська»", Price = 120, Category = "Продукти", Color = Color3.fromRGB(205, 120, 120), Use = { Heal = 20, Message = "Бутерброд з ковбасою." } },
	{ Id = "salo", Name = "Сало", Price = 95, Category = "Продукти", Color = Color3.fromRGB(245, 230, 220), Use = { Heal = 25, Message = "Сало з часником. Сила!" } },
	{ Id = "buckwheat", Name = "Гречка 1 кг", Price = 55, Category = "Продукти", Color = Color3.fromRGB(120, 80, 50) },
	{ Id = "oil", Name = "Олія соняшникова", Price = 70, Category = "Продукти", Color = Color3.fromRGB(240, 200, 60) },
	{ Id = "eggs", Name = "Яйця (10 шт)", Price = 60, Category = "Продукти", Color = Color3.fromRGB(240, 225, 200) },
	{ Id = "tea", Name = "Чай чорний", Price = 45, Category = "Продукти", Color = Color3.fromRGB(150, 40, 30) },
	{ Id = "candy", Name = "Цукерки «Каштан»", Price = 40, Category = "Солодощі", Color = Color3.fromRGB(110, 60, 30), Use = { Heal = 5, Message = "Шоколадна цукерка." } },
	{ Id = "icecream", Name = "Морозиво пломбір", Price = 30, Category = "Солодощі", Color = Color3.fromRGB(250, 250, 250), Use = { Heal = 5, Message = "Пломбір у вафельному стаканчику!" } },
	{ Id = "water", Name = "Вода мінеральна", Price = 20, Category = "Напої", Color = Color3.fromRGB(120, 190, 230), Use = { Heal = 5, Message = "Ковток мінералки." } },
	{ Id = "kvass", Name = "Квас", Price = 28, Category = "Напої", Color = Color3.fromRGB(130, 70, 20), Use = { Heal = 6, Message = "Холодний квас." } },
	{ Id = "juice", Name = "Сік яблучний", Price = 42, Category = "Напої", Color = Color3.fromRGB(230, 170, 40), Use = { Heal = 6, Message = "Яблучний сік." } },
	-- Household
	{ Id = "bulb", Name = "Лампочка 60 Вт", Price = 25, Category = "Господарські", Color = Color3.fromRGB(255, 240, 180) },
	{ Id = "soap", Name = "Мило господарське", Price = 15, Category = "Господарські", Color = Color3.fromRGB(150, 100, 50) },
	{ Id = "matches", Name = "Сірники", Price = 5, Category = "Господарські", Color = Color3.fromRGB(200, 60, 40) },
	-- Pharmacy
	{ Id = "bandage", Name = "Бинт", Price = 25, Category = "Аптека", Color = Color3.fromRGB(245, 245, 245), Use = { Heal = 35, Message = "Перев'язали рану." } },
	{ Id = "valerian", Name = "Валеріанка", Price = 30, Category = "Аптека", Color = Color3.fromRGB(150, 100, 60), Use = { Heal = 10, Message = "Заспокоїлися." } },
	{ Id = "vitamins", Name = "Вітаміни", Price = 80, Category = "Аптека", Color = Color3.fromRGB(255, 150, 40), Use = { Heal = 15, Message = "Вітамінка!" } },
}

local Items: { [string]: Item } = {}
for _, item in list do
	Items[item.Id] = item
end

return Items
