--[[

A minimap button, drawn by the addon: left-click opens the options page,
right-click toggles tooltip prices.

The addon ships no button library, and the button is small enough to draw
directly. It stores its position in the same saved preferences table as
everything else, so there is no second saved variable to declare.

]]

local addonName, addonTable = ...
local L = addonTable.localization

local BUTTON_SIZE = 32
local ICON = 'Interface\\Icons\\INV_Misc_Coin_02'
local DEFAULT_ANGLE = 220

local function settings()
    return addonTable.getTooltipsSettings and addonTable.getTooltipsSettings() or {}
end

local button

local function updatePosition(self)
    local angle = self.angle or DEFAULT_ANGLE
    local radius = (Minimap:GetWidth() / 2) + 5
    local x = math.cos(math.rad(angle)) * radius
    local y = math.sin(math.rad(angle)) * radius
    self:ClearAllPoints()
    self:SetPoint('CENTER', Minimap, 'CENTER', x, y)
end

-- Drag it around the minimap. The angle is stored, so it stays put between
-- sessions without a saved variable of its own. Only runs while dragging.
local function followCursor(f)
    local mx, my = Minimap:GetCenter()
    if not (mx and my) then return end
    -- GetCursorPosition is in screen pixels, GetCenter in the minimap's own
    -- coordinates, so the cursor is brought into the minimap's space with its
    -- full effective scale. UIParent's scale alone would cancel the scaling the
    -- minimap inherits, and the angle would be measured between two spaces.
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale
    f.angle = math.deg(math.atan2(cy - my, cx - mx))
    updatePosition(f)
end

local function startMoving(self)
    self:SetScript('OnUpdate', followCursor)
end

local function refreshIcon(self)
    local enabled = not addonTable.OETooltip or addonTable.OETooltip()
    self.icon:SetDesaturated(not enabled)
    self.icon:SetAlpha(enabled and 1 or .5)
end

-- The ring around the icon, the way Blizzard's own minimap buttons look.
local function drawRing(self)
    local border = self:CreateTexture(nil, 'BACKGROUND')
    border:SetSize(BUTTON_SIZE + 6, BUTTON_SIZE + 6)
    border:SetPoint('CENTER')
    border:SetTexture('Interface\\Minimap\\MiniMap-TrackingBorder')

    local background = self:CreateTexture(nil, 'BACKGROUND', nil, -1)
    background:SetSize(BUTTON_SIZE - 4, BUTTON_SIZE - 4)
    background:SetPoint('CENTER')
    background:SetTexture('Interface\\Minimap\\UI-Minimap-Background')

    local icon = self:CreateTexture(nil, 'ARTWORK')
    icon:SetSize(BUTTON_SIZE - 10, BUTTON_SIZE - 10)
    icon:SetPoint('CENTER')
    icon:SetTexture(ICON)
    icon:SetTexCoord(.08, .92, .08, .92)
    self.icon = icon
end

local function create()
    local self = CreateFrame('Button', 'OribosExchangeMinimapButton', Minimap)
    self:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    self:SetFrameStrata('MEDIUM')
    self:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
    self:RegisterForDrag('LeftButton')

    drawRing(self)

    self.angle = tonumber(settings().minimapAngle) or DEFAULT_ANGLE
    updatePosition(self)

    self:SetScript('OnDragStart', startMoving)
    self:SetScript('OnDragStop', function(f)
        settings().minimapAngle = f.angle
        f:SetScript('OnUpdate', nil)
    end)

    self:SetScript('OnEnter', function(f)
        GameTooltip:SetOwner(f, 'ANCHOR_LEFT')
        GameTooltip:AddLine(L["Oribos Exchange"], 1, 1, 1)
        GameTooltip:AddLine(L["Left-click: options"], .7, .7, .7)
        GameTooltip:AddLine(L["Right-click: toggle tooltip prices"], .7, .7, .7)
        GameTooltip:AddLine(L["Drag: move this button"], .7, .7, .7)
        GameTooltip:Show()
    end)
    self:SetScript('OnLeave', function() GameTooltip_Hide() end)

    self:SetScript('OnClick', function(f, mouseButton)
        if mouseButton == 'RightButton' then
            if addonTable.OETooltip then
                addonTable.OETooltip(not addonTable.OETooltip())
            end
            refreshIcon(f)
            if addonTable.SettingsPage then addonTable.SettingsPage.refresh() end
            return
        end
        if addonTable.OpenOptions then addonTable.OpenOptions() end
    end)

    refreshIcon(self)
    return self
end

--[[
    Public: whether the button is meant to be visible.
]]
function addonTable.minimapShown()
    return settings().hideMinimap ~= true
end

--[[
    Public: show or hide the button, and remember the choice.
]]
function addonTable.setMinimapShown(shown)
    -- Not "shown and nil or true": that always yields true, because a nil
    -- middle operand falls through to the third.
    if shown then
        settings().hideMinimap = nil
    else
        settings().hideMinimap = true
    end

    if not button then
        if not shown then return end
        button = create()
        return
    end
    button:SetShown(shown)
end

local loader = CreateFrame('Frame')
loader:RegisterEvent('PLAYER_LOGIN')
loader:SetScript('OnEvent', function()
    if addonTable.minimapShown() and not button then
        button = create()
    end
end)
