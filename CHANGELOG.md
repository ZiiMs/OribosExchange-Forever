# Changelog

## 1.3.20261106-forever1

First WoW Forever release.

- Addon interface `16001` for WoW Forever 1.60.1.
- Generate Forever price data for US, EU, TW and KR (`usf`/`euf`/`twf`/`krf`), covering all 36 auction houses (PvP / Normal / Roleplay / Roleplay PvP × Alliance / Horde / Neutral).
- Select the auction house by realm ID, with a ruleset + faction fallback for beta/test realms.
- Copper-precision prices and coin icons by default; `/oetooltip coins` switches to text.
- `/oetooltip debug` and the `OETooltipDebug` saved variable for diagnostics.
- `tools/forever-data/build.js` data generator and a 3-hour GitHub Actions refresh.
- Rolling `latest` release with the packaged addon.
