--!strict
-- TextUtil: Unicode-aware helpers. Luau's string.lower only handles ASCII, so
-- Ukrainian/Russian street names need their own lower-casing for search.

local TextUtil = {}

local SPECIAL: { [number]: number } = {
	[0x0401] = 0x0451, -- Ё
	[0x0404] = 0x0454, -- Є
	[0x0406] = 0x0456, -- І
	[0x0407] = 0x0457, -- Ї
	[0x0490] = 0x0491, -- Ґ
}

function TextUtil.Lower(s: string): string
	if utf8.len(s) == nil then
		return string.lower(s)
	end
	local out = {}
	for _, code in utf8.codes(s) do
		if code >= 0x41 and code <= 0x5A then
			code += 0x20
		elseif code >= 0x0410 and code <= 0x042F then
			code += 0x20
		elseif SPECIAL[code] then
			code = SPECIAL[code]
		end
		table.insert(out, utf8.char(code))
	end
	return table.concat(out)
end

local STREET_WORDS = {
	"вулиця", "вул.", "вул", "проспект", "просп.", "просп", "провулок", "пров.", "пров",
	"бульвар", "бульв.", "бульв", "площа", "пл.", "набережна", "наб.", "проїзд", "узвіз",
	"улица", "ул.", "переулок", "пер.",
}

-- "вулиця Хіміків" / "вул. Хіміків" / "хіміків" -> "хіміків"
function TextUtil.NormalizeStreet(s: string): string
	local low = " " .. TextUtil.Lower(s) .. " "
	for _, word in STREET_WORDS do
		low = string.gsub(low, " " .. string.gsub(word, "%.", "%%.") .. " ", " ")
	end
	low = string.gsub(low, "[%s%p]+", "")
	return low
end

-- "7 А" / "7а" -> "7а"
function TextUtil.NormalizeNumber(s: string): string
	return (string.gsub(TextUtil.Lower(s), "[%s]+", ""))
end

return TextUtil
