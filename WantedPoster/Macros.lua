local _, addon = ...
local Roster = addon.Roster
local Macros = {}
addon.Macros = Macros

Macros.pageSlot = Roster.pageSize + 1
local secret = issecretvalue or function() return false end
local defaultIcon = 134400

local function macroBody(body)
    if secret(body) or type(body) ~= "string" then return nil end
    return (body:gsub("\r\n", "\n"):gsub("[ \t\r\n]+$", ""))
end

local function readBank()
    local shared, character = GetNumMacros()
    local offset = Constants.MacroConsts.MAX_ACCOUNT_MACROS
    local bank = { names = {}, character = {} }
    local function read(index, personal)
        local name, icon, body = GetMacroInfo(index)
        if secret(name) or type(name) ~= "string" or name == "" then return end
        bank.names[name:lower()] = true
        if personal then
            if secret(icon) then icon = nil end
            bank.character[#bank.character + 1] = { index = index, name = name, body = macroBody(body), icon = icon }
        end
    end
    for index = 1, shared do read(index, false) end
    for index = 1, character do read(offset + index, true) end
    return bank
end

local function ownedMacro(bank, record)
    if not record then return nil end
    local found
    for _, macro in ipairs(bank.character) do
        if macro.name == record.name then
            if found then return nil end
            found = macro
        end
    end
    if found and found.body and found.body == macroBody(record.body) and
        (record.icon == nil or found.icon == record.icon) then
        return found
    end
end

local function namedSlot(name)
    local slot = tonumber(name:match("^WP_Target([1-9])$") or name:match("^WP_Target([1-9])_%d+$"))
    if slot and slot <= Macros.pageSlot then return slot end
end

local function compatibleMacro(bank, slot, body)
    for _, macro in ipairs(bank.character) do
        if macro.body == body and namedSlot(macro.name) == slot then
            return macro.index
        end
    end
end

local function targetsOnlyThisPage(macro, slot, lines)
    if not macro.body then return false end
    if slot ~= Macros.pageSlot then return lines[macro.body] == true end
    local count = 0
    for line in (macro.body .. "\n"):gmatch("(.-)\n") do
        if not lines[line] then return false end
        count = count + 1
    end
    return count > 0 and count <= Roster.pageSize
end

function Macros.QueuePageCleanup(database, page)
    local bank = readBank()
    local lines, owned = {}, {}
    for _, name in ipairs(page.names) do lines[Roster.Line(name)] = true end
    for _, record in pairs(database.macros) do
        local macro = ownedMacro(bank, record)
        if macro then owned[macro.index] = true end
    end

    local cleanup = database.macroCleanup or {}
    for _, macro in ipairs(bank.character) do
        local slot = namedSlot(macro.name)
        -- A legacy macro must still match the original label, icon, and target commands.
        if slot and (owned[macro.index] or macro.icon == defaultIcon) and targetsOnlyThisPage(macro, slot, lines) then
            cleanup[macro.name] = { name = macro.name, body = macro.body, icon = macro.icon }
        end
    end
    if next(cleanup) then
        database.macroCleanup = cleanup
        for slot, record in pairs(database.macros) do
            if cleanup[record.name] then database.macros[slot] = nil end
        end
    end
end

local function clearQueued(database, bank, writable)
    local cleanup = database.macroCleanup
    if not cleanup then return bank end
    for name, record in pairs(cleanup) do
        local macro = ownedMacro(bank, record)
        if macro and writable and pcall(DeleteMacro, macro.index) then
            bank = readBank()
        end
        if not ownedMacro(bank, record) then cleanup[name] = nil end
    end
    if not next(cleanup) then database.macroCleanup = nil end
    return bank
end

local function freeName(bank, slot)
    local base = "WP_Target" .. slot
    local name = base
    local suffix = 0
    while bank.names[name:lower()] do
        suffix = suffix + 1
        name = base .. "_" .. suffix
    end
    return name
end

local function writeMacro(bank, registry, slot, body)
    local previous = ownedMacro(bank, registry[slot])
    local name = previous and previous.name or freeName(bank, slot)
    local ok, index
    if previous then
        ok, index = pcall(EditMacro, previous.index, nil, nil, body)
    else
        ok, index = pcall(CreateMacro, name, defaultIcon, body, true)
    end
    if not ok then return bank, false end
    local updated = readBank()
    local record = { name = name, body = body }
    local accepted = not secret(index) and type(index) == "number" and index > Constants.MacroConsts.MAX_ACCOUNT_MACROS
    if accepted or ownedMacro(updated, record) then
        registry[slot] = record
    end
    return updated, accepted
end

function Macros.Sync(database, page, writable)
    local bodies = {}
    for slot, name in ipairs(page.names) do
        bodies[slot] = Roster.Line(name)
    end
    if page.body ~= "" then
        bodies[Macros.pageSlot] = page.body
    end

    local registry = database.macros
    local bank = clearQueued(database, readBank(), writable)
    local accepted = false
    if writable and not database.macroCleanup then
        for slot = 1, Macros.pageSlot do
            if not bodies[slot] and registry[slot] then
                local owned = ownedMacro(bank, registry[slot])
                if owned and pcall(DeleteMacro, owned.index) then
                    bank = readBank()
                end
                if not ownedMacro(bank, registry[slot]) then registry[slot] = nil end
            end
        end
        for slot = Macros.pageSlot, 1, -1 do
            local body = bodies[slot]
            if body and not compatibleMacro(bank, slot, body) then
                local wrote
                bank, wrote = writeMacro(bank, registry, slot, body)
                accepted = accepted or wrote
            end
        end
    end

    local bindings = {}
    local complete = true
    for slot = 1, Macros.pageSlot do
        if bodies[slot] then
            bindings[slot] = compatibleMacro(bank, slot, bodies[slot])
            if not bindings[slot] then
                complete = false
            end
        end
    end
    return bindings, complete, accepted and not complete
end
