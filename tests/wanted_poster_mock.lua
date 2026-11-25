local M = { frames = {}, macros = {}, calls = {}, notices = {}, timers = {}, combat = false, macroLimit = 18 }
M.nameplates, M.alerts, M.plateNameReads = {}, {}, 0
MOCK = M

local Frame = {}
Frame.__index = Frame

local function newFrame(kind, name, parent, template)
    local frame = setmetatable({
        kind = kind, name = name, parent = parent, template = template,
        shown = true, enabled = true, children = {}, scripts = {}, events = {}, attributes = {}
    }, Frame)
    M.frames[#M.frames + 1] = frame
    if parent then table.insert(parent.children, frame) end
    if name then _G[name] = frame end
    frame.panelButton = template and template:find("UIPanelButtonTemplate", 1, true) ~= nil
    frame.secureAction = template and template:find("SecureActionButtonTemplate", 1, true) ~= nil
    if frame.secureAction then
        frame.protected = true
        while parent and parent ~= UIParent do
            parent.protected = true
            parent = parent.parent
        end
    end
    return frame
end

local function run(frame, script, ...)
    if frame.scripts[script] then
        return frame.scripts[script](frame, ...)
    end
end
M.Fire = run

local function assertUnlocked(frame)
    assert(not (frame.protected and M.combat), "protected frame changed in combat")
end

CreateFrame = newFrame
UIParent = CreateFrame("Frame", "UIParent")
Minimap = CreateFrame("Frame", "Minimap", UIParent)

function Frame:SetPoint(point, _, _, x, y) self.point, self.x, self.y = point, x or 0, -(y or 0) end
function Frame:ClearAllPoints() self.x, self.y = nil, nil end
function Frame:SetSize(w, h) self.width, self.height = w, h end
function Frame:GetWidth() return self.width end
function Frame:GetHeight() return self.height end
function Frame:GetCenter() return self.centerX, self.centerY end
function Frame:GetLeft() return self.left end
function Frame:GetTop() return self.top end
function Frame:GetScale() return self.scale or 1 end
function Frame:SetScale(scale) assertUnlocked(self); self.scale = scale end
function Frame:GetEffectiveScale() return self:GetScale() * (self.parent and self.parent:GetEffectiveScale() or 1) end
function Frame:EnableMouse(enabled) self.mouseEnabled = enabled end
function Frame:SetAllPoints(parent) self.allPoints = parent end
function Frame:SetFrameLevel(level) self.level = level end
function Frame:GetFrameLevel() return self.level or 1 end
function Frame:RegisterForClicks(...) self.clicks = { ... } end
function Frame:RegisterForDrag(...) self.dragButtons = { ... } end
function Frame:SetScript(event, fn) self.scripts[event] = fn end
function Frame:RegisterEvent(event) self.events[event] = true end
function Frame:UnregisterEvent(event) self.events[event] = nil end
function Frame:IsShown() return self.shown end
function Frame:SetShown(shown)
    assertUnlocked(self)
    local changed = self.shown ~= shown
    self.shown = shown
    if changed then run(self, shown and "OnShow" or "OnHide") end
end
function Frame:Show() self:SetShown(true) end
function Frame:Hide() self:SetShown(false) end
function Frame:SetEnabled(enabled) assertUnlocked(self); self.enabled = enabled end
function Frame:SetAttribute(attribute, value) assertUnlocked(self); self.attributes[attribute] = value end
function Frame:SetText(value)
    self.text = value
    if self.kind == "EditBox" then run(self, "OnTextChanged") end
end
function Frame:GetText() return self.text or "" end
function Frame:ClearFocus() run(self, "OnEditFocusLost") end
function Frame:SetFont(_, size, flags)
    if self.kind == "EditBox" then
        assert(type(flags) == "string", "bad argument #3 to 'SetFont' (font flags required)")
    end
    self.size = size
end
function Frame:GetUnboundedStringWidth()
    local width = 0
    for glyph in (self.text or ""):gmatch(".[\128-\191]*") do
        width = width + self.size * (#glyph > 1 and 1 or 0.55)
    end
    return width
end
function Frame:SetJustifyH(value) self.justify = value end
function Frame:SetTextColor(...) self.color = { ... } end
function Frame:SetColorTexture(...) self.color = { ... } end
function Frame:SetTexture(asset) self.asset = asset end
function Frame:CreateTexture(_, layer) local t = newFrame("Texture", nil, self); t.layer = layer; return t end
function Frame:CreateFontString(_, layer) local f = newFrame("FontString", nil, self); f.layer = layer; return f end
function Frame:SetNormalTexture(region)
    if type(region) == "string" then self.normalAsset = region else region.state = "normal" end
end
function Frame:SetPushedTexture(region)
    if type(region) == "string" then self.pushedAsset = region else region.state = "pushed" end
end
function Frame:SetDisabledTexture(region) region.state = "disabled" end
function Frame:SetHighlightTexture(region)
    if type(region) == "string" then self.highlightAsset = region else region.state = "highlight" end
end
function Frame:HookScript(script, hook)
    local original = self.scripts[script]
    self.scripts[script] = function(...)
        if original then original(...) end
        hook(...)
    end
end

for _, method in ipairs({
    "SetFrameStrata", "SetClampedToScreen", "SetMovable",
    "StartMoving", "StopMovingOrSizing", "SetFontString", "SetPushedTextOffset",
    "SetShadowOffset", "SetJustifyV", "SetWordWrap", "SetAutoFocus", "SetFontObject", "SetTextInsets",
}) do
    Frame[method] = function() end
end

UIParent:SetSize(1920, 1080)
UIParent.left, UIParent.top = 0, 1080
Minimap:SetSize(140, 140)
Minimap.centerX, Minimap.centerY, Minimap.scale = 900, 700, 0.8
function GetCursorPosition() return M.cursorX, M.cursorY end
GameFontNormal = { GetFont = function() return "Fonts\\Mock.ttf", 14, "" end }
GameTooltip = { SetOwner = function() end, SetText = function() end, Show = function() end, Hide = function() end }
UIErrorsFrame = { AddMessage = function(_, text) table.insert(M.alerts, text) end }
SlashCmdList = {}
StaticPopupDialogs = {}
CANCEL = "取消"

function StaticPopup_Show(key, count, _, data)
    M.popup = { dialog = StaticPopupDialogs[key], count = count, data = data }
end

function M.Accept()
    local popup = assert(M.popup)
    M.popup = nil
    popup.dialog.OnAccept(nil, popup.data)
end

C_Timer = { After = function(_, callback) table.insert(M.timers, callback) end }
function M.Tick()
    local callbacks = M.timers
    M.timers = {}
    for _, callback in ipairs(callbacks) do callback() end
end

function M.Emit(event, ...)
    for _, frame in ipairs(M.frames) do
        if frame.events[event] then run(frame, "OnEvent", event, ...) end
    end
end

function M.SetCombat(value)
    M.combat = value
    M.Emit(value and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
end

function M.AddNameplate(unit, info)
    M.nameplates[unit] = info
    M.Emit("NAME_PLATE_UNIT_ADDED", unit)
end

function M.RemoveNameplate(unit)
    M.nameplates[unit] = nil
    M.Emit("NAME_PLATE_UNIT_REMOVED", unit)
end

function InCombatLockdown() return M.combat end
function UnitIsPlayer(unit)
    if unit == "target" then return M.target and M.target.player or false end
    local plate = M.nameplates[unit]
    return plate and plate.player or false
end
function UnitIsEnemy(source, unit)
    assert(source == "player")
    local plate = M.nameplates[unit]
    return plate and plate.enemy or false
end
function UnitName(unit)
    if unit == "target" then return M.target.first, M.target.last end
    M.plateNameReads = M.plateNameReads + 1
    local plate = assert(M.nameplates[unit])
    assert(not plate.nameError, "nameplate identity unavailable")
    return plate.first, plate.last
end
C_Secrets = {
    ShouldUnitIdentityBeSecret = function(unit)
        local plate = M.nameplates[unit]
        return plate and plate.hidden or false
    end,
}
function issecretvalue(value) return value == M.secret end
M.secret = {}
function GetTime() return M.uptime or 0 end
function time() return M.now or 1794989600 end
date = os.date
function print(text) table.insert(M.notices, text) end

Constants = { MacroConsts = { MAX_ACCOUNT_MACROS = 120, MAX_CHARACTER_MACROS = 18 } }

function GetNumMacros()
    local shared, character = 0, 0
    for index in pairs(M.macros) do
        if index <= Constants.MacroConsts.MAX_ACCOUNT_MACROS then shared = shared + 1
        else character = character + 1 end
    end
    return shared, character
end

function GetMacroIndexByName(name)
    for index, macro in pairs(M.macros) do
        if M.missCharacterMacroNames and index > Constants.MacroConsts.MAX_ACCOUNT_MACROS then
            macro = nil
        end
        if macro and macro.name == name then return index end
    end
    return 0
end

function GetMacroInfo(index)
    local entry = M.macros[index]
    if entry then return entry.name, entry.icon, entry.body end
end

function CreateMacro(name, icon, body, character)
    assert(not M.combat and not (MacroFrame and MacroFrame:IsShown()))
    assert(character and #body <= 255)
    local first = Constants.MacroConsts.MAX_ACCOUNT_MACROS + 1
    for index = first, first + M.macroLimit - 1 do
        if not M.macros[index] then
            M.macros[index] = { name = name, icon = icon, body = body }
            M.Emit("UPDATE_MACROS")
            return index
        end
    end
    error("Character macro limit reached")
end

function EditMacro(index, name, icon, body)
    assert(not M.combat and not (MacroFrame and MacroFrame:IsShown()) and #body <= 255)
    local entry = assert(M.macros[index])
    entry.name, entry.icon, entry.body = name or entry.name, icon or entry.icon, body
    M.Emit("UPDATE_MACROS")
    return index
end

function DeleteMacro(index)
    assert(not M.combat and not (MacroFrame and MacroFrame:IsShown()))
    while M.macros[index + 1] do
        M.macros[index] = M.macros[index + 1]
        index = index + 1
    end
    M.macros[index] = nil
    M.Emit("UPDATE_MACROS")
end

function M.Click(frame, mouse)
    if not (frame.shown and frame.enabled) then return end
    mouse = mouse or "LeftButton"
    run(frame, "OnMouseDown", mouse)
    if frame.secureAction then
        assert(not frame.scripts.OnClick, "secure template click handler was replaced")
        assert(frame.attributes.type == "macro" and not frame.attributes.macrotext)
        local macro = assert(frame.attributes.macro)
        local index = type(macro) == "number" and macro or GetMacroIndexByName(macro)
        local _, _, body = GetMacroInfo(index)
        table.insert(M.calls, assert(body))
    else
        run(frame, "OnClick", mouse)
    end
end

function M.Paste(name, enter)
    local frame = assert(WantedPosterFrame)
    frame.input:SetText(name)
    if enter then run(frame.input, "OnEnterPressed") else M.Click(frame.addPasted) end
end

function M.Load(saved, initialLogin, reloadingUI)
    M.frames = { UIParent, Minimap }
    UIParent.children = { Minimap }
    Minimap.children = {}
    WantedPosterFrame = nil
    WantedPosterMinimapButton = nil
    MacroFrame = nil
    WantedPosterDB = saved
    M.namespace = {}
    for line in io.lines(ADDON_ROOT .. "/WantedPoster.toc") do
        local module = line:match("^([%w]+%.lua)")
        if module then assert(loadfile(ADDON_ROOT .. "/" .. module))("WantedPoster", M.namespace) end
    end
    M.Emit("PLAYER_ENTERING_WORLD", initialLogin, reloadingUI)
    return WantedPosterDB
end

function M.Open()
    SlashCmdList.WANTEDPOSTER()
    return assert(WantedPosterFrame)
end
