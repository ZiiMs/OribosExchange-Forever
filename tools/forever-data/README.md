# WoW Forever price data

`build.js` downloads WoW Forever auction-house prices and writes the four data
files the addon loads:

| File | Region | Auction houses |
| --- | --- | --- |
| `OribosExchange/dynamic/data.us.lua` | US (`usf`) | 12 (PvP / Normal / Roleplay / Roleplay PvP x Alliance / Horde / Neutral) |
| `OribosExchange/dynamic/data.eu.lua` | EU (`euf`) | 12 |
| `OribosExchange/dynamic/data.tw.lua` | TW (`twf`) | 6 |
| `OribosExchange/dynamic/data.kr.lua` | KR (`krf`) | 6 |

By default the source is Blizzard's Forever auction API: the same live data the
game serves, under the `dynamic-forever-{region}` namespace. `--source undermine`
keeps the old Undermine Exchange download path as a fallback.

## Blizzard credentials

The API needs a Battle.net client with client-credentials access. Create one at
<https://develop.battle.net/access/clients>, then set:

```
BLIZZARD_CLIENT_ID=...
BLIZZARD_CLIENT_SECRET=...
```

The GitHub workflow reads them from the repository secrets of the same names.
The token is only used for the read-only auction endpoints.

## Run it

From the repository root:

```
node tools/forever-data/build.js
```

Options:

```
--out <dir>        output directory (default: auto-detected)
--cache <dir>      cache and history directory (default: tools/forever-data/cache)
--regions <list>   comma list of usf,euf,twf,krf (default: all)
--source <name>    blizzard (default) or undermine
--history <file>   rolling history (default: <cache>/history.json)
--offline          use only the Undermine cache (undermine source only)
--min-age <min>    skip if the output files are newer than this many minutes
--quiet            less output
```

The Blizzard source fetches every active house's listings and commodities,
takes the lowest buyout per item, and writes the same blob format the addon
already reads. The 15 house IDs are global and 112/115/118 are empty, so the 12
active houses map onto our slots without a scan:

| Blizzard house | Slot | Ruleset / faction |
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

The realm ID to house mapping (`houseGuids`) is preserved from the previous
data, so a player still selects their exact house by `GetRealmID()`.

## History

Blizzard returns current listings, not history. `history.json` keeps, for each
region, house and item, the last four daily lows and the day it was last seen.
From that the builder writes:

- `market`: the median of the available daily lows (the 4-day median);
- `days`: days since the item was last seen, 0-250 or 251 for older;
- `region`: the median across the region's houses.

The first run has one day of history, so every price equals that day's low and
every seen item is day 0. The file lives in the cache by default and is
gitignored. The workflow keeps it in an `actions/cache` entry named
`auction-history-*`; do not commit it.

Vendor-sold items (`days = 252` in the old Undermine data) are not detected by
Blizzard's feed. The last-seen line is our own history, so it is only as old as
the cache.

## Automatic refresh

The [Refresh Forever data](../../.github/workflows/refresh-data.yml) workflow
is dispatched by the [Railway cron dispatcher](../railway-dispatch/README.md)
every hour at :37 UTC (`37 * * * *`), and can be started by hand. GitHub's own
schedule trigger is deliberately disabled: it delivered runs 16 minutes to
2.6 hours late, after the Railway run for the same slot, so it duplicated work
instead of acting as a fallback. Every run downloads all regions; no
source-data timestamp can suppress the build. Concurrent runs queue instead of
cancelling an active publish. When prices change it:

1. commits `OribosExchange/dynamic/data.*.lua`;
2. bumps the addon version in `OribosExchange/OribosExchange.toc` to
   `1.3.20261106-forever2.<UTC timestamp>`;
3. builds `OribosExchange-<version>.zip`;
4. publishes a new versioned GitHub release marked latest.

The version bump is deliberate: addon managers (WowUp, etc.) detect updates by
version, so replacing a zip on an unchanged tag would not trigger an update.

Users install the latest release, or `git pull` if they cloned the repo.

Railway cron timing is approximate: it can drift by a few minutes and skips a
slot if the previous dispatcher process is still running. GitHub is no longer a
secondary timer, so an outage there leaves Railway as the only scheduler. No new
release is expected when the downloaded data is unchanged.

Verify the configuration and automatic delivery separately:

```
node --test tools/forever-data/*.test.js
node tools/forever-data/check-refresh.js
node tools/forever-data/check-refresh.js --after 2026-11-07T20:30:00Z
```

The read-only health check requires `gh` and — by default — fails unless the
latest Railway-labelled dispatch completed successfully within 75 minutes and
actually ran the data build. `--source github` checks the retired GitHub
schedule instead. `--after` requires a new run after a deployment. Manual
dispatches never satisfy the Railway check. Each workflow run also writes a
summary showing the trigger, completion time, change/release status and all four
source timestamps.

For a local Windows refresh, `refresh.cmd` runs the builder and appends to
`refresh.log`. Schedule it with Task Scheduler (or put a shortcut in the
Startup folder) if you prefer; it is not required for the repository data.

## How the data maps to the addon

* The addon asks for the current realm (`GetRealmID()`), the player's faction
  (`UnitFactionGroup("player")`) and the realm name (`GetRealmName()`).
* `houseGuids` maps both the realm ID (e.g. `33134`) and its base ID (e.g.
  `366`) to the auction house. If the ID is not known (for example a beta/test
  realm), the ruleset is read from the realm name (`PvP`, `Normal`, `Roleplay`,
  `Roleplay PvP`) and combined with the faction.
* Only the file for the client's region is used (`GetCurrentRegion()`). If that
  is unavailable, the `US2`/`EU2`/`TW2`/`KR2` prefix in the realm name is used.
* Prices are stored in copper (`addonTable.priceScale = 1`). The tooltip uses
  the selected house's 4-day median for the "PvP Alliance"/"PvP Horde"/... line
  and the median across the region's houses for the "US Region" line.
* `addonTable.dataAge` is the time of the selected house's newest data.

## Caveats

* Blizzard has not documented the Forever auction namespace. The endpoints and
  the fifteen house IDs were confirmed against live data on 2026-11-10; treat
  them as best-effort.
* Values are a snapshot. The retail addon rebuilds its data a few times a
  week; the workflow above refreshes every hour.
* `/oetooltip debug` prints what was loaded. The same information is written
  to the `OETooltipDebug` saved variable on the next reload/logout.
* Price data comes from Blizzard's Forever auction API. This project is not
  affiliated with Blizzard Entertainment.
