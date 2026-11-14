--[[

Crafting cost from auction-house prices, shown in the profession window.

Select a recipe and the recipe panel shows what its reagents cost at
auction-house prices and, when every reagent has a price, what the output sells
for after the 5% cut and the profit. It updates with the selection; there is
nothing to hover.

Only the recipe's basic reagents are priced. Optional and finishing reagents are
bonuses the player chooses to add, so a recipe is costed as written rather than
as currently allocated, where one cheap optional reagent could make a craft look
almost free.

Prices are the ones the tooltip lines already use: the selected house's 4-day
median of the daily lowest listings, falling back to the region median when the
house has no listing of that item. Both are medians, so one overpriced listing
does not move the cost.

Other addons can query it:

    o={}
    OECraftCost(recipeSpellID,o)
    print(o['cost'], o['value'], o['profit'], o['roi'])

    o['cost']    -> copper for the recipe's basic reagents
    o['priced']  -> how many of those reagents had a price
    o['total']   -> how many basic reagent slots the recipe has
    o['output']  -> the item one craft makes
    o['made']    -> how many it makes
    o['value']   -> the output's auction value, after the auction house cut;
                    absent when the output has no price or a reagent is unpriced
    o['profit']  -> value - cost, same conditions
    o['roi']     -> profit as a percentage of cost, absent when cost is zero
    o['age']     -> seconds since the price data was compiled

OECraftCost returns false when the client has no schematic for the recipe, which
is the case for a recipe whose profession is not open. That tells a caller "no
data" apart from "free".

]]

local addonName, addonTable = ...
local L = addonTable.localization

local floor = math.floor
local format = string.format
local tonumber, pcall = tonumber, pcall

-- The auction house keeps 5% of a sale, so the value shown is what the sale
-- would actually bring.
local AH_CUT = 0.05
local NO_ITEM = 0

local LABEL_COLOR = '|cffe6cc80'
local PROFIT_COLOR = '|cff21ff21'
local LOSS_COLOR = '|cffff2121'
local DIM = '|cff999999'
local RESET = '|r'

-- Numbers per recipe, invalidated when the price data changes (a reload, or a
-- live price source later). The drawn strings keep their own key, which also
-- changes with the coin style.
local crafts, craftAge = {}, nil
local drawnLines, drawnKey = {}, nil

local function settings()
    return addonTable.getTooltipsSettings and addonTable.getTooltipsSettings() or {}
end

-- Copper for one unit of the item: the selected house's median, else the region
-- median. Nil when the loaded data has no listing for it.
local function unitPrice(itemID)
    if not itemID or itemID <= NO_ITEM then return nil end

    -- A fresh table every time. OEMarketInfo only writes 'input' when it finds
    -- the item, so a reused table would carry the previous item's answer.
    local info = {}
    OEMarketInfo(itemID, info)
    if not info['input'] then return nil end

    local market = tonumber(info['market'])
    if market and market > 0 then return market end

    local region = tonumber(info['region'])
    if region and region > 0 then return region end
end

-- One craft's numbers for a recipe, from the client's own schematic. Nil when
-- the client has no schematic, as for a recipe outside its open profession.
local function craftFor(recipeID)
    if craftAge ~= addonTable.dataAge then
        crafts, craftAge = {}, addonTable.dataAge
    end
    local cached = crafts[recipeID]
    if cached ~= nil then return cached or nil end

    local ok, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
    if not (ok and schematic and schematic.reagentSlotSchematics) then
        crafts[recipeID] = false
        return nil
    end

    local basic = Enum.CraftingReagentType and Enum.CraftingReagentType.Basic or 1
    local craft = {
        cost = 0,
        priced = 0,
        total = 0,
        output = schematic.outputItemID,
        made = math.max(1, tonumber(schematic.quantityMin) or 1),
    }

    for _, slot in ipairs(schematic.reagentSlotSchematics) do
        local reagent = slot.reagents and slot.reagents[1]
        local itemID = reagent and tonumber(reagent.itemID)
        local need = tonumber(slot.quantityRequired) or 0
        -- A slot may pay a currency instead of an item, and an unrequired slot
        -- need not be filled; neither adds to the cost of the craft as written.
        if slot.reagentType == basic and slot.required ~= false and itemID and itemID > NO_ITEM and need > 0 then
            craft.total = craft.total + 1
            local each = unitPrice(itemID)
            if each then
                craft.cost = craft.cost + each * need
                craft.priced = craft.priced + 1
            end
        end
    end

    -- A value built on a partly unpriced cost would overstate the profit, so
    -- the comparison is only made when every reagent is known.
    if craft.output and craft.output > NO_ITEM and craft.priced == craft.total then
        local each = unitPrice(craft.output)
        if each then
            craft.value = floor(each * craft.made * (1 - AH_CUT))
            craft.profit = craft.value - craft.cost
            if craft.cost > 0 then
                craft.roi = craft.profit / craft.cost * 100
            end
        end
    end

    if addonTable.dataAge then
        craft.age = time() - addonTable.dataAge
    end

    crafts[recipeID] = craft
    return craft
end

--[[
    Public: one craft's cost and value for a recipe spell ID. Copies into the
    optional table (wiped first), as OEMarketInfo does. False when the client has
    no schematic for the recipe.
]]
function OECraftCost(recipeID, out)
    recipeID = tonumber(recipeID)
    if not (recipeID and addonTable.marketData) then return false end

    local craft = craftFor(recipeID)
    if not craft then return false end

    local tr = out
    if tr then
        wipe(tr)
    else
        tr = {}
    end
    for k, v in pairs(craft) do tr[k] = v end
    return tr
end

-- A value covering more than one item is marked the way the stack lines mark a
-- stack.
local function madeLabel(label, made)
    if made > 1 then
        return label .. ' x' .. made
    end
    return label
end

-- Negative money would confuse the coin formatter, so the sign is written out.
local function money(value)
    if value < 0 then
        return '-' .. addonTable.coins(-value)
    end
    return addonTable.coins(value)
end

-- A percentage with a thousands separator, so a 1040% craft reads as 1,040%
-- rather than a wall of digits. '%.0f' keeps a huge value out of the exponent
-- form tostring would use for it.
local function percent(roi)
    local digits = format('%.0f', math.abs(roi))
    local grouped = digits:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
    if roi < 0 then
        grouped = '-' .. grouped
    end
    return grouped .. '%'
end

-- The text the recipe panel shows, as one string with a line per figure. Built
-- once per recipe and reused, because the panel is re-initialized often.
local function drawnFor(recipeID)
    local key = (settings()['text-coins'] and 'text' or 'icons') .. '/' .. tostring(addonTable.dataAge)
    if drawnKey ~= key then
        drawnLines, drawnKey = {}, key
    end
    local cached = drawnLines[recipeID]
    if cached ~= nil then return cached or nil end

    local craft = craftFor(recipeID)
    -- Nothing priced at all is not a free craft, it is an unknown one.
    if not (craft and craft.total > 0 and craft.priced > 0) then
        drawnLines[recipeID] = false
        return nil
    end

    local unpriced = craft.total - craft.priced
    local lines = { LABEL_COLOR .. L["Crafting cost"] .. RESET }
    if unpriced > 0 then
        lines[1] = lines[1] .. DIM .. '*' .. RESET
    end
    lines[1] = lines[1] .. '  ' .. money(craft.cost)

    if craft.value then
        local profit = craft.profit or 0
        local color = profit < 0 and LOSS_COLOR or PROFIT_COLOR
        local second = color .. madeLabel(L["Craft profit"], craft.made) .. '  ' .. money(profit)
        if craft.roi then
            second = second .. ' ' .. DIM .. '(' .. percent(craft.roi) .. ')'
        end
        lines[#lines + 1] = second .. RESET
    end

    if unpriced > 0 then
        lines[#lines + 1] = DIM .. format(L["* %d of %d reagents have no price"], unpriced, craft.total) .. RESET
    end

    local drawn = table.concat(lines, '\n')
    drawnLines[recipeID] = drawn
    return drawn
end

-- The reagent containers stack under the description: the basic list, then the
-- optional list, and in the minimized view a finishing list beside or below it.
-- The cost goes under whichever of them reaches lowest, so it never covers a
-- list taller than the basic one. Positions are only trusted once the panel has
-- been laid out; before that the list order decides.
local function lowestReagentContainer(form)
    local shown = {}
    -- Appended one at a time: a missing frame would truncate a table literal
    -- and hide the containers after it.
    for _, key in ipairs({ 'Reagents', 'OptionalReagents', 'FinishingReagents' }) do
        local frame = form[key]
        if frame and frame.IsShown and frame:IsShown() then
            shown[#shown + 1] = frame
        end
    end

    local lowest, lowestBottom
    for _, frame in ipairs(shown) do
        local bottom = frame.GetBottom and frame:GetBottom()
        if bottom and bottom > 0 and (not lowestBottom or bottom < lowestBottom) then
            lowest, lowestBottom = frame, bottom
        end
    end

    -- Not laid out yet: the containers are anchored in this order, so the last
    -- one shown is the bottom of the stack.
    if not lowest then
        lowest = shown[#shown]
    end
    return lowest
end

-- Draw the cost under the reagents. It updates with the selection, so there is
-- nothing to hover.
local function showCost(form, recipeID)
    local text
    if not settings()['disable-craft'] and addonTable.marketData then
        if not (addonTable.OETooltip and not addonTable.OETooltip()) then
            text = drawnFor(recipeID)
        end
    end

    local line = form.OECraftCostLine
    if not text then
        if line then line:Hide() end
        return
    end

    if not line then
        line = form:CreateFontString(nil, 'ARTWORK', 'GameFontNormal')
        line:SetJustifyH('LEFT')
        line:SetJustifyV('TOP')
        form.OECraftCostLine = line
    end

    local minimized = ProfessionsUtil and ProfessionsUtil.IsCraftingMinimized and ProfessionsUtil.IsCraftingMinimized()
    line:SetWidth(minimized and 250 or 300)
    line:SetText(text)

    local anchorTo = lowestReagentContainer(form)
    line:ClearAllPoints()
    if anchorTo then
        line:SetPoint('TOPLEFT', anchorTo, 'BOTTOMLEFT', 0, -10)
    else
        -- A recipe with no reagent list still gets the numbers, under the name.
        line:SetPoint('TOPLEFT', form.OutputText, 'BOTTOMLEFT', 0, -4)
    end
    line:Show()
end

-- The recipe panel initializes on every selection, and the order forms use the
-- same mixin, so one hook covers both.
local panelHooked = false

local function hookPanel()
    if panelHooked then return end
    local mixin = _G.ProfessionsRecipeSchematicFormMixin
    if type(mixin) ~= 'table' or type(mixin.Init) ~= 'function' then return end

    panelHooked = true
    hooksecurefunc(mixin, 'Init', function(form, recipeInfo)
        if not recipeInfo then
            if form.OECraftCostLine then form.OECraftCostLine:Hide() end
            return
        end
        if form.isRecraft then
            if form.OECraftCostLine then form.OECraftCostLine:Hide() end
            return
        end
        showCost(form, recipeInfo.recipeID)
    end)
end

-- Blizzard_ProfessionsTemplates loads on demand with the profession window, so
-- the mixin may not exist yet.
hookPanel()

local watcher = CreateFrame('Frame')
watcher:RegisterEvent('PLAYER_ENTERING_WORLD')
watcher:RegisterEvent('ADDON_LOADED')
watcher:SetScript('OnEvent', function()
    hookPanel()
end)
