# Yuzhne / Pivdenne (Південне): Roblox open-world replica

Phase 1 sets up the foundation: data persistence, entrances, entrance doors, intercoms, keys, flat ownership, plus a test block you can play straight away.

## 1. Folder tree and where each script goes

```
default.project.json                      Rojo project (also turns on StreamingEnabled)
tools/fetch_osm.sh        download OSM data for Pivdenne and convert it
tools/osm_to_roblox.py    OSM XML -> Luau map chunks (buildings, addresses, plates, roads, areas, POIs)
tools/osm_details.py      street-level detail: coastline, trees, lamps, crossings, bus stops, benches, bins, rail
tools/dem.py              elevation: downloads AWS Terrain Tiles (SRTM), samples the height grid
map/data/        -> ServerStorage.MapData             (generated Luau chunks + Index)
src/shared/      -> ReplicatedStorage.Shared          (ModuleScripts)
  Config.luau            scale (1 m = 3.5 studs), prices, timings, sound ids
  Types.luau             shared type definitions
  Net.luau               the ONLY place remotes are declared
  IntercomBrands.luau    VIZOR (Vizit-style) / METRON (Metacom-style) look and behaviour
  Items.luau             every item (food, household, pharmacy) with prices and use effects
  ShopCatalogs.luau      what each kind of shop sells (Grocery, Kiosk, Pharmacy)
  Vehicles.luau          car models (specs, prices) and Soviet-era paint colours
  Equipment.luau         equipment you own and carry (phone, flashlight, umbrella, rod, backpack)
  TextUtil.luau          Cyrillic-aware lower-casing and street/number normalisation
src/server/      -> ServerScriptService.Server
  Main.server.luau       Script: bootstrap, init order
  Services/              ModuleScripts, one system each
    PlayerDataService    DataStore, session locking, retry, autosave, BindToClose
    EntranceRegistry     finds tagged entrances, builds panel display + prompts
    DoorService          maglock door, door closer, exit button
    KeyService           TM/RFID keys: create, check, copy
    ApartmentService     flat ownership (global registry + player data)
    IntercomService      dialling, calls, owner answer/talk/open, key reader
    KioskService         key-copy kiosk and housing office (ЖЕК) remotes
    ElevatorService      Soviet lifts: state machine, queue, physics cabin, doors, stalls
    InventoryService     item stacks in the bag and in apartment storage (fridge)
    ShopService          buying at shop tills and kiosks
    InteriorService      on-demand apartment interiors + lights/TV/stove/fridge
    ApartmentDoorService flat doors: enter/leave, doorbell, guest passes
    VehicleService       dealership, spawning cars at parking spots, seats, lock/lights/horn, speed checks
  Vehicles/CarFactory    builds a drivable car (body, seats, sprung wheels, steering, motors)
  City/CityBuilder       builds Workspace.City from MapData (also bakeable from the command bar)
  City/AddressPlates     street + house-number plate on a wall
  City/Geometry          part / triangle / polygon / polyline helpers
    CityService          builds the city at runtime, moves the spawn, adds the spawn service point
    StairwellService     city entrances: open door -> instanced stairwell; exit; cleanup
    EquipmentService     buying equipment, loadout, tools on spawn, flashlight/umbrella, backpack bonus
    FishingService       casting, bites, catches, water zones (map + FishingSpot), fish buyer
    AddressService       real-address search from OSM data (for the phone)
  City/MapData           read-only access to the generated chunks
  City/StreetDetails     sea, railway, trees, street lamps, zebras, bus shelters, benches, bins
  City/Height            ground height anywhere (same triangles as the terrain), cliff segments
  City/TerrainBuilder    sculpts the real relief: heightmap, materials, loess cliffs over sand beaches
  City/Facade            real OSM colours/materials, plinths, parapets, balconies, antennas, lift rooms
    LightingService      day/night with the real sun path at 46.62°N, sea haze
  Building/EntrancePlanner  which OSM entrances become working ones, flat ranges (addr:flats or estimated)
  Building/EntranceBuilder  outside of a working entrance: door, intercom, reader, canopy, doorway trigger
  Building/StairwellBuilder Soviet stairwell: marches, landings, flat doors, lift, chute, mailboxes
  Building/LiftBuilder      complete lift (shaft, cabin, landings), reused by stairwells and the test tower
  Building/FlatDoorBuilder  dermantin flat door with number plate, peephole, bell
  Util/Teleport          fade + stream-in + move character
  Equipment/ToolFactory  builds the Tool models
  Util/                  RateLimiter, Validation, Sfx
  Dev/TestSceneBuilder   test 9-storey block (turn off with Config.Dev.BuildTestScene)
  Dev/TestElevatorBuilder test 9-stop lift tower with landings and a climbable ladder
  Dev/TestApartmentBuilder flat doors in the test lobbies (flats 1–4 and 37–40)
  Dev/TestShopBuilder    grocery shop, ice-cream kiosk and pharmacy kiosk
  Dev/TestParkingBuilder dealership, parking lot with 4 spots, a long test road
  Dev/TestEquipmentBuilder sports kiosk, fishing pond with a pier, fish stall
  Dev/TestStairwellBuilder  a city-style entrance "test-a/3" (flats 73–108, 9 floors, lift) on the test block
  Dev/TestStreetBuilder  lamps, zebra, bus shelter, trees, benches, bins around the test scene
src/client/      -> StarterPlayer.StarterPlayerScripts.Client
  Main.client.luau       LocalScript: bootstrap
  Controllers/           DataController, HudController, KeyRingController,
                         IntercomController, CallController, KioskController,
                         ElevatorController (lift sounds, jolts, flicker, cabin panel UI),
                         InventoryController (bag + fridge), ShopController,
                         ApartmentController (teleport fade, doorbell popup),
                         VehicleController (driving physics, speedometer, horn/lights),
                         GarageController (my cars, dealership),
                         EquipmentController (sports shop, loadout, fishing feedback),
                         PhoneController (clock, money, address search + marker),
                         NightLightsController (street lamps + lit windows near you at night)
  Ui/UiKit.luau          GUI helpers (all GUIs are built in code)
```

**With Rojo:** run `rojo serve` in this folder, then click Connect in the Rojo Studio plugin.
**Without Rojo:** make the same hierarchy by hand. `*.server.luau` files become a **Script**, `*.client.luau` files become a **LocalScript**, everything else becomes a **ModuleScript** named after the file without its extension. Folders become **Folder**s.

Studio settings: Game Settings → Security → **Enable Studio Access to API Services** (if this is off, saving is skipped and a warning is printed). Workspace → **StreamingEnabled = true**.

## 2. Architecture rules

- **Server-authoritative.** Clients only send intents (`IntercomDial`, `UseKey`, `CallAction`, …). For each one the server checks argument types, rate limits, distance to the panel or kiosk, ownership and money.
- **Data** changes only through `PlayerDataService.Update`, which keeps the client snapshot in sync.
- **Session lock:** `UpdateAsync` with `{JobId, Time}`. A lock counts as stale after 180 s, and autosave refreshes it every 60 s. If another server takes over the lock, this server stops writing and kicks the player, so items can't be duplicated across servers.
- **Flat purchase** is atomic across servers through the `YuzhneApartments_v1` registry (`UpdateAsync`).
- **No per-frame server loops.** Doors use one tween on an anchored hinge. Call watchdogs run every 2 s, and only over calls that are active.
- **Chat** in intercom calls is filtered with `TextService` (`PrivateChat` context), as Roblox rules require.

## 3. Entrance model contract (for real buildings)

Tag a Model `Entrance` (Tag Editor / Properties → Tags) and give it these attributes:

| Attribute | Example | Meaning |
|---|---|---|
| `EntranceId` | `b0142/3` | `<BuildingId>/<entrance number>`, unique |
| `Brand` | `Vizor` / `Metron` | intercom family |
| `AptFrom`, `AptTo` | `37`, `72` | flats served by this entrance |

Children: `Door` (Model) with `Hinge` (part on the hinge axis, front = outward) plus any door parts; `Intercom` (Model) with `Panel` (front face outward) and `Reader`; optionally `ExitButton` on the inside. `TestSceneBuilder.buildEntrance` is the reference implementation. Kiosks are a BasePart tagged `KeyKiosk` or `HousingOffice`.

## 4. How to test Phase 1 in Studio

Press **Play** (use **Test → Start** with 2 players for the multiplayer tests). In front of the spawn you'll find a 9-storey block with entrance `test-a/1` (VIZOR, flats 1–36, TM keys only) and `test-a/2` (METRON, flats 37–72, RFID or TM), plus the blue **КЛЮЧІ** kiosk and the red **ЖЕК** office.

| # | Test | Expected |
|---|---|---|
| 1 | Output shows `[Yuzhne] Server ready`; HUD shows `₴ 1000` and the OSM attribution | data loaded |
| 2 | VIZOR panel → E → dial `12` → 🔔 | display shows `  12`, rings ~6 s, then `----` (nobody home) |
| 3 | Dial `99` on VIZOR | `Err` and a toast "Тут квартири 1–36" |
| 4 | METRON → type `40` and wait 2.5 s | dials automatically, display shows `ВИКЛИК 40` |
| 5 | Reader (F) with no key in hand | toast, and the key ring opens |
| 6 | ЖЕК → pick `test-a/1` → flat `12` → Купити | ₴500 is taken, the key "Кв. 12 · test-a/1" (TM) shows up in the ring (K) |
| 7 | Key ring → Взяти → reader on `test-a/1` | green flash, `OPEN`, maglock → door swings out → stays open 4 s → closer → slam |
| 8 | Same key on `test-a/2` | red flash, "Ключ не запрограмований для цих дверей" |
| 9 | Go inside → exit button (E) | door opens without a key |
| 10 | Dial your own flat `12` | the handset pops up for you: Відповісти → type a message → 🔓 Відчинити opens the door |
| 11 | 2 players: P2 dials P1's flat | P1 answers and chats, the text is filtered; P1 Відхилити → P2 sees `----` and "Виклик відхилено" |
| 12 | Kiosk → copy a key | ₴60 is taken, a "(копія)" key appears |
| 13 | Stop, then Play again (API access on) | money, keys and the flat persist |
| 14 | Spam the keypad or reader | rate limiter quietly drops the extra requests |

Exploit check: in the client console run `game.ReplicatedStorage.Remotes.UseKey:FireServer("test-a/1","fake")` from far away. Nothing should happen.

## 5. Phase 3: Soviet elevator

**How it works**
- **The cabin really moves with physics.** It's an unanchored assembly driven by a server-owned `PrismaticConstraint` servo running at 1 m/s. Roblox's character controller carries riders on a platform that moves with real velocity. Tweening an anchored part teleports it instead, and that's what makes players jitter or fall through. The cabin and the shaft are in separate collision groups, so the tight clearances never jam.
- **Movement feels like an old Soviet lift:** a jolt at the start (a fraction of a second at reduced speed), a slow creep over the last 0.8 studs to level with the floor, then a hard stop. Riders feel these as camera jolts on their own client.
- **Doors:** each floor has a hinged shaft door that swings outward. The cabin has two sliding panels, moved by tweening `Weld.C0`. Shaft doors only open where the cabin actually is, so nobody can fall into the shaft. If someone stands in the doorway, the doors wait again (up to 3 times).
- **Server state machine:** `Idle, MovingUp, MovingDown, DoorsOpening, DoorsOpen, DoorsClosing, Stalled, OutOfService`. It's replicated as attributes on the model: `State`, `Floor`, `CabinRequests`, `AlarmAt`.
- **Queue:** it keeps going in its current direction while there are calls ahead, and stops for calls on the way if it still has room to brake. Set `Config.Elevator.Mode = "Soviet"` to get the original single-button behaviour: landing calls are refused with **ЗАНЯТО** while the cabin is busy or occupied.
- **Optional realism:**
  - It sometimes stalls between floors (`StallChance`) for 8–25 s. The **ВИКЛИК** button rings the bell, the "dispatcher" answers, and the lift restarts within 4 s.
  - **СТОП** stops it at the next floor.
  - It can be **out of service** (10% chance per server start). A broken lift waits with its doors open, so nobody is ever trapped inside.
- **Client side:** all sounds, the flickering lamp (much worse while stalled) and the camera jolts run locally from those attributes, so there's no extra network traffic.

**Model contract.** Tag a Model `Elevator` and give it these attributes:
- `ElevatorId`
- `Floors`
- `FloorHeight` (9.8 = 2.8 m)
- optional: `StallChance`, `RandomOutOfService=false`, `OutOfService`

Children: `Rail`; `Cabin` (built **at floor 1**: `Platform`, `Bounds`, `ButtonPanel`, `DoorL`, `DoorR`, `Lamp`); `Landings/Landing_1..N` (`ShaftDoor` with `Hinge`, `CallButton`, optional `Indicator`). `TestElevatorBuilder` is the reference.

**Test in Studio.** The lift tower stands to the left of the test block, at x ≈ −80. Its stall chance is raised to 25% so you'll actually see a stall. Out-of-service never happens on its own here; you trigger it yourself (test 8).

| # | Test | Expected |
|---|---|---|
| 1 | Floor 1 call button (E) | button lights orange, shaft door swings out, cabin doors slide open |
| 2 | Step in → "Кнопки" (E) → press 7 | button lights, doors close after ~1.5 s, a jolt, it climbs; panel shows `2 ▲`, `3 ▲` … |
| 3 | Stand still during the ride | you ride smoothly: no jitter, no falling through, a short jolt at start and stop |
| 4 | Ride from 1 to 9; a second player calls from 5 while you're going up | it stops at 5 on the way, then carries on to 9 |
| 5 | Climb the ladder to 9 and call the lift (it's at 1) | it comes up; the **ЗАНЯТО** lamp is lit on every floor while it moves |
| 6 | Press СТОП mid-ride | it stops at the next floor and opens |
| 7 | Keep riding until it stalls (or set `StallChance` = 1) | it stops between floors, the lamp flickers, a toast appears; ВИКЛИК → the dispatcher answers and it restarts in ~4 s |
| 8 | Server view: set the lift's `OutOfService` attribute to true | lamps show **НЕ ПРАЦЮЄ**, doors stay open, calls answer "Ліфт не працює"; set it back to false and it works again |
| 9 | Stand in the doorway | doors wait instead of closing (3 times at most) |
| 10 | Exploit check: fire `ElevatorPanel` from outside the cabin | ignored |

## 6. Phase 4: apartments and shops

**Apartments**
- **Flat doors.** A flat door is a Model tagged `ApartmentDoor` with attributes `EntranceId` and `Apt`, and children `Door` (front face toward the stairwell) and `Bell`. The owner walks straight in (E). Everyone else rings the bell (F).
- **Doorbell.** The owner only hears it while they're inside the flat; a popup lets them open or ignore it. Opening gives the visitor a 10-minute guest pass and lets them straight in. If nobody's home: "Ніхто не відчиняє".
- **Interiors are instanced on demand.** A city has thousands of flats, so none of them exist until someone enters. Each one is generated in a free slot in a "pocket" area far from the map (`Config.Interiors.Origin`). It's destroyed after 60 s empty, so unvisited flats cost nothing. The server streams the area in before teleporting, and the client shows a short black fade.
- **Layout "1k"** (однокімнатна, ~35 m², real proportions):
  - hall, combined bathroom, ~6 m² kitchen, a room, and a glazed balcony
  - furniture: the brown "стінка" wall unit, a carpet on the wall, sofa, TV, gas stove, fridge, bathtub
  - wallpaper colour varies by flat
- **Things you can use:**
  - a light switch in each room
  - the TV (cycles through channels and off)
  - the stove burners
  - the **fridge**, which is real storage saved in the owner's data
  - the inside of the door ("Вийти"), which always works, so nobody can get trapped
- **Persistence.** Data schema v2: `Inventory` (itemId → count) and `Storage` (flat → itemId → count). v1 saves migrate automatically.

**Shops**
- A shop is a Model tagged `Shop` with attributes `ShopId`, `Catalog` and `DisplayName`, and a `Till` part. The server always takes the price from `ShopCatalogs`, never from the client. It checks distance to the till, money, and inventory space, and refunds you if adding the item fails.
- **Items** can be used from the bag (B). Food and pharmacy items restore a little health.
- **Test scene:**
  - behind the spawn: the enterable grocery **Продукти «Каштан»**, with shelves, a dairy fridge, a counter and a shop assistant
  - left: the kiosk **«Пломбір»**
  - right: **Аптека «Ромашка»**
  - all names are fictional

**How to test**

| # | Test | Expected |
|---|---|---|
| 1 | ЖЕК → buy flat `2` in `test-a/1` (₴500) → open the entrance door with your key → lobby back wall → door **2** → E | fade → you're inside the flat |
| 2 | Inside: try the switches, TV, stove | lights toggle, TV cycles channels then off, blue flames on the stove |
| 3 | Grocery shop → till → buy bread, milk, salo | money goes down, items appear in the bag (B) |
| 4 | Back home → fridge → put milk in → Stop, then Play again → fridge | the milk is still there |
| 5 | Bag → Використати on salo | a toast appears, health goes up, salo ×1 is gone |
| 6 | Try door **3** (not yours) | "Зачинено. Подзвоніть у дзвінок." |
| 7 | 2 players: P1 is inside flat 2, P2 rings at door 2 | P1 gets a popup → Відчинити → P2 teleports in |
| 8 | Exit: the inside of the door → Вийти | back in the lobby in front of door 2 |
| 9 | Exploit check: `BuyItem` from far away or with a fake price; `StorageMove` from outside the flat | refused |

## 7. Phase 5: vehicles

**How it works**
- **Cars are built from constraints.** Each car is a heavy, low chassis with massless bodywork welded on: glasshouse, roof, pillars, chrome bumpers, headlights (real SpotLights), taillights, and Ukrainian plates `BH 1234 AE` with the blue UA strip.
  - Each wheel sits on a `PrismaticConstraint` with a `SpringConstraint` (suspension).
  - Front wheels steer through servo `HingeConstraint`s.
  - Every axle is a motor, used to drive and to brake.
  - Springs and torque are tuned from the real chassis mass.
- **The driver's computer runs the car's physics.** When the owner sits in the driver's seat, the server gives that car's physics to their client. `VehicleController` reads `VehicleSeat.ThrottleFloat` / `SteerFloat` every frame, so keyboard, gamepad and the mobile thumbstick all work. It sets the motors (drive, brake when you press against the direction of travel, light engine braking) and reduces steering at speed so cars don't roll over.
- **The server keeps control of the rules:**
  - only the owner drives
  - passengers may sit only while the car is unlocked
  - one active car per player
  - cars can only be called to a `CarSpawn` spot within 60 studs
  - once a second it checks speed and teleporting, and takes physics back from a cheating client
  - when you get out, it places you beside your door
- **Models:**
  - «Ластівка»: small, front-wheel drive, ₴400
  - «Класика»: rear-wheel-drive sedan, ₴1500
  - «Мандрівник»: estate, ₴2500
  - «Буханка»: 4×4 van, ₴4000
- **Paint colours:** Вишня, Баклажан, Коррида, Сафарі, Морська хвиля…
- Bought cars are saved in `PlayerData.Cars`.

**Model contract.** Tag a part `CarDealer` for a dealership. Tag flat, non-colliding parts `CarSpawn` for parking spots or garages; each spot's LookVector is the direction the car faces.

**Tuning.** If cars drive backwards on W, set `Config.Vehicles.MotorSign = 1`. If they steer the wrong way, set `SteerSign = 1`. The 1 m = 3.5 studs scale makes real speeds feel fast, so top speeds are 80–97 km/h.

**How to test** (parking lot at x ≈ 115, to the right of the spawn)

| # | Test | Expected |
|---|---|---|
| 1 | АВТОСАЛОН → pick a colour → buy «Ластівка» (₴400) | toast with your plate number |
| 2 | 🚗 Авто (V) → Викликати | the car appears on a yellow spot |
| 3 | E at the driver's door → W/A/S/D | it drives and steers smoothly; speedometer in km/h; S brakes, then reverses |
| 4 | H, L | horn; headlights turn on (try at night: Lighting.ClockTime = 22) |
| 5 | Jump (Space) to get out | you land next to the driver's door |
| 6 | 2 players: P2 tries to drive P1's car | "Це не ваша машина." P1 unlocks (V → 🔒) → P2 can sit as a passenger and ride along |
| 7 | Flip the car on the road, then V → ↻ | it stands back on its wheels |
| 8 | Leave the game | the car disappears; it's still in "Мої машини" after rejoining |
| 9 | Exploit check: speed hack the owned car | after 2 s: "Двигун заглух", the server takes physics back |

## 8. Phase 2: the real city from OpenStreetMap

Every building, street and address comes from OpenStreetMap. **Nothing is invented:** if OSM has no address for a building, it gets no plate.

**Pipeline**
1. `bash tools/fetch_osm.sh` downloads the Pivdenne bounding box from the OSM API in 4 tiles into `data/`. The box is the city boundary, OSM relation 3606547, padded about 400 m.
2. It then runs `python3 tools/osm_to_roblox.py data/*.osm --out map/data` (standard-library Python only). The converter:
   - **Projects** coordinates onto a local plane around the city centre (46.6225029, 31.0994897): east → +X, north → −Z, **1 m = 3.5 studs**.
   - **Buildings:** footprints are simplified and oriented. Height = `building:levels` × 2.8 m, or `height`, or a typology default. Each building gets a typology: panel5 / panel9 / panel_high / house / garage / industrial / public / commercial.
   - **Addresses:** taken from `addr:street` + `addr:housenumber`, including separate address points inside an outline.
   - **Address plate placement:** for every addressed building, it picks the wall facing the street named in the address (falling back to the nearest road). Plates go 1.5 m in from the corners, with a second plate on walls longer than 25 m. Street names are shortened the standard way (вулиця → вул., проспект → просп., провулок → пров. …).
   - **Entrances:** `entrance=*` nodes, with their `ref` (entrance number) and `addr:flats`.
   - **Other features:** roads with widths, parks/water/beach/parking areas, and named POIs.
   - **Output:** chunks of 512 studs, split so each module stays under 180 KB, plus `Index.luau` (bounds, spawn, a list of streets, stats).
3. Rojo syncs `map/data` to `ServerStorage.MapData`. On server start `CityService` builds `Workspace.City`, a little per frame:
   - **Buildings:** rectangular blocks become a single box with a roof slab and window bands; other shapes become walls plus a roof triangulated from WedgeParts.
   - **Address plates** on the walls.
   - **Entrances:** a door and canopy at each entrance, with an "Під'їзд N · кв. X–Y" plate when OSM has those tags.
   - **Roads, areas, ground,** and labels for schools, markets, the bus station and so on.
   - **Spawn** is moved onto a main road near the centre.
4. **For release, bake the city:** run `require(game.ServerScriptService.Server.City.CityBuilder).Build(workspace)` in the Studio command bar, save the place, then set `Config.Map.BuildAtRuntime = false`.

**Rules from the brief:**
- Shop, fuel and bank labels show generic categories instead of chain names (`Config.Map.ShowBrandNames = false`).
- "Map data © OpenStreetMap contributors" stays on the HUD.
- The derived map is ODbL.

When map data exists, the dev test scene isn't built, because it would overlap the city centre. Set `Config.Dev.ForceTestScene` to build it anyway.

**How to test**

| # | Test | Expected |
|---|---|---|
| 1 | `bash tools/fetch_osm.sh` | stats are printed: buildings, how many have addresses, plates, entrances, streets |
| 2 | Rojo sync → Play | Output: `[City] Built N buildings from OSM`; you spawn on a real street |
| 3 | Walk to a block whose address you know | the plate on its street-facing wall shows the OSM street and number |
| 4 | Explorer: Workspace.City → a building model | model name and attributes = `Street`, `HouseNumber`, `Levels`, `OsmId`; check the OsmId on openstreetmap.org/way/ID |
| 5 | Find a 9-storey block | 9 window bands, about 26 m tall (≈ 90 studs) |
| 6 | A missing or wrong address in game | fix it **in OpenStreetMap** (that helps everyone), then re-run the script |

**Working city entrances**
- **Which entrances work:** every OSM `entrance=*` node on an apartment block (panel typologies) becomes a real `Entrance` at its real position. That means the heavy door with closer and maglock, a VIZOR or METRON intercom, and a key reader. Each one is registered through the normal `EntranceRegistry`, `DoorService` and `IntercomService`. Other buildings get a decorative door.
- **Flats per entrance** come from `addr:flats`, e.g. "1-36". When OSM doesn't have it, they're **estimated**: entrances in `ref` order, 4 flats per floor. The model then carries `FlatsSource = "estimated"`. The "Під'їзд N · кв. X–Y" plate is only shown with real OSM tags.
- **Going inside:** open the door with the intercom (the owner presses "open") or your key, then step through. You're teleported into that entrance's **instanced stairwell**, built on demand in a pocket slot like the flat interiors.
- **Stairwell, per storey:**
  - two stair flights with a half-landing in between
  - a terrazzo landing with green oil paint on the lower walls
  - a bare bulb
  - up to 6 flat doors (working `ApartmentDoor`s: walk in if it's yours, ring the bell otherwise)
  - a window
- **Building-wide:** a stencilled floor number; on 9+ floors, a garbage chute with a hatch on every half-landing; on 6+ floors, a **complete Soviet lift** behind the back wall, with call buttons and ЗАНЯТО lamps. The lift is now built by `LiftBuilder`, shared with the test tower. Mailboxes on the ground floor.
- **Leaving:** the inside door or the green exit button takes you back to the street, and the street door swings open behind you.
- **Cleanup:** a stairwell is removed after 90 s with nobody inside it, in its lift, or in one of its flats. Lifts and flat doors unregister cleanly when it's removed, so it can be rebuilt later.
- **Intercom brand:** VIZOR or METRON is assigned per entrance by a stable hash for now. Set the real one in `Config.Entrances.BrandOverrides` once photos show it.
- **City service point:** a temporary ЖЕК, key-cutting kiosk, car dealer and two parking spots next to the spawn, so flats and keys can be bought in the city.

**How to test (no map data needed):** there's a city-style entrance on the **east end wall of the test block**, «Під'їзд 3 · кв. 73–108», with a METRON panel, 9 floors and a lift.

| # | Test | Expected |
|---|---|---|
| 1 | ЖЕК → `test-a/3` → flat 80 | an RFID key "Кв. 80 · test-a/3" in your key ring |
| 2 | Hold the key → reader (F) | door unlocks and swings open; walk through → fade → you're in the ground-floor lobby |
| 3 | Look around | mailboxes, green lower walls, floor numbers, flat doors 73–76 on floor 1 |
| 4 | Lift call button → ride to 2 | flat 80 is on floor 2 (4 per floor); its door lets you straight in |
| 5 | Walk the stairs to 9 | marches with a half-landing between each floor; garbage chute hatches; flats up to 108 |
| 6 | Ground floor → Вийти (door or green button) | back on the street, and the street door opens behind you |
| 7 | 2 players: P2 dials 80 on the panel while P1 is anywhere | P1 answers and presses "open" → the door opens → P2 walks in |
| 8 | Leave for 90 s | Explorer: Workspace.Stairwells is emptied; entering again rebuilds it |
| 9 | With map data | the same works on every mapped entrance of every apartment block in Pivdenne |

**Current real data (downloaded 2026-11-07, OSM API, 4 tiles)**

| | |
|---|---|
| buildings mapped in OSM | 469: 93 apartment blocks, 103 with a floor count (54 nine-storey, 13 ten-storey, 7 sixteen-storey) |
| real addresses → plates | 108 buildings, 144 plates, 36 streets (вул. Хіміків, просп. Миру, просп. Григорівського Десанту, вул. Будівельників, вул. Тараса Шевченка, Приморська вул. …) |
| entrances | 4 mapped in OSM; **245 estimated** (one per ~24 m section, courtyard side) so every apartment block has working під'їзди |
| roads / areas / POIs | 589 / 138 / 117 |
| details | coastline (sea side verified: all 46 nearby buildings are on the land side), 5 714 trees, 1 332 lamps (generated, none mapped), 17 zebra crossings, 4 bus stops |
| skipped | 1 malformed value: way 970273977 `addr:street` holds a whole address from the village of Sychavka. Fix it in OSM. |

**OSM coverage is the limit.** Many private houses and some blocks aren't mapped, and most buildings have no floor count; apartment blocks without one default to 5 storeys. Adding `building:levels`, `addr:*` and `entrance=*` (with `ref` and `addr:flats`) on openstreetmap.org, then re-running `bash tools/fetch_osm.sh`, improves the game directly. That includes plates, real flat numbers and entrance positions.

**Realism pass: details**

Real OSM objects are used wherever they're mapped. Generated detail only fills gaps, is reproducible (seeded by position), and never lands on buildings or roads.

| Detail | Source | In game |
|---|---|---|
| **Sea, estuary, lakes** | `natural=coastline` (water is right of the way direction), `natural=water` | Terrain water 16 studs deep you can swim in; Black Sea green-blue; the ground is Terrain too |
| **Trees** | real `natural=tree`, `tree_row`; generated in parks, forests, grass and **residential courtyards** | trunk + ellipsoid crown, round crowns and pyramidal poplars, varied greens |
| **Street lamps** | real `highway=street_lamp`; generated every ~35 m along streets with no mapped lamps | concrete pole, arm over the road, sodium-orange light at night |
| **Zebra crossings** | `highway=crossing`, aligned to the road under them | white stripes across the road |
| **Road markings** | main roads (trunk/primary/secondary/tertiary) | dashed centre line (3 m dash / 6 m gap) |
| **Bus stops** | `highway=bus_stop` with the **real stop name** | shelter with bench and a name sign |
| **Benches, bins** | `amenity=bench`, `waste_disposal`/`recycling`; plus a bench beside **every working під'їзд** | Soviet slatted bench on concrete legs, green containers |
| **Railway** | `railway=rail` | ballast + rails at the real **1520 mm** gauge |
| **Building colours** | `building:colour`, `roof:colour`, `building:material` | the real colour and material; typology palette otherwise |
| **Panel blocks** | typology | dark plinth (цоколь), roof parapet, TV antennas, balcony columns on the side without entrances, with the **patchwork of glazed and open balconies** |
| **Roofs** | entrances with a lift | lift machine room above each lifted entrance |
| **Sky** | real latitude 46.62°N | day/night cycle (24 min); sea haze, warm southern light; at night lamps and ~45% of windows light up near you |

Everything is switchable in `Config.Map` (`Trees`, `StreetLamps`, `Balconies`, `RoofDetails`, …) to tune for phones. The converter prints a count for every detail type.

**How to test without map data:** Play and look around the test scene:
- lamps and a zebra crossing on the road next to the parking lot
- a bus shelter
- trees and benches in front of the test block
- containers by the pond

Set `Lighting.ClockTime = 21` in the server view: the lamps come on near you.

**Hills and coastal cliffs (real elevation)**
- **Source:** the public AWS Terrain Tiles (terrarium PNGs, zoom 14, SRTM-based, ~30 m). `tools/dem.py` downloads the 20 tiles over Pivdenne and decodes them with the standard library. The converter samples a grid every 24 m on the map's own projection, with one light smoothing pass: `--dem data/dem`, spacing set by `--dem-grid`.
- **What the data shows:**
  - the city sits on a **plateau of about 32–46 m** (the spawn is at 32.5 m)
  - a low valley runs north–south toward the estuary
  - the land drops to the Black Sea in the south
- **Terrain:** every grid cell is two `FillWedge` triangles, thick enough to reach the sea floor. Materials come from OSM areas: grass in parks, leafy ground in woods, sand on beaches, asphalt and concrete for car parks and garages. Anything steeper than 30° becomes yellow-brown loess.
- **Coastal cliffs:** the grid smooths cliffs to at most 12°, so the converter finds coastline segments where the land 50–90 m inland stands higher than 8 m. That's **39 segments, up to 29 m high**. Along those, `TerrainBuilder` cuts a **sand beach** (18 m) at the waterline and raises a **near-vertical loess cliff** (14 m run) to the plateau. Both widths are set in `Config.Map.CliffBeach` / `CliffRun`.
- **Everything sits on the ground:** `Height.At()` interpolates on exactly the triangles the terrain uses.
  - buildings stand on their lowest corner and the hillside covers the rest (median ground drop under a footprint 0.8 m, max 8 m)
  - roads are subdivided every 6 m and follow the slope
  - plates, entrances, trees, lamps, benches, shelters, counters, labels, the spawn and the service point use the ground height at their own spot
  - lakes sit at their lowest shore level
  - small car parks are laid flat at mid height
- **Turning it off:** without elevation data, or with `Config.Map.TerrainGround = false`, the map is flat as before.

**Still to come in Phase 2:**
- Finer cliffs where photos show them (ravines, landslide terraces); the cliff widths are estimates. (`natural=coastline` → Terrain water).
- Facade templates with balconies.
- Courtyard props: playgrounds, benches, garages.

## 9. Phase 6: equipment

**What it does**
- **Equipment** is bought once at a **«Спорттовари»** counter (tag `EquipmentShop`) and kept forever (`PlayerData.Equipment`). You choose what to carry in the loadout (J, up to 4 slots, `PlayerData.Loadout`). Carried tools appear in the Roblox hotbar on every spawn.
  - **Мобільний телефон**, ₴150: while it's in your hand you see the clock and your money, and can **search for a real address**. Street suggestions come from the OSM data; Cyrillic matching works for both "вул. Хіміків" and "хіміків". A map marker shows the distance in metres. Only addresses that exist in OpenStreetMap can be found.
  - **Ліхтарик**, ₴60: click to switch the real SpotLight on and off.
  - **Парасолька**, ₴40: open and close.
  - **Вудка**, ₴120: fishing (below).
  - **Рюкзак**, ₴200 (passive): +15 item kinds and +10 per stack in the bag, and it's visible on your back.
- **Fishing, the first way to earn money:**
  - **Where:** near water. That's a `FishingSpot` part, or a water/beach area from the OSM data.
  - **Catching:** click to cast. After 4–12 s you get **"Клює!"**, and you have 2.5 s to click again. Miss it and the fish gets away.
  - **Catches:** бичок, тюлька, ставрида, піленгас, and rarely камбала (₴150).
  - **Selling:** at a **«Риба»** counter (tag `FishBuyer`).
  - **Ending a cast:** walking away or putting the rod away reels in.
- **In the real city**, OSM shops turn into working counters at their real locations, just outside their building and facing the street:
  - convenience stores and supermarkets → grocery till
  - kiosks → kiosk till
  - pharmacies → pharmacy till
  - sports and hardware shops → equipment counter
  - the marketplace → equipment counter **and** fish buyer
  - labels stay generic, never chain names
- **Server-authoritative:** prices and ownership are checked on the server; activating a tool only counts while it's in the holder's hand; casting checks water distance on the server; catches are rolled on the server; selling checks distance.

**How to test** (test scene: kiosk at x ≈ −75, pond at x ≈ −115)

| # | Test | Expected |
|---|---|---|
| 1 | СПОРТТОВАРИ → buy a rod and a phone | money goes down; both appear in the hotbar (they're added to your loadout automatically) |
| 2 | Walk onto the pier, rod in hand, click | "Закинули"; a red bobber with a line |
| 3 | Wait for "КЛЮЄ!" and click within 2.5 s | "Спіймали: Бичок!"; it shows up in the bag (B) |
| 4 | Don't click after a bite | "Зірвалася…" |
| 5 | Cast away from water | "Тут немає води" |
| 6 | РИБА stall → Продати рибу | money goes up by the fish prices; the fish leave the bag |
| 7 | J → untick the rod | it leaves the hotbar; it's back after respawning only if ticked |
| 8 | Buy the backpack | a bag on your back; more space in the inventory |
| 9 | With map data: phone → type part of a street → pick one → house number → Знайти | the marker appears at that building; "Ви на місці" when you arrive |
| 10 | Flashlight at night (Lighting.ClockTime = 22) | the beam lights the way |

## 10. Roadmap

- **Phase 1 (done):** data, entrances, doors, intercoms, keys, flats, kiosks.
- **Phase 2 (in progress):** done: OSM converter, city builder, real address plates, roads, areas, POI labels, working entrances with instanced stairwells, lifts and flats. Next: the coastline, facade templates, courtyard props.
- **Phase 3 (done):** Soviet elevator system.
- **Phase 4 (done):** apartments (instanced interiors, doorbell, fridge) and shops (catalogues, tills, inventory). Next: a "2k" layout, furniture you can buy and place, a way to earn money (jobs), and shop opening hours with a day/night cycle.
- **Phase 5 (done):** vehicles. Next: fuel and petrol stations, garages in courtyards (tag `CarSpawn` inside a garage), traffic/NPC cars, damage.
- **Phase 6 (done):** equipment, fishing economy, phone with address search, real shop counters in the city. Next: more jobs (courier with the car, market seller), bicycle, camera.
- Intercom voice: wire `AudioDeviceInput → AudioEmitter` on the panel and the handset (Roblox's new Audio API) for players who have voice chat. Text chat stays as the fallback.

## 11. NEEDS VERIFICATION (please send photos / Street View)

- Exact panel layouts and colours of the Vizit and Metacom models actually fitted in Yuzhne: display type (LED or LCD), position of the call key, reader shape, and whether the entrance door has a visible maglock.
- Which key type each building uses (TM tablet or RFID fob), and whether any panels accept both.
- Dialling behaviour on the real panels: auto-dial delay, whether a "B"/bell key is pressed after the number, and the confirmation beep patterns.
- Flat-numbering scheme per entrance (flats per floor: 4 on 9-storey blocks? 3 on some 5-storey ones?).
- Entrance door style: brown or green steel, the canopy shape, and whether there are steps or a ramp.
- Origin coordinates for the map projection, and the positions of landmarks: central square(s), the seaside promenade and beach access, the port and plant area, schools, markets, the bus station, main shops.
- Lifts in Yuzhne: which plant made them (Karacharovo/KMZ, Mogilev/MOGILEVLIFTMASH, Shcherbinka?), and whether 1980s blocks have **automatic sliding shaft doors** rather than the hinged ones you asked for. Hinged manual shaft doors are typical of older lifts. Also the cabin size, the panel layout (one or two button columns, СТОП/ВИКЛИК labels in Russian or Ukrainian), the wall finish, and whether a lift stops at every floor or only at half-landings.
- Street-level look: lamp pole types (concrete or metal), bus shelter design, tree species along the main streets (the generator mixes round crowns and poplars), balcony glazing share, building colours (OSM rarely tags `building:colour`).
- The coastal cliffs: real height and steepness, beach width at their foot, and where there are ravines or concrete stairs down to the beach.
- Address plate design in Yuzhne: colours, size, height, which corner, and whether one or both street-facing corners have one. The defaults are white on dark blue, 60 × 40 cm, 3 m up (`Config.Map.Plate`).
- OSM coverage: how many buildings have `building:levels` and `addr:*`, and whether entrances are mapped. The converter prints these numbers; anything missing is best fixed directly in OSM.
- Stairwells in Yuzhne: number of flats per landing, which side the lift is on, whether there's a garbage chute, wall colours, and whether there are ground-floor flats or a raised ground floor.
- Where the real ЖЕК / housing office and key-cutting kiosks are (the spawn service point is temporary).
- Which intercom brand is on which entrance (`Config.Entrances.BrandOverrides`).
- Flat layouts in Yuzhne's panel series: room sizes, combined or separate bathroom, glazed or open balconies, and flats per floor. Please send floor plans or photos.
- Real shop names: these get parody names unless you confirm otherwise.

## 12. Assets and licensing

Every model in this phase is built from primitive Parts in code. Sound ids in `Config.Sounds` and `IntercomBrands.*.Sounds` are empty on purpose: upload your own recordings, or sounds licensed for Roblox, and paste the ids in. Until then the game runs silently.
