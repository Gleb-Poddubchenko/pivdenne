--!strict
-- VehicleService: buying, spawning and owning cars.
--
-- Server-authoritative rules:
--   * Cars are bought at a "CarDealer" part and stored in PlayerData.Cars.
--   * A car is called to a "CarSpawn" parking spot near the player (one active
--     car per player). Spots are BaseParts tagged CarSpawn; LookVector = car forward.
--   * Only the owner may drive. Passengers may sit only while the car is unlocked.
--   * While someone drives, the car's physics belongs to the driver's client for
--     smooth, lag-free handling; the server checks speed and teleports once a
--     second and takes ownership back from anyone who cheats.

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Types = require(Shared:WaitForChild("Types"))
local Vehicles = require(Shared:WaitForChild("Vehicles"))

local PlayerDataService = require(script.Parent.PlayerDataService)
local CarFactory = require(script.Parent.Parent.Vehicles.CarFactory)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)
local Validation = require(script.Parent.Parent.Util.Validation)
local Sfx = require(script.Parent.Parent.Util.Sfx)

type Active = {
	Owner: Player,
	CarId: string,
	Built: CarFactory.BuiltCar,
	Locked: boolean,
	LightsOn: boolean,
	Strikes: number,
	LastPos: Vector3,
	LastHonk: number,
}

local VehicleService = {}

local active: { [Player]: Active } = {}
local folder: Folder
local notifyEvent: RemoteEvent

local buyLimiter = RateLimiter.new(2, 0.3)
local spawnLimiter = RateLimiter.new(2, 0.2)
local actionLimiter = RateLimiter.new(6, 3)
local seatLimiter = RateLimiter.new(4, 1)

local PLATE_LETTERS = { "A", "B", "C", "E", "H", "I", "K", "M", "O", "P", "T", "X" } -- letters shared by Latin and Cyrillic

local function notify(player: Player, text: string, kind: string?)
	notifyEvent:FireClient(player, text, kind)
end

local function randomPlate(): string
	local function letter(): string
		return PLATE_LETTERS[math.random(1, #PLATE_LETTERS)]
	end
	return ("%s %04d %s%s"):format(Config.Vehicles.RegionCode, math.random(0, 9999), letter(), letter())
end

local function nearTagged(player: Player, tag: string, radius: number): BasePart?
	local root = Validation.GetRoot(player)
	if not root then
		return nil
	end
	local best: BasePart?, bestDist = nil, radius
	for _, inst in CollectionService:GetTagged(tag) do
		if inst:IsA("BasePart") then
			local d = (inst.Position - root.Position).Magnitude
			if d <= bestDist then
				best, bestDist = inst, d
			end
		end
	end
	return best
end

local function findCar(data: Types.PlayerData, carId: string): Types.CarData?
	for _, car in data.Cars do
		if car.Id == carId then
			return car
		end
	end
	return nil
end

local function despawn(player: Player)
	local a = active[player]
	if a then
		active[player] = nil
		a.Built.Model:Destroy()
		player:SetAttribute("ActiveCarId", nil)
	end
end

local function playerFromSeat(seat: BasePart): (Player?, Humanoid?)
	local occupant = (seat :: any).Occupant :: Humanoid?
	if not occupant then
		return nil, nil
	end
	return Players:GetPlayerFromCharacter(occupant.Parent), occupant
end

local function eject(humanoid: Humanoid)
	humanoid.Sit = false
	local seatPart = humanoid.SeatPart
	if seatPart then
		local weld = seatPart:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
	end
end

-- Seat permissions, network ownership and stepping out at the side of the car.
local function wireSeats(a: Active)
	local built = a.Built
	for _, seat in built.Seats do
		local isDriver = seat == built.DriverSeat
		local last: Humanoid? = nil

		seat:GetPropertyChangedSignal("Occupant"):Connect(function()
			local player, humanoid = playerFromSeat(seat)
			if humanoid then
				local allowed = player ~= nil
					and (player == a.Owner or (not isDriver and not a.Locked))
				if not allowed then
					task.defer(eject, humanoid)
					return
				end
				last = humanoid
				if isDriver and player then
					pcall(function()
						built.Chassis:SetNetworkOwner(player)
					end)
					if built.Engine then
						built.Engine:Play()
					end
				end
			else
				if isDriver then
					pcall(function()
						built.Chassis:SetNetworkOwner(nil)
					end)
					if built.Engine then
						built.Engine:Stop()
					end
				end
				local leaving = last
				last = nil
				if leaving then
					-- Put them next to their door instead of inside the bodywork.
					task.defer(function()
						local character = leaving.Parent
						if character and character:IsA("Model") and not leaving.SeatPart and seat.Parent then
							local side = if built.Chassis.CFrame:PointToObjectSpace(seat.Position).X < 0 then -1 else 1
							local exitCF = built.Chassis.CFrame * CFrame.new(side * (built.Width / 2 + 2.5), 2, 0)
							character:PivotTo(CFrame.new(exitCF.Position) * built.Chassis.CFrame.Rotation)
						end
					end)
				end
			end
		end)

		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = if isDriver then "За кермо" else "Сісти"
		prompt.ObjectText = built.Model:GetAttribute("Plate") :: string
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 9
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = if isDriver then Enum.KeyCode.E else Enum.KeyCode.F
		prompt.Parent = seat
		prompt.Triggered:Connect(function(player: Player)
			if not seatLimiter.Check(player) or (seat :: any).Occupant ~= nil then
				return
			end
			if isDriver and player ~= a.Owner then
				notify(player, "Це не ваша машина.", "bad")
				return
			end
			if not isDriver and a.Locked and player ~= a.Owner then
				notify(player, "Машина зачинена.", "bad")
				return
			end
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 and not humanoid.SeatPart and Validation.IsNear(player, seat, 14) then
				(seat :: any):Sit(humanoid)
			end
		end)
	end
end

local function onBuy(player: Player, modelId: any, colorIndex: any): (boolean, string)
	if not buyLimiter.Check(player) then
		return false, "Не так швидко"
	end
	if typeof(modelId) ~= "string" or not Validation.IsInteger(colorIndex, 1, #Vehicles.Colors) then
		return false, "Невірний запит"
	end
	local spec = Vehicles.Models[modelId]
	if not spec then
		return false, "Такої моделі немає"
	end
	if not nearTagged(player, "CarDealer", Config.InteractDistance) then
		return false, "Підійдіть до автосалону"
	end
	local data = PlayerDataService.Get(player)
	if not data then
		return false, "Дані ще не завантажено"
	end
	if #data.Cars >= Config.Vehicles.MaxOwned then
		return false, ("Максимум %d машини"):format(Config.Vehicles.MaxOwned)
	end
	if not PlayerDataService.TrySpend(player, spec.Price) then
		return false, ("Недостатньо грошей (потрібно %s%d)"):format(Config.Currency, spec.Price)
	end
	local plate = randomPlate()
	PlayerDataService.Update(player, function(d)
		table.insert(d.Cars, {
			Id = HttpService:GenerateGUID(false),
			ModelId = modelId,
			ColorIndex = colorIndex,
			Plate = plate,
			BoughtAt = os.time(),
		})
	end)
	return true, ("%s, %s — ваша! Номер %s. Викличте її на парковці."):format(spec.Name, Vehicles.Colors[colorIndex].Name, plate)
end

local function onSpawn(player: Player, carId: any): (boolean, string)
	if not spawnLimiter.Check(player) or typeof(carId) ~= "string" then
		return false, "Не так швидко"
	end
	local data = PlayerDataService.Get(player)
	local car = data and findCar(data, carId)
	if not car then
		return false, "Машину не знайдено"
	end
	local spec = Vehicles.Models[car.ModelId]
	if not spec then
		return false, "Невідома модель"
	end
	local pad = nearTagged(player, "CarSpawn", Config.Vehicles.SpawnRadius)
	if not pad then
		return false, "Підійдіть до парковки або гаража"
	end
	local current = active[player]
	if current and current.Built.Chassis.AssemblyLinearVelocity.Magnitude > 5 then
		return false, "Спершу зупиніть поточну машину"
	end
	for owner, other in active do
		if owner ~= player and (other.Built.Chassis.Position - pad.Position).Magnitude < 10 then
			return false, "Це місце зайняте — підійдіть до іншого"
		end
	end
	despawn(player)

	local paint = Vehicles.Colors[car.ColorIndex] or Vehicles.Colors[1]
	local groundCF = pad.CFrame * CFrame.new(0, -pad.Size.Y / 2, 0)
	local built = CarFactory.Build(spec, paint.Color, car.Plate, CFrame.new(groundCF.Position) * pad.CFrame.Rotation)
	built.Model:SetAttribute("OwnerUserId", player.UserId)
	built.Model:SetAttribute("CarId", car.Id)
	built.Model:SetAttribute("Locked", true)
	built.Model.Parent = folder
	pcall(function()
		built.Chassis:SetNetworkOwner(nil)
	end)

	local a: Active = {
		Owner = player,
		CarId = car.Id,
		Built = built,
		Locked = true,
		LightsOn = false,
		Strikes = 0,
		LastPos = built.Chassis.Position,
		LastHonk = 0,
	}
	active[player] = a
	player:SetAttribute("ActiveCarId", car.Id)
	wireSeats(a)
	return true, ("%s чекає на парковці."):format(spec.Name)
end

local function onAction(player: Player, action: any)
	if not actionLimiter.Check(player) or typeof(action) ~= "string" then
		return
	end
	local a = active[player]
	if not a then
		return
	end
	local built = a.Built
	local driving = built.DriverSeat.Occupant ~= nil and Players:GetPlayerFromCharacter(built.DriverSeat.Occupant.Parent) == player
	if not driving and not Validation.IsNear(player, built.Chassis, Config.Vehicles.ActionDistance) then
		notify(player, "Ви задалеко від машини.", "bad")
		return
	end

	if action == "honk" then
		local now = os.clock()
		if now - a.LastHonk > 0.8 then
			a.LastHonk = now
			Sfx.Play(built.Chassis, Config.Sounds.CarHorn, 0.9)
			built.Model:SetAttribute("HonkAt", now)
		end
	elseif action == "lights" then
		a.LightsOn = not a.LightsOn
		CarFactory.SetLights(built, a.LightsOn)
	elseif action == "lock" then
		a.Locked = not a.Locked
		built.Model:SetAttribute("Locked", a.Locked)
		Sfx.Play(built.Chassis, Config.Sounds.CarLock, 0.6)
		if a.Locked then
			-- Locking from outside: passengers who aren't the owner get out.
			for _, seat in built.Seats do
				local p, humanoid = playerFromSeat(seat)
				if humanoid and p ~= player then
					eject(humanoid)
				end
			end
		end
		notify(player, if a.Locked then "Машину зачинено." else "Машину відчинено.")
	elseif action == "flip" then
		if built.Chassis.CFrame.UpVector.Y < 0.5 and built.Chassis.AssemblyLinearVelocity.Magnitude < 8 then
			local pos = built.Chassis.Position + Vector3.new(0, 4, 0)
			local look = built.Chassis.CFrame.LookVector
			local flat = Vector3.new(look.X, 0, look.Z)
			if flat.Magnitude < 0.1 then
				flat = Vector3.zAxis
			end
			built.Model:PivotTo(CFrame.lookAt(pos, pos + flat.Unit))
			built.Chassis.AssemblyLinearVelocity = Vector3.zero
			built.Chassis.AssemblyAngularVelocity = Vector3.zero
		else
			notify(player, "Машина стоїть на колесах.")
		end
	elseif action == "despawn" then
		if driving then
			notify(player, "Спершу вийдіть з машини.", "bad")
		else
			despawn(player)
			notify(player, "Машину відігнано в гараж.")
		end
	end
end

-- Once a second: speed / teleport sanity check on client-owned cars.
local function patrol()
	while true do
		task.wait(1)
		for owner, a in active do
			local chassis = a.Built.Chassis
			if not chassis.Parent then
				active[owner] = nil
				continue
			end
			local limit = a.Built.TopSpeed * Config.Vehicles.SpeedCheckFactor + 20
			local moved = (chassis.Position - a.LastPos).Magnitude
			a.LastPos = chassis.Position
			local speeding = chassis.AssemblyLinearVelocity.Magnitude > limit or moved > limit * 1.5
			if speeding then
				a.Strikes += 1
				if a.Strikes >= 2 then
					a.Strikes = 0
					pcall(function()
						chassis:SetNetworkOwner(nil)
					end)
					chassis.AssemblyLinearVelocity = Vector3.zero
					warn(("[Vehicles] %s's car exceeded the speed check; ownership reset"):format(owner.Name))
					notify(owner, "Двигун заглух.", "bad")
					-- Give control back after a moment if they are still driving.
					task.delay(2, function()
						local p = playerFromSeat(a.Built.DriverSeat)
						if p == owner and chassis.Parent then
							pcall(function()
								chassis:SetNetworkOwner(owner)
							end)
						end
					end)
				end
			else
				a.Strikes = math.max(a.Strikes - 1, 0)
			end
		end
	end
end

function VehicleService.Init()
	notifyEvent = Net.Event("Notify")
	folder = Instance.new("Folder")
	folder.Name = "Vehicles"
	folder.Parent = workspace

	local function setupDealer(inst: Instance)
		if inst:IsA("BasePart") and not inst:FindFirstChild("DealerPrompt") then
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "DealerPrompt"
			prompt.ActionText = "Купити авто"
			prompt.ObjectText = "Автосалон"
			prompt.HoldDuration = 0
			prompt.MaxActivationDistance = 8
			prompt.RequiresLineOfSight = false
			prompt:SetAttribute("Action", "CarDealer")
			prompt.Parent = inst
		end
	end
	for _, inst in CollectionService:GetTagged("CarDealer") do
		setupDealer(inst)
	end
	CollectionService:GetInstanceAddedSignal("CarDealer"):Connect(setupDealer)

	Net.Function("BuyCar").OnServerInvoke = onBuy
	Net.Function("SpawnCar").OnServerInvoke = onSpawn
	Net.Event("VehicleAction").OnServerEvent:Connect(onAction)

	Players.PlayerRemoving:Connect(despawn)
	task.spawn(patrol)
end

return VehicleService
