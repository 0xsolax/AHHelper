-- Narrow WoW UI/API simulator for lifecycle and interaction tests. Solazhu.
MOCK = { time = 100, frames = {}, timers = {}, tickers = {}, messages = {}, queries = {}, postCalls = 0,
    items = { [1] = "硫酸", [2] = "黄铁矿", [3] = "空瓶", [4] = "铜锭", [5] = "亚麻布卷" } }
local Frame = {}; Frame.__index = Frame
local function make(kind, name, parent, template)
    local f = setmetatable({ kind = kind, name = name, parent = parent, template = template, shown = true,
        enabled = true, scripts = {}, points = {}, width = 0, height = 0, text = "", fontSize = 14 }, Frame)
    table.insert(MOCK.frames, f); f.index = #MOCK.frames
    if name then _G[name] = f end
    return f
end
function CreateFrame(kind, name, parent, template) return make(kind, name, parent, template) end
function Frame:SetSize(w, h)
    local changed = self.width ~= w or self.height ~= h
    self.width, self.height = w, h
    if changed and self.scripts.OnSizeChanged then self.scripts.OnSizeChanged(self, w, h) end
end
function Frame:SetWidth(w) self.width = w end
function Frame:SetHeight(h) self.height = h end
function Frame:GetWidth() return self.width end
function Frame:GetHeight() return self.height end
function Frame:SetPoint(point, relative, relativePoint, x, y)
    if type(relative) == "number" then x, y, relative, relativePoint = relative, relativePoint, self.parent, point end
    if relative == nil then relative, relativePoint = self.parent, point end
    table.insert(self.points, {point, relative, relativePoint or point, x or 0, y or 0})
end
function Frame:ClearAllPoints() self.points = {} end
function Frame:SetAllPoints(relative)
    self.allPoints = relative or self.parent
end
function Frame:SetParent(parent) self.parent = parent end
function Frame:GetParent() return self.parent end
function Frame:GetName() return self.name end
function Frame:IsObjectType(kind) return self.kind == kind end
function Frame:SetScript(event, callback) self.scripts[event] = callback end
function Frame:HookScript(event, callback)
    local previous = self.scripts[event]
    self.scripts[event] = function(...) if previous then previous(...) end; callback(...) end
end
function Frame:Show()
    local changed = not self.shown; self.shown = true
    if changed and self.scripts.OnShow then self.scripts.OnShow(self) end
end
function Frame:Hide()
    local changed = self.shown; self.shown = false
    if changed and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function Frame:SetShown(show) if show then self:Show() else self:Hide() end end
function Frame:IsShown() return self.shown end
function Frame:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function Frame:SetText(text)
    self.text = tostring(text)
    if self.label then self.label.text = self.text end
    if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self, false) end
end
function Frame:SetUserText(text)
    self.text = tostring(text)
    if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self, true) end
end
function Frame:GetText() return self.text end
function Frame:SetEnabled(enabled) self.enabled = enabled end
function Frame:IsEnabled() return self.enabled end
function Frame:SetChecked(value) self.checked = value end
function Frame:GetChecked() return self.checked end
function Frame:SetFont(font, size) self.fontSize = size end
function Frame:GetFont() return "MockChineseFont", self.fontSize, "" end
function Frame:SetTextColor(...) self.color = {...} end
function Frame:SetJustifyH(value) self.justify = value end
function Frame:SetTexture(value) self.texture = value end
function Frame:SetColorTexture(...) self.fill = {...} end
function Frame:SetBackdropColor(...) self.fill = {...} end
function Frame:SetBackdropBorderColor(...) self.border = {...} end
function Frame:SetBackdrop(value) self.backdrop = value end
function Frame:CreateFontString(name) return make("FontString", name, self) end
function Frame:CreateTexture(name) return make("Texture", name, self) end
function Frame:GetFontString()
    if not self.label then
        self.label = self:CreateFontString(); self.label:SetPoint("CENTER"); self.label.text = self.text
    end
    return self.label
end
function Frame:SetScrollChild(child) self.scrollChild = child end
function Frame:HasFocus() return MOCK.focus == self end
function Frame:SetFocus()
    if MOCK.focus then MOCK.focus:ClearFocus() end
    MOCK.focus = self
    if self.scripts.OnEditFocusGained then self.scripts.OnEditFocusGained(self) end
end
function Frame:ClearFocus()
    if MOCK.focus ~= self then return end
    MOCK.focus = nil
    if self.scripts.OnEditFocusLost then self.scripts.OnEditFocusLost(self) end
end
function Frame:SetScale(value) self.scale = value end
function Frame:SetMovable(value) self.movable = value end
function Frame:SetClampedToScreen(value) self.clamped = value end
function Frame:GetScale() return self.scale or 1 end
function Frame:GetEffectiveScale() return self:GetScale() * (self.parent and self.parent:GetEffectiveScale() or 1) end
function Frame:Click()
    if self.enabled and self:IsVisible() and self.scripts.OnClick then self.scripts.OnClick(self, "LeftButton") end
end
function Frame:RegisterEvent(event) self.registered = self.registered or {}; self.registered[event] = true end
for _, method in ipairs({"SetAutoFocus", "SetFontObject", "SetMaxLetters", "SetWordWrap", "SetFrameStrata",
    "EnableMouse", "RegisterForDrag", "StartMoving",
    "StopMovingOrSizing", "SetHighlightTexture", "SetHitRectInsets", "SetCursorPosition", "SetOwner",
    "SetItemByID", "AddLine"}) do Frame[method] = function() end end

UIParent = make("Frame", "UIParent"); UIParent:SetSize(1600, 1000)
GameFontHighlight = {}
GameTooltip = make("Frame", "GameTooltip"); GameTooltip:Hide()
UISpecialFrames, SlashCmdList, StaticPopupDialogs = {}, {}, {}
tinsert = table.insert
strmatch = string.match
function GetTime() return MOCK.time end
function GetServerTime() return MOCK.serverTime or 1794450000 end
date = os.date
function GetRealmName() return "TestRealm" end
function UnitGUID() return "TestCharacter" end
function UnitName() return "TestPlayer" end
function IsLoggedIn() return true end
function GetCurrentKeyBoardFocus() return MOCK.focus end
function IsShiftKeyDown() return MOCK.shift == true end
ChatFrameUtil = {InsertLink = function(text)
    MOCK.normalLinks = (MOCK.normalLinks or 0) + 1; return "native", text
end}
function InCombatLockdown() return MOCK.combat or false end
function GetCursorInfo() return unpack(MOCK.cursor or {}) end
function ClearCursor() MOCK.cursor = nil end
function StaticPopup_Show(which, _, _, data) MOCK.popup = {which = which, data = data} end
DEFAULT_CHAT_FRAME = {AddMessage = function(_, text) table.insert(MOCK.messages, text) end}
SOUNDKIT = {TELL_MESSAGE = 3081}
function PlaySound() MOCK.sounds = (MOCK.sounds or 0) + 1 end
function FlashClientIcon() end
function hooksecurefunc(object, method, callback)
    local previous = object[method]
    object[method] = function(...) local result = previous(...); callback(...); return result end
end
function PanelTemplates_TabResize() end
function PanelTemplates_DeselectTab(tab) tab.selected = false end
function PanelTemplates_SelectTab(tab) tab.selected = true end
function PanelTemplates_SetTab() end
WOW_PROJECT_ID, WOW_PROJECT_CAMELOT, WOW_PROJECT_MAINLINE = 3, 3, 1
Enum = {BagIndex = {ReagentBag = 4}, AuctionHouseSortOrder = {Price = 0},
    ItemCommodityStatus = {Unknown = 0, Item = 1, Commodity = 2}}
C_Timer = {
    After = function(_, callback) table.insert(MOCK.timers, callback) end,
    NewTicker = function(_, callback) table.insert(MOCK.tickers, callback); return {} end,
}
function MOCK.flush()
    for _ = 1, 20 do
        if #MOCK.timers == 0 then return end
        local pending = MOCK.timers; MOCK.timers = {}
        for _, callback in ipairs(pending) do callback() end
    end
    error("Timer loop did not settle")
end
C_Item = {
    GetItemInfo = function(value)
        local id = tonumber(value) or (type(value) == "string" and tonumber(value:match("item:(%d+)")))
        if not id then for key, name in pairs(MOCK.items) do if name == value then id = key end end end
        if not id or not MOCK.items[id] then return nil end
        return MOCK.items[id], "|Hitem:" .. id .. "|h[" .. MOCK.items[id] .. "]|h", 1, 1, 1, "材料", "材料", 200, "", 134400, 1
    end,
    RequestLoadItemDataByID = function() end,
    GetItemCount = function(id) return id == 1 and 120 or 80 end,
}
C_Container = {
    GetContainerNumSlots = function(bag) return bag == 0 and 1 or 0 end,
    GetContainerItemInfo = function() return {itemID = 1, isLocked = MOCK.locked} end,
}
Enum.TooltipDataType = {Item = 0}
TooltipDataProcessor = {callbacks = {}}
function TooltipDataProcessor.AddTooltipPostCall(kind, callback)
    assert(kind == Enum.TooltipDataType.Item)
    table.insert(TooltipDataProcessor.callbacks, callback)
end
function GameTooltip:GetProcessingTooltipInfo() return self.processingInfo end
function GameTooltip:GetPrimaryTooltipInfo() return self.primaryInfo end
function GameTooltip:AddDoubleLine(left, right)
    self.lines = self.lines or {}; table.insert(self.lines, {left, right})
end
function GameTooltip:AddLine(text)
    self.lines = self.lines or {}; table.insert(self.lines, {text})
end
function MOCK.bagTooltip(itemID, bag)
    GameTooltip.lines = {}
    GameTooltip.primaryInfo = {getterName = "GetBagItem", getterArgs = {bag or 0, 1}}
    GameTooltip.processingInfo = GameTooltip.primaryInfo
    for _, callback in ipairs(TooltipDataProcessor.callbacks) do callback(GameTooltip, {id = itemID}) end
    return GameTooltip.lines
end
ItemLocation = {CreateFromBagAndSlot = function(_, bag, slot) return {bag = bag, slot = slot} end}
C_AuctionHouse = {
    MakeItemKey = function(id) return {itemID = id} end,
    GetItemKeyInfo = function() return {isCommodity = true} end,
    IsThrottledMessageSystemReady = function() return MOCK.ready ~= false end,
    SendSearchQuery = function(key) table.insert(MOCK.queries, key.itemID) end,
    SupportsCopperValues = function() return false end,
    IsSellItemValid = function() return not MOCK.bound end,
    GetAvailablePostCount = function() return 120 end,
    GetItemCommodityStatus = function() return MOCK.commodityStatus or 2 end,
    PostCommodity = function() MOCK.postCalls = MOCK.postCalls + 1 end,
    PostItem = function() MOCK.postCalls = MOCK.postCalls + 1 end,
}
AuctionHouseFrame = make("Frame", "AuctionHouseFrame", UIParent)
AuctionHouseFrame:SetSize(850, 600)
AuctionHouseFrame.Tabs = {make("Button", nil, AuctionHouseFrame), make("Button", nil, AuctionHouseFrame), make("Button", nil, AuctionHouseFrame)}
AuctionHouseFrameDisplayMode = {Buy = {"Buy"}, ItemSell = {"ItemSell"}, CommoditiesSell = {"CommoditiesSell"}, Auctions = {"Auctions"}}
function AuctionHouseFrame:SetDisplayMode(mode) self.displayMode = mode end
function AuctionHouseFrame:GetDisplayMode() return self.displayMode end
function AuctionHouseFrame:SetTitle(title) self.title = title end
local function sellForm()
    return {GetItem = function(self) return self.item end,
        QuantityInput = {SetQuantity = function(self, value) self.value = value end},
        PriceInput = {SetAmount = function(self, value) self.value = value end},
        UpdatePostState = function(self) self.updated = true end}
end
AuctionHouseFrame.CommoditiesSellFrame = sellForm()
AuctionHouseFrame.ItemSellFrame = sellForm()
function AuctionHouseFrame:SetPostItem(item)
    if MOCK.rejectPostItem then return end
    local isCommodity = C_AuctionHouse.GetItemCommodityStatus(item) == 2
    self:SetDisplayMode(isCommodity and AuctionHouseFrameDisplayMode.CommoditiesSell or AuctionHouseFrameDisplayMode.ItemSell)
    local form = isCommodity and self.CommoditiesSellFrame or self.ItemSellFrame
    form.item = item
end
