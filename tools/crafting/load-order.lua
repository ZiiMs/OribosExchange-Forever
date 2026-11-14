-- Loads the addon the way the client does, in .toc order, against stubs, and
-- exercises the crafting feature: the recipe panel hook, the drawn text and the
-- toggles. Catches load-order mistakes (a helper read before the file that
-- defines it) that a per-file lint cannot.
--
-- Usage: luajit tools/crafting/load-order.lua

local ADDON = 'OribosExchange'

-- The .toc, in order, minus the libraries (not under test).
local files = {
    'dynamic/bonusToName.lua',
    'dynamic/speciesStats.lua',
    'dynamic/data.us.lua',
    'Localization.lua',
    'Localization-ruRU.lua',
    'WhatsNew.lua',
    'OribosExchange.lua',
    'Crafting.lua',
    'Settings.lua',
    'MinimapButton.lua',
}

local savedVars = {}
local openedSettings = false
local hooks = {}

local frames = {}
local function CreateFrame(kind, name)
    local frame = {
        name = name,
        events = {},
        scripts = {},
        -- Widget bits the options page and the minimap button touch.
        CreateTexture = function()
            return {
                SetSize = function() end,
                SetPoint = function() end,
                SetColorTexture = function() end,
                SetTexture = function() end,
                SetTexCoord = function() end,
                SetDrawLayer = function() end,
                SetDesaturated = function() end,
                SetAlpha = function() end,
                SetShown = function() end,
                SetAllPoints = function() end,
            }
        end,
        CreateFontString = function()
            return {
                SetPoint = function() end,
                SetText = function() end,
                SetJustifyH = function() end,
                SetJustifyV = function() end,
                SetTextColor = function() end,
                SetAlpha = function() end,
                SetWidth = function() end,
                Show = function() end,
                Hide = function() end,
            }
        end,
        SetSize = function() end,
        SetHeight = function() end,
        SetWidth = function() end,
        SetPoint = function() end,
        ClearAllPoints = function() end,
        SetFrameStrata = function() end,
        SetAlpha = function() end,
        SetShown = function() end,
        Enable = function() end,
        Disable = function() end,
        RegisterForClicks = function() end,
        RegisterForDrag = function() end,
        RegisterEvent = function(self, e) self.events[e] = true end,
        UnregisterEvent = function(self, e) self.events[e] = nil end,
        SetScript = function(self, s, fn) self.scripts[s] = fn end,
        Show = function() end,
        Hide = function() end,
        IsShown = function() return false end,
        GetBottom = function() return 0 end,
        GetCenter = function() return 0, 0 end,
        GetEffectiveScale = function() return 1 end,
        GetWidth = function() return 140 end,
    }
    frames[#frames + 1] = frame
    return frame
end

-- A stand-in for the recipe panel's font string, recording what it is given.
local function makeFontString()
    local line = {
        text = '',
        shown = false,
        width = 0,
        points = {},
        SetText = function(self, text) self.text = text end,
        SetWidth = function(self, w) self.width = w end,
        SetJustifyH = function() end,
        SetJustifyV = function() end,
        ClearAllPoints = function(self) self.points = {} end,
        SetPoint = function(self, ...) self.points[#self.points + 1] = { ... } end,
        Show = function(self) self.shown = true end,
        Hide = function(self) self.shown = false end,
    }
    return line
end

-- A recipe panel with the parts the crafting feature touches.
local function makePanel()
    local function container(shown, bottom)
        return {
            shown = shown,
            bottom = bottom,
            points = {},
            IsShown = function(self) return self.shown end,
            GetBottom = function(self) return self.bottom end,
            ClearAllPoints = function(self) self.points = {} end,
            SetPoint = function(self, ...) self.points[#self.points + 1] = { ... } end,
        }
    end

    local panel = {
        OutputText = { SetPoint = function() end },
        RequiredTools = container(false, 0),
        Reagents = container(true, 400),
        OptionalReagents = container(false, 0),
        FinishingReagents = container(false, 0),
        isRecraft = false,
        created = {},
        CreateFontString = function(self)
            local line = makeFontString()
            self.created[#self.created + 1] = line
            return line
        end,
    }
    return panel
end

local addonTable = {}

local env = {
    CreateFrame = CreateFrame,
    GameTooltip = { AddLine = function() end, AddDoubleLine = function() end, Show = function() end },
    GameTooltip_AddBlankLineToTooltip = function() end,
    GameTooltip_Show = function() end,
    GameTooltip_Hide = function() end,
    hooksecurefunc = function(tbl, method, fn)
        hooks[method] = fn
        local original = tbl[method] or function() end
        tbl[method] = function(...)
            local result = original(...)
            fn(...)
            return result
        end
    end,
    C_TradeSkillUI = {
        GetRecipeSchematic = function(recipeID)
            if recipeID == 2152 then
                return {
                    recipeID = 2152,
                    outputItemID = 2304,
                    quantityMin = 1,
                    quantityMax = 1,
                    reagentSlotSchematics = {
                        { reagentType = 1, required = true, quantityRequired = 1, reagents = { { itemID = 2318 } } },
                    },
                }
            end
            if recipeID == 2660 then
                return {
                    recipeID = 2660,
                    outputItemID = 2840,
                    quantityMin = 1,
                    quantityMax = 1,
                    reagentSlotSchematics = {
                        { reagentType = 1, required = true, quantityRequired = 1, reagents = { { itemID = 2841 } } },
                    },
                }
            end
            return nil
        end,
    },
    Enum = { CraftingReagentType = { Modifying = 0, Basic = 1, Finishing = 2, Automatic = 3 } },
    ProfessionsUtil = { IsCraftingMinimized = function() return false end },
    GetItemInfoInstant = function() return 2318 end,
    GetDetailedItemLevelInfo = function() return 1 end,
    GetTime = os.time,
    time = os.time,
    date = os.date,
    GetRealmID = function() return 0 end,
    GetRealmName = function() return 'Test' end,
    UnitFactionGroup = function() return 'Alliance' end,
    GetCurrentRegion = function() return 1 end,
    GetBuildInfo = function() return '1.60.1', '70938', '', 16001 end,
    GetLocale = function() return 'enUS' end,
    SecondsToTime = function(s) return tostring(s) end,
    wipe = function(t) for k in pairs(t) do t[k] = nil end end,
    sort = table.sort,
    strsplit = string.split or function(...) return ... end,
    strfind = string.find,
    strmatch = string.match,
    strsub = string.sub,
    strbyte = string.byte,
    strlen = string.len,
    strlower = string.lower,
    IsShiftKeyDown = function() return false end,
    C_CurrencyInfo = { GetCoinTextureString = function(money) return tostring(money) end },
    C_AddOns = { GetAddOnInfo = function() return nil end },
    C_Item = {
        GetItemInfo = function() return nil end,
        GetItemInfoInstant = function() return 2318 end,
        RequestLoadItemDataByID = function() end,
    },
    C_Timer = { After = function(_, fn) fn() end },
    debugstack = function() return '' end,
    GetMoneyString = function(money) return tostring(money) end,
    UIParent = { GetEffectiveScale = function() return 1 end },
    Minimap = {
        GetCenter = function() return 0, 0 end,
        GetWidth = function() return 140 end,
    },
    GetCursorPosition = function() return 0, 0 end,
    -- The settings API, before and after Blizzard_Settings loads.
    C_SettingsUtil = {
        OpenSettingsPanel = function() openedSettings = true end,
    },
    SlashCmdList = {},
    math = math,
    string = string,
    table = table,
    pairs = pairs,
    ipairs = ipairs,
    type = type,
    tostring = tostring,
    tonumber = tonumber,
    select = select,
    pcall = pcall,
    next = next,
    error = error,
    assert = assert,
    unpack = unpack,
    rawget = rawget,
    setmetatable = setmetatable,
    getmetatable = getmetatable,
    print = function() end,
    LibStub = function()
        return {
            AddLine = function() end,
            AddDoubleLine = function() end,
            AddCallback = function() end,
            RegisterTooltip = function() end,
            GetTooltipAdditional = function() return { quantity = 1 } end,
        }
    end,
}
env._G = env
setmetatable(env, { __index = _G })

local failures = 0
local function check(ok, msg)
    if not ok then
        io.stderr:write('FAIL ' .. msg .. '\n')
        failures = failures + 1
    end
end

-- Load each file as the client does, passing (addonName, addonTable).
for _, file in ipairs(files) do
    local path = ADDON .. '/' .. file
    local chunk, err = loadfile(path)
    if not chunk then
        io.stderr:write('FAIL cannot load ' .. path .. ': ' .. tostring(err) .. '\n')
        failures = failures + 1
    else
        setfenv(chunk, env)
        local ok, problem = pcall(chunk, 'OribosExchange', addonTable)
        if not ok then
            io.stderr:write('FAIL ' .. path .. ' raised: ' .. tostring(problem) .. '\n')
            failures = failures + 1
        end
    end
end

-- What the client provides at run time.
env.OEMarketInfo = function(itemID, out)
    if itemID == 2318 then
        out.input = itemID
        out.market = 500
        return out
    end
    if itemID == 2304 then
        out.input = itemID
        out.market = 2000
        return out
    end
    if itemID == 2841 then
        out.input = itemID
        out.market = 100
        return out
    end
    return out
end
addonTable.marketData = { ['0'] = true }

check(type(env.OETooltip) == 'function', 'OETooltip is missing')
check(type(env.OECraftCost) == 'function', 'OECraftCost is missing')
check(type(addonTable.getTooltipsSettings) == 'function', 'settings accessor is missing')
check(type(addonTable.coins) == 'function', 'coins is missing')

-- The panel hook is installed when the mixin first exists.
env.ProfessionsRecipeSchematicFormMixin = { Init = function() end }
env.ProfessionsUtil.IsCraftingMinimized = function() return false end

-- Fire the events the module waits on, the way the client would.
for _, frame in ipairs(frames) do
    for event in pairs(frame.events) do
        if event == 'ADDON_LOADED' or event == 'PLAYER_ENTERING_WORLD' or event == 'PLAYER_LOGIN' then
            if frame.scripts.OnEvent then
                pcall(frame.scripts.OnEvent, frame, event)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Options: the settings page and the minimap button
-- ---------------------------------------------------------------------------
check(type(addonTable.OpenOptions) == 'function', 'OpenOptions is missing')

-- Without Blizzard_Settings the page must not error, and the command has to
-- report that it could not open anything rather than silently do nothing.
local okMissing = pcall(addonTable.OpenOptions)
check(okMissing, 'OpenOptions raised while the settings API was absent')

-- Now let the API appear, as it does once Blizzard_Settings loads.
local categories, addOnCategories = {}, {}
env.Settings = {
    RegisterCanvasLayoutCategory = function(frame, name)
        local category = { id = #categories + 1, name = name, frame = frame, GetID = function(self) return self.id end }
        categories[#categories + 1] = category
        return category, { AddAnchorPoint = function() end }
    end,
    RegisterAddOnCategory = function(category)
        addOnCategories[#addOnCategories + 1] = category
    end,
}
-- Re-run the loader events so the page registers.
for _, frame in ipairs(frames) do
    for event in pairs(frame.events) do
        if event == 'PLAYER_LOGIN' then
            pcall(frame.scripts.OnEvent, frame, event)
        end
    end
end

check(#categories == 1, 'the options page did not register a category (' .. #categories .. ')')
check(#addOnCategories == 1, 'the category was not filed as an add-on category')
check(categories[1] and categories[1].name == 'Oribos Exchange', 'the category name is wrong')

openedSettings = false
local opened = addonTable.OpenOptions()
check(opened == true, 'OpenOptions did not report success once the API existed')
check(openedSettings == true, 'OpenOptions did not open the settings panel')

-- The page's own toggles must move the same preferences the tooltip code reads.
local page = categories[1].frame
check(type(page.Refresh) == 'function', 'the page has no Refresh')

local craftSetting = addonTable.SettingsPage
craftSetting.setOn('craft', false)
check(addonTable.getTooltipsSettings()['disable-craft'] == true, 'turning a line off did not store it')
check(craftSetting.isOn('craft') == false, 'the line did not read back as off')
craftSetting.setOn('craft', true)
check(addonTable.getTooltipsSettings()['disable-craft'] == nil, 'turning a line on did not clear it')
check(craftSetting.isOn('craft') == true, 'the line did not read back as on')

-- OnDefault must put every preference back.
addonTable.getTooltipsSettings()['disable-market'] = true
addonTable.getTooltipsSettings()['text-coins'] = true
page.OnDefault()
check(addonTable.getTooltipsSettings()['disable-market'] == nil, 'OnDefault left a line disabled')
check(addonTable.getTooltipsSettings()['text-coins'] == nil, 'OnDefault left the coin style changed')

-- The minimap button: shown by default, hideable, and remembered.
check(addonTable.minimapShown() == true, 'the minimap button is hidden by default')
addonTable.setMinimapShown(false)
check(addonTable.minimapShown() == false, 'hiding the minimap button was not remembered')
check(addonTable.getTooltipsSettings()['hideMinimap'] == true, 'the hide flag was not stored')
addonTable.setMinimapShown(true)
check(addonTable.minimapShown() == true, 'showing the minimap button was not remembered')
check(addonTable.getTooltipsSettings()['hideMinimap'] == nil, 'the hide flag was not cleared')

check(hooks['Init'] ~= nil, 'the recipe panel Init was not hooked')

if hooks['Init'] then
    local panel = makePanel()
    hooks['Init'](panel, { recipeID = 2152 })
    local line = panel.OECraftCostLine
    check(line ~= nil, 'no cost line was created')
    if line then
        check(line.shown, 'the cost line was not shown')
        check(line.text:find('Crafting', 1, true) ~= nil, 'no cost label: ' .. tostring(line.text))
        check(line.text:find('500', 1, true) ~= nil, 'no cost value: ' .. tostring(line.text))
        check(line.text:find('Craft profit', 1, true) ~= nil, 'no profit line: ' .. tostring(line.text))
        -- 2000 * 0.95 = 1900 value, minus 500 cost, over 500: 280%.
        check(line.text:find('1400', 1, true) ~= nil, 'no profit value: ' .. tostring(line.text))
        check(line.text:find('280%', 1, true) ~= nil, 'no roi: ' .. tostring(line.text))
    end

    -- A recipe the client has no schematic for: nothing drawn.
    local unknown = makePanel()
    hooks['Init'](unknown, { recipeID = 99999999 })
    check(unknown.OECraftCostLine == nil, 'an unknown recipe created a line')

    -- A recraft: nothing drawn.
    local recraft = makePanel()
    recraft.isRecraft = true
    hooks['Init'](recraft, { recipeID = 2152 })
    check(recraft.OECraftCostLine == nil, 'a recraft created a line')

    -- No recipe selected: nothing drawn.
    local empty = makePanel()
    hooks['Init'](empty, nil)
    check(empty.OECraftCostLine == nil, 'an empty selection created a line')

    -- The preference toggle must silence it.
    addonTable.getTooltipsSettings()['disable-craft'] = true
    local off = makePanel()
    hooks['Init'](off, { recipeID = 2152 })
    check(off.OECraftCostLine == nil, 'disable-craft did not silence the line')
    addonTable.getTooltipsSettings()['disable-craft'] = nil

    -- OETooltip(false) must silence it too.
    env.OETooltip(false)
    local hidden = makePanel()
    hooks['Init'](hidden, { recipeID = 2152 })
    check(hidden.OECraftCostLine == nil, 'OETooltip(false) did not silence the line')
    env.OETooltip(true)

    -- And it must come back.
    local back = makePanel()
    hooks['Init'](back, { recipeID = 2152 })
    check(back.OECraftCostLine ~= nil, 'the line did not return after enabling')

    -- Toggling the coin style must redraw, not reuse the cached string.
    local coinSettings = addonTable.getTooltipsSettings()
    local before = back.OECraftCostLine.text
    coinSettings['text-coins'] = true
    local restyled = makePanel()
    hooks['Init'](restyled, { recipeID = 2152 })
    check(restyled.OECraftCostLine and restyled.OECraftCostLine.text ~= before,
        'coin style change kept the cached string')
    coinSettings['text-coins'] = nil

    -- The cost sits under the reagent list, not under the output name.
    local withTools = makePanel()
    hooks['Init'](withTools, { recipeID = 2152 })
    local placed = withTools.OECraftCostLine
    check(placed and #placed.points == 1, 'the cost line was not anchored')
    if placed and #placed.points == 1 then
        local point = placed.points[1]
        check(point[2] == withTools.Reagents, 'the cost line is not under the reagents')
        check(point[3] == 'BOTTOMLEFT', 'the cost line is not anchored to the bottom of the reagents')
    end

    -- A taller optional list must take the cost line with it.
    local optional = makePanel()
    optional.OptionalReagents = makePanel().Reagents
    optional.OptionalReagents.shown = true
    optional.OptionalReagents.bottom = 300
    hooks['Init'](optional, { recipeID = 2152 })
    check(optional.OECraftCostLine and optional.OECraftCostLine.points[1]
        and optional.OECraftCostLine.points[1][2] == optional.OptionalReagents,
        'the cost line did not follow the optional reagents')

    -- The tool list must be left where Blizzard put it: the cost now lives
    -- below the reagents, so nothing is competing for that space any more.
    local toolsPanel = makePanel()
    toolsPanel.RequiredTools.shown = true
    hooks['Init'](toolsPanel, { recipeID = 2152 })
    check(#toolsPanel.RequiredTools.points == 0, 'RequiredTools was moved')

    -- A form missing its basic reagent list must still find a finishing list.
    -- A table literal would truncate at the nil and never see it.
    local sparse = makePanel()
    sparse.Reagents = nil
    sparse.OptionalReagents = nil
    sparse.FinishingReagents = makePanel().Reagents
    sparse.FinishingReagents.shown = true
    sparse.FinishingReagents.bottom = 200
    hooks['Init'](sparse, { recipeID = 2152 })
    check(sparse.OECraftCostLine and sparse.OECraftCostLine.points[1]
        and sparse.OECraftCostLine.points[1][2] == sparse.FinishingReagents,
        'a form without a basic list did not fall back to the finishing list')

    -- Once hidden, the same panel must hide its line again.
    withTools.isRecraft = true
    hooks['Init'](withTools, { recipeID = 2152 })
    check(not withTools.OECraftCostLine.shown, 'the line was left showing after a recraft')
end

if failures > 0 then
    io.stderr:write(string.format('\n%d failure(s)\n', failures))
    os.exit(1)
end
print('load order OK: ' .. #files .. ' files, panel hook, text and toggles behave')
