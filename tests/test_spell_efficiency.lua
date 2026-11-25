-- Offline tooltip fixtures; screenshot-derived cases are identified below. Operator: Solazhu.
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
local channel, channelReads = nil, 0
local now, maxMana, manaReads, costReads = 0, 1000, 0, 0
local secret = {}
issecretvalue = function(value) return value == secret end
GetLocale = function() return "zhCN" end
UnitClass = function() return "牧师", playerClass end
IsLoggedIn = function() return loggedIn end
Enum = {TooltipDataType={Spell=1,Item=0}, TooltipDataLineType={SpellDescription=34},
    SpellBookSpellBank={Player=0,Pet=1}, SpellBookItemType={Spell=1,FutureSpell=2}, PowerType={Mana=0}}
GetTime = function() return now end
UnitPowerMax = function(unit, powerType)
    eq(unit,"player"); eq(powerType,Enum.PowerType.Mana)
    return maxMana
end
UnitPower = function() manaReads=manaReads+1; return secret end
C_Spell = {
    GetSpellInfo=function(id)
        queries[#queries+1] = id
        local s = spells[id]; if not s then return end
        if s.fail then error("temporary API failure") end
        return {spellID=id,name=s.name or "治疗术",castTime=s.cast}
    end,
    GetSpellDescription=function(id) return spells[id] and spells[id].description end,
    GetSpellPowerCost=function(id)
        costReads=costReads+1
        local s=spells[id]
        if s and s.costError then error("cost data unavailable") end
        return s and s.costs
    end,
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
UnitChannelInfo = function(unit)
    eq(unit,"player"); channelReads=channelReads+1
    if not channel then return end
    if channel.fail then error("channel not ready") end
    return "苦修","苦修",1,channel.startMS,channel.endMS,false,false,channel.id
end
CreateFrame = function(kind, name, parent, template)
    local f = {events={},scripts={},kind=kind,name=name,parent=parent,shown=true,width=0,height=0,text=""}
    if name then _G[name]=f end
    function f:RegisterEvent(event) self.events[event]=true end
    function f:RegisterUnitEvent(event, unit) self.events[event]=unit end
    function f:UnregisterEvent(event) self.events[event]=nil end
    function f:UnregisterAllEvents() self.events={} end
    function f:SetScript(event, fn) self.scripts[event]=fn end
    function f:SetSize(w,h) self.width=w; self.height=h end
    function f:SetWidth(w) self.width=w end
    function f:SetHeight(h) self.height=h end
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
    function f:SetFrameStrata(strata) self.strata=strata end
    function f:SetMovable(value) self.movable=value end
    function f:EnableMouse(value) self.mouse=value end
    function f:StartMoving() self.moving=true end
    function f:StopMovingOrSizing() self.moving=false end
    function f:SetUserPlaced(value) self.userPlaced=value end
    function f:SetAlpha(value) self.alpha=value end
    function f:GetEffectiveScale() return self.scale or 1 end
    function f:GetCenter() return self.x or 200,self.y or 300 end
    function f:IsShown() return self.shown end
    function f:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
    function f:Show()
        local changed=not self.shown; self.shown=true
        if changed and self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    function f:Hide()
        local changed=self.shown; self.shown=false
        if changed and self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    function f:SetShown(shown) if shown then self:Show() else self:Hide() end end
    function f:Click(key)
        if kind=="CheckButton" then self:SetChecked(not self:GetChecked()) end
        if self.scripts.OnClick then self.scripts.OnClick(self,key or "LeftButton") end
    end
    function f:SetTexture(value) self.texture=value end
    function f:SetTexCoord(...) self.texCoord={...} end
    function f:SetDesaturated(value) self.desaturated=value end
    function f:CreateTexture(name,layer,_,sublayer)
        local frame=CreateFrame("Texture",name,self)
        frame.layer=layer; frame.sublayer=sublayer
        return frame
    end
    function f:CreateFontString() return CreateFrame("FontString",nil,self) end
    function f:CreateAnimationGroup()
        local group={plays=0,playing=false}
        function group:SetLooping(value) self.looping=value end
        function group:Play() self.plays=self.plays+1; self.playing=true end
        function group:Stop() self.playing=false end
        function group:IsPlaying() return self.playing end
        function group:CreateAnimation(animationType)
            local animation={kind=animationType}
            function animation:SetFromAlpha(value) self.from=value end
            function animation:SetToAlpha(value) self.to=value end
            function animation:SetDuration(value) self.duration=value end
            function animation:SetSmoothing(value) self.smoothing=value end
            self.animation=animation
            return animation
        end
        self.animation=group
        return group
    end
    for _,method in ipairs({"SetBackdrop","SetBackdropColor","SetAllPoints","RegisterForDrag",
        "SetClampedToScreen","RegisterForClicks","SetHighlightTexture","SetBlendMode",
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
        -- Native rebuilding discards cached tooltipData and calls the original getter again.
        local spell=info.tooltipData and spells[info.tooltipData.id]
        if spell and spell.freshTooltip then info.tooltipData=spell.freshTooltip end
        self:ClearLines(); self.info=info; self.data=info.tooltipData; self.processingInfo=info
        self:AddLine("技能名称")
        for _,line in ipairs(self.data.lines) do if line.leftText then self:AddLine(line.leftText) end end
        for _,callback in ipairs(callbacks) do callback(self,self.data) end
        self:Show()
    end
    return t
end
GameTooltip = newTooltip("GameTooltip")
local function event(name, unit, ...)
    for _,frame in ipairs(frames) do
        local registered=frame.events[name]
        if (registered==true or (unit and registered==unit)) and frame.scripts.OnEvent then
            frame.scripts.OnEvent(frame,name,unit,...)
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
test("Greater Heal screenshot displays the range as blue healing only",function()
    local description="施法缓慢的法术，可以为单一目标治疗881到982点伤害。"
    fixture(1060,description,2600,370)
    local t,n=hover(1060,"GetAction")
    eq(t:NumLines(),n+1)
    eq(last(t),"效率：|cff66b3ff治疗 1.17|r")
    local amount,kind=effect(description,"zhCN")
    eq(amount,931.5); eq(kind,"healing")
    local wrapped=description:gsub("治疗881","治\n疗881")
    eq(last(hover(1060,"GetAction",wrapped)),"效率：|cff66b3ff治疗 1.17|r")
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
test("repeated hovers retain only character settings and no history",function()
    for i=1,1000 do
        local t,n=hover(i%2==0 and 1001 or 1002,"GetAction")
        eq(t:NumLines(),n+1)
    end
    local count=0
    for key in pairs(SpellEfficiencyDB) do
        assert(key=="enabled" or key=="timeWeight" or key=="minimapAngle" or key=="manaRegen"
            or key=="vialX" or key=="vialY")
        count=count+1
    end
    eq(count,6)
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
    local rebuilds=t.rebuilds or 0
    local panel=SpellEfficiencySettingsFrame
    panel.enabled:SetChecked(false); panel.weight:SetText("0.8"); panel.apply:Click()
    eq(SpellEfficiencyDB.enabled,false)
    eq(t:NumLines(),n); eq(t.rebuilds,rebuilds+1); eq(#queries,count)
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
local function reload(saved, alreadyLoggedIn)
    SpellEfficiencyDB=saved; loggedIn=alreadyLoggedIn or false; callbacks={}; frames={}; A={}
    GameTooltip=newTooltip("GameTooltip"); UISpecialFrames={}
    SpellEfficiencyMinimapButton=nil; SpellEfficiencySettingsFrame=nil
    SpellEfficiencyManaRegenBar=nil
    for line in io.lines(PROJECT_ROOT .. "/SpellEfficiency/SpellEfficiency.toc") do
        if line:match("%.lua$") then assert(loadfile(PROJECT_ROOT .. "/SpellEfficiency/" .. line))("SpellEfficiency",A) end
    end
    eq(SpellEfficiencyDB,saved)
    event("ADDON_LOADED","SpellEfficiency")
    if not loggedIn then loggedIn=true; event("PLAYER_LOGIN") end
end
test("settings reload preserves existing choices and defaults the new monitor off",function()
    reload({enabled=false,timeWeight=0.25,minimapAngle=90})
    eq(SpellEfficiencyDB.enabled,false); eq(SpellEfficiencyDB.timeWeight,0.25)
    eq(SpellEfficiencyDB.manaRegen,false)
    near(SpellEfficiencyMinimapButton.point[5],78)
    SpellEfficiencyMinimapButton:Click(); local panel=SpellEfficiencySettingsFrame
    eq(panel.enabled:GetChecked(),false); eq(panel.weight:GetText(),"0.25")
    local t,n=hover(1004); eq(t:NumLines(),n)
    reload({enabled="bad",timeWeight=2,minimapAngle=math.huge,manaRegen="yes"})
    eq(SpellEfficiencyDB.enabled,true); eq(SpellEfficiencyDB.timeWeight,0.8)
    eq(SpellEfficiencyDB.minimapAngle,225)
    eq(SpellEfficiencyDB.manaRegen,false)
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
end)

test("regrowth healing continuation contributes the complete second effect",function()
    for _,unit in ipairs({"sec","second","seconds"}) do
        local effects,reason=L.Effects("Heals a friendly target for 90 to 110 and another 140 over 21 " .. unit .. ".","enUS")
        eq(reason,nil); eq(effects.healing,240); eq(effects.damage,nil)
    end
    for _,text in ipairs({
        "Heals a friendly target for 100 and another 40% over 21 sec.",
        "Heals a friendly target for 100 and another 1.4k over 21 sec.",
        "Heals a friendly target for 100 and another 140 over 0 sec.",
        "Causes 100 Nature damage and another 140 over 21 sec.",
    }) do
        local value,reason=L.Effects(text,"enUS"); eq(value,nil); eq(reason,"unsupported")
    end
end)
test("rebirth descriptions are never counted as combat healing",function()
    for _,case in ipairs({
        {"使一个死去的目标复生，并为其恢复400点生命值。","zhCN"},
        {"Returns a dead target to life and heals the target for 400 health.","enUS"},
    }) do
        local value,reason=L.Effects(case[1],case[2]); eq(value,nil); eq(reason,"not_applicable")
    end
    local effects=L.Effects("Causes 100 Holy damage to an undead target.","enUS")
    eq(effects.damage,100)
end)
test("insect swarm hit penalties do not hide genuinely conditional damage",function()
    local text="The target is swarmed by insects, decreasing their chance to hit by 2% and causing 180 Nature damage over 12 sec."
    local effects,reason=L.Effects(text,"enUS"); eq(reason,nil); eq(effects.damage,180)
    for _,case in ipairs({
        {"使目标命中几率降低2%，有20%的几率造成100点自然伤害。","zhCN"},
        {"Decreasing their chance to hit by 2% and a 20% chance to cause 100 Nature damage.","enUS"},
    }) do
        effects,reason=L.Effects(case[1],case[2]); eq(effects,nil); eq(reason,"unsupported")
    end
end)
test("resource classification respects active form costs and excludes nonmana",function()
    for _,costs in ipairs({{{type=1,cost=15}},{{type=3,cost=40}},{{type=3,cost=0}},
        {{type=3,cost=35},{type=4,cost=5}},{{type=0,cost=0},{type=3,cost=40}},
        {{type=0,cost=100},{type=1,cost=15}}}) do
        local value,reason=L.ManaCost(costs); eq(value,nil); eq(reason,"not_applicable")
    end
    local costs={{type=0,cost=100},{type=3,cost=40,requiredAuraID=7,hasRequiredAura=false}}
    eq(L.ManaCost(costs),100)
    costs[2].hasRequiredAura=true
    local value,reason=L.ManaCost(costs); eq(value,nil); eq(reason,"not_applicable")
    for _,bad in ipairs({{}, {type=secret,cost=40}, {type="3",cost=40}}) do
        value,reason=L.ManaCost({{type=0,cost=100},bad}); eq(value,nil); eq(reason,nil)
    end
end)
test("druid login enables one minimap entry and restores character settings",function()
    playerClass="DRUID"; reload({enabled=false,timeWeight=0.5,minimapAngle=90})
    assert(SpellEfficiencyMinimapButton,"druid minimap entry missing"); eq(#callbacks,1)
    SpellEfficiencyMinimapButton:Click()
    eq(SpellEfficiencySettingsFrame.weight:GetText(),"0.5")
    eq(SpellEfficiencySettingsFrame.enabled:GetChecked(),false)
    near(SpellEfficiencyMinimapButton.point[5],78)
    local t,n=hover(1004); eq(t:NumLines(),n)
    SpellEfficiencyMinimapButton:Click("RightButton")
    eq(last(t),"效率：|cff66b3ff治疗 4.90|r")
    local saved=SpellEfficiencyDB; reload(saved,true)
    eq(SpellEfficiencyDB.timeWeight,0.5); eq(SpellEfficiencyDB.enabled,true); eq(#callbacks,1)
    event("ADDON_LOADED","UnrelatedAddon"); event("PLAYER_LOGIN"); eq(#callbacks,1)
    for _,frame in ipairs(frames) do eq(frame.scripts.OnUpdate,nil) end
    assert(A.Settings.Apply(true,0.8))
end)
-- Druid-shaped descriptions below use synthetic amounts and IDs, not a fixed live spell database.
test("druid healing ranks retain their own amounts costs and cast times",function()
    fixture(4101,"恢复友方目标220到260点生命值。",2000,60)
    fixture(4102,"恢复友方目标680到760点生命值。",3000,150)
    spells[4101].name="治疗之触"; spells[4102].name="治疗之触"
    eq(last(hover(4101,"GetSpellBookItem")),"效率：|cff66b3ff治疗 2.30|r")
    eq(last(hover(4102,"GetAction")),"效率：|cff66b3ff治疗 1.99|r"); eq(queries[#queries],4102)
    books[4102].spellID=4101; local t,n=hover(4102); books[4102].spellID=4102
    eq(t:NumLines(),n)
end)
test("druid balance spells include direct periodic and control damage per target",function()
    for _,case in ipairs({
        {4103,"对目标造成90到110点自然伤害。",2000,50,"1.15"},
        {4104,"对目标造成400到600点奥术伤害。",3500,100,"1.84"},
        {4105,"对目标造成60点奥术伤害，并在12秒内造成180点额外的奥术伤害。",0,60,"2.89"},
        {4106,"使目标命中几率降低2%，并在12秒内造成180点自然伤害。",0,60,"2.17"},
        {4107,"将目标缠绕在原地，并在12秒内造成60点自然伤害。",0,30,"1.45"},
    }) do
        fixture(case[1],case[2],case[3],case[4])
        eq(last(hover(case[1])),"效率：|cffff6666伤害 " .. case[5] .. "|r")
    end
end)
test("druid healing includes complete HoTs and direct plus periodic components",function()
    fixture(4110,"在12秒内恢复目标360点生命值。",0,90)
    eq(last(hover(4110)),"效率：|cff66b3ff治疗 2.89|r")
    fixture(4111,"立即恢复90到110点生命值，并在21秒内恢复140点生命值。",2000,60)
    eq(last(hover(4111)),"效率：|cff66b3ff治疗 2.30|r")
    local original=GetLocale; GetLocale=function() return "enUS" end
    local t=hover(4111,"GetAction","Heals a friendly target for 90 to 110 and another 140 over 21 sec.")
    GetLocale=original; eq(last(t),"效率：|cff66b3ff治疗 2.30|r")
end)
test("tranquility and hurricane count full channels without multiplying target count",function()
    fixture(4112,"每2秒为附近5名队友恢复100点生命值，持续8秒。",0,100)
    eq(last(hover(4112,"GetAction",nil,true)),"效率：|cff66b3ff治疗 0.76|r")
    fixture(4113,"每秒对目标区域内的所有敌人造成30点自然伤害，持续10秒。",0,100)
    eq(last(hover(4113,"GetAction",nil,true)),"效率：|cffff6666伤害 0.48|r")
end)
test("druid rage energy and combo skills are nonapplicable before effect parsing",function()
    fixture(4120,"造成150%的武器伤害。",0,100)
    for _,costs in ipairs({{{type=1,cost=15}},{{type=3,cost=40}},{{type=3,cost=0}},
        {{type=3,cost=35},{type=4,cost=5}},{{type=0,cost=0},{type=3,cost=40}}}) do
        spells[4120].costs=costs
        eq(last(hover(4120,"GetAction")),"效率：不适用")
    end
end)
test("druid form cost changes are reread without using the current power bar",function()
    fixture(4121,"造成240点自然伤害。",0,60)
    spells[4121].costs={{type=0,cost=60},{type=3,cost=40,requiredAuraID=7,hasRequiredAura=false}}
    UnitPowerType=function() error("the visible power bar does not determine a spell cost") end
    eq(last(hover(4121)),"效率：|cffff6666伤害 2.89|r")
    spells[4121].costs[2].hasRequiredAura=true
    eq(last(hover(4121)),"效率：不适用")
    spells[4121].costs[2].hasRequiredAura=false
    eq(last(hover(4121)),"效率：|cffff6666伤害 2.89|r")
    UnitPowerType=nil
end)
test("druid mana readiness and free casts cannot produce stale or infinite scores",function()
    fixture(4122,"恢复240点生命值。",2000,60)
    spells[4122].costs=nil; eq(last(hover(4122)),"效率：耗蓝未知")
    spells[4122].costs={}; eq(last(hover(4122)),"效率：耗蓝未知")
    spells[4122].costs={{type=0,cost=0}}; eq(last(hover(4122)),"效率：当前免耗蓝")
    spells[4122].costs={{type=0,cost=60}}; eq(last(hover(4122)),"效率：|cff66b3ff治疗 2.30|r")
    local t,n=hover(4122,"GetBagItem"); eq(t:NumLines(),n)
end)
test("druid haste and weight changes update one line and priest support remains",function()
    spellHaste=nil; eq(last(hover(4110)),"效率：|cff66b3ff治疗 2.89|r")
    spellHaste=50; local n=GameTooltip:NumLines(); event("UNIT_SPELL_HASTE","player")
    eq(last(GameTooltip),"效率：|cff66b3ff治疗 4.00|r"); eq(GameTooltip:NumLines(),n)
    spellHaste=0; assert(A.Settings.Apply(true,0))
    eq(last(hover(4102)),"效率：|cff66b3ff治疗 4.80|r")
    assert(A.Settings.Apply(true,1)); eq(last(GameTooltip),"效率：|cff66b3ff治疗 1.60|r")
    playerClass="PRIEST"; reload(nil)
    eq(last(hover(1004)),"效率：|cff66b3ff治疗 4.34|r"); eq(#callbacks,1)
end)
-- Chinese text and first-rank amounts supplied by the user's Forever screenshot.
local penanceCN="向目标施放圣光能量，立即对一名敌人造成52点神圣伤害，或为一名盟友恢复144点生命值，并在接下来的2秒内每1秒重复一次效果。"
local penanceEN="Launches a volley of holy light at the target, causing 52 Holy damage to an enemy, or 144 healing to an ally, instantly and every 1 sec for 2 sec."

test("penance screenshot includes the initial bolt and two repeated bolts",function()
    local effects,reason,seconds=L.Effects(penanceCN,"zhCN")
    eq(reason,nil); eq(effects.healing,432); eq(effects.damage,156); eq(effects.absorb,nil); eq(seconds,2)
end)

test("English penance shares its timing across alternative healing and damage",function()
    for _,locale in ipairs({"enUS","enGB"}) do
        local effects,reason,seconds=L.Effects("  " .. penanceEN:gsub(", ",",\n") .. "  ",locale)
        eq(reason,nil); eq(effects.healing,432); eq(effects.damage,156); eq(seconds,2)
    end
end)

test("penance keeps range means formatting and current effect magnitudes",function()
    local text=penanceCN:gsub("52","50到54"):gsub("144","|cffffffff1,000至1,400|r")
        :gsub("施放","释放"):gsub("，","，\n")
    local effects,reason,seconds=L.Effects(text,"zhCN")
    eq(reason,nil); eq(effects.healing,3600); eq(effects.damage,156); eq(seconds,2)
    effects,reason,seconds=L.Effects(penanceEN:gsub("52","50 to 54"):gsub("144","140-148"),"enUS")
    eq(reason,nil); eq(effects.healing,432); eq(effects.damage,156); eq(seconds,2)
end)

test("initial bolt counts derive from the stated duration and interval",function()
    local effects,reason,seconds=L.Effects(penanceCN:gsub("2秒内每1秒","4秒内每2秒"),"zhCN")
    eq(reason,nil); eq(effects.healing,432); eq(effects.damage,156); eq(seconds,4)
    effects,reason,seconds=L.Effects(penanceEN:gsub("every 1 sec","every 0.5 sec"),"enUS")
    eq(reason,nil); eq(effects.healing,720); eq(effects.damage,260); eq(seconds,2)
end)

test("incomplete or ambiguous penance never becomes a partial estimate",function()
    for _,case in ipairs({
        {penanceCN:gsub("每1秒","每0秒"),"zhCN"},
        {penanceCN:gsub("2秒内","0秒内"),"zhCN"},
        {penanceCN:gsub("每1秒","每1.5秒"),"zhCN"},
        {penanceCN:gsub("每1秒","每3秒"),"zhCN"},
        {penanceCN:gsub("144点生命值","144%%生命值"),"zhCN"},
        {penanceCN:gsub("52点","52万点"),"zhCN"},
        {penanceCN:gsub("52点","52+100点"),"zhCN"},
        {penanceCN:gsub("立即",""),"zhCN"},
        {penanceCN:gsub("，并在接下来.*","。"),"zhCN"},
        {penanceCN .. "并额外恢复100点生命值。","zhCN"},
        {penanceEN:gsub("every 1 sec","every 0 sec"),"enUS"},
        {penanceEN:gsub("for 2 sec","for 0 sec"),"enUS"},
        {penanceEN:gsub("for 2 sec","for 2.5 sec"),"enUS"},
        {penanceEN:gsub("144 healing","144%% healing"),"enUS"},
        {penanceEN:gsub("52 Holy","52k Holy"),"enUS"},
        {penanceEN:gsub("144 healing","144 + 200 healing"),"enUS"},
        {penanceEN:gsub("instantly and ",""),"enUS"},
        {penanceEN:gsub(", instantly.*","."),"enUS"},
        {penanceEN .. " Heals you for 100 health.","enUS"},
        {penanceEN:gsub("52 Holy",string.rep("9",310) .. " Holy"),"enUS"},
    }) do
        local effects,reason=L.Effects(case[1],case[2]); eq(effects,nil); eq(reason,"unsupported")
    end
end)

test("penance hover shows complete blue healing and red damage on one line",function()
    fixture(5001,penanceCN,0,150); spells[5001].name="苦修"
    local t,n=hover(5001,"GetSpellBookItem",nil,true)
    eq(last(t),"效率：|cff66b3ff治疗 1.65|r  |cffff6666伤害 0.60|r"); eq(t:NumLines(),n+1)
    callbacks[1](t,t.data); eq(t:NumLines(),n+1)
    local original=GetLocale; GetLocale=function() return "enUS" end
    t=hover(5001,"GetAction",penanceEN,true); GetLocale=original
    eq(last(t),"效率：|cff66b3ff治疗 1.65|r  |cffff6666伤害 0.60|r")
end)

test("penance ranks use the displayed description and their own mana costs",function()
    fixture(5002,penanceCN:gsub("52点","100点"):gsub("144点","250点"),0,250)
    spells[5002].name="苦修"
    eq(last(hover(5002,"GetAction",nil,true)),"效率：|cff66b3ff治疗 1.72|r  |cffff6666伤害 0.69|r")
    eq(queries[#queries],5002)
    eq(last(hover(5001,"GetAction",nil,true)),"效率：|cff66b3ff治疗 1.65|r  |cffff6666伤害 0.60|r")
    local t=hover(5002,"GetAction",penanceCN,true)
    eq(last(t),"效率：|cff66b3ff治疗 0.99|r  |cffff6666伤害 0.36|r")
end)

test("penance uses the configured time weight for its complete channel",function()
    local t,n=hover(5001,"GetAction",nil,true)
    assert(A.Settings.Apply(true,0))
    eq(last(t),"效率：|cff66b3ff治疗 2.88|r  |cffff6666伤害 1.04|r"); eq(t:NumLines(),n+1)
    assert(A.Settings.Apply(true,1))
    eq(last(t),"效率：|cff66b3ff治疗 1.44|r  |cffff6666伤害 0.52|r"); eq(t:NumLines(),n+1)
    assert(A.Settings.Apply(true,0.8))
    eq(last(t),"效率：|cff66b3ff治疗 1.65|r  |cffff6666伤害 0.60|r")
end)

test("penance timing honors client channel headers without applying haste twice",function()
    spellHaste=nil; local t,n=hover(5001,"GetAction",nil,true)
    eq(last(t),"效率：|cff66b3ff治疗 1.65|r  |cffff6666伤害 0.60|r")
    spellHaste=50; event("UNIT_SPELL_HASTE","player")
    eq(last(t),"效率：|cff66b3ff治疗 1.65|r  |cffff6666伤害 0.60|r"); eq(t:NumLines(),n+1)
    -- Synthetic client-supplied duration: use it, while retaining the three stated bolts.
    t.data.lines[2].leftText="需引导（1秒）"; callbacks[1](t,t.data)
    eq(last(t),"效率：|cff66b3ff治疗 2.88|r  |cffff6666伤害 1.04|r")
    spellHaste=0; event("UNIT_SPELL_HASTE","player")
    eq(last(t),"效率：|cff66b3ff治疗 2.08|r  |cffff6666伤害 0.75|r")
end)

test("penance failed reads clear old values and recover on the next hover",function()
    spells[5001].costs=nil
    eq(last(hover(5001,"GetAction",nil,true)),"效率：耗蓝未知")
    spells[5001].costs={{type=0,cost=0}}
    eq(last(hover(5001,"GetAction",nil,true)),"效率：当前免耗蓝")
    spells[5001].costs={{type=0,cost=150}}
    eq(last(hover(5001,"GetAction",penanceCN:gsub("每1秒","每0秒"),true)),"效率：无法估算")
    eq(last(hover(5001,"GetAction",nil,true)),"效率：|cff66b3ff治疗 1.65|r  |cffff6666伤害 0.60|r")
end)
-- Synthetic channel timestamps exercise the real event path; these are not live measurements.
local panelPenance="效率：|cff66b3ff治疗 1.65|r  |cffff6666伤害 0.60|r"
local measuredPenance="效率：|cff66b3ff治疗 1.98|r  |cffff6666伤害 0.71|r"
local function startPenance(id, seconds)
    channel={id=id,startMS=100000,endMS=100000+seconds*1000}
    event("UNIT_SPELLCAST_CHANNEL_START","player","cast-penance",id)
end

test("penance channel start uses the full millisecond span without applying haste again",function()
    fixture(5101,penanceCN,0,150); spellHaste=50
    local t,n=hover(5101,"GetAction",nil,true); eq(last(t),panelPenance)
    startPenance(5101,1.6)
    eq(last(t),measuredPenance); eq(t:NumLines(),n+1)
    channel=nil
    eq(last(hover(5101,"GetAction",nil,true)),measuredPenance)
end)

test("penance calibrates without a visible tooltip and keeps ranks separate",function()
    fixture(5102,penanceCN,0,150); fixture(5103,penanceCN,0,150)
    GameTooltip:Hide(); startPenance(5102,1.8); eq(GameTooltip:IsShown(),false); channel=nil
    eq(last(hover(5102,"GetAction",nil,true)),"效率：|cff66b3ff治疗 1.80|r  |cffff6666伤害 0.65|r")
    eq(last(hover(5101,"GetAction",nil,true)),measuredPenance)
    eq(last(hover(5103,"GetAction",nil,true)),panelPenance)
end)

test("haste changes invalidate penance calibration and the next cast refreshes the open line",function()
    local t,n=hover(5101,"GetAction",nil,true)
    spellHaste=25; event("UNIT_SPELL_HASTE","player")
    eq(last(t),panelPenance); eq(t:NumLines(),n+1)
    startPenance(5101,1.3); channel=nil
    eq(last(t),"效率：|cff66b3ff治疗 2.33|r  |cffff6666伤害 0.84|r"); eq(t:NumLines(),n+1)
end)

test("haste round trips while hidden do not resurrect old penance measurements",function()
    GameTooltip:Hide()
    spellHaste=0; event("UNIT_SPELL_HASTE","player")
    spellHaste=25; event("UNIT_SPELL_HASTE","player")
    eq(last(hover(5101,"GetAction",nil,true)),panelPenance)
    spellHaste=50; event("UNIT_SPELL_HASTE","player")
    eq(last(hover(5102,"GetAction",nil,true)),panelPenance)
end)

test("unchanged haste retains calibration while unseen haste changes invalidate it on hover",function()
    startPenance(5101,1.6); channel=nil
    local t,n=hover(5101,"GetAction",nil,true)
    event("UNIT_SPELL_HASTE","player"); eq(last(t),measuredPenance); eq(t:NumLines(),n+1)
    spellHaste=25; eq(last(hover(5101,"GetAction",nil,true)),panelPenance)
    spellHaste=50; eq(last(hover(5101,"GetAction",nil,true)),panelPenance)
end)

test("haste refresh reads new native tooltip data instead of an old channel header",function()
    local t,n=hover(5103,"GetAction",nil,true)
    spells[5103].freshTooltip={type=1,id=5103,lines={{type=34,leftText=penanceCN},
        {type=0,leftText="需引导（1.7秒）"}}}
    event("UNIT_SPELL_HASTE","player")
    eq(last(t),"效率：|cff66b3ff治疗 1.88|r  |cffff6666伤害 0.68|r"); eq(t:NumLines(),n+1)
    spells[5103].freshTooltip=nil
end)

test("invalid channel reads drop the old sample and recover on a later cast",function()
    for _,sample in ipairs({{}, {fail=true}, {id=5102,startMS=100000,endMS=101000},
        {id=5101,startMS=100000,endMS=100000}, {id=5101,startMS=100000,endMS=99999},
        {id=5101,startMS=secret,endMS=101600}, {id=secret,startMS=100000,endMS=101600},
        {id=5101,startMS=100000,endMS=math.huge}, {id=5101,startMS=0/0,endMS=101600}}) do
        startPenance(5101,1.6); eq(last(hover(5101,"GetAction",nil,true)),measuredPenance)
        channel=sample; event("UNIT_SPELLCAST_CHANNEL_START","player","cast-bad",5101)
        eq(last(GameTooltip),panelPenance)
    end
    local original=UnitChannelInfo; UnitChannelInfo=nil
    event("UNIT_SPELLCAST_CHANNEL_START","player","cast-no-api",5101)
    eq(last(GameTooltip),panelPenance); UnitChannelInfo=original
    startPenance(5101,1.6); channel=nil; eq(last(GameTooltip),measuredPenance)
end)

test("unknown haste can use an actual measurement but cannot reuse it after a haste event",function()
    spellHaste=nil; event("UNIT_SPELL_HASTE","player")
    startPenance(5101,1.6); channel=nil
    eq(last(hover(5101,"GetAction",nil,true)),measuredPenance)
    event("UNIT_SPELL_HASTE","player"); eq(last(GameTooltip),panelPenance)
    spellHaste=secret; startPenance(5101,1.6); channel=nil
    eq(last(GameTooltip),measuredPenance)
    spellHaste=50; event("UNIT_SPELL_HASTE","player"); eq(last(GameTooltip),panelPenance)
end)

test("pushback interruption and channel stop do not turn a partial cast into full output",function()
    startPenance(5101,1.6)
    channel.endMS=100400
    event("UNIT_SPELLCAST_CHANNEL_UPDATE","player","cast-penance",5101)
    event("UNIT_SPELLCAST_INTERRUPTED","player","cast-penance",5101)
    channel=nil; event("UNIT_SPELLCAST_CHANNEL_STOP","player","cast-penance",5101)
    eq(last(hover(5101,"GetAction",nil,true)),measuredPenance)
end)

test("other units unknown ranks and nonpenance channels cannot calibrate penance",function()
    local count=channelReads
    event("UNIT_SPELLCAST_CHANNEL_START","target","cast-target",5101)
    event("UNIT_SPELLCAST_CHANNEL_START","player","cast-secret",secret)
    event("UNIT_SPELLCAST_CHANNEL_START","player","cast-unknown",999999)
    eq(channelReads,count)
    startPenance(1003,1); channel=nil
    eq(last(hover(1003,"GetAction",nil,true)),"效率：|cffff6666伤害 2.49|r")
    eq(last(hover(5101,"GetAction",nil,true)),measuredPenance)
    books[5102].isPassive=true; startPenance(5102,1); channel=nil; books[5102].isPassive=false
    eq(last(hover(5102,"GetAction",nil,true)),panelPenance)
end)

test("disabled efficiency does not query channels or keep old calibration",function()
    assert(A.Settings.Apply(false,0.8)); local count=channelReads
    startPenance(5101,1); channel=nil; eq(channelReads,count)
    assert(A.Settings.Apply(true,0.8))
    eq(last(hover(5101,"GetAction",nil,true)),panelPenance)
end)

test("calibrated penance still respects GCD weight and one line across repeated hovers",function()
    startPenance(5101,0.7); channel=nil
    local t,n=hover(5101,"GetAction",nil,true)
    eq(last(t),"效率：|cff66b3ff治疗 2.88|r  |cffff6666伤害 1.04|r")
    startPenance(5101,1.6); channel=nil
    assert(A.Settings.Apply(true,0)); eq(last(t),"效率：|cff66b3ff治疗 2.88|r  |cffff6666伤害 1.04|r")
    assert(A.Settings.Apply(true,1)); eq(last(t),"效率：|cff66b3ff治疗 1.80|r  |cffff6666伤害 0.65|r")
    assert(A.Settings.Apply(true,0.8))
    for i=1,10 do callbacks[1](t,t.data); eq(last(t),measuredPenance); eq(t:NumLines(),n+1) end
    event("PLAYER_LOGOUT")
    local count=0; for key in pairs(SpellEfficiencyDB) do
        assert(key=="enabled" or key=="timeWeight" or key=="minimapAngle" or key=="manaRegen"
            or key=="vialX" or key=="vialY"); count=count+1
    end
    eq(count,6)
    for _,frame in ipairs(frames) do eq(frame.scripts.OnUpdate,nil) end
    spellHaste=0
end)
test("mana users outside the tooltip class list can enable the monitor",function()
    playerClass="MAGE"; reload(nil)
    assert(SpellEfficiencyMinimapButton,"mana users need the minimap settings entry")
    eq(#callbacks,0); eq(SpellEfficiencyManaRegenBar,nil)
    local reads=costReads
    event("UNIT_SPELLCAST_SUCCEEDED","player","before-enable",1004)
    eq(costReads,reads)
    SpellEfficiencyMinimapButton:Click()
    local panel=SpellEfficiencySettingsFrame
    eq(panel.enabled,nil); eq(panel.weight,nil); eq(panel.manaRegen:GetChecked(),false)
    panel.manaRegen:Click()
    eq(SpellEfficiencyDB.manaRegen,true)
    eq(SpellEfficiencyManaRegenBar:IsShown(),true)
    eq(SpellEfficiencyManaRegenBar.scripts.OnUpdate,nil)
    SpellEfficiencyMinimapButton:Click("RightButton")
    eq(panel.manaRegen:GetChecked(),false)
    eq(SpellEfficiencyManaRegenBar:IsShown(),false)
end)

local function vialTextures()
    local vial=SpellEfficiencyManaRegenBar
    local liquid, halo
    for _,frame in ipairs(frames) do
        if frame.parent==vial and frame.kind=="Texture" then
            if frame.layer=="ARTWORK" and not frame.sublayer then liquid=frame end
            if frame.layer=="BACKGROUND" and frame.sublayer==-1 then halo=frame end
        end
    end
    assert(liquid and halo,"vial needs liquid and a separate glow")
    return liquid,halo
end

local function manaRemaining()
    if not SpellEfficiencyManaRegenBar.scripts.OnUpdate then return 0 end
    local liquid=vialTextures()
    if not liquid:IsShown() then return 5 end
    return math.floor((1 - liquid.height/62)*50 + 0.5)/10
end

local function stepTimer(at)
    now=at
    local bar=SpellEfficiencyManaRegenBar
    if bar.scripts.OnUpdate then bar.scripts.OnUpdate(bar) end
    return manaRemaining()
end

local function sendCast(guid, id)
    event("UNIT_SPELLCAST_SENT","player","",guid,id)
end

local function succeed(guid, id)
    event("UNIT_SPELLCAST_SUCCEEDED","player",guid,id)
end

test("characters without a mana pool have no monitor even with a saved toggle",function()
    playerClass="WARRIOR"; maxMana=0; reload({manaRegen=true})
    event("PLAYER_ENTERING_WORLD")
    eq(SpellEfficiencyMinimapButton,nil); eq(SpellEfficiencyManaRegenBar,nil); eq(#callbacks,0)
    for _,frame in ipairs(frames) do eq(frame.events.UNIT_SPELLCAST_SUCCEEDED,nil) end
end)

test("a protected or pending mana maximum is checked again on entering the world",function()
    playerClass="SHAMAN"; maxMana=secret; reload({manaRegen=true})
    eq(SpellEfficiencyMinimapButton,nil); eq(SpellEfficiencyManaRegenBar,nil)
    maxMana=1800; event("PLAYER_ENTERING_WORLD")
    assert(SpellEfficiencyMinimapButton); eq(SpellEfficiencyManaRegenBar:IsShown(),true); eq(#callbacks,0)
    local bar=SpellEfficiencyManaRegenBar
    event("PLAYER_ENTERING_WORLD"); eq(SpellEfficiencyManaRegenBar,bar)
end)

test("druid forms and empty mana keep the same monitor while energy casts do not reset it",function()
    playerClass="DRUID"; maxMana=1400; now=100
    local previousPower=UnitPower
    UnitPower=function() manaReads=manaReads+1; return 0 end
    UnitPowerType=function() return 3 end
    local reads=manaReads
    reload({manaRegen=true}); eq(#callbacks,1)
    local bar=SpellEfficiencyManaRegenBar
    eq(bar:IsShown(),true)
    fixture(6101,"造成100点伤害。",0,80)
    fixture(6102,"造成100点伤害。",0,50); spells[6102].costs={{type=3,cost=50}}
    succeed("cast-form",6101); eq(manaRemaining(),5)
    stepTimer(102); UnitPowerType=function() return 1 end; event("UNIT_DISPLAYPOWER","player")
    succeed("cast-energy",6102); eq(manaRemaining(),3); eq(manaReads,reads)
    eq(SpellEfficiencyManaRegenBar,bar)
    UnitPower=previousPower; UnitPowerType=nil
end)

test("successful casts start five seconds and new spending restarts the same bar",function()
    playerClass="PRIEST"; now=100; reload({manaRegen=true})
    local bar=SpellEfficiencyManaRegenBar
    sendCast("cast-read",6101); event("UNIT_SPELLCAST_START","player","cast-read",6101)
    eq(bar.scripts.OnUpdate,nil)
    stepTimer(102); succeed("cast-read",6101)
    eq(manaRemaining(),5)
    eq(stepTimer(104),3)
    succeed("cast-instant",6101); eq(manaRemaining(),5)
    eq(stepTimer(107),2)
    eq(stepTimer(108.95),0.1)
    eq(stepTimer(109),0); eq(bar.scripts.OnUpdate,nil)
end)

test("cancelled casts, potions and zero cost spells leave the existing deadline alone",function()
    now=120; succeed("cast-paid",6101); stepTimer(121)
    fixture(6103,"恢复100点法力值。",0,0)
    fixture(6104,"恢复法力药水。",0,0); spells[6104].costs=nil
    succeed("cast-free",6103); succeed("cast-potion",6104)
    sendCast("cast-cancelled",6101); event("UNIT_SPELLCAST_START","player","cast-cancelled",6101)
    event("UNIT_SPELLCAST_INTERRUPTED","player","cast-cancelled",6101)
    event("UNIT_SPELLCAST_STOP","player","cast-cancelled",6101)
    eq(stepTimer(124),1); eq(stepTimer(125),0)
end)

test("a consumed free-cast aura still applies to its matched instant and cast-time spell",function()
    fixture(6105,"恢复100点生命值。",0,100)
    local costs={{type=0,cost=100},{type=0,cost=0,requiredAuraID=999,hasRequiredAura=true}}
    spells[6105].costs=costs
    for _,isCastTime in ipairs({false,true}) do
        local guid=isCastTime and "zero-cast-time" or "zero-instant"
        costs[2].hasRequiredAura=true
        sendCast(guid,6105)
        if isCastTime then event("UNIT_SPELLCAST_START","player",guid,6105) end
        costs[2].hasRequiredAura=false
        succeed(guid,6105)
        eq(SpellEfficiencyManaRegenBar.scripts.OnUpdate,nil)
    end
    succeed("paid-after-proc",6105); eq(manaRemaining(),5)
end)

test("a queued spell keeps its own cost and is refreshed when its cast actually starts",function()
    now=150; reload({manaRegen=true})
    local costs=spells[6105].costs; costs[2].hasRequiredAura=true
    sendCast("previous-free",6105); event("UNIT_SPELLCAST_START","player","previous-free",6105)
    sendCast("queued",6105)
    costs[2].hasRequiredAura=false
    succeed("previous-free",6105); eq(SpellEfficiencyManaRegenBar.scripts.OnUpdate,nil)
    event("UNIT_SPELLCAST_START","player","queued",6105)
    succeed("queued",6105); eq(manaRemaining(),5)
end)

test("one channel uses its first spend regardless of success event order and interruption",function()
    fixture(6106,"在3秒内造成600点暗影伤害。",0,150)
    playerClass="MAGE"; now=160; reload({manaRegen=true})
    sendCast("channel-first",6106)
    event("UNIT_SPELLCAST_CHANNEL_START","player","channel-first",6106)
    eq(manaRemaining(),5)
    stepTimer(161); succeed("channel-first",6106)
    eq(manaRemaining(),4)
    event("UNIT_SPELLCAST_CHANNEL_UPDATE","player","channel-first",6106)
    event("UNIT_SPELLCAST_CHANNEL_STOP","player","channel-first",6106)
    eq(stepTimer(165),0)
    stepTimer(170); succeed("success-first",6106)
    stepTimer(171); event("UNIT_SPELLCAST_CHANNEL_START","player","success-first",6106)
    eq(manaRemaining(),4); eq(stepTimer(175),0)
end)

test("only confirmed up-front mana spending starts the timer, including mixed costs",function()
    now=180
    fixture(6107,"造成100点伤害。",0,100)
    for i,costs in ipairs({{{type=-2,cost=40}},{{type=0,cost=0,costPerSec=10}},
        {{type=0,cost=100,requiredAuraID=1,hasRequiredAura=false}}}) do
        spells[6107].costs=costs
        succeed("no-initial-mana-" .. i,6107); eq(SpellEfficiencyManaRegenBar.scripts.OnUpdate,nil)
    end
    spells[6107].costs={{type=-2,cost=40},{type=0,cost=20,costPerSec=10}}
    succeed("mixed-mana",6107); eq(manaRemaining(),5)
end)

test("inaccessible cast fields and cost errors do not restart the timer, and the next cast recovers",function()
    now=190; reload({manaRegen=true})
    local bar=SpellEfficiencyManaRegenBar
    local reads=costReads
    event("UNIT_SPELLCAST_SUCCEEDED","party1","other",6101)
    succeed(secret,6101); succeed("locked-id",secret); succeed(nil,6101)
    eq(costReads,reads)
    fixture(6108,"造成100点伤害。",0,100); spells[6108].costError=true
    sendCast("error",6108); succeed("error",6108)
    eq(bar.scripts.OnUpdate,nil)
    spells[6108].costError=false; spells[6108].costs={{type=0,cost=secret}}
    succeed("hidden-cost",6108); eq(bar.scripts.OnUpdate,nil)
    spells[6108].costs={{type=0,cost=30}}
    succeed("ok",6108); eq(manaRemaining(),5)
end)

test("the monitor switch acts independently and reload persists only the preference",function()
    playerClass="PRIEST"; now=200; reload({enabled=true,timeWeight=0.6,manaRegen=true})
    succeed("paid-before-toggle",6101); eq(manaRemaining(),5)
    SpellEfficiencyMinimapButton:Click("RightButton")
    eq(SpellEfficiencyDB.enabled,false); eq(SpellEfficiencyDB.manaRegen,true)
    eq(stepTimer(201),4)
    SpellEfficiencyMinimapButton:Click(); local panel=SpellEfficiencySettingsFrame
    panel.weight:SetText("0.4")
    panel.manaRegen:Click()
    local bar=SpellEfficiencyManaRegenBar
    eq(SpellEfficiencyDB.manaRegen,false); eq(bar:IsShown(),false); eq(next(bar.events),nil)
    eq(bar.scripts.OnUpdate,nil); eq(panel.weight:GetText(),"0.4"); eq(SpellEfficiencyDB.timeWeight,0.6)
    local reads=costReads; succeed("paid-disabled",6101); eq(costReads,reads)
    panel.manaRegen:Click()
    local _,halo=vialTextures()
    eq(halo:IsShown(),true); eq(bar.scripts.OnUpdate,nil)
    succeed("paid-before-reload",6101); eq(manaRemaining(),5)
    reload(SpellEfficiencyDB,true)
    eq(SpellEfficiencyDB.enabled,false); eq(SpellEfficiencyDB.manaRegen,true)
    _,halo=vialTextures()
    eq(halo:IsShown(),true); eq(SpellEfficiencyManaRegenBar.scripts.OnUpdate,nil)
end)

test("mana vial fills upward, glows only when full and clears instantly on spending",function()
    now=210; reload({manaRegen=true})
    local vial=SpellEfficiencyManaRegenBar
    eq(vial.width,48); eq(vial.height,96)
    local liquid,halo=vialTextures()
    local textureFile=assert(liquid.texture:match("([^\\\\]+)$"))
    local atlas=assert(io.open(PROJECT_ROOT .. "/SpellEfficiency/" .. textureFile,"rb"))
    atlas:close()
    near(liquid.height,62); eq(halo:IsShown(),true); eq(halo.animation.plays,1)
    succeed("first-vial",6101)
    eq(liquid:IsShown(),false); eq(halo:IsShown(),false)
    stepTimer(212.5)
    eq(liquid:IsShown(),true); eq(halo:IsShown(),false)
    near(liquid.height,31); eq(liquid.point[1],"BOTTOM"); eq(liquid.point[5],-84)
    near(liquid.texCoord[3],53/96); near(liquid.texCoord[4],84/96)
    stepTimer(215)
    near(liquid.height,62); eq(halo:IsShown(),true); eq(vial.scripts.OnUpdate,nil)
    eq(halo.animation.plays,2); eq(halo.animation.looping,"BOUNCE")
    eq(halo.animation.animation.kind,"Alpha"); eq(halo.animation.animation.duration,1)
    stepTimer(216); eq(halo.animation.plays,2)
    succeed("second-vial",6101)
    eq(liquid:IsShown(),false); eq(halo:IsShown(),false)
    eq(halo.animation.playing,false); eq(manaRemaining(),5)
end)

test("the mana vial has no text in any state",function()
    now=220; reload({manaRegen=true})
    local vial=SpellEfficiencyManaRegenBar
    for _,frame in ipairs(frames) do
        assert(frame.parent~=vial or frame.kind~="FontString","the vial must be icon-only")
    end
end)

test("opening defaults to a full vial without tracking any closed-session casts",function()
    playerClass="MAGE"; now=230; reload(nil)
    local reads,currentManaReads=costReads,manaReads
    eq(SpellEfficiencyManaRegenBar,nil)
    for _,frame in ipairs(frames) do eq(frame.events.UNIT_SPELLCAST_SUCCEEDED,nil) end
    event("UNIT_SPELLCAST_SUCCEEDED","player","cast-while-closed",6101)
    SpellEfficiencyMinimapButton:Click("RightButton")
    local vial=SpellEfficiencyManaRegenBar
    local liquid,halo=vialTextures()
    eq(halo:IsShown(),true); near(liquid.height,62)
    eq(halo.animation.plays,1); eq(vial.scripts.OnUpdate,nil)
    eq(costReads,reads); eq(manaReads,currentManaReads)
end)

test("dragging in settings persists the position and locks on closing",function()
    playerClass="PRIEST"; now=300; reload({manaRegen=true,vialX="bad",vialY=-999})
    local vial=SpellEfficiencyManaRegenBar
    eq(vial.point[4],0); eq(vial.point[5],-118); eq(vial.mouse,false)
    vial.scripts.OnDragStart(vial); assert(not vial.moving)
    SpellEfficiencyMinimapButton:Click()
    eq(vial.mouse,true); eq(vial.strata,"DIALOG"); eq(vial.movable,true)
    vial.scripts.OnDragStart(vial)
    eq(vial.moving,true)
    vial.x,vial.y=147,369
    SpellEfficiencySettingsFrame:Hide()
    eq(vial.moving,false); eq(vial.mouse,false); eq(vial.strata,"MEDIUM")
    eq(vial.userPlaced,false)
    eq(SpellEfficiencyDB.vialX,-53); eq(SpellEfficiencyDB.vialY,69)
    eq(vial.point[2],UIParent); eq(vial.point[4],-53); eq(vial.point[5],69)
    reload(SpellEfficiencyDB,true)
    vial=SpellEfficiencyManaRegenBar
    eq(vial.point[4],-53); eq(vial.point[5],69); eq(vial.mouse,false)
end)

test("full vial glow stops when hidden and restarts only when visible and full",function()
    playerClass="MAGE"; now=310; reload({manaRegen=true})
    local vial=SpellEfficiencyManaRegenBar
    local _,halo=vialTextures()
    local pulse=halo.animation
    eq(pulse.playing,true); eq(pulse.plays,1); eq(vial.scripts.OnUpdate,nil)
    vial:Hide()
    eq(pulse.playing,false); eq(halo:IsShown(),true)
    vial:Show()
    eq(pulse.playing,true); eq(pulse.plays,2)
    succeed("paid-before-hide",6101)
    eq(pulse.playing,false); eq(halo:IsShown(),false)
    vial:Hide(); now=313; vial:Show()
    eq(pulse.playing,false); eq(pulse.plays,2)
    stepTimer(315)
    eq(pulse.playing,true); eq(pulse.plays,3); eq(vial.scripts.OnUpdate,nil)
    SpellEfficiencyMinimapButton:Click("RightButton")
    eq(vial:IsShown(),false); eq(pulse.playing,false)

    UIParent:Hide(); reload({manaRegen=true},true)
    vial=SpellEfficiencyManaRegenBar
    _,halo=vialTextures()
    pulse=halo.animation
    eq(vial:IsShown(),true); eq(vial:IsVisible(),false); eq(pulse.plays,0)
    UIParent:Show(); vial.scripts.OnShow(vial)
    eq(pulse.playing,true); eq(pulse.plays,1)
    vial.scripts.OnShow(vial)
    eq(pulse.plays,1); eq(vial.scripts.OnUpdate,nil)
end)

local function vialMist()
    for _,frame in ipairs(frames) do
        if frame.kind=="Texture" and frame.texture and frame.texture:match("ManaVialMist%.tga$") then
            eq(frame.parent.parent,SpellEfficiencyManaRegenBar)
            return frame.parent,frame
        end
    end
    error("missing the vial's spiral mist texture")
end

test("actual refill plays the mist once, then leaves only the existing full glow",function()
    playerClass="MAGE"; now=330; reload({manaRegen=true})
    local mist,art=vialMist()
    local _,halo=vialTextures()
    local atlas=assert(io.open(PROJECT_ROOT .. "/SpellEfficiency/ManaVialMist.tga","rb"))
    atlas:close()
    eq(mist:IsShown(),false); eq(mist.scripts.OnUpdate,nil)
    eq(halo.animation.plays,1)

    fixture(6120,"造成100点伤害。",0,80)
    succeed("mist-first",6120)
    eq(stepTimer(334.95),0.1); eq(mist:IsShown(),false)
    eq(stepTimer(335),0); eq(mist:IsShown(),true)
    eq(halo.animation.plays,2)
    near(art.texCoord[1],1/1024); near(art.texCoord[3],1/512)
    near(art.texCoord[2],99/1024); near(art.texCoord[4],101/512)
    local update=assert(mist.scripts.OnUpdate)
    now=335+11.25/24; update(mist)
    near(art.texCoord[1],101/1024); near(art.texCoord[3],103/512)
    local coords=art.texCoord
    now=335+11.5/24; update(mist)
    eq(art.texCoord,coords)
    now=335+48.5/24; update(mist)
    eq(mist:IsShown(),true)
    near(art.texCoord[1],801/1024); near(art.texCoord[3],409/512)
    now=335+49.5/24; update(mist)
    eq(mist:IsShown(),false); eq(mist.scripts.OnUpdate,nil)
    eq(SpellEfficiencyManaRegenBar.scripts.OnUpdate,nil)
    eq(halo.animation.playing,true); eq(halo.animation.plays,2)

    succeed("mist-next",6120)
    stepTimer(now+5.01)
    eq(mist:IsShown(),true); near(art.texCoord[1],1/1024)
    eq(halo.animation.plays,3)
end)

test("only new spending, hiding or disabling cuts off a live mist",function()
    playerClass="MAGE"; now=350; reload({manaRegen=true})
    local vial=SpellEfficiencyManaRegenBar
    local mist=vialMist()
    local _,halo=vialTextures()
    fixture(6120,"造成100点伤害。",0,80)
    fixture(6121,"恢复100点生命值。",0,0)
    succeed("mist-before-free-cast",6120)
    stepTimer(355)
    succeed("free-with-mist",6121); eq(mist:IsShown(),true)
    succeed("paid-with-mist",6120)
    eq(mist:IsShown(),false); eq(mist.scripts.OnUpdate,nil)
    eq(manaRemaining(),5); eq(halo.animation.playing,false)

    stepTimer(360)
    eq(mist:IsShown(),true)
    vial:Hide(); eq(mist:IsShown(),false); eq(mist.scripts.OnUpdate,nil)
    vial:Show(); eq(mist:IsShown(),false); eq(halo.animation.playing,true)

    succeed("mist-before-disable",6120); stepTimer(365)
    eq(mist:IsShown(),true)
    SpellEfficiencyMinimapButton:Click("RightButton")
    eq(mist:IsShown(),false); eq(mist.scripts.OnUpdate,nil)
    SpellEfficiencyMinimapButton:Click("RightButton")
    eq(mist:IsShown(),false); eq(mist.scripts.OnUpdate,nil)
    eq(halo.animation.playing,true)
end)

print("TOTAL " .. passed .. " spell-efficiency tests passed")
