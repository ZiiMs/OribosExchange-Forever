#!/usr/bin/env node
/*
 * Builds the recipe list the crafting-cost check runs against, from the
 * client's own game tables.
 *
 * The addon itself needs no recipe data: inside the profession window the
 * client hands it the live recipe schematic. This list exists so the check can
 * exercise the addon's arithmetic against every craftable recipe without
 * logging in.
 *
 * Usage:
 *   node tools/crafting/build-recipes.js [options]
 *
 * Options:
 *   --build <id>   Client build to read (default: the Forever build below)
 *   --out <file>   Output file (default: tools/crafting/recipes.json)
 *   --quiet        Less output
 *
 * Source: wago.tools DB2 exports for the Forever client.
 */

'use strict';

const fs = require('fs');
const path = require('path');

// Forever 1.60.1, matching the client the addon targets.
const DEFAULT_BUILD = '1.60.1.70938';
const BASE = 'https://wago.tools/db2';

// Professions that craft an item. Mining is included for its smelts, which do
// make bars from ore; the rest of the gathering lines only produce materials.
// Jewelcrafting and Inscription do not exist on this client.
const PROFESSIONS = {
    129: 'First Aid',
    164: 'Blacksmithing',
    165: 'Leatherworking',
    171: 'Alchemy',
    185: 'Cooking',
    186: 'Mining',
    197: 'Tailoring',
    202: 'Engineering',
    333: 'Enchanting',
};

const DEFAULT_OUT = path.join(__dirname, 'recipes.json');

function parseArgs(argv) {
    const args = { build: DEFAULT_BUILD, out: DEFAULT_OUT, quiet: false };
    for (let i = 0; i < argv.length; i++) {
        const a = argv[i];
        if (a === '--build') args.build = argv[++i];
        else if (a === '--out') args.out = path.resolve(argv[++i]);
        else if (a === '--quiet') args.quiet = true;
        else if (a === '--help' || a === '-h') {
            console.log(fs.readFileSync(__filename, 'utf8').split('*/')[0].replace(/^\/\*|\s*\*\s?/gm, ''));
            process.exit(0);
        } else throw new Error(`Unknown option: ${a}`);
    }
    return args;
}

const args = parseArgs(process.argv.slice(2));
const log = (...parts) => {
    if (!args.quiet) console.log(...parts);
};

async function fetchCsv(table) {
    const url = `${BASE}/${table}/csv?build=${args.build}`;
    const res = await fetch(url, { signal: AbortSignal.timeout(120000) });
    if (!res.ok) throw new Error(`${table}: HTTP ${res.status}`);
    const text = await res.text();

    const lines = text.split(/\r?\n/).filter((line) => line.length > 0);
    const header = lines[0].split(',');
    const rows = [];
    for (let i = 1; i < lines.length; i++) {
        const cols = lines[i].split(',');
        const row = {};
        for (let c = 0; c < header.length; c++) row[header[c]] = cols[c];
        rows.push(row);
    }
    return rows;
}

// Effect 24 creates an item; EffectItemType is the item, EffectBasePointsF + 1
// how many.
const EFFECT_CREATE_ITEM = 24;

async function main() {
    log(`reading ${args.build} tables from wago.tools`);

    const [reagents, effects, abilities, skillLines] = await Promise.all([
        fetchCsv('SpellReagents'),
        fetchCsv('SpellEffect'),
        fetchCsv('SkillLineAbility'),
        fetchCsv('SkillLine'),
    ]);
    log(`  SpellReagents ${reagents.length}, SpellEffect ${effects.length}, ` +
        `SkillLineAbility ${abilities.length}, SkillLine ${skillLines.length}`);

    const professionName = new Map();
    for (const row of skillLines) {
        const id = Number(row.ID);
        if (PROFESSIONS[id]) professionName.set(id, PROFESSIONS[id]);
    }
    // Mining's row is absent from this client's SkillLine table, so its name
    // comes from the list above rather than the export.

    // Spell -> profession, for the crafting lines only. Mining has no SkillLine
    // row on this client, so its smelts (which do make bars) are matched by the
    // skill line ability's own name where the table provides one.
    const professionOf = new Map();
    for (const row of abilities) {
        const skillLine = Number(row.SkillLine);
        if (!PROFESSIONS[skillLine]) continue;
        const spell = Number(row.Spell);
        if (spell && !professionOf.has(spell)) professionOf.set(spell, skillLine);
    }

    // Spell -> the item it makes and how many.
    const madeBy = new Map();
    for (const row of effects) {
        if (Number(row.Effect) !== EFFECT_CREATE_ITEM) continue;
        const item = Number(row.EffectItemType);
        if (!item) continue;
        const spell = Number(row.SpellID);
        if (madeBy.has(spell)) continue;
        madeBy.set(spell, { item, count: Math.max(1, Number(row.EffectBasePointsF) || 1) });
    }

    const recipes = [];
    let noOutput = 0;
    let noReagents = 0;
    for (const row of reagents) {
        const spell = Number(row.SpellID);
        const skillLine = professionOf.get(spell);
        if (!skillLine) continue;

        const made = madeBy.get(spell);
        if (!made) {
            noOutput++;
            continue;
        }

        const parts = [];
        for (let i = 0; i < 8; i++) {
            const item = Number(row[`Reagent_${i}`]);
            const count = Number(row[`ReagentCount_${i}`]);
            if (item > 0 && count > 0) parts.push([item, count]);
        }
        if (!parts.length) {
            noReagents++;
            continue;
        }

        recipes.push({
            spell,
            prof: professionName.get(skillLine) || PROFESSIONS[skillLine],
            out: made.item,
            count: made.count,
            parts,
        });
    }

    recipes.sort((a, b) => a.spell - b.spell);

    const byProfession = {};
    for (const r of recipes) byProfession[r.prof] = (byProfession[r.prof] || 0) + 1;

    fs.mkdirSync(path.dirname(args.out), { recursive: true });
    fs.writeFileSync(args.out, JSON.stringify(recipes), 'utf8');

    log(`  ${recipes.length} recipes, ${noOutput} have no item output, ${noReagents} have no reagents`);
    log(`  by profession: ${Object.entries(byProfession).map(([p, n]) => `${p} ${n}`).join(', ')}`);
    log(`wrote ${args.out} (${(fs.statSync(args.out).size / 1024).toFixed(0)} KB)`);
}

main().catch((e) => {
    console.error('ERROR: ' + e.message);
    process.exit(1);
});
