#!/usr/bin/env node
/*
 * Builds Oribos Exchange price data for WoW Forever from Undermine Exchange's
 * public realm data (the same files the undermine.exchange website loads).
 *
 * Usage:
 *   node tools/forever-data/build.js [options]
 *
 * Options:
 *   --out <dir>        Output directory (default: <addon>/dynamic)
 *   --cache <dir>      Download cache (default: tools/forever-data/cache)
 *   --regions <list>   Comma list of usf,euf,twf,krf (default: all)
 *   --offline          Use only cached downloads
 *   --no-cache-save    Don't write downloads to the cache
 *   --min-age <min>    Skip if the output files are newer than this many minutes
 *   --quiet            Less output
 *
 * The generated files replace dynamic/data.us.lua, data.eu.lua, data.tw.lua and
 * data.kr.lua with WoW Forever auction-house data. The retail data files are
 * backed up outside the addon by the porting step, not by this script.
 */

'use strict';

const fs = require('fs');
const path = require('path');
const http2 = require('node:http2');
const zlib = require('node:zlib');
const { STATUS_CODES } = require('node:http');

const SITE = 'https://undermine.exchange';
const HEADERS = {
    accept: 'application/json, text/plain, */*',
    'accept-language': 'en-US,en;q=0.9',
    'accept-encoding': 'gzip',
    referer: SITE + '/',
    'user-agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
        '(KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36',
};

// Forever region -> addon region. currentRegion is GetCurrentRegion().
const REGIONS = {
    usf: { addonRegion: 'US', currentRegion: 1, file: 'data.us.lua' },
    euf: { addonRegion: 'EU', currentRegion: 3, file: 'data.eu.lua' },
    twf: { addonRegion: 'TW', currentRegion: 4, file: 'data.tw.lua' },
    krf: { addonRegion: 'KR', currentRegion: 2, file: 'data.kr.lua' },
};

// Two refresh cycles. A run that is still green must not publish source data
// older than this, even when every HTTP request succeeds.
const MAX_SOURCE_AGE_MINUTES = 6 * 60;

const RULESET_BY_SLUG = {
    pvp: 'PvP',
    pve: 'Normal',
    rp: 'Roleplay',
    rppvp: 'Roleplay PvP',
};

const FACTION_LABEL = { alliance: 'Alliance', horde: 'Horde', neutral: 'Neutral' };

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

const ADDON_ROOT = path.resolve(__dirname, '..', '..');
const REPO_ADDON_ROOT = path.join(ADDON_ROOT, 'OribosExchange');
const DEFAULT_OUT = fs.existsSync(path.join(REPO_ADDON_ROOT, 'OribosExchange.toc'))
    ? path.join(REPO_ADDON_ROOT, 'dynamic')
    : path.join(ADDON_ROOT, 'dynamic');

function parseArgs(argv) {
    const args = {
        out: DEFAULT_OUT,
        cache: path.resolve(__dirname, 'cache'),
        regions: Object.keys(REGIONS),
        offline: false,
        cacheSave: true,
        minAge: 0,
        quiet: false,
    };
    for (let i = 0; i < argv.length; i++) {
        const a = argv[i];
        if (a === '--out') args.out = path.resolve(argv[++i]);
        else if (a === '--cache') args.cache = path.resolve(argv[++i]);
        else if (a === '--regions') args.regions = argv[++i].split(',').map(s => s.trim()).filter(Boolean);
        else if (a === '--offline') args.offline = true;
        else if (a === '--no-cache-save') args.cacheSave = false;
        else if (a === '--min-age') args.minAge = Number(argv[++i]) || 0;
        else if (a === '--quiet') args.quiet = true;
        else if (a === '--help' || a === '-h') {
            console.log(fs.readFileSync(__filename, 'utf8').split('*/')[0].replace(/^\/\*|\s*\*\s?/gm, ''));
            process.exit(0);
        } else {
            throw new Error(`Unknown option: ${a}`);
        }
    }
    for (const r of args.regions) {
        if (!REGIONS[r]) throw new Error(`Unknown region: ${r}`);
    }
    return args;
}

const args = parseArgs(process.argv.slice(2));
const log = (...parts) => { if (!args.quiet) console.log(...parts); };
const warn = (...parts) => console.error('WARN:', ...parts);
// ---------------------------------------------------------------------------
// Refresh lock (the daily task and the logon script can coincide)
// ---------------------------------------------------------------------------

const LOCK_PATH = path.join(args.cache, 'build.lock');
let lockHeld = false;

function acquireLock() {
    fs.mkdirSync(args.cache, { recursive: true });
    for (let attempt = 0; attempt < 2; attempt++) {
        try {
            const fd = fs.openSync(LOCK_PATH, 'wx');
            fs.writeFileSync(fd, String(process.pid));
            fs.closeSync(fd);
            lockHeld = true;
            return true;
        } catch (e) {
            if (e.code !== 'EEXIST') throw e;
            try {
                const age = Date.now() - fs.statSync(LOCK_PATH).mtimeMs;
                if (age > 15 * 60 * 1000) {
                    fs.rmSync(LOCK_PATH, { force: true });
                    continue;
                }
            } catch (statError) {
                continue;
            }
            return false;
        }
    }
    return false;
}

function releaseLock() {
    if (!lockHeld) return;
    lockHeld = false;
    try { fs.rmSync(LOCK_PATH, { force: true }); } catch (e) { /* ignore */ }
}

process.on('exit', releaseLock);

// ---------------------------------------------------------------------------
// HTTP + cache
// ---------------------------------------------------------------------------

// Undermine Exchange rejects HTTP/1.1 requests for /data/*.bin with 403 and
// serves the same files over HTTP/2, so downloads use node:http2. Replies are
// shaped like the small part of the fetch() Response interface this file uses.
function request(url, headers) {
    const target = new URL(url);
    return new Promise((resolve, reject) => {
        const client = http2.connect(target.origin);
        let settled = false;
        const finish = (fn, value) => {
            if (settled) return;
            settled = true;
            client.destroy();
            fn(value);
        };
        client.on('error', error => finish(reject, error));

        const stream = client.request({
            ':method': 'GET',
            ':path': target.pathname + target.search,
            ...headers,
        });
        stream.setTimeout(20000, () => {
            stream.close(http2.constants.NGHTTP2_CANCEL);
            finish(reject, new Error('Request timed out'));
        });

        let status = 0;
        let responseHeaders = {};
        const chunks = [];
        stream.on('response', h => { status = h[':status']; responseHeaders = h; });
        stream.on('data', chunk => chunks.push(chunk));
        stream.on('end', () => {
            let body = Buffer.concat(chunks);
            if (status !== 304 && body.length) {
                const encoding = String(responseHeaders['content-encoding'] || '').toLowerCase();
                try {
                    if (encoding === 'gzip') body = zlib.gunzipSync(body);
                    else if (encoding === 'deflate') body = zlib.inflateSync(body);
                    else if (encoding === 'br') body = zlib.brotliDecompressSync(body);
                } catch (error) {
                    finish(reject, error);
                    return;
                }
            }
            finish(resolve, {
                status,
                statusText: STATUS_CODES[status] || '',
                ok: status >= 200 && status < 300,
                headers: { get: name => responseHeaders[String(name).toLowerCase()] ?? null },
                arrayBuffer: async () => body,
            });
        });
        stream.on('error', error => finish(reject, error));
        stream.end();
    });
}

async function fetchBuffer(url, cachePath) {
    if (args.offline) {
        if (!fs.existsSync(cachePath)) throw new Error(`Offline and not cached: ${url}`);
        return fs.readFileSync(cachePath);
    }

    let lastError;
    for (let attempt = 1; attempt <= 3; attempt++) {
        try {
            const headers = { ...HEADERS };
            if (fs.existsSync(cachePath)) {
                headers['if-modified-since'] = fs.statSync(cachePath).mtime.toUTCString();
            }
            const res = await request(url, headers);
            if (res.status === 304 && fs.existsSync(cachePath)) {
                return fs.readFileSync(cachePath);
            }
            if (!res.ok) throw new Error(`HTTP ${res.status} ${res.statusText}`);
            const buf = Buffer.from(await res.arrayBuffer());
            if (args.cacheSave) {
                fs.mkdirSync(path.dirname(cachePath), { recursive: true });
                fs.writeFileSync(cachePath, buf);
                const lastModified = res.headers.get('last-modified');
                if (lastModified) {
                    const date = new Date(lastModified);
                    if (!isNaN(date.getTime())) {
                        fs.utimesSync(cachePath, date, date);
                    }
                }
            }
            return buf;
        } catch (e) {
            lastError = e;
            if (attempt < 3) await new Promise(r => setTimeout(r, 1000 * attempt));
        }
    }

    if (fs.existsSync(cachePath)) {
        warn(`${url}: ${lastError.message}; using cached copy`);
        return fs.readFileSync(cachePath);
    }
    throw new Error(`${url}: ${lastError.message} (no cache)`);
}

async function fetchJson(url, cachePath) {
    return JSON.parse((await fetchBuffer(url, cachePath)).toString('utf8'));
}

// ---------------------------------------------------------------------------
// Binary readers (mirror the parser in undermine.exchange's front end)
// ---------------------------------------------------------------------------

class Reader {
    constructor(buf) { this.buf = buf; this.o = 0; }
    u8() { const v = this.buf.readUInt8(this.o); this.o += 1; return v; }
    u16() { const v = this.buf.readUInt16LE(this.o); this.o += 2; return v; }
    u32() { const v = this.buf.readUInt32LE(this.o); this.o += 4; return v; }
}

// Price encoding used by Undermine Exchange:
//   top 2 bits 0 -> silver*100 (copper)
//   top 2 bits 1 -> copper
//   top 2 bits 2 -> gold*10000 (copper)
function decodePrice(encoded) {
    const n = encoded & 0x3fffffff;
    const kind = (encoded & 0xc0000000) >>> 0;
    if (kind === 0) return n * 100;
    if (kind === 0x40000000) return n;
    if (kind === 0x80000000) return n * 10000;
    return 0;
}

// Realm-state binary: one file per auction house, with the latest summary for
// every item key (item id, bonus level, suffix).
function parseState(buf) {
    const r = new Reader(buf);
    const version = r.u8();
    if (version !== 3 && version !== 4) throw new Error(`Unknown state version ${version}`);
    const snapshot = r.u32();
    const lastCheck = r.u32();
    const snapshotCount = r.u16();
    for (let i = 0; i < snapshotCount; i++) r.u32();

    const itemCount = r.u32();
    const items = new Map();
    for (let i = 0; i < itemCount; i++) {
        const id = r.u32();
        const level = r.u16();
        const suffix = r.u16();
        const snap = r.u32();
        const price = decodePrice(r.u32());
        const qty = r.u32();
        items.set(`${id}:${level}:${suffix}`, { id, level, suffix, snap, price, qty });
    }

    if (version === 4) {
        // Bonus-stat item groups, unused by the addon.
        const groups = r.u8();
        for (let g = 0; g < groups; g++) {
            r.u8();
            const count = r.u16();
            for (let i = 0; i < count; i++) { r.u32(); r.u16(); r.u16(); }
        }
    }

    return { version, snapshot, lastCheck, items };
}

// Region-state binary: region-wide prices per item key.
function parseRegion(buf) {
    const r = new Reader(buf);
    const version = r.u8();
    let hasVariants = true;
    let delta16 = false;
    if (version === 1) { hasVariants = false; delta16 = true; }
    else if (version === 2) { delta16 = true; }
    else if (version !== 3) throw new Error(`Unknown region version ${version}`);

    const count = r.u32();
    const items = new Map();
    let last = 0;
    for (let i = 0; i < count; i++) {
        last += delta16 ? r.u16() : r.u32();
        const level = r.u16();
        const suffix = r.u16();
        const price = decodePrice(r.u32());
        items.set(`${last}:${level}:${suffix}`, price);
    }
    // The rest (variants, arbitrage) is not needed for the addon.
    return { version, hasVariants, items };
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function beBytes(value, size) {
    const out = new Array(size).fill(0);
    let n = Math.max(0, Math.floor(Number(value) || 0));
    for (let i = size - 1; i >= 0; i--) {
        out[i] = n % 256;
        n = Math.floor(n / 256);
    }
    return out;
}

function decodeBE(bytes) {
    let n = 0;
    for (const b of bytes) n = n * 256 + b;
    return n;
}

function bytesFor(value) {
    if (value < 256) return 1;
    if (value < 65536) return 2;
    if (value < 16777216) return 3;
    if (value < 4294967296) return 4;
    if (value < 1099511627776) return 5;
    return 6;
}

function median(values) {
    const v = values.filter(n => n > 0).sort((a, b) => a - b);
    if (!v.length) return 0;
    const mid = v.length >> 1;
    return v.length % 2 ? v[mid] : Math.round((v[mid - 1] + v[mid]) / 2);
}

function daysSince(entry, nowSec) {
    if (!entry || !entry.price) return 0;
    if (entry.qty > 0) return 0;
    if (!entry.snap) return 251;
    const d = Math.floor((nowSec - entry.snap) / 86400);
    if (d > 250) return 251;
    if (d < 0) return 0;
    return d;
}

function slugPrefix(slug) {
    return (slug || '').split('-')[0].toLowerCase();
}

function slugFaction(slug) {
    const f = (slug || '').split('-').pop().toLowerCase();
    return FACTION_LABEL[f] ? f : 'neutral';
}

function luaEscape(bytes) {
    return bytes.map(b => '\\' + String(b).padStart(3, '0')).join('');
}

function luaString(s) {
    return "'" + String(s).replace(/\\/g, '\\\\').replace(/'/g, "\\'") + "'";
}

// Verify one generated blob with exactly the crop/decode logic the addon uses.
function cropDecode(blob, realmIndex) {
    const priceSize = blob[0];
    const headerSize = 1 + priceSize;
    const recordSize = 1 + priceSize;
    const recordOffset = headerSize + recordSize * realmIndex;
    const region = decodeBE(blob.slice(1, 1 + priceSize));
    const days = blob[recordOffset];
    const market = decodeBE(blob.slice(recordOffset + 1, recordOffset + 1 + priceSize));
    return { region, days, market };
}

// ---------------------------------------------------------------------------
// Build one region
// ---------------------------------------------------------------------------

async function loadHouse(region, house, cacheRoot) {
    const url = `${SITE}/data/${house.connectedId}/state.free.bin`;
    const cachePath = path.join(cacheRoot, region, `state-${house.connectedId}.bin`);
    try {
        const buf = await fetchBuffer(url, cachePath);
        if (!buf.length) return { items: new Map(), snapshot: 0, lastCheck: 0, empty: true };
        return parseState(buf);
    } catch (e) {
        warn(`${region}/${house.label}: ${e.message}`);
        return { items: new Map(), snapshot: 0, lastCheck: 0, empty: true };
    }
}

async function loadRegion(region, cacheRoot) {
    const url = `${SITE}/data/global/region-${region}.bin`;
    const cachePath = path.join(cacheRoot, region, 'region.bin');
    try {
        const buf = await fetchBuffer(url, cachePath);
        return parseRegion(buf);
    } catch (e) {
        warn(`${region} region file: ${e.message}; using house medians`);
        return { items: new Map() };
    }
}

async function buildRegion(region, config, houses, stateData, regionData, cacheRoot) {
    const houseCount = houses.length;
    const nowSec = Math.floor(Date.now() / 1000);

    // Index of the best entry for a house, used when an exact key is missing.
    function bestVariant(houseItems, id, level) {
        let best = null;
        for (const entry of houseItems.values()) {
            if (entry.id !== id) continue;
            if (level !== undefined && entry.level !== level) continue;
            if (!entry.price) continue;
            if (!best) { best = entry; continue; }
            const bestLive = best.qty > 0;
            const live = entry.qty > 0;
            if (live && !bestLive) { best = entry; continue; }
            if (!live && bestLive) continue;
            if (entry.price < best.price) best = entry;
            else if (entry.price === best.price && entry.snap > best.snap) best = entry;
        }
        return best;
    }

    function houseFor(houseIndex, id, level) {
        const state = stateData[houseIndex];
        if (level === 0) {
            const exact = state.items.get(`${id}:0:0`);
            if (exact && exact.price) return { price: exact.price, days: daysSince(exact, state.lastCheck || nowSec) };
            // No exact base entry: derive from the item's variants.
            const best = bestVariant(state.items, id);
            if (best) return { price: best.price, days: daysSince(best, state.lastCheck || nowSec) };
            return { price: 0, days: 0 };
        }
        const best = bestVariant(state.items, id, level);
        if (best) return { price: best.price, days: daysSince(best, state.lastCheck || nowSec) };
        return { price: 0, days: 0 };
    }

    function regionFor(id, level) {
        if (level === 0) {
            const exact = regionData.items.get(`${id}:0:0`);
            if (exact) return exact;
            const prices = [];
            for (const [key, price] of regionData.items) {
                const [i, l] = key.split(':').map(Number);
                if (i === id && price > 0) prices.push(price);
            }
            if (prices.length) return median(prices);
        } else {
            const exact = regionData.items.get(`${id}:${level}:0`);
            if (exact) return exact;
            const prices = [];
            for (const [key, price] of regionData.items) {
                const [i, l] = key.split(':').map(Number);
                if (i === id && l === level && price > 0) prices.push(price);
            }
            if (prices.length) return median(prices);
        }
        const prices = [];
        for (let h = 0; h < houseCount; h++) {
            const got = houseFor(h, id, level);
            if (got.price > 0) prices.push(got.price);
        }
        return median(prices);
    }

    // Collect keys that exist anywhere.
    const baseIds = new Set();
    const levelKeys = new Map(); // `${id}:${level}` -> {id, level}
    for (const state of stateData) {
        for (const entry of state.items.values()) {
            if (!entry.price) continue;
            if (entry.level === 0 && entry.suffix === 0) baseIds.add(entry.id);
            else if (entry.level > 0) levelKeys.set(`${entry.id}:${entry.level}`, { id: entry.id, level: entry.level });
        }
    }
    for (const [key, price] of regionData.items) {
        if (!price) continue;
        const [id, level, suffix] = key.split(':').map(Number);
        if (level === 0 && suffix === 0) baseIds.add(id);
        else if (level > 0) levelKeys.set(`${id}:${level}`, { id, level });
    }
    // Items that only have level/suffix variants still get a base entry.
    const variantIds = new Set();
    for (const state of stateData) {
        for (const entry of state.items.values()) {
            if (entry.price) variantIds.add(entry.id);
        }
    }
    for (const id of variantIds) baseIds.add(id);

    const records = []; // { key, blob, regionPrice, houses:[{price,days}] }
    let skipped = 0;

    function addRecord(key, id, level) {
        const houseValues = [];
        for (let h = 0; h < houseCount; h++) houseValues.push(houseFor(h, id, level));
        // A level-only entry with no house price adds nothing over the base
        // item; skip it so it cannot shadow the base price in the addon.
        if (level > 0 && !houseValues.some(v => v.price > 0)) { skipped++; return; }
        const regionPrice = regionFor(id, level);
        if (!regionPrice && !houseValues.some(v => v.price > 0)) { skipped++; return; }

        const maxPrice = Math.max(regionPrice, ...houseValues.map(v => v.price));
        const size = bytesFor(maxPrice);
        const blob = [size, ...beBytes(regionPrice, size)];
        for (const v of houseValues) {
            blob.push(v.days);
            blob.push(...beBytes(v.price, size));
        }

        // Self-check: decode each house with the addon's crop logic.
        for (let h = 0; h < houseCount; h++) {
            const got = cropDecode(blob, h);
            if (got.region !== regionPrice || got.days !== houseValues[h].days || got.market !== houseValues[h].price) {
                throw new Error(`${key} house ${h}: round-trip mismatch (region ${got.region}/${regionPrice}, days ${got.days}/${houseValues[h].days}, market ${got.market}/${houseValues[h].price}, size ${size})`);
            }
        }
        records.push({ key, blob, regionPrice, houses: houseValues });
    }

    for (const id of [...baseIds].sort((a, b) => a - b)) addRecord(String(id), id, 0);
    for (const { id, level } of [...levelKeys.values()].sort((a, b) => a.id - b.id || a.level - b.level)) {
        addRecord(`${id}-${level}`, id, level);
    }

    if (!records.length) return { region, config, houses, records, houseTimes: [] };

    const houseTimes = stateData.map((s) => s.lastCheck || s.snapshot || 0);
    return { region, config, houses, records, houseTimes };
}

// ---------------------------------------------------------------------------
// Lua writer
// ---------------------------------------------------------------------------

function writeLua(region, config, houses, records, houseTimes) {
    const houseLabels = houses.map(h => h.label);
    const houseFactions = houses.map(h => h.faction);
    const houseRulesets = houses.map(h => h.ruleset);
    const houseGuids = [];
    const guids = new Set();
    for (let i = 0; i < houses.length; i++) {
        const ids = [houses[i].id];
        if (houses[i].base !== houses[i].id) ids.push(houses[i].base);
        for (const v of ids) {
            if (guids.has(v)) {
                warn(`${region}: realm id ${v} collides across houses; keeping the first`);
                continue;
            }
            guids.add(v);
            houseGuids.push([v, i]);
        }
    }
    houseGuids.sort((a, b) => a[0] - b[0]);

    const byRuleset = {};
    for (let i = 0; i < houses.length; i++) {
        const h = houses[i];
        byRuleset[h.ruleset] ??= {};
        byRuleset[h.ruleset][h.faction] = i;
    }

    const rulesetKeys = Object.keys(byRuleset).sort();
    const luaTable = (entries, indent = '    ') => {
        if (!entries.length) return '{}';
        return '{\n' + entries.map(([k, v]) => {
            const key = typeof k === 'number' ? `${k}` : JSON.stringify(String(k));
            return `${indent}[${key}]=${v},`;
        }).join('\n') + '\n' + indent.slice(2) + '}';
    };

    const guidEntries = houseGuids.map(([id, idx]) => [id, idx]);
    const rulesetEntries = rulesetKeys.map(rs => {
        const inner = Object.entries(byRuleset[rs]).map(([f, idx]) => `["${f}"]=${idx}`);
        return [rs, '{' + inner.join(',') + '}'];
    });
    const labelEntries = houseLabels.map((l, i) => [i + 1, luaString(l)]);
    const factionEntries = houseFactions.map((f, i) => [i + 1, luaString(f)]);
    const rulesetEntriesH = houseRulesets.map((r, i) => [i + 1, luaString(r)]);
    const timeEntries = houseTimes.map((t, i) => [i + 1, t]);
    const dataTime = houseTimes.length ? Math.max(...houseTimes) : Math.floor(Date.now() / 1000);
    const regionLastCheck = Math.max(...houseTimes, 0);

    const chunks = [];
    const CHUNK = 200;
    let funcIndex = 0;
    for (let i = 0; i < records.length; i += CHUNK) {
        funcIndex++;
        const lines = [`dataFuncs[${funcIndex}] = function()`, 'local md = addonTable.marketData'];
        for (const rec of records.slice(i, i + CHUNK)) {
            lines.push(`md[${luaString(rec.key)}]=crop(${rec.blob[0]},"${luaEscape(rec.blob)}")`);
        }
        lines.push('end');
        chunks.push(lines.join('\n'));
    }

    const lua = `-- Generated by tools/forever-data/build.js. Do not edit by hand.
-- WoW Forever (${region}) price data from Undermine Exchange.
-- Data as of ${new Date(dataTime * 1000).toISOString()}.
local addonName, addonTable = ...
addonTable.dataLoads = addonTable.dataLoads or {}

local dataFuncs = {}
local regionId = ${config.currentRegion}
local regionName = ${luaString(config.addonRegion)}
local regionLastCheck = ${regionLastCheck}

local houseGuids = ${luaTable(guidEntries).replace(/\n/g, '\n')}
local houseByRuleset = ${luaTable(rulesetEntries).replace(/\n/g, '\n')}
local houseLabels = ${luaTable(labelEntries).replace(/\n/g, '\n')}
local houseFactions = ${luaTable(factionEntries).replace(/\n/g, '\n')}
local houseRulesets = ${luaTable(rulesetEntriesH).replace(/\n/g, '\n')}
local houseLastCheck = ${luaTable(timeEntries).replace(/\n/g, '\n')}

local function crop(priceSize, b)
    local headerSize = 1 + priceSize
    local recordSize = 1 + priceSize
    local offset = 1 + headerSize + recordSize * addonTable.realmIndex
    return string.sub(b, 1, headerSize)..string.sub(b, offset, offset + recordSize - 1)
end

${chunks.join('\n\n')}

local function parseRuleset(name)
    if not name then return nil end
    local n = string.lower(name)
    if string.find(n, "rppvp", 1, true) then return "Roleplay PvP" end
    if string.find(n, "roleplay", 1, true) or string.find(n, "rp", 1, true) then
        if string.find(n, "pvp", 1, true) then return "Roleplay PvP" end
        return "Roleplay"
    end
    if string.find(n, "pvp", 1, true) then return "PvP" end
    if string.find(n, "normal", 1, true) or string.find(n, "pve", 1, true) then return "Normal" end
    return nil
end

local function pickHouse(realmId, faction, realmName)
    faction = string.lower(faction or "Neutral")
    local id = tonumber(realmId)
    if id then
        local exact = houseGuids[id]
        if exact == nil then exact = houseGuids[id % 16384] end
        if exact ~= nil then
            if houseFactions[exact + 1] == faction then
                return exact
            end
            local group = houseByRuleset[houseRulesets[exact + 1]]
            if group and group[faction] then
                return group[faction]
            end
            return exact
        end
    end
    local ruleset = parseRuleset(realmName)
    if ruleset and houseByRuleset[ruleset] then
        local group = houseByRuleset[ruleset]
        return group[faction] or group["neutral"] or group["alliance"] or group["horde"]
    end
    for i = 1, #houseLabels, 1 do
        if houseFactions[i] == faction then return i - 1 end
    end
    return nil
end

local dataLoad = function(realmId, faction, realmName)
    local clientRegion = GetCurrentRegion and GetCurrentRegion()
    if not clientRegion or clientRegion == 0 then
        local n = string.lower(realmName or "")
        if string.find(n, "us1", 1, true) or string.find(n, "us2", 1, true) then
            clientRegion = 1
        elseif string.find(n, "eu1", 1, true) or string.find(n, "eu2", 1, true) then
            clientRegion = 3
        elseif string.find(n, "tw1", 1, true) or string.find(n, "tw2", 1, true) then
            clientRegion = 4
        elseif string.find(n, "kr1", 1, true) or string.find(n, "kr2", 1, true) then
            clientRegion = 2
        end
    end
    if clientRegion and clientRegion ~= regionId then
        wipe(dataFuncs)
        return false
    end
    local idx = pickHouse(realmId, faction, realmName)
    if idx == nil then
        wipe(dataFuncs)
        return false
    end
    addonTable.marketData = {}
    addonTable.realmIndex = idx
    addonTable.dataAge = houseLastCheck[idx + 1]
    if not addonTable.dataAge or addonTable.dataAge == 0 then
        addonTable.dataAge = regionLastCheck
    end
    addonTable.region = regionName
    addonTable.regionId = regionId
    addonTable.priceScale = 1
    addonTable.isForever = true
    addonTable.houseLabel = houseLabels[idx + 1]
    addonTable.houseFaction = houseFactions[idx + 1]
    addonTable.houseRuleset = houseRulesets[idx + 1]
    for i = 1, #dataFuncs, 1 do
        dataFuncs[i]()
        dataFuncs[i] = nil
    end
    wipe(dataFuncs)
    return true
end

table.insert(addonTable.dataLoads, dataLoad)
`;

    fs.mkdirSync(args.out, { recursive: true });
    const outPath = path.join(args.out, config.file);
    const tmpPath = `${outPath}.tmp-${process.pid}`;
    fs.writeFileSync(tmpPath, lua, 'utf8');
    try {
        fs.renameSync(tmpPath, outPath);
    } catch (e) {
        fs.rmSync(outPath, { force: true });
        fs.renameSync(tmpPath, outPath);
    }
    return { outPath, bytes: Buffer.byteLength(lua) };
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main() {
    fs.mkdirSync(args.cache, { recursive: true });

    if (!acquireLock()) {
        log('Another refresh is already running; skipping.');
        return;
    }

    if (args.minAge > 0) {
        const files = args.regions.map(r => path.join(args.out, REGIONS[r].file));
        if (files.every(f => fs.existsSync(f))) {
            const newest = Math.max(...files.map(f => fs.statSync(f).mtimeMs));
            const ageMinutes = (Date.now() - newest) / 60000;
            if (ageMinutes < args.minAge) {
                log(`Data is ${ageMinutes.toFixed(0)} minutes old (< ${args.minAge}); skipping refresh.`);
                return;
            }
        }
    }

    log(`Output: ${args.out}`);
    log(`Cache:  ${args.cache}`);

    const realmList = await fetchJson(`${SITE}/json/realms/realm-list.json`, path.join(args.cache, 'realm-list.json'));
    const realmNames = await fetchJson(`${SITE}/json/realms/realm-names.enus.json`, path.join(args.cache, 'realm-names.enus.json'));

    const regions = {};
    for (const [id, v] of Object.entries(realmList)) {
        if (!REGIONS[v.region]) continue;
        const faction = slugFaction(v.slug);
        const ruleset = RULESET_BY_SLUG[slugPrefix(v.slug)] ||
            (realmNames[id]?.name || v.name || '').replace(/\s+(Alliance|Horde|Neutral)$/i, '') ||
            slugPrefix(v.slug);
        const label = realmNames[id]?.name || v.name || `${ruleset} ${FACTION_LABEL[faction]}`;
        regions[v.region] ??= [];
        regions[v.region].push({
            id: Number(id),
            connectedId: v.connectedId,
            base: Number(id) & 0x3fff,
            slug: v.slug,
            label,
            faction,
            ruleset,
        });
    }

    const failed = [];
    let newestSource = 0;
    for (const region of args.regions) {
        const config = REGIONS[region];
        const houses = (regions[region] || []).sort((a, b) => a.id - b.id);
        if (!houses.length) {
            warn(`${region}: no realms found`);
            failed.push(region);
            continue;
        }
        log(`\n${region} (${config.addonRegion}): ${houses.length} auction houses`);

        const stateData = [];
        for (const house of houses) {
            const state = await loadHouse(region, house, args.cache);
            stateData.push(state);
            log(`  ${house.label.padEnd(20)} ${state.items.size} item keys${state.empty ? ' (empty)' : ''}`);
        }
        const regionData = await loadRegion(region, args.cache);
        log(`  region medians: ${regionData.items.size} item keys`);

        const result = await buildRegion(region, config, houses, stateData, regionData, args.cache);
        if (!result.records.length) {
            warn(`${region}: no price records; leaving the existing file untouched`);
            failed.push(region);
            continue;
        }
        const written = writeLua(region, config, houses, result.records, result.houseTimes);
        const baseCount = result.records.filter(r => !r.key.includes('-')).length;
        log(`  -> ${path.basename(written.outPath)}: ${result.records.length} entries (${baseCount} base), ${(written.bytes / 1024).toFixed(0)} KiB`);
        const maxTime = Math.max(...result.houseTimes);
        newestSource = Math.max(newestSource, maxTime);
        log(`  newest house scan: ${new Date(maxTime * 1000).toISOString()}`);
    }

    if (failed.length) {
        throw new Error(`Refresh incomplete: ${failed.join(', ')} produced no data (wrote ${args.regions.length - failed.length} of ${args.regions.length} regions).`);
    }

    if (!args.offline) {
        if (!newestSource) {
            throw new Error('Source data is stale: no auction-house scan timestamp was found.');
        }
        const ageMinutes = (Date.now() / 1000 - newestSource) / 60;
        if (ageMinutes > MAX_SOURCE_AGE_MINUTES) {
            throw new Error(`Source data is stale: newest auction-house scan is ${ageMinutes.toFixed(0)} minutes old (limit ${MAX_SOURCE_AGE_MINUTES}).`);
        }
    }
}

main().catch(e => {
    console.error('ERROR:', e.stack || e.message);
    process.exit(1);
});
