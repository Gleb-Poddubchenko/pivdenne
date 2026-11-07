--!strict
-- ToolFactory: builds the Tool instances for equipment, from primitive parts.
-- Convention: each Handle's front (-Z) points forward in the hand.

local ToolFactory = {}

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, props: { [string]: any }?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.Massless = true
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

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
end

local function newTool(id: string, name: string): Tool
	local tool = Instance.new("Tool")
	tool.Name = name
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool:SetAttribute("EquipmentId", id)
	return tool
end

local builders: { [string]: (Tool) -> () } = {
	flashlight = function(tool)
		local handle = part(tool, "Handle", Vector3.new(0.4, 0.4, 1.4), CFrame.new(), Color3.fromRGB(30, 30, 30), { Material = Enum.Material.Metal })
		local lens = part(tool, "Lens", Vector3.new(0.5, 0.5, 0.1), handle.CFrame * CFrame.new(0, 0, -0.72), Color3.fromRGB(220, 220, 200), { Material = Enum.Material.Neon })
		weld(handle, lens)
		local spot = Instance.new("SpotLight")
		spot.Name = "Beam"
		spot.Face = Enum.NormalId.Front
		spot.Range = 45
		spot.Angle = 45
		spot.Brightness = 4
		spot.Enabled = false
		spot.Parent = handle
		tool.Grip = CFrame.new(0, 0, 0.3)
	end,
	phone = function(tool)
		local handle = part(tool, "Handle", Vector3.new(0.4, 0.75, 0.08), CFrame.new(), Color3.fromRGB(25, 25, 30))
		local screen = part(tool, "Screen", Vector3.new(0.34, 0.6, 0.02), handle.CFrame * CFrame.new(0, 0, -0.05), Color3.fromRGB(60, 110, 170), { Material = Enum.Material.Neon })
		weld(handle, screen)
	end,
	umbrella = function(tool)
		local handle = part(tool, "Handle", Vector3.new(0.2, 0.9, 0.2), CFrame.new(), Color3.fromRGB(70, 45, 30), { Material = Enum.Material.Wood })
		local shaft = part(tool, "Shaft", Vector3.new(0.12, 4.2, 0.12), handle.CFrame * CFrame.new(0, 2.5, 0), Color3.fromRGB(40, 40, 40), { Material = Enum.Material.Metal })
		local canopy = part(tool, "Canopy", Vector3.new(0.3, 7, 7), handle.CFrame * CFrame.new(0, 4.6, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(150, 25, 35), {
			Shape = Enum.PartType.Cylinder,
			Material = Enum.Material.Fabric,
			Transparency = 1, -- closed
		})
		weld(handle, shaft)
		weld(handle, canopy)
		tool:SetAttribute("Open", false)
	end,
	fishingrod = function(tool)
		local handle = part(tool, "Handle", Vector3.new(0.25, 0.25, 1.4), CFrame.new(), Color3.fromRGB(60, 40, 25), { Material = Enum.Material.Wood })
		-- rod rises forward and up from the hand
		local rodCF = handle.CFrame * CFrame.new(0, 2.2, -3.6) * CFrame.Angles(math.rad(32), 0, 0)
		local rod = part(tool, "Rod", Vector3.new(0.1, 0.1, 8), rodCF, Color3.fromRGB(30, 30, 30), { Material = Enum.Material.Metal })
		weld(handle, rod)
		local tip = Instance.new("Attachment")
		tip.Name = "Tip"
		tip.Position = Vector3.new(0, 0, -4)
		tip.Parent = rod
		tool.Grip = CFrame.new(0, 0, 0.4)
	end,
}

-- Returns nil for passive equipment (no tool).
function ToolFactory.Build(id: string, name: string): Tool?
	local build = builders[id]
	if not build then
		return nil
	end
	local tool = newTool(id, name)
	build(tool)
	return tool
end

-- Visible backpack strapped to the character's back.
function ToolFactory.AttachBackpack(character: Model)
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if not (torso and torso:IsA("BasePart")) or character:FindFirstChild("EquipmentBackpack") then
		return
	end
	local bag = part(character, "EquipmentBackpack", Vector3.new(1.6, 1.8, 0.7), torso.CFrame * CFrame.new(0, 0, torso.Size.Z / 2 + 0.35), Color3.fromRGB(70, 90, 60), {
		Material = Enum.Material.Fabric,
		CanQuery = false,
		CanTouch = false,
	})
	weld(torso, bag)
end

return ToolFactory
