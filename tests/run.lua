local unpack_ = table.unpack or unpack

local ADDON_NAME = "BagPlus_for_EllesmereUI"
local ADDON_PATH = "src/BagPlus_for_EllesmereUI/BagPlus_for_EllesmereUI.lua"

local tests = {}

local function test(name, fn)
    tests[#tests + 1] = { name = name, fn = fn }
end

local function fail(message)
    error(message or "assertion failed", 2)
end

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        fail((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local function assertTrue(value, message)
    if not value then fail(message or "expected truthy value") end
end

local function assertNil(value, message)
    if value ~= nil then fail((message or "expected nil") .. ": got " .. tostring(value)) end
end

local function newRegion()
    local region = {
        shown = true,
        text = "",
        width = 0,
        height = 0,
        alpha = 1,
    }

    function region:Show() self.shown = true end
    function region:Hide() self.shown = false end
    function region:IsShown() return self.shown ~= false end
    function region:SetShown(shown) self.shown = shown and true or false end
    function region:SetText(text)
        if self.requiresFont and text ~= "" and not self.font and not self.fontObject then
            error("FontString:SetText(): Font not set", 2)
        end
        self.text = tostring(text or "")
    end
    function region:GetText() return self.text end
    function region:GetStringWidth() return #(self.text or "") * 6 end
    function region:SetWidth(width) self.width = width end
    function region:GetWidth() return self.width end
    function region:SetHeight(height) self.height = height end
    function region:GetHeight() return self.height end
    function region:SetSize(width, height) self.width, self.height = width, height end
    function region:SetAlpha(alpha) self.alpha = alpha end
    function region:SetFont(font, size, flags) self.font, self.fontSize, self.fontFlags = font, size, flags end
    function region:SetFontObject(fontObject) self.fontObject = fontObject end
    function region:GetFont() return self.font end
    function region:SetTextColor() end
    function region:SetJustifyH() end
    function region:SetJustifyV() end
    function region:SetShadowColor() end
    function region:SetShadowOffset() end
    function region:SetAllPoints(relativeTo) self.allPoints = relativeTo or true end
    function region:SetPoint() end
    function region:ClearAllPoints() end
    function region:SetTexture(texture, hWrap, vWrap)
        self.texture = texture
        self.hWrap = hWrap
        self.vWrap = vWrap
    end
    function region:SetTexCoord(...)
        self.texCoord = { ... }
    end
    function region:AddMaskTexture(mask)
        self.mask = mask
    end

    return region
end

local Frame = {}
Frame.__index = Frame

local function removeChild(parent, child)
    if not (parent and parent.children) then return end
    for index = #parent.children, 1, -1 do
        if parent.children[index] == child then
            table.remove(parent.children, index)
            return
        end
    end
end

local function newFrame(objectType, parent)
    local frame = setmetatable({
        objectType = objectType or "Frame",
        children = {},
        scripts = {},
        shown = true,
        width = 0,
        height = 0,
        frameLevel = 1,
        scale = 1,
        verticalScroll = 0,
        verticalScrollRange = 0,
    }, Frame)
    if parent then frame:SetParent(parent) end
    return frame
end

function Frame:SetParent(parent)
    if self.parent == parent then return end
    removeChild(self.parent, self)
    self.parent = parent
    if parent and parent.children then parent.children[#parent.children + 1] = self end
end

function Frame:GetParent() return self.parent end
function Frame:GetChildren() return unpack_(self.children) end
function Frame:SetSize(width, height) self.width, self.height = width, height end
function Frame:SetWidth(width) self.width = width end
function Frame:GetWidth() return self.width end
function Frame:SetHeight(height) self.height = height end
function Frame:GetHeight() return self.height end
function Frame:Show() self.shown = true end
function Frame:Hide() self.shown = false end
function Frame:IsShown() return self.shown ~= false end
function Frame:IsVisible() return self:IsShown() end
function Frame:SetShown(shown) self.shown = shown and true or false end
function Frame:GetObjectType() return self.objectType end
function Frame:SetFrameLevel(level) self.frameLevel = level end
function Frame:GetFrameLevel() return self.frameLevel end
function Frame:SetScale(scale) self.scale = scale end
function Frame:GetScale() return self.scale end
function Frame:SetID(id) self.id = id end
function Frame:GetID() return self.id end
function Frame:EnableMouse(enabled) self.mouseEnabled = enabled ~= false end
function Frame:SetMouseClickEnabled() end
function Frame:SetAllPoints() end
function Frame:SetAlpha() end
function Frame:SetScript(scriptName, fn) self.scripts[scriptName] = fn end
function Frame:GetScript(scriptName) return self.scripts[scriptName] end
function Frame:RegisterEvent(eventName) self.events = self.events or {}; self.events[eventName] = true end
function Frame:UnregisterAllEvents() self.events = {} end
function Frame:SetVerticalScroll(value) self.verticalScroll = value end
function Frame:GetVerticalScroll() return self.verticalScroll end
function Frame:GetVerticalScrollRange() return self.verticalScrollRange end
function Frame:SetNormalTexture() end
function Frame:SetHighlightTexture() end
function Frame:SetPushedTexture() end
function Frame:SetDisabledTexture() end

function Frame:ClearAllPoints()
    self.point = nil
end

function Frame:SetPoint(point, relativeTo, relativePoint, x, y)
    if type(relativeTo) == "number" then
        x, y = relativeTo, relativePoint
        relativeTo, relativePoint = nil, nil
    end
    self.point = {
        point = point,
        relativeTo = relativeTo,
        relativePoint = relativePoint,
        x = x or 0,
        y = y or 0,
    }
end

function Frame:GetPoint()
    local p = self.point or {}
    return p.point, p.relativeTo, p.relativePoint, p.x, p.y
end

function Frame:CreateTexture()
    return newRegion()
end

function Frame:CreateMaskTexture()
    return newRegion()
end

function Frame:CreateFontString()
    local region = newRegion()
    region.requiresFont = true
    return region
end

local function pointXY(frame)
    local _, _, _, x, y = frame:GetPoint(1)
    return x, y
end

local function makeCategoryHeader(parent, text, x, y, width)
    local frame = newFrame("Frame", parent)
    frame:SetSize(width or 456, 22)
    frame._label = newRegion()
    frame._label:SetText(text)
    frame._hint = newRegion()
    frame._hint:SetText("")
    frame._line = newRegion()
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    frame:Show()
    return frame
end

local function makeSubHeader(parent, text, x, y, width)
    local frame = newFrame("Frame", parent)
    frame:SetSize(width or 76, 18)
    frame._label = newRegion()
    frame._label:SetText(text)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    frame:Show()
    return frame
end

local function makeSlot(parent, x, y)
    local frame = newFrame("Frame", parent)
    frame:SetSize(34, 34)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    frame:Show()
    newFrame("Frame", frame)
    return frame
end

local function makePad(parent, x, y)
    local frame = newFrame("Frame", parent)
    frame:SetSize(34, 34)
    frame._bg = newRegion()
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    frame:Show()
    return frame
end

local function resetGlobals()
    _G.BagPlusForEllesmereUIDB = nil
    _G.EllesmereUIDB = {}
    _G.EllesmereUI = nil
    _G.EUI_CategoryManager = nil
    _G.EUI_Bags = nil
    _G.EUI_Bank = nil
    _G.EUI_BankFrame = nil
    _G.SlashCmdList = {}
    _G.SLASH_BAGPLUSFORELLESMEREUI1 = nil
    _G.Enum = {
        BagIndex = {
            AccountBankTab_1 = 100,
            AccountBankTab_2 = 101,
            AccountBankTab_3 = 102,
            AccountBankTab_4 = 103,
            AccountBankTab_5 = 104,
            CharacterBankTab_1 = 200,
            CharacterBankTab_2 = 201,
            CharacterBankTab_3 = 202,
            CharacterBankTab_4 = 203,
            CharacterBankTab_5 = 204,
            CharacterBankTab_6 = 205,
        },
        BagSlotFlags = {
            DisableAutoSort = 0x1,
            ClassEquipment = 0x2,
            ClassConsumables = 0x4,
            ClassProfessionGoods = 0x8,
            ClassJunk = 0x10,
            ClassQuestItems = 0x20,
            ClassReagents = 0x80,
            ExpansionCurrent = 0x100,
            ExpansionLegacy = 0x200,
        },
        BankType = { Character = 0, Guild = 1, Account = 2 },
        ItemClass = {
            Consumable = 0,
            Container = 1,
            Weapon = 2,
            Gem = 3,
            Armor = 4,
            Reagent = 5,
            Tradegoods = 7,
            ItemEnhancement = 8,
            Recipe = 9,
            Questitem = 12,
            Miscellaneous = 15,
            Profession = 19,
        },
        ItemBind = { OnEquip = 2, Quest = 4 },
        ItemQuality = { Poor = 0 },
    }
    _G.C_Container = {
        GetContainerNumSlots = function() return 0 end,
        GetContainerItemInfo = function() return nil end,
        GetContainerItemLink = function() return nil end,
        GetContainerItemQuestInfo = function() return nil end,
        GetBagSlotFlag = function() return false end,
        PickupContainerItem = function() end,
        SortBank = function() end,
        SetSortBagsRightToLeft = function() end,
    }
    _G.C_Bank = {
        FetchPurchasedBankTabData = function() return {} end,
        IsItemAllowedInBankType = function() return true end,
    }
    _G.C_Item = {
        DoesItemExist = function() return true end,
        IsBoundToAccountUntilEquip = function() return false end,
        IsLocked = function() return false end,
        GetItemMaxStackSizeByID = function() return 1 end,
    }
    _G.ItemLocation = {
        CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end,
    }
    _G.GetItemInfoInstant = nil
    _G.GetItemInfo = nil
    _G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    _G.print = function(...) io.write(table.concat({ ... }, " "), "\n") end

    local createdFrames = {}
    _G.CreateFrame = function(objectType, _, parent)
        local frame = newFrame(objectType, parent)
        createdFrames[#createdFrames + 1] = frame
        return frame
    end
    _G.C_Timer = {
        After = function(_, fn) if fn then fn() end end,
    }
    _G.UIParent = newFrame("Frame")
    UIParent:SetSize(1920, 1080)

    return createdFrames
end

local function setup(options)
    options = options or {}
    local createdFrames = resetGlobals()
    local prints = {}
    local tooltip = {}
    local registeredModules = {}

    local profile = {
        bagColumns = 12,
        bagAutoSize = false,
        bagCategoryOrder = {},
        bagCategoryState = {},
        bagVisualOrder = {},
    }
    _G.EllesmereUI = {
        _bagsDB = { profile = profile },
        ADDON_ROSTER = {},
        ADDON_GROUPS = {},
        _addonInfoByFolder = {},
        Widgets = {},
        Print = function(msg) prints[#prints + 1] = msg end,
        L = function(text) return text end,
        Lf = function(fmt, ...) return string.format(fmt, ...) end,
        ShowWidgetTooltip = function(_, text) tooltip.text = text end,
        HideWidgetTooltip = function() tooltip.text = nil end,
        RegisterModule = function(_, name, config) registeredModules[name] = config end,
    }

    local manager = {
        _categories = {
            { _defaultName = "Item Set Gear", name = "Item Set Gear", isSetGear = true },
            { _defaultName = "Armor", name = "Armor" },
            { _defaultName = "Weapons / Trinkets", name = "Weapons / Trinkets" },
            { _defaultName = "Quest Items", name = "Quest Items" },
        },
        _groupMembers = {},
    }
    function manager:InitCategories() self.initCount = (self.initCount or 0) + 1 end
    function manager:GetCategories() return self._categories end
    function manager:GetGroupMembers(groupName) return self._groupMembers[groupName] or {} end
    function manager:ClassifyItem() return nil end
    function manager:ClassifyAll(items) return {}, #items end
    _G.EUI_CategoryManager = manager

    local bags = newFrame("Frame")
    bags:SetSize(600, 650)
    bags.Header = newFrame("Frame", bags)
    bags.Header:SetHeight(35)
    bags._searchBox = newFrame("EditBox", bags.Header)
    bags._searchBox:SetSize(160, 22)
    bags._searchBox:SetPoint("RIGHT", bags.Header, "RIGHT", -35, 0)
    bags._sortBtn = newFrame("Button", bags.Header)
    bags._sortBtn:SetSize(24, 24)
    bags._sortBtn:SetPoint("RIGHT", bags._searchBox, "LEFT", -13, 0)
    bags._sortBtn.icon = newRegion()
    bags._bagsBtn = newFrame("Button", bags.Header)
    bags._bagsBtn:SetSize(24, 24)
    bags._bagsBtn:SetPoint("RIGHT", bags._sortBtn, "LEFT", -6, 0)
    bags._bagsBtn.icon = newRegion()
    bags.Footer = newFrame("Frame", bags)
    bags.Footer:SetHeight(28)
    bags._footerH = 28
    bags._scrollFrame = newFrame("Frame", bags)
    bags._scrollChild = newFrame("Frame", bags)
    bags._scrollChild:SetSize(488, 320)
    bags._updateThumb = function() bags.thumbUpdated = true end
    bags.RefreshInventory = options.refreshInventory or function() end
    _G.EUI_Bags = bags

    local bank = newFrame("Frame")
    bank:SetSize(700, 650)
    bank.Header = newFrame("Frame", bank)
    bank.Header:SetHeight(35)
    bank._searchBox = newFrame("EditBox", bank.Header)
    bank._searchBox:SetSize(160, 22)
    bank._searchBox:SetPoint("RIGHT", bank.Header, "RIGHT", -35, 0)
    bank._nativeSortBtn = newFrame("Button", bank.Header)
    bank._nativeSortBtn:SetSize(24, 24)
    bank._nativeSortBtn:SetPoint("RIGHT", bank._searchBox, "LEFT", -13, 0)
    bank._nativeSortBtn.icon = newRegion()
    bank._allTabs = {}
    bank._originalTransfers = {}
    bank.GetSelectedTabBagID = function(self) return self._selectedBagID end
    bank.IsWarbandView = function(self) return self._warbandView == true end
    bank.QueueTransfer = function(self, srcBag, srcSlot)
        self._originalTransfers[#self._originalTransfers + 1] = { srcBag, srcSlot }
    end
    bank.RefreshBank = function(self) self.refreshCount = (self.refreshCount or 0) + 1 end
    _G.EUI_BankFrame = bank
    _G.EUI_Bank = bank

    return {
        createdFrames = createdFrames,
        prints = prints,
        tooltip = tooltip,
        registeredModules = registeredModules,
        profile = profile,
        manager = manager,
        bags = bags,
        bank = bank,
    }
end

local function loadAddon(ctx)
    local chunk, err = loadfile(ADDON_PATH)
    assertTrue(chunk, err)
    chunk(ADDON_NAME)

    local eventFrame = ctx.createdFrames[#ctx.createdFrames]
    assertTrue(eventFrame and eventFrame.scripts.OnEvent, "addon event frame was not created")
    eventFrame.scripts.OnEvent(eventFrame, "PLAYER_LOGIN")
end

local function bagItem(itemID, count, link, locked)
    return {
        itemID = itemID,
        count = count or 1,
        link = link or ("item:" .. tostring(itemID)),
        locked = locked,
    }
end

local function installInventory(layout, details)
    details = details or {}
    local cursor

    local function detailFor(item)
        local detail = details[item]
        if detail then return detail end
        if type(item) == "string" then
            for _, d in pairs(details) do
                if d.link == item then return d end
            end
        elseif type(item) == "number" then
            for _, d in pairs(details) do
                if d.itemID == item or d.link == ("item:" .. tostring(item)) then return d end
            end
        end
        return {}
    end

    local function bagTable(bag)
        local t = layout[bag]
        if not t then
            t = { size = 0 }
            layout[bag] = t
        end
        return t
    end

    local function canPlaceInBag(item, bag)
        if bag ~= 5 then return true end
        return detailFor(item.link or item.itemID).reagent == true
    end

    local function maxStackFor(item)
        return tonumber(detailFor(item.link or item.itemID).maxStack) or 1
    end

    local function placeCursorBack()
        if not cursor then return end
        local origin = cursor.origin
        if origin then
            local originBag = bagTable(origin.bag)
            if not originBag[origin.slot] then
                originBag[origin.slot] = cursor.item
            end
        end
        cursor = nil
    end

    _G.GetCursorInfo = function()
        if not cursor then return nil end
        return "item", cursor.item.itemID, cursor.item.link
    end
    _G.ClearCursor = placeCursorBack

    _G.C_Container.GetContainerNumSlots = function(bag)
        return bagTable(bag).size or 0
    end
    _G.C_Container.GetContainerItemInfo = function(bag, slot)
        local item = bagTable(bag)[slot]
        if not item then return nil end
        return {
            itemID = item.itemID,
            stackCount = item.count,
            isLocked = item.locked,
            hyperlink = item.link,
            quality = detailFor(item.link or item.itemID).quality,
        }
    end
    _G.C_Container.GetContainerItemLink = function(bag, slot)
        local item = bagTable(bag)[slot]
        return item and item.link or nil
    end
    _G.C_Container.PickupContainerItem = function(bag, slot)
        local targetBag = bagTable(bag)
        local target = targetBag[slot]

        if not cursor then
            if target and not target.locked then
                cursor = { item = target, origin = { bag = bag, slot = slot } }
                targetBag[slot] = nil
            end
            return
        end

        if not canPlaceInBag(cursor.item, bag) then return end

        if not target then
            targetBag[slot] = cursor.item
            cursor = nil
            return
        end

        if target.itemID == cursor.item.itemID and target.link == cursor.item.link then
            local maxStack = maxStackFor(target)
            local room = maxStack - target.count
            if room > 0 then
                local moved = math.min(room, cursor.item.count)
                target.count = target.count + moved
                cursor.item.count = cursor.item.count - moved
                if cursor.item.count <= 0 then
                    cursor = nil
                else
                    placeCursorBack()
                end
                return
            end
        end

        targetBag[slot], cursor.item = cursor.item, target
    end

    _G.C_Item.GetItemInfo = function(item)
        local detail = detailFor(item)
        if not detail.name then return nil end
        return detail.name, detail.link or (type(item) == "string" and item or ("item:" .. tostring(item))),
            detail.quality or 1, detail.ilvl or 1, 0, detail.itemType or "Tradeskill",
            detail.itemSubType or "", detail.maxStack or 1, detail.equipLoc or "", detail.texture or 1, 0,
            detail.classID, detail.subclassID or 0, detail.bindType, detail.expansionID, detail.setID, detail.reagent == true
    end
    _G.GetItemInfo = _G.C_Item.GetItemInfo
    _G.GetItemInfoInstant = function(item)
        local detail = detailFor(item)
        return detail.itemID, nil, nil, detail.equipLoc or "", nil, detail.classID, detail.subclassID
    end
    _G.C_Item.GetItemMaxStackSizeByID = function(itemID)
        return detailFor(itemID).maxStack or 1
    end
    _G.C_Item.IsLocked = function(loc)
        local item = loc and bagTable(loc.bag)[loc.slot]
        return item and item.locked or false
    end

    return layout
end

local function testBitBand(a, b)
    a, b = tonumber(a) or 0, tonumber(b) or 0
    local result = 0
    local bitValue = 1
    while a > 0 and b > 0 do
        local aa, bb = a % 2, b % 2
        if aa == 1 and bb == 1 then result = result + bitValue end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        bitValue = bitValue * 2
    end
    return result
end

local function bankBagID(bankType, index)
    local prefix = bankType == Enum.BankType.Account and "AccountBankTab_" or "CharacterBankTab_"
    return Enum.BagIndex[prefix .. tostring(index)]
end

local function configureBankTabs(ctx, bankType, tabFlags)
    ctx._bankTabFlagsByType = ctx._bankTabFlagsByType or {}
    ctx._bankTabFlagsByType[bankType] = tabFlags
    ctx._bankFlagsByBag = ctx._bankFlagsByBag or {}

    ctx.bank._allTabs = {}
    ctx.bank._warbandView = bankType == Enum.BankType.Account
    ctx.bank._selectedBagID = nil

    for index, flags in ipairs(tabFlags) do
        local bagID = bankBagID(bankType, index)
        ctx._bankFlagsByBag[bagID] = flags or 0
        ctx.bank._allTabs[#ctx.bank._allTabs + 1] = {
            bagID = bagID,
            index = index,
            numSlots = C_Container.GetContainerNumSlots(bagID),
            depositFlags = flags or 0,
            isWarband = bankType == Enum.BankType.Account,
        }
    end

    _G.C_Bank.FetchPurchasedBankTabData = function(requestedBankType)
        local flagsForType = ctx._bankTabFlagsByType and ctx._bankTabFlagsByType[requestedBankType]
        local data = {}
        if flagsForType then
            for index, flags in ipairs(flagsForType) do
                data[index] = { name = "Tab " .. tostring(index), depositFlags = flags or 0 }
            end
        end
        return data
    end
    _G.C_Container.GetBagSlotFlag = function(bagID, flag)
        return testBitBand(ctx._bankFlagsByBag[bagID] or 0, flag or 0) ~= 0
    end
end

local function slash(command)
    assertTrue(SlashCmdList.BAGPLUSFORELLESMEREUI, "slash command was not registered")
    SlashCmdList.BAGPLUSFORELLESMEREUI(command)
end

local function findCategory(manager, key)
    for index, category in ipairs(manager:GetCategories()) do
        if category._defaultName == key then return index, category end
    end
end

local function clearChildren(frame)
    for index = #frame.children, 1, -1 do
        frame.children[index].parent = nil
        frame.children[index] = nil
    end
end

local function buildSimpleGrid(ctx)
    local child = ctx.bags._scrollChild
    clearChildren(child)
    child:SetSize(488, 320)
    ctx.bags:SetWidth(600)
    makeCategoryHeader(child, "Main Bags", 15, -6, 456)
    ctx.simpleSlots = {}
    for index = 1, 12 do
        local col = (index - 1) % 12
        local row = math.floor((index - 1) / 12)
        ctx.simpleSlots[index] = makeSlot(child, 15 + col * 38, -28 - row * 38)
    end
end

local function buildSharedArmoryGrid(ctx)
    local child = ctx.bags._scrollChild
    clearChildren(child)
    child:SetSize(488, 320)
    ctx.bags:SetWidth(600)
    makeCategoryHeader(child, "Armor", 15, -6, 456)

    ctx.armoryHeaders = {
        makeSubHeader(child, "A (2)", 15, -28, 76),
        makeSubHeader(child, "B (2)", 103, -28, 76),
        makeSubHeader(child, "C (2)", 191, -28, 76),
    }
    ctx.armorySlots = {}
    local starts = { 15, 103, 191 }
    for bucket = 1, 3 do
        for item = 1, 2 do
            ctx.armorySlots[#ctx.armorySlots + 1] = makeSlot(child, starts[bucket] + (item - 1) * 38, -46)
        end
    end
    for pad = 1, 6 do
        makePad(child, 267 + (pad - 1) * 38, -46)
    end
end

test("loads and registers in a mocked EllesmereUI environment", function()
    local ctx = setup()
    loadAddon(ctx)

    assertTrue(SlashCmdList.BAGPLUSFORELLESMEREUI, "slash command should be registered")
    assertTrue(ctx.registeredModules[ADDON_NAME], "options module should be registered")
    assertEqual(SLASH_BAGPLUSFORELLESMEREUI1, "/bagplus")
end)

test("adds a reagent move button beside the EllesmereUI sort controls", function()
    local ctx = setup()
    loadAddon(ctx)

    local btn = ctx.bags._bagPlusReagentBtn
    assertTrue(btn, "reagent move button should be created")
    assertTrue(btn:GetScript("OnClick"), "reagent move button should be clickable")
    assertTrue(btn.icon.texCoord, "reagent icon should be cropped like the header icons")
    assertEqual(btn.icon.mask, btn.iconMask, "reagent icon should use a circular mask")
    assertEqual(btn.iconMask.texture, "Interface\\AddOns\\EllesmereUI\\media\\portraits\\circle_mask.tga")

    local _, reagentAnchor = btn:GetPoint()
    local _, bagsAnchor = ctx.bags._bagsBtn:GetPoint()
    assertEqual(reagentAnchor, ctx.bags._sortBtn, "reagent button should anchor next to sort")
    assertEqual(bagsAnchor, btn, "bags overview button should move left of reagent button")
end)

test("adds a native Blizzard warbank sort button to the bank header", function()
    local ctx = setup()
    local sortedBankType
    _G.C_Container.SortBank = function(bankType) sortedBankType = bankType end
    loadAddon(ctx)

    local btn = ctx.bank._bagPlusWarbankSortBtn
    assertTrue(btn, "warbank sort button should be created")
    assertTrue(btn:GetScript("OnClick"), "warbank sort button should be clickable")
    assertEqual(btn.icon.texture, "Interface\\AddOns\\EllesmereUIBags\\Media\\clean-up.png")
    assertEqual(btn.badge.text, "WoW", "warbank button should be visually distinct")
    assertEqual(btn.badge.fontSize, 6, "warbank badge should fit inside a 24px icon")
    assertEqual(btn.badge.width, 24, "warbank badge should use the full icon width")

    local _, anchor = btn:GetPoint()
    assertEqual(anchor, ctx.bank._nativeSortBtn, "warbank sort button should anchor beside the native bank sort")

    btn:GetScript("OnEnter")(btn)
    assertEqual(ctx.tooltip.text, "Blizzard's Warbank Cleanup")

    btn:GetScript("OnClick")(btn)
    assertEqual(sortedBankType, Enum.BankType.Account, "button should call Blizzard's account-bank sort")
end)

test("right-click bank transfer routes equipment to an equipment bank tab", function()
    local ctx = setup()
    local charEquipTab = Enum.BagIndex.CharacterBankTab_1
    local charConsumableTab = Enum.BagIndex.CharacterBankTab_2
    local layout = installInventory({
        [0] = {
            size = 2,
            [1] = bagItem(1001, 1, "item:1001"),
        },
        [charEquipTab] = { size = 3 },
        [charConsumableTab] = { size = 3 },
    }, {
        ["item:1001"] = {
            itemID = 1001,
            name = "Warplate",
            link = "item:1001",
            maxStack = 1,
            classID = Enum.ItemClass.Armor,
            equipLoc = "INVTYPE_CHEST",
        },
    })
    configureBankTabs(ctx, Enum.BankType.Character, {
        Enum.BagSlotFlags.ClassEquipment,
        Enum.BagSlotFlags.ClassConsumables,
    })
    loadAddon(ctx)

    assertEqual(ctx.bank:GetSelectedTabBagID(), charEquipTab, "categorized aggregate bank view should still allow right-click routing")
    ctx.bank:QueueTransfer(0, 1)

    assertNil(layout[0][1], "source slot should be emptied")
    assertEqual(layout[charEquipTab][1].itemID, 1001, "equipment should land in the equipment tab")
    assertNil(layout[charConsumableTab][1], "equipment should not land in the consumable tab")
    assertEqual(#ctx.bank._originalTransfers, 0, "category-aware transfer should not fall back to EUI's original queue")
end)

test("right-click bank transfer routes consumables to a consumable bank tab", function()
    local ctx = setup()
    local charEquipTab = Enum.BagIndex.CharacterBankTab_1
    local charConsumableTab = Enum.BagIndex.CharacterBankTab_2
    local layout = installInventory({
        [0] = {
            size = 2,
            [1] = bagItem(1501, 5, "item:1501"),
        },
        [charEquipTab] = { size = 3 },
        [charConsumableTab] = { size = 3 },
    }, {
        ["item:1501"] = {
            itemID = 1501,
            name = "Potion",
            link = "item:1501",
            maxStack = 20,
            classID = Enum.ItemClass.Consumable,
        },
    })
    configureBankTabs(ctx, Enum.BankType.Character, {
        Enum.BagSlotFlags.ClassEquipment,
        Enum.BagSlotFlags.ClassConsumables,
    })
    loadAddon(ctx)

    ctx.bank:QueueTransfer(0, 1)

    assertNil(layout[0][1], "source slot should be emptied")
    assertNil(layout[charEquipTab][1], "consumable should not land in the equipment tab")
    assertEqual(layout[charConsumableTab][1].itemID, 1501, "consumable should land in the consumable tab")
end)

test("right-click warbank transfer routes warbound equipment to an equipment warbank tab", function()
    local ctx = setup()
    local warEquipTab = Enum.BagIndex.AccountBankTab_1
    local warConsumableTab = Enum.BagIndex.AccountBankTab_2
    local layout = installInventory({
        [0] = {
            size = 2,
            [1] = bagItem(2001, 1, "item:2001"),
        },
        [warEquipTab] = { size = 3 },
        [warConsumableTab] = { size = 3 },
    }, {
        ["item:2001"] = {
            itemID = 2001,
            name = "Warbound Chestguard",
            link = "item:2001",
            maxStack = 1,
            classID = Enum.ItemClass.Armor,
            equipLoc = "INVTYPE_CHEST",
            warbound = true,
        },
    })
    configureBankTabs(ctx, Enum.BankType.Account, {
        Enum.BagSlotFlags.ClassEquipment,
        Enum.BagSlotFlags.ClassConsumables,
    })
    _G.C_Bank.IsItemAllowedInBankType = function(bankType, loc)
        local item = loc and layout[loc.bag] and layout[loc.bag][loc.slot]
        return bankType ~= Enum.BankType.Account or (item and item.link == "item:2001")
    end
    loadAddon(ctx)

    assertEqual(ctx.bank:GetSelectedTabBagID(), warEquipTab, "categorized aggregate warbank view should allow right-click routing")
    ctx.bank:QueueTransfer(0, 1)

    assertNil(layout[0][1], "source slot should be emptied")
    assertEqual(layout[warEquipTab][1].itemID, 2001, "warbound equipment should land in the equipment warbank tab")
    assertNil(layout[warConsumableTab][1], "warbound equipment should not land in the consumable warbank tab")
    assertEqual(#ctx.bank._originalTransfers, 0, "warbank category transfer should not use the old aggregate route")
end)

test("right-click bank transfer leaves an item alone when no matching categorized tab exists", function()
    local ctx = setup()
    local charEquipTab = Enum.BagIndex.CharacterBankTab_1
    local layout = installInventory({
        [0] = {
            size = 2,
            [1] = bagItem(3001, 5, "item:3001"),
        },
        [charEquipTab] = { size = 3 },
    }, {
        ["item:3001"] = {
            itemID = 3001,
            name = "Potion",
            link = "item:3001",
            maxStack = 20,
            classID = Enum.ItemClass.Consumable,
        },
    })
    configureBankTabs(ctx, Enum.BankType.Character, {
        Enum.BagSlotFlags.ClassEquipment,
    })
    loadAddon(ctx)

    ctx.bank:QueueTransfer(0, 1)

    assertEqual(layout[0][1].itemID, 3001, "unmatched item should remain in the source bag")
    assertNil(layout[charEquipTab][1], "unmatched item should not be placed in the wrong category tab")
    assertEqual(#ctx.bank._originalTransfers, 0, "unmatched categorized transfer should not fall back into the wrong tab")
end)

test("warbank cleanup button only calls Blizzard account-bank cleanup", function()
    local ctx = setup()
    local equipTab = Enum.BagIndex.AccountBankTab_1
    local consumableTab = Enum.BagIndex.AccountBankTab_2
    local sortedBankType
    local layout = installInventory({
        [equipTab] = {
            size = 3,
            [1] = bagItem(5001, 1, "item:5001"),
            [2] = bagItem(5002, 5, "item:5002"),
        },
        [consumableTab] = { size = 3 },
    }, {
        ["item:5001"] = {
            itemID = 5001,
            name = "Plate Helm",
            link = "item:5001",
            maxStack = 1,
            classID = Enum.ItemClass.Armor,
            equipLoc = "INVTYPE_HEAD",
        },
        ["item:5002"] = {
            itemID = 5002,
            name = "Potion",
            link = "item:5002",
            maxStack = 20,
            classID = Enum.ItemClass.Consumable,
        },
    })
    configureBankTabs(ctx, Enum.BankType.Account, {
        Enum.BagSlotFlags.ClassEquipment,
        Enum.BagSlotFlags.ClassConsumables,
    })
    _G.C_Container.SortBank = function(bankType) sortedBankType = bankType end
    loadAddon(ctx)

    ctx.bank._bagPlusWarbankSortBtn:GetScript("OnClick")(ctx.bank._bagPlusWarbankSortBtn)

    assertEqual(sortedBankType, Enum.BankType.Account, "button should still call Blizzard's account-bank cleanup")
    assertEqual(layout[equipTab][1].itemID, 5001, "BagPlus should not move existing warbank items from the cleanup button")
    assertEqual(layout[equipTab][2].itemID, 5002, "BagPlus should leave Blizzard cleanup behavior to Blizzard")
    assertNil(layout[consumableTab][1], "BagPlus should not add a category-enforcement pass after Blizzard cleanup")
end)

test("uncategorized aggregate bank view keeps the original routing path", function()
    local ctx = setup()
    installInventory({
        [0] = {
            size = 2,
            [1] = bagItem(4001, 1, "item:4001"),
        },
        [Enum.BagIndex.CharacterBankTab_1] = { size = 3 },
    }, {
        ["item:4001"] = {
            itemID = 4001,
            name = "Plain Item",
            link = "item:4001",
            maxStack = 1,
            classID = Enum.ItemClass.Miscellaneous,
        },
    })
    configureBankTabs(ctx, Enum.BankType.Character, { 0 })
    loadAddon(ctx)

    assertNil(ctx.bank:GetSelectedTabBagID(), "aggregate uncategorized bank should not force the EUI right-click queue")
    ctx.bank:QueueTransfer(0, 1)
    assertEqual(#ctx.bank._originalTransfers, 1, "direct QueueTransfer should still fall back to the original EUI queue")
end)

test("initializes defaults and migrates old saved keys", function()
    _G.BagPlusForEllesmereUIDB = {
        condensedCategoryRows = true,
        maxItemsPerRow = 99,
        maxBagColumns = 7,
    }
    local ctx = setup()
    _G.BagPlusForEllesmereUIDB = {
        condensedCategoryRows = true,
        maxItemsPerRow = 99,
        maxBagColumns = 7,
    }
    loadAddon(ctx)

    local db = BagPlusForEllesmereUIDB
    assertEqual(db.boeEnabled, true)
    assertEqual(db.wueEnabled, true)
    assertEqual(db.ilvlSort, "desc")
    assertEqual(db.compactCategoryRows, true)
    assertNil(db.condensedCategoryRows)
    assertEqual(db.hideEmptyRecentItems, true)
    assertEqual(db.limitItemsPerRow, false)
    assertEqual(db.maxItemsPerRow, 17)
    assertNil(db.maxBagColumns)
end)

test("adds BagPlus categories and routes BoE and Warbound gear", function()
    local ctx = setup()
    _G.GetItemInfoInstant = function(link)
        if link == "boe" then return nil, nil, nil, "INVTYPE_CHEST", nil, Enum.ItemClass.Armor end
        if link == "wue" then return nil, nil, nil, "INVTYPE_CHEST", nil, Enum.ItemClass.Armor end
        return nil, nil, nil, nil, nil, nil
    end
    _G.GetItemInfo = function(link)
        if link == "boe" then
            return "BoE", nil, 2, 500, nil, "Armor", nil, nil, nil, nil, nil, nil, nil, Enum.ItemBind.OnEquip
        end
        return "Item", nil, 1, 1, nil, "Armor", nil, nil, nil, nil, nil, nil, nil, nil
    end
    _G.C_Item.IsBoundToAccountUntilEquip = function(loc)
        return loc and loc.bag == 0 and loc.slot == 2
    end

    loadAddon(ctx)

    local wueIndex = findCategory(ctx.manager, "Warbound Gear")
    local boeIndex = findCategory(ctx.manager, "BoE Gear")
    assertTrue(wueIndex, "Warbound category should exist")
    assertTrue(boeIndex, "BoE category should exist")
    assertEqual(ctx.manager:ClassifyItem("wue", 1, 0, 2, { isBound = false }), wueIndex)
    assertEqual(ctx.manager:ClassifyItem("boe", 2, 0, 1, { isBound = false }), boeIndex)
end)

test("reagent command merges stacks and moves reagents into bag 5 only", function()
    local ctx = setup()
    local layout = installInventory({
        [0] = {
            size = 4,
            [1] = bagItem(900, 1, "item:900"),
            [2] = bagItem(101, 40, "item:101"),
            [3] = bagItem(102, 5, "item:102"),
        },
        [1] = {
            size = 2,
            [1] = bagItem(101, 20, "item:101"),
            [2] = bagItem(901, 1, "item:901"),
        },
        [5] = {
            size = 4,
            [1] = bagItem(101, 160, "item:101"),
            [2] = bagItem(101, 10, "item:101"),
            [4] = bagItem(102, 15, "item:102"),
        },
    }, {
        ["item:101"] = { name = "Herb", link = "item:101", maxStack = 200, classID = Enum.ItemClass.Tradegoods, reagent = true },
        ["item:102"] = { name = "Ore", link = "item:102", maxStack = 20, classID = Enum.ItemClass.Tradegoods, reagent = true },
        ["item:900"] = { name = "Rock", link = "item:900", maxStack = 1, classID = 15, reagent = false },
        ["item:901"] = { name = "Cloth Hat", link = "item:901", maxStack = 1, classID = Enum.ItemClass.Armor, reagent = false },
    })
    loadAddon(ctx)

    slash("reagents")

    assertEqual(layout[0][1].itemID, 900, "normal item should stay put")
    assertNil(layout[0][2], "main-bag reagent should move")
    assertNil(layout[0][3], "main-bag reagent should merge into reagent bag")
    assertNil(layout[1][1], "second main-bag reagent should move")
    assertEqual(layout[1][2].itemID, 901, "other normal item should stay put")

    assertEqual(layout[5][1].itemID, 101)
    assertEqual(layout[5][1].count, 200)
    assertEqual(layout[5][2].itemID, 101)
    assertEqual(layout[5][2].count, 30)
    assertNil(layout[5][3])
    assertEqual(layout[5][4].itemID, 102)
    assertEqual(layout[5][4].count, 20)
end)

test("perrow slash command validates, saves, and toggles the feature", function()
    local ctx = setup()
    loadAddon(ctx)

    slash("perrow 17")
    assertEqual(BagPlusForEllesmereUIDB.limitItemsPerRow, true)
    assertEqual(BagPlusForEllesmereUIDB.maxItemsPerRow, 17)

    slash("perrow 18")
    assertEqual(BagPlusForEllesmereUIDB.limitItemsPerRow, true)
    assertEqual(BagPlusForEllesmereUIDB.maxItemsPerRow, 17)

    slash("perrow off")
    assertEqual(BagPlusForEllesmereUIDB.limitItemsPerRow, false)
    assertEqual(BagPlusForEllesmereUIDB.maxItemsPerRow, 17)

    slash("perrow 99")
    assertEqual(BagPlusForEllesmereUIDB.limitItemsPerRow, false)
    assertEqual(BagPlusForEllesmereUIDB.maxItemsPerRow, 17)
end)

test("maximum items per row reflows a simple rendered bag grid", function()
    local ctx
    ctx = setup({
        refreshInventory = function() buildSimpleGrid(ctx) end,
    })
    loadAddon(ctx)

    slash("perrow 5")

    local slot1x, slot1y = pointXY(ctx.simpleSlots[1])
    local slot5x, slot5y = pointXY(ctx.simpleSlots[5])
    local slot6x, slot6y = pointXY(ctx.simpleSlots[6])
    local slot11x, slot11y = pointXY(ctx.simpleSlots[11])

    assertEqual(slot1x, 15)
    assertEqual(slot1y, -28)
    assertEqual(slot5x, 167)
    assertEqual(slot5y, -28)
    assertEqual(slot6x, 15)
    assertEqual(slot6y, -66)
    assertEqual(slot11x, 15)
    assertEqual(slot11y, -104)
    assertEqual(ctx.bags._scrollChild:GetWidth(), 222)
end)

test("maximum items per row repacks compact armory slot groups", function()
    local ctx
    ctx = setup({
        refreshInventory = function() buildSharedArmoryGrid(ctx) end,
    })
    loadAddon(ctx)

    slash("perrow 5")

    local _, firstY = pointXY(ctx.armoryHeaders[1])
    local _, secondY = pointXY(ctx.armoryHeaders[2])
    local thirdX, thirdY = pointXY(ctx.armoryHeaders[3])
    local thirdSlotX, thirdSlotY = pointXY(ctx.armorySlots[5])

    assertEqual(firstY, -28)
    assertEqual(secondY, -28)
    assertEqual(thirdX, 15)
    assertEqual(thirdY, -84)
    assertEqual(thirdSlotX, 15)
    assertEqual(thirdSlotY, -102)
end)

local passed = 0
for _, entry in ipairs(tests) do
    io.write("test: ", entry.name, " ... ")
    local ok, err = xpcall(entry.fn, debug.traceback)
    if ok then
        passed = passed + 1
        io.write("ok\n")
    else
        io.write("FAILED\n")
        io.write(err, "\n")
        os.exit(1)
    end
end

io.write(string.format("%d tests passed\n", passed))
