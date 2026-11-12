local addonName, A = ...
A.name = addonName
A.version = "0.7.0-test"
A.quotes, A.alerts, A.noticeAt = {}, {}, {}
A.activity = {}
A.ttl = 120
A.open = false

function A.Now() return GetTime() end

function A.Message(text)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffe4bd72拍卖助手|r：" .. text) end
end

function A.RefreshUI()
    if A.UI and A.UI.Refresh then A.UI.Refresh() end
end

function A.ItemInfo(itemID)
    if not itemID then return "未选择商品", 134400 end
    local name, link, _, _, _, _, _, _, _, icon = C_Item.GetItemInfo(itemID)
    return name or ("物品 " .. itemID), icon or 134400, link
end

function A.Product(id)
    if not A.profile then return nil end
    for _, product in ipairs(A.profile.products) do
        if product.id == id then return product end
    end
end

function A.Selected() return A.profile and A.Product(A.profile.selectedID) end

function A.SelectedRecipe(product)
    product = product or A.Selected()
    if not product then return nil end
    for _, recipe in ipairs(product.recipes) do
        if recipe.id == product.activeRecipeID then return recipe end
    end
end

-- Keep the merchant cache bounded by the saved watchlist, including alternate recipes.
function A.PruneVendorPrices()
    local tracked = {}
    for _, product in ipairs(A.profile.products) do
        tracked[product.itemID] = true
        for _, recipe in ipairs(product.recipes) do
            for _, material in ipairs(recipe.materials) do tracked[material.itemID] = true end
        end
    end
    if type(A.profile.vendorPrices) ~= "table" then A.profile.vendorPrices = {} end
    for id in pairs(A.profile.vendorPrices) do
        if not tracked[id] then A.profile.vendorPrices[id] = nil end
    end
    return tracked
end

function A.Select(id, recipeID)
    local product = A.Product(id)
    if not product then return end
    if A.Native then A.Native.pendingPost = nil end
    if recipeID then
        local found = false
        for _, recipe in ipairs(product.recipes) do if recipe.id == recipeID then found = true; break end end
        if not found then return end
        product.activeRecipeID = recipeID
    end
    local changedProduct = A.profile.selectedID ~= id
    A.profile.selectedID = id
    if A.UI and changedProduct then A.UI.selectedChanged = true end
    A.RefreshUI()
end

function A.SaveProduct(draft)
    local valid, err = A.Logic.Validate(draft)
    if not valid then return nil, err end
    local name = type(draft.recipeName) == "string" and draft.recipeName:match("^%s*(.-)%s*$") or ""
    if name == "" or #name > 120 then return nil, "请填写简短的配方名称。" end
    local existing = draft.id and A.Product(draft.id)
    if draft.id and not existing then return nil, "商品已不存在，请重新打开编辑。" end
    if existing and existing.itemID ~= draft.itemID then return nil, "已有产品的成品不能更换，请另添产品。" end
    for _, other in ipairs(A.profile.products) do
        if other.itemID == draft.itemID and other.id ~= draft.id then
            return nil, "该商品已在列表，请使用它的「添加配方」。"
        end
    end
    local product = existing and A.Logic.Copy(existing)
        or { id = A.profile.nextID, itemID = draft.itemID, recipes = {}, nextRecipeID = 1 }
    local targetIndex
    for index, recipe in ipairs(product.recipes) do
        if recipe.id == draft.recipeID then targetIndex = index
        elseif recipe.name == name then return nil, "这个产品已有同名配方，请换个名称。" end
    end
    if draft.recipeID and not targetIndex then return nil, "配方已不存在，请重新打开编辑。" end
    local recipe = { id = draft.recipeID or product.nextRecipeID, name = name, output = draft.output,
        extra = draft.extra, materials = A.Logic.Copy(draft.materials), sourceRecipeID = draft.sourceRecipeID,
        sourceOutputMin = draft.sourceOutputMin, sourceOutputMax = draft.sourceOutputMax }
    if targetIndex then product.recipes[targetIndex] = recipe
    else
        table.insert(product.recipes, recipe)
        product.nextRecipeID = product.nextRecipeID + 1
    end
    product.fee, product.alert, product.activeRecipeID = draft.fee, draft.alert, recipe.id
    if existing then
        for i, other in ipairs(A.profile.products) do
            if other.id == product.id then A.profile.products[i] = product; break end
        end
    else
        A.profile.nextID = A.profile.nextID + 1
        table.insert(A.profile.products, product)
    end
    A.alerts[product.itemID] = nil
    A.PruneVendorPrices()
    A.Select(product.id, recipe.id)
    return true
end

function A.DeleteRecipe(productID, recipeID)
    local product = A.Product(productID)
    if not product then return nil, "商品已不存在。" end
    if #product.recipes <= 1 then return nil, "至少保留一套配方，或移除整个产品。" end
    for i, recipe in ipairs(product.recipes) do
        if recipe.id == recipeID then
            table.remove(product.recipes, i)
            if product.activeRecipeID == recipeID then product.activeRecipeID = product.recipes[1].id end
            A.PruneVendorPrices()
            A.RefreshUI()
            return true
        end
    end
    return nil, "配方已不存在。"
end

function A.DeleteProduct(id)
    local product
    for _, entry in ipairs(A.profile.products) do if entry.id == id then product = entry; break end end
    if not product then return end
    for i, other in ipairs(A.profile.products) do
        if other.id == product.id then table.remove(A.profile.products, i); break end
    end
    A.alerts[product.itemID] = nil
    A.activity[product.itemID] = nil
    if A.profile.selectedID == id then
        A.profile.selectedID = A.profile.products[1] and A.profile.products[1].id or nil
    end
    A.PruneVendorPrices()
    A.RefreshUI()
end

function A.Estimate(product, recipe)
    recipe = recipe or A.SelectedRecipe(product)
    if not product or not recipe then return { error = "请选择配方", materials = {} } end
    return A.EstimateInput(A.Logic.RecipeInput(product, recipe))
end

function A.EstimateInput(input)
    -- A manual watchlist retains the last complete snapshot, visibly marked by age.
    local vendorPrices = A.profile and A.profile.vendorPrices
    local result = A.Logic.Estimate(input, A.quotes, A.Now(), math.huge, nil, nil, vendorPrices)
    local age = 0
    local function include(id)
        local quote = A.quotes[id]
        if quote and quote.complete and not quote.error then age = math.max(age, A.Now() - quote.at) end
    end
    if input.itemID then include(input.itemID) end
    for _, material in ipairs(input.materials or {}) do
        if A.Logic.UsesMarketPrice(material, vendorPrices) then include(material.itemID) end
    end
    result.age, result.stale = age, age > A.ttl
    return result
end

function A.AgeText(age)
    if age == nil then return "未刷新" end
    if age < 60 then return math.floor(math.max(0, age)) .. "秒前" end
    if age < 3600 then return math.floor(age / 60) .. "分前" end
    return math.floor(age / 3600) .. "小时前"
end

function A.RecipeNote(recipe)
    if not recipe or not recipe.sourceRecipeID then return "手动配置" end
    local note = "读取自配方 #" .. recipe.sourceRecipeID
    if recipe.sourceOutputMin and recipe.sourceOutputMax and recipe.sourceOutputMax > recipe.sourceOutputMin then
        note = note .. " · 产量 " .. recipe.sourceOutputMin .. "–" .. recipe.sourceOutputMax
            .. (recipe.output == recipe.sourceOutputMin and "，按最低产量估算" or "，按自填产量估算")
    end
    return note
end

function A.AlertText(alert)
    if not alert then return "等待行情更新" end
    if alert.kind == "undercut" then return "有更低价：" .. A.Logic.Money(alert.price) end
    return "同价货量增加 " .. alert.increase .. " 件，可能被超过"
end

function A.BreakActivity(itemID, reason)
    for id, state in pairs(A.activity) do
        if not itemID or id == itemID then
            state.previous, state.reference, state.referenceAt = nil, nil, nil
            state.status = reason or "已暂停"
        end
    end
end

local function recordActivity(itemID, quote)
    if not quote.complete or quote.error then A.BreakActivity(itemID, "查询失败"); return end
    local state = A.activity[itemID] or {}
    A.activity[itemID] = state
    local previous, minimum = state.previous, quote.levels[1] and quote.levels[1].price
    -- Repeated events for a single observation do not create an extra sample.
    if previous and quote.at <= previous.at then return end
    if not previous or not state.reference or quote.at - previous.at > A.ttl then
        state.result = nil
        state.reference, state.referenceAt = minimum, quote.at
        state.status = minimum and "采样中" or "无挂单"
    else
        state.result = A.Logic.Activity(previous, quote, state.reference)
        state.status = nil
        -- Finish the old range first; the new reference applies only to the next pair.
        if quote.at - state.referenceAt >= 600 or (minimum and minimum > state.reference) then
            state.reference, state.referenceAt = minimum, quote.at
        end
    end
    state.previous = quote
end

function A.AcceptQuote(itemID, quote)
    A.History.AcceptQuote(itemID, quote)
    local previous = A.quotes[itemID]
    A.quotes[itemID] = quote
    local product
    for _, entry in ipairs(A.profile.products) do
        if entry.itemID == itemID then product = entry; break end
    end
    if product then
        recordActivity(itemID, quote)
        local alert = A.Logic.Competition(A.Logic.Fresh(previous, A.Now(), A.ttl) and previous or nil, quote)
        local last = A.alerts[itemID]
        if alert then
            local now = A.Now()
            alert.at = now
            if product.alert and (not last or last.key ~= alert.key)
                and (not A.noticeAt[itemID] or now - A.noticeAt[itemID] >= 30) then
                A.noticeAt[itemID] = now
                A.Message((A.ItemInfo(itemID)) .. "：" .. A.AlertText(alert))
                if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.TELL_MESSAGE or 3081, "Master") end
                if FlashClientIcon then FlashClientIcon() end
            end
            A.alerts[itemID] = alert
        elseif last and last.kind == "same" and A.Now() - last.at < 60 then
            A.alerts[itemID] = nil
            for _, level in ipairs(quote.levels) do
                if level.price == last.price and level.own > 0 then A.alerts[itemID] = last; break end
            end
        else
            A.alerts[itemID] = nil
        end
    end
    A.RefreshUI()
end

function A.Initialize()
    if A.profile then return end
    local database, err = A.Logic.MigrateDB(AuctionPilotDB)
    if not database then A.Message(err); return end
    AuctionPilotDB = database
    local key = GetRealmName() .. ":" .. (UnitGUID("player") or UnitName("player"))
    local profile = AuctionPilotDB.profiles[key]
    if not profile then
        profile = { products = {}, nextID = 1 }
        AuctionPilotDB.profiles[key] = profile
    end
    A.profile = profile
    A.PruneVendorPrices()
    A.History.Initialize()
    A.UI.Build()
    A.Widgets.InstallItemLinks()
    A.Market.StartTicker()
end

local events = CreateFrame("Frame")
A.events = events
for _, event in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED",
    "COMMODITY_SEARCH_RESULTS_UPDATED", "COMMODITY_SEARCH_RESULTS_ADDED",
    "ITEM_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_ADDED", "BAG_UPDATE_DELAYED",
    "GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT", "AUCTION_HOUSE_AUCTION_CREATED",
    "AUCTION_HOUSE_THROTTLED_SYSTEM_READY", "AUCTION_HOUSE_SHOW_ERROR",
    "PLAYER_MONEY", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "MERCHANT_SHOW", "MERCHANT_UPDATE" }) do
    events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" or (event == "ADDON_LOADED" and ... == addonName and IsLoggedIn()) then
        A.Initialize()
    elseif event == "AUCTION_HOUSE_SHOW" then
        A.Initialize()
        if not A.profile then return end
        A.open, A.quotes, A.alerts, A.noticeAt, A.activity = true, {}, {}, {}, {}
        A.Market.auto = false
        A.Native.OnEvent(event)
        A.Market.Pause()
        C_Timer.After(0, function() if A.open then A.Native.Attach(); A.RefreshUI() end end)
    elseif event == "AUCTION_HOUSE_CLOSED" then
        A.open = false
        A.Market.auto, A.activity = false, {}
        A.Native.OnEvent(event)
        A.Market.Pause()
        if A.UI and A.UI.frame then A.UI.frame:Hide() end
    elseif A.profile then
        A.Native.OnEvent(event, ...)
        A.History.OnEvent(event, ...)
        A.Market.OnEvent(event, ...)
        if event == "BAG_UPDATE_DELAYED" or event == "GET_ITEM_INFO_RECEIVED"
            or event == "ITEM_DATA_LOAD_RESULT" or event == "AUCTION_HOUSE_AUCTION_CREATED"
            or event == "PLAYER_MONEY" or event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED"
            or event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
            A.RefreshUI()
        end
    end
end)

SLASH_AUCTIONPILOT1 = "/ap"
SLASH_AUCTIONPILOT2 = "/auctionpilot"
SlashCmdList.AUCTIONPILOT = function()
    A.Initialize()
    if not A.profile then return end
    if A.open then A.Native.Attach(); A.Native.ShowMonitor()
    else A.UI.frame:SetParent(UIParent); A.UI.Layout(); A.UI.frame:Show(); A.RefreshUI() end
end
