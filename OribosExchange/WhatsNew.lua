--[[
    What's New panel and data-sync status.

    Bump `revision` and replace `entries` when a release adds a feature or a
    user-visible fix. Data-only price refreshes leave this file untouched, so
    they never open the panel; their status goes to chat instead.
]]

local addonName, addonTable = ...
local L = addonTable.localization

local floor = math.floor
local SYNC_INTERVAL = 3 * 60 * 60

local function contains(t, value)
    for _, entry in ipairs(t) do
        if entry == value then return true end
    end
    return false
end

local function coinText(copper)
    if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
        return C_CurrencyInfo.GetCoinTextureString(copper, 12)
    end
    if GetMoneyString then
        return GetMoneyString(copper, true)
    end
    return tostring(copper)
end

local function durationText(seconds)
    seconds = floor(tonumber(seconds) or 0)
    if seconds < 0 then seconds = 0 end
    if seconds < 1 then return L["just now"] end
    return SecondsToTime(seconds, seconds > 60) or L["just now"]
end

local function syncAges()
    local dataAge = tonumber(addonTable.dataAge)
    if not dataAge then return nil end
    local age = math.max(0, time() - dataAge)
    local remaining = math.max(0, SYNC_INTERVAL - age)
    return age, remaining
end

local WhatsNew = {
    revision = 1,
    entries = {
        {
            kind = "FEATURE",
            title = L["Stack value with Shift"],
            description = L["Hold Shift over a stack to see the total value of the whole stack on the realm and region lines. Release Shift to return to per-item prices."],
            icon = "Interface\\Icons\\INV_Misc_Coin_02",
            preview = {
                { L["Realm"] .. " x20", coinText(240000) },
                { L["Regional"] .. " x20", coinText(200000) },
            },
        },
        {
            kind = "FEATURE",
            title = L["What's New panel"],
            description = L["A new panel shows the features and fixes in each update, with icons and previews. Reopen it with /oetooltip whatsnew."],
            icon = "Interface\\Icons\\INV_Misc_Note_01",
        },
        {
            kind = "FEATURE",
            title = L["Auction house data sync status"],
            description = L["Login chat now reports when the auction-house data was last synced and when the next sync is due. Data-only updates skip the panel and use this chat status."],
            icon = "Interface\\Icons\\INV_Misc_PocketWatch_01",
        },
    },
}
addonTable.WhatsNew = WhatsNew

function WhatsNew.DataSyncChatLines()
    local age, remaining = syncAges()
    if not age then return nil end

    local first = L["Auction house data last synced %s ago."]:format(durationText(age))
    local second
    if remaining <= 0 then
        second = L["Next sync available now."]
    else
        second = L["Next sync available in %s."]:format(durationText(remaining))
    end
    return first, second
end

function WhatsNew.DataSyncFooterText()
    local age, remaining = syncAges()
    if not age then return L["No auction house data loaded."] end

    if remaining <= 0 then
        return L["Data %s old · next sync available now"]:format(durationText(age))
    end
    return L["Data %s old · next sync in %s"]:format(durationText(age), durationText(remaining))
end

function WhatsNew.SeenRevision()
    local seen = _G.OEWhatsNewSeen
    if type(seen) == "table" then
        return tonumber(seen.revision) or 0
    end
    return tonumber(seen) or 0
end

function WhatsNew.HasUnseen()
    return WhatsNew.SeenRevision() < WhatsNew.revision
end

function WhatsNew.MarkSeen()
    local seen = _G.OEWhatsNewSeen
    if type(seen) ~= "table" then seen = {} end
    seen.revision = WhatsNew.revision
    _G.OEWhatsNewSeen = seen
end

local frame

local function versionText()
    local version
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        version = C_AddOns.GetAddOnMetadata(addonName, "Version")
    elseif GetAddOnMetadata then
        version = GetAddOnMetadata(addonName, "Version")
    end

    local brand = L["Oribos Exchange by ZiiM"]
    if version and version ~= "" then
        return brand .. " · " .. L["Version %s"]:format(version)
    end
    return brand
end

local function fontTemplate(name, fallback)
    if _G[name] then return name end
    return fallback
end

local function fontString(parent, template, text, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    if text then fs:SetText(text) end
    if r then fs:SetTextColor(r, g, b) end
    return fs
end

local function applyBackdrop(f, bgAlpha, borderAlpha)
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        f:SetBackdropColor(0.03, 0.04, 0.06, bgAlpha or 0.96)
        f:SetBackdropBorderColor(0.85, 0.68, 0.30, borderAlpha or 1)
    else
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.03, 0.04, 0.06, bgAlpha or 0.96)
    end
end

local function createBackdrop(parent, bgAlpha, borderAlpha)
    local f = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    applyBackdrop(f, bgAlpha, borderAlpha)
    return f
end

local CARD_PADDING = 16
local CARD_GAP = 12
local ICON_SIZE = 64
local ICON_GAP = 16
local CONTENT_WIDTH = 528

local function buildCard(parent, entry, y)
    local card = CreateFrame("Frame", nil, parent)
    card:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
    card:SetWidth(CONTENT_WIDTH)

    local bg = card:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(1, 1, 1, 0.035)

    local accentColor = entry.kind == "FIX" and { 1.0, 0.55, 0.25 } or { 0.35, 1.0, 0.55 }
    local accent = card:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT")
    accent:SetPoint("BOTTOMLEFT")
    accent:SetWidth(3)
    accent:SetColorTexture(accentColor[1], accentColor[2], accentColor[3], 0.9)

    local iconBG = card:CreateTexture(nil, "BORDER")
    iconBG:SetSize(ICON_SIZE + 6, ICON_SIZE + 6)
    iconBG:SetPoint("TOPLEFT", CARD_PADDING, -CARD_PADDING)
    iconBG:SetColorTexture(0, 0, 0, 0.55)

    local icon = card:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("CENTER", iconBG)
    icon:SetTexture(entry.icon or "Interface\\Icons\\INV_Misc_QuestionMark")

    local textX = CARD_PADDING + ICON_SIZE + 6 + ICON_GAP
    local textWidth = CONTENT_WIDTH - textX - CARD_PADDING

    local tag = fontString(card,
        fontTemplate("GameFontNormalSmall", "GameFontNormal"),
        L[entry.kind] or entry.kind,
        accentColor[1], accentColor[2], accentColor[3])
    tag:SetPoint("TOPLEFT", textX, -CARD_PADDING)

    local title = fontString(card,
        fontTemplate("GameFontNormalLarge", "GameFontNormal"),
        entry.title,
        1.0, 0.82, 0.35)
    title:SetWidth(textWidth)
    title:SetWordWrap(true)
    title:SetPoint("TOPLEFT", tag, "BOTTOMLEFT", 0, -2)

    local description = fontString(card,
        fontTemplate("GameFontHighlightSmall", "GameFontHighlight"),
        entry.description,
        0.78, 0.78, 0.82)
    description:SetWidth(textWidth)
    description:SetWordWrap(true)
    description:SetSpacing(2)
    description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)

    local textHeight = tag:GetStringHeight() + 2
        + title:GetStringHeight() + 4
        + description:GetStringHeight()

    local previewHeight = 0
    if entry.preview and #entry.preview > 0 then
        local lineHeight = 18
        previewHeight = 16 + #entry.preview * lineHeight
        local preview = createBackdrop(card, 0.55, 0.35)
        preview:SetPoint("TOPLEFT", textX, -(CARD_PADDING + textHeight + 10))
        preview:SetSize(textWidth, previewHeight)

        for i, line in ipairs(entry.preview) do
            local left = fontString(preview,
                fontTemplate("GameFontHighlightSmall", "GameFontHighlight"),
                line[1], 0.9, 0.8, 0.5)
            left:SetPoint("TOPLEFT", 10, -(8 + (i - 1) * lineHeight))
            left:SetWidth(textWidth * 0.55)

            local right = fontString(preview,
                fontTemplate("GameFontHighlightSmall", "GameFontHighlight"),
                line[2], 1, 1, 1)
            right:SetPoint("TOPRIGHT", -10, -(8 + (i - 1) * lineHeight))
            right:SetJustifyH("RIGHT")
        end
    end

    local contentHeight = textHeight + (previewHeight > 0 and previewHeight + 10 or 0)
    if contentHeight < ICON_SIZE + 6 then contentHeight = ICON_SIZE + 6 end
    local cardHeight = contentHeight + CARD_PADDING * 2
    card:SetHeight(cardHeight)
    return cardHeight
end

local function buildFrame()
    local f = CreateFrame("Frame", "OribosExchangeWhatsNew", UIParent,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(620, 600)
    f:SetPoint("CENTER")
    f:SetClampedToScreen(true)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)

    applyBackdrop(f, 0.97, 1)

    if not contains(UISpecialFrames, "OribosExchangeWhatsNew") then
        table.insert(UISpecialFrames, "OribosExchangeWhatsNew")
    end

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -8, -8)
    close:SetScript("OnClick", function() f:Hide() end)

    local drag = CreateFrame("Frame", nil, f)
    drag:SetPoint("TOPLEFT", 10, -10)
    drag:SetPoint("TOPRIGHT", close, "LEFT", -4, 0)
    drag:SetHeight(72)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() f:StartMoving() end)
    drag:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

    local headerBg = f:CreateTexture(nil, "BACKGROUND")
    headerBg:SetPoint("TOPLEFT", 4, -4)
    headerBg:SetPoint("TOPRIGHT", -4, -4)
    headerBg:SetHeight(96)
    headerBg:SetTexture("Interface\\Buttons\\WHITE8X8")
    if headerBg.SetGradient and CreateColor then
        headerBg:SetGradient("VERTICAL",
            CreateColor(0.22, 0.16, 0.05, 0.85),
            CreateColor(0.03, 0.04, 0.06, 0))
    else
        headerBg:SetColorTexture(0.12, 0.10, 0.04, 0.5)
    end

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(56, 56)
    icon:SetPoint("TOPLEFT", 24, -22)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")

    local title = fontString(f,
        fontTemplate("GameFontNormalHuge", "GameFontNormalLarge"),
        L["What's New"],
        1, 0.82, 0.35)
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 16, -4)
    title:SetPoint("RIGHT", close, "LEFT", -12, 0)

    local subtitle = fontString(f,
        fontTemplate("GameFontHighlightSmall", "GameFontHighlight"),
        versionText() or L["Oribos Exchange"],
        0.8, 0.8, 0.85)
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 1, -4)
    subtitle:SetPoint("RIGHT", close, "LEFT", -12, 0)

    local divider = f:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", 24, -100)
    divider:SetPoint("TOPRIGHT", -24, -100)
    divider:SetHeight(1)
    divider:SetColorTexture(0.85, 0.68, 0.30, 0.55)

    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 24, -112)
    scroll:SetPoint("BOTTOMRIGHT", -42, 88)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    content:SetWidth(CONTENT_WIDTH)

    local y = 0
    for _, entry in ipairs(WhatsNew.entries) do
        y = y + buildCard(content, entry, y) + CARD_GAP
    end
    content:SetHeight(math.max(1, y))

    local footerLine = f:CreateTexture(nil, "ARTWORK")
    footerLine:SetPoint("BOTTOMLEFT", 24, 78)
    footerLine:SetPoint("BOTTOMRIGHT", -24, 78)
    footerLine:SetHeight(1)
    footerLine:SetColorTexture(0.85, 0.68, 0.30, 0.35)

    local status = fontString(f,
        fontTemplate("GameFontHighlightSmall", "GameFontHighlight"),
        nil,
        0.7, 0.7, 0.75)
    status:SetPoint("BOTTOMLEFT", 24, 54)
    status:SetPoint("BOTTOMRIGHT", -24, 54)

    local hint = fontString(f,
        fontTemplate("GameFontDisableSmall", "GameFontHighlightSmall"),
        L["Reopen with /oetooltip whatsnew."],
        0.5, 0.5, 0.55)
    hint:SetPoint("BOTTOMLEFT", 24, 18)

    local button = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    button:SetSize(120, 24)
    button:SetPoint("BOTTOMRIGHT", -24, 18)
    button:SetText(L["Got it"])
    button:SetScript("OnClick", function() f:Hide() end)

    f.status = status
    f.subtitle = subtitle
    f:SetScript("OnHide", function() WhatsNew.MarkSeen() end)
    return f
end

function WhatsNew.Show()
    if not frame then frame = buildFrame() end

    frame.status:SetText(WhatsNew.DataSyncFooterText())

    local wasShown = frame:IsShown()
    frame:Show()
    WhatsNew.MarkSeen()
    frame:Raise()
    if not wasShown and UIFrameFadeIn then
        frame:SetAlpha(0)
        UIFrameFadeIn(frame, 0.2, 0, 1)
    end
end
