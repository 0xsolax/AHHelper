local _, A = ...
local N = {}
A.Native = N

function N.RecordMerchantPrices()
    if not C_MerchantFrame or not C_MerchantFrame.GetItemInfo
        or not GetMerchantItemID or not GetMerchantNumItems then return end
    local tracked = A.PruneVendorPrices()
    if not next(tracked) then return end
    local L = A.Logic
    for index = 1, GetMerchantNumItems() or 0 do
        local itemID = GetMerchantItemID(index)
        if tracked[itemID] then
            local info = C_MerchantFrame.GetItemInfo(index)
            if info and info.name and info.name ~= "" and info.isPurchasable and info.numAvailable == -1
                and not info.hasExtendedCost and not info.currencyID and not info.spellID
                and L.Number(info.price, 1, 1000000000000, true)
                and L.Number(info.stackCount, 1, 100000, true) then
                local previous = L.VendorPrice({itemID = itemID, source = "vendor"}, A.profile.vendorPrices)
                A.profile.vendorPrices[itemID] = { price = info.price, stackCount = info.stackCount, seenAt = GetServerTime() }
                if not previous or previous.price / previous.stackCount ~= info.price / info.stackCount then
                    local _, _, link = A.ItemInfo(itemID)
                    local unit = (info.price % info.stackCount ~= 0 and "约 " or "") .. L.Money(info.price / info.stackCount)
                    A.Message((previous and "商店价已更新：" or "已记录商店价：") .. (link or info.name)
                        .. " · " .. unit .. " / 件（" .. L.Money(info.price) .. " / " .. info.stackCount .. " 件）")
                end
            end
        end
    end
    A.RefreshUI()
end

-- Read only the native profession selection; never craft or change its filters.
function N.ReadRecipe()
    local form = ProfessionsFrame and ProfessionsFrame.CraftingPage and ProfessionsFrame.CraftingPage.SchematicForm
    if not form or not form.GetRecipeInfo then return nil, "请先打开专业窗口并选择一个配方，再点击读取。" end
    if not C_TradeSkillUI or not C_TradeSkillUI.GetRecipeSchematic then return nil, "当前客户端没有可用的配方读取接口。" end
    local ok, info, schematic = pcall(function()
        local selected = form:GetRecipeInfo()
        if not selected or not selected.recipeID then return end
        local level = form.GetCurrentRecipeLevel and form:GetCurrentRecipeLevel() or nil
        return selected, C_TradeSkillUI.GetRecipeSchematic(selected.recipeID, false, level)
    end)
    if not ok or not info or not schematic or schematic.recipeID ~= info.recipeID then
        return nil, "配方尚未载入，请在专业窗口重新选择后再读取。"
    end
    local L = A.Logic
    if info.isRecraft or info.isSalvageRecipe or info.isGatheringRecipe or info.supportsQualities
        or not L.ItemID(schematic.outputItemID) then
        return nil, "该配方没有固定的成品物品，或需要品质、分解等特殊计算；请手动配置。"
    end
    local minimum, maximum = schematic.quantityMin, schematic.quantityMax
    if not L.Number(minimum, 1, 100000, true) or not L.Number(maximum, minimum, 100000, true) then
        return nil, "尚未读取到有效产量，请稍后重试。"
    end
    if type(schematic.reagentSlotSchematics) ~= "table" then return nil, "材料数据尚未载入，请稍后重试。" end
    local materials, byItem = {}, {}
    for _, slot in ipairs(schematic.reagentSlotSchematics) do
        -- Ambiguous alternatives must not silently become a cheap baseline.
        if not Enum.CraftingReagentType or slot.reagentType ~= Enum.CraftingReagentType.Basic
            or type(slot.reagents) ~= "table" or #slot.reagents ~= 1
            or not L.Number(slot.quantityRequired, 1, 100000, true)
            or (slot.variableQuantities and next(slot.variableQuantities)) then
            return nil, "配方含可选材料、替代材料或变化用量，请手动配置所选方案。"
        end
        local reagent = slot.reagents[1]
        if not L.ItemID(reagent.itemID) or reagent.currencyID then return nil, "配方包含非物品材料，请手动配置费用。" end
        local material = byItem[reagent.itemID]
        if material then material.quantity = material.quantity + slot.quantityRequired
        else
            material = { itemID = reagent.itemID, quantity = slot.quantityRequired, source = "market" }
            table.insert(materials, material); byItem[reagent.itemID] = material
        end
    end
    local draft = { itemID = schematic.outputItemID, output = minimum, fee = 5, extra = 0, materials = materials,
        recipeName = (schematic.name or info.name or "专业配方") .. " #" .. info.recipeID,
        sourceRecipeID = info.recipeID, sourceOutputMin = minimum, sourceOutputMax = maximum }
    local valid, err = L.Validate(draft)
    if not valid then return nil, err end
    return draft
end

function N.Attach()
    if not A.open or not AuctionHouseFrame or not A.UI.frame then return false end
    local lib = LibStub("LibAHTab-1-0")
    A.UI.frame:SetParent(AuctionHouseFrame)
    A.UI.Layout()
    if not N.layoutHooked then
        AuctionHouseFrame:HookScript("OnSizeChanged", function()
            if A.UI.frame:GetParent() == AuctionHouseFrame then A.UI.Layout() end
        end)
        N.layoutHooked = true
    end
    if not lib:DoesIDExist("AuctionPilot") then
        lib:CreateTab("AuctionPilot", A.UI.frame, "监控利润", "拍卖助手")
    end
    return true
end

function N.ShowMonitor()
    if N.Attach() then LibStub("LibAHTab-1-0"):SetSelected("AuctionPilot") end
end

function N.Navigate(mode)
    if not A.open or not AuctionHouseFrame then return nil, "请先与拍卖师交谈。" end
    local modes = AuctionHouseFrameDisplayMode
    local selected = mode == "buy" and modes.Buy or mode == "sell" and modes.ItemSell or modes.Auctions
    A.Market.Pause()
    AuctionHouseFrame:SetDisplayMode(selected)
    return true
end

-- Use the native result selection path; its OnShow refreshes the matching buy list.
function N.OpenBuy(itemID)
    if not A.open or not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then
        return nil, "请先打开拍卖行。"
    end
    if InCombatLockdown() then return nil, "战斗结束后再操作。" end
    itemID = A.Logic.ItemID(itemID)
    if not itemID then return nil, "请选择有效的物品。" end
    if not AuctionHouseFrame.SelectBrowseResult then return nil, "当前客户端的购买入口不可用。" end
    local key = C_AuctionHouse.MakeItemKey(itemID)
    local info = C_AuctionHouse.GetItemKeyInfo(key)
    if not info then
        C_Item.RequestLoadItemDataByID(itemID)
        return nil, "物品信息尚未载入，请稍后再点击。"
    end
    if info.isEquipment or info.isPet then return nil, "装备或宠物请在原生拍卖行选择具体属性。" end
    if not C_AuctionHouse.IsThrottledMessageSystemReady() then return nil, "拍卖行正忙，请稍后再点击。" end
    A.Market.Pause()
    GameTooltip:Hide()
    local ok = pcall(AuctionHouseFrame.SelectBrowseResult, AuctionHouseFrame, { itemKey = key, minPrice = 0 })
    if not ok then return nil, "未能打开该物品的购买页，请在原生拍卖行搜索。" end
    return true
end

function N.FindStock(itemID)
    local lastBag = Enum.BagIndex and Enum.BagIndex.ReagentBag or NUM_BAG_SLOTS or 4
    for bag = 0, lastBag do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID == itemID and not info.isLocked then
                local location = ItemLocation:CreateFromBagAndSlot(bag, slot)
                if C_AuctionHouse.IsSellItemValid(location) then return location end
            end
        end
    end
end

-- Read-only preview. No search or transaction is started by edits, data events or timers.
function N.PostDetails(product, price, quantity, duration, item)
    local L = A.Logic
    local details = {itemID = product and product.itemID, price = price, quantity = quantity, duration = duration}
    local function fail(reason) details.error = reason; return details end
    if not A.open or not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then return fail("请先打开拍卖行。") end
    if not product then return fail("选择产品后可上架。") end
    item = item or N.FindStock(product.itemID)
    if not item or not C_Item.DoesItemExist(item) or C_Item.GetItemID(item) ~= product.itemID then
        return fail("背包中没有可出售的该商品。")
    end
    local bag, slot = item:GetBagAndSlot()
    local stock = C_Container.GetContainerItemInfo(bag, slot)
    if not stock or stock.isLocked or stock.itemID ~= product.itemID or not C_AuctionHouse.IsSellItemValid(item) then
        return fail("商品已变化或被锁定，请稍后再试。")
    end
    details.item, details.guid = item, C_Item.GetItemGUID(item)
    details.available = C_AuctionHouse.GetAvailablePostCount(item)
    local status = C_AuctionHouse.GetItemCommodityStatus(item)
    local key = C_AuctionHouse.GetItemKeyFromItem(item)
    local info = key and C_AuctionHouse.GetItemKeyInfo(key)
    if status == Enum.ItemCommodityStatus.Unknown or not details.guid or not C_Item.GetItemLink(item) or not info then
        return fail("物品资料载入中，请稍候。")
    end
    if info.isEquipment or info.isPet or (key.itemSuffix or 0) ~= 0 or (key.battlePetSpeciesID or 0) ~= 0 then
        return fail("装备、宠物及属性变体请在原生页面上架。")
    end
    details.commodity = status == Enum.ItemCommodityStatus.Commodity
    if not L.Number(price, 1, 1000000000000, true) then return fail("请输入有效单价。") end
    if not C_AuctionHouse.SupportsCopperValues() and price % 100 ~= 0 then return fail("当前上架价格须为整银。") end
    if not L.Number(quantity, 1, 100000, true) then return fail("数量须为正整数。") end
    if quantity > details.available then return fail("可出售库存不足。") end
    if not L.Number(duration, 1, 3, true) then return fail("请选择拍卖时长。") end
    details.total = price * quantity
    if details.total > 9007199254740991 then return fail("总价超出精确计算范围。") end
    local deposit
    if details.commodity then deposit = C_AuctionHouse.CalculateCommodityDeposit(product.itemID, duration, quantity)
    else deposit = C_AuctionHouse.CalculateItemDeposit(item, duration, quantity) end
    if not L.Number(deposit, 0, 9007199254740991, true) then return fail("押金计算中，请稍候。") end
    if not C_AuctionHouse.SupportsCopperValues() then deposit = math.ceil(deposit / 100) * 100 end
    details.deposit = deposit
    if GetMoney() < deposit then return fail("金币不足以支付押金。") end
    if InCombatLockdown() then return fail("战斗结束后再上架。") end
    if A.Market.active or #A.Market.queue > 0 then return fail("请等待行情刷新完成。") end
    if not C_AuctionHouse.IsThrottledMessageSystemReady() then return fail("拍卖行正忙，请稍候。") end
    if AuctionHouseMultisellProgressFrame and AuctionHouseMultisellProgressFrame:IsShown() then
        return fail("原生上架尚未结束，请稍候。")
    end
    return details
end

local function watchPostEdits(form)
    if form.auctionPilotPostHooks then return end
    form.auctionPilotPostHooks = true
    local function cancel()
        if N.pendingPost and N.pendingPost.form == form then N.pendingPost = nil end
    end
    form:HookScript("OnHide", cancel)
    local money = form.PriceInput.MoneyInputFrame
    for _, box in pairs({form.QuantityInput.InputBox, money.GoldBox, money.SilverBox, money.CopperBox}) do
        box:HookScript("OnEditFocusGained", cancel)
        box:HookScript("OnTextChanged", function(_, userInput) if userInput then cancel() end end)
    end
    form.QuantityInput.MaxButton:HookScript("OnClick", cancel)
    form.Duration.Dropdown:HookScript("OnClick", cancel)
    for _, event in ipairs({"OnClick", "OnDragStart", "OnReceiveDrag"}) do
        form.ItemDisplay.ItemButton:HookScript(event, cancel)
    end
end

local function finishPost(pending)
    if N.pendingPost ~= pending then return end
    local form, item = pending.form, pending.item
    if not A.open or not form:IsVisible() or form:GetItem() ~= item
        or not C_Item.DoesItemExist(item) or C_Item.GetItemID(item) ~= pending.itemID
        or C_Item.GetItemGUID(item) ~= pending.guid then
        N.pendingPost = nil; return
    end
    if not form.ItemDisplay:GetItemLink() then return end
    N.pendingPost = nil
    if InCombatLockdown() then A.Message("已停止带入数量，请在战斗结束后重新准备上架。"); return end
    local bag, slot = item:GetBagAndSlot()
    local stock = C_Container.GetContainerItemInfo(bag, slot)
    if not stock or stock.isLocked or not C_AuctionHouse.IsSellItemValid(item)
        or pending.quantity > C_AuctionHouse.GetAvailablePostCount(item) then
        A.Message("可出售库存已变化，数量未带入，请重新准备上架。"); return
    end
    form.QuantityInput:SetQuantity(pending.quantity)
    form.QuantityInput.InputBox:SetCursorPosition(0)
    form.PriceInput:SetAmount(pending.price)
    form.Duration:SetDuration(pending.duration)
    form.Duration.Dropdown:GenerateMenu()
    form:UpdatePostState()
    if form:GetQuantity() ~= pending.quantity or form.PriceInput:GetAmount() ~= pending.price
        or form.Duration:GetDuration() ~= pending.duration then
        A.Message("原生界面未采用全部参数，请核对单价、数量及时长。"); return
    end
    A.Message("已带入数量 " .. pending.quantity .. "；请核对原生单价、时长和押金，再手动创建拍卖。")
end

function N.OnEvent(event, itemID)
    if event == "MERCHANT_SHOW" or (event == "MERCHANT_UPDATE" and MerchantFrame and MerchantFrame:IsShown()) then
        N.RecordMerchantPrices()
        return
    end
    if event == "AUCTION_HOUSE_SHOW" or event == "AUCTION_HOUSE_CLOSED" then N.pendingPost = nil; return end
    local pending = N.pendingPost
    if pending and itemID == pending.itemID and (event == "GET_ITEM_INFO_RECEIVED" or event == "ITEM_DATA_LOAD_RESULT") then
        -- Run after native item-data callbacks, which can call SetPostItem again and reset quantity.
        C_Timer.After(0, function() finishPost(pending) end)
    end
end

-- This only prepares the native form. Only its own post button executes a sale.
function N.PreparePost(product, price, quantity, duration)
    if N.pendingPost then return nil, "正在带入原生出售页，请稍候。" end
    local details = N.PostDetails(product, price, quantity, duration)
    if details.error then return nil, details.error end
    local item = details.item
    A.Market.Pause()
    AuctionHouseFrame:SetPostItem(item)
    local form = details.commodity and AuctionHouseFrame.CommoditiesSellFrame
        or AuctionHouseFrame.ItemSellFrame
    if not form or form:GetItem() ~= item then return nil, "原生出售界面未接收物品，请手动拖入。" end
    watchPostEdits(form)
    local pending = {form = form, item = item, itemID = product.itemID, guid = details.guid,
        price = price, quantity = quantity, duration = duration}
    N.pendingPost = pending
    -- Avoid leaving the native default stack quantity ready to post while item data is pending.
    form.QuantityInput:SetQuantity(0)
    form:UpdatePostState()
    C_Timer.After(0, function() finishPost(pending) end)
    C_Timer.After(5, function()
        if N.pendingPost == pending then
            N.pendingPost = nil
            A.Message("物品资料尚未就绪，数量未带入，请重新准备上架。")
        end
    end)
    A.UI.frame:Hide()
    return true
end
