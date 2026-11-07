--!strict
-- Facade: detail for building exteriors.
--   * real colours / materials from OSM (building:colour, roof:colour, building:material)
--   * panel blocks: dark plinth (цоколь), roof parapet, balcony columns with the
--     typical patchwork of glazed and open balconies, TV antennas
--   * lift machine rooms (будка ліфта) on the roof above entrances with a lift

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local Geometry = require(script.Parent.Geometry)

local M = Config.Meters
local FLOOR_H = M(2.8)

local Facade = {}

local NAMED: { [string]: Color3 } = {
	white = Color3.fromRGB(236, 236, 232), grey = Color3.fromRGB(170, 170, 168), gray = Color3.fromRGB(170, 170, 168),
	lightgrey = Color3.fromRGB(200, 200, 198), lightgray = Color3.fromRGB(200, 200, 198), darkgrey = Color3.fromRGB(110, 110, 110),
	beige = Color3.fromRGB(220, 205, 175), cream = Color3.fromRGB(240, 230, 200), yellow = Color3.fromRGB(235, 210, 120),
	orange = Color3.fromRGB(225, 150, 80), brown = Color3.fromRGB(130, 90, 60), red = Color3.fromRGB(170, 60, 50),
	pink = Color3.fromRGB(225, 170, 170), blue = Color3.fromRGB(110, 150, 200), lightblue = Color3.fromRGB(170, 200, 225),
	green = Color3.fromRGB(110, 160, 110), black = Color3.fromRGB(40, 40, 40),
}

local MATERIALS: { [string]: Enum.Material } = {
	brick = Enum.Material.Brick, panel = Enum.Material.Concrete, concrete = Enum.Material.Concrete,
	plaster = Enum.Material.Plaster, wood = Enum.Material.WoodPlanks, metal = Enum.Material.Metal,
	stone = Enum.Material.Slate, glass = Enum.Material.Glass,
}

-- "#c8b896", "#ccc", "beige", "light grey" -> Color3 (nil when unknown)
function Facade.ParseColour(value: string?): Color3?
	if not value or value == "" then
		return nil
	end
	local v = string.lower(string.gsub(value, "[%s_%-]", ""))
	local hex = string.match(v, "^#(%x+)$")
	if hex and #hex == 6 then
		return Color3.fromRGB(tonumber(string.sub(hex, 1, 2), 16) :: number, tonumber(string.sub(hex, 3, 4), 16) :: number, tonumber(string.sub(hex, 5, 6), 16) :: number)
	elseif hex and #hex == 3 then
		local r, g, b = string.sub(hex, 1, 1), string.sub(hex, 2, 2), string.sub(hex, 3, 3)
		return Color3.fromRGB(tonumber(r .. r, 16) :: number, tonumber(g .. g, 16) :: number, tonumber(b .. b, 16) :: number)
	end
	return NAMED[v]
end

function Facade.ParseMaterial(value: string?): Enum.Material?
	if not value or value == "" then
		return nil
	end
	return MATERIALS[string.lower(value)]
end

local function hash(n: number): number
	return (n * 2654435761) % 4294967296
end

local function detail(p: BasePart)
	p.CanQuery = false
	p.CastShadow = false
end

-- Panel block details on a rectangular body. base: ground-level centre, X along length L.
-- balconyFace: +1 / -1 picks the long face (local ±Z) for balconies.
function Facade.PanelBlock(parent: Instance, base: CFrame, L: number, W: number, h: number, floors: number, color: Color3, id: number, balconyFace: number)
	local cfg = Config.Map
	if cfg.RoofDetails then
		local plinth = Geometry.Part(parent, "Plinth", Vector3.new(L + 0.3, M(0.9), W + 0.3), base * CFrame.new(0, M(0.45), 0),
			color:Lerp(Color3.fromRGB(70, 66, 62), 0.55), Enum.Material.Concrete)
		detail(plinth)
		-- roof parapet
		for _, s in { -1, 1 } do
			detail(Geometry.Part(parent, "Parapet", Vector3.new(L, M(0.5), 0.5), base * CFrame.new(0, h + M(0.25), s * (W / 2 - 0.25)), color, Enum.Material.Concrete))
			detail(Geometry.Part(parent, "Parapet", Vector3.new(0.5, M(0.5), W), base * CFrame.new(s * (L / 2 - 0.25), h + M(0.25), 0), color, Enum.Material.Concrete))
		end
		-- TV antennas
		local count = 1 + hash(id) % 3
		for i = 1, count do
			local ax = (((hash(id + i * 17) % 1000) / 1000) - 0.5) * (L - 4)
			local az = (((hash(id + i * 31) % 1000) / 1000) - 0.5) * (W - 4)
			local pole = Geometry.Part(parent, "Antenna", Vector3.new(0.15, M(3), 0.15), base * CFrame.new(ax, h + M(1.5), az), Color3.fromRGB(90, 90, 92), Enum.Material.Metal)
			detail(pole)
			pole.CanCollide = false
			local bar = Geometry.Part(parent, "AntennaBar", Vector3.new(M(1.2), 0.12, 0.12), base * CFrame.new(ax, h + M(2.6), az) * CFrame.Angles(0, (hash(id + i) % 180) * math.pi / 180, 0),
				Color3.fromRGB(90, 90, 92), Enum.Material.Metal)
			detail(bar)
			bar.CanCollide = false
		end
	end

	if cfg.Balconies and floors >= 2 then
		local spacing = M(cfg.BalconySpacing)
		local columns = math.floor((L - M(2)) / spacing)
		local start = -(columns - 1) * spacing / 2
		local bw, depth = M(2.7), M(1.0)
		local zFace = balconyFace * (W / 2 + depth / 2)
		for c = 0, columns - 1 do
			local x = start + c * spacing
			for f = 2, floors do
				local y = (f - 1) * FLOOR_H
				local r = hash(id * 131 + c * 17 + f)
				local slab = Geometry.Part(parent, "Balcony", Vector3.new(bw, M(0.15), depth), base * CFrame.new(x, y + M(0.075), zFace), color, Enum.Material.Concrete)
				detail(slab)
				local glazed = (r % 1000) / 1000 < cfg.GlazedBalconyChance
				local front = balconyFace * (W / 2 + depth - 0.05)
				if glazed then
					-- owner-glazed balcony: random frame colour, glass to the ceiling
					local frames = { Color3.fromRGB(240, 240, 236), Color3.fromRGB(120, 85, 55), Color3.fromRGB(200, 200, 196) }
					detail(Geometry.Part(parent, "BalconyParapet", Vector3.new(bw, M(1.0), 0.1), base * CFrame.new(x, y + M(0.65), front),
						frames[r % #frames + 1], Enum.Material.SmoothPlastic))
					local glass = Geometry.Part(parent, "BalconyGlass", Vector3.new(bw, FLOOR_H - M(1.3), 0.08), base * CFrame.new(x, y + M(1.15) + (FLOOR_H - M(1.3)) / 2, front),
						Color3.fromRGB(150, 175, 190), Enum.Material.Glass)
					glass.Transparency = 0.35
					glass.CanCollide = false
					detail(glass)
				else
					detail(Geometry.Part(parent, "BalconyParapet", Vector3.new(bw, M(1.0), 0.15), base * CFrame.new(x, y + M(0.65), front),
						color:Lerp(Color3.fromRGB(120, 116, 110), 0.25), Enum.Material.Concrete))
				end
			end
		end
	end
end

-- Lift machine room on the roof above an entrance (entrance on the wall at `pos`,
-- outward `normal`), pulled 3 m inside the building.
function Facade.LiftRoom(parent: Instance, pos: Vector3, normal: Vector3, h: number, color: Color3)
	if not Config.Map.RoofDetails then
		return
	end
	local inside = Vector3.new(pos.X, 0, pos.Z) - normal * M(3)
	local cf = CFrame.lookAt(inside, inside + normal)
	detail(Geometry.Part(parent, "LiftMachineRoom", Vector3.new(M(3), M(2.4), M(3.5)), cf * CFrame.new(0, h + M(1.2), 0), color, Enum.Material.Concrete))
	detail(Geometry.Part(parent, "LiftRoomDoor", Vector3.new(M(0.8), M(1.8), 0.1), cf * CFrame.new(M(0.6), h + M(0.9), -M(1.75) - 0.05),
		Color3.fromRGB(90, 80, 70), Enum.Material.Metal))
end

return Facade
