--!strict
-- Types: shared data shapes. No runtime logic.

export type KeyData = {
	Id: string,
	Type: string, -- Config.Keys.Types
	Label: string,
	Entrances: { string }, -- EntranceIds this key is programmed for
	CreatedAt: number,
}

export type CarData = {
	Id: string,
	ModelId: string, -- key in Vehicles.Models
	ColorIndex: number, -- index in Vehicles.Colors
	Plate: string,
	BoughtAt: number,
}

export type PlayerData = {
	Version: number,
	Money: number,
	Keys: { [string]: KeyData },
	Apartments: { string }, -- "<EntranceId>#<apt>"
	Cars: { CarData },
	Inventory: { [string]: number }, -- itemId -> count
	Storage: { [string]: { [string]: number } }, -- aptKey -> (itemId -> count), e.g. the fridge
}

-- What the client is allowed to see about its own data.
export type Snapshot = {
	Money: number,
	Keys: { KeyData },
	Apartments: { string },
	Inventory: { [string]: number },
	Storage: { [string]: { [string]: number } },
	Cars: { CarData },
}

return {}
