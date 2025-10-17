

local gfind = string.gmatch or string.gfind

LootSense_keep   = LootSense_keep   or {}
LootSense_vendor = LootSense_vendor or {}
LootSense_delete = LootSense_delete or {}
local versionNumber = "1.0.0"
local colors = {
  [0] = {0.6, 0.6, 0.6},   
  [1] = {1, 1, 1},         
  [2] = {0, 1, 0},         
  [3] = {0, 0.44, 0.87},   
  [4] = {0.64, 0.21, 0.93},
}

local loginFrame = CreateFrame("Frame")
loginFrame:RegisterEvent("PLAYER_LOGIN")
loginFrame:SetScript("OnEvent", function(self, event)
    DEFAULT_CHAT_FRAME:AddMessage("LootSense [" .. versionNumber .. "]|cff00FF00 loaded|cffffffff")
end)



if not LootSense_MinimapPos then LootSense_MinimapPos = 45 end

local buttonSize = 32
local radius = 80

LootSense_MinimapButton = CreateFrame("Button", "LootSense_MinimapButton", Minimap)
LootSense_MinimapButton:SetWidth(buttonSize)
LootSense_MinimapButton:SetHeight(buttonSize)
LootSense_MinimapButton:SetFrameStrata("MEDIUM")

local texture = LootSense_MinimapButton:CreateTexture(nil, "BACKGROUND")
texture:SetTexture("Interface\\AddOns\\LootSense\\image\\minimap.tga")
texture:SetAllPoints(LootSense_MinimapButton)
LootSense_MinimapButton.texture = texture

LootSense_MinimapButton:SetNormalTexture("Interface\\Minimap\\UI-Minimap-Background")
LootSense_MinimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
LootSense_MinimapButton:GetHighlightTexture():SetAlpha(0.6)

LootSense_MinimapButton:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_LEFT")
    GameTooltip:AddLine("|cff33ffccLoot|cffffffffSense")
    GameTooltip:AddLine("Left-click: Open LootSense", 1,1,1)
    GameTooltip:AddLine("Right-click + drag: Move button", 0.7,0.7,0.7)
    GameTooltip:Show()
end)
LootSense_MinimapButton:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

local function UpdateMinimapButtonPosition()
    local angle = LootSense_MinimapPos
    local x = radius * math.cos(angle)
    local y = radius * math.sin(angle)
    LootSense_MinimapButton:ClearAllPoints()
    LootSense_MinimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

LootSense_MinimapButton:SetScript("OnClick", function()
    if arg1 == "LeftButton" then
        if LootSenseList:IsShown() then
            LootSenseList:Hide()
        else
            LootSenseList:Show()
        end
    end
end)

LootSense_MinimapButton:SetScript("OnMouseDown", function()
    if arg1 == "RightButton" then
        this.isDragging = true
        this:SetScript("OnUpdate", function()
            if this.isDragging then
                local mx, my = Minimap:GetCenter()
                local px, py = GetCursorPosition()
                local scale = Minimap:GetEffectiveScale()
                px, py = px / scale, py / scale
                local angle = math.atan2(py - my, px - mx)
                LootSense_MinimapPos = angle
                UpdateMinimapButtonPosition()
            end
        end)
    end
end)

LootSense_MinimapButton:SetScript("OnMouseUp", function()
    this.isDragging = false
    this:SetScript("OnUpdate", nil)
end)

local minimapInit = CreateFrame("Frame")
minimapInit:RegisterEvent("ADDON_LOADED")
minimapInit:SetScript("OnEvent", function()
    if arg1 == "LootSense" then
        UpdateMinimapButtonPosition()
    end
end)






local AutoTrash = CreateFrame("Frame", "AutoTrashFrame", UIParent)
AutoTrash:RegisterEvent("ITEM_PUSH")

AutoTrash:SetScript("OnEvent", function()
	if LootSense_paused then return end
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
LootSenseList:SetMovable(true)
LootSenseList:EnableMouse(true)
LootSenseList:RegisterForDrag("LeftButton")
LootSenseList:SetScript("OnDragStart", function() this:StartMoving() end)
LootSenseList:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)

LootSenseList.closeBtn = CreateFrame("Button", nil, LootSenseList, "UIPanelButtonTemplate")
LootSenseList.closeBtn:SetWidth(24)
LootSenseList.closeBtn:SetHeight(24)
LootSenseList.closeBtn:SetText("X")
LootSenseList.closeBtn:SetPoint("TOPRIGHT", -5, -5)
LootSenseList.closeBtn:SetScript("OnClick", function()
    LootSenseList:Hide()
end)

LootSenseList.tabs = {}
LootSenseList.activeTab = "manage"

function SwitchTab(tabName)
 
  for _, tab in pairs(LootSenseList.tabs) do
    PanelTemplates_DeselectTab(tab)
  end

 
  LootSenseList.manageContent:Hide()
  LootSenseList.autoDeleteContent:Hide()
  LootSenseList.settingsContent:Hide()

 
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

  else
    LootSenseList.title:SetText("LootSense Lists")
  end
end



local function ResizeTab(tab)
    local textWidth = tab:GetFontString():GetWidth()
    tab:SetWidth(textWidth + 30)
end

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

LootSenseList.tabs.settings = CreateFrame("Button", "LootSenseTabSettings", LootSenseList, "CharacterFrameTabButtonTemplate")
LootSenseList.tabs.settings:SetText("Settings")
LootSenseList.tabs.settings.tabName = "LootSenseTabSettings"
LootSenseList.tabs.settings:SetID(3)
LootSenseList.tabs.settings:SetPoint("LEFT", LootSenseList.tabs.autoDelete, "RIGHT", -15, 0)
LootSenseList.tabs.settings:SetScript("OnClick", function() SwitchTab("settings") end)
ResizeTab(LootSenseList.tabs.settings)



LootSenseList.settingsContent = CreateFrame("Frame", nil, LootSenseList)
LootSenseList.settingsContent:SetPoint("TOPLEFT", 10, -40)
LootSenseList.settingsContent:SetPoint("BOTTOMRIGHT", -10, 10)
LootSenseList.settingsContent:Hide()


LootSenseList.pauseCheck = CreateFrame("CheckButton", "LootSensePauseCheck", LootSenseList.settingsContent, "UICheckButtonTemplate")
LootSenseList.pauseCheck:SetPoint("TOPLEFT", 20, -50)
LootSenseList.pauseCheck:SetWidth(24)
LootSenseList.pauseCheck:SetHeight(24)
LootSenseList.pauseCheck.text = LootSenseList.pauseCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
LootSenseList.pauseCheck.text:SetPoint("LEFT", LootSenseList.pauseCheck, "RIGHT", 4, 0)
LootSenseList.pauseCheck.text:SetText("Pause LootSense")


LootSenseList.pauseCheck:SetScript("OnClick", function()
	LootSense_paused = this:GetChecked()
	if LootSense_paused then
		DEFAULT_CHAT_FRAME:AddMessage("|cffaaaaaa[LootSense]|r Addon paused")
	else
		DEFAULT_CHAT_FRAME:AddMessage("|cffaaaaaa[LootSense]|r Addon resumed")
	end
end)

LootSenseList.autoDeleteContent = CreateFrame("Frame", nil, LootSenseList)
LootSenseList.autoDeleteContent:SetPoint("TOPLEFT", 10, -40)
LootSenseList.autoDeleteContent:SetPoint("BOTTOMRIGHT", -10, 10)
LootSenseList.autoDeleteContent:Hide()

LootSenseList.autoDeleteTitle = LootSenseList.autoDeleteContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
LootSenseList.autoDeleteTitle:SetPoint("TOP", 0, -15)

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


LootSenseList.grayCheck = CreateFrame("CheckButton", "LootSenseGrayCheck", LootSenseList.autoDeleteContent, "UICheckButtonTemplate")
LootSenseList.grayCheck:SetPoint("TOPLEFT", 20, -50)
LootSenseList.grayCheck:SetWidth(24)
LootSenseList.grayCheck:SetHeight(24)
LootSenseList.grayCheck.text = LootSenseList.grayCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
LootSenseList.grayCheck.text:SetPoint("LEFT", LootSenseList.grayCheck, "RIGHT", 4, 0)
LootSenseList.grayCheck.text:SetText("Auto add gray items to delete list")
AddTooltip(LootSenseList.grayCheck, "|cff9d9d9dGray items|r", "Automatically adds poor-quality (gray) items to the delete list.")

LootSenseList.whiteCheck = CreateFrame("CheckButton", "LootSenseWhiteCheck", LootSenseList.autoDeleteContent, "UICheckButtonTemplate")
LootSenseList.whiteCheck:SetPoint("TOPLEFT", LootSenseList.grayCheck, "BOTTOMLEFT", 0, -10)
LootSenseList.whiteCheck:SetWidth(24)
LootSenseList.whiteCheck:SetHeight(24)
LootSenseList.whiteCheck.text = LootSenseList.whiteCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
LootSenseList.whiteCheck.text:SetPoint("LEFT", LootSenseList.whiteCheck, "RIGHT", 4, 0)
LootSenseList.whiteCheck.text:SetText("Auto add white items to delete list")
AddTooltip(LootSenseList.whiteCheck, "|cffffffffWhite items|r", "Automatically adds common-quality (white) items to the delete list.")

LootSenseList.greenCheck = CreateFrame("CheckButton", "LootSenseGreenCheck", LootSenseList.autoDeleteContent, "UICheckButtonTemplate")
LootSenseList.greenCheck:SetPoint("TOPLEFT", LootSenseList.whiteCheck, "BOTTOMLEFT", 0, -10)
LootSenseList.greenCheck:SetWidth(24)
LootSenseList.greenCheck:SetHeight(24)
LootSenseList.greenCheck.text = LootSenseList.greenCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
LootSenseList.greenCheck.text:SetPoint("LEFT", LootSenseList.greenCheck, "RIGHT", 4, 0)
LootSenseList.greenCheck.text:SetText("Auto add green items to delete list")
AddTooltip(LootSenseList.greenCheck, "|cff1eff00Green items|r", "Automatically adds uncommon-quality (green) items to the delete list.")

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




	LootSenseList.grayCheck:SetChecked(LootSense_autoDelete.gray)
	LootSenseList.whiteCheck:SetChecked(LootSense_autoDelete.white)
	LootSenseList.greenCheck:SetChecked(LootSense_autoDelete.green)
	LootSenseList.blueCheck:SetChecked(LootSense_autoDelete.blue)
	LootSenseList.pauseCheck:SetChecked(LootSense_paused)
end)



LootSenseList.grayCheck:SetScript("OnClick", function()
    LootSense_autoDelete.gray = this:GetChecked()
    DEFAULT_CHAT_FRAME:AddMessage("|cffaaaaaa[LootSense]|r Auto-delete gray items: " .. (this:GetChecked() and "|cff33ff33ON|r" or "|cffff3333OFF|r"))
end)

LootSenseList.whiteCheck:SetScript("OnClick", function()
    LootSense_autoDelete.white = this:GetChecked()
    DEFAULT_CHAT_FRAME:AddMessage("|cffffffff[LootSense]|r Auto-delete white items: " .. (this:GetChecked() and "|cff33ff33ON|r" or "|cffff3333OFF|r"))
end)

LootSenseList.greenCheck:SetScript("OnClick", function()
    LootSense_autoDelete.green = this:GetChecked()
    DEFAULT_CHAT_FRAME:AddMessage("|cff55ff55[LootSense]|r Auto-delete green items: " .. (this:GetChecked() and "|cff33ff33ON|r" or "|cffff3333OFF|r"))
end)

LootSenseList.blueCheck:SetScript("OnClick", function()
    LootSense_autoDelete.blue = this:GetChecked()
    DEFAULT_CHAT_FRAME:AddMessage("|cff0070dd[LootSense]|r Auto-delete blue items: " .. (this:GetChecked() and "|cff33ff33ON|r" or "|cffff3333OFF|r"))
end)


LootSenseList.manageContent = CreateFrame("Frame", nil, LootSenseList)
LootSenseList.manageContent:SetPoint("TOPLEFT", 10, -20)
LootSenseList.manageContent:SetPoint("BOTTOMRIGHT", -10, 10)

LootSenseList.title = LootSenseList:CreateFontString(nil, "OVERLAY", "GameFontNormal")
LootSenseList.title:SetPoint("TOP", LootSenseList, "TOP", 0, -8)
LootSenseList.title:SetText("LootSense Lists")

local qualityColors = colors  
local listItems = {}

local function tableSize(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

local function RefreshLootSenseList()
    local searchText = string.lower(LootSenseList.search:GetText() or "")

   
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
            local entry = list[i]
            local itemID = entry.id
            local itemName = entry.name

            local _, _, itemRarity, _, _, _, _, _, itemEquipLoc = GetItemInfo(itemID)
            local icon = "Interface\\Icons\\INV_Misc_QuestionMark"
            if itemEquipLoc then icon = itemEquipLoc end

            if searchText == "" or string.find(string.lower(itemName), searchText) then
                local frame = CreateFrame("Frame", nil, LootSenseList.child)
                frame:SetWidth(width)
                frame:SetHeight(itemHeight)
                frame:SetPoint("TOPLEFT", 0, -((index-1)*(itemHeight+spacing)))

                frame.icon = frame:CreateTexture(nil, "OVERLAY")
                frame.icon:SetWidth(28)
                frame.icon:SetHeight(28)
                frame.icon:SetPoint("LEFT", frame, "LEFT", 5, 0)
                frame.icon:SetTexture(icon)

                frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                frame.text:SetPoint("LEFT", frame.icon, "RIGHT", 5, 0)
                frame.text:SetText(itemName)
                if itemRarity and qualityColors[itemRarity] then
                    frame.text:SetTextColor(unpack(qualityColors[itemRarity]))
                else
                    frame.text:SetTextColor(1,1,1)
                end

                frame.listType = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                frame.listType:SetPoint("LEFT", frame.text, "RIGHT", 10, 0)
                frame.listType:SetText("(" .. listName .. ")")
                frame.listType:SetTextColor(1,1,1)

                frame.remove = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
                frame.remove:SetWidth(20)
                frame.remove:SetHeight(20)
                frame.remove:SetText("X")
                frame.remove:SetPoint("RIGHT", frame, "RIGHT", -5, 0)
                frame.remove:SetScript("OnClick", function()
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

   
    if LootSenseList.filter == "all" or LootSenseList.filter == "keep" then
        addSection(LootSense_keep, "Keep")
    end
    if LootSenseList.filter == "all" or LootSenseList.filter == "vendor" then
        addSection(LootSense_vendor, "Vendor")
    end
    if LootSenseList.filter == "all" or LootSenseList.filter == "delete" then
        addSection(LootSense_delete, "Delete")
    end

   
    local totalHeight = index * (itemHeight + spacing)
    local visibleHeight = LootSenseList.scroll:GetHeight()
    LootSenseList.child:SetHeight(math.max(totalHeight, visibleHeight + 1))
    LootSenseList.scroll:UpdateScrollChildRect()
    LootSenseList.scroll:SetVerticalScroll(0)
end

local buttonWidth = 80
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

    btn:SetScript("OnClick", function()
        LootSenseList.filter = filter
        RefreshLootSenseList()
    end)
    return btn
end

createFilterButton(LootSenseList.manageContent, "Keep", "keep")
createFilterButton(LootSenseList.manageContent, "Vendor", "vendor")
createFilterButton(LootSenseList.manageContent, "Delete", "delete")
createFilterButton(LootSenseList.manageContent, "All", "all")

LootSenseList.search = CreateFrame("EditBox", nil, LootSenseList.manageContent)
LootSenseList.search:SetPoint("TOPLEFT", 10, -10)
LootSenseList.search:SetWidth(350)
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

LootSenseList.search:SetScript("OnEnterPressed", function() LootSenseList.search:ClearFocus() end)
LootSenseList.search:SetScript("OnTextChanged", function()
    if LootSenseList.search:GetText() == "" then
        LootSenseList.search.placeholder:Show()
    else
        LootSenseList.search.placeholder:Hide()
    end
    RefreshLootSenseList()
end)

LootSenseList.scroll = CreateFrame("ScrollFrame", "LootSenseScrollFrame", LootSenseList.manageContent, "UIPanelScrollFrameTemplate")
LootSenseList.scroll:SetPoint("TOPLEFT", 10, -65)
LootSenseList.scroll:SetPoint("BOTTOMRIGHT", -30, 10)

LootSenseList.child = CreateFrame("Frame", "LootSenseScrollChild", LootSenseList.scroll)
LootSenseList.child:SetWidth(1)
LootSenseList.child:SetHeight(1)
LootSenseList.scroll:SetScrollChild(LootSenseList.child)

LootSenseList.filter = "all"
SwitchTab("manage")
RefreshLootSenseList()


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

local lootButtons = {} 

local function ClearLootButtons()
    for slot, frame in pairs(lootButtons) do
        if frame then frame:Hide() frame:SetParent(nil) end
        lootButtons[slot] = nil
    end
end

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





SLASH_LootSenseLIST1 = "/ls"
SlashCmdList["LootSenseLIST"] = function(msg)
    local cmd = string.lower(msg or "")
    if cmd == "list" then
        if LootSenseList:IsShown() then
            LootSenseList:Hide()
        else
            LootSenseList.search:SetText("")
            RefreshLootSenseList()          
            LootSenseList:Show()
        end
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccUsage:|r /sl list")
    end
end

local LootHelperFrame = CreateFrame("Frame", "ShaguLootHelper", UIParent)
LootHelperFrame:SetWidth(320)
LootHelperFrame:SetHeight(200)
LootHelperFrame:SetPoint("TOPLEFT", LootFrame, "TOPRIGHT", 10, 0)
LootHelperFrame:Hide()
LootHelperFrame:SetMovable(true)
LootHelperFrame:EnableMouse(true)
LootHelperFrame:RegisterForDrag("LeftButton")
LootHelperFrame:SetScript("OnDragStart", function() this:StartMoving() end)
LootHelperFrame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
LootHelperFrame.settingsBtn = CreateFrame("Button", nil, LootHelperFrame)
LootHelperFrame.settingsBtn:SetWidth(20)
LootHelperFrame.settingsBtn:SetHeight(20)
LootHelperFrame.settingsBtn:SetPoint("TOPRIGHT", -8, -8)

LootHelperFrame.settingsBtn.icon = LootHelperFrame.settingsBtn:CreateTexture(nil, "BACKGROUND")
LootHelperFrame.settingsBtn.icon:SetAllPoints()
LootHelperFrame.settingsBtn.icon:SetTexture("Interface\\Icons\\INV_Gizmo_01") 

LootHelperFrame.settingsBtn:SetScript("OnClick", function()
    if LootSenseList:IsShown() then
        LootSenseList:Hide()
    else
        LootSenseList:Show()
    end
end)

LootHelperFrame.settingsBtn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(LootHelperFrame.settingsBtn, "ANCHOR_RIGHT")
    GameTooltip:SetText("Manage", 1, 1, 1)
    GameTooltip:Show()
end)

LootHelperFrame.settingsBtn:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)


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

   
    row.highlight = row:CreateTexture(nil, "BACKGROUND")
    row.highlight:SetAllPoints(row)
    row.highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    row.highlight:SetBlendMode("ADD")
    row.highlight:SetAlpha(0.3)
    row.highlight:Hide()

   
    row.icon = row:CreateTexture(nil, "OVERLAY")
    row.icon:SetWidth(18)
    row.icon:SetHeight(18)
    row.icon:SetPoint("LEFT", row, "LEFT", 5, 0)
    row.icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")

   
    row.textBtn = CreateFrame("Button", nil, row)
    row.textBtn:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
    row.textBtn:SetWidth(120) 
    row.textBtn:SetHeight(18)
    
   
    row.text = row.textBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.text:SetPoint("LEFT", row.textBtn, "LEFT", 0, 0)
    row.text:SetText(name or "?")
    if quality and colors[quality] then
        row.text:SetTextColor(unpack(colors[quality]))
    else
        row.text:SetTextColor(1,1,1)
    end

   
    row.textBtn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetLootItem(slot) 
        GameTooltip:Show()
        row.highlight:Show()
    end)
    
    row.textBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
        row.highlight:Hide()
    end)
    
    row.textBtn:SetScript("OnClick", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetLootItem(slot)
        GameTooltip:Show()
    end)

   
    row:SetScript("OnEnter", function()
        row.highlight:Show()
    end)
    
    row:SetScript("OnLeave", function()
        row.highlight:Hide()
    end)

   
   
   
    local function makeBtn(icon, tooltip, action, xoff, itemID)
        local btn = CreateFrame("Button", nil, row)
        btn:SetWidth(22)
        btn:SetHeight(22)
        btn:SetPoint("LEFT", row, "LEFT", xoff, 0)
        btn:SetNormalTexture(icon)
        btn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        
       
        btn:SetScript("OnEnter", function()
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            GameTooltip:SetText(tooltip)
            GameTooltip:Show()
            row.highlight:Show()
        end)
        
        btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
            row.highlight:Hide()
        end)

btn:SetScript("OnClick", function()
    createButtonAction(slot, action, name, itemID, row)()
    
   
    if action == "throw" then
        AutoTrash:Show()
    end
    
    row:Hide()
   
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

   
    row.keep   = makeBtn("Interface\\Buttons\\Button-Backpack-Up",   "Keep this item",   "keep",   180, itemID)
    row.vendor = makeBtn("Interface\\Buttons\\UI-GroupLoot-Coin-Up",  "Vendor this item", "vendor", 210, itemID)
    row.throw  = makeBtn("Interface\\Buttons\\UI-GroupLoot-Pass-Up",   "Delete this item", "throw",  240, itemID)
    row.ignore = makeBtn("Interface\\Buttons\\UI-Panel-MinimizeButton-Up", "Ignore this item", "ignore", 270, itemID)

    return row
end
local lootFrame = CreateFrame("Frame")
lootFrame:RegisterEvent("LOOT_OPENED")
lootFrame:RegisterEvent("LOOT_CLOSED")

lootFrame:SetScript("OnEvent", function()
    if event == "LOOT_OPENED" then
		if LootSense_paused then return end
        ClearLootHelper()
        local numLoot = GetNumLootItems()
        local lastRow = nil

       
        local function isInList(itemID, list)
            for i = 1, table.getn(list) do
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

               
                local _, _, id = string.find(itemLink, "item:(%d+):")
                local itemID = id and tonumber(id)

               
				if itemID then
					if LootSense_autoDelete.gray and quality == 0 and not isInList(itemID, LootSense_delete) then
						table.insert(LootSense_delete, { id = itemID, name = name })
						LootSlot(slot)
						DEFAULT_CHAT_FRAME:AddMessage("|cffff5555Auto-deleted gray:|r " .. name)
						return
					elseif LootSense_autoDelete.white and quality == 1 and not isInList(itemID, LootSense_delete) then
						table.insert(LootSense_delete, { id = itemID, name = name })
						LootSlot(slot)
						DEFAULT_CHAT_FRAME:AddMessage("|cffffffffAuto-deleted white:|r " .. name)
						return
					elseif LootSense_autoDelete.green and quality == 2 and not isInList(itemID, LootSense_delete) then
						table.insert(LootSense_delete, { id = itemID, name = name })
						LootSlot(slot)
						DEFAULT_CHAT_FRAME:AddMessage("|cff55ff55Auto-deleted green:|r " .. name)
						return
					elseif LootSense_autoDelete.blue and quality == 3 and not isInList(itemID, LootSense_delete) then
						table.insert(LootSense_delete, { id = itemID, name = name })
						LootSlot(slot)
						DEFAULT_CHAT_FRAME:AddMessage("|cff0070ddAuto-deleted blue:|r " .. name)
						return
					end
				end


               
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
   
   
    end
end)




local AutoSell = CreateFrame("Frame")
AutoSell:RegisterEvent("MERCHANT_SHOW")
AutoSell:RegisterEvent("MERCHANT_CLOSED")

AutoSell.active = false
AutoSell.lastCheck = 0

AutoSell:SetScript("OnEvent", function()
    if event == "MERCHANT_SHOW" then
	if LootSense_paused then return end
        AutoSell.active = true
        AutoSell:Show()
    elseif event == "MERCHANT_CLOSED" then
        AutoSell.active = false
        AutoSell:Hide()
    end
end)

AutoSell:SetScript("OnUpdate", function()
   
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

   
    AutoSell:Hide()
end)





