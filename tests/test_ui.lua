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
    A.UI.detailMenu:Click(); menuEntry("编辑当前配方"):Click()
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
test("closing AH retains configuration but clears all query work", function()
    eq(#MOCK.queries,0)
    A.UI.refresh:Click(); eq(table.concat(A.Market.queue,","),"1,2")
    A.Market.Tick(); eq(#MOCK.queries,1); eq(MOCK.queries[1],1)
    event("AUCTION_HOUSE_CLOSED"); eq(A.open, false); eq(#A.profile.products, 1)
    eq(A.UI.frame:IsShown(), false); eq(#A.Market.queue, 0)
    event("AUCTION_HOUSE_SHOW"); MOCK.flush(); eq(next(A.quotes), nil)
end)
test("one product row shows the selected recipe and menu switches independent estimates", function()
    A.Native.ShowMonitor(); MOCK.flush()
    A.UI.productRows[1].menu:Click(); menuEntry("添加配方"):Click()
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
    A.Editor.Open(A.Selected()); button("删除配方"):Click(); eq(#A.Selected().recipes,2)
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
    A.UI.productRows[1].menu:Click(); menuEntry("添加配方"):Click(); A.Editor.import:Click()
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
        if frame.kind == "Button" and frame:IsVisible() and frame.text:find("刷新") then refreshes = refreshes + 1 end
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
    A.Market.queue = {1,2}; A.Market.active = {itemID = 1}
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

MOCK.addon = A
print("TOTAL " .. passed .. " UI/lifecycle tests passed")
