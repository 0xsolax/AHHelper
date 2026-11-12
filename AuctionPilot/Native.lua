local _, A = ...
local N = {}
A.Native = N

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

-- This only prepares the native form. Only its own post button executes a sale.
function N.PreparePost(product, price, quantity)
    if not A.open or not AuctionHouseFrame then return nil, "请先打开拍卖行。" end
    if InCombatLockdown() then return nil, "战斗结束后再操作。" end
    if not product then return nil, "请先选择商品。" end
    if not A.Logic.Number(price, 1, 1000000000000, true) then return nil, "请输入有效的上架单价。" end
    if not A.Logic.Number(quantity, 1, 100000, true) then return nil, "数量须为大于零的整数。" end
    if not C_AuctionHouse.SupportsCopperValues() and price % 100 ~= 0 then
        return nil, "当前拍卖行的上架价格须为整银。"
    end
    local item = N.FindStock(product.itemID)
    if not item then return nil, "背包中没有可出售的该商品，或物品正被锁定。" end
    if quantity > C_AuctionHouse.GetAvailablePostCount(item) then return nil, "可出售库存不足。" end
    local status = C_AuctionHouse.GetItemCommodityStatus(item)
    if status == Enum.ItemCommodityStatus.Unknown then return nil, "物品信息尚未载入，请稍后重试。" end
    if not C_AuctionHouse.IsThrottledMessageSystemReady() then return nil, "拍卖行正忙，请稍后重试。" end
    A.Market.Pause()
    AuctionHouseFrame:SetPostItem(item)
    local form = status == Enum.ItemCommodityStatus.Commodity and AuctionHouseFrame.CommoditiesSellFrame
        or AuctionHouseFrame.ItemSellFrame
    if not form or form:GetItem() ~= item then return nil, "原生出售界面未接收物品，请手动拖入。" end
    form.QuantityInput:SetQuantity(quantity)
    if status == Enum.ItemCommodityStatus.Commodity then
        form.PriceInput:SetAmount(price)
    else
        -- Normal-item pricing is controlled by the native form's stack rules.
        A.Message("已放入出售商品；请在原生界面确认每组价格与数量。")
    end
    form:UpdatePostState()
    A.UI.frame:Hide()
    A.Message("请在原生出售界面确认价格、数量和押金，再点击上架。")
    return true
end
