--!strict
-- EntranceBuilder: the outside of a working city entrance (під'їзд), placed on
-- the building wall at the real OSM entrance node. It follows the Entrance model
-- contract (EntranceRegistry / DoorService / IntercomService) and adds:
--   * "Doorway": an invisible trigger in front of the door. Stepping into it while
--     the door is open takes you into the instanced stairwell (StairwellService).
--   * a dark recess behind the door, the concrete canopy and step, and the
--     "Під'їзд N · кв. X–Y" plate when OSM has those tags.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Brands = require(Shared:WaitForChild("IntercomBrands"))

local EntrancePlanner = require(script.Parent.EntrancePlanner)

local M = Config.Meters
local DOOR_W, DOOR_H = M(1.0), M(2.1)

local EntranceBuilder = {}

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, props: { [string]: any }?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
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

function EntranceBuilder.Build(parent: Instance, plan: EntrancePlanner.Plan): Model
	local normal = Vector3.new(plan.NX, 0, plan.NZ)
	if normal.Magnitude < 0.5 then
		normal = Vector3.new(0, 0, -1)
	end
	normal = normal.Unit
	local base = Vector3.new(plan.X, (plan :: any).Y or 0, plan.Z) -- Y = ground height at the door
	local cf = CFrame.lookAt(base, base + normal) -- on the wall face, LookVector = outward

	local model = Instance.new("Model")
	model.Name = "Entrance_" .. plan.Id
	model:SetAttribute("EntranceId", plan.Id)
	model:SetAttribute("Brand", plan.Brand)
	model:SetAttribute("AptFrom", plan.AptFrom)
	model:SetAttribute("AptTo", plan.AptTo)
	model:SetAttribute("Floors", plan.Floors)
	model:SetAttribute("PerFloor", plan.PerFloor)
	model:SetAttribute("HasLift", plan.HasLift)
	model:SetAttribute("HasChute", plan.HasChute)
	model:SetAttribute("FlatsSource", plan.FlatsSource)
	model:SetAttribute("Instanced", true) -- interior is an instanced stairwell

	part(model, "Recess", Vector3.new(DOOR_W + 0.2, DOOR_H + 0.1, 0.05), cf * CFrame.new(0, DOOR_H / 2, -0.03), Color3.fromRGB(12, 12, 14), {
		CanCollide = false,
	})
	part(model, "Step", Vector3.new(DOOR_W + M(1.4), 0.3, M(1.2)), cf * CFrame.new(0, 0.15, -M(0.6)), Color3.fromRGB(150, 146, 140), {
		Material = Enum.Material.Concrete,
	})
	part(model, "Canopy", Vector3.new(DOOR_W + M(1.6), M(0.15), M(1.4)), cf * CFrame.new(0, DOOR_H + M(0.5), -M(0.7)), Color3.fromRGB(190, 186, 178), {
		Material = Enum.Material.Concrete,
	})

	-- Door: anchored Hinge + leaf + handle (DoorService welds and swings it)
	local door = Instance.new("Model")
	door.Name = "Door"
	part(door, "Hinge", Vector3.new(0.2, DOOR_H, 0.2), cf * CFrame.new(-DOOR_W / 2, DOOR_H / 2 + 0.3, -0.15), Color3.new(), {
		Transparency = 1,
		CanCollide = false,
	})
	part(door, "Leaf", Vector3.new(DOOR_W - 0.1, DOOR_H - 0.3, 0.25), cf * CFrame.new(0, DOOR_H / 2 + 0.45, -0.15), Color3.fromRGB(74, 58, 46), {
		Material = Enum.Material.DiamondPlate,
	})
	part(door, "Handle", Vector3.new(0.15, 1.2, 0.25), cf * CFrame.new(DOOR_W / 2 - 0.5, M(1.0) + 0.3, -0.4), Color3.fromRGB(40, 40, 40), {
		Material = Enum.Material.Metal,
		CanCollide = false,
	})
	door.Parent = model

	-- Intercom panel + key reader right of the door, ~1.5 m up
	local brand = Brands[plan.Brand] or Brands.Vizor
	local intercom = Instance.new("Model")
	intercom.Name = "Intercom"
	local px = DOOR_W / 2 + M(0.35)
	part(intercom, "Panel", Vector3.new(1.1, 2.2, 0.2), cf * CFrame.new(px, M(1.5) + 0.3, -0.1), brand.PanelColor, {
		Material = Enum.Material.Metal,
	})
	part(intercom, "Reader", Vector3.new(0.12, 0.45, 0.45), cf * CFrame.new(px, M(1.5) - 0.5, -0.26) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(30, 30, 30), {
		Shape = Enum.PartType.Cylinder,
		Material = Enum.Material.Metal,
	})
	intercom.Parent = model

	part(model, "Doorway", Vector3.new(DOOR_W, DOOR_H, 1.2), cf * CFrame.new(0, DOOR_H / 2 + 0.3, -0.9), Color3.new(), {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
	})

	-- Entrance plate only with real OSM data (ref / addr:flats)
	local text = ""
	if plan.Ref ~= "" then
		text = "Під'їзд " .. plan.Ref
	end
	if plan.FlatsText ~= "" then
		text ..= (if text ~= "" then "\n" else "") .. "кв. " .. plan.FlatsText
	end
	if text ~= "" then
		local plate = part(model, "EntrancePlate", Vector3.new(M(0.5), M(0.3), 0.08), cf * CFrame.new(0, DOOR_H + M(0.25), -0.05), Color3.fromRGB(18, 58, 140), {
			CanCollide = false,
		})
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.MaxDistance = 80
		gui.Parent = plate
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextScaled = true
		label.Font = Enum.Font.GothamBold
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Text = text
		label.Parent = gui
	end

	model.Parent = parent
	CollectionService:AddTag(model, "Entrance")
	return model
end

return EntranceBuilder
