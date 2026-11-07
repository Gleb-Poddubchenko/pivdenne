--!strict
-- AddressService: real-address lookup for the phone. The index is built from
-- the OSM map data (addr:street + addr:housenumber), so it only knows addresses
-- that exist in OpenStreetMap.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local TextUtil = require(Shared:WaitForChild("TextUtil"))

local MapData = require(script.Parent.Parent.City.MapData)
local Height = require(script.Parent.Parent.City.Height)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

type Entry = { Position: Vector3, Label: string }

local AddressService = {}

local byStreet: { [string]: { [string]: Entry } } = {} -- normStreet -> normNumber -> entry
local displayStreet: { [string]: string } = {} -- normStreet -> full OSM name
local streets: { string } = {}
local built = false
local limiter = RateLimiter.new(5, 1)

local function build()
	if built then
		return
	end
	built = true
	for _, chunk in MapData.Chunks() do
		for _, b in chunk.b do
			if b.st and b.hn then
				local key = TextUtil.NormalizeStreet(b.st)
				byStreet[key] = byStreet[key] or {}
				displayStreet[key] = b.st
				-- Prefer the plate position (on the street side), else the first corner.
				local x, z = b.p[1], b.p[2]
				if b.pl and b.pl[1] then
					x, z = b.pl[1][1] + b.pl[1][3] * 4, b.pl[1][2] + b.pl[1][4] * 4
				end
				byStreet[key][TextUtil.NormalizeNumber(b.hn)] = {
					Position = Vector3.new(x, Height.Ground(x, z) + 3, z),
					Label = ("%s, %s"):format(b.sa or b.st, b.hn),
				}
			end
		end
	end
	for _, name in displayStreet do
		table.insert(streets, name)
	end
	table.sort(streets)
end

function AddressService.Find(street: string, number: string): (Entry?, string?)
	build()
	local key = TextUtil.NormalizeStreet(street)
	if key == "" then
		return nil, "Введіть вулицю"
	end
	local houses = byStreet[key]
	if not houses then
		-- unique partial match ("хім" -> "хіміків")
		local match: string? = nil
		for k in byStreet do
			if string.find(k, key, 1, true) then
				if match then
					return nil, "Уточніть назву вулиці"
				end
				match = k
			end
		end
		houses = if match then byStreet[match] else nil
	end
	if not houses then
		return nil, "Такої вулиці немає в даних карти"
	end
	local entry = houses[TextUtil.NormalizeNumber(number)]
	if not entry then
		return nil, "Такого номера будинку немає в даних карти"
	end
	return entry, nil
end

function AddressService.Init()
	Net.Function("GetStreets").OnServerInvoke = function(_player: Player)
		build()
		return streets
	end
	Net.Function("FindAddress").OnServerInvoke = function(player: Player, street: any, number: any)
		if not limiter.Check(player) or typeof(street) ~= "string" or typeof(number) ~= "string"
			or #street > 120 or #number > 16
		then
			return false, "Невірний запит"
		end
		local entry, err = AddressService.Find(street, number)
		if not entry then
			return false, err
		end
		return true, entry.Position, entry.Label
	end
end

return AddressService
