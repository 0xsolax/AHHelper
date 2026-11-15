-- Tooltip estimates only; no combat simulation or historical state. Author: Solazhu.
local _, A = ...
local L = {}
A.Logic = L
local number = "(%d+%.?%d*)"

function L.Readable(value)
    return not issecretvalue or not issecretvalue(value)
end

function L.Number(value)
    return L.Readable(value) and type(value) == "number" and value == value
        and value >= 0 and value < math.huge
end

local function plain(text)
    if not L.Readable(text) or type(text) ~= "string" then return end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        :gsub("|T.-|t", ""):gsub("|A.-|a", "")
    return text:lower()
end

local function normalize(text)
    text = plain(text)
    if not text or text == "" then return nil, "missing" end
    if text:find("$", 1, true) then return nil, "unsupported" end
    -- zhCN/enUS use commas for thousands, not decimal fractions.
    for i = 1, 4 do text = text:gsub("(%d),(%d%d%d)", "%1%2") end
    for _, separator in ipairs({"至", "到", "~", "～", "–", "—", "to"}) do
        text = text:gsub("(%d)%s*" .. separator .. "%s*(%d)", "%1-%2")
    end
    local invalid = false
    text = text:gsub(number .. "%s*%-%s*" .. number, function(low, high)
        low, high = tonumber(low), tonumber(high)
        if not L.Number(low) or not L.Number(high) or low > high then invalid = true; return "?" end
        return string.format("%.6f", low / 2 + high / 2):gsub("0+$", ""):gsub("%.$", "")
    end)
    if invalid then return nil, "unsupported" end
    return text
end

local durationPatterns = {
    "持续%s*" .. number .. "%s*秒", "在%s*" .. number .. "%s*秒内",
    "over%s+" .. number .. "%s+sec", "for%s+" .. number .. "%s+sec",
    "lasts%s+" .. number .. "%s+sec", "lasting%s+" .. number .. "%s+sec",
}
local function duration(text)
    local found
    for _, pattern in ipairs(durationPatterns) do
        for value in text:gmatch(pattern) do
            value = tonumber(value)
            if not L.Number(value) or value <= 0 or (found and found ~= value) then return end
            found = value
        end
    end
    return found
end

local function interval(text)
    local value = text:match("每%s*" .. number .. "%s*秒")
        or text:match("every%s+" .. number .. "%s+sec")
        or text:match("per%s+" .. number .. "%s+sec")
    if value then return tonumber(value) end
    if text:find("每秒", 1, true) or text:find("every second", 1, true)
        or text:find("every sec", 1, true) or text:find("per second", 1, true)
        or text:find("per sec", 1, true) then return 1 end
end

local schools = { [""]=true, ["的"]=true, ["神圣"]=true, ["暗影"]=true, ["火焰"]=true,
    ["奥术"]=true, ["自然"]=true, ["冰霜"]=true, ["物理"]=true,
    holy=true, shadow=true, fire=true, arcane=true, nature=true, frost=true, physical=true }

local function healingTail(text)
    if text:match("^%s*[%.!]?%s*$") then return true end
    for _, word in ipairs({"health", "over", "every", "per", "for"}) do
        if text:match("^%s+" .. word .. "%f[%A]") then return true end
    end
    return false
end

local function components(clause, chinese)
    local values = {}
    local function add(kind, value)
        value = tonumber(value)
        if L.Number(value) then values[kind] = (values[kind] or 0) + value end
    end
    if chinese then
        clause = clause:gsub("%s", ""):gsub("点", "")
        if clause:find("恢复", 1, true) or clause:find("治疗", 1, true) then
            for value in clause:gmatch(number .. "生命值") do add("healing", value) end
        end
        for _, entry in ipairs({{"造成", "damage"}, {"吸收", "absorb"}}) do
            local text = clause:gsub(entry[1] .. "总计", entry[1]):gsub(entry[1] .. "最多", entry[1])
            for value, school in text:gmatch(entry[1] .. number .. "(.-)伤害") do
                school = school:gsub("额外的", ""):gsub("额外", "")
                if schools[school] then add(entry[2], value) end
            end
        end
    else
        for _, pattern in ipairs({"%f[%a]heals?%f[%A].-for%s+" .. number, "%f[%a]healing%f[%A].-for%s+" .. number,
            "restores?%s+" .. number .. "%s+health"}) do
            for value, after in clause:gmatch(pattern .. "()") do
                if not healingTail(clause:sub(after)) then return nil end
                add("healing", value)
            end
        end
        for _, pattern in ipairs({"absorbs?%s+" .. number .. "%s+damage", "absorbing%s+" .. number .. "%s+damage"}) do
            for value in clause:gmatch(pattern) do add("absorb", value) end
        end
        if not values.absorb then
            for value, school in clause:gmatch(number .. "%s+([%a%s]-)damage") do
                if schools[school:gsub("%s", "")] then add("damage", value) end
            end
        end
    end
    return values
end

local function claimsOutput(clause, chinese)
    if not clause:find("%d") then return false end
    if chinese then
        return ((clause:find("恢复", 1, true) or clause:find("治疗", 1, true)) and clause:find("生命", 1, true))
            or ((clause:find("造成", 1, true) or clause:find("吸收", 1, true)) and clause:find("伤害", 1, true))
    end
    return clause:find("%f[%a]heals?%f[%A]") or clause:find("%f[%a]healing%f[%A]")
        or (clause:find("restore", 1, true) and clause:find("health", 1, true))
        or clause:find("damage", 1, true) or clause:find("absorb", 1, true)
end

function L.Effects(description, locale)
    if locale ~= "zhCN" and locale ~= "enUS" and locale ~= "enGB" then return nil, "locale" end
    local text, reason = normalize(description)
    if not text then return nil, reason end
    for _, word in ipairs({"复活", "resurrect"}) do
        if text:find(word, 1, true) then return nil, "not_applicable" end
    end
    -- Reactive damage, charges, and percentages need assumptions about future events.
    for _, word in ipairs({"每当", "受到攻击", "攻击者", "点击", "每消耗", "每损失", "几率", "下一次近战",
        "when hit", "when struck", "attacker", "for each", "click", "charges", "next melee", "chance"}) do
        if text:find(word, 1, true) then return nil, "unsupported" end
    end
    local fullDuration, totals = duration(text), {}
    -- Keep each direct/periodic component separate, so a tick interval cannot multiply a direct heal.
    local clauses = text:gsub("，", ";"):gsub("。", ";"):gsub("；", ";"):gsub("并", ";")
        :gsub(",", ";"):gsub("%s+and%s+", ";"):gsub("%.%s+", ";")
    for clause in clauses:gmatch("[^;]+") do
        local values = components(clause, locale == "zhCN")
        if not values then return nil, "unsupported" end
        local period = interval(clause)
        -- A separate interval cannot safely be assigned to one of several effects.
        if period and not next(values) then return nil, "unsupported" end
        if claimsOutput(clause, locale == "zhCN") and (not next(values) or clause:find("%%")) then
            return nil, "unsupported"
        end
        if next(values) then
            local multiplier = 1
            if period then
                local seconds = duration(clause) or fullDuration
                if not L.Number(period) or period <= 0 or not seconds then return nil, "unsupported" end
                multiplier = seconds / period
                if multiplier < 1 or math.abs(multiplier - math.floor(multiplier + 0.5)) > 0.000001 then
                    return nil, "unsupported"
                end
            end
            for kind, value in pairs(values) do totals[kind] = (totals[kind] or 0) + value * multiplier end
        end
    end
    -- Preserve every effect category; damage, healing and absorption are never added together.
    if next(totals) then
        for _, amount in pairs(totals) do
            if not L.Number(amount) or amount <= 0 then return nil, "unsupported" end
        end
        return totals, nil, fullDuration
    end
    for _, word in ipairs({"伤害", "恢复", "治疗", "damage", "heal", "absorb"}) do
        if text:find(word, 1, true) then return nil, "unsupported" end
    end
    return nil, "not_applicable"
end

function L.ManaCost(costs)
    if type(costs) ~= "table" or not L.Readable(costs) then return end
    local base, aura, baseCount, auraCount = nil, nil, 0, 0
    for _, cost in ipairs(costs) do
        if type(cost) ~= "table" or not L.Readable(cost.type) then return end
        if cost.type == 0 then
            if not L.Readable(cost.requiredAuraID) or not L.Readable(cost.hasRequiredAura) then return end
            local required = cost.requiredAuraID and cost.requiredAuraID ~= 0
            if not required or cost.hasRequiredAura then
                if not L.Number(cost.cost) or (cost.costPerSec ~= nil
                    and (not L.Number(cost.costPerSec) or cost.costPerSec ~= 0)) then return end
                if required then aura, auraCount = cost.cost, auraCount + 1
                else base, baseCount = cost.cost, baseCount + 1 end
            end
        end
    end
    if auraCount == 1 then return aura end
    if auraCount == 0 and baseCount == 1 then return base end
end

function L.Score(effect, mana, castMS, gcdMS, channelled, channelSeconds)
    if not L.Number(effect) or effect <= 0 then return nil, "unsupported" end
    if not L.Number(mana) then return nil, "mana" end
    if mana == 0 then return nil, "free" end
    if not L.Number(castMS) or not L.Number(gcdMS) then return nil, "time" end
    local occupied = castMS / 1000
    if channelled then
        if not L.Number(channelSeconds) or channelSeconds <= 0 then return nil, "time" end
        occupied = channelSeconds
    end
    occupied = math.max(occupied, gcdMS / 1000)
    if occupied <= 0 then return nil, "time" end
    local score = effect / mana / occupied
    if not L.Number(score) or score <= 0 then return nil, "unsupported" end
    return score
end

function L.IsChannel(text)
    text = plain(text)
    return text and (text:find("引导", 1, true) ~= nil or text:find("channeled", 1, true) ~= nil
        or text:find("channelled", 1, true) ~= nil or text:find("持续施法", 1, true) ~= nil)
end

function L.ChannelSeconds(text)
    if not L.IsChannel(text) then return end
    text = plain(text)
    return tonumber(text:match(number .. "%s*秒") or text:match(number .. "%s+sec"))
end
