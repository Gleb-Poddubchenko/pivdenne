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

-- Splits a triangle into two right-angled wedges: returns (cf1, size1, cf2, size2) or nil.
local function wedgePair(a: Vector3, b: Vector3, c: Vector3, thickness: number): (CFrame?, Vector3?, CFrame?, Vector3?)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local cross = ac:Cross(ab)
	if cross.Magnitude < 1e-6 or bc.Magnitude < 1e-6 then
		return nil, nil, nil, nil
	end
	local right = cross.Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	return CFrame.fromMatrix((a + b) / 2, right, up, back), Vector3.new(thickness, height, math.abs(ab:Dot(back))),
		CFrame.fromMatrix((a + c) / 2, -right, up, -back), Vector3.new(thickness, height, math.abs(ac:Dot(back)))
end

Geometry.WedgePair = wedgePair

-- Fill a flat triangulated polygon with Terrain (e.g. Water), `depth` studs deep below y.
function Geometry.TerrainPolygon(flat: { number }, tri: { number }, y: number, depth: number, material: Enum.Material)
	local terrain = workspace.Terrain
	local function v(i: number): Vector3
		return Vector3.new(flat[2 * i - 1], y - depth / 2, flat[2 * i])
	end
	for k = 1, #tri - 2, 3 do
		local cf1, s1, cf2, s2 = wedgePair(v(tri[k]), v(tri[k + 1]), v(tri[k + 2]), depth)
		if cf1 and s1 and cf2 and s2 then
			terrain:FillWedge(cf1, s1, material)
			terrain:FillWedge(cf2, s2, material)
		end
	end
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

-- Polyline that follows the ground: segments are subdivided every `step` studs and
-- each point is lifted to heightAt(x, z) + yOffset. Optional dashed centre line.
function Geometry.DrapedPolyline(parent: Instance, flat: { number }, width: number, yOffset: number, thickness: number,
	color: Color3, material: Enum.Material?, heightAt: (number, number) -> number, step: number, dashed: boolean?)
	local pts: { Vector3 } = {}
	local n = #flat // 2
	for i = 1, n - 1 do
		local ax, az, bx, bz = flat[2 * i - 1], flat[2 * i], flat[2 * i + 1], flat[2 * i + 2]
		local len = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
		local pieces = math.max(1, math.ceil(len / step))
		for k = 0, pieces - 1 do
			local t = k / pieces
			local x, z = ax + (bx - ax) * t, az + (bz - az) * t
			table.insert(pts, Vector3.new(x, heightAt(x, z) + yOffset, z))
		end
	end
	if n >= 1 then
		local x, z = flat[2 * n - 1], flat[2 * n]
		table.insert(pts, Vector3.new(x, heightAt(x, z) + yOffset, z))
	end
	local dashLen, dashGap = 10.5, 21 -- 3 m dash, 6 m gap
	local carry = 0
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local len = (b - a).Magnitude
		if len > 0.05 then
			Geometry.Part(parent, "Road", Vector3.new(width, thickness, len + 0.1), CFrame.lookAt((a + b) / 2, b), color, material)
			if dashed then
				local dir = (b - a) / len
				local d = carry
				while d < len do
					local pos = a + dir * math.min(d + dashLen / 2, len) + Vector3.new(0, thickness / 2 + 0.02, 0)
					local dash = Geometry.Part(parent, "Marking", Vector3.new(0.4, 0.04, math.min(dashLen, len - d)), CFrame.lookAt(pos, pos + dir), Color3.fromRGB(235, 235, 230))
					dash.CanCollide = false
					dash.CanQuery = false
					dash.CastShadow = false
					d += dashLen + dashGap
				end
				carry = d - len
			end
		end
		if i > 1 and math.abs((pts[i] - pts[i - 1]).Unit:Dot((b - a).Unit)) < 0.995 then
			local joint = Geometry.Part(parent, "Joint", Vector3.new(thickness, width, width), CFrame.new(a) * CFrame.Angles(0, 0, math.pi / 2), color, material)
			joint.Shape = Enum.PartType.Cylinder
		end
	end
end

return Geometry
