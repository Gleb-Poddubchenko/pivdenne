# Yuzhne / Pivdenne (Південне): Roblox open-world replica

Phase 1 sets up the foundation: data persistence, entrances, entrance doors, intercoms, keys, flat ownership, plus a test block you can play straight away.

## 1. Folder tree and where each script goes

```
default.project.json                      Rojo project (also turns on StreamingEnabled)
src/shared/      -> ReplicatedStorage.Shared          (ModuleScripts)
  Config.luau            scale (1 m = 3.5 studs), prices, timings, sound ids
  Types.luau             shared type definitions
  Net.luau               the ONLY place remotes are declared
  IntercomBrands.luau    VIZOR (Vizit-style) / METRON (Metacom-style) look and behaviour
  Items.luau             every item (food, household, pharmacy) with prices and use effects
  ShopCatalogs.luau      what each kind of shop sells (Grocery, Kiosk, Pharmacy)
  Vehicles.luau          car models (specs, prices) and Soviet-era paint colours
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
  Util/                  RateLimiter, Validation, Sfx
  Dev/TestSceneBuilder   test 9-storey block (turn off with Config.Dev.BuildTestScene)
  Dev/TestElevatorBuilder test 9-stop lift tower with landings and a climbable ladder
  Dev/TestApartmentBuilder flat doors in the test lobbies (flats 1–4 and 37–40)
  Dev/TestShopBuilder    grocery shop, ice-cream kiosk and pharmacy kiosk
  Dev/TestParkingBuilder dealership, parking lot with 4 spots, a long test road
src/client/      -> StarterPlayer.StarterPlayerScripts.Client
  Main.client.luau       LocalScript: bootstrap
  Controllers/           DataController, HudController, KeyRingController,
                         IntercomController, CallController, KioskController,
                         ElevatorController (lift sounds, jolts, flicker, cabin panel UI),
                         InventoryController (bag + fridge), ShopController,
                         ApartmentController (teleport fade, doorbell popup),
                         VehicleController (driving physics, speedometer, horn/lights),
                         GarageController (my cars, dealership)
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

## 8. OSM → Roblox map pipeline (Phase 2)

1. **Export:** Overpass query for the Yuzhne/Pivdenne bounding box: `building=*` (with `building:levels`, `addr:*`), `highway=*`, `landuse`, `leisure`, `amenity`, `shop`. Save it as `.osm`/GeoJSON.
2. **Project:** use a local tangent plane (ENU) centred on one fixed origin point near the city centre: metres east → +X, metres north → −Z, then multiply by **3.5** (1 m = 3.5 studs). A ~6 × 4 km city fits within ±11 000 studs, which is fine for float precision.
3. **Convert**, either way:
   - **(A) Script route (recommended):** a Python converter turns footprints into JSON chunks (ModuleScripts per 512-stud grid cell). A Studio plugin builds walls along each polygon edge, roofs (triangulated with WedgeParts), and `floors = building:levels` at 2.8 m per floor. Each footprint is matched to a typology template (5-storey / 9-storey / 12–16-storey panel blocks) that holds the instanced interiors and entrances.
   - **(B) Blender route:** blender-osm / "Blosm" add-on → clean up → export FBX per chunk → 3D Importer in Studio.
4. **Streaming/LOD:** one Model per building, `ModelStreamingMode = Atomic` for entrances and `Persistent` only for landmarks. Use low-poly façade MeshParts with `RenderFidelity = Automatic`. Interiors are separate Models that stream in only near the entrance.
5. **Attribution:** "Map data © OpenStreetMap contributors" is on the HUD at all times (ODbL). Add the same text to the game description, and say that the derived map database is ODbL.

## 9. Roadmap

- **Phase 1 (done):** data, entrances, doors, intercoms, keys, flats, kiosks.
- **Phase 2 (next):** OSM converter and building typology templates (5/9/14-storey), courtyards (playgrounds, benches, garages), stairwells, garbage chutes, mailboxes. The 9-storey template will put an `Elevator` model in each stairwell and `ApartmentDoor`s on every landing.
- **Phase 3 (done):** Soviet elevator system.
- **Phase 4 (done):** apartments (instanced interiors, doorbell, fridge) and shops (catalogues, tills, inventory). Next: a "2k" layout, furniture you can buy and place, a way to earn money (jobs), and shop opening hours with a day/night cycle.
- **Phase 5 (done):** vehicles. Next: fuel and petrol stations, garages in courtyards (tag `CarSpawn` inside a garage), traffic/NPC cars, damage.
- **Phase 6:** equipment.
- Intercom voice: wire `AudioDeviceInput → AudioEmitter` on the panel and the handset (Roblox's new Audio API) for players who have voice chat. Text chat stays as the fallback.

## 10. NEEDS VERIFICATION (please send photos / Street View)

- Exact panel layouts and colours of the Vizit and Metacom models actually fitted in Yuzhne: display type (LED or LCD), position of the call key, reader shape, and whether the entrance door has a visible maglock.
- Which key type each building uses (TM tablet or RFID fob), and whether any panels accept both.
- Dialling behaviour on the real panels: auto-dial delay, whether a "B"/bell key is pressed after the number, and the confirmation beep patterns.
- Flat-numbering scheme per entrance (flats per floor: 4 on 9-storey blocks? 3 on some 5-storey ones?).
- Entrance door style: brown or green steel, the canopy shape, and whether there are steps or a ramp.
- Origin coordinates for the map projection, and the positions of landmarks: central square(s), the seaside promenade and beach access, the port and plant area, schools, markets, the bus station, main shops.
- Lifts in Yuzhne: which plant made them (Karacharovo/KMZ, Mogilev/MOGILEVLIFTMASH, Shcherbinka?), and whether 1980s blocks have **automatic sliding shaft doors** rather than the hinged ones you asked for. Hinged manual shaft doors are typical of older lifts. Also the cabin size, the panel layout (one or two button columns, СТОП/ВИКЛИК labels in Russian or Ukrainian), the wall finish, and whether a lift stops at every floor or only at half-landings.
- Flat layouts in Yuzhne's panel series: room sizes, combined or separate bathroom, glazed or open balconies, and flats per floor. Please send floor plans or photos.
- Real shop names: these get parody names unless you confirm otherwise.

## 11. Assets and licensing

Every model in this phase is built from primitive Parts in code. Sound ids in `Config.Sounds` and `IntercomBrands.*.Sounds` are empty on purpose: upload your own recordings, or sounds licensed for Roblox, and paste the ids in. Until then the game runs silently.
