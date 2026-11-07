--!strict
-- NightLightsController: at night, switches on the street lamps and lights up a
-- random (but stable) share of apartment windows — only near the player, every
-- 2 s, so hundreds of lights never run at once. Purely local/cosmetic.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local NightLightsController = {}

local WINDOW_DAY = Color3.fromRGB(70, 86, 100)
local WINDOW_WARM = { Color3.fromRGB(255, 214, 150), Color3.fromRGB(255, 236, 190), Color3.fromRGB(230, 240, 255) }

local function isNight(): boolean
	local t = Lighting.ClockTime
	return t >= Config.Time.NightStart or t < Config.Time.NightEnd
end

local function stableRandom(part: BasePart): number
	local p = part.Position
	return math.floor(math.abs(p.X * 12.9898 + p.Y * 4.1414 + p.Z * 78.233) * 43758.5453) % 1000
end

function NightLightsController.Init()
	task.spawn(function()
		while true do
			task.wait(2)
			local night = isNight()
			local camPos = workspace.CurrentCamera.CFrame.Position
			local range = Config.Time.LightDistance

			for _, head in CollectionService:GetTagged("StreetLamp") do
				if head:IsA("BasePart") then
					local light = head:FindFirstChildWhichIsA("Light")
					if light then
						local on = night and (head.Position - camPos).Magnitude < range
						if light.Enabled ~= on then
							light.Enabled = on
							head.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
						end
					end
				end
			end

			for _, band in CollectionService:GetTagged("WindowBand") do
				if band:IsA("BasePart") then
					local lit = night and (band.Position - camPos).Magnitude < range * 1.5 and stableRandom(band) < 450
					local isLit = band:GetAttribute("Lit") == true
					if lit ~= isLit then
						band:SetAttribute("Lit", lit)
						if lit then
							band.Material = Enum.Material.Neon
							band.Color = WINDOW_WARM[stableRandom(band) % #WINDOW_WARM + 1]:Lerp(Color3.new(0, 0, 0), 0.35)
						else
							band.Material = Enum.Material.Glass
							band.Color = WINDOW_DAY
						end
					end
				end
			end
		end
	end)
end

return NightLightsController
