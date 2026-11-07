--!strict
-- Validation: helpers for checking untrusted remote arguments.

local Validation = {}

function Validation.GetRoot(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

function Validation.IsNear(player: Player, part: BasePart, maxDistance: number): boolean
	local root = Validation.GetRoot(player)
	if not root then
		return false
	end
	return (root.Position - part.Position).Magnitude <= maxDistance
end

function Validation.IsInteger(value: any, min: number, max: number): boolean
	return typeof(value) == "number"
		and value == value -- NaN
		and value % 1 == 0
		and value >= min
		and value <= max
end

-- Returns a trimmed, valid UTF-8 string truncated to maxChars, or nil.
function Validation.CleanText(value: any, maxChars: number): string?
	if typeof(value) ~= "string" or utf8.len(value) == nil then
		return nil
	end
	local text = string.gsub(value, "^%s+", "")
	text = string.gsub(text, "%s+$", "")
	local cut = utf8.offset(text, maxChars + 1)
	if cut then
		text = string.sub(text, 1, cut - 1)
	end
	if text == "" then
		return nil
	end
	return text
end

return Validation
