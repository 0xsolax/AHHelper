local _, A = ...
local E = { rows = {} }
A.Editor = E
local W = A.Widgets

function E.Read()
    local draft = { id = E.id, itemID = E.item.itemID, output = tonumber(E.output:GetText()),
        recipeID = E.recipeID, recipeName = E.name:GetText(), fee = tonumber(E.fee:GetText()),
        extra = E.extra:GetCopper(), alert = E.alert:GetChecked(), materials = {}, sourceRecipeID = E.sourceRecipeID,
        sourceOutputMin = E.sourceOutputMin, sourceOutputMax = E.sourceOutputMax }
    for _, row in ipairs(E.rows) do
        if row:IsShown() then
            table.insert(draft.materials, { itemID = row.item.itemID, quantity = tonumber(row.quantity:GetText()),
                source = row.source, price = row.price:GetCopper() })
        end
    end
    return draft
end

function E.Preview()
    if E.loading or not E.frame or not E.frame:IsShown() then return end
    local draft = E.Read()
    E.sourceNote:SetText(A.RecipeNote(draft))
    local estimate = A.EstimateInput(draft)
    local index = 0
    for _, row in ipairs(E.rows) do
        if row:IsShown() then
            index = index + 1
            if row.source == "market" then row.price:SetCopper(estimate.materials[index] and estimate.materials[index].unit) end
        end
    end
    E.warning:SetText(estimate.error or (estimate.stale and "历史测算 · " or "")
        .. "行情 " .. A.AgeText(estimate.age) .. "；返回列表可手动刷新。")
    E.warning:SetTextColor(unpack((estimate.error or estimate.stale) and W.amber or W.muted))
    W.Amount(E.sale, estimate.sale)
    W.Amount(E.cost, estimate.cost)
    W.Amount(E.cut, estimate.fee)
    W.Amount(E.net, estimate.net)
    W.Amount(E.profit, estimate.unitProfit, true)
    E.profit:SetText(E.profit:GetText() .. " / 件")
    E.roi:SetText(estimate.roi and string.format("%.1f%%", estimate.roi) or "--")
    E.roi:SetTextColor(unpack(W.ProfitColor(estimate.roi)))
end

function E.ArrangeRows()
    local index = 0
    for _, row in ipairs(E.rows) do
        if row:IsShown() then
            row:ClearAllPoints(); row:SetPoint("TOPLEFT", E.scroll.content, "TOPLEFT", 0, -index * 50)
            index = index + 1
        end
    end
    E.scroll.content:SetHeight(math.max(230, index * 50))
    E.Preview()
end

function E.AddMaterial(material)
    local row
    for _, existing in ipairs(E.rows) do if not existing:IsShown() then row = existing; break end end
    if not row then
        row = CreateFrame("Frame", nil, E.scroll.content)
        row:SetSize(674, 48)
        row.item = W.ItemInput(row, 260, E.Preview); row.item:SetPoint("LEFT", 0, 0)
        row.quantity = W.Edit(row, 48, "1"); row.quantity:SetPoint("LEFT", 281, 0)
        row.quantity:SetScript("OnTextChanged", E.Preview)
        row.sourceButton = W.Button(row, "拍卖行", 92, 26, function()
            row.source = row.source == "market" and "fixed" or "market"
            row.sourceButton:SetText(row.source == "market" and "拍卖行" or "固定价")
            row.price:SetEnabled(row.source == "fixed")
            E.Preview()
        end)
        row.sourceButton:SetPoint("LEFT", 346, 0)
        row.price = W.MoneyInput(row, E.Preview); row.price:SetPoint("LEFT", 444, 0)
        row.remove = W.Button(row, "移除", 40, 24, function() row:Hide(); E.ArrangeRows() end)
        row.remove:SetPoint("RIGHT", 0, 0)
        table.insert(E.rows, row)
    end
    local wasLoading = E.loading
    E.loading = true
    row:Show()
    row.item:SetItem(material and material.itemID)
    row.quantity:SetText(material and tostring(material.quantity) or "1")
    row.source = material and material.source or "market"
    row.sourceButton:SetText(row.source == "market" and "拍卖行" or "固定价")
    row.price:SetCopper(material and material.price or nil)
    row.price:SetEnabled(row.source == "fixed")
    E.loading = wasLoading
    E.ArrangeRows()
end

function E.Open(product, recipe, adding)
    E.loading = true
    E.id = product and product.id
    if product and not adding then recipe = recipe or A.SelectedRecipe(product) else recipe = nil end
    E.recipeID = recipe and recipe.id
    E.sourceRecipeID = recipe and recipe.sourceRecipeID
    E.sourceOutputMin, E.sourceOutputMax = recipe and recipe.sourceOutputMin, recipe and recipe.sourceOutputMax
    A.UI.main:Hide()
    E.frame:Show()
    E.title:SetText(recipe and "编辑配方" or product and "添加配方" or "添加产品与首个配方")
    E.item:SetItem(product and product.itemID)
    E.item:SetEnabled(product == nil)
    E.name:SetText(recipe and recipe.name or product and ("配方" .. product.nextRecipeID) or "默认配方")
    E.output:SetText(recipe and tostring(recipe.output) or "1")
    E.fee:SetText(product and tostring(product.fee) or "5")
    E.extra:SetCopper(recipe and recipe.extra or 0)
    E.alert:SetChecked(not product or product.alert)
    E.delete:SetShown(recipe ~= nil)
    E.delete:SetEnabled(product ~= nil and #product.recipes > 1)
    E.removeProduct:SetShown(product ~= nil)
    for _, row in ipairs(E.rows) do row:Hide() end
    if recipe then for _, material in ipairs(recipe.materials) do E.AddMaterial(material) end
    else E.AddMaterial() end
    E.loading = false
    E.error:SetText("")
    E.Preview()
end

function E.ImportRecipe()
    local draft, err = A.Native.ReadRecipe()
    if not draft then E.error:SetText(err); return end
    local product = E.id and A.Product(E.id)
    if product and product.itemID ~= draft.itemID then
        E.error:SetText("所选配方的成品与当前产品不同，请使用「添加产品」。"); return
    end
    local prices = {}
    for _, row in ipairs(E.rows) do
        if row:IsShown() and row.item.itemID then prices[row.item.itemID] = { source = row.source, price = row.price:GetCopper() } end
    end
    E.loading = true
    E.item:SetItem(draft.itemID); E.name:SetText(draft.recipeName); E.output:SetText(tostring(draft.output))
    E.sourceRecipeID, E.sourceOutputMin, E.sourceOutputMax = draft.sourceRecipeID, draft.sourceOutputMin, draft.sourceOutputMax
    for _, row in ipairs(E.rows) do row:Hide() end
    for _, material in ipairs(draft.materials) do
        local previous = prices[material.itemID]
        if previous then material.source, material.price = previous.source, previous.price end
        E.AddMaterial(material)
    end
    E.loading = false; E.error:SetText(""); E.Preview()
end

function E.Close()
    E.frame:Hide()
    A.UI.main:Show()
    A.RefreshUI()
end

function E.Build(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints(parent)
    E.frame = frame
    E.title = W.Label(frame, "添加监控", 0, 0, 24, W.gold)
    W.Label(frame, "读取专业配方；或点击物品输入框后 Shift 点击物品填入", 0, 32, 13, W.muted)
    W.Label(frame, "出售商品", 8, 65, 14)
    E.item = W.ItemInput(frame, 348, E.Preview); E.item:SetPoint("TOPLEFT", 8, -87)
    W.Label(frame, "配方名称", 400, 65, 14)
    E.name = W.Edit(frame, 160, "默认配方"); E.name:SetPoint("TOPLEFT", 406, -90)
    E.name:SetMaxLetters(32)
    W.Label(frame, "每次产量", 590, 65, 14)
    E.output = W.Edit(frame, 64, "1"); E.output:SetPoint("TOPLEFT", 596, -90)
    E.output:SetScript("OnTextChanged", E.Preview)
    W.Label(frame, "件", 670, 96, 13, W.muted)
    E.sourceNote = W.Label(frame, "手动配置", 8, 125, 12, W.muted, 520)
    E.import = W.Button(frame, "读取当前配方", 154, 26, E.ImportRecipe)
    E.import:SetPoint("TOPLEFT", 548, -119)
    W.Label(frame, "采购材料", 8, 157, 18, W.gold)
    W.Label(frame, "物品", 8, 188, 13, W.muted)
    W.Label(frame, "用量", 286, 188, 13, W.muted)
    W.Label(frame, "价格来源", 350, 188, 13, W.muted)
    W.Label(frame, "采购单价", 458, 188, 13, W.muted)
    E.scroll = W.Scroll(frame, 698, 180); E.scroll:SetPoint("TOPLEFT", 8, -210)
    local add = W.Button(frame, "+ 添加材料", 112, 26, function() E.AddMaterial() end)
    add:SetPoint("TOPLEFT", 8, -397)
    W.Label(frame, "产品费率", 8, 443, 14)
    E.fee = W.Edit(frame, 54, "5"); E.fee:SetPoint("TOPLEFT", 111, -434)
    E.fee:SetScript("OnTextChanged", E.Preview)
    W.Label(frame, "%", 174, 442, 14, W.muted)
    W.Label(frame, "额外费用 / 次", 245, 443, 14)
    E.extra = W.MoneyInput(frame, E.Preview); E.extra:SetPoint("TOPLEFT", 364, -434)
    E.alert = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    E.alert:SetSize(26, 26); E.alert:SetPoint("TOPLEFT", 4, -475)
    W.Label(frame, "手动刷新售价后，发现竞争变化时提醒", 34, 481, 14)
    local preview = W.Panel(frame, 356, 458); preview:SetPoint("TOPRIGHT", 0, -56)
    W.Label(preview, "利润预览", 20, 20, 22, W.gold)
    local function previewRow(label, y)
        W.Label(preview, label, 20, y, 14, W.muted)
        local value = W.Text(preview, "--", 16)
        value:SetPoint("TOPRIGHT", -20, -y); value:SetJustifyH("RIGHT")
        return value
    end
    E.sale = previewRow("售价 / 件", 70)
    E.cost = previewRow("成本 / 次", 108)
    E.cut = previewRow("成交抽成 / 次", 146)
    E.net = previewRow("预计到手 / 次", 203)
    E.profit = W.Label(preview, "-- / 件", 20, 259, 30, W.green, 316)
    E.roi = previewRow("成本利润率", 320)
    E.warning = W.Label(preview, "", 20, 375, 13, W.muted, 316)
    E.error = W.Label(frame, "", 8, 515, 13, W.red, 700)
    E.delete = W.Button(frame, "删除配方", 100, 30, function()
        StaticPopup_Show("AUCTIONPILOT_DELETE_RECIPE", nil, nil, { productID = E.id, recipeID = E.recipeID })
    end); E.delete:SetPoint("BOTTOMLEFT", 0, 0)
    E.removeProduct = W.Button(frame, "移除产品", 100, 30, function()
        StaticPopup_Show("AUCTIONPILOT_DELETE", nil, nil, E.id)
    end); E.removeProduct:SetPoint("BOTTOMLEFT", 112, 0)
    local cancel = W.Button(frame, "取消", 92, 32, E.Close); cancel:SetPoint("BOTTOMRIGHT", -166, 0)
    local save = W.Button(frame, "保存配方", 150, 34, function()
        local ok, err = A.SaveProduct(E.Read())
        if ok then E.Close() else E.error:SetText(err) end
    end); save:SetPoint("BOTTOMRIGHT", 0, 0)
    frame:Hide()
end

StaticPopupDialogs.AUCTIONPILOT_DELETE = {
    text = "移除这个产品及全部配方？已上架的拍卖不会改变。", button1 = "移除", button2 = "取消",
    OnAccept = function(_, id) A.DeleteProduct(id); E.Close() end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs.AUCTIONPILOT_DELETE_RECIPE = {
    text = "删除这套配方？其他配方和已上架的拍卖不会改变。", button1 = "删除", button2 = "取消",
    OnAccept = function(_, data)
        local ok, err = A.DeleteRecipe(data.productID, data.recipeID)
        if ok then E.Close() else E.error:SetText(err) end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}
