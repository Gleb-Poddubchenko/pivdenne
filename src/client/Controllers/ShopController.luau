--!strict
-- ShopController: the catalogue window at a shop till.

local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Items = require(Shared:WaitForChild("Items"))
local ShopCatalogs = require(Shared:WaitForChild("ShopCatalogs"))

local UiKit = require(script.Parent.Parent.Ui.UiKit)
local HudController = require(script.Parent.HudController)

local ShopController = {}

local function open(shopId: string, catalog: string, title: string)
	local entries = ShopCatalogs[catalog]
	if not entries then
		return
	end
	local _, body = UiKit.window("ShopWindow", title)
	local remote = Net.Function("BuyItem")
	local pending = false
	for i, entry in entries do
		local item = Items[entry.ItemId]
		if item then
			local price = entry.Price or item.Price
			UiKit.row(body, i, ("%s — %s%d"):format(item.Name, Config.Currency, price), "Купити", function()
				if pending then
					return
				end
				pending = true
				local ok, msg = remote:InvokeServer(shopId, item.Id, 1)
				pending = false
				HudController.Toast(msg, if ok then "good" else "bad")
			end, UiKit.Colors.Good)
		end
	end
end

function ShopController.Init()
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		if prompt:GetAttribute("Action") ~= "Shop" then
			return
		end
		local shopId = prompt:GetAttribute("ShopId")
		local catalog = prompt:GetAttribute("Catalog")
		if typeof(shopId) == "string" and typeof(catalog) == "string" then
			open(shopId, catalog, prompt.ObjectText)
		end
	end)
end

return ShopController
