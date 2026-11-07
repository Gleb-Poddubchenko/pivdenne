--!strict
-- TestShopBuilder (DEV ONLY): an enterable grocery shop (продуктовий) behind the
-- spawn, plus an ice-cream/drinks kiosk and a pharmacy kiosk.
-- Shop names are generic/fictional on purpose (no real chains).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Items = require(Shared:WaitForChild("Items"))
local ShopCatalogs = require(Shared:WaitForChild("ShopCatalogs"))

local M = Config.Meters

local TestShopBuilder = {}

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, props: { [string]: any }?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Material = Enum.Material.SmoothPlastic
	p.Color = Color3.fromRGB(225, 220, 205)
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props then
		for k, v in props do
			(p :: any)[k] = v
		end
	end
	p.Parent = parent
	return p
end

local function sign(target: BasePart, text: string, fg: Color3, bg: Color3)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0.2
	gui.Parent = target
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = bg
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = fg
	label.Text = text
	label.Parent = gui
end

-- Simple shop assistant made of parts (not a rig; purely decorative).
local function shopAssistant(parent: Instance, cf: CFrame, title: string)
	local npc = Instance.new("Model")
	npc.Name = "ShopAssistant"
	local skin = Color3.fromRGB(234, 190, 160)
	part(npc, "Legs", Vector3.new(2, 2, 1), cf * CFrame.new(0, 1, 0), { Color = Color3.fromRGB(50, 50, 70) })
	part(npc, "Torso", Vector3.new(2, 2, 1), cf * CFrame.new(0, 3, 0), { Color = Color3.fromRGB(235, 235, 240) }) -- white coat
	part(npc, "ArmL", Vector3.new(1, 2, 1), cf * CFrame.new(-1.5, 3, 0), { Color = Color3.fromRGB(235, 235, 240) })
	part(npc, "ArmR", Vector3.new(1, 2, 1), cf * CFrame.new(1.5, 3, 0), { Color = Color3.fromRGB(235, 235, 240) })
	local head = part(npc, "Head", Vector3.new(1.2, 1.2, 1.2), cf * CFrame.new(0, 4.6, 0), { Color = skin })
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(140, 30)
	bb.StudsOffset = Vector3.new(0, 1.6, 0)
	bb.MaxDistance = 40
	bb.Parent = head
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Text = title
	label.Parent = bb
	npc.Parent = parent
end

local function productColors(catalog: string): { Color3 }
	local colors = {}
	for _, entry in ShopCatalogs[catalog] do
		local item = Items[entry.ItemId]
		if item then
			table.insert(colors, item.Color)
		end
	end
	return colors
end

local function buildGrocery(parent: Instance)
	-- Front wall faces the spawn (+Z). Local +Z = into the shop.
	local origin = Vector3.new(0, 0, -50)
	local cf = CFrame.lookAt(origin, origin + Vector3.new(0, 0, 1))
	local W, D, H, T = M(12), M(8), M(3.4), 0.8
	local shop = Instance.new("Model")
	shop.Name = "Shop_test-grocery"
	shop:SetAttribute("ShopId", "test-grocery")
	shop:SetAttribute("Catalog", "Grocery")
	shop:SetAttribute("DisplayName", "Продукти «Каштан»")

	local wallColor = { Material = Enum.Material.Brick, Color = Color3.fromRGB(200, 190, 170) }
	local doorW, doorH = M(1.8), M(2.3)
	local winW, winBottom, winTop = M(3.0), M(0.8), M(2.6)
	-- Front wall pieces: [wall][window][wall][door][wall][window][wall]
	local xs = { -W / 2, -W / 2 + M(0.6), -W / 2 + M(0.6) + winW, -doorW / 2, doorW / 2, W / 2 - M(0.6) - winW, W / 2 - M(0.6), W / 2 }
	local function front(a: number, b: number, y0: number, y1: number, props: { [string]: any }?)
		if b - a > 0.01 and y1 - y0 > 0.01 then
			part(shop, "Front", Vector3.new(b - a, y1 - y0, T), cf * CFrame.new((a + b) / 2, (y0 + y1) / 2, T / 2), props or wallColor)
		end
	end
	front(xs[1], xs[2], 0, H)
	front(xs[2], xs[3], 0, winBottom)
	front(xs[2], xs[3], winTop, H)
	front(xs[3], xs[4], 0, H)
	front(xs[4], xs[5], doorH, H)
	front(xs[5], xs[6], 0, H)
	front(xs[6], xs[7], 0, winBottom)
	front(xs[6], xs[7], winTop, H)
	front(xs[7], xs[8], 0, H)
	local glass = { Material = Enum.Material.Glass, Transparency = 0.6, Color = Color3.fromRGB(180, 215, 230) }
	front(xs[2], xs[3], winBottom, winTop, glass)
	front(xs[6], xs[7], winBottom, winTop, glass)

	part(shop, "WallL", Vector3.new(T, H, D), cf * CFrame.new(-W / 2 + T / 2, H / 2, D / 2), wallColor)
	part(shop, "WallR", Vector3.new(T, H, D), cf * CFrame.new(W / 2 - T / 2, H / 2, D / 2), wallColor)
	part(shop, "WallBack", Vector3.new(W, H, T), cf * CFrame.new(0, H / 2, D - T / 2), wallColor)
	part(shop, "Roof", Vector3.new(W + 1, 0.8, D + 1), cf * CFrame.new(0, H + 0.4, D / 2), { Material = Enum.Material.Concrete, Color = Color3.fromRGB(140, 140, 135) })
	part(shop, "Floor", Vector3.new(W - 2 * T, 0.3, D - T), cf * CFrame.new(0, 0.15, D / 2), {
		Material = Enum.Material.CeramicTiles,
		Color = Color3.fromRGB(210, 205, 190),
	})
	local board = part(shop, "Sign", Vector3.new(W * 0.7, M(0.8), 0.3), cf * CFrame.new(0, H - M(0.45), -0.15), {})
	sign(board, "ПРОДУКТИ «КАШТАН»", Color3.new(1, 1, 1), Color3.fromRGB(30, 80, 150))

	-- Ceiling lights
	for _, x in { -W / 4, W / 4 } do
		local tube = part(shop, "Light", Vector3.new(M(1.2), 0.2, 0.4), cf * CFrame.new(x, H - 0.2, D / 2), {
			Material = Enum.Material.Neon,
			Color = Color3.fromRGB(240, 245, 255),
			CanCollide = false,
		})
		local light = Instance.new("PointLight")
		light.Range = 24
		light.Brightness = 0.9
		light.Parent = tube
	end

	-- Shelves with product boxes along both side walls
	local colors = productColors("Grocery")
	local n = 0
	for _, side in { -1, 1 } do
		local sx = side * (W / 2 - T - M(0.25))
		part(shop, "ShelfUnit", Vector3.new(M(0.5), M(1.9), M(4.5)), cf * CFrame.new(sx, M(0.95) + 0.3, D / 2 - M(0.5)), {
			Material = Enum.Material.Metal,
			Color = Color3.fromRGB(150, 155, 160),
		})
		for level = 0, 2 do
			for k = 0, 6 do
				n += 1
				part(shop, "Product", Vector3.new(0.7, 1.0, 0.9), cf * CFrame.new(sx - side * M(0.32), 0.3 + M(0.4) + level * M(0.6), D / 2 - M(2.5) + k * M(0.6)), {
					Color = colors[(n - 1) % #colors + 1],
					CanCollide = false,
				})
			end
		end
	end
	-- Fridge display along the back wall (dairy)
	part(shop, "FridgeDisplay", Vector3.new(M(4), M(1.8), M(0.7)), cf * CFrame.new(-M(2.5), M(0.9) + 0.3, D - T - M(0.4)), {
		Color = Color3.fromRGB(235, 240, 245),
	})
	part(shop, "FridgeGlass", Vector3.new(M(3.8), M(1.4), 0.1), cf * CFrame.new(-M(2.5), M(1.0) + 0.3, D - T - M(0.77)), glass)

	-- Counter + till (the Shop contract's "Till")
	local counter = part(shop, "Counter", Vector3.new(M(3), M(1.0), M(0.7)), cf * CFrame.new(M(2.8), M(0.5) + 0.3, D - M(2.6)), {
		Material = Enum.Material.Wood,
		Color = Color3.fromRGB(110, 75, 45),
	})
	part(shop, "Till", Vector3.new(M(0.45), M(0.3), M(0.4)), counter.CFrame * CFrame.new(-M(0.8), M(0.65), 0), {
		Color = Color3.fromRGB(50, 50, 55),
	})
	shopAssistant(shop, cf * CFrame.new(M(2.8), 0.3, D - M(1.7)) * CFrame.Angles(0, math.pi, 0), "Продавчиня")

	shop.Parent = parent
	CollectionService:AddTag(shop, "Shop")
end

local function buildKiosk(parent: Instance, position: Vector3, facing: Vector3, id: string, catalog: string, name: string, signText: string, color: Color3)
	local cf = CFrame.lookAt(position, position + facing)
	local kiosk = Instance.new("Model")
	kiosk.Name = "Shop_" .. id
	kiosk:SetAttribute("ShopId", id)
	kiosk:SetAttribute("Catalog", catalog)
	kiosk:SetAttribute("DisplayName", name)
	local size = M(2.4)
	part(kiosk, "Body", Vector3.new(size, M(2.6), size), cf * CFrame.new(0, M(1.3), size / 2), { Color = color })
	part(kiosk, "Window", Vector3.new(size * 0.7, M(0.9), 0.1), cf * CFrame.new(0, M(1.5), -0.05), {
		Material = Enum.Material.Glass,
		Transparency = 0.4,
		Color = Color3.fromRGB(200, 220, 230),
	})
	part(kiosk, "Ledge", Vector3.new(size * 0.8, 0.3, M(0.4)), cf * CFrame.new(0, M(1.0), -M(0.2)), { Color = Color3.fromRGB(90, 90, 90) })
	part(kiosk, "Till", Vector3.new(M(0.35), M(0.2), M(0.3)), cf * CFrame.new(size * 0.25, M(1.0) + 0.5, -M(0.2)), { Color = Color3.fromRGB(50, 50, 55) })
	local board = part(kiosk, "Sign", Vector3.new(size, M(0.5), 0.2), cf * CFrame.new(0, M(2.35), -0.15), {})
	sign(board, signText, Color3.new(1, 1, 1), color)
	kiosk.Parent = parent
	CollectionService:AddTag(kiosk, "Shop")
end

function TestShopBuilder.Build()
	if workspace:FindFirstChild("TestShops") then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "TestShops"
	buildGrocery(folder)
	buildKiosk(folder, Vector3.new(-45, 0, -30), Vector3.new(0, 0, 1), "test-kiosk", "Kiosk", "Кіоск «Пломбір»", "МОРОЗИВО · НАПОЇ", Color3.fromRGB(200, 60, 50))
	buildKiosk(folder, Vector3.new(45, 0, -30), Vector3.new(0, 0, 1), "test-pharmacy", "Pharmacy", "Аптека «Ромашка»", "✚ АПТЕКА", Color3.fromRGB(40, 150, 80))
	folder.Parent = workspace
end

return TestShopBuilder
