local _, A = ...
local U = { groups = {}, materialRows = {}, selectedChanged = true, sort = "roi" }
A.UI = U
local W, L = A.Widgets, A.Logic

local function message(ok, err)
    U.message:SetText(not ok and err or "")
    if not ok and err then A.Message(err) end
end
local function request(scope, id) message(A.Market.RequestRefresh(scope, id)) end
local function ready() return A.open and not A.Market.active and #A.Market.queue == 0 end
local function column(parent, x, width, size)
    local text = W.Text(parent, "", size or 13, W.text, width)
    text:SetPoint("LEFT", x, 0); text:SetWordWrap(false)
    return text
end

local function recipeRow(group, index)
    if group.rows[index] then return group.rows[index] end
    local row = CreateFrame("Button", nil, group)
    row:SetSize(1036, 36); row:SetPoint("TOPLEFT", 0, -48 - (index - 1) * 36)
    row.selected = row:CreateTexture(nil, "BACKGROUND")
    row.selected:SetAllPoints(); row.selected:SetColorTexture(0.63, 0.47, 0.16, 0.24)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.name = column(row, 48, 190)
    row.output = column(row, 250, 58)
    row.sale = column(row, 320, 104)
    row.cost = column(row, 434, 108)
    row.profit = column(row, 552, 110)
    row.roi = column(row, 678, 82)
    row.age = column(row, 776, 118, 12)
    row.pick = W.Button(row, "选用", 58, 25, function() A.Select(group.productID, row.recipeID) end)
    row.pick:SetPoint("LEFT", 906, 0)
    row.edit = W.Button(row, "编辑", 58, 25, function()
        A.Select(group.productID, row.recipeID); A.Editor.Open(A.Selected())
    end); row.edit:SetPoint("LEFT", 974, 0)
    row:SetScript("OnClick", function() A.Select(group.productID, row.recipeID) end)
    row:SetScript("OnEnter", function()
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT"); GameTooltip:SetText(row.help or ""); GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    group.rows[index] = row
    return row
end

local function productGroup(productID)
    if U.groups[productID] then return U.groups[productID] end
    local group = CreateFrame("Frame", nil, U.list.content)
    group:SetSize(1036, 84); group.rows = {}; group.productID = productID
    local header = CreateFrame("Button", nil, group)
    header:SetSize(1036, 44); header:SetPoint("TOPLEFT")
    local background = header:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(); background:SetColorTexture(0.25, 0.22, 0.16, 0.7)
    group.icon = W.Icon(header, 28); group.icon:SetPoint("LEFT", 8, 0)
    group.name = column(header, 48, 220, 16)
    group.description = column(header, 280, 235, 12)
    group.alert = column(header, 520, 252, 12)
    group.alert:SetTextColor(unpack(W.amber))
    group.sale = W.Button(header, "刷新售价", 78, 26, function() request("sale", productID) end)
    group.sale:SetPoint("LEFT", 784, 0)
    group.materials = W.Button(header, "刷新材料", 78, 26, function() request("materials", productID) end)
    group.materials:SetPoint("LEFT", 870, 0)
    group.add = W.Button(header, "+ 配方", 78, 26, function() A.Editor.Open(A.Product(productID), nil, true) end)
    group.add:SetPoint("LEFT", 956, 0)
    header:SetScript("OnClick", function() A.Select(productID) end)
    U.groups[productID] = group
    return group
end

function U.RefreshList()
    local products = {}
    for _, product in ipairs(A.profile.products) do
        products[#products + 1] = { product = product, estimate = A.Estimate(product) }
    end
    table.sort(products, function(a, b)
        local av, bv = a.estimate[U.sort], b.estimate[U.sort]
        if av == bv then return a.product.id < b.product.id end
        if av == nil then return false end
        if bv == nil then return true end
        return av > bv
    end)
    for _, group in pairs(U.groups) do group:Hide() end
    local y = 0
    for _, entry in ipairs(products) do
        local product = entry.product
        local group = productGroup(product.id)
        group:ClearAllPoints(); group:SetPoint("TOPLEFT", 0, -y); group:Show()
        local name, icon = A.ItemInfo(product.itemID)
        group.name:SetText(name); group.icon:SetTexture(icon)
        local quote = A.quotes[product.itemID]
        group.description:SetText(#product.recipes .. "套配方 · 售价 " .. A.AgeText(quote and quote.at and A.Now() - quote.at))
        local alert = A.alerts[product.itemID]
        group.alert:SetText(alert and L.Fresh(quote, A.Now(), A.ttl) and A.AlertText(alert) or "")
        group.sale:SetEnabled(ready()); group.materials:SetEnabled(ready())
        for i, recipe in ipairs(product.recipes) do
            local row, estimate = recipeRow(group, i), A.Estimate(product, recipe)
            row:Show(); row.recipeID = recipe.id
            row.name:SetText(recipe.name); row.output:SetText(tostring(recipe.output))
            row.selected:SetShown(A.profile.selectedID == product.id and recipe.id == product.activeRecipeID)
            W.Amount(row.sale, estimate.sale); W.Amount(row.cost, estimate.unitCost)
            W.Amount(row.profit, estimate.unitProfit, true)
            row.roi:SetText(estimate.roi and string.format("%.1f%%", estimate.roi) or "--")
            row.roi:SetTextColor(unpack(W.ProfitColor(estimate.roi)))
            row.age:SetText(estimate.error and "待刷新 / 缺价" or (estimate.stale and "历史 · " or "") .. A.AgeText(estimate.age))
            row.age:SetTextColor(unpack((estimate.error or estimate.stale) and W.amber or W.muted))
            if estimate.stale then row.profit:SetTextColor(unpack(W.muted)); row.roi:SetTextColor(unpack(W.muted)) end
            row.pick:SetText(recipe.id == product.activeRecipeID and "已选用" or "选用")
            row.help = name .. " · " .. recipe.name .. "\n" .. A.RecipeNote(recipe) .. "\n" .. (estimate.error or
                (estimate.stale and "历史测算。" or "") .. "按最后一次手动刷新报价估算；单击选用。")
        end
        for i = #product.recipes + 1, #group.rows do group.rows[i]:Hide() end
        local height = 48 + #product.recipes * 36
        group:SetHeight(height); y = y + height + 8
    end
    U.list.content:SetHeight(math.max(238, y))
    U.empty:SetShown(#products == 0)
end

local function materialRow(index)
    if U.materialRows[index] then return U.materialRows[index] end
    local row = CreateFrame("Frame", nil, U.materials.content)
    row:SetSize(686, 34); row:SetPoint("TOPLEFT", 0, -(index - 1) * 34)
    row.icon = W.Icon(row, 24); row.icon:SetPoint("LEFT", 2, 0)
    row.name = column(row, 36, 204)
    row.quantity = column(row, 250, 64)
    row.unit = column(row, 324, 110)
    row.cost = column(row, 444, 116)
    row.age = column(row, 574, 110, 12)
    row:EnableMouse(true)
    row:SetScript("OnEnter", function()
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT"); GameTooltip:SetText(row.help or ""); GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    U.materialRows[index] = row
    return row
end

function U.RefreshDetail()
    local product, recipe = A.Selected(), A.SelectedRecipe()
    U.edit:SetEnabled(recipe ~= nil); U.prepare:SetEnabled(product ~= nil and A.open)
    local quote = product and A.quotes[product.itemID]
    U.usePrice:SetEnabled(A.open and L.Fresh(quote, A.Now(), A.ttl) and quote.levels[1] ~= nil)
    if not product or not recipe then
        U.materialTitle:SetText("选择一套配方查看材料")
        U.profit:SetText("预计利润 --"); U.roi:SetText("成本利润率 --")
        U.materialFoot:SetText("报价只在点击刷新按钮后更新。")
        U.stock:SetText("选择产品后可准备上架。")
        for _, row in ipairs(U.materialRows) do row:Hide() end
        return
    end
    local estimate = A.Estimate(product, recipe)
    U.materialTitle:SetText((A.ItemInfo(product.itemID)) .. " · " .. recipe.name)
    for i, material in ipairs(recipe.materials) do
        local row, info = materialRow(i), estimate.materials[i]
        row:Show()
        local name, icon = A.ItemInfo(material.itemID)
        row.name:SetText(name); row.icon:SetTexture(icon); row.quantity:SetText(tostring(material.quantity))
        W.Amount(row.unit, info and info.unit); W.Amount(row.cost, info and info.cost)
        local source = A.quotes[material.itemID]
        local age = source and A.Now() - source.at
        row.age:SetText(material.source == "fixed" and "固定采购价" or A.AgeText(age))
        row.age:SetTextColor(unpack(age and age > A.ttl and material.source == "market" and W.amber or W.muted))
        row.help = name .. "\n" .. (info and info.error or "按需要的材料数量逐档核算采购支出。")
        if info and info.purchased and info.purchased > info.quantity then row.help = row.help .. "\n整组购入 " .. info.purchased .. " 件，余料未抵扣。" end
        if info and info.error then row.cost:SetText(info.error); row.cost:SetTextColor(unpack(W.amber)) end
    end
    for i = #recipe.materials + 1, #U.materialRows do U.materialRows[i]:Hide() end
    U.materials.content:SetHeight(math.max(78, #recipe.materials * 34))
    U.profit:SetText((estimate.stale and "历史利润 " or "预计利润 ") .. L.Money(estimate.unitProfit) .. " / 件")
    U.profit:SetTextColor(unpack(estimate.stale and W.muted or W.ProfitColor(estimate.unitProfit)))
    U.roi:SetText("成本利润率 " .. (estimate.roi and string.format("%.1f%%", estimate.roi) or "--"))
    U.roi:SetTextColor(unpack(estimate.stale and W.muted or W.ProfitColor(estimate.roi)))
    U.materialFoot:SetText(estimate.error or "产量 " .. recipe.output .. " 件 · 抽成 " .. product.fee
        .. "% · 额外费用 " .. L.Money(recipe.extra) .. " / 次")
    local owned = 0
    if quote then for _, level in ipairs(quote.levels) do owned = owned + level.own end end
    U.stock:SetText("在售 " .. owned .. " · 背包 " .. C_Item.GetItemCount(product.itemID))
    if U.selectedChanged then
        U.price:SetCopper(L.Fresh(quote, A.Now(), A.ttl) and estimate.sale or nil)
        U.priceEdited = false; U.quantity:SetText("1"); U.selectedChanged = false; U.message:SetText("")
    elseif not U.priceEdited and not U.price:GetCopper() and L.Fresh(quote, A.Now(), A.ttl) and estimate.sale then
        U.price:SetCopper(estimate.sale)
    end
end

function U.Refresh()
    if not U.frame or not U.frame:IsShown() or not A.profile then return end
    for _, button in ipairs(U.nativeButtons) do button:SetEnabled(A.open) end
    for _, button in pairs(U.refreshButtons) do button:SetEnabled(ready()) end
    local active = A.Market.active
    U.status:SetText(active and ("正在查询：" .. (A.ItemInfo(active.itemID)) .. " · 余 " .. #A.Market.queue .. " 项")
        or #A.Market.queue > 0 and ("等待查询 · " .. #A.Market.queue .. " 项")
        or A.open and "手动刷新模式 · 点击按钮后更新报价与利润" or "拍卖行未打开 · 可编辑产品和配方")
    U.freshness:SetText("超过 2 分钟标记为历史测算")
    if A.Editor.frame:IsShown() then
        A.Editor.item:RefreshName()
        for _, row in ipairs(A.Editor.rows) do if row:IsShown() then row.item:RefreshName() end end
        A.Editor.Preview()
    else U.RefreshList(); U.RefreshDetail() end
end

function U.Layout()
    local root, canvas = U.frame, U.canvas
    if not root or not canvas then return end
    local docked = A.open and AuctionHouseFrame and root:GetParent() == AuctionHouseFrame
    root:SetMovable(not docked); root:SetClampedToScreen(not docked)
    root:ClearAllPoints()
    if docked then
        -- Keep the native title/portrait, money bar and tabs outside our content area.
        root:SetScale(1)
        root:SetSize(math.max(1, AuctionHouseFrame:GetWidth() - 12), math.max(1, AuctionHouseFrame:GetHeight() - 60))
        root:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPLEFT", 6, -32)
        canvas:SetSize(1120, 615)
        canvas:SetScale(math.min(1, root:GetWidth() / 1120, root:GetHeight() / 615))
    else
        root:SetSize(1120, 720)
        root:SetScale(math.min(1, (UIParent:GetWidth() - 36) / 1120, (UIParent:GetHeight() - 36) / 720))
        root:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        canvas:SetSize(1120, 720); canvas:SetScale(1)
    end
    U.header:SetShown(not docked)
    U.body:ClearAllPoints(); U.body:SetPoint("TOPLEFT", 18, docked and -4 or -110)
    U.message:ClearAllPoints(); U.message:SetPoint("TOPLEFT", 22, docked and -578 or -684)
    U.status:ClearAllPoints(); U.status:SetPoint("TOPLEFT", 22, docked and -596 or -701)
end

function U.Build()
    if U.frame then return end
    local root = W.Panel(UIParent, 1120, 720)
    U.frame = root; _G.AuctionPilotFrame = root; tinsert(UISpecialFrames, "AuctionPilotFrame")
    root:SetFrameStrata("HIGH"); root:SetClampedToScreen(true); root:EnableMouse(true); root:SetMovable(true)
    local frame = CreateFrame("Frame", nil, root)
    U.canvas = frame; frame:SetSize(1120, 720); frame:SetPoint("CENTER", root, "CENTER", 0, 0)
    local header = CreateFrame("Frame", nil, frame)
    U.header = header; header:SetSize(1120, 110); header:SetPoint("TOPLEFT")
    local drag = CreateFrame("Frame", nil, header)
    drag:SetPoint("TOPLEFT", 12, -8); drag:SetPoint("TOPRIGHT", -50, -8); drag:SetHeight(42)
    drag:EnableMouse(true); drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() if root:GetParent() == UIParent then root:StartMoving() end end)
    drag:SetScript("OnDragStop", function() root:StopMovingOrSizing() end)
    W.Label(header, "拍卖助手", 24, 16, 28, W.gold)
    W.Label(header, "产品与多配方列表 · 手动刷新", 200, 26, 13, W.muted)
    local close = CreateFrame("Button", nil, header, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", -6, -6)
    close:SetScript("OnClick", function() if A.open then A.Native.Navigate("buy") else root:Hide() end end)
    U.nativeButtons = {}
    for i, tab in ipairs({{"浏览", "buy"}, {"出售", "sell"}, {"我的拍卖", "owned"}}) do
        local mode = tab[2]
        local button = W.Button(header, tab[1], 120, 32, function() message(A.Native.Navigate(mode)) end)
        button:SetPoint("TOPLEFT", 22 + (i - 1) * 126, -62); U.nativeButtons[i] = button
    end
    local monitorTab = W.Button(header, "监控列表", 154, 32, function() A.Editor.Close() end)
    monitorTab:SetPoint("TOPLEFT", 400, -62); monitorTab:GetFontString():SetTextColor(unpack(W.gold))
    local body = CreateFrame("Frame", nil, frame); body:SetSize(1084, 570); body:SetPoint("TOPLEFT", 18, -110)
    U.body = body
    U.main = CreateFrame("Frame", nil, body); U.main:SetAllPoints(body)
    local list = W.Panel(U.main, 1084, 340); list:SetPoint("TOPLEFT")
    W.Label(list, "关注的产品", 16, 14, 21, W.gold)
    local add = W.Button(list, "+ 添加产品", 112, 28, function() A.Editor.Open() end); add:SetPoint("TOPLEFT", 156, -12)
    U.refreshButtons = {}
    for i, spec in ipairs({{"刷新售价", "sale"}, {"刷新材料", "materials"}, {"全部刷新", "all"}}) do
        local scope = spec[2]
        local button = W.Button(list, spec[1], 108, 28, function() request(scope) end)
        button:SetPoint("TOPRIGHT", -16 - (3 - i) * 116, -12); U.refreshButtons[scope] = button
    end
    U.refresh = U.refreshButtons.all
    for _, header in ipairs({{"产品 / 配方", 20}, {"产量", 264}, {"售价 / 件", 334}, {"成本 / 件", 448}, {"资料时间", 790}}) do
        W.Label(list, header[1], header[2], 58, 13, W.gold)
    end
    local profitSort = W.Button(list, "利润 / 件", 102, 24, function() U.sort = "unitProfit"; U.RefreshList() end)
    profitSort:SetPoint("TOPLEFT", 562, -50)
    local roiSort = W.Button(list, "利润率", 86, 24, function() U.sort = "roi"; U.RefreshList() end)
    roiSort:SetPoint("TOPLEFT", 686, -50)
    W.Label(list, "配方操作", 932, 58, 13, W.gold)
    U.list = W.Scroll(list, 1060, 238); U.list:SetPoint("TOPLEFT", 14, -86)
    U.empty = W.Label(list, "添加你关注的产品，再为每个产品建立材料配方。\n\n售价与材料价格都由你手动刷新。", 80, 150, 16, W.muted, 900)
    local materials = W.Panel(U.main, 740, 214); materials:SetPoint("TOPLEFT", 0, -352)
    U.materialTitle = W.Label(materials, "选择一套配方查看材料", 16, 14, 18, W.gold, 530)
    U.edit = W.Button(materials, "编辑配方", 112, 26, function() A.Editor.Open(A.Selected()) end)
    U.edit:SetPoint("TOPRIGHT", -16, -10)
    for _, header in ipairs({{"材料", 16}, {"用量", 264}, {"采购均价", 338}, {"小计", 458}, {"更新时间", 588}}) do
        W.Label(materials, header[1], header[2], 50, 12, W.gold)
    end
    U.materials = W.Scroll(materials, 710, 78); U.materials:SetPoint("TOPLEFT", 14, -73)
    U.profit = W.Label(materials, "预计利润 --", 16, 165, 15, W.green, 300)
    U.roi = W.Label(materials, "成本利润率 --", 336, 165, 14, W.green, 370)
    U.materialFoot = W.Label(materials, "", 16, 190, 12, W.muted, 708)
    local posting = W.Panel(U.main, 330, 214); posting:SetPoint("TOPRIGHT", 0, -352)
    W.Label(posting, "手动上架", 16, 14, 18, W.gold)
    W.Label(posting, "单价", 18, 60, 13)
    U.price = W.MoneyInput(posting, function(userInput) if userInput then U.priceEdited = true end end)
    U.price:SetPoint("TOPLEFT", 90, -49)
    W.Label(posting, "数量", 18, 96, 13)
    U.quantity = W.Edit(posting, 60, "1"); U.quantity:SetPoint("TOPLEFT", 96, -85)
    U.usePrice = W.Button(posting, "用最低价", 92, 26, function()
        local product = A.Selected(); local quote = product and A.quotes[product.itemID]
        if L.Fresh(quote, A.Now(), A.ttl) and quote.levels[1] then
            U.price:SetCopper(quote.levels[1].price); U.priceEdited = true; U.message:SetText("")
        else U.message:SetText("请先刷新成品售价。") end
    end); U.usePrice:SetPoint("TOPRIGHT", -16, -85)
    U.prepare = W.Button(posting, "准备上架", 298, 30, function()
        message(A.Native.PreparePost(A.Selected(), U.price:GetCopper(), tonumber(U.quantity:GetText())))
    end); U.prepare:SetPoint("TOPLEFT", 16, -124)
    U.stock = W.Label(posting, "", 18, 165, 12, W.muted, 298)
    W.Label(posting, "带入原生出售界面，确认后提交", 18, 190, 12, W.muted)
    U.message = W.Label(frame, "", 22, 684, 12, W.amber, 700)
    U.status = W.Label(frame, "", 22, 701, 11, W.muted, 780)
    U.freshness = W.Text(frame, "", 11, W.muted); U.freshness:SetPoint("BOTTOMRIGHT", -22, 9)
    A.Editor.Build(body)
    root:SetScript("OnShow", function() U.Layout(); U.Refresh() end)
    root:SetScript("OnHide", function()
        A.Market.Pause()
        C_Timer.After(0, function()
            if not A.open or root:IsShown() or not AuctionHouseFrame or not AuctionHouseFrame:IsShown()
                or AuctionHouseFrame:GetDisplayMode() then return end
            local state = LibStub("LibAHTab-1-0").internalState
            for _, tab in ipairs(state and state.Tabs or {}) do if tab.frameRef:IsShown() then return end end
            A.Native.Navigate("buy")
        end)
    end)
    U.Layout(); root:Hide()
end
