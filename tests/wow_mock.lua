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
    if MOCK.menu and not MOCK.menu.owner:IsVisible() then MOCK.menu = nil end
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
function Frame:SetNumber(value) self:SetText(tostring(value)) end
function Frame:GetNumber() return tonumber(self.text) or 0 end
function Frame:SetEnabled(enabled) self.enabled = enabled end
function Frame:IsEnabled() return self.enabled end
function Frame:SetChecked(value) self.checked = value end
function Frame:GetChecked() return self.checked end
function Frame:SetFont(font, size) self.fontSize = size end
function Frame:GetFont() return "MockChineseFont", self.fontSize, "" end
function Frame:SetTextColor(...) self.color = {...} end
function Frame:SetJustifyH(value) self.justify = value end
function Frame:SetWordWrap(value) self.wordWrap = value end
function Frame:GetUnboundedStringWidth()
    if MOCK.measureText then return MOCK.measureText(self.text, self.fontSize) end
    local width = 0
    for char in self.text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        width = width + self.fontSize * (#char > 1 and 1 or 0.55)
    end
    return width
end
function Frame:SetTexture(value) self.texture = value end
function Frame:SetNormalTexture(value) self.normalTexture = value end
function Frame:SetPushedTexture(value) self.pushedTexture = value end
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
    if self.enabled and self:IsVisible() and self.scripts.OnClick then
        local previous = MOCK.hardware; MOCK.hardware = true
        self.scripts.OnClick(self, "LeftButton")
        MOCK.hardware = previous
    end
end
function Frame:RegisterEvent(event) self.registered = self.registered or {}; self.registered[event] = true end
for _, method in ipairs({"SetAutoFocus", "SetFontObject", "SetMaxLetters", "SetFrameStrata",
    "EnableMouse", "RegisterForDrag", "StartMoving",
    "StopMovingOrSizing", "SetHighlightTexture", "SetHitRectInsets", "SetCursorPosition", "SetOwner",
    "SetItemByID", "AddLine"}) do Frame[method] = function() end end

UIParent = make("Frame", "UIParent"); UIParent:SetSize(1600, 1000)
GameFontHighlight = {}
GameTooltip = make("Frame", "GameTooltip"); GameTooltip:Hide()
UISpecialFrames, SlashCmdList, StaticPopupDialogs = {}, {}, {}
MenuUtil = {}
function MenuUtil.CreateContextMenu(owner, generator)
    local menu = {owner = owner, entries = {}}
    function menu:SetScrollMode(height) self.scrollHeight = height end
    function menu:CreateTitle(text) table.insert(self.entries, {kind = "title", text = text}) end
    function menu:CreateDivider() table.insert(self.entries, {kind = "divider"}) end
    function menu:CreateButton(text, callback)
        local entry = {kind = "button", text = text, callback = callback}
        function entry:Click()
            if owner:IsVisible() then MOCK.menu = nil; self.callback() end
        end
        table.insert(self.entries, entry); return entry
    end
    function menu:CreateRadio(text, selected, callback)
        local entry = self:CreateButton(text, callback)
        entry.kind, entry.selected = "radio", selected
        return entry
    end
    generator(owner, menu); MOCK.menu = menu
    return menu
end
tinsert = table.insert
strmatch = string.match
function GetTime() return MOCK.time end
function GetServerTime() return MOCK.serverTime or 1794450000 end
function GetMoney() return MOCK.money or 10000000 end
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
function StaticPopup_Show(which, text, _, data) MOCK.popup = {which = which, text = text, data = data} end
function StaticPopup_Visible(which) return MOCK.popup and MOCK.popup.which == which end
function StaticPopup_Hide(which)
    if not StaticPopup_Visible(which) then return end
    local popup = MOCK.popup; MOCK.popup = nil
    local definition = StaticPopupDialogs[which]
    if definition and definition.OnHide then definition.OnHide(popup, popup.data) end
end
function MOCK.acceptPopup()
    local popup = assert(MOCK.popup)
    MOCK.hardware = true
    StaticPopupDialogs[popup.which].OnAccept(popup, popup.data)
    MOCK.hardware = nil
    StaticPopup_Hide(popup.which)
end
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
    After = function(delay, callback)
        if delay == 0 then table.insert(MOCK.timers, callback)
        else
            MOCK.delayed = MOCK.delayed or {}
            table.insert(MOCK.delayed, {at = MOCK.time + delay, callback = callback})
        end
    end,
    NewTicker = function(_, callback) table.insert(MOCK.tickers, callback); return {} end,
}
function MOCK.flush()
    for i = #(MOCK.delayed or {}), 1, -1 do
        if MOCK.delayed[i].at <= MOCK.time then
            table.insert(MOCK.timers, table.remove(MOCK.delayed, i).callback)
        end
    end
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
    DoesItemExist = function() return not MOCK.removed end,
    GetItemID = function() return MOCK.bagItemID or 1 end,
    GetItemGUID = function() return not MOCK.removed and (MOCK.itemGUID or "Item-1") or nil end,
    GetItemLink = function() return not MOCK.coldItem and "item:" .. (MOCK.bagItemID or 1) or nil end,
}
C_Container = {
    GetContainerNumSlots = function(bag) return bag == 0 and 1 or 0 end,
    GetContainerItemInfo = function() return {itemID = MOCK.bagItemID or 1, isLocked = MOCK.locked} end,
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
ItemLocation = {CreateFromBagAndSlot = function(_, bag, slot)
    return {bag = bag, slot = slot, GetBagAndSlot = function(self) return self.bag, self.slot end}
end}
local function post(kind, item, duration, quantity, price, bid)
    assert(MOCK.hardware, "Transaction without a hardware click")
    MOCK.postCalls = MOCK.postCalls + 1
    MOCK.lastPost = {kind=kind,item=item,duration=duration,quantity=quantity,price=price,bid=bid}
    if MOCK.onPost then MOCK.onPost() end
    return MOCK.needsConfirmation or false
end
C_AuctionHouse = {
    GetBrowseResults = function() return MOCK.browseResults or {} end,
    SendBrowseQuery = function() MOCK.browseQueries = (MOCK.browseQueries or 0)+1 end,
    SearchForFavorites = function() MOCK.browseQueries = (MOCK.browseQueries or 0)+1 end,
    SearchForItemKeys = function() MOCK.browseQueries = (MOCK.browseQueries or 0)+1 end,
    RequestMoreBrowseResults = function() MOCK.browsePageRequests = (MOCK.browsePageRequests or 0)+1 end,
    MakeItemKey = function(id) return {itemID = id} end,
    GetItemKeyFromItem = function() return {itemID=MOCK.bagItemID or 1,itemSuffix=MOCK.itemSuffix or 0} end,
    GetItemKeyInfo = function()
        if MOCK.keyInfo == false then return nil end
        return MOCK.keyInfo or {isCommodity = true}
    end,
    IsThrottledMessageSystemReady = function() return MOCK.ready ~= false end,
    SendSearchQuery = function(key) table.insert(MOCK.queries, key.itemID) end,
    SupportsCopperValues = function() return MOCK.copper == true end,
    IsSellItemValid = function() return not MOCK.bound end,
    GetAvailablePostCount = function() return MOCK.availableCount or 120 end,
    GetItemCommodityStatus = function() return MOCK.commodityStatus or 2 end,
    CalculateCommodityDeposit = function(id,duration,quantity)
        if MOCK.depositMissing then return nil end
        return MOCK.deposit or 75 * duration * quantity
    end,
    CalculateItemDeposit = function(item,duration,quantity)
        if MOCK.depositMissing then return nil end
        return MOCK.deposit or 100 * duration * quantity
    end,
    GetAuctionInfoByID = function() return MOCK.auctionInfo end,
    PostCommodity = function(item,duration,quantity,price) return post("commodity",item,duration,quantity,price) end,
    PostItem = function(item,duration,quantity,bid,buyout) return post("item",item,duration,quantity,buyout,bid) end,
    ConfirmPostCommodity = function(item,duration,quantity,price) return post("confirmCommodity",item,duration,quantity,price) end,
    ConfirmPostItem = function(item,duration,quantity,bid,buyout) return post("confirmItem",item,duration,quantity,buyout,bid) end,
    StartCommoditiesPurchase = function() MOCK.purchaseCalls = (MOCK.purchaseCalls or 0) + 1 end,
    ConfirmCommoditiesPurchase = function() MOCK.purchaseCalls = (MOCK.purchaseCalls or 0) + 1 end,
    PlaceBid = function() MOCK.purchaseCalls = (MOCK.purchaseCalls or 0) + 1 end,
}
AuctionHouseUtil = {GetErrorText = function(code) return "拍卖行错误 " .. tostring(code) end}
AuctionHouseFrame = make("Frame", "AuctionHouseFrame", UIParent)
AuctionHouseFrame:SetSize(850, 600)
AuctionHouseFrame.Tabs = {make("Button", nil, AuctionHouseFrame), make("Button", nil, AuctionHouseFrame), make("Button", nil, AuctionHouseFrame)}
AuctionHouseFrameDisplayMode = {Buy = {"Buy"}, ItemBuy = {"ItemBuy"}, CommoditiesBuy = {"CommoditiesBuy"},
    ItemSell = {"ItemSell"}, CommoditiesSell = {"CommoditiesSell"}, Auctions = {"Auctions"}}
function AuctionHouseFrame:SetDisplayMode(mode)
    self.displayMode = mode
    if self.CommoditiesSellFrame then
        self.CommoditiesSellFrame:SetShown(mode == AuctionHouseFrameDisplayMode.CommoditiesSell)
        self.ItemSellFrame:SetShown(mode == AuctionHouseFrameDisplayMode.ItemSell)
    end
end
function AuctionHouseFrame:GetDisplayMode() return self.displayMode end
function AuctionHouseFrame:SetTitle(title) self.title = title end
function AuctionHouseFrame:SelectBrowseResult(result)
    if MOCK.rejectBuy then error("Native selection failed") end
    self.buyResult = result
    local info = C_AuctionHouse.GetItemKeyInfo(result.itemKey)
    self:SetDisplayMode(info.isCommodity and AuctionHouseFrameDisplayMode.CommoditiesBuy or AuctionHouseFrameDisplayMode.ItemBuy)
    -- The native buy list's OnShow refreshes its exact item, independently of the monitor queue.
    MOCK.nativeQueries = MOCK.nativeQueries or {}
    table.insert(MOCK.nativeQueries, result.itemKey.itemID)
end
local function sellForm()
    local form = make("Frame", nil, AuctionHouseFrame); form:Hide()
    form.QuantityInput = {InputBox = make("EditBox", nil, form), MaxButton = make("Button", nil, form)}
    function form.QuantityInput:SetQuantity(value) self.value = value; self.InputBox:SetNumber(value) end
    function form.QuantityInput:GetQuantity() return self.InputBox:GetNumber() end
    form.PriceInput = {MoneyInputFrame = {GoldBox = make("EditBox", nil, form),
        SilverBox = make("EditBox", nil, form), CopperBox = make("EditBox", nil, form)}}
    function form.PriceInput:SetAmount(value) self.value = value end
    function form.PriceInput:GetAmount() return self.value end
    form.Duration = {Dropdown = make("Button", nil, form), value = 2}
    function form.Duration:SetDuration(value) self.value = value end
    function form.Duration:GetDuration() return self.value end
    function form.Duration.Dropdown:GenerateMenu() end
    form.ItemDisplay = {ItemButton = make("Button", nil, form)}
    function form.ItemDisplay:GetItemLink() if not MOCK.coldItem and not MOCK.coldDisplay then return "item:1" end end
    function form:GetItem() return self.item end
    function form:GetQuantity() return self.QuantityInput:GetQuantity() end
    function form:UpdatePostState() self.updated = true end
    return form
end
AuctionHouseFrame.CommoditiesSellFrame = sellForm()
AuctionHouseFrame.ItemSellFrame = sellForm()
function AuctionHouseFrame:SetPostItem(item)
    MOCK.nativeSetPostCalls = (MOCK.nativeSetPostCalls or 0) + 1
    if MOCK.rejectPostItem then return end
    local isCommodity = C_AuctionHouse.GetItemCommodityStatus(item) == 2
    self:SetDisplayMode(isCommodity and AuctionHouseFrameDisplayMode.CommoditiesSell or AuctionHouseFrameDisplayMode.ItemSell)
    local form = isCommodity and self.CommoditiesSellFrame or self.ItemSellFrame
    form.item = item
    -- The native item display locks the selected bag item until it is cleared.
    MOCK.locked = true
    -- Native SetItem resets quantity, then commodities replace it with the bag stack count.
    form.QuantityInput:SetQuantity(isCommodity and (MOCK.stackCount or 120) or 1)
    form.PriceInput:SetAmount(0)
end
