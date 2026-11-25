local _, A = ...
local U = { productRows = {}, materialRows = {}, selectedChanged = true, sort = "roi", durationID = 2 }
A.UI = U
local W, L = A.Widgets, A.Logic

local function message(ok, err)
    U.message:SetText(not ok and err or "")
    if not ok and err then A.Message(err) end
end
local function ready() return A.open and not A.Market.active and #A.Market.queue == 0 end
local function column(parent, x, width, size)
    local text = W.Text(parent, "", size or 13, W.text, width)
    text:SetPoint("LEFT", x, 0); text:SetWordWrap(false)
    return text
end

local function showHelp(owner, text)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT"); GameTooltip:SetText(text or ""); GameTooltip:Show()
end

local function fitName(label, text)
    text = text:gsub("[\r\n]", " ")
    label:SetText(text)
    -- Keep names on one line without shrinking prices or splitting a UTF-8 character.
    while text ~= "" and label:GetUnboundedStringWidth() > label:GetWidth() do
        text = text:gsub("[%z\1-\127\194-\244][\128-\191]*$", "")
        label:SetText(text)
    end
end

local function priceTimeText(itemID)
    local quote = A.quotes[itemID]
    local current = quote and quote.complete and not quote.error and quote.seenAt
    local records = A.profile.lastSeenPrices
    local saved = type(records) == "table" and records[itemID]
    local seenAt, price
    if current then
        seenAt, price = quote.seenAt, quote.levels[1] and quote.levels[1].price
    elseif type(saved) == "table" and saved.priceVersion == 2 then
        seenAt, price = saved.seenAt, saved.price
    end
    if not L.Number(seenAt, 1, 100000000000, true)
        or (price ~= nil and not L.Number(price, 0.000000001, 1000000000000, false)) then
        return "待采样", "尚无有效售价采样，请刷新关注产品。", true
    end
    local historical = not current or not A.open or quote.historical or A.Now() - quote.at > A.ttl
    local text = (historical and "历史 " or "") .. date("%m-%d %H:%M", seenAt)
    local help = "售价采样时间：" .. date("%Y-%m-%d %H:%M:%S", seenAt)
        .. "\n" .. (not current and saved.source == "browse" and "搜索列表参考价：" or "采样最低单价：")
        .. (price and L.Money(price) or "无一口价")
        .. "\n" .. (not current and "历史参考，未用于当前利润测算。"
            or historical and "上次完整监控报价，请刷新后确认当前价格。" or "当前监控报价。")
    return text, help, historical
end

local function buyItem(itemID) message(A.Native.OpenBuy(itemID)) end

function U.OpenProductMenu(owner, productID)
    local product = A.Product(productID)
    if not product then return end
    if not MenuUtil or not MenuUtil.CreateContextMenu then
        message(nil, "菜单尚未载入，请重载界面后重试。"); return
    end
    A.Select(productID)
    GameTooltip:Hide()
    MenuUtil.CreateContextMenu(owner, function(_, menu)
        menu:SetScrollMode(300)
        menu:CreateTitle((A.ItemInfo(product.itemID)))
        menu:CreateTitle("选用方案 · 净利润 / 件")
        for _, recipe in ipairs(product.recipes) do
            local recipeID, estimate = recipe.id, A.Estimate(product, recipe)
            local profit = estimate.error and "缺价" or (estimate.stale and "历史 " or "")
                .. (estimate.unitProfit and estimate.unitProfit > 0 and "+" or "") .. L.Money(estimate.unitProfit)
            menu:CreateRadio(recipe.name .. " · " .. profit, function()
                local current = A.Product(productID)
                return current and current.activeRecipeID == recipeID
            end, function() A.Select(productID, recipeID) end)
        end
        menu:CreateDivider()
        menu:CreateButton("编辑当前方案", function() A.Editor.Open(A.Product(productID)) end)
        menu:CreateButton("添加方案", function() A.Editor.Open(A.Product(productID), nil, true) end)
        menu:CreateDivider()
        menu:CreateButton("移除产品", function() StaticPopup_Show("AUCTIONPILOT_DELETE", nil, nil, productID) end)
    end)
end

local function menuButton(parent, callback)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(30, 30)
    button:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    button:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down")
    button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    button:SetScript("OnClick", callback)
    button:SetScript("OnEnter", function() showHelp(button, "切换方案、编辑或移除产品") end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return button
end

local function refreshButton(parent, help, callback)
    local button = CreateFrame("Button", nil, parent, "RefreshButtonTemplate")
    button:SetSize(28, 28)
    button.help = help
    button:SetScript("OnClick", callback)
    button:HookScript("OnEnter", function() showHelp(button, button.help) end)
    button:HookScript("OnLeave", function() GameTooltip:Hide() end)
    return button
end

local function scanHistorical(record)
    return record.historical or record.refreshError or not A.open or (record.at and A.Now()-record.at>A.ttl)
end

local function showScanHelp(owner, record, message, skipped)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    if record then
        local draft, estimate = record.draft, record.estimate
        GameTooltip:SetText((A.ItemInfo(draft.itemID)), 1, 1, 1)
        local color = W.ProfitColor(estimate.unitProfit)
        local profit = (estimate.unitProfit and estimate.unitProfit>0 and "+" or "") .. L.Money(estimate.unitProfit)
        GameTooltip:AddDoubleLine("每件净利", profit, .75,.75,.72, color[1],color[2],color[3])
        GameTooltip:AddDoubleLine("售价 / 件", L.Money(estimate.sale), .75,.75,.72, 1,1,1)
        GameTooltip:AddDoubleLine("总成本 / 件（含手续费）", L.Money(estimate.unitCost), .75,.75,.72, 1,1,1)
        if record.seenAt then GameTooltip:AddLine((scanHistorical(record) and "历史报价 " or "报价 ")
            .. date("%m-%d %H:%M:%S",record.seenAt), .65,.65,.62) end
        if draft.sourceOutputMax and draft.sourceOutputMax>draft.output then
            GameTooltip:AddLine("按最低产量 " .. draft.output .. " 件估算，金额均为每件。", .65,.65,.62, true)
        end
        local error = record.refreshError or estimate.error
        if error then GameTooltip:AddLine(error .. (record.refreshError and record.at and "；保留上次完整结果。" or ""), 1,.73,.28,true) end
    else GameTooltip:SetText("尚未扫描这个配方。", 1,1,1) end
    local note = skipped and skipped~="" and skipped or message
    if note and note~="" then GameTooltip:AddLine(note, 1,.73,.28,true) end
    GameTooltip:Show()
end

function U.ScanProfession(favorites)
    local p, M = U.profession, A.Market
    if not p or not A.Native.ProfessionVisible() then return nil, "请先打开专业制作页面并选择配方。" end
    if not A.open then return nil, "请先打开拍卖行，再扫描配方。" end
    if A.Editor.frame and A.Editor.frame:IsShown() then return nil, "请先保存或取消正在编辑的监控方案，再扫描。" end
    if M.batch and M.batch.scan and (M.active or #M.queue > 0) then return nil, "正在扫描，请等待完成。" end
    local drafts, skipped = {}, {}
    if favorites then
        local ids, err = A.Native.FavoriteRecipes()
        if not ids then return nil, err end
        for _, id in ipairs(ids) do
            local draft, why = A.ReadRecipeScan(id)
            if draft then drafts[#drafts + 1] = draft
            else
                skipped[#skipped + 1] = "#" .. id .. "：" .. why
                if A.scanResults[id] then A.scanResults[id].historical, A.scanResults[id].refreshError = true, why end
            end
        end
        if #drafts == 0 then return nil, #skipped > 0 and ("偏好配方暂不能扫描：" .. skipped[1]) or "当前专业没有标记为偏好的配方。" end
    else
        local draft, err = A.ReadRecipeScan()
        if not draft then return nil, err end
        drafts[1] = draft
    end
    M.Pause()
    A.Native.ShowMonitor()
    p.message = #skipped > 0 and ("跳过 " .. #skipped .. " 项；悬停查看原因") or ""
    p.skipped = table.concat(skipped, "\n")
    return M.RequestRecipes(drafts)
end

function U.RefreshProfessionRow(row)
    local p = U.profession
    if not p or not row.GetElementData then return end
    local node = row:GetElementData()
    local data = node and node.GetData and node:GetData()
    local info = data and data.recipeInfo
    if not info or not row.Label then
        if row.auctionPilotProfit then row.auctionPilotProfit:Hide() end
        row.auctionPilotRecipeID = nil
        return
    end
    if Professions and Professions.GetHighestLearnedRecipe then info = Professions.GetHighestLearnedRecipe(info) or info end
    row.auctionPilotRecipeID = info.recipeID
    if not row.auctionPilotProfit then
        row.auctionPilotProfit = W.Text(row, "", 11, W.muted, 78)
        row.auctionPilotProfit:SetJustifyH("RIGHT"); row.auctionPilotProfit:SetWordWrap(false)
        row:HookScript("OnLeave", function() GameTooltip:Hide() end)
        if row.SetCraftableCount then hooksecurefunc(row, "SetCraftableCount", function() U.RefreshProfessionRow(row) end) end
    end
    local locked = row.LockedIcon and row.LockedIcon:IsShown() and row.LockedIcon:GetWidth() or 0
    local count = row.Count and row.Count:IsShown() and row.Count:GetStringWidth() or 0
    row.auctionPilotProfit:ClearAllPoints(); row.auctionPilotProfit:SetPoint("RIGHT", row, "RIGHT", -locked - 4, 0)
    row.Label:SetWidth(math.max(24, math.min(row.Label:GetWidth(), row:GetWidth() - count - locked - 120)))
    local record, label = A.scanResults[info.recipeID], row.auctionPilotProfit
    if record and record.estimate.unitProfit then W.Amount(label, record.estimate.unitProfit, true)
    else label:SetText(record and "无法测算" or "未扫描"); label:SetTextColor(unpack(W.muted)) end
    if label:GetUnboundedStringWidth() > label:GetWidth() then label:SetText("悬停查看") end
    label:Show()
end

-- Native row initialization replaces its OnEnter handler on every pool reuse.
function U.InitializeProfessionRow(row)
    U.RefreshProfessionRow(row)
    if row.auctionPilotRecipeID then
        row:HookScript("OnEnter", function()
            if row.auctionPilotRecipeID then showScanHelp(row, A.scanResults[row.auctionPilotRecipeID]) end
        end)
    end
end

function U.RestoreProfessionSize()
    local p = U.profession
    if not p then return end
    local form = p.page.SchematicForm
    if p.appliedFormHeight and form:GetHeight() == p.appliedFormHeight then form:SetHeight(p.baseFormHeight) end
    if p.appliedHeight and p.root:GetHeight() == p.appliedHeight then p.root:SetHeight(p.baseHeight) end
    if p.appliedScale and p.root:GetScale() == p.appliedScale then p.root:SetScale(p.baseScale) end
    p.appliedHeight, p.appliedScale, p.appliedFormHeight = nil, nil, nil
end

function U.LayoutProfessionScan()
    local p = U.profession
    if not p or p.layingOut or not A.Native.ProfessionVisible() then return end
    p.layingOut = true
    local page, form, root = p.page, p.page.SchematicForm, p.root
    if not p.appliedHeight or root:GetHeight() ~= p.appliedHeight then p.baseHeight = root:GetHeight() end
    if not p.appliedScale or root:GetScale() ~= p.appliedScale then p.baseScale = root:GetScale() end
    if not p.appliedFormHeight or form:GetHeight() ~= p.appliedFormHeight then p.baseFormHeight = form:GetHeight() end
    local scale = form:GetEffectiveScale()
    local lowest = (form:GetTop() - 90) * scale
    for _, key in ipairs({"Description","Reagents","OptionalReagents","FinishingReagents","Details",
        "Cooldown","RecipeSourceButton","FirstCraftBonus","RecipeLevelBar"}) do
        local child = form[key]
        if child and child:IsShown() and child:GetBottom() then lowest = math.min(lowest, child:GetBottom() * child:GetEffectiveScale()) end
    end
    local top = (form:GetTop()*scale - lowest)/scale + 8
    local width = math.max(180, form:GetWidth() - 32)
    p.panel:SetWidth(width); p.panel:ClearAllPoints(); p.panel:SetPoint("TOPLEFT",form,"TOPLEFT",16,-top)
    p.title:SetWidth(width - p.current:GetWidth() - p.favorites:GetWidth() - 38)
    p.profit:SetWidth(width - 110); p.sale:SetWidth(width - 166); p.cost:SetWidth(width - 166)
    p.time:SetWidth(width - 132); p.status:SetWidth(width - 132)
    local reserve = 16
    for _, key in ipairs({"TrackRecipeCheckbox","AllocateBestQualityCheckbox"}) do
        local control = form[key]
        if control and control:IsShown() and control:GetTop() then
            reserve = math.max(reserve, (control:GetTop()*control:GetEffectiveScale() - form:GetBottom()*scale)/scale + 8)
        end
    end
    local needed = math.max(p.baseFormHeight, math.ceil(top + p.panel:GetHeight() + reserve))
    form:SetHeight(needed); p.appliedFormHeight = form:GetHeight()
    p.appliedHeight = p.baseHeight + p.appliedFormHeight - p.baseFormHeight
    root:SetHeight(p.appliedHeight)
    p.appliedHeight = root:GetHeight()
    p.appliedScale = math.min(p.baseScale, (UIParent:GetHeight()-44)/p.appliedHeight)
    root:SetScale(p.appliedScale)
    p.appliedScale = root:GetScale()
    p.layingOut = nil
end

function U.RefreshProfessionScan()
    local p = U.profession
    if not p or not A.Native.ProfessionVisible() then return end
    U.LayoutProfessionScan()
    local M, batch = A.Market, A.Market.batch
    local busy = batch and batch.scan and (M.active or #M.queue > 0)
    local editing = A.Editor.frame and A.Editor.frame:IsShown()
    p.current:SetEnabled(A.open and not busy and not editing); p.favorites:SetEnabled(A.open and not busy and not editing)
    p.current:SetText(busy and "扫描中…" or "扫描当前配方")
    p.page.RecipeList.ScrollBox:ForEachFrame(U.RefreshProfessionRow)
    local info = A.Native.CurrentRecipe()
    local record = info and A.scanResults[info.recipeID]
    local estimate = record and record.estimate
    p.title:SetText("利润 / 件")
    if record then
        W.Amount(p.sale, estimate.sale); W.Amount(p.cost, estimate.unitCost)
        W.Amount(p.profit, estimate.unitProfit, true)
        p.time:SetText((scanHistorical(record) and "历史 · " or "报价 ")
            .. (record.seenAt and date("%H:%M:%S",record.seenAt) or "未完成"))
    else
        W.Amount(p.sale,nil); W.Amount(p.cost,nil); W.Amount(p.profit,nil,true)
        p.time:SetText(not info and "请选择配方" or not A.open and "请先打开拍卖行" or "尚未扫描")
    end
    for _, label in ipairs({p.sale,p.cost,p.profit,p.time}) do
        if label:GetUnboundedStringWidth() > label:GetWidth() then label:SetText("悬停查看") end
    end
    local watched = false
    if info then
        for _, product in ipairs(A.profile.products) do
            for _, recipe in ipairs(product.recipes) do if recipe.sourceRecipeID == info.recipeID then watched = true end end
        end
    end
    p.add:SetEnabled(record ~= nil and not watched and not busy and not editing); p.add:SetText(watched and "已在监控" or "加入监控")
    local status = record and record.refreshError and (record.at and "刷新失败，保留上次结果" or "扫描失败，请重试")
        or record and record.estimate.error and "暂不能测算，悬停查看"
        or (p.message and p.message~="" and "提示：悬停查看") or ""
    if busy then
        local complete = 0; for _ in pairs(batch.scan.finished) do complete = complete + 1 end
        status = M.draining and "等待上次查询结束" or M.waitSince and "等待拍卖行响应"
            or ("扫描配方 " .. complete .. "/" .. #batch.scan.drafts)
    end
    if editing then status = "请先保存或取消编辑" end
    fitName(p.status,status)
    p.status:SetShown(status~=""); p.time:SetShown(status=="")
end

function U.BuildProfessionScan(page)
    if U.profession and U.profession.page == page then return end
    local p = {page=page,root=ProfessionsFrame,message=""}; U.profession = p
    local function start(favorites)
        local ok, err = U.ScanProfession(favorites)
        if not ok then p.message = err; A.Message(err); U.RefreshProfessionScan() end
    end
    p.panel = W.Panel(page.SchematicForm,430,158)
    p.current = W.Button(p.panel,"扫描当前配方",116,24,function() start(false) end)
    p.current:SetPoint("TOPRIGHT",p.panel,"TOPRIGHT",-12,-6)
    p.favorites = W.Button(p.panel,"扫描偏好",100,24,function() start(true) end)
    p.favorites:SetPoint("RIGHT",p.current,"LEFT",-6,0)
    p.title = W.Label(p.panel,"利润 / 件",12,10,13,W.gold,176); p.title:SetWordWrap(false)
    W.Label(p.panel,"净利润",12,46,13,W.muted,80)
    W.Label(p.panel,"售价",12,76,12,W.muted,80)
    W.Label(p.panel,"总成本（含手续费）",12,98,12,W.muted,142)
    p.profit = W.Text(p.panel,"--",22,W.muted,320); p.profit:SetPoint("TOPRIGHT",-12,-38)
    p.sale = W.Text(p.panel,"--",14,W.text,264); p.sale:SetPoint("TOPRIGHT",-12,-73)
    p.cost = W.Text(p.panel,"--",14,W.text,264); p.cost:SetPoint("TOPRIGHT",-12,-95)
    for _,label in ipairs({p.profit,p.sale,p.cost}) do label:SetJustifyH("RIGHT"); label:SetWordWrap(false) end
    p.add = W.Button(p.panel,"加入监控",100,24,function()
        local info = A.Native.CurrentRecipe()
        if info then local ok,err=A.AddRecipeScan(info.recipeID); p.message=not ok and err or ""; U.RefreshProfessionScan() end
    end); p.add:SetPoint("TOPLEFT",12,-124)
    p.time = W.Label(p.panel,"",120,130,11,W.muted,298); p.time:SetWordWrap(false)
    p.status = W.Label(p.panel,"",120,130,11,W.amber,298); p.status:SetWordWrap(false)
    p.panel:EnableMouse(true)
    p.panel:SetScript("OnEnter",function()
        local info=A.Native.CurrentRecipe()
        showScanHelp(p.panel,info and A.scanResults[info.recipeID],p.message,p.skipped)
    end)
    p.panel:SetScript("OnLeave",function() GameTooltip:Hide() end)
end


local function productRow(productID)
    if U.productRows[productID] then return U.productRows[productID] end
    local row = CreateFrame("Button", nil, U.list.content)
    row:SetSize(1036, 42)
    local divider = row:CreateTexture(nil, "BACKGROUND")
    divider:SetSize(1036, 1); divider:SetPoint("BOTTOMLEFT"); divider:SetColorTexture(0.4, 0.34, 0.22, 0.35)
    row.selected = row:CreateTexture(nil, "BACKGROUND")
    row.selected:SetAllPoints(); row.selected:SetColorTexture(0.63, 0.47, 0.16, 0.24)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.icon = W.Icon(row, 28); row.icon:SetPoint("LEFT", 8, 0)
    row.name = column(row, 46, 130, 15)
    row.alert = column(row, 180, 14, 16); row.alert:SetTextColor(unpack(W.amber))
    row.recipe = column(row, 202, 100)
    row.recipe:SetTextColor(unpack(W.muted))
    row.sale = column(row, 310, 102, 14)
    row.cost = column(row, 424, 98, 14)
    row.profit = column(row, 534, 98, 14)
    row.roi = column(row, 644, 92, 14)
    row.age = column(row, 746, 84, 12)
    row.priceTime = column(row, 840, 122, 11)
    for _, label in ipairs({row.sale, row.cost, row.profit, row.roi, row.age, row.priceTime}) do label:SetJustifyH("RIGHT") end
    row.refresh = refreshButton(row, "刷新该产品售价及全部配方材料", function()
        message(A.Market.RequestRefresh("all", productID))
    end); row.refresh:SetPoint("LEFT", 970, 0)
    row.menu = menuButton(row, function(owner) U.OpenProductMenu(owner, productID) end)
    row.menu:SetPoint("LEFT", 1002, 0)
    row:SetScript("OnClick", function() A.Select(productID) end)
    row:SetScript("OnEnter", function() showHelp(row, row.help) end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    U.productRows[productID] = row
    return row
end

function U.RefreshList()
    for key, button in pairs(U.sortButtons) do
        button.label:SetText(button.caption .. (U.sort == key and " ↓" or ""))
        button.label:SetTextColor(unpack(U.sort == key and W.gold or W.muted))
    end
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
    local y, visible = 0, {}
    for _, entry in ipairs(products) do
        local product, estimate = entry.product, entry.estimate
        local row, recipe = productRow(product.id), A.SelectedRecipe(product)
        visible[product.id] = true
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -y); row:Show()
        local name, icon = A.ItemInfo(product.itemID)
        fitName(row.name, name); row.icon:SetTexture(icon)
        fitName(row.recipe, recipe and recipe.name or "未选方案")
        row.selected:SetShown(A.profile.selectedID == product.id)
        row.refresh:SetEnabled(ready())
        W.Amount(row.sale, estimate.sale); W.Amount(row.cost, estimate.unitCost)
        W.Amount(row.profit, estimate.unitProfit, true)
        row.roi:SetText(estimate.roi and string.format("%.1f%%", estimate.roi) or "--")
        row.roi:SetTextColor(unpack(W.ProfitColor(estimate.roi)))
        row.age:SetText(estimate.refreshError and "刷新失败" or estimate.error and "待刷新 / 缺价"
            or (estimate.stale and "历史 · " or "") .. A.AgeText(estimate.age))
        row.age:SetTextColor(unpack((estimate.error or estimate.stale) and W.amber or W.muted))
        local priceTime, priceTimeHelp, historical = priceTimeText(product.itemID)
        row.priceTime:SetText(priceTime)
        row.priceTime:SetTextColor(unpack(historical and W.amber or W.muted))
        for _, label in ipairs({row.sale, row.cost, row.profit, row.roi, row.age, row.priceTime}) do
            if label:GetUnboundedStringWidth() > label:GetWidth() then label:SetText("悬停查看") end
        end
        if estimate.stale then row.profit:SetTextColor(unpack(W.muted)); row.roi:SetTextColor(unpack(W.muted)) end
        local quote = A.quotes[product.itemID]
        local alert = A.alerts[product.itemID]
        local alertText = alert and L.Fresh(quote, A.Now(), A.ttl) and A.AlertText(alert)
        row.alert:SetText(alertText and "!" or "")
        row.help = name .. " · " .. (recipe and recipe.name or "未选方案") .. "\n" .. A.RecipeNote(recipe)
            .. "\n售价 " .. L.Money(estimate.sale) .. " · 总成本 " .. L.Money(estimate.unitCost)
            .. " · 净利 " .. L.Money(estimate.unitProfit)
            .. "\n总成本利润率 " .. (estimate.roi and string.format("%.1f%%", estimate.roi) or "--")
            .. " · 报价时间 " .. (estimate.error and "待刷新 / 缺价" or A.AgeText(estimate.age))
            .. "\n" .. (estimate.error or (estimate.stale and "历史测算。" or "")
                .. "总成本含采购支出、额外费用和手续费；总成本利润率 = 净利润 ÷ 总成本。"
                .. "\n采购 " .. L.Money(estimate.materialCost / estimate.output)
                .. " · 额外费用 " .. L.Money(recipe.extra / recipe.output)
                .. " · 手续费 " .. L.Money(estimate.fee / estimate.output) .. " / 件"
                .. "\n时间为所用报价中最早的一项。")
            .. (estimate.refreshError and "\n" .. estimate.refreshError .. "；沿用上次完整报价作历史测算。" or "")
            .. (alertText and "\n" .. alertText or "") .. "\n\n" .. priceTimeHelp
            .. "\n单击查看采购明细；右侧箭头切换或管理方案。"
        y = y + 44
    end
    -- Do not hide live rows on the age ticker: a native menu closes when its owner hides.
    for id, row in pairs(U.productRows) do if not visible[id] then row:Hide() end end
    U.list.content:SetHeight(math.max(238, y))
    U.empty:SetShown(#products == 0)
end

local function materialRow(index)
    if U.materialRows[index] then return U.materialRows[index] end
    local row = CreateFrame("Button", nil, U.materials.content)
    row:SetSize(686, 34); row:SetPoint("TOPLEFT", 0, -(index - 1) * 34)
    row.icon = W.Icon(row, 24); row.icon:SetPoint("LEFT", 2, 0)
    row.name = column(row, 36, 120)
    row.name:SetTextColor(unpack(W.gold))
    row.quantity = column(row, 160, 30)
    row.cost = column(row, 202, 80)
    row.unit = column(row, 294, 80)
    row.marketQuantity = column(row, 386, 72, 12)
    row.tierCost = column(row, 466, 92, 12)
    row.age = column(row, 570, 78, 12)
    row.refresh = refreshButton(row, "刷新该材料的拍卖行报价", function()
        message(A.Market.RequestItem(row.itemID))
    end); row.refresh:SetPoint("LEFT", 654, 0)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row:SetScript("OnClick", function() buyItem(row.itemID) end)
    row:SetScript("OnEnter", function()
        showHelp(row, (row.help or "") .. (A.open and "\n点击打开该物品的购买页" or "\n请先打开拍卖行，再点击购买"))
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    U.materialRows[index] = row
    return row
end

function U.RefreshPosting()
    if not U.postButton then return end
    local product = A.Selected()
    local details = A.Native.PostDetails(product, U.price:GetCopper(), tonumber(U.quantity:GetText()), U.durationID)
    U.postPreview = details
    U.price:SetEnabled(product ~= nil)
    U.quantity:SetEnabled(product ~= nil)
    U.duration:SetEnabled(product ~= nil)
    U.maxQuantity:SetEnabled(details.available ~= nil and details.available > 0)
    U.postButton:SetEnabled(details.error == nil)
    local quote = product and A.quotes[product.itemID]
    U.usePrice:SetEnabled(A.open and L.Fresh(quote, A.Now(), A.ttl) and quote.levels[1] ~= nil)
    U.stock:SetText("可售 " .. (details.available or "--") .. " 件")
    local hours = ({12, 24, 48})[U.durationID]
    U.duration:SetText(hours and hours .. "小时" or "选择时长")
    W.Amount(U.deposit, details.deposit)
    W.Amount(U.totalPrice, details.total)
    local status = details.error or "带入原生出售页，核对后手动创建拍卖"
    fitName(U.postStatus, status)
    U.postStatus:SetTextColor(unpack(details.error and W.amber or W.muted))
    U.postHelp = status .. "\n押金以原生出售页为准，总价为扣费前的销售金额。"
end

function U.RefreshDetail()
    local product, recipe = A.Selected(), A.SelectedRecipe()
    U.detailMenu:SetEnabled(recipe ~= nil)
    U.recipeRefresh:SetEnabled(recipe ~= nil and ready())
    U.productLink:SetShown(product ~= nil and recipe ~= nil)
    U.vendorStock:SetShown(recipe ~= nil and recipe.purchase ~= nil)
    local quote = product and A.quotes[product.itemID]
    U.usePrice:SetEnabled(A.open and L.Fresh(quote, A.Now(), A.ttl) and quote.levels[1] ~= nil)
    if not product or not recipe then
        U.materialTitle:SetText("选择产品查看采购明细")
        U.recipeTitle:SetText("")
        U.profit:SetText("预计利润 --"); U.roi:SetText("总成本利润率 --")
        U.materialFoot:SetText("报价只在点击刷新按钮后更新。")
        for _, row in ipairs(U.materialRows) do row:Hide() end
        U.RefreshPosting()
        return
    end
    local estimate = A.Estimate(product, recipe)
    local productName, productIcon = A.ItemInfo(product.itemID)
    U.productLink.itemID = product.itemID
    U.productLink.icon:SetTexture(productIcon)
    U.materialTitle:SetText("")
    fitName(U.productLink.name, productName)
    fitName(U.recipeTitle, recipe.name .. (recipe.purchase and " · 每件核算" or " · 每次产出 " .. recipe.output .. " 件"))
    if recipe.purchase then U.vendorStock:SetText(A.VendorStockText(product.itemID)) end
    local materials = L.InputMaterials(L.RecipeInput(product, recipe))
    for i, material in ipairs(materials) do
        local row, info = materialRow(i), estimate.materials[i]
        local vendor = L.VendorPrice(material, A.profile.vendorPrices)
        row:Show(); row.itemID = material.itemID
        row.refresh:SetEnabled(ready())
        row.refresh.help = not L.UsesMarketPrice(material, A.profile.vendorPrices) and "刷新拍卖行参考价，悬停查看；采购成本不变"
            or "只刷新该物品的拍卖行报价"
        local name, icon = A.ItemInfo(material.itemID)
        fitName(row.name, name); row.icon:SetTexture(icon); row.quantity:SetText(tostring(material.quantity))
        W.Amount(row.unit, info and info.unit); W.Amount(row.cost, info and info.cost)
        local source = A.quotes[material.itemID]
        local age = source and A.Now() - source.at
        local historical = source and (source.historical or age > A.ttl)
        fitName(row.age, material.source == "fixed" and "固定价" or vendor and "商店价"
            or material.source == "vendor" and "商店缺价"
            or (historical and "历史 · " or "") .. A.AgeText(age))
        row.age:SetTextColor(unpack((info and info.error or historical
            and L.UsesMarketPrice(material, A.profile.vendorPrices)) and W.amber or W.muted))
        local level
        if source and source.complete and not source.error then
            for _, candidate in ipairs(source.levels) do
                if candidate.available > 0 then level = candidate; break end
            end
        end
        local marketText = level and (L.Money(level.price) .. " × " .. level.available)
            or source and source.complete and not source.error and (#source.levels > 0 and "无可买量" or "无挂单") or "--"
        local tierCost = level and math.ceil(level.price * level.available)
        local budgetError = tierCost and tierCost > 9007199254740991 and "整档采购额超出精确计算范围"
        if budgetError then tierCost = nil end
        row.marketQuantity:SetText(level and tostring(level.available) or marketText)
        W.Amount(row.tierCost, tierCost)
        for _, label in ipairs({row.marketQuantity, row.tierCost}) do
            label:SetTextColor(unpack(historical and W.amber or W.text))
            if label:GetUnboundedStringWidth() > label:GetWidth() then label:SetText("悬停查看") end
        end
        row.help = name .. "\n" .. (info and info.error or vendor and "商店整组价格按所需数量分摊，费用向上取整至铜。"
            or material.source == "fixed" and "按手填单价核算。" or "按需要的数量逐档核算采购支出。")
            .. "\nAH 最低可买价 × 可买量：" .. marketText .. "（排除自己的挂单）"
            .. "\n整档采购额：" .. (budgetError or L.Money(tierCost))
            .. "；按 AH 该档单价计算，不使用配方采购均价，也不包含更贵档位。"
            .. "\n" .. (historical and "历史参考 · " or "") .. A.AgeText(age)
            .. (source and source.refreshError and "\n" .. source.refreshError .. "；保留上次完整报价。" or "")
        if material.source == "fixed" or vendor then
            row.help = row.help .. (vendor and ("\n商店最低价 " .. L.Money(vendor.price) .. " / " .. vendor.stackCount
                .. " 件 · " .. date("%m-%d %H:%M", vendor.seenAt))
                or ("\n固定采购价 " .. L.Money(material.price)))
                .. "，刷新拍卖行不会修改成本。"
        end
        if vendor then row.help = row.help .. "\n" .. A.VendorSourceText(vendor)
            .. "\n" .. A.VendorStockText(material.itemID) .. "；仅为历史观察，不保证当前有货。" end
        if info and info.error then row.cost:SetText("--"); row.cost:SetTextColor(unpack(W.amber)) end
    end
    for i = #materials + 1, #U.materialRows do U.materialRows[i]:Hide() end
    U.materials.content:SetHeight(math.max(78, #materials * 34))
    U.profit:SetText((estimate.stale and "历史利润 " or "预计利润 ") .. L.Money(estimate.unitProfit) .. " / 件")
    U.profit:SetTextColor(unpack(estimate.stale and W.muted or W.ProfitColor(estimate.unitProfit)))
    U.roi:SetText("总成本利润率 " .. (estimate.roi and string.format("%.1f%%", estimate.roi) or "--"))
    U.roi:SetTextColor(unpack(estimate.stale and W.muted or W.ProfitColor(estimate.roi)))
    U.materialFoot:SetText(estimate.error or (recipe.purchase and "单品转售" or "产量 " .. recipe.output .. " 件")
        .. " · 抽成 " .. product.fee .. "% · 额外费用 " .. L.Money(recipe.extra) .. (recipe.purchase and " / 件" or " / 次"))
    if U.selectedChanged then
        U.price:SetCopper(L.Fresh(quote, A.Now(), A.ttl) and estimate.sale or nil)
        U.priceEdited = false; U.quantity:SetText("1"); U.selectedChanged = false; U.message:SetText("")
    elseif not U.priceEdited and quote and quote.historical then
        U.price:SetCopper(nil)
    elseif not U.priceEdited and not U.price:GetCopper() and L.Fresh(quote, A.Now(), A.ttl) and estimate.sale then
        U.price:SetCopper(estimate.sale)
    end
    U.RefreshPosting()
end

function U.Refresh()
    U.RefreshProfessionScan()
    if not U.frame or not U.frame:IsShown() or not A.profile then return end
    for _, button in ipairs(U.nativeButtons) do button:SetEnabled(A.open) end
    U.refresh:SetEnabled(ready())
    U.refresh:SetText((A.Market.active or #A.Market.queue > 0) and "刷新中…" or "全部刷新")
    U.auto:SetText(A.Market.auto and "自动刷新：开" or "自动刷新：关")
    U.auto:SetEnabled(A.open and (A.Market.auto or ready()))
    local market, status = A.Market
    local active, batch = market.active, market.batch
    if not A.open then status = "拍卖行未打开 · 可编辑监控方案"
    elseif market.draining then status = "等待上次查询结束，再开始下一次采样"
    elseif batch and batch.stopped then status = batch.stopped
    elseif market.waitSince then status = "等待拍卖行限流恢复 · " .. math.floor(A.Now() - market.waitSince) .. "/30秒"
    elseif active then
        local retry = batch and batch.attempts[active.itemID] == 2
        status = (retry and "重试1/1 · " or "") .. (active.more and "补全行情：" or "正在查询：") .. A.ItemInfo(active.itemID)
    elseif #market.queue > 0 then
        local nextAt
        for _, id in ipairs(market.queue) do
            local at = math.max(market.nextSend, market.discardUntil[id] or 0)
            nextAt = nextAt and math.min(nextAt, at) or at
        end
        status = "等待发送或失败项重试 · " .. math.ceil(math.max(0, nextAt - A.Now())) .. "秒"
    elseif market.auto then status = "自动刷新关注成品 · 下一轮 "
        .. math.ceil(math.max(0, (market.nextAuto or A.Now()) - A.Now())) .. " 秒后"
    elseif batch then status = "本轮结束"
    else status = "手动刷新模式 · 点击按钮后更新报价与利润" end
    if A.open and batch then
        status = "完成 " .. batch.completed .. " · 失败 " .. batch.failed .. " · 待查 "
            .. (batch.total - batch.completed - batch.failed) .. " · " .. status
    end
    fitName(U.status, status)
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
    W.Label(header, "利润监控 · 价格记录", 200, 26, 13, W.muted)
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
    U.main:SetScript("OnHide", function() A.Market.Pause() end)
    local list = W.Panel(U.main, 1084, 340); list:SetPoint("TOPLEFT")
    W.Label(list, "关注的产品", 16, 14, 21, W.gold)
    local add = W.Button(list, "+ 添加产品", 112, 28, function() A.Editor.Open() end); add:SetPoint("TOPLEFT", 156, -12)
    W.Label(list, "按当前选用方案测算", 294, 21, 13, W.muted)
    U.refresh = W.Button(list, "全部刷新", 112, 28, function() message(A.Market.RequestRefresh("all")) end)
    U.refresh:SetPoint("TOPRIGHT", -16, -12)
    U.auto = W.Button(list, "自动刷新：关", 144, 28, function() message(A.Market.SetAuto(not A.Market.auto)) end)
    U.auto:SetPoint("TOPRIGHT", -136, -12)
    U.auto:SetScript("OnEnter", function()
        showHelp(U.auto, "只刷新关注成品，记录最低售价与采样时间；每轮完成后等待 30 秒。\n材料按需手动刷新。离开列表暂停，返回继续采集；关闭拍卖行自动关闭。")
    end)
    U.auto:SetScript("OnLeave", function() GameTooltip:Hide() end)
    W.Label(list, "产品", 22, 58, 13, W.gold)
    W.Label(list, "当前方案", 216, 58, 13, W.gold)
    for _, spec in ipairs({{"售价 / 件", 324, 102}, {"总成本 / 件", 438, 98}, {"报价时间", 760, 84},
        {"售价采样时间", 854, 122}}) do
        local label = W.Label(list, spec[1], spec[2], 58, 13, W.gold, spec[3])
        label:SetJustifyH("RIGHT"); label:SetWordWrap(false)
    end
    U.sortButtons = {}
    for _, spec in ipairs({{"净利 / 件", "unitProfit", 548, 98}, {"总成本利润率", "roi", 658, 92}}) do
        local key = spec[2]
        local button = CreateFrame("Button", nil, list)
        button:SetSize(spec[4], 28); button:SetPoint("TOPLEFT", spec[3], -50)
        button.label = column(button, 0, spec[4]); button.label:SetJustifyH("RIGHT")
        button.caption = spec[1]
        button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        button:SetScript("OnClick", function() U.sort = key; U.RefreshList() end)
        U.sortButtons[key] = button
    end
    U.list = W.Scroll(list, 1060, 238); U.list:SetPoint("TOPLEFT", 14, -86)
    U.empty = W.Label(list, "添加产品，选择配方制作或单品转售，再点「全部刷新」查看利润。\n\n每个产品一行，右侧箭头可切换和管理方案。", 80, 150, 16, W.muted, 900)
    local materials = W.Panel(U.main, 740, 214); materials:SetPoint("TOPLEFT", 0, -352)
    U.materialTitle = W.Label(materials, "选择产品查看采购明细", 16, 14, 18, W.gold, 650)
    U.productLink = CreateFrame("Button", nil, materials)
    U.productLink:SetSize(224, 32); U.productLink:SetPoint("TOPLEFT", 16, -8)
    U.productLink.icon = W.Icon(U.productLink, 24); U.productLink.icon:SetPoint("LEFT")
    U.productLink.name = column(U.productLink, 32, 190, 16)
    U.productLink.name:SetTextColor(unpack(W.gold))
    U.productLink:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    U.productLink:SetScript("OnClick", function() buyItem(U.productLink.itemID) end)
    U.productLink:SetScript("OnEnter", function()
        showHelp(U.productLink, (A.ItemInfo(U.productLink.itemID))
            .. (A.open and "\n点击打开该成品的购买页" or "\n请先打开拍卖行，再点击购买"))
    end)
    U.productLink:SetScript("OnLeave", function() GameTooltip:Hide() end)
    U.recipeTitle = W.Label(materials, "", 250, 17, 13, W.muted, 402); U.recipeTitle:SetWordWrap(false)
    U.recipeRefresh = refreshButton(materials, "刷新当前方案的售价及所需 AH 采购价", function()
        local product, recipe = A.Selected(), A.SelectedRecipe()
        if product and recipe then message(A.Market.RequestRefresh("all", product.id, recipe.id)) end
    end); U.recipeRefresh:SetPoint("TOPRIGHT", -48, -9)
    U.detailMenu = menuButton(materials, function(owner) U.OpenProductMenu(owner, A.profile.selectedID) end)
    U.detailMenu:SetPoint("TOPRIGHT", -12, -8)
    for _, header in ipairs({{"采购物品", 16}, {"用量", 174}, {"小计", 216}, {"采购均价", 308},
        {"最低档数量", 400}, {"整档采购额", 480}, {"时间/来源", 584}}) do
        W.Label(materials, header[1], header[2], 50, 12, W.gold)
    end
    U.materials = W.Scroll(materials, 710, 78); U.materials:SetPoint("TOPLEFT", 14, -73)
    U.vendorStock = W.Label(materials, "", 16, 122, 13, W.muted, 690)
    U.profit = W.Label(materials, "预计利润 --", 16, 165, 15, W.green, 300)
    U.roi = W.Label(materials, "总成本利润率 --", 336, 165, 14, W.green, 370)
    U.materialFoot = W.Label(materials, "", 16, 190, 12, W.muted, 708)
    local posting = W.Panel(U.main, 330, 214); posting:SetPoint("TOPRIGHT", 0, -352)
    W.Label(posting, "上架准备", 16, 12, 16, W.gold)
    U.stock = W.Label(posting, "", 144, 15, 12, W.muted, 170); U.stock:SetJustifyH("RIGHT")
    local function inputChanged()
        U.RefreshPosting()
    end
    W.Label(posting, "单价", 16, 45, 12)
    U.price = W.MoneyInput(posting, function(userInput)
        if userInput then U.priceEdited = true end
        inputChanged(userInput)
    end); U.price:SetPoint("TOPLEFT", 56, -36)
    W.Label(posting, "数量", 16, 77, 12)
    U.quantity = W.Edit(posting, 70, "1"); U.quantity:SetPoint("TOPLEFT", 64, -68)
    U.quantity:SetMaxLetters(6)
    U.quantity:SetScript("OnTextChanged", function(_, userInput) inputChanged(userInput) end)
    U.maxQuantity = W.Button(posting, "最大", 48, 26, function()
        local count = U.postPreview and U.postPreview.available
        if count then U.quantity:SetText(tostring(math.min(100000, count))); inputChanged(true) end
    end); U.maxQuantity:SetPoint("TOPLEFT", 142, -68)
    W.Label(posting, "时长", 200, 77, 12)
    U.duration = W.Button(posting, "24小时", 84, 26, function(owner)
        MenuUtil.CreateContextMenu(owner, function(_, menu)
            for index, hours in ipairs({12, 24, 48}) do
                local duration = index
                menu:CreateRadio(hours .. " 小时", function() return U.durationID == duration end, function()
                    U.durationID = duration; inputChanged(true)
                end)
            end
        end)
    end); U.duration:SetPoint("TOPLEFT", 230, -68)
    local durationText = U.duration:GetFontString()
    durationText:ClearAllPoints(); durationText:SetPoint("LEFT", 8, 0)
    durationText:SetWidth(60); durationText:SetJustifyH("LEFT"); durationText:SetWordWrap(false)
    local durationArrow = U.duration:CreateTexture(nil, "OVERLAY")
    durationArrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    durationArrow:SetSize(16, 16); durationArrow:SetPoint("RIGHT", -1, 0)
    U.usePrice = W.Button(posting, "最低价", 64, 26, function()
        local product = A.Selected(); local quote = product and A.quotes[product.itemID]
        if L.Fresh(quote, A.Now(), A.ttl) and quote.levels[1] then
            U.price:SetCopper(quote.levels[1].price); U.priceEdited = true; U.message:SetText("")
            inputChanged(true)
        else U.message:SetText("请先刷新成品售价。") end
    end); U.usePrice:SetPoint("TOPLEFT", 250, -36)
    W.Label(posting, "押金", 16, 108, 12, W.muted)
    U.deposit = W.Label(posting, "--", 58, 108, 13, W.text, 256); U.deposit:SetJustifyH("RIGHT"); U.deposit:SetWordWrap(false)
    W.Label(posting, "总价", 16, 130, 12, W.muted)
    U.totalPrice = W.Label(posting, "--", 58, 130, 13, W.gold, 256); U.totalPrice:SetJustifyH("RIGHT"); U.totalPrice:SetWordWrap(false)
    U.postButton = W.Button(posting, "准备上架", 298, 28, function()
        message(A.Native.PreparePost(A.Selected(), U.price:GetCopper(), tonumber(U.quantity:GetText()), U.durationID))
    end); U.postButton:SetPoint("TOPLEFT", 16, -154)
    U.postStatus = W.Label(posting, "", 16, 190, 11, W.muted, 298); U.postStatus:SetWordWrap(false)
    posting:EnableMouse(true)
    posting:SetScript("OnEnter", function() showHelp(posting, U.postHelp) end)
    posting:SetScript("OnLeave", function() GameTooltip:Hide() end)
    U.message = W.Label(frame, "", 22, 684, 12, W.amber, 700)
    U.status = W.Label(frame, "", 22, 701, 11, W.muted, 780)
    U.freshness = W.Text(frame, "", 11, W.muted); U.freshness:SetPoint("BOTTOMRIGHT", -22, 9)
    A.Editor.Build(body)
    A.Editor.frame:HookScript("OnShow", U.RefreshProfessionScan)
    root:SetScript("OnShow", function() U.Layout(); U.Refresh() end)
    root:SetScript("OnHide", function()
        A.Market.Pause()
        U.RefreshProfessionScan()
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
