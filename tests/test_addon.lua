-- Operator: Solazhu. All examples are synthetic, not live AH observations.
local A = {}
local function loadAddon(name) assert(loadfile(PROJECT_ROOT .. "/AuctionPilot/" .. name))("AuctionPilot", A) end
loadAddon("Logic.lua")
local L = A.Logic
local passed = 0
local function test(name, callback)
    local ok, err = pcall(callback)
    if not ok then error(name .. ": " .. tostring(err)) end
    passed = passed + 1
    print("PASS " .. name)
end
local function eq(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local product = { itemID = 1, output = 1, fee = 5, extra = 0, alert = true,
    materials = { { itemID = 2, quantity = 2, source = "market" }, { itemID = 3, quantity = 1, source = "fixed", price = 200 } } }
local function quote(rows, now) return L.Snapshot(rows, now or 100, true) end
local function quotes()
    return { [1] = quote({{ price = 12000, quantity = 100 }}), [2] = quote({{price = 4200, quantity = 100}}) }
end
test("known profit and seller fee", function()
    local e = L.Estimate(product, quotes(), 100, 120)
    eq(e.cost, 8600); eq(e.fee, 600); eq(e.net, 11400); eq(e.profit, 2800)
    eq(string.format("%.1f", e.roi), "32.6")
end)
test("quantity-aware procurement walks price tiers", function()
    local q = quotes()
    q[2] = quote({{price = 100, quantity = 1}, {price = 500, quantity = 10}})
    local e = L.Estimate(product, q, 100, 120)
    eq(e.materialCost, 800)
end)
test("non-commodity lots must be bought whole", function()
    local q = quotes()
    q[2].commodity = false
    q[2].lots = {{price = 100, quantity = 20, own = 0}}
    local e = L.Estimate(product, q, 100, 120)
    eq(e.cost, 2200); eq(e.materials[1].purchased, 20)
end)
test("empty output market cannot manufacture a sale price", function()
    local q = quotes(); q[1] = quote({})
    local e = L.Estimate(product, q, 100, 120)
    assert(e.error); eq(e.sale, nil); eq(e.profit, nil)
end)
test("zero total cost leaves rate undefined rather than infinity", function()
    local p = L.Copy(product)
    for _, m in ipairs(p.materials) do m.source, m.price = "fixed", 0 end
    local e = L.Estimate(p, quotes(), 100, 120)
    eq(e.roi, nil); eq(e.profit, 11400)
end)
test("invalid explicit selling prices are rejected", function()
    local e = L.Estimate(product, quotes(), 100, 120, 1, -1)
    assert(e.error); eq(e.profit, nil)
end)
test("own material auctions cannot fund procurement", function()
    local q = quotes()
    q[2] = quote({{price = 1, quantity = 10, own = 10}, {price = 4200, quantity = 2}})
    eq(L.Estimate(product, q, 100, 120).cost, 8600)
end)
test("insufficient material yields no fabricated profit", function()
    local q = quotes(); q[2] = quote({{price = 10, quantity = 1}})
    local e = L.Estimate(product, q, 100, 120)
    assert(e.error); eq(e.profit, nil); eq(e.cost, nil)
end)
test("missing stale incomplete and failed prices are unknown", function()
    for _, state in ipairs({"missing", "stale", "incomplete", "failed"}) do
        local q = quotes()
        if state == "missing" then q[2] = nil
        elseif state == "stale" then q[2].at = 0
        elseif state == "incomplete" then q[2].complete = false
        else q[2].error = "network failure" end
        local e = L.Estimate(product, q, 121, 120)
        assert(e.error, state); eq(e.profit, nil)
    end
end)
test("explicit zero fixed price is valid but blank is not", function()
    local p = L.Copy(product); p.materials[2].price = 0
    assert(L.Validate(p)); p.materials[2].price = nil; eq(L.Validate(p), nil)
end)
test("output and extra loss are apportioned per unit", function()
    local p = L.Copy(product); p.output = 2; p.extra = 100
    local e = L.Estimate(p, quotes(), 100, 120)
    eq(e.cost, 8700); eq(e.fee, 1200); eq(e.profit, 14100); eq(e.unitProfit, 7050)
end)
test("batch procurement is not naive multiplication", function()
    local q = quotes(); q[2] = quote({{price = 4200, quantity = 2}, {price = 5000, quantity = 50}})
    local e = L.Estimate(product, q, 100, 120, 2)
    eq(e.cost, 18800); eq(e.profit, 4000)
end)
test("reject invalid counts fees duplicates and self materials", function()
    for _, value in ipairs({0, -1, 1.5, math.huge, "junk"}) do
        local p = L.Copy(product); p.output = value; eq(L.Validate(p), nil)
    end
    local p = L.Copy(product); p.fee = 100; eq(L.Validate(p), nil)
    p = L.Copy(product); p.materials[2].itemID = 2; eq(L.Validate(p), nil)
    p = L.Copy(product); p.materials[2].itemID = 1; eq(L.Validate(p), nil)
end)
test("money formats and item links", function()
    eq(L.Money(-160), "-1银60铜"); eq(L.Money(0), "0铜"); eq(L.Money(12000), "1金20银")
    eq(L.ItemID("|cffa335ee|Hitem:123:0:0|h[Test]|h|r"), 123)
    eq(L.ItemID("硫酸"), nil); eq(L.ItemID("12.3"), nil)
end)
test("no own listings means no overtaken alert", function()
    eq(L.Competition(nil, quote({{price = 100, quantity = 20}})), nil)
end)
test("lower external price is a real undercut", function()
    local c = quote({{price = 12000, quantity = 40, own = 40}, {price = 11900, quantity = 10}})
    eq(L.Competition(nil, c).kind, "undercut")
end)
test("same price rise is a caution not an exact queue rank", function()
    local p = quote({{price = 12000, quantity = 200, own = 40}})
    local c = quote({{price = 12000, quantity = 280, own = 40}})
    local alert = L.Competition(p, c)
    eq(alert.kind, "same"); eq(alert.increase, 80); eq(alert.rank, nil)
    eq(L.Competition(c, c), nil)
end)
test("own replenishment and own sale do not cause same-price alerts", function()
    local p = quote({{price = 12000, quantity = 200, own = 40}})
    eq(L.Competition(p, quote({{price = 12000, quantity = 220, own = 60}})), nil)
    eq(L.Competition(p, quote({{price = 12000, quantity = 180, own = 20}})), nil)
end)
test("partial snapshots and first observations cannot establish same-price movement", function()
    local p = quote({{price = 100, quantity = 2, own = 1}})
    local c = quote({{price = 100, quantity = 3, own = 1}})
    eq(L.Competition(nil, c), nil); p.complete = false; eq(L.Competition(p, c), nil)
end)

-- Scheduler contract tests use only explicitly supplied asynchronous events.
local now, ready, sends, moreCalls, pendingTick = 100, true, {}, 0
A.Now = function() return now end
A.RefreshUI = function() end
A.open = true
A.UI = {frame = {IsShown = function() return true end}}
A.profile = {products = {{id = 1, itemID = 1, fee = 5, activeRecipeID = 1,
    recipes = {{id = 1, name = "默认配方", output = 1, extra = 0, materials = product.materials}}}}}
A.Selected = function() return product end
A.quotes = {}
A.AcceptQuote = function(id, value) A.quotes[id] = value end
Enum = {AuctionHouseSortOrder = {Price = 0}, ItemCommodityStatus = {Unknown = 0, Item = 1, Commodity = 2}, BagIndex = {ReagentBag = 4}}
local full, rows = true, {{unitPrice = 12000, quantity = 80, numOwnerItems = 20}}
C_AuctionHouse = {
    MakeItemKey = function(id) return {itemID = id} end,
    IsThrottledMessageSystemReady = function() return ready end,
    GetItemKeyInfo = function() return {isCommodity = true} end,
    SendSearchQuery = function(key) sends[#sends + 1] = key.itemID end,
    HasFullCommoditySearchResults = function() return full end,
    RequestMoreCommoditySearchResults = function() moreCalls = moreCalls + 1 end,
    GetNumCommoditySearchResults = function() return #rows end,
    GetCommoditySearchResultInfo = function(_, i) return rows[i] end,
}
C_Timer = {NewTicker = function(_, callback) pendingTick = callback; return {} end}
loadAddon("Market.lua")
local M = A.Market
test("throttled scheduler sends nothing until ready", function()
    M.RequestRefresh(); ready = false; M.Tick(); eq(#sends, 0)
    ready = true; M.Tick(); eq(sends[1], 1)
end)
test("unrelated result cannot complete an active item", function()
    M.OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 999)
    eq(M.active.itemID, 1); eq(A.quotes[1], nil)
end)
test("partial search requests more without publishing prices", function()
    full = false; M.OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 1)
    eq(A.quotes[1], nil); now = 101.3; M.Tick(); eq(moreCalls, 1)
end)
test("complete search publishes price and preserves query spacing", function()
    full = true; M.OnEvent("COMMODITY_SEARCH_RESULTS_ADDED", 1)
    eq(A.quotes[1].levels[1].price, 12000)
    M.Tick(); eq(#sends, 1)
    now = 102.6; M.Tick(); eq(sends[2], 2)
end)
test("timeout invalidates quote instead of pretending it is fresh", function()
    now = 130; M.Tick(); assert(A.quotes[2].error); eq(A.quotes[2].complete, false)
end)
test("closed AH cancels work and ignores late responses", function()
    M.Pause(); A.open = false; M.Tick(); eq(#M.queue, 0)
    M.OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 1); eq(M.active, nil)
end)
test("request-more returning complete needs no additional event", function()
    A.open = true; full = false; now = 200
    M.RequestRefresh(); M.Tick()
    M.OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED", 1)
    C_AuctionHouse.RequestMoreCommoditySearchResults = function() full = true; return true end
    now = 202; M.Tick(); eq(M.active, nil); eq(A.quotes[1].at, 202)
end)

test("v1 migration preserves all characters and an independent backup", function()
    local p = L.Copy(product); p.id = 7
    local old = {version=1,profiles={one={products={p},selectedID=7,nextID=8},two={products={L.Copy(p)},nextID=8}}}
    local migrated = assert(L.MigrateDB(old))
    eq(migrated.version,2); eq(old.version,1); eq(old.profiles.one.products[1].recipes,nil)
    local new = migrated.profiles.one.products[1]
    eq(new.id,7); eq(migrated.profiles.one.selectedID,7); eq(migrated.profiles.one.nextID,8)
    eq(new.output,nil); eq(new.activeRecipeID,1); eq(new.nextRecipeID,2)
    eq(new.recipes[1].name,"默认配方"); eq(new.recipes[1].materials[2].price,200)
    eq(migrated.profiles.two.products[1].recipes[1].materials[1].quantity,2)
    new.recipes[1].materials[1].quantity = 10
    eq(old.profiles.one.products[1].materials[1].quantity,2)
    eq(migrated.backupV1.profiles.one.products[1].materials[1].quantity,2)
    eq(L.MigrateDB(migrated),migrated)
end)

test("invalid migration leaves original database intact", function()
    local bad = {version=1,profiles={one={products={L.Copy(product)}}}}
    bad.profiles.one.products[1].output = 0
    eq(L.MigrateDB(bad),nil); eq(bad.version,1); eq(bad.profiles.one.products[1].recipes,nil)
    eq(L.MigrateDB({version=9,profiles={}}),nil)
    eq(L.MigrateDB({version=1,profiles={one={}}}),nil)
end)

test("completed manual batch stays idle even after thirty seconds", function()
    now = 204; M.Tick(); eq(M.active.itemID,2)
    M.OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED",2); eq(M.active,nil); eq(#M.queue,0)
    local count = #sends
    for _, time in ipairs({240,300,1000}) do now = time; M.Tick() end
    eq(#sends,count); eq(#M.queue,0)
end)

test("refresh scopes deduplicate all recipe materials and skip fixed prices", function()
    A.profile.products[1].recipes[2] = {materials={{itemID=4,source="market"},{itemID=2,source="market"}}}
    A.profile.products[2] = {id=2,itemID=7,recipes={{materials={{itemID=4,source="market"},{itemID=5,source="market"}}}}}
    local function queued(scope,id,expected)
        M.Pause(); assert(M.RequestRefresh(scope,id)); eq(table.concat(M.queue,","),expected)
    end
    queued("sale",nil,"1,7"); queued("materials",nil,"2,4,5"); queued("all",nil,"1,2,4,7,5")
    queued("materials",2,"4,5"); queued("sale",1,"1")
    local count = #M.queue
    eq(M.RequestRefresh("all"),nil); eq(#M.queue,count)
    M.Pause(); eq(M.RequestRefresh("bad"),nil); eq(#M.queue,0)
    eq(M.RequestRefresh("all",999),nil); eq(#M.queue,0)
end)

print("TOTAL " .. passed .. " tests passed")
