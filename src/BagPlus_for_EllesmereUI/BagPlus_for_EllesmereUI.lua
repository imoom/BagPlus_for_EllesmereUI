-- SPDX-License-Identifier: MIT

local ADDON_NAME = ...

local TITLE = "BagPlus for EllesmereUI"
local PAGE = "BagPlus"
local GROUP_KEY = "bagplus"

local KEY_WUE = "Warbound Gear"
local KEY_BOE = "BoE Gear"
local RULE_WUE = "warboundUntilEquip"
local RULE_BOE = "bindOnEquip"

local ILVL_SORT_VALUES = {
    desc = "Highest First",
    asc = "Lowest First",
    off = "Off",
}
local ILVL_SORT_ORDER = { "desc", "asc", "off" }

local CATEGORY_DEFS = {
    { key = KEY_WUE, name = "Warbound Gear", rule = RULE_WUE, icon = 4871338 },
    { key = KEY_BOE, name = "BoE Gear", rule = RULE_BOE, icon = 4382688 },
}

local patched
local refreshPatched
local refreshingOrder

local function DB()
    if type(BagPlusForEllesmereUIDB) ~= "table" then
        BagPlusForEllesmereUIDB = {}
    end
    if BagPlusForEllesmereUIDB.boeEnabled == nil then
        BagPlusForEllesmereUIDB.boeEnabled = BagPlusForEllesmereUIDB.enabled ~= false
    end
    if BagPlusForEllesmereUIDB.wueEnabled == nil then
        BagPlusForEllesmereUIDB.wueEnabled = BagPlusForEllesmereUIDB.enabled ~= false
    end
    local sortMode = BagPlusForEllesmereUIDB.ilvlSort
    if sortMode ~= "asc" and sortMode ~= "desc" and sortMode ~= "off" then
        BagPlusForEllesmereUIDB.ilvlSort = BagPlusForEllesmereUIDB.sortGearByItemLevel == false and "off" or "desc"
    end
    BagPlusForEllesmereUIDB.sortGearByItemLevel = BagPlusForEllesmereUIDB.ilvlSort ~= "off"
    if BagPlusForEllesmereUIDB.compactCategoryRows == nil then
        BagPlusForEllesmereUIDB.compactCategoryRows = BagPlusForEllesmereUIDB.condensedCategoryRows == true
    end
    BagPlusForEllesmereUIDB.condensedCategoryRows = nil
    if BagPlusForEllesmereUIDB.hideEmptyRecentItems == nil then
        BagPlusForEllesmereUIDB.hideEmptyRecentItems = true
    end
    return BagPlusForEllesmereUIDB
end

local function IsRuleEnabled(rule)
    local db = DB()
    if rule == RULE_WUE then return db.wueEnabled ~= false end
    if rule == RULE_BOE then return db.boeEnabled ~= false end
    return true
end

local function AnyRuleEnabled()
    local db = DB()
    return db.wueEnabled ~= false or db.boeEnabled ~= false
end

local function SortMode()
    return DB().ilvlSort
end

local function SortEnabled()
    return SortMode() ~= "off"
end

local function CompactCategoryRowsEnabled()
    return DB().compactCategoryRows == true
end

local function HideEmptyRecentItemsEnabled()
    return DB().hideEmptyRecentItems == true
end

local function BagsProfile()
    return EllesmereUI and EllesmereUI._bagsDB and EllesmereUI._bagsDB.profile
end

local function L(text)
    return (EllesmereUI and EllesmereUI.L and EllesmereUI.L(text)) or text
end

local function ItemClassIDs()
    local ic = Enum and Enum.ItemClass
    return ic and ic.Armor, ic and ic.Weapon
end

local function IsGearLink(itemLink)
    if not itemLink or not GetItemInfoInstant then return false end
    local armorClass, weaponClass = ItemClassIDs()
    if not armorClass or not weaponClass then return false end
    local _, _, _, _, _, classID = GetItemInfoInstant(itemLink)
    return classID == armorClass or classID == weaponClass
end

local function GetBindRule(itemLink, itemInfo, bag, slot)
    if not IsGearLink(itemLink) then return nil end
    local info = itemInfo
    if not info and bag and slot and C_Container and C_Container.GetContainerItemInfo then
        info = C_Container.GetContainerItemInfo(bag, slot)
    end
    if info and info.isBound then return nil end

    if bag and slot and C_Item and C_Item.IsBoundToAccountUntilEquip and ItemLocation then
        local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
        if loc and (not C_Item.DoesItemExist or C_Item.DoesItemExist(loc))
           and C_Item.IsBoundToAccountUntilEquip(loc) then
            return RULE_WUE
        end
    end

    if GetItemInfo and Enum and Enum.ItemBind then
        local _, _, _, _, _, _, _, _, _, _, _, _, _, bindType = GetItemInfo(itemLink)
        if bindType == Enum.ItemBind.OnEquip then
            return RULE_BOE
        end
    end
    return nil
end

local function HasOrderKey(order, key)
    if type(order) ~= "table" then return false end
    for _, v in ipairs(order) do
        if v == key then return true end
    end
    return false
end

local function NewManagedCategory(def, seenInOrder)
    local p = BagsProfile() or {}
    local state = p.bagCategoryState and p.bagCategoryState[def.key]
    local cat = {
        _defaultName = def.key,
        name = (state and state.rename) or L(def.name),
        types = {},
        icon = def.icon,
        bindRule = def.rule,
        groupName = state and state.groupName,
        groupNameCustom = state and state.groupNameCustom,
        _bagPlusManaged = true,
    }
    if not state and not seenInOrder then
        cat.groupName = "The Armory"
        cat.groupNameCustom = true
    end
    return cat
end

local function RemoveManagedCategories(cats)
    for i = #cats, 1, -1 do
        local cat = cats[i]
        local disabledRule =
            (cat._defaultName == KEY_WUE and not IsRuleEnabled(RULE_WUE)) or
            (cat._defaultName == KEY_BOE and not IsRuleEnabled(RULE_BOE))
        if cat._bagPlusManaged or disabledRule then
            table.remove(cats, i)
        end
    end
end

local function FindCategory(cats, key)
    for i, cat in ipairs(cats) do
        if cat._defaultName == key then return i, cat end
    end
    return nil, nil
end

local function FindRuleCategory(cats, rule)
    for i, cat in ipairs(cats) do
        if cat.bindRule == rule then return i, cat end
    end
    return nil, nil
end

local function InsertDefaultCategories(cats, missing)
    local insertAt
    for i, cat in ipairs(cats) do
        if cat._defaultName == "Item Set Gear" then
            insertAt = i + 1
            break
        end
    end
    if not insertAt then
        for i, cat in ipairs(cats) do
            if cat._defaultName == "Quest Items" or cat._defaultName == "Weapons / Trinkets" or cat.isCatchAll then
                insertAt = i
                break
            end
        end
    end
    insertAt = insertAt or (#cats + 1)

    for _, cat in ipairs(missing) do
        table.insert(cats, insertAt, cat)
        insertAt = insertAt + 1
    end
end

local function MergeOrderedCategories(cats, managedByKey)
    local p = BagsProfile() or {}
    local order = p.bagCategoryOrder
    if type(order) ~= "table" then return false end

    local currentByKey = {}
    for _, cat in ipairs(cats) do
        currentByKey[cat._defaultName] = cat
    end

    local output, used = {}, {}
    for _, key in ipairs(order) do
        local cat = currentByKey[key] or managedByKey[key]
        if cat and not used[cat] then
            output[#output + 1] = cat
            used[cat] = true
        end
    end
    for _, cat in ipairs(cats) do
        if not used[cat] then
            output[#output + 1] = cat
            used[cat] = true
        end
    end
    for _, def in ipairs(CATEGORY_DEFS) do
        local cat = managedByKey[def.key]
        if cat and not used[cat] then
            output[#output + 1] = cat
            used[cat] = true
        end
    end

    for i = #cats, 1, -1 do cats[i] = nil end
    for i, cat in ipairs(output) do cats[i] = cat end
    return true
end

local function EnsureCategories(manager)
    if not manager or type(manager._categories) ~= "table" then return end
    local cats = manager._categories
    RemoveManagedCategories(cats)
    if not AnyRuleEnabled() then return end

    local missing, managedByKey = {}, {}
    local p = BagsProfile() or {}
    local order = p.bagCategoryOrder
    local ordered = false

    for _, def in ipairs(CATEGORY_DEFS) do
        if IsRuleEnabled(def.rule) then
            if HasOrderKey(order, def.key) then ordered = true end
            if not FindCategory(cats, def.key) then
                local cat = NewManagedCategory(def, HasOrderKey(order, def.key))
                missing[#missing + 1] = cat
                managedByKey[def.key] = cat
            end
        end
    end

    if #missing == 0 then return end
    if not ordered or not MergeOrderedCategories(cats, managedByKey) then
        InsertDefaultCategories(cats, missing)
    end
end

local function IsProtectedOriginalCategory(cat)
    if not cat then return false end
    if cat.bindRule then return true end
    if cat.isReagentBag or cat.isSetGear or cat.isEquipSet then return true end
    if cat._defaultName == "Quest Items" then return true end
    return false
end

local function IsOriginalGearBucket(cat)
    return cat and (cat._defaultName == "Armor" or cat._defaultName == "Weapons / Trinkets")
end

local function FindFallbackGearBucket(cats, itemLink)
    if not (cats and itemLink and GetItemInfoInstant) then return nil end
    local armorClass, weaponClass = ItemClassIDs()
    local _, _, _, equipSlot, _, classID = GetItemInfoInstant(itemLink)
    local target
    if classID == weaponClass or equipSlot == "INVTYPE_TRINKET" then
        target = "Weapons / Trinkets"
    elseif classID == armorClass then
        target = "Armor"
    end
    if not target then return nil end
    for i, cat in ipairs(cats) do
        if cat._defaultName == target then return i end
    end
    return nil
end

local function StampGearSortFields(items)
    if type(items) ~= "table" then return end
    local mode = SortMode()
    for _, data in ipairs(items) do
        if data.itemLink and IsGearLink(data.itemLink) then
            local name, _, quality, ilvl, _, itemType = GetItemInfo(data.itemLink)
            local rawIlvl = ilvl or 0
            data._sortName = name or ""
            data._sortQuality = quality or 0
            data._sortIlvl = mode == "asc" and -rawIlvl or rawIlvl
            data._sortType = itemType or ""
            data._sortTrackRank = mode == "off" and 0 or 1
            data._sortGear = mode ~= "off"
            data._bagPlusIlvl = rawIlvl
            data._sortCached = true
        end
    end
end

local function GearSortCompare(a, b)
    local mode = SortMode()
    local ailvl = a._bagPlusIlvl or 0
    local bilvl = b._bagPlusIlvl or 0
    if ailvl ~= bilvl then
        if mode == "asc" then return ailvl < bilvl end
        return ailvl > bilvl
    end
    if (a._sortQuality or 0) ~= (b._sortQuality or 0) then return (a._sortQuality or 0) > (b._sortQuality or 0) end
    if (a._sortName or "") ~= (b._sortName or "") then return (a._sortName or "") < (b._sortName or "") end
    local ai = (a.info and a.info.itemID) or 0
    local bi = (b.info and b.info.itemID) or 0
    if ai ~= bi then return ai < bi end
    if a.bag ~= b.bag then return a.bag < b.bag end
    return a.slot < b.slot
end

local function IsBagPlusGearCategory(cat)
    if not cat then return false end
    return cat.bindRule
        or cat.isSetGear
        or cat.isEquipSet
        or cat._defaultName == "Armor"
        or cat._defaultName == "Weapons / Trinkets"
end

local function SaveOrder(order, key, items)
    local list = {}
    for i, data in ipairs(items) do
        list[i] = data.info and data.info.itemID or 0
    end
    order[key] = list
end

local function ClearGearVisualOrder()
    local p = BagsProfile()
    local manager = _G.EUI_CategoryManager
    if not (p and type(p.bagVisualOrder) == "table" and manager and manager.GetCategories) then return end

    local cats = manager:GetCategories()
    local order = p.bagVisualOrder
    local doneGroups = {}

    for ci, cat in ipairs(cats) do
        if IsBagPlusGearCategory(cat) then
            order[ci] = nil
        end

        local groupName = cat.groupName
        if groupName and not doneGroups[groupName] then
            doneGroups[groupName] = true
            local members = manager.GetGroupMembers and manager:GetGroupMembers(groupName)
            local allGear = members and #members > 0
            if allGear then
                for _, mi in ipairs(members) do
                    if not IsBagPlusGearCategory(cats[mi]) then
                        allGear = false
                        break
                    end
                end
            end
            if allGear then
                order[groupName] = nil
            end
        end
    end
end

local function RefreshGearVisualOrder()
    if refreshingOrder or not SortEnabled() then return end
    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then return end
    local manager = _G.EUI_CategoryManager
    if not (manager and manager.ClassifyAll and manager.GetCategories) then return end
    local p = BagsProfile()
    if not p then return end

    refreshingOrder = true

    local items = {}
    for bag = 0, 5 do
        local numSlots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info then
                local itemLink = C_Container.GetContainerItemLink(bag, slot)
                items[#items + 1] = { bag = bag, slot = slot, info = info, itemLink = itemLink }
            end
        end
    end

    manager:ClassifyAll(items)
    StampGearSortFields(items)

    local cats = manager:GetCategories()
    local byCat = {}
    for i = 1, #cats do byCat[i] = {} end
    for _, data in ipairs(items) do
        local ci = data.categoryIndex
        if ci and byCat[ci] then
            byCat[ci][#byCat[ci] + 1] = data
        end
    end

    if type(p.bagVisualOrder) ~= "table" then p.bagVisualOrder = {} end
    local order = p.bagVisualOrder
    local doneGroups = {}

    for ci, cat in ipairs(cats) do
        if IsBagPlusGearCategory(cat) then
            local catItems = byCat[ci] or {}
            if #catItems > 1 then table.sort(catItems, GearSortCompare) end
            SaveOrder(order, ci, catItems)
        end

        local groupName = cat.groupName
        if groupName and not doneGroups[groupName] then
            doneGroups[groupName] = true
            local members = manager:GetGroupMembers(groupName)
            local allGear = members and #members > 0
            if allGear then
                for _, mi in ipairs(members) do
                    if not IsBagPlusGearCategory(cats[mi]) then
                        allGear = false
                        break
                    end
                end
            end
            if allGear then
                local merged = {}
                for _, mi in ipairs(members) do
                    for _, data in ipairs(byCat[mi] or {}) do
                        merged[#merged + 1] = data
                    end
                    if cats[mi] and cats[mi].isSetGear and not cats[mi].isEquipSet and p.bagSplitSetGearBySet then
                        for i, c in ipairs(cats) do
                            if c.isEquipSet then
                                for _, data in ipairs(byCat[i] or {}) do
                                    merged[#merged + 1] = data
                                end
                            end
                        end
                    end
                end
                if #merged > 1 then table.sort(merged, GearSortCompare) end
                SaveOrder(order, groupName, merged)
            end
        end
    end

    refreshingOrder = nil
end

local function RefreshBags()
    if _G.EUI_Bags and EUI_Bags.RefreshInventory and EUI_Bags:IsVisible() then
        EUI_Bags:RefreshInventory()
    end
    if _G.EUI_Bank and EUI_Bank.RefreshBank and EUI_Bank:IsVisible() then
        EUI_Bank:RefreshBank()
    end
end

local BAG_SLOT_SIZE = 34
local BAG_SLOT_SPACING = 4
local BAG_SECTION_HEADER_H = 22
local BAG_SUBHEADER_H = 18
local BAG_SECTION_GAP = 6
local BAG_GRID_START_X = 15
local BAG_COMPACT_MIN_COLUMNS = 2
local BAG_COMPACT_MAX_ROWS = 2
local BAG_HEADER_H = 35
local BAG_FOOTER_H = 28
local BAG_POST_LAYOUT_AUTOSIZE_MIN_H = 260

local function SelectedAllItemsView()
    local sidebar = _G.EUI_Bags and (EUI_Bags._sidebarChild or EUI_Bags._sidebar)
    if not sidebar or not sidebar.GetChildren then return false end
    local children = { sidebar:GetChildren() }
    for _, child in ipairs(children) do
        if child and child._indicator and child._indicator.IsShown and child._indicator:IsShown() then
            return child._catIdx == 0 and not child._isGroupHeader
        end
    end
    return false
end

local function BagGridColumns()
    local p = BagsProfile() or {}
    local columns = (p.bagAutoSize and _G.EUI_Bags and EUI_Bags._asCols) or p.bagColumns or 12
    columns = tonumber(columns) or 12
    if columns < 1 then columns = 12 end
    return math.floor(columns)
end

local function FrameTopLeft(frame)
    if not frame or not frame.GetPoint then return nil, nil end
    local _, _, _, x, y = frame:GetPoint(1)
    return x, y
end

local function SetFrameTopLeft(frame, parent, x, y)
    if not (frame and parent) then return end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
end

local function SetRegionShown(region, shown)
    if not region then return end
    if shown then
        if region.Show then region:Show() end
    elseif region.Hide then
        region:Hide()
    end
end

local function SetCompactHeader(header, compact)
    if not header then return end
    SetRegionShown(header._line, not compact)
end

local function FrameHeight(frame, fallback)
    if frame and frame.GetHeight then
        local height = frame:GetHeight()
        if type(height) == "number" and height > 0 then return height end
    end
    return fallback
end

local function OffsetFrame(frame, dx, dy)
    if not frame or not frame.GetPoint then return end
    local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
    if not point or type(x) ~= "number" or type(y) ~= "number" then return end
    frame:ClearAllPoints()
    if relativeTo then
        frame:SetPoint(point, relativeTo, relativePoint, x + dx, y + dy)
    else
        frame:SetPoint(point, x + dx, y + dy)
    end
end

local function IsCategoryHeader(frame)
    return frame and frame._label and frame._hint and frame._line
end

local function IsExpansionSubHeader(frame)
    return frame and frame._label and not frame._line and frame.GetObjectType
        and frame:GetObjectType() == "Frame"
end

local function IsSlotParent(frame)
    if not (frame and frame.GetChildren and frame.GetWidth and frame.GetHeight and frame:IsShown()) then
        return false
    end
    if math.abs((frame:GetWidth() or 0) - BAG_SLOT_SIZE) > 1 then return false end
    if math.abs((frame:GetHeight() or 0) - BAG_SLOT_SIZE) > 1 then return false end
    return select("#", frame:GetChildren()) > 0
end

local function IsEmptyPad(frame)
    if not (frame and frame.GetChildren and frame.GetWidth and frame.GetHeight and frame:IsShown()) then
        return false
    end
    if not frame._bg then return false end
    if math.abs((frame:GetWidth() or 0) - BAG_SLOT_SIZE) > 1 then return false end
    if math.abs((frame:GetHeight() or 0) - BAG_SLOT_SIZE) > 1 then return false end
    return select("#", frame:GetChildren()) == 0
end

local function SectionIsSpecial(section)
    local hdr = section and section.header
    if not hdr then return true end
    if hdr._hideBtn and hdr._hideBtn.IsShown and hdr._hideBtn:IsShown() then return true end
    if hdr._hint and hdr._hint.GetText and (hdr._hint:GetText() or "") ~= "" then return true end
    return false
end

local function SectionSpan(section, columns, stride)
    local slotCount = #section.slots
    if slotCount > columns * BAG_COMPACT_MAX_ROWS then return columns, true end

    local labelWidth = 0
    local label = section.header and section.header._label
    if label and label.GetStringWidth then
        labelWidth = label:GetStringWidth() or 0
    end

    local minForLabel = math.ceil((labelWidth + 24) / stride)
    local minForItems = slotCount <= columns and slotCount or math.ceil(slotCount / BAG_COMPACT_MAX_ROWS)
    local span = math.max(BAG_COMPACT_MIN_COLUMNS, minForItems, minForLabel)
    if span > columns then span = columns end
    return span, false
end

local function SectionContentHeight(section, stride)
    local height = BAG_SECTION_HEADER_H
    local pads = {}
    for _, frame in ipairs(section.pads) do
        pads[frame] = true
    end

    for _, frame in ipairs(section.frames) do
        local _, y = FrameTopLeft(frame)
        if type(y) == "number" then
            local extent
            if frame == section.header then
                extent = BAG_SECTION_HEADER_H
            elseif IsSlotParent(frame) then
                extent = section.y - y + stride
            elseif IsExpansionSubHeader(frame) then
                extent = section.y - y + BAG_SUBHEADER_H
            elseif not pads[frame] and frame.GetHeight then
                extent = section.y - y + (frame:GetHeight() or 0)
            end
            if extent and extent > height then height = extent end
        end
    end
    return height + BAG_SECTION_GAP
end

local function HeaderText(header)
    local label = header and header._label
    if label and label.GetText then return label:GetText() or "" end
    return ""
end

local function IsRecentSection(section)
    return HeaderText(section and section.header) == L("Recent Items")
end

local function ShouldHideEmptyRecentSection(section)
    return HideEmptyRecentItemsEnabled()
        and IsRecentSection(section)
        and #section.slots == 0
        and #section.subheaders == 0
end

local function HideSection(section)
    for _, frame in ipairs(section.frames) do
        if frame.Hide then frame:Hide() end
    end
end

local function CollectRenderedSections(child)
    if not (child and child.GetChildren) then return nil end

    local children = { child:GetChildren() }
    local headers = {}
    for _, frame in ipairs(children) do
        if frame:IsShown() and IsCategoryHeader(frame) then
            local x, y = FrameTopLeft(frame)
            if type(x) == "number" and type(y) == "number" then
                headers[#headers + 1] = { frame = frame, x = x, y = y }
            end
        end
    end
    if #headers == 0 then return nil end

    table.sort(headers, function(a, b)
        if a.y ~= b.y then return a.y > b.y end
        return a.x < b.x
    end)

    local columns = BagGridColumns()
    local stride = BAG_SLOT_SIZE + BAG_SLOT_SPACING
    local startX = headers[1].x or BAG_GRID_START_X
    local rowEndX = startX + columns * stride + 1
    local originalBottom = -(child:GetHeight() or 1) + 10
    local headerRows = {}
    for _, entry in ipairs(headers) do
        local row = headerRows[#headerRows]
        if not row or math.abs((row.y or 0) - entry.y) > 1 then
            row = { y = entry.y, entries = {} }
            headerRows[#headerRows + 1] = row
        end
        row.entries[#row.entries + 1] = entry
    end

    local sections = {}
    for rowIndex, row in ipairs(headerRows) do
        local nextY = headerRows[rowIndex + 1] and headerRows[rowIndex + 1].y or originalBottom
        for entryIndex, entry in ipairs(row.entries) do
            local nextX = row.entries[entryIndex + 1] and row.entries[entryIndex + 1].x or rowEndX
            local section = {
                header = entry.frame,
                x = entry.x,
                y = entry.y,
                nextY = nextY,
                height = math.max(0, entry.y - nextY),
                slots = {},
                pads = {},
                subheaders = {},
                frames = { entry.frame },
            }

            for _, frame in ipairs(children) do
                if frame ~= entry.frame and frame:IsShown() then
                    local fx, fy = FrameTopLeft(frame)
                    if type(fx) == "number" and type(fy) == "number"
                       and fy < entry.y and fy > nextY
                       and fx >= entry.x - 1 and fx < nextX - 1 then
                        if IsEmptyPad(frame) then
                            section.pads[#section.pads + 1] = frame
                            section.frames[#section.frames + 1] = frame
                        elseif IsSlotParent(frame) then
                            section.slots[#section.slots + 1] = frame
                            section.frames[#section.frames + 1] = frame
                        elseif IsExpansionSubHeader(frame) then
                            section.subheaders[#section.subheaders + 1] = frame
                            section.frames[#section.frames + 1] = frame
                        end
                    end
                end
            end

            table.sort(section.slots, function(a, b)
                local ax, ay = FrameTopLeft(a)
                local bx, by = FrameTopLeft(b)
                if ay ~= by then return (ay or 0) > (by or 0) end
                return (ax or 0) < (bx or 0)
            end)
            sections[#sections + 1] = section
        end
    end

    return sections, headers, columns, stride, startX, children
end

local function RestoreCategoryHeaderLines()
    local child = _G.EUI_Bags and EUI_Bags._scrollChild
    if not (child and child.GetChildren) then return end
    local children = { child:GetChildren() }
    for _, frame in ipairs(children) do
        if frame:IsShown() and IsCategoryHeader(frame) then
            SetCompactHeader(frame, false)
        end
    end
end

local function ApplyPostLayoutAutoSize(contentH)
    local p = BagsProfile() or {}
    if p.bagAutoSize ~= true then return end
    if not (_G.EUI_Bags and EUI_Bags.SetHeight) then return end

    local headerH = FrameHeight(EUI_Bags.Header, BAG_HEADER_H)
    local footerH = EUI_Bags._footerH or FrameHeight(EUI_Bags.Footer, BAG_FOOTER_H)
    local targetH = contentH + headerH + footerH + 2

    local sc = EUI_Bags.GetScale and EUI_Bags:GetScale() or 1
    if not sc or sc <= 0 then sc = 1 end
    if UIParent and UIParent.GetHeight then
        targetH = math.min(targetH, (UIParent:GetHeight() / sc) * 0.95)
    end
    targetH = math.max(BAG_POST_LAYOUT_AUTOSIZE_MIN_H, targetH)

    EUI_Bags._asMaxH = targetH
    EUI_Bags:SetHeight(targetH)
end

local function UpdateBagScrollRange()
    if EUI_Bags._scrollFrame then
        local sf = EUI_Bags._scrollFrame
        sf:SetVerticalScroll(math.min(sf:GetVerticalScroll(), sf:GetVerticalScrollRange() or 0))
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if _G.EUI_Bags and EUI_Bags._updateThumb then EUI_Bags._updateThumb() end
        end)
    elseif EUI_Bags._updateThumb then
        EUI_Bags._updateThumb()
    end
end

local function ApplyHideEmptyRecentItems()
    if not HideEmptyRecentItemsEnabled() then return end
    if not (_G.EUI_Bags and EUI_Bags:IsVisible() and SelectedAllItemsView()) then return end

    local child = EUI_Bags._scrollChild
    local sections, _, _, _, _, children = CollectRenderedSections(child)
    if not sections then return end

    local hiddenFrames = {}
    local hiddenSections = {}
    local totalHiddenHeight = 0
    for _, section in ipairs(sections) do
        if ShouldHideEmptyRecentSection(section) then
            HideSection(section)
            hiddenSections[#hiddenSections + 1] = section
            totalHiddenHeight = totalHiddenHeight + section.height
            for _, frame in ipairs(section.frames) do
                hiddenFrames[frame] = true
            end
        end
    end
    if totalHiddenHeight <= 0 then return end

    for _, frame in ipairs(children) do
        if not hiddenFrames[frame] and frame:IsShown() then
            local _, y = FrameTopLeft(frame)
            if type(y) == "number" then
                local dy = 0
                for _, section in ipairs(hiddenSections) do
                    if y <= section.nextY + 1 then
                        dy = dy + section.height
                    end
                end
                if dy > 0 then OffsetFrame(frame, 0, dy) end
            end
        end
    end

    local contentH = math.max(1, FrameHeight(child, 1) - totalHiddenHeight)
    child:SetHeight(contentH)
    ApplyPostLayoutAutoSize(contentH)
    UpdateBagScrollRange()
end

local function ApplyCompactCategoryRows()
    if not CompactCategoryRowsEnabled() then return end
    if not (_G.EUI_Bags and EUI_Bags:IsVisible() and SelectedAllItemsView()) then return end

    local child = EUI_Bags._scrollChild
    local sections, headers, columns, stride, startX = CollectRenderedSections(child)
    if not sections then return end

    local curY = headers[1].y or -6
    local rowUsed = 0
    local rowHeight = 0
    local rowTop = curY

    local function FlushCompactRow()
        if rowUsed == 0 then return end
        curY = rowTop - rowHeight - BAG_SECTION_GAP
        rowUsed = 0
        rowHeight = 0
        rowTop = curY
    end

    local function PreserveFullWidthSection(section, keepPads)
        FlushCompactRow()
        SetCompactHeader(section.header, false)
        local height = keepPads and section.height or SectionContentHeight(section, stride)
        local dx = startX - section.x
        local dy = curY - section.y
        for _, frame in ipairs(section.frames) do
            OffsetFrame(frame, dx, dy)
            if IsEmptyPad(frame) then
                frame:SetShown(keepPads == true)
            end
        end
        curY = curY - height
        rowTop = curY
    end

    local function PlaceCompactSection(section, span)
        local slotCount = #section.slots
        if slotCount == 0 then
            PreserveFullWidthSection(section)
            return
        end

        if rowUsed > 0 and rowUsed + span > columns then
            FlushCompactRow()
        end

        local x = startX + rowUsed * stride
        local width = span * stride
        SetFrameTopLeft(section.header, child, x, rowTop)
        section.header:SetWidth(width)
        SetCompactHeader(section.header, true)

        local sectionHeaderH = BAG_SECTION_HEADER_H
        if #section.subheaders == 1 then
            sectionHeaderH = sectionHeaderH + BAG_SUBHEADER_H
            local subheader = section.subheaders[1]
            SetFrameTopLeft(subheader, child, x, rowTop - BAG_SECTION_HEADER_H)
            subheader:SetWidth(width)
        end

        for index, slot in ipairs(section.slots) do
            local col = (index - 1) % span
            local row = math.floor((index - 1) / span)
            SetFrameTopLeft(slot, child, x + col * stride, rowTop - sectionHeaderH - row * stride)
        end

        for _, pad in ipairs(section.pads) do
            pad:Hide()
        end

        rowUsed = rowUsed + span
        rowHeight = math.max(rowHeight, sectionHeaderH + math.ceil(slotCount / span) * stride)
    end

    for _, section in ipairs(sections) do
        if ShouldHideEmptyRecentSection(section) then
            HideSection(section)
        else
            local span, fullWidth = SectionSpan(section, columns, stride)
            local complex = #section.subheaders > 1
            local special = SectionIsSpecial(section)
            if fullWidth or complex or special then
                PreserveFullWidthSection(section, special)
            else
                PlaceCompactSection(section, span)
            end
        end
    end
    FlushCompactRow()

    local contentH = math.abs(curY) + 10
    child:SetHeight(contentH)
    ApplyPostLayoutAutoSize(contentH)
    UpdateBagScrollRange()
end

local function Print(msg)
    if EllesmereUI and EllesmereUI.Print then
        EllesmereUI.Print(msg)
    else
        print(msg)
    end
end

local function RebuildBagPlus()
    ClearGearVisualOrder()
    if _G.EUI_CategoryManager and EUI_CategoryManager.InitCategories then
        EUI_CategoryManager:InitCategories()
    end
    RefreshGearVisualOrder()
    RefreshBags()
end

local function PatchManager()
    local manager = _G.EUI_CategoryManager
    if patched or not manager then return patched end

    manager._BagPlusOriginalInitCategories = manager._BagPlusOriginalInitCategories or manager.InitCategories
    manager._BagPlusOriginalGetCategories = manager._BagPlusOriginalGetCategories or manager.GetCategories
    manager._BagPlusOriginalClassifyItem = manager._BagPlusOriginalClassifyItem or manager.ClassifyItem
    manager._BagPlusOriginalClassifyAll = manager._BagPlusOriginalClassifyAll or manager.ClassifyAll

    function manager:InitCategories(...)
        local result = self:_BagPlusOriginalInitCategories(...)
        EnsureCategories(self)
        return result
    end

    function manager:GetCategories(...)
        local cats = self:_BagPlusOriginalGetCategories(...)
        EnsureCategories(self)
        return cats
    end

    function manager:ClassifyItem(itemLink, itemID, bag, slot, itemInfo, ...)
        local idx = self:_BagPlusOriginalClassifyItem(itemLink, itemID, bag, slot, itemInfo, ...)

        local cats = self:GetCategories()
        local originalCat = idx and cats[idx]
        local assignments = itemID and EllesmereUIDB and EllesmereUIDB.bagItemAssignments
        if assignments and assignments[itemID] then return idx end
        if originalCat and originalCat.bindRule and not IsRuleEnabled(originalCat.bindRule) then
            return FindFallbackGearBucket(cats, itemLink) or idx
        end
        if IsProtectedOriginalCategory(originalCat) and not IsOriginalGearBucket(originalCat) then return idx end
        if originalCat and not IsOriginalGearBucket(originalCat) and not originalCat.bindRule then return idx end

        local rule = GetBindRule(itemLink, itemInfo, bag, slot)
        if not rule or not IsRuleEnabled(rule) then return idx end
        local ruleIdx = FindRuleCategory(cats, rule)
        return ruleIdx or idx
    end

    function manager:ClassifyAll(items, ...)
        local counts, total = self:_BagPlusOriginalClassifyAll(items, ...)
        StampGearSortFields(items)
        return counts, total
    end

    manager:InitCategories()
    patched = true
    return true
end

local function PatchRefresh()
    if refreshPatched or not (_G.EUI_Bags and EUI_Bags.RefreshInventory) then return refreshPatched end
    local originalRefresh = EUI_Bags.RefreshInventory
    EUI_Bags.RefreshInventory = function(self, ...)
        RefreshGearVisualOrder()
        local result = originalRefresh(self, ...)
        if CompactCategoryRowsEnabled() then
            pcall(ApplyCompactCategoryRows)
        else
            pcall(RestoreCategoryHeaderLines)
            if HideEmptyRecentItemsEnabled() then
                pcall(ApplyHideEmptyRecentItems)
            end
        end
        return result
    end
    refreshPatched = true
    return true
end

local function EnsureSidebarEntry()
    local EUI = EllesmereUI
    if not EUI then return end

    local info = {
        folder = ADDON_NAME,
        display = "BagPlus",
        search_name = "BagPlus for EllesmereUI bags boe warbound item level gear",
        alwaysLoaded = true,
    }

    if type(EUI.ADDON_ROSTER) == "table" then
        local exists
        for _, entry in ipairs(EUI.ADDON_ROSTER) do
            if entry.folder == ADDON_NAME then
                exists = true
                break
            end
        end
        if not exists then EUI.ADDON_ROSTER[#EUI.ADDON_ROSTER + 1] = info end
    end

    if type(EUI._addonInfoByFolder) == "table" then
        EUI._addonInfoByFolder[ADDON_NAME] = info
    end

    if type(EUI.ADDON_GROUPS) == "table" then
        local group
        for _, g in ipairs(EUI.ADDON_GROUPS) do
            if g.key == GROUP_KEY then
                group = g
                break
            end
        end
        if not group then
            group = { key = GROUP_KEY, label = "BagPlus", members = {} }
            EUI.ADDON_GROUPS[#EUI.ADDON_GROUPS + 1] = group
        end
        local inGroup
        for _, folder in ipairs(group.members) do
            if folder == ADDON_NAME then
                inGroup = true
                break
            end
        end
        if not inGroup then group.members[#group.members + 1] = ADDON_NAME end
    end
end

local function RegisterOptions()
    local EUI = EllesmereUI
    if not EUI then return end
    EnsureSidebarEntry()

    local config = {
        title = TITLE,
        description = "Adds Warbound Gear and BoE Gear categories to EllesmereUI Bags, sorts gear by item level, and can compact short category rows.",
        searchTerms = "bagplus bags boe warbound wue gear item level sort compact condensed category rows recent empty",
        pages = { PAGE },
        _euiCore = false,
        buildPage = function(pageName, parent, yOffset)
            if pageName ~= PAGE then return 0 end
            local W = EllesmereUI.Widgets
            if not W then return 0 end
            local y = yOffset
            local _, h

            _, h = W:SectionHeader(parent, "BAGPLUS", y); y = y - h
            _, h = W:Toggle(parent, "Warbound Gear Category", y,
                function() return DB().wueEnabled ~= false end,
                function(v)
                    DB().wueEnabled = v and true or false
                    DB().enabled = AnyRuleEnabled()
                    RebuildBagPlus()
                end,
                "Adds a Warbound Gear category for unbound Warbound-until-Equipped armor and weapons."
            ); y = y - h

            _, h = W:Toggle(parent, "BoE Gear Category", y,
                function() return DB().boeEnabled ~= false end,
                function(v)
                    DB().boeEnabled = v and true or false
                    DB().enabled = AnyRuleEnabled()
                    RebuildBagPlus()
                end,
                "Adds a BoE Gear category for unbound Bind-on-Equip armor and weapons."
            ); y = y - h

            _, h = W:Dropdown(parent, "Gear Sort", y,
                ILVL_SORT_VALUES,
                function() return SortMode() end,
                function(v)
                    local mode = (v == "asc" or v == "off") and v or "desc"
                    local db = DB()
                    if db.ilvlSort == mode then return end
                    db.ilvlSort = mode
                    db.sortGearByItemLevel = mode ~= "off"
                    RebuildBagPlus()
                end,
                ILVL_SORT_ORDER,
                "Choose whether armor and weapons sort by highest item level first, lowest first, or use EllesmereUI's normal gear order."
            ); y = y - h

            _, h = W:Toggle(parent, "Compact Category Rows", y,
                function() return CompactCategoryRowsEnabled() end,
                function(v)
                    DB().compactCategoryRows = v and true or false
                    RebuildBagPlus()
                end,
                "In the All Items view, lets short category sections share a row from left to right instead of reserving one full row per category."
            ); y = y - h

            _, h = W:Toggle(parent, "Hide Empty Recent Items", y,
                function() return HideEmptyRecentItemsEnabled() end,
                function(v)
                    DB().hideEmptyRecentItems = v and true or false
                    RebuildBagPlus()
                end,
                "Temporarily hides the Recent Items quickview when it has no items, without changing EllesmereUI's own Recent Items setting."
            ); y = y - h

            _, h = W:Button(parent, "Refresh BagPlus", y, function()
                RebuildBagPlus()
            end); y = y - h

            return math.abs(y)
        end,
        onReset = function()
            DB().enabled = true
            DB().wueEnabled = true
            DB().boeEnabled = true
            DB().ilvlSort = "desc"
            DB().sortGearByItemLevel = true
            DB().compactCategoryRows = false
            DB().hideEmptyRecentItems = true
            RebuildBagPlus()
        end,
    }

    if EUI.RegisterModule then
        pcall(EUI.RegisterModule, EUI, ADDON_NAME, config)
    end
    if type(EUI._modules) == "table" and not EUI._modules[ADDON_NAME] then
        EUI._modules[ADDON_NAME] = config
    end
end

local function TryPatch()
    PatchManager()
    PatchRefresh()
    RegisterOptions()
    RefreshGearVisualOrder()
end

local retries = 0
local function RetryPatch()
    TryPatch()
    if patched and refreshPatched then return end
    retries = retries + 1
    if retries <= 20 and C_Timer and C_Timer.After then
        C_Timer.After(0.25, RetryPatch)
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event, addon)
    if event == "ADDON_LOADED" and addon ~= ADDON_NAME and addon ~= "EllesmereUIBags" and addon ~= "EllesmereUI" then
        return
    end
    RetryPatch()
end)

SLASH_BAGPLUSFORELLESMEREUI1 = "/bagplus"
SlashCmdList.BAGPLUSFORELLESMEREUI = function(msg)
    local args = {}
    for token in tostring(msg or ""):lower():gmatch("%S+") do
        args[#args + 1] = token
    end

    local cmd = args[1]
    local arg = args[2]
    local function OnOff(v) return v and "on" or "off" end
    local function PrintStatus()
        local db = DB()
        Print("|cff6fe7c5BagPlus|r boe " .. OnOff(db.boeEnabled ~= false)
            .. ", wue " .. OnOff(db.wueEnabled ~= false)
            .. ", ilvl " .. SortMode()
            .. ", compact " .. OnOff(CompactCategoryRowsEnabled())
            .. ", hide empty recent " .. OnOff(HideEmptyRecentItemsEnabled()))
    end
    local function PrintHelp()
        Print("|cff6fe7c5BagPlus|r /bagplus boe on|off")
        Print("|cff6fe7c5BagPlus|r /bagplus wue on|off")
        Print("|cff6fe7c5BagPlus|r /bagplus ilvl asc|desc|off")
        Print("|cff6fe7c5BagPlus|r /bagplus compact on|off")
        Print("|cff6fe7c5BagPlus|r /bagplus emptyrecent on|off")
        Print("|cff6fe7c5BagPlus|r /bagplus refresh")
    end

    if cmd == "boe" or cmd == "wue" then
        if arg ~= "on" and arg ~= "off" then
            local current = cmd == "boe" and DB().boeEnabled ~= false or DB().wueEnabled ~= false
            Print("|cff6fe7c5BagPlus|r " .. cmd .. " is " .. OnOff(current))
            Print("|cff6fe7c5BagPlus|r /bagplus " .. cmd .. " on|off")
            return
        end

        local enabled = arg == "on"
        if cmd == "boe" then
            DB().boeEnabled = enabled
            Print("|cff6fe7c5BagPlus|r BoE Gear: " .. arg)
        else
            DB().wueEnabled = enabled
            Print("|cff6fe7c5BagPlus|r Warbound Gear: " .. arg)
        end
        DB().enabled = AnyRuleEnabled()
        RebuildBagPlus()
        return
    end

    if cmd == "ilvl" then
        if arg ~= "asc" and arg ~= "desc" and arg ~= "off" then
            Print("|cff6fe7c5BagPlus|r ilvl is " .. SortMode())
            Print("|cff6fe7c5BagPlus|r /bagplus ilvl asc|desc|off")
            return
        end
        DB().ilvlSort = arg
        DB().sortGearByItemLevel = arg ~= "off"
        RebuildBagPlus()
        Print("|cff6fe7c5BagPlus|r Item level sort: " .. arg)
        return
    end

    if cmd == "compact" or cmd == "condensed" then
        if arg ~= "on" and arg ~= "off" then
            Print("|cff6fe7c5BagPlus|r compact is " .. OnOff(CompactCategoryRowsEnabled()))
            Print("|cff6fe7c5BagPlus|r /bagplus compact on|off")
            return
        end
        DB().compactCategoryRows = arg == "on"
        RebuildBagPlus()
        Print("|cff6fe7c5BagPlus|r Compact Category Rows: " .. arg)
        return
    end

    if cmd == "emptyrecent" or cmd == "recentempty" then
        if arg ~= "on" and arg ~= "off" then
            Print("|cff6fe7c5BagPlus|r hide empty recent is " .. OnOff(HideEmptyRecentItemsEnabled()))
            Print("|cff6fe7c5BagPlus|r /bagplus emptyrecent on|off")
            return
        end
        DB().hideEmptyRecentItems = arg == "on"
        RebuildBagPlus()
        Print("|cff6fe7c5BagPlus|r Hide Empty Recent Items: " .. arg)
        return
    end

    if cmd == "refresh" then
        TryPatch()
        RebuildBagPlus()
        Print("|cff6fe7c5BagPlus|r refreshed.")
        return
    end

    if cmd == "status" or not cmd then
        PrintStatus()
        PrintHelp()
        return
    end

    PrintHelp()
end
