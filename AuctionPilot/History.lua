local _, A = ...
local H, L = {}, A.Logic
A.History = H
local maxAge, maxSamples = 48 * 3600, 30000

local function validPrice(price) return L.Number(price, 0.000000001, 1000000000000, false) end
local function validTime(at) return L.Number(at, 1, 100000000000, true) end

local function prune(history, now)
    while history.first < history.next do
        local sample = history.samples[history.first]
        if history.next - history.first <= maxSamples and now - sample[2] <= maxAge then break end
        history.samples[history.first] = nil
        history.first = history.first + 1
    end
end

local function initializeSeries()
    if A.profile.priceHistory == nil then
        A.profile.priceHistory = {version=1, first=1, next=1, samples={}}
    end
    local history = A.profile.priceHistory
    H.prices = nil
    local valid = type(history) == "table" and history.version == 1 and type(history.samples) == "table"
        and type(history.first) == "number" and type(history.next) == "number"
        and L.Number(history.first, 1, 1000000000000, true)
        and L.Number(history.next, history.first, 1000000000000, true)
    if valid then
        local count = 0
        for id, sample in pairs(history.samples) do
            if type(id) ~= "number" or not L.Number(id, history.first, history.next - 1, true) or type(sample) ~= "table"
                or not L.ItemID(sample[1]) or not validTime(sample[2])
                or (sample[3] ~= false and not validPrice(sample[3])) then
                valid = false; break
            end
            count = count + 1
        end
        valid = valid and count == history.next - history.first
    end
    if not valid then
        A.Message("价格历史格式不兼容，暂不追加；原记录已保留。")
        return
    end
    H.prices = history
    prune(history, GetServerTime())
end

local function save(itemID, price, seenAt, source)
    if not A.open or not L.ItemID(itemID) or (price ~= nil and not validPrice(price)) then return end
    local records = A.profile and A.profile.lastSeenPrices
    if type(records) ~= "table" then return end
    seenAt = seenAt or GetServerTime()
    if not validTime(seenAt) then return end
    local previous = records[itemID]
    if type(previous) == "table" and previous.priceVersion == 2 and validTime(previous.seenAt)
        and (seenAt < previous.seenAt or (seenAt == previous.seenAt
            and source == "browse" and previous.source ~= "browse")) then return end
    records[itemID] = { price = price, seenAt = seenAt, priceVersion = 2, source = source }
end

function H.AcceptQuote(itemID, quote)
    if not A.open or not L.ItemID(itemID) or not quote or not quote.complete or quote.error
        or quote.seenAt or type(quote.levels) ~= "table" then return end
    local minimum
    for _, level in ipairs(quote.levels) do
        if not validPrice(level.price) then return end
        minimum = minimum and math.min(minimum, level.price) or level.price
    end
    local seenAt = GetServerTime()
    if not validTime(seenAt) then return end
    quote.seenAt = seenAt
    save(itemID, minimum, seenAt)
    local history = H.prices
    if not history or history ~= A.profile.priceHistory then return end
    for _, product in ipairs(A.profile.products) do
        if product.itemID == itemID then
            -- Sequence keys survive reload and pruning. A false price means a complete result without a buyout.
            history.samples[history.next] = {itemID, seenAt, minimum or false}
            history.next = history.next + 1
            prune(history, seenAt)
            break
        end
    end
end

local function plainKey(key)
    return key and L.ItemID(key.itemID) and (key.itemSuffix or 0) == 0 and (key.battlePetSpeciesID or 0) == 0
end

local function recordBrowse(row, seenAt)
    if type(row) ~= "table" or not plainKey(row.itemKey) or not validPrice(row.minPrice)
        or not L.Number(row.totalQuantity, 1, 1000000000, true) then return end
    local key = row.itemKey
    H.browseRows[key.itemID] = nil
    local info = C_AuctionHouse.GetItemKeyInfo(key)
    if not info then
        H.browseRows[key.itemID] = {row={itemKey=L.Copy(key), minPrice=row.minPrice,
            totalQuantity=row.totalQuantity}, seenAt=seenAt}
    elseif not info.isEquipment and not info.isPet then
        save(key.itemID, row.minPrice, seenAt, "browse")
    end
end

local function initializeBrowse()
    H.browseRequested, H.browseRows = false, {}
    if H.browseHooked then return end
    for _, method in ipairs({"SendBrowseQuery", "SearchForFavorites", "SearchForItemKeys", "RequestMoreBrowseResults"}) do
        local nextPage = method == "RequestMoreBrowseResults"
        if type(C_AuctionHouse[method]) == "function" then
            -- Observe native queries without starting one; item-detail updates can also emit browse events.
            hooksecurefunc(C_AuctionHouse, method, function()
                H.browseRequested = true
                if not nextPage then H.browseRows = {} end
            end)
        end
    end
    H.browseHooked = true
end

-- Observe completed searches (including native AH searches), never start or page one.
function H.OnEvent(event, arg)
    if event == "AUCTION_HOUSE_CLOSED" or event == "AUCTION_HOUSE_BROWSE_FAILURE" then
        H.browseRequested, H.browseRows = false, {}
        return
    end
    if not A.open then return end
    if event == "ITEM_KEY_ITEM_INFO_RECEIVED" then
        local pending = H.browseRows[arg]
        if pending then recordBrowse(pending.row, pending.seenAt) end
        return
    end
    if event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
        if not H.browseRequested then return end
        H.browseRequested = false
        local rows = arg
        if event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" then rows = C_AuctionHouse.GetBrowseResults() end
        if type(rows) == "table" then
            local seenAt = GetServerTime()
            for _, row in ipairs(rows) do recordBrowse(row, seenAt) end
        end
        return
    end
    local commodity = event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "COMMODITY_SEARCH_RESULTS_ADDED"
    local item = event == "ITEM_SEARCH_RESULTS_UPDATED" or event == "ITEM_SEARCH_RESULTS_ADDED"
    if not commodity and not item then return end
    local key = commodity and L.ItemID(arg) and C_AuctionHouse.MakeItemKey(arg) or item and arg
    if not plainKey(key) then return end
    -- The monitor publishes its complete snapshot through AcceptQuote.
    if (A.Market.active and A.Market.active.itemID == key.itemID)
        or (A.Market.draining and A.Market.draining.itemID == key.itemID)
        or (A.Market.discardUntil and (A.Market.discardUntil[key.itemID] or 0) > A.Now()) then return end
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
            price = row.buyoutAmount
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
    if type(entry) ~= "table" or not L.Number(entry.seenAt, 1, 100000000000, true) then return end
    if entry.priceVersion ~= 2 then
        -- Old saves do not identify commodity versus grouped-item prices, so none can be safely converted.
        tooltip:AddLine(" ")
        tooltip:AddDoubleLine("拍卖助手 · 旧版价格记录", "请在拍卖行刷新", 0.89, 0.75, 0.47, 1, 0.73, 0.28)
        return
    end
    if entry.price ~= nil and not validPrice(entry.price) then return end
    local priceText = "无一口价"
    if entry.price then
        priceText = entry.price < 1 and "不足1铜"
            or (entry.price % 1 ~= 0 and "约 " or "") .. L.Money(entry.price)
    end
    tooltip:AddLine(" ")
    tooltip:AddDoubleLine(entry.source == "browse" and "拍卖助手 · 上次搜索参考价" or "拍卖助手 · 上次最低单价",
        priceText, 0.89, 0.75, 0.47, 0.91, 0.87, 0.77)
    tooltip:AddLine(date("%Y-%m-%d %H:%M", entry.seenAt) .. " · "
        .. A.AgeText(GetServerTime() - entry.seenAt) .. " · 历史参考", 0.61, 0.61, 0.57, true)
end

function H.Initialize()
    if A.profile.lastSeenPrices == nil then A.profile.lastSeenPrices = {} end
    initializeSeries()
    initializeBrowse()
    if H.hooked then return end
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, H.AddTooltip)
        H.hooked = true
    end
end
