-- Exercise real addon entry points against the existing UI simulator. Solazhu.
dofile(PROJECT_ROOT .. "/tests/wow_mock.lua")
Minimap = CreateFrame("Frame", "Minimap", UIParent)
Minimap:SetSize(140, 140)
Minimap:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -20)
local frameType = getmetatable(Minimap)
function frameType:GetFrameLevel() return self.frameLevel or 1 end
function frameType:SetFrameLevel(level) self.frameLevel = level end
function frameType:RegisterForClicks(...) self.clicks = {...} end
local passed, reading, metricCalls, listCalls = 0, false, 0, 0
local firstFrame = #MOCK.frames + 1
local enabled, failName = true, nil
local addons = {}
function GameTooltip:SetOwner(owner) self.owner = owner end
function GameTooltip:IsOwned(owner) return self.owner == owner end
local function test(name, callback)
    local ok, err = pcall(callback)
    if not ok then error(name .. ": " .. tostring(err)) end
    passed = passed + 1; print("PASS " .. name)
end
local function eq(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function forbidden() error("Background work or game setting mutation is forbidden") end
C_Timer = {After = forbidden, NewTimer = forbidden, NewTicker = forbidden}
SetCVar, ResetCPUUsage, UpdateAddOnCPUUsage = forbidden, forbidden, forbidden
C_CVar = {SetCVar = forbidden}
Enum.AddOnProfilerMetric = {SessionAverageTime = 0, PeakTime = 4}
C_AddOns = {
    GetNumAddOns = function()
        assert(reading, "enumeration outside manual refresh")
        listCalls = listCalls + 1; return #addons
    end,
    GetAddOnInfo = function(index)
        assert(reading, "metadata outside manual refresh")
        local a = addons[index]
        return a.name, a.title or a.name, "", true, "", a.security or "INSECURE"
    end,
    IsAddOnLoaded = function(index)
        assert(reading, "load check outside manual refresh")
        return addons[index].loaded ~= false, addons[index].loaded ~= false
    end,
}
C_AddOnProfiler = {
    IsEnabled = function() assert(reading); return enabled end,
    GetAddOnMetric = function(name, metric)
        assert(reading, "metric outside manual refresh")
        metricCalls = metricCalls + 1
        if name == failName then error("simulated metric read failure") end
        for _, a in ipairs(addons) do
            if a.name == name then
                if metric == 0 then return a.average end
                if metric == 4 then return a.peak end
                error("wrong metric")
            end
        end
        error("unknown addon")
    end,
}
local A = {}
for line in io.lines(ADDON_DIR .. "/AddonCPU.toc") do
    local entry = line:match("^%s*(.-)%s*$")
    if entry ~= "" and entry:sub(1, 1) ~= "#" then
        assert(loadfile(ADDON_DIR .. "/" .. entry))("AddonCPU", A)
    end
end
local function refresh()
    reading = true
    local ok, err = pcall(function() A.UI.refresh:Click() end)
    reading = false
    assert(ok, err)
end
local function basicData()
    addons = {
        {name = "Fast", title = "轻量插件", average = 0, peak = 0},
        {name = "Slow", title = "耗时插件", average = 2.25, peak = 8.5},
        {name = "Disabled", loaded = false, average = 900, peak = 999},
        {name = "Blizzard_Test", security = "SECURE", average = 800, peak = 999},
        {name = "AddonCPU", title = "插件耗时", average = 0.02, peak = 0.12},
    }
end

test("load provides a minimap entry without opening the main UI or reading metrics", function()
    assert(A.minimapButton and A.minimapButton:IsVisible())
    eq(A.minimapButton:GetParent(), Minimap); eq(A.UI, nil)
    eq(metricCalls, 0); eq(listCalls, 0)
    eq(SLASH_ADDONCPU1, "/addoncpu"); assert(SlashCmdList.ADDONCPU)
end)
test("first minimap click opens the window without collecting data", function()
    A.minimapButton:Click()
    assert(A.UI.frame:IsShown()); eq(metricCalls, 0); eq(listCalls, 0)
    assert(A.UI.status:GetText():find("尚未刷新", 1, true))
end)
test("minimap and command toggle the same window without rebuilding it", function()
    local frame, count = A.UI.frame, #MOCK.frames
    A.minimapButton:Click(); assert(not frame:IsShown())
    SlashCmdList.ADDONCPU(); assert(frame:IsShown())
    eq(A.UI.frame, frame); eq(#MOCK.frames, count); eq(metricCalls, 0); eq(listCalls, 0)
end)
test("minimap hover only displays an owned help tooltip", function()
    local button, before = A.minimapButton, metricCalls
    button.scripts.OnEnter(button)
    assert(GameTooltip:IsOwned(button)); eq(GameTooltip:GetText(), "插件耗时")
    assert(GameTooltip:IsShown()); button.scripts.OnLeave(button)
    assert(not GameTooltip:IsShown()); eq(metricCalls, before)
    GameTooltip:SetOwner(UIParent); GameTooltip:Show()
    button.scripts.OnHide(button); assert(GameTooltip:IsShown()); GameTooltip:Hide()
end)
test("unsupported client before the first refresh shows an error and no fake snapshot", function()
    local api = C_AddOnProfiler; C_AddOnProfiler = nil
    refresh(); C_AddOnProfiler = api
    eq(A.snapshot, nil); eq(metricCalls, 0); eq(listCalls, 0)
    assert(A.UI.message:GetText():find("不支持", 1, true))
    assert(not A.UI.status:GetText():find("上次", 1, true))
    for _, row in ipairs(A.UI.rows) do assert(not row:IsShown()) end
end)
test("manual refresh reads loaded user addons including itself, ordered by average", function()
    basicData(); refresh()
    eq(listCalls, 1); eq(metricCalls, 6); eq(#A.snapshot.entries, 3)
    eq(A.snapshot.entries[1].name, "Slow"); eq(A.snapshot.entries[2].name, "AddonCPU")
    eq(A.snapshot.entries[3].name, "Fast")
    eq(A.UI.rows[1].average:GetText(), "2.250")
    eq(A.UI.rows[1].peak:GetText(), "8.500")
end)
test("real zero values remain zero rather than missing data", function()
    eq(A.UI.rows[3].average:GetText(), "0.000")
    eq(A.UI.rows[3].peak:GetText(), "0.000")
end)
test("name tooltip is read-only and shows the complete addon title", function()
    local before = metricCalls; local row = A.UI.rows[1]
    row.scripts.OnEnter(row)
    eq(GameTooltip:GetText(), "耗时插件"); assert(GameTooltip:IsShown())
    assert(GameTooltip:IsOwned(row)); row.scripts.OnLeave(row)
    assert(not GameTooltip:IsShown()); eq(metricCalls, before)
end)
test("hiding an unused row never dismisses another UI's tooltip", function()
    GameTooltip:SetOwner(UIParent); GameTooltip:Show()
    local row = A.UI.rows[1]; row.scripts.OnHide(row)
    assert(GameTooltip:IsShown()); GameTooltip:Hide()
end)
test("time passing and reopening preserve the snapshot without a read", function()
    local before = metricCalls
    addons[2].average = 12; MOCK.time = MOCK.time + 600; MOCK.flush()
    SlashCmdList.ADDONCPU(); assert(not A.UI.frame:IsShown())
    SlashCmdList.ADDONCPU(); assert(A.UI.frame:IsShown())
    eq(metricCalls, before); eq(A.snapshot.entries[1].average, 2.25)
    eq(A.UI.rows[1].average:GetText(), "2.250")
end)
test("repeated minimap toggles preserve the snapshot without queries or more frames", function()
    local before, count, snapshot = metricCalls, #MOCK.frames, A.snapshot
    for _ = 1, 30 do A.minimapButton:Click() end
    assert(A.UI.frame:IsShown()); eq(A.snapshot, snapshot)
    eq(metricCalls, before); eq(#MOCK.frames, count)
end)
test("minimap visibility changes leave the CPU window and snapshot alone", function()
    local before, snapshot = metricCalls, A.snapshot
    Minimap:Hide(); assert(not A.minimapButton:IsVisible())
    assert(A.UI.frame:IsShown()); eq(A.snapshot, snapshot)
    Minimap:Show(); assert(A.minimapButton:IsVisible()); eq(metricCalls, before)
end)
test("another manual refresh replaces the snapshot", function()
    local old = A.snapshot; refresh()
    assert(A.snapshot ~= old); eq(A.snapshot.entries[1].average, 12)
    eq(A.UI.rows[1].average:GetText(), "12.000")
end)
test("many addons remain reachable through pages without new metric reads", function()
    addons = {}
    for i = 1, 31 do addons[i] = {name = string.format("Addon%02d", i), average = 32 - i, peak = 50} end
    refresh(); local before = metricCalls
    assert(not A.UI.previous:IsEnabled()); assert(A.UI.next:IsEnabled())
    eq(A.UI.rows[1].entry.name, "Addon01")
    A.UI.next:Click(); eq(A.UI.rows[1].entry.name, "Addon13")
    A.UI.next:Click(); eq(A.UI.rows[1].entry.name, "Addon25")
    eq(A.UI.rows[7].entry.name, "Addon31"); assert(not A.UI.rows[8]:IsShown())
    assert(not A.UI.next:IsEnabled()); A.UI.previous:Click()
    eq(A.UI.rows[1].entry.name, "Addon13"); eq(metricCalls, before)
end)
test("refresh after list shrink returns to the first page and hides stale rows", function()
    basicData(); refresh()
    eq(A.UI.rows[1].entry.name, "Slow"); assert(not A.UI.rows[4]:IsShown())
    assert(not A.UI.previous:IsEnabled()); assert(not A.UI.next:IsEnabled())
end)
test("equal average values have deterministic name ordering", function()
    addons = {{name = "Zulu", average = 1, peak = 9}, {name = "Alpha", average = 1, peak = 2}}
    refresh(); eq(A.snapshot.entries[1].name, "Alpha")
end)
test("missing measurements do not fabricate zero and sort after measured addons", function()
    addons = {{name = "Unknown"}, {name = "Zero", average = 0, peak = 0}}
    refresh(); eq(A.snapshot.entries[1].name, "Zero")
    eq(A.UI.rows[2].average:GetText(), "无数据"); eq(A.UI.rows[2].peak:GetText(), "无数据")
end)
test("invalid numeric measurements are displayed as missing", function()
    for _, value in ipairs({-1, math.huge, 0/0, "2.5"}) do
        addons = {{name = "Invalid", average = value, peak = value}}; refresh()
        eq(A.UI.rows[1].average:GetText(), "无数据"); eq(A.UI.rows[1].peak:GetText(), "无数据")
    end
end)
test("tiny positive measurements are not rounded to apparent zero", function()
    addons = {{name = "Tiny", average = 0.00001, peak = 0.0001}}; refresh()
    eq(A.UI.rows[1].average:GetText(), "<0.001"); eq(A.UI.rows[1].peak:GetText(), "<0.001")
end)
test("missing profiler leaves old snapshot visibly stale", function()
    local api, old = C_AddOnProfiler, A.snapshot; C_AddOnProfiler = nil
    refresh(); C_AddOnProfiler = api
    eq(A.snapshot, old); assert(A.UI.status:GetText():find("上次", 1, true))
    assert(A.UI.message:GetText():find("不支持", 1, true))
end)
test("disabled profiler does not trigger any legacy profiling or metric reads", function()
    local before, old = metricCalls, A.snapshot; enabled = false
    refresh(); enabled = true
    eq(metricCalls, before); eq(A.snapshot, old)
    assert(A.UI.message:GetText():find("未启用", 1, true))
end)
test("missing metric enum fails visibly rather than using guessed identifiers", function()
    local value = Enum.AddOnProfilerMetric.PeakTime; Enum.AddOnProfilerMetric.PeakTime = nil
    local before = metricCalls; refresh(); Enum.AddOnProfilerMetric.PeakTime = value
    eq(metricCalls, before); assert(A.UI.message:GetText():find("不支持", 1, true))
end)
test("missing addon enumeration API is recoverable", function()
    local api, before = C_AddOns, metricCalls; C_AddOns = nil
    refresh(); C_AddOns = api; eq(metricCalls, before)
    assert(A.UI.message:GetText():find("不支持", 1, true))
end)
test("mid-snapshot API failure cannot publish a partially refreshed list", function()
    basicData(); refresh(); local old = A.snapshot
    addons[1].average = 42; failName = "Slow"; refresh(); failName = nil
    eq(A.snapshot, old); eq(A.UI.rows[1].entry.name, "Slow")
    assert(A.UI.status:GetText():find("上次", 1, true))
    assert(A.UI.message:GetText():find("读取失败", 1, true))
end)
test("next successful refresh recovers and clears prior error", function()
    refresh(); eq(A.UI.rows[1].entry.name, "Fast"); eq(A.UI.message:GetText(), "")
end)
test("empty results remove prior rows without manufacturing addon data", function()
    addons = {{name = "Disabled", loaded = false}, {name = "Blizzard_Test", security = "SECURE"}}
    refresh(); eq(#A.snapshot.entries, 0)
    for _, row in ipairs(A.UI.rows) do assert(not row:IsShown()) end
    assert(not A.UI.previous:IsEnabled()); assert(not A.UI.next:IsEnabled())
    assert(A.UI.pageLabel:GetText():find("0 个", 1, true))
end)
test("repeated refreshes reuse a bounded number of UI rows", function()
    basicData(); local count = #MOCK.frames
    for _ = 1, 30 do refresh() end
    eq(#MOCK.frames, count); eq(#A.UI.rows, 12)
end)
test("window close and escape registration do not change statistics", function()
    local before = metricCalls; A.UI.close:Click(); assert(not A.UI.frame:IsShown())
    eq(metricCalls, before); eq(UISpecialFrames[#UISpecialFrames], "AddonCPUFrame")
    SlashCmdList.ADDONCPU(); eq(metricCalls, before)
end)
test("no addon-owned frame registers background scripts or game events", function()
    for i = firstFrame, #MOCK.frames do
        local frame = MOCK.frames[i]
        eq(frame.scripts.OnUpdate, nil); eq(frame.scripts.OnEvent, nil)
        eq(frame.registered, nil)
    end
end)
print(string.format("AddonCPU: %d tests passed", passed))
