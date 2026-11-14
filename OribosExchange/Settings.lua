--[[

The options page: Options > AddOns > Oribos Exchange, and a minimap button that
opens it.

The page is a canvas, so its layout and wording match the rest of the addon
rather than the generic settings list. Each checkbox writes into the same saved
preferences table the slash command uses, so `/oetooltip` and this page never
disagree.

The minimap button is drawn here rather than by a library: the addon ships no
button library, and one small frame is cheaper than embedding one.

]]

local addonName, addonTable = ...
local L = addonTable.localization

local floor = math.floor
local format = string.format

local C = {
    accent = { .2, 1, .6 },
    text = { .9, .9, .9 },
    dim = { .55, .55, .55 },
}

-- The lines the page controls, in display order, with the key each one stores
-- under. The same names the slash command and the tooltip code read.
local LINES = {
    { key = 'craft', label = "Crafting cost in the profession window." },
    { key = 'market', label = "Realm price line." },
    { key = 'region', label = "Region median line." },
    { key = 'lastSeen', label = "'Last seen' line." },
    { key = 'age', label = "Data age line." },
}

-- Preferences live in the saved table; these helpers keep the null-means-on
-- convention in one place.
local function settings()
    return addonTable.getTooltipsSettings and addonTable.getTooltipsSettings() or {}
end

local function isOn(key)
    return not settings()['disable-' .. key]
end

local function setOn(key, on)
    local store = settings()
    if on then
        store['disable-' .. key] = nil
    else
        store['disable-' .. key] = true
    end
end

local function tooltipAdditionOn()
    return not addonTable.OETooltip or addonTable.OETooltip()
end

local function setTooltipAddition(on)
    if addonTable.OETooltip then addonTable.OETooltip(on) end
end

local function coinTextOn()
    return settings()['text-coins'] and true or false
end

local function setCoinText(on)
    settings()['text-coins'] = on and true or nil
end

-- ---------------------------------------------------------------------------
-- A small checkbox in the addon's own colours.
-- ---------------------------------------------------------------------------
local function createCheckbox(parent, label, getter, setter)
    local button = CreateFrame('Button', nil, parent)
    button:SetHeight(22)
    button:SetPoint('LEFT')
    button:SetPoint('RIGHT')

    local box = button:CreateTexture(nil, 'ARTWORK')
    box:SetSize(16, 16)
    box:SetPoint('LEFT', 2, 0)
    box:SetColorTexture(.1, .1, .1, 1)

    local border = button:CreateTexture(nil, 'OVERLAY')
    border:SetSize(18, 18)
    border:SetPoint('CENTER', box, 'CENTER')
    border:SetColorTexture(.45, .4, .3, 1)
    border:SetDrawLayer('BACKGROUND', -1)

    local tick = button:CreateTexture(nil, 'OVERLAY')
    tick:SetSize(10, 10)
    tick:SetPoint('CENTER', box, 'CENTER')
    tick:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)

    local text = button:CreateFontString(nil, 'ARTWORK', 'GameFontHighlight')
    text:SetPoint('LEFT', box, 'RIGHT', 8, 0)
    text:SetPoint('RIGHT', -2, 0)
    text:SetJustifyH('LEFT')
    text:SetText(label)

    button.getter, button.setter = getter, setter

    local highlight = button:CreateTexture(nil, 'HIGHLIGHT')
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, .06)

    function button:Refresh()
        local on = self.getter()
        tick:SetShown(on)
        if on then
            box:SetColorTexture(.16, .16, .16, 1)
            text:SetTextColor(C.text[1], C.text[2], C.text[3])
        else
            box:SetColorTexture(.1, .1, .1, 1)
            text:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
        end
    end

    button:SetScript('OnClick', function(self)
        self.setter(not self.getter())
        self:Refresh()
    end)

    function button:SetEnabledState(enabled)
        if enabled then
            self:Enable()
            text:SetAlpha(1)
        else
            self:Disable()
            text:SetAlpha(.4)
        end
        self:Refresh()
    end

    button:Refresh()
    return button
end

-- ---------------------------------------------------------------------------
-- The page
-- ---------------------------------------------------------------------------
local frame
local refreshers = {}

local function buildPage()
    local page = CreateFrame('Frame')
    page.name = L["Oribos Exchange"]

    local title = page:CreateFontString(nil, 'ARTWORK', 'GameFontNormalLarge')
    title:SetPoint('TOPLEFT', 16, -16)
    title:SetText(L["Oribos Exchange"])

    local subtitle = page:CreateFontString(nil, 'ARTWORK', 'GameFontHighlightSmall')
    subtitle:SetPoint('TOPLEFT', title, 'BOTTOMLEFT', 0, -6)
    subtitle:SetText(L["Auction-house prices in item tooltips, using Blizzard's Forever auction data."])
    subtitle:SetTextColor(C.dim[1], C.dim[2], C.dim[3])

    -- Tooltip additions on/off, which is what OETooltip() reports.
    local master = createCheckbox(page, L["Show prices in tooltips"], tooltipAdditionOn, setTooltipAddition)
    master:SetPoint('TOPLEFT', subtitle, 'BOTTOMLEFT', 0, -18)
    master:SetPoint('RIGHT', -16, 0)
    refreshers[#refreshers + 1] = master

    local linesHeader = page:CreateFontString(nil, 'ARTWORK', 'GameFontNormal')
    linesHeader:SetPoint('TOPLEFT', master, 'BOTTOMLEFT', 2, -16)
    linesHeader:SetText(L["Lines"])
    linesHeader:SetTextColor(C.accent[1], C.accent[2], C.accent[3])

    local previous, lineBoxes = linesHeader, {}
    for _, line in ipairs(LINES) do
        local key = line.key
        local box = createCheckbox(page, L[line.label], function() return isOn(key) end,
            function(on) setOn(key, on) end)
        box:SetPoint('TOPLEFT', previous, 'BOTTOMLEFT', 0, -6)
        box:SetPoint('RIGHT', -16, 0)
        previous = box
        lineBoxes[#lineBoxes + 1] = box
        refreshers[#refreshers + 1] = box
    end

    -- A line whose parent is off cannot take effect; say so instead of leaving
    -- a checkbox that appears to do nothing.
    local note = page:CreateFontString(nil, 'ARTWORK', 'GameFontHighlightSmall')
    note:SetPoint('TOPLEFT', previous, 'BOTTOMLEFT', 18, -6)
    note:SetText(L["Lines are shown only while tooltip prices are on."])
    note:SetTextColor(C.dim[1], C.dim[2], C.dim[3])

    local coins = createCheckbox(page, L["Use text instead of coin icons"],
        coinTextOn, setCoinText)
    coins:SetPoint('TOPLEFT', note, 'BOTTOMLEFT', -18, -14)
    coins:SetPoint('RIGHT', -16, 0)
    refreshers[#refreshers + 1] = coins

    local data = page:CreateFontString(nil, 'ARTWORK', 'GameFontHighlightSmall')
    data:SetPoint('TOPLEFT', coins, 'BOTTOMLEFT', 18, -18)
    data:SetPoint('RIGHT', -16, 0)
    data:SetJustifyH('LEFT')
    data:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
    page.dataStatus = data

    -- The minimap button toggle sits with the page it belongs to, so there is
    -- one place to turn everything off.
    local minimap = createCheckbox(page, L["Show a minimap button"],
        function() return addonTable.minimapShown and addonTable.minimapShown() end,
        function(on) if addonTable.setMinimapShown then addonTable.setMinimapShown(on) end end)
    minimap:SetPoint('TOPLEFT', data, 'BOTTOMLEFT', -18, -6)
    minimap:SetPoint('RIGHT', -16, 0)
    refreshers[#refreshers + 1] = minimap

    function page:Refresh()
        for _, widget in ipairs(refreshers) do
            widget:Refresh()
        end

        local additions = tooltipAdditionOn()
        for _, box in ipairs(lineBoxes) do
            box:SetEnabledState(additions)
        end

        if addonTable.dataAge then
            local age = math.max(0, time() - addonTable.dataAge)
            self.dataStatus:SetText(format(L["Data synced %s ago."], SecondsToTime(age, age > 60)))
        else
            self.dataStatus:SetText(L["No auction house data loaded."])
        end
    end

    -- Canvas pages get these callbacks when the panel shows or resets.
    page.OnRefresh = function() page:Refresh() end
    page.OnDefault = function()
        local store = settings()
        wipe(store)
        for _, line in ipairs(LINES) do setOn(line.key, true) end
        setTooltipAddition(true)
        if addonTable.setMinimapShown then addonTable.setMinimapShown(true) end
        page:Refresh()
    end

    page:Refresh()
    return page
end

-- ---------------------------------------------------------------------------
-- Registration
-- ---------------------------------------------------------------------------
local registered = false

local function register()
    if registered then return end
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
        return
    end

    frame = buildPage()
    local category, layout = Settings.RegisterCanvasLayoutCategory(frame, L["Oribos Exchange"])
    if layout and layout.AddAnchorPoint then
        layout:AddAnchorPoint('TOPLEFT', 0, 0)
        layout:AddAnchorPoint('BOTTOMRIGHT', 0, 0)
    end
    Settings.RegisterAddOnCategory(category)
    addonTable.settingsCategory = category
    registered = true
end

--[[
    Public: open this addon's page in the settings panel.
]]
function addonTable.OpenOptions()
    register()
    if C_SettingsUtil and C_SettingsUtil.OpenSettingsPanel and addonTable.settingsCategory then
        C_SettingsUtil.OpenSettingsPanel(addonTable.settingsCategory:GetID())
        return true
    end
    if InterfaceOptionsFrame_OpenToCategory and frame then
        InterfaceOptionsFrame_OpenToCategory(frame)
        InterfaceOptionsFrame_OpenToCategory(frame)
        return true
    end
    return false
end

-- The settings API needs Blizzard_Settings loaded, which happens with the rest
-- of the interface, so register once it exists rather than at file load.
local watcher = CreateFrame('Frame')
watcher:RegisterEvent('ADDON_LOADED')
watcher:RegisterEvent('PLAYER_LOGIN')
watcher:SetScript('OnEvent', function()
    register()
end)
register()

addonTable.SettingsPage = {
    register = register,
    refresh = function()
        if frame then frame:Refresh() end
    end,
    isOn = isOn,
    setOn = setOn,
}
