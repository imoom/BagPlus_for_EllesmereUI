-- SPDX-License-Identifier: MIT

local ADDON_NAME = ...

local TITLE = "BagPlus for EllesmereUI"
local PAGE = "BagPlus"
local GROUP_KEY = "bagplus"

local KEY_WUE = "Warbound Gear"
local KEY_BOE = "BoE Gear"
local RULE_WUE = "warboundUntilEquip"
local RULE_BOE = "bindOnEquip"

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
        return originalRefresh(self, ...)
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
        description = "Adds Warbound Gear and BoE Gear categories to EllesmereUI Bags and sorts gear by item level.",
        searchTerms = "bagplus bags boe warbound wue gear item level sort",
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

            _, h = W:Toggle(parent, "Sort Gear by Item Level", y,
                function() return SortEnabled() end,
                function(v)
                    DB().ilvlSort = v and "desc" or "off"
                    DB().sortGearByItemLevel = v and true or false
                    RebuildBagPlus()
                end,
                "Sorts armor and weapons by item level within gear categories."
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
            .. ", ilvl " .. SortMode())
    end
    local function PrintHelp()
        Print("|cff6fe7c5BagPlus|r /bagplus boe on|off")
        Print("|cff6fe7c5BagPlus|r /bagplus wue on|off")
        Print("|cff6fe7c5BagPlus|r /bagplus ilvl asc|desc|off")
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
