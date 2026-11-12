-- Native sell-form handoff must never submit restricted transactions. Operator: Solazhu.
dofile(PROJECT_ROOT .. "/tests/wow_mock.lua")
local A = {}
for _, name in ipairs({"Libs/LibStub.lua","Libs/LibAHTab.lua","Logic.lua","Core.lua","History.lua",
    "Market.lua","Native.lua","Widgets.lua","Editor.lua","UI.lua"}) do
    assert(loadfile(PROJECT_ROOT .. "/AuctionPilot/" .. name))("AuctionPilot",A)
end
A.Initialize()
assert(A.SaveProduct({itemID=1,recipeName="默认配方",output=1,fee=5,extra=0,
    materials={{itemID=2,quantity=1,source="fixed",price=8000}}}))
-- Model the real-client rejection: these APIs must be unreachable from the addon.
for _, name in ipairs({"PostCommodity","PostItem","ConfirmPostCommodity","ConfirmPostItem"}) do
    C_AuctionHouse[name] = function()
        MOCK.postCalls = MOCK.postCalls + 1
        error("restricted transaction API blocked")
    end
end
local function eq(actual,expected)
    assert(actual == expected,"expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function event(name,...) A.events.scripts.OnEvent(A.events,name,...) end
local function reset()
    for _, key in ipairs({"locked","bound","removed","bagItemID","itemGUID","commodityStatus","keyInfo","itemSuffix",
        "coldItem","coldDisplay","depositMissing","deposit","money","ready","combat","copper","availableCount",
        "rejectPostItem"}) do MOCK[key] = nil end
    MOCK.time,MOCK.timers,MOCK.delayed,MOCK.queries,MOCK.postCalls,MOCK.nativeSetPostCalls = 100,{},{},{},0,0
    A.Native.pendingPost = nil
    A.open = true; A.Market.Pause(); A.Native.ShowMonitor(); MOCK.flush(); A.Select(1)
    A.UI.durationID = 2; A.UI.price:SetCopper(12000); A.UI.priceEdited = true
    A.UI.quantity:SetText("20"); A.RefreshUI()
end
local passed = 0
local function test(name,callback)
    reset()
    local ok,err = pcall(callback)
    if not ok then error(name .. ": " .. tostring(err)) end
    eq(MOCK.postCalls,0)
    passed = passed + 1; print("PASS " .. name)
end
local function click() A.UI.postButton:Click() end

test("readonly price quantity duration and deposit previews never submit or search",function()
    eq(A.UI.deposit:GetText(),"30银"); eq(A.UI.totalPrice:GetText(),"24金")
    eq(A.UI.postButton:GetText(),"准备上架")
    A.UI.quantity:SetUserText("3"); eq(A.UI.postPreview.deposit,500)
    MOCK.copper = true; A.RefreshUI(); eq(A.UI.postPreview.deposit,450)
    A.UI.duration:Click(); MOCK.menu.entries[3]:Click()
    eq(A.UI.durationID,3); eq(A.UI.postPreview.deposit,675)
    A.UI.maxQuantity:Click(); eq(A.UI.quantity:GetText(),"120")
    for _, tick in ipairs(MOCK.tickers) do tick() end
    MOCK.flush(); eq(#MOCK.queries,0); eq(MOCK.nativeSetPostCalls,0)
end)

test("commodity prepare accepts the native item lock and transfers exact values without posting",function()
    A.UI.durationID = 3; A.RefreshUI(); click()
    eq(MOCK.locked,true)
    local form = AuctionHouseFrame.CommoditiesSellFrame
    eq(form:IsVisible(),true); eq(A.UI.frame:IsShown(),false)
    eq(form:GetQuantity(),0); eq(MOCK.nativeSetPostCalls,1)
    MOCK.flush()
    eq(form:GetQuantity(),20); eq(form.PriceInput:GetAmount(),12000); eq(form.Duration:GetDuration(),3)
    eq(A.Native.pendingPost,nil); eq(StaticPopupDialogs["AUCTIONPILOT_POST_CONFIRM"],nil)
end)

test("ordinary items receive a per-item price quantity and duration in the native form",function()
    MOCK.commodityStatus = Enum.ItemCommodityStatus.Item
    A.UI.durationID = 1; A.UI.quantity:SetText("8"); A.RefreshUI()
    click(); MOCK.flush()
    local form = AuctionHouseFrame.ItemSellFrame
    eq(form:IsVisible(),true); eq(form:GetQuantity(),8)
    eq(form.PriceInput:GetAmount(),12000); eq(form.Duration:GetDuration(),1)
end)

test("invalid fields inventory funds combat and unavailable data cannot start a handoff",function()
    local cases = {
        function() A.UI.price:SetCopper(0) end, function() A.UI.price:SetCopper(12001) end,
        function() A.UI.quantity:SetText("0") end, function() A.UI.quantity:SetText("1.5") end,
        function() A.UI.quantity:SetText("121") end, function() A.UI.durationID = 0 end,
        function() MOCK.locked = true end, function() MOCK.bound = true end,
        function() MOCK.removed = true end, function() MOCK.money = 1 end,
        function() MOCK.combat = true end, function() MOCK.ready = false end,
        function() MOCK.keyInfo = {isEquipment=true} end, function() MOCK.keyInfo = {isPet=true} end,
        function() MOCK.coldItem = true end, function() MOCK.depositMissing = true end,
        function() A.open = false end,
    }
    for _, setup in ipairs(cases) do
        reset(); setup(); A.RefreshUI()
        eq(A.UI.postButton:IsEnabled(),false); click()
        eq(MOCK.nativeSetPostCalls,0); eq(MOCK.postCalls,0)
    end
end)

test("delayed native initialization cannot overwrite the requested quantity",function()
    MOCK.coldDisplay = true; click(); MOCK.flush()
    local pending = assert(A.Native.pendingPost)
    eq(pending.form:GetQuantity(),0)
    MOCK.coldDisplay = nil
    event("ITEM_DATA_LOAD_RESULT",1)
    AuctionHouseFrame:SetPostItem(pending.item)
    eq(pending.form:GetQuantity(),120)
    MOCK.flush()
    eq(pending.form:GetQuantity(),20); eq(pending.form.PriceInput:GetAmount(),12000)
    eq(pending.form.Duration:GetDuration(),2); eq(A.Native.pendingPost,nil)
end)

test("manual native quantity price duration and item edits cancel pending autofill",function()
    local actions = {
        function(form) form.QuantityInput.InputBox:SetUserText("7") end,
        function(form) form.PriceInput.MoneyInputFrame.GoldBox:SetUserText("3") end,
        function(form) form.Duration.Dropdown:Click() end,
        function(form) form.QuantityInput.MaxButton:Click() end,
        function(form) form.ItemDisplay.ItemButton:Click() end,
    }
    for _, edit in ipairs(actions) do
        reset(); MOCK.coldDisplay = true; click(); MOCK.flush()
        local form = assert(A.Native.pendingPost).form
        edit(form); eq(A.Native.pendingPost,nil)
        local quantity = form:GetQuantity()
        MOCK.coldDisplay = nil; event("GET_ITEM_INFO_RECEIVED",1); MOCK.flush()
        eq(form:GetQuantity(),quantity)
    end
end)

test("leaving the native sell page or closing AH prevents delayed autofill",function()
    for _, leave in ipairs({
        function() A.Native.Navigate("buy") end,
        function() event("AUCTION_HOUSE_CLOSED") end,
    }) do
        reset(); MOCK.coldDisplay = true; click(); MOCK.flush()
        local form = assert(A.Native.pendingPost).form
        leave(); eq(A.Native.pendingPost,nil)
        MOCK.coldDisplay = nil; event("ITEM_DATA_LOAD_RESULT",1); MOCK.flush()
        eq(form:GetQuantity(),0)
    end
end)

test("inventory identity availability and combat are rechecked before filling",function()
    for _, change in ipairs({
        function() MOCK.availableCount = 10 end, function() MOCK.itemGUID = "replacement" end,
        function() MOCK.removed = true end, function() MOCK.bagItemID = 2 end,
        function() MOCK.bound = true end, function() MOCK.combat = true end,
    }) do
        reset(); MOCK.coldDisplay = true; click(); MOCK.flush()
        local form = assert(A.Native.pendingPost).form
        change(); MOCK.coldDisplay = nil; event("ITEM_DATA_LOAD_RESULT",1); MOCK.flush()
        eq(form:GetQuantity(),0); eq(A.Native.pendingPost,nil)
    end
end)

test("handoff timeout clears pending state and ignores later native data",function()
    MOCK.coldDisplay = true; click(); MOCK.flush()
    local form = assert(A.Native.pendingPost).form
    MOCK.time = MOCK.time + 6; MOCK.flush(); eq(A.Native.pendingPost,nil)
    MOCK.coldDisplay = nil; event("GET_ITEM_INFO_RECEIVED",1); MOCK.flush()
    eq(form:GetQuantity(),0); eq(MOCK.nativeSetPostCalls,1)
end)

test("repeated clicks cannot start overlapping handoffs",function()
    MOCK.coldDisplay = true; click()
    eq(A.Native.PreparePost(A.Selected(),12000,20,2),nil)
    click(); eq(MOCK.nativeSetPostCalls,1)
    MOCK.flush(); eq(MOCK.nativeSetPostCalls,1)
end)

test("native rejection keeps the monitor available and reports an error",function()
    MOCK.rejectPostItem = true; click(); MOCK.flush()
    eq(A.Native.pendingPost,nil); eq(A.UI.frame:IsVisible(),true)
    assert(A.UI.message:GetText():find("未接收物品"))
end)

test("late warnings results and timers never cause addon transaction calls",function()
    click(); MOCK.flush()
    for _, name in ipairs({"AUCTION_HOUSE_POST_WARNING","AUCTION_HOUSE_POST_ERROR",
        "AUCTION_HOUSE_AUCTION_CREATED","AUCTION_MULTISELL_START","AUCTION_MULTISELL_UPDATE"}) do
        event(name,1,1)
    end
    event("AUCTION_HOUSE_CLOSED"); MOCK.time = MOCK.time + 60; MOCK.flush()
    for _, tick in ipairs(MOCK.tickers) do tick() end
    eq(MOCK.nativeSetPostCalls,1)
end)

print(string.format("TOTAL %d native-handoff tests passed",passed))
