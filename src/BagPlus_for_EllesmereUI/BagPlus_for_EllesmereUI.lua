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

local MAX_ITEMS_PER_ROW_MIN = 5
local MAX_ITEMS_PER_ROW_MAX = 17
local MAX_ITEMS_PER_ROW_DEFAULT = 12

local function NormalizeMaxItemsPerRow(value)
    local n = tonumber(value) or MAX_ITEMS_PER_ROW_DEFAULT
    n = math.floor(n + 0.5)
    if n < MAX_ITEMS_PER_ROW_MIN then n = MAX_ITEMS_PER_ROW_MIN end
    if n > MAX_ITEMS_PER_ROW_MAX then n = MAX_ITEMS_PER_ROW_MAX end
    return n
end

local patched
local refreshPatched
local reagentButtonPatched
local refreshingOrder
local reagentMoveLocked
local Print

local REAGENT_BAG_ID = 5
local REAGENT_MOVE_DELAY = 0.08
local REAGENT_MOVE_RETRY_LIMIT = 80
local REAGENT_BUTTON_ICON = 3622222
local REAGENT_BUTTON_MASK = "Interface\\AddOns\\EllesmereUI\\media\\portraits\\circle_mask.tga"

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
    if BagPlusForEllesmereUIDB.limitItemsPerRow == nil then
        BagPlusForEllesmereUIDB.limitItemsPerRow = false
    end
    BagPlusForEllesmereUIDB.maxItemsPerRow = NormalizeMaxItemsPerRow(BagPlusForEllesmereUIDB.maxItemsPerRow)
    BagPlusForEllesmereUIDB.maxBagColumns = nil
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

local function LimitItemsPerRowEnabled()
    return DB().limitItemsPerRow == true
end

local function MaxItemsPerRow()
    return NormalizeMaxItemsPerRow(DB().maxItemsPerRow)
end

local function ItemsPerRowLimit()
    if not LimitItemsPerRowEnabled() then return nil end
    return MaxItemsPerRow()
end

local function ApplyItemsPerRowLimit(columns)
    columns = math.floor(tonumber(columns) or MAX_ITEMS_PER_ROW_DEFAULT)
    if columns < 1 then columns = MAX_ITEMS_PER_ROW_DEFAULT end

    local limit = ItemsPerRowLimit()
    if limit and columns > limit then
        return limit
    end
    return columns
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

local function RefreshBagWindows()
    RefreshBags()
    if _G.EUI_BagsReagent and EUI_BagsReagent.RefreshInventory and EUI_BagsReagent:IsVisible() then
        EUI_BagsReagent:RefreshInventory()
    end
end

local function ReadItemDetails(item)
    if not item then return nil, 1, nil, nil end

    local name, maxStack, classID, isCraftingReagent
    if C_Item and C_Item.GetItemInfo then
        local itemName, itemLink, itemQuality, itemLevel, itemMinLevel, itemType, itemSubType,
              itemStackCount, itemEquipLoc, itemTexture, sellPrice, itemClassID, itemSubClassID,
              bindType, expansionID, setID, reagent = C_Item.GetItemInfo(item)
        name = itemName
        maxStack = itemStackCount
        classID = itemClassID
        isCraftingReagent = reagent
    end

    if not name and GetItemInfo then
        local itemName, itemLink, itemQuality, itemLevel, itemMinLevel, itemType, itemSubType,
              itemStackCount, itemEquipLoc, itemTexture, sellPrice, itemClassID, itemSubClassID,
              bindType, expansionID, setID, reagent = GetItemInfo(item)
        name = itemName
        maxStack = itemStackCount or maxStack
        classID = itemClassID or classID
        isCraftingReagent = reagent
    end

    if not classID and GetItemInfoInstant then
        local itemID, itemType, itemSubType, itemEquipLoc, icon, instantClassID = GetItemInfoInstant(item)
        classID = instantClassID
    end

    maxStack = tonumber(maxStack) or 1
    if maxStack < 1 then maxStack = 1 end
    return name, maxStack, classID, isCraftingReagent
end

local function IsCraftingReagent(itemLink, itemID)
    local item = itemLink or itemID
    local name, _, classID, reagent = ReadItemDetails(item)
    if reagent ~= nil then return reagent == true end

    -- If full item data is not cached yet, keep the fallback conservative.
    local ic = Enum and Enum.ItemClass
    return not name and ic and classID == ic.Reagent
end

local function ContainerItemLink(bag, slot, info)
    if C_Container and C_Container.GetContainerItemLink then
        return C_Container.GetContainerItemLink(bag, slot)
    end
    return info and info.hyperlink
end

local function StackKey(itemID, itemLink)
    if itemLink and itemLink ~= "" then return itemLink end
    return itemID and ("item:" .. itemID) or nil
end

local function CursorOccupied()
    if GetCursorInfo then
        local cursorType = GetCursorInfo()
        return cursorType ~= nil
    end
    if CursorHasItem then return CursorHasItem() end
    return false
end

local function SlotIsLocked(bag, slot, info)
    if info and info.isLocked then return true end
    if not (C_Item and C_Item.IsLocked and ItemLocation and ItemLocation.CreateFromBagAndSlot) then
        return false
    end
    local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
    return loc and C_Item.IsLocked(loc) or false
end

local function SlotData(bag, slot, info)
    local itemLink = ContainerItemLink(bag, slot, info)
    local itemID = info and info.itemID
    local _, maxStack = ReadItemDetails(itemLink or itemID)
    return {
        bag = bag,
        slot = slot,
        info = info,
        itemID = itemID,
        itemLink = itemLink,
        stackCount = tonumber(info and info.stackCount) or 1,
        maxStack = maxStack,
        stackKey = StackKey(itemID, itemLink),
    }
end

local function HasStackRoom(data)
    return data and data.itemID and data.stackKey and data.maxStack > 1
        and data.stackCount < data.maxStack
end

local function AddPartial(partialByKey, partialKeys, data)
    local key = data and data.stackKey
    if not key then return end
    if not partialByKey[key] then
        partialByKey[key] = {}
        partialKeys[#partialKeys + 1] = key
    end
    partialByKey[key][#partialByKey[key] + 1] = data
end

local function SortPartialsByRoom(a, b)
    if a.stackCount ~= b.stackCount then return a.stackCount < b.stackCount end
    return a.slot < b.slot
end

local function BuildReagentMoveState()
    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then
        return nil, "missing-api"
    end

    local reagentSlots = C_Container.GetContainerNumSlots(REAGENT_BAG_ID) or 0
    if reagentSlots <= 0 then return nil, "no-reagent-bag" end

    local emptySlots = {}
    local partialByKey = {}
    local partialKeys = {}
    local lockedCount = 0
    for slot = 1, reagentSlots do
        local info = C_Container.GetContainerItemInfo(REAGENT_BAG_ID, slot)
        if info then
            local data = SlotData(REAGENT_BAG_ID, slot, info)
            if HasStackRoom(data) then
                if SlotIsLocked(REAGENT_BAG_ID, slot, info) then
                    lockedCount = lockedCount + 1
                else
                    AddPartial(partialByKey, partialKeys, data)
                end
            end
        else
            emptySlots[#emptySlots + 1] = { bag = REAGENT_BAG_ID, slot = slot }
        end
    end

    local sources = {}
    for bag = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                local data = SlotData(bag, slot, info)
                if IsCraftingReagent(data.itemLink, data.itemID) then
                    if SlotIsLocked(bag, slot, info) then
                        lockedCount = lockedCount + 1
                    else
                        sources[#sources + 1] = data
                    end
                end
            end
        end
    end

    return {
        sources = sources,
        emptySlots = emptySlots,
        partialByKey = partialByKey,
        partialKeys = partialKeys,
        lockedCount = lockedCount,
    }
end

local function PickupIntoSlot(srcBag, srcSlot, destBag, destSlot)
    if not (C_Container and C_Container.PickupContainerItem) then return false, "missing-api" end
    if CursorOccupied() then return false, "cursor-busy" end

    C_Container.PickupContainerItem(srcBag, srcSlot)
    if GetCursorInfo and not CursorOccupied() then return false, "locked" end

    C_Container.PickupContainerItem(destBag, destSlot)
    if CursorOccupied() then
        C_Container.PickupContainerItem(srcBag, srcSlot)
    end
    if ClearCursor then ClearCursor() end
    return true
end

local function FindNextReagentMove()
    local state, reason = BuildReagentMoveState()
    if not state then return nil, reason end

    for _, key in ipairs(state.partialKeys) do
        local partials = state.partialByKey[key]
        if partials and #partials > 1 then
            table.sort(partials, SortPartialsByRoom)
            local source = partials[1]
            local target = partials[#partials]
            if source and target and source.slot ~= target.slot then
                return { source = source, target = target }
            end
        end
    end

    for _, source in ipairs(state.sources) do
        local partials = state.partialByKey[source.stackKey]
        if partials and #partials > 0 then
            table.sort(partials, SortPartialsByRoom)
            for _, target in ipairs(partials) do
                if target.slot and target.stackCount < target.maxStack then
                    return { source = source, target = target }
                end
            end
        end
    end

    if #state.sources == 0 then
        return nil, state.lockedCount > 0 and "locked-wait" or "done"
    end
    if #state.emptySlots == 0 then
        return nil, state.lockedCount > 0 and "locked-wait" or "full"
    end

    return { source = state.sources[1], target = state.emptySlots[1] }
end

local function MoveOneReagentStack()
    local move, reason = FindNextReagentMove()
    if not move then return false, reason end
    local source, target = move.source, move.target
    local moved, moveReason = PickupIntoSlot(source.bag, source.slot, target.bag, target.slot)
    return moved, moveReason
end

local function SetReagentMoveLocked(locked)
    reagentMoveLocked = locked and true or nil
    local btn = _G.EUI_Bags and EUI_Bags._bagPlusReagentBtn
    if not btn then return end

    btn._bagPlusLocked = reagentMoveLocked
    if btn.EnableMouse then btn:EnableMouse(not reagentMoveLocked) end
    if btn.icon and btn.icon.SetAlpha then
        btn.icon:SetAlpha(reagentMoveLocked and 0.25 or 0.9)
    end
end

local function MoveReagentsToReagentBag(printResult)
    if reagentMoveLocked then return false end
    if InCombatLockdown and InCombatLockdown() then
        if printResult ~= false then Print("|cff6fe7c5BagPlus|r Cannot move reagents while in combat.") end
        return false
    end
    if CursorOccupied() then
        if printResult ~= false then Print("|cff6fe7c5BagPlus|r Clear your cursor first.") end
        return false
    end
    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.PickupContainerItem) then
        if printResult ~= false then Print("|cff6fe7c5BagPlus|r Container API is not available.") end
        return false
    end
    if (C_Container.GetContainerNumSlots(REAGENT_BAG_ID) or 0) <= 0 then
        if printResult ~= false then Print("|cff6fe7c5BagPlus|r No reagent bag is equipped.") end
        return false
    end
    if _G.EUI_Bags and EUI_Bags.refreshEnabled == false then
        if printResult ~= false then Print("|cff6fe7c5BagPlus|r Bags are already busy.") end
        return false
    end

    local previousRefreshEnabled = _G.EUI_Bags and EUI_Bags.refreshEnabled
    if _G.EUI_Bags then EUI_Bags.refreshEnabled = false end
    SetReagentMoveLocked(true)

    local movedCount = 0
    local lastReason
    local attempts = 0

    local function Finish(reason)
        if _G.EUI_Bags then EUI_Bags.refreshEnabled = previousRefreshEnabled ~= false end
        SetReagentMoveLocked(false)
        RefreshGearVisualOrder()
        RefreshBagWindows()

        if printResult ~= false then
            if movedCount > 0 then
                Print("|cff6fe7c5BagPlus|r Moved reagents to the reagent bag.")
            elseif reason == "full" then
                Print("|cff6fe7c5BagPlus|r Reagent bag is full.")
            elseif reason == "locked" or reason == "locked-wait" or reason == "retry-limit" then
                Print("|cff6fe7c5BagPlus|r Some reagent slots are locked. Try again in a moment.")
            else
                Print("|cff6fe7c5BagPlus|r No reagents need moving.")
            end
        end
    end

    local function Step()
        attempts = attempts + 1
        local moved, reason = MoveOneReagentStack()
        lastReason = reason
        if moved then
            movedCount = movedCount + 1
        end

        if (moved or reason == "locked" or reason == "locked-wait") and attempts < REAGENT_MOVE_RETRY_LIMIT then
            if C_Timer and C_Timer.After then
                C_Timer.After(REAGENT_MOVE_DELAY, Step)
            else
                Step()
            end
        else
            Finish(moved and "retry-limit" or lastReason)
        end
    end

    Step()
    return true
end

local BAG_SLOT_SIZE = 34
local BAG_SLOT_SPACING = 4
local BAG_SECTION_HEADER_H = 22
local BAG_SUBHEADER_H = 18
local BAG_SECTION_GAP = 6
local BAG_GRID_START_X = 15
local BAG_COMPACT_MIN_COLUMNS = 2
local BAG_COMPACT_MAX_ROWS = 2
local BAG_COMPACT_BUCKET_GAP = math.max(8, BAG_SLOT_SPACING * 3)
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

local function FrameWidth(frame, fallback)
    if frame and frame.GetWidth then
        local width = frame:GetWidth()
        if type(width) == "number" and width > 0 then return width end
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

local function SortFramesByGridPosition(frames)
    table.sort(frames, function(a, b)
        local ax, ay = FrameTopLeft(a)
        local bx, by = FrameTopLeft(b)
        if ay ~= by then return (ay or 0) > (by or 0) end
        return (ax or 0) < (bx or 0)
    end)
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

            SortFramesByGridPosition(section.slots)
            SortFramesByGridPosition(section.pads)
            SortFramesByGridPosition(section.subheaders)
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

local function ApplyPostLayoutWidth(renderedColumns, layoutColumns, stride)
    if not (_G.EUI_Bags and EUI_Bags.SetWidth and EUI_Bags._scrollChild) then return end
    renderedColumns = math.floor(tonumber(renderedColumns) or 0)
    layoutColumns = math.floor(tonumber(layoutColumns) or 0)
    if renderedColumns < 1 or layoutColumns < 1 or layoutColumns >= renderedColumns then return end

    stride = stride or (BAG_SLOT_SIZE + BAG_SLOT_SPACING)
    local child = EUI_Bags._scrollChild
    local renderedGridW = renderedColumns * stride
    local oldChildW = FrameWidth(child, renderedGridW)
    local extraW = oldChildW - renderedGridW
    if type(extraW) ~= "number" or extraW < 0 then extraW = 0 end

    local newChildW = layoutColumns * stride + extraW
    local deltaW = newChildW - oldChildW
    if child.SetWidth then child:SetWidth(newChildW) end

    if EUI_Bags._asMaxGridW then EUI_Bags._asMaxGridW = newChildW end

    local oldFrameW = FrameWidth(EUI_Bags, newChildW)
    local newFrameW = oldFrameW + deltaW
    if newFrameW > 0 then EUI_Bags:SetWidth(newFrameW) end
end

local function WantedPadCount(slotCount, padCount, columns, keepPads)
    if keepPads == false or padCount <= 0 then return 0 end
    if slotCount == 0 then return math.min(columns, padCount) end
    local remainder = slotCount % columns
    if remainder == 0 then return 0 end
    return math.min(columns - remainder, padCount)
end

local function ReflowSlotBlock(slots, pads, child, startX, topY, columns, stride, keepPads)
    for index, slot in ipairs(slots) do
        local col = (index - 1) % columns
        local row = math.floor((index - 1) / columns)
        SetFrameTopLeft(slot, child, startX + col * stride, topY - row * stride)
    end

    local padCount = WantedPadCount(#slots, #pads, columns, keepPads)
    for index, pad in ipairs(pads) do
        if index <= padCount then
            local totalIndex = #slots + index
            local col = (totalIndex - 1) % columns
            local row = math.floor((totalIndex - 1) / columns)
            SetFrameTopLeft(pad, child, startX + col * stride, topY - row * stride)
            if pad.Show then pad:Show() end
        elseif pad.Hide then
            pad:Hide()
        end
    end

    local rows = 0
    if #slots > 0 then
        rows = math.ceil(#slots / columns)
    elseif padCount > 0 then
        rows = 1
    end
    return topY - rows * stride
end

local function FilterFramesInBand(frames, topY, bottomY)
    local result = {}
    for _, frame in ipairs(frames) do
        local _, y = FrameTopLeft(frame)
        if type(y) == "number" and y < topY and y > bottomY then
            result[#result + 1] = frame
        end
    end
    SortFramesByGridPosition(result)
    return result
end

local function FilterFramesInBox(frames, leftX, rightX, topY, bottomY)
    local result = {}
    for _, frame in ipairs(frames) do
        local x, y = FrameTopLeft(frame)
        if type(x) == "number" and type(y) == "number"
           and x >= leftX - 1 and x < rightX + 1
           and y < topY and y > bottomY then
            result[#result + 1] = frame
        end
    end
    SortFramesByGridPosition(result)
    return result
end

local function SectionHasSharedSubheaderRows(section)
    local subheaders = section and section.subheaders
    if not subheaders or #subheaders < 2 then return false end

    for i = 2, #subheaders do
        local _, prevY = FrameTopLeft(subheaders[i - 1])
        local _, y = FrameTopLeft(subheaders[i])
        if type(prevY) == "number" and type(y) == "number" and math.abs(prevY - y) <= 1 then
            return true
        end
    end
    return false
end

local function CanReflowSection(section)
    return not SectionHasSharedSubheaderRows(section)
end

local function NextLowerSubheaderY(subheaders, index, fallbackY)
    local _, y = FrameTopLeft(subheaders[index])
    if type(y) ~= "number" then return fallbackY end
    for nextIndex = index + 1, #subheaders do
        local _, nextY = FrameTopLeft(subheaders[nextIndex])
        if type(nextY) == "number" and nextY < y - 1 then
            return nextY
        end
    end
    return fallbackY
end

local function HeaderLabelWidth(header)
    local label = header and header._label
    if label and label.GetStringWidth then
        return label:GetStringWidth() or 0
    end
    return 0
end

local function BuildSharedSubheaderBuckets(section, stride)
    local buckets = {}
    for index, subheader in ipairs(section.subheaders) do
        local x, y = FrameTopLeft(subheader)
        if type(x) == "number" and type(y) == "number" then
            local width = FrameWidth(subheader, stride)
            local bottomY = NextLowerSubheaderY(section.subheaders, index, section.nextY)
            buckets[#buckets + 1] = {
                subheader = subheader,
                slots = FilterFramesInBox(section.slots, x, x + width + BAG_SLOT_SPACING, y, bottomY),
            }
        end
    end
    return buckets
end

local function SharedBucketSpan(bucket, columns, stride)
    local slotCount = #bucket.slots
    local itemSpan = math.max(1, math.min(columns, slotCount))
    local labelSpan = math.ceil((HeaderLabelWidth(bucket.subheader) + 8) / stride)
    local span = math.max(1, itemSpan, labelSpan)
    if span > columns then span = columns end
    return span
end

local function ReflowSharedSubheaderSection(section, child, startX, topY, columns, stride, keepPads)
    local width = columns * stride
    SetFrameTopLeft(section.header, child, startX, topY)
    section.header:SetWidth(width)
    SetCompactHeader(section.header, false)

    local buckets = BuildSharedSubheaderBuckets(section, stride)
    for _, pad in ipairs(section.pads) do
        if pad.Hide then pad:Hide() end
    end

    local nextPadIndex = 1
    local function PlacePad(x, y)
        if keepPads == false then return false end
        local pad = section.pads[nextPadIndex]
        if not pad then return false end
        nextPadIndex = nextPadIndex + 1
        SetFrameTopLeft(pad, child, x, y)
        if pad.Show then pad:Show() end
        return true
    end

    local function FillRowPads(rowTop, usedWidth)
        if keepPads == false then return end
        local padTop = rowTop - BAG_SUBHEADER_H
        local padCount = math.floor(math.max(0, width - usedWidth) / stride)
        for index = 1, padCount do
            PlacePad(startX + usedWidth + (index - 1) * stride, padTop)
        end
    end

    local function FillLastItemRowPads(rowTop, usedColumns, span, rows)
        if keepPads == false or rows <= 0 or usedColumns <= 0 or usedColumns >= span then return end
        local padTop = rowTop - BAG_SUBHEADER_H - (rows - 1) * stride
        for index = usedColumns + 1, span do
            PlacePad(startX + (index - 1) * stride, padTop)
        end
    end

    local rowTop = topY - BAG_SECTION_HEADER_H
    local usedWidth = 0
    local rowItemRows = 0

    local function FlushRow()
        if usedWidth == 0 then return end
        FillRowPads(rowTop, usedWidth)
        rowTop = rowTop - BAG_SUBHEADER_H - rowItemRows * stride
        usedWidth = 0
        rowItemRows = 0
    end

    for _, bucket in ipairs(buckets) do
        local slotCount = #bucket.slots
        local span = SharedBucketSpan(bucket, columns, stride)
        local rows = slotCount > 0 and math.ceil(slotCount / span) or 0
        local bucketWidth = span * stride
        local startOffset = usedWidth > 0 and usedWidth + BAG_COMPACT_BUCKET_GAP or 0
        local needsOwnRow = rows > 1

        if usedWidth > 0 and (needsOwnRow or startOffset + bucketWidth > width + 0.5) then
            FlushRow()
            startOffset = 0
        end

        local bucketX = startX + startOffset
        SetFrameTopLeft(bucket.subheader, child, bucketX, rowTop)
        bucket.subheader:SetWidth(bucketWidth)
        if bucket.subheader.Show then bucket.subheader:Show() end

        for index, slot in ipairs(bucket.slots) do
            local col = (index - 1) % span
            local row = math.floor((index - 1) / span)
            SetFrameTopLeft(slot, child, bucketX + col * stride, rowTop - BAG_SUBHEADER_H - row * stride)
        end

        if needsOwnRow then
            local remainder = slotCount % span
            FillLastItemRowPads(rowTop, remainder, span, rows)
            rowTop = rowTop - BAG_SUBHEADER_H - rows * stride
            usedWidth = 0
            rowItemRows = 0
        else
            usedWidth = startOffset + bucketWidth
            rowItemRows = math.max(rowItemRows, rows)
        end
    end
    FlushRow()

    for index = nextPadIndex, #section.pads do
        local pad = section.pads[index]
        if pad and pad.Hide then pad:Hide() end
    end

    return rowTop - BAG_SECTION_GAP
end

local function ReflowSection(section, child, startX, topY, columns, stride, keepPads)
    local width = columns * stride
    SetFrameTopLeft(section.header, child, startX, topY)
    section.header:SetWidth(width)
    SetCompactHeader(section.header, false)

    local nextTop = topY - BAG_SECTION_HEADER_H
    if #section.subheaders == 0 then
        nextTop = ReflowSlotBlock(section.slots, section.pads, child, startX, nextTop, columns, stride, keepPads)
        return nextTop - BAG_SECTION_GAP
    end

    local _, firstSubY = FrameTopLeft(section.subheaders[1])
    if type(firstSubY) == "number" then
        local leadingSlots = FilterFramesInBand(section.slots, section.y, firstSubY)
        local leadingPads = FilterFramesInBand(section.pads, section.y, firstSubY)
        if #leadingSlots > 0 or #leadingPads > 0 then
            nextTop = ReflowSlotBlock(leadingSlots, leadingPads, child, startX, nextTop, columns, stride, keepPads)
        end
    end

    local blocks = {}
    for index, subheader in ipairs(section.subheaders) do
        local _, subY = FrameTopLeft(subheader)
        local _, nextSubY = FrameTopLeft(section.subheaders[index + 1])
        blocks[#blocks + 1] = {
            subheader = subheader,
            topY = subY or section.y,
            bottomY = nextSubY or section.nextY,
        }
    end

    for _, block in ipairs(blocks) do
        SetFrameTopLeft(block.subheader, child, startX, nextTop)
        block.subheader:SetWidth(width)
        if block.subheader.Show then block.subheader:Show() end
        nextTop = nextTop - BAG_SUBHEADER_H
        nextTop = ReflowSlotBlock(
            FilterFramesInBand(section.slots, block.topY, block.bottomY),
            FilterFramesInBand(section.pads, block.topY, block.bottomY),
            child, startX, nextTop, columns, stride, keepPads
        )
    end

    return nextTop - BAG_SECTION_GAP
end

local function PreserveSectionLayout(section, child, startX, topY, stride, keepPads)
    SetCompactHeader(section.header, false)
    local height = keepPads and section.height or SectionContentHeight(section, stride)
    local dx = startX - section.x
    local dy = topY - section.y
    for _, frame in ipairs(section.frames) do
        OffsetFrame(frame, dx, dy)
        if IsEmptyPad(frame) then
            frame:SetShown(keepPads == true)
        end
    end
    return topY - height
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

local function ApplyMaxItemsPerRow()
    if not LimitItemsPerRowEnabled() then return end
    if not (_G.EUI_Bags and EUI_Bags:IsVisible()) then return end

    local child = EUI_Bags._scrollChild
    local sections, headers, renderedColumns, stride, startX = CollectRenderedSections(child)
    if not sections then return end

    local columns = ApplyItemsPerRowLimit(renderedColumns)
    if columns >= renderedColumns then return end

    local curY = headers[1].y or -6
    local canResizeWidth = true
    for _, section in ipairs(sections) do
        if SectionHasSharedSubheaderRows(section) then
            curY = ReflowSharedSubheaderSection(section, child, startX, curY, columns, stride, true)
        elseif CanReflowSection(section) then
            curY = ReflowSection(section, child, startX, curY, columns, stride, true)
        else
            canResizeWidth = false
            curY = PreserveSectionLayout(section, child, startX, curY, stride, true)
        end
    end

    local contentH = math.abs(curY) + 10
    child:SetHeight(contentH)
    if canResizeWidth then
        ApplyPostLayoutWidth(renderedColumns, columns, stride)
    end
    ApplyPostLayoutAutoSize(contentH)
    UpdateBagScrollRange()
end

local function ApplyCompactCategoryRows()
    if not CompactCategoryRowsEnabled() then return end
    if not (_G.EUI_Bags and EUI_Bags:IsVisible() and SelectedAllItemsView()) then return end

    local child = EUI_Bags._scrollChild
    local sections, headers, renderedColumns, stride, startX = CollectRenderedSections(child)
    if not sections then return end

    local columns = ApplyItemsPerRowLimit(renderedColumns)
    local shouldShrinkWidth = columns < renderedColumns
    local canResizeWidth = true
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
        if shouldShrinkWidth and SectionHasSharedSubheaderRows(section) then
            curY = ReflowSharedSubheaderSection(section, child, startX, curY, columns, stride, keepPads)
        elseif shouldShrinkWidth and CanReflowSection(section) then
            curY = ReflowSection(section, child, startX, curY, columns, stride, keepPads)
        else
            if shouldShrinkWidth then canResizeWidth = false end
            curY = PreserveSectionLayout(section, child, startX, curY, stride, keepPads)
        end
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
    if shouldShrinkWidth and canResizeWidth then
        ApplyPostLayoutWidth(renderedColumns, columns, stride)
    end
    ApplyPostLayoutAutoSize(contentH)
    UpdateBagScrollRange()
end

function Print(msg)
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
        local compactApplied = false
        if CompactCategoryRowsEnabled() and SelectedAllItemsView() then
            pcall(ApplyCompactCategoryRows)
            compactApplied = true
        else
            pcall(RestoreCategoryHeaderLines)
            if HideEmptyRecentItemsEnabled() then
                pcall(ApplyHideEmptyRecentItems)
            end
        end
        if not compactApplied and LimitItemsPerRowEnabled() then
            pcall(ApplyMaxItemsPerRow)
        end
        return result
    end
    refreshPatched = true
    return true
end

local function PositionReagentButton()
    local bags = _G.EUI_Bags
    local btn = bags and bags._bagPlusReagentBtn
    local header = bags and bags.Header
    if not (btn and header and btn.ClearAllPoints and btn.SetPoint) then return end

    btn:ClearAllPoints()
    local sortBtn = bags._sortBtn
    local searchBox = bags._searchBox
    if sortBtn and (not sortBtn.IsShown or sortBtn:IsShown()) then
        btn:SetPoint("RIGHT", sortBtn, "LEFT", -6, 0)
    elseif searchBox then
        btn:SetPoint("RIGHT", searchBox, "LEFT", -13, 0)
    else
        btn:SetPoint("RIGHT", header, "RIGHT", -210, 0)
    end

    local bagsBtn = bags._bagsBtn
    if bagsBtn and bagsBtn ~= btn and bagsBtn.ClearAllPoints and bagsBtn.SetPoint then
        bagsBtn:ClearAllPoints()
        bagsBtn:SetPoint("RIGHT", btn, "LEFT", -6, 0)
    end
end

local function StyleReagentButtonIcon(btn)
    if not (btn and btn.icon) then return end

    btn.icon:SetAllPoints()
    btn.icon:SetTexture(REAGENT_BUTTON_ICON)
    btn.icon:SetAlpha(0.9)
    if btn.icon.SetTexCoord then btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end

    if btn.CreateMaskTexture and btn.icon.AddMaskTexture and not btn.iconMask then
        local mask = btn:CreateMaskTexture()
        mask:SetTexture(REAGENT_BUTTON_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(btn.icon)
        pcall(btn.icon.AddMaskTexture, btn.icon, mask)
        btn.iconMask = mask
    end
end

local function PatchReagentButton()
    if not (_G.EUI_Bags and EUI_Bags.Header and CreateFrame) then return reagentButtonPatched end

    local btn = EUI_Bags._bagPlusReagentBtn
    if not btn then
        btn = CreateFrame("Button", nil, EUI_Bags.Header)
        btn:SetSize(24, 24)
        if btn.SetFrameLevel and EUI_Bags.Header.GetFrameLevel then
            btn:SetFrameLevel((EUI_Bags.Header:GetFrameLevel() or 1) + 2)
        end
        btn.icon = btn:CreateTexture(nil, "OVERLAY")
        StyleReagentButtonIcon(btn)
        btn:SetScript("OnEnter", function(self)
            if self.icon and self.icon.SetAlpha and not self._bagPlusLocked then self.icon:SetAlpha(1) end
            if EllesmereUI and EllesmereUI.ShowWidgetTooltip then
                EllesmereUI.ShowWidgetTooltip(self, "Move Reagents to Reagent Bag")
            end
        end)
        btn:SetScript("OnLeave", function(self)
            if self.icon and self.icon.SetAlpha then
                self.icon:SetAlpha(self._bagPlusLocked and 0.25 or 0.9)
            end
            if EllesmereUI and EllesmereUI.HideWidgetTooltip then EllesmereUI.HideWidgetTooltip() end
        end)
        btn:SetScript("OnClick", function()
            MoveReagentsToReagentBag(true)
        end)
        EUI_Bags._bagPlusReagentBtn = btn
        EUI_Bags._bagPlusMoveReagentsToReagentBag = MoveReagentsToReagentBag
        EUI_Bags._bagPlusMoveOneReagentStack = MoveOneReagentStack
    else
        StyleReagentButtonIcon(btn)
        EUI_Bags._bagPlusMoveReagentsToReagentBag = MoveReagentsToReagentBag
        EUI_Bags._bagPlusMoveOneReagentStack = MoveOneReagentStack
    end

    PositionReagentButton()
    reagentButtonPatched = true
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
        description = "Adds Warbound Gear and BoE Gear categories to EllesmereUI Bags, sorts gear by item level, can compact or cap bag rows, and can move reagents into the reagent bag.",
        searchTerms = "bagplus bags boe warbound wue gear item level sort compact condensed category rows recent empty maximum items per row onebag multibag reagent reagents mats",
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

            _, h = W:Toggle(parent, "Change Maximum Items Per Row", y,
                function() return LimitItemsPerRowEnabled() end,
                function(v)
                    DB().limitItemsPerRow = v and true or false
                    RebuildBagPlus()
                end,
                "Enables a BagPlus maximum for how many item slots can appear on each row in All Items, OneBag, and MultiBag."
            ); y = y - h

            _, h = W:Slider(parent, "Maximum Items Per Row", y,
                MAX_ITEMS_PER_ROW_MIN, MAX_ITEMS_PER_ROW_MAX, 1,
                function() return MaxItemsPerRow() end,
                function(v)
                    local n = NormalizeMaxItemsPerRow(v)
                    if DB().maxItemsPerRow == n then return end
                    DB().maxItemsPerRow = n
                    RebuildBagPlus()
                end,
                "Sets the maximum row length used when Change Maximum Items Per Row is enabled."
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
            DB().limitItemsPerRow = false
            DB().maxItemsPerRow = MAX_ITEMS_PER_ROW_DEFAULT
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
    PatchReagentButton()
    RegisterOptions()
    RefreshGearVisualOrder()
end

local retries = 0
local function RetryPatch()
    TryPatch()
    if patched and refreshPatched and reagentButtonPatched then return end
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
            .. ", hide empty recent " .. OnOff(HideEmptyRecentItemsEnabled())
            .. ", max items per row " .. (LimitItemsPerRowEnabled() and tostring(MaxItemsPerRow()) or "off"))
    end
    local function PrintHelp()
        Print("|cff6fe7c5BagPlus|r /bagplus boe on|off")
        Print("|cff6fe7c5BagPlus|r /bagplus wue on|off")
        Print("|cff6fe7c5BagPlus|r /bagplus ilvl asc|desc|off")
        Print("|cff6fe7c5BagPlus|r /bagplus compact on|off")
        Print("|cff6fe7c5BagPlus|r /bagplus emptyrecent on|off")
        Print("|cff6fe7c5BagPlus|r /bagplus perrow on|off")
        Print("|cff6fe7c5BagPlus|r /bagplus perrow "
            .. MAX_ITEMS_PER_ROW_MIN .. "-" .. MAX_ITEMS_PER_ROW_MAX)
        Print("|cff6fe7c5BagPlus|r /bagplus reagents")
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

    if cmd == "perrow" or cmd == "itemsperrow" or cmd == "maxrow" then
        if arg == "on" or arg == "off" then
            DB().limitItemsPerRow = arg == "on"
            RebuildBagPlus()
            Print("|cff6fe7c5BagPlus|r Change Maximum Items Per Row: " .. arg)
            return
        end

        local n = tonumber(arg)
        if not n then
            Print("|cff6fe7c5BagPlus|r max items per row is "
                .. (LimitItemsPerRowEnabled() and tostring(MaxItemsPerRow()) or "off")
                .. " (saved value " .. MaxItemsPerRow() .. ")")
            Print("|cff6fe7c5BagPlus|r /bagplus perrow on|off")
            Print("|cff6fe7c5BagPlus|r /bagplus perrow "
                .. MAX_ITEMS_PER_ROW_MIN .. "-" .. MAX_ITEMS_PER_ROW_MAX)
            return
        end

        n = math.floor(n + 0.5)
        if n < MAX_ITEMS_PER_ROW_MIN or n > MAX_ITEMS_PER_ROW_MAX then
            Print("|cff6fe7c5BagPlus|r max items per row must be "
                .. MAX_ITEMS_PER_ROW_MIN .. "-" .. MAX_ITEMS_PER_ROW_MAX)
            return
        end
        DB().maxItemsPerRow = n
        DB().limitItemsPerRow = true
        RebuildBagPlus()
        Print("|cff6fe7c5BagPlus|r Maximum Items Per Row: " .. n)
        return
    end

    if cmd == "refresh" then
        TryPatch()
        RebuildBagPlus()
        Print("|cff6fe7c5BagPlus|r refreshed.")
        return
    end

    if cmd == "reagents" or cmd == "reagent" or cmd == "mats" then
        MoveReagentsToReagentBag(true)
        return
    end

    if cmd == "status" or not cmd then
        PrintStatus()
        PrintHelp()
        return
    end

    PrintHelp()
end
