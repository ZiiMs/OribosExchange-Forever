# Crafting cost checks

The addon needs no recipe data: in the profession window the client hands it the
recipe schematic through `C_TradeSkillUI.GetRecipeSchematic`, so the cost is
built from the recipe as the game reports it.

These tools check that arithmetic offline, without logging in.

## `build-recipes.js`

Reads the client's own tables from wago.tools and writes `recipes.json`: every
recipe on this client that makes an item, with its profession, output and basic
reagents.

```sh
node tools/crafting/build-recipes.js
```

Options: `--build <id>` (default `1.60.1.70938`, the build the addon targets),
`--out <file>`, `--quiet`.

Mining is included for its smelts. Jewelcrafting and Inscription have no
SkillLine on this client, so they contribute nothing.

`recipes.json` is a test fixture, not something the addon ships. Rebuild it when
the client patches, and commit it so the checks run without network access.

## `check-crafting.lua`

Runs `OribosExchange/Crafting.lua` against `recipes.json` and the committed
price data, then recomputes every cost, value, profit and ROI independently and
compares. Fails on any disagreement.

```sh
luajit tools/crafting/check-crafting.lua tools/crafting/recipes.json
```

Pass a data file as the second argument to check another region or house
(default `OribosExchange/dynamic/data.us.lua`, Normal Alliance).

It also checks the edges: a recipe the client has no schematic for returns
`false`, a non-numeric recipe returns `false`, and a zero-cost craft reports no
ROI instead of dividing by zero.

## `load-order.lua`

Loads the addon's files in `.toc` order against stubs and exercises the crafting
feature: the panel hook draws the text, it follows the lowest reagent list, an
unknown recipe and a recraft draw nothing, `disable-craft` silences it, and so
does `OETooltip(false)`. This catches a helper read before the file that defines
it, which a per-file lint cannot.

```sh
luajit tools/crafting/load-order.lua
```

## `preview-lines.lua`

Prints the panel text as a player would see it, for the cases worth eyeballing:
a profitable craft, a craft with an unpriced reagent, and a high-margin craft.

```sh
luajit tools/crafting/preview-lines.lua
```

## What the checks cannot cover

The panel hook only runs in a real client. These checks prove the arithmetic and
the wiring, not that Blizzard calls `Init` on the frame you see, nor that the
line lands where the panel has room for it. Verify that in game by selecting a
recipe and looking below its reagents.
