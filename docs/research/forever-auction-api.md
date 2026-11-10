# Forever auction data: Blizzard's API vs Undermine Exchange

Research for Oribos Exchange, 2026-11-10. Probe run read-only with a normal Battle.net
client-credentials token.

## What NaowhForever does

NaowhForever did not replace its feed with WoWAPI. It has two independent sources:

1. **A release feed built from Blizzard's web Game Data API.** `Tools/build/auction_feed.py`
   fetches every Forever auction house at release and writes `NaowhForever_AuctionData/Prices.lua`,
   a load-on-demand addon. Added in PR #955, after Blizzard started serving Forever auctions on
   2026-11-06. A price release is tagged every evening at 20:30 UTC.
2. **An in-game scan.** `NaowhForever_QoL/Loot/AuctionPrices.lua` calls
   `C_AuctionHouse.ReplicateItems()`, reads `GetReplicateItemInfo(i)` in chunks of 1,000, and stores
   the lowest buyout and listing count per item, per realm and faction. Blizzard allows one full
   scan every 15 minutes; the scan needs an open auction house. It also hooks `ReplicateItems` to
   capture scans started by Auctionator or TSM. A player's own scan wins when it is newer than the
   release feed.

The scan cannot replace the feed: it sees only the player's house, only at an auctioneer, at most
every 15 minutes. The feed is what gives prices before the first scan and for every other house.

## Blizzard's Forever auction API

Normal OAuth client credentials, no special access:

```
POST https://oauth.battle.net/token          grant_type=client_credentials
GET  https://{us,eu,kr,tw}.api.blizzard.com/data/wow/ruleset/index?namespace=dynamic-forever-{region}
GET  .../data/wow/ruleset/{rulesetId}/auctions/index
GET  .../data/wow/ruleset/{rulesetId}/auctions/{houseId}
GET  .../data/wow/ruleset/{rulesetId}/auctions/{houseId}/commodities
```

Rulesets: 1 PvP, 2 Normal, 3 Roleplay, 15 Roleplay PvP (3 and 15 absent in KR/TW). The house index
is identical under every ruleset; fetching house 114 under ruleset 1 and 2 returned the same count
and checksum. The ruleset path is only an entry point.

Every region lists the same fifteen house IDs, 110-125 without 122. 112, 115 and 118 are empty.
The twelve active houses map exactly onto the twelve houses our data files already carry.

## Mapping (confirmed on US, EU and KR)

| Blizzard house | Our slot | Label |
| --- | --- | --- |
| 110 | 1 | PvP Alliance |
| 113 | 2 | PvP Horde |
| 116 | 3 | PvP Neutral |
| 111 | 4 | Normal Alliance |
| 114 | 5 | Normal Horde |
| 117 | 6 | Normal Neutral |
| 119 | 7 | Roleplay Alliance |
| 120 | 8 | Roleplay Horde |
| 121 | 9 | Roleplay Neutral |
| 123 | 10 | Roleplay PvP Alliance |
| 124 | 11 | Roleplay PvP Horde |
| 125 | 12 | Roleplay PvP Neutral |

112, 115 and 118 are empty and have no slot.

The match came from comparing the API's lowest price for the house's 300 most-listed items against
each of our houses. The correct slot won every time; at a 3% tolerance it matched 140-260 of 300
items. US house 110 matched slot 1; EU house 110 also matched slot 1; KR confirmed the PvP/Normal
subset (110, 111, 113, 114, 116, 117).

Because the IDs are fixed, a Blizzard-based builder can keep the exact realm-to-house mapping by
hardcoding this table. Naowh's scan-matching and faction-median fallback are not required.

## Measured cost

- US: 15 houses, 93 MB and 5.6 s for all listings plus commodities (30 requests).
- Biggest house: 142,409 listings, 73,500 commodities, 3,507 unique items, 19 MB.
- The other regions are smaller; KR/TW only have the six PvP/Normal houses active.
- Freshness: `Last-Modified` was 04:13 UTC when read at 04:41, while our current data was compiled
  at 02:13. A 3-hour build would always take fresh data.
- Fields: `buyout`, `quantity`, `unit_price`, `time_left`. Bid-only listings have no buyout and are
  skipped (30 of 142,409 in house 114). `bonus_lists` or `context` appear on about 36% of listings,
  but our Forever data currently has zero level/suffix records, so pricing the base item ID loses
  nothing today.

## What the swap would lose

- `market` — the 4-day median on the auction house, currently provided by Undermine.
- `days` — days since the item was last seen, currently provided by Undermine.

`region` can be recomputed as the median across the twelve houses. Everything else maps directly.
Undermine also has much smaller downloads and no credentials; Blizzard's route costs roughly 250 MB
per full four-region build and needs a client ID and secret in CI.

## Verdict

The feed swap is viable, and the fixed house-ID mapping makes it cleaner than Naowh's version: no
scan is needed to know which house a player is in. The only feature decision is the 4-day median and
last-seen line. Either rebuild a small rolling history from our own snapshots, or ship current
lowest plus region median first and add history later.

The live scan is a separate, optional freshness layer. It works in the Forever client
(`C_AuctionHouse.ReplicateItems` and `GetReplicateItemInfo` are present), but it should not be sold
as a replacement for the feed.

## Implementation

The feed swap is implemented in `tools/forever-data/build.js`; Blizzard is the default source, and
`--source undermine` keeps the old download path as a fallback. The fixed house map and the rolling
history are documented in `tools/forever-data/README.md`. The refresh workflow reads
`BLIZZARD_CLIENT_ID` and `BLIZZARD_CLIENT_SECRET` from repository secrets and keeps
`history.json` in an `actions/cache` entry.

