-- Use the native tooltip callback; do not replace protected action or spellbook handlers. Solazhu.
local _, A = ...
local L = A.Logic
local label = "效率："
local reasons = { missing="数据未就绪", not_applicable="不适用", unsupported="无法估算",
    locale="语言未支持", mana="耗蓝未知", free="当前免耗蓝", time="时间未知" }
local sources = {GetSpellBookItem=true, GetAction=true, GetSpellByID=true}
local effectStyles = {
    {"healing", "治疗", "|cff66b3ff"},
    {"damage", "伤害", "|cffff6666"},
    {"absorb", "吸收", "|cff66b3ff"},
}
local installed, lineIndex = false, nil
local channelTimes = {}

local function currentHaste()
    if type(UnitSpellHaste) ~= "function" then return end
    local ok, value = pcall(UnitSpellHaste, "player")
    if ok and L.Readable(value) and type(value) == "number" and L.Number(value + 100) and value > -100 then
        return value
    end
end

local function spellBookInfo(id)
    if not C_SpellBook or not C_SpellBook.FindSpellBookSlotForSpell or not C_SpellBook.GetSpellBookItemInfo then return end
    -- Find the exact hovered rank, including low ranks hidden by the native spellbook UI.
    local slot, bank = C_SpellBook.FindSpellBookSlotForSpell(id, true, false, false, false)
    if not slot or bank ~= Enum.SpellBookSpellBank.Player then return end
    local info = C_SpellBook.GetSpellBookItemInfo(slot, bank)
    if not info or info.itemType ~= Enum.SpellBookItemType.Spell or info.isOffSpec
        or not L.Number(info.skillLineIndex) or info.skillLineIndex < 2 then return end
    if info.spellID ~= id then return end
    return info
end

local function recordChannel(id)
    if not L.Number(id) or id <= 0 then return end
    channelTimes[id] = nil
    local info = spellBookInfo(id)
    if not info or info.isPassive or type(UnitChannelInfo) ~= "function" then return end
    local _, _, _, kind = L.Effects(C_Spell.GetSpellDescription(id), GetLocale())
    if kind ~= "penance" then return end
    local _, _, _, startMS, endMS, _, _, channelID = UnitChannelInfo("player")
    if not L.Number(channelID) or channelID ~= id or not L.Number(startMS)
        or not L.Number(endMS) or endMS <= startMS then return end
    -- The initial scheduled span already includes client modifiers. Never time an early stop.
    channelTimes[id] = {seconds=(endMS - startMS) / 1000, haste=currentHaste()}
end

local function estimate(id, data, info)
    if info.isPassive then return reasons.not_applicable end
    local spell = C_Spell.GetSpellInfo(id)
    if not spell or spell.spellID ~= id then return reasons.missing end
    local mana, costReason = L.ManaCost(C_Spell.GetSpellPowerCost(id))
    if costReason == "not_applicable" then return reasons.not_applicable end
    local descriptions, channelled, channelSeconds = {}, false, nil
    for _, line in ipairs(data.lines or {}) do
        if line.type == Enum.TooltipDataLineType.SpellDescription then
            if not L.Readable(line.leftText) then return "暂不可用" end
            if type(line.leftText) == "string" and line.leftText ~= "" then
                descriptions[#descriptions + 1] = line.leftText
            end
        elseif L.IsChannel(line.leftText) or L.IsChannel(line.rightText) then
            channelled = true
            channelSeconds = L.ChannelSeconds(line.leftText) or L.ChannelSeconds(line.rightText) or channelSeconds
        end
    end
    local description = #descriptions > 0 and table.concat(descriptions, "\n") or C_Spell.GetSpellDescription(id)
    local effects, reason, seconds, kind = L.Effects(description, GetLocale())
    if not effects then return reasons[reason] or reasons.unsupported end
    local haste = currentHaste()
    local measured = kind == "penance" and channelTimes[id]
    if measured then
        if measured.haste == haste then channelSeconds = measured.seconds
        else channelTimes[id] = nil end
    end
    -- Forever spell haste scales GCD within 1.0-1.5s (forever-bugs #389).
    -- Cast time is already supplied by the client; do not apply haste to it again.
    local gcdMS = 1500
    if type(GetSpellBaseCooldown) == "function" then
        local ok, _, base = pcall(GetSpellBaseCooldown, id)
        if ok and L.Number(base) then gcdMS = base end
    end
    if gcdMS > 0 then
        -- Until haste is readable, keep the base GCD (or the caster 1.5s default).
        if haste then
            gcdMS = math.max(math.min(gcdMS, 1000), math.min(gcdMS, 1500, gcdMS / (1 + haste / 100)))
        end
    end
    local parts = {}
    for _, style in ipairs(effectStyles) do
        local effect = effects[style[1]]
        if effect then
            local score, failure = L.Score(effect, mana, spell.castTime, gcdMS, channelled,
                channelSeconds or seconds, A.Settings.GetWeight())
            if not score then return reasons[failure] or reasons.unsupported end
            local value = score < 0.005 and "<0.01" or string.format("%.2f", score)
            parts[#parts + 1] = style[3] .. style[2] .. " " .. value .. "|r"
        end
    end
    return table.concat(parts, "  ")
end

local function setLine(tooltip, value)
    local text = label .. value
    local name = tooltip:GetName()
    local line = name and lineIndex and lineIndex <= tooltip:NumLines() and _G[name .. "TextLeft" .. lineIndex]
    if line then
        local previous = line:GetText()
        if L.Readable(previous) and type(previous) == "string" and previous:sub(1, #label) == label then
            line:SetText(text)
            return
        end
    end
    tooltip:AddLine(text, 0.55, 0.85, 1)
    lineIndex = tooltip:NumLines()
end

local function onTooltip(tooltip, data, source)
    if not A.Settings.IsEnabled() then return end
    if tooltip ~= GameTooltip or tooltip:IsForbidden() then return end
    local _, class = UnitClass("player")
    if not L.SupportsClass(class) then return end
    source = source or tooltip:GetProcessingTooltipInfo()
    if not source or not sources[source.getterName] or source.append then return end
    if not data or data.type ~= Enum.TooltipDataType.Spell or not L.Number(data.id) or data.id <= 0 then return end
    -- Fail one hover locally; no persistent error state or work queue can block the next spell.
    local ok, info = pcall(spellBookInfo, data.id)
    if not ok or not info then return end
    local succeeded, value = pcall(estimate, data.id, data, info)
    setLine(tooltip, succeeded and value or "暂不可用")
    return true
end

function A.RefreshTooltip(rebuild)
    if not A.Settings.IsEnabled() then channelTimes = {} end
    if not installed or GameTooltip:IsForbidden() or not GameTooltip:IsShown() then return end
    local info = GameTooltip:GetPrimaryTooltipInfo()
    if not info or not sources[info.getterName] or info.append or not info.tooltipData
        or info.tooltipData.type ~= Enum.TooltipDataType.Spell then return end
    if not A.Settings.IsEnabled() or rebuild then
        -- Native rebuilding re-queries the original getter, including changed channel headers.
        if lineIndex then GameTooltip:RebuildFromTooltipInfo() end
    elseif onTooltip(GameTooltip, info.tooltipData, info) then
        GameTooltip:Show()
    end
end

local events = CreateFrame("Frame")
local function install()
    if installed then return end
    if not IsLoggedIn() then return end
    local _, class = UnitClass("player")
    if not L.SupportsClass(class) then
        events:UnregisterEvent("PLAYER_LOGIN"); events:UnregisterEvent("ADDON_LOADED")
        return
    end
    if not TooltipDataProcessor or not TooltipDataProcessor.AddTooltipPostCall or not GameTooltip
        or not Enum or not Enum.TooltipDataType then return end
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, onTooltip)
    GameTooltip:HookScript("OnTooltipCleared", function() lineIndex = nil end)
    events:RegisterUnitEvent("UNIT_SPELL_HASTE", "player")
    if class == "PRIEST" then events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player") end
    installed = true
    events:UnregisterEvent("PLAYER_LOGIN"); events:UnregisterEvent("ADDON_LOADED")
end
events:SetScript("OnEvent", function(_, event, unit, _, spellID)
    if event == "UNIT_SPELLCAST_CHANNEL_START" then
        if unit ~= "player" then return end
        if not A.Settings.IsEnabled() then channelTimes = {}; return end
        pcall(recordChannel, spellID)
        if lineIndex then A.RefreshTooltip() end
    elseif event == "UNIT_SPELL_HASTE" then
        if unit ~= "player" then return end
        local haste = currentHaste()
        for id, measured in pairs(channelTimes) do
            if haste == nil or measured.haste ~= haste then channelTimes[id] = nil end
        end
        if lineIndex then A.RefreshTooltip(true) end
    else
        install()
    end
end)
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
if IsLoggedIn() then install() end
