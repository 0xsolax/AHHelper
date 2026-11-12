local _, A = ...
local H, L = {}, A.Logic
A.History = H

local function validPrice(price) return L.Number(price, 0.000000001, 1000000000000, false) end

local function save(itemID, price)
    if not A.open or not L.ItemID(itemID) or (price ~= nil and not validPrice(price)) then return end
    local records = A.profile and A.profile.lastSeenPrices
    if type(records) ~= "table" then return end
    -- GetTime resets with the session; history needs an absolute timestamp.
    records[itemID] = { price = price, seenAt = GetServerTime() }
end

function H.AcceptQuote(itemID, quote)
    if not quote or not quote.complete or quote.error or type(quote.levels) ~= "table" then return end
    local minimum
    for _, level in ipairs(quote.levels) do
        if not validPrice(level.price) then return end
        minimum = minimum and math.min(minimum, level.price) or level.price
    end
    save(itemID, minimum)
end

local function plainKey(key)
    return key and L.ItemID(key.itemID) and (key.itemSuffix or 0) == 0 and (key.battlePetSpeciesID or 0) == 0
end

-- Observe completed searches (including native AH searches), never start or page one.
function H.OnEvent(event, arg)
    if not A.open then return end
    local commodity = event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "COMMODITY_SEARCH_RESULTS_ADDED"
    local item = event == "ITEM_SEARCH_RESULTS_UPDATED" or event == "ITEM_SEARCH_RESULTS_ADDED"
    if not commodity and not item then return end
    local key = commodity and L.ItemID(arg) and C_AuctionHouse.MakeItemKey(arg) or item and arg
    if not plainKey(key) then return end
    -- The monitor publishes its complete snapshot through AcceptQuote.
    if A.Market.active and A.Market.active.itemID == key.itemID then return end
    local info = C_AuctionHouse.GetItemKeyInfo(key)
    if not info or info.isEquipment or info.isPet then return end
    local complete = commodity and C_AuctionHouse.HasFullCommoditySearchResults(key.itemID)
        or item and C_AuctionHouse.HasFullItemSearchResults(key)
    if not complete then return end
    local count = commodity and C_AuctionHouse.GetNumCommoditySearchResults(key.itemID)
        or C_AuctionHouse.GetNumItemSearchResults(key)
    local minimum
    for index = 1, count do
        local row
        if commodity then row = C_AuctionHouse.GetCommoditySearchResultInfo(key.itemID, index)
        else row = C_AuctionHouse.GetItemSearchResultInfo(key, index) end
        if not row or not L.Number(row.quantity, 1, 1000000000, true) then return end
        if item and (not plainKey(row.itemKey) or row.itemKey.itemID ~= key.itemID
            or (row.itemKey.itemLevel or 0) ~= (key.itemLevel or 0)) then return end
        local price
        if commodity then
            if not validPrice(row.unitPrice) then return end
            price = row.unitPrice
        elseif row.buyoutAmount and row.buyoutAmount ~= 0 then
            if not validPrice(row.buyoutAmount) then return end
            price = row.buyoutAmount / row.quantity
        end
        if price then minimum = minimum and math.min(minimum, price) or price end
    end
    save(key.itemID, minimum)
end

function H.AddTooltip(tooltip, data)
    if tooltip ~= GameTooltip or not A.profile then return end
    local info = tooltip:GetProcessingTooltipInfo()
    if not info or info ~= tooltip:GetPrimaryTooltipInfo() or info.append or info.getterName ~= "GetBagItem" then return end
    local bag = info.getterArgs and info.getterArgs[1]
    local lastBag = Enum.BagIndex and Enum.BagIndex.ReagentBag or NUM_BAG_SLOTS or 4
    if not L.Number(bag, 0, lastBag, true) then return end
    local records = A.profile.lastSeenPrices
    local entry = type(records) == "table" and data and L.ItemID(data.id) and records[data.id]
    if type(entry) ~= "table" or not L.Number(entry.seenAt, 1, 100000000000, true)
        or (entry.price ~= nil and not validPrice(entry.price)) then return end
    local priceText = "无一口价"
    if entry.price then
        priceText = entry.price < 1 and "不足1铜"
            or (entry.price % 1 ~= 0 and "约 " or "") .. L.Money(entry.price)
    end
    tooltip:AddLine(" ")
    tooltip:AddDoubleLine("拍卖助手 · 上次最低单价", priceText, 0.89, 0.75, 0.47, 0.91, 0.87, 0.77)
    tooltip:AddLine(date("%Y-%m-%d %H:%M", entry.seenAt) .. " · "
        .. A.AgeText(GetServerTime() - entry.seenAt) .. " · 历史参考", 0.61, 0.61, 0.57, true)
end

function H.Initialize()
    if A.profile.lastSeenPrices == nil then A.profile.lastSeenPrices = {} end
    if H.hooked then return end
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, H.AddTooltip)
        H.hooked = true
    end
end
