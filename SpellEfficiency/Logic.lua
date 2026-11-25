-- Tooltip estimates only; no combat simulation or historical state. Author: Solazhu.
local _, A = ...
local L = {}
A.Logic = L
local number = "(%d+%.?%d*)"

function L.SupportsClass(class)
    return class == "PRIEST" or class == "DRUID"
end

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

local function normalize(text, rangeMode)
    text = plain(text)
    if not text or text == "" then return nil, "missing" end
    if text:find("$", 1, true) then return nil, "unsupported" end
    -- zhCN/enUS use commas for thousands, not decimal fractions.
    for i = 1, 4 do text = text:gsub("(%d),(%d%d%d)", "%1%2") end
    for _, separator in ipairs({"至", "到", "~", "～", "–", "—", "to"}) do
        text = text:gsub("(%d)%s*" .. separator .. "%s*(%d)", "%1-%2")
    end
    local invalid, hasRange = false, false
    text = text:gsub(number .. "%s*%-%s*" .. number .. "()", function(low, high, after)
        low, high = tonumber(low), tonumber(high)
        if not L.Number(low) or not L.Number(high) or low > high then invalid = true; return "?" end
        local value = low / 2 + high / 2
        if rangeMode and low < high then
            local suffix = text:sub(after)
            -- Keep the same durations and tick intervals for both bounds.
            if not suffix:match("^%s*秒") and not suffix:match("^%s*sec") then
                hasRange = true
                if rangeMode == "lower" then value = low
                elseif rangeMode == "upper" then value = high end
            end
        end
        return string.format("%.6f", value):gsub("0+$", ""):gsub("%.$", "")
    end)
    if invalid then return nil, "unsupported" end
    return text, nil, hasRange
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

local function damageHealing(clause, chinese, values)
    local text = clause:gsub("^%s+", ""):gsub("%s+$", ""):gsub("[%.!]$", "")
    local percent, related
    if chinese then
        text = text:gsub("%s", ""):gsub("的", "")
            :gsub("^为施法者", ""):gsub("^为自身", ""):gsub("^为你", "")
            :gsub("所造成伤害", "伤害"):gsub("造成伤害", "伤害")
            :gsub("总伤害", "伤害"):gsub("伤害量", "伤害"):gsub("等同于", "相当于")
        if text == "恢复等量生命值" or text == "恢复相当于伤害生命值"
            or text == "恢复与伤害等量生命值" then return 1, true end
        percent = text:match("^恢复相当于伤害" .. number .. "%%生命值$")
            or text:match("^恢复伤害" .. number .. "%%生命值$")
            or text:match("^将伤害" .. number .. "%%转化为生命值$")
        related = ((text:find("恢复", 1, true) or text:find("转化", 1, true))
            and text:find("生命", 1, true) and (text:find("伤害", 1, true)
            or text:find("等量", 1, true) or text:find("相当于", 1, true)))
            or text == "治疗施法者"
    else
        text = text:gsub("heals the caster", "heals you"):gsub("the damage dealt", "damage dealt")
        if text:match("^damage caused by .+ heals you$")
            or text == "heals you for an amount equal to damage dealt"
            or text == "heals you for an equal amount" or text == "heals you for the same amount" then return 1, true end
        percent = text:match("^" .. number .. "%% of damage caused by .+ heals you$")
            or text:match("^heals you for " .. number .. "%% of damage dealt$")
        related = (text:find("heal", 1, true) and (text:find("damage", 1, true)
            or text:find("equal", 1, true) or text:find("same amount", 1, true)))
            or text == "heals you"
    end
    if percent then return tonumber(percent) / 100, true end
    if values and values.healing and not text:find("%%") and not text:find("等量", 1, true)
        and not text:find("相当于", 1, true) and not text:find("equal", 1, true)
        and not text:find("same amount", 1, true) then return end
    return nil, related
end

local function validAmount(value, allowZero)
    return L.Number(value) and (value > 0 or allowZero)
end

local function parseEffects(text, locale, allowZero)
    if locale == "zhCN" then
        -- Some direct heals describe the amount of damage healed.
        text = text:gsub("治%s*疗%s*" .. number .. "%s*点%s*伤%s*害", "治疗%1点生命值")
    end
    for _, word in ipairs({"复活", "复生", "resurrect"}) do
        if text:find(word, 1, true) then return nil, "not_applicable" end
    end
    if text:find("%f[%a]dead%s+target%f[%A]") then return nil, "not_applicable" end
    -- A fixed hit-chance penalty is not a probabilistic damage proc (Insect Swarm).
    local procText = text:gsub("命中几率降低", "命中率降低")
        :gsub("decreasing their chance to hit", "decreasing their hit rate")
    -- Reactive damage and charges need assumptions about future events.
    for _, word in ipairs({"每当", "受到攻击", "攻击者", "点击", "每消耗", "每损失", "几率", "下一次近战",
        "when hit", "when struck", "attacker", "for each", "click", "charges", "next melee", "chance"}) do
        if procText:find(word, 1, true) then return nil, "unsupported" end
    end
    -- Penance's timing applies to both alternatives, including the immediate first bolt.
    -- Parse the complete sentence before splitting; an unfamiliar variant must not return one bolt.
    local volley, prefix, pattern = text:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    if locale == "zhCN" then
        volley = volley:gsub("%s", ""):gsub("^向目标释放圣光能量", "向目标施放圣光能量"):gsub("。$", "")
        prefix = "向目标施放圣光能量，"
        pattern = "^" .. prefix .. "立即对一名敌人造成" .. number .. "点神圣伤害，或为一名盟友恢复"
            .. number .. "点生命值，并在接下来的" .. number .. "秒内每" .. number .. "秒重复一次效果$"
    else
        prefix = "launches a volley of holy light at the target, "
        pattern = "^" .. prefix .. "causing " .. number .. " holy damage to an enemy, or " .. number
            .. " healing to an ally, instantly and every " .. number .. " sec for " .. number .. " sec%.?$"
    end
    if volley:find(prefix, 1, true) == 1 then
        local damage, healing, seconds, period = volley:match(pattern)
        if locale ~= "zhCN" then seconds, period = period, seconds end
        damage, healing, seconds, period = tonumber(damage), tonumber(healing), tonumber(seconds), tonumber(period)
        if not validAmount(damage, allowZero) or not validAmount(healing, allowZero)
            or not L.Number(seconds) or seconds <= 0 or not L.Number(period) or period <= 0 then
            return nil, "unsupported"
        end
        local repeats = seconds / period
        if not L.Number(repeats) or repeats < 1 or math.abs(repeats - math.floor(repeats + 0.5)) > 0.000001 then
            return nil, "unsupported"
        end
        local bolts = 1 + math.floor(repeats + 0.5)
        damage, healing = damage * bolts, healing * bolts
        if not L.Number(damage) or not L.Number(healing) then return nil, "unsupported" end
        return {damage=damage, healing=healing}, nil, seconds, "penance"
    end
    local fullDuration, totals, healingRatio, previousHealing = duration(text), {}, nil, false
    -- Keep each direct/periodic component separate, so a tick interval cannot multiply a direct heal.
    local clauses = text:gsub("，", ";"):gsub("。", ";"):gsub("；", ";"):gsub("并", ";")
        :gsub(",", ";"):gsub("%s+and%s+", ";"):gsub("%.%s+", ";")
    for clause in clauses:gmatch("[^;]+") do
        local values = components(clause, locale == "zhCN")
        -- Regrowth: "heals ... and another N over X sec" omits the second healing verb.
        if locale ~= "zhCN" and clause:match("^%s*another%f[%A]") then
            local value, seconds, unit = clause:match("^%s*another%s+" .. number .. "%s+over%s+" .. number .. "%s+(%a+)%.?%s*$")
            if not previousHealing or not value or tonumber(seconds) <= 0
                or (unit ~= "sec" and unit ~= "second" and unit ~= "seconds") then return nil, "unsupported" end
            values = {healing=tonumber(value)}
        end
        local ratio, related = damageHealing(clause, locale == "zhCN", values)
        if related then
            if not validAmount(ratio, allowZero) or healingRatio then return nil, "unsupported" end
            healingRatio = ratio
            values = {}
        end
        if not values then return nil, "unsupported" end
        local period = interval(clause)
        -- A separate interval cannot safely be assigned to one of several effects.
        if period and not next(values) then return nil, "unsupported" end
        if not related and claimsOutput(clause, locale == "zhCN") and (not next(values) or clause:find("%%")) then
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
        previousHealing = values.healing and not values.damage and not values.absorb
    end
    if healingRatio then
        -- Derive healing once from complete damage, never once per clause or per tick again.
        -- An additional flat heal may describe the same healing; do not count it twice.
        if not totals.damage or totals.healing then return nil, "unsupported" end
        totals.healing = totals.damage * healingRatio
    end
    -- Preserve every effect category; damage, healing and absorption are never added together.
    if next(totals) then
        for _, amount in pairs(totals) do
            if not validAmount(amount, allowZero) then return nil, "unsupported" end
        end
        return totals, nil, fullDuration
    end
    for _, word in ipairs({"伤害", "恢复", "治疗", "damage", "heal", "absorb"}) do
        if text:find(word, 1, true) then return nil, "unsupported" end
    end
    return nil, "not_applicable"
end

function L.Effects(description, locale, showRange)
    if locale ~= "zhCN" and locale ~= "enUS" and locale ~= "enGB" then return nil, "locale" end
    local text, reason, hasRange = normalize(description, showRange and "mean")
    if not text then return nil, reason end
    if not hasRange then return parseEffects(text, locale) end

    local effects, failure, seconds, kind = parseEffects(text, locale)
    if not effects then return nil, failure end
    local lower = parseEffects(normalize(description, "lower"), locale, true)
    local upper = parseEffects(normalize(description, "upper"), locale, true)
    return effects, nil, seconds, kind, lower, upper
end

-- The regen timer only needs the initial mana charge, even when a spell has other costs.
function L.ManaCost(costs, upfrontOnly)
    if type(costs) ~= "table" or not L.Readable(costs) then return end
    local base, aura, baseCount, auraCount = nil, nil, 0, 0
    local nonMana = false
    for _, cost in ipairs(costs) do
        if not L.Readable(cost) or type(cost) ~= "table" then return end
        local power = cost.type
        if not L.Readable(power) or type(power) ~= "number" or power % 1 ~= 0 then return end
        if not upfrontOnly and power < 0 then return end
        if not L.Readable(cost.requiredAuraID) or not L.Readable(cost.hasRequiredAura) then return end
        local required = cost.requiredAuraID and cost.requiredAuraID ~= 0
        if not required or cost.hasRequiredAura then
            if power == 0 then
                if not L.Number(cost.cost) or (not upfrontOnly and cost.costPerSec ~= nil
                    and (not L.Number(cost.costPerSec) or cost.costPerSec ~= 0)) then return end
                if required then aura, auraCount = cost.cost, auraCount + 1
                else base, baseCount = cost.cost, baseCount + 1 end
            else
                nonMana = true
            end
        end
    end
    if nonMana and not upfrontOnly then return nil, "not_applicable" end
    if auraCount == 1 then return aura end
    if auraCount == 0 and baseCount == 1 then return base end
end

function L.Score(effect, mana, castMS, gcdMS, channelled, channelSeconds, weight)
    if not L.Number(effect) or effect <= 0 then return nil, "unsupported" end
    if not L.Number(mana) then return nil, "mana" end
    if mana == 0 then return nil, "free" end
    if weight == nil then weight = 0.8 end
    if not L.Number(weight) or weight > 1 then return nil, "unsupported" end
    local occupied = 1
    if weight > 0 then
        if not L.Number(castMS) or not L.Number(gcdMS) then return nil, "time" end
        occupied = castMS / 1000
        if channelled then
            if not L.Number(channelSeconds) or channelSeconds <= 0 then return nil, "time" end
            occupied = channelSeconds
        end
        occupied = math.max(occupied, gcdMS / 1000)
        if occupied <= 0 then return nil, "time" end
    end
    -- Weight zero means effect per mana, independent of timing data readiness.
    local score = effect / mana / (occupied ^ weight)
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
