--!strict
-- TestApartmentBuilder (DEV ONLY): puts four ground-floor flat doors on the back
-- wall of each test lobby (test-a/1: flats 1–4, test-a/2: flats 37–40).
-- Also the reference layout for the ApartmentDoor model contract.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local M = Config.Meters

local TestApartmentBuilder = {}

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, props: { [string]: any }?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props then
		for k, v in props do
			(p :: any)[k] = v
		end
	end
	p.Parent = parent
	return p
end

-- cf: on the wall surface at floor level, centre of the door, LookVector = stairwell.
function TestApartmentBuilder.BuildDoor(parent: Instance, cf: CFrame, entranceId: string, apt: number): Model
	local model = Instance.new("Model")
	model.Name = ("FlatDoor_%s#%d"):format(entranceId, apt)
	model:SetAttribute("EntranceId", entranceId)
	model:SetAttribute("Apt", apt)

	local w, h = M(0.9), M(2.05)
	part(model, "Frame", Vector3.new(w + 0.4, h + 0.2, 0.2), cf * CFrame.new(0, (h + 0.2) / 2, -0.1), {
		Color = Color3.fromRGB(120, 110, 95),
	})
	part(model, "Door", Vector3.new(w, h, 0.25), cf * CFrame.new(0, h / 2, -0.32), {
		Material = Enum.Material.Leather, -- dermantin
		Color = Color3.fromRGB(95, 40, 34),
	})
	part(model, "Handle", Vector3.new(0.15, 0.6, 0.15), cf * CFrame.new(w / 2 - 0.45, M(1.0), -0.52), {
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(200, 170, 90),
		CanCollide = false,
	})
	part(model, "Peephole", Vector3.new(0.1, 0.18, 0.18), cf * CFrame.new(0, M(1.55), -0.47) * CFrame.Angles(0, math.pi / 2, 0), {
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(200, 170, 90),
		CanCollide = false,
	})
	part(model, "Bell", Vector3.new(0.3, 0.3, 0.1), cf * CFrame.new(w / 2 + 0.6, M(1.5), -0.05), {
		Color = Color3.fromRGB(232, 226, 210),
	})
	local plate = part(model, "NumberPlate", Vector3.new(0.9, 0.5, 0.05), cf * CFrame.new(0, M(1.8), -0.47), {
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(190, 160, 80),
		CanCollide = false,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.Parent = plate
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.fromRGB(40, 30, 20)
	label.Text = tostring(apt)
	label.Parent = gui

	model.Parent = parent
	CollectionService:AddTag(model, "ApartmentDoor")
	return model
end

function TestApartmentBuilder.Build()
	local scene = workspace:FindFirstChild("TestScene")
	local block = scene and scene:FindFirstChild("Block_test-a")
	if not block or block:FindFirstChild("FlatDoors") then
		return
	end
	local holder = Instance.new("Folder")
	holder.Name = "FlatDoors"

	for _, spec in { { id = "test-a/1", first = 1 }, { id = "test-a/2", first = 37 } } do
		local entrance = block:FindFirstChild("Entrance_" .. spec.id)
		local back = entrance and entrance:FindFirstChild("LobbyBack")
		if back and back:IsA("BasePart") then
			-- Front face of LobbyBack faces the lobby; floor top is 0.1 above ground.
			local surface = back.CFrame * CFrame.new(0, -back.Size.Y / 2 + 0.1, -back.Size.Z / 2)
			for i, x in { -13, -4.5, 4.5, 13 } do
				TestApartmentBuilder.BuildDoor(holder, surface * CFrame.new(x, 0, 0), spec.id, spec.first + i - 1)
			end
		end
	end
	holder.Parent = block
end

return TestApartmentBuilder
