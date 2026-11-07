--!strict
-- MapData: read-only access to the generated OSM chunks in ServerStorage.MapData
-- (for systems that need map facts without the built parts, e.g. address search
-- and fishing water zones, which also work when the city is baked).

local ServerStorage = game:GetService("ServerStorage")

local MapData = {}

local chunks: { any }? = nil

function MapData.Index(): any
	local folder = ServerStorage:FindFirstChild("MapData")
	local module = folder and folder:FindFirstChild("Index")
	if not (module and module:IsA("ModuleScript")) then
		return nil
	end
	local ok, index = pcall(require, module)
	return if ok and typeof(index) == "table" and index.Chunks then index else nil
end

-- All chunk tables (cached after the first call).
function MapData.Chunks(): { any }
	if chunks then
		return chunks
	end
	local list = {}
	local index = MapData.Index()
	local folder = ServerStorage:FindFirstChild("MapData")
	if index and folder then
		for _, name in index.Chunks do
			local module = folder:FindFirstChild(name)
			if module and module:IsA("ModuleScript") then
				local ok, chunk = pcall(require, module)
				if ok and typeof(chunk) == "table" then
					table.insert(list, chunk)
				end
			end
		end
	end
	chunks = list
	return list
end

return MapData
