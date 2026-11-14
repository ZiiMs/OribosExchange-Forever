-- Runs OribosExchange/Crafting.lua against the committed price data, with a
-- stand-in for the parts of the client it touches. The recipe list is the
-- client's own SpellReagents/SpellEffect tables, so the schematics match what
-- GetRecipeSchematic returns in game.
--
-- Usage: luajit tools/crafting/check-crafting.lua <recipes.json> [data.us.lua]

local recipesFile = assert(arg[1], 'usage: luajit check-crafting.lua <recipes.json> [data.us.lua]')
local dataFile = arg[2] or 'OribosExchange/dynamic/data.us.lua'

-- ---------------------------------------------------------------------------
-- Read the generated price data by running it the way the addon does
-- ---------------------------------------------------------------------------
local prices

local function loadPrices(file)
    local addonTable = { dataLoads = {} }
    -- The generated file calls crop() for each item; keep the raw blobs.
    local blobs = {}
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
    local chunk = assert(loadfile(file))
    setfenv(chunk, env)
    chunk('OribosExchange', addonTable)
    for _, load in ipairs(addonTable.dataLoads) do
        -- 33391 is the US Normal Alliance house: the busiest one.
        load('33391', 'Alliance', 'Test')
    end
    return addonTable
end

local addonTable = loadPrices(dataFile)
assert(addonTable.marketData, 'no market data loaded')

-- The addon's own reader. marketData holds blobs already cropped to the
-- selected house: a header (size byte + region price) then one record
-- (days byte + house price), so no realm index is applied here.
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
        days = blob:byte(recordOffset),
        market = char2dec(blob:sub(recordOffset + 1, recordOffset + priceSize)),
    }
end

-- ---------------------------------------------------------------------------
-- A JSON reader good enough for the recipe list (numbers, arrays, objects)
-- ---------------------------------------------------------------------------
local function jsonDecode(text)
    local pos = 1
    local function skip()
        pos = text:find('[^ \t\r\n]', pos) or #text + 1
    end
    local parseValue
    local function parseString()
        local out, i = {}, pos + 1
        while true do
            local c = text:sub(i, i)
            if c == '"' then pos = i + 1 break end
            if c == '\\' then
                local n = text:sub(i + 1, i + 1)
                local map = { n = '\n', t = '\t', r = '\r', b = '\b', f = '\f' }
                out[#out + 1] = map[n] or n
                i = i + 2
            else
                out[#out + 1] = c
                i = i + 1
            end
        end
        return table.concat(out)
    end
    local function parseNumber()
        local s, e = text:find('^-?%d+%.?%d*[eE]?[-+]?%d*', pos)
        local n = tonumber(text:sub(s, e))
        pos = e + 1
        return n
    end
    parseValue = function()
        skip()
        local c = text:sub(pos, pos)
        if c == '{' then
            local obj = {}
            pos = pos + 1
            skip()
            if text:sub(pos, pos) == '}' then pos = pos + 1 return obj end
            while true do
                skip()
                local key = parseString()
                skip()
                pos = pos + 1 -- colon
                obj[key] = parseValue()
                skip()
                local sep = text:sub(pos, pos)
                pos = pos + 1
                if sep == '}' then return obj end
            end
        elseif c == '[' then
            local arr = {}
            pos = pos + 1
            skip()
            if text:sub(pos, pos) == ']' then pos = pos + 1 return arr end
            while true do
                arr[#arr + 1] = parseValue()
                skip()
                local sep = text:sub(pos, pos)
                pos = pos + 1
                if sep == ']' then return arr end
            end
        elseif c == '"' then
            return parseString()
        elseif text:sub(pos, pos + 3) == 'true' then
            pos = pos + 4
            return true
        elseif text:sub(pos, pos + 4) == 'false' then
            pos = pos + 5
            return false
        elseif text:sub(pos, pos + 3) == 'null' then
            pos = pos + 4
            return nil
        else
            return parseNumber()
        end
    end
    return parseValue()
end

local recipes = jsonDecode(assert(io.open(recipesFile, 'rb')):read('*a'))

-- ---------------------------------------------------------------------------
-- The client stand-in
-- ---------------------------------------------------------------------------
local schema = {}
for _, r in ipairs(recipes) do
    local slots = {}
    for _, part in ipairs(r.parts) do
        slots[#slots + 1] = {
            reagentType = 1, -- Enum.CraftingReagentType.Basic
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

local lines = {}
local tooltip = {
    AddDoubleLine = function(self, left, right) lines[#lines + 1] = { left, right } end,
}

local env = setmetatable({
    addonTable = addonTable,
    Enum = { CraftingReagentType = { Modifying = 0, Basic = 1, Finishing = 2, Automatic = 3 } },
    C_TradeSkillUI = {
        GetRecipeSchematic = function(recipeID)
            return schema[recipeID]
        end,
    },
    CreateFrame = function()
        return { RegisterEvent = function() end, SetScript = function() end }
    end,
    hooksecurefunc = function() end,
    GameTooltip = { SetRecipeResultItem = function() end, SetRecipeResultItemForOrder = function() end },
    GameTooltip_AddBlankLineToTooltip = function() end,
    wipe = function(t) for k in pairs(t) do t[k] = nil end end,
    time = os.time,
    string = string,
    math = math,
    table = table,
    pairs = pairs,
    ipairs = ipairs,
    type = type,
    pcall = pcall,
    tonumber = tonumber,
    tostring = tostring,
    print = print,
}, { __index = _G })

addonTable.localization = setmetatable({}, { __index = function(_, k) return k end })
addonTable.coins = function(money) return tostring(money) end
addonTable.getTooltipsSettings = function() return {} end
addonTable.marketData[0] = true

-- OEMarketInfo: the house median, else the region median. The generated data
-- keys items by their decimal string, as the addon's own lookup does.
env.OEMarketInfo = function(itemID, out)
    local blob = addonTable.marketData[tostring(itemID)]
    if not blob then return out end
    local got = decode(blob)
    out.input = itemID
    if got.market > 0 then out.market = got.market end
    if got.region > 0 then out.region = got.region end
    return out
end

local chunk = assert(loadfile('OribosExchange/Crafting.lua'))
setfenv(chunk, env)
chunk('OribosExchange', addonTable)

-- OECraftCost is written into the file's global environment.
local OECraftCost = assert(env.OECraftCost, 'Crafting.lua did not define OECraftCost')

-- ---------------------------------------------------------------------------
-- Checks
-- ---------------------------------------------------------------------------
local failures = 0
local function fail(msg)
    io.stderr:write('FAIL ' .. msg .. '\n')
    failures = failures + 1
end

local function eachPrice(itemID)
    local blob = addonTable.marketData[tostring(itemID)]
    if not blob then return nil end
    local got = decode(blob)
    if got.market > 0 then return got.market end
    if got.region > 0 then return got.region end
end

local costed, complete, withValue, profitable = 0, 0, 0, 0
local best = {}

for _, r in ipairs(recipes) do
    local out = {}
    local got = OECraftCost(r.spell, out)
    if not got then
        fail('recipe ' .. r.spell .. ': no result')
    else
        if got.total ~= #r.parts then fail('recipe ' .. r.spell .. ': total') end
        if got.output ~= r.out then fail('recipe ' .. r.spell .. ': output') end
        if got.made ~= r.count then fail('recipe ' .. r.spell .. ': made') end

        if got.priced > 0 then
            costed = costed + 1

            local expectCost, expectPriced = 0, 0
            for _, part in ipairs(r.parts) do
                local each = eachPrice(part[1])
                if each then
                    expectCost = expectCost + each * part[2]
                    expectPriced = expectPriced + 1
                end
            end
            if got.cost ~= expectCost then
                fail(string.format('recipe %d: cost %d != %d', r.spell, got.cost, expectCost))
            end
            if got.priced ~= expectPriced then
                fail(string.format('recipe %d: priced %d != %d', r.spell, got.priced, expectPriced))
            end

            if got.priced == got.total then complete = complete + 1 end

            if got.value then
                withValue = withValue + 1
                local each = eachPrice(r.out)
                local expectValue = math.floor(each * r.count * 0.95)
                if got.value ~= expectValue then
                    fail(string.format('recipe %d: value %d != %d', r.spell, got.value, expectValue))
                end
                if got.profit ~= got.value - got.cost then
                    fail('recipe ' .. r.spell .. ': profit')
                end
                if got.cost > 0 then
                    local roi = got.profit / got.cost * 100
                    if math.abs(got.roi - roi) > 1e-9 then fail('recipe ' .. r.spell .. ': roi') end
                elseif got.roi ~= nil then
                    fail('recipe ' .. r.spell .. ': roi without cost')
                end
                if got.profit > 0 then
                    profitable = profitable + 1
                    best[#best + 1] = { spell = r.spell, out = r.out, cost = got.cost,
                        value = got.value, profit = got.profit, roi = got.roi }
                end
            end
        end
    end
end

-- A recipe the client has no schematic for: the profession is not open.
if OECraftCost(99999999, {}) ~= false then fail('unknown recipe should return false') end
if OECraftCost('nope', {}) ~= false then fail('non-numeric recipe should return false') end
-- A cost of zero must not divide by zero for roi.
do
    local craft = OECraftCost(recipes[1].spell, {})
    if craft and craft.cost == 0 and craft.roi ~= nil then fail('roi on a free craft') end
end

table.sort(best, function(a, b) return a.profit > b.profit end)
print(string.format('%d recipes, %d costed, %d fully priced, %d with an output price, %d profitable',
    #recipes, costed, complete, withValue, profitable))
print('')
print('Best crafts on this house:')
for i = 1, math.min(#best, 8) do
    local p = best[i]
    print(string.format('  spell %-8d out %-7d cost %9d value %9d profit %9d roi %3.0f%%',
        p.spell, p.out, p.cost, p.value, p.profit, p.roi or 0))
end

if failures > 0 then
    io.stderr:write(string.format('\n%d failure(s)\n', failures))
    os.exit(1)
end
print('\nOK')
