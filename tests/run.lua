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
    function region:SetText(text) self.text = tostring(text or "") end
    function region:GetText() return self.text end
    function region:GetStringWidth() return #(self.text or "") * 6 end
    function region:SetWidth(width) self.width = width end
    function region:GetWidth() return self.width end
    function region:SetHeight(height) self.height = height end
    function region:GetHeight() return self.height end
    function region:SetSize(width, height) self.width, self.height = width, height end
    function region:SetAlpha(alpha) self.alpha = alpha end
    function region:SetTextColor() end
    function region:SetJustifyH() end
    function region:SetAllPoints() end
    function region:SetPoint() end
    function region:ClearAllPoints() end
    function region:SetTexture() end

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
function Frame:EnableMouse() end
function Frame:SetMouseClickEnabled() end
function Frame:SetAllPoints() end
function Frame:SetAlpha() end
function Frame:SetScript(scriptName, fn) self.scripts[scriptName] = fn end
function Frame:GetScript(scriptName) return self.scripts[scriptName] end
function Frame:RegisterEvent(eventName) self.events = self.events or {}; self.events[eventName] = true end
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

function Frame:CreateFontString()
    return newRegion()
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
    _G.SlashCmdList = {}
    _G.SLASH_BAGPLUSFORELLESMEREUI1 = nil
    _G.Enum = {
        ItemClass = { Armor = 4, Weapon = 2 },
        ItemBind = { OnEquip = 2 },
    }
    _G.C_Container = {
        GetContainerNumSlots = function() return 0 end,
        GetContainerItemInfo = function() return nil end,
        GetContainerItemLink = function() return nil end,
    }
    _G.C_Item = {
        DoesItemExist = function() return true end,
        IsBoundToAccountUntilEquip = function() return false end,
    }
    _G.ItemLocation = {
        CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end,
    }
    _G.GetItemInfoInstant = nil
    _G.GetItemInfo = nil
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
    bags.Footer = newFrame("Frame", bags)
    bags.Footer:SetHeight(28)
    bags._footerH = 28
    bags._scrollFrame = newFrame("Frame", bags)
    bags._scrollChild = newFrame("Frame", bags)
    bags._scrollChild:SetSize(488, 320)
    bags._updateThumb = function() bags.thumbUpdated = true end
    bags.RefreshInventory = options.refreshInventory or function() end
    _G.EUI_Bags = bags

    return {
        createdFrames = createdFrames,
        prints = prints,
        registeredModules = registeredModules,
        profile = profile,
        manager = manager,
        bags = bags,
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
    assertEqual(db.maxItemsPerRow, 20)
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

test("perrow slash command validates, saves, and toggles the feature", function()
    local ctx = setup()
    loadAddon(ctx)

    slash("perrow 17")
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
