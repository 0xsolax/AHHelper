local _, A = ...
local W = {}
A.Widgets = W
W.gold = { 0.89, 0.75, 0.47 }
W.text = { 0.91, 0.87, 0.77 }
W.muted = { 0.61, 0.61, 0.57 }
W.green = { 0.58, 0.89, 0.36 }
W.red = { 1, 0.39, 0.30 }
W.amber = { 1, 0.73, 0.28 }

function W.Panel(parent, width, height)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(width, height)
    frame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16,
        edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    frame:SetBackdropColor(0.12, 0.12, 0.11, 1)
    frame:SetBackdropBorderColor(0.56, 0.43, 0.22, 1)
    return frame
end

function W.Text(parent, text, size, color, width)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    local font = label:GetFont()
    label:SetFont(font, size or 14, "")
    label:SetText(text or "")
    label:SetTextColor(unpack(color or W.text))
    label:SetJustifyH("LEFT")
    if width then label:SetWidth(width); label:SetWordWrap(true) end
    return label
end

function W.Label(parent, text, x, y, size, color, width)
    local label = W.Text(parent, text, size, color, width)
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    return label
end

function W.Button(parent, text, width, height, callback)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, height or 28)
    button:SetText(text)
    if callback then button:SetScript("OnClick", callback) end
    return button
end

function W.Edit(parent, width, value)
    local edit = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    edit:SetSize(width, 28)
    edit:SetAutoFocus(false)
    edit:SetFontObject(GameFontHighlight)
    edit:SetMaxLetters(80)
    edit:SetText(value == nil and "" or tostring(value))
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return edit
end

function W.MoneyInput(parent, callback)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(184, 28)
    frame.boxes = {}
    local specs = { {0, 60, "金"}, {84, 30, "银"}, {138, 30, "铜"} }
    for i, spec in ipairs(specs) do
        local box = W.Edit(frame, spec[2], "")
        box:SetPoint("LEFT", spec[1] + 4, 0)
        box:SetMaxLetters(i == 1 and 8 or 2)
        local label = W.Text(frame, spec[3], 12, W.muted)
        label:SetPoint("LEFT", box, "RIGHT", 4, 0)
        frame.boxes[i] = box
        box:SetScript("OnTextChanged", function(_, userInput)
            if not frame.setting and callback then callback(userInput) end
        end)
    end
    function frame:GetCopper()
        local values, blank = {}, true
        for i, box in ipairs(self.boxes) do
            local text = box:GetText()
            if text ~= "" then blank = false end
            values[i] = A.Logic.Number(text == "" and 0 or text, 0, i == 1 and 100000000 or 99, true)
            if not values[i] then return nil end
        end
        if blank then return nil end
        return values[1] * 10000 + values[2] * 100 + values[3]
    end
    function frame:SetCopper(value)
        self.setting = true
        local n = value and math.floor(value + 0.5)
        self.boxes[1]:SetText(n and tostring(math.floor(n / 10000)) or "")
        self.boxes[2]:SetText(n and tostring(math.floor(n % 10000 / 100)) or "")
        self.boxes[3]:SetText(n and tostring(n % 100) or "")
        self.setting = false
    end
    function frame:SetEnabled(enabled)
        for _, box in ipairs(self.boxes) do
            box:SetEnabled(enabled)
            box:SetTextColor(unpack(enabled and W.text or W.muted))
        end
    end
    return frame
end

function W.ItemInput(parent, width, callback)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(width, 34)
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetSize(30, 30)
    frame.icon:SetPoint("LEFT", 0, 0)
    frame.icon:SetTexture(134400)
    frame.edit = W.Edit(frame, width - 42, "")
    frame.edit.auctionPilotItemInput = frame
    frame.edit:SetPoint("LEFT", 40, 0)
    frame.edit:SetMaxLetters(255)
    function frame:RefreshName()
        if self.itemID then
            local name, icon = A.ItemInfo(self.itemID)
            self.icon:SetTexture(icon)
            if not self.edit:HasFocus() then
                self.setting = true; self.edit:SetText(name); self.setting = false
            end
        end
    end
    function frame:SetItem(id)
        self.itemID = id
        self.setting = true
        self.edit:SetText(id and (A.ItemInfo(id)) or "")
        self.icon:SetTexture(id and select(2, A.ItemInfo(id)) or 134400)
        self.setting = false
        if id then C_Item.RequestLoadItemDataByID(id) end
        if callback then callback() end
    end
    local function receive()
        if frame.locked then return end
        local kind, id = GetCursorInfo()
        if kind == "item" and id then frame:SetItem(id); ClearCursor() end
    end
    frame:EnableMouse(true)
    frame:SetScript("OnMouseDown", function() if not frame.locked then frame.edit:SetFocus() end end)
    frame:SetScript("OnReceiveDrag", receive)
    frame.edit:SetScript("OnReceiveDrag", receive)
    frame.edit:SetScript("OnTextChanged", function(_, userInput)
        if frame.setting or not userInput then return end
        local text = frame.edit:GetText()
        local id = A.Logic.ItemID(text)
        if not id and text ~= "" then
            local _, link = C_Item.GetItemInfo(text)
            id = A.Logic.ItemID(link)
        end
        frame.itemID = id
        frame.icon:SetTexture(id and select(2, A.ItemInfo(id)) or 134400)
        if id then C_Item.RequestLoadItemDataByID(id) end
        if callback then callback() end
    end)
    frame.edit:SetScript("OnEditFocusLost", function() frame:RefreshName() end)
    function frame:SetEnabled(enabled)
        self.locked = not enabled
        self:EnableMouse(enabled)
        self.edit:SetEnabled(enabled)
    end
    frame:SetScript("OnEnter", function()
        GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
        if frame.itemID then GameTooltip:SetItemByID(frame.itemID)
        else GameTooltip:SetText("点击输入框后 Shift 点击物品，也可拖入或粘贴链接 / 编号") end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return frame
end

function W.InstallItemLinks()
    if W.itemLinksInstalled then return end
    local owner, key = ChatFrameUtil, "InsertLink"
    if not owner or type(owner[key]) ~= "function" then owner, key = _G, "ChatEdit_InsertLink" end
    local previous = owner[key]
    if type(previous) ~= "function" then return end
    -- Return true only for our focused item field, so native stack splitting does not also run.
    owner[key] = function(link, ...)
        local focus = GetCurrentKeyBoardFocus()
        local input = focus and focus.auctionPilotItemInput
        local id = A.Logic.ItemID(link)
        if id and input and not input.locked and focus:IsVisible() and focus:IsEnabled()
            and IsShiftKeyDown() and A.Editor.frame:IsVisible() then
            input:SetItem(id); focus:ClearFocus(); return true
        end
        return previous(link, ...)
    end
    W.itemLinksInstalled = true
end

function W.Scroll(parent, width, height)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetSize(width - 24, height)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(width - 24, height)
    scroll:SetScrollChild(content)
    scroll.content = content
    return scroll
end

function W.Icon(parent, size)
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetSize(size, size)
    icon:SetTexture(134400)
    return icon
end

function W.ProfitColor(value) return value and value >= 0 and W.green or value and W.red or W.muted end

function W.Amount(label, amount, signed)
    label:SetText((signed and amount and amount > 0 and "+" or "") .. A.Logic.Money(amount))
    label:SetTextColor(unpack(signed and W.ProfitColor(amount) or W.text))
end
