-- Adjustable screen-space effects anchored to the client's interaction plate.
-- Copyright (C) 2026 Sola. SPDX-License-Identifier: GPL-3.0-or-later
local ADDON, ns = ...
local PATH = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\"
local visuals = {}
local sin, cos, pi, min, max = math.sin, math.cos, math.pi, math.min, math.max

local function Texture(frame, file)
    local texture = frame:CreateTexture(nil, "OVERLAY")
    texture:SetTexture(PATH .. file)
    texture:SetBlendMode("ADD")
    if texture.SetSnapToPixelGrid then
        texture:SetSnapToPixelGrid(false)
        texture:SetTexelSnappingBias(0)
    end
    return texture
end

local function NewVisual()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(1, 1)
    frame:EnableMouse(false)
    frame:Hide()
    local visual = {frame = frame, time = 0, glints = {}, appear = 0}
    visual.halo = Texture(frame, "halo")
    visual.beam = Texture(frame, "beam")
    for i = 1, 12 do
        local glint = Texture(frame, "flare")
        visual.glints[i] = glint
    end
    frame:SetScript("OnUpdate", function(_, elapsed)
        elapsed = min(elapsed, 0.10)
        visual.time = visual.time + elapsed
        visual.appear = min(1, visual.appear + elapsed / 0.25)
        local db = ns.db or ns.defaults
        local size = visual.preview and db.size * 0.55 or db.size
        local base = ns.palettes[db.palette] or ns.colors[visual.category] or ns.colors.quest
        local r, g, b = base[1], base[2], base[3]
        local factor = visual.state == "far" and 0.50 or 1
        if visual.state == "locked" then r, g, b, factor = 0.6, 0.6, 0.6, 0.40 end
        local alpha = db.brightness * factor * visual.appear
        local pulse = 0.82 + 0.18 * sin(visual.time * 3)
        visual.halo:ClearAllPoints()
        visual.halo:SetPoint("CENTER", frame, "CENTER", 0, 0)
        local diameter = (db.style == "ring" and 94 or 67) * size * pulse
        visual.halo:SetSize(diameter, diameter * 0.58)
        visual.halo:SetVertexColor(r, g, b, min(alpha * (db.style == "ring" and 0.90 or 0.28), 1))
        visual.beam:ClearAllPoints()
        visual.beam:SetPoint("BOTTOM", frame, "CENTER", 0, -4 * size)
        visual.beam:SetSize(44 * size, 145 * size)
        visual.beam:SetVertexColor(r, g, b, db.style == "beacon" and min(alpha * 0.72 * pulse, 1) or 0)
        for i, texture in ipairs(visual.glints) do
            local age = (visual.time * (visual.state == "locked" and 0.48 or 0.9) + i * 0.193) % 1.6 / 1.6
            local shine = max(0, sin(age * pi))
            local angle = i * 2.39996
            local reach = (18 + (i % 5) * 7) * size
            texture:ClearAllPoints()
            texture:SetPoint("CENTER", frame, "CENTER", cos(angle) * reach,
                sin(angle) * reach * 0.55 + age * 22 * size)
            local width = (15 + (i % 3) * 8) * size * (0.45 + 0.55 * shine)
            texture:SetSize(width, width)
            texture:SetRotation(angle + visual.time * (i % 2 == 0 and 0.2 or -0.2))
            texture:SetVertexColor(r, g, b, min(alpha * shine * (db.style == "ring" and 0.50 or 1), 1))
        end
    end)
    visuals[#visuals + 1] = visual
    return visual
end

local world
local veil
local function Unveil()
    if veil then
        local previous = veil
        veil = nil
        -- Preserve another addon's edit made after our alpha change.
        if ns.SafeCall(previous.frame.GetAlpha, previous.frame) == 0 then
            pcall(previous.frame.SetAlpha, previous.frame, previous.alpha)
        end
    end
end

local function Veil(plate)
    local frame = plate and plate.UnitFrame
    if not ns.db.hidePlate or not frame or type(frame.SetAlpha) ~= "function" then return end
    local alpha = ns.SafeCall(frame.GetAlpha, frame)
    if type(alpha) ~= "number" then return end
    veil = {frame = frame, alpha = alpha}
    pcall(frame.SetAlpha, frame, 0)
end

function ns.EffectRelease()
    Unveil()
    if not world then return end
    world.frame:Hide()
    world.frame:ClearAllPoints()
    world.frame:SetParent(UIParent)
    world.anchor, world.unit = nil, nil
end

function ns.EffectAttach(plate, state, category)
    ns.EffectRelease()
    world = world or NewVisual()
    world.frame:SetParent(plate)
    local level = ns.SafeCall(plate.GetFrameLevel, plate) or 1
    world.frame:SetFrameLevel(max(0, level + 1))
    world.frame:SetPoint("CENTER", plate, "CENTER", 0, ns.db.offsetY)
    if world.frame.SetIgnoreParentAlpha then world.frame:SetIgnoreParentAlpha(true) end
    world.anchor, world.state, world.category, world.appear = plate, state, category, 0
    Veil(plate)
    world.frame:Show()
end

function ns.EffectState(state, category)
    if world then world.state, world.category = state, category end
end

function ns.CreatePreview(parent)
    local visual = NewVisual()
    visual.preview, visual.state, visual.category = true, "ready", "quest"
    visual.frame:SetParent(parent)
    visual.frame:SetPoint("BOTTOM", parent, "BOTTOM", 0, 35)
    visual.frame:Show()
    return visual
end

function ns.RefreshEffects()
    if world and world.anchor then
        world.frame:ClearAllPoints()
        world.frame:SetPoint("CENTER", world.anchor, "CENTER", 0, ns.db.offsetY)
        Unveil()
        Veil(world.anchor)
    end
end
