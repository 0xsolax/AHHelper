-- Character settings and a native minimap entry; no external libraries. Solazhu.
local addonName, A = ...
local L, S = A.Logic, {}
A.Settings = S
local config = {enabled=true, timeWeight=0.8, minimapAngle=225, manaRegen=false, vialX=0, vialY=-118}
local loaded, button, panel = false, nil, nil
local tooltipAvailable, manaAvailable = false, false

local function validOffset(value)
    return L.Readable(value) and type(value) == "number" and L.Number(math.abs(value))
end

-- Keep the five-second display in an existing TOC file for in-game reloads.
local hasManaPool, trackManaRegen, setVialDrag
do
    local duration = 5
    local manaPower = Enum and Enum.PowerType and Enum.PowerType.Mana or 0
    local vialWidth, vialHeight = 48, 96
    local liquidTop, liquidBottom = 22, 84
    local vialArt = "Interface\\AddOns\\" .. addonName .. "\\ManaVial.tga"
    local mistAtlas = "Interface\\AddOns\\" .. addonName .. "\\ManaVialMist.tga"
    local mistFPS, mistFrames, mistColumns = 24, 49, 10
    local enabled = false
    local bar, liquid, waterline, halo, pulse
    local mist, mistArt, mistStartedAt, mistIndex
    local endsAt, displayedTenths
    local sent, started, lastCast, lastChannel
    local dragging = false

    function hasManaPool()
        if type(UnitPowerMax) ~= "function" then return end
        local ok, maximum = pcall(UnitPowerMax, "player", manaPower)
        if ok and L.Number(maximum) then return maximum > 0 end
    end

    local function initialManaCost(spellID)
        local read = C_Spell and C_Spell.GetSpellPowerCost
        if type(read) ~= "function" then return end
        local ok, costs = pcall(read, spellID)
        if ok then return L.ManaCost(costs, true) end
    end

    local function matches(cast, guid, spellID)
        return cast and cast.guid == guid and cast.spellID == spellID
    end

    local function displayFill(progress)
        halo:SetShown(progress == 1)
        liquid:SetShown(progress > 0)
        waterline:SetShown(progress > 0)
        if progress <= 0 then return end

        -- Crop the atlas from the bottom so the liquid keeps its shape as it rises.
        local filled = (liquidBottom - liquidTop) * progress
        local top = (liquidBottom - filled) / vialHeight
        local rim = math.min(1.2, filled)
        liquid:SetHeight(filled)
        liquid:SetTexCoord(0.25, 0.5, top, liquidBottom / vialHeight)
        waterline:SetHeight(rim)
        waterline:SetTexCoord(0.25, 0.5, top, top + rim / vialHeight)
    end

    local function playGlow()
        if enabled and halo:IsShown() and bar:IsVisible() and not pulse:IsPlaying() then
            pulse:Play()
        end
    end

    local function stopMist()
        if not mistStartedAt then return end
        mistStartedAt, mistIndex = nil, nil
        mist:SetScript("OnUpdate", nil)
        mist:Hide()
    end

    local function updateMist()
        local index = math.floor((GetTime() - mistStartedAt) * mistFPS)
        if index >= mistFrames then
            stopMist()
            return
        end
        if index == mistIndex then return end
        mistIndex = index

        -- The one-pixel gutters keep adjacent atlas frames out of the filter.
        local left = (index % mistColumns) * 100 + 1
        local top = math.floor(index / mistColumns) * 102 + 1
        mistArt:SetTexCoord(left / 1024, (left + 98) / 1024, top / 512, (top + 100) / 512)
    end

    local function playMist()
        if not bar:IsVisible() then return end
        mistStartedAt = GetTime()
        updateMist()
        mist:Show()
        mist:SetScript("OnUpdate", updateMist)
    end

    local function showReady()
        endsAt, displayedTenths = nil, nil
        bar:SetScript("OnUpdate", nil)
        displayFill(1)
        playGlow()
    end

    local function updateCountdown()
        local left = endsAt - GetTime()
        if left <= 0 then
            showReady()
            playMist()
            return
        end
        local tenths = math.min(duration * 10, math.ceil(left * 10))
        if tenths == displayedTenths then return end
        displayedTenths = tenths
        displayFill(1 - tenths / (duration * 10))
    end

    local function onCast(_, event, unit, guid, spellID, sentSpellID)
        if not L.Readable(unit) or unit ~= "player" then return end
        if event == "UNIT_SPELLCAST_SENT" then guid, spellID = spellID, sentSpellID end
        if not L.Readable(guid) or type(guid) ~= "string" or guid == "" or not L.Number(spellID) or spellID == 0 then return end

        if event == "UNIT_SPELLCAST_SENT" then
            sent = {guid=guid, spellID=spellID, cost=initialManaCost(spellID)}
            return
        end
        local wasSent = matches(sent, guid, spellID)
        if event == "UNIT_SPELLCAST_START" then
            -- Starting the queued cast gives a newer cost after any earlier spell used a proc.
            local cost = initialManaCost(spellID)
            if cost == nil and wasSent then cost = sent.cost end
            started = {guid=guid, spellID=spellID, cost=cost}
            if wasSent then sent = nil end
            return
        end

        local channelStart = event == "UNIT_SPELLCAST_CHANNEL_START"
        if guid == lastCast or guid == lastChannel then
            if channelStart then lastChannel = guid end
            return
        end
        local wasStarted = matches(started, guid, spellID)
        local before = wasStarted and started or (wasSent and sent)
        -- A free cast can consume its discount before the success event is delivered.
        local cost = before and before.cost == 0 and 0 or initialManaCost(spellID)
        if cost == nil then return end
        if wasSent then sent = nil end
        if wasStarted then started = nil end
        lastCast = guid
        if channelStart then lastChannel = guid end
        if cost <= 0 then return end

        stopMist()
        pulse:Stop()
        endsAt = GetTime() + duration
        displayedTenths = nil
        bar:SetScript("OnUpdate", updateCountdown)
        updateCountdown()
    end

    local function anchorVial()
        bar:ClearAllPoints()
        bar:SetPoint("CENTER", UIParent, "CENTER", config.vialX, config.vialY)
    end

    local function finishDrag()
        if not dragging then return end
        dragging = false
        bar:StopMovingOrSizing()
        local x, y = bar:GetCenter()
        local cx, cy = UIParent:GetCenter()
        if validOffset(x) and validOffset(y) and validOffset(cx) and validOffset(cy) then
            config.vialX, config.vialY = x - cx, y - cy
        end
        anchorVial()
        bar:SetUserPlaced(false)
    end

    function setVialDrag(open)
        if not bar then return end
        local movable = enabled and open
        if not movable then finishDrag() end
        local parent = movable and panel or UIParent
        bar:EnableMouse(movable)
        bar:SetFrameStrata(movable and "DIALOG" or "MEDIUM")
        bar:SetFrameLevel(parent:GetFrameLevel() + 1)
    end

    local function createVial()
        bar = CreateFrame("Frame", "SpellEfficiencyManaRegenBar", UIParent)
        bar:SetSize(vialWidth, vialHeight)
        bar:SetClampedToScreen(true)
        anchorVial()
        bar:SetMovable(true)
        bar:EnableMouse(false)
        bar:RegisterForDrag("LeftButton")
        bar:SetScript("OnDragStart", function(self)
            if enabled and panel and panel:IsShown() then
                dragging = true
                self:StartMoving()
            end
        end)
        bar:SetScript("OnDragStop", finishDrag)
        halo = bar:CreateTexture(nil, "BACKGROUND", nil, -1)
        halo:SetAllPoints()
        halo:SetTexture(vialArt)
        halo:SetTexCoord(0.5, 0.75, 0, 1)
        halo:Hide()
        pulse = halo:CreateAnimationGroup()
        pulse:SetLooping("BOUNCE")
        local flare = pulse:CreateAnimation("Alpha")
        flare:SetFromAlpha(0.3)
        flare:SetToAlpha(1)
        flare:SetDuration(1)
        flare:SetSmoothing("IN_OUT")

        local glass = bar:CreateTexture(nil, "BACKGROUND")
        glass:SetAllPoints()
        glass:SetTexture(vialArt)
        glass:SetTexCoord(0, 0.25, 0, 1)

        liquid = bar:CreateTexture(nil, "ARTWORK")
        liquid:SetTexture(vialArt)
        liquid:SetWidth(vialWidth)
        liquid:SetPoint("BOTTOM", bar, "TOP", 0, -liquidBottom)
        waterline = bar:CreateTexture(nil, "ARTWORK", nil, 1)
        waterline:SetTexture(vialArt)
        waterline:SetBlendMode("ADD")
        waterline:SetAlpha(0.55)
        waterline:SetWidth(vialWidth)
        waterline:SetPoint("TOP", liquid, "TOP")

        mist = CreateFrame("Frame", nil, bar)
        mist:SetSize(150, 168)
        mist:SetPoint("TOP", bar, "TOP", 0, 148)
        mistArt = mist:CreateTexture(nil, "OVERLAY")
        mistArt:SetAllPoints()
        mistArt:SetTexture(mistAtlas)
        mist:Hide()

        bar:SetScript("OnShow", playGlow)
        bar:SetScript("OnHide", function()
            stopMist()
            pulse:Stop()
            finishDrag()
        end)
        bar:SetScript("OnEvent", onCast)
    end

    function trackManaRegen(value)
        if enabled == value then return end
        enabled = value
        if enabled then
            if not bar then createVial() end
            bar:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
            bar:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
            bar:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
            bar:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
            bar:Show()
            showReady()
        else
            bar:UnregisterAllEvents()
            sent, started, lastCast, lastChannel = nil, nil, nil, nil
            endsAt, displayedTenths = nil, nil
            stopMist()
            pulse:Stop()
            bar:SetScript("OnUpdate", nil)
            displayFill(0)
            setVialDrag(false)
            bar:Hide()
        end
    end
end

function S.IsEnabled() return config.enabled end
function S.GetWeight() return config.timeWeight end

local function syncIcon()
    if button then
        local active = (tooltipAvailable and config.enabled) or (manaAvailable and config.manaRegen)
        button.icon:SetDesaturated(not active)
    end
end

local function syncControls()
    syncIcon()
    if panel and panel.manaRegen then panel.manaRegen:SetChecked(config.manaRegen) end
    if panel and panel.enabled then
        panel.enabled:SetChecked(config.enabled)
        panel.weight:SetText(tostring(config.timeWeight))
        panel.error:SetText("")
    end
end

function S.Apply(enabled, weight)
    if not loaded or not L.Readable(weight) then return false end
    if type(weight) == "string" then weight = tonumber(weight) end
    if type(enabled) ~= "boolean" or not L.Number(weight) or weight > 1 then return false end
    config.enabled, config.timeWeight = enabled, weight
    syncControls()
    if A.RefreshTooltip then A.RefreshTooltip() end
    return true
end

local function setManaRegen(value)
    config.manaRegen = value
    trackManaRegen(value)
    if value then setVialDrag(panel ~= nil and panel:IsShown()) end
    if panel and panel.manaRegen then panel.manaRegen:SetChecked(value) end
    syncIcon()
end

local function addManaControl()
    panel.manaRegen = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    panel.manaRegen:SetPoint("TOPLEFT", 20, tooltipAvailable and -75 or -48)
    panel.manaRegen.Text:SetText("显示五秒回蓝瓶")
    panel.manaRegen:SetChecked(config.manaRegen)
    panel.manaRegen:SetScript("OnClick", function(self) setManaRegen(self:GetChecked() and true or false) end)
end

local function addEfficiencyControls()
    panel.enabled = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    panel.enabled:SetPoint("TOPLEFT", 20, -48); panel.enabled.Text:SetText("显示法术效率")
    local label = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", 25, -117); label:SetText("时间权重")
    panel.weight = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    panel.weight:SetSize(80, 24); panel.weight:SetPoint("TOPLEFT", 130, -111)
    panel.weight:SetAutoFocus(false); panel.weight:SetMaxLetters(12)
    panel.weight:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", 25, -149); hint:SetWidth(290); hint:SetJustifyH("LEFT")
    hint:SetText("0：仅每蓝收益　1：完全计入时间")
    panel.error = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.error:SetPoint("TOPLEFT", 25, -174); panel.error:SetWidth(290)
    panel.error:SetJustifyH("LEFT"); panel.error:SetTextColor(1, 0.3, 0.3)
    local function apply()
        if S.Apply(panel.enabled:GetChecked() and true or false, panel.weight:GetText()) then
            panel.weight:ClearFocus()
        else
            panel.error:SetText("请输入 0 到 1 之间的数值。")
        end
    end
    panel.apply = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.apply:SetSize(110, 24); panel.apply:SetPoint("BOTTOMLEFT", 25, 20)
    panel.apply:SetText("应用"); panel.apply:SetScript("OnClick", apply)
    panel.weight:SetScript("OnEnterPressed", apply)
    panel.defaults = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.defaults:SetSize(150, 24); panel.defaults:SetPoint("BOTTOMRIGHT", -25, 20)
    panel.defaults:SetText("恢复默认 0.8")
    panel.defaults:SetScript("OnClick", function() S.Apply(true, 0.8) end)
end

local function createPanel()
    panel = CreateFrame("Frame", "SpellEfficiencySettingsFrame", UIParent, "BackdropTemplate")
    panel:SetSize(340, tooltipAvailable and 252 or 92); panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG"); panel:SetClampedToScreen(true)
    panel:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize=24,
        insets={left=5,right=5,top=5,bottom=5}})
    panel:EnableMouse(true); panel:SetMovable(true); panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
    panel:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    panel:SetScript("OnHide", function(self)
        self:StopMovingOrSizing()
        if self.weight then self.weight:ClearFocus() end
        setVialDrag(false)
    end)
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 25, -20); title:SetText("效率")
    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4); close:SetScript("OnClick", function() panel:Hide() end)
    if tooltipAvailable then addEfficiencyControls() end
    if manaAvailable then addManaControl() end
    panel:SetScript("OnShow", function()
        syncControls()
        setVialDrag(true)
    end)
    table.insert(UISpecialFrames, "SpellEfficiencySettingsFrame")
    panel:Hide()
end

local function positionButton()
    local radians = math.rad(config.minimapAngle)
    local radius = Minimap:GetWidth() / 2 + 8
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(radians) * radius, math.sin(radians) * radius)
end

local function buttonTooltip()
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:SetText("效率")
    if tooltipAvailable then
        GameTooltip:AddLine(config.enabled and "法术效率已开启" or "法术效率已关闭", 1, 1, 1)
        GameTooltip:AddLine("时间权重：" .. tostring(config.timeWeight), 1, 1, 1)
    end
    if manaAvailable then
        GameTooltip:AddLine(config.manaRegen and "五秒回蓝已开启" or "五秒回蓝已关闭", 1, 1, 1)
        GameTooltip:AddLine("打开设置时可拖动回蓝瓶", 0.7, 0.7, 0.7)
    end
    local rightClick = tooltipAvailable and "法术效率" or "五秒回蓝"
    GameTooltip:AddLine("左键：设置　右键：" .. rightClick .. "\n拖动：移动按钮", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

local function createButton()
    button = CreateFrame("Button", "SpellEfficiencyMinimapButton", Minimap)
    button:SetSize(32, 32); button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp"); button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(); background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(20, 20); button.icon:SetPoint("CENTER")
    button.icon:SetTexture("Interface\\Icons\\Spell_Holy_Heal")
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(54, 54); border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    button:SetScript("OnClick", function(self, key)
        if key == "RightButton" then
            if tooltipAvailable then S.Apply(not config.enabled, config.timeWeight)
            else setManaRegen(not config.manaRegen) end
            if GameTooltip:IsOwned(self) then buttonTooltip() end
        else
            if not panel then createPanel() end
            if panel:IsShown() then panel:Hide() else panel:Show() end
        end
    end)
    button:SetScript("OnEnter", buttonTooltip)
    button:SetScript("OnLeave", function(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
    button:SetScript("OnDragStart", function(self)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
        self:SetScript("OnUpdate", function()
            local x, y = GetCursorPosition()
            local cx, cy = Minimap:GetCenter()
            if not cx or not cy then return end
            local scale = Minimap:GetEffectiveScale()
            config.minimapAngle = math.deg(math.atan2(y / scale - cy, x / scale - cx)) % 360
            positionButton()
        end)
    end)
    local function stopDrag(self) self:SetScript("OnUpdate", nil) end
    button:SetScript("OnDragStop", stopDrag); button:SetScript("OnHide", stopDrag)
    positionButton(); syncControls()
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, name)
    if not loaded and ((event == "ADDON_LOADED" and name == addonName) or event == "PLAYER_LOGIN") then
        local saved = type(SpellEfficiencyDB) == "table" and SpellEfficiencyDB or {}
        if type(saved.enabled) == "boolean" then config.enabled = saved.enabled end
        if L.Number(saved.timeWeight) and saved.timeWeight <= 1 then config.timeWeight = saved.timeWeight end
        if L.Number(saved.minimapAngle) then config.minimapAngle = saved.minimapAngle % 360 end
        if type(saved.manaRegen) == "boolean" then config.manaRegen = saved.manaRegen end
        if validOffset(saved.vialX) and validOffset(saved.vialY) then
            config.vialX, config.vialY = saved.vialX, saved.vialY
        end
        SpellEfficiencyDB = config
        loaded = true
    end
    if not loaded or not IsLoggedIn() or not UIParent then return end
    local _, class = UnitClass("player")
    tooltipAvailable = L.SupportsClass(class)
    if not manaAvailable and hasManaPool() then
        manaAvailable = true
        setManaRegen(config.manaRegen)
        if panel then addManaControl() end
    end
    if manaAvailable or event == "PLAYER_ENTERING_WORLD" then events:UnregisterEvent("PLAYER_ENTERING_WORLD") end
    if tooltipAvailable or manaAvailable then
        if not Minimap then return end
        if not button then createButton() end
    end
    events:UnregisterEvent("ADDON_LOADED"); events:UnregisterEvent("PLAYER_LOGIN")
end)
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
