--!strict
-- AddressPlates: the street-name + house-number plate (адресна табличка) mounted
-- on a building wall. Street names and numbers come only from OSM data
-- (addr:street / addr:housenumber); nothing is invented here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local M = Config.Meters

local AddressPlates = {}

-- position: point on the wall's outer face (y = ground); normal: outward unit vector.
function AddressPlates.Create(parent: Instance, position: Vector3, normal: Vector3, street: string, number: string, buildingHeight: number): Part
	local style = Config.Map.Plate
	local elevation = math.min(M(style.Elevation), buildingHeight * 0.7)
	local center = position + Vector3.new(0, elevation, 0) + normal * 0.08
	local plate = Instance.new("Part")
	plate.Name = "AddressPlate"
	plate.Anchored = true
	plate.CanCollide = false
	plate.CanQuery = false
	plate.CastShadow = false
	plate.Size = Vector3.new(M(style.Width), M(style.Height), 0.1)
	plate.CFrame = CFrame.lookAt(center, center + normal) -- Front face looks out from the wall
	plate.Color = style.Background
	plate.Material = Enum.Material.SmoothPlastic
	plate:SetAttribute("Street", street)
	plate:SetAttribute("HouseNumber", number)

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 0.3
	gui.MaxDistance = 120 -- text only renders up close (performance)
	gui.Parent = plate

	local border = Instance.new("UIStroke")
	border.Color = style.TextColor
	border.Thickness = 3
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, -8, 1, -8)
	frame.Position = UDim2.fromOffset(4, 4)
	frame.BackgroundTransparency = 1
	frame.Parent = gui
	border.Parent = frame

	local streetLabel = Instance.new("TextLabel")
	streetLabel.Size = UDim2.new(0.92, 0, 0.38, 0)
	streetLabel.Position = UDim2.fromScale(0.04, 0.06)
	streetLabel.BackgroundTransparency = 1
	streetLabel.TextScaled = true
	streetLabel.Font = Enum.Font.GothamMedium
	streetLabel.TextColor3 = style.TextColor
	streetLabel.Text = street
	streetLabel.Parent = frame

	local numberLabel = Instance.new("TextLabel")
	numberLabel.Size = UDim2.new(0.92, 0, 0.5, 0)
	numberLabel.Position = UDim2.fromScale(0.04, 0.46)
	numberLabel.BackgroundTransparency = 1
	numberLabel.TextScaled = true
	numberLabel.Font = Enum.Font.GothamBlack
	numberLabel.TextColor3 = style.TextColor
	numberLabel.Text = number
	numberLabel.Parent = frame

	plate.Parent = parent
	return plate
end

return AddressPlates
