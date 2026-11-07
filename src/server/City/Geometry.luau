--!strict
-- Geometry: low-level part builders for the generated city.

local Geometry = {}

function Geometry.Part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = size.Y > 1
	p.Parent = parent
	return p
end

-- Any 3D triangle as two WedgeParts (thickness along the triangle normal).
function Geometry.Triangle(parent: Instance, a: Vector3, b: Vector3, c: Vector3, thickness: number, color: Color3, material: Enum.Material?)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	-- make bc the longest edge
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local cross = ac:Cross(ab)
	if cross.Magnitude < 1e-6 or bc.Magnitude < 1e-6 then
		return -- degenerate
	end
	local right = cross.Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))

	local w1 = Instance.new("WedgePart")
	w1.Size = Vector3.new(thickness, height, math.abs(ab:Dot(back)))
	w1.CFrame = CFrame.fromMatrix((a + b) / 2, right, up, back)
	local w2 = Instance.new("WedgePart")
	w2.Size = Vector3.new(thickness, height, math.abs(ac:Dot(back)))
	w2.CFrame = CFrame.fromMatrix((a + c) / 2, -right, up, -back)
	for _, w in { w1, w2 } do
		w.Anchored = true
		w.Color = color
		w.Material = material or Enum.Material.SmoothPlastic
		w.TopSurface = Enum.SurfaceType.Smooth
		w.BottomSurface = Enum.SurfaceType.Smooth
		w.CastShadow = false
		w.Parent = parent
	end
end

-- Flat polygon (already triangulated; 1-based index triples into flat x,z list).
function Geometry.Polygon(parent: Instance, flat: { number }, tri: { number }, y: number, thickness: number, color: Color3, material: Enum.Material?)
	local function v(i: number): Vector3
		return Vector3.new(flat[2 * i - 1], y, flat[2 * i])
	end
	for k = 1, #tri - 2, 3 do
		Geometry.Triangle(parent, v(tri[k]), v(tri[k + 1]), v(tri[k + 2]), thickness, color, material)
	end
end

-- Thick polyline (roads): one box per segment + round joints at inner vertices.
function Geometry.Polyline(parent: Instance, flat: { number }, width: number, y: number, thickness: number, color: Color3, material: Enum.Material?)
	local n = #flat // 2
	for i = 1, n - 1 do
		local a = Vector3.new(flat[2 * i - 1], y, flat[2 * i])
		local b = Vector3.new(flat[2 * i + 1], y, flat[2 * i + 2])
		local len = (b - a).Magnitude
		if len > 0.05 then
			Geometry.Part(parent, "Road", Vector3.new(width, thickness, len), CFrame.lookAt((a + b) / 2, b), color, material)
		end
		if i > 1 then
			local joint = Geometry.Part(parent, "Joint", Vector3.new(thickness, width, width), CFrame.new(a) * CFrame.Angles(0, 0, math.pi / 2), color, material)
			joint.Shape = Enum.PartType.Cylinder
		end
	end
end

return Geometry
