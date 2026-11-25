-- Native profession UI and favorite batch contracts. Operator: Solazhu.
dofile(PROJECT_ROOT .. "/tests/wow_mock.lua")
local A = {}
for _, file in ipairs({"Libs/LibStub.lua","Libs/LibAHTab.lua","Logic.lua","Core.lua","History.lua",
    "Market.lua","Native.lua","Widgets.lua","Editor.lua","UI.lua"}) do
    assert(loadfile(PROJECT_ROOT .. "/AuctionPilot/" .. file))("AuctionPilot",A)
end
A.Initialize()
local function recipe(id,item,favorite)
    return {info={recipeID=id,name="专业配方"..id,learned=true,favorite=favorite},
        schematic={recipeID=id,name="专业配方"..id,outputItemID=item,quantityMin=1,quantityMax=1,
            reagentSlotSchematics={{reagentType=1,quantityRequired=2,reagents={{itemID=2}}},
                {reagentType=1,quantityRequired=1,reagents={{itemID=3}}}}}}
end
local recipes = {[900]=recipe(900,1,true),[901]=recipe(901,4,true),[902]=recipe(902,5,false)}
local frame, scroll, form = MOCK.Profession(recipes,900)
local function event(name,...) A.events.scripts.OnEvent(A.events,name,...) end
event("AUCTION_HOUSE_SHOW"); MOCK.flush(); event("TRADE_SKILL_SHOW")
local function eq(a,b) assert(a==b,"expected "..tostring(b)..", got "..tostring(a)) end
local passed=0
local function test(name,callback)
    local ok,err=pcall(callback); if not ok then error(name..": "..tostring(err)) end
    passed=passed+1; print("PASS "..name)
end

test("scan controls and profit details belong to the native profession page",function()
    assert(A.UI.profession, "profit UI must be embedded in the native profession page")
    eq(A.UI.profession.panel:GetParent(),form)
    assert(A.UI.profession.current:IsVisible())
    eq(A.UI.scanFrame,nil); eq(A.UI.scanOpen,nil)
    eq(#MOCK.queries,0)
end)

test("ordinary recipes fit the profit panel between materials and tracking without enlarging the window",function()
    local panel=A.UI.profession.panel
    eq(frame:GetHeight(),594); eq(form:GetHeight(),484)
    assert(panel:GetTop()<=form.Reagents:GetBottom()-8)
    assert(panel:GetBottom()>=form.TrackRecipeCheckbox:GetTop()+8)
    assert(panel:GetLeft()>=form:GetLeft()+12)
    assert(panel:GetLeft()+panel:GetWidth()<=form:GetLeft()+form:GetWidth()-12)
end)

test("scan buttons remain inside the profit header clear of the native title and prices",function()
    local p=A.UI.profession
    local original=form:GetWidth()
    for _,width in ipairs({original,original-80,original-108}) do
        form:SetWidth(width); A.UI.RefreshProfessionScan()
        for _,button in ipairs({p.current,p.favorites}) do
            assert(button:GetTop()<frame.TitleContainer:GetBottom(),"native title overlaps scan action")
            assert(button:GetTop()<=p.panel:GetTop()-4 and button:GetBottom()>p.sale:GetTop(),"scan action overlaps price row")
            assert(button:GetLeft()>=p.title:GetLeft()+p.title:GetWidth()+6,"scan action overlaps profit heading")
            assert(button:GetLeft()+button:GetWidth()<=p.panel:GetLeft()+p.panel:GetWidth()-10,"scan action escapes panel")
        end
        assert(p.title:GetStringWidth()<=p.title:GetWidth(),"profit heading does not fit")
    end
    form:SetWidth(original); A.UI.RefreshProfessionScan()
end)

test("unloaded favorite metadata cannot fall back to the selected nonfavorite",function()
    form:Init(recipes[902].info)
    local get=C_TradeSkillUI.GetRecipeInfo
    C_TradeSkillUI.GetRecipeInfo=function(id) if id~=901 then return get(id) end end
    local draft,why=A.Native.ReadRecipe(901)
    C_TradeSkillUI.GetRecipeInfo=get
    eq(draft,nil); assert(why:find("载入"))
end)

local M=A.Market
local function reset(clear)
    M.Pause(); M.auto=false; M.draining=nil; M.discardUntil={}; M.nextSend=0
    MOCK.ready=true; MOCK.keyInfo=nil
    A.open=true; frame:Show(); frame.CraftingPage:Show(); A.Native.ShowMonitor(); MOCK.flush()
    if clear then A.scanResults={} end
    A.UI.RefreshProfessionScan()
end
local prices={[1]=10000,[2]=2000,[3]=100,[4]=20000,[5]=8000}
C_AuctionHouse.HasFullCommoditySearchResults=function() return true end
C_AuctionHouse.GetNumCommoditySearchResults=function(id) return prices[id] and 1 or 0 end
C_AuctionHouse.GetCommoditySearchResultInfo=function(id) return {unitPrice=prices[id],quantity=100,numOwnerItems=0} end
local function tickOne()
    MOCK.time=MOCK.time+4; M.Tick()
    if M.active then event("COMMODITY_SEARCH_RESULTS_UPDATED",M.active.itemID) end
end
local function finish()
    for _=1,25 do tickOne(); if not M.active and #M.queue==0 then break end end
    eq(M.active,nil); eq(#M.queue,0)
end

test("favorite batches use native favorites without selecting recipes and deduplicate shared materials",function()
    reset(true); form:Init(recipes[902].info)
    local all=C_TradeSkillUI.GetAllRecipeIDs
    C_TradeSkillUI.GetAllRecipeIDs=function() return {900,901,902,900} end
    local count=#A.profile.products
    assert(A.UI.ScanProfession(true)); eq(form:GetRecipeInfo().recipeID,902)
    eq(table.concat(M.queue,","),"1,2,3,4"); eq(#M.batch.scan.drafts,2)
    eq(M.batch.scan.drafts[1].sourceRecipeID,900); eq(M.batch.scan.drafts[2].sourceRecipeID,901)
    finish(); C_TradeSkillUI.GetAllRecipeIDs=all
    eq(A.scanResults[900].estimate.unitProfit,5400); eq(A.scanResults[901].estimate.unitProfit,14900)
    eq(A.scanResults[902],nil); eq(#A.profile.products,count); eq(A.profile.scanResults,nil)
end)

test("completed recipes appear before the remaining batch and survive cancellation",function()
    reset(true); assert(A.UI.ScanProfession(true))
    tickOne(); eq(A.scanResults[900],nil)
    tickOne(); eq(A.scanResults[900],nil)
    tickOne(); assert(A.scanResults[900]); eq(A.scanResults[901],nil)
    local saved=A.scanResults[900]; local at=saved.at
    frame:Hide(); eq(A.scanResults[900],saved); eq(saved.refreshError,nil); eq(saved.at,at)
    assert(A.scanResults[901].refreshError); eq(A.scanResults[901].estimate.unitProfit,nil)
    local queries=#MOCK.queries
    frame:Show(); eq(#MOCK.queries,queries); eq(A.scanResults[900],saved)
end)

test("one permanently failed favorite preserves its old result and does not poison successful recipes",function()
    reset(true); assert(A.UI.ScanProfession(true)); finish()
    local old=A.scanResults[901]; local oldAt=old.at
    local send=C_AuctionHouse.SendSearchQuery
    C_AuctionHouse.SendSearchQuery=function(key,...)
        if key.itemID==4 then error("unavailable") end
        return send(key,...)
    end
    prices[1]=12000; assert(A.UI.ScanProfession(true)); finish()
    C_AuctionHouse.SendSearchQuery=send
    eq(A.scanResults[900].estimate.unitProfit,7300); eq(A.scanResults[900].refreshError,nil)
    eq(A.scanResults[901],old); eq(old.at,oldAt); assert(old.refreshError)
    eq(M.batch.attempts[4],2); eq(M.batch.failed,1); prices[1]=10000
end)

test("unloaded and unsupported favorites are explicitly skipped without adding nonfavorites",function()
    reset(true); form:Init(recipes[902].info)
    local get=C_TradeSkillUI.GetRecipeInfo
    C_TradeSkillUI.GetRecipeInfo=function(id) if id~=901 then return get(id) end end
    assert(A.UI.ScanProfession(true)); eq(#M.batch.scan.drafts,1)
    assert(A.UI.profession.skipped:find("#901")); finish()
    eq(A.scanResults[902],nil); eq(form:GetRecipeInfo().recipeID,902)
    C_TradeSkillUI.GetRecipeInfo=get
    recipes[901].info.supportsQualities=true
    assert(A.UI.ScanProfession(true)); eq(#M.batch.scan.drafts,1); finish()
    eq(A.scanResults[901],nil); assert(A.UI.profession.skipped:find("品质"))
    recipes[901].info.supportsQualities=nil
end)

test("empty favorite lists and unavailable favorite APIs issue no queries",function()
    reset(true); local queries=#MOCK.queries
    local favorite=C_TradeSkillUI.IsRecipeFavorite
    C_TradeSkillUI.IsRecipeFavorite=function() return false end
    local ok,err=A.UI.ScanProfession(true); eq(ok,nil); assert(err:find("没有")); eq(#MOCK.queries,queries)
    C_TradeSkillUI.IsRecipeFavorite=nil
    ok,err=A.UI.ScanProfession(true); eq(ok,nil); assert(err:find("接口")); eq(#MOCK.queries,queries)
    C_TradeSkillUI.IsRecipeFavorite=favorite
end)

test("native row reuse clears old profits and category rows and selection updates the inline detail",function()
    reset(true); form:Init(recipes[900].info); A.UI.profession.current:Click(); finish()
    local row=scroll.rows[1]
    eq(row.auctionPilotRecipeID,900); assert(row.auctionPilotProfit:GetText()~="未扫描")
    scroll:Reuse(row,902); eq(row.auctionPilotRecipeID,902); eq(row.auctionPilotProfit:GetText(),"未扫描")
    GameTooltip:Hide(); row.scripts.OnEnter(row); assert(GameTooltip:IsShown())
    local hovers=MOCK.nativeRecipeHovers
    for _=1,10 do A.UI.RefreshProfessionScan() end
    row.scripts.OnEnter(row); eq(MOCK.nativeRecipeHovers,hovers+1)
    row:Click(); eq(A.Native.CurrentRecipe().recipeID,902); eq(A.UI.profession.profit:GetText(),"--")
    scroll:Reuse(row,nil); eq(row.auctionPilotRecipeID,nil); eq(row.auctionPilotProfit:IsShown(),false)
    scroll:Reuse(row,900); row:Click(); assert(A.UI.profession.profit:GetText()~="--")
    local saved=A.scanResults[900]; frame.CraftingPage:Hide(); eq(A.scanResults[900],saved)
    frame.CraftingPage:Show(); eq(A.scanResults[900],saved); assert(A.UI.profession.time:GetText():find("历史"))
end)

test("long names and large values do not overwrite native craftable counts",function()
    reset(); local row=scroll.rows[1]
    row.Label:SetText(string.rep("极长配方名称",20)); row.Count:SetText(" (99999)")
    A.scanResults[900].estimate.unitProfit=80000000123
    A.UI.RefreshProfessionRow(row)
    eq(row.auctionPilotProfit:GetText(),"悬停查看"); eq(row.Count:GetText()," (99999)")
    local countRight=row.Count:GetLeft()+row.Count:GetStringWidth()
    assert(countRight<=row.auctionPilotProfit:GetLeft(),"native count overlaps profit")
end)

test("opening professions keeps normal monitor refresh available when no scan is active",function()
    reset(); assert(A.SaveProduct({itemID=1,recipeName="监控保留",output=1,fee=5,extra=0,materials={{itemID=2,quantity=1,source="fixed",price=100}}}))
    assert(M.RequestRefresh("all")); finish(); reset()
    assert(M.SetAuto(true)); assert(M.active or #M.queue>0); M.auto=false; finish()
end)

test("native materials tracking checkbox and creation controls remain outside the profit panel",function()
    reset(); local p=A.UI.profession
    assert(p.panel:GetTop()<form.Reagents:GetBottom())
    assert(p.panel:GetBottom()>=form.TrackRecipeCheckbox:GetTop()+8)
    assert(p.panel:GetBottom()>frame.CraftingPage.CreateButton:GetTop())
    local h,s=frame:GetHeight(),frame:GetScale()
    for _=1,20 do A.UI.RefreshProfessionScan() end
    eq(frame:GetHeight(),h); eq(frame:GetScale(),s)
    frame:Hide(); eq(frame:GetHeight(),594); eq(frame:GetScale(),1)
    frame:Show()
end)

test("long material lists extend the native content only as needed and restore on close",function()
    reset(); form.Reagents:SetHeight(280); A.UI.RefreshProfessionScan()
    local p=A.UI.profession; local height=frame:GetHeight()
    assert(form:GetHeight()>484); assert(height>594)
    assert(p.panel:GetTop()<=form.Reagents:GetBottom()-8)
    assert(p.panel:GetBottom()>=form.TrackRecipeCheckbox:GetTop()+8)
    assert(form:GetBottom()>frame.CraftingPage.CreateButton:GetTop())
    for _=1,20 do A.UI.RefreshProfessionScan() end
    eq(frame:GetHeight(),height)
    frame:Hide(); eq(form:GetHeight(),484); eq(frame:GetHeight(),594)
    form.Reagents:SetHeight(116); frame:Show(); eq(frame:GetHeight(),594)
end)

test("low viewport scales the extended native page and external size changes are restored",function()
    reset(); local width,height=UIParent:GetWidth(),UIParent:GetHeight()
    local setScale=frame.SetScale
    function frame:SetScale(value) setScale(self,math.floor(value*10000000)/10000000) end
    UIParent:SetSize(1024,600); A.UI.RefreshProfessionScan()
    assert(frame:GetHeight()*frame:GetScale()<=556)
    local h,s=frame:GetHeight(),frame:GetScale()
    for _=1,5 do A.UI.RefreshProfessionScan() end
    eq(frame:GetHeight(),h); eq(frame:GetScale(),s)
    frame:Hide(); eq(frame:GetHeight(),594); eq(frame:GetScale(),1)
    UIParent:SetSize(width,height); frame:Show()
    frame:SetHeight(680); frame:SetScale(.85); A.UI.RefreshProfessionScan(); frame:Hide()
    eq(frame:GetHeight(),680); eq(frame:GetScale(),.85)
    frame:SetHeight(594); frame:SetScale(1); frame:Show()
    frame.SetScale=setScale
end)

test("explicitly enabling monitor auto refresh after a completed scan starts queries without discarding results",function()
    reset(true); form:Init(recipes[900].info); assert(A.UI.ScanProfession()); finish()
    local saved=A.scanResults[900]; local queries=#MOCK.queries
    assert(M.SetAuto(true)); MOCK.time=MOCK.time+2; M.Tick()
    assert(#MOCK.queries>queries,"explicit auto refresh is stuck behind completed scan")
    eq(A.scanResults[900],saved); M.auto=false; finish()
end)

test("scanning during a monitor edit preserves the unsaved draft and issues no query",function()
    reset(); A.Editor.Open(A.Selected()); A.Editor.name:SetText("尚未保存的监控修改")
    eq(A.UI.profession.current:IsEnabled(),false); eq(A.UI.profession.favorites:IsEnabled(),false)
    eq(A.UI.profession.add:IsEnabled(),false)
    local queries=#MOCK.queries
    eq(A.UI.ScanProfession(),nil); eq(A.UI.ScanProfession(true),nil)
    assert(A.Editor.frame:IsShown()); eq(A.Editor.name:GetText(),"尚未保存的监控修改")
    eq(#MOCK.queries,queries); A.Editor.Close()
    eq(A.UI.profession.current:IsEnabled(),true)
end)

test("profit tooltips present three per-item values and quote time without recipe identifiers or material dumps",function()
    reset(true); form:Init(recipes[900].info); assert(A.UI.ScanProfession()); finish()
    local row=scroll.rows[1]; scroll:Reuse(row,900); row.scripts.OnEnter(row)
    local record=A.scanResults[900]
    eq(GameTooltip:GetText(),A.ItemInfo(record.draft.itemID)); eq(#GameTooltip.lines,4)
    eq(GameTooltip.lines[1][1],"每件净利"); eq(GameTooltip.lines[2][1],"售价 / 件")
    eq(GameTooltip.lines[3][1],"总成本 / 件（含手续费）")
    eq(GameTooltip.lines[2][2],A.Logic.Money(record.estimate.sale))
    eq(GameTooltip.lines[3][2],A.Logic.Money(record.estimate.unitCost))
    assert(not GameTooltip:GetText():find("#")); assert(GameTooltip.lines[4][1]:find("报价"))
    local green=A.Widgets.green
    eq(GameTooltip.lines[1].rightColor[2],green[2])
    A.UI.profession.panel.scripts.OnEnter(); eq(#GameTooltip.lines,4)
    frame:Hide(); frame:Show(); row.scripts.OnEnter(row)
    assert(GameTooltip.lines[4][1]:find("历史报价")); eq(#GameTooltip.lines,4)
end)

test("compact values distinguish losses missing prices and failed first scans without invented history",function()
    reset(true); form:Init(recipes[900].info); prices[1]=100
    assert(A.UI.ScanProfession()); finish()
    local p=A.UI.profession
    assert(A.scanResults[900].estimate.unitProfit<0); eq(p.profit.color[1],A.Widgets.red[1])
    eq(p.sale:GetText(),A.Logic.Money(100)); assert(p.time:IsShown()); eq(p.status:IsShown(),false)
    prices[1]=nil; assert(A.UI.ScanProfession()); finish()
    eq(p.profit:GetText(),"--"); assert(p.status:GetText():find("暂不能")); eq(p.time:IsShown(),false)
    p.panel.scripts.OnEnter(); assert(GameTooltip.lines[#GameTooltip.lines][1]:find(A.scanResults[900].estimate.error,1,true))
    prices[1]=10000; reset(true); assert(A.UI.ScanProfession()); frame:Hide(); frame:Show()
    assert(p.status:GetText():find("扫描失败")); assert(not p.status:GetText():find("保留"))
end)

test("native form size ownership survives external resize and repeated recipe changes",function()
    reset(); form:SetHeight(540); form.Reagents:SetHeight(260); A.UI.RefreshProfessionScan()
    assert(form:GetHeight()>540)
    frame:Hide(); eq(form:GetHeight(),540)
    form:SetHeight(484); form.Reagents:SetHeight(116); frame:Show()
    for i=1,40 do
        form.Reagents:SetHeight(i%2==0 and 116 or 280); form:Init(recipes[i%2==0 and 900 or 901].info)
        assert(A.UI.profession.panel:GetBottom()>=form.TrackRecipeCheckbox:GetTop()+8)
    end
    eq(form:GetHeight(),484); eq(frame:GetHeight(),594)
end)

print("TOTAL "..passed.." native-profession tests passed")
