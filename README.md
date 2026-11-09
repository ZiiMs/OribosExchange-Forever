# Oribos Exchange — WoW Forever

Auction-house prices in item tooltips for **World of Warcraft: Forever** (interface `16001`), using the price data published by [Undermine Exchange](https://undermine.exchange).

This is a port of the retail addon by **Erorus** (the author of Undermine Exchange). The original addon is built for Midnight and ships retail-only price data; this fork adds Forever realms, data generation, and a 3-hour refresh.

## Features

- Auction-house prices in item tooltips, outside the auction house too.
- Separate prices for every Forever auction house: `PvP`, `Normal`, `Roleplay`, `Roleplay PvP` × `Alliance`, `Horde`, `Neutral`.
- Region median line and auction-house line.
- Hold **Shift** while hovering a stack to see the **total value of the stack** instead of the per-item price: the realm and region lines are multiplied by the stack size and marked `xN` (for example `Realm x20`). The line updates when Shift is pressed or released without re-hovering.
- A **What's New** panel opens once after a feature or fix release, with icons and a small preview. Data-only price refreshes skip the panel and print the sync status in chat instead.
- Login chat reports when the auction-house data was last synced and when the next sync is due.
- Copper precision (a 25-copper item shows as 25c, not 0s).
- Coin **icons** (gold/silver/copper) by default, showing only the denominations used. `/oetooltip coins` switches to text.
- Railway cron triggers the GitHub build every 3 hours at :37 UTC; GitHub's native cron is disabled so the two cannot double-run a slot. Every build downloads all regions, without a freshness skip. Changed prices produce a **new versioned release** (with a UTC timestamp in the version), so addon managers like WowUp can see the update. Scheduling is approximate, not an exact-time guarantee.
- Same data API for other addons: `OEMarketInfo(itemId, table)` and `OETooltip()`.

## Install

1. Download the zip from the [latest release](https://github.com/ZiiMs/OribosExchange-Forever/releases/latest).
2. Extract the `OribosExchange` folder into:
   `World of Warcraft\_forever_\Interface\AddOns\`
3. Fully restart WoW (the addon list is read at startup), then make sure **Oribos Exchange** is enabled.
4. Hover an item.

Or clone straight into your AddOns folder:

```
git clone https://github.com/ZiiMs/OribosExchange-Forever.git OribosExchange
```

If you keep the folder name `OribosExchange-Forever`, the game will not see it as `OribosExchange`; rename it or clone with the target name above.

## Updating with WowUp

Add this repository as a GitHub source in WowUp and install **Oribos Exchange**. WowUp checks the latest published release.

When prices change, the workflow publishes a new release and bumps the addon version to `1.3.20261106-forever2.<UTC timestamp>` (for example `1.3.20261106-forever2.20261107031500`). That version change is what tells WowUp an update exists; replacing a zip on an unchanged tag would not.

If WowUp does not show an update, use **Check for updates** and make sure the source points at `ZiiMs/OribosExchange-Forever` and its releases, not a fixed tag.

## Commands

| Command | Effect |
| --- | --- |
| `/oetooltip` | List options |
| `/oetooltip on` / `off` | Enable/disable tooltip changes |
| `/oetooltip coins` | Toggle coin icons / text |
| `/oetooltip age` | Toggle the data-age line |
| `/oetooltip market` | Toggle the auction-house price line |
| `/oetooltip region` | Toggle the region median line |
| `/oetooltip lastseen` | Toggle the "Last seen" line |
| `/oetooltip quiet` | Disable all extra lines |
| `/oetooltip reset` | Reset preferences |
| `/oetooltip whatsnew` | Reopen the What's New panel |
| `/oetooltip debug` | Print what loaded (realm, house, data age, sample price) |

## How the data gets here

- `tools/forever-data/build.js` downloads Undermine Exchange's public Forever data (US/EU/TW/KR; 12/12/6/6 auction houses).
- The data is written into `OribosExchange/dynamic/data.*.lua` and committed by the [Refresh Forever data](.github/workflows/refresh-data.yml) workflow. The [Railway cron dispatcher](tools/railway-dispatch/README.md) requests a build at 02:37, 05:37, 08:37, 11:37, 14:37, 17:37, 20:37 and 23:37 UTC; GitHub's own schedule trigger is disabled. Minute zero is avoided to reduce scheduling contention.
- When prices change, the workflow bumps the addon version to a UTC timestamp, packages the zip, and publishes a **new versioned release** marked latest.
- The addon selects the house from the realm ID (or the realm-name ruleset) and the player's faction. It only loads the file for the client's region.
- Feature and fix releases update `OribosExchange/WhatsNew.lua` and bump its `revision`; the panel opens once per account. Data-only builds leave that file unchanged, so they never open the panel and print the data sync status in chat instead.
- Prices are stored in copper; the tooltip uses `C_CurrencyInfo.GetCoinTextureString` so only the used coins are shown.

This is the central updater for the repository: you do not need to run anything locally. The workflow commits data to `main` and publishes the new release. If you also publish to CurseForge/WoWUp, upload that release zip there.

Data is a snapshot: the auction-house line is the lowest current listing, and the region line is Undermine Exchange's region median. Like the retail addon, freshness depends on the last update.

To verify automatic operation, run `node tools/forever-data/check-refresh.js`
(requires GitHub CLI). It fails if the latest Railway dispatch is overdue or did
not build data. A manual run or a green workflow badge does **not** establish
that the schedule works. See the [Actions history](https://github.com/ZiiMs/OribosExchange-Forever/actions/workflows/refresh-data.yml)
and each run's summary for the trigger, outcome and per-region timestamps.

### Railway scheduler

A one-shot [Railway cron dispatcher](tools/railway-dispatch/README.md) triggers the
build every three hours and is the only unattended scheduler; GitHub's native
cron is disabled so it cannot double-run a slot. It runs briefly, sends an
authenticated workflow dispatch, and exits. Its token stays in Railway's private
variables. Runs are labelled **Forever prices (railway)**; check them with
`node tools/forever-data/check-refresh.js`.
Verify unattended timing in Railway's cron history as well; an accepted API
request alone does not prove the build finished or the timer fired.

## Build it yourself

```sh
node tools/forever-data/build.js
```

The script auto-detects the repository layout and writes to `OribosExchange/dynamic`. See [tools/forever-data/README.md](tools/forever-data/README.md) for options and the local scheduled-refresh setup.

When a release adds a feature or a user-visible fix, update `OribosExchange/WhatsNew.lua`: bump `revision`, replace `entries` with the new release's cards, and keep the icons or preview images current. Data-only refreshes must leave that file alone.

Build a release zip on Windows:

```powershell
pwsh tools/package.ps1
```

## Credits & licence

- Original addon and Undermine Exchange data: **Erorus** — <https://undermine.exchange/>
- WoW Forever port, data generator, and automation: **ZiiMs**
- Price data is provided by Undermine Exchange; this project is not affiliated with Blizzard Entertainment or Undermine Exchange.
- Licensed under the **GNU Lesser General Public License v3.0**; see [LICENSE](LICENSE) and [LICENSE-GPL-3.0](LICENSE-GPL-3.0). The original addon is also distributed under LGPL-3.0.

Use at your own risk. Prices are third-party estimates and can be stale or missing.
