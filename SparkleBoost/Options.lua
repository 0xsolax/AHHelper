-- Chinese controls and a preview that never changes targeting settings.
-- Copyright (C) 2026 Sola. SPDX-License-Identifier: GPL-3.0-or-later
local _, ns = ...
local panel, updating
local checks, sliders, styleButtons, paletteButtons = {}, {}, {}, {}

local function Text(parent, text, x, y, width, font)
    local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    label:SetWidth(width)
    label:SetJustifyH("LEFT")
    label:SetText(text)
    return label
end

local function Button(parent, text, x, y, width, callback)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 25)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    button:SetText(text)
    button:SetScript("OnClick", callback)
    return button
end

local function Checkbox(parent, key, text, x, y)
    local button = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    button:SetSize(26, 26)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    local label = button.Text or button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:ClearAllPoints()
    label:SetPoint("LEFT", button, "RIGHT", 2, 0)
    label:SetWidth(x >= 400 and 180 or 340)
    label:SetJustifyH("LEFT")
    label:SetText(text)
    button:SetScript("OnClick", function(self)
        if not updating then ns.SetOption(key, self:GetChecked() == true) end
    end)
    checks[key] = button
    return button
end

local function Slider(parent, key, title, low, high, step, y, format)
    Text(parent, title, 20, y + 2, 100)
    local slider = CreateFrame("Slider", "SparkleBoostSlider_" .. key, parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", parent, "TOPLEFT", 128, y)
    slider:SetSize(244, 17)
    slider:SetMinMaxValues(low, high)
    slider:SetValueStep(step)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    for _, suffix in ipairs({"Low", "High", "Text"}) do
        local region = slider[suffix] or _G[slider:GetName() .. suffix]
        if region then region:Hide() end
    end
    local value = Text(parent, "", 381, y + 2, 61)
    slider:SetScript("OnValueChanged", function(_, number)
        if updating then return end
        number = math.floor(number / step + 0.5) * step
        if ns.SetOption(key, number) then value:SetText(format(number)) end
    end)
    sliders[key] = {slider = slider, value = value, format = format}
    return slider
end

local function Build()
    local frame = CreateFrame("Frame", "SparkleBoostOptions", UIParent, "BackdropTemplate")
    panel = frame
    frame:SetSize(700, 618)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    frame:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = false, edgeSize = 14,
        insets = {left = 3, right = 3, top = 3, bottom = 3}})
    frame:SetBackdropColor(0.055, 0.065, 0.09, 0.98)
    frame:SetBackdropBorderColor(0.70, 0.55, 0.26, 1)
    Text(frame, "拾光  SparkleBoost", 20, -18, 570, "GameFontNormalLarge")
    Text(frame, "让任务物品更容易被发现。先在右侧预览，再开启附近增强。", 20, -49, 650)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() frame:Hide() end)

    Checkbox(frame, "enabled", "启用拾光", 18, -81)
    Checkbox(frame, "native", "保持原生任务闪光", 18, -111)
    Checkbox(frame, "enhanced", "附近增强（测试）", 18, -141)
    Text(frame, "提示对象", 20, -184, 350, "GameFontNormal")
    Checkbox(frame, "sparkleQuest", "任务物品", 18, -204)
    Checkbox(frame, "sparkleHerbs", "草药", 173, -204)
    Checkbox(frame, "sparkleOre", "矿脉", 18, -234)
    Checkbox(frame, "sparkleCorpseLoot", "可拾取尸体", 173, -234)
    Checkbox(frame, "hidePlate", "隐藏提示下方的空姓名板", 18, -272)

    Text(frame, "光效样式", 20, -318, 100, "GameFontNormal")
    for i, entry in ipairs({{"sparkles", "星光"}, {"beacon", "光柱"}, {"ring", "光圈"}}) do
        local key = entry[1]
        styleButtons[key] = {button = Button(frame, entry[2], 126 + (i - 1) * 91, -311, 83,
            function() ns.SetOption("style", key) end), label = entry[2]}
    end
    Slider(frame, "size", "大小", 0.6, 3, 0.1, -357, function(v) return string.format("%.1f 倍", v) end)
    Slider(frame, "brightness", "亮度", 0.25, 1.5, 0.05, -402, function(v) return string.format("%.0f%%", v * 100) end)
    Slider(frame, "range", "提示范围", 5, 15, 1, -447, function(v) return string.format("%.0f 码", v) end)
    Slider(frame, "offsetY", "上下位置", -120, 40, 5, -492, function(v) return string.format("%.0f", v) end)

    Text(frame, "效果预览", 454, -84, 220, "GameFontNormal")
    local preview = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    preview:SetPoint("TOPLEFT", frame, "TOPLEFT", 450, -108)
    preview:SetSize(226, 254)
    preview:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8"})
    preview:SetBackdropColor(0.015, 0.025, 0.045, 1)
    if preview.SetClipsChildren then preview:SetClipsChildren(true) end
    local icon = preview:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\INV_Crate_01")
    icon:SetSize(30, 30)
    icon:SetPoint("BOTTOM", preview, "BOTTOM", 0, 15)
    ns.CreatePreview(preview)
    Text(frame, "预览按比例缩小。实际位置与遮挡\n以游戏内显示为准。", 454, -371, 222, "GameFontHighlightSmall")
    for i, entry in ipairs({{"auto", "分类色"}, {"gold", "金色"}, {"cyan", "青色"}, {"violet", "紫色"}}) do
        local key = entry[1]
        paletteButtons[key] = {button = Button(frame, entry[2], 452 + ((i - 1) % 2) * 115,
            -413 - math.floor((i - 1) / 2) * 32, 107, function() ns.SetOption("palette", key) end), label = entry[2]}
    end
    local arc = Checkbox(frame, "arc", "环视搜索", 450, -487)
    arc:SetScript("OnClick", function(self) if not updating then ns.SetOption("arc", self:GetChecked() and 2 or 1) end end)
    frame.status = Text(frame, "", 20, -535, 650, "GameFontHighlightSmall")
    frame.status:SetHeight(36)
    frame.status:SetJustifyV("TOP")
    Button(frame, "恢复原设置", 20, -578, 126, ns.RestoreAll)
    Button(frame, "输出诊断", 156, -578, 106, ns.StatusCommand)
    Button(frame, "关闭", 568, -578, 108, function() frame:Hide() end)
    frame:SetScript("OnShow", function() ns.UIRefresh() end)
    UISpecialFrames = UISpecialFrames or {}
    UISpecialFrames[#UISpecialFrames + 1] = "SparkleBoostOptions"
    frame:Hide()
    return frame
end

function ns.UIRefresh()
    if not panel or not ns.db then return end
    updating = true
    for key, check in pairs(checks) do
        check:SetChecked(key == "arc" and ns.db.arc == 2 or ns.db[key] == true)
    end
    for key, control in pairs(sliders) do
        control.slider:SetValue(ns.db[key])
        control.value:SetText(control.format(ns.db[key]))
    end
    for key, entry in pairs(styleButtons) do
        entry.button:SetText(ns.db.style == key and "|cffffd166" .. entry.label .. "|r" or entry.label)
    end
    for key, entry in pairs(paletteButtons) do
        entry.button:SetText(ns.db.palette == key and "|cffffd166" .. entry.label .. "|r" or entry.label)
    end
    panel.status:SetText(ns.GetStatus() .. "\n附近增强一次提示一个目标；战斗中隐藏新增光效。")
    updating = false
end

function ns.ToggleOptions(forceShow)
    if not panel then Build() end
    if forceShow or not panel:IsShown() then panel:Show(); ns.UIRefresh() else panel:Hide() end
end

local minimapButton
function ns.CreateMinimapButton()
    if minimapButton or not Minimap or not ns.db then return end
    local button = CreateFrame("Button", "SparkleBoostMinimapButton", Minimap)
    minimapButton = button
    button:SetSize(32, 32)
    button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    button:EnableMouse(true)
    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")
    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", button, "TOPLEFT", 7, -5)
    icon:SetTexture("Interface\\Icons\\Spell_Holy_InnerFire")
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")

    local dragging, suppressClick
    local function Position()
        local angle = math.rad(ns.db.minimapAngle)
        button:ClearAllPoints()
        button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * (Minimap:GetWidth() / 2 + 6),
            math.sin(angle) * (Minimap:GetHeight() / 2 + 6))
    end
    local function Drag()
        local x, y = GetCursorPosition()
        local cx, cy = Minimap:GetCenter()
        if not x or not y or not cx or not cy then return end
        local scale = Minimap:GetEffectiveScale()
        local dx = (x / scale - cx) / (Minimap:GetWidth() / 2 + 6)
        local dy = (y / scale - cy) / (Minimap:GetHeight() / 2 + 6)
        if dx == 0 and dy == 0 then return end
        -- Position changes must not reapply the targeting CVars.
        ns.db.minimapAngle = math.deg(math.atan2(dy, dx)) % 360
        Position()
    end
    local function StopDrag()
        dragging = false
        button:SetScript("OnUpdate", nil)
    end
    button:SetScript("OnMouseDown", function(_, mouseButton)
        if mouseButton == "LeftButton" then suppressClick = false end
    end)
    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "LeftButton" and not dragging and not suppressClick then ns.ToggleOptions() end
    end)
    button:SetScript("OnDragStart", function()
        dragging, suppressClick = true, true
        GameTooltip:Hide()
        button:SetScript("OnUpdate", Drag)
        Drag()
    end)
    button:SetScript("OnDragStop", function()
        if dragging then Drag() end
        StopDrag()
    end)
    button:SetScript("OnHide", function() StopDrag(); GameTooltip:Hide() end)
    button:SetScript("OnShow", Position)
    button:SetScript("OnEnter", function(self)
        if dragging then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("拾光")
        GameTooltip:AddLine("左键：打开 / 关闭设置", 1, 1, 1)
        GameTooltip:AddLine("按住左键拖动：调整位置（自动保存）", 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    Position()
end
