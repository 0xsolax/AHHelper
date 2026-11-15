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
CreateFrame = function()
    local f = {events={},scripts={}}
    function f:RegisterEvent(event) self.events[event]=true end
    function f:UnregisterEvent(event) self.events[event]=nil end
    function f:SetScript(event, fn) self.scripts[event]=fn end
    frames[#frames+1]=f; return f
end
TooltipDataProcessor = {AddTooltipPostCall=function(kind, callback)
    eq(kind,1); callbacks[#callbacks+1]=callback
end}
local function newTooltip(name)
    local t = {lines={},hooks={},name=name}
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
        if self.hooks.OnTooltipCleared then self.hooks.OnTooltipCleared(self) end
    end
    function t:GetPrimaryTooltipData() return self.data end
    function t:GetProcessingTooltipInfo() return self.info end
    function t:Show() end
    return t
end
GameTooltip = newTooltip("GameTooltip")
local function event(name)
    for _,frame in ipairs(frames) do
        if frame.events[name] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame,name) end
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
    t:AddLine("技能名称")
    for _,line in ipairs(t.data.lines) do if line.leftText then t:AddLine(line.leftText) end end
    local original=t:NumLines()
    for _,callback in ipairs(callbacks) do callback(t,t.data) end
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
    near(L.Score(600,100,2500,1500,false),2.4)
    near(L.Score(600,100,500,1500,false),4)
end)
test("instant and channel spells have nonzero occupied time",function()
    near(L.Score(600,100,0,1500,false),4)
    near(L.Score(600,100,0,1500,true,3),2)
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
    local t,n=hover(1001); eq(t:NumLines(),n+1); eq(last(t),"效率：|cff66b3ff治疗 1.00|r")
    t,n=hover(1002); eq(t:NumLines(),n+1); eq(last(t),"效率：|cff66b3ff治疗 2.00|r")
    eq(queries[#queries],1002)
end)
test("action bar uses the displayed rank even with the same spell name",function()
    local t=hover(1001,"GetAction"); eq(last(t),"效率：|cff66b3ff治疗 1.00|r")
    t=hover(1002,"GetAction"); eq(last(t),"效率：|cff66b3ff治疗 2.00|r")
end)
test("native description wins over an out of date description API",function()
    local t=hover(1001,"GetAction","恢复200点生命值。")
    eq(last(t),"效率：|cff66b3ff治疗 2.00|r")
end)
test("repeated postprocessing updates one existing line",function()
    local t=hover(1001); local count=t:NumLines()
    for i=1,10 do callbacks[1](t,t.data) end
    eq(t:NumLines(),count); eq(last(t),"效率：|cff66b3ff治疗 1.00|r")
end)
test("native rebuild clears the old line and computes new costs",function()
    spells[1001].costs[1].cost=25
    local t,n=hover(1001); eq(t:NumLines(),n+1); eq(last(t),"效率：|cff66b3ff治疗 2.00|r")
    spells[1001].costs[1].cost=50
end)
test("channel hover uses complete duration instead of instant cast time",function()
    fixture(1003,"在3秒内造成600点暗影伤害。",0,100)
    local t=hover(1003,"GetAction",nil,true); eq(last(t),"效率：|cffff6666伤害 2.00|r")
end)
test("explicit channel header duration can supply the occupied time",function()
    local t=hover(1003,"GetAction","造成600点暗影伤害。",true)
    t.data.lines[2].leftText="引导（3秒）"
    callbacks[1](t,t.data); eq(last(t),"效率：|cffff6666伤害 2.00|r")
end)
test("missing channel duration never falls back to instant GCD",function()
    local t=hover(1003,"GetAction","造成600点暗影伤害。",true)
    eq(last(t),"效率：时间未知")
end)
test("instant HoT uses GCD rather than the duration of healing",function()
    fixture(1004,"在15秒内恢复600点生命值。",0,100)
    local t=hover(1004); eq(last(t),"效率：|cff66b3ff治疗 4.00|r")
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
    t=hover(1002); eq(last(t),"效率：|cff66b3ff治疗 2.00|r")
    spells[1001].fail=nil
end)
test("unloaded data retries on the next native hover",function()
    local old=spells[1001].description; spells[1001].description=""
    local t=hover(1001); eq(last(t),"效率：数据未就绪")
    spells[1001].description=old
    t=hover(1001); eq(last(t),"效率：|cff66b3ff治疗 1.00|r")
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
test("a missing GCD API never fabricates a 1.5 second reference",function()
    local original=GetSpellBaseCooldown; GetSpellBaseCooldown=nil
    local t=hover(1004)
    GetSpellBaseCooldown=original
    eq(last(t),"效率：时间未知")
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
    eq(last(t),"效率：|cff66b3ff治疗 2.00|r  |cffff6666伤害 1.00|r")
end)
test("mixed ranks and repeated callbacks update both scores without extra lines",function()
    fixture(2002,"造成400点神圣伤害，并为附近队友恢复800点生命值。",2000,400)
    local t,n=hover(2002)
    for i=1,10 do callbacks[1](t,t.data) end
    eq(t:NumLines(),n+1)
    eq(last(t),"效率：|cff66b3ff治疗 1.00|r  |cffff6666伤害 0.50|r")
    t,n=hover(1001); eq(t:NumLines(),n+1)
    eq(last(t),"效率：|cff66b3ff治疗 1.00|r")
end)
test("pure damage and shields do not invent another effect",function()
    fixture(2003,"造成300点暗影伤害。",3000,100)
    local t=hover(2003); eq(last(t),"效率：|cffff6666伤害 1.00|r")
    fixture(2004,"吸收300点伤害，持续30秒。",0,100)
    t=hover(2004); eq(last(t),"效率：|cff66b3ff吸收 2.00|r")
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
    eq(t:NumLines(),n+1); eq(last(t),"效率：|cff66b3ff治疗 2.00|r  |cffff6666伤害 2.00|r")
    t,n=hover(3002); eq(t:NumLines(),n+1)
    eq(last(t),"效率：|cff66b3ff治疗 3.00|r  |cffff6666伤害 3.00|r")
end)
test("proportional leech shares one mana cost and occupied time",function()
    fixture(3003,"在24秒内造成600点暗影伤害，并为施法者恢复相当于伤害量50%的生命值。",0,100)
    local t,n=hover(3003); eq(t:NumLines(),n+1)
    eq(last(t),"效率：|cff66b3ff治疗 2.00|r  |cffff6666伤害 4.00|r")
    spellHaste=25; t=hover(3003); spellHaste=0
    eq(last(t),"效率：|cff66b3ff治疗 2.50|r  |cffff6666伤害 5.00|r")
    t=hover(1001); eq(last(t),"效率：|cff66b3ff治疗 1.00|r")
end)
test("a 1.3 second cast uses the hasted GCD without adjusting cast time twice",function()
    fixture(3101,"恢复600点生命值。",1300,100)
    eq(last(hover(3101)),"效率：|cff66b3ff治疗 4.00|r")
    spellHaste=(1500/1300-1)*100
    local t=hover(3101); spellHaste=0
    eq(last(t),"效率：|cff66b3ff治疗 4.62|r")
    fixture(3102,"恢复600点生命值。",2000,100)
    spellHaste=30; t=hover(3102); spellHaste=0
    eq(last(t),"效率：|cff66b3ff治疗 3.00|r")
end)
test("instant GCD follows current spell haste and the Forever limits",function()
    for _,case in ipairs({{0,"4.00"},{25,"5.00"},{50,"6.00"},{100,"6.00"},{-20,"4.00"}}) do
        spellHaste=case[1]; local t=hover(1004); spellHaste=0
        eq(last(t),"效率：|cff66b3ff治疗 " .. case[2] .. "|r")
    end
    eq(last(hover(1004)),"效率：|cff66b3ff治疗 4.00|r")
end)
test("unavailable or invalid haste never invents a GCD or leaks old scores",function()
    for _,value in ipairs({secret,false,math.huge,0/0,-100}) do
        spellHaste=value; local t=hover(1004); spellHaste=0
        eq(last(t),"效率：时间未知")
    end
    local original=UnitSpellHaste; UnitSpellHaste=nil
    local t=hover(1004); UnitSpellHaste=original
    eq(last(t),"效率：时间未知")
    eq(last(hover(1004)),"效率：|cff66b3ff治疗 4.00|r")
end)
test("an off GCD cast does not require haste or invent a one second minimum",function()
    fixture(3103,"恢复600点生命值。",1300,100); spells[3103].gcd=0
    local original=UnitSpellHaste; UnitSpellHaste=nil
    local t=hover(3103); UnitSpellHaste=original
    eq(last(t),"效率：|cff66b3ff治疗 4.62|r")
end)
test("no history or saved variables accumulate over repeated hovers",function()
    for i=1,1000 do
        local t,n=hover(i%2==0 and 1001 or 1002,"GetAction")
        eq(t:NumLines(),n+1)
    end
    eq(SpellEfficiencyDB,nil)
    for line in io.lines(PROJECT_ROOT .. "/SpellEfficiency/SpellEfficiency.toc") do
        assert(not line:find("SavedVariables",1,true))
    end
end)
print("TOTAL " .. passed .. " spell-efficiency tests passed")
