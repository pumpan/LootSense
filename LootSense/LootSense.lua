--[[ 
 LootSense+LootHelper (WoW 1.12.1 Addon)
 ---------------------------------------
 Features:
    - Adds slash commands for managing Keep, Vendor, and Delete lists
    - Creates a loot popup with buttons: Keep, Vendor, Throw, Ignore
    - Auto-vendors Vendor-list items at merchants
    - Auto-deletes Delete-list items when looted
    - Items in lists won't show buttons again
    - Loot popup now looks like WoW loot window
]]

local gfind = string.gmatch or string.gfind

-- ##################################################
-- ## CONFIG / DATABASE
-- ##################################################
LootSense_keep   = LootSense_keep   or {}
LootSense_vendor = LootSense_vendor or {}
LootSense_delete = LootSense_delete or {}

-- item quality colors
local colors = {
  [0] = {0.6, 0.6, 0.6},    -- Poor (gray)
  [1] = {1, 1, 1},          -- Common (white)
  [2] = {0, 1, 0},          -- Uncommon (green)
  [3] = {0, 0.44, 0.87},    -- Rare (blue)
  [4] = {0.64, 0.21, 0.93}, -- Epic (purple)
}

-- ##################################################
-- ## AUTODELETE
-- ##################################################

local AutoTrash = CreateFrame("Frame", "AutoTrashFrame", UIParent)
AutoTrash:RegisterEvent("ITEM_PUSH")

AutoTrash:SetScript("OnEvent", function()
    AutoTrash.active = true
    AutoTrash:Show()
end)

AutoTrash:SetScript("OnUpdate", function()
    if (this.nextScan or 0) > GetTime() then return end
    this.nextScan = GetTime() + 0.15

    for bagIndex = 0, 4 do
        for slotIndex = 1, GetContainerNumSlots(bagIndex) do
            local link = GetContainerItemLink(bagIndex, slotIndex)
            if link then
                local _, _, itemString = string.find(link, "(item:%d+:%d+:%d+:%d+)")
                local itemName = itemString and GetItemInfo(itemString)
                if itemName then
                    local lowerName = string.lower(itemName)

                    -- loop through trash list
                    for n = 1, table.getn(LootSense_delete) do
                        local data = LootSense_delete[n]
                        if data.name and string.lower(data.name) == lowerName then
                            ClearCursor()
                            PickupContainerItem(bagIndex, slotIndex)
                            DeleteCursorItem()
                            return
                        end
                    end
                end
            end
        end
    end

    this:Hide()
end)



-- ##################################################
-- ## SCROLLABLE LootSense LISTA MED ICON + RARITY
-- ##################################################
LootSenseList = CreateFrame("Frame", "LootSenseList", UIParent)
LootSenseList:SetWidth(380)
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

-- Stäng-knapp
LootSenseList.closeBtn = CreateFrame("Button", nil, LootSenseList, "UIPanelButtonTemplate")
LootSenseList.closeBtn:SetWidth(24)
LootSenseList.closeBtn:SetHeight(24)
LootSenseList.closeBtn:SetText("X")
LootSenseList.closeBtn:SetPoint("TOPRIGHT", -5, -5)
LootSenseList.closeBtn:SetScript("OnClick", function()
    LootSenseList:Hide()
end)

-- === AUTO DELETE CHECKBOXAR ===
-- Grå items
LootSenseList.grayCheck = CreateFrame("CheckButton", "LootSenseGrayCheck", LootSenseList, "UICheckButtonTemplate")
LootSenseList.grayCheck:SetPoint("TOPLEFT", 10, -10)
LootSenseList.grayCheck:SetWidth(24)
LootSenseList.grayCheck:SetHeight(24)
LootSenseList.grayCheck.text = LootSenseList.grayCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
LootSenseList.grayCheck.text:SetPoint("LEFT", LootSenseList.grayCheck, "RIGHT", 4, 0)
LootSenseList.grayCheck.text:SetText("Auto delete gray items")

-- Grön items
LootSenseList.greenCheck = CreateFrame("CheckButton", "LootSenseGreenCheck", LootSenseList, "UICheckButtonTemplate")
LootSenseList.greenCheck:SetPoint("TOPLEFT", 10, -35)
LootSenseList.greenCheck:SetWidth(24)
LootSenseList.greenCheck:SetHeight(24)
LootSenseList.greenCheck.text = LootSenseList.greenCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
LootSenseList.greenCheck.text:SetPoint("LEFT", LootSenseList.greenCheck, "RIGHT", 4, 0)
LootSenseList.greenCheck.text:SetText("Auto delete green items")

-- Initiera variabler om de saknas
if not LootSense_autoDeleteGray then LootSense_autoDeleteGray = "off" end
if not LootSense_autoDeleteGreen then LootSense_autoDeleteGreen = "off" end

-- Ställ in checkboxarna efter sparade värden
LootSenseList.grayCheck:SetChecked(LootSense_autoDeleteGray == "on")
LootSenseList.greenCheck:SetChecked(LootSense_autoDeleteGreen == "on")

-- Klick-händelser
LootSenseList.grayCheck:SetScript("OnClick", function()
    if this:GetChecked() then
        LootSense_autoDeleteGray = "on"
        DEFAULT_CHAT_FRAME:AddMessage("|cffaaaaaa[LootSense]|r Auto-delete gray items: |cff33ff33ON|r")
    else
        LootSense_autoDeleteGray = "off"
        DEFAULT_CHAT_FRAME:AddMessage("|cffaaaaaa[LootSense]|r Auto-delete gray items: |cffff3333OFF|r")
    end
end)

LootSenseList.greenCheck:SetScript("OnClick", function()
    if this:GetChecked() then
        LootSense_autoDeleteGreen = "on"
        DEFAULT_CHAT_FRAME:AddMessage("|cff55ff55[LootSense]|r Auto-delete green items: |cff33ff33ON|r")
    else
        LootSense_autoDeleteGreen = "off"
        DEFAULT_CHAT_FRAME:AddMessage("|cff55ff55[LootSense]|r Auto-delete green items: |cffff3333OFF|r")
    end
end)


-- återanvänd Loot Helper’s colors-tabell
local qualityColors = colors  
local listItems = {}  -- håller alla item frames

local function tableSize(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

local function RefreshLootSenseList()
    local searchText = string.lower(LootSenseList.search:GetText() or "")

    -- rensa gamla frames
    for i,v in pairs(listItems) do
        if v.frame then v.frame:Hide() v.frame:SetParent(nil) end
    end
    listItems = {}

    local itemHeight = 36
    local spacing = 5
    local width = LootSenseList.scroll:GetWidth() - 20
    local index = 1

local function addSection(list, listName)
    for i = 1, table.getn(list) do
        local entry = list[i]   -- entry now has .id and .name
        local itemID = entry.id
        local itemName = entry.name

        local _, itemLink, itemRarity, _, _, _, _, _, itemEquipLoc = GetItemInfo(itemID)
        local icon = "Interface\\Icons\\INV_Misc_QuestionMark"
        if itemEquipLoc then icon = itemEquipLoc end

        -- filter by search text
        if searchText == "" or string.find(string.lower(itemName), searchText) then
            local frame = CreateFrame("Frame", nil, LootSenseList.child)
            frame:SetWidth(width)
            frame:SetHeight(itemHeight)
            frame:SetPoint("TOPLEFT", 0, -((index-1)*(itemHeight+spacing)))

            -- icon
            frame.icon = frame:CreateTexture(nil, "OVERLAY")
            frame.icon:SetWidth(28)
            frame.icon:SetHeight(28)
            frame.icon:SetPoint("LEFT", frame, "LEFT", 5, 0)
            frame.icon:SetTexture(icon)

            -- text
            frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            frame.text:SetPoint("LEFT", frame.icon, "RIGHT", 5, 0)
            frame.text:SetText(itemName)
            if itemRarity and qualityColors[itemRarity] then
                frame.text:SetTextColor(unpack(qualityColors[itemRarity]))
            else
                frame.text:SetTextColor(1,1,1)
            end

            -- list type text (delete/keep/vendor)
            frame.listType = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            frame.listType:SetPoint("LEFT", frame.text, "RIGHT", 10, 0)
            frame.listType:SetText("(" .. listName .. ")")
            frame.listType:SetTextColor(1, 1, 1) -- vit färg

            -- remove button
            frame.remove = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
            frame.remove:SetWidth(20)
            frame.remove:SetHeight(20)
            frame.remove:SetText("X")
            frame.remove:SetPoint("RIGHT", frame, "RIGHT", -5, 0)
            frame.remove:SetScript("OnClick", function()
                -- Find and remove the correct entry by itemID
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

    -- justera scrollchild
    local totalHeight = index * (itemHeight + spacing)
    local visibleHeight = LootSenseList.scroll:GetHeight()
    LootSenseList.child:SetHeight(math.max(totalHeight, visibleHeight + 1))
    LootSenseList.scroll:UpdateScrollChildRect()
    LootSenseList.scroll:SetVerticalScroll(0)
end


-- ##################################################
-- ## FILTERKNAPPAR HÖGST UPP
-- ##################################################
local buttonWidth = 80
local buttonHeight = 20
local spacing = 5
local xOffset = 10
local yOffset = -30  -- under titel, men ovanför scroll

local function createFilterButton(parent, label, filter)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetWidth(buttonWidth)
    btn:SetHeight(buttonHeight)
    btn:SetText(label)
    btn:SetPoint("TOPLEFT", xOffset, yOffset)
    xOffset = xOffset + buttonWidth + spacing

    btn:SetScript("OnClick", function()
        LootSenseList.filter = filter
        RefreshLootSenseList()
    end)
    return btn
end

-- skapa knappar i LootSenseList, inte scroll
createFilterButton(LootSenseList, "Keep", "keep")
createFilterButton(LootSenseList, "Vendor", "vendor")
createFilterButton(LootSenseList, "Delete", "delete")
createFilterButton(LootSenseList, "All", "all")


-- default filter
LootSenseList.filter = "all"






-- titel
LootSenseList.title = LootSenseList:CreateFontString(nil, "OVERLAY", "GameFontNormal")
LootSenseList.title:SetPoint("TOP", 0, -10)
LootSenseList.title:SetText("LootSense Lists")

-- sökfält
-- EditBox
LootSenseList.search = CreateFrame("EditBox", nil, LootSenseList)
LootSenseList.search:SetPoint("TOPLEFT", 10, -50)
LootSenseList.search:SetWidth(350)
LootSenseList.search:SetHeight(20)
LootSenseList.search:SetFontObject(GameFontHighlight)
LootSenseList.search:SetAutoFocus(false)
LootSenseList.search:SetText("")

-- bakgrund
LootSenseList.search.bg = LootSenseList.search:CreateTexture(nil, "BACKGROUND")
LootSenseList.search.bg:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
LootSenseList.search.bg:SetVertexColor(0,0,0,0.5)  -- svart med 50% alpha
LootSenseList.search.bg:SetAllPoints(LootSenseList.search)

-- placeholder-text
LootSenseList.search.placeholder = LootSenseList.search:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
LootSenseList.search.placeholder:SetPoint("LEFT", 5, 0)
LootSenseList.search.placeholder:SetText("Search...")
LootSenseList.search.placeholder:SetTextColor(0.7,0.7,0.7,1)

LootSenseList.search:SetScript("OnEnterPressed", function() LootSenseList.search:ClearFocus() end)
LootSenseList.search:SetScript("OnTextChanged", function()
    if this:GetText() == "" then
        LootSenseList.search.placeholder:Show()
    else
        LootSenseList.search.placeholder:Hide()
    end
    RefreshLootSenseList()
end)


-- scroll frame
LootSenseList.scroll = CreateFrame("ScrollFrame", "LootSenseScrollFrame", LootSenseList, "UIPanelScrollFrameTemplate")
LootSenseList.scroll:SetPoint("TOPLEFT", 10, -85)
LootSenseList.scroll:SetPoint("BOTTOMRIGHT", -30, 10)

-- scroll child
LootSenseList.child = CreateFrame("Frame", "LootSenseScrollChild", LootSenseList.scroll)
LootSenseList.child:SetWidth(1)
LootSenseList.child:SetHeight(1)
LootSenseList.scroll:SetScrollChild(LootSenseList.child)

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
    button:SetScript("OnEnter", function()
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:SetText(text)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
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
-- ## CREATE BUTTON ACTION (SAVES ITEMID)
-- ##################################################
local function createButtonAction(slot, action, name, itemID, itemFrame)
    return function()
        local entry = { id = itemID, name = name }

        if action == "keep" then
            table.insert(LootSense_keep, entry)
            LootSlot(slot)
            DEFAULT_CHAT_FRAME:AddMessage("Keep: "..name.." (ID: "..itemID..")")
        elseif action == "vendor" then
            table.insert(LootSense_vendor, entry)
            LootSlot(slot)
            DEFAULT_CHAT_FRAME:AddMessage("Vendor: "..name.." (ID: "..itemID..")")
        elseif action == "throw" then
            table.insert(LootSense_delete, entry)
            LootSlot(slot)
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
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccUsage:|r /sk list")
    end
end

-- ##################################################
-- ## LOOT HELPER FRAME (WoW-style)
-- ##################################################
local LootHelperFrame = CreateFrame("Frame", "ShaguLootHelper", UIParent)
LootHelperFrame:SetWidth(320)
LootHelperFrame:SetHeight(200)
LootHelperFrame:SetPoint("TOPLEFT", LootFrame, "TOPRIGHT", 10, 0)
LootHelperFrame:Hide()
-- Gör fönstret flyttbart
LootHelperFrame:SetMovable(true)
LootHelperFrame:EnableMouse(true)
LootHelperFrame:RegisterForDrag("LeftButton")
LootHelperFrame:SetScript("OnDragStart", function() this:StartMoving() end)
LootHelperFrame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
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
LootHelperFrame.settingsBtn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(LootHelperFrame.settingsBtn, "ANCHOR_RIGHT")
    GameTooltip:SetText("Manage", 1, 1, 1)
    GameTooltip:Show()
end)

LootHelperFrame.settingsBtn:SetScript("OnLeave", function()
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

local function UpdateLootHelperVisibility()
    if LootHelperFrame.count == 0 then
        LootHelperFrame:Hide()
    else
        LootHelperFrame:Show()
    end
end

local function CreateItemRow(parent, slot, texture, name, quality, itemLink, itemID)
    local row = CreateFrame("Frame", nil, parent)
    row:SetWidth(300)
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
    row.textBtn:SetWidth(120)  -- Justera bredd efter behov
    row.textBtn:SetHeight(18)
    
    -- text
    row.text = row.textBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.text:SetPoint("LEFT", row.textBtn, "LEFT", 0, 0)
    row.text:SetText(name or "?")
    if quality and colors[quality] then
        row.text:SetTextColor(unpack(colors[quality]))
    else
        row.text:SetTextColor(1,1,1)
    end

    -- Tooltip för item text - använd samma metod som lootfönstret
    row.textBtn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetLootItem(slot)  -- Använd loot slot istället för hyperlink
        GameTooltip:Show()
        row.highlight:Show() -- Visa highlight
    end)
    
    row.textBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
        row.highlight:Hide() -- Dölj highlight
    end)
    
    row.textBtn:SetScript("OnClick", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetLootItem(slot)
        GameTooltip:Show()
    end)

    -- Hovra över hela raden (för knapparna)
    row:SetScript("OnEnter", function()
        row.highlight:Show()
    end)
    
    row:SetScript("OnLeave", function()
        row.highlight:Hide()
    end)

    -- ##################################################
    -- ## MAKE BUTTON
    -- ##################################################
    local function makeBtn(icon, tooltip, action, xoff, itemID)
        local btn = CreateFrame("Button", nil, row)
        btn:SetWidth(22)
        btn:SetHeight(22)
        btn:SetPoint("LEFT", row, "LEFT", xoff, 0)
        btn:SetNormalTexture(icon)
        btn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        
        -- Tooltip för knapparna
        btn:SetScript("OnEnter", function()
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            GameTooltip:SetText(tooltip)
            GameTooltip:Show()
            row.highlight:Show() -- Visa highlight även när man hovrar över knappar
        end)
        
        btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
            row.highlight:Hide()
        end)

btn:SetScript("OnClick", function()
    createButtonAction(slot, action, name, itemID, row)()
    
    -- Aktivera autodelete OM det är delete-knappen
    if action == "throw" then
        AutoTrash:Show()
    end
    
    row:Hide()
    -- ta bort från loot helper listan
    for i=1, table.getn(LootHelperFrame.items) do
        if LootHelperFrame.items[i] == row then
            table.remove(LootHelperFrame.items, i)
            LootHelperFrame.count = LootHelperFrame.count - 1
            break
        end
    end
    UpdateLootHelperVisibility()
end)
        
        return btn
    end

    -- knappar: Keep/Vendor/Delete/Ignore
    row.keep   = makeBtn("Interface\\Buttons\\Button-Backpack-Up",   "Keep this item",   "keep",   180, itemID)
    row.vendor = makeBtn("Interface\\Buttons\\UI-GroupLoot-Coin-Up",  "Vendor this item", "vendor", 210, itemID)
    row.throw  = makeBtn("Interface\\Buttons\\UI-GroupLoot-Pass-Up",   "Delete this item", "throw",  240, itemID)
    row.ignore = makeBtn("Interface\\Buttons\\UI-Panel-MinimizeButton-Up", "Ignore this item", "ignore", 270, itemID)

    return row
end
-- ##################################################
-- ## LOOT WINDOW INTEGRATION WITH ITEMID
-- ##################################################
local lootFrame = CreateFrame("Frame")
lootFrame:RegisterEvent("LOOT_OPENED")
lootFrame:RegisterEvent("LOOT_CLOSED")
lootFrame:SetScript("OnEvent", function()
    if event == "LOOT_OPENED" then
        ClearLootHelper()
        local numLoot = GetNumLootItems()
        local lastRow = nil

        -- helper to check if itemID exists in your new tables
        local function isInList(itemID, list)
            for i=1, table.getn(list) do
                if list[i].id == itemID then
                    return true
                end
            end
            return false
        end

        for slot = 1, numLoot do
            local texture, itemName, quantity, quality = GetLootSlotInfo(slot)
            local itemLink = GetLootSlotLink(slot)

            if itemLink then
                local name = GetItemInfo(itemLink) or itemName
                if not name then name = itemName end

				-- kolla om automatisk radering är aktiverad
				if LootSense_autoDeleteGray == "on" or LootSense_autoDeleteGreen == "on" then
					-- grå items (poor quality)
					if LootSense_autoDeleteGray == "on" and quality == 0 then
						table.insert(LootSense_delete, { id = itemID, name = name })
						LootSlot(slot)
						DEFAULT_CHAT_FRAME:AddMessage("|cffff5555Auto-deleted gray:|r " .. name)
						return
					end

					-- gröna items (uncommon quality)
					if LootSense_autoDeleteGreen == "on" and quality == 2 then
						table.insert(LootSense_delete, { id = itemID, name = name })
						LootSlot(slot)
						DEFAULT_CHAT_FRAME:AddMessage("|cff55ff55Auto-deleted green:|r " .. name)
						return
					end
				end


                -- extract numeric itemID
                local itemID
                local _, _, id = string.find(itemLink, "item:(%d+):")
                if id then itemID = tonumber(id) end

                if itemID and not (isInList(itemID, LootSense_keep) or isInList(itemID, LootSense_vendor) or isInList(itemID, LootSense_delete)) then
                    local row = CreateItemRow(LootHelperFrame, slot, texture, name, quality, itemLink, itemID)
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

        local h = 40 + (LootHelperFrame.count * 37)
        LootHelperFrame:SetHeight(h)
        UpdateLootHelperVisibility()

    --elseif event == "LOOT_CLOSED" then
    --    ClearLootHelper()
    end
end)


-- ##################################################
-- ## AutoSell
-- ##################################################

local AutoSell = CreateFrame("Frame")
AutoSell:RegisterEvent("MERCHANT_SHOW")
AutoSell:RegisterEvent("MERCHANT_CLOSED")

-- internal state
AutoSell.active = false
AutoSell.lastCheck = 0

-- event handling
AutoSell:SetScript("OnEvent", function()
    if event == "MERCHANT_SHOW" then
        AutoSell.active = true
        AutoSell:Show()
    elseif event == "MERCHANT_CLOSED" then
        AutoSell.active = false
        AutoSell:Hide()
    end
end)

-- main loop
AutoSell:SetScript("OnUpdate", function()
    -- tick timer, check every 0.1s
    if GetTime() < AutoSell.lastCheck then return end
    AutoSell.lastCheck = GetTime() + 0.1

    if not AutoSell.active then return end

    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local _, _, rawLink = string.find(link, "(item:%d+:%d+:%d+:%d+)")
                local itemName = rawLink and GetItemInfo(rawLink)
                if itemName then
                    itemName = string.lower(itemName)
                    for i = 1, table.getn(LootSense_vendor) do
                        local entry = LootSense_vendor[i]
                        if entry.name and string.lower(entry.name) == itemName then
                            ClearCursor()
                            UseContainerItem(bag, slot)
                            return
                        end
                    end
                end
            end
        end
    end

    -- hide when done selling
    AutoSell:Hide()
end)





