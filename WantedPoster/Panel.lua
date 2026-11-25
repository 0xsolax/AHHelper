local _, addon = ...
local Roster = addon.Roster
local Macros = addon.Macros
local Panel = {}
addon.Panel = Panel

local ink = { 48, 27, 15 }
local muted = { 93, 58, 32 }
local inactive = { 116, 85, 55 }
local alert = { 125, 43, 30 }
local panelWidth, panelHeight = 280, 326
local playerNameSize = 23

local function place(region, parent, x, y, width, height)
    region:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    region:SetSize(width, height)
    return region
end

local function fill(parent, layer, x, y, width, height, color, alpha)
    local texture = place(parent:CreateTexture(nil, layer), parent, x, y, width, height)
    texture:SetColorTexture(color[1] / 255, color[2] / 255, color[3] / 255, alpha or 1)
    return texture
end

local function textColor(region, color)
    region:SetTextColor(color[1] / 255, color[2] / 255, color[3] / 255)
end

local function label(parent, value, x, y, width, height, size, color, justify)
    local font = place(parent:CreateFontString(nil, "OVERLAY", "GameFontNormal"), parent, x, y, width, height)
    font:SetFont(GameFontNormal:GetFont(), size)
    font:SetShadowOffset(0, 0)
    font:SetJustifyH(justify or "LEFT")
    font:SetJustifyV("MIDDLE")
    font:SetWordWrap(false)
    textColor(font, color)
    font:SetText(value)
    return font
end

local function setPlayerName(font, name)
    local fontFile = GameFontNormal:GetFont()
    local width = font:GetWidth()
    font:SetText(name)
    for size = playerNameSize, 16, -1 do
        font:SetFont(fontFile, size, "")
        if font:GetUnboundedStringWidth() <= width then return end
    end

    -- Trim whole UTF-8 characters. The tooltip and macro still use the full name.
    repeat
        name = name:gsub(".[\128-\191]*$", ""):gsub(" +$", "")
        font:SetText(name)
    until name == "" or font:GetUnboundedStringWidth() <= width
end

local function tooltip(control, hint, anchor)
    control.hint = hint
    control:SetScript("OnEnter", function(self)
        if self.hint and self.hint ~= "" then
            GameTooltip:SetOwner(self, anchor)
            GameTooltip:SetText(self.hint)
            GameTooltip:Show()
        end
    end)
    control:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function button(parent, value, x, y, width, height, action, hint, secure)
    local template = "UIPanelButtonTemplate"
    if secure then
        template = value and "UIPanelButtonTemplate, SecureActionButtonTemplate" or "SecureActionButtonTemplate"
    end
    local control = place(CreateFrame("Button", nil, parent, template), parent, x, y, width, height)
    if value then
        control:SetText(value)
    else
        control:SetPushedTexture(fill(control, "ARTWORK", 0, 0, width, height, { 184, 132, 75 }, 0.35))
        control:SetHighlightTexture(fill(control, "HIGHLIGHT", 0, 0, width, height, { 255, 229, 192 }, 0.26))
        -- Mirror the right inset across the poster centerline.
        local right = width - 3
        local left = panelWidth - 2 * x - right
        control.label = label(control, "", left, 0, right - left, height, playerNameSize, ink, "CENTER")
        control:SetFontString(control.label)
        control:SetPushedTextOffset(0, -1)
    end
    tooltip(control, hint, "ANCHOR_TOP")
    if secure then
        control:RegisterForClicks("LeftButtonUp")
        control:SetAttribute("type", "macro")
        control:SetAttribute("useOnKeyDown", false)
    else
        control:SetScript("OnClick", action)
    end
    return control
end

local function enabled(control, value)
    control:SetEnabled(not not value)
    if control.label then
        textColor(control.label, value and ink or inactive)
    end
end

function Panel.CreateMinimapButton(app)
    if not Minimap then return end
    local database = app.database
    local angle = database.minimapAngle
    if type(angle) ~= "number" or not (angle > -math.huge and angle < math.huge) then
        angle = 164
    end
    database.minimapAngle = angle % 360

    local control = CreateFrame("Button", "WantedPosterMinimapButton", Minimap)
    control:SetSize(32, 32)
    control:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    control:EnableMouse(true)
    control:RegisterForClicks("LeftButtonUp")
    control:RegisterForDrag("LeftButton")
    control:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")

    local icon = place(control:CreateTexture(nil, "BACKGROUND"), control, 7, 5, 20, 20)
    icon:SetTexture("Interface\\Icons\\INV_Scroll_03")
    local border = place(control:CreateTexture(nil, "OVERLAY"), control, 0, 0, 54, 54)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    local function radius()
        return Minimap:GetWidth() / 2 + 6, Minimap:GetHeight() / 2 + 6
    end

    local function position()
        local radians = math.rad(database.minimapAngle)
        local rx, ry = radius()
        control:ClearAllPoints()
        control:SetPoint("CENTER", Minimap, "CENTER", math.cos(radians) * rx, math.sin(radians) * ry)
    end

    local function drag()
        local centerX, centerY = Minimap:GetCenter()
        if not centerX or not centerY then return end
        local cursorX, cursorY = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        local rx, ry = radius()
        local x, y = (cursorX / scale - centerX) / rx, (cursorY / scale - centerY) / ry
        if x == 0 and y == 0 then return end
        database.minimapAngle = math.deg(math.atan2(y, x)) % 360
        position()
    end

    local dragging, suppressClick
    local function stopDrag(self)
        dragging = false
        self:SetScript("OnUpdate", nil)
    end

    tooltip(control, "通缉令\n左键打开或关闭面板\n拖动调整位置", "ANCHOR_LEFT")
    control:SetScript("OnMouseDown", function(_, mouse)
        if mouse == "LeftButton" then suppressClick = false end
    end)
    control:SetScript("OnClick", function(_, mouse)
        if mouse == "LeftButton" and not dragging and not suppressClick then app:Toggle() end
    end)
    control:SetScript("OnDragStart", function(self)
        dragging, suppressClick = true, true
        GameTooltip:Hide()
        self:SetScript("OnUpdate", drag)
        drag()
    end)
    control:SetScript("OnDragStop", function(self)
        if dragging then drag() end
        stopDrag(self)
    end)
    control:SetScript("OnHide", stopDrag)
    control:SetScript("OnShow", position)
    position()
end

local function panelScale(value)
    if type(value) ~= "number" or value ~= value then return 1 end
    return math.max(0.70, math.min(1.50, value))
end

local function resizeGrip(frame, database)
    local grip = place(CreateFrame("Button", nil, frame), frame, 248, 306, 20, 18)
    grip:EnableMouse(true)
    grip:RegisterForDrag("LeftButton")
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    tooltip(grip, "拖动可等比调整尺寸", "ANCHOR_LEFT")

    local drag
    local function stop()
        drag = nil
        grip:SetScript("OnUpdate", nil)
    end

    local function resize()
        if not drag then return end
        if InCombatLockdown() then
            stop()
            return
        end
        local x, y = GetCursorPosition()
        local diagonal = panelWidth * panelWidth + panelHeight * panelHeight
        local delta = ((x - drag.x) * panelWidth + (drag.y - y) * panelHeight) / (drag.parentScale * diagonal)
        local scale = panelScale(drag.scale + delta)
        if scale == frame:GetScale() then return end
        frame:SetScale(scale)
        local effective = frame:GetEffectiveScale()
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", drag.left / effective, drag.top / effective)
        database.panelScale = scale
    end

    grip:SetScript("OnDragStart", function()
        if InCombatLockdown() then return end
        local left, top = frame:GetLeft(), frame:GetTop()
        if not left or not top then return end
        local x, y = GetCursorPosition()
        local effective, scale = frame:GetEffectiveScale(), frame:GetScale()
        local uiScale = UIParent:GetEffectiveScale()
        drag = {
            x = x, y = y, scale = scale, parentScale = effective / scale,
            left = left * effective - UIParent:GetLeft() * uiScale,
            top = top * effective - UIParent:GetTop() * uiScale,
        }
        GameTooltip:Hide()
        grip:SetScript("OnUpdate", resize)
    end)
    grip:SetScript("OnDragStop", function()
        resize()
        stop()
    end)
    grip:SetScript("OnHide", stop)
    return grip
end

function Panel.Create(app)
    local frame = CreateFrame("Frame", "WantedPosterFrame", UIParent)
    frame:SetSize(panelWidth, panelHeight)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetScale(panelScale(app.database.panelScale))
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if not InCombatLockdown() then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    frame:Hide()

    local paper = frame:CreateTexture(nil, "BACKGROUND")
    paper:SetAllPoints(frame)
    paper:SetTexture("Interface\\AddOns\\WantedPoster\\Parchment.tga")
    label(frame, "WANTED", 72, 15, 136, 40, 27, ink, "CENTER")
    frame.close = button(frame, "×", 246, 8, 23, 21, function() app:Toggle() end, "关闭")
    frame.previousGroup = button(frame, "<", 40, 23, 26, 24, function() app:MoveGroup(-1) end)
    frame.nextGroup = button(frame, ">", 214, 23, 26, 24, function() app:MoveGroup(1) end)
    fill(frame, "BACKGROUND", 12, 62, 256, 1, ink, 0.56)

    frame.addTarget = button(frame, "通缉目标", 12, 72, 91, 27,
        function() app:AddTarget() end)
    fill(frame, "ARTWORK", 109, 72, 109, 27, { 125, 83, 48 }, 0.80)
    fill(frame, "ARTWORK", 110, 73, 107, 25, { 250, 222, 170 })
    frame.input = place(CreateFrame("EditBox", nil, frame), frame, 110, 73, 107, 25)
    frame.input:SetAutoFocus(false)
    frame.input:SetFontObject(GameFontNormal)
    frame.input:SetFont(GameFontNormal:GetFont(), 14, "")
    frame.input:SetTextInsets(7, 7, 0, 0)
    textColor(frame.input, ink)
    local placeholder = label(frame, "粘贴完整姓名", 117, 73, 93, 25, 14, muted)
    local inputEdge = fill(frame, "OVERLAY", 111, 96, 105, 2, alert)
    inputEdge:Hide()
    frame.input:SetScript("OnTextChanged", function(self) placeholder:SetShown(self:GetText() == "") end)
    frame.input:SetScript("OnEditFocusGained", function() inputEdge:Show() end)
    frame.input:SetScript("OnEditFocusLost", function() inputEdge:Hide() end)
    frame.input:SetScript("OnEnterPressed", function(self) app:AddPasted(self:GetText()) end)
    frame.input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    frame.addPasted = button(frame, "加入", 224, 72, 44, 27,
        function() app:AddPasted(frame.input:GetText()) end)

    frame.rows = {}
    for slot = 1, Roster.pageSize do
        local y = 107 + (slot - 1) * 35
        local rule = fill(frame, "BACKGROUND", 12, y + 32, 256, 1, ink, 0.34)
        local find = button(frame, nil, 12, y, 228, 32, nil, nil, true)
        local remove = button(frame, "×", 246, y + 5, 22, 22,
            function() app:Remove(slot) end, "移除这条记录")
        frame.rows[slot] = { find = find, remove = remove, rule = rule }
    end
    frame.empty = label(frame, "这组暂时没有记录", 12, 176, 256, 34, 16, muted, "CENTER")

    fill(frame, "BACKGROUND", 12, 281, 256, 1, ink, 0.55)
    frame.previousPage = button(frame, "<", 12, 284, 22, 21,
        function() app:MovePage(-1) end, "上一页")
    frame.pageLabel = label(frame, "", 34, 284, 77, 21, 12, ink, "CENTER")
    frame.nextPage = button(frame, ">", 111, 284, 22, 21,
        function() app:MovePage(1) end, "下一页")
    frame.clear = button(frame, "清空", 137, 284, 64, 21,
        function() app:ConfirmClear() end)
    frame.searchPage = button(frame, "搜索", 205, 284, 63, 21, nil, "依次查找本页玩家", true)
    frame.status = label(frame, "", 12, 306, 225, 14, 12, muted)
    frame.resize = resizeGrip(frame, app.database)
    return frame
end

function Panel.Controls(frame, locked, view)
    enabled(frame.close, not locked)
    enabled(frame.previousGroup, not locked and view.groupIndex > 1)
    enabled(frame.nextGroup, not locked and view.groupIndex < view.groupCount)
    enabled(frame.previousPage, not locked and view.pageIndex > 1)
    enabled(frame.nextPage, not locked and view.pageIndex < view.pageCount)
    enabled(frame.clear, not locked and #view.page.names > 0)
    enabled(frame.resize, not locked)
    for _, row in ipairs(frame.rows) do
        enabled(row.remove, not locked)
    end
end

function Panel.Status(frame, message, warning)
    frame.status:SetText(message)
    textColor(frame.status, warning and alert or muted)
end

function Panel.Draw(frame, view, bindings)
    local historyHint = view.groupIndex < view.groupCount and "\n正在查看 " .. view.groupLabel or ""
    frame.previousGroup.hint = "上一组登录" .. historyHint
    frame.nextGroup.hint = "下一组登录" .. historyHint
    frame.pageLabel:SetText(("%d / %d 页"):format(view.pageIndex, view.pageCount))
    frame.empty:SetShown(#view.page.names == 0)
    for slot, row in ipairs(frame.rows) do
        local name = view.page.names[slot]
        setPlayerName(row.find.label, name or "")
        row.find.hint = name
        row.find:SetAttribute("macro", bindings[slot])
        enabled(row.find, bindings[slot] ~= nil)
        row.find:SetShown(name ~= nil)
        row.remove:SetShown(name ~= nil)
        row.rule:SetShown(name ~= nil)
    end
    frame.searchPage:SetAttribute("macro", bindings[Macros.pageSlot])
    enabled(frame.searchPage, bindings[Macros.pageSlot] ~= nil)
    Panel.Controls(frame, false, view)
end
