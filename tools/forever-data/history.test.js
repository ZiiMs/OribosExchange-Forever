'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');
const { dayNumber, dayDiff, loadHistory, saveHistory, regionHistoryFor } = require('./history');

test('day numbers are UTC dates', () => {
    assert.equal(dayNumber(new Date('2026-11-10T04:13:00Z')), 20261110);
    assert.equal(dayNumber(new Date('2026-01-01T23:59:59Z')), 20260101);
});

test('day differences cross month, year and leap boundaries', () => {
    assert.equal(dayDiff(20261109, 20261110), 1);
    assert.equal(dayDiff(20261231, 20270101), 1);
    assert.equal(dayDiff(20260228, 20260301), 1);
    assert.equal(dayDiff(20240228, 20240301), 2);
    assert.equal(dayDiff(20261110, 20261110), 0);
});

test('a new day shifts the four daily prices and keeps the last-seen day', () => {
    const history = { version: 1, regions: { usf: { day: 20261109, houses: [{ 2589: [10, 9, 8, 7, 20261109] }] } } };
    const state = regionHistoryFor(history, 'usf', [{}], 20261110);
    assert.deepEqual(state.houses[0]['2589'], [null, 10, 9, 8, 20261109]);
    assert.equal(state.day, 20261110);
});

test('a gap of two days shifts twice', () => {
    const history = { version: 1, regions: { usf: { day: 20261108, houses: [{ 2589: [10, 9, 8, 7, 20261108] }] } } };
    const state = regionHistoryFor(history, 'usf', [{}], 20261110);
    assert.deepEqual(state.houses[0]['2589'], [null, null, 10, 9, 20261108]);
});

test('a gap of four or more days empties the prices but keeps last seen', () => {
    for (const day of [20261106, 20260101]) {
        const history = { version: 1, regions: { usf: { day, houses: [{ 2589: [10, 9, 8, 7, day] }] } } };
        const state = regionHistoryFor(history, 'usf', [{}], 20261110);
        assert.deepEqual(state.houses[0]['2589'], [null, null, null, null, day]);
    }
});

test('the same day leaves the prices alone', () => {
    const entry = [10, 9, 8, 7, 20261110];
    const history = { version: 1, regions: { usf: { day: 20261110, houses: [{ 2589: entry }] } } };
    const state = regionHistoryFor(history, 'usf', [{}], 20261110);
    assert.equal(state.houses[0]['2589'], entry);
});

test('a new region gets one history table per house', () => {
    const history = { version: 1, regions: {} };
    const state = regionHistoryFor(history, 'krf', [{}, {}, {}], 20261110);
    assert.equal(state.day, 20261110);
    assert.equal(state.houses.length, 3);
    assert.deepEqual(state.houses, [{}, {}, {}]);
});

test('history round trips and a missing file starts empty', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'oe-history-'));
    const file = path.join(dir, 'history.json');
    assert.deepEqual(loadHistory(file), { version: 1, regions: {} });
    const history = { version: 1, regions: { usf: { day: 20261110, houses: [{ 2589: [10, null, null, null, 20261110] }] } } };
    saveHistory(file, history);
    assert.deepEqual(loadHistory(file), history);
    fs.rmSync(dir, { recursive: true, force: true });
});
