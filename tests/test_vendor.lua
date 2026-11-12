-- Only monitored items may enter the merchant-price cache. Operator: Solazhu.
dofile(PROJECT_ROOT .. "/tests/wow_mock.lua")
local A = {}
for _, name in ipairs({"Libs/LibStub.lua","Libs/LibAHTab.lua","Logic.lua","Core.lua","History.lua",
    "Market.lua","Native.lua","Widgets.lua","Editor.lua","UI.lua"}) do
    assert(loadfile(PROJECT_ROOT .. "/AuctionPilot/" .. name))("AuctionPilot",A)
end
A.Initialize()
assert(A.SaveProduct({itemID=1,recipeName="默认配方",output=1,fee=5,extra=0,materials={
    {itemID=2,quantity=2,source="market"}, {itemID=3,quantity=5,source="market"},
    {itemID=4,quantity=1,source="fixed",price=200}}}))
local seed = A.Logic.Copy(A.profile.products)
MerchantFrame = CreateFrame("Frame")
function GetMerchantNumItems() return #MOCK.goods end
function GetMerchantItemID(index) return MOCK.goods[index].itemID end
C_MerchantFrame = {GetItemInfo=function(index)
    MOCK.vendorReads = MOCK.vendorReads + 1
    return MOCK.goods[index].info
end}
local function offer(id,price,count)
    return {itemID=id,info={name="商店材料",price=price,stackCount=count or 1,
        numAvailable=-1,isPurchasable=true,hasExtendedCost=false}}
end
local function eq(actual,expected)
    assert(actual == expected,"expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function event(name) A.events.scripts.OnEvent(A.events,name) end
local function chooseSource(row, text)
    row.sourceButton:Click()
    assert(MOCK.menu, "Source dropdown did not open")
    for _, entry in ipairs(MOCK.menu.entries) do
        if entry.text == text then entry:Click(); return end
    end
    error("Missing source option: " .. text)
end
local function snapshot(id,price)
    A.AcceptQuote(id,A.Logic.Snapshot({{price=price,quantity=1000}},MOCK.time,true))
end
local function reset()
    A.profile.products,A.profile.nextID,A.profile.selectedID = A.Logic.Copy(seed),2,nil
    A.profile.vendorPrices,A.Native.post = {},nil
    MOCK.goods,MOCK.vendorReads,MOCK.serverTime = {offer(99,1),offer(3,9,5),offer(1,1)},0,1794450000
    MOCK.queries,MOCK.postCalls,MOCK.messages,MOCK.menu = {},0,{},nil
    MerchantFrame:Show(); A.open = true; A.Market.Pause()
    A.Editor.Close(); A.Native.ShowMonitor(); MOCK.flush(); A.Select(1)
    A.quotes = {}; snapshot(1,10000); snapshot(2,1000); snapshot(3,500)
end
local passed = 0
local function test(name,callback)
    reset()
    local ok,err = pcall(callback)
    if not ok then error(name .. ": " .. tostring(err)) end
    passed = passed + 1; print("PASS " .. name)
end

test("merchant capture reads prices only for monitored products and recipe materials",function()
    for id=100,599 do table.insert(MOCK.goods,offer(id,100)) end
    event("MERCHANT_SHOW")
    eq(A.profile.vendorPrices[3].price,9); eq(A.profile.vendorPrices[3].stackCount,5)
    eq(A.profile.vendorPrices[1].price,1); eq(A.profile.vendorPrices[99],nil)
    eq(A.profile.vendorPrices[599],nil); eq(MOCK.vendorReads,2)
    eq(#MOCK.queries,0); eq(MOCK.postCalls,0)
    for _, tick in ipairs(MOCK.tickers) do tick() end
    eq(MOCK.vendorReads,2)
end)

test("bundle purchase price is apportioned without confusing sellback or AH prices",function()
    event("MERCHANT_SHOW")
    A.quotes[3].at = MOCK.time - 5000
    local result = A.Estimate(A.Selected())
    eq(result.materials[2].unit,1.8); eq(result.materials[2].cost,9)
    eq(result.materials[2].source,"vendor"); eq(result.materialCost,2209)
    eq(result.fee,500); eq(result.cost,2709); eq(result.profit,7291); eq(result.stale,false)
    local input = A.Logic.RecipeInput(A.Selected(),A.SelectedRecipe())
    input = A.Logic.Copy(input); input.materials[2].quantity = 2
    eq(A.EstimateInput(input).materials[2].cost,4)
end)

test("manual fixed prices win and monitored sale prices always come from the AH",function()
    table.insert(MOCK.goods,offer(4,9,5)); event("MERCHANT_SHOW")
    local result = A.Estimate(A.Selected())
    eq(result.sale,10000); eq(result.materials[3].source,"fixed"); eq(result.materials[3].cost,200)
    eq(result.materials[1].source,"market"); eq(result.materials[1].cost,2000)
    A.quotes[1] = nil; assert(A.Estimate(A.Selected()).error)
end)

test("limited currency restricted incomplete and invalid offers are not automatic costs",function()
    local cases = {
        {numAvailable=0}, {numAvailable=3}, {hasExtendedCost=true}, {currencyID=7},
        {spellID=7}, {isPurchasable=false}, {price=0}, {price=-1}, {price=0/0},
        {stackCount=0}, {stackCount=1.5}, {name=""},
    }
    for _, fields in ipairs(cases) do
        MOCK.goods = {offer(3,9,5)}
        for key,value in pairs(fields) do MOCK.goods[1].info[key] = value end
        event("MERCHANT_SHOW"); eq(A.profile.vendorPrices[3],nil)
    end
    MOCK.goods = {{itemID=3}}; event("MERCHANT_SHOW"); eq(A.profile.vendorPrices[3],nil)
end)

test("visible merchant updates complete delayed data and closed updates do nothing",function()
    MOCK.goods = {{itemID=3}}; event("MERCHANT_SHOW")
    eq(A.profile.vendorPrices[3],nil)
    MOCK.goods = {offer(3,9,5)}; event("MERCHANT_UPDATE"); eq(A.profile.vendorPrices[3].price,9)
    MOCK.serverTime = 1794450100; MOCK.goods = {offer(3,8,5)}
    event("MERCHANT_UPDATE"); eq(A.profile.vendorPrices[3].price,8)
    eq(A.profile.vendorPrices[3].seenAt,1794450100)
    MOCK.goods[1].info = nil; event("MERCHANT_UPDATE"); eq(A.profile.vendorPrices[3].price,8)
    MerchantFrame:Hide(); MOCK.goods = {offer(3,100,5)}
    event("MERCHANT_UPDATE"); eq(A.profile.vendorPrices[3].price,8)
end)

test("batch refresh skips merchant materials but individual refresh remains a reference",function()
    event("MERCHANT_SHOW")
    assert(A.Market.RequestRefresh("all")); eq(#A.Market.queue,2)
    eq(A.Market.queue[1],1); eq(A.Market.queue[2],2)
    A.Market.Pause(); assert(A.Market.RequestRefresh("materials",1,1))
    eq(#A.Market.queue,1); eq(A.Market.queue[1],2)
    A.Market.Pause(); assert(A.Market.RequestItem(3)); eq(A.Market.queue[1],3)
    snapshot(3,1); eq(A.Estimate(A.Selected()).materials[2].cost,9)
    A.Market.Pause()
end)

test("material detail and editor disclose merchant sourcing and allow a fixed override",function()
    event("MERCHANT_SHOW"); A.RefreshUI()
    eq(A.UI.materialRows[2].age:GetText(),"商店价")
    assert(A.UI.materialRows[2].help:find("5 件"))
    A.Editor.Open(A.Selected())
    local row = A.Editor.rows[2]
    eq(row.sourceButton:GetText(),"自动"); eq(row.price.boxes[1]:IsEnabled(),false)
    chooseSource(row,"固定价"); row.price:SetCopper(6); A.Editor.Preview()
    eq(row.sourceButton:GetText(),"固定价"); eq(A.EstimateInput(A.Editor.Read()).materials[2].cost,30)
    chooseSource(row,"自动（商店优先）"); eq(A.EstimateInput(A.Editor.Read()).materials[2].cost,9)
    A.Editor.Close()
end)

test("all saved alternate recipes are tracked and removing one prunes only its unique material",function()
    assert(A.SaveProduct({id=1,itemID=1,recipeName="备选",output=1,fee=5,extra=0,
        materials={{itemID=6,quantity=1,source="market"}}}))
    table.insert(MOCK.goods,offer(6,99)); event("MERCHANT_SHOW")
    eq(A.profile.vendorPrices[6].price,99); eq(A.profile.vendorPrices[3].price,9)
    assert(A.DeleteRecipe(1,2)); eq(A.profile.vendorPrices[6],nil)
    eq(A.profile.vendorPrices[3].price,9)
end)

test("product deletion keeps shared materials until their last monitored reference disappears",function()
    assert(A.SaveProduct({itemID=5,recipeName="共享材料",output=1,fee=5,extra=0,
        materials={{itemID=3,quantity=1,source="market"}}}))
    event("MERCHANT_SHOW"); A.DeleteProduct(1)
    eq(A.profile.vendorPrices[1],nil); eq(A.profile.vendorPrices[3].price,9)
    A.DeleteProduct(2); eq(next(A.profile.vendorPrices),nil)
    MOCK.vendorReads = 0; event("MERCHANT_SHOW"); eq(MOCK.vendorReads,0)
end)

test("editing materials prunes old prices and adding later requires a new merchant visit",function()
    event("MERCHANT_SHOW")
    local input = A.Logic.Copy(A.Logic.RecipeInput(A.Selected(),A.SelectedRecipe()))
    input.id,input.recipeID,input.recipeName = 1,1,"默认配方"
    input.materials = {{itemID=7,quantity=1,source="market"}}
    assert(A.SaveProduct(input)); eq(A.profile.vendorPrices[3],nil); eq(A.profile.vendorPrices[7],nil)
    MOCK.goods = {offer(7,10)}; event("MERCHANT_SHOW"); eq(A.profile.vendorPrices[7].price,10)
end)

test("invalid cached entries fall back to AH instead of creating free materials",function()
    for _, entry in ipairs({{}, {price=0,stackCount=1,seenAt=1},
        {price=9,stackCount=0,seenAt=1}, {price=9,stackCount=5,seenAt="bad"}}) do
        A.profile.vendorPrices[3] = entry
        eq(A.Estimate(A.Selected()).materials[2].cost,2500)
    end
end)

test("merchant records survive reload inside the character profile",function()
    event("MERCHANT_SHOW")
    AuctionPilotDB = A.Logic.Copy(AuctionPilotDB)
    A.profile = nil; A.Initialize()
    eq(A.profile.vendorPrices[3].price,9); eq(AuctionPilotDB.vendorPrices,nil)
    eq(A.Estimate(A.Selected()).materials[2].cost,9)
end)

test("opening the source dropdown does not change the draft and exposes all four choices",function()
    event("MERCHANT_SHOW"); A.Editor.Open(A.Selected())
    local row = A.Editor.rows[2]
    row.sourceButton:Click()
    eq(row.source,"market"); assert(MOCK.menu); eq(#MOCK.menu.entries,4)
    eq(MOCK.menu.entries[1].text,"自动（商店优先）")
    eq(MOCK.menu.entries[2].text,"AH价"); eq(MOCK.menu.entries[3].text,"商店价")
    eq(MOCK.menu.entries[4].text,"固定价"); eq(MOCK.menu.entries[1].selected(),true)
    A.RefreshUI(); assert(MOCK.menu); eq(row.source,"market")
    A.Editor.Close(); eq(A.SelectedRecipe().materials[2].source,"market")
end)

test("explicit AH pricing persists through capture refresh save and reload",function()
    event("MERCHANT_SHOW"); A.Editor.Open(A.Selected())
    chooseSource(A.Editor.rows[2],"AH价")
    eq(A.Editor.rows[2].sourceButton:GetText(),"AH价")
    eq(A.EstimateInput(A.Editor.Read()).materials[2].cost,2500)
    assert(A.SaveProduct(A.Editor.Read())); A.Editor.Close()
    MOCK.goods[2].info.price = 8; event("MERCHANT_UPDATE")
    eq(A.SelectedRecipe().materials[2].source,"auction")
    eq(A.Estimate(A.Selected()).materials[2].cost,2500)
    assert(A.Market.RequestRefresh("materials")); eq(#A.Market.queue,2)
    eq(A.Market.queue[2],3); A.Market.Pause()
    AuctionPilotDB = A.Logic.Copy(AuctionPilotDB); A.profile = nil; A.Initialize()
    eq(A.SelectedRecipe().materials[2].source,"auction")
    eq(A.Estimate(A.Selected()).materials[2].cost,2500)
end)

test("explicit merchant pricing never silently falls back to AH when its record is missing",function()
    A.Editor.Open(A.Selected()); chooseSource(A.Editor.rows[2],"商店价")
    local draft = A.Editor.Read()
    assert(A.Logic.Validate(draft))
    local result = A.EstimateInput(draft)
    assert(result.error); eq(result.materials[2].cost,nil); eq(result.roi,nil)
    eq(A.Editor.rows[2].price:GetCopper(),nil)
    assert(A.SaveProduct(draft)); A.Editor.Close()
    assert(A.Market.RequestRefresh("materials")); eq(#A.Market.queue,1); A.Market.Pause()
    event("MERCHANT_SHOW"); eq(A.Estimate(A.Selected()).materials[2].cost,9)
    eq(A.SelectedRecipe().materials[2].source,"vendor")
end)

test("native recipe reimport preserves explicitly chosen AH and merchant sources",function()
    A.Editor.Open(A.Selected())
    chooseSource(A.Editor.rows[1],"AH价"); chooseSource(A.Editor.rows[2],"商店价")
    local readRecipe = A.Native.ReadRecipe
    A.Native.ReadRecipe = function() return {itemID=1,recipeName="重读",output=1,materials={
        {itemID=2,quantity=3,source="market"},{itemID=3,quantity=1,source="market"}}} end
    A.Editor.ImportRecipe(); A.Native.ReadRecipe = readRecipe
    eq(A.Editor.rows[1].source,"auction"); eq(A.Editor.rows[2].source,"vendor")
    A.Editor.Close()
end)

test("merchant chat announces first captures and price changes without repeat-update spam",function()
    event("MERCHANT_SHOW"); eq(#MOCK.messages,2)
    assert(MOCK.messages[1]:find("已记录商店价")); assert(MOCK.messages[1]:find("item:3"))
    assert(MOCK.messages[1]:find("9铜")); assert(MOCK.messages[1]:find("5 件"))
    event("MERCHANT_UPDATE"); event("MERCHANT_SHOW"); eq(#MOCK.messages,2)
    MOCK.goods[2].info.price = 8; event("MERCHANT_UPDATE"); eq(#MOCK.messages,3)
    assert(MOCK.messages[3]:find("商店价已更新"))
    MOCK.goods[2].info.price,MOCK.goods[2].info.stackCount = 16,10
    event("MERCHANT_UPDATE"); eq(#MOCK.messages,3)
    MOCK.goods[2].info.hasExtendedCost = true; event("MERCHANT_UPDATE"); eq(#MOCK.messages,3)
    MOCK.goods = {offer(99,123)}; event("MERCHANT_SHOW"); eq(#MOCK.messages,3)
end)

test("AH tier quantity and purchase budget remain separate from recipe costs",function()
    event("MERCHANT_SHOW")
    A.AcceptQuote(3,A.Logic.Snapshot({{price=1,quantity=100,own=100},
        {price=466,quantity=320,own=20},{price=500,quantity=900}},MOCK.time,true))
    eq(A.UI.materialRows[2].marketQuantity:GetText(),"300")
    eq(A.UI.materialRows[2].tierCost:GetText(),"13金98银")
    eq(A.UI.materialRows[2].cost:GetText(),"9铜")
    assert(A.UI.materialRows[2].help:find("4银66铜 × 300"))
    eq(A.Estimate(A.Selected()).materials[2].cost,9)
    A.quotes[3].at = MOCK.time - 180; A.RefreshUI()
    eq(A.UI.materialRows[2].marketQuantity:GetText(),"300")
    eq(A.UI.materialRows[2].tierCost:GetText(),"13金98银")
    assert(A.UI.materialRows[2].help:find("历史"))
    A.quotes[3].complete = false; A.RefreshUI()
    eq(A.UI.materialRows[2].marketQuantity:GetText(),"--")
    eq(A.UI.materialRows[2].tierCost:GetText(),"--")
    A.quotes[3].complete = true; A.quotes[3].error = "查询失败"; A.RefreshUI()
    eq(A.UI.materialRows[2].marketQuantity:GetText(),"--")
    eq(A.UI.materialRows[2].tierCost:GetText(),"--")
    A.AcceptQuote(3,A.Logic.Snapshot({{price=500,quantity=8,own=8}},MOCK.time,true))
    eq(A.UI.materialRows[2].marketQuantity:GetText(),"无可买量")
    eq(A.UI.materialRows[2].tierCost:GetText(),"--")
    A.AcceptQuote(3,A.Logic.Snapshot({},MOCK.time,true))
    eq(A.UI.materialRows[2].marketQuantity:GetText(),"无挂单")
    eq(A.UI.materialRows[2].tierCost:GetText(),"--")
end)

test("whole-tier funding uses the lowest tier price instead of a blended procurement average",function()
    local material = A.SelectedRecipe().materials[2]
    material.source,material.quantity = "auction",500
    A.AcceptQuote(3,A.Logic.Snapshot({{price=466,quantity=300},{price=500,quantity=900}},MOCK.time,true))
    local estimate = A.Estimate(A.Selected())
    eq(estimate.materials[2].unit,479.6); eq(estimate.materials[2].cost,239800)
    eq(A.UI.materialRows[2].cost:GetText(),"23金98银")
    eq(A.UI.materialRows[2].marketQuantity:GetText(),"300")
    eq(A.UI.materialRows[2].tierCost:GetText(),"13金98银")
    material.source,material.price = "fixed",6; A.RefreshUI()
    eq(A.UI.materialRows[2].cost:GetText(),"30银")
    eq(A.UI.materialRows[2].tierCost:GetText(),"13金98银")
end)

test("tier budgets beyond precise currency arithmetic are withheld without changing recipe profit",function()
    event("MERCHANT_SHOW")
    A.AcceptQuote(3,A.Logic.Snapshot({{price=1000000000000,quantity=1000000}},MOCK.time,true))
    eq(A.UI.materialRows[2].marketQuantity:GetText(),"1000000")
    eq(A.UI.materialRows[2].tierCost:GetText(),"--")
    assert(A.UI.materialRows[2].help:find("超出精确计算范围"))
    eq(A.Estimate(A.Selected()).materials[2].cost,9)
end)

print(string.format("%d merchant-price tests passed",passed))
