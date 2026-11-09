# WoW Forever price data

`build.js` downloads the WoW Forever auction-house prices that
[Undermine Exchange](https://undermine.exchange) publishes and writes the
four data files the addon loads:

| File | Region | Auction houses |
| --- | --- | --- |
| `OribosExchange/dynamic/data.us.lua` | US (`usf`) | 12 (PvP / Normal / Roleplay / Roleplay PvP x Alliance / Horde / Neutral) |
| `OribosExchange/dynamic/data.eu.lua` | EU (`euf`) | 12 |
| `OribosExchange/dynamic/data.tw.lua` | TW (`twf`) | 6 |
| `OribosExchange/dynamic/data.kr.lua` | KR (`krf`) | 6 |

The script uses the same public data files the Undermine Exchange website
loads. It does not scrape HTML and does not need an API key. (The official
API at <https://undermine.exchange/api.html> is the supported programmatic
interface, but it requires a Patreon API key; the generated output is the
same price data.)

## Run it

From the repository root:

```
node tools/forever-data/build.js
```

The script detects the repository layout and writes to
`OribosExchange/dynamic`. Options:

```
--out <dir>        output directory (default: auto-detected)
--cache <dir>      download cache (default: tools/forever-data/cache)
--regions <list>   comma list of usf,euf,twf,krf (default: all)
--offline          build from the cached downloads without fetching
--no-cache-save    don't write downloads to the cache
--min-age <min>    skip if the output files are newer than this many minutes
--quiet            less output
```

If Undermine Exchange is unreachable, the script falls back to the last
cached download and keeps the previous data files.

Undermine Exchange serves `/data/*.bin` only over HTTP/2; the same URL answers
HTTP/1.1 with `403 Forbidden`. The builder therefore downloads through
`node:http2` and decompresses the gzip response. A run fails, and commits
nothing, when any requested region produces no data or when the newest
auction-house scan is more than six hours old, so a green run always means
every region refreshed from fresh source data. `--offline` builds from cache
on purpose and skips the freshness check.

## Automatic refresh

The [Refresh Forever data](../../.github/workflows/refresh-data.yml) workflow
is dispatched by the [Railway cron dispatcher](../railway-dispatch/README.md)
every three hours at 02:37, 05:37, 08:37, 11:37, 14:37, 17:37, 20:37 and
23:37 UTC (`37 2-23/3 * * *`), and can be started by hand. GitHub's own
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
latest Railway-labelled dispatch completed successfully within 195 minutes and
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
* `houseGuids` maps both the realm ID Undermine uses (e.g. `33134`) and its
  base ID (e.g. `366`) to the auction house. If the ID is not known (for
  example a beta/test realm), the ruleset is read from the realm name
  (`PvP`, `Normal`, `Roleplay`, `Roleplay PvP`) and combined with the faction.
* Only the file for the client's region is used (`GetCurrentRegion()`). If that
  is unavailable, the `US2`/`EU2`/`TW2`/`KR2` prefix in the realm name is used.
* Prices are stored in copper (`addonTable.priceScale = 1`). The tooltip uses
  the selected house's price for the "PvP Alliance"/"PvP Horde"/... line and
  Undermine Exchange's region median for the "US Region" line.
* `addonTable.dataAge` is the time of the selected house's newest scan.

## Caveats

* The house price is the lowest current listing (not a 4-day median). The
  region line is Undermine Exchange's region median.
* Values are a snapshot. The retail addon rebuilds its data a few times a
  week; the workflow above refreshes every 3 hours.
* `/oetooltip debug` prints what was loaded. The same information is written
  to the `OETooltipDebug` saved variable on the next reload/logout.
* Data courtesy of Undermine Exchange; this project is not affiliated with
  them or Blizzard.
