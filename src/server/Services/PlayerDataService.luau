--!strict
-- PlayerDataService: loads and saves player data with session locking.
--
-- Session lock: each record stores { JobId, Time }. A server only loads a record
-- if it is unlocked, locked by itself, or the lock is stale (older than
-- Config.Data.LockStaleAfter, i.e. the owning server crashed). Autosave refreshes
-- the lock; leaving the game releases it. If another server steals the lock, this
-- server stops saving and kicks the player, so data can never be duplicated.
--
-- Other services MUST mutate data through PlayerDataService.Update so the client
-- snapshot stays in sync.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Types = require(Shared:WaitForChild("Types"))
local Net = require(Shared:WaitForChild("Net"))

type PlayerData = Types.PlayerData
type Lock = { JobId: string, Time: number }
type Record = { Data: PlayerData, Lock: Lock? }

type Profile = {
	Player: Player,
	Key: string,
	Data: PlayerData,
	Persistent: boolean, -- false = in-memory only (Studio without API access)
	Released: boolean,
}

local PlayerDataService = {}

local loadedEvent = Instance.new("BindableEvent")
local releasingEvent = Instance.new("BindableEvent")
PlayerDataService.ProfileLoaded = loadedEvent.Event -- (player: Player)
PlayerDataService.ProfileReleasing = releasingEvent.Event -- (player: Player)

local profiles: { [Player]: Profile } = {}
local pendingReleases = 0

-- game.JobId is "" in Studio; give each Studio session its own id.
local jobId = if game.JobId ~= "" then game.JobId else ("studio-" .. tostring(math.random(1, 2 ^ 30)))

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.Data.StoreName)
	end)
	if ok then
		store = result
	else
		warn("[PlayerData] DataStore unavailable:", result)
	end
end

local function template(): PlayerData
	return {
		Version = Config.Data.SchemaVersion,
		Money = Config.StartingMoney,
		Keys = {},
		Apartments = {},
		Cars = {},
		Inventory = {},
		Storage = {},
	}
end

local function deepCopy(value: any): any
	if typeof(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value do
		out[k] = deepCopy(v)
	end
	return out
end

-- Fill in fields added to the template after the record was first saved.
local function reconcile(target: { [any]: any }, source: { [any]: any })
	for k, v in source do
		if target[k] == nil then
			target[k] = deepCopy(v)
		end
	end
end

local function migrate(data: PlayerData): PlayerData
	local version = data.Version or 1
	reconcile(data :: any, template() :: any)
	if version < 2 then
		-- v1 had a placeholder Inventory array; v2 uses itemId -> count.
		data.Inventory = {}
		data.Storage = {}
	end
	data.Version = Config.Data.SchemaVersion
	return data
end

local function backoff(attempt: number)
	task.wait(math.min(Config.Data.RetryBaseDelay * 2 ^ (attempt - 1), Config.Data.RetryMaxDelay))
end

local function snapshot(data: PlayerData): Types.Snapshot
	local keys = {}
	for _, key in data.Keys do
		table.insert(keys, key)
	end
	table.sort(keys, function(a, b)
		if a.CreatedAt == b.CreatedAt then
			return a.Id < b.Id
		end
		return a.CreatedAt < b.CreatedAt
	end)
	local storage = {}
	for aptKey, items in data.Storage do
		storage[aptKey] = table.clone(items)
	end
	return {
		Money = data.Money,
		Keys = keys,
		Apartments = table.clone(data.Apartments),
		Inventory = table.clone(data.Inventory),
		Storage = storage,
		Cars = table.clone(data.Cars),
	}
end

local function sync(profile: Profile)
	if profile.Player.Parent then
		Net.Event("DataSync"):FireClient(profile.Player, snapshot(profile.Data))
	end
end

local function memoryProfile(player: Player, key: string): Profile
	warn("[PlayerData] Using in-memory data for", player.Name, "(enable Studio Access to API Services to test saving)")
	return { Player = player, Key = key, Data = template(), Persistent = false, Released = false }
end

local function loadProfile(player: Player): Profile?
	local key = "player_" .. player.UserId
	local ds = store
	if ds == nil then
		return if RunService:IsStudio() then memoryProfile(player, key) else nil
	end

	for attempt = 1, Config.Data.LoadAttempts do
		local acquired = false
		local loaded: PlayerData? = nil

		local ok, err = pcall(function()
			ds:UpdateAsync(key, function(old: Record?): Record?
				acquired = false
				local record: Record = old or { Data = template() }
				local lock = record.Lock
				if lock and lock.JobId ~= jobId and os.time() - lock.Time < Config.Data.LockStaleAfter then
					return nil -- locked by another live server: cancel write
				end
				record.Lock = { JobId = jobId, Time = os.time() }
				acquired = true
				loaded = record.Data
				return record
			end)
		end)

		if ok and acquired and loaded then
			return {
				Player = player,
				Key = key,
				Data = migrate(loaded),
				Persistent = true,
				Released = false,
			}
		end

		if not ok then
			warn(("[PlayerData] Load %s failed (attempt %d): %s"):format(key, attempt, tostring(err)))
			if RunService:IsStudio() then
				return memoryProfile(player, key)
			end
		else
			warn(("[PlayerData] %s is locked by another server (attempt %d)"):format(key, attempt))
		end

		if player.Parent == nil then
			return nil
		end
		backoff(attempt)
	end
	return nil
end

local function saveProfile(profile: Profile, release: boolean)
	if not profile.Persistent then
		return
	end
	local ds = store :: DataStore
	local lost = false

	for attempt = 1, Config.Data.SaveAttempts do
		local ok, err = pcall(function()
			ds:UpdateAsync(profile.Key, function(old: Record?): Record?
				lost = false
				-- An autosave queued behind the release must not re-lock the record.
				if profile.Released and not release then
					return nil
				end
				if old and old.Lock and old.Lock.JobId ~= jobId then
					lost = true -- another server owns this session now
					return nil
				end
				return {
					Data = profile.Data,
					Lock = if release then nil else { JobId = jobId, Time = os.time() },
				}
			end)
		end)
		if ok then
			break
		end
		warn(("[PlayerData] Save %s failed (attempt %d): %s"):format(profile.Key, attempt, tostring(err)))
		if attempt < Config.Data.SaveAttempts then
			backoff(attempt)
		end
	end

	if lost and not profile.Released then
		profile.Released = true
		profiles[profile.Player] = nil
		profile.Player:Kick("Ваш профіль відкрито на іншому сервері. Перезайдіть у гру.")
	end
end

local function releaseProfile(profile: Profile)
	if profile.Released then
		return
	end
	releasingEvent:Fire(profile.Player)
	profile.Released = true
	pendingReleases += 1
	saveProfile(profile, true)
	pendingReleases -= 1
	if profiles[profile.Player] == profile then
		profiles[profile.Player] = nil
	end
end

local function onPlayerAdded(player: Player)
	local profile = loadProfile(player)
	if not profile then
		if player.Parent then
			player:Kick("Не вдалося завантажити ваші дані. Спробуйте зайти ще раз за хвилину.")
		end
		return
	end
	if player.Parent == nil then
		-- Left while loading: give the lock back immediately.
		saveProfile(profile, true)
		return
	end
	profiles[player] = profile
	sync(profile)
	loadedEvent:Fire(player)
end

-- PUBLIC API -----------------------------------------------------------------

-- Read-only view. Mutate only through Update().
function PlayerDataService.Get(player: Player): PlayerData?
	local profile = profiles[player]
	if profile and not profile.Released then
		return profile.Data
	end
	return nil
end

function PlayerDataService.IsLoaded(player: Player): boolean
	return PlayerDataService.Get(player) ~= nil
end

function PlayerDataService.GetLoadedPlayers(): { Player }
	local list = {}
	for player, profile in profiles do
		if not profile.Released then
			table.insert(list, player)
		end
	end
	return list
end

-- Runs mutator synchronously (must not yield), then syncs the client.
function PlayerDataService.Update(player: Player, mutator: (PlayerData) -> ()): boolean
	local profile = profiles[player]
	if not profile or profile.Released then
		return false
	end
	mutator(profile.Data)
	sync(profile)
	return true
end

function PlayerDataService.TrySpend(player: Player, amount: number): boolean
	assert(amount >= 0, "negative spend")
	local data = PlayerDataService.Get(player)
	if not data or data.Money < amount then
		return false
	end
	return PlayerDataService.Update(player, function(d)
		d.Money -= amount
	end)
end

function PlayerDataService.AddMoney(player: Player, amount: number): boolean
	assert(amount >= 0, "negative add")
	return PlayerDataService.Update(player, function(d)
		d.Money += amount
	end)
end

function PlayerDataService.Init()
	Net.Function("GetSnapshot").OnServerInvoke = function(player: Player)
		local profile = profiles[player]
		return if profile and not profile.Released then snapshot(profile.Data) else nil
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		local profile = profiles[player]
		if profile then
			releaseProfile(profile)
		end
	end)

	-- Autosave, staggered across the interval so we stay inside DataStore budgets.
	task.spawn(function()
		while true do
			task.wait(Config.Data.AutosaveInterval)
			local list = PlayerDataService.GetLoadedPlayers()
			local gap = Config.Data.AutosaveInterval / math.max(#list, 1) * 0.5
			for _, player in list do
				local profile = profiles[player]
				if profile and not profile.Released then
					task.spawn(saveProfile, profile, false)
				end
				task.wait(gap)
			end
		end
	end)

	game:BindToClose(function()
		for _, profile in profiles do
			task.spawn(releaseProfile, profile)
		end
		local deadline = os.clock() + 25
		task.wait() -- let releases start
		while pendingReleases > 0 and os.clock() < deadline do
			task.wait(0.25)
		end
	end)
end

return PlayerDataService
