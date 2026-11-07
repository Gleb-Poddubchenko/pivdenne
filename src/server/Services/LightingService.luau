--!strict
-- LightingService: day/night cycle with the real sun path over Pivdenne
-- (GeographicLatitude 46.62°N) and a hazy, sea-side southern atmosphere.
-- Advances the clock once a second (cheap; Lighting replicates on its own).
-- For the best look also set Lighting.Technology = Future in Studio
-- (it can't be changed from a script).

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local LightingService = {}

local function ensure(className: string, name: string): Instance
	local existing = Lighting:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	local inst = Instance.new(className :: any)
	inst.Name = name
	inst.Parent = Lighting
	return inst
end

function LightingService.Init()
	local cfg = Config.Time
	Lighting.GeographicLatitude = cfg.Latitude
	Lighting.ClockTime = cfg.StartClock
	-- Bright, readable daylight. Ambient was 0 before, which made every shaded
	-- side (and anything under the city) almost black.
	Lighting.Brightness = 3
	Lighting.ExposureCompensation = 0.25
	Lighting.Ambient = Color3.fromRGB(110, 110, 118)
	Lighting.OutdoorAmbient = Color3.fromRGB(165, 165, 172)
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
	Lighting.GlobalShadows = true
	Lighting.FogEnd = 100000

	local atmosphere = ensure("Atmosphere", "SeaHaze") :: Atmosphere
	atmosphere.Density = 0.2 -- light sea haze (0.3+ swallowed the far city)
	atmosphere.Offset = 0
	atmosphere.Haze = 0.5
	atmosphere.Glare = 0.2
	atmosphere.Color = Color3.fromRGB(205, 210, 215)
	atmosphere.Decay = Color3.fromRGB(190, 200, 215)

	local bloom = ensure("BloomEffect", "Bloom") :: BloomEffect
	bloom.Intensity = 0.4
	bloom.Size = 20
	bloom.Threshold = 1.6

	local grade = ensure("ColorCorrectionEffect", "SouthernSun") :: ColorCorrectionEffect
	grade.Saturation = 0.05
	grade.Contrast = 0.05
	grade.TintColor = Color3.fromRGB(255, 250, 240)

	if not cfg.Cycle then
		return -- clock stays at Config.Time.StartClock (daylight)
	end
	-- 24 in-game hours per Config.Time.DayLengthMinutes real minutes.
	local hoursPerSecond = 24 / (cfg.DayLengthMinutes * 60)
	task.spawn(function()
		while true do
			task.wait(1)
			Lighting.ClockTime = (Lighting.ClockTime + hoursPerSecond) % 24
		end
	end)
end

return LightingService
