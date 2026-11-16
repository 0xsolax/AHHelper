-- Character settings and a native minimap entry; no external libraries. Solazhu.
local addonName, A = ...
local L, S = A.Logic, {}
A.Settings = S
local config = {enabled=true, timeWeight=0.8, minimapAngle=225}
local loaded, button, panel = false, nil, nil

function S.IsEnabled() return config.enabled end
function S.GetWeight() return config.timeWeight end

local function syncControls()
    if button then button.icon:SetDesaturated(not config.enabled) end
    if panel then
        panel.enabled:SetChecked(config.enabled)
        panel.weight:SetText(tostring(config.timeWeight))
        panel.error:SetText("")
    end
end

function S.Apply(enabled, weight)
    if not loaded or not L.Readable(weight) then return false end
    if type(weight) == "string" then weight = tonumber(weight) end
    if type(enabled) ~= "boolean" or not L.Number(weight) or weight > 1 then return false end
    config.enabled, config.timeWeight = enabled, weight
    syncControls()
    if A.RefreshTooltip then A.RefreshTooltip() end
    return true
end

local function createPanel()
    panel = CreateFrame("Frame", "SpellEfficiencySettingsFrame", UIParent, "BackdropTemplate")
    panel:SetSize(340, 230); panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG"); panel:SetClampedToScreen(true)
    panel:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize=24,
        insets={left=5,right=5,top=5,bottom=5}})
    panel:EnableMouse(true); panel:SetMovable(true); panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
    panel:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    panel:SetScript("OnHide", function(self) self:StopMovingOrSizing(); self.weight:ClearFocus() end)
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 25, -20); title:SetText("效率")
    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4); close:SetScript("OnClick", function() panel:Hide() end)
    panel.enabled = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    panel.enabled:SetPoint("TOPLEFT", 20, -48); panel.enabled.Text:SetText("显示法术效率")
    local label = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", 25, -96); label:SetText("时间权重")
    panel.weight = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    panel.weight:SetSize(80, 24); panel.weight:SetPoint("TOPLEFT", 130, -90)
    panel.weight:SetAutoFocus(false); panel.weight:SetMaxLetters(12)
    panel.weight:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", 25, -128); hint:SetWidth(290); hint:SetJustifyH("LEFT")
    hint:SetText("0：仅每蓝收益　1：完全计入时间")
    panel.error = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.error:SetPoint("TOPLEFT", 25, -153); panel.error:SetWidth(290)
    panel.error:SetJustifyH("LEFT"); panel.error:SetTextColor(1, 0.3, 0.3)
    local function apply()
        if S.Apply(panel.enabled:GetChecked() and true or false, panel.weight:GetText()) then
            panel.weight:ClearFocus()
        else
            panel.error:SetText("请输入 0 到 1 之间的数值。")
        end
    end
    panel.apply = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.apply:SetSize(110, 24); panel.apply:SetPoint("BOTTOMLEFT", 25, 20)
    panel.apply:SetText("应用"); panel.apply:SetScript("OnClick", apply)
    panel.weight:SetScript("OnEnterPressed", apply)
    panel.defaults = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.defaults:SetSize(150, 24); panel.defaults:SetPoint("BOTTOMRIGHT", -25, 20)
    panel.defaults:SetText("恢复默认 0.8")
    panel.defaults:SetScript("OnClick", function() S.Apply(true, 0.8) end)
    panel:SetScript("OnShow", syncControls)
    table.insert(UISpecialFrames, "SpellEfficiencySettingsFrame")
    panel:Hide()
end

local function positionButton()
    local radians = math.rad(config.minimapAngle)
    local radius = Minimap:GetWidth() / 2 + 8
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(radians) * radius, math.sin(radians) * radius)
end

local function buttonTooltip()
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:SetText(config.enabled and "效率：已开启" or "效率：已关闭")
    GameTooltip:AddLine("时间权重：" .. tostring(config.timeWeight), 1, 1, 1)
    GameTooltip:AddLine("左键：设置　右键：开关\n拖动：移动按钮", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

local function createButton()
    button = CreateFrame("Button", "SpellEfficiencyMinimapButton", Minimap)
    button:SetSize(32, 32); button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp"); button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(); background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(20, 20); button.icon:SetPoint("CENTER")
    button.icon:SetTexture("Interface\\Icons\\Spell_Holy_Heal")
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(54, 54); border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    button:SetScript("OnClick", function(self, key)
        if key == "RightButton" then
            S.Apply(not config.enabled, config.timeWeight)
            if GameTooltip:IsOwned(self) then buttonTooltip() end
        else
            if not panel then createPanel() end
            if panel:IsShown() then panel:Hide() else panel:Show() end
        end
    end)
    button:SetScript("OnEnter", buttonTooltip)
    button:SetScript("OnLeave", function(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
    button:SetScript("OnDragStart", function(self)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
        self:SetScript("OnUpdate", function()
            local x, y = GetCursorPosition()
            local cx, cy = Minimap:GetCenter()
            if not cx or not cy then return end
            local scale = Minimap:GetEffectiveScale()
            config.minimapAngle = math.deg(math.atan2(y / scale - cy, x / scale - cx)) % 360
            positionButton()
        end)
    end)
    local function stopDrag(self) self:SetScript("OnUpdate", nil) end
    button:SetScript("OnDragStop", stopDrag); button:SetScript("OnHide", stopDrag)
    positionButton(); syncControls()
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, name)
    if not loaded and ((event == "ADDON_LOADED" and name == addonName) or event == "PLAYER_LOGIN") then
        local saved = type(SpellEfficiencyDB) == "table" and SpellEfficiencyDB or {}
        if type(saved.enabled) == "boolean" then config.enabled = saved.enabled end
        if L.Number(saved.timeWeight) and saved.timeWeight <= 1 then config.timeWeight = saved.timeWeight end
        if L.Number(saved.minimapAngle) then config.minimapAngle = saved.minimapAngle % 360 end
        SpellEfficiencyDB = config
        loaded = true
    end
    if not loaded or not IsLoggedIn() then return end
    local _, class = UnitClass("player")
    if L.SupportsClass(class) then
        if not Minimap or not UIParent then return end
        if not button then createButton() end
    end
    events:UnregisterEvent("ADDON_LOADED"); events:UnregisterEvent("PLAYER_LOGIN")
end)
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
