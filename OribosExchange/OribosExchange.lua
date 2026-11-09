--[[

Oribos Exchange addon, v 1.3
From Erorus, the author of Undermine Exchange https://undermine.exchange/

You should be able to query this DB from other addons:

    o={}
    OEMarketInfo(52719,o)
    print(o['market'])

Prints the market price of Greater Celestial Essence.
The item can be identified by anything GetItemInfo takes (itemid, itemstring, itemlink) or a battlepet itemstring/itemlink.

Prices are returned in copper, but accurate to the last *silver* (with coppers always 0).

    o['input']          -> the item/battlepet parameter you just passed in, verbatim

    o['itemid']         -> the ID of the item you just passed in

    o['species']        -> the species of the battlepet you just passed in
    o['breed']          -> the numeric breed ID of the battlepet
    o['quality']        -> the numeric quality/rarity of the battlepet

    o['age']            -> number of seconds since data was compiled

    o['region']         -> median market price across all realms in this region
    o['market']         -> median market price of the item on this AH over the past 4 days.

    o['days']           -> number of days since item was last seen on the auction house, when data was compiled. valid values 0 - 250.
     o['days'] = 251 means item was seen on this AH, but over 250 days ago
     o['days'] = 252 means the item is sold by vendors in unlimited quantities


You can also query and set whether the additional tooltip lines appear from this addon.
This is useful for other addons (Auctioneer, TSM, etc) that have their own fancy tooltips to disable OE tooltips and use OE simply as a data source.

    OETooltip()        -> returns a boolean whether OE tooltips are enabled
    OETooltip(true)    -> enables OE tooltips
    OETooltip(false)   -> disables OE tooltips

]]

local addonName, addonTable = ...
local L = addonTable.localization
local accentColor = '|cff33ff99'
local prettyName = accentColor .. L["Oribos Exchange"] .. '|r'

local floor = math.floor
local tinsert, tonumber = tinsert, tonumber
local strLen, strByte, strSub = string.len, string.byte, string.sub
local GetItemInfoInstant = C_Item.GetItemInfoInstant
local GetDetailedItemLevelInfo = C_Item.GetDetailedItemLevelInfo
local issecretvalue = rawget(_G, "issecretvalue")
local PET_CAGE = 82800
local tooltipsSettings = {}

local function coins(money)
    money = floor(tonumber(money) or 0)

    if not tooltipsSettings['text-coins'] then
        if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
            return C_CurrencyInfo.GetCoinTextureString(money, 12)
        end
        if GetMoneyString then
            return GetMoneyString(money, true)
        end
    end

    local GOLD="ffd100"
    local SILVER="e6e6e6"
    local COPPER="c8602c"

    local GSC_3 = "|cff%s%d|cff999999.|cff%s%02d|cff999999.|cff%s%02d|r"
    local GSC_2 = "|cff%s%d|cff999999.|cff%s%02d|r"

    local g = floor(money / 10000)
    local s = floor(money % 10000 / 100)
    local c = money % 100

    if (c > 0) then
        return GSC_3:format(GOLD, g, SILVER, s, COPPER, c)
    else
        return GSC_2:format(GOLD, g, SILVER, s)
    end
end

local function char2dec(s)
    local n, l = 0, strLen(s)
    for i=1,l,1 do
        n = n * 256 + strByte(s,i)
    end
    return n
end

-- Market price from an already-cropped data record (header + selected house).
local function blobMarket(dta)
    local priceSize = strByte(dta, 1)
    local offset = 3 + priceSize
    return char2dec(strSub(dta, offset, offset + priceSize - 1))
end

local function round(num)
    return floor(num + 0.5)
end

local function roundToOdd(value)
    local floored = floor(value)
    if floor((value - floored) * 1000000) == 500000 then
        if floored % 2 == 0 then
            return floored + 1
        end

        return floored
    end

    return floor(value + 0.5)
end

local breedPoints = {
    [3] = {0.5,0.5,0.5,["name"]="B/B"},
    [4] = {0,2,0,["name"]="P/P"},
    [5] = {0,0,2,["name"]="S/S"},
    [6] = {2,0,0,["name"]="H/H"},
    [7] = {0.9,0.9,0,["name"]="H/P"},
    [8] = {0,0.9,0.9,["name"]="P/S"},
    [9] = {0.9,0,0.9,["name"]="H/S"},
    [10] = {0.4,0.9,0.4,["name"]="P/B"},
    [11] = {0.4,0.4,0.9,["name"]="S/B"},
    [12] = {0.9,0.4,0.4,["name"]="H/B"},
}
local breedCandidates = {}
local function getBreedFromPetLink(link)
    local petString = string.match(link, "battlepet[%-?%d:]+")
    local _, speciesID, level, quality, health, power, speed = strsplit(":", petString)

    if not (speciesID and level and quality and health and power and speed) then
        return
    end

    speciesID = tonumber(speciesID,10)
    level = tonumber(level,10)
    quality = tonumber(quality,10)
    health = tonumber(health,10)
    power = tonumber(power,10)
    speed = tonumber(speed,10)

    local speciesStats = addonTable.speciesStats[speciesID] or addonTable.speciesStats[0]
    local qualityFactor = level * (1 + quality / 10)
    wipe(breedCandidates)

    for breed, points in pairs(breedPoints) do
        local breedHealth = roundToOdd((speciesStats[1] + points[1]) * 5 * qualityFactor + 100)
        local breedPower = roundToOdd((speciesStats[2] + points[2]) * qualityFactor)
        local breedSpeed = roundToOdd((speciesStats[3] + points[3]) * qualityFactor)

        if (breedHealth == health) and (breedPower == power) and (breedSpeed == speed) then
            tinsert(breedCandidates, breed)
        end
    end

    local breed
    if #breedCandidates == 1 then
        breed = breedCandidates[1]
    elseif #breedCandidates > 1 then
        for i=1,#breedCandidates,1 do
            local dataKey = PET_CAGE .. '-' .. speciesID .. '-' .. breedCandidates[i]
            if addonTable.marketData[dataKey] then
                breed = breedCandidates[i]
            end
        end
    end

    return breed, speciesID, level, quality, health, power, speed
end

local marketInfoCache, marketInfoCacheKeys, marketInfoCacheMaxDepth = {}, {}, 16

local function InfoCacheKeyComparitor(x,y)
    return (marketInfoCache[x] and marketInfoCache[x]['__queried'] or 0) <
           (marketInfoCache[y] and marketInfoCache[y]['__queried'] or 0)
end

-- The auction house UI builds its own fake tooltip via the base item plus a custom item level and suffix. This mess
-- helps us pull out the item key they use to show that tooltip so we know the correct item level.
local browseItemKey
local function onBrowseLineEnter(line, rowData)
    if rowData and rowData.itemKey then
        browseItemKey = rowData.itemKey
    end
end
local function onBrowseLineLeave()
    browseItemKey = nil
end
local function checkAuctionHouseLineHandlers()
    if not AuctionHouseFrame then return end

    local resultsFrame = AuctionHouseFrame.BrowseResultsFrame
    local itemList = resultsFrame and resultsFrame.ItemList
    if not itemList then return end

    local oldEnter = itemList.lineOnEnterCallback;
    local oldLeave = itemList.lineOnLeaveCallback;
    if not (oldEnter and oldLeave) then return end

    itemList:SetLineOnEnterCallback(function (...)
        onBrowseLineEnter(...)
        oldEnter(...)
    end)
    itemList:SetLineOnLeaveCallback(function (...)
        onBrowseLineLeave(...)
        oldLeave(...)
    end)

    return true
end
local function getActiveItemKey()
    if browseItemKey then return browseItemKey end
    if not AuctionHouseFrame then return end
    local buyFrame = AuctionHouseFrame.ItemBuyFrame
    local itemDisplay = buyFrame and buyFrame.ItemDisplay
    if itemDisplay and itemDisplay.ItemButton and GameTooltip:GetOwner() == itemDisplay.ItemButton then
        return itemDisplay.itemKey
    end
end

--[[
    pass a table as the second argument to wipe and reuse that table
    otherwise a new table will be created and returned
]]
function OEMarketInfo(item,...)
    if item == 0 then
        if addonTable.marketData then
            return true
        else
            return false
        end
    end

    local numargs = select('#', ...)
    local tr

    if (numargs > 0) and (type(select(1,...)) == 'table') then
        tr = select(1,...)
        wipe(tr)
    end

    if not addonTable.marketData then return tr end
    local cacheKey = item
    local activeItemKey = getActiveItemKey()
    if activeItemKey then
        cacheKey = cacheKey .. '~~~' .. activeItemKey.itemID .. '-' .. activeItemKey.itemLevel .. '-' .. activeItemKey.itemSuffix
    end

    if marketInfoCache[cacheKey] then
        marketInfoCache[cacheKey]['__queried'] = GetTime()
        if not marketInfoCache[cacheKey]['input'] then return tr end
        if not tr then tr = {} end
        for k,v in pairs(marketInfoCache[cacheKey]) do
            tr[k] = v
        end
        tr['__queried'] = nil
        return tr
    end

    if #marketInfoCacheKeys >= marketInfoCacheMaxDepth then
        -- reuse oldest cache table
        sort(marketInfoCacheKeys, InfoCacheKeyComparitor)
        marketInfoCache[cacheKey] = marketInfoCache[marketInfoCacheKeys[1]] or {}
        wipe(marketInfoCache[cacheKey])

        while #marketInfoCacheKeys >= marketInfoCacheMaxDepth do
            marketInfoCache[marketInfoCacheKeys[1]] = nil
            table.remove(marketInfoCacheKeys, 1)
        end
    else
        -- add new table to cache
        marketInfoCache[cacheKey] = {}
    end
    table.insert(marketInfoCacheKeys, cacheKey)
    marketInfoCache[cacheKey]['__queried'] = GetTime()

    local _, link, dataKey
    local iid, breed, species, quality

    if (strfind(item, 'battlepet:')) then
        breed, species, _, quality = getBreedFromPetLink(item)
        dataKey = PET_CAGE .. '-' .. (species or 0) .. '-' .. (breed or 0)
    else
        local itemId, _, _, _, _, itemClass = GetItemInfoInstant(item)
        if not itemId then return tr end

        iid = itemId
        dataKey = tostring(iid)

        if (itemClass == 2) or (itemClass == 4) then
            local effectiveLevel
            local nameId

            local activeItemKey = getActiveItemKey()
            if activeItemKey and activeItemKey.itemID == itemId then
                if activeItemKey.itemLevel > 0 then
                    effectiveLevel = activeItemKey.itemLevel
                    if activeItemKey.itemSuffix > 0 then
                        nameId = activeItemKey.itemSuffix
                    end
                end
            end

            effectiveLevel = effectiveLevel or (GetDetailedItemLevelInfo and GetDetailedItemLevelInfo(item))
            -- effectiveLevel may be nil when GetItemInfo didn't have the item readily available.
            if effectiveLevel then
                nameId = nameId or addonTable.getNameId(item)

                local testKey
                if nameId then
                    testKey = dataKey .. '-' .. effectiveLevel .. '-' .. nameId
                else
                    testKey = dataKey .. '-' .. effectiveLevel
                end
                if addonTable.marketData[testKey] then
                    -- On Forever an item-level entry can exist only because
                    -- another ruleset/faction house has that level. If it has
                    -- no price for the selected house, keep the base item
                    -- price instead of hiding the auction-house line.
                    local testData = addonTable.marketData[testKey]
                    if not addonTable.isForever or not addonTable.marketData[dataKey] or blobMarket(testData) > 0 then
                        dataKey = testKey
                    end
                end
            end
        end
    end

    local dta = addonTable.marketData[dataKey]
    if not dta then return tr end

    if not tr then tr = {} end

    tr['input'] = item
    if (iid) then
        tr['itemid'] = iid
    end
    if (species) then
        tr['species'] = species
        tr['breed'] = breed
        tr['quality'] = quality
    end

    if addonTable.dataAge then
        tr['age'] = time() - addonTable.dataAge
    end

    local priceSize = strByte(dta, 1)
    local offset = 2
    local priceScale = addonTable.priceScale or 100

    tr['region'] = round(char2dec(strSub(dta, offset, offset+priceSize-1))) * priceScale
    if tr['region'] == 0 then tr['region'] = nil end
    offset = offset + priceSize

    tr['days'] = strByte(dta, offset, offset)
    offset = offset + 1

    tr['market'] = round(char2dec(strSub(dta, offset, offset+priceSize-1))) * priceScale
    -- offset = offset + priceSize

    for k,v in pairs(tr) do
        marketInfoCache[cacheKey][k] = v
    end

    return tr
end

--[[
    enable/disable/query whether the OE tooltip additions are enabled
]]
local tooltipsEnabled = true
function OETooltip(...)
    if select('#', ...) >= 1 then
        tooltipsEnabled = not not select(1,...) --coerce into boolean

        local line = strmatch(debugstack(2, 1, 0), "[Aa][Dd][Dd][Oo][Nn][Ss]\\([^\\]+)")
        if line and line ~= addonName then
            local callingName, callingTitle = C_AddOns.GetAddOnInfo(line)
            if callingName then
                callingName = callingTitle or callingName
                local status = tooltipsEnabled and L["enabled"] or L["disabled"]
                print(prettyName .. " - " .. L["Tooltip prices %s by %s"]:format(status, callingName))
            end
        end
    end
    return tooltipsEnabled
end

local qualityRGB = {
    [0] = {0.616,0.616,0.616},
    [1] = {1,1,1},
    [2] = {0.118,1,0},
    [3] = {0,0.439,0.867},
    [4] = {0.639,0.208,0.933},
    [5] = {1,0.502,0},
    [6] = {0.898,0.8,0.502},
    [7] = {0.898,0.8,0.502},
    [8] = {0,0.8,1},
    [9] = {0.443,0.835,1},
}

local LibExtraTip = LibStub("LibExtraTip-1")
local regionName = L["Regional"]
local realmName = L["Realm"]

-- Stack size passed by LibExtraTip for the tooltip's item, as a positive whole number.
local function stackQuantity(quantity)
    if issecretvalue and issecretvalue(quantity) then return 1 end
    quantity = floor(tonumber(quantity) or 1)
    return quantity > 0 and quantity or 1
end

-- The label for a price line, marked with the stack size when its value is a stack total.
local function priceLabel(label, quantity)
    if quantity > 1 then
        return label .. accentColor .. ' x' .. quantity .. '|r'
    end
    return label
end

local function buildExtraTip(tooltip, pricingData, quantity)
    local r,g,b = .9,.8,.5

    if pricingData['breed'] and breedPoints[pricingData['breed']] and qualityRGB[pricingData['quality']] then
        LibExtraTip:AddLine(tooltip,
            L["Breed %s - Species %s"]:format(breedPoints[pricingData['breed']]["name"], pricingData['species']),
            qualityRGB[pricingData['quality']][1],
            qualityRGB[pricingData['quality']][2],
            qualityRGB[pricingData['quality']][3],
            true)
    end

    LibExtraTip:AddLine(tooltip," ",r,g,b,true)

    if (pricingData['age'] > 3*24*60*60) and not tooltipsSettings['disable-age'] then
        LibExtraTip:AddLine(tooltip,L["As of %s ago:"]:format(SecondsToTime(pricingData['age'],pricingData['age']>60)),r,g,b,true)
    end

    -- Holding Shift prices the whole stack instead of a single item.
    local stack = IsShiftKeyDown() and stackQuantity(quantity) or 1

    if pricingData['market'] and pricingData['market'] > 0 and not tooltipsSettings['disable-market'] then
        LibExtraTip:AddDoubleLine(tooltip,priceLabel(realmName, stack),coins(pricingData['market'] * stack),r,g,b,nil,nil,nil,true)
    end

    if pricingData['region'] and not tooltipsSettings['disable-region'] then
        LibExtraTip:AddDoubleLine(tooltip,priceLabel(regionName, stack),coins(pricingData['region'] * stack),r,g,b,nil,nil,nil,true)
    end

    if not tooltipsSettings['disable-lastSeen'] then
        if pricingData['days'] == 252 then
            LibExtraTip:AddLine(tooltip,L["Sold by Vendors"],r,g,b,true)
        elseif pricingData['days'] > 250 then
            LibExtraTip:AddLine(tooltip,L["Last seen over 250 days ago"],r,g,b,true)
        elseif pricingData['days'] > 1 then
            LibExtraTip:AddLine(tooltip,L["Last seen %s ago"]:format(SecondsToTime(pricingData['days']*24*60*60)),r,g,b,true)
        end
    end
end

local function printHelp()
    local function getLineStatus(lineName)
        if tooltipsSettings['disable-' .. lineName] then
            return '(|cFFFF0000' .. L["OFF"] .. '|r)'
        else
            return '(|cFF00FF00' .. L["ON"] .. '|r)'
        end
    end

    local regionName = addonTable.region or L["Regional"]

    print(prettyName .. " - " .. L["Arguments for %s are:"]:format("|cFFFFFF78/oetooltip|r"))
    print("|cFFFFFF78on|r|||cFFFFFF78off|r - " .. L["Enable/disable tooltip modifications."])
    print("|cFFFFFF78reset|r - " .. L["Reset all preferences and enable all lines."])
    print("|cFFFFFF78coins|r - " .. L["Toggle displaying coin prices."])
    print("|cFFFFFF78quiet|r - " .. L["Disable all lines."])
    print("|cFFFFFF78age|r - " .. L["Toggle data age line."] .. " " .. getLineStatus('age'))
    print("|cFFFFFF78market|r - " .. L["Toggle realm price line."] .. " " .. getLineStatus('market'))
    print("|cFFFFFF78region|r - " .. L["Toggle %s median line."]:format(regionName) .. " " .. getLineStatus('region'))
    print("|cFFFFFF78lastseen|r - " .. L["Toggle 'Last seen' line."] .. " " .. getLineStatus('lastSeen'))
    print("|cFFFFFF78whatsnew|r - " .. L["Show the What's New panel."])
    print("|cFFFFFF78debug|r - " .. "Print data diagnostics. Use debug <item link> for one item.")
    print(prettyName .. " - " .. L["Hold Shift over a stack to show its total value."])
end

local dataResults = {}
local function onTooltipSetItem(tooltip, itemLink, quantity)
    if not addonTable.marketData then return end
    if not tooltipsEnabled then return end
    if not itemLink then return end

    OEMarketInfo(itemLink, dataResults)

    if not (dataResults['input'] and (dataResults['input'] == itemLink)) then
        return
    end

    buildExtraTip(tooltip, dataResults, quantity)
end

-- Pressing or releasing Shift changes a price line between one item and the whole stack.
-- Refresh the tooltip already on screen so it does not have to be re-hovered.
local stackWatcher = CreateFrame("Frame")
stackWatcher:RegisterEvent("MODIFIER_STATE_CHANGED")
stackWatcher:SetScript("OnEvent", function(_, _, key)
    if key ~= "LSHIFT" and key ~= "RSHIFT" then return end
    if not tooltipsEnabled or not addonTable.marketData then return end
    if not GameTooltip:IsShown() or not GameTooltip.RefreshData then return end

    local additional = LibExtraTip:GetTooltipAdditional(GameTooltip)
    if not additional or stackQuantity(additional.quantity) < 2 then return end

    GameTooltip:RefreshData()
end)

local eventframe = CreateFrame("FRAME",addonName.."Events")

local pendingWhatsNew = false

local function tryShowWhatsNew()
    if not pendingWhatsNew then return end
    if InCombatLockdown and InCombatLockdown() then return end

    pendingWhatsNew = false
    local whatsNew = addonTable.WhatsNew
    if whatsNew and whatsNew.Show then
        whatsNew.Show()
    end
end

local function queueWhatsNew()
    pendingWhatsNew = true
    if C_Timer and C_Timer.After then
        C_Timer.After(2, tryShowWhatsNew)
    else
        tryShowWhatsNew()
    end
end

local function printDataStatus()
    local whatsNew = addonTable.WhatsNew
    local line1, line2
    if whatsNew and whatsNew.DataSyncChatLines then
        line1, line2 = whatsNew.DataSyncChatLines()
    elseif addonTable.isForever and addonTable.dataAge then
        local age = time() - addonTable.dataAge
        if age < 0 then age = 0 end
        line1 = "WoW Forever: " .. tostring(addonTable.houseLabel) .. " prices (" .. SecondsToTime(age, true) .. " old)"
    end

    if line1 then print(prettyName .. " - " .. line1) end
    if line2 then print(prettyName .. " - " .. line2) end
end

local function onEvent(self,event,arg)
    if event == "PLAYER_ENTERING_WORLD" then
        eventframe:UnregisterEvent("PLAYER_ENTERING_WORLD")

        local realmId = GetRealmID()
        if not realmId then
            local guid = UnitGUID("player")
            if guid then
                realmId = tonumber(strmatch(guid, "^Player%-(%d+)"))
            end
        end
        if not realmId then
            realmId = "nil"
        end

        local currentRealmName = GetRealmName()
        local playerFaction = UnitFactionGroup("player")
        for i=1,#addonTable.dataLoads,1 do
            addonTable.dataLoads[i](realmId, playerFaction, currentRealmName)
            addonTable.dataLoads[i]=nil
        end
        wipe(addonTable.dataLoads)
        collectgarbage("collect") -- lots of strings made and trunc'ed in MarketData

        local loadedCount = 0
        if addonTable.marketData then
            for _ in pairs(addonTable.marketData) do loadedCount = loadedCount + 1 end
        end
        _G.OETooltipDebug = {
            build = select(1, GetBuildInfo()),
            buildNumber = select(2, GetBuildInfo()),
            toc = select(4, GetBuildInfo()),
            locale = GetLocale(),
            project = WOW_PROJECT_ID,
            realmId = realmId,
            realmName = currentRealmName,
            faction = playerFaction,
            region = addonTable.region,
            regionId = addonTable.regionId,
            house = addonTable.houseLabel,
            houseFaction = addonTable.houseFaction,
            houseRuleset = addonTable.houseRuleset,
            dataAge = addonTable.dataAge,
            dataAgeText = addonTable.dataAge and date("%Y-%m-%d %H:%M:%S", addonTable.dataAge) or nil,
            priceScale = addonTable.priceScale,
            isForever = addonTable.isForever,
            items = loadedCount,
            whatsNewRevision = addonTable.WhatsNew and addonTable.WhatsNew.revision,
            whatsNewSeen = addonTable.WhatsNew and addonTable.WhatsNew.SeenRevision and addonTable.WhatsNew.SeenRevision(),
            updated = date("%Y-%m-%d %H:%M:%S"),
        }

        if not addonTable.realmIndex then
            print(prettyName .. " - " .. L["Warning: could not find data for realm ID %s, no data loaded!"]:format(tostring(realmId)))
        elseif not addonTable.marketData or loadedCount == 0 then
            print(prettyName .. " - " .. L["Warning: no data loaded!"])
        else
            regionName = L["%s Region"]:format(addonTable.region)
            realmName = addonTable.houseLabel or currentRealmName
            local whatsNew = addonTable.WhatsNew
            if whatsNew and whatsNew.HasUnseen and whatsNew.HasUnseen() then
                queueWhatsNew()
            else
                printDataStatus()
            end
            if not tooltipsEnabled then
                print(prettyName .. " - " .. L["Tooltip prices disabled. Run %s to enable."]:format("|cFFFFFF78/oetooltip on|r"))
            end
            LibExtraTip:AddCallback({type = "item", callback = onTooltipSetItem})
            LibExtraTip:AddCallback({type = "battlepet", callback = onTooltipSetItem})
            LibExtraTip:RegisterTooltip(GameTooltip)
            LibExtraTip:RegisterTooltip(ItemRefTooltip)
            if BattlePetTooltip then
                LibExtraTip:RegisterTooltip(BattlePetTooltip)
            end
            if FloatingBattlePetTooltip then
                LibExtraTip:RegisterTooltip(FloatingBattlePetTooltip)
            end
        end
    elseif event == "ADDON_LOADED" and arg == addonName then
        tooltipsEnabled = not _G["OETooltipsHidden"]
        tooltipsSettings = _G["OETooltipsSettings"] or {}
        tooltipsSettings['coins'] = nil -- old setting; coin icons are the default now
    elseif event == "AUCTION_HOUSE_SHOW" then
        if checkAuctionHouseLineHandlers() then
            eventframe:UnregisterEvent("AUCTION_HOUSE_SHOW")
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        tryShowWhatsNew()
    elseif event == "PLAYER_LOGOUT" then
        _G["OETooltipsHidden"] = not tooltipsEnabled
        _G["OETooltipsSettings"] = tooltipsSettings
    end
end

eventframe:RegisterEvent("PLAYER_ENTERING_WORLD")
eventframe:RegisterEvent("ADDON_LOADED")
eventframe:RegisterEvent("AUCTION_HOUSE_SHOW")
eventframe:RegisterEvent("PLAYER_REGEN_ENABLED")
eventframe:RegisterEvent("PLAYER_LOGOUT")
eventframe:SetScript("OnEvent", onEvent)

SLASH_ORIBOSEXCHANGE1 = '/oetooltip'
function SlashCmdList.ORIBOSEXCHANGE(msg)
    local lineNames = {
        ['age'] = 'age',
        ['market'] = 'market',
        ['region'] = 'region',

        ['lastseen'] = 'lastSeen',
        ['last-seen'] = 'lastSeen',
    }

    local loweredMsg = string.lower(msg)
    local debugItem = string.match(msg, "^[Dd][Ee][Bb][Uu][Gg]%s+(.+)$")

    if loweredMsg == 'whatsnew' or loweredMsg == 'news' then
        if addonTable.WhatsNew and addonTable.WhatsNew.Show then
            addonTable.WhatsNew.Show()
        end
        return
    end

    if loweredMsg == 'debug' or debugItem then
        local md = addonTable.marketData
        local count = 0
        if md then for _ in pairs(md) do count = count + 1 end end
        local version, build, buildDate, toc = GetBuildInfo()
        print(prettyName .. " - debug")
        print(("  client %s build %s toc %s locale %s project %s"):format(tostring(version), tostring(build), tostring(toc), tostring(GetLocale()), tostring(WOW_PROJECT_ID)))
        print(("  realmID %s  realm %s  faction %s"):format(tostring(GetRealmID()), tostring(GetRealmName()), tostring(UnitFactionGroup("player"))))
        print(("  region %s (%s)  house %s  ruleset %s  faction %s"):format(tostring(addonTable.region), tostring(addonTable.regionId), tostring(addonTable.houseLabel), tostring(addonTable.houseRuleset), tostring(addonTable.houseFaction)))
        print(("  dataAge %s  priceScale %s  forever %s  items %d"):format(addonTable.dataAge and date("%Y-%m-%d %H:%M:%S", addonTable.dataAge) or "nil", tostring(addonTable.priceScale), tostring(addonTable.isForever), count))
        print(("  coins %s  coinAPI %s"):format(tooltipsSettings['text-coins'] and "text" or "icons", tostring(C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString ~= nil)))
        local whatsNewSeen = addonTable.WhatsNew and addonTable.WhatsNew.SeenRevision and addonTable.WhatsNew.SeenRevision()
        print(("  whatsNew rev %s seen %s"):format(tostring(addonTable.WhatsNew and addonTable.WhatsNew.revision), tostring(whatsNewSeen)))
        if md then
            local info = OEMarketInfo(2589, {})
            if info then
                print(("  sample 2589: market %s  region %s  days %s  age %s"):format(tostring(info['market']), tostring(info['region']), tostring(info['days']), tostring(info['age'])))
            end
        end
        if debugItem then
            local itemId = GetItemInfoInstant(debugItem)
            print(("  item %s  itemid %s"):format(debugItem, tostring(itemId)))
            if itemId then
                local baseKey = tostring(itemId)
                local keys = {}
                for key in pairs(md or {}) do
                    if key == baseKey or string.sub(key, 1, #baseKey + 1) == baseKey .. '-' then
                        keys[#keys + 1] = key
                    end
                end
                table.sort(keys)
                print(("  keys for %s: %s"):format(baseKey, table.concat(keys, ", ")))
                for _, key in ipairs(keys) do
                    local dta = md[key]
                    local size = strByte(dta, 1)
                    local region = char2dec(strSub(dta, 2, 1 + size))
                    local days = strByte(dta, 2 + size)
                    local market = blobMarket(dta)
                    print(("    %s: market=%s region=%s days=%s"):format(key, market, region, days))
                end
                local info = OEMarketInfo(debugItem, {})
                if info then
                    print(("  lookup: market=%s region=%s days=%s"):format(tostring(info['market']), tostring(info['region']), tostring(info['days'])))
                end
            end
        end
        return
    end

    if msg == 'reset' then
        wipe(tooltipsSettings)
        OETooltip(true)
        print(prettyName .. " - " .. L["Preferences reset to defaults."])

        return
    end
    if msg == 'quiet' then
        for input, lineName in pairs(lineNames) do
            local settingName = 'disable-' .. lineName
            tooltipsSettings[settingName] = true
        end
        print(prettyName .. " - " .. L["All lines disabled."])

        return
    end
    if lineNames[loweredMsg] then
        local lineName = lineNames[loweredMsg]
        local settingName = 'disable-' .. lineName
        if tooltipsSettings[settingName] then
            tooltipsSettings[settingName] = nil
            print(prettyName .. " - " .. L["%s line enabled."]:format("|cFFFFFF78" .. lineName .. "|r"))
        else
            tooltipsSettings[settingName] = true
            print(prettyName .. " - " .. L["%s line disabled."]:format("|cFFFFFF78" .. lineName .. "|r"))
        end

        return
    end
    if msg == 'coins' then
        if tooltipsSettings['text-coins'] then
            tooltipsSettings['text-coins'] = nil
            print(prettyName .. " - " .. L["Coin icons enabled."])
        else
            tooltipsSettings['text-coins'] = true
            print(prettyName .. " - " .. L["Coin text enabled."])
        end

        return
    end
    if msg == 'on' then
        OETooltip(true)
        print(prettyName .. " - " .. L["Tooltip additions enabled."])

        return
    end
    if msg == 'off' then
        OETooltip(false)
        print(prettyName .. " - " .. L["Tooltip additions disabled."])

        return
    end

    printHelp()
end

local origGetAuctionBuyout = GetAuctionBuyout
local getAuctionBuyoutTable = {}

function GetAuctionBuyout(item) -- Tekkub's API
    local result = OEMarketInfo(item, getAuctionBuyoutTable)
    if (result and result['input'] == item) then
        if (result['market']) then
            return result['market']
        else
            return result['region']
        end
    end

    if (origGetAuctionBuyout) then
        return origGetAuctionBuyout(item)
    end

    return nil
end
