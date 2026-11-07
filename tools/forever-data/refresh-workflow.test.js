'use strict';

const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const workflow = readFileSync(path.join(__dirname, '../../.github/workflows/refresh-data.yml'), 'utf8');

test('automatic refresh requests eight evenly spaced runs, away from minute zero', () => {
    const cron = workflow.match(/cron:\s*['"]([^'"]+)['"]/)[1];
    const [minute, hours, day, month, weekday] = cron.split(/\s+/);
    assert.equal(minute, '37');
    assert.equal(hours, '2-23/3');
    assert.deepEqual([day, month, weekday], ['*', '*', '*']);
    const slots = Array.from({ length: 8 }, (_, i) => (2 + i * 3) * 60 + Number(minute));
    for (let i = 0; i < slots.length; i++) {
        assert.equal((slots[(i + 1) % slots.length] - slots[i] + 1440) % 1440, 180);
    }
});

test('each scheduled run downloads prices without a newest-region skip gate', () => {
    const step = workflow.match(/      - name: Build Forever data\r?\n([\s\S]*?)(?=\r?\n      - name:)/)[1];
    assert.match(step, /run: node tools\/forever-data\/build\.js/);
    assert.doesNotMatch(step, /\bif:|--min-age/);
    assert.doesNotMatch(workflow, /Check data age|steps\.age\.outputs|sort \| tail -n 1/);
});

test('a refresh cannot cancel an active release, and checkout follows main', () => {
    assert.match(workflow, /cancel-in-progress: false/);
    assert.match(workflow, /ref: main/);
    assert.doesNotMatch(workflow, /git reset --hard/);
});
