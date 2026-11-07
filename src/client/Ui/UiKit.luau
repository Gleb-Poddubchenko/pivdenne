--!strict
-- UiKit: tiny helpers for building GUIs in code (mobile-friendly defaults).

local Players = game:GetService("Players")

local UiKit = {}

UiKit.Colors = {
	Bg = Color3.fromRGB(24, 26, 30),
	Panel = Color3.fromRGB(36, 39, 45),
	Accent = Color3.fromRGB(255, 196, 0), -- Ukrainian yellow
	Blue = Color3.fromRGB(0, 87, 183), -- Ukrainian blue
	Text = Color3.fromRGB(235, 238, 242),
	Muted = Color3.fromRGB(150, 156, 166),
	Good = Color3.fromRGB(60, 180, 90),
	Bad = Color3.fromRGB(210, 60, 50),
}

function UiKit.make(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className :: any)
	local parent: Instance? = nil
	if props then
		for k, v in props do
			if k == "Parent" then
				parent = v
			else
				(inst :: any)[k] = v
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function UiKit.corner(px: number?): UICorner
	return UiKit.make("UICorner", { CornerRadius = UDim.new(0, px or 8) })
end

function UiKit.padding(px: number): UIPadding
	return UiKit.make("UIPadding", {
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
	})
end

function UiKit.list(gap: number, horizontal: boolean?): UIListLayout
	return UiKit.make("UIListLayout", {
		Padding = UDim.new(0, gap),
		FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	})
end

function UiKit.screen(name: string, displayOrder: number?): ScreenGui
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
	return UiKit.make("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = displayOrder or 0,
		Parent = playerGui,
	})
end

function UiKit.label(text: string, props: { [string]: any }?): TextLabel
	local label = UiKit.make("TextLabel", {
		Text = text,
		BackgroundTransparency = 1,
		TextColor3 = UiKit.Colors.Text,
		Font = Enum.Font.Gotham,
		TextSize = 16,
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 22),
	})
	if props then
		for k, v in props do
			(label :: any)[k] = v
		end
	end
	return label
end

function UiKit.button(text: string, props: { [string]: any }?): TextButton
	local button = UiKit.make("TextButton", {
		Text = text,
		AutoButtonColor = true,
		BackgroundColor3 = UiKit.Colors.Panel,
		TextColor3 = UiKit.Colors.Text,
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		Size = UDim2.new(1, 0, 0, 40), -- >= 40 px: thumb-sized on phones
	}, { UiKit.corner(8) })
	if props then
		for k, v in props do
			(button :: any)[k] = v
		end
	end
	return button
end

-- Plays a UI sound locally; ignores empty ids.
function UiKit.playLocal(soundId: string, volume: number?)
	if soundId == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume or 0.5
	sound.Parent = workspace.CurrentCamera
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
end


-- Centred, phone-friendly window with a title, close button and scrolling body.
function UiKit.window(name: string, title: string, displayOrder: number?): (ScreenGui, ScrollingFrame)
	local gui = UiKit.screen(name, displayOrder or 6)
	local frame = UiKit.make("Frame", {
		Size = UDim2.new(0.9, 0, 0.7, 0),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = UiKit.Colors.Bg,
		Parent = gui,
	}, {
		UiKit.corner(12),
		UiKit.padding(12),
		UiKit.make("UISizeConstraint", { MaxSize = Vector2.new(440, 540) }),
	})
	UiKit.label(title, {
		Font = Enum.Font.GothamBold,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -50, 0, 30),
		Parent = frame,
	})
	local close = UiKit.button("✕", { Size = UDim2.fromOffset(40, 40), Position = UDim2.new(1, -40, 0, -6), Parent = frame })
	close.Activated:Connect(function()
		gui:Destroy()
	end)
	local body = UiKit.make("ScrollingFrame", {
		Name = "Body",
		Size = UDim2.new(1, 0, 1, -40),
		Position = UDim2.fromOffset(0, 40),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = frame,
	}, { UiKit.list(6) })
	return gui, body
end

-- Removes every GuiObject child (keeps layouts).
function UiKit.clear(container: Instance)
	for _, child in container:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- A row: label on the left, button on the right.
function UiKit.row(parent: Instance, order: number, text: string, buttonText: string, onClick: () -> (), color: Color3?): TextButton
	local row = UiKit.make("Frame", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 48),
		BackgroundColor3 = UiKit.Colors.Panel,
		Parent = parent,
	}, { UiKit.corner(8) })
	UiKit.label(text, {
		Size = UDim2.new(1, -140, 1, 0),
		Position = UDim2.fromOffset(10, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row,
	})
	local button = UiKit.button(buttonText, {
		Size = UDim2.fromOffset(120, 40),
		Position = UDim2.new(1, -124, 0.5, -20),
		BackgroundColor3 = color or UiKit.Colors.Blue,
		TextSize = 14,
		Parent = row,
	})
	button.Activated:Connect(onClick)
	return button
end

return UiKit
