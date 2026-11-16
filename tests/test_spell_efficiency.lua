-- Synthetic tooltip fixtures, not observations from a running client. Operator: Solazhu.
local A, passed = {}, 0
local function test(name, callback)
    local ok, err = pcall(callback)
    if not ok then error(name .. ": " .. tostring(err)) end
    passed = passed + 1; print("PASS " .. name)
end
local function eq(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function near(actual, expected)
    assert(type(actual) == "number" and math.abs(actual - expected) < 0.000001,
        "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

-- Load the real manifest; missing runtime files or dependencies must fail the test.
local callbacks, frames, spells, books, queries = {}, {}, {}, {}, {}
local playerClass, loggedIn, spellHaste = "PRIEST", false, 0
local secret = {}
issecretvalue = function(value) return value == secret end
GetLocale = function() return "zhCN" end
UnitClass = function() return "牧师", playerClass end
IsLoggedIn = function() return loggedIn end
Enum = {TooltipDataType={Spell=1,Item=0}, TooltipDataLineType={SpellDescription=34},
    SpellBookSpellBank={Player=0,Pet=1}, SpellBookItemType={Spell=1,FutureSpell=2}}
C_Spell = {
    GetSpellInfo=function(id)
        queries[#queries+1] = id
        local s = spells[id]; if not s then return end
        if s.fail then error("temporary API failure") end
        return {spellID=id,name=s.name or "治疗术",castTime=s.cast}
    end,
    GetSpellDescription=function(id) return spells[id] and spells[id].description end,
    GetSpellPowerCost=function(id) return spells[id] and spells[id].costs end,
}
C_SpellBook = {
    FindSpellBookSlotForSpell=function(id, hidden, flyouts, future, offspec)
        eq(hidden,true); eq(flyouts,false); eq(future,false); eq(offspec,false)
        if books[id] then return id, books[id].bank or 0 end
    end,
    GetSpellBookItemInfo=function(slot) return books[slot] end,
}
GetSpellBaseCooldown = function(id) return 60000, spells[id] and spells[id].gcd end
UnitSpellHaste = function(unit) eq(unit,"player"); return spellHaste end
CreateFrame = function(kind, name, parent, template)
    local f = {events={},scripts={},name=name,parent=parent,shown=true,width=0,height=0,text=""}
    if name then _G[name]=f end
    function f:RegisterEvent(event) self.events[event]=true end
    function f:RegisterUnitEvent(event, unit) self.events[event]=unit end
    function f:UnregisterEvent(event) self.events[event]=nil end
    function f:SetScript(event, fn) self.scripts[event]=fn end
    function f:SetSize(w,h) self.width=w; self.height=h end
    function f:SetWidth(w) self.width=w end
    function f:GetWidth() return self.width end
    function f:GetHeight() return self.height end
    function f:SetPoint(...) self.point={...} end
    function f:ClearAllPoints() self.point=nil end
    function f:SetText(value) self.text=tostring(value) end
    function f:GetText() return self.text end
    function f:SetChecked(value) self.checked=value end
    function f:GetChecked() return self.checked end
    function f:GetName() return self.name end
    function f:GetFrameLevel() return self.level or 1 end
    function f:SetFrameLevel(level) self.level=level end
    function f:GetEffectiveScale() return self.scale or 1 end
    function f:GetCenter() return self.x or 200,self.y or 300 end
    function f:IsShown() return self.shown end
    function f:Show()
        local changed=not self.shown; self.shown=true
        if changed and self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    function f:Hide()
        local changed=self.shown; self.shown=false
        if changed and self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    function f:Click(key) if self.scripts.OnClick then self.scripts.OnClick(self,key or "LeftButton") end end
    function f:SetTexture(value) self.texture=value end
    function f:SetDesaturated(value) self.desaturated=value end
    function f:CreateTexture() return CreateFrame("Texture",nil,self) end
    function f:CreateFontString() return CreateFrame("FontString",nil,self) end
    for _,method in ipairs({"SetBackdrop","SetBackdropColor","SetAllPoints","SetFrameStrata",
        "SetMovable","EnableMouse","RegisterForDrag","StartMoving","StopMovingOrSizing",
        "SetClampedToScreen","RegisterForClicks","SetHighlightTexture","SetTexCoord",
        "SetAutoFocus","SetMaxLetters","ClearFocus","SetJustifyH","SetTextColor"}) do
        f[method]=function() end
    end
    if template=="UICheckButtonTemplate" then f.Text=f:CreateFontString() end
    frames[#frames+1]=f; return f
end
UIParent=CreateFrame("Frame","UIParent")
Minimap=CreateFrame("Frame","Minimap",UIParent); Minimap:SetSize(140,140)
UISpecialFrames={}
local cursorX,cursorY=200,300
GetCursorPosition=function() return cursorX,cursorY end
TooltipDataProcessor = {AddTooltipPostCall=function(kind, callback)
    eq(kind,1); callbacks[#callbacks+1]=callback
end}
local function newTooltip(name)
    local t = {lines={},hooks={},name=name,shown=false}
    function t:GetName() return self.name end
    function t:IsForbidden() return self.forbidden or false end
    function t:NumLines() return #self.lines end
    function t:HookScript(event, fn) self.hooks[event]=fn end
    function t:AddLine(text)
        local line = {text=text}
        function line:GetText() return self.text end
        function line:SetText(value) self.text=value end
        self.lines[#self.lines+1]=line
        _G[self.name .. "TextLeft" .. #self.lines]=line
    end
    function t:ClearLines()
        self.lines={}
        self.info=nil; self.data=nil; self.processingInfo=nil
        if self.hooks.OnTooltipCleared then self.hooks.OnTooltipCleared(self) end
    end
    function t:GetPrimaryTooltipData() return self.data end
    function t:GetPrimaryTooltipInfo() return self.info end
    function t:GetProcessingTooltipInfo() return self.processingInfo end
    function t:IsShown() return self.shown end
    function t:Show() self.shown=true end
    function t:Hide() self.shown=false end
    function t:SetOwner(owner) self.owner=owner end
    function t:IsOwned(owner) return self.owner==owner end
    function t:SetText(value) self:ClearLines(); self:AddLine(value) end
    function t:RebuildFromTooltipInfo()
        local info=self.info; if not info then return end
        self.rebuilds=(self.rebuilds or 0)+1
        self:ClearLines(); self.info=info; self.data=info.tooltipData; self.processingInfo=info
        self:AddLine("技能名称")
        for _,line in ipairs(self.data.lines) do if line.leftText then self:AddLine(line.leftText) end end
        for _,callback in ipairs(callbacks) do callback(self,self.data) end
        self:Show()
    end
    return t
end
GameTooltip = newTooltip("GameTooltip")
local function event(name, unit)
    for _,frame in ipairs(frames) do
        local registered=frame.events[name]
        if (registered==true or (unit and registered==unit)) and frame.scripts.OnEvent then
            frame.scripts.OnEvent(frame,name,unit)
        end
    end
end
local function fixture(id, text, cast, mana)
    spells[id]={description=text,cast=cast or 2500,gcd=1500,
        costs={{type=0,cost=mana or 100,costPerSec=0,requiredAuraID=0}}}
    books[id]={spellID=id,actionID=id,itemType=1,isPassive=false,isOffSpec=false,skillLineIndex=2}
end
-- Model the native order: clear, add source lines, post-process, then Show.
local function hover(id, getter, text, channel, target)
    local t=target or GameTooltip
    t:ClearLines()
    t.data={type=1,id=id,lines={{type=34,leftText=text or (spells[id] and spells[id].description)}}}
    if channel then t.data.lines[#t.data.lines+1]={type=0,leftText="引导"} end
    t.info={getterName=getter or "GetSpellBookItem",tooltipData=t.data}
    t.processingInfo=t.info
    t:AddLine("技能名称")
    for _,line in ipairs(t.data.lines) do if line.leftText then t:AddLine(line.leftText) end end
    local original=t:NumLines()
    for _,callback in ipairs(callbacks) do callback(t,t.data) end
    t:Show()
    return t,original
end
local function last(t) return t.lines[#t.lines].text end
for line in io.lines(PROJECT_ROOT .. "/SpellEfficiency/SpellEfficiency.toc") do
    if line:match("%.lua$") then assert(loadfile(PROJECT_ROOT .. "/SpellEfficiency/" .. line))("SpellEfficiency",A) end
end
local L=A.Logic
local function effect(text,locale)
    local effects,reason,seconds=L.Effects(text,locale)
    if not effects then return nil,reason end
    local kind,amount=next(effects)
    assert(next(effects,kind)==nil,"expected a single effect in this fixture")
    return amount,kind,seconds
end

test("Chinese direct healing ranges use the mean",function()
    local amount,kind=effect("治疗目标，恢复500到700点生命值。","zhCN")
    eq(amount,600); eq(kind,"healing")
end)
test("Chinese direct damage ignores range and percentages",function()
    local amount,kind=effect("30码射程。对目标造成90至110点暗影伤害，使移动速度降低50%。","zhCN")
    eq(amount,100); eq(kind,"damage")
end)
test("English direct and periodic damage add once",function()
    local amount,kind=effect("Causes 100 to 200 Holy damage and an additional 70 Holy damage over 7 sec.","enUS")
    eq(amount,220); eq(kind,"damage")
end)
test("Chinese direct and periodic damage add once",function()
    eq(effect("造成100到200点神圣伤害，并在7秒内造成70点神圣伤害。","zhCN"),220)
end)
test("total HoT amount is not multiplied by duration",function()
    eq(effect("在15秒内恢复目标600点生命值。","zhCN"),600)
end)
test("per tick healing converts to the complete effect",function()
    eq(effect("每3秒恢复100点生命值，持续15秒。","zhCN"),500)
    eq(effect("Heals the target for 100 every 3 sec for 15 sec.","enUS"),500)
end)
test("direct healing does not inherit another components tick interval",function()
    eq(effect("立即恢复200点生命值，并在15秒内每3秒恢复100点生命值。","zhCN"),700)
end)
test("per second channel damage converts to total",function()
    local amount,kind,duration=effect("每秒造成100点暗影伤害，持续3秒。","zhCN")
    eq(amount,300); eq(kind,"damage"); eq(duration,3)
end)
test("channels expressed as total damage keep their duration",function()
    local amount,_,duration=effect("在3秒内对其造成300点暗影伤害，并使移动速度降低50%。","zhCN")
    eq(amount,300); eq(duration,3)
end)
test("AoE uses one target rather than guessing target count",function()
    eq(effect("恢复30码内5名队友500到700点生命值。","zhCN"),600)
    eq(effect("A prayer heals party members within 30 yards for 500 to 700.","enUS"),600)
end)
test("absorb shield is not counted again as damage",function()
    local amount,kind=effect("为目标施加护盾，吸收500点伤害，持续30秒。","zhCN")
    eq(amount,500); eq(kind,"absorb")
    eq(effect("Shields an ally, absorbing 500 damage. Lasts 30 sec.","enUS"),500)
end)
test("mixed damage and healing preserve separate categories",function()
    local effects=L.Effects("造成100点神圣伤害，并为附近队友恢复200点生命值。","zhCN")
    eq(effects.healing,200); eq(effects.damage,100); eq(effects.absorb,nil)
end)
test("English healing participles are counted exactly once",function()
    local effects=L.Effects("Causes 100 Holy damage and healing all party members for 200.","enUS")
    eq(effects.healing,200); eq(effects.damage,100); eq(effects.absorb,nil)
end)
test("Devouring Plague wording converts the complete damage at each rank",function()
    for _,amount in ipairs({152,904}) do
        local effects,reason,seconds=L.Effects("使目标患上疾病，在24秒内造成总计" .. amount ..
            "点暗影伤害，并为施法者恢复等量的生命值。","zhCN")
        eq(reason,nil); eq(seconds,24); eq(effects.damage,amount); eq(effects.healing,amount)
        eq(effects.absorb,nil)
    end
end)
test("periodic leech totals each tick once for both effects",function()
    local effects=L.Effects("每3秒造成120点暗影伤害，持续24秒，并为施法者恢复等量的生命值。","zhCN")
    eq(effects.damage,960); eq(effects.healing,960)
end)
test("explicit damage percentages produce proportional healing",function()
    for _,percent in ipairs({15,50,125}) do
        local effects=L.Effects("在24秒内造成600点暗影伤害，并为施法者恢复相当于所造成伤害" ..
            percent .. "%的生命值。","zhCN")
        eq(effects.damage,600); near(effects.healing,600*percent/100)
    end
    local effects=L.Effects("造成600点暗影伤害，将所造成伤害的50%转化为生命值。","zhCN")
    eq(effects.damage,600); eq(effects.healing,300)
end)
test("English disease leech and explicit damage fractions are recognized",function()
    local lead="Afflicts the target with a disease that causes 600 Shadow damage over 24 sec. "
    for _,case in ipairs({
        {"Damage caused by the Devouring Plague heals the caster.",600},
        {"15% of damage caused by the Devouring Plague heals the caster.",90},
        {"Heals you for 50% of damage dealt.",300},
        {"Heals the caster for 50% of the damage dealt.",300},
        {"Heals the caster for an equal amount.",600},
        {"Heals you for an amount equal to the damage dealt.",600},
    }) do
        local effects=L.Effects(lead .. case[1],"enUS")
        eq(effects.damage,600); eq(effects.healing,case[2])
    end
end)
test("explicit mixed amounts in one clause are not mistaken for a leech relation",function()
    local effects=L.Effects("造成100点神圣伤害同时恢复200点生命值。","zhCN")
    eq(effects.damage,100); eq(effects.healing,200)
    effects=L.Effects("Causes 100 Holy damage while healing the caster for 200 health.","enUS")
    eq(effects.damage,100); eq(effects.healing,200)
end)
test("a total damage reference includes direct and periodic damage once",function()
    local effects=L.Effects("造成100点暗影伤害，并在24秒内造成500点暗影伤害，" ..
        "并为施法者恢复相当于总伤害50%的生命值。","zhCN")
    eq(effects.damage,600); eq(effects.healing,300)
end)
test("leech needs a known complete damage source",function()
    for _,text in ipairs({"为施法者恢复等量的生命值。",
        "吸收600点伤害，并为施法者恢复等量的生命值。",
        "每3秒造成100点暗影伤害，并为施法者恢复等量的生命值。"}) do
        local effects,reason=L.Effects(text,"zhCN")
        eq(effects,nil); eq(reason,"unsupported")
    end
end)
test("unknown relative healing is not silently omitted",function()
    for _,tail in ipairs({"为施法者恢复部分伤害量的生命值。","治疗施法者。",
        "为施法者恢复相当于伤害量0%的生命值。","为施法者恢复相当于伤害量-50%的生命值。"}) do
        local effects,reason=L.Effects("造成600点暗影伤害，并" .. tail,"zhCN")
        eq(effects,nil); eq(reason,"unsupported")
    end
end)
test("ambiguous duplicate healing cannot double a leech estimate",function()
    for _,tail in ipairs({"恢复等量的生命值，并恢复等量的生命值。",
        "恢复600点生命值，并恢复等量的生命值。"}) do
        local effects,reason=L.Effects("造成600点暗影伤害，并" .. tail,"zhCN")
        eq(effects,nil); eq(reason,"unsupported")
    end
end)
test("percentage healing is not mistaken for a flat number",function()
    eq(effect("Heals the target for 20% of maximum health.","enUS"),nil)
end)
test("a second unparsed output is not silently dropped",function()
    eq(effect("恢复100点生命值，并恢复最大生命值的5%。","zhCN"),nil)
    eq(effect("Heals the target for 100 and restores 5% of maximum health.","enUS"),nil)
end)
test("conditional next attack and chance effects have no fixed total",function()
    eq(effect("The next melee attack against the caster causes 100 Shadow damage.","enUS"),nil)
    eq(effect("有20%几率恢复100点生命值。","zhCN"),nil)
end)
test("formatting and thousands separators preserve magnitude",function()
    eq(effect("恢复|cffffffff1,000至1,400|r点生命值。","zhCN"),1200)
end)
test("ASCII tilde ranges cannot be truncated to their upper bound",function()
    eq(effect("恢复100~200点生命值。","zhCN"),150)
end)
test("per second and per interval English effects use the complete total",function()
    eq(effect("Heals the target for 100 per second for 15 sec.","enUS"),1500)
    eq(effect("Heals the target for 100 per 3 sec for 15 sec.","enUS"),500)
end)
test("a detached tick interval is not silently treated as a total effect",function()
    eq(effect("恢复100点生命值，每3秒一次，持续15秒。","zhCN"),nil)
end)
test("unparsed healing quantity suffixes never become a partial scalar",function()
    for _,text in ipairs({"Heals the target for 1.2k health.", "Heals the target for 1.2 million health.",
        "Heals the target for 100 + 200 health."}) do
        eq(effect(text,"enUS"),nil)
    end
end)
test("additional damage wording still contributes to the total",function()
    eq(effect("造成100点神圣伤害，并在7秒内造成70点额外的神圣伤害。","zhCN"),170)
end)
test("buffs and resurrection have no efficiency",function()
    local amount,reason=effect("使目标的耐力提高30点，持续30分钟。","zhCN")
    eq(amount,nil); eq(reason,"not_applicable")
    amount,reason=effect("复活一名死亡的玩家，为其恢复500点生命值。","zhCN")
    eq(amount,nil); eq(reason,"not_applicable")
end)
test("conditional and percentage effects are never guessed",function()
    eq(effect("每当受到攻击时，对攻击者造成100点暗影伤害，可使用3次。","zhCN"),nil)
    eq(effect("恢复目标20%的生命值。","zhCN"),nil)
    eq(effect("For each point of mana burned the target takes 0.5 Shadow damage.","enUS"),nil)
end)
test("unknown language missing text and unresolved variables stay unavailable",function()
    eq(effect("Heals the target for 100.","deDE"),nil)
    eq(effect("","zhCN"),nil)
    eq(effect("恢复$s1点生命值。","zhCN"),nil)
end)
test("invalid ranges and incomplete periodic data do not produce numbers",function()
    eq(effect("恢复700到500点生命值。","zhCN"),nil)
    eq(effect("每3秒恢复100点生命值。","zhCN"),nil)
    eq(effect("每2秒恢复100点生命值，持续5秒。","zhCN"),nil)
end)
test("one malformed effect component invalidates the complete estimate",function()
    eq(effect("恢复100点生命值，并每3秒恢复50点生命值。","zhCN"),nil)
end)
test("cast time and GCD overlap rather than adding",function()
    near(L.Score(600,100,2500,1500,false),2.882698641555435)
    near(L.Score(600,100,500,1500,false),4.337887084790794)
end)
test("instant and channel spells have nonzero occupied time",function()
    near(L.Score(600,100,0,1500,false),4.337887084790794)
    near(L.Score(600,100,0,1500,true,3),2.4914618792310343)
    near(L.Score(600,100,0,1000,false),6)
end)
test("doubling occupied time penalizes less than doubling mana",function()
    local base=L.Score(600,100,1500,1500,false)
    near(L.Score(600,100,3000,1500,false)/base,0.5743491774985175)
    near(L.Score(600,200,1500,1500,false)/base,0.5)
    near(L.Score(1200,100,1500,1500,false)/base,2)
end)
test("reduced time weight can favor a slower spell with higher effect per mana",function()
    local fast=L.Score(600,100,1500,1500,false)
    local slow=L.Score(1100,100,3000,1500,false)
    -- Old per-second scores were 4.00 and 3.67; a uniform scale cannot reverse that ranking.
    assert(slow>fast,"higher per-mana yield should outweigh this casting-time difference")
    near(fast,4.337887084790794); near(slow,4.567680111923563)
end)
test("missing channel time zero mana and nonfinite inputs are not scores",function()
    eq(L.Score(600,100,0,1500,true),nil)
    eq(L.Score(600,0,2500,1500,false),nil)
    eq(L.Score(600,100,0,0,false),nil)
    eq(L.Score(600,100,nil,1500,false),nil)
    eq(L.Score(math.huge,100,2500,1500,false),nil)
    eq(L.Score(600,0/0,2500,1500,false),nil)
end)
test("mana cost is absolute even when a percentage is also supplied",function()
    eq(L.ManaCost({{type=0,cost=120,costPercent=5,costPerSec=0}}),120)
end)
test("mana cost respects required aura and does not add alternatives",function()
    eq(L.ManaCost({{type=0,cost=100},{type=0,cost=50,requiredAuraID=4,hasRequiredAura=false}}),100)
    eq(L.ManaCost({{type=0,cost=100},{type=0,cost=50,requiredAuraID=4,hasRequiredAura=true}}),50)
end)
test("missing cost is distinct from confirmed free cast",function()
    eq(L.ManaCost(nil),nil); eq(L.ManaCost({}),nil)
    eq(L.ManaCost({{type=0,cost=0}}),0)
    eq(L.ManaCost({{type=1,cost=50}}),nil)
    eq(L.ManaCost({{type=0,cost=50,costPerSec=2}}),nil)
end)
test("login registers one spell postprocessor and no polling script",function()
    event("ADDON_LOADED"); eq(#callbacks,0)
    loggedIn=true; event("PLAYER_LOGIN"); event("ADDON_LOADED"); event("PLAYER_LOGIN")
    eq(#callbacks,1)
    for _,frame in ipairs(frames) do eq(frame.scripts.OnUpdate,nil) end
end)
test("spellbook low and high ranks keep separate IDs and values",function()
    fixture(1001,"恢复100点生命值。",2000,50)
    fixture(1002,"恢复600点生命值。",3000,100)
    local t,n=hover(1001); eq(t:NumLines(),n+1); eq(last(t),"效率：|cff66b3ff治疗 1.15|r")
    t,n=hover(1002); eq(t:NumLines(),n+1); eq(last(t),"效率：|cff66b3ff治疗 2.49|r")
    eq(queries[#queries],1002)
end)
test("action bar uses the displayed rank even with the same spell name",function()
    local t=hover(1001,"GetAction"); eq(last(t),"效率：|cff66b3ff治疗 1.15|r")
    t=hover(1002,"GetAction"); eq(last(t),"效率：|cff66b3ff治疗 2.49|r")
end)
test("native description wins over an out of date description API",function()
    local t=hover(1001,"GetAction","恢复200点生命值。")
    eq(last(t),"效率：|cff66b3ff治疗 2.30|r")
end)
test("repeated postprocessing updates one existing line",function()
    local t=hover(1001); local count=t:NumLines()
    for i=1,10 do callbacks[1](t,t.data) end
    eq(t:NumLines(),count); eq(last(t),"效率：|cff66b3ff治疗 1.15|r")
end)
test("native rebuild clears the old line and computes new costs",function()
    spells[1001].costs[1].cost=25
    local t,n=hover(1001); eq(t:NumLines(),n+1); eq(last(t),"效率：|cff66b3ff治疗 2.30|r")
    spells[1001].costs[1].cost=50
end)
test("channel hover uses complete duration instead of instant cast time",function()
    fixture(1003,"在3秒内造成600点暗影伤害。",0,100)
    local t=hover(1003,"GetAction",nil,true); eq(last(t),"效率：|cffff6666伤害 2.49|r")
end)
test("explicit channel header duration can supply the occupied time",function()
    local t=hover(1003,"GetAction","造成600点暗影伤害。",true)
    t.data.lines[2].leftText="引导（3秒）"
    callbacks[1](t,t.data); eq(last(t),"效率：|cffff6666伤害 2.49|r")
end)
test("missing channel duration never falls back to instant GCD",function()
    local t=hover(1003,"GetAction","造成600点暗影伤害。",true)
    eq(last(t),"效率：时间未知")
end)
test("instant HoT uses GCD rather than the duration of healing",function()
    fixture(1004,"在15秒内恢复600点生命值。",0,100)
    local t=hover(1004); eq(last(t),"效率：|cff66b3ff治疗 4.34|r")
end)
test("utility and passive spells get only one nonapplicable line",function()
    fixture(1005,"使目标耐力提高30点。",0,100)
    local t,n=hover(1005); eq(t:NumLines(),n+1); eq(last(t),"效率：不适用")
    books[1005].isPassive=true; spells[1005].description="造成100点伤害。"
    t,n=hover(1005); eq(t:NumLines(),n+1); eq(last(t),"效率：不适用")
end)
test("temporarily free casts are not displayed as infinity",function()
    spells[1001].costs[1].cost=0
    local t=hover(1001); eq(last(t),"效率：当前免耗蓝")
    spells[1001].costs[1].cost=50
end)
test("failed query does not break the next spell or retain a stale score",function()
    spells[1001].fail=true
    local t,n=hover(1001); eq(t:NumLines(),n+1); eq(last(t),"效率：暂不可用")
    t=hover(1002); eq(last(t),"效率：|cff66b3ff治疗 2.49|r")
    spells[1001].fail=nil
end)
test("unloaded data retries on the next native hover",function()
    local old=spells[1001].description; spells[1001].description=""
    local t=hover(1001); eq(last(t),"效率：数据未就绪")
    spells[1001].description=old
    t=hover(1001); eq(last(t),"效率：|cff66b3ff治疗 1.15|r")
end)
test("items auras links other players and forbidden tooltips are untouched",function()
    for _,getter in ipairs({"GetBagItem","GetUnitAura","GetHyperlink"}) do
        local t,n=hover(1001,getter); eq(t:NumLines(),n)
    end
    local other=newTooltip("ItemRefTooltip")
    local t,n=hover(1001,nil,nil,nil,other); eq(t:NumLines(),n)
    GameTooltip.forbidden=true; t,n=hover(1001); eq(t:NumLines(),n); GameTooltip.forbidden=false
    playerClass="MAGE"; t,n=hover(1001); eq(t:NumLines(),n); playerClass="PRIEST"
end)
test("unlearned pet general and future spells are excluded",function()
    local t,n=hover(9999); eq(t:NumLines(),n)
    for key,value in pairs({bank=1,skillLineIndex=1,itemType=2}) do
        local old=books[1001][key]; books[1001][key]=value
        t,n=hover(1001); eq(t:NumLines(),n); books[1001][key]=old
    end
end)
test("a lookup returning a different rank never supplies its values",function()
    books[1001].spellID=1002; books[1001].actionID=1002
    local t,n=hover(1001); eq(t:NumLines(),n)
    books[1001].spellID=1001; books[1001].actionID=1001
end)
test("secret spell IDs do not enter arithmetic or lookups",function()
    local t,n=hover(secret); eq(t:NumLines(),n)
end)
test("inaccessible descriptions cannot retain the previous numeric value",function()
    local t=hover(1001)
    t.data.lines[1].leftText=secret
    callbacks[1](t,t.data); eq(last(t),"效率：暂不可用")
end)
test("very small scores do not round to a misleading zero",function()
    fixture(1006,"恢复1点生命值。",2000,1000)
    local t=hover(1006); eq(last(t),"效率：|cff66b3ff治疗 <0.01|r")
end)
test("a missing GCD API uses the default and still applies available haste",function()
    local original=GetSpellBaseCooldown; GetSpellBaseCooldown=nil
    local t=hover(1004)
    GetSpellBaseCooldown=original
    eq(last(t),"效率：|cff66b3ff治疗 4.34|r")
    GetSpellBaseCooldown=nil; spellHaste=25
    t=hover(1004); spellHaste=0; GetSpellBaseCooldown=original
    eq(last(t),"效率：|cff66b3ff治疗 5.19|r")
end)

test("unavailable or invalid base GCD uses the default",function()
    for _,value in ipairs({secret,false,math.huge,0/0,-1}) do
        spells[1004].gcd=value; local t=hover(1004); spells[1004].gcd=1500
        eq(last(t),"效率：|cff66b3ff治疗 4.34|r")
    end
    spells[1004].gcd=nil; local t=hover(1004); spells[1004].gcd=1500
    eq(last(t),"效率：|cff66b3ff治疗 4.34|r")
end)
test("a genuine zero GCD is not silently replaced by a positive default",function()
    spells[1004].gcd=0
    local t=hover(1004); eq(last(t),"效率：时间未知")
    spells[1004].gcd=1500
end)
test("mixed spell keeps blue healing and red damage in one line",function()
    fixture(2001,"造成300点神圣伤害，并为附近队友恢复600点生命值。",3000,100)
    local t,n=hover(2001,"GetAction")
    eq(t:NumLines(),n+1)
    eq(last(t),"效率：|cff66b3ff治疗 2.49|r  |cffff6666伤害 1.25|r")
end)
test("mixed ranks and repeated callbacks update both scores without extra lines",function()
    fixture(2002,"造成400点神圣伤害，并为附近队友恢复800点生命值。",2000,400)
    local t,n=hover(2002)
    for i=1,10 do callbacks[1](t,t.data) end
    eq(t:NumLines(),n+1)
    eq(last(t),"效率：|cff66b3ff治疗 1.15|r  |cffff6666伤害 0.57|r")
    t,n=hover(1001); eq(t:NumLines(),n+1)
    eq(last(t),"效率：|cff66b3ff治疗 1.15|r")
end)
test("pure damage and shields do not invent another effect",function()
    fixture(2003,"造成300点暗影伤害。",3000,100)
    local t=hover(2003); eq(last(t),"效率：|cffff6666伤害 1.25|r")
    fixture(2004,"吸收300点伤害，持续30秒。",0,100)
    t=hover(2004); eq(last(t),"效率：|cff66b3ff吸收 2.17|r")
end)
test("a mixed spell with unknown mana shows one status rather than partial scores",function()
    local previous=spells[2001].costs; spells[2001].costs=nil
    local t,n=hover(2001); eq(t:NumLines(),n+1); eq(last(t),"效率：耗蓝未知")
    spells[2001].costs=previous
end)
test("leech ranks keep blue healing and red damage in one tooltip line",function()
    fixture(3001,"在24秒内造成600点暗影伤害，并为施法者恢复等量的生命值。",0,200)
    fixture(3002,"在24秒内造成900点暗影伤害，并为施法者恢复等量的生命值。",0,200)
    local t,n=hover(3001,"GetAction")
    for i=1,10 do callbacks[1](t,t.data) end
    eq(t:NumLines(),n+1); eq(last(t),"效率：|cff66b3ff治疗 2.17|r  |cffff6666伤害 2.17|r")
    t,n=hover(3002); eq(t:NumLines(),n+1)
    eq(last(t),"效率：|cff66b3ff治疗 3.25|r  |cffff6666伤害 3.25|r")
end)
test("proportional leech shares one mana cost and occupied time",function()
    fixture(3003,"在24秒内造成600点暗影伤害，并为施法者恢复相当于伤害量50%的生命值。",0,100)
    local t,n=hover(3003); eq(t:NumLines(),n+1)
    eq(last(t),"效率：|cff66b3ff治疗 2.17|r  |cffff6666伤害 4.34|r")
    spellHaste=25; t=hover(3003); spellHaste=0
    eq(last(t),"效率：|cff66b3ff治疗 2.59|r  |cffff6666伤害 5.19|r")
    t=hover(1001); eq(last(t),"效率：|cff66b3ff治疗 1.15|r")
end)
test("a 1.3 second cast uses the hasted GCD without adjusting cast time twice",function()
    fixture(3101,"恢复600点生命值。",1300,100)
    eq(last(hover(3101)),"效率：|cff66b3ff治疗 4.34|r")
    spellHaste=(1500/1300-1)*100
    local t=hover(3101); spellHaste=0
    eq(last(t),"效率：|cff66b3ff治疗 4.86|r")
    fixture(3102,"恢复600点生命值。",2000,100)
    spellHaste=30; t=hover(3102); spellHaste=0
    eq(last(t),"效率：|cff66b3ff治疗 3.45|r")
end)
test("instant GCD follows current spell haste and the Forever limits",function()
    for _,case in ipairs({{0,"4.34"},{25,"5.19"},{50,"6.00"},{100,"6.00"},{-20,"4.34"}}) do
        spellHaste=case[1]; local t=hover(1004); spellHaste=0
        eq(last(t),"效率：|cff66b3ff治疗 " .. case[2] .. "|r")
    end
    eq(last(hover(1004)),"效率：|cff66b3ff治疗 4.34|r")
end)
test("unavailable or invalid haste uses base GCD instead of stale scores",function()
    for _,value in ipairs({secret,false,math.huge,0/0,-100}) do
        spellHaste=value; local t=hover(1004); spellHaste=0
        eq(last(t),"效率：|cff66b3ff治疗 4.34|r")
    end
    local original=UnitSpellHaste; UnitSpellHaste=nil
    local t=hover(1004); UnitSpellHaste=original
    eq(last(t),"效率：|cff66b3ff治疗 4.34|r")
    spellHaste=nil; t=hover(1004); spellHaste=0
    eq(last(t),"效率：|cff66b3ff治疗 4.34|r")
    eq(last(hover(1004)),"效率：|cff66b3ff治疗 4.34|r")
end)

test("missing haste preserves a known shorter base GCD",function()
    spells[1004].gcd=1000; spellHaste=nil
    local t=hover(1004); spells[1004].gcd=1500; spellHaste=0
    eq(last(t),"效率：|cff66b3ff治疗 6.00|r")
end)

test("timing API errors use the default without breaking the next hover",function()
    local originalBase,originalHaste=GetSpellBaseCooldown,UnitSpellHaste
    GetSpellBaseCooldown=function() error("GCD not ready") end
    UnitSpellHaste=function() error("haste not ready") end
    local t=hover(1004)
    GetSpellBaseCooldown=originalBase; UnitSpellHaste=originalHaste
    eq(last(t),"效率：|cff66b3ff治疗 4.34|r")
    spellHaste=25; t=hover(1004); spellHaste=0
    eq(last(t),"效率：|cff66b3ff治疗 5.19|r")
end)

test("haste becoming available updates the open tooltip without another hover",function()
    spellHaste=nil
    local t,n=hover(1004,"GetAction"); spellHaste=0
    eq(last(t),"效率：|cff66b3ff治疗 4.34|r")
    -- Outside postprocessing, use the primary tooltip rather than a transient callback context.
    t.processingInfo=nil
    spellHaste=25; event("UNIT_SPELL_HASTE","player"); spellHaste=0
    eq(last(t),"效率：|cff66b3ff治疗 5.19|r"); eq(t:NumLines(),n+1)
    for _,value in ipairs({50,secret,0,25}) do
        spellHaste=value; event("UNIT_SPELL_HASTE","player"); spellHaste=0
        local expected=value==50 and "6.00" or (value==25 and "5.19" or "4.34")
        eq(last(t),"效率：|cff66b3ff治疗 " .. expected .. "|r"); eq(t:NumLines(),n+1)
    end
end)

test("haste events use current primary spell even after an appended tooltip",function()
    hover(1004,"GetAction")
    local t,n=hover(3003,"GetSpellBookItem")
    t.processingInfo={getterName="GetSpellByID",append=true,tooltipData={type=1,id=1004}}
    spellHaste=25; event("UNIT_SPELL_HASTE","player"); spellHaste=0
    eq(last(t),"效率：|cff66b3ff治疗 2.59|r  |cffff6666伤害 5.19|r")
    eq(t:NumLines(),n+1); eq(queries[#queries],3003)
end)

test("haste events do not query hidden cleared or unrelated tooltips",function()
    local t,n=hover(1004); local count=#queries
    spellHaste=25; event("UNIT_SPELL_HASTE","target"); spellHaste=0
    eq(#queries,count); eq(last(t),"效率：|cff66b3ff治疗 4.34|r")
    t:Hide(); spellHaste=25; event("UNIT_SPELL_HASTE","player"); spellHaste=0
    eq(#queries,count); eq(t:IsShown(),false)
    t:Show(); t.forbidden=true; event("UNIT_SPELL_HASTE","player"); t.forbidden=false
    eq(#queries,count)
    -- A reused item tooltip may share the numeric ID of a known spell.
    t.data.type=0; t.info.getterName="GetBagItem"
    event("UNIT_SPELL_HASTE","player"); eq(#queries,count); eq(t:NumLines(),n+1)
    t:ClearLines(); t:AddLine("背包物品")
    event("UNIT_SPELL_HASTE","player"); eq(#queries,count); eq(t:NumLines(),1)
    t,n=hover(1004,"GetUnitAura"); count=#queries
    event("UNIT_SPELL_HASTE","player"); eq(#queries,count); eq(t:NumLines(),n)
end)
test("an off GCD cast does not require haste or invent a one second minimum",function()
    fixture(3103,"恢复600点生命值。",1300,100); spells[3103].gcd=0
    local original=UnitSpellHaste; UnitSpellHaste=nil
    local t=hover(3103); UnitSpellHaste=original
    eq(last(t),"效率：|cff66b3ff治疗 4.86|r")
end)
test("repeated hovers retain only three settings and no history",function()
    for i=1,1000 do
        local t,n=hover(i%2==0 and 1001 or 1002,"GetAction")
        eq(t:NumLines(),n+1)
    end
    local count=0
    for key in pairs(SpellEfficiencyDB) do
        assert(key=="enabled" or key=="timeWeight" or key=="minimapAngle")
        count=count+1
    end
    eq(count,3)
    local declared=false
    for line in io.lines(PROJECT_ROOT .. "/SpellEfficiency/SpellEfficiency.toc") do
        if line=="## SavedVariablesPerCharacter: SpellEfficiencyDB" then declared=true end
    end
    eq(declared,true)
end)
test("manual time weights cover mana only original timing and intermediate values",function()
    near(L.Score(600,100,3000,1500,false,nil,0),6)
    near(L.Score(600,100,3000,1500,false,nil,1),2)
    near(L.Score(600,100,3000,1500,false,nil,0.5),3.4641016151377544)
    near(L.Score(600,100,nil,nil,true,nil,0),6)
    eq(L.Score(600,0,nil,nil,false,nil,0),nil)
    for _,weight in ipairs({-0.1,1.1,secret,false,math.huge,0/0}) do
        eq(L.Score(600,100,3000,1500,false,nil,weight),nil)
    end
end)
test("minimap opens settings and applies a decimal weight to both tooltip effects",function()
    local button=SpellEfficiencyMinimapButton
    assert(button,"missing minimap button"); button:Click()
    local panel=SpellEfficiencySettingsFrame
    assert(panel and panel:IsShown(),"settings must open")
    eq(panel.weight:GetText(),"0.8"); eq(panel.enabled:GetChecked(),true)
    panel.weight:SetText("0.5"); panel.apply:Click()
    eq(SpellEfficiencyDB.timeWeight,0.5)
    eq(last(hover(3003)),"效率：|cff66b3ff治疗 2.45|r  |cffff6666伤害 4.90|r")
    panel.weight:SetText("1"); panel.weight.scripts.OnEnterPressed(panel.weight)
    eq(last(GameTooltip),"效率：|cff66b3ff治疗 2.00|r  |cffff6666伤害 4.00|r")
    panel.defaults:Click(); eq(SpellEfficiencyDB.timeWeight,0.8)
    eq(last(GameTooltip),"效率：|cff66b3ff治疗 2.17|r  |cffff6666伤害 4.34|r")
end)
test("invalid settings preserve both saved fields and the active tooltip",function()
    local panel=SpellEfficiencySettingsFrame
    local t=hover(1004); local text=last(t); local count=#queries
    for _,value in ipairs({"","abc","-0.1","1.1","50%","nan","inf"}) do
        panel.weight:SetText(value); panel.enabled:SetChecked(false); panel.apply:Click()
        eq(SpellEfficiencyDB.timeWeight,0.8); eq(SpellEfficiencyDB.enabled,true)
        eq(last(t),text); eq(#queries,count)
        assert(panel.error:GetText()~="","invalid input needs a visible explanation")
    end
    panel:Hide(); SpellEfficiencyMinimapButton:Click()
    eq(panel.weight:GetText(),"0.8"); eq(panel.enabled:GetChecked(),true)
end)
test("disabling removes the current efficiency line and prevents further spell queries",function()
    local t,n=hover(1004); local count=#queries
    local panel=SpellEfficiencySettingsFrame
    panel.enabled:SetChecked(false); panel.weight:SetText("0.8"); panel.apply:Click()
    eq(SpellEfficiencyDB.enabled,false)
    eq(t:NumLines(),n); eq(t.rebuilds,1); eq(#queries,count)
    event("UNIT_SPELL_HASTE","player"); eq(#queries,count)
    t,n=hover(1004); eq(t:NumLines(),n); eq(#queries,count)
    SpellEfficiencyMinimapButton:Click("RightButton")
    eq(SpellEfficiencyDB.enabled,true); eq(t:NumLines(),n+1)
    eq(last(t),"效率：|cff66b3ff治疗 4.34|r")
end)
test("settings changes cannot resurrect hidden or unrelated spell data",function()
    local t=hover(1004); t:Hide(); local count=#queries
    assert(A.Settings.Apply(true,0.25)); eq(t:IsShown(),false); eq(#queries,count)
    for _,getter in ipairs({"GetBagItem","GetUnitAura","GetHyperlink"}) do
        local n; t,n=hover(1004,getter); count=#queries
        assert(A.Settings.Apply(false,0.5)); assert(A.Settings.Apply(true,0.8))
        eq(t:NumLines(),n); eq(#queries,count)
    end
end)
test("zero time weight ignores missing timing but still requires known mana",function()
    assert(A.Settings.Apply(true,0))
    local old=spells[1004].cast; spells[1004].cast=nil
    local t=hover(1004); spells[1004].cast=old
    eq(last(t),"效率：|cff66b3ff治疗 6.00|r")
    eq(last(hover(1003,"GetAction","造成600点暗影伤害。",true)),"效率：|cffff6666伤害 6.00|r")
    local costs=spells[1004].costs; spells[1004].costs=nil
    t=hover(1004); spells[1004].costs=costs
    eq(last(t),"效率：耗蓝未知")
    assert(A.Settings.Apply(true,0.8))
end)
test("dragging uses minimap scale and stops all update work on release or hide",function()
    local button=SpellEfficiencyMinimapButton
    Minimap.scale=2; cursorX=400; cursorY=800
    button.scripts.OnDragStart(button); assert(button.scripts.OnUpdate)
    button.scripts.OnUpdate(button)
    near(SpellEfficiencyDB.minimapAngle,90)
    near(button.point[4],0); near(button.point[5],78)
    button.scripts.OnDragStop(button); eq(button.scripts.OnUpdate,nil)
    button.scripts.OnDragStart(button); button:Hide(); eq(button.scripts.OnUpdate,nil)
    button:Show(); Minimap.scale=1
    for _,frame in ipairs(frames) do eq(frame.scripts.OnUpdate,nil) end
end)
test("settings reload restores only the current characters three scalar values",function()
    local function reload(saved, alreadyLoggedIn)
        SpellEfficiencyDB=saved; loggedIn=alreadyLoggedIn or false; callbacks={}; frames={}; A={}
        GameTooltip=newTooltip("GameTooltip"); UISpecialFrames={}
        SpellEfficiencyMinimapButton=nil; SpellEfficiencySettingsFrame=nil
        for line in io.lines(PROJECT_ROOT .. "/SpellEfficiency/SpellEfficiency.toc") do
            if line:match("%.lua$") then assert(loadfile(PROJECT_ROOT .. "/SpellEfficiency/" .. line))("SpellEfficiency",A) end
        end
        eq(SpellEfficiencyDB,saved)
        event("ADDON_LOADED","SpellEfficiency")
        if not loggedIn then loggedIn=true; event("PLAYER_LOGIN") end
    end
    reload({enabled=false,timeWeight=0.25,minimapAngle=90})
    eq(SpellEfficiencyDB.enabled,false); eq(SpellEfficiencyDB.timeWeight,0.25)
    near(SpellEfficiencyMinimapButton.point[5],78)
    SpellEfficiencyMinimapButton:Click(); local panel=SpellEfficiencySettingsFrame
    eq(panel.enabled:GetChecked(),false); eq(panel.weight:GetText(),"0.25")
    local t,n=hover(1004); eq(t:NumLines(),n)
    reload({enabled="bad",timeWeight=2,minimapAngle=math.huge})
    eq(SpellEfficiencyDB.enabled,true); eq(SpellEfficiencyDB.timeWeight,0.8)
    eq(SpellEfficiencyDB.minimapAngle,225)
    reload(nil); eq(SpellEfficiencyDB.timeWeight,0.8)
    local buttons=0
    event("ADDON_LOADED","UnrelatedAddon"); event("PLAYER_LOGIN")
    for _,frame in ipairs(frames) do if frame.name=="SpellEfficiencyMinimapButton" then buttons=buttons+1 end end
    eq(buttons,1)
    reload({enabled=true,timeWeight=0,minimapAngle=0},true)
    eq(last(hover(1004)),"效率：|cff66b3ff治疗 6.00|r")
    local map=Minimap; Minimap=nil; reload(nil)
    eq(SpellEfficiencyMinimapButton,nil)
    Minimap=map; event("ADDON_LOADED","Blizzard_Minimap")
    assert(SpellEfficiencyMinimapButton)
    playerClass="MAGE"; reload(nil); eq(SpellEfficiencyMinimapButton,nil); eq(#callbacks,0)
    playerClass="PRIEST"; reload(nil)
end)
print("TOTAL " .. passed .. " spell-efficiency tests passed")
