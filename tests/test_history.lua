-- Saved historical prices and native bag tooltips. Synthetic prices only. Solazhu.
dofile(PROJECT_ROOT .. "/tests/wow_mock.lua")
local A = {}
-- Use the actual manifest so a missing delivery entry fails this test.
for line in io.lines(PROJECT_ROOT .. "/AuctionPilot/AuctionPilot.toc") do
    if line:match("%.lua$") then
        assert(loadfile(PROJECT_ROOT .. "/AuctionPilot/" .. line:gsub("\\", "/")))("AuctionPilot", A)
    end
end
local passed = 0
local function test(name, callback)
    local ok, err = pcall(callback)
    if not ok then error(name .. ": " .. tostring(err)) end
    passed = passed + 1; print("PASS " .. name)
end
local function eq(a,b) assert(a == b, "expected " .. tostring(b) .. ", got " .. tostring(a)) end
local function event(name, ...) A.events.scripts.OnEvent(A.events, name, ...) end
local full, commodityRows, itemRows, itemInfo = true, {}, {}, {isCommodity=true}
C_AuctionHouse.HasFullCommoditySearchResults = function() return full end
C_AuctionHouse.HasFullItemSearchResults = function() return full end
C_AuctionHouse.GetNumCommoditySearchResults = function() return #commodityRows end
C_AuctionHouse.GetCommoditySearchResultInfo = function(_, i) return commodityRows[i] end
C_AuctionHouse.GetNumItemSearchResults = function() return #itemRows end
C_AuctionHouse.GetItemSearchResultInfo = function(_, i) return itemRows[i] end
C_AuctionHouse.GetItemKeyInfo = function() return itemInfo end
local function record(id) return A.profile.lastSeenPrices[id] end
local function quote(price)
    local q = A.Logic.Snapshot(price and {{price=price,quantity=100}} or {}, MOCK.time, true)
    q.commodity = true
    return q
end

test("initialization adds an empty history without changing existing recipes", function()
    AuctionPilotDB = {version=2,profiles={["TestRealm:TestCharacter"]={products={},nextID=8,custom="preserved"}}}
    A.Initialize()
    eq(A.profile.nextID,8); eq(A.profile.custom,"preserved"); eq(next(A.profile.lastSeenPrices),nil)
    eq(#TooltipDataProcessor.callbacks,1); A.Initialize(); eq(#TooltipDataProcessor.callbacks,1)
    eq(#MOCK.bagTooltip(1),0); eq(#MOCK.queries,0)
end)

test("plugin quotes persist minimum unit price and wall clock time", function()
    event("AUCTION_HOUSE_SHOW"); MOCK.flush()
    MOCK.serverTime = 1794450000
    A.AcceptQuote(1,quote(12000))
    eq(record(1).price,12000); eq(record(1).seenAt,MOCK.serverTime)
    local lines = MOCK.bagTooltip(1)
    eq(#lines,3); assert(lines[2][1]:find("上次最低单价")); eq(lines[2][2],"1金20银")
    assert(lines[3][1]:find("历史参考")); eq(#MOCK.queries,0)
end)

test("partial failed and nonfinite snapshots never replace historical prices", function()
    local saved = record(1)
    local q = quote(1); q.complete = false; A.AcceptQuote(1,q); eq(record(1),saved)
    q = quote(1); q.error = "failed"; A.AcceptQuote(1,q); eq(record(1),saved)
    q = quote(1); q.levels[1].price = math.huge; A.AcceptQuote(1,q); eq(record(1),saved)
    event("AUCTION_HOUSE_SHOW_ERROR"); eq(record(1),saved)
end)

test("native commodity result events work while monitor is hidden and do not query", function()
    eq(A.UI.frame:IsShown(),false)
    commodityRows = {{unitPrice=4200,quantity=10},{unitPrice=3900,quantity=3}}
    MOCK.serverTime = MOCK.serverTime + 90
    event("COMMODITY_SEARCH_RESULTS_UPDATED",2)
    eq(record(2).price,3900); eq(record(2).seenAt,MOCK.serverTime); eq(A.quotes[2],nil)
    eq(#MOCK.queries,0); eq(#A.Market.queue,0)
    local saved = record(2)
    full = false; commodityRows[1].unitPrice = 1
    event("COMMODITY_SEARCH_RESULTS_ADDED",2); eq(record(2),saved)
    full = true
end)

test("native item prices use per-item buyout and ignore bid-only auctions", function()
    itemInfo = {isEquipment=false,isPet=false,isCommodity=false}
    local key = {itemID=4,itemLevel=0,itemSuffix=0,battlePetSpeciesID=0}
    itemRows = {{itemKey=key,buyoutAmount=100000,quantity=20},
        {itemKey=key,buyoutAmount=18000,quantity=4},{itemKey=key,minBid=1,quantity=1}}
    event("ITEM_SEARCH_RESULTS_UPDATED",key)
    eq(record(4).price,18000); eq(#MOCK.queries,0)
    local saved = record(4)
    itemRows[1].itemKey = {itemID=4,itemSuffix=9}
    event("ITEM_SEARCH_RESULTS_ADDED",key); eq(record(4),saved)
    itemRows = {{itemKey=key,buyoutAmount=10,quantity=0}}
    event("ITEM_SEARCH_RESULTS_UPDATED",key); eq(record(4),saved)
end)

test("unknown equipment and pet variants cannot pollute plain item history", function()
    local key = {itemID=5,itemSuffix=0,battlePetSpeciesID=0}
    for _, info in ipairs({{isEquipment=true},{isPet=true}}) do
        itemInfo = info; event("ITEM_SEARCH_RESULTS_UPDATED",key); eq(record(5),nil)
    end
    itemInfo = nil; event("ITEM_SEARCH_RESULTS_UPDATED",key); eq(record(5),nil)
    itemInfo = {isEquipment=false,isPet=false}
    key.itemSuffix = 7; event("ITEM_SEARCH_RESULTS_UPDATED",key); eq(record(5),nil)
end)

test("missing commodity rows cannot fall through to unrelated item results", function()
    itemInfo = {isCommodity=true}
    local saved = record(2)
    local getRow = C_AuctionHouse.GetCommoditySearchResultInfo
    local getItems = C_AuctionHouse.GetItemSearchResultInfo
    commodityRows = {{unitPrice=5000,quantity=1}}
    C_AuctionHouse.GetCommoditySearchResultInfo = function() return nil end
    C_AuctionHouse.GetItemSearchResultInfo = function() error("wrong result accessor") end
    event("COMMODITY_SEARCH_RESULTS_UPDATED",2); eq(record(2),saved)
    C_AuctionHouse.GetCommoditySearchResultInfo = getRow
    C_AuctionHouse.GetItemSearchResultInfo = getItems
end)

test("wizard oil history matches native unit prices regardless of grouped stock", function()
    itemInfo = {isCommodity=false}
    local key = {itemID=20744,itemLevel=0,itemSuffix=0,battlePetSpeciesID=0}
    itemRows = {{itemKey=key,buyoutAmount=290,quantity=1},
        {itemKey=key,buyoutAmount=300,quantity=234},{itemKey=key,buyoutAmount=500,quantity=18}}
    event("ITEM_SEARCH_RESULTS_UPDATED",key)
    eq(record(20744).price,290); eq(MOCK.bagTooltip(20744)[2][2],"2银90铜")
    itemRows[2].quantity = 300; event("ITEM_SEARCH_RESULTS_UPDATED",key)
    eq(record(20744).price,290)
end)

test("legacy mispriced history is retained but withheld until a fresh complete quote", function()
    local legacy = {price=1.5,seenAt=MOCK.serverTime-20}
    A.profile.lastSeenPrices[5] = legacy
    local lines = MOCK.bagTooltip(5)
    eq(lines[2][2],"请在拍卖行刷新"); eq(record(5),legacy)
    local q = quote(290); q.complete = false; A.AcceptQuote(5,q)
    eq(record(5),legacy)
    A.AcceptQuote(5,quote(290)); eq(record(5).priceVersion,2)
    eq(MOCK.bagTooltip(5)[2][2],"2银90铜")
end)

test("a complete empty result records no buyout rather than a zero price", function()
    commodityRows = {}; MOCK.serverTime = MOCK.serverTime + 30
    event("COMMODITY_SEARCH_RESULTS_UPDATED",2)
    eq(record(2).price,nil); eq(record(2).seenAt,MOCK.serverTime)
    local lines = MOCK.bagTooltip(2); assert(lines[2][2]:find("无一口价")); eq(#MOCK.queries,0)
end)

test("bag tooltip rebuilding neither duplicates history nor leaks to other sources", function()
    eq(#MOCK.bagTooltip(1),3); eq(#MOCK.bagTooltip(1),3)
    eq(#MOCK.bagTooltip(999),0); eq(#MOCK.bagTooltip(1,-1),0); eq(#MOCK.bagTooltip(1,9),0)
    GameTooltip.lines = {}
    GameTooltip.primaryInfo = {getterName="GetHyperlink",getterArgs={"item:1"}}
    GameTooltip.processingInfo = GameTooltip.primaryInfo
    for _, callback in ipairs(TooltipDataProcessor.callbacks) do callback(GameTooltip,{id=1}) end
    eq(#GameTooltip.lines,0)
    GameTooltip.primaryInfo = {getterName="GetBagItem",getterArgs={0,1}}
    GameTooltip.processingInfo = {getterName="GetBagItem",getterArgs={0,1},append=true}
    for _, callback in ipairs(TooltipDataProcessor.callbacks) do callback(GameTooltip,{id=1}) end
    eq(#GameTooltip.lines,0)
end)

test("closed AH ignores late results and preserves bag prices", function()
    local saved = record(1)
    event("AUCTION_HOUSE_CLOSED")
    commodityRows = {{unitPrice=1,quantity=5}}
    event("COMMODITY_SEARCH_RESULTS_UPDATED",1); eq(record(1),saved)
    local lines = MOCK.bagTooltip(1); eq(lines[2][2],"1金20银")
end)

test("saved history survives reload time reset without becoming a live quote", function()
    local saved = A.Logic.Copy(AuctionPilotDB)
    local oldStamp = record(1).seenAt
    A.profile = nil; AuctionPilotDB = saved; A.quotes = {}; MOCK.time = 0
    MOCK.serverTime = oldStamp + 90000
    A.Initialize(); eq(record(1).seenAt,oldStamp)
    local lines = MOCK.bagTooltip(1); eq(lines[2][2],"1金20银")
    assert(lines[3][1]:find("25小时前")); eq(#TooltipDataProcessor.callbacks,1)
    event("AUCTION_HOUSE_SHOW"); MOCK.flush()
    eq(next(A.quotes),nil); eq(record(1).price,12000)
    eq(#MOCK.queries,0); eq(MOCK.postCalls,0)
end)

test("other character profiles do not inherit a previous character's price", function()
    local original = A.profile
    A.profile = {products={},nextID=1}; A.History.Initialize()
    eq(#MOCK.bagTooltip(1),0); eq(next(A.profile.lastSeenPrices),nil)
    A.profile = original; eq(MOCK.bagTooltip(1)[2][2],"1金20银")
    eq(#TooltipDataProcessor.callbacks,1); eq(#MOCK.queries,0)
end)

local function setupSeries()
    A.profile = {products={},nextID=1}
    AuctionPilotDB = {version=2,profiles={["TestRealm:TestCharacter"]=A.profile}}
    A.quotes = {}; A.open = true
    A.Market.active, A.Market.draining = nil, nil
    MOCK.time, MOCK.serverTime = 10000, 1794450000
    A.History.Initialize()
    assert(A.SaveProduct({itemID=1,recipeName="价格记录",output=1,fee=5,extra=0,
        materials={{itemID=2,quantity=1,source="market"}}}))
    return A.profile.priceHistory
end

local function sample(itemID, price, seconds)
    seconds = seconds or 30
    MOCK.time, MOCK.serverTime = MOCK.time + seconds, MOCK.serverTime + seconds
    local q = quote(price)
    A.AcceptQuote(itemID,q)
    return q
end

test("watched prices retain consecutive changed and unchanged observations in copper", function()
    local history = setupSeries()
    sample(1,1150); sample(1,1145); sample(1,1145)
    eq(history.version,1); eq(history.first,1); eq(history.next,4)
    eq(history.samples[1][1],1); eq(history.samples[1][2],1794450030)
    eq(history.samples[1][3],1150); eq(history.samples[2][3],1145)
    eq(history.samples[3][3],1145); eq(history.samples[3][2],1794450090)
    eq(A.quotes[1].seenAt,1794450090); eq(record(1).seenAt,1794450090)
end)

test("material and native observations keep bag history without adding monitored samples", function()
    local history = setupSeries()
    sample(2,500); eq(history.next,1); eq(record(2).price,500)
    itemInfo = {isCommodity=true}; full = true
    commodityRows = {{unitPrice=1200,quantity=10}}
    event("COMMODITY_SEARCH_RESULTS_UPDATED",1)
    eq(history.next,1); eq(record(1).price,1200)
    sample(1,1190); eq(history.next,2)
end)

test("duplicate snapshots do not append or acquire a newer collection timestamp", function()
    local history = setupSeries()
    local q = sample(1,1150); local saved = record(1)
    MOCK.serverTime = MOCK.serverTime + 90
    A.AcceptQuote(1,q)
    eq(history.next,2); eq(q.seenAt,1794450030); eq(record(1),saved)
    sample(1,1150); eq(history.next,3)
end)

test("failed partial and invalid observations leave the series intact while empty means no price", function()
    local history = setupSeries()
    sample(1,100); local saved = record(1)
    local q = quote(1); q.complete = false; A.AcceptQuote(1,q)
    q = quote(1); q.error = "failed"; A.AcceptQuote(1,q)
    q = quote(1); q.levels[1].price = math.huge; A.AcceptQuote(1,q)
    eq(history.next,2); eq(record(1),saved)
    sample(1,nil); eq(history.samples[2][3],false); eq(record(1).price,nil)
    sample(1,105,3600); eq(history.samples[3][3],105)
    eq(history.samples[3][2]-history.samples[2][2],3600); eq(history.next,4)
end)

test("cancelled native responses cannot refresh saved prices or append history", function()
    local history = setupSeries()
    sample(1,1150); local saved = record(1)
    itemInfo = {isCommodity=true}; commodityRows = {{unitPrice=1,quantity=10}}
    A.Market.draining = {itemID=1,started=MOCK.time}
    MOCK.serverTime = MOCK.serverTime + 20
    event("COMMODITY_SEARCH_RESULTS_UPDATED",1)
    eq(history.next,2); eq(record(1),saved); eq(A.Market.draining,nil)
end)

test("reload retains sample identity and never converts saved prices into live quotes", function()
    local history = setupSeries(); sample(1,1150); sample(1,1145)
    local saved = A.Logic.Copy(AuctionPilotDB)
    A.profile, A.quotes = nil, {}; AuctionPilotDB = saved
    MOCK.time = 0; MOCK.serverTime = MOCK.serverTime + 60
    A.Initialize(); history = A.profile.priceHistory
    eq(history.first,1); eq(history.next,3); eq(history.samples[1][3],1150)
    eq(history.samples[2][2],1794450060); eq(next(A.quotes),nil)
    sample(1,1160); eq(history.next,4); eq(history.samples[3][2],1794450150)
end)

test("retention expires observations after forty-eight hours without reusing record ids", function()
    local history = setupSeries(); sample(1,100)
    sample(1,200,48*3600); eq(history.first,1); eq(history.next,3)
    sample(1,300,1); eq(history.first,2); eq(history.samples[1],nil)
    MOCK.serverTime = MOCK.serverTime + 48*3600+1
    A.History.Initialize(); eq(history.first,history.next); eq(next(history.samples),nil)
    sample(1,400); eq(history.first,4); eq(history.next,5); eq(history.samples[4][3],400)
    A.profile.priceHistory = A.Logic.Copy(history); A.History.Initialize()
    history = A.profile.priceHistory
    eq(history.first,4); eq(history.next,5); eq(history.samples[4][3],400)
    sample(1,401); eq(history.next,6); eq(history.samples[5][3],401)
end)

test("thirty-thousand-record cap applies across products and removes the oldest samples", function()
    local history = setupSeries()
    assert(A.SaveProduct({itemID=3,recipeName="另一个产品",output=1,fee=5,extra=0,
        materials={{itemID=2,quantity=1,source="market"}}}))
    for i=1,30005 do
        MOCK.time, MOCK.serverTime = MOCK.time+1, MOCK.serverTime+1
        A.History.AcceptQuote(i%2==0 and 1 or 3,quote(100+i))
    end
    eq(history.next-history.first,30000); eq(history.first,6); eq(history.next,30006)
    eq(history.samples[5],nil); eq(history.samples[6][1],1)
    eq(history.samples[30005][1],3); eq(history.samples[30005][3],30105)
    local count=0; for _ in pairs(history.samples) do count=count+1 end
    eq(count,30000)
end)

test("removing a product stops new samples without erasing its retained history", function()
    local history = setupSeries(); sample(1,100)
    A.DeleteProduct(A.Selected().id); sample(1,200)
    eq(history.next,2); eq(history.samples[1][3],100); eq(record(1).price,200)
end)

test("unknown historical storage is preserved and does not interfere with normal pricing", function()
    setupSeries()
    local unknown = {version=99,custom="preserved"}
    A.profile.priceHistory = unknown; A.History.Initialize(); sample(1,100)
    eq(A.profile.priceHistory,unknown); eq(unknown.custom,"preserved"); eq(record(1).price,100)
end)

test("damaged known-format history is preserved instead of partially pruning it", function()
    setupSeries()
    local damaged = {version=1,first=1,next=3,samples={[1]={1,1794450000,100}}}
    A.profile.priceHistory = damaged; A.History.Initialize(); sample(1,101)
    eq(A.profile.priceHistory,damaged); eq(damaged.first,1); eq(damaged.next,3)
    eq(damaged.samples[1][3],100); eq(record(1).price,101)
end)

test("numeric-string history indices are preserved without interrupting initialization", function()
    for _, damaged in ipairs({
        {version=1,first="1",next=2,samples={[1]={1,1794450000,100}}},
        {version=1,first=1,next="2",samples={[1]={1,1794450000,100}}},
        {version=1,first=1,next=2,samples={["1"]={1,1794450000,100}}},
    }) do
        setupSeries()
        A.profile.priceHistory = damaged
        A.History.Initialize(); sample(1,101)
        eq(A.profile.priceHistory,damaged); eq(A.History.prices,nil)
        eq(record(1).price,101)
    end
end)

local function browseRow(id, price, quantity)
    return {itemKey={itemID=id,itemLevel=0,itemSuffix=0,battlePetSpeciesID=0},
        minPrice=price,totalQuantity=quantity or 10}
end

local function browse(rows)
    MOCK.browseResults = rows
    C_AuctionHouse.SendBrowseQuery({searchString="test"})
    event("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
end

test("native browse records untracked materials without querying or creating a price series", function()
    local history = setupSeries(); itemInfo = {isCommodity=true}
    local queries, pages = #MOCK.queries, MOCK.browsePageRequests or 0
    browse({browseRow(999,1150)})
    eq(record(999).price,1150); eq(record(999).seenAt,MOCK.serverTime)
    eq(record(999).source,"browse"); eq(history.next,1); eq(A.quotes[999],nil)
    eq(#MOCK.queries,queries); eq(MOCK.browsePageRequests or 0,pages)
    assert(MOCK.bagTooltip(999)[2][1]:find("搜索参考价",1,true))
end)

test("a fresh same-price browse renews time but unsolicited cached browse events do not", function()
    setupSeries(); itemInfo = {isCommodity=true}
    browse({browseRow(999,1150)}); local saved = record(999)
    MOCK.serverTime = MOCK.serverTime+30
    event("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED"); eq(record(999),saved)
    browse({browseRow(999,1150)}); eq(record(999).seenAt,MOCK.serverTime)
    eq(record(999).price,1150)
end)

test("browse pagination records only newly returned rows without redating earlier pages", function()
    setupSeries(); itemInfo = {isCommodity=false}
    browse({browseRow(999,1150)}); local saved = record(999)
    MOCK.serverTime = MOCK.serverTime+30
    local added = {browseRow(998,300)}
    MOCK.browseResults = {browseRow(999,1150),added[1]}
    C_AuctionHouse.RequestMoreBrowseResults()
    event("AUCTION_HOUSE_BROWSE_RESULTS_ADDED",added)
    eq(record(999),saved); eq(record(998).price,300); eq(record(998).seenAt,MOCK.serverTime)
    local second = record(998)
    MOCK.serverTime = MOCK.serverTime+30; C_AuctionHouse.RequestMoreBrowseResults()
    event("AUCTION_HOUSE_BROWSE_RESULTS_ADDED",nil)
    eq(record(999),saved); eq(record(998),second)
end)

test("browse metadata may arrive later without replacing a newer complete price", function()
    setupSeries(); itemInfo = nil
    browse({browseRow(999,1150)}); eq(record(999),nil)
    local observed = MOCK.serverTime; MOCK.serverTime = MOCK.serverTime+30
    itemInfo = {isCommodity=true}; event("ITEM_KEY_ITEM_INFO_RECEIVED",999)
    eq(record(999).price,1150); eq(record(999).seenAt,observed)
    itemInfo = nil; browse({browseRow(998,400)})
    MOCK.serverTime = MOCK.serverTime+30; sample(998,390)
    local saved = record(998); itemInfo = {isCommodity=true}
    event("ITEM_KEY_ITEM_INFO_RECEIVED",998); eq(record(998),saved)
end)

test("browse does not downgrade a complete same-second price or turn empty rows into zero", function()
    setupSeries(); itemInfo = {isCommodity=true}
    sample(999,1145); local saved = record(999)
    browse({browseRow(999,1150)}); eq(record(999),saved)
    MOCK.serverTime = MOCK.serverTime+1
    browse({browseRow(999,0,0),browseRow(998,math.huge),browseRow(997,100,-1)})
    eq(record(999),saved); eq(record(998),nil); eq(record(997),nil)
    browse({browseRow(999,1100)}); eq(record(999).source,"browse")
    commodityRows = {{unitPrice=1090,quantity=10}}; full = true
    event("COMMODITY_SEARCH_RESULTS_UPDATED",999)
    eq(record(999).price,1090); eq(record(999).source,nil)
    assert(MOCK.bagTooltip(999)[2][1]:find("上次最低单价",1,true))
end)

test("equipment pet suffix and failed or closed browse results preserve existing references", function()
    setupSeries(); itemInfo = {isCommodity=true}; browse({browseRow(999,1150)})
    local saved = record(999)
    for _, info in ipairs({{isEquipment=true},{isPet=true}}) do
        itemInfo = info; browse({browseRow(998,100)}); eq(record(998),nil)
    end
    itemInfo = {isCommodity=true}; local row = browseRow(998,100); row.itemKey.itemSuffix=7
    browse({row}); eq(record(998),nil)
    MOCK.browseResults = {browseRow(999,1)}
    C_AuctionHouse.SendBrowseQuery({}); event("AUCTION_HOUSE_BROWSE_FAILURE")
    event("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED"); eq(record(999),saved)
    C_AuctionHouse.SendBrowseQuery({}); event("AUCTION_HOUSE_CLOSED")
    event("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED"); eq(record(999),saved)
    event("AUCTION_HOUSE_SHOW"); MOCK.flush()
    event("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED"); eq(record(999),saved)
    itemInfo = nil; browse({browseRow(997,100)})
    event("AUCTION_HOUSE_CLOSED"); itemInfo = {isCommodity=true}
    event("AUCTION_HOUSE_SHOW"); MOCK.flush(); event("ITEM_KEY_ITEM_INFO_RECEIVED",997)
    eq(record(997),nil)
end)

test("favorite and item-key searches overwrite one reference per item without adding requests", function()
    local history = setupSeries(); itemInfo = {isCommodity=true}
    local queries, pages = #MOCK.queries, MOCK.browsePageRequests or 0
    for i=1,20 do
        MOCK.serverTime = MOCK.serverTime+30
        MOCK.browseResults = {browseRow(999,100+i),browseRow(998,200+i)}
        if i%2==0 then C_AuctionHouse.SearchForFavorites({})
        else C_AuctionHouse.SearchForItemKeys({}, {}) end
        event("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
    end
    local count=0; for _ in pairs(A.profile.lastSeenPrices) do count=count+1 end
    eq(count,2); eq(record(999).price,120); eq(record(998).price,220)
    eq(history.next,1); eq(#MOCK.queries,queries); eq(MOCK.browsePageRequests or 0,pages)
end)

print("TOTAL " .. passed .. " history/tooltip tests passed")
