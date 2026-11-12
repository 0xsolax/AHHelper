local _, A = ...
local M = { queue = {}, active = nil, nextSend = 0 }
A.Market = M

function M.IsVisible()
    return A.open and A.UI and A.UI.frame and A.UI.frame:IsShown()
end

function M.Pause()
    M.queue, M.active = {}, nil
end

local function enqueue(items)
    if not M.IsVisible() then return nil, "请在拍卖行打开监控面板。" end
    if M.active or #M.queue > 0 then return nil, "正在更新，请稍候。" end
    local queue, seen = {}, {}
    for _, id in ipairs(items) do
        if not seen[id] then seen[id] = true; table.insert(queue, id) end
    end
    if #queue == 0 then return nil, "没有需要查询的拍卖行报价。" end
    M.queue = queue
    A.RefreshUI()
    return true
end

function M.RequestItem(itemID)
    local id = A.Logic.ItemID(itemID)
    if not id then return nil, "物品编号无效。" end
    return enqueue({id})
end

function M.RequestRefresh(scope, productID, recipeID)
    scope = scope or "all"
    if scope ~= "all" and scope ~= "sale" and scope ~= "materials" then return nil, "刷新范围无效。" end
    if recipeID and not productID then return nil, "请先选择产品和配方。" end
    local items = {}
    for _, product in ipairs(A.profile.products) do
        if not productID or product.id == productID then
            if recipeID then
                local found = false
                for _, recipe in ipairs(product.recipes) do if recipe.id == recipeID then found = true; break end end
                if not found then return nil, "配方已不存在，请重新选择。" end
            end
            if scope ~= "materials" then table.insert(items, product.itemID) end
            if scope ~= "sale" then
                for _, recipe in ipairs(product.recipes) do
                    if not recipeID or recipe.id == recipeID then
                        for _, material in ipairs(recipe.materials) do
                            if A.Logic.UsesMarketPrice(material, A.profile.vendorPrices) then
                                table.insert(items, material.itemID)
                            end
                        end
                    end
                end
            end
        end
    end
    return enqueue(items)
end

local function fail(message)
    local active = M.active
    if not active then return end
    local old = A.quotes[active.itemID]
    A.quotes[active.itemID] = { levels = old and old.levels or {}, at = old and old.at or 0,
        complete = false, error = message }
    M.active = nil
    A.RefreshUI()
end

local function finish(rows)
    local id = M.active.itemID
    local quote = A.Logic.Snapshot(rows, A.Now(), true)
    M.active = nil
    A.AcceptQuote(id, quote)
end

function M.ReadCommodity()
    local active = M.active
    if not active then return end
    if not C_AuctionHouse.HasFullCommoditySearchResults(active.itemID) then
        active.more = "commodity"
        return
    end
    local rows = {}
    for i = 1, C_AuctionHouse.GetNumCommoditySearchResults(active.itemID) do
        local entry = C_AuctionHouse.GetCommoditySearchResultInfo(active.itemID, i)
        if entry then
            table.insert(rows, { price = entry.unitPrice, quantity = entry.quantity, own = entry.numOwnerItems })
        end
    end
    finish(rows)
end

function M.ReadItem()
    local active = M.active
    if not active then return end
    if not C_AuctionHouse.HasFullItemSearchResults(active.key) then active.more = "item"; return end
    local rows = {}
    for i = 1, C_AuctionHouse.GetNumItemSearchResults(active.key) do
        local entry = C_AuctionHouse.GetItemSearchResultInfo(active.key, i)
        if entry and entry.buyoutAmount and entry.buyoutAmount > 0 and entry.quantity > 0 then
            -- Never mix level/suffix variants into a generic material's cost.
            local key = entry.itemKey
            if key.itemID == active.itemID and (key.itemSuffix or 0) == 0 and (key.battlePetSpeciesID or 0) == 0 then
                -- Native item results group identical offers; buyoutAmount is already the unit buyout.
                table.insert(rows, { price = entry.buyoutAmount, quantity = entry.quantity,
                    own = entry.containsOwnerItem and entry.quantity or 0 })
            end
        end
    end
    finish(rows)
end

function M.OnEvent(event, arg)
    local active = M.active
    if not active or not M.IsVisible() then return end
    if (event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "COMMODITY_SEARCH_RESULTS_ADDED")
        and arg == active.itemID then
        M.ReadCommodity()
    elseif (event == "ITEM_SEARCH_RESULTS_UPDATED" or event == "ITEM_SEARCH_RESULTS_ADDED")
        and arg and arg.itemID == active.itemID then
        M.ReadItem()
    elseif event == "AUCTION_HOUSE_SHOW_ERROR" then
        fail("拍卖行查询失败，请刷新重试")
    end
end

function M.Tick()
    if not M.IsVisible() then return end
    local now = A.Now()
    if M.active and now - M.active.started > 25 then fail("查询超时，请刷新重试") end
    if now < M.nextSend or not C_AuctionHouse.IsThrottledMessageSystemReady() then return end
    if M.active then
        local active = M.active
        if active.more then
            local more = active.more
            active.more = nil
            M.nextSend = now + 1.2
            local ok, hasFull = pcall(function()
                if more == "commodity" then return C_AuctionHouse.RequestMoreCommoditySearchResults(active.itemID)
                else return C_AuctionHouse.RequestMoreItemSearchResults(active.key) end
            end)
            if not ok then fail("补全行情失败，请重试") end
            if ok and hasFull and M.active == active then
                if more == "commodity" then M.ReadCommodity() else M.ReadItem() end
            end
        end
        return
    end
    local id = table.remove(M.queue, 1)
    if not id then return end
    local key = C_AuctionHouse.MakeItemKey(id)
    M.active = { itemID = id, key = key, started = now }
    local info = C_AuctionHouse.GetItemKeyInfo(key)
    if info and (info.isEquipment or info.isPet) then
        fail("装备或宠物请使用原生拍卖界面")
        return
    end
    M.nextSend = now + 1.2
    local ok = pcall(C_AuctionHouse.SendSearchQuery, key,
        { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }, true)
    if not ok then fail("查询未发送，请稍后重试") end
end

function M.StartTicker()
    if M.ticker then return end
    local elapsed = 0
    M.ticker = C_Timer.NewTicker(0.25, function()
        M.Tick()
        elapsed = elapsed + 0.25
        if elapsed >= 1 then elapsed = 0; if M.IsVisible() then A.RefreshUI() end end
    end)
end
