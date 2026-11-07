--!strict
-- EntrancePlanner: decides, for one OSM building, which entrances become working
-- game entrances and which flats each one serves.
--
-- Flat numbers come from OSM addr:flats when tagged (e.g. "1-36"). When they are
-- missing they are ESTIMATED (entrances in ref order, Config.Entrances.
-- DefaultFlatsPerFloor per floor) and the entrance is marked FlatsSource =
-- "estimated", so it can be corrected once real data or photos exist.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local M = Config.Meters

export type Plan = {
	Id: string,
	X: number,
	Z: number,
	NX: number,
	NZ: number,
	Ref: string,
	FlatsText: string, -- raw OSM addr:flats ("" if none)
	AptFrom: number,
	AptTo: number,
	FlatsSource: string, -- "osm" | "estimated"
	Floors: number,
	PerFloor: number,
	HasLift: boolean,
	HasChute: boolean,
	Brand: string,
}

local EntrancePlanner = {}

local function hash(s: string): number
	local h = 0
	for i = 1, #s do
		h = (h * 31 + string.byte(s, i)) % 2147483647
	end
	return h
end

-- "1-36" / "1–36" / "37-72;80" / "1,2,3" -> min, max (nil if nothing sensible)
local function parseFlats(text: string): (number?, number?)
	local lo, hi = math.huge, -math.huge
	for digits in string.gmatch(text, "%d+") do
		local n = tonumber(digits) :: number
		lo = math.min(lo, n)
		hi = math.max(hi, n)
	end
	if lo == math.huge or hi - lo > 600 then
		return nil, nil
	end
	return lo, hi
end

local function isApartmentBlock(t: string): boolean
	return string.sub(t, 1, 5) == "panel"
end

-- Returns a list aligned with b.en: a Plan, or false for decorative-only entrances.
function EntrancePlanner.Plan(b: any): { Plan | boolean }
	local result: { Plan | boolean } = {}
	local entrances = b.en or {}
	if not Config.Entrances.Functional or not isApartmentBlock(b.t) then
		for i = 1, #entrances do
			result[i] = false
		end
		return result
	end

	local floors = if b.lv and b.lv > 0 then b.lv else math.floor((b.h - M(0.6)) / M(2.8) + 0.5)
	floors = math.clamp(floors, 1, 30)

	-- Order entrances by ref number, then by position along the building.
	local order = {}
	for i = 1, #entrances do
		table.insert(order, i)
	end
	table.sort(order, function(a, c)
		local ra, rc = tonumber(entrances[a].ref), tonumber(entrances[c].ref)
		if ra and rc and ra ~= rc then
			return ra < rc
		end
		local ea, ec = entrances[a], entrances[c]
		if math.abs(ea.x - ec.x) > 1 then
			return ea.x < ec.x
		end
		return ea.z < ec.z
	end)

	local perDefault = Config.Entrances.DefaultFlatsPerFloor
	local nextFree = 1
	local usedIds: { [string]: boolean } = {}
	for rank, i in order do
		local e = entrances[i]
		local from, to = parseFlats(e.flats or "")
		local source = "osm"
		if not from or not to then
			from = nextFree
			to = nextFree + floors * perDefault - 1
			source = "estimated"
		end
		nextFree = math.max(nextFree, (to :: number) + 1)
		local count = (to :: number) - (from :: number) + 1
		local perFloor = math.clamp(math.ceil(count / floors), 1, 6)

		local ref = if e.ref ~= "" then e.ref else tostring(rank)
		local id = ("osm%d/%s"):format(b.id, ref)
		if usedIds[id] then
			id ..= "-" .. rank
		end
		usedIds[id] = true

		result[i] = {
			Id = id,
			X = e.x,
			Z = e.z,
			NX = e.nx or 0,
			NZ = e.nz or 0,
			Ref = e.ref or "",
			FlatsText = e.flats or "",
			AptFrom = from :: number,
			AptTo = to :: number,
			FlatsSource = source,
			Floors = floors,
			PerFloor = perFloor,
			HasLift = floors >= Config.Entrances.LiftMinFloors,
			HasChute = floors >= Config.Entrances.ChuteMinFloors,
			Brand = Config.Entrances.BrandOverrides[id] or (if hash(id) % 2 == 0 then "Vizor" else "Metron"),
		}
	end
	return result
end

return EntrancePlanner
