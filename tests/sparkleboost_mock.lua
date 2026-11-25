-- A narrow simulator: observable CVar writes, events, nameplate reuse and UI.
MOCK = {time = 100, frames = {}, writes = {}, messages = {}, cv = {}, loaded = {}, units = {}, y = 0, x = 0}
local M = MOCK
local Frame = {}; Frame.__index = Frame
local function New(kind, name, parent)
    local f = setmetatable({kind = kind, name = name, parent = parent, shown = true, alpha = 1,
        scripts = {}, events = {}, points = {}, width = 1, height = 1, level = 2, textures = {}}, Frame)
    f.index = #M.frames + 1
    M.frames[#M.frames + 1] = f
    if name then _G[name] = f end
    return f
end
function CreateFrame(kind, name, parent) return New(kind, name, parent) end
UIParent = New("Frame", "UIParent")
function Frame:SetSize(w,h) self.width,self.height = w,h end
UIParent:SetSize(1920,1080)
function Frame:SetWidth(v) self.width = v end
function Frame:SetHeight(v) self.height = v end
function Frame:GetWidth() return self.width end
function Frame:GetHeight() return self.height end
function Frame:SetPoint(...) self.points[#self.points+1] = {...} end
function Frame:ClearAllPoints() self.points = {} end
function Frame:SetParent(v) self.parent = v end
function Frame:GetParent() return self.parent end
function Frame:GetName() return self.name end
function Frame:SetScript(name,fn) self.scripts[name] = fn end
function Frame:RegisterEvent(name) self.events[name] = true end
function Frame:UnregisterEvent(name) self.events[name] = nil end
function Frame:Show() local was = self.shown; self.shown = true; if not was and self.scripts.OnShow then self.scripts.OnShow(self) end end
function Frame:Hide() local was = self.shown; self.shown = false; if was and self.scripts.OnHide then self.scripts.OnHide(self) end end
function Frame:SetShown(v) if v then self:Show() else self:Hide() end end
function Frame:IsShown() return self.shown end
function Frame:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function Frame:SetFrameLevel(v) self.level = v end
function Frame:GetFrameLevel() return self.level end
function Frame:SetAlpha(v) self.alpha = v end
function Frame:GetAlpha() return self.alpha end
function Frame:SetIgnoreParentAlpha(v) self.ignoreAlpha = v end
function Frame:SetTexture(v) self.texture = v; return true end
function Frame:GetTexture() return self.texture end
function Frame:GetAtlas() return self.atlas end
function Frame:SetVertexColor(r,g,b,a) self.color = {r,g,b,a} end
function Frame:SetRotation(v) self.rotation = v end
function Frame:CreateTexture(name) local t = New("Texture",name,self); self.textures[#self.textures+1]=t; return t end
function Frame:CreateFontString(name,layer,font) local f=New("FontString",name,self); f.font=font; return f end
function Frame:SetText(v) self.text = v end
function Frame:GetText() return self.text end
function Frame:SetChecked(v) self.checked = v end
function Frame:GetChecked() return self.checked end
function Frame:SetValue(v) self.value=v; if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self,v) end end
function Frame:SetMinMaxValues(low,high) self.low,self.high = low,high end
function Frame:SetValueStep(v) self.step = v end
function Frame:GetEffectiveScale() return self.scale or 1 end
function Frame:GetCenter() return self.centerX,self.centerY end
function Frame:RegisterForClicks(...) self.clicks = {...} end
function Frame:SetHighlightTexture(v) self.highlight = v end
function Frame:SetOwner(v) self.owner = v end
function Frame:AddLine(v) self.lines = self.lines or {}; self.lines[#self.lines+1] = v end
Minimap = New("Frame", "Minimap", UIParent)
Minimap:SetSize(160,160)
Minimap.centerX,Minimap.centerY = 1800,950
GameTooltip = New("Frame", "GameTooltip", UIParent)
GameTooltip:Hide()
function GetCursorPosition() return M.cursorX,M.cursorY end
for _, name in ipairs({"SetJustifyH","SetJustifyV","EnableMouse","SetClampedToScreen","SetMovable","RegisterForDrag",
    "StartMoving","StopMovingOrSizing","SetBackdrop","SetBackdropColor","SetBackdropBorderColor","SetFrameStrata",
    "SetBlendMode","SetSnapToPixelGrid","SetTexelSnappingBias","SetClipsChildren","SetObeyStepOnDrag"}) do Frame[name] = function() end end
function GetTime() return M.time end
function InCombatLockdown() return M.combat == true end
function GetBuildInfo() return "1.60.1", "70938", "Nov 2026", M.interface or 16001 end
function print(...) M.messages[#M.messages+1] = {...} end
function wipe(t) for k in pairs(t) do t[k]=nil end end
function strsplit(delimiter,text)
    local values={}; for part in text:gmatch("[^"..delimiter.."]+") do values[#values+1]=part end
    return unpack(values)
end
M.secret = {}
function issecretvalue(value) return value == M.secret end
function M.Fire(event,...)
    local count = #M.frames
    for i=1,count do local f=M.frames[i]; if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f,event,...) end end
end
C_CVar = {
    GetCVar = function(name) return M.cv[name] end,
    SetCVar = function(name,value)
        M.writes[#M.writes+1] = {name=name,value=tostring(value),combat=M.combat}
        assert(not M.combat,"CVar write attempted in combat")
        if M.fail == name then error("rejected by client") end
        assert(M.cv[name] ~= nil,"unknown CVar was written")
        M.cv[name]=tostring(value)
        M.Fire("CVAR_UPDATE",name,tostring(value))
    end,
}
C_AddOns = {IsAddOnLoaded=function(name) return M.loaded[name] == true end}
local function Unit(token) if token=="softinteract" then return M.target else return M.units[token] end end
local function Value(token,key,fallback)
    if M.secrets then return M.secret end
    local unit=Unit(token)
    if not unit then return fallback end
    return unit[key]
end
function UnitExists(token) local unit=Unit(token); return Value(token,"exists",false) == true or (unit and not unit.object) or false end
function UnitIsGameObject(token) return Value(token,"object",false) end
function UnitIsDead(token) return Value(token,"dead",false) end
function UnitName(token) return Value(token,"name",nil) end
function UnitGUID(token) return Value(token,"guid",nil) end
function UnitIsUnit(a,b) return Unit(a) ~= nil and Unit(a) == Unit(b) end
function UnitIsInInteractRange(token) return Value(token,"inRange",nil) end
function UnitPosition() return M.y,M.x,0,1 end
function SetUnitCursorTexture(texture,token)
    local unit=Unit(token)
    if not unit then return false end
    texture:SetTexture("Interface\\Cursor\\" .. (unit.cursor or "Interact"))
    return true
end
function CanLootUnit(guid) return M.loot == true,M.loot == true end
C_NamePlate = {GetNamePlateForUnit=function(token)
    if M.cv.SoftTargetNameplateInteract ~= "1" then return nil end
    local unit=Unit(token); return unit and unit.plate
end}
C_QuestLog = {
    UnitIsRelatedToActiveQuest=function(token) return Value(token,"quest",false) end,
    GetQuestObjectives=function() return M.objectives or {} end,
    GetNumQuestLogEntries=function() return M.objectives and 1 or 0 end,
    GetQuestIDForLogIndex=function() return 42 end,
}
SlashCmdList,UISpecialFrames = {},{}
function M.Advance(seconds)
    local remaining=seconds
    while remaining > 0.000001 do
        local step=math.min(0.05,remaining); remaining=remaining-step; M.time=M.time+step
        local count=#M.frames
        for i=1,count do local f=M.frames[i]; if f:IsVisible() and f.scripts.OnUpdate then f.scripts.OnUpdate(f,step) end end
    end
end
function M.Load(saved)
    local defaults={outlineModeShowLootEffectWhenDisabled="0",graphicsOutlineMode="2",SoftTargetInteract="0",
        SoftTargetNameplateInteract="0",SoftTargetInteractRange="10",SoftTargetInteractArc="0",
        SoftTargetInteractOnlyInRange="1",SoftTargetIconGameObject="0"}
    for k,v in pairs(defaults) do if M.cv[k]==nil then M.cv[k]=v end end
    SparkleBoostDB=saved
    M.ns={}
    for _,file in ipairs({"Core.lua","Effects.lua","Engine.lua","Options.lua"}) do
        assert(loadfile(PROJECT_ROOT .. "/SparkleBoost/" .. file))("SparkleBoost",M.ns)
    end
    M.Fire("ADDON_LOADED","SparkleBoost"); M.Fire("PLAYER_LOGIN"); M.Advance(2.5)
    return M.ns
end
function M.Target(options)
    local old=M.target and M.target.guid
    options.guid=options.guid or "GameObject-0-1-2-3-42-0000"
    options.name=options.name or "丢失的木箱"
    if options.object == nil then options.object=true end
    if options.inRange == nil then options.inRange=true end
    if options.dead == nil then options.dead=false end
    options.plate=options.plate or New("Frame",nil,UIParent)
    options.plate.UnitFrame=options.plate.UnitFrame or New("Frame",nil,options.plate)
    options.plate.UnitFrame.alpha=0.65
    M.target=options; M.units.nameplate1=options
    M.Fire("PLAYER_SOFT_INTERACT_CHANGED",old,options.guid)
    M.Fire("NAME_PLATE_UNIT_ADDED","nameplate1"); M.Advance(0.3)
    return options.plate
end
function M.Effect(plate)
    for _,f in ipairs(M.frames) do
        if f.parent==plate and f.kind=="Frame" and f.scripts.OnUpdate and #f.textures==14 then return f end
    end
end
function M.SetCombat(combat)
    M.combat=combat
    M.Fire(combat and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
end
