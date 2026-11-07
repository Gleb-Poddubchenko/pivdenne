--!strict
-- StairwellService: makes city entrances enterable.
--
-- City entrances (EntranceBuilder, attribute Instanced = true) are real Entrance
-- models: intercom, key reader and the heavy door all work through the normal
-- IntercomService / DoorService. When the door is open, stepping into its
-- "Doorway" trigger takes the player into that entrance's stairwell, built on
-- demand in a pocket slot (like flat interiors) and removed when nobody is in it,
-- in its lift, or in one of its flats.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local EntranceRegistry = require(script.Parent.EntranceRegistry)
local DoorService = require(script.Parent.DoorService)
local InteriorService = require(script.Parent.InteriorService)
local StairwellBuilder = require(script.Parent.Parent.Building.StairwellBuilder)
local Teleport = require(script.Parent.Parent.Util.Teleport)
local Validation = require(script.Parent.Parent.Util.Validation)

type Entrance = EntranceRegistry.Entrance
type Instance_ = {
	EntranceId: string,
	Built: StairwellBuilder.Built,
	Slot: number,
	EmptySince: number?,
}

local StairwellService = {}

local entrances: { [string]: { Entrance: Entrance, Doorway: BasePart } } = {}
local instances: { [string]: Instance_ } = {}
local usedSlots: { [number]: boolean } = {}
local busy: { [Player]: boolean } = {}
local cooldownUntil: { [Player]: number } = {}
local folder: Folder

local function slotBase(slot: number): CFrame
	local cfg = Config.Stairwells
	local col = slot % cfg.SlotsPerRow
	local row = slot // cfg.SlotsPerRow
	return CFrame.new(cfg.Origin + Vector3.new(col * cfg.Spacing, 0, row * cfg.Spacing))
end

local function inBox(cf: CFrame, size: Vector3, position: Vector3): boolean
	local p = cf:PointToObjectSpace(position)
	return math.abs(p.X) <= size.X / 2 and math.abs(p.Y) <= size.Y / 2 and math.abs(p.Z) <= size.Z / 2
end

local function outsideCFrame(doorway: BasePart): CFrame
	-- Doorway's LookVector points out of the building; stand beyond the trigger.
	local pos = (doorway.CFrame * CFrame.new(0, 0, -Config.Meters(2.0))).Position
	return CFrame.lookAt(pos, pos + doorway.CFrame.LookVector)
end

local function leave(player: Player, entranceId: string)
	if busy[player] then
		return
	end
	local info = entrances[entranceId]
	if not info then
		player:LoadCharacter()
		return
	end
	busy[player] = true
	DoorService.Unlock(entranceId, "exit") -- the street door swings open as you come out
	cooldownUntil[player] = os.clock() + Config.Stairwells.ReenterCooldown
	Teleport.To(player, outsideCFrame(info.Doorway))
	busy[player] = nil
end

local function getOrCreate(info: { Entrance: Entrance, Doorway: BasePart }): Instance_
	local id = info.Entrance.Id
	local existing = instances[id]
	if existing then
		existing.EmptySince = nil
		return existing
	end
	local slot = 0
	while usedSlots[slot] do
		slot += 1
	end
	usedSlots[slot] = true
	local m = info.Entrance.Model
	local function num(name: string, default: number): number
		local v = m:GetAttribute(name)
		return if typeof(v) == "number" then v else default
	end
	local built = StairwellBuilder.Build(folder, slotBase(slot), {
		EntranceId = id,
		Floors = num("Floors", 5),
		AptFrom = info.Entrance.AptFrom,
		AptTo = info.Entrance.AptTo,
		PerFloor = num("PerFloor", Config.Entrances.DefaultFlatsPerFloor),
		HasLift = m:GetAttribute("HasLift") == true,
		HasChute = m:GetAttribute("HasChute") == true,
	}, function(player: Player)
		task.spawn(leave, player, id)
	end)
	local inst: Instance_ = { EntranceId = id, Built = built, Slot = slot, EmptySince = nil }
	instances[id] = inst
	return inst
end

local function enter(player: Player, entranceId: string)
	if busy[player] or (cooldownUntil[player] or 0) > os.clock() then
		return
	end
	local info = entrances[entranceId]
	if not info then
		return
	end
	busy[player] = true
	local inst = getOrCreate(info)
	Teleport.To(player, inst.Built.EntryCFrame)
	busy[player] = nil
end

local function register(entrance: Entrance)
	if entrance.Model:GetAttribute("Instanced") ~= true then
		return -- hand-built entrances (test scene) have real lobbies
	end
	local doorway = entrance.Model:FindFirstChild("Doorway")
	if not (doorway and doorway:IsA("BasePart")) then
		warn("[Stairwell] Instanced entrance without Doorway:", entrance.Model:GetFullName())
		return
	end
	entrances[entrance.Id] = { Entrance = entrance, Doorway = doorway }
	doorway.Touched:Connect(function(hit: BasePart)
		local character = hit.Parent
		local player = character and Players:GetPlayerFromCharacter(character)
		if not player or hit.Name ~= "HumanoidRootPart" then
			return
		end
		local state = DoorService.GetState(entrance.Id)
		if state == "Opening" or state == "Open" then
			task.spawn(enter, player, entrance.Id)
		end
	end)
end

function StairwellService.Init()
	folder = Instance.new("Folder")
	folder.Name = "Stairwells"
	folder.Parent = workspace

	for _, entrance in EntranceRegistry.All() do
		register(entrance)
	end
	EntranceRegistry.EntranceAdded:Connect(register)

	Players.PlayerRemoving:Connect(function(player)
		busy[player] = nil
		cooldownUntil[player] = nil
	end)

	-- Every 10 s: remove stairwells nobody uses (counting players in its flats).
	task.spawn(function()
		while true do
			task.wait(10)
			local now = os.clock()
			for id, inst in instances do
				local used = false
				for _, player in Players:GetPlayers() do
					local root = Validation.GetRoot(player)
					if root and inBox(inst.Built.BoxCFrame, inst.Built.BoxSize, root.Position) then
						used = true
						break
					end
					local flat = InteriorService.GetLocation(player)
					if flat and string.sub(flat, 1, #id + 1) == id .. "#" then
						used = true
						break
					end
				end
				if used then
					inst.EmptySince = nil
				else
					inst.EmptySince = inst.EmptySince or now
					if now - (inst.EmptySince :: number) > Config.Stairwells.EmptyLifetime then
						inst.Built.Model:Destroy()
						usedSlots[inst.Slot] = nil
						instances[id] = nil
					end
				end
			end
		end
	end)
end

return StairwellService
