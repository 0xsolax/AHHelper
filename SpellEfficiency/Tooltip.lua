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

local function estimate(id, data, info)
    if info.isPassive then return reasons.not_applicable end
    local spell = C_Spell.GetSpellInfo(id)
    if not spell or spell.spellID ~= id then return reasons.missing end
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
    local effects, reason, seconds = L.Effects(description, GetLocale())
    if not effects then return reasons[reason] or reasons.unsupported end
    local mana = L.ManaCost(C_Spell.GetSpellPowerCost(id))
    -- Forever spell haste scales GCD within 1.0-1.5s (forever-bugs #389).
    -- Cast time is already supplied by the client; do not apply haste to it again.
    local gcdMS
    if type(GetSpellBaseCooldown) == "function" then local _; _, gcdMS = GetSpellBaseCooldown(id) end
    if L.Number(gcdMS) and gcdMS > 0 then
        local haste = type(UnitSpellHaste) == "function" and UnitSpellHaste("player")
        if not L.Readable(haste) or type(haste) ~= "number" or not L.Number(haste + 100)
            or haste <= -100 then return reasons.time end
        gcdMS = math.max(math.min(gcdMS, 1000), math.min(gcdMS, 1500, gcdMS / (1 + haste / 100)))
    end
    local parts = {}
    for _, style in ipairs(effectStyles) do
        local effect = effects[style[1]]
        if effect then
            local score, failure = L.Score(effect, mana, spell.castTime, gcdMS, channelled, channelSeconds or seconds)
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

local function onTooltip(tooltip, data)
    if tooltip ~= GameTooltip or tooltip:IsForbidden() then return end
    local _, class = UnitClass("player")
    if class ~= "PRIEST" then return end
    local source = tooltip:GetProcessingTooltipInfo()
    if not source or not sources[source.getterName] or source.append then return end
    if not data or not L.Number(data.id) or data.id <= 0 then return end
    -- Fail one hover locally; no persistent error state or work queue can block the next spell.
    local ok, info = pcall(spellBookInfo, data.id)
    if not ok or not info then return end
    local succeeded, value = pcall(estimate, data.id, data, info)
    setLine(tooltip, succeeded and value or "暂不可用")
end

local events = CreateFrame("Frame")
local function install()
    if installed then return end
    if not IsLoggedIn() then return end
    local _, class = UnitClass("player")
    if class ~= "PRIEST" then
        events:UnregisterEvent("PLAYER_LOGIN"); events:UnregisterEvent("ADDON_LOADED")
        return
    end
    if not TooltipDataProcessor or not TooltipDataProcessor.AddTooltipPostCall or not GameTooltip
        or not Enum or not Enum.TooltipDataType then return end
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, onTooltip)
    GameTooltip:HookScript("OnTooltipCleared", function() lineIndex = nil end)
    installed = true
    events:UnregisterEvent("PLAYER_LOGIN"); events:UnregisterEvent("ADDON_LOADED")
end
events:SetScript("OnEvent", install)
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
if IsLoggedIn() then install() end
