local _, addon = ...
local Roster = { pageSize = 5, macroLimit = 255 }
addon.Roster = Roster

function Roster.Line(name)
    return "/tar " .. name
end

function Roster.Normalize(name)
    if type(name) ~= "string" or name:find("[%c/%[%];|]") then
        return nil
    end
    name = name:gsub("　", " "):gsub("^ +", ""):gsub(" +$", ""):gsub(" +", " ")
    if not name:match("^[^ ]+ [^ ]+$") or #Roster.Line(name) > Roster.macroLimit then
        return nil
    end
    return name
end

function Roster.Open(database, newLogin, now)
    database.groups = database.groups or {}
    database.macros = database.macros or {}
    local groups = database.groups
    local current = groups[#groups]
    if not current or newLogin then
        if current and #current.names == 0 then
            groups[#groups] = nil
        end
        groups[#groups + 1] = { started = now, names = {} }
    end
    return #groups
end

function Roster.Add(group, name)
    local key = name:lower()
    for _, existing in ipairs(group.names) do
        if existing:lower() == key then
            return false
        end
    end
    group.names[#group.names + 1] = name
    return true
end

function Roster.Pages(group)
    local page = { first = 1, names = {}, body = "" }
    local pages = { page }
    for index, name in ipairs(group.names) do
        local line = Roster.Line(name)
        local size = #page.body + (page.body == "" and 0 or 1) + #line
        if #page.names == Roster.pageSize or size > Roster.macroLimit then
            page = { first = index, names = {}, body = "" }
            pages[#pages + 1] = page
        end
        page.names[#page.names + 1] = name
        page.body = page.body == "" and line or page.body .. "\n" .. line
    end
    return pages
end
