# Changelog

## Unreleased

- Hold Shift while hovering a stack to show the total value of the stack on the realm and region lines, marked `xN`. An open tooltip updates when Shift is pressed or released.

## 1.3.20261106-forever2

- Fixed item-level entries hiding the base item price on Forever. If an item-level variant has only a region price, the addon now falls back to the base auction-house price instead of showing nothing (for example Yorgen Bracers).
- `/oetooltip debug <item link>` now reports the item ID, every data key for it, and each key's market/region price.
- The data generator skips level entries that have no auction-house price, so they cannot shadow the base item price and the data files are smaller.

## 1.3.20261106-forever1

First WoW Forever release.

- Addon interface `16001` for WoW Forever 1.60.1.
- Generate Forever price data for US, EU, TW and KR (`usf`/`euf`/`twf`/`krf`), covering all 36 auction houses (PvP / Normal / Roleplay / Roleplay PvP × Alliance / Horde / Neutral).
- Select the auction house by realm ID, with a ruleset + faction fallback for beta/test realms.
- Copper-precision prices and coin icons by default; `/oetooltip coins` switches to text.
- `/oetooltip debug` and the `OETooltipDebug` saved variable for diagnostics.
- `tools/forever-data/build.js` data generator and a 3-hour GitHub Actions refresh.
- Each data refresh publishes a new timestamped addon version and GitHub release, so addon managers such as WowUp can detect updates.
