-- Behavior tests run the actual addon files against narrow WoW API stubs. Solazhu.
dofile(PROJECT_ROOT .. "/tests/wow_mock.lua")
local A = {}
for _, name in ipairs({"Libs/LibStub.lua", "Libs/LibAHTab.lua", "Logic.lua", "Core.lua", "History.lua", "Market.lua",
    "Native.lua", "Widgets.lua", "Editor.lua", "UI.lua"}) do
    assert(loadfile(PROJECT_ROOT .. "/AuctionPilot/" .. name))("AuctionPilot", A)
end
local passed = 0
local function test(name, callback)
    local ok, err = pcall(callback)
    if not ok then error(name .. ": " .. tostring(err)) end
    passed = passed + 1; print("PASS " .. name)
end
local function eq(actual, expected) assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual)) end
local function event(name, ...) A.events.scripts.OnEvent(A.events, name, ...) end
local function button(text)
    for _, frame in ipairs(MOCK.frames) do
        if frame.kind == "Button" and frame.text == text and frame:IsVisible() then return frame end
    end
    error("Visible button not found: " .. text)
end
local function menuEntry(text)
    assert(MOCK.menu, "No menu open")
    for _, entry in ipairs(MOCK.menu.entries) do
        if entry.callback and entry.text:sub(1, #text) == text then return entry end
    end
    error("Menu entry not found: " .. text)
end
local function editSelected()
    A.UI.detailMenu:Click(); menuEntry("编辑当前方案"):Click()
end
test("load all TOC modules and initialize offline", function()
    event("ADDON_LOADED", "AuctionPilot"); MOCK.flush()
    eq(#A.profile.products, 0); eq(A.UI.frame:IsShown(), false)
    SlashCmdList.AUCTIONPILOT(); eq(A.UI.frame:IsShown(), true)
    eq(A.UI.postButton:IsEnabled(), false); eq(A.UI.refresh:IsEnabled(), false)
end)
test("save rejects incomplete configuration and preserves storage", function()
    button("+ 添加产品"):Click(); button("保存配方"):Click()
    eq(#A.profile.products, 0); assert(A.Editor.error:GetText() ~= "")
end)
test("drag item into editor and manually save material graph", function()
    local e = A.Editor
    MOCK.cursor = {"item", 1}; e.item.scripts.OnReceiveDrag(); eq(e.item.itemID, 1); eq(MOCK.cursor, nil)
    e.rows[1].item:SetItem(2); e.rows[1].quantity:SetUserText("2")
    button("+ 添加材料"):Click()
    e.rows[2].item:SetItem(3); e.rows[2].sourceButton:Click(); menuEntry("固定价"):Click(); e.rows[2].price:SetCopper(200)
    button("保存配方"):Click()
    eq(#A.profile.products, 1); eq(A.profile.products[1].recipes[1].materials[2].price, 200)
    eq(A.Editor.frame:IsShown(), false); eq(A.UI.main:IsShown(), true)
end)
test("cancel editing cannot mutate persisted product", function()
    editSelected(); A.Editor.output:SetUserText("8"); button("取消"):Click()
    eq(A.profile.products[1].recipes[1].output, 1)
end)
test("source switch cannot silently invent a free fixed price", function()
    editSelected(); A.Editor.rows[1].sourceButton:Click(); menuEntry("固定价"):Click(); button("保存配方"):Click()
    assert(A.Editor.error:GetText() ~= ""); eq(A.profile.products[1].recipes[1].materials[1].source, "market")
    button("取消"):Click()
end)
test("native AH integration adds one tab and keeps native frame open", function()
    event("AUCTION_HOUSE_SHOW"); MOCK.flush(); A.Native.ShowMonitor(); MOCK.flush()
    eq(#LibStub("LibAHTab-1-0").internalState.Tabs, 1)
    A.Native.Attach(); eq(#LibStub("LibAHTab-1-0").internalState.Tabs, 1)
    eq(AuctionHouseFrame:IsShown(), true); eq(A.UI.frame:IsShown(), true)
end)
test("live snapshots populate actual text and prices", function()
    A.AcceptQuote(2, A.Logic.Snapshot({{price = 4200, quantity = 100}}, MOCK.time, true))
    A.AcceptQuote(1, A.Logic.Snapshot({{price = 12000, quantity = 200, own = 40}}, MOCK.time, true))
    eq(A.UI.profit:GetText(), "预计利润 28银 / 件"); eq(A.UI.roi:GetText(), "总成本利润率 30.4%")
    eq(A.UI.price:GetCopper(), 12000)
end)
test("price refresh cannot overwrite a player's typed listing price", function()
    A.UI.price.boxes[1]:SetUserText("2")
    A.AcceptQuote(1, A.Logic.Snapshot({{price = 11000, quantity = 200, own = 40}}, MOCK.time, true))
    eq(A.UI.price:GetCopper(), 22000)
    button("最低价"):Click(); eq(A.UI.price:GetCopper(), 11000)
end)
test("same-price alert is deduplicated and disappears after own stock sells", function()
    local function q(total, own) return A.Logic.Snapshot({{price = 11000, quantity = total, own = own}}, MOCK.time, true) end
    local start = MOCK.sounds or 0
    A.AcceptQuote(1, q(280, 40)); eq(MOCK.sounds, start + 1)
    A.AcceptQuote(1, q(280, 40)); eq(MOCK.sounds, start + 1)
    A.AcceptQuote(1, q(240, 0)); eq(A.alerts[1], nil)
end)
test("alert cooldown survives disappearance and reappearance", function()
    local start = MOCK.sounds
    local rows = {{price = 11000, quantity = 40, own = 40}, {price = 10000, quantity = 5}}
    A.AcceptQuote(1, A.Logic.Snapshot(rows, MOCK.time, true)); eq(MOCK.sounds, start)
    A.AcceptQuote(1, A.Logic.Snapshot({{price = 11000, quantity = 40, own = 40}}, MOCK.time, true))
    MOCK.time = MOCK.time + 31
    A.AcceptQuote(1, A.Logic.Snapshot(rows, MOCK.time, true)); eq(MOCK.sounds, start + 1)
end)
test("stale baseline is not a same-price change detector", function()
    MOCK.time = MOCK.time + 121
    local start = MOCK.sounds
    A.AcceptQuote(1, A.Logic.Snapshot({{price = 11000, quantity = 400, own = 40}}, MOCK.time, true))
    eq(MOCK.sounds, start)
end)
test("native navigation pauses background monitor", function()
    A.Native.Navigate("buy"); eq(A.UI.frame:IsShown(), false); eq(A.Market.active, nil); eq(#A.Market.queue, 0)
    A.Native.ShowMonitor(); MOCK.flush(); eq(A.UI.frame:IsShown(), true)
end)
test("editor has removable rows and requires at least one material", function()
    editSelected()
    for _, row in ipairs(A.Editor.rows) do if row:IsShown() then row.remove:Click() end end
    button("保存配方"):Click(); assert(A.Editor.error:GetText() ~= "")
    button("取消"):Click(); eq(#A.SelectedRecipe().materials, 2)
end)
test("reopening AH retains the last estimate as historical without querying or enabling live prices", function()
    local sale, material = A.quotes[1], A.quotes[2]
    local before = A.Estimate(A.Selected())
    eq(#MOCK.queries,0)
    A.UI.refresh:Click(); eq(table.concat(A.Market.queue,","),"1,2")
    A.Market.Tick(); eq(#MOCK.queries,1); eq(MOCK.queries[1],1)
    event("AUCTION_HOUSE_CLOSED"); eq(A.open, false); eq(#A.profile.products, 1)
    eq(A.UI.frame:IsShown(), false); eq(#A.Market.queue, 0)
    event("AUCTION_HOUSE_SHOW"); MOCK.flush(); A.Native.ShowMonitor(); MOCK.flush()
    eq(A.quotes[1],sale); eq(A.quotes[2],material)
    eq(A.Estimate(A.Selected()).roi,before.roi); eq(A.Estimate(A.Selected()).stale,true)
    eq(A.Logic.Fresh(sale,MOCK.time,A.ttl),false); eq(A.UI.usePrice:IsEnabled(),false)
    assert(A.UI.profit:GetText():find("历史利润")); eq(#MOCK.queries,1)
end)
test("one product row shows the selected recipe and menu switches independent estimates", function()
    A.Native.ShowMonitor(); MOCK.flush()
    A.UI.productRows[1].menu:Click(); menuEntry("添加方案"):Click()
    A.Editor.name:SetText("双份方案"); A.Editor.output:SetText("2")
    A.Editor.rows[1].item:SetItem(2); A.Editor.rows[1].quantity:SetText("3")
    button("保存配方"):Click()
    eq(#A.Selected().recipes,2); eq(A.SelectedRecipe().name,"双份方案")
    A.AcceptQuote(1,A.Logic.Snapshot({{price=12000,quantity=100}},MOCK.time,true))
    A.AcceptQuote(2,A.Logic.Snapshot({{price=4200,quantity=100}},MOCK.time,true))
    local row = A.UI.productRows[1]
    eq(row.cost:GetText(),"69银"); eq(row.profit:GetText(),"+51银")
    eq(row.recipe:GetText(),"双份方案"); eq(row:GetHeight(),42)
    row.menu:Click()
    eq(menuEntry("默认配方").selected(),false); eq(menuEntry("双份方案").selected(),true)
    assert(menuEntry("默认配方").text:find("28银"))
    assert(menuEntry("双份方案").text:find("51银"))
    A.UI.price:SetCopper(15000); A.UI.priceEdited = true
    menuEntry("默认配方"):Click(); eq(A.SelectedRecipe().id,1); eq(A.UI.price:GetCopper(),15000)
    eq(row.cost:GetText(),"92银"); eq(A.UI.materialRows[1].quantity:GetText(),"2")
    row.menu:Click(); menuEntry("双份方案"):Click(); editSelected()
    A.Editor.output:SetText("4"); button("保存配方"):Click()
    eq(A.Selected().recipes[1].output,1); eq(A.Selected().recipes[2].output,4)
    eq(AuctionPilotDB.profiles["TestRealm:TestCharacter"].products[1].activeRecipeID,2)
    eq(#A.Market.queue,0); eq(#MOCK.queries,1)
end)

test("duplicate recipes and product identity changes leave saved data intact", function()
    local p = A.Selected(); local nextID = p.nextRecipeID
    local draft = A.Logic.RecipeInput(p,p.recipes[1]); draft.id = p.id; draft.recipeName = p.recipes[1].name
    eq(A.SaveProduct(draft),nil)
    draft.recipeName = " "; eq(A.SaveProduct(draft),nil)
    draft.recipeName = "新方案"; draft.itemID = 4; eq(A.SaveProduct(draft),nil)
    eq(#A.Selected().recipes,2); eq(A.Selected().nextRecipeID,nextID)
    A.Editor.Open(p); local before = A.Editor.item.itemID
    MOCK.cursor = {"item",4}; A.Editor.item.scripts.OnReceiveDrag(); eq(A.Editor.item.itemID,before)
    MOCK.cursor = nil; button("取消"):Click()
end)

test("manual mode retains dated estimates but failed quotes never become profit", function()
    local before = A.Estimate(A.Selected()).unitProfit
    MOCK.time = MOCK.time + 121
    for _, tick in ipairs(MOCK.tickers) do for _ = 1,4 do tick() end end
    eq(#MOCK.queries,1); eq(#A.Market.queue,0)
    eq(A.Estimate(A.Selected()).unitProfit,before); eq(A.Estimate(A.Selected()).stale,true)
    assert(A.UI.profit:GetText():find("历史利润")); eq(A.UI.usePrice:IsEnabled(),false)
    A.quotes[2].complete = false; A.quotes[2].error = "查询失败"; A.RefreshUI()
    eq(A.Estimate(A.Selected()).unitProfit,nil); assert(A.UI.productRows[1].age:GetText():find("缺价"))
    A.AcceptQuote(2,A.Logic.Snapshot({{price=4200,quantity=100}},MOCK.time,true))
end)

test("deleting the active recipe falls back without deleting other recipes", function()
    A.Editor.Open(A.Selected()); button("删除方案"):Click(); eq(#A.Selected().recipes,2)
    local popup = MOCK.popup; StaticPopupDialogs[popup.which].OnAccept(nil,popup.data)
    eq(#A.Selected().recipes,1); eq(A.SelectedRecipe().id,1)
    eq(A.DeleteRecipe(1,1),nil); eq(#A.Selected().recipes,1)
end)

local function recipeFixture()
    return {recipeID=900,name="专业硫酸",outputItemID=1,quantityMin=1,quantityMax=1,
        reagentSlotSchematics={
            {reagentType=1,quantityRequired=2,reagents={{itemID=2}},variableQuantities={}},
            {reagentType=1,quantityRequired=1,reagents={{itemID=3}},variableQuantities={}},
        }}
end
local schematic, selectedRecipe, readLevel
local function enableRecipeAPI()
    schematic, selectedRecipe = recipeFixture(), {recipeID=900,name="专业硫酸",learned=true}
    Enum.CraftingReagentType = {Basic=1,Modifying=0}
    ProfessionsFrame = {CraftingPage={SchematicForm={
        GetRecipeInfo=function() return selectedRecipe end, GetCurrentRecipeLevel=function() return 2 end,
    }}}
    C_TradeSkillUI = {GetRecipeSchematic=function(id,recraft,level)
        eq(id,900); eq(recraft,false); readLevel = level; return schematic
    end}
end

test("missing profession selection and API failures preserve the editor draft", function()
    A.Editor.Open(A.Selected()); A.Editor.name:SetText("保留草稿")
    A.Editor.import:Click(); assert(A.Editor.error:GetText():find("专业窗口")); eq(A.Editor.name:GetText(),"保留草稿")
    enableRecipeAPI(); C_TradeSkillUI.GetRecipeSchematic = nil
    A.Editor.import:Click(); assert(A.Editor.error:GetText():find("接口")); eq(A.Editor.name:GetText(),"保留草稿")
    C_TradeSkillUI.GetRecipeSchematic = function() error("not loaded") end
    A.Editor.import:Click(); assert(A.Editor.error:GetText():find("载入")); eq(A.Editor.name:GetText(),"保留草稿")
    button("取消"):Click()
end)

test("read selected native recipe fills quantities and preserves fixed purchase prices", function()
    enableRecipeAPI(); A.Editor.Open(A.Selected()); A.Editor.import:Click()
    eq(readLevel,2); eq(A.Editor.error:GetText(),""); eq(A.Editor.item.itemID,1)
    eq(A.Editor.rows[1].quantity:GetText(),"2"); eq(A.Editor.rows[2].item.itemID,3)
    eq(A.Editor.rows[2].source,"fixed"); eq(A.Editor.rows[2].price:GetCopper(),200)
    eq(A.SelectedRecipe().name,"默认配方")
    button("保存配方"):Click()
    eq(A.SelectedRecipe().sourceRecipeID,900); eq(#A.Selected().recipes,1)
    eq(#MOCK.queries,1); eq(MOCK.postCalls,0)
end)

test("variable output uses its minimum and persists the visible assumption", function()
    enableRecipeAPI(); schematic.quantityMin,schematic.quantityMax = 2,4
    A.UI.productRows[1].menu:Click(); menuEntry("添加方案"):Click(); A.Editor.import:Click()
    eq(A.Editor.output:GetText(),"2"); assert(A.Editor.sourceNote:GetText():find("按最低产量"))
    A.Editor.name:SetText("保守产量"); button("保存配方"):Click()
    eq(A.SelectedRecipe().output,2); eq(A.SelectedRecipe().sourceOutputMax,4)
    assert(A.UI.productRows[1].help:find("按最低产量"))
    A.Editor.Open(A.Selected()); A.Editor.output:SetText("3")
    assert(A.Editor.sourceNote:GetText():find("自填产量")); button("取消"):Click()
end)

test("ambiguous or incomplete recipes cannot silently omit costs", function()
    enableRecipeAPI(); A.Editor.Open(A.Selected()); local before = A.Editor.name:GetText()
    schematic.reagentSlotSchematics[2].reagentType = 0
    A.Editor.import:Click(); assert(A.Editor.error:GetText():find("可选材料"))
    schematic = recipeFixture(); schematic.reagentSlotSchematics[1].reagents[2] = {itemID=4}
    eq(A.Native.ReadRecipe(),nil)
    schematic = recipeFixture(); schematic.reagentSlotSchematics[1].reagents = {{currencyID=1}}
    eq(A.Native.ReadRecipe(),nil)
    schematic = recipeFixture(); schematic.quantityMin = nil; eq(A.Native.ReadRecipe(),nil)
    schematic = recipeFixture(); schematic.outputItemID = 4
    A.Editor.import:Click(); assert(A.Editor.error:GetText():find("成品与当前产品不同"))
    eq(A.Editor.name:GetText(),before); eq(A.Editor.item.itemID,1)
    schematic = recipeFixture(); selectedRecipe.supportsQualities = true; eq(A.Native.ReadRecipe(),nil)
    button("取消"):Click()
end)

test("menu stays open during age updates and browsing alternatives never queries", function()
    local before = #MOCK.queries
    A.UI.productRows[1].menu:Click()
    local menu = MOCK.menu
    MOCK.time = MOCK.time + 1
    for _, tick in ipairs(MOCK.tickers) do for _ = 1, 4 do tick() end end
    eq(MOCK.menu,menu); eq(#MOCK.queries,before)
    eq(menuEntry("保守产量").selected(),true)
    menuEntry(A.Selected().recipes[1].name):Click()
    eq(A.SelectedRecipe().id,1); eq(#MOCK.queries,before)
    eq(A.UI.materialRows[1].itemID,2); eq(A.UI.productLink.itemID,1)
    eq(A.UI.productRows[1].selected:IsShown(),true)
end)

test("global refresh covers every recipe and prevents duplicate queued work", function()
    local refreshes = 0
    for _, frame in ipairs(MOCK.frames) do
        if frame.kind == "Button" and frame:IsVisible() and frame.text == "全部刷新" then refreshes = refreshes + 1 end
    end
    eq(refreshes,1)
    A.UI.refresh:Click(); eq(table.concat(A.Market.queue,","),"1,2,3")
    eq(A.UI.refresh:IsEnabled(),false)
    A.UI.refresh:Click(); eq(table.concat(A.Market.queue,","),"1,2,3")
    A.Market.Pause(); A.RefreshUI(); eq(A.UI.refresh:IsEnabled(),true)
end)

test("visible product recipe and material refresh icons target the requested scope", function()
    local row, selection = A.UI.productRows[1], A.SelectedRecipe().id
    eq(row.refresh:IsVisible(),true); eq(A.UI.recipeRefresh:IsVisible(),true)
    row.refresh:Click(); eq(table.concat(A.Market.queue,","),"1,2,3")
    eq(A.SelectedRecipe().id,selection); eq(row.refresh:IsEnabled(),false)
    eq(A.UI.recipeRefresh:IsEnabled(),false); eq(A.UI.materialRows[1].refresh:IsEnabled(),false)
    A.Market.Pause(); A.RefreshUI()
    A.UI.recipeRefresh:Click(); eq(table.concat(A.Market.queue,","),"1,2")
    A.Market.Pause(); A.RefreshUI()
    local previousResult = AuctionHouseFrame.buyResult
    A.UI.materialRows[1].refresh:Click(); eq(table.concat(A.Market.queue,","),"2")
    eq(AuctionHouseFrame.buyResult,previousResult); eq(A.UI.frame:IsShown(),true)
    A.Market.Pause(); A.RefreshUI()
    local fixedPrice = A.SelectedRecipe().materials[2].price
    A.UI.materialRows[2].refresh:Click(); eq(table.concat(A.Market.queue,","),"3")
    A.Market.Pause(); A.AcceptQuote(3,A.Logic.Snapshot({{price=550,quantity=10}},MOCK.time,true))
    eq(A.SelectedRecipe().materials[2].price,fixedPrice)
    assert(A.UI.materialRows[2].help:find("5银50铜")); eq(A.UI.materialRows[2].unit:GetText(),"2银")
end)

test("material and finished-product clicks open their exact native buy page without purchasing", function()
    local before = #MOCK.queries
    A.Market.queue = {1,2}; A.Market.active = {itemID = 1, key = {itemID=1}, started = MOCK.time}
    A.UI.materialRows[1]:Click(); MOCK.flush()
    eq(AuctionHouseFrame.buyResult.itemKey.itemID,2)
    eq(AuctionHouseFrame:GetDisplayMode(),AuctionHouseFrameDisplayMode.CommoditiesBuy)
    eq(A.Market.active,nil); eq(#A.Market.queue,0); eq(A.UI.frame:IsShown(),false)
    eq(A.profile.selectedID,1); eq(A.SelectedRecipe().id,1)
    A.Native.ShowMonitor(); MOCK.flush(); A.UI.productLink:Click(); MOCK.flush()
    eq(AuctionHouseFrame.buyResult.itemKey.itemID,1)
    eq(#MOCK.queries,before); eq(MOCK.purchaseCalls or 0,0); eq(MOCK.postCalls,0)
    A.Native.ShowMonitor(); MOCK.flush()
    MOCK.keyInfo = {isCommodity = false}
    A.UI.materialRows[2]:Click(); MOCK.flush()
    eq(AuctionHouseFrame.buyResult.itemKey.itemID,3)
    eq(AuctionHouseFrame:GetDisplayMode(),AuctionHouseFrameDisplayMode.ItemBuy)
    eq(MOCK.purchaseCalls or 0,0)
    MOCK.keyInfo = nil; A.Native.ShowMonitor(); MOCK.flush()
end)

test("unavailable purchase targets preserve the monitor and never send transactions", function()
    local before, result = #MOCK.nativeQueries, AuctionHouseFrame.buyResult
    A.Market.queue = {1,2}
    MOCK.ready = false; A.UI.productLink:Click()
    assert(A.UI.message:GetText():find("正忙")); eq(#A.Market.queue,2)
    MOCK.ready = true
    eq(A.Native.OpenBuy("not-an-item"),nil)
    MOCK.keyInfo = false; eq(A.Native.OpenBuy(1),nil)
    MOCK.keyInfo = {isEquipment = true}; eq(A.Native.OpenBuy(1),nil)
    MOCK.keyInfo = {isPet = true}; eq(A.Native.OpenBuy(1),nil)
    MOCK.keyInfo = nil
    MOCK.combat = true; eq(A.Native.OpenBuy(1),nil); MOCK.combat = false
    A.open = false; eq(A.Native.OpenBuy(1),nil); A.open = true
    eq(#MOCK.nativeQueries,before); eq(AuctionHouseFrame.buyResult,result)
    eq(A.UI.frame:IsShown(),true); eq(#A.Market.queue,2)
    A.Market.Pause()
    MOCK.rejectBuy = true; A.UI.productLink:Click(); MOCK.rejectBuy = false
    assert(A.UI.message:GetText():find("未能打开")); eq(A.UI.frame:IsShown(),true)
    eq(MOCK.purchaseCalls or 0,0); eq(MOCK.postCalls,0)
end)

test("sorting selection and reused detail rows remain attached to the correct product", function()
    local p = A.Selected()
    assert(A.SaveProduct({itemID=4, recipeName="铜锭配方", output=1, fee=5, extra=0, alert=true,
        materials={{itemID=3,quantity=1,source="fixed",price=1000}}}))
    A.AcceptQuote(1,A.Logic.Snapshot({{price=10000,quantity=100}},MOCK.time,true))
    A.AcceptQuote(2,A.Logic.Snapshot({{price=4200,quantity=100}},MOCK.time,true))
    A.AcceptQuote(4,A.Logic.Snapshot({{price=5000,quantity=100}},MOCK.time,true))
    A.UI.sortButtons.unitProfit:Click()
    eq(A.UI.productRows[2].points[1][5],0)
    eq(A.UI.productRows[1].points[1][5],-44)
    eq(A.UI.materialRows[1].itemID,3); eq(A.UI.materialRows[2]:IsShown(),false)
    eq(A.UI.productLink.itemID,4)
    A.UI.materialRows[1]:Click(); eq(AuctionHouseFrame.buyResult.itemKey.itemID,3)
    A.Native.ShowMonitor(); MOCK.flush(); A.UI.productLink:Click()
    eq(AuctionHouseFrame.buyResult.itemKey.itemID,4)
    A.Native.ShowMonitor(); MOCK.flush(); A.UI.productRows[1]:Click()
    eq(A.Selected().id,p.id); eq(A.UI.materialRows[1].itemID,2)
    eq(A.UI.materialRows[2]:IsShown(),true); eq(A.UI.productLink.itemID,1)
    A.DeleteProduct(2); eq(A.UI.productRows[2]:IsShown(),false)
    eq(A.SelectedRecipe().id,1)
end)

test("long localized names stay on one line and keep full text in item help", function()
    local product, recipe = A.Selected(), A.SelectedRecipe()
    local oldName, oldItem = recipe.name, MOCK.items[1]
    recipe.name = "用于比较黄铁矿采购成本的另一套专业生产配方"
    MOCK.items[1] = "需要测试显示宽度的很长的中文成品名称"
    A.RefreshUI()
    local row = A.UI.productRows[1]
    for _, label in ipairs({row.name, row.recipe, A.UI.productLink.name, A.UI.recipeTitle}) do
        eq(label.wordWrap,false); assert(label:GetUnboundedStringWidth() <= label:GetWidth())
        assert(not label:GetText():find("\n")); assert(not label:GetText():find("…"))
    end
    assert(row.help:find(recipe.name,1,true)); assert(row.help:find(MOCK.items[1],1,true))
    eq(A.UI.productLink.itemID,product.itemID); eq(A.UI.materialRows[1].itemID,2)
    recipe.name, MOCK.items[1] = oldName, oldItem; A.RefreshUI()
end)

test("deletion confirmation targets the specific saved record", function()
    A.Native.ShowMonitor(); MOCK.flush(); A.UI.productRows[1].menu:Click(); menuEntry("移除产品"):Click()
    eq(#A.profile.products, 1)
    local popup = MOCK.popup
    StaticPopupDialogs[popup.which].OnAccept(nil, popup.data)
    eq(#A.profile.products, 0); eq(A.Selected(), nil); eq(MOCK.postCalls, 0)
    eq(A.UI.empty:IsShown(),true); eq(A.UI.productLink:IsShown(),false)
    eq(A.UI.detailMenu:IsEnabled(),false); eq(A.UI.recipeRefresh:IsEnabled(),false)
end)

test("shift item links fill only the focused visible unlocked item field", function()
    A.Editor.Open(); A.Editor.item.edit:SetFocus(); MOCK.shift = true
    eq(ChatFrameUtil.InsertLink("|Hitem:1:0|h[硫酸]|h"),true); eq(A.Editor.item.itemID,1)
    eq(MOCK.normalLinks or 0,0)
    A.Editor.rows[1].item.edit:SetFocus()
    eq(ChatFrameUtil.InsertLink("|Hitem:2:0|h[黄铁矿]|h"),true)
    eq(A.Editor.rows[1].item.itemID,2); eq(A.Editor.item.itemID,1)
    A.Editor.rows[1].item.edit:SetFocus(); MOCK.shift = false
    local result, link = ChatFrameUtil.InsertLink("item:4")
    eq(result,"native"); eq(link,"item:4"); eq(A.Editor.rows[1].item.itemID,2)
    MOCK.shift = true; A.Editor.item:SetEnabled(false); A.Editor.item.edit:SetFocus()
    eq(ChatFrameUtil.InsertLink("item:4"),"native"); eq(A.Editor.item.itemID,1)
    A.Editor.item:SetEnabled(true); A.Editor.item.edit:SetFocus()
    eq(ChatFrameUtil.InsertLink("|Hspell:1|h[Spell]|h"),"native")
    A.Editor.Close(); eq(ChatFrameUtil.InsertLink("item:4"),"native"); eq(A.Editor.item.itemID,1)
    A.Editor.item.edit:ClearFocus(); MOCK.shift = false
end)

test("docked frame matches AH bounds and scales its content inside them", function()
    A.Native.ShowMonitor(); MOCK.flush()
    local frame, canvas = A.UI.frame, A.UI.canvas
    for _, size in ipairs({{800,538},{850,600},{1000,650}}) do
        AuctionHouseFrame:SetSize(size[1],size[2]); A.Native.Attach()
        eq(frame:GetParent(),AuctionHouseFrame); eq(frame:GetScale(),1)
        eq(frame.movable,false); eq(frame.clamped,false)
        eq(frame:GetWidth(),size[1]-12); eq(frame:GetHeight(),size[2]-60)
        eq(#frame.points,1); eq(frame.points[1][1],"TOPLEFT"); eq(frame.points[1][2],AuctionHouseFrame)
        eq(frame.points[1][4],6); eq(frame.points[1][5],-32); eq(A.UI.header:IsShown(),false)
        assert(canvas:GetWidth()*canvas:GetScale() <= frame:GetWidth()+0.01)
        assert(canvas:GetHeight()*canvas:GetScale() <= frame:GetHeight()+0.01)
        A.Editor.Open(); eq(frame:GetWidth(),size[1]-12); A.Editor.Close()
    end
    A.Native.Navigate("buy"); eq(AuctionHouseFrame:GetWidth(),1000); eq(A.UI.frame:IsShown(),false)
end)

test("offline reopening restores standalone size and screen anchor", function()
    event("AUCTION_HOUSE_CLOSED"); SlashCmdList.AUCTIONPILOT()
    eq(A.UI.frame:GetParent(),UIParent); eq(A.UI.frame:GetWidth(),1120); eq(A.UI.frame:GetHeight(),720)
    eq(A.UI.frame.points[1][1],"CENTER"); eq(A.UI.frame.points[1][2],UIParent)
    eq(A.UI.canvas:GetScale(),1)
    eq(A.UI.frame.movable,true); eq(A.UI.frame.clamped,true)
    UIParent:SetSize(1024,768); A.UI.Layout()
    assert(A.UI.frame:GetWidth()*A.UI.frame:GetScale() <= 1024-36)
    assert(A.UI.frame:GetHeight()*A.UI.frame:GetScale() <= 768-36)
    UIParent:SetSize(1600,1000); A.UI.Layout()
end)

local function observe(at, rows, complete)
    MOCK.time = at
    MOCK.serverTime = 1794450000 + at
    A.AcceptQuote(1,A.Logic.Snapshot(rows,at,complete ~= false))
    return A.quotes[1]
end
local function stock(price, quantity) return {{price=price,quantity=quantity}} end

test("manual prices show their collection timestamp without refreshing material age", function()
    assert(A.SaveProduct({itemID=1,recipeName="价格记录测试",output=1,fee=5,extra=0,
        materials={{itemID=2,quantity=1,source="market"}}}))
    event("AUCTION_HOUSE_SHOW"); MOCK.flush(); A.Native.ShowMonitor(); MOCK.flush()
    eq(A.Market.auto,false); eq(A.UI.auto:GetText(),"自动刷新：关")
    local history = A.profile.priceHistory; local before = history.next
    MOCK.time = 1000; A.AcceptQuote(2,A.Logic.Snapshot(stock(500,100),MOCK.time,true))
    eq(history.next,before)
    observe(1000,stock(1150,100))
    local q = observe(1030,{{price=1145,quantity=50},{price=1150,quantity=50},{price=1200,quantity=999}})
    eq(history.next,before+2); eq(history.samples[before+1][3],1145)
    local row = A.UI.productRows[A.Selected().id]
    eq(row.activity,nil); eq(row.priceTime:GetText(),date("%m-%d %H:%M",q.seenAt))
    assert(row.help:find(date("%Y-%m-%d %H:%M:%S",q.seenAt),1,true))
    assert(not row.help:find("波动",1,true)); eq(A.quotes[2].at,1000)
    observe(1060,stock(1145,100)); observe(1090,stock(1145,100)); observe(1121,stock(1145,100))
    eq(A.Estimate(A.Selected()).stale,true); eq(A.quotes[2].at,1000)
end)

local book = stock(100,40)
local full = true
C_AuctionHouse.HasFullCommoditySearchResults = function() return full end
C_AuctionHouse.GetNumCommoditySearchResults = function() return #book end
C_AuctionHouse.GetCommoditySearchResultInfo = function(_, index)
    local row = book[index]
    if row then return {unitPrice=row.price,quantity=row.quantity} end
end
C_AuctionHouse.RequestMoreCommoditySearchResults = function() return false end

test("auto pauses for editor and native tabs and resumes price recording on return", function()
    local M = A.Market
    local history = A.profile.priceHistory; local before = history.next
    MOCK.time = 5200; A.UI.auto:Click(); eq(M.auto,true); eq(M.active.itemID,1)
    M.OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED",1); eq(history.next,before+1)
    MOCK.time = 5230; M.Tick(); book = stock(100,20); M.OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED",1)
    eq(history.next,before+2)
    A.Editor.Open(A.Selected()); eq(M.active,nil); eq(#M.queue,0); eq(M.auto,true)
    local count = #MOCK.queries
    MOCK.time = 5300; M.Tick(); eq(#MOCK.queries,count)
    eq(M.RequestItem(2),nil)
    A.Editor.Close(); M.Tick(); eq(M.active.itemID,1)
    book = stock(100,5); M.OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED",1)
    eq(history.next,before+3)
    A.Native.Navigate("buy"); eq(M.auto,true)
    MOCK.time = 5400; M.Tick(); eq(M.active,nil)
    A.Native.ShowMonitor(); MOCK.flush(); M.Tick(); eq(M.active.itemID,1)
    M.OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED",1); eq(history.next,before+4)
    eq(MOCK.postCalls,0); eq(MOCK.purchaseCalls or 0,0)
    M.SetAuto(false)
end)

test("incomplete pages and timeout retain the last recorded price and timestamp", function()
    local M = A.Market
    observe(6000,stock(100,100)); observe(6030,stock(100,80))
    local history = A.profile.priceHistory; local before = history.next
    local saved = A.profile.lastSeenPrices[1]
    full = false; MOCK.time = 6060; assert(M.RequestItem(1)); M.Tick()
    M.OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED",1)
    eq(history.next,before); eq(A.quotes[1].at,6030)
    MOCK.time = 6086; M.Tick(); eq(M.active,nil)
    eq(history.next,before); eq(A.profile.lastSeenPrices[1],saved)
    full = true; observe(6100,stock(100,2)); eq(history.next,before+1)
    M.Pause() -- Cancel the deferred retry before the next independent scenario.
end)

test("turning auto off cancels its round and late events cannot update prices", function()
    local M = A.Market
    MOCK.time = 6200; assert(M.SetAuto(true)); local before = A.quotes[1]
    assert(M.SetAuto(false)); eq(M.active,nil); eq(#M.queue,0)
    M.OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED",1); eq(A.quotes[1],before)
    local count = #MOCK.queries
    MOCK.time = 6300; M.Tick(); eq(#MOCK.queries,count)
    assert(M.RequestItem(1)); M.Tick(); eq(M.active.itemID,1)
    M.SetAuto(false); eq(M.active.itemID,1) -- Disabling the timer never cancels a manual query.
    M.OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED",1)
end)

test("rapid resume drains the cancelled request before sending the same item again", function()
    local M = A.Market
    MOCK.time = 6500; assert(M.SetAuto(true)); eq(M.active.itemID,1)
    MOCK.time = 6501; M.SetAuto(false)
    local count = #MOCK.queries
    MOCK.time = 6502; assert(M.SetAuto(true)); eq(#MOCK.queries,count)
    local before = A.quotes[1]
    local history = A.profile.priceHistory; local nextSample = history.next
    book = stock(100,100); M.OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED",1)
    eq(A.quotes[1],before); eq(M.active,nil)
    eq(history.next,nextSample)
    MOCK.time = 6504; M.Tick(); eq(#MOCK.queries,count+1); eq(M.active.itemID,1)
    book = stock(100,40); M.OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED",1)
    eq(A.quotes[1].levels[1].quantity,40); eq(history.next,nextSample+1)
    M.SetAuto(false)
end)

test("cancelled partial queries expire without publishing or blocking the next session", function()
    local M = A.Market
    MOCK.time = 6600; assert(M.SetAuto(true)); full = false
    M.OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED",1)
    A.Native.Navigate("buy"); local before, count = A.quotes[1], #MOCK.queries
    MOCK.time = 6605; M.OnEvent("COMMODITY_SEARCH_RESULTS_ADDED",1); M.Tick()
    eq(A.quotes[1],before); eq(#MOCK.queries,count); assert(M.draining)
    MOCK.time = 6626; M.Tick(); eq(M.draining,nil); eq(#MOCK.queries,count)
    full = true; A.Native.ShowMonitor(); MOCK.flush(); M.Tick(); eq(M.active.itemID,1)
    M.OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED",1); eq(A.quotes[1].complete,true)
    M.SetAuto(false)
end)

test("stale prices retain readable dates and a full timestamp in the tooltip", function()
    observe(7000,stock(100,1000000000))
    local q = observe(7030,stock(99,1000000000))
    local row = A.UI.productRows[A.Selected().id]
    eq(row.priceTime:GetText(),date("%m-%d %H:%M",q.seenAt))
    assert(row.help:find("采样最低单价：99铜",1,true))
    MOCK.time = 7160; A.RefreshUI(); assert(row.priceTime:GetText():find("历史",1,true))
    assert(row.help:find(date("%Y-%m-%d %H:%M:%S",q.seenAt),1,true))
end)

test("a native observation cannot relabel the timestamp of the displayed monitor quote", function()
    local row = A.UI.productRows[A.Selected().id]
    local seenAt = A.quotes[1].seenAt; local nextSample = A.profile.priceHistory.next
    MOCK.serverTime = MOCK.serverTime + 300; book = stock(1,10)
    A.History.OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED",1); A.RefreshUI()
    eq(A.profile.lastSeenPrices[1].seenAt,MOCK.serverTime)
    eq(A.profile.priceHistory.next,nextSample); eq(A.quotes[1].seenAt,seenAt)
    assert(row.help:find(date("%Y-%m-%d %H:%M:%S",seenAt),1,true))
    assert(row.help:find("采样最低单价：99铜",1,true))
end)

test("invalid saved price metadata cannot break the timestamp column", function()
    local row = A.UI.productRows[A.Selected().id]
    local saved, quotes = A.profile.lastSeenPrices, A.quotes
    A.profile.lastSeenPrices = "preserved"; A.quotes = {}; A.RefreshUI()
    eq(row.priceTime:GetText(),"待采样"); eq(A.profile.lastSeenPrices,"preserved")
    A.profile.lastSeenPrices = {[1]={price=1,seenAt="invalid",priceVersion=2}}; A.RefreshUI()
    eq(row.priceTime:GetText(),"待采样")
    A.profile.lastSeenPrices, A.quotes = saved, quotes; A.RefreshUI()
end)

test("AH close preserves price history and never persists auto mode", function()
    local M = A.Market
    local history = A.profile.priceHistory; local nextSample = history.next
    assert(M.SetAuto(true)); event("AUCTION_HOUSE_CLOSED")
    eq(M.auto,false); eq(M.active,nil); eq(#M.queue,0); eq(history.next,nextSample)
    eq(A.profile.auto,nil)
    event("AUCTION_HOUSE_SHOW"); MOCK.flush(); A.Native.ShowMonitor(); MOCK.flush()
    local count = #MOCK.queries; MOCK.time = 7300; M.Tick(); eq(#MOCK.queries,count)
    observe(7330,stock(100,20)); eq(history.next,nextSample+1)
    A.DeleteProduct(A.Selected().id); eq(history.next,nextSample+1)
end)

local function resetProfitFixture()
    local M = A.Market
    M.Pause(); M.draining, M.auto, M.nextSend, M.discardUntil = nil, false, 0, {}
    A.profile = {products={},nextID=1,vendorPrices={}}; A.quotes = {}
    AuctionPilotDB = {version=2,profiles={["TestRealm:TestCharacter"]=A.profile}}
    MOCK.time, MOCK.serverTime = 10000, 1794460000
    A.History.Initialize(); event("AUCTION_HOUSE_SHOW"); MOCK.flush()
    A.Native.ShowMonitor(); MOCK.flush(); full = true
    assert(A.SaveProduct({itemID=1,recipeName="历史利润",output=1,fee=5,extra=0,
        materials={{itemID=2,quantity=2,source="auction"}}}))
    A.AcceptQuote(2,A.Logic.Snapshot(stock(400,200),MOCK.time,true))
    A.AcceptQuote(1,A.Logic.Snapshot(stock(1200,100),MOCK.time,true))
    A.UI.priceEdited = false; A.UI.price:SetCopper(1200)
    return M, A.profile.priceHistory
end

test("a failed refresh keeps the last profit without renewing its age or making it a live price", function()
    local M, history = resetProfitFixture()
    local before, sale, nextSample = A.Estimate(A.Selected()), A.quotes[1], history.next
    assert(M.RequestItem(1)); M.Tick(); MOCK.time = MOCK.time+26; M.Tick()
    eq(A.quotes[1],sale); eq(sale.at,10000); eq(sale.seenAt,1794460000)
    local result = A.Estimate(A.Selected())
    eq(result.roi,before.roi); eq(result.stale,true); assert(result.refreshError)
    eq(history.next,nextSample); eq(A.UI.usePrice:IsEnabled(),false); eq(A.UI.price:GetCopper(),nil)
    assert(A.UI.productRows[1].help:find("沿用上次完整报价",1,true))
    eq(A.UI.productRows[1].age:GetText(),"刷新失败")
    eq(M.RequestItem(1),nil) -- The failed attempt already has one deferred retry.
    book = stock(1400,100); MOCK.time = MOCK.time+25; M.Tick(); eq(M.active.itemID,1)
    MOCK.serverTime = MOCK.serverTime+30; M.OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED",1)
    result = A.Estimate(A.Selected())
    assert(result.roi>before.roi); eq(result.stale,false); eq(result.refreshError,nil)
    eq(A.quotes[1].seenAt,1794460030); eq(history.next,nextSample+1)
    eq(A.UI.usePrice:IsEnabled(),true); eq(A.UI.price:GetCopper(),1400)
end)

test("a successful empty market replaces the old price instead of retaining a fabricated profit", function()
    local M, history = resetProfitFixture()
    local nextSample = history.next
    book = {}; assert(M.RequestItem(1)); M.Tick(); M.OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED",1)
    eq(A.Estimate(A.Selected()).unitProfit,nil); eq(history.samples[nextSample][3],false)
    eq(#A.quotes[1].levels,0)
    MOCK.time = MOCK.time+2; assert(M.RequestItem(1)); M.Tick(); MOCK.time = MOCK.time+26; M.Tick()
    eq(A.Estimate(A.Selected()).unitProfit,nil); eq(history.next,nextSample+1)
end)

test("failure without a complete session quote never restores a profit from saved price history", function()
    local M = resetProfitFixture()
    A.quotes[1] = nil
    assert(M.RequestItem(1)); M.Tick(); MOCK.time = MOCK.time+26; M.Tick()
    eq(A.Estimate(A.Selected()).unitProfit,nil); eq(A.quotes[1].complete,false)
    assert(A.quotes[1].error); assert(A.profile.lastSeenPrices[1].price)
end)

test("recipe edits recalculate retained prices and release session quotes no longer referenced", function()
    resetProfitFixture()
    local original = A.Estimate(A.Selected()).roi
    A.AcceptQuote(3,A.Logic.Snapshot(stock(500,100),MOCK.time,true))
    event("AUCTION_HOUSE_CLOSED"); event("AUCTION_HOUSE_SHOW"); MOCK.flush()
    assert(A.SaveProduct({id=1,itemID=1,recipeID=1,recipeName="历史利润",output=1,fee=5,extra=0,
        materials={{itemID=2,quantity=3,source="auction"}}}))
    local result = A.Estimate(A.Selected())
    assert(result.roi<original); eq(result.stale,true); eq(A.quotes[3],nil)
    assert(A.quotes[1] and A.quotes[2]); assert(A.profile.lastSeenPrices[3])
    A.DeleteProduct(1); eq(next(A.quotes),nil)
    eq(A.profile.quotes,nil); assert(A.profile.priceHistory.next>1)
end)

test("late success and failure cannot restore session quotes after the last reference is deleted", function()
    for _, timeout in ipairs({false,true}) do
        local M, history = resetProfitFixture()
        local nextSample = history.next
        assert(M.RequestItem(1)); M.Tick(); eq(M.active.itemID,1)
        A.DeleteProduct(1); eq(next(A.quotes),nil)
        if timeout then MOCK.time = MOCK.time+26; M.Tick()
        else book = stock(1300,100); M.OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED",1) end
        eq(next(A.quotes),nil); eq(history.next,nextSample)
        event("AUCTION_HOUSE_CLOSED"); event("AUCTION_HOUSE_SHOW"); MOCK.flush()
        eq(next(A.quotes),nil)
    end
    local M, history = resetProfitFixture()
    assert(A.SaveProduct({itemID=4,recipeName="共享材料",output=1,fee=5,extra=0,
        materials={{itemID=1,quantity=1,source="auction"}}}))
    local nextSample = history.next
    assert(M.RequestItem(1)); M.Tick(); A.DeleteProduct(1)
    book = stock(1300,100); M.OnEvent("COMMODITY_SEARCH_RESULTS_UPDATED",1)
    eq(A.quotes[1].levels[1].price,1300); eq(history.next,nextSample)
end)

test("throttle status and progress remain visible and the refresh button unlocks at the deadline", function()
    local M, history = resetProfitFixture()
    local before, sale, last = history.next, A.quotes[1], A.profile.lastSeenPrices[1]
    MOCK.ready = false; A.UI.refresh:Click(); M.Tick(); A.RefreshUI()
    eq(A.UI.refresh:IsEnabled(),false); assert(A.UI.status:GetText():find("限流"))
    assert(A.UI.status:GetText():find("完成 0 · 失败 0 · 待查 2",1,true))
    MOCK.time = MOCK.time+30; M.Tick()
    eq(A.UI.refresh:IsEnabled(),true); eq(A.UI.refresh:GetText(),"全部刷新")
    assert(A.UI.status:GetText():find("本轮已停止")); eq(M.active,nil); eq(#M.queue,0)
    eq(A.quotes[1],sale); eq(history.next,before); eq(A.profile.lastSeenPrices[1],last)
    eq(A.profile.batch,nil); eq(A.profile.discardUntil,nil)
    MOCK.ready = true; A.UI.refresh:Click(); M.Tick(); eq(M.active.itemID,1)
end)

test("late failed responses cannot leak into passive prices while later items complete", function()
    local M, history = resetProfitFixture()
    local before, sale, last = history.next, A.quotes[1], A.profile.lastSeenPrices[1]
    A.UI.refresh:Click(); M.Tick(); MOCK.time = MOCK.time+26; M.Tick()
    eq(M.active.itemID,2)
    book = stock(9999,100); event("COMMODITY_SEARCH_RESULTS_UPDATED",1)
    eq(A.quotes[1],sale); eq(A.profile.lastSeenPrices[1],last); eq(history.next,before)
    book = stock(500,100); event("COMMODITY_SEARCH_RESULTS_UPDATED",2)
    eq(M.batch.completed,1); eq(M.batch.failed,0); eq(A.quotes[2].levels[1].price,500)
    A.RefreshUI(); assert(A.UI.status:GetText():find("完成 1 · 失败 0 · 待查 1",1,true))
    assert(A.UI.status:GetText():find("重试 · 25秒",1,true)); eq(A.UI.refresh:IsEnabled(),false)
    MOCK.time = MOCK.time+25; M.Tick(); A.RefreshUI()
    eq(M.active.itemID,1); assert(A.UI.status:GetText():find("重试1/1",1,true))
    book = stock(1400,100); event("COMMODITY_SEARCH_RESULTS_UPDATED",1)
    eq(history.next,before+1); eq(A.quotes[1].levels[1].price,1400)
    assert(A.UI.status:GetText():find("完成 2 · 失败 0 · 待查 0",1,true))
    eq(A.UI.refresh:IsEnabled(),true)
end)

test("leaving the monitor cancels retries and still ignores the failed attempt's late result", function()
    local M, history = resetProfitFixture()
    local last, before = A.profile.lastSeenPrices[1], history.next
    assert(M.RequestItem(1)); M.Tick(); MOCK.time = MOCK.time+26; M.Tick()
    local queries = #MOCK.queries
    A.Native.Navigate("buy"); eq(#M.queue,0); eq(M.batch,nil)
    book = stock(9999,100); event("COMMODITY_SEARCH_RESULTS_UPDATED",1)
    eq(A.profile.lastSeenPrices[1],last); eq(history.next,before)
    MOCK.time = MOCK.time+60; M.Tick(); eq(#MOCK.queries,queries)
    A.Native.ShowMonitor(); MOCK.flush(); M.Tick(); eq(#MOCK.queries,queries)
end)

local function scanFixture(recipeID, itemID)
    if ProfessionsFrame and ProfessionsFrame.Hide then ProfessionsFrame:Hide() end
    enableRecipeAPI()
    selectedRecipe.recipeID, schematic.recipeID = recipeID or 900, recipeID or 900
    schematic.outputItemID = itemID or 1
    MOCK.Profession({[selectedRecipe.recipeID]={info=selectedRecipe,schematic=schematic}},selectedRecipe.recipeID)
    event("TRADE_SKILL_SHOW")
    A.open = true; A.Native.pendingPost = nil
    A.Market.Pause(); A.Market.auto = false; A.Market.draining = nil
    A.Market.discardUntil = {}; A.Market.nextSend = 0
    MOCK.ready = true; MOCK.keyInfo = nil
end

local function completeScan(prices)
    local function rows(id)
        if type(prices[id]) == "table" then return prices[id] end
        return prices[id] and {{unitPrice=prices[id],quantity=100,numOwnerItems=0}} or {}
    end
    C_AuctionHouse.HasFullCommoditySearchResults = function() return true end
    C_AuctionHouse.GetNumCommoditySearchResults = function(id) return #rows(id) end
    C_AuctionHouse.GetCommoditySearchResultInfo = function(id,index) return rows(id)[index] end
    local M = A.Market
    for _ = 1, 20 do
        MOCK.time = MOCK.time+2; M.Tick()
        if M.active then event("COMMODITY_SEARCH_RESULTS_UPDATED",M.active.itemID) end
        if not M.active and #M.queue == 0 then break end
    end
    eq(M.active,nil); eq(#M.queue,0)
end

test("profession scan reads the selected recipe and never saves a watch entry", function()
    while #A.profile.products > 0 do A.DeleteProduct(A.profile.products[1].id) end
    scanFixture()
    local before = A.profile.nextID
    assert(A.UI.ScanProfession())
    eq(table.concat(A.Market.queue,","),"1,2,3")
    completeScan({[1]=10000,[2]=2000,[3]=100})
    eq(A.scanResults[900].estimate.unitProfit,5400)
    eq(A.profile.nextID,before); eq(#A.profile.products,0)
    eq(A.profile.scanResults,nil); eq(MOCK.postCalls,0)
end)

test("scanned recipes keep frozen independent results across page and auction closure", function()
    local first = A.scanResults[900]
    scanFixture(901,4); assert(A.UI.ScanProfession())
    selectedRecipe.recipeID = 999 -- Selection changes cannot relabel a batch in flight.
    completeScan({[4]=20000,[2]=3000,[3]=100})
    eq(A.scanResults[900],first); eq(first.estimate.unitProfit,5400)
    eq(A.scanResults[901].draft.itemID,4); eq(A.scanResults[999],nil)
    ProfessionsFrame:Hide(); event("AUCTION_HOUSE_CLOSED")
    eq(A.scanResults[900],first); eq(A.scanResults[901].estimate.unitProfit,12900)
    event("AUCTION_HOUSE_SHOW"); MOCK.flush(); ProfessionsFrame:Show(); A.UI.RefreshProfessionScan()
    eq(A.scanResults[900],first); eq(first.estimate.unitProfit,5400)
    selectedRecipe.recipeID=901; A.UI.RefreshProfessionScan(); eq(A.UI.profession.sale:GetText(),A.Logic.Money(A.scanResults[901].estimate.sale))
end)

test("a cancelled rescan preserves the old result and its original quote time", function()
    local old = A.scanResults[900]
    scanFixture(); assert(A.UI.ScanProfession()); A.Market.Tick()
    ProfessionsFrame:Hide()
    eq(A.Market.active,nil); eq(#A.Market.queue,0)
    eq(A.scanResults[900],old); assert(old.refreshError:find("中断"))
    local at = old.at
    event("COMMODITY_SEARCH_RESULTS_UPDATED",1)
    eq(A.scanResults[900].at,at); eq(old.estimate.unitProfit,5400)
end)

test("complete empty or insufficient markets replace old profit with an unknown result", function()
    scanFixture(); assert(A.UI.ScanProfession())
    completeScan({[2]=2000,[3]=100})
    eq(A.scanResults[900].estimate.unitProfit,nil); assert(A.scanResults[900].estimate.error)
    scanFixture(); assert(A.UI.ScanProfession())
    completeScan({[1]=10000,[2]=2000,[3]=100})
    eq(A.scanResults[900].estimate.unitProfit,5400)
end)

test("adding a scan reuses existing watches without overwriting their configuration", function()
    assert(A.AddRecipeScan(900)); eq(#A.profile.products,1)
    local product = A.Selected(); local recipe = A.SelectedRecipe()
    eq(recipe.sourceRecipeID,900); eq(A.Estimate(product).unitProfit,5400)
    product.fee = 8; recipe.materials[1].source = "fixed"; recipe.materials[1].price = 1000
    local original = A.Logic.Copy(product)
    assert(A.AddRecipeScan(900)); eq(#A.profile.products,1); eq(#product.recipes,1)
    eq(product.fee,original.fee); eq(recipe.materials[1].price,1000)
    scanFixture(); assert(A.UI.ScanProfession())
    eq(table.concat(A.Market.queue,","),"1,3")
    completeScan({[1]=10000,[3]=100})
    eq(A.scanResults[900].estimate.unitProfit,7100)
    eq(recipe.materials[1].price,1000)
end)

test("temporary unmonitored items retry once and can recover without saving configuration", function()
    scanFixture(902,5)
    local send, attempts = C_AuctionHouse.SendSearchQuery, 0
    C_AuctionHouse.SendSearchQuery = function(key,...)
        if key.itemID == 5 then
            attempts = attempts+1
            if attempts == 1 then error("temporary failure") end
        end
        return send(key,...)
    end
    local count = #A.profile.products
    assert(A.UI.ScanProfession()); completeScan({[5]=9000,[2]=2000,[3]=100})
    C_AuctionHouse.SendSearchQuery = send
    eq(attempts,2); eq(A.scanResults[902].refreshError,nil)
    eq(A.scanResults[902].estimate.unitProfit,4450); eq(#A.profile.products,count)
end)

test("failed or throttled rescans retain an entire old result instead of mixing prices", function()
    scanFixture(902,5)
    local old = A.scanResults[902]
    local send = C_AuctionHouse.SendSearchQuery
    C_AuctionHouse.SendSearchQuery = function(key,...)
        if key.itemID == 5 then error("still unavailable") end
        return send(key,...)
    end
    assert(A.UI.ScanProfession()); completeScan({[2]=100,[3]=1})
    C_AuctionHouse.SendSearchQuery = send
    eq(A.scanResults[902],old); eq(old.estimate.unitProfit,4450); assert(old.refreshError)
    scanFixture(902,5); assert(A.UI.ScanProfession())
    MOCK.ready = false; A.Market.Tick(); MOCK.time = MOCK.time+31; A.Market.Tick()
    eq(#A.Market.queue,0); eq(A.Market.active,nil); assert(A.Market.batch.stopped)
    eq(A.scanResults[902],old); assert(old.refreshError:find("30")); eq(old.estimate.unitProfit,4450)
    MOCK.ready = true
end)

test("a missing response has bounded retries and no invented initial profit", function()
    scanFixture(904,5); assert(A.UI.ScanProfession())
    for _ = 1, 20 do A.Market.Tick(); MOCK.time = MOCK.time+26 end
    A.Market.Tick()
    eq(A.Market.active,nil); eq(#A.Market.queue,0); eq(A.Market.batch.failed,3)
    eq(A.scanResults[904].at,nil); eq(A.scanResults[904].estimate.unitProfit,nil)
    assert(A.scanResults[904].refreshError)
    for _, attempts in pairs(A.Market.batch.attempts) do eq(attempts,2) end
end)

test("scan handoff drains a monitor request and never runs auto refresh behind the scan page", function()
    scanFixture(905,5); ProfessionsFrame:Hide(); A.Native.ShowMonitor(); MOCK.flush()
    A.Market.auto = true; A.Market.Tick(); assert(A.Market.active)
    local oldItem = A.Market.active.itemID
    ProfessionsFrame:Show(); assert(A.UI.ScanProfession()); assert(A.Market.draining)
    local queries = #MOCK.queries
    A.Market.Tick(); eq(#MOCK.queries,queries)
    event("COMMODITY_SEARCH_RESULTS_UPDATED",oldItem)
    eq(A.Market.draining,nil); eq(next(A.Market.batch.scan.quotes),nil)
    completeScan({[5]=9000,[2]=2000,[3]=100})
    queries = #MOCK.queries; MOCK.time = MOCK.time+60; A.Market.Tick()
    eq(#MOCK.queries,queries)
    ProfessionsFrame:Hide(); A.Market.Tick(); assert(#MOCK.queries>queries)
    A.Market.auto = false; A.Market.Pause()
end)

test("scan costs use purchase depth exclude own stock and honor vendor prices and minimum output", function()
    scanFixture(910,5)
    schematic.quantityMin, schematic.quantityMax = 2,4
    A.profile.vendorPrices[3] = {price=50,stackCount=5,seenAt=GetServerTime()}
    assert(A.UI.ScanProfession()); eq(table.concat(A.Market.queue,","),"5,2")
    local levels = {{unitPrice=1000,quantity=5,numOwnerItems=5},
        {unitPrice=1500,quantity=1,numOwnerItems=0},{unitPrice=2000,quantity=1,numOwnerItems=0}}
    completeScan({[5]=10000,[2]=levels})
    local record = A.scanResults[910]
    eq(record.draft.output,2); eq(record.estimate.materialCost,3510)
    eq(record.estimate.unitProfit,7745); eq(record.estimate.materials[2].source,"vendor")
    A.profile.vendorPrices[3].price = 500
    eq(record.estimate.materialCost,3510)
    scanFixture(910,5); assert(A.UI.ScanProfession())
    completeScan({[5]=10000,[2]={{unitPrice=1500,quantity=1,numOwnerItems=0}}})
    eq(A.scanResults[910].estimate.unitProfit,nil); assert(A.scanResults[910].estimate.error:find("不足"))
end)

test("adding another source recipe preserves existing product fee alert and manual material prices", function()
    scanFixture(911,1); assert(A.UI.ScanProfession()); completeScan({[1]=10000,[2]=2000,[3]=100})
    local product = A.profile.products[1]
    local firstRecipe = product.recipes[1]
    product.alert = false
    assert(A.AddRecipeScan(911)); product = A.Selected()
    eq(#product.recipes,2); eq(product.fee,8); eq(product.alert,false)
    eq(product.recipes[1].materials[1].price,firstRecipe.materials[1].price)
    assert(A.AddRecipeScan(911)); eq(#A.Selected().recipes,2)
end)

test("invalid profession states cannot scan and unsupported equipment cannot fabricate results", function()
    scanFixture(912,5); ProfessionsFrame:Hide()
    local queries = #MOCK.queries
    eq(A.UI.ScanProfession(),nil); eq(#MOCK.queries,queries)
    ProfessionsFrame:Show(); ProfessionsFrame.CraftingPage:Hide()
    eq(A.UI.ScanProfession(),nil); eq(#MOCK.queries,queries)
    ProfessionsFrame.CraftingPage:Show(); selectedRecipe.supportsQualities = true
    eq(A.UI.ScanProfession(),nil); eq(A.scanResults[912],nil)
    selectedRecipe.supportsQualities = nil; A.open = false
    eq(A.UI.ScanProfession(),nil); A.open = true
    MOCK.keyInfo = {isEquipment=true}
    assert(A.UI.ScanProfession()); completeScan({})
    eq(A.scanResults[912].estimate.unitProfit,nil)
    for _, attempts in pairs(A.Market.batch.attempts) do eq(attempts,1) end
    MOCK.keyInfo = nil
end)

test("native scan button operates through AH navigation without recipe persistence", function()
    scanFixture(913,4)
    A.Native.Navigate("buy"); eq(A.UI.frame:IsShown(),false)
    A.UI.profession.current:Click(); assert(A.Market.batch.scan); eq(A.UI.frame:IsShown(),true)
    A.Market.Tick(); A.Native.Navigate("buy")
    eq(A.Market.active,nil); eq(#A.Market.queue,0); assert(A.scanResults[913].refreshError)
    A.UI.profession.current:Click(); eq(A.UI.frame:IsShown(),true); assert(A.Market.draining)
    event("COMMODITY_SEARCH_RESULTS_UPDATED",4); eq(A.Market.draining,nil)
    local batch = A.Market.batch
    eq(A.UI.ScanProfession(),nil); eq(A.Market.batch,batch)
    completeScan({[4]=20000,[2]=2000,[3]=100})
    eq(A.UI.profession.page.RecipeList.ScrollBox.rows[1].auctionPilotRecipeID,913)
    assert(A.UI.profession.profit:GetText() ~= "--")
    local saved = A.scanResults[913]
    A.AcceptQuote(4,A.Logic.Snapshot({{price=50000,quantity=100}},MOCK.time,true))
    eq(A.scanResults[913],saved); eq(saved.estimate.sale,20000)
    ProfessionsFrame:Hide(); ProfessionsFrame:Show(); A.UI.RefreshProfessionScan(); eq(A.scanResults[913],saved)
end)

test("reopened native scan history ages without issuing queries", function()
    scanFixture(914,4); assert(A.UI.ScanProfession()); completeScan({[4]=10000,[2]=2000,[3]=100})
    assert(not A.UI.profession.time:GetText():find("历史"))
    ProfessionsFrame:Hide(); local queries = #MOCK.queries
    MOCK.time = MOCK.time+121; ProfessionsFrame:Show()
    for _, tick in ipairs(MOCK.tickers) do for _ = 1,4 do tick() end end
    assert(A.UI.profession.time:GetText():find("历史")); eq(#MOCK.queries,queries)
end)

test("a scanned craft joins an existing resale product without inheriting or overwriting its purchase plan", function()
    while #A.profile.products > 0 do A.DeleteProduct(A.profile.products[1].id) end
    assert(A.SaveProduct({itemID=1,recipeName="原有单品转售",output=1,fee=5,extra=20,alert=false,
        materials={},purchase={source="fixed",price=1000}}))
    local productID, resaleID = A.Selected().id, A.SelectedRecipe().id
    scanFixture(920,1); assert(A.UI.ScanProfession())
    completeScan({[1]=12000,[2]=4000,[3]=100})
    local record = A.scanResults[920]
    eq(record.draft.purchase,nil); eq(record.draft.extra,0)
    eq(record.draft.materials[1].source,"market"); eq(record.estimate.unitProfit,3300)
    A.UI.profession.add:Click()
    local product, craft = A.Product(productID), A.SelectedRecipe()
    eq(#A.profile.products,1); eq(#product.recipes,2); eq(product.alert,false)
    eq(craft.sourceRecipeID,920); eq(craft.purchase,nil)
    A.Select(productID,resaleID)
    eq(A.SelectedRecipe().purchase.price,1000); eq(A.SelectedRecipe().extra,20)
    eq(A.Estimate(product).unitProfit,10380)
    assert(A.AddRecipeScan(920)); eq(#A.Product(productID).recipes,2)
    eq(A.Estimate(A.Selected()).unitProfit,3300)
    MOCK.combinedProductID, MOCK.combinedResaleID = productID, resaleID
end)

test("resale edits and merchant updates do not change a completed craft scan snapshot", function()
    local product = A.Product(MOCK.combinedProductID)
    A.Select(product.id,MOCK.combinedResaleID)
    ProfessionsFrame:Hide(); A.Editor.Open(product)
    eq(A.Editor.resale,true)
    A.Editor.purchase.price:SetCopper(2000)
    local draft = A.Editor.Read(); assert(A.SaveProduct(draft)); A.Editor.Close()
    local record = A.scanResults[920]
    A.profile.vendorPrices[2] = {price=1,stackCount=1,seenAt=GetServerTime(),numAvailable=0,stockSeenAt=GetServerTime()}
    A.AcceptQuote(1,A.Logic.Snapshot({{price=90000,quantity=100}},MOCK.time+1,true))
    ProfessionsFrame:Show(); A.UI.RefreshProfessionScan()
    eq(record.estimate.unitProfit,3300); eq(record.draft.materials[1].source,"market")
    eq(A.Product(product.id).recipes[1].purchase.price,2000)
    eq(A.Product(product.id).recipes[2].materials[1].quantity,2)
end)

test("a new Lua session clears scan results while preserving explicitly saved watches", function()
    local savedCount, database = #A.profile.products, AuctionPilotDB
    local reloaded = {}
    for _, name in ipairs({"Logic.lua","Core.lua","History.lua","Market.lua","Native.lua","Widgets.lua","Editor.lua","UI.lua"}) do
        assert(loadfile(PROJECT_ROOT .. "/AuctionPilot/" .. name))("AuctionPilot",reloaded)
    end
    reloaded.Initialize()
    eq(AuctionPilotDB,database); eq(#reloaded.profile.products,savedCount)
    eq(next(reloaded.scanResults),nil); eq(reloaded.profile.scanResults,nil)
    eq(next(reloaded.quotes),nil)
    local product = reloaded.Product(MOCK.combinedProductID)
    eq(product.recipes[1].purchase.price,2000)
    eq(product.recipes[2].sourceRecipeID,920); eq(#product.recipes[2].materials,2)
end)

MOCK.addon = A
print("TOTAL " .. passed .. " UI/lifecycle tests passed")
