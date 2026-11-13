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
    eq(e.cost, 9200); eq(e.fee, 600); eq(e.net, 11400); eq(e.profit, 2800)
    eq(string.format("%.1f", e.roi), "30.4")
end)
test("quantity-aware procurement walks price tiers", function()
    local q = quotes()
    q[2] = quote({{price = 100, quantity = 1}, {price = 500, quantity = 10}})
    local e = L.Estimate(product, q, 100, 120)
    eq(e.materialCost, 800)
end)
test("grouped item offers charge only the required quantity", function()
    local q = quotes()
    q[2] = quote({{price = 100, quantity = 20}})
    local e = L.Estimate(product, q, 100, 120)
    eq(e.cost, 1000); eq(e.materials[1].cost, 200)
end)
test("empty output market cannot manufacture a sale price", function()
    local q = quotes(); q[1] = quote({})
    local e = L.Estimate(product, q, 100, 120)
    assert(e.error); eq(e.sale, nil); eq(e.profit, nil)
end)
test("zero total cost leaves rate undefined rather than infinity", function()
    local p = L.Copy(product)
    for _, m in ipairs(p.materials) do m.source, m.price = "fixed", 0 end
    p.fee = 0
    local e = L.Estimate(p, quotes(), 100, 120)
    eq(e.roi, nil); eq(e.profit, 12000)
end)

test("total-cost return includes selling fees without deducting them twice", function()
    local p = L.Copy(product)
    p.materials = {{itemID=2,quantity=1,source="fixed",price=800000}}
    local e = L.Estimate(p, quotes(), 100, 120, 1, 1000000)
    eq(e.cost,850000); eq(e.profit,150000); eq(e.unitCost,850000)
    eq(string.format("%.2f",e.roi),"17.65")
    p.materials[1].price = 0
    e = L.Estimate(p,quotes(),100,120,1,1000000)
    eq(e.cost,50000); eq(e.roi,1900)
    p.materials[1].price = 1000000
    e = L.Estimate(p,quotes(),100,120,1,1000000)
    eq(e.profit,-50000); assert(e.roi < 0)
end)
test("invalid explicit selling prices are rejected", function()
    local e = L.Estimate(product, quotes(), 100, 120, 1, -1)
    assert(e.error); eq(e.profit, nil)
end)
test("own material auctions cannot fund procurement", function()
    local q = quotes()
    q[2] = quote({{price = 1, quantity = 10, own = 10}, {price = 4200, quantity = 2}})
    eq(L.Estimate(product, q, 100, 120).cost, 9200)
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
    eq(e.cost, 9900); eq(e.fee, 1200); eq(e.profit, 14100); eq(e.unitProfit, 7050)
end)
test("batch procurement is not naive multiplication", function()
    local q = quotes(); q[2] = quote({{price = 4200, quantity = 2}, {price = 5000, quantity = 50}})
    local e = L.Estimate(product, q, 100, 120, 2)
    eq(e.cost, 20000); eq(e.profit, 4000)
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

test("wizard oil grouped offers retain their native buyout prices", function()
    M.Pause()
    local key = {itemID=20744,itemLevel=0,itemSuffix=0,battlePetSpeciesID=0}
    local results = {
        {itemKey=key,buyoutAmount=290,quantity=1},
        {itemKey=key,buyoutAmount=300,quantity=234},
        {itemKey=key,buyoutAmount=500,quantity=18},
        {itemKey=key,minBid=1,quantity=1},
    }
    C_AuctionHouse.HasFullItemSearchResults = function() return true end
    C_AuctionHouse.GetNumItemSearchResults = function() return #results end
    C_AuctionHouse.GetItemSearchResultInfo = function(_, i) return results[i] end
    M.active = {itemID=20744,key=key,started=now}
    M.OnEvent("ITEM_SEARCH_RESULTS_UPDATED",key)
    local snapshot = A.quotes[20744]
    eq(snapshot.levels[1].price,290)
    eq(snapshot.levels[2].price,300); eq(snapshot.levels[2].quantity,234)
    eq(L.PurchaseCost(snapshot,2),590)
end)

test("targeted refreshes select one recipe or one item without expanding the scope", function()
    A.profile.products[1].recipes[2].id = 2
    M.Pause(); assert(M.RequestRefresh("all",1,1)); eq(table.concat(M.queue,","),"1,2")
    M.Pause(); assert(M.RequestRefresh("all",1,2)); eq(table.concat(M.queue,","),"1,4,2")
    M.Pause(); assert(M.RequestRefresh("all",1)); eq(table.concat(M.queue,","),"1,2,4")
    M.Pause(); assert(M.RequestItem(3)); eq(table.concat(M.queue,","),"3")
    eq(M.RequestRefresh("all",1,1),nil); eq(table.concat(M.queue,","),"3")
    M.Pause(); eq(M.RequestRefresh("all",1,999),nil); eq(#M.queue,0)
    eq(M.RequestRefresh("all",nil,1),nil); eq(M.RequestItem("bad"),nil); eq(#M.queue,0)
    A.open = false; eq(M.RequestItem(2),nil); eq(M.RequestRefresh("all",1,1),nil)
    eq(#M.queue,0); A.open = true
end)

test("auto refresh queries watched products only and waits from round completion", function()
    M.Pause(); now = 2000; ready = true; full = true
    assert(M.SetAuto(true)); eq(M.active.itemID,1); eq(table.concat(M.queue,","),"7")
    M.OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED",1)
    now = 2002; M.Tick(); eq(M.active.itemID,7)
    now = 2010; M.OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED",7)
    local count = #sends
    now = 2039.9; M.Tick(); eq(#sends,count)
    now = 2040; M.Tick(); eq(#sends,count+1); eq(M.active.itemID,1)
    assert(M.SetAuto(false)); eq(M.active,nil); eq(#M.queue,0)
end)

test("partial or missing result rows cannot become an empty complete book", function()
    M.Pause(); now = 2100; assert(M.RequestItem(1)); M.Tick()
    local read = C_AuctionHouse.GetCommoditySearchResultInfo
    C_AuctionHouse.GetCommoditySearchResultInfo = function() return nil end
    M.OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED",1)
    eq(A.quotes[1].complete,true); assert(A.quotes[1].refreshError)
    eq(L.Fresh(A.quotes[1],now,120),false)
    C_AuctionHouse.GetCommoditySearchResultInfo = read
end)

test("manual work shares the auto queue and restarts the thirty-second wait", function()
    M.Pause(); now = 2200; assert(M.SetAuto(true))
    M.OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED",1)
    now = 2202; M.Tick(); M.OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED",7)
    now = 2210; assert(M.RequestItem(2)); M.Tick()
    eq(M.active.itemID,2); eq(M.RequestRefresh("sale"),nil)
    now = 2218; M.OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED",2)
    now = 2247; M.Tick(); eq(M.active,nil)
    now = 2248; M.Tick(); eq(M.active.itemID,1)
    M.SetAuto(false)
end)

test("auto obeys throttle and skips products removed from a queued round", function()
    M.Pause(); now = 2300; ready = false; local count = #sends
    assert(M.SetAuto(true)); M.Tick(); eq(#sends,count); eq(#M.queue,2)
    local removed = table.remove(A.profile.products,2)
    ready = true; M.Tick(); eq(M.active.itemID,1)
    M.OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED",1)
    now = 2302; M.Tick(); eq(M.active,nil); eq(#M.queue,0); eq(#sends,count+1)
    now = 2331; M.Tick(); eq(M.active,nil)
    now = 2332; M.Tick(); eq(M.active.itemID,1)
    M.SetAuto(false); table.insert(A.profile.products,removed)
end)

test("item pages must be complete and readable before publishing a replacement", function()
    M.Pause(); now = 2400
    local watched = L.Copy(A.profile.products[1])
    watched.id, watched.itemID = 3, 20744
    table.insert(A.profile.products,watched)
    local key = {itemID=20744,itemSuffix=0,battlePetSpeciesID=0}
    local itemFull, calls = false, 0
    C_AuctionHouse.HasFullItemSearchResults = function() return itemFull end
    C_AuctionHouse.RequestMoreItemSearchResults = function() calls = calls+1; itemFull = true; return true end
    C_AuctionHouse.GetNumItemSearchResults = function() return 1 end
    C_AuctionHouse.GetItemSearchResultInfo = function() return {itemKey=key,buyoutAmount=300,quantity=45} end
    assert(M.RequestItem(20744)); M.Tick()
    local previous = A.quotes[20744]
    M.OnEvent("ITEM_SEARCH_RESULTS_UPDATED",key); eq(A.quotes[20744],previous)
    now = 2402; M.Tick(); eq(calls,1); eq(A.quotes[20744].levels[1].quantity,45)
    now = 2410; assert(M.RequestItem(20744)); M.Tick()
    C_AuctionHouse.GetItemSearchResultInfo = function() return nil end
    M.OnEvent("ITEM_SEARCH_RESULTS_UPDATED",key)
    eq(A.quotes[20744].complete,true); eq(A.quotes[20744].levels[1].quantity,45)
    assert(A.quotes[20744].refreshError); eq(L.Fresh(A.quotes[20744],now,120),false)
end)

local function recoveryFixture()
    M.Pause(); M.draining, M.auto, M.nextSend, M.discardUntil = nil, false, 0, {}
    now, ready, full, sends = 3000, true, true, {}
    A.quotes = {}
    A.profile.products = {
        {id=1,itemID=1,recipes={{materials={}}}},
        {id=2,itemID=2,recipes={{materials={}}}},
        {id=3,itemID=3,recipes={{materials={}}}},
    }
    C_AuctionHouse.GetItemKeyInfo = function() return {isCommodity=true} end
    C_AuctionHouse.SendSearchQuery = function(key) sends[#sends+1] = key.itemID end
    C_AuctionHouse.GetCommoditySearchResultInfo = function(_, index) return rows[index] end
    assert(M.RequestRefresh("sale"))
end

test("a stalled throttle ends the batch and releases the queue without fabricating quotes", function()
    recoveryFixture(); ready = false; M.auto = true
    M.Tick(); now = now+29; M.Tick(); eq(#sends,0); eq(#M.queue,3)
    now = now+1; M.Tick()
    eq(M.active,nil); eq(#M.queue,0); eq(M.auto,false)
    eq(M.batch.completed,0); eq(M.batch.failed,0); eq(M.batch.total,3)
    assert(M.batch.stopped:find("限流")); eq(next(A.quotes),nil)
    now = now+120; ready = true; M.Tick(); eq(#sends,0)
    assert(M.RequestRefresh("sale")); M.Tick(); eq(sends[1],1)
end)

test("one lost response cannot stop later products and its deferred retry is bounded", function()
    recoveryFixture(); M.Tick(); eq(sends[1],1)
    now = now+26; M.Tick(); eq(M.active.itemID,2)
    M.OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED",1); eq(M.active.itemID,2); eq(A.quotes[1].complete,false)
    M.OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED",2)
    now = now+2; M.Tick(); eq(M.active.itemID,3)
    M.OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED",3)
    eq(M.batch.completed,2); eq(M.batch.failed,0); eq(#M.queue,1)
    now = now+24; M.Tick(); eq(M.active.itemID,1); eq(table.concat(sends,","),"1,2,3,1")
    now = now+26; M.Tick(); eq(M.active,nil); eq(#M.queue,0)
    eq(M.batch.completed,2); eq(M.batch.failed,1)
    now = now+120; M.Tick(); eq(#sends,4)
end)

test("transient send failure retries behind healthy products and counts each product once", function()
    recoveryFixture()
    local attempts = {}
    C_AuctionHouse.SendSearchQuery = function(key)
        sends[#sends+1] = key.itemID
        attempts[key.itemID] = (attempts[key.itemID] or 0)+1
        if key.itemID == 1 and attempts[1] == 1 then error("synthetic send failure") end
    end
    M.Tick(); eq(M.active,nil); assert(A.quotes[1].error)
    now = now+2; M.Tick(); eq(M.active.itemID,2); M.OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED",2)
    now = now+2; M.Tick(); eq(M.active.itemID,3); M.OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED",3)
    now = now+2; M.Tick(); eq(M.active.itemID,1); M.OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED",1)
    eq(table.concat(sends,","),"1,2,3,1"); eq(M.batch.completed,3); eq(M.batch.failed,0)
    eq(A.quotes[1].error,nil); eq(#M.queue,0)
end)

test("unsupported equipment is skipped without retry while supported products complete", function()
    recoveryFixture()
    C_AuctionHouse.GetItemKeyInfo = function(key) return {isEquipment=key.itemID==1} end
    M.Tick(); eq(M.active,nil)
    now = now+2; M.Tick(); M.OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED",2)
    now = now+2; M.Tick(); M.OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED",3)
    eq(table.concat(sends,","),"2,3"); eq(M.batch.completed,2); eq(M.batch.failed,1); eq(#M.queue,0)
end)

test("a recovered throttle resumes the same queue without overlapping requests", function()
    recoveryFixture(); ready = false; M.Tick()
    now = now+20; ready = true; M.Tick(); eq(M.active.itemID,1)
    now = now+20; M.Tick(); eq(#sends,1); eq(M.active.itemID,1)
    M.OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED",1)
    M.Tick(); eq(M.active.itemID,2); eq(M.batch.stopped,nil)
end)

test("read and page API exceptions fail only their item and never publish partial results", function()
    for _, failure in ipairs({"read","page"}) do
        recoveryFixture()
        C_AuctionHouse.GetCommoditySearchResultInfo = function(id, index)
            if id == 1 and failure == "read" then error("synthetic result read failure") end
            return rows[index]
        end
        C_AuctionHouse.RequestMoreCommoditySearchResults = function() error("synthetic page failure") end
        M.Tick()
        if failure == "page" then full = false end
        M.OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED",1)
        now = now+2; M.Tick(); full = true
        now = now+2; M.Tick(); eq(M.active.itemID,2)
        M.OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED",2)
        eq(A.quotes[1].complete,false); eq(A.quotes[2].complete,true); eq(M.batch.completed,1)
    end
end)

test("even a whole batch of missing responses finishes after exactly two attempts each", function()
    recoveryFixture()
    for tick = 0, 700 do now = 3000+tick*0.25; M.Tick() end
    eq(table.concat(sends,","),"1,2,3,1,2,3"); eq(M.active,nil); eq(#M.queue,0)
    eq(M.batch.completed,0); eq(M.batch.failed,3); eq(M.batch.total,3)
end)

test("a synchronous server error cannot schedule duplicate retries when the send also raises", function()
    recoveryFixture()
    C_AuctionHouse.SendSearchQuery = function(key)
        sends[#sends+1] = key.itemID
        M.OnEvent("AUCTION_HOUSE_SHOW_ERROR",123)
        error("synthetic exception after server error")
    end
    for tick = 0, 80 do now = 3000+tick*0.25; M.Tick() end
    eq(#sends,6); eq(M.active,nil); eq(#M.queue,0); eq(M.batch.failed,3)
end)

test("a persistent throttle after one success leaves an honest unfinished count", function()
    recoveryFixture(); M.Tick(); M.OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED",1)
    now = now+2; ready = false; M.Tick()
    now = now+30; M.Tick()
    eq(M.batch.completed,1); eq(M.batch.failed,0); eq(M.batch.total,3)
    eq(#M.queue,0); eq(#sends,1); eq(A.quotes[1].complete,true); eq(A.quotes[2],nil)
    ready = true
end)

print("TOTAL " .. passed .. " tests passed")
