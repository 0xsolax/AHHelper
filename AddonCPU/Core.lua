local addonName, A = ...
local PAGE_SIZE = 12
local page = 1

local function ValidTime(value)
    if type(value) == "number" and value >= 0 and value < math.huge then return value end
end

local function ReadSnapshot()
    local profiler = C_AddOnProfiler
    local metrics = Enum and Enum.AddOnProfilerMetric
    if not profiler or type(profiler.GetAddOnMetric) ~= "function"
        or type(profiler.IsEnabled) ~= "function" or not metrics
        or metrics.SessionAverageTime == nil or metrics.PeakTime == nil
        or not C_AddOns or type(C_AddOns.GetNumAddOns) ~= "function"
        or type(C_AddOns.GetAddOnInfo) ~= "function" or type(C_AddOns.IsAddOnLoaded) ~= "function" then
        return nil, "当前客户端不支持所需的插件耗时统计接口。"
    end
    if not profiler.IsEnabled() then return nil, "游戏的插件耗时统计未启用，暂时无法读取。" end

    local entries = {}
    for i = 1, C_AddOns.GetNumAddOns() do
        local name, title, _, _, _, security = C_AddOns.GetAddOnInfo(i)
        if name and security ~= "SECURE" and C_AddOns.IsAddOnLoaded(i) then
            entries[#entries + 1] = {
                name = name,
                title = title and title ~= "" and title or name,
                average = ValidTime(profiler.GetAddOnMetric(name, metrics.SessionAverageTime)),
                peak = ValidTime(profiler.GetAddOnMetric(name, metrics.PeakTime)),
            }
        end
    end
    table.sort(entries, function(left, right)
        local a, b = left.average or -1, right.average or -1
        if a ~= b then return a > b end
        return left.name < right.name
    end)
    return {entries = entries, time = date("%H:%M:%S")}
end

local function FormatTime(value)
    if value == nil then return "无数据" end
    if value > 0 and value < 0.001 then return "<0.001" end
    return string.format("%.3f", value)
end

local function Render()
    local ui = A.UI
    local entries = A.snapshot and A.snapshot.entries or {}
    local pages = math.max(1, math.ceil(#entries / PAGE_SIZE))
    page = math.max(1, math.min(page, pages))
    for i, row in ipairs(ui.rows) do
        local index = (page - 1) * PAGE_SIZE + i
        local entry = entries[index]
        row.entry = entry
        if entry then
            row.name:SetText(index .. ". " .. entry.title)
            row.average:SetText(FormatTime(entry.average))
            row.peak:SetText(FormatTime(entry.peak))
            row:Show()
        else
            row:Hide()
        end
    end
    ui.previous:SetEnabled(page > 1)
    ui.next:SetEnabled(page < pages)
    ui.pageLabel:SetText(string.format("第 %d / %d 页 · %d 个插件", page, pages, #entries))
end

local function Refresh()
    local ok, snapshot, message = pcall(ReadSnapshot)
    if not ok then
        snapshot, message = nil, "本次读取失败，请稍后手动刷新。"
    end
    if not snapshot then
        A.UI.message:SetText(message)
        A.UI.status:SetText(A.snapshot and ("刷新失败 · 仍为上次快照 " .. A.snapshot.time) or "尚未取得快照")
        return
    end
    A.snapshot, page = snapshot, 1
    A.UI.message:SetText("")
    A.UI.status:SetText("快照时间 " .. snapshot.time .. " · 按会话平均耗时降序")
    Render()
end

local function Label(parent, text, x, y, width, font)
    local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    label:SetSize(width, 20)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetText(text)
    return label
end

local function Button(parent, text, x, y, width, callback)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    button:SetSize(width, 26)
    button:SetText(text)
    button:SetScript("OnClick", callback)
    return button
end

local function HideTooltip(owner)
    if GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
end

local function CreateUI()
    local frame = CreateFrame("Frame", "AddonCPUFrame", UIParent, "BackdropTemplate")
    frame:SetSize(680, 550)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetScript("OnHide", frame.StopMovingOrSizing)
    frame:SetBackdrop({bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16,
        edgeSize = 16, insets = {left = 4, right = 4, top = 4, bottom = 4}})
    frame:SetBackdropColor(0.08, 0.08, 0.08, 1)
    frame:Hide()

    local ui = {frame = frame, rows = {}}
    A.UI = ui
    Label(frame, "插件耗时", 20, 18, 540, "GameFontNormalLarge")
    Label(frame, "仅手动刷新 · 打开窗口和翻页不会重新读取统计", 20, 48, 640)
    ui.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    ui.close:SetSize(28, 28)
    ui.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
    ui.close:SetScript("OnClick", function() frame:Hide() end)
    ui.refresh = Button(frame, "刷新", 20, 78, 104, Refresh)
    ui.status = Label(frame, "尚未刷新 · 点击左侧按钮读取统计", 140, 81, 510)
    ui.message = Label(frame, "", 20, 112, 640)
    ui.message:SetTextColor(1, 0.45, 0.3)
    Label(frame, "插件", 20, 144, 350, "GameFontNormal")
    local average = Label(frame, "会话平均 (ms)", 390, 144, 110, "GameFontNormal")
    average:SetJustifyH("RIGHT")
    local peak = Label(frame, "会话峰值 (ms)", 530, 144, 120, "GameFontNormal")
    peak:SetJustifyH("RIGHT")

    for i = 1, PAGE_SIZE do
        local row = CreateFrame("Frame", nil, frame)
        row:SetSize(640, 24)
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -(170 + (i - 1) * 24))
        row.name = Label(row, "", 0, 0, 350)
        row.average = Label(row, "", 370, 0, 110)
        row.peak = Label(row, "", 510, 0, 120)
        row.average:SetJustifyH("RIGHT")
        row.peak:SetJustifyH("RIGHT")
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            if not self.entry then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.entry.title)
            GameTooltip:AddLine(self.entry.name, 0.8, 0.8, 0.8)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", HideTooltip)
        row:SetScript("OnHide", HideTooltip)
        ui.rows[i] = row
    end
    Label(frame, "平均与峰值来自游戏本次统计会话；刷新不清零，单位为毫秒。", 20, 468, 640)
    ui.previous = Button(frame, "上一页", 20, 510, 96, function() page = page - 1; Render() end)
    ui.next = Button(frame, "下一页", 128, 510, 96, function() page = page + 1; Render() end)
    ui.pageLabel = Label(frame, "", 246, 513, 404)
    table.insert(UISpecialFrames, "AddonCPUFrame")
    Render()
end

local function ToggleWindow()
    if not A.UI then CreateUI() end
    A.UI.frame:SetShown(not A.UI.frame:IsShown())
end

SLASH_ADDONCPU1 = "/addoncpu"
SlashCmdList.ADDONCPU = ToggleWindow

if Minimap then
    local button = CreateFrame("Button", "AddonCPUMinimapButton", Minimap)
    button:SetSize(32, 32)
    button:SetFrameLevel(Minimap:GetFrameLevel() + 5)
    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", button, "CENTER", 0, 0)
    icon:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01")
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(52, 52)
    border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    local db, dragging, suppressClick
    local function Position()
        local angle = math.rad(db and db.minimapAngle or 200)
        button:ClearAllPoints()
        button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * (Minimap:GetWidth() / 2 + 10),
            math.sin(angle) * (Minimap:GetHeight() / 2 + 10))
    end
    local function Drag()
        local x, y = GetCursorPosition()
        local cx, cy = Minimap:GetCenter()
        if not x or not y or not cx or not cy then return end
        local scale = Minimap:GetEffectiveScale()
        local dx = (x / scale - cx) / (Minimap:GetWidth() / 2 + 10)
        local dy = (y / scale - cy) / (Minimap:GetHeight() / 2 + 10)
        if dx == 0 and dy == 0 then return end
        db.minimapAngle = math.deg(math.atan2(dy, dx)) % 360
        Position()
    end
    local function StopDrag()
        dragging = false
        button:SetScript("OnUpdate", nil)
    end
    local function FinishDrag()
        if dragging then Drag() end
        StopDrag()
    end
    button:RegisterEvent("ADDON_LOADED")
    button:SetScript("OnEvent", function(self, _, name)
        if name ~= addonName then return end
        if type(AddonCPUDB) ~= "table" then AddonCPUDB = {} end
        db = AddonCPUDB
        local angle = db.minimapAngle
        if type(angle) ~= "number" or angle ~= angle or angle == math.huge or angle == -math.huge then
            angle = 200
        end
        db.minimapAngle = angle % 360
        self:UnregisterEvent("ADDON_LOADED")
        self:SetScript("OnEvent", nil)
        Position()
    end)
    button:SetScript("OnMouseDown", function(_, mouseButton)
        if mouseButton == "LeftButton" then StopDrag(); suppressClick = false end
    end)
    button:SetScript("OnMouseUp", function(_, mouseButton)
        if mouseButton == "LeftButton" then FinishDrag() end
    end)
    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "LeftButton" and not dragging and not suppressClick then ToggleWindow() end
    end)
    button:SetScript("OnDragStart", function(self)
        if not db then return end
        dragging, suppressClick = true, true
        HideTooltip(self)
        self:SetScript("OnUpdate", function()
            if IsMouseButtonDown("LeftButton") then Drag() else FinishDrag() end
        end)
        Drag()
    end)
    button:SetScript("OnDragStop", FinishDrag)
    button:SetScript("OnEnter", function(self)
        if dragging then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("插件耗时")
        GameTooltip:AddLine("左键：打开 / 关闭窗口", 1, 1, 1)
        GameTooltip:AddLine("按住左键拖动：沿小地图边缘移动并保存位置", 1, 1, 1)
        GameTooltip:AddLine("数据需在窗口内手动刷新", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", HideTooltip)
    button:SetScript("OnHide", function(self) StopDrag(); HideTooltip(self) end)
    button:SetScript("OnShow", Position)
    Position()
    A.minimapButton = button
end
