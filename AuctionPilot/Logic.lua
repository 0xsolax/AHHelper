local _, A = ...
local L = {}
A.Logic = L

function L.Number(value, minimum, maximum, integer)
    local n = tonumber(value)
    if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
    if n < minimum or n > maximum or (integer and n ~= math.floor(n)) then return nil end
    return n
end

function L.Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = L.Copy(child) end
    return result
end

function L.ItemID(value)
    if type(value) == "number" then return L.Number(value, 1, 10000000, true) end
    if type(value) ~= "string" then return nil end
    return L.Number(value:match("item:(%d+)") or value:match("^%s*(%d+)%s*$"), 1, 10000000, true)
end

function L.TrackedItems(products)
    local tracked = {}
    for _, product in ipairs(products) do
        tracked[product.itemID] = true
        for _, recipe in ipairs(product.recipes) do
            for _, material in ipairs(recipe.materials) do tracked[material.itemID] = true end
        end
    end
    return tracked
end

function L.RecipeInput(product, recipe)
    return { itemID = product.itemID, fee = product.fee, output = recipe.output,
        extra = recipe.extra, materials = recipe.materials }
end

function L.MigrateDB(database)
    if not database then return { version = 2, profiles = {} } end
    if type(database) ~= "table" or type(database.profiles) ~= "table" then
        return nil, "保存数据格式不兼容，已保留原数据。"
    end
    if database.version == 2 then return database end
    if database.version ~= 1 then return nil, "保存数据版本不兼容，已保留原数据。" end
    local migrated = L.Copy(database)
    for _, profile in pairs(migrated.profiles) do
        if type(profile) ~= "table" or type(profile.products) ~= "table" then
            return nil, "旧配置不完整，未执行迁移。"
        end
        for _, product in ipairs(profile.products) do
            if type(product) ~= "table" then return nil, "旧商品记录无效，未执行迁移。" end
            local valid = L.Validate(product)
            if not valid then return nil, "旧配方记录无效，未执行迁移。" end
            product.recipes = { { id = 1, name = "默认配方", output = product.output,
                extra = product.extra, materials = product.materials } }
            product.activeRecipeID, product.nextRecipeID = 1, 2
            product.output, product.extra, product.materials = nil, nil, nil
        end
    end
    migrated.version = 2
    migrated.backupV1 = L.Copy(database)
    return migrated
end

function L.Validate(product)
    if not L.ItemID(product.itemID) then return nil, "请选择出售商品。" end
    if not L.Number(product.output, 1, 100000, true) then return nil, "产量须为大于零的整数。" end
    if not L.Number(product.fee, 0, 99.99, false) then return nil, "手续费须在 0% 至 99.99% 之间。" end
    if not L.Number(product.extra, 0, 1000000000000, true) then return nil, "额外费用须为有效金额。" end
    if type(product.materials) ~= "table" or #product.materials == 0 then return nil, "请至少添加一种材料。" end
    local seen = {}
    for i, material in ipairs(product.materials) do
        if not L.ItemID(material.itemID) then return nil, "第 " .. i .. " 行尚未选择材料。" end
        if seen[material.itemID] then return nil, "同一种材料请合并用量。" end
        if product.itemID == material.itemID then return nil, "成品与材料不能是同一物品。" end
        seen[material.itemID] = true
        if not L.Number(material.quantity, 1, 100000, true) then return nil, "材料用量须为大于零的整数。" end
        if material.source ~= "market" and material.source ~= "auction"
            and material.source ~= "vendor" and material.source ~= "fixed" then return nil, "请选择材料价格来源。" end
        if material.source == "fixed" and not L.Number(material.price, 0, 1000000000000, true) then
            return nil, "请输入有效的固定采购价。"
        end
    end
    return true
end

-- Prices stay in copper. A snapshot contains complete, price-sorted levels.
function L.Snapshot(rows, at, complete)
    local grouped = {}
    for _, row in ipairs(rows) do
        local price, quantity = row.price, row.quantity
        if L.Number(price, 1, 1000000000000, false) and L.Number(quantity, 1, 1000000000, true) then
            local level = grouped[price] or { price = price, quantity = 0, own = 0 }
            level.quantity = level.quantity + quantity
            level.own = level.own + math.min(quantity, math.max(0, row.own or 0))
            grouped[price] = level
        end
    end
    local snapshot = { levels = {}, at = at, complete = complete == true }
    for _, level in pairs(grouped) do
        level.available = math.max(0, level.quantity - level.own)
        table.insert(snapshot.levels, level)
    end
    table.sort(snapshot.levels, function(a, b) return a.price < b.price end)
    return snapshot
end

function L.Fresh(snapshot, now, ttl, allowHistorical)
    return snapshot and snapshot.complete and not snapshot.error
        and (allowHistorical or not snapshot.historical)
        and now >= snapshot.at and now - snapshot.at <= ttl
end

function L.PurchaseCost(snapshot, quantity)
    local remaining, cost = quantity, 0
    for _, level in ipairs(snapshot.levels) do
        local take = math.min(remaining, level.available)
        cost = cost + take * level.price
        remaining = remaining - take
        if remaining == 0 then return math.ceil(cost), quantity end
    end
    return nil, quantity - remaining
end

function L.VendorPrice(material, prices)
    local entry = type(prices) == "table" and prices[material.itemID]
    if (material.source ~= "market" and material.source ~= "vendor") or type(entry) ~= "table"
        or not L.Number(entry.price, 1, 1000000000000, true)
        or not L.Number(entry.stackCount, 1, 100000, true)
        or not L.Number(entry.seenAt, 1, 9007199254740991, true) then return nil end
    return entry
end

function L.UsesMarketPrice(material, prices)
    return material.source == "auction" or (material.source == "market" and not L.VendorPrice(material, prices))
end

function L.Estimate(product, quotes, now, ttl, batches, saleOverride, vendorPrices, allowHistorical)
    local valid, err = L.Validate(product)
    if not valid then return { error = err, materials = {} } end
    batches = batches or 1
    if not L.Number(batches, 1, 100000, true) then return { error = "生产批次无效。", materials = {} } end
    local result = { materials = {}, batches = batches, output = product.output * batches }
    local saleQuote = quotes[product.itemID]
    if saleOverride then
        if L.Number(saleOverride, 1, 1000000000000, true) then result.sale = saleOverride
        else result.error = "销售单价无效" end
    elseif L.Fresh(saleQuote, now, ttl, allowHistorical) and saleQuote.levels[1] then
        result.sale = saleQuote.levels[1].price
    else
        result.error = saleQuote and saleQuote.error or "成品缺价或行情已过期"
    end
    local materialCost = 0
    for _, material in ipairs(product.materials) do
        local quantity = material.quantity * batches
        local row = { itemID = material.itemID, quantity = quantity, source = material.source }
        local vendor = L.VendorPrice(material, vendorPrices)
        if material.source == "fixed" then
            row.cost = material.price * quantity
            row.unit = material.price
        elseif vendor then
            row.source, row.unit = "vendor", vendor.price / vendor.stackCount
            row.cost = math.ceil(vendor.price * quantity / vendor.stackCount)
        elseif material.source == "vendor" then
            row.error = "未记录商店价，请打开对应商店。"
        else
            row.source = "market"
            local quote = quotes[material.itemID]
            if not L.Fresh(quote, now, ttl, allowHistorical) then
                row.error = quote and quote.error or "缺价或已过期"
            else
                row.cost, row.available = L.PurchaseCost(quote, quantity)
                row.unit = row.cost and row.cost / quantity or nil
                if not row.cost then row.error = "可买数量不足" end
            end
        end
        if row.error then result.error = result.error or "材料" .. row.itemID .. "：" .. row.error end
        materialCost = materialCost + (row.cost or 0)
        table.insert(result.materials, row)
    end
    if result.error then return result end
    result.materialCost = materialCost
    result.cost = materialCost + product.extra * batches
    result.gross = result.sale * result.output
    if result.cost > 9007199254740991 or result.gross > 9007199254740991 then
        return { error = "金额超出精确计算范围", materials = result.materials }
    end
    result.fee = math.ceil(result.gross * product.fee / 100)
    result.cost = result.cost + result.fee
    if result.cost > 9007199254740991 then
        return { error = "金额超出精确计算范围", materials = result.materials }
    end
    result.net = result.gross - result.fee
    result.profit = result.gross - result.cost
    result.unitCost = result.cost / result.output
    result.unitProfit = result.profit / result.output
    result.roi = result.cost > 0 and result.profit / result.cost * 100 or nil
    return result
end

function L.Competition(previous, current)
    if not current or not current.complete or current.error then return nil end
    local ownPrice, competitorPrice, sameQuantity
    for _, level in ipairs(current.levels) do
        if level.own > 0 and not ownPrice then ownPrice = level.price end
        if level.available > 0 and not competitorPrice then competitorPrice = level.price end
    end
    if not ownPrice then return nil end
    if competitorPrice and competitorPrice < ownPrice then
        return { kind = "undercut", price = competitorPrice, ownPrice = ownPrice,
            key = "under:" .. ownPrice .. ":" .. competitorPrice }
    end
    if not previous or not previous.complete or previous.error then return nil end
    local previousOwn, previousQuantity
    for _, level in ipairs(previous.levels) do
        if level.own > 0 and not previousOwn then previousOwn = level.price end
        if level.price == ownPrice then previousQuantity = level.available end
    end
    -- A new own price establishes a new baseline, it is not a competitor alert.
    if previousOwn ~= ownPrice then return nil end
    for _, level in ipairs(current.levels) do
        if level.price == ownPrice then sameQuantity = level.available end
    end
    local increase = (sameQuantity or 0) - (previousQuantity or 0)
    if increase > 0 then
        return { kind = "same", price = ownPrice, increase = increase,
            key = "same:" .. ownPrice .. ":" .. (sameQuantity or 0) }
    end
    return nil
end

function L.Money(copper)
    if copper == nil then return "--" end
    local negative = copper < 0
    copper = math.floor(math.abs(copper) + 0.5)
    local gold = math.floor(copper / 10000)
    local silver = math.floor(copper % 10000 / 100)
    local rest = copper % 100
    local text = gold > 0 and gold .. "金" or ""
    if silver > 0 then text = text .. silver .. "银" end
    if rest > 0 or text == "" then text = text .. rest .. "铜" end
    return (negative and "-" or "") .. text
end
