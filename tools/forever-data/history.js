'use strict';

const fs = require('fs');
const path = require('path');

function dayNumber(date = new Date()) {
    return date.getUTCFullYear() * 10000 + (date.getUTCMonth() + 1) * 100 + date.getUTCDate();
}

function dayDiff(from, to) {
    const midnight = (n) => Date.UTC(Math.floor(n / 10000), Math.floor(n / 100) % 100 - 1, n % 100);
    return Math.round((midnight(to) - midnight(from)) / 86400000);
}

function loadHistory(file) {
    if (!fs.existsSync(file)) return { version: 1, regions: {} };
    const parsed = JSON.parse(fs.readFileSync(file, 'utf8'));
    if (parsed.version !== 1 || !parsed.regions) throw new Error(`${file}: unknown history format`);
    return parsed;
}

function saveHistory(file, history) {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    const tmp = `${file}.tmp-${process.pid}`;
    fs.writeFileSync(tmp, JSON.stringify(history), 'utf8');
    fs.renameSync(tmp, file);
}

// Each item carries [today, yesterday, ... 4 daily lows, last seen YYYYMMDD].
function regionHistoryFor(history, region, houses, today) {
    let state = history.regions[region];
    if (!state) state = history.regions[region] = { day: today, houses: houses.map(() => ({})) };
    if (!Array.isArray(state.houses)) state.houses = [];
    while (state.houses.length < houses.length) state.houses.push({});
    if (state.day !== today) {
        const delta = dayDiff(state.day, today);
        if (delta > 0) {
            const shift = Math.min(delta, 4);
            for (const hist of state.houses) {
                for (const entry of Object.values(hist)) {
                    const old = [entry[0] ?? null, entry[1] ?? null, entry[2] ?? null, entry[3] ?? null];
                    for (let k = 3; k >= 0; k--) entry[k] = k >= shift ? old[k - shift] : null;
                    if (entry[4] == null) entry[4] = 0;
                }
            }
        }
        state.day = today;
    }
    return state;
}

module.exports = { dayNumber, dayDiff, loadHistory, saveHistory, regionHistoryFor };
