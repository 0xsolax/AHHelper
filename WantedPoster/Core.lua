local _, addon = ...
local Roster, Macros, Panel = addon.Roster, addon.Macros, addon.Panel
local App = {}
local clearDialog = "WANTEDPOSTER_CLEAR_PAGE"
local secret = issecretvalue or function() return false end

function App:Status(message, warning)
    if self.frame and self.frame:IsShown() then
        Panel.Status(self.frame, message, warning)
    else
        print("通缉令  " .. message)
    end
end

function App:Refresh(readOnly)
    if not self.frame or not self.currentGroup or InCombatLockdown() then
        return
    end
    local groups = self.database.groups
    local group = groups[self.groupIndex]
    local pages = Roster.Pages(group)
    self.pageIndex = math.min(self.pageIndex, #pages)
    local view = {
        group = group,
        groupIndex = self.groupIndex,
        groupCount = #groups,
        groupLabel = self.groupIndex == self.currentGroup and "本次登录" or date("%m月%d日 %H:%M", group.started),
        pageIndex = self.pageIndex,
        pageCount = #pages,
        page = pages[self.pageIndex],
    }

    local editorOpen = MacroFrame and MacroFrame:IsShown()
    if editorOpen and self.macroEditor ~= MacroFrame then
        self.macroEditor = MacroFrame
        MacroFrame:HookScript("OnHide", function()
            C_Timer.After(0, function()
                if self.frame:IsShown() or self.database.macroCleanup then self:Refresh() end
            end)
        end)
    end

    self.syncing = true
    local bindings, complete, pending = Macros.Sync(self.database, view.page, not (readOnly or editorOpen))
    self.syncing = false
    self.view = view
    Panel.Draw(self.frame, view, bindings)
    if self.database.macroCleanup then
        local message = editorOpen and "关闭游戏宏窗口后清理查找宏。" or "对应的查找宏待清理。"
        Panel.Status(self.frame, message, editorOpen)
    elseif complete then
        Panel.Status(self.frame, self.message or ("本组共 %d 人"):format(#group.names), false)
    elseif pending then
        Panel.Status(self.frame, "正在同步查找宏。", false)
        C_Timer.After(0, function()
            if self.frame:IsShown() then self:Refresh(true) end
        end)
    elseif editorOpen then
        Panel.Status(self.frame, "关闭游戏宏窗口后更新查找。", true)
    else
        Panel.Status(self.frame, "有查找宏尚未匹配当前名单。", true)
    end
end

function App:Toggle()
    if InCombatLockdown() then
        self:Status("脱战后可以打开或关闭面板。", true)
        return
    end
    if not self.currentGroup then
        return
    end
    if self.frame and self.frame:IsShown() then
        self.frame:Hide()
        return
    end
    self.frame = self.frame or Panel.Create(self)
    self.message = nil
    self:Refresh()
    self.frame:Show()
end

function App:AddName(name)
    if not Roster.Add(self.database.groups[self.currentGroup], name) then
        self:Status("本次名单已记录此人。")
        return
    end
    self.groupIndex = self.currentGroup
    self.pageIndex = math.huge
    self.message = "已加入通缉令。"
    if InCombatLockdown() then
        self:Status("已记下，脱战后更新查找。")
    else
        self:Refresh()
    end
end

function App:AddTarget()
    local player = UnitIsPlayer("target")
    if secret(player) or not player then
        self:Status("请先选中一名玩家。", true)
        return
    end
    local first, last = UnitName("target")
    if secret(first) or secret(last) or type(first) ~= "string" then
        self:Status("当前目标姓名不可读，可以粘贴加入。", true)
        return
    end
    local name = Roster.Normalize(first)
    if not name and type(last) == "string" then
        name = Roster.Normalize(first .. " " .. last)
    end
    if not name then
        self:Status("未取得完整姓名，可以粘贴加入。", true)
        return
    end
    self:AddName(name)
end

function App:AddPasted(value)
    local name = Roster.Normalize(value)
    if not name then
        self:Status("请粘贴一个完整角色名（名 姓）。", true)
        return
    end
    self.frame.input:SetText("")
    self.frame.input:ClearFocus()
    self:AddName(name)
end

function App:MoveGroup(step)
    if InCombatLockdown() then return end
    self.groupIndex = math.max(1, math.min(self.currentGroup, self.groupIndex + step))
    self.pageIndex = 1
    self.message = nil
    self:Refresh()
end

function App:MovePage(step)
    if InCombatLockdown() then return end
    self.pageIndex = math.max(1, math.min(self.view.pageCount, self.pageIndex + step))
    self.message = nil
    self:Refresh()
end

function App:Remove(slot, selected)
    if InCombatLockdown() then
        self:Status("脱战后可以清理名单。", true)
        return
    end
    local view = selected or self.view
    local page = view.page
    local names = view.group.names
    local first = slot or 1
    local last = slot or #page.names
    if not page.names[first] then return end
    for row = first, last do
        if names[page.first + row - 1] ~= page.names[row] then
            self:Status("名单已变动，请重新选择要清理的记录。", true)
            return
        end
    end
    if not slot then Macros.QueuePageCleanup(self.database, page) end
    for row = last, first, -1 do
        table.remove(names, page.first + row - 1)
    end
    self.message = slot and "已移除这条记录。" or "已清空所选页。"
    self:Refresh()
end

StaticPopupDialogs[clearDialog] = {
    text = "清空这页的 %d 条通缉记录，并删除对应的查找宏？",
    button1 = "清空",
    button2 = CANCEL,
    timeout = 0,
    hideOnEscape = true,
    whileDead = true,
    OnAccept = function(_, view) App:Remove(nil, view) end,
}

function App:ConfirmClear()
    if not InCombatLockdown() and #self.view.page.names > 0 then
        StaticPopup_Show(clearDialog, #self.view.page.names, nil, self.view)
    end
end

local visiblePlates, alertUntil = {}, {}
local alertCooldown = 30

local function isNameplateToken(unit)
    return not secret(unit) and type(unit) == "string" and unit:match("^nameplate%d+$") ~= nil
end

local function readableEnemyName(unit)
    if C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret then
        local hidden = C_Secrets.ShouldUnitIdentityBeSecret(unit)
        if secret(hidden) or hidden ~= false then return end
    end
    local player = UnitIsPlayer(unit)
    if secret(player) or player ~= true then return end
    local enemy = UnitIsEnemy("player", unit)
    if secret(enemy) or enemy ~= true then return end

    local first, last = UnitName(unit)
    if secret(first) or secret(last) or type(first) ~= "string" then return end
    if last ~= nil and type(last) ~= "string" then return end
    local name = Roster.Normalize(first)
    if last == nil or last == "" then return name end
    if not name then return Roster.Normalize(first .. " " .. last) end

    -- An explicitly returned realm must be part of the full matching name.
    local suffix = "-" .. last
    if name:sub(-#suffix) == suffix then return name end
end

local function hasWantedName(groups, key)
    for _, group in ipairs(groups) do
        for _, name in ipairs(group.names) do
            if type(name) == "string" and name:lower() == key then return true end
        end
    end
    return false
end

function App:NameplateAdded(unit)
    if not self.database or not isNameplateToken(unit) then return end
    local previous = visiblePlates[unit]
    visiblePlates[unit] = nil
    local ok, name = pcall(readableEnemyName, unit)
    if not ok or not name then return end

    local key = name:lower()
    if not hasWantedName(self.database.groups, key) then return end
    visiblePlates[unit] = key
    if previous == key then return end

    local now = GetTime()
    for alerted, expires in pairs(alertUntil) do
        if expires <= now then alertUntil[alerted] = nil end
    end
    if alertUntil[key] or not UIErrorsFrame then return end
    if pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, "通缉目标出现：" .. name, 1, 0.82, 0.2, 1) then
        alertUntil[key] = now + alertCooldown
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("UPDATE_MACROS")
events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
events:SetScript("OnEvent", function(self, event, arg1, reloadingUI)
    if event == "PLAYER_ENTERING_WORLD" then
        local initialLogin = arg1
        WantedPosterDB = WantedPosterDB or {}
        App.database = WantedPosterDB
        App.currentGroup = Roster.Open(App.database, initialLogin and not reloadingUI, time())
        App.groupIndex = App.currentGroup
        App.pageIndex = 1
        self:UnregisterEvent(event)
        Panel.CreateMinimapButton(App)
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        App:NameplateAdded(arg1)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        if isNameplateToken(arg1) then visiblePlates[arg1] = nil end
    elseif event == "PLAYER_REGEN_ENABLED" and App.database and App.database.macroCleanup then
        App:Refresh()
    elseif App.frame and App.frame:IsShown() then
        if event == "PLAYER_REGEN_DISABLED" then
            Panel.Controls(App.frame, true, App.view)
            App:Status("战斗中可查找当前页。")
        elseif event == "PLAYER_REGEN_ENABLED" then
            App:Refresh()
        elseif event == "UPDATE_MACROS" and not App.syncing then
            App:Refresh(true)
        end
    end
end)

SLASH_WANTEDPOSTER1 = "/wanted"
SlashCmdList.WANTEDPOSTER = function() App:Toggle() end
