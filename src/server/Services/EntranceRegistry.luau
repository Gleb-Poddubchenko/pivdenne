--!strict
-- EntranceRegistry: discovers every building entrance (під'їзд) in Workspace.
--
-- An entrance is a Model tagged "Entrance" (CollectionService) with attributes:
--   EntranceId : string  unique, "<BuildingId>/<EntranceNo>", e.g. "b0142/3"
--   Brand      : string  key in IntercomBrands ("Vizor" | "Metron")
--   AptFrom    : number  first apartment number served by this entrance
--   AptTo      : number  last apartment number
-- and children:
--   Door       (Model)  with "Hinge" (BasePart on the hinge axis) + door parts
--   Intercom   (Model)  with "Panel" (BasePart, front face = outward) and "Reader" (BasePart)
--   ExitButton (BasePart, optional) on the inside wall
-- The registry adds the panel display + ProximityPrompts; models stay art-only.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Brands = require(Shared:WaitForChild("IntercomBrands"))

export type Entrance = {
	Id: string,
	Model: Model,
	Brand: Brands.Brand,
	AptFrom: number,
	AptTo: number,
	Door: Model,
	Hinge: BasePart,
	Panel: BasePart,
	Reader: BasePart,
	ExitButton: BasePart?,
	Display: TextLabel,
}

local TAG = "Entrance"

local EntranceRegistry = {}

local entrances: { [string]: Entrance } = {}
local addedEvent = Instance.new("BindableEvent")
EntranceRegistry.EntranceAdded = addedEvent.Event -- (entrance: Entrance)

local function findPart(parent: Instance?, name: string): BasePart?
	if not parent then
		return nil
	end
	local child = parent:FindFirstChild(name)
	if child and child:IsA("BasePart") then
		return child
	end
	return nil
end

local function makeLabel(props: { [string]: any }): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	for k, v in props do
		(label :: any)[k] = v
	end
	return label
end

-- Draws the brand plate, LED/LCD display and a decorative keypad on the panel.
local function buildPanelGui(panel: BasePart, brand: Brands.Brand): TextLabel
	local old = panel:FindFirstChild("PanelGui")
	if old then
		old:Destroy()
	end

	local gui = Instance.new("SurfaceGui")
	gui.Name = "PanelGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 100
	gui.LightInfluence = 0.4
	gui.MaxDistance = 60 -- hundreds of panels in the city: only render nearby ones
	gui.Parent = panel

	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = brand.PanelColor
	bg.BorderSizePixel = 0
	bg.Parent = gui

	makeLabel({
		Text = brand.DisplayName,
		Size = UDim2.fromScale(0.8, 0.06),
		Position = UDim2.fromScale(0.1, 0.03),
		TextColor3 = brand.ButtonTextColor,
		Parent = bg,
	})

	local screen = Instance.new("Frame")
	screen.Size = UDim2.fromScale(0.84, 0.13)
	screen.Position = UDim2.fromScale(0.08, 0.11)
	screen.BackgroundColor3 = brand.DisplayBg
	screen.BorderSizePixel = 0
	screen.Parent = bg

	local display = makeLabel({
		Name = "Display",
		Text = brand.Text.Idle,
		Size = UDim2.fromScale(0.92, 0.8),
		Position = UDim2.fromScale(0.04, 0.1),
		TextColor3 = brand.DisplayTextColor,
		Font = brand.DisplayFont,
		Parent = screen,
	})

	local keys = { "1", "2", "3", "4", "5", "6", "7", "8", "9", brand.ClearLabel, "0", brand.CallLabel }
	for i, text in keys do
		local col = (i - 1) % 3
		local row = (i - 1) // 3
		local key = Instance.new("Frame")
		key.Size = UDim2.fromScale(0.24, 0.085)
		key.Position = UDim2.fromScale(0.1 + col * 0.28, 0.29 + row * 0.105)
		key.BackgroundColor3 = brand.ButtonColor
		key.BorderSizePixel = 0
		key.Parent = bg
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.2, 0)
		corner.Parent = key
		makeLabel({
			Text = text,
			Size = UDim2.fromScale(1, 0.8),
			Position = UDim2.fromScale(0, 0.1),
			TextColor3 = brand.ButtonTextColor,
			Parent = key,
		})
	end

	return display
end

local function makePrompt(parent: BasePart, action: string, actionText: string, objectText: string, keyCode: Enum.KeyCode, entranceId: string, brandId: string)
	local old = parent:FindFirstChild(action .. "Prompt")
	if old then
		old:Destroy()
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = action .. "Prompt"
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.KeyboardKeyCode = keyCode
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("Action", action)
	prompt:SetAttribute("EntranceId", entranceId)
	prompt:SetAttribute("Brand", brandId)
	prompt.Parent = parent
end

local function register(inst: Instance)
	local path = inst:GetFullName()
	if not inst:IsA("Model") then
		warn("[Entrance] Tagged instance is not a Model:", path)
		return
	end
	local id = inst:GetAttribute("EntranceId")
	local brandId = inst:GetAttribute("Brand")
	local aptFrom = inst:GetAttribute("AptFrom")
	local aptTo = inst:GetAttribute("AptTo")
	if typeof(id) ~= "string" or id == "" then
		warn("[Entrance] Missing EntranceId attribute:", path)
		return
	end
	if typeof(brandId) ~= "string" or Brands[brandId] == nil then
		warn("[Entrance] Unknown Brand attribute on", path, brandId)
		return
	end
	if typeof(aptFrom) ~= "number" or typeof(aptTo) ~= "number" or aptFrom > aptTo then
		warn("[Entrance] Bad AptFrom/AptTo on", path)
		return
	end
	if entrances[id] then
		warn("[Entrance] Duplicate EntranceId", id, "at", path)
		return
	end

	local door = inst:FindFirstChild("Door")
	local intercom = inst:FindFirstChild("Intercom")
	local hinge = findPart(door, "Hinge")
	local panel = findPart(intercom, "Panel")
	local reader = findPart(intercom, "Reader")
	if not (door and door:IsA("Model") and hinge and panel and reader) then
		warn("[Entrance] Needs Door/Hinge and Intercom/Panel + Intercom/Reader:", path)
		return
	end

	-- Stream door and panel as whole units so clients never see half a door.
	door.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	if intercom:IsA("Model") then
		intercom.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end

	local brand = Brands[brandId]
	local entrance: Entrance = {
		Id = id,
		Model = inst,
		Brand = brand,
		AptFrom = aptFrom,
		AptTo = aptTo,
		Door = door,
		Hinge = hinge,
		Panel = panel,
		Reader = reader,
		ExitButton = findPart(inst, "ExitButton"),
		Display = buildPanelGui(panel, brand),
	}

	local objectText = ("%s · кв. %d–%d"):format(brand.DisplayName, aptFrom, aptTo)
	makePrompt(panel, "Intercom", "Набрати квартиру", objectText, Enum.KeyCode.E, id, brandId)
	makePrompt(reader, "Reader", "Прикласти ключ", objectText, Enum.KeyCode.F, id, brandId)

	entrances[id] = entrance
	addedEvent:Fire(entrance)
end

function EntranceRegistry.Get(id: string): Entrance?
	return entrances[id]
end

function EntranceRegistry.All(): { [string]: Entrance }
	return entrances
end

function EntranceRegistry.Init()
	for _, inst in CollectionService:GetTagged(TAG) do
		register(inst)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(register)
end

return EntranceRegistry
