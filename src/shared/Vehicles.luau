--!strict
-- Vehicles: car models sold at the dealership and the factory paint colours.
-- Names are generic and fictional, but the cars are styled after the Soviet and
-- Ukrainian classics you still see in Yuzhne's courtyards.

export type CarModel = {
	Id: string,
	Name: string,
	Description: string,
	Price: number,
	Length: number, -- metres
	Width: number,
	Height: number,
	CabinStart: number, -- glasshouse span, as fractions of length from the front
	CabinEnd: number,
	TopSpeed: number, -- m/s
	Acceleration: number, -- m/s²
	Drive: string, -- "FWD" | "RWD" | "AWD"
	Seats: number,
}

export type PaintColor = { Name: string, Color: Color3 }

local list: { CarModel } = {
	{
		Id = "lastivka",
		Name = "«Ластівка»",
		Description = "Маленька передньопривідна. Дешева, жвава, тісна.",
		Price = 400,
		Length = 3.7, Width = 1.55, Height = 1.4,
		CabinStart = 0.30, CabinEnd = 0.86,
		TopSpeed = 22, Acceleration = 2.6, Drive = "FWD", Seats = 4,
	},
	{
		Id = "klasyka",
		Name = "«Класика»",
		Description = "Задньопривідний седан. Вічна класика двору.",
		Price = 1500,
		Length = 4.1, Width = 1.62, Height = 1.45,
		CabinStart = 0.33, CabinEnd = 0.72,
		TopSpeed = 27, Acceleration = 3.0, Drive = "RWD", Seats = 5,
	},
	{
		Id = "mandrivnyk",
		Name = "«Мандрівник»",
		Description = "Універсал: на дачу, на базар, на море.",
		Price = 2500,
		Length = 4.2, Width = 1.65, Height = 1.5,
		CabinStart = 0.30, CabinEnd = 0.95,
		TopSpeed = 26, Acceleration = 2.8, Drive = "RWD", Seats = 5,
	},
	{
		Id = "bukhanka",
		Name = "«Буханка»",
		Description = "Повнопривідний мікроавтобус. Повільний, але проїде всюди.",
		Price = 4000,
		Length = 4.4, Width = 1.95, Height = 2.0,
		CabinStart = 0.05, CabinEnd = 0.98,
		TopSpeed = 22, Acceleration = 2.2, Drive = "AWD", Seats = 6,
	},
}

local Models: { [string]: CarModel } = {}
local order: { string } = {}
for _, model in list do
	Models[model.Id] = model
	table.insert(order, model.Id)
end

-- Classic Soviet-era factory paint names.
local Colors: { PaintColor } = {
	{ Name = "Білий", Color = Color3.fromRGB(235, 235, 228) },
	{ Name = "Вишня", Color = Color3.fromRGB(120, 20, 35) },
	{ Name = "Баклажан", Color = Color3.fromRGB(60, 30, 60) },
	{ Name = "Коррида", Color = Color3.fromRGB(200, 40, 30) },
	{ Name = "Сафарі", Color = Color3.fromRGB(205, 180, 130) },
	{ Name = "Морська хвиля", Color = Color3.fromRGB(30, 120, 130) },
	{ Name = "Валюта", Color = Color3.fromRGB(90, 120, 90) },
	{ Name = "Сріблястий", Color = Color3.fromRGB(170, 175, 180) },
}

return {
	Models = Models,
	Order = order, -- display order at the dealership
	Colors = Colors,
}
