--!strict
-- IntercomBrands: look, sounds and dialing behaviour of the two panel families.
-- In-game names are generic ("VIZOR", "METRON") to avoid trademark issues; they
-- are *styled after* the Vizit and Metacom panels seen on Yuzhne entrances.
-- Exact colours/layouts are marked NEEDS VERIFICATION in docs/README.md.

export type BrandSounds = {
	Click: string,
	Ring: string, -- looped while calling a flat
	Connected: string,
	Open: string, -- "door open" melody/beeps
	Deny: string, -- wrong key / error
	Busy: string,
}

export type BrandText = {
	Idle: string,
	Connected: string,
	Open: string,
	Deny: string,
	Busy: string,
	Invalid: string,
	NoAnswer: string,
}

export type Brand = {
	Id: string,
	DisplayName: string,
	PanelColor: Color3,
	ButtonColor: Color3,
	ButtonTextColor: Color3,
	DisplayBg: Color3,
	DisplayTextColor: Color3,
	DisplayFont: Enum.Font,
	CallLabel: string,
	ClearLabel: string,
	-- nil: the user must press CALL. number: dial automatically after this many
	-- seconds without a new digit.
	AutoDialDelay: number?,
	AcceptedKeyTypes: { string },
	DefaultKeyType: string,
	Sounds: BrandSounds,
	Text: BrandText,
	FormatNumber: (digits: string) -> string,
	RingingText: (digits: string) -> string,
}

local function padLeft(s: string, width: number): string
	return string.rep(" ", math.max(0, width - #s)) .. s
end

local Brands: { [string]: Brand } = {
	-- Vizit-style: brushed silver panel, red 7-segment LED, bell key to call,
	-- round touch-memory reader.
	Vizor = {
		Id = "Vizor",
		DisplayName = "VIZOR",
		PanelColor = Color3.fromRGB(178, 182, 188),
		ButtonColor = Color3.fromRGB(214, 216, 220),
		ButtonTextColor = Color3.fromRGB(35, 35, 35),
		DisplayBg = Color3.fromRGB(28, 6, 6),
		DisplayTextColor = Color3.fromRGB(255, 48, 36),
		DisplayFont = Enum.Font.Code,
		CallLabel = "🔔",
		ClearLabel = "C",
		AutoDialDelay = nil,
		AcceptedKeyTypes = { "TM" },
		DefaultKeyType = "TM",
		Sounds = { Click = "", Ring = "", Connected = "", Open = "", Deny = "", Busy = "" },
		Text = {
			Idle = "----",
			Connected = "TALK",
			Open = "OPEN",
			Deny = "Err",
			Busy = "bUSY",
			Invalid = "Err",
			NoAnswer = "----",
		},
		FormatNumber = function(digits: string): string
			return padLeft(digits, 4)
		end,
		RingingText = function(digits: string): string
			return padLeft(digits, 4)
		end,
	},

	-- Metacom-style: dark panel, blue-backlit LCD with text prompts,
	-- auto-dial after a pause, reads both RFID fobs and TM tablets.
	Metron = {
		Id = "Metron",
		DisplayName = "METRON",
		PanelColor = Color3.fromRGB(38, 40, 46),
		ButtonColor = Color3.fromRGB(62, 66, 74),
		ButtonTextColor = Color3.fromRGB(225, 232, 240),
		DisplayBg = Color3.fromRGB(20, 60, 120),
		DisplayTextColor = Color3.fromRGB(215, 235, 255),
		DisplayFont = Enum.Font.RobotoMono,
		CallLabel = "☎",
		ClearLabel = "✕",
		AutoDialDelay = 2.5,
		AcceptedKeyTypes = { "RFID", "TM" },
		DefaultKeyType = "RFID",
		Sounds = { Click = "", Ring = "", Connected = "", Open = "", Deny = "", Busy = "" },
		Text = {
			Idle = "НАБЕРІТЬ №",
			Connected = "РОЗМОВА",
			Open = "ВІДЧИНЕНО",
			Deny = "НЕМАЄ ДОСТУПУ",
			Busy = "ЗАЙНЯТО",
			Invalid = "ПОМИЛКА",
			NoAnswer = "НЕ ВІДПОВІДАЄ",
		},
		FormatNumber = function(digits: string): string
			return "КВ " .. digits
		end,
		RingingText = function(digits: string): string
			return "ВИКЛИК " .. digits
		end,
	},
}

return Brands
