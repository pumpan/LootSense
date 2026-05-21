

local gfind = string.gmatch or string.gfind

-- ##################################################
-- ## CONFIG / DATABASE
-- ##################################################
LootSense_keep   = LootSense_keep   or {}
LootSense_vendor = LootSense_vendor or {}
LootSense_delete = LootSense_delete or {}

-- Bank system SavedVariables
LootSense_banks        = LootSense_banks        or {}
LootSense_bankRules    = LootSense_bankRules    or {}
LootSense_bankPending  = LootSense_bankPending  or {}
LootSense_bankOutgoing = LootSense_bankOutgoing or {}

-- Collections: auto-route loot categories to a bank
-- { [collectionName] = { bank = "BankAlt", category = "enchant" } }
LootSense_collections  = LootSense_collections  or {}

-- ##################################################
-- ## COLLECTION CATEGORY DEFINITIONS
-- ##################################################
-- Maps a short category key -> { itemType patterns, itemSubType patterns }
-- Uses lowercase string matching against GetItemInfo returns.
local LootSense_CategoryDefs = {
    enchant   = { types = { "trade goods" }, subtypes = { "enchanting" } },
    recipe    = { types = { "recipe", "tradeskill" }, subtypes = {} },
    cloth     = { types = { "trade goods" }, subtypes = { "cloth" } },
    leather   = { types = { "trade goods" }, subtypes = { "leather" } },
    metal     = { types = { "trade goods" }, subtypes = { "metal & stone", "metal and stone" } },
    herb      = { types = { "trade goods" }, subtypes = { "herbs" } },
    gem       = { types = { "trade goods" }, subtypes = { "gems", "jewelcrafting" } },
    potion    = { types = { "consumable" }, subtypes = { "potion", "elixir", "flask" } },
    food      = { types = { "consumable" }, subtypes = { "food & drink", "food and drink" } },
    green     = { quality = 2 },  -- quality-based, any type
    blue      = { quality = 3 },
    epic      = { quality = 4 },
}

-- Human-readable labels for the UI
local LootSense_CategoryLabels = {
    enchant   = "Enchanting mats",
    recipe    = "Recipes / Formulas",
    cloth     = "Cloth",
    leather   = "Leather",
    metal     = "Metal & Stone",
    herb      = "Herbs",
    gem       = "Gems",
    potion    = "Potions & Elixirs",
    food      = "Food & Drink",
    green     = "Uncommon (green)",
    blue      = "Rare (blue)",
    epic      = "Epic (purple)",
}

-- Ordered list for UI display
local LootSense_CategoryOrder = {
    "enchant","recipe","cloth","leather","metal","herb","gem","potion","food","green","blue","epic"
}

-- Returns the category key that matches an item, or nil.
-- itemType/itemSubType are the raw strings from GetItemInfo.
function LootSense_GetItemCategory(itemType, itemSubType, quality)
    local lType    = string.lower(itemType or "")
    local lSubType = string.lower(itemSubType or "")
    local q        = tonumber(quality) or 1

    for _, key in ipairs(LootSense_CategoryOrder) do
        local def = LootSense_CategoryDefs[key]
        if def then
            -- quality-based check (green/blue/epic) – only match if quality exactly matches
            if def.quality and not def.types then
                if q == def.quality then return key end
            else
                -- type/subtype check
                local typeMatch = false
                for _, t in ipairs(def.types or {}) do
                    if string.find(lType, t, 1, true) then typeMatch = true break end
                end
                if typeMatch then
                    if #(def.subtypes or {}) == 0 then
                        return key
                    end
                    for _, s in ipairs(def.subtypes) do
                        if string.find(lSubType, s, 1, true) then return key end
                    end
                end
            end
        end
    end
    return nil
end

-- Check if an item should be auto-banked by a collection rule.
-- Returns bankName or nil.
function LootSense_GetCollectionBank(itemType, itemSubType, quality)
    local cat = LootSense_GetItemCategory(itemType, itemSubType, quality)
    if not cat then return nil end
    local rule = LootSense_collections[cat]
    if rule and rule.bank and rule.bank ~= "" and LootSense_BankExists and LootSense_BankExists(rule.bank) then
        return rule.bank, cat
    end
    return nil
end

LootSense_settings = LootSense_settings or {}
if LootSense_settings.autoDeleteEnabled == nil then LootSense_settings.autoDeleteEnabled = true end
if LootSense_settings.mailEnabled == nil then LootSense_settings.mailEnabled = true end
if LootSense_settings.vendorEnabled == nil then LootSense_settings.vendorEnabled = true end

function LootSense_IsFeatureEnabled(feature)
    LootSense_settings = LootSense_settings or {}
    if feature == "autoDelete" then return LootSense_settings.autoDeleteEnabled ~= false end
    if feature == "mail" then return LootSense_settings.mailEnabled ~= false end
    if feature == "vendor" then return LootSense_settings.vendorEnabled ~= false end
    return true
end

local versionNumber = "1.1.1"

-- Debug helper. Set LootSense_debug = false in-game if you want to silence these test messages.
if LootSense_debug == nil then LootSense_debug = false end
local function LootSense_Debug(msg)
    if LootSense_debug and DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff[LootSense Debug]|r " .. tostring(msg or ""))
    end
end

-- item quality colors
local colors = {
  [0] = {0.6, 0.6, 0.6},    -- Poor (gray)
  [1] = {1, 1, 1},          -- Common (white)
  [2] = {0, 1, 0},          -- Uncommon (green)
  [3] = {0, 0.44, 0.87},    -- Rare (blue)
  [4] = {0.64, 0.21, 0.93}, -- Epic (purple)
  [5] = {1, 0.5, 0},        -- Legendary (orange)
  [6] = {0.9, 0.8, 0.5},    -- Artifact / heirloom-ish fallback
  [7] = {0.9, 0.8, 0.5},
  [8] = {0, 0.8, 1},
}

local LootSense_ActionIcons = {
    keep   = "Interface\\Buttons\\Button-Backpack-Up",
    bank   = "Interface\\Icons\\INV_Box_01",
    vendor = "Interface\\Buttons\\UI-GroupLoot-Coin-Up",
    delete = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
    throw  = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
    ignore = "Interface\\Buttons\\UI-Panel-MinimizeButton-Up",
    none   = "Interface\\Icons\\INV_Misc_QuestionMark",
}

local function LootSense_AddSpecialFrame(frameName)
    if not frameName or not UISpecialFrames then return end
    for i = 1, #UISpecialFrames do
        if UISpecialFrames[i] == frameName then return end
    end
    table.insert(UISpecialFrames, frameName)
end

local function LootSense_ApplyQualityColor(fontString, quality, itemLink)
    if not fontString then return end
    if quality and colors[quality] then
        fontString:SetTextColor(unpack(colors[quality]))
        return
    end
    if itemLink then
        local hex = string.match(itemLink, "|c(%x%x)(%x%x)(%x%x)(%x%x)")
        if hex then
            local a, r, g, b = string.match(itemLink, "|c(%x%x)(%x%x)(%x%x)(%x%x)")
            if r and g and b then
                fontString:SetTextColor(tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255)
                return
            end
        end
    end
    fontString:SetTextColor(1, 1, 1)
end

local function LootSense_Clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function LootSense_GetItemIcon(itemID, itemLink)
    local key = itemLink or itemID
    local icon

    if itemID and C_Item and C_Item.GetItemIconByID then
        icon = C_Item.GetItemIconByID(itemID)
    end

    if not icon and key and GetItemInfoInstant then
        local _, _, _, _, instantIcon = GetItemInfoInstant(key)
        icon = instantIcon
    end

    if not icon and key then
        local _, _, _, _, _, _, _, _, _, itemIcon = GetItemInfo(key)
        icon = itemIcon
    end

    return icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- =========================================================
-- == LootSense Minimap Button (WoW 1.14) ==
-- =========================================================
local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self, event)
    DEFAULT_CHAT_FRAME:AddMessage("LootSense [" .. versionNumber .. "]|cff00FF00 loaded|cffffffff")
end)

if not LootSense_MinimapPos then LootSense_MinimapPos = 45 end

local buttonSize = 31
local radius = 80

LootSense_MinimapButton = CreateFrame("Button", "LootSense_MinimapButton", Minimap)
LootSense_MinimapButton:SetSize(buttonSize, buttonSize)
LootSense_MinimapButton:SetFrameStrata("MEDIUM")
LootSense_MinimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")

LootSense_MinimapButton.icon = LootSense_MinimapButton:CreateTexture(nil, "ARTWORK")
LootSense_MinimapButton.icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_10")
LootSense_MinimapButton.icon:SetPoint("TOPLEFT", 7, -6)
LootSense_MinimapButton.icon:SetSize(20, 20)

LootSense_MinimapButton.border = LootSense_MinimapButton:CreateTexture(nil, "OVERLAY")
LootSense_MinimapButton.border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
LootSense_MinimapButton.border:SetSize(54, 54)
LootSense_MinimapButton.border:SetPoint("TOPLEFT", 0, 0)

LootSense_MinimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")

local function UpdateMinimapButtonPosition()
    local angle = LootSense_MinimapPos or 45
    local x = radius * math.cos(angle)
    local y = radius * math.sin(angle)
    LootSense_MinimapButton:ClearAllPoints()
    LootSense_MinimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

LootSense_MinimapButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("|cff33ffccLoot|cffffffffSense")
    GameTooltip:AddLine("Left-click: Open LootSense", 1,1,1)
    GameTooltip:AddLine("Left-click + drag: Move button", 0.7,0.7,0.7)
    GameTooltip:AddLine("Right-click: Clean Bags", 0.7,0.7,0.7)
    GameTooltip:Show()
end)
LootSense_MinimapButton:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
end)

LootSense_MinimapButton:SetScript("OnClick", function(self, button)
    if button == "LeftButton" and not self.isDragging then
        if LootSenseList and LootSenseList:IsShown() then
            LootSenseList:Hide()
        elseif LootSenseList then
            LootSenseList:Show()
        end
    elseif button == "RightButton" then
        LootSense_ScanDeleteQueue()
        local totalStacks = LootSense_CountDeleteQueue()
        if totalStacks > 0 then
            LootSense_RefreshCleanBagsFrame()
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cffaaaaaa[LootSense]|r No deletable items in bags.")
        end
    end
end)

LootSense_MinimapButton:SetScript("OnMouseDown", function(self, button)
    if button == "LeftButton" then
        self.isDragging = false
        self.dragStartX, self.dragStartY = GetCursorPosition()
        self:SetScript("OnUpdate", function(self)
            local cx, cy = GetCursorPosition()
            -- only start dragging after moving 4px to distinguish from a click
            if not self.isDragging then
                local dx = (cx - (self.dragStartX or cx))
                local dy = (cy - (self.dragStartY or cy))
                if math.sqrt(dx*dx + dy*dy) < 4 then return end
                self.isDragging = true
            end
            local mx, my = Minimap:GetCenter()
            local scale = Minimap:GetEffectiveScale()
            local px, py = cx / scale, cy / scale
            LootSense_MinimapPos = math.atan2(py - my, px - mx)
            UpdateMinimapButtonPosition()
        end)
    end
end)

LootSense_MinimapButton:SetScript("OnMouseUp", function(self, button)
    if button == "LeftButton" then
        self.isDragging = false
        self:SetScript("OnUpdate", nil)
    end
end)

local minimapInit = CreateFrame("Frame")
minimapInit:RegisterEvent("ADDON_LOADED")
minimapInit:SetScript("OnEvent", function(self, event, addonName)
    if addonName == "LootSense" then
        UpdateMinimapButtonPosition()
        LootSense_MinimapButton:Show()
    end
end)
UpdateMinimapButtonPosition()


-- ##################################################
-- ## AUTODELETE / CLEAN BAGS (WoW 1.14 safe-ish)
-- ##################################################
-- DeleteCursorItem() is protected in 1.14 when called from OnUpdate/timers.
-- This frame scans automatically, but the actual delete attempt is done from
-- the player's Clean Bags click. Variant B: try to clean multiple stacks in one click.

local AutoTrash = CreateFrame("Frame", "AutoTrashFrame", UIParent)
-- Only open Clean Bags after the client says loot could not fit in the bags.
-- Normal ITEM_PUSH/BAG_UPDATE while looting a delete-list item should NOT show the popup.
AutoTrash:RegisterEvent("UI_ERROR_MESSAGE")
AutoTrash:RegisterEvent("BAG_UPDATE_DELAYED")
AutoTrash.queue = {}
AutoTrash.rows = {}
AutoTrash.active = false
AutoTrash.lastCleaned = 0
AutoTrash.showBecauseInventoryFull = false
AutoTrash.suppressUntil = 0
AutoTrash:Hide()

local function LootSense_GetContainerSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bag)
    end
    return GetContainerNumSlots(bag)
end

local function LootSense_GetContainerLink(bag, slot)
    if C_Container and C_Container.GetContainerItemLink then
        return C_Container.GetContainerItemLink(bag, slot)
    end
    return GetContainerItemLink(bag, slot)
end

local function LootSense_GetContainerInfo(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info then
            local count = tonumber(info.stackCount) or tonumber(info.count) or tonumber(info.itemCount)
            if count and count > 0 then
                local icon = info.iconFileID or info.iconFileDataID or info.texture
                LootSense_Debug("GetContainerInfo (C_Container) bag="..bag.." slot="..slot.." count="..tostring(count))
                return icon, count
            end
        end
        -- C_Container returned nil or empty table, fall through to classic API
    end
    local r1, r2, r3, r4, r5, r6, r7, r8, r9, r10 = GetContainerItemInfo(bag, slot)
    LootSense_Debug("GetContainerInfo (classic) bag="..bag.." slot="..slot.." r1="..tostring(r1).." r2="..tostring(r2).." r3="..tostring(r3))
    local texture = r1
    local count = tonumber(r2) or 1
    return texture, count
end

local function LootSense_PickupContainerItem(bag, slot)
    if C_Container and C_Container.PickupContainerItem then
        C_Container.PickupContainerItem(bag, slot)
    else
        PickupContainerItem(bag, slot)
    end
end

local function LootSense_IsDeleteItemName(itemName)
    if not itemName then return false end
    local lowerName = string.lower(itemName)
    for n = 1, #(LootSense_delete or {}) do
        local data = LootSense_delete[n]
        if data and data.name and string.lower(data.name) == lowerName then
            return true
        end
    end
    return false
end

local function LootSense_GetFreeBagSlots()
    local free = 0
    for bagIndex = 0, 4 do
        local slots = LootSense_GetContainerSlots(bagIndex) or 0
        for slotIndex = 1, slots do
            if not LootSense_GetContainerLink(bagIndex, slotIndex) then
                free = free + 1
            end
        end
    end
    return free
end

local function LootSense_IsInventoryFullError(errorType, message)
    local msg = tostring(message or errorType or "")
    local low = string.lower(msg)

    -- 1.14 usually passes an errorType plus a localized message. Keep this loose
    -- so it still works on non-English clients if the global constant is available.
    if ERR_INV_FULL and msg == ERR_INV_FULL then return true end
    if ERR_BAG_FULL and msg == ERR_BAG_FULL then return true end

    if string.find(low, "inventory is full", 1, true) then return true end
    if string.find(low, "bag is full", 1, true) then return true end
    if string.find(low, "bags are full", 1, true) then return true end

    return false
end

function LootSense_ScanDeleteQueue()
    local queue = {}
    local grouped = {}

    for bagIndex = 0, 4 do
        local numSlots = LootSense_GetContainerSlots(bagIndex) or 0
        for slotIndex = 1, numSlots do
            local link = LootSense_GetContainerLink(bagIndex, slotIndex)
            if link then
                local itemName = GetItemInfo(link)
                if itemName and LootSense_IsDeleteItemName(itemName) then
                    local texture, count = LootSense_GetContainerInfo(bagIndex, slotIndex)
                    count = tonumber(count) or 1
                    table.insert(queue, {
                        bag = bagIndex,
                        slot = slotIndex,
                        name = itemName,
                        link = link,
                        texture = texture or "Interface\\Icons\\INV_Misc_QuestionMark",
                        count = count,
                    })

                    local key = string.lower(itemName)
                    if not grouped[key] then
                        grouped[key] = { name = itemName, texture = texture or "Interface\\Icons\\INV_Misc_QuestionMark", count = 0, stacks = 0 }
                    end
                    grouped[key].count = grouped[key].count + count
                    grouped[key].stacks = grouped[key].stacks + 1
                end
            end
        end
    end

    AutoTrash.queue = queue
    AutoTrash.grouped = grouped
    return queue, grouped
end

function LootSense_CountDeleteQueue()
    local totalStacks = 0
    local totalItems = 0
    for i = 1, #(AutoTrash.queue or {}) do
        totalStacks = totalStacks + 1
        totalItems = totalItems + (tonumber(AutoTrash.queue[i].count) or 1)
    end
    return totalStacks, totalItems
end

function LootSense_RefreshCleanBagsFrame()
    if not LootSenseCleanBagsFrame then return end

    LootSense_ScanDeleteQueue()
    local totalStacks, totalItems = LootSense_CountDeleteQueue()
    local freeSlots = LootSense_GetFreeBagSlots()

    if totalStacks <= 0 then
        LootSenseCleanBagsFrame:Hide()
        return
    end

    LootSenseCleanBagsFrame.status:SetText("Deletable: "..totalStacks.." stack(s), "..totalItems.." item(s). Free bag slots: "..freeSlots)

    for i = 1, #(LootSenseCleanBagsFrame.rows or {}) do
        LootSenseCleanBagsFrame.rows[i]:Hide()
    end

    local rowIndex = 1
    local key, data
    for key, data in pairs(AutoTrash.grouped or {}) do
        if rowIndex > 8 then break end
        local row = LootSenseCleanBagsFrame.rows[rowIndex]
        if not row then
            row = CreateFrame("Frame", nil, LootSenseCleanBagsFrame)
            row:SetWidth(260)
            row:SetHeight(22)
            row:SetPoint("TOPLEFT", 16, -(56 + ((rowIndex - 1) * 24)))
            row.icon = row:CreateTexture(nil, "OVERLAY")
            row.icon:SetWidth(18)
            row.icon:SetHeight(18)
            row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
            row.text:SetJustifyH("LEFT")
            LootSenseCleanBagsFrame.rows[rowIndex] = row
        end
        row.icon:SetTexture(data.texture or "Interface\\Icons\\INV_Misc_QuestionMark")
        row.text:SetText((data.name or "?").." x"..(data.count or 1).."  ("..(data.stacks or 1).." stack(s))")
        row:Show()
        rowIndex = rowIndex + 1
    end

    if totalStacks > 8 then
        LootSenseCleanBagsFrame.moreText:SetText("+"..(totalStacks - 8).." more stack(s)...")
        LootSenseCleanBagsFrame.moreText:Show()
    else
        LootSenseCleanBagsFrame.moreText:Hide()
    end

    LootSenseCleanBagsFrame.cleanBtn:SetText("Clean Bags")
    LootSenseCleanBagsFrame:Show()
end

LootSenseCleanBagsFrame = CreateFrame("Frame", "LootSenseCleanBagsFrame", UIParent, "BackdropTemplate")
LootSenseCleanBagsFrame:SetWidth(310)
LootSenseCleanBagsFrame:SetHeight(300)
LootSenseCleanBagsFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 90)
LootSenseCleanBagsFrame:SetFrameStrata("DIALOG")
LootSenseCleanBagsFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
LootSenseCleanBagsFrame:SetBackdropColor(0,0,0,0.86)
LootSenseCleanBagsFrame:SetBackdropBorderColor(0.7,0.7,0.7,1)
LootSenseCleanBagsFrame:SetMovable(true)
LootSenseCleanBagsFrame:EnableMouse(true)
LootSenseCleanBagsFrame:RegisterForDrag("LeftButton")
LootSenseCleanBagsFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
LootSenseCleanBagsFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
LootSenseCleanBagsFrame:Hide()
LootSenseCleanBagsFrame.rows = {}

LootSense_AddSpecialFrame("LootSenseCleanBagsFrame")

LootSenseCleanBagsFrame.title = LootSenseCleanBagsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
LootSenseCleanBagsFrame.title:SetPoint("TOP", 0, -10)
LootSenseCleanBagsFrame.title:SetText("LootSense Clean Bags")

LootSenseCleanBagsFrame.closeBtn = CreateFrame("Button", nil, LootSenseCleanBagsFrame, "UIPanelButtonTemplate")
LootSenseCleanBagsFrame.closeBtn:SetWidth(24)
LootSenseCleanBagsFrame.closeBtn:SetHeight(22)
LootSenseCleanBagsFrame.closeBtn:SetPoint("TOPRIGHT", -7, -7)
LootSenseCleanBagsFrame.closeBtn:SetText("X")
LootSenseCleanBagsFrame.closeBtn:SetScript("OnClick", function() LootSenseCleanBagsFrame:Hide() end)

LootSenseCleanBagsFrame.status = LootSenseCleanBagsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
LootSenseCleanBagsFrame.status:SetPoint("TOPLEFT", 16, -34)
LootSenseCleanBagsFrame.status:SetTextColor(1, 0.82, 0)
LootSenseCleanBagsFrame.status:SetText("Deletable items found.")

LootSenseCleanBagsFrame.moreText = LootSenseCleanBagsFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
LootSenseCleanBagsFrame.moreText:SetPoint("TOPLEFT", 16, -250)
LootSenseCleanBagsFrame.moreText:Hide()

LootSenseCleanBagsFrame.cleanBtn = CreateFrame("Button", nil, LootSenseCleanBagsFrame, "UIPanelButtonTemplate")
LootSenseCleanBagsFrame.cleanBtn:SetWidth(105)
LootSenseCleanBagsFrame.cleanBtn:SetHeight(24)
LootSenseCleanBagsFrame.cleanBtn:SetPoint("BOTTOMLEFT", 18, 12)
LootSenseCleanBagsFrame.cleanBtn:SetText("Clean Bags")
LootSenseCleanBagsFrame.cleanBtn:SetScript("OnClick", function()
    if LootSense_paused or (LootSense_IsFeatureEnabled and not LootSense_IsFeatureEnabled("autoDelete")) then return end

    LootSense_ScanDeleteQueue()
    local cleaned = 0
    local blockedOrStopped = false

    for i = 1, #(AutoTrash.queue or {}) do
        local item = AutoTrash.queue[i]
        if item and item.bag and item.slot and LootSense_GetContainerLink(item.bag, item.slot) then
            ClearCursor()
            LootSense_PickupContainerItem(item.bag, item.slot)

            if CursorHasItem and CursorHasItem() then
                -- Variant B: try several deletes from this one hardware click.
                DeleteCursorItem()
                cleaned = cleaned + 1
            else
                blockedOrStopped = true
                ClearCursor()
                break
            end
        end
    end

    ClearCursor()

    if cleaned > 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff5555[LootSense]|r Clean Bags deleted "..cleaned.." stack(s).")
        -- Hide immediately after a successful clean. Bag updates can lag slightly, so
        -- suppress automatic reopen for a moment. It will appear again on the next
        -- real inventory-full loot error if more cleanup is needed.
        AutoTrash.showBecauseInventoryFull = false
        AutoTrash.suppressUntil = GetTime() + 1.0
        LootSenseCleanBagsFrame:Hide()
    elseif blockedOrStopped then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff3333[LootSense]|r Could not delete from this click. Try again or use manual delete.")
        LootSense_RefreshCleanBagsFrame()
    else
        LootSenseCleanBagsFrame:Hide()
    end
end)

LootSenseCleanBagsFrame.closeBottomBtn = CreateFrame("Button", nil, LootSenseCleanBagsFrame, "UIPanelButtonTemplate")
LootSenseCleanBagsFrame.closeBottomBtn:SetWidth(70)
LootSenseCleanBagsFrame.closeBottomBtn:SetHeight(24)
LootSenseCleanBagsFrame.closeBottomBtn:SetPoint("LEFT", LootSenseCleanBagsFrame.cleanBtn, "RIGHT", 10, 0)
LootSenseCleanBagsFrame.closeBottomBtn:SetText("Close")
LootSenseCleanBagsFrame.closeBottomBtn:SetScript("OnClick", function() LootSenseCleanBagsFrame:Hide() end)

AutoTrash:SetScript("OnEvent", function(self, event, errorType, message)
    if LootSense_paused or (LootSense_IsFeatureEnabled and not LootSense_IsFeatureEnabled("autoDelete")) then return end

    if event == "UI_ERROR_MESSAGE" then
        if (self.suppressUntil or 0) > GetTime() then return end

        if LootSense_IsInventoryFullError(errorType, message) then
            self.showBecauseInventoryFull = true
            self.nextScan = GetTime() + 0.10
            self:Show()
        end

    elseif event == "BAG_UPDATE_DELAYED" then
        -- Bag updates are only allowed to refresh an already-open popup.
        -- They should not open it by themselves, otherwise every normal loot of a
        -- delete-list item would bring the frame back.
        if LootSenseCleanBagsFrame and LootSenseCleanBagsFrame:IsShown() then
            LootSense_RefreshCleanBagsFrame()
        end
    end
end)

AutoTrash:SetScript("OnShow", function(self)
    if (self.nextScan or 0) <= GetTime() then
        self.nextScan = GetTime() + 0.15
    end
end)

AutoTrash:SetScript("OnUpdate", function(self)
    if LootSense_paused or (LootSense_IsFeatureEnabled and not LootSense_IsFeatureEnabled("autoDelete")) then self:Hide() return end
    if (self.nextScan or 0) > GetTime() then return end
    self.nextScan = GetTime() + 0.75

    if not self.showBecauseInventoryFull then
        self:Hide()
        return
    end

    LootSense_ScanDeleteQueue()
    local totalStacks = LootSense_CountDeleteQueue()

    if totalStacks > 0 then
        LootSense_RefreshCleanBagsFrame()
    else
        if LootSenseCleanBagsFrame then LootSenseCleanBagsFrame:Hide() end
    end

    self.showBecauseInventoryFull = false
    self:Hide()
end)



-- ##################################################
-- ## SCROLLABLE LootSense LISTA MED ICON + RARITY
-- ##################################################
-- LootSenseList frame
-- =====================================================
-- LootSenseList för WoW 1.12.1
-- =====================================================
LootSenseList = CreateFrame("Frame", "LootSenseList", UIParent, "BackdropTemplate")

LootSenseList:SetWidth(520)
LootSenseList:SetHeight(450)
LootSenseList:SetPoint("CENTER", 10, -30)
LootSenseList:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
LootSenseList:SetBackdropColor(0,0,0,0.7)
LootSenseList:SetBackdropBorderColor(0.6,0.6,0.6,1)
LootSenseList:Hide()
LootSense_AddSpecialFrame("LootSenseList")
LootSenseList:SetMovable(true)
LootSenseList:EnableMouse(true)
LootSenseList:RegisterForDrag("LeftButton")
LootSenseList:SetScript("OnDragStart", function(self) self:StartMoving() end)
LootSenseList:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
LootSenseList:SetScript("OnHide", function(self) LootSense_HideActionMenu() end)

-- =====================================================
-- Stäng-knapp
-- =====================================================
LootSenseList.closeBtn = CreateFrame("Button", nil, LootSenseList, "UIPanelButtonTemplate")
LootSenseList.closeBtn:SetWidth(24)
LootSenseList.closeBtn:SetHeight(24)
LootSenseList.closeBtn:SetText("X")
LootSenseList.closeBtn:SetPoint("TOPRIGHT", -5, -5)
LootSenseList.closeBtn:SetScript("OnClick", function()
    LootSenseList:Hide()
end)

-- =====================================================
-- FLiKAR
-- =====================================================
LootSenseList.tabs = {}
LootSenseList.activeTab = "manage"

function SwitchTab(tabName)
  -- Deselect all tabs
  for _, tab in pairs(LootSenseList.tabs) do
    PanelTemplates_DeselectTab(tab)
  end

  -- Hide all content frames
  LootSenseList.manageContent:Hide()
  LootSenseList.autoDeleteContent:Hide()
  LootSenseList.settingsContent:Hide()
  if LootSenseList.banksContent then LootSenseList.banksContent:Hide() end
  if LootSenseList.exportImportContent then LootSenseList.exportImportContent:Hide() end

  -- Show the chosen tab and content
  if tabName == "manage" then
    LootSenseList.title:SetText("Manage Lists")
    LootSenseList.manageContent:Show()
    PanelTemplates_SelectTab(LootSenseList.tabs.manage)

  elseif tabName == "autoDelete" then
    LootSenseList.title:SetText("Auto Delete")
    LootSenseList.autoDeleteContent:Show()
    PanelTemplates_SelectTab(LootSenseList.tabs.autoDelete)

  elseif tabName == "settings" then
    LootSenseList.title:SetText("Settings")
    LootSenseList.settingsContent:Show()
    PanelTemplates_SelectTab(LootSenseList.tabs.settings)

  elseif tabName == "banks" then
    LootSenseList.title:SetText("Banks")
    if LootSense_RefreshBanksUI then LootSense_RefreshBanksUI() end
    if LootSense_RefreshCollectionsUI then LootSense_RefreshCollectionsUI() end
    LootSenseList.banksContent:Show()
    PanelTemplates_SelectTab(LootSenseList.tabs.banks)

  elseif tabName == "exportimport" then
    LootSenseList.title:SetText("Export / Import")
    if LootSense_RefreshExportUI then LootSense_RefreshExportUI() end
    LootSenseList.exportImportContent:Show()
    PanelTemplates_SelectTab(LootSenseList.tabs.exportimport)

  else
    LootSenseList.title:SetText("LootSense Lists")
  end
end



-- enkel funktion för tab-storlek
local function ResizeTab(tab)
    local textWidth = tab:GetFontString():GetWidth()
    tab:SetWidth(textWidth + 30)
end

-- skapa tabbar
LootSenseList.tabs.manage = CreateFrame("Button", "LootSenseTabManage", LootSenseList, "CharacterFrameTabButtonTemplate")
LootSenseList.tabs.manage:SetText("Manage Lists")
LootSenseList.tabs.manage.tabName = "LootSenseTabManage"
LootSenseList.tabs.manage:SetID(1)
LootSenseList.tabs.manage:SetPoint("BOTTOMLEFT", LootSenseList, "BOTTOMLEFT", 10, -30)
LootSenseList.tabs.manage:SetScript("OnClick", function() SwitchTab("manage") end)
ResizeTab(LootSenseList.tabs.manage)

LootSenseList.tabs.autoDelete = CreateFrame("Button", "LootSenseTabAutoDelete", LootSenseList, "CharacterFrameTabButtonTemplate")
LootSenseList.tabs.autoDelete:SetText("Auto Delete")
LootSenseList.tabs.autoDelete.tabName = "LootSenseTabAutoDelete"
LootSenseList.tabs.autoDelete:SetID(2)
LootSenseList.tabs.autoDelete:SetPoint("LEFT", LootSenseList.tabs.manage, "RIGHT", -15, 0)
LootSenseList.tabs.autoDelete:SetScript("OnClick", function() SwitchTab("autoDelete") end)
ResizeTab(LootSenseList.tabs.autoDelete)

-- Settings tab
LootSenseList.tabs.settings = CreateFrame("Button", "LootSenseTabSettings", LootSenseList, "CharacterFrameTabButtonTemplate")
LootSenseList.tabs.settings:SetText("Settings")
LootSenseList.tabs.settings.tabName = "LootSenseTabSettings"
LootSenseList.tabs.settings:SetID(3)
LootSenseList.tabs.settings:SetPoint("LEFT", LootSenseList.tabs.autoDelete, "RIGHT", -15, 0)
LootSenseList.tabs.settings:SetScript("OnClick", function() SwitchTab("settings") end)
ResizeTab(LootSenseList.tabs.settings)

-- Banks tab
LootSenseList.tabs.banks = CreateFrame("Button", "LootSenseTabBanks", LootSenseList, "CharacterFrameTabButtonTemplate")
LootSenseList.tabs.banks:SetText("Banks")
LootSenseList.tabs.banks.tabName = "LootSenseTabBanks"
LootSenseList.tabs.banks:SetID(4)
LootSenseList.tabs.banks:SetPoint("LEFT", LootSenseList.tabs.settings, "RIGHT", -15, 0)
LootSenseList.tabs.banks:SetScript("OnClick", function() SwitchTab("banks") end)
ResizeTab(LootSenseList.tabs.banks)

-- Export/Import tab
LootSenseList.tabs.exportimport = CreateFrame("Button", "LootSenseTabExport", LootSenseList, "CharacterFrameTabButtonTemplate")
LootSenseList.tabs.exportimport:SetText("Export/Import")
LootSenseList.tabs.exportimport.tabName = "LootSenseTabExport"
LootSenseList.tabs.exportimport:SetID(5)
LootSenseList.tabs.exportimport:SetPoint("LEFT", LootSenseList.tabs.banks, "RIGHT", -15, 0)
LootSenseList.tabs.exportimport:SetScript("OnClick", function() SwitchTab("exportimport") end)
ResizeTab(LootSenseList.tabs.exportimport)


-- =====================================================
-- Settings-flik
-- =====================================================

LootSenseList.settingsContent = CreateFrame("Frame", nil, LootSenseList)
LootSenseList.settingsContent:SetPoint("TOPLEFT", 10, -40)
LootSenseList.settingsContent:SetPoint("BOTTOMRIGHT", -10, 10)
LootSenseList.settingsContent:Hide()

-- =====================================================
-- Banks-flik
-- =====================================================
LootSenseList.banksContent = CreateFrame("Frame", nil, LootSenseList)
LootSenseList.banksContent:SetPoint("TOPLEFT", 10, -40)
LootSenseList.banksContent:SetPoint("BOTTOMRIGHT", -10, 10)
LootSenseList.banksContent:Hide()

LootSenseList.banksHint = LootSenseList.banksContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
LootSenseList.banksHint:SetPoint("TOPLEFT", 14, -14)
LootSenseList.banksHint:SetText("Add bank alts here. A Bank button will appear in the loot helper.")
LootSenseList.banksHint:SetTextColor(1, 0.82, 0)

LootSenseList.bankNameEdit = CreateFrame("EditBox", nil, LootSenseList.banksContent, "InputBoxTemplate")
LootSenseList.bankNameEdit:SetSize(190, 20)
LootSenseList.bankNameEdit:SetPoint("TOPLEFT", 18, -44)
LootSenseList.bankNameEdit:SetAutoFocus(false)

LootSenseList.addBankBtn = CreateFrame("Button", nil, LootSenseList.banksContent, "UIPanelButtonTemplate")
LootSenseList.addBankBtn:SetSize(70, 22)
LootSenseList.addBankBtn:SetPoint("LEFT", LootSenseList.bankNameEdit, "RIGHT", 10, 0)
LootSenseList.addBankBtn:SetText("Add")
LootSenseList.addBankBtn:SetScript("OnClick", function()
    if LootSense_AddBankName then
        LootSense_AddBankName(LootSenseList.bankNameEdit:GetText() or "")
        LootSenseList.bankNameEdit:SetText("")
        LootSense_RefreshBanksUI()
    end
end)

LootSenseList.bankRows = {}
LootSenseList.banksScroll = CreateFrame("ScrollFrame", "LootSenseBanksScrollFrame", LootSenseList.banksContent, "UIPanelScrollFrameTemplate")
LootSenseList.banksScroll:SetPoint("TOPLEFT", 18, -80)
LootSenseList.banksScroll:SetPoint("BOTTOMRIGHT", -32, 18)
LootSenseList.banksChild = CreateFrame("Frame", "LootSenseBanksScrollChild", LootSenseList.banksScroll)
LootSenseList.banksChild:SetSize(1, 1)
LootSenseList.banksScroll:SetScrollChild(LootSenseList.banksChild)

LootSenseList.bankNameEdit:SetScript("OnEnterPressed", function(self)
    if LootSense_AddBankName then
        LootSense_AddBankName(self:GetText() or "")
        self:SetText("")
        self:ClearFocus()
        LootSense_RefreshBanksUI()
    end
end)

-- =====================================================
-- COLLECTIONS UI – stub (logic now lives in LootSense_RefreshBanksUI)
-- =====================================================
LootSenseList.collectionRows = {}
function LootSense_RefreshCollectionsUI()
    -- no-op: collections are rendered per bank inside LootSense_RefreshBanksUI
end

-- =====================================================
-- EXPORT / IMPORT CONTENT FRAME
-- =====================================================
LootSenseList.exportImportContent = CreateFrame("Frame", nil, LootSenseList)
LootSenseList.exportImportContent:SetPoint("TOPLEFT", 10, -40)
LootSenseList.exportImportContent:SetPoint("BOTTOMRIGHT", -10, 10)
LootSenseList.exportImportContent:Hide()

local eiHint = LootSenseList.exportImportContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
eiHint:SetPoint("TOPLEFT", 10, -10)
eiHint:SetText("|cffffcc00Export|r: copy the text below and paste it on another account.\n|cffffcc00Import|r: paste exported text into the box and click Import.")
eiHint:SetWidth(480)
eiHint:SetJustifyH("LEFT")

-- Export button
local exportBtn = CreateFrame("Button", nil, LootSenseList.exportImportContent, "UIPanelButtonTemplate")
exportBtn:SetSize(100, 22)
exportBtn:SetPoint("TOPLEFT", 10, -52)
exportBtn:SetText("Export")

-- Import button
local importBtn = CreateFrame("Button", nil, LootSenseList.exportImportContent, "UIPanelButtonTemplate")
importBtn:SetSize(100, 22)
importBtn:SetPoint("LEFT", exportBtn, "RIGHT", 8, 0)
importBtn:SetText("Import")

-- Status label
local eiStatus = LootSenseList.exportImportContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
eiStatus:SetPoint("LEFT", importBtn, "RIGHT", 10, 0)
eiStatus:SetWidth(260)
eiStatus:SetJustifyH("LEFT")
eiStatus:SetText("")

-- Text area (EditBox inside a ScrollFrame)
local eiScroll = CreateFrame("ScrollFrame", "LootSenseExportScroll", LootSenseList.exportImportContent, "UIPanelScrollFrameTemplate")
eiScroll:SetPoint("TOPLEFT", 10, -82)
eiScroll:SetPoint("BOTTOMRIGHT", -30, 10)

local eiEdit = CreateFrame("EditBox", "LootSenseExportEdit", eiScroll)
eiEdit:SetMultiLine(true)
eiEdit:SetMaxLetters(0)
eiEdit:SetAutoFocus(false)
eiEdit:SetFontObject(GameFontHighlightSmall)
eiEdit:SetWidth(eiScroll:GetWidth() or 440)
eiEdit:SetHeight(1)
eiEdit:SetText("")
eiScroll:SetScrollChild(eiEdit)

-- Serialise / deserialise helpers
local function LS_SerializeList(list)
    local parts = {}
    for i = 1, #(list or {}) do
        local e = list[i]
        if e and e.id and e.name then
            table.insert(parts, tostring(e.id).."|"..tostring(e.name))
        end
    end
    return table.concat(parts, ";")
end

local function LS_DeserializeList(str)
    local out = {}
    if not str or str == "" then return out end
    for entry in string.gmatch(str, "[^;]+") do
        local id, name = string.match(entry, "^(%d+)|(.+)$")
        if id and name then table.insert(out, { id = tonumber(id), name = name }) end
    end
    return out
end

local function LS_SerializeBankRules(rules)
    local parts = {}
    for k, v in pairs(rules or {}) do
        if v and v.id and v.name and v.bank then
            table.insert(parts, tostring(v.id).."|"..tostring(v.name).."|"..tostring(v.bank))
        end
    end
    return table.concat(parts, ";")
end

local function LS_DeserializeBankRules(str)
    local out = {}
    if not str or str == "" then return out end
    for entry in string.gmatch(str, "[^;]+") do
        local id, name, bank = string.match(entry, "^(%d+)|([^|]+)|(.+)$")
        if id and name and bank then out[tostring(id)] = { id = tonumber(id), name = name, bank = bank } end
    end
    return out
end

local function LS_SerializeBanks(banks)
    return table.concat(banks or {}, ";")
end

local function LS_DeserializeBanks(str)
    local out = {}
    if not str or str == "" then return out end
    for b in string.gmatch(str, "[^;]+") do table.insert(out, b) end
    return out
end

local function LS_SerializeCollections(cols)
    local parts = {}
    for cat, rule in pairs(cols or {}) do
        if rule and rule.bank then table.insert(parts, cat.."|"..rule.bank) end
    end
    return table.concat(parts, ";")
end

local function LS_DeserializeCollections(str)
    local out = {}
    if not str or str == "" then return out end
    for entry in string.gmatch(str, "[^;]+") do
        local cat, bank = string.match(entry, "^([^|]+)|(.+)$")
        if cat and bank then out[cat] = { bank = bank } end
    end
    return out
end

local function LS_BuildExportString()
    local lines = {
        "LSEXPORT:1",
        "keep:"    .. LS_SerializeList(LootSense_keep),
        "vendor:"  .. LS_SerializeList(LootSense_vendor),
        "delete:"  .. LS_SerializeList(LootSense_delete),
        "banks:"   .. LS_SerializeBanks(LootSense_banks),
        "rules:"   .. LS_SerializeBankRules(LootSense_bankRules),
        "cols:"    .. LS_SerializeCollections(LootSense_collections),
    }
    return table.concat(lines, "\n")
end

local function LS_ApplyImportString(str)
    if not str or not string.find(str, "LSEXPORT:1", 1, true) then
        return false, "Not a valid LootSense export string."
    end
    local newKeep, newVendor, newDelete, newBanks, newRules, newCols
    for line in string.gmatch(str, "[^\n]+") do
        local key, val = string.match(line, "^([^:]+):(.*)$")
        if key == "keep"   then newKeep   = LS_DeserializeList(val)
        elseif key == "vendor" then newVendor = LS_DeserializeList(val)
        elseif key == "delete" then newDelete = LS_DeserializeList(val)
        elseif key == "banks"  then newBanks  = LS_DeserializeBanks(val)
        elseif key == "rules"  then newRules  = LS_DeserializeBankRules(val)
        elseif key == "cols"   then newCols   = LS_DeserializeCollections(val)
        end
    end
    if newKeep   then LootSense_keep        = newKeep   end
    if newVendor then LootSense_vendor      = newVendor end
    if newDelete then LootSense_delete      = newDelete end
    if newBanks  then LootSense_banks       = newBanks  end
    if newRules  then LootSense_bankRules   = newRules  end
    if newCols   then LootSense_collections = newCols   end
    return true, "Import successful! Reloading UI..."
end

function LootSense_RefreshExportUI()
    if eiEdit then eiEdit:SetText(LS_BuildExportString()) end
    if eiStatus then eiStatus:SetText("") end
end

exportBtn:SetScript("OnClick", function()
    local txt = LS_BuildExportString()
    eiEdit:SetText(txt)
    eiEdit:SetFocus()
    eiEdit:HighlightText()
    eiStatus:SetText("|cff33ff33Exported! Select all and copy (Ctrl+A, Ctrl+C).|r")
end)

importBtn:SetScript("OnClick", function()
    local txt = eiEdit:GetText() or ""
    local ok, msg = LS_ApplyImportString(txt)
    if ok then
        eiStatus:SetText("|cff33ff33"..msg.."|r")
        RefreshLootSenseList()
        if LootSense_RefreshBanksUI then LootSense_RefreshBanksUI() end
        if LootSense_RefreshCollectionsUI then LootSense_RefreshCollectionsUI() end
    else
        eiStatus:SetText("|cffff3333"..msg.."|r")
    end
end)


-- Pause checkbox
LootSenseList.pauseCheck = CreateFrame("CheckButton", "LootSensePauseCheck", LootSenseList.settingsContent, "UICheckButtonTemplate")
LootSenseList.pauseCheck:SetPoint("TOPLEFT", 20, -50)
LootSenseList.pauseCheck:SetWidth(24)
LootSenseList.pauseCheck:SetHeight(24)
LootSenseList.pauseCheck.text = LootSenseList.pauseCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
LootSenseList.pauseCheck.text:SetPoint("LEFT", LootSenseList.pauseCheck, "RIGHT", 4, 0)
LootSenseList.pauseCheck.text:SetText("Pause LootSense")


-- Klickhändelse
LootSenseList.pauseCheck:SetScript("OnClick", function(self)
	LootSense_paused = self:GetChecked()
	if LootSense_paused then
		DEFAULT_CHAT_FRAME:AddMessage("|cffaaaaaa[LootSense]|r Addon paused")
	else
		DEFAULT_CHAT_FRAME:AddMessage("|cffaaaaaa[LootSense]|r Addon resumed")
	end
end)

local function LootSense_CreateSettingsCheckbox(name, label, anchor, yoff, settingKey, featureName)
    local cb = CreateFrame("CheckButton", name, LootSenseList.settingsContent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, yoff)
    cb:SetWidth(24)
    cb:SetHeight(24)
    cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cb.text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    cb.text:SetText(label)
    cb.settingKey = settingKey
    cb.featureName = featureName
    cb:SetScript("OnClick", function(self)
        LootSense_settings = LootSense_settings or {}
        LootSense_settings[self.settingKey] = self:GetChecked() and true or false
        DEFAULT_CHAT_FRAME:AddMessage("|cffaaaaaa[LootSense]|r "..self.featureName..": " .. (self:GetChecked() and "|cff33ff33ON|r" or "|cffff3333OFF|r"))
        if self.settingKey == "mailEnabled" and not self:GetChecked() and LootSenseBankMailFrame then LootSenseBankMailFrame:Hide() end
        if self.settingKey == "vendorEnabled" and not self:GetChecked() and AutoSell then AutoSell.active = false AutoSell:Hide() end
        if self.settingKey == "autoDeleteEnabled" and not self:GetChecked() and LootSenseCleanBagsFrame then LootSenseCleanBagsFrame:Hide() end
    end)
    return cb
end

LootSenseList.enableAutoDeleteCheck = LootSense_CreateSettingsCheckbox("LootSenseEnableAutoDeleteCheck", "Enable auto delete / Clean Bags", LootSenseList.pauseCheck, -12, "autoDeleteEnabled", "Auto delete")
LootSenseList.enableMailCheck = LootSense_CreateSettingsCheckbox("LootSenseEnableMailCheck", "Enable bank mail frame", LootSenseList.enableAutoDeleteCheck, -8, "mailEnabled", "Bank mail")
LootSenseList.enableVendorCheck = LootSense_CreateSettingsCheckbox("LootSenseEnableVendorCheck", "Enable auto vendor", LootSenseList.enableMailCheck, -8, "vendorEnabled", "Auto vendor")

-- Debug checkbox
LootSenseList.debugCheck = CreateFrame("CheckButton", "LootSenseDebugCheck", LootSenseList.settingsContent, "UICheckButtonTemplate")
LootSenseList.debugCheck:SetPoint("TOPLEFT", LootSenseList.enableVendorCheck, "BOTTOMLEFT", 0, -8)
LootSenseList.debugCheck:SetWidth(24)
LootSenseList.debugCheck:SetHeight(24)
LootSenseList.debugCheck.text = LootSenseList.debugCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
LootSenseList.debugCheck.text:SetPoint("LEFT", LootSenseList.debugCheck, "RIGHT", 4, 0)
LootSenseList.debugCheck.text:SetText("|cff66ccffDebug mode|r (chat spam)")
LootSenseList.debugCheck:SetScript("OnClick", function(self)
    LootSense_debug = self:GetChecked() and true or false
    DEFAULT_CHAT_FRAME:AddMessage("|cffaaaaaa[LootSense]|r Debug mode: " .. (LootSense_debug and "|cff33ff33ON|r" or "|cffff3333OFF|r"))
end)

-- =====================================================
-- AUTO DELETE-FLIKEN
-- =====================================================
LootSenseList.autoDeleteContent = CreateFrame("Frame", nil, LootSenseList)
LootSenseList.autoDeleteContent:SetPoint("TOPLEFT", 10, -40)
LootSenseList.autoDeleteContent:SetPoint("BOTTOMRIGHT", -10, 10)
LootSenseList.autoDeleteContent:Hide()

-- Titel
LootSenseList.autoDeleteTitle = LootSenseList.autoDeleteContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
LootSenseList.autoDeleteTitle:SetPoint("TOP", 0, -15)

-- ===========================
-- Tooltip Helper (Vanilla safe)
-- ===========================
local function AddTooltip(frame, title, text)
  frame:SetScript("OnEnter", function()
    if not GameTooltip then return end
    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
    GameTooltip:SetText(title)
    if text then
      GameTooltip:AddLine(text, 1, 1, 1, 1, true)
    end
    GameTooltip:Show()
  end)

  frame:SetScript("OnLeave", function()
    if GameTooltip then GameTooltip:Hide() end
  end)
end

-- ===========================
-- UI Elements
-- ===========================

-- Gray
LootSenseList.grayCheck = CreateFrame("CheckButton", "LootSenseGrayCheck", LootSenseList.autoDeleteContent, "UICheckButtonTemplate")
LootSenseList.grayCheck:SetPoint("TOPLEFT", 20, -50)
LootSenseList.grayCheck:SetWidth(24)
LootSenseList.grayCheck:SetHeight(24)
LootSenseList.grayCheck.text = LootSenseList.grayCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
LootSenseList.grayCheck.text:SetPoint("LEFT", LootSenseList.grayCheck, "RIGHT", 4, 0)
LootSenseList.grayCheck.text:SetText("Auto add gray items to delete list")
AddTooltip(LootSenseList.grayCheck, "|cff9d9d9dGray items|r", "Automatically adds poor-quality (gray) items to the delete list.")

-- White
LootSenseList.whiteCheck = CreateFrame("CheckButton", "LootSenseWhiteCheck", LootSenseList.autoDeleteContent, "UICheckButtonTemplate")
LootSenseList.whiteCheck:SetPoint("TOPLEFT", LootSenseList.grayCheck, "BOTTOMLEFT", 0, -10)
LootSenseList.whiteCheck:SetWidth(24)
LootSenseList.whiteCheck:SetHeight(24)
LootSenseList.whiteCheck.text = LootSenseList.whiteCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
LootSenseList.whiteCheck.text:SetPoint("LEFT", LootSenseList.whiteCheck, "RIGHT", 4, 0)
LootSenseList.whiteCheck.text:SetText("Auto add white items to delete list")
AddTooltip(LootSenseList.whiteCheck, "|cffffffffWhite items|r", "Automatically adds common-quality (white) items to the delete list.")

-- Green
LootSenseList.greenCheck = CreateFrame("CheckButton", "LootSenseGreenCheck", LootSenseList.autoDeleteContent, "UICheckButtonTemplate")
LootSenseList.greenCheck:SetPoint("TOPLEFT", LootSenseList.whiteCheck, "BOTTOMLEFT", 0, -10)
LootSenseList.greenCheck:SetWidth(24)
LootSenseList.greenCheck:SetHeight(24)
LootSenseList.greenCheck.text = LootSenseList.greenCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
LootSenseList.greenCheck.text:SetPoint("LEFT", LootSenseList.greenCheck, "RIGHT", 4, 0)
LootSenseList.greenCheck.text:SetText("Auto add green items to delete list")
AddTooltip(LootSenseList.greenCheck, "|cff1eff00Green items|r", "Automatically adds uncommon-quality (green) items to the delete list.")

-- Blue
LootSenseList.blueCheck = CreateFrame("CheckButton", "LootSenseBlueCheck", LootSenseList.autoDeleteContent, "UICheckButtonTemplate")
LootSenseList.blueCheck:SetPoint("TOPLEFT", LootSenseList.greenCheck, "BOTTOMLEFT", 0, -10)
LootSenseList.blueCheck:SetWidth(24)
LootSenseList.blueCheck:SetHeight(24)
LootSenseList.blueCheck.text = LootSenseList.blueCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
LootSenseList.blueCheck.text:SetPoint("LEFT", LootSenseList.blueCheck, "RIGHT", 4, 0)
LootSenseList.blueCheck.text:SetText("Auto add blue items to delete list")
AddTooltip(LootSenseList.blueCheck, "|cff0070ddBlue items|r", "Automatically adds rare-quality (blue) items to the delete list.")






local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function()

	if not LootSense_autoDelete then
		LootSense_autoDelete = {
			gray = false,
			white = false,
			green = false,
			blue = false,
		}
	end

	if LootSense_paused == nil then
		LootSense_paused = false
	end

    LootSense_settings = LootSense_settings or {}
    if LootSense_settings.autoDeleteEnabled == nil then LootSense_settings.autoDeleteEnabled = true end
    if LootSense_settings.mailEnabled == nil then LootSense_settings.mailEnabled = true end
    if LootSense_settings.vendorEnabled == nil then LootSense_settings.vendorEnabled = true end

	LootSenseList.grayCheck:SetChecked(LootSense_autoDelete.gray)
	LootSenseList.whiteCheck:SetChecked(LootSense_autoDelete.white)
	LootSenseList.greenCheck:SetChecked(LootSense_autoDelete.green)
	LootSenseList.blueCheck:SetChecked(LootSense_autoDelete.blue)
	LootSenseList.pauseCheck:SetChecked(LootSense_paused)
    if LootSenseList.enableAutoDeleteCheck then LootSenseList.enableAutoDeleteCheck:SetChecked(LootSense_settings.autoDeleteEnabled ~= false) end
    if LootSenseList.enableMailCheck then LootSenseList.enableMailCheck:SetChecked(LootSense_settings.mailEnabled ~= false) end
    if LootSenseList.enableVendorCheck then LootSenseList.enableVendorCheck:SetChecked(LootSense_settings.vendorEnabled ~= false) end
    if LootSenseList.debugCheck then LootSenseList.debugCheck:SetChecked(LootSense_debug == true) end

    LootSense_banks = LootSense_banks or {}
    LootSense_bankRules = LootSense_bankRules or {}
    LootSense_bankPending = LootSense_bankPending or {}
    LootSense_bankOutgoing = LootSense_bankOutgoing or {}
    LootSense_collections = LootSense_collections or {}
    if LootSense_RefreshBanksUI then LootSense_RefreshBanksUI() end
    if LootSense_RefreshCollectionsUI then LootSense_RefreshCollectionsUI() end
    if LootSense_RefreshBankMailFrame then LootSense_RefreshBankMailFrame() end
end)



-- klick-händelser
LootSenseList.grayCheck:SetScript("OnClick", function(self)
    LootSense_autoDelete.gray = self:GetChecked()
    DEFAULT_CHAT_FRAME:AddMessage("|cffaaaaaa[LootSense]|r Auto-delete gray items: " .. (self:GetChecked() and "|cff33ff33ON|r" or "|cffff3333OFF|r"))
end)

LootSenseList.whiteCheck:SetScript("OnClick", function(self)
    LootSense_autoDelete.white = self:GetChecked()
    DEFAULT_CHAT_FRAME:AddMessage("|cffffffff[LootSense]|r Auto-delete white items: " .. (self:GetChecked() and "|cff33ff33ON|r" or "|cffff3333OFF|r"))
end)

LootSenseList.greenCheck:SetScript("OnClick", function(self)
    LootSense_autoDelete.green = self:GetChecked()
    DEFAULT_CHAT_FRAME:AddMessage("|cff55ff55[LootSense]|r Auto-delete green items: " .. (self:GetChecked() and "|cff33ff33ON|r" or "|cffff3333OFF|r"))
end)

LootSenseList.blueCheck:SetScript("OnClick", function(self)
    LootSense_autoDelete.blue = self:GetChecked()
    DEFAULT_CHAT_FRAME:AddMessage("|cff0070dd[LootSense]|r Auto-delete blue items: " .. (self:GetChecked() and "|cff33ff33ON|r" or "|cffff3333OFF|r"))
end)


-- =====================================================
-- MANAGE-FLIKEN
-- =====================================================
LootSenseList.manageContent = CreateFrame("Frame", nil, LootSenseList)
LootSenseList.manageContent:SetPoint("TOPLEFT", 10, -20)
LootSenseList.manageContent:SetPoint("BOTTOMRIGHT", -10, 10)

-- titel
-- titel på huvudframen
LootSenseList.title = LootSenseList:CreateFontString(nil, "OVERLAY", "GameFontNormal")
LootSenseList.title:SetPoint("TOP", LootSenseList, "TOP", 0, -8)
LootSenseList.title:SetText("LootSense Lists")

-- återanvänd Loot Helper's colors-tabell
local qualityColors = colors  
local listItems = {}

local function tableSize(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

local function LootSense_RemoveFromListByID(list, itemID)
    for i = #(list or {}), 1, -1 do
        if list[i] and tonumber(list[i].id) == tonumber(itemID) then table.remove(list, i) end
    end
end

local function LootSense_ListHasID(list, itemID)
    for i = 1, #(list or {}) do
        if list[i] and tonumber(list[i].id) == tonumber(itemID) then return true end
    end
    return false
end

local function LootSense_AddToListOnce(list, itemID, itemName)
    if not list or not itemID then return end
    if not LootSense_ListHasID(list, itemID) then table.insert(list, { id = itemID, name = itemName or "?" }) end
end

local function LootSense_RemoveIDEverywhere(itemID)
    LootSense_RemoveFromListByID(LootSense_keep, itemID)
    LootSense_RemoveFromListByID(LootSense_vendor, itemID)
    LootSense_RemoveFromListByID(LootSense_delete, itemID)
    if LootSense_bankRules then LootSense_bankRules[tostring(itemID)] = nil end
end

function LootSense_SetItemAction(itemID, itemName, action, bankName)
    if not itemID or not action then return end
    LootSense_RemoveIDEverywhere(itemID)
    if action == "keep" then
        LootSense_AddToListOnce(LootSense_keep, itemID, itemName)
    elseif action == "vendor" then
        LootSense_AddToListOnce(LootSense_vendor, itemID, itemName)
    elseif action == "delete" or action == "throw" then
        LootSense_AddToListOnce(LootSense_delete, itemID, itemName)
    elseif action == "bank" and bankName and bankName ~= "" then
        LootSense_bankRules[tostring(itemID)] = { id = itemID, name = itemName or "?", bank = bankName }
        if LootSense_SyncBankPendingFromBags then LootSense_SyncBankPendingFromBags() end
        if LootSense_RefreshBankMailFrame then LootSense_RefreshBankMailFrame() end
    end
    if RefreshLootSenseList then RefreshLootSenseList() end
end

local function LootSense_GetActionLabel(listName, bankName)
    if listName == "Bank" and bankName then return "Bank: "..bankName end
    return listName or "Action"
end

local function LootSense_EstimateTextWidth(text)
    text = tostring(text or "")
    return math.ceil(string.len(text) * 7)
end

local function LootSense_GetActionWidth(label)
    -- All buttons use the same fixed width so the list stays uniform.
    return 120
end

function LootSense_HidePopupCatcher()
    if LootSensePopupCatcher then LootSensePopupCatcher:Hide() end
end

function LootSense_HideActionMenu()
    if LootSenseActionMenu then LootSenseActionMenu:Hide() end
    LootSense_HidePopupCatcher()
end

function LootSense_HideBankChooser()
    if LootSenseBankChooser then LootSenseBankChooser:Hide() end
    LootSense_HidePopupCatcher()
end

function LootSense_ShowPopupCatcher(ownerFrame, onClose)
    if not LootSensePopupCatcher then
        LootSensePopupCatcher = CreateFrame("Button", "LootSensePopupCatcher", UIParent)
        LootSensePopupCatcher:SetAllPoints(UIParent)
        LootSensePopupCatcher:EnableMouse(true)
        LootSensePopupCatcher:SetFrameStrata("DIALOG")
        LootSensePopupCatcher:Hide()
        LootSense_AddSpecialFrame("LootSensePopupCatcher")
    end
    LootSensePopupCatcher.ownerFrame = ownerFrame
    LootSensePopupCatcher.closeFunc = onClose
    LootSensePopupCatcher:SetFrameLevel(math.max((ownerFrame and ownerFrame:GetFrameLevel() or 20) - 1, 1))
    LootSensePopupCatcher:SetScript("OnClick", function(self)
        if self.closeFunc then self.closeFunc() end
        self:Hide()
    end)
    LootSensePopupCatcher:SetScript("OnMouseDown", function(self)
        if self.closeFunc then self.closeFunc() end
        self:Hide()
    end)
    LootSensePopupCatcher:Show()
end

local function LootSense_ShowActionMenu(anchor, itemID, itemName, currentAction)
    if not LootSenseActionMenu then
        LootSenseActionMenu = CreateFrame("Frame", "LootSenseActionMenu", UIParent, "BackdropTemplate")
        LootSenseActionMenu:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16 })
        LootSenseActionMenu:SetBackdropColor(0,0,0,0.94)
        LootSenseActionMenu:SetFrameStrata("DIALOG")
        LootSenseActionMenu:SetFrameLevel(50)
        LootSenseActionMenu:EnableMouse(true)
        LootSenseActionMenu.rows = {}
        LootSense_AddSpecialFrame("LootSenseActionMenu")
        LootSenseActionMenu:SetScript("OnHide", function() LootSense_HidePopupCatcher() end)
    end
    for i = 1, #(LootSenseActionMenu.rows or {}) do LootSenseActionMenu.rows[i]:Hide() end
    local opts = {
        { label = "Keep", action = "keep", icon = LootSense_ActionIcons.keep },
        { label = "Delete", action = "delete", icon = LootSense_ActionIcons.delete },
        { label = "Vendor", action = "vendor", icon = LootSense_ActionIcons.vendor },
    }
    for i = 1, #(LootSense_banks or {}) do
        table.insert(opts, { label = "Bank: "..LootSense_banks[i], action = "bank", bank = LootSense_banks[i], icon = LootSense_ActionIcons.bank })
    end
    if #(LootSense_banks or {}) == 0 then table.insert(opts, { label = "Bank (add bank first)", action = "none", icon = LootSense_ActionIcons.none }) end

    local menuWidth = 178
    for i = 1, #opts do
        menuWidth = math.max(menuWidth, LootSense_GetActionWidth(opts[i].label) + 18)
    end
    menuWidth = LootSense_Clamp(menuWidth, 178, 340)
    LootSenseActionMenu:SetWidth(menuWidth)
    LootSenseActionMenu:SetHeight(10 + (#opts * 24))
    LootSenseActionMenu:ClearAllPoints()
    LootSenseActionMenu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    for i = 1, #opts do
        local opt = opts[i]
        local row = LootSenseActionMenu.rows[i]
        if not row then
            row = CreateFrame("Button", nil, LootSenseActionMenu)
            row:SetSize(menuWidth - 14, 22)
            row:SetPoint("TOPLEFT", 7, -(5 + ((i-1)*24)))
            row.bg = row:CreateTexture(nil, "BACKGROUND")
            row.bg:SetAllPoints(row)
            row.bg:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            row.bg:SetBlendMode("ADD")
            row.bg:SetAlpha(0.25)
            row.bg:Hide()
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(18, 18)
            row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
            row.text:SetJustifyH("LEFT")
            row:SetScript("OnEnter", function(self) if self.bg then self.bg:Show() end end)
            row:SetScript("OnLeave", function(self) if self.bg then self.bg:Hide() end end)
            LootSenseActionMenu.rows[i] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", LootSenseActionMenu, "TOPLEFT", 7, -(5 + ((i-1)*24)))
        row:SetSize(menuWidth - 14, 22)
        row.icon:SetTexture(opt.icon or LootSense_ActionIcons.none)
        row.text:SetText(opt.label)
        row.text:SetWidth(menuWidth - 44)
        row.action = opt.action
        row.bank = opt.bank
        row.itemID = itemID
        row.itemName = itemName
        row:SetScript("OnClick", function(self)
            if self.action == "none" then
                DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[LootSense]|r Add a bank under Banks first.")
                return
            end
            LootSense_SetItemAction(self.itemID, self.itemName, self.action, self.bank)
            LootSense_HideActionMenu()
        end)
        row:Show()
    end
    LootSenseActionMenu:Show()
    LootSense_ShowPopupCatcher(LootSenseActionMenu, LootSense_HideActionMenu)
end

local function LootSense_CreateActionDropdown(parent, itemID, itemName, label)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(120, 20)

    btn.icon = btn:CreateTexture(nil, "OVERLAY")
    btn.icon:SetDrawLayer("OVERLAY", 7)
    btn.icon:SetSize(15, 15)
    btn.icon:SetPoint("LEFT", btn, "LEFT", 5, 0)

    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.text:SetDrawLayer("OVERLAY", 7)
    btn.text:SetPoint("LEFT", btn.icon, "RIGHT", 4, 0)
    btn.text:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
    btn.text:SetJustifyH("LEFT")
    btn.text:SetNonSpaceWrap(false)
    btn:SetText("")

    local actionKey = "none"
    local isBankBtn = false
    local bankName = nil

    if label == "Keep" then
        actionKey = "keep"
    elseif label == "Vendor" then
        actionKey = "vendor"
    elseif label == "Delete" then
        actionKey = "delete"
    elseif label and string.find(label, "Bank", 1, true) then
        actionKey = "bank"
        isBankBtn = true
        bankName = string.match(label, "^Bank: (.+)$") or label
    end

    btn.icon:SetTexture(LootSense_ActionIcons[actionKey] or LootSense_ActionIcons.none)

    if isBankBtn and bankName then
        btn.text:SetText(bankName)
        btn.bankTooltip = "Bank: " .. bankName
    else
        btn.text:SetText(label or "Action")
        btn.bankTooltip = nil
    end

    btn.dynamicWidth = 120

    btn:SetScript("OnEnter", function(self)
        if self.bankTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.bankTooltip, 0.4, 0.85, 1)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    btn:SetScript("OnClick", function(self)
        if LootSenseActionMenu and LootSenseActionMenu:IsShown() then LootSenseActionMenu:Hide() return end
        LootSense_ShowActionMenu(self, itemID, itemName, label)
    end)
    return btn
end
-- =====================================================
-- REFRESH LIST-FUNKTION
-- =====================================================
LootSenseList.sortOrder = "none"  -- "none" | "az" | "za" | "category"

-- Maps itemType strings returned by GetItemInfo to a display category bucket
local LootSense_SortCategories = {
    ["trade goods"] = "Trade Goods",
    ["recipe"]      = "Recipes",
    ["tradeskill"]  = "Recipes",
    ["consumable"]  = "Consumable",
    ["weapon"]      = "Weapon",
    ["armor"]       = "Armor",
    ["container"]   = "Container",
    ["projectile"]  = "Projectile",
    ["quiver"]      = "Quiver",
    ["quest"]       = "Quest",
    ["key"]         = "Key",
    ["misc"]        = "Miscellaneous",
    ["miscellaneous"] = "Miscellaneous",
}

local function LootSense_GetSortCategoryLabel(itemID)
    if not itemID then return "zzz_Unknown" end
    local _, _, _, _, _, itemType, itemSubType = GetItemInfo(itemID)
    if not itemType then return "zzz_Unknown" end
    local lType = string.lower(itemType)
    -- Enchanting mats / recipes get finer labels
    if lType == "trade goods" then
        local lSub = string.lower(itemSubType or "")
        if string.find(lSub, "enchant", 1, true) then return "Enchanting" end
        if string.find(lSub, "herb",    1, true) then return "Herbs" end
        if string.find(lSub, "cloth",   1, true) then return "Cloth" end
        if string.find(lSub, "leather", 1, true) then return "Leather" end
        if string.find(lSub, "metal",   1, true) then return "Metal" end
        if string.find(lSub, "gem",     1, true) then return "Gems" end
        if string.find(lSub, "jewel",   1, true) then return "Gems" end
        return "Trade Goods"
    end
    if lType == "recipe" or lType == "tradeskill" then return "Recipes" end
    return LootSense_SortCategories[lType] or itemType or "zzz_Unknown"
end

function RefreshLootSenseList()
    LootSense_HideActionMenu()
    local searchText = string.lower(LootSenseList.search:GetText() or "")

    -- rensa gamla frames
    for i,v in pairs(listItems) do
        if v.frame then v.frame:Hide() v.frame:SetParent(nil) end
    end
    listItems = {}

    local itemHeight = 28
    local spacing = 3
    local width = LootSenseList.scroll:GetWidth() - 20
    local index = 1

    local function sortedCopy(list)
        local copy = {}
        for i = 1, #list do copy[i] = list[i] end
        if LootSenseList.sortOrder == "az" then
            table.sort(copy, function(a, b) return string.lower(a.name or "") < string.lower(b.name or "") end)
        elseif LootSenseList.sortOrder == "za" then
            table.sort(copy, function(a, b) return string.lower(a.name or "") > string.lower(b.name or "") end)
        elseif LootSenseList.sortOrder == "category" then
            table.sort(copy, function(a, b)
                local catA = LootSense_GetSortCategoryLabel(a.id)
                local catB = LootSense_GetSortCategoryLabel(b.id)
                if catA ~= catB then return catA < catB end
                return string.lower(a.name or "") < string.lower(b.name or "")
            end)
        end
        return copy
    end

    local function addSection(list, listName)
        local sorted = sortedCopy(list)
        local lastCatHeader = nil
        for i = 1, #sorted do
            local entry = sorted[i]
            local itemID = entry.id
            local itemName = entry.name

            local _, _, itemRarity = GetItemInfo(itemID)
            local icon = LootSense_GetItemIcon(itemID)

            if searchText == "" or string.find(string.lower(itemName or ""), searchText) then
                -- Category header row when sorting by category
                if LootSenseList.sortOrder == "category" then
                    local cat = LootSense_GetSortCategoryLabel(itemID)
                    if cat ~= lastCatHeader then
                        lastCatHeader = cat
                        local hdr = CreateFrame("Frame", nil, LootSenseList.child)
                        hdr:SetWidth(width)
                        hdr:SetHeight(16)
                        hdr:SetPoint("TOPLEFT", 0, -((index-1)*(itemHeight+spacing)))
                        hdr.bg = hdr:CreateTexture(nil, "BACKGROUND")
                        hdr.bg:SetAllPoints(hdr)
                        hdr.bg:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
                        hdr.bg:SetBlendMode("ADD")
                        hdr.bg:SetAlpha(0.15)
                        hdr.text = hdr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                        hdr.text:SetPoint("LEFT", hdr, "LEFT", 5, 0)
                        hdr.text:SetText("|cffffcc00"..cat.."|r")
                        listItems[index] = { frame = hdr }
                        index = index + 1
                    end
                end
                local frame = CreateFrame("Frame", nil, LootSenseList.child)
                frame:SetWidth(width)
                frame:SetHeight(itemHeight)
                frame:SetPoint("TOPLEFT", 0, -((index-1)*(itemHeight+spacing)))

                frame.icon = frame:CreateTexture(nil, "OVERLAY")
                frame.icon:SetWidth(22)
                frame.icon:SetHeight(22)
                frame.icon:SetPoint("LEFT", frame, "LEFT", 5, 0)
                frame.icon:SetTexture(icon)

                frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                frame.text:SetPoint("LEFT", frame.icon, "RIGHT", 5, 0)
                frame.text:SetWidth(170)
                frame.text:SetJustifyH("LEFT")
                frame.text:SetText(itemName)
                LootSense_ApplyQualityColor(frame.text, itemRarity)



                frame.actionDrop = LootSense_CreateActionDropdown(frame, itemID, itemName, listName)
                frame.actionDrop:SetPoint("RIGHT", frame, "RIGHT", -31, 0)
                frame.actionDrop:SetWidth(120)
                frame.actionDrop.dynamicWidth = 120
                frame.text:SetWidth(math.max(45, width - 120 - 70))

                frame.remove = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
                frame.remove:SetWidth(20)
                frame.remove:SetHeight(20)
                frame.remove:SetText("X")
                frame.remove:SetPoint("RIGHT", frame, "RIGHT", -5, 0)
                frame.remove:SetScript("OnClick", function(self)
                    for j = 1, table.getn(list) do
                        if list[j].id == itemID then
                            table.remove(list, j)
                            RefreshLootSenseList()
                            break
                        end
                    end
                end)

                listItems[index] = { frame = frame }
                index = index + 1
            end
        end
    end

    local function addBankSection()
        for key, entry in pairs(LootSense_bankRules or {}) do
            local itemID = entry and (entry.id or tonumber(key))
            local itemName = entry and entry.name
            local bankName = entry and entry.bank
            if itemID and bankName and LootSense_BankExists and LootSense_BankExists(bankName) then
                if not itemName or itemName == "" or itemName == "?" then
                    itemName = GetItemInfo(itemID) or "Item ID " .. tostring(itemID)
                end
                local _, _, itemRarity = GetItemInfo(itemID)
                local icon = LootSense_GetItemIcon(itemID)
                if searchText == "" or string.find(string.lower(itemName or ""), searchText) or string.find(string.lower(bankName or ""), searchText) then
                    local frame = CreateFrame("Frame", nil, LootSenseList.child)
                    frame:SetWidth(width)
                    frame:SetHeight(itemHeight)
                    frame:SetPoint("TOPLEFT", 0, -((index-1)*(itemHeight+spacing)))
                    frame.icon = frame:CreateTexture(nil, "OVERLAY")
                    frame.icon:SetSize(22, 22)
                    frame.icon:SetPoint("LEFT", frame, "LEFT", 5, 0)
                    frame.icon:SetTexture(icon)
                    frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    frame.text:SetPoint("LEFT", frame.icon, "RIGHT", 5, 0)
                    frame.text:SetWidth(170)
                    frame.text:SetJustifyH("LEFT")
                    frame.text:SetText(itemName)
                    LootSense_ApplyQualityColor(frame.text, itemRarity)
                    frame.listType = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")

                    frame.listType:SetTextColor(0.4, 0.85, 1)
                    frame.actionDrop = LootSense_CreateActionDropdown(frame, itemID, itemName, "Bank: "..bankName)
                    frame.actionDrop:SetPoint("RIGHT", frame, "RIGHT", -31, 0)
                    frame.actionDrop:SetWidth(120)
                    frame.actionDrop.dynamicWidth = 120
                    frame.text:SetWidth(math.max(45, width - 120 - 70))
                    frame.remove = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
                    frame.remove:SetSize(20, 20)
                    frame.remove:SetText("X")
                    frame.remove:SetPoint("RIGHT", frame, "RIGHT", -5, 0)
                    frame.remove:SetScript("OnClick", function()
                        LootSense_bankRules[tostring(itemID)] = nil
                        if LootSense_SyncBankPendingFromBags then LootSense_SyncBankPendingFromBags() end
                        RefreshLootSenseList()
                        if LootSense_RefreshBankMailFrame then LootSense_RefreshBankMailFrame() end
                    end)
                    listItems[index] = { frame = frame }
                    index = index + 1
                end
            end
        end
    end

    -- Lägg till sektioner beroende på filter
    if LootSenseList.filter == "all" or LootSenseList.filter == "keep" then
        addSection(LootSense_keep, "Keep")
    end
    if LootSenseList.filter == "all" or LootSenseList.filter == "vendor" then
        addSection(LootSense_vendor, "Vendor")
    end
    if LootSenseList.filter == "all" or LootSenseList.filter == "delete" then
        addSection(LootSense_delete, "Delete")
    end
    if LootSenseList.filter == "all" or LootSenseList.filter == "bank" then
        addBankSection()
    end

    -- justera scroll child
    local totalHeight = index * (itemHeight + spacing)
    local visibleHeight = LootSenseList.scroll:GetHeight()
    LootSenseList.child:SetHeight(math.max(totalHeight, visibleHeight + 1))
    LootSenseList.scroll:UpdateScrollChildRect()
    LootSenseList.scroll:SetVerticalScroll(0)
end

-- =====================================================
-- FILTERKNAPPAR FÖR MANAGE-FLIKEN
-- =====================================================
local buttonWidth = 65
local buttonHeight = 20
local spacing = 5
local xOffset = 10
local yOffset = -35

local function createFilterButton(parent, label, filter)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetWidth(buttonWidth)
    btn:SetHeight(buttonHeight)
    btn:SetText(label)
    btn:SetPoint("TOPLEFT", xOffset, yOffset)
    xOffset = xOffset + buttonWidth + spacing

    btn:SetScript("OnClick", function(self)
        LootSenseList.filter = filter
        RefreshLootSenseList()
    end)
    return btn
end

createFilterButton(LootSenseList.manageContent, "Keep", "keep")
createFilterButton(LootSenseList.manageContent, "Vendor", "vendor")
createFilterButton(LootSenseList.manageContent, "Delete", "delete")
createFilterButton(LootSenseList.manageContent, "Bank", "bank")
createFilterButton(LootSenseList.manageContent, "All", "all")

-- Sort-knapp
LootSenseList.sortBtn = CreateFrame("Button", nil, LootSenseList.manageContent, "UIPanelButtonTemplate")
LootSenseList.sortBtn:SetWidth(90)
LootSenseList.sortBtn:SetHeight(buttonHeight)
LootSenseList.sortBtn:SetPoint("TOPLEFT", xOffset, yOffset)
LootSenseList.sortBtn:SetText("Sort A-Z")
LootSenseList.sortBtn:SetScript("OnClick", function(self)
    if LootSenseList.sortOrder == "none" or LootSenseList.sortOrder == "za" then
        LootSenseList.sortOrder = "az"
        self:SetText("Sort Z-A")
    elseif LootSenseList.sortOrder == "az" then
        LootSenseList.sortOrder = "category"
        self:SetText("Sort Cat.")
    else
        LootSenseList.sortOrder = "none"
        self:SetText("Sort A-Z")
    end
    RefreshLootSenseList()
end)
LootSenseList.sortBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Sort the list")
    GameTooltip:AddLine("Click to cycle: A-Z  \226\128\186  Z-A  \226\128\186  Category  \226\128\186  Default", 1, 1, 1)
    GameTooltip:Show()
end)
LootSenseList.sortBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- =====================================================
-- SÖKFÄLT FÖR MANAGE-FLIKEN
-- =====================================================
LootSenseList.search = CreateFrame("EditBox", nil, LootSenseList.manageContent)
LootSenseList.search:SetPoint("TOPLEFT", 10, -10)
LootSenseList.search:SetWidth(480)
LootSenseList.search:SetHeight(20)
LootSenseList.search:SetFontObject(GameFontHighlight)
LootSenseList.search:SetAutoFocus(false)
LootSenseList.search:SetText("")

LootSenseList.search.bg = LootSenseList.search:CreateTexture(nil, "BACKGROUND")
LootSenseList.search.bg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
LootSenseList.search.bg:SetVertexColor(0,0,0,0.5)
LootSenseList.search.bg:SetAllPoints(LootSenseList.search)

LootSenseList.search.placeholder = LootSenseList.search:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
LootSenseList.search.placeholder:SetPoint("LEFT", 5, 0)
LootSenseList.search.placeholder:SetText("Search...")
LootSenseList.search.placeholder:SetTextColor(0.7,0.7,0.7,1)

LootSenseList.search:SetScript("OnEnterPressed", function(self) LootSenseList.search:ClearFocus() end)
LootSenseList.search:SetScript("OnTextChanged", function(self)
    if LootSenseList.search:GetText() == "" then
        LootSenseList.search.placeholder:Show()
    else
        LootSenseList.search.placeholder:Hide()
    end
    RefreshLootSenseList()
end)

-- =====================================================
-- SCROLL FRAME FÖR MANAGE-FLIKEN
-- =====================================================
LootSenseList.scroll = CreateFrame("ScrollFrame", "LootSenseScrollFrame", LootSenseList.manageContent, "UIPanelScrollFrameTemplate")
LootSenseList.scroll:SetPoint("TOPLEFT", 10, -65)
LootSenseList.scroll:SetPoint("BOTTOMRIGHT", -30, 10)

LootSenseList.child = CreateFrame("Frame", "LootSenseScrollChild", LootSenseList.scroll)
LootSenseList.child:SetWidth(1)
LootSenseList.child:SetHeight(1)
LootSenseList.scroll:SetScrollChild(LootSenseList.child)

-- =====================================================
-- INITIERING
-- =====================================================
LootSenseList.filter = "all"
SwitchTab("manage")
RefreshLootSenseList()


-- ##################################################
-- ## HELPER FUNCTIONS
-- ##################################################
local function tContains(tbl, item)
    if not tbl then return false end
    for _, v in pairs(tbl) do
        if v == item then return true end
    end
    return false
end

local function AddTooltip(button, text)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:SetText(text)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
end

-- ##################################################
-- ## LOOT BUTTON ACTION
-- ##################################################
local lootButtons = {}  -- global table for loot frames

local function ClearLootButtons()
    for slot, frame in pairs(lootButtons) do
        if frame then frame:Hide() frame:SetParent(nil) end
        lootButtons[slot] = nil
    end
end

-- ##################################################
-- ## BANK SYSTEM HELPERS + MAIL ATTACH (WoW 1.14)
-- ##################################################
local function LootSense_TrimText(txt)
    txt = txt or ""
    txt = string.gsub(txt, "^%s+", "")
    txt = string.gsub(txt, "%s+$", "")
    return txt
end

local function LootSense_Lower(txt)
    return string.lower(txt or "")
end

function LootSense_HasBanks()
    return LootSense_banks and #LootSense_banks > 0
end

function LootSense_BankExists(name)
    local low = LootSense_Lower(name)
    for i = 1, #(LootSense_banks or {}) do
        if LootSense_Lower(LootSense_banks[i]) == low then return true end
    end
    return false
end

function LootSense_AddBankName(name)
    name = LootSense_TrimText(name)
    if name == "" then return end
    if LootSense_BankExists(name) then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ffcc[LootSense]|r Bank already exists: "..name)
        return
    end
    table.insert(LootSense_banks, name)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffcc[LootSense]|r Added bank: "..name)
end

function LootSense_RemoveBankName(name)
    for i = #(LootSense_banks or {}), 1, -1 do
        if LootSense_Lower(LootSense_banks[i]) == LootSense_Lower(name) then
            table.remove(LootSense_banks, i)
        end
    end
    for k, v in pairs(LootSense_bankRules or {}) do
        if v and LootSense_Lower(v.bank) == LootSense_Lower(name) then LootSense_bankRules[k] = nil end
    end
    if LootSense_bankPending then LootSense_bankPending[name] = nil end
    if LootSense_bankOutgoing then LootSense_bankOutgoing[name] = nil end
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffcc[LootSense]|r Removed bank: "..name)
end

-- Shared dropdown menu for collection category assignment.
-- Shows a list of categories; clicking one toggles assignment to the active bank.
local LS_ColDropMenu = nil

local function LS_HideColDropMenu()
    if LS_ColDropMenu then LS_ColDropMenu:Hide() end
    if LootSensePopupCatcher then LootSensePopupCatcher:Hide() end
end

local function LS_ShowColDropMenu(anchor, bankName, refreshFunc)
    if not LS_ColDropMenu then
        LS_ColDropMenu = CreateFrame("Frame", "LootSenseColDropMenu", UIParent, "BackdropTemplate")
        LS_ColDropMenu:SetBackdrop({
            bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
        })
        LS_ColDropMenu:SetBackdropColor(0, 0, 0, 0.94)
        LS_ColDropMenu:SetFrameStrata("DIALOG")
        LS_ColDropMenu:SetFrameLevel(55)
        LS_ColDropMenu:EnableMouse(true)
        LS_ColDropMenu.rows = {}
        LootSense_AddSpecialFrame("LootSenseColDropMenu")
        LS_ColDropMenu:SetScript("OnHide", function()
            if LootSensePopupCatcher then LootSensePopupCatcher:Hide() end
        end)
    end

    -- Hide old rows
    for i = 1, #(LS_ColDropMenu.rows or {}) do LS_ColDropMenu.rows[i]:Hide() end

    local catCount  = #LootSense_CategoryOrder
    local menuW     = 210
    local rowH      = 22
    LS_ColDropMenu:SetSize(menuW, 10 + catCount * rowH)
    LS_ColDropMenu:ClearAllPoints()
    LS_ColDropMenu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)

    for i, catKey in ipairs(LootSense_CategoryOrder) do
        local row = LS_ColDropMenu.rows[i]
        if not row then
            row = CreateFrame("Button", nil, LS_ColDropMenu)
            row:SetSize(menuW - 14, rowH)
            row:SetPoint("TOPLEFT", LS_ColDropMenu, "TOPLEFT", 7, -(5 + (i - 1) * rowH))
            row.bg = row:CreateTexture(nil, "BACKGROUND")
            row.bg:SetAllPoints(row)
            row.bg:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            row.bg:SetBlendMode("ADD")
            row.bg:SetAlpha(0.25)
            row.bg:Hide()
            row.check = row:CreateTexture(nil, "OVERLAY")
            row.check:SetSize(14, 14)
            row.check:SetPoint("LEFT", row, "LEFT", 2, 0)
            row.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.text:SetPoint("LEFT", row, "LEFT", 20, 0)
            row.text:SetJustifyH("LEFT")
            row.text:SetWidth(menuW - 38)
            row:SetScript("OnEnter", function(self) self.bg:Show() end)
            row:SetScript("OnLeave", function(self) self.bg:Hide() end)
            LS_ColDropMenu.rows[i] = row
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", LS_ColDropMenu, "TOPLEFT", 7, -(5 + (i - 1) * rowH))
        row:SetSize(menuW - 14, rowH)

        local assigned = LootSense_collections[catKey]
        local isThisBank = assigned and string.lower(assigned.bank or "") == string.lower(bankName)

        row.text:SetText(LootSense_CategoryLabels[catKey] or catKey)
        if isThisBank then
            row.check:Show()
            row.text:SetTextColor(0.2, 1, 0.6)
        else
            row.check:Hide()
            if assigned then
                row.text:SetTextColor(0.55, 0.55, 0.55)  -- assigned to another bank
            else
                row.text:SetTextColor(1, 1, 1)
            end
        end

        row.catKey   = catKey
        row.bankName = bankName
        row:SetScript("OnClick", function(self)
            local cur = LootSense_collections[self.catKey]
            if cur and string.lower(cur.bank or "") == string.lower(self.bankName) then
                -- Already assigned here → unassign
                LootSense_collections[self.catKey] = nil
            else
                -- Assign (overwrites any previous bank)
                LootSense_collections[self.catKey] = { bank = self.bankName }
            end
            LS_HideColDropMenu()
            if refreshFunc then refreshFunc() end
        end)
        row:Show()
    end

    LS_ColDropMenu:Show()
    LootSense_ShowPopupCatcher(LS_ColDropMenu, LS_HideColDropMenu)
end

-- Build a short summary string of categories assigned to a bank, e.g. "Cloth, Herbs"
local function LS_BankCatSummary(bankName)
    local parts = {}
    for _, catKey in ipairs(LootSense_CategoryOrder) do
        local rule = LootSense_collections[catKey]
        if rule and string.lower(rule.bank or "") == string.lower(bankName) then
            table.insert(parts, LootSense_CategoryLabels[catKey] or catKey)
        end
    end
    if #parts == 0 then return "|cff888888-- none --|r" end
    return table.concat(parts, ", ")
end

function LootSense_RefreshBanksUI()
    if not LootSenseList or not LootSenseList.banksChild then return end

    for i = 1, #(LootSenseList.bankRows or {}) do
        local r = LootSenseList.bankRows[i]
        if r then r:Hide() r:SetParent(nil) end
    end
    LootSenseList.bankRows = {}

    local bankCount = #(LootSense_banks or {})

    if bankCount == 0 then
        local row = CreateFrame("Frame", nil, LootSenseList.banksChild)
        row:SetSize(400, 24)
        row:SetPoint("TOPLEFT", 0, 0)
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.text:SetPoint("LEFT", 4, 0)
        row.text:SetText("No banks added yet.")
        LootSenseList.bankRows[1] = row
        LootSenseList.banksChild:SetHeight(60)
        LootSenseList.banksScroll:UpdateScrollChildRect()
        return
    end

    -- Each bank block: header row (28px) + summary row (18px) + category dropdown btn (22px) + gap (8px)
    local blockH   = 28 + 18 + 22 + 8
    local childW   = 400
    local yOffset  = 0

    for bi = 1, bankCount do
        local bankName = LootSense_banks[bi]

        local block = CreateFrame("Frame", nil, LootSenseList.banksChild)
        block:SetSize(childW, blockH)
        block:SetPoint("TOPLEFT", 0, -yOffset)

        -- Separator line between banks
        if bi > 1 then
            local sep = block:CreateTexture(nil, "BACKGROUND")
            sep:SetSize(childW - 8, 1)
            sep:SetPoint("TOPLEFT", block, "TOPLEFT", 4, 0)
            sep:SetTexture(1, 1, 1, 0.12)
        end

        -- Bank name
        local nameLabel = block:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameLabel:SetPoint("TOPLEFT", block, "TOPLEFT", 6, -6)
        nameLabel:SetText("|cff33ffcc"..bankName.."|r")

        -- Remove bank button
        local delBtn = CreateFrame("Button", nil, block, "UIPanelButtonTemplate")
        delBtn:SetSize(22, 20)
        delBtn:SetText("X")
        delBtn:SetPoint("TOPRIGHT", block, "TOPRIGHT", -4, -4)
        delBtn.bankName = bankName
        delBtn:SetScript("OnClick", function(self)
            -- Clear any collection rules pointing to this bank
            for catKey, rule in pairs(LootSense_collections or {}) do
                if rule and string.lower(rule.bank or "") == string.lower(self.bankName) then
                    LootSense_collections[catKey] = nil
                end
            end
            LootSense_RemoveBankName(self.bankName)
            LS_HideColDropMenu()
            LootSense_RefreshBanksUI()
            if LootSense_RefreshBankMailFrame then LootSense_RefreshBankMailFrame() end
        end)
        delBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Remove bank: "..self.bankName, 1, 0.4, 0.4)
            GameTooltip:Show()
        end)
        delBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- Summary label showing assigned categories
        local summaryLabel = block:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        summaryLabel:SetPoint("TOPLEFT", block, "TOPLEFT", 6, -26)
        summaryLabel:SetWidth(childW - 40)
        summaryLabel:SetJustifyH("LEFT")
        summaryLabel:SetText(LS_BankCatSummary(bankName))
        block.summaryLabel = summaryLabel
        block.bankName     = bankName

        -- "Categories ▾" dropdown button
        local ddBtn = CreateFrame("Button", nil, block, "UIPanelButtonTemplate")
        ddBtn:SetSize(140, 20)
        ddBtn:SetPoint("TOPLEFT", block, "TOPLEFT", 6, -46)
        ddBtn:SetText("Categories \226\150\190")   -- ▾
        ddBtn.bankName = bankName
        ddBtn:SetScript("OnClick", function(self)
            if LS_ColDropMenu and LS_ColDropMenu:IsShown() and LS_ColDropMenu.activeBankName == self.bankName then
                LS_HideColDropMenu()
            else
                LS_ColDropMenu = LS_ColDropMenu  -- ensure created
                if LS_ColDropMenu then LS_ColDropMenu.activeBankName = self.bankName end
                LS_ShowColDropMenu(self, self.bankName, LootSense_RefreshBanksUI)
                if LS_ColDropMenu then LS_ColDropMenu.activeBankName = self.bankName end
            end
        end)
        ddBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Assign item categories to "..self.bankName, 1,1,1)
            GameTooltip:AddLine("Items in assigned categories will be auto-banked here.", 1,1,1,true)
            GameTooltip:Show()
        end)
        ddBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        LootSenseList.bankRows[bi] = block
        yOffset = yOffset + blockH
    end

    local totalH = math.max(yOffset + 4, LootSenseList.banksScroll:GetHeight() + 1)
    LootSenseList.banksChild:SetHeight(totalH)
    LootSenseList.banksScroll:UpdateScrollChildRect()
end

function LootSense_AddBankRule(itemID, itemName, bankName)
    if not itemID or not bankName or bankName == "" then return end
    LootSense_bankRules[tostring(itemID)] = { id = itemID, name = itemName or "?", bank = bankName }
    LootSense_RemoveFromListByID(LootSense_keep, itemID)
    LootSense_RemoveFromListByID(LootSense_vendor, itemID)
    LootSense_RemoveFromListByID(LootSense_delete, itemID)
    if RefreshLootSenseList then RefreshLootSenseList() end
end

function LootSense_GetBankRule(itemID)
    if not itemID then return nil end
    local rule = LootSense_bankRules and LootSense_bankRules[tostring(itemID)]
    if rule and rule.bank and LootSense_BankExists(rule.bank) then return rule end
    return nil
end

function LootSense_ExtractItemID(link)
    if not link then return nil end
    local id = link:match("item:(%d+):")
    return id and tonumber(id) or nil
end

local function LootSense_AddCountToPendingTable(tbl, bankName, itemID, itemName, count)
    if not tbl or not bankName or bankName == "" or not itemID then return end
    count = tonumber(count) or 1
    if count < 1 then count = 1 end
    tbl[bankName] = tbl[bankName] or {}
    local list = tbl[bankName]
    for i = 1, #list do
        if list[i] and list[i].id == itemID then
            list[i].count = (tonumber(list[i].count) or 0) + count
            list[i].name = itemName or list[i].name or "?"
            return
        end
    end
    table.insert(list, { id = itemID, name = itemName or "?", count = count })
end

function LootSense_SyncBankPendingFromBags()
    local rebuilt = {}
    for bag = 0, 4 do
        local slots = LootSense_GetContainerSlots and LootSense_GetContainerSlots(bag) or GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local link = LootSense_GetContainerLink and LootSense_GetContainerLink(bag, slot) or GetContainerItemLink(bag, slot)
            local itemID = LootSense_ExtractItemID(link)
            local rule = itemID and LootSense_GetBankRule(itemID)
            if rule and rule.bank then
                local texture, itemCount = LootSense_GetContainerInfo and LootSense_GetContainerInfo(bag, slot) or GetContainerItemInfo(bag, slot)
                LootSense_Debug("SyncBankPending: bag="..bag.." slot="..slot.." itemID="..tostring(itemID).." count="..tostring(itemCount))
                LootSense_AddCountToPendingTable(rebuilt, rule.bank, itemID, rule.name or GetItemInfo(itemID) or "?", itemCount or 1)
            end
        end
    end
    -- Do not add LootSense_bankOutgoing here. Attached mail items can still be visible
    -- during BAG_UPDATE in 1.14, and adding outgoing again made the bank row count
    -- climb when clicking the same bank twice. A fresh bag scan is the source of truth.
    LootSense_bankPending = rebuilt
end

function LootSense_AddBankPending(bankName, itemID, itemName, count)
    if not bankName or bankName == "" or not itemID then return end
    LootSense_AddCountToPendingTable(LootSense_bankPending, bankName, itemID, itemName, count)
    if LootSense_RefreshBankMailFrame then LootSense_RefreshBankMailFrame() end
end

local function LootSense_GetBankPendingCount(bankName)
    local total = 0
    local list = LootSense_bankPending and LootSense_bankPending[bankName]
    for i = 1, #(list or {}) do total = total + (tonumber(list[i] and list[i].count) or 0) end
    return total
end

local function LootSense_IsCTMailVisible()
    local ctFrames = { "CT_MailFrame", "CTMailFrame", "CT_MailModFrame", "CT_MailModSendFrame", "CT_MailModFrame_Send", "CT_MailMod_SendFrame", "CT_MMFrame", "CT_MailFrame_MassMailFrame" }
    for i = 1, #ctFrames do
        local frame = _G[ctFrames[i]]
        if frame and frame.IsVisible and frame:IsVisible() then return true end
    end
    return false
end

local function LootSense_SetEditBoxText(box, text)
    if not box or not box.SetText then return false end
    box:SetText(text or "")
    if box.ClearFocus then box:ClearFocus() end
    return true
end

local function LootSense_FindCTEditBox(kind)
    local wanted = string.lower(kind or "")
    local candidates
    if wanted == "name" then
        candidates = { "CT_MailFrameNameEditBox", "CTMailFrameNameEditBox", "CT_MailNameEditBox", "CT_MailModNameEditBox", "CT_MailModSendNameEditBox", "CT_MailModFrameNameEditBox", "CT_MailFrameRecipientEditBox", "CTMailRecipientEditBox", "CT_MailRecipientEditBox", "MassMailNameEditBox", "CT_MassMailNameEditBox", "CT_MailFrame_MassMailNameEditBox" }
    elseif wanted == "subject" then
        candidates = { "CT_MailFrameSubjectEditBox", "CTMailFrameSubjectEditBox", "CT_MailSubjectEditBox", "CT_MailModSubjectEditBox", "CT_MailModSendSubjectEditBox", "CT_MailModFrameSubjectEditBox", "MassMailSubjectEditBox", "CT_MassMailSubjectEditBox", "CT_MailFrame_MassMailSubjectEditBox" }
    else
        candidates = { "CT_MailFrameBodyEditBox", "CTMailFrameBodyEditBox", "CT_MailBodyEditBox", "CT_MailModBodyEditBox", "CT_MailModSendBodyEditBox", "CT_MailModFrameBodyEditBox", "MassMailBodyEditBox", "CT_MassMailBodyEditBox", "CT_MailFrame_MassMailBodyEditBox" }
    end
    for i = 1, #candidates do if _G[candidates[i]] and _G[candidates[i]].SetText then return _G[candidates[i]] end end
    for k, v in pairs(_G) do
        if type(k) == "string" and type(v) == "table" and v.SetText and v.GetText then
            local low = string.lower(k)
            if string.find(low, "ct") and string.find(low, "mail") then
                if wanted == "name" and (string.find(low, "name") or string.find(low, "recipient") or string.find(low, "to")) then return v end
                if wanted == "subject" and string.find(low, "subject") then return v end
                if wanted == "body" and (string.find(low, "body") or string.find(low, "message")) then return v end
            end
        end
    end
    return nil
end

local function LootSense_SwitchToSendMailTab()
    -- Switch the mailbox to the Send Mail tab so the player can immediately press Send.
    -- Try vanilla tab click first, then fall back to PanelTemplates.
    if MailFrameTab2 and MailFrameTab2.Click then
        MailFrameTab2:Click()
    elseif SendMailFrame and not SendMailFrame:IsVisible() then
        if PanelTemplates_SelectTab and MailFrame then PanelTemplates_SelectTab(MailFrameTab2) end
        if SendMailFrame then SendMailFrame:Show() end
        if InboxFrame then InboxFrame:Hide() end
    end
end

local function LootSense_SetMailFields(name, subject, body)
    if LootSense_IsCTMailVisible() then
        local nameBox = LootSense_FindCTEditBox("name")
        local subjectBox = LootSense_FindCTEditBox("subject")
        local bodyBox = LootSense_FindCTEditBox("body")
        if LootSense_SetEditBoxText(nameBox, name) then
            LootSense_SetEditBoxText(subjectBox, subject)
            LootSense_SetEditBoxText(bodyBox, "")  -- empty body so receiver can delete mail in one click
            return true
        end
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[LootSense]|r CT_MailMod detected, but I could not find CT's recipient box. Open CT's send/mass-mail tab and try again.")
        return false
    end
    if SendMailNameEditBox then SendMailNameEditBox:SetText(name or "") end
    if SendMailSubjectEditBox then SendMailSubjectEditBox:SetText(subject or "") end
    if SendMailBodyEditBox then SendMailBodyEditBox:SetText("") end  -- empty body
    -- Switch to the Send tab so the player can immediately click Send
    LootSense_SwitchToSendMailTab()
    return true
end

local function LootSense_FindPendingItemInBags(itemID, usedSlots)
    for bag = 0, 4 do
        local slots = LootSense_GetContainerSlots and LootSense_GetContainerSlots(bag) or GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local key = bag..":"..slot
            if not usedSlots or not usedSlots[key] then
                local link = LootSense_GetContainerLink and LootSense_GetContainerLink(bag, slot) or GetContainerItemLink(bag, slot)
                if LootSense_ExtractItemID(link) == itemID then
                    local texture, itemCount = LootSense_GetContainerInfo and LootSense_GetContainerInfo(bag, slot) or GetContainerItemInfo(bag, slot)
                    return bag, slot, link, key, (tonumber(itemCount) or 1)
                end
            end
        end
    end
    return nil
end

local function LootSense_AttachBankItem(itemID, usedSlots)
    local bag, slot, link, key, stackCount = LootSense_FindPendingItemInBags(itemID, usedSlots)
    if not bag then return false, 0 end
    ClearCursor()
    if C_Container and C_Container.UseContainerItem then C_Container.UseContainerItem(bag, slot) else UseContainerItem(bag, slot) end
    if usedSlots and key then usedSlots[key] = true end
    return true, (stackCount or 1)
end

local function LootSense_SubtractPending(bankName, sentItems)
    local list = LootSense_bankPending and LootSense_bankPending[bankName]
    if not list then return end
    for si = 1, #(sentItems or {}) do
        local sent = sentItems[si]
        for i = #list, 1, -1 do
            if list[i] and sent and list[i].id == sent.id then
                list[i].count = (tonumber(list[i].count) or 0) - (tonumber(sent.count) or 1)
                if list[i].count <= 0 then table.remove(list, i) end
                break
            end
        end
    end
    if #list == 0 then LootSense_bankPending[bankName] = nil end
end

function LootSense_PrepareBankMail(bankName)
    if LootSense_IsFeatureEnabled and not LootSense_IsFeatureEnabled("mail") then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[LootSense]|r Bank mail is disabled in Settings.")
        return
    end
    if not bankName or bankName == "" then return end
    if LootSense_bankOutgoing and LootSense_bankOutgoing[bankName] and LootSense_bankOutgoing[bankName].items and #LootSense_bankOutgoing[bankName].items > 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[LootSense]|r Mail for "..bankName.." is already prepared. Press Send first, or clear the attachment.")
        return
    end
    if LootSense_SyncBankPendingFromBags then LootSense_SyncBankPendingFromBags() end
    if not ((MailFrame and MailFrame:IsVisible()) or (SendMailFrame and SendMailFrame:IsVisible()) or LootSense_IsCTMailVisible()) then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff3333[LootSense]|r Open your mailbox first.")
        return
    end
    local list = LootSense_bankPending and LootSense_bankPending[bankName]
    if not list or #list == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[LootSense]|r No bank items pending for "..bankName..".")
        if LootSense_RefreshBankMailFrame then LootSense_RefreshBankMailFrame() end
        return
    end
    local ctMailOpen = LootSense_IsCTMailVisible()
    local maxAttach = 14
    if ctMailOpen then
        maxAttach = 24
    end
    local usedSlots, attached, attachedCount = {}, {}, 0
    if not LootSense_SetMailFields(bankName, ".", "") then return end
    for i = 1, #list do
        local entry = list[i]
        local remainingForEntry = tonumber(entry and entry.count) or 0
        while entry and remainingForEntry > 0 and attachedCount < maxAttach do
            local ok, stackCount = LootSense_AttachBankItem(entry.id, usedSlots)
            if not ok then break end
            stackCount = stackCount or 1
            attachedCount = attachedCount + 1
            table.insert(attached, { id = entry.id, name = entry.name, count = stackCount })
            remainingForEntry = remainingForEntry - stackCount
			-- WoW 1.14 supports 7 attachments without CTMail
			if ctMailOpen and attachedCount >= maxAttach then
				break
			end
        end
        if attachedCount >= maxAttach then break end
    end
    if attachedCount <= 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff3333[LootSense]|r Could not find pending items for "..bankName.." in your bags.")
        return
    end
    LootSense_bankOutgoing[bankName] = { bank = bankName, items = attached, ts = time() }
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffcc[LootSense]|r Prepared mail for "..bankName..". Attached "..attachedCount.." item stack(s). Press Send.")
    if not ctMailOpen and LootSense_GetBankPendingCount(bankName) > attachedCount then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[LootSense]|r Vanilla mail only attaches 1 item/stack. Send this mail, then click "..bankName.." again.")
    end
    if LootSense_RefreshBankMailFrame then LootSense_RefreshBankMailFrame() end
end

LootSenseBankMailFrame = CreateFrame("Frame", "LootSenseBankMailFrame", UIParent, "BackdropTemplate")
LootSenseBankMailFrame:SetSize(260, 220)
LootSenseBankMailFrame:SetPoint("TOPLEFT", MailFrame or UIParent, "TOPRIGHT", 8, -20)
LootSenseBankMailFrame:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16 })
LootSenseBankMailFrame:SetBackdropColor(0,0,0,0.88)
LootSenseBankMailFrame:SetMovable(true)
LootSenseBankMailFrame:EnableMouse(true)
LootSenseBankMailFrame:RegisterForDrag("LeftButton")
LootSenseBankMailFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
LootSenseBankMailFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
LootSenseBankMailFrame:Hide()
LootSense_AddSpecialFrame("LootSenseBankMailFrame")

LootSenseBankMailFrame.title = LootSenseBankMailFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
LootSenseBankMailFrame.title:SetPoint("TOP", 0, -8)
LootSenseBankMailFrame.title:SetText("LootSense Banks")
LootSenseBankMailFrame.close = CreateFrame("Button", nil, LootSenseBankMailFrame, "UIPanelButtonTemplate")
LootSenseBankMailFrame.close:SetSize(22, 20)
LootSenseBankMailFrame.close:SetPoint("TOPRIGHT", -6, -6)
LootSenseBankMailFrame.close:SetText("X")
LootSenseBankMailFrame.close:SetScript("OnClick", function() LootSenseBankMailFrame:Hide() end)
LootSenseBankMailFrame.rows = {}
for LootSense_rowIndex = 1, 8 do
    local row = CreateFrame("Button", nil, LootSenseBankMailFrame)
    row:SetSize(205, 20)
    row:SetPoint("TOPLEFT", 16, -(34 + ((LootSense_rowIndex-1) * 22)))
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.text:SetPoint("LEFT", 2, 0)
    row.text:SetJustifyH("LEFT")
    row:SetScript("OnClick", function(self) if self.bankName then LootSense_PrepareBankMail(self.bankName) end end)
    row:SetScript("OnEnter", function(self)
        if self.bankName then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Attach items for "..self.bankName)
            GameTooltip:AddLine("Click to prepare this bank mail.", 1,1,1)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    LootSenseBankMailFrame.rows[LootSense_rowIndex] = row
end
LootSense_rowIndex = nil

function LootSense_RefreshBankMailFrame()
    if not LootSenseBankMailFrame then return end
    local arr = {}
    for bankName, list in pairs(LootSense_bankPending or {}) do
        local count = LootSense_GetBankPendingCount(bankName)
        if LootSense_BankExists(bankName) and count > 0 then table.insert(arr, { name = bankName, count = count }) end
    end
    table.sort(arr, function(a,b) return string.lower(a.name or "") < string.lower(b.name or "") end)
    for i = 1, #(LootSenseBankMailFrame.rows or {}) do
        local row = LootSenseBankMailFrame.rows[i]
        if arr[i] then
            row.bankName = arr[i].name
            row.text:SetText(arr[i].name.." - "..arr[i].count.." item(s)")
            row:Show()

            row:SetScript("OnEnter", function(self)
                local bName = self.bankName
                if not bName then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(bName, 0.2, 1, 0.8)
                local grouped = {}

                for bag = 0, 4 do
                    local slots = LootSense_GetContainerSlots and LootSense_GetContainerSlots(bag) or GetContainerNumSlots(bag) or 0

                    for slot = 1, slots do
                        local link = LootSense_GetContainerLink and LootSense_GetContainerLink(bag, slot) or GetContainerItemLink(bag, slot)
                        local itemID = LootSense_ExtractItemID(link)
                        local rule = itemID and LootSense_GetBankRule(itemID)

                        if rule and rule.bank == bName then
                            local _, itemCount = LootSense_GetContainerInfo(bag, slot)
                            local itemName = rule.name or GetItemInfo(itemID) or ("Item "..tostring(itemID))

                            if not grouped[itemID] then
                                grouped[itemID] = {
                                    id = itemID,
                                    name = itemName,
                                    count = 0
                                }
                            end

                            grouped[itemID].count = grouped[itemID].count + (tonumber(itemCount) or 1)
                        end
                    end
                end

                local sorted = {}

                for _, data in pairs(grouped) do
                    table.insert(sorted, data)
                end

                table.sort(sorted, function(a, b)
                    return string.lower(a.name or "") < string.lower(b.name or "")
                end)

                if #sorted > 0 then
                    for j = 1, #sorted do
                        local entry = sorted[j]

                        local icon = LootSense_GetItemIcon(entry.id)
                        local _, _, quality = GetItemInfo(entry.id)

                        local qColor = quality and colors[quality]
                        local r, g, b = 1, 1, 1

                        if qColor then
                            r, g, b = qColor[1], qColor[2], qColor[3]
                        end

                        GameTooltip:AddLine(
                            "|T"..(icon or "Interface\\Icons\\INV_Misc_QuestionMark")..":16:16:0:0|t "
                            ..entry.name.."  "..tostring(entry.count),
                            r, g, b
                        )
                    end
                else
                    GameTooltip:AddLine("No pending items.", 0.7, 0.7, 0.7)
                end
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Click to prepare mail.", 0.6, 0.6, 0.6)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)

        else
            row.bankName = nil
            row:Hide()
        end
    end
    if #arr > 0 and (not LootSense_IsFeatureEnabled or LootSense_IsFeatureEnabled("mail")) and ((MailFrame and MailFrame:IsVisible()) or (SendMailFrame and SendMailFrame:IsVisible()) or LootSense_IsCTMailVisible()) then
        LootSenseBankMailFrame:Show()
    elseif #arr == 0 then
        LootSenseBankMailFrame:Hide()
    end
end


local LootSenseMailEvents = CreateFrame("Frame")
LootSenseMailEvents:RegisterEvent("MAIL_SHOW")
LootSenseMailEvents:RegisterEvent("MAIL_CLOSED")
LootSenseMailEvents:RegisterEvent("MAIL_SEND_SUCCESS")
LootSenseMailEvents:RegisterEvent("BAG_UPDATE_DELAYED")
LootSenseMailEvents:SetScript("OnEvent", function(self, event)
    if event == "MAIL_SHOW" then
        if LootSense_IsFeatureEnabled and not LootSense_IsFeatureEnabled("mail") then
            LootSense_Debug("MAIL_SHOW ignored because bank mail is disabled.")
            if LootSenseBankMailFrame then LootSenseBankMailFrame:Hide() end
            return
        end
        LootSense_Debug("MAIL_SHOW fired. Scanning bags for bank rules...")
        if LootSense_SyncBankPendingFromBags then LootSense_SyncBankPendingFromBags() end
        local totalBanks = 0
        local totalItems = 0
        for bankName, list in pairs(LootSense_bankPending or {}) do
            local count = LootSense_GetBankPendingCount(bankName)
            if LootSense_BankExists(bankName) and count > 0 then
                totalBanks = totalBanks + 1
                totalItems = totalItems + count
            end
        end
        LootSense_Debug("Bank pending after scan: "..totalBanks.." bank(s), "..totalItems.." item(s).")
        if totalBanks == 0 then
            LootSense_Debug("No mailbox frame shown because no bag items currently match Bank rules.")
        end
        LootSense_RefreshBankMailFrame()
    elseif event == "MAIL_CLOSED" then
        LootSense_Debug("MAIL_CLOSED fired. Hiding bank mail frame.")
        if LootSenseBankMailFrame then LootSenseBankMailFrame:Hide() end
        LootSense_bankOutgoing = {}
        if LootSense_SyncBankPendingFromBags then LootSense_SyncBankPendingFromBags() end
    elseif event == "MAIL_SEND_SUCCESS" then
        LootSense_Debug("MAIL_SEND_SUCCESS fired.")
        for bankName, outgoing in pairs(LootSense_bankOutgoing or {}) do
            if outgoing and outgoing.items then
                LootSense_SubtractPending(bankName, outgoing.items)
                LootSense_bankOutgoing[bankName] = nil
                DEFAULT_CHAT_FRAME:AddMessage("|cff33ffcc[LootSense]|r Marked bank mail sent for "..bankName..".")
                break
            end
        end
        if LootSense_SyncBankPendingFromBags then LootSense_SyncBankPendingFromBags() end
        LootSense_RefreshBankMailFrame()
    elseif event == "BAG_UPDATE_DELAYED" then
        if (MailFrame and MailFrame:IsVisible()) or (SendMailFrame and SendMailFrame:IsVisible()) or LootSense_IsCTMailVisible() or (LootSenseBankMailFrame and LootSenseBankMailFrame:IsVisible()) then
            LootSense_Debug("BAG_UPDATE_DELAYED while mailbox/bank frame is open. Refreshing pending bank items.")
            if LootSense_SyncBankPendingFromBags then LootSense_SyncBankPendingFromBags() end
            LootSense_RefreshBankMailFrame()
        end
    end
end)

local function LootSense_RemoveLootHelperRow(row)
    if not row then return end
    row:Hide()
    for i = 1, #(LootHelperFrame.items or {}) do
        if LootHelperFrame.items[i] == row then
            table.remove(LootHelperFrame.items, i)
            LootHelperFrame.count = math.max((LootHelperFrame.count or 1) - 1, 0)
            break
        end
    end
    if LootSense_UpdateLootHelperWidth then LootSense_UpdateLootHelperWidth() end
    if LootSense_UpdateLootHelperVisibility then LootSense_UpdateLootHelperVisibility() end
end

local function LootSense_TryLootSlot(slot, expectedItemID)
    if not slot then return false end
    if not (LootFrame and LootFrame:IsShown()) then return false end

    local link = GetLootSlotLink and GetLootSlotLink(slot)
    if not link then return false end

    if expectedItemID and LootSense_ExtractItemID and LootSense_ExtractItemID(link) ~= expectedItemID then
        return false
    end

    LootSlot(slot)
    return true
end

local function LootSense_RelayoutLootHelperRows()
    local lastRow = nil
    for i = 1, #(LootHelperFrame.items or {}) do
        local row = LootHelperFrame.items[i]
        if row then
            row:ClearAllPoints()
            if lastRow then
                row:SetPoint("TOPLEFT", lastRow, "BOTTOMLEFT", 0, -5)
            else
                row:SetPoint("TOPLEFT", LootHelperFrame, "TOPLEFT", 10, -30)
            end
            row:Show()
            lastRow = row
        end
    end
    local h = 40 + ((LootHelperFrame.count or 0) * 37)
    LootHelperFrame:SetHeight(h)
    if LootSense_UpdateLootHelperWidth then LootSense_UpdateLootHelperWidth() end
    if LootSense_UpdateLootHelperVisibility then LootSense_UpdateLootHelperVisibility() end
end

local function LootSense_LootHelperHasID(itemID)
    if not itemID then return false end
    for i = 1, #(LootHelperFrame.items or {}) do
        local row = LootHelperFrame.items[i]
        if row and tonumber(row.itemID) == tonumber(itemID) then return true end
    end
    return false
end

local function LootSense_RemoveKnownLootHelperRows()
    for i = #(LootHelperFrame.items or {}), 1, -1 do
        local row = LootHelperFrame.items[i]
        local itemID = row and row.itemID
        if itemID and (
            LootSense_ListHasID(LootSense_keep, itemID) or
            LootSense_ListHasID(LootSense_vendor, itemID) or
            LootSense_ListHasID(LootSense_delete, itemID) or
            (LootSense_GetBankRule and LootSense_GetBankRule(itemID))
        ) then
            row:Hide()
            table.remove(LootHelperFrame.items, i)
            LootHelperFrame.count = math.max((LootHelperFrame.count or 1) - 1, 0)
        end
    end
    LootSense_RelayoutLootHelperRows()
end

local function LootSense_ShowBankChooser(row, slot, name, itemID, quantity)
    if not LootSense_HasBanks() then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[LootSense]|r Add at least one bank in /ls list -> Banks first.")
        return
    end
    if not LootSenseBankChooser then
        LootSenseBankChooser = CreateFrame("Frame", "LootSenseBankChooser", UIParent, "BackdropTemplate")
        LootSenseBankChooser:SetSize(180, 120)
        LootSenseBankChooser:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16 })
        LootSenseBankChooser:SetBackdropColor(0,0,0,0.9)
        LootSenseBankChooser:SetFrameStrata("DIALOG")
        LootSenseBankChooser:SetFrameLevel(50)
        LootSenseBankChooser:EnableMouse(true)
        LootSenseBankChooser.rows = {}
        LootSenseBankChooser:SetScript("OnHide", function() LootSense_HidePopupCatcher() end)
        LootSenseBankChooser.title = LootSenseBankChooser:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        LootSenseBankChooser.title:SetPoint("TOP", 0, -8)
        LootSenseBankChooser.title:SetText("Send to bank")
        LootSense_AddSpecialFrame("LootSenseBankChooser")
    end
    for i = 1, #(LootSenseBankChooser.rows or {}) do LootSenseBankChooser.rows[i]:Hide() end
    local bankCount = #(LootSense_banks or {})
    local chooserWidth = 180
    for i = 1, bankCount do
        chooserWidth = math.max(chooserWidth, LootSense_GetActionWidth("Bank: "..tostring(LootSense_banks[i] or "")) + 18)
    end
    chooserWidth = LootSense_Clamp(chooserWidth, 180, 340)
    LootSenseBankChooser:SetWidth(chooserWidth)
    LootSenseBankChooser:SetHeight(34 + (bankCount * 24))
    LootSenseBankChooser:ClearAllPoints()
    -- Anchor the bank chooser below the loot-helper action buttons instead of
    -- beside the whole row. This keeps it visually tied to the button you clicked.
    if row and row.ignore then
        LootSenseBankChooser:SetPoint("TOPRIGHT", row.ignore, "BOTTOMRIGHT", 0, -4)
    elseif row and row.bank then
        LootSenseBankChooser:SetPoint("TOPLEFT", row.bank, "BOTTOMLEFT", 0, -4)
    else
        LootSenseBankChooser:SetPoint("LEFT", row, "RIGHT", 8, 0)
    end
    for i = 1, bankCount do
        local btn = LootSenseBankChooser.rows[i]
        if not btn then
            btn = CreateFrame("Button", nil, LootSenseBankChooser)
            btn:SetSize(chooserWidth - 16, 20)
            btn:SetPoint("TOPLEFT", LootSenseBankChooser, "TOPLEFT", 8, -(18 + ((i-1) * 24)))
            btn.bg = btn:CreateTexture(nil, "BACKGROUND")
            btn.bg:SetAllPoints(btn)
            btn.bg:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            btn.bg:SetBlendMode("ADD")
            btn.bg:SetAlpha(0.25)
            btn.bg:Hide()
            btn.icon = btn:CreateTexture(nil, "ARTWORK")
            btn.icon:SetSize(17, 17)
            btn.icon:SetPoint("LEFT", btn, "LEFT", 3, 0)
            btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            btn.text:SetPoint("LEFT", btn.icon, "RIGHT", 6, 0)
            btn.text:SetJustifyH("LEFT")
            btn:SetScript("OnEnter", function(self) if self.bg then self.bg:Show() end end)
            btn:SetScript("OnLeave", function(self) if self.bg then self.bg:Hide() end end)
            LootSenseBankChooser.rows[i] = btn
        end
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", LootSenseBankChooser, "TOPLEFT", 8, -(18 + ((i-1) * 24)))
        btn:SetSize(chooserWidth - 16, 20)
        btn.bankName = LootSense_banks[i]
        btn.icon:SetTexture(LootSense_ActionIcons.bank)
        btn.text:SetWidth(chooserWidth - 48)
        btn.text:SetText(LootSense_banks[i])
        btn:SetScript("OnClick", function(self)
            local bankName = self.bankName
            LootSense_AddBankRule(itemID, name, bankName)
            if LootSense_TryLootSlot(slot, itemID) then
                LootSense_AddBankPending(bankName, itemID, name, quantity or 1)
            elseif LootSense_SyncBankPendingFromBags then
                LootSense_SyncBankPendingFromBags()
            end
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ffcc[LootSense]|r Bank: "..name.." -> "..bankName)
            LootSense_HideBankChooser()
            LootSense_RemoveLootHelperRow(row)
        end)
        btn:Show()
    end
    LootSenseBankChooser:Show()
    LootSense_ShowPopupCatcher(LootSenseBankChooser, LootSense_HideBankChooser)
end

-- ##################################################
-- ## CREATE BUTTON ACTION (SAVES ITEMID)
-- ##################################################
local function createButtonAction(slot, action, name, itemID, itemFrame)
    return function(self)
        local entry = { id = itemID, name = name }

        if action == "keep" then
            LootSense_SetItemAction(itemID, name, "keep")
            LootSense_TryLootSlot(slot, itemID)
            DEFAULT_CHAT_FRAME:AddMessage("Keep: "..name.." (ID: "..itemID..")")
        elseif action == "vendor" then
            LootSense_SetItemAction(itemID, name, "vendor")
            LootSense_TryLootSlot(slot, itemID)
            DEFAULT_CHAT_FRAME:AddMessage("Vendor: "..name.." (ID: "..itemID..")")
        elseif action == "throw" then
            LootSense_SetItemAction(itemID, name, "delete")
            LootSense_TryLootSlot(slot, itemID)
            DEFAULT_CHAT_FRAME:AddMessage("Delete: "..name.." (ID: "..itemID..")")
        elseif action == "ignore" then
            DEFAULT_CHAT_FRAME:AddMessage("Ignored: "..name.." (ID: "..itemID..")")
        end

        if itemFrame then
            itemFrame:Hide()
        end
    end
end



-- ##################################################
-- ## SLASH COMMANDS
-- ##################################################


SLASH_LootSenseLIST1 = "/ls"
SlashCmdList["LootSenseLIST"] = function(msg)
    local cmd = string.lower(msg or "")
    if cmd == "list" then
        if LootSenseList:IsShown() then
            LootSenseList:Hide()
        else
            LootSenseList.search:SetText("") -- rensa sökfältet
            RefreshLootSenseList()           -- uppdatera listan
            LootSenseList:Show()
        end
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccUsage:|r /ls list")
    end
end

-- ##################################################
-- ## LOOT HELPER FRAME (WoW-style)
-- ##################################################
LootHelperFrame = CreateFrame("Frame", "LootHelperFrame", UIParent, "BackdropTemplate")

LootHelperFrame:SetWidth(360)
LootHelperFrame:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
LootHelperFrame:SetHeight(200)
LootHelperFrame:Hide()
LootSense_AddSpecialFrame("LootHelperFrame")
-- Gör fönstret flyttbart
LootHelperFrame:SetMovable(true)
LootHelperFrame:EnableMouse(true)
LootHelperFrame:RegisterForDrag("LeftButton")
LootHelperFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
LootHelperFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
LootHelperFrame:SetScript("OnHide", function(self) LootSense_HideBankChooser() end)
-- ##################################################
-- ## SETTINGS KNAPP
-- ##################################################
LootHelperFrame.settingsBtn = CreateFrame("Button", nil, LootHelperFrame)
LootHelperFrame.settingsBtn:SetWidth(20)
LootHelperFrame.settingsBtn:SetHeight(20)
LootHelperFrame.settingsBtn:SetPoint("TOPRIGHT", -8, -8)

-- ikon (kugghjul)
LootHelperFrame.settingsBtn.icon = LootHelperFrame.settingsBtn:CreateTexture(nil, "BACKGROUND")
LootHelperFrame.settingsBtn.icon:SetAllPoints()
LootHelperFrame.settingsBtn.icon:SetTexture("Interface\\Icons\\INV_Gizmo_01")  -- kugghjulsikon

-- klick: öppna/stäng LootSenseList
LootHelperFrame.settingsBtn:SetScript("OnClick", function()
    if LootSenseList:IsShown() then
        LootSenseList:Hide()
    else
        LootSenseList:Show()
    end
end)

-- tooltip
LootHelperFrame.settingsBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(LootHelperFrame.settingsBtn, "ANCHOR_RIGHT")
    GameTooltip:SetText("Manage", 1, 1, 1)
    GameTooltip:Show()
end)

LootHelperFrame.settingsBtn:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
end)


-- backdrop och border
LootHelperFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
LootHelperFrame:SetBackdropColor(0,0,0,0.7)
LootHelperFrame:SetBackdropBorderColor(0.6,0.6,0.6,1)

LootHelperFrame.items = {}
LootHelperFrame.count = 0

-- titel
LootHelperFrame.title = LootHelperFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
LootHelperFrame.title:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
LootHelperFrame.title:SetPoint("TOP", 0, -8)
LootHelperFrame.title:SetText("ALWAYS?")

local function ClearLootHelper()
    for _, row in pairs(LootHelperFrame.items) do
        row:Hide()
    end
    LootHelperFrame.items = {}
    LootHelperFrame.count = 0
    LootHelperFrame:Hide()
end

function LootSense_UpdateLootHelperVisibility()
    if LootHelperFrame.count == 0 then
        LootHelperFrame:Hide()
    else
        LootHelperFrame:Show()
    end
end

function LootSense_UpdateLootHelperWidth()
    if not LootHelperFrame then return end
    local maxWidth = 360
    for i = 1, #(LootHelperFrame.items or {}) do
        local row = LootHelperFrame.items[i]
        if row and row.neededWidth then
            maxWidth = math.max(maxWidth, row.neededWidth)
        end
    end
    maxWidth = LootSense_Clamp(maxWidth, 360, 720)
    LootHelperFrame:SetWidth(maxWidth)
    for i = 1, #(LootHelperFrame.items or {}) do
        local row = LootHelperFrame.items[i]
        if row and row.UpdateDynamicLayout then row:UpdateDynamicLayout(maxWidth) end
    end
end

local function CreateItemRow(parent, slot, texture, name, quality, itemLink, itemID, quantity)
    local row = CreateFrame("Frame", nil, parent)
    row.itemID = itemID
    row.itemName = name
    row.itemLink = itemLink
    row.quality = quality
    row:SetHeight(22)

    -- Bakgrund för hover effect
    row.highlight = row:CreateTexture(nil, "BACKGROUND")
    row.highlight:SetAllPoints(row)
    row.highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    row.highlight:SetBlendMode("ADD")
    row.highlight:SetAlpha(0.3)
    row.highlight:Hide()

    -- ikon
    row.icon = row:CreateTexture(nil, "OVERLAY")
    row.icon:SetWidth(18)
    row.icon:SetHeight(18)
    row.icon:SetPoint("LEFT", row, "LEFT", 5, 0)
    row.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")

    -- Gör texten till en klickbar knapp för tooltip
    row.textBtn = CreateFrame("Button", nil, row)
    row.textBtn:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
    row.textBtn:SetHeight(18)

    -- text
    row.text = row.textBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.text:SetPoint("LEFT", row.textBtn, "LEFT", 0, 0)
    row.text:SetJustifyH("LEFT")
    local displayName = name or "?"
    if quantity and quantity > 1 then displayName = displayName .. " |cffaaaaaa x" .. quantity .. "|r" end
    row.text:SetText(displayName)
    LootSense_ApplyQualityColor(row.text, quality, itemLink)

    -- Tooltip för item text - använd samma metod som lootfönstret
    row.textBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if LootFrame and LootFrame:IsShown() and GetLootSlotLink and GetLootSlotLink(slot) then
            GameTooltip:SetLootItem(slot)
        elseif itemLink and GameTooltip.SetHyperlink then
            GameTooltip:SetHyperlink(itemLink)
        else
            GameTooltip:SetText(name or "?")
        end
        GameTooltip:Show()
        row.highlight:Show()
    end)

    row.textBtn:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        row.highlight:Hide()
    end)

    row.textBtn:SetScript("OnClick", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if LootFrame and LootFrame:IsShown() and GetLootSlotLink and GetLootSlotLink(slot) then
            GameTooltip:SetLootItem(slot)
        elseif itemLink and GameTooltip.SetHyperlink then
            GameTooltip:SetHyperlink(itemLink)
        else
            GameTooltip:SetText(name or "?")
        end
        GameTooltip:Show()
    end)

    row:SetScript("OnEnter", function(self) row.highlight:Show() end)
    row:SetScript("OnLeave", function(self) row.highlight:Hide() end)

    local function makeBtn(icon, tooltip, action, itemID)
        local btn = CreateFrame("Button", nil, row)
        btn:SetWidth(22)
        btn:SetHeight(22)
        btn:SetNormalTexture(icon)
        btn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tooltip)
            GameTooltip:Show()
            row.highlight:Show()
        end)

        btn:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
            row.highlight:Hide()
        end)

        btn:SetScript("OnClick", function(self)
            if action == "bank" then
                LootSense_ShowBankChooser(row, slot, name, itemID, quantity or 1)
                return
            end

            createButtonAction(slot, action, name, itemID, row)()

            if action == "throw" then
                AutoTrash:Show()
            end

            LootSense_RemoveLootHelperRow(row)
        end)
        return btn
    end

    -- knappar: Keep/Bank/Vendor/Delete/Ignore
    row.keep   = makeBtn(LootSense_ActionIcons.keep,   "Keep this item",   "keep",   itemID)
    row.bank   = makeBtn(LootSense_ActionIcons.bank,   "Bank this item",   "bank",   itemID)
    row.vendor = makeBtn(LootSense_ActionIcons.vendor, "Vendor this item", "vendor", itemID)
    row.throw  = makeBtn(LootSense_ActionIcons.throw,  "Delete this item", "throw",  itemID)
    row.ignore = makeBtn(LootSense_ActionIcons.ignore, "Ignore this item", "ignore", itemID)
    if LootSense_HasBanks and LootSense_HasBanks() then row.bank:Show() else row.bank:Hide() end

    row.UpdateDynamicLayout = function(self, frameWidth)
        frameWidth = frameWidth or (LootHelperFrame and LootHelperFrame:GetWidth()) or 360
        self:SetWidth(frameWidth - 15)
        local buttons = { self.keep, self.bank, self.vendor, self.throw, self.ignore }
        local visibleButtons = {}
        for i = 1, #buttons do
            if buttons[i] and buttons[i]:IsShown() then table.insert(visibleButtons, buttons[i]) end
        end
        local totalButtonWidth = (#visibleButtons * 22) + (math.max(#visibleButtons - 1, 0) * 8)
        local firstButtonX = frameWidth - totalButtonWidth - 22
        for i = 1, #visibleButtons do
            visibleButtons[i]:ClearAllPoints()
            visibleButtons[i]:SetPoint("LEFT", self, "LEFT", firstButtonX + ((i - 1) * 30), 0)
        end
        local textWidth = math.max(110, firstButtonX - 36)
        self.textBtn:SetWidth(textWidth)
        self.text:SetWidth(textWidth)
    end

    local nameWidth = 110
    if row.text and row.text.GetStringWidth then nameWidth = math.ceil(row.text:GetStringWidth() or 110) end
    local buttonCount = (LootSense_HasBanks and LootSense_HasBanks()) and 5 or 4
    row.neededWidth = LootSense_Clamp(10 + 18 + 5 + nameWidth + 18 + (buttonCount * 22) + ((buttonCount - 1) * 8) + 24, 360, 720)
    row:UpdateDynamicLayout(row.neededWidth)

    return row
end
-- ##################################################
-- ## LOOT WINDOW INTEGRATION WITH ITEMID
-- ##################################################


local lootFrame = CreateFrame("Frame")
lootFrame:RegisterEvent("LOOT_OPENED")
lootFrame:RegisterEvent("LOOT_CLOSED")

-- ##################################################
-- ## UNCACHED ITEM RETRY SYSTEM
-- ##################################################
-- When GetItemInfo returns no itemType (item not yet cached by client),
-- we store the slot info here and retry every 0.2s until the loot window
-- closes or the data arrives.
local LS_PendingCollectionSlots = {}  -- { {slot, itemID, name, quality, texture, quantity, link}, ... }
local LS_LootWindowOpen = false

local lootRetryFrame = CreateFrame("Frame")
lootRetryFrame:Hide()
lootRetryFrame.elapsed = 0
lootRetryFrame:SetScript("OnUpdate", function(self, dt)
    self.elapsed = (self.elapsed or 0) + dt
    if self.elapsed < 0.2 then return end
    self.elapsed = 0

    if not LS_LootWindowOpen or #LS_PendingCollectionSlots == 0 then
        self:Hide()
        return
    end

    local stillPending = {}
    for _, info in ipairs(LS_PendingCollectionSlots) do
        local _, _, _, _, _, iType, iSubType = GetItemInfo(info.itemID)
        if iType then
            -- Data is now cached — run collection check
            local colBank = LootSense_GetCollectionBank
                and LootSense_GetCollectionBank(iType, iSubType, info.quality)
            if colBank and (not LootSense_IsFeatureEnabled or LootSense_IsFeatureEnabled("mail")) then
                LootSense_AddBankRule(info.itemID, info.name, colBank)
                LootSense_AddBankPending(colBank, info.itemID, info.name, info.quantity or 1)
                -- Only loot if the window is still open and the slot still has our item
                if LootFrame and LootFrame:IsShown() then
                    local currentLink = GetLootSlotLink and GetLootSlotLink(info.slot)
                    local currentID = currentLink and currentLink:match("item:(%d+):")
                    if currentID and tonumber(currentID) == info.itemID then
                        LootSlot(info.slot)
                    end
                end
                DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccAuto-bank (collection)|r: " .. info.name .. " -> " .. colBank)
                -- Remove from LootHelper if it was shown there already
                if LootSense_RemoveLootHelperRow then
                    for i = #(LootHelperFrame.items or {}), 1, -1 do
                        local row = LootHelperFrame.items[i]
                        if row and tonumber(row.itemID) == tonumber(info.itemID) then
                            LootSense_RemoveLootHelperRow(row)
                            break
                        end
                    end
                end
            else
                -- No collection rule matched — it belongs in LootHelper (if not already there)
                if not LootSense_LootHelperHasID(info.itemID) then
                    local lastRow = LootHelperFrame.items and LootHelperFrame.items[#LootHelperFrame.items] or nil
                    local row = CreateItemRow(
                        LootHelperFrame, info.slot, info.texture, info.name,
                        info.quality, info.link, info.itemID, info.quantity
                    )
                    if lastRow then
                        row:SetPoint("TOPLEFT", lastRow, "BOTTOMLEFT", 0, -5)
                    else
                        row:SetPoint("TOPLEFT", LootHelperFrame, "TOPLEFT", 10, -30)
                    end
                    table.insert(LootHelperFrame.items, row)
                    LootHelperFrame.count = LootHelperFrame.count + 1
                    LootHelperFrame:SetHeight(40 + LootHelperFrame.count * 37)
                    if LootSense_UpdateLootHelperWidth then LootSense_UpdateLootHelperWidth() end
                    LootSense_UpdateLootHelperVisibility()
                end
            end
        else
            -- Still not cached, keep waiting
            table.insert(stillPending, info)
        end
    end
    LS_PendingCollectionSlots = stillPending
    if #LS_PendingCollectionSlots == 0 then self:Hide() end
end)

-- ##################################################
-- ## LOOT WINDOW INTEGRATION WITH ITEMID
-- ##################################################

-- helper used in both LOOT_OPENED and the retry frame
local function LS_isInList(itemID, list)
    if not itemID or not list then return false end
    local targetID = tonumber(itemID)
    if not targetID then return false end
    for i = 1, #list do
        local entry = list[i]
        if entry and tonumber(entry.id) == targetID then return true end
    end
    return false
end

lootFrame:SetScript("OnEvent", function(self, event, ...)

    if event == "LOOT_OPENED" then

        if LootSense_paused then
            return
        end

        LS_LootWindowOpen = true
        LS_PendingCollectionSlots = {}

        -- Do not clear unresolved rows here. With autoloot the loot window can close
        -- before the player has picked an action, so pending choices must stay visible.
        LootSense_RemoveKnownLootHelperRows()

        local numLoot = GetNumLootItems()
        local lastRow = LootHelperFrame.items and LootHelperFrame.items[#LootHelperFrame.items] or nil

        for slot = 1, numLoot do

            local texture, itemName, quantity, quality = GetLootSlotInfo(slot)
            local itemLink = GetLootSlotLink(slot)

            if itemLink then

                local cachedName, _, cachedQuality, _, _, iType, iSubType = GetItemInfo(itemLink)

                local name    = cachedName or itemName or "Unknown Item"
                quality       = cachedQuality or quality or 1

                local id      = itemLink:match("item:(%d+):")
                local itemID  = id and tonumber(id)

                -- `handled` = true means we've already decided what to do with this
                -- item and it must NOT appear in the LootHelper popup.
                local handled = false

                if itemID then

                    -- ── 1. KNOWN DELETE LIST ──────────────────────────────────
                    if LS_isInList(itemID, LootSense_delete) then
                        LootSlot(slot)
                        handled = true

                    -- ── 2. KNOWN KEEP LIST ────────────────────────────────────
                    elseif LS_isInList(itemID, LootSense_keep) then
                        LootSlot(slot)
                        handled = true

                    -- ── 3. KNOWN VENDOR LIST ──────────────────────────────────
                    elseif LS_isInList(itemID, LootSense_vendor) then
                        LootSlot(slot)
                        handled = true

                    -- ── 4. PER-ITEM BANK RULE ─────────────────────────────────
                    elseif LootSense_GetBankRule and LootSense_GetBankRule(itemID) then
                        local bankRule = LootSense_GetBankRule(itemID)
                        if (not LootSense_IsFeatureEnabled or LootSense_IsFeatureEnabled("mail")) then
                            LootSense_AddBankPending(bankRule.bank, itemID, name, quantity or 1)
                            LootSlot(slot)
                            DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccAuto-bank:|r " .. name .. " -> " .. bankRule.bank)
                        end
                        handled = true

                    -- ── 5. COLLECTION RULE (category-based) ───────────────────
                    else
                        if iType then
                            -- Item data already cached — check immediately
                            local colBank = LootSense_GetCollectionBank
                                and LootSense_GetCollectionBank(iType, iSubType, quality)

                            if colBank then
                                if (not LootSense_IsFeatureEnabled or LootSense_IsFeatureEnabled("mail")) then
                                    LootSense_AddBankRule(itemID, name, colBank)
                                    LootSense_AddBankPending(colBank, itemID, name, quantity or 1)
                                    LootSlot(slot)
                                    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccAuto-bank (collection)|r: " .. name .. " -> " .. colBank)
                                end
                                handled = true

                            -- ── 6. AUTO DELETE BY QUALITY ─────────────────────────
                            elseif (not LootSense_IsFeatureEnabled or LootSense_IsFeatureEnabled("autoDelete")) then
                                local autoDelQ = nil
                                if LootSense_autoDelete.gray  and quality == 0 then autoDelQ = "|cffff5555Auto-deleted gray:|r "
                                elseif LootSense_autoDelete.white and quality == 1 then autoDelQ = "|cffffffffAuto-deleted white:|r "
                                elseif LootSense_autoDelete.green and quality == 2 then autoDelQ = "|cff55ff55Auto-deleted green:|r "
                                elseif LootSense_autoDelete.blue  and quality == 3 then autoDelQ = "|cff0070ddAuto-deleted blue:|r "
                                end
                                if autoDelQ then
                                    table.insert(LootSense_delete, { id = itemID, name = name })
                                    LootSlot(slot)
                                    DEFAULT_CHAT_FRAME:AddMessage(autoDelQ .. name)
                                    handled = true
                                end
                            end
                        else
                            -- Item data NOT cached yet — queue for retry, don't show LootHelper yet
                            LootSense_Debug("Item not cached, queuing for retry: " .. tostring(itemLink))
                            table.insert(LS_PendingCollectionSlots, {
                                slot = slot, itemID = itemID, name = name,
                                quality = quality, texture = texture,
                                quantity = quantity, link = itemLink,
                            })
                            handled = true  -- prevent LootHelper from showing it now
                        end
                    end
                end

                -- ── 7. UNKNOWN: show in LootHelper ────────────────────────────
                if itemID and not handled and not LootSense_LootHelperHasID(itemID) then

                    local row = CreateItemRow(
                        LootHelperFrame, slot, texture, name,
                        quality, itemLink, itemID, quantity
                    )

                    if lastRow then
                        row:SetPoint("TOPLEFT", lastRow, "BOTTOMLEFT", 0, -5)
                    else
                        row:SetPoint("TOPLEFT", LootHelperFrame, "TOPLEFT", 10, -30)
                    end

                    table.insert(LootHelperFrame.items, row)
                    LootHelperFrame.count = LootHelperFrame.count + 1
                    lastRow = row
                end
            end
        end

        -- Start retry frame if there are uncached items pending
        if #LS_PendingCollectionSlots > 0 then
            lootRetryFrame.elapsed = 0
            lootRetryFrame:Show()
        end

        local h = 40 + (LootHelperFrame.count * 37)
        LootHelperFrame:SetHeight(h)
        if LootSense_UpdateLootHelperWidth then LootSense_UpdateLootHelperWidth() end
        LootSense_UpdateLootHelperVisibility()

    elseif event == "LOOT_CLOSED" then

        LS_LootWindowOpen = false
        LS_PendingCollectionSlots = {}
        lootRetryFrame:Hide()

        -- Keep LootHelperFrame open. Autoloot often closes the loot window before
        -- the player has chosen Keep/Delete/Vendor/Bank for unknown items.
        LootSense_UpdateLootHelperVisibility()
    end
end)


-- ##################################################
-- ## AutoSell
-- ##################################################

AutoSell = CreateFrame("Frame")
AutoSell:RegisterEvent("MERCHANT_SHOW")
AutoSell:RegisterEvent("MERCHANT_CLOSED")

-- internal state
AutoSell.active = false
AutoSell.lastCheck = 0

local function LootSense_IsVendorItem(itemID, itemName)
    if not itemID and not itemName then return false end
    local lowerName = itemName and string.lower(itemName) or nil
    for i = 1, #(LootSense_vendor or {}) do
        local entry = LootSense_vendor[i]
        if entry then
            if itemID and entry.id and tonumber(entry.id) == tonumber(itemID) then
                return true
            end
            if lowerName and entry.name and string.lower(entry.name) == lowerName then
                return true
            end
        end
    end
    return false
end

-- event handling
AutoSell:SetScript("OnEvent", function(self, event)
    if event == "MERCHANT_SHOW" then
        LootSense_Debug("MERCHANT_SHOW fired. Vendor rules: "..#(LootSense_vendor or {}))
        if LootSense_paused or (LootSense_IsFeatureEnabled and not LootSense_IsFeatureEnabled("vendor")) then
            LootSense_Debug("AutoSell skipped because LootSense is paused or auto vendor is disabled.")
            return
        end
        AutoSell.active = true
        AutoSell.soldCount = 0
        AutoSell:Show()
    elseif event == "MERCHANT_CLOSED" then
        LootSense_Debug("MERCHANT_CLOSED fired. AutoSell stopped.")
        AutoSell.active = false
        AutoSell:Hide()
    end
end)

-- main loop
AutoSell:SetScript("OnUpdate", function(self)
    -- tick timer, check every 0.1s
    if GetTime() < AutoSell.lastCheck then return end
    AutoSell.lastCheck = GetTime() + 0.1

    if not AutoSell.active then return end

    for bag = 0, 4 do
        local slots = LootSense_GetContainerSlots and LootSense_GetContainerSlots(bag) or GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local link = LootSense_GetContainerLink and LootSense_GetContainerLink(bag, slot) or GetContainerItemLink(bag, slot)
            if link then
                local itemID = LootSense_ExtractItemID and LootSense_ExtractItemID(link)
                local itemName = GetItemInfo(link)
                if LootSense_IsVendorItem(itemID, itemName) then
                    ClearCursor()
                    if C_Container and C_Container.UseContainerItem then
                        C_Container.UseContainerItem(bag, slot)
                    else
                        UseContainerItem(bag, slot)
                    end
                    AutoSell.soldCount = (AutoSell.soldCount or 0) + 1
                    LootSense_Debug("AutoSell sold stack: "..(itemName or ("itemID "..tostring(itemID))).." from bag "..bag..", slot "..slot..".")
                    return
                end
            end
        end
    end

    -- hide when done selling
    LootSense_Debug("AutoSell scan finished. Sold "..(AutoSell.soldCount or 0).." stack(s).")
    AutoSell.active = false
    AutoSell:Hide()
end)





