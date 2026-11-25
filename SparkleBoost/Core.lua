-- SparkleBoost: lifecycle, settings and reversible CVar ownership.
-- Copyright (C) 2026 Sola. SPDX-License-Identifier: GPL-3.0-or-later
local ADDON, ns = ...
ns.name, ns.version = ADDON, "0.1.1-test"
ns.defaults = {
    enabled = true, native = true, enhanced = false,
    sparkleQuest = true, sparkleHerbs = true, sparkleOre = true,
    sparkleCorpseLoot = false, sparkleFootlocker = false,
    safeSelfCast = true, hidePlate = true,
    size = 1.5, brightness = 1, offsetY = -45, range = 15, arc = 1,
    style = "beacon", palette = "auto", minimapAngle = 225,
}
ns.colors = {
    quest = {1, 0.82, 0.28}, herb = {0.30, 1, 0.45}, ore = {1, 0.52, 0.18},
    corpseLoot = {0.74, 0.50, 1}, footlocker = {0.30, 0.78, 1},
}
ns.palettes = {gold = {1, 0.82, 0.28}, cyan = {0.30, 0.85, 1}, violet = {0.85, 0.50, 1}}
local db, initialized, loggedIn, writing
local managedGroups = {
    outlineModeShowLootEffectWhenDisabled = "native",
    SoftTargetInteract = "soft", SoftTargetNameplateInteract = "soft",
    SoftTargetInteractRange = "soft", SoftTargetInteractArc = "soft",
    SoftTargetInteractOnlyInRange = "soft", SoftTargetIconGameObject = "soft",
}
local scheduler = CreateFrame("Frame")
local jobs = {}
scheduler:Hide()
scheduler:SetScript("OnUpdate", function(self)
    local now = GetTime()
    local due = {}
    for key, job in pairs(jobs) do
        if now >= job.at then due[#due + 1] = {key, job} end
    end
    for _, entry in ipairs(due) do
        if jobs[entry[1]] == entry[2] then
            jobs[entry[1]] = nil
            entry[2].callback()
        end
    end
    if next(jobs) == nil then self:Hide() end
end)

function ns.After(key, seconds, callback)
    jobs[key] = {at = GetTime() + seconds, callback = callback}
    scheduler:Show()
end

function ns.IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value)
end

function ns.SafeCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok and not ns.IsSecret(value) then return value end
end

function ns.Print(message)
    print("|cffffd166拾光：|r" .. tostring(message))
end

function ns.GetCVar(name)
    local value = ns.SafeCall(C_CVar and C_CVar.GetCVar or GetCVar, name)
    if type(value) == "string" or type(value) == "number" then return tostring(value) end
end

local function WriteCVar(name, value)
    if not ns.supported or InCombatLockdown() then return false end
    local setter = C_CVar and C_CVar.SetCVar or SetCVar
    if type(setter) ~= "function" then return false end
    writing = true
    local ok = pcall(setter, name, value)
    writing = false
    return ok and ns.GetCVar(name) == value
end

-- Save before writing: CVAR_UPDATE can run synchronously inside SetCVar.
-- Unknown CVars are never registered or written.
function ns.SetManagedCVar(name, value, group)
    if not db or not ns.supported or InCombatLockdown() then return false end
    if managedGroups[name] ~= group then return false end
    local current = ns.GetCVar(name)
    if current == nil then
        ns.lastError = "客户端未开放 " .. name
        return false
    end
    value = tostring(value)
    local entry = db.journal[name]
    if current == value then return true end
    local previousLast = entry and entry.last
    if not entry then
        entry = {original = current, group = group}
        db.journal[name] = entry
    end
    entry.last = value
    if WriteCVar(name, value) then return true end
    entry.last = previousLast
    if previousLast == nil then db.journal[name] = nil end
    ns.lastError = "设置未生效：" .. name
    return false
end

-- An external edit wins: only restore values still owned by this addon.
function ns.RestoreCVars(group)
    if not db then return true end
    if InCombatLockdown() then ns.pendingRestore = true; return false end
    local allRestored = true
    for name, entry in pairs(db.journal) do
        if group == nil or entry.group == group then
            local current = ns.GetCVar(name)
            if current ~= entry.last or current == entry.original then
                db.journal[name] = nil
            elseif WriteCVar(name, entry.original) then
                db.journal[name] = nil
            else
                allRestored = false
            end
        end
    end
    return allRestored
end

function ns.FindConflict()
    ns.conflict = nil
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    for _, name in ipairs({"Lueur", "ForeverLootSparkles_Coloring", "ForeverLootSparkles_HerbsOres"}) do
        if ns.SafeCall(loaded, name) == true then ns.conflict = name; break end
    end
    return ns.conflict
end

function ns.CanEnhance()
    return db and db.enabled and db.enhanced and ns.supported and not ns.conflict
end

function ns.Apply()
    if not initialized or not loggedIn then return end
    if InCombatLockdown() then ns.pendingApply = true; return end
    ns.pendingApply, ns.pendingRestore = nil, nil
    ns.lastError = nil
    ns.FindConflict()
    if db.enabled and db.native and ns.supported then
        ns.SetManagedCVar("outlineModeShowLootEffectWhenDisabled", 1, "native")
    else
        ns.RestoreCVars("native")
    end
    if ns.EngineRefresh then ns.EngineRefresh() end
    if ns.UIRefresh then ns.UIRefresh() end
end

local limits = {size = {0.6, 3}, brightness = {0.25, 1.5}, offsetY = {-120, 40}, range = {5, 15}, arc = {1, 2}, minimapAngle = {0, 360}}
local function Finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function ns.SetOption(key, value)
    if not db or ns.defaults[key] == nil then return false end
    local limit = limits[key]
    if limit then
        value = tonumber(value)
        if not Finite(value) then return false end
        value = math.max(limit[1], math.min(limit[2], value))
        if key == "arc" then value = math.floor(value) end
    elseif type(ns.defaults[key]) == "boolean" then
        if type(value) ~= "boolean" then return false end
    elseif key == "style" then
        if value ~= "beacon" and value ~= "sparkles" and value ~= "ring" then return false end
    elseif key == "palette" then
        if value ~= "auto" and ns.palettes[value] == nil then return false end
    end
    db[key] = value
    -- Self-cast protection stays enabled in this version.
    db.safeSelfCast = true
    if ns.RefreshEffects then ns.RefreshEffects() end
    ns.Apply()
    return true
end

function ns.RestoreAll()
    if not db then return end
    db.enabled = false
    if ns.EngineStop then ns.EngineStop() end
    ns.RestoreCVars()
    if ns.UIRefresh then ns.UIRefresh() end
    ns.Print("已停用并请求恢复安装前的设置。战斗中的恢复会延后；原生闪光关闭后可能要完全退出游戏再登录。")
end

function ns.GetStatus()
    if not ns.supported then return "当前客户端接口不受支持，未应用增强。" end
    if ns.conflict then return "增强已暂停：请先停用 " .. ns.conflict .. " 的同类效果。" end
    if not db.enabled then return "已停用；可点击启用，或保留原设置。" end
    if InCombatLockdown() then return "战斗中暂停新增光效，设置将在脱战后应用。" end
    if ns.lastError then return ns.lastError .. "；输入 /sg status 查看详情。" end
    if not db.enhanced then
        return db.native and "原生闪光保持；附近增强已关闭。" or "原生闪光保持与附近增强均已关闭。"
    end
    return "附近增强已启用；实际效果等待游戏内验证。"
end

local function Initialize()
    if initialized then return end
    if type(SparkleBoostDB) ~= "table" then SparkleBoostDB = {} end
    db, ns.db = SparkleBoostDB, SparkleBoostDB
    for key, default in pairs(ns.defaults) do
        if db[key] == nil or type(db[key]) ~= type(default) then db[key] = default end
        local limit = limits[key]
        if limit then
            if not Finite(db[key]) then db[key] = default end
            db[key] = math.max(limit[1], math.min(limit[2], db[key]))
        end
    end
    if db.style ~= "beacon" and db.style ~= "ring" and db.style ~= "sparkles" then db.style = "beacon" end
    if db.palette ~= "auto" and not ns.palettes[db.palette] then db.palette = "auto" end
    db.safeSelfCast, db.schema = true, 1
    if type(db.journal) ~= "table" then db.journal = {} end
    for name, entry in pairs(db.journal) do
        if type(name) ~= "string" or type(entry) ~= "table" or type(entry.original) ~= "string"
            or type(entry.last) ~= "string" or managedGroups[name] ~= entry.group then
            db.journal[name] = nil
        end
    end
    local _, _, _, interface = GetBuildInfo()
    ns.supported = tonumber(interface) == 16001
    ns.FindConflict()
    initialized = true
    if ns.SparkleInit then ns.SparkleInit(db) end
end

local events = CreateFrame("Frame")
for _, event in ipairs({"ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_LOGOUT", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "CVAR_UPDATE"}) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, arg)
    if event == "ADDON_LOADED" then
        if arg == ADDON then Initialize() end
        if initialized and loggedIn then ns.After("apply", 1, ns.Apply) end
    elseif event == "PLAYER_LOGIN" then
        Initialize()
        loggedIn = true
        if ns.CreateMinimapButton then ns.CreateMinimapButton() end
        ns.Apply()
        ns.After("apply", 2, ns.Apply)
        ns.Print("0.1.1 测试版已加载。点击小地图按钮或输入 /sg 打开设置。")
    elseif event == "PLAYER_REGEN_ENABLED" then
        if initialized then ns.Apply() end
    elseif event == "PLAYER_REGEN_DISABLED" then
        if ns.UIRefresh then ns.UIRefresh() end
    elseif event == "PLAYER_LOGOUT" then
        loggedIn = false
        if ns.EngineStop then ns.EngineStop(true) end
        ns.RestoreCVars()
    elseif event == "CVAR_UPDATE" and not writing and initialized and type(arg) == "string" then
        arg = arg:lower()
        if arg == "graphicsquality" or arg == "raidgraphicsquality" or arg == "outlinemodeshowlooteffectwhendisabled" then
            ns.After("apply", 1, ns.Apply)
        end
    end
end)

function ns.StatusCommand()
    ns.Print(ns.GetStatus())
    local version, build, _, interface = GetBuildInfo()
    ns.Print("客户端 " .. tostring(version) .. "." .. tostring(build) .. " / 接口 " .. tostring(interface))
    for _, name in ipairs({"outlineModeShowLootEffectWhenDisabled", "graphicsOutlineMode", "SoftTargetInteract", "SoftTargetNameplateInteract", "SoftTargetInteractRange"}) do
        ns.Print(name .. " = " .. tostring(ns.GetCVar(name) or "未开放"))
    end
    if ns.DebugTarget then ns.DebugTarget() end
end

SLASH_SPARKLEBOOST1, SLASH_SPARKLEBOOST2 = "/sg", "/sparkleboost"
SlashCmdList.SPARKLEBOOST = function(message)
    if not initialized then Initialize() end
    local command, argument = (message or ""):match("^%s*(%S*)%s*(.-)%s*$")
    command = command:lower()
    if command == "" or command == "test" then
        if ns.ToggleOptions then ns.ToggleOptions(command == "test") end
    elseif command == "on" or command == "off" then ns.SetOption("enabled", command == "on")
    elseif command == "restore" then ns.RestoreAll()
    elseif command == "status" then ns.StatusCommand()
    elseif command == "size" or command == "range" then
        if not ns.SetOption(command, argument) then ns.Print("请输入有效数字。") end
    elseif command == "brightness" then
        if not ns.SetOption(command, tonumber(argument) and tonumber(argument) / 100) then ns.Print("亮度范围为 25–150。") end
    elseif command == "style" or command == "palette" then
        if not ns.SetOption(command, argument:lower()) then ns.Print("样式：beacon / sparkles / ring；配色：auto / gold / cyan / violet。") end
    else
        ns.Print("/sg 打开设置；on / off 启停；status 诊断；restore 恢复原设置；test 预览。")
    end
end
