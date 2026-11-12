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
    eq(record(4).price,4500); eq(#MOCK.queries,0)
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

test("fractional unit prices are marked rounded and never look free", function()
    itemInfo = {isCommodity=false}
    local key = {itemID=5,itemLevel=0,itemSuffix=0,battlePetSpeciesID=0}
    itemRows = {{itemKey=key,buyoutAmount=1,quantity=2}}
    event("ITEM_SEARCH_RESULTS_UPDATED",key)
    eq(record(5).price,0.5); eq(MOCK.bagTooltip(5)[2][2],"不足1铜")
    itemRows[1].buyoutAmount = 3; event("ITEM_SEARCH_RESULTS_UPDATED",key)
    eq(MOCK.bagTooltip(5)[2][2],"约 2铜")
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

print("TOTAL " .. passed .. " history/tooltip tests passed")
