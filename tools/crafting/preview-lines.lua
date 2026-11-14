-- Renders the recipe panel text the way the profession window would, for the
-- cases worth eyeballing: profitable, unpriced reagent, multi-output, and a
-- loss. Colour codes are shown as their readable text so the output is legible.
--
-- Usage: luajit tools/crafting/preview-lines.lua [data.us.lua]

local dataFile = arg[1] or 'OribosExchange/dynamic/data.us.lua'

local addonTable = { dataLoads = {} }
local env = setmetatable({
    addonTable = addonTable,
    string = string,
    pairs = pairs,
    ipairs = ipairs,
    sort = table.sort,
    wipe = function(t) for k in pairs(t) do t[k] = nil end end,
    GetRealmID = function() return 0 end,
    GetRealmName = function() return 'Test' end,
    UnitFactionGroup = function() return 'Alliance' end,
    GetCurrentRegion = function() return 1 end,
    C_Item = { GetItemInfo = function() return nil end },
    time = os.time,
    date = os.date,
}, { __index = _G })

local chunk = assert(loadfile(dataFile))
setfenv(chunk, env)
chunk('OribosExchange', addonTable)
for _, load in ipairs(addonTable.dataLoads) do
    load('33391', 'Alliance', 'Test')
end

local function char2dec(s)
    local n = 0
    for i = 1, #s do n = n * 256 + s:byte(i) end
    return n
end

local function decode(blob)
    local priceSize = blob:byte(1)
    local recordOffset = 2 + priceSize
    return {
        region = char2dec(blob:sub(2, 1 + priceSize)),
        market = char2dec(blob:sub(recordOffset + 1, recordOffset + priceSize)),
    }
end

-- Recipes chosen to exercise each display case.
local recipes = {
    { spell = 20648, out = 4234, count = 1, parts = { { 2318, 4 }, { 2320, 1 } }, note = 'profitable' },
    { spell = 16667, out = 12628, count = 1,
        parts = { { 12359, 40 }, { 12662, 10 }, { 12361, 4 }, { 7910, 4 } }, note = 'one reagent unpriced' },
    { spell = 1252343, out = 250594, count = 1, parts = { { 124437, 1 } }, note = 'high margin' },
}

local schema = {}
for _, r in ipairs(recipes) do
    local slots = {}
    for _, part in ipairs(r.parts) do
        slots[#slots + 1] = {
            reagentType = 1,
            required = true,
            quantityRequired = part[2],
            reagents = { { itemID = part[1] } },
        }
    end
    schema[r.spell] = {
        recipeID = r.spell,
        outputItemID = r.out,
        quantityMin = r.count,
        quantityMax = r.count,
        reagentSlotSchematics = slots,
    }
end

-- Coins as plain text, the way /oetooltip coins text renders them.
addonTable.coins = function(money)
    money = math.floor(tonumber(money) or 0)
    local sign = money < 0 and '-' or ''
    money = math.abs(money)
    local gold = math.floor(money / 10000)
    local silver = math.floor(money % 10000 / 100)
    local copper = money % 100
    local parts = {}
    if gold > 0 then parts[#parts + 1] = gold .. 'g' end
    if silver > 0 then parts[#parts + 1] = silver .. 's' end
    if copper > 0 or #parts == 0 then parts[#parts + 1] = copper .. 'c' end
    return sign .. table.concat(parts, ' ')
end

addonTable.localization = setmetatable({}, { __index = function(_, k) return k end })
addonTable.getTooltipsSettings = function() return {} end
-- addonTable.marketData is already populated by the data file above.

env.Enum = { CraftingReagentType = { Modifying = 0, Basic = 1, Finishing = 2, Automatic = 3 } }
env.C_TradeSkillUI = { GetRecipeSchematic = function(recipeID) return schema[recipeID] end }
env.CreateFrame = function() return { RegisterEvent = function() end, SetScript = function() end } end
env.ProfessionsUtil = { IsCraftingMinimized = function() return false end }
env.ProfessionsRecipeSchematicFormMixin = { Init = function() end }
env.time = os.time
-- The module reads these through _G, so point it at this sandbox.
env._G = env
env.OEMarketInfo = function(itemID, out)
    local blob = addonTable.marketData[tostring(itemID)]
    if not blob then return out end
    local got = decode(blob)
    out.input = itemID
    if got.market > 0 then out.market = got.market end
    if got.region > 0 then out.region = got.region end
    return out
end

-- Capture the panel hook Crafting.lua installs. The mixin has to exist before
-- the file loads, because it hooks at load time.
local installed
env.hooksecurefunc = function(_, _, fn) if not installed then installed = fn end end

local craftChunk = assert(loadfile('OribosExchange/Crafting.lua'))
setfenv(craftChunk, env)
craftChunk('OribosExchange', addonTable)

assert(installed, 'Crafting.lua did not hook the recipe panel')

-- OECraftCost lands in the file's environment, not this chunk's.
local OECraftCost = assert(env.OECraftCost, 'Crafting.lua did not define OECraftCost')

local function makePanel()
    local panel = {
        OutputText = {},
        isRecraft = false,
        CreateFontString = function(self)
            local line = {
                text = '',
                SetText = function(l, t) l.text = t end,
                SetWidth = function() end,
                SetJustifyH = function() end,
                SetJustifyV = function() end,
                ClearAllPoints = function() end,
                SetPoint = function() end,
                Show = function(l) l.shown = true end,
                Hide = function(l) l.shown = false end,
            }
            self.OECraftCostLine = line
            return line
        end,
    }
    return panel
end

-- Colour codes made readable: emit their name, drop the reset.
local function readable(text)
    text = text:gsub('|cffe6cc80', '<label>')
    text = text:gsub('|cff21ff21', '<profit>')
    text = text:gsub('|cffff2121', '<loss>')
    text = text:gsub('|cff999999', '<dim>')
    text = text:gsub('|r', '</>')
    return text
end

for _, r in ipairs(recipes) do
    local panel = makePanel()
    installed(panel, { recipeID = r.spell })
    local craft = OECraftCost(r.spell, {}) or {}
    print(string.format('spell %d (out %d) - %s', r.spell, r.out, r.note))
    print(string.format('  raw: cost %d, priced %d/%d, value %s, profit %s, roi %s',
        craft.cost or 0, craft.priced or 0, craft.total or 0,
        tostring(craft.value), tostring(craft.profit),
        craft.roi and string.format('%.0f', craft.roi) or 'nil'))
    if not (panel.OECraftCostLine and panel.OECraftCostLine.shown) then
        print('  (nothing shown)')
    else
        for text in panel.OECraftCostLine.text:gmatch('[^\n]+') do
            print('  ' .. readable(text))
        end
    end
    print('')
end

-- A recipe the client has no schematic for must draw nothing.
local unknown = makePanel()
installed(unknown, { recipeID = 99999999 })
print('unknown recipe drawn: ' .. tostring(unknown.OECraftCostLine ~= nil))
