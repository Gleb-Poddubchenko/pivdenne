--!strict
-- DoorService: heavy metal entrance doors with maglock + door closer.
--
-- Sequence on Unlock: maglock clack -> door swings open (outward) -> held open ->
-- closer pulls it shut -> slam -> locked. Unlocking again while open/closing
-- re-opens it. All motion is a single TweenService tween on the anchored Hinge
-- part; every other door part is welded to it, so clients interpolate smoothly
-- and the server runs no per-frame code.

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local EntranceRegistry = require(script.Parent.EntranceRegistry)
local Sfx = require(script.Parent.Parent.Util.Sfx)
local Validation = require(script.Parent.Parent.Util.Validation)

type Entrance = EntranceRegistry.Entrance
export type DoorStateName = "Locked" | "Opening" | "Open" | "Closing"

type DoorState = {
	Entrance: Entrance,
	HingeClosed: CFrame,
	Parts: { BasePart },
	State: DoorStateName,
	Gen: number, -- incremented on each Unlock; stale sequences abort
}

local DoorService = {}
local doors: { [string]: DoorState } = {}

local function setState(door: DoorState, state: DoorStateName)
	door.State = state
	door.Entrance.Model:SetAttribute("DoorState", state)
end

local function setCollide(door: DoorState, collide: boolean)
	-- No collision while moving, so the leaf never shoves or flings players.
	for _, part in door.Parts do
		part.CanCollide = collide
	end
end

local function swing(door: DoorState, angle: number, duration: number, style: Enum.EasingStyle): Tween
	local goal = door.HingeClosed * CFrame.Angles(0, math.rad(angle), 0)
	local tween = TweenService:Create(
		door.Entrance.Hinge,
		TweenInfo.new(duration, style, Enum.EasingDirection.Out),
		{ CFrame = goal }
	)
	tween:Play()
	return tween
end

local function prepare(entrance: Entrance)
	local hinge = entrance.Hinge
	hinge.Anchored = true
	hinge.CanCollide = false
	hinge.Transparency = 1

	local parts: { BasePart } = {}
	for _, d in entrance.Door:GetDescendants() do
		if d:IsA("BasePart") and d ~= hinge then
			if not d:FindFirstChild("DoorWeld") then
				local weld = Instance.new("WeldConstraint")
				weld.Name = "DoorWeld"
				weld.Part0 = hinge
				weld.Part1 = d
				weld.Parent = d
			end
			d.Anchored = false
			d.Massless = true
			table.insert(parts, d)
		end
	end

	local door: DoorState = {
		Entrance = entrance,
		HingeClosed = hinge.CFrame,
		Parts = parts,
		State = "Locked",
		Gen = 0,
	}
	doors[entrance.Id] = door
	setState(door, "Locked")

	-- Inside "ВИХІД" button: anyone inside may leave without a key.
	local button = entrance.ExitButton
	if button then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "ExitPrompt"
		prompt.ActionText = "Вихід"
		prompt.ObjectText = "Кнопка виходу"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 7
		prompt.RequiresLineOfSight = false
		prompt:SetAttribute("Action", "Exit")
		prompt.Parent = button
		prompt.Triggered:Connect(function(player: Player)
			if Validation.IsNear(player, button, Config.InteractDistance) then
				DoorService.Unlock(entrance.Id, "exit")
			end
		end)
	end
end

-- Server-only. Callers are responsible for having validated access.
function DoorService.Unlock(entranceId: string, reason: string)
	local door = doors[entranceId]
	if not door then
		return
	end
	door.Gen += 1
	local gen = door.Gen
	local entrance = door.Entrance
	local cfg = Config.Door

	task.spawn(function()
		if door.State == "Locked" then
			Sfx.Play(entrance.Hinge, Config.Sounds.DoorRelease, 0.8)
			task.wait(cfg.ReleaseDelay)
			if gen ~= door.Gen then
				return
			end
			Sfx.Play(entrance.Hinge, Config.Sounds.DoorCreak, 0.5)
		end

		setState(door, "Opening")
		setCollide(door, false)
		swing(door, cfg.OpenAngle, cfg.OpenDuration, Enum.EasingStyle.Quad).Completed:Wait()
		if gen ~= door.Gen then
			return
		end

		setState(door, "Open")
		setCollide(door, true)
		task.wait(cfg.HoldOpenTime)
		if gen ~= door.Gen then
			return
		end

		setState(door, "Closing")
		setCollide(door, false)
		swing(door, 0, cfg.CloseDuration, Enum.EasingStyle.Sine).Completed:Wait()
		if gen ~= door.Gen then
			return
		end

		setCollide(door, true)
		Sfx.Play(entrance.Hinge, Config.Sounds.DoorSlam, 0.9)
		setState(door, "Locked")
	end)
end

function DoorService.GetState(entranceId: string): DoorStateName?
	local door = doors[entranceId]
	return if door then door.State else nil
end

function DoorService.Init()
	for _, entrance in EntranceRegistry.All() do
		prepare(entrance)
	end
	EntranceRegistry.EntranceAdded:Connect(prepare)
end

return DoorService
