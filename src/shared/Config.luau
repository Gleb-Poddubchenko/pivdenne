--!strict
-- Config: central tuning values shared by server and client.
-- SCALE RULE (never change after the map import starts): 1 metre = 3.5 studs.

local STUDS_PER_METER = 3.5

local Config = {
	StudsPerMeter = STUDS_PER_METER,
	Meters = function(m: number): number
		return m * STUDS_PER_METER
	end,

	Currency = "₴",
	StartingMoney = 1000,

	-- Max distance (studs) between a player's HumanoidRootPart and a panel/kiosk
	-- for the server to accept a request. Slightly larger than prompt distance to
	-- tolerate latency.
	InteractDistance = 14,

	Data = {
		StoreName = "YuzhnePlayerData_v1",
		ApartmentRegistryStore = "YuzhneApartments_v1",
		SchemaVersion = 3, -- v2: Inventory itemId -> count + Storage; v3: Equipment + Loadout
		AutosaveInterval = 60,
		-- A session lock older than this is treated as abandoned (crashed server).
		-- Must be comfortably larger than AutosaveInterval, because autosave refreshes it.
		LockStaleAfter = 180,
		LoadAttempts = 6,
		SaveAttempts = 4,
		RetryBaseDelay = 1,
		RetryMaxDelay = 8,
	},

	Keys = {
		MaxKeysPerPlayer = 24,
		CopyPrice = 60,
		-- TM = touch-memory "tablet" (iButton), RFID = 125 kHz proximity fob.
		Types = { TM = "TM", RFID = "RFID" } :: { [string]: string },
		TypeNames = { TM = "Таблетка (TM)", RFID = "Брелок (RFID)" } :: { [string]: string },
	},

	Apartments = {
		Price = 500,
		MaxPerPlayer = 1,
	},

	Door = {
		OpenAngle = 95, -- degrees; Soviet entrance doors open outward
		ReleaseDelay = 0.25, -- maglock "clack" before the leaf moves
		OpenDuration = 1.1,
		HoldOpenTime = 4,
		CloseDuration = 2.6, -- door closer pulls it shut
	},

	Intercom = {
		RingTimeout = 25, -- owned flat, owner online
		UnownedRingTime = 6, -- nobody home: rings out
		MaxCallDuration = 180,
		MaxChatLength = 120,
		MaxDigits = 4,
		CallerMaxDistance = 24, -- caller walking further than this hangs up
	},

	-- Sound asset ids. Leave "" until you upload/licence your own sounds;
	-- empty ids are silently skipped so everything still works.
	Sounds = {
		DoorRelease = "", -- maglock release clack
		DoorCreak = "", -- hinge creak while opening
		DoorSlam = "", -- heavy metal door hitting the frame
		HandsetRing = "", -- the apartment handset (трубка) ringing, played to the owner
		-- Elevator (played client-side at the cabin, so no server sound traffic)
		ElevatorStart = "", -- contactor clunk + jolt when the winch starts
		ElevatorHum = "", -- looped motor/winch hum while moving
		ElevatorStop = "", -- brake clunk on arrival
		ElevatorDoors = "", -- sliding cabin doors clatter
		ElevatorShaftDoor = "", -- hinged shaft door bang
		ElevatorButton = "", -- worn panel button click
		ElevatorBell = "", -- emergency call bell ("ВИКЛИК")
		-- Apartments / shops
		Doorbell = "", -- flat doorbell ("дзвоник")
		FlatDoor = "", -- flat door opening/closing
		LightSwitch = "", -- wall switch click
		Purchase = "", -- till / receipt
		-- Equipment / fishing
		FlashlightClick = "",
		UmbrellaOpen = "",
		FishingCast = "",
		FishingSplash = "", -- bite / catch
		-- Vehicles
		CarEngine = "", -- looped engine; pitch follows speed (client-side)
		CarHorn = "",
		CarLock = "", -- central locking "chirp"
		CarDoor = "",
	},

	Elevator = {
		-- "Collective": request queue, stops for calls on the way (default).
		-- "Soviet": one command at a time; landing calls are refused with "ЗАНЯТО"
		-- while the cabin is busy or occupied, like the original single-button lifts.
		Mode = "Collective",
		Speed = 1.0 * STUDS_PER_METER, -- 1 m/s, typical for 9-storey residential lifts
		StartJerkFactor = 0.3, -- first fraction of a second at reduced speed = jolt
		StartJerkTime = 0.35,
		LevelingDistance = 0.8, -- studs from the floor where it creeps in slowly
		LevelingSpeedFactor = 0.2,
		MinStopDistance = 2.5, -- can't stop for a call closer than this (studs)
		CabinDoorTime = 0.9,
		ShaftDoorTime = 1.0,
		ShaftDoorAngle = 90,
		DoorHoldTime = 5,
		DoorHoldAfterCommand = 1.5, -- doors close soon after a floor button is pressed
		MaxDoorReversals = 3, -- doorway blocked -> wait again, at most this many times
		StallChance = 0.04, -- per trip; overridable per elevator with attribute StallChance
		StallMin = 8,
		StallMax = 25,
		AlarmRescueTime = 4, -- after ВИКЛИК the "dispatcher" restarts a stalled lift this fast
		AlarmCooldown = 3,
		OutOfServiceChance = 0.1, -- per elevator per server start (attribute RandomOutOfService=false disables)
		MaxTravelTimePerFloor = 8, -- safety timeout
		PanelDistance = 10,
	},

	Inventory = {
		MaxDistinctItems = 30,
		MaxStack = 20,
	},

	Storage = {
		MaxDistinctItems = 20,
		MaxStack = 50,
	},

	Shops = {
		MaxQuantityPerPurchase = 10,
	},

	Interiors = {
		-- Apartment interiors are instanced on demand in a "pocket" area far from the
		-- city and destroyed when empty, so 1000s of flats cost nothing until visited.
		Origin = Vector3.new(30000, 3000, 30000),
		Spacing = 80, -- studs between interior slots
		SlotsPerRow = 20,
		EmptyLifetime = 60, -- seconds an empty interior is kept before cleanup
		GuestPassDuration = 600, -- seconds a visitor may re-enter after being let in
		DoorbellTimeout = 20,
	},

	Vehicles = {
		MaxOwned = 3,
		WheelRadius = 0.3, -- metres
		HeightScale = 1.2, -- cars are drawn 20% taller so seated avatars fit (Roblox avatars are chunky)
		MaxSteerAngle = 32, -- degrees
		ReverseFactor = 0.35, -- reverse top speed as a fraction of forward
		-- Constraint sign conventions. If a car drives backwards on W, flip MotorSign;
		-- if it steers the wrong way, flip SteerSign.
		MotorSign = -1,
		SteerSign = -1,
		SpawnRadius = 60, -- must be this close to a parking spot to call a car
		ActionDistance = 30, -- lock/lights/flip/despawn range
		SpeedCheckFactor = 1.6, -- server flags cars faster than TopSpeed * this
		RegionCode = "BH", -- Odesa oblast plate prefix
	},

	Equipment = {
		LoadoutSlots = 4,
		BackpackBonusDistinct = 15,
		BackpackBonusStack = 10,
	},

	Fishing = {
		WaterDistance = 25, -- studs from water/beach to be allowed to cast
		CastDistance = 14, -- bobber lands this far in front of you
		BiteMin = 4,
		BiteMax = 12,
		BiteWindow = 2.5, -- seconds to click again after "Клює!"
		MaxDrift = 25, -- walking further than this from the bobber reels in
		-- itemId -> weight
		Catch = { fish_goby = 50, fish_sprat = 25, fish_horse = 15, fish_mullet = 8, fish_flounder = 2 } :: { [string]: number },
	},

	Entrances = {
		-- City entrances (from OSM entrance=* nodes on apartment blocks).
		Functional = true, -- real Entrance (door + intercom + reader) leading into an instanced stairwell
		DefaultFlatsPerFloor = 4, -- used when OSM has no addr:flats for the entrance
		LiftMinFloors = 6, -- Soviet blocks of 6+ floors have a lift (5-storeys don't)
		ChuteMinFloors = 9, -- garbage chute (сміттєпровід) in 9+ storey blocks
		-- EntranceId -> "Vizor" | "Metron". Everything else is assigned by a stable hash
		-- until photos tell us which panel each entrance really has.
		BrandOverrides = {} :: { [string]: string },
	},

	Stairwells = {
		Origin = Vector3.new(-30000, 3000, 30000), -- pocket area, separate from flat interiors
		Spacing = 70,
		SlotsPerRow = 20,
		EmptyLifetime = 90, -- seconds before an unused stairwell is removed
		ReenterCooldown = 4, -- after leaving, the open door won't pull you straight back in
	},

	Map = {
		-- City generated from OpenStreetMap (ServerStorage.MapData, made by tools/osm_to_roblox.py).
		BuildAtRuntime = true, -- build on server start if Workspace.City is missing (or bake it in Studio)
		YieldEvery = 120, -- features per frame while building at runtime
		ReplaceBaseplate = true, -- the 2048-stud template baseplate is replaced by ground covering the city
		MoveSpawns = true, -- move SpawnLocations to the generated spawn point (a main road near the centre)
		WindowBands = true, -- window strips on panel blocks (cheap facade detail)
		EntranceDetails = true, -- canopy + door + "під'їзд" plate at OSM entrance nodes
		ShowBrandNames = false, -- shop/fuel/bank labels show a generic category instead of chain names
		LabelDistance = 220, -- studs at which POI labels are visible
		-- Realism details (turn down for low-end phones)
		TerrainGround = true, -- ground and sea/lakes as Terrain (real water you can swim in)
		SeaExtrude = 1200, -- studs of sea drawn on the water side of each coastline segment
		SeaDepth = 16,
		-- Coastal cliffs (from the elevation data): beach width at the waterline and
		-- horizontal run of the cliff face, in metres. NEEDS VERIFICATION from photos.
		CliffBeach = 18,
		CliffRun = 14,
		Trees = true,
		StreetLamps = true,
		RoadMarkings = true, -- dashed centre lines on main roads, zebra crossings
		StreetFurniture = true, -- bus shelters, benches, rubbish containers, railway
		EntranceBenches = true, -- the classic bench by every під'їзд
		Balconies = true,
		BalconySpacing = 6.6, -- metres between balcony columns on panel blocks
		GlazedBalconyChance = 0.45, -- the patchwork of glazed / open balconies
		RoofDetails = true, -- lift machine rooms, roof parapets, TV antennas, plinths
		-- Address plate (адресна табличка). Colours/size NEEDS VERIFICATION from photos.
		Plate = {
			Width = 0.6, -- metres
			Height = 0.4,
			Elevation = 3.0, -- metres above ground (lower on small buildings)
			Background = Color3.fromRGB(18, 58, 140),
			TextColor = Color3.fromRGB(255, 255, 255),
		},
	},

	Time = {
		DayLengthMinutes = 24, -- one in-game day
		StartClock = 13,
		Latitude = 46.62, -- Pivdenne: real sun path
		NightStart = 19.8,
		NightEnd = 6.2,
		LightDistance = 320, -- client lights street lamps / windows within this range
	},

	Dev = {
		-- Builds a test block with two entrances, a key kiosk and a housing office.
		-- Turn off once the real map is in place.
		BuildTestScene = true,
		ForceTestScene = false, -- build the test scene even when OSM map data exists
	},
}

return Config
