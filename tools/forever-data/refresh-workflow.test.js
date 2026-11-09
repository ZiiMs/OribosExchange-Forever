'use strict';

const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const workflow = readFileSync(path.join(__dirname, '../../.github/workflows/refresh-data.yml'), 'utf8');

test('Railway cron is the only unattended scheduler', () => {
    assert.doesNotMatch(workflow, /^\s*schedule:/m);
    assert.doesNotMatch(workflow, /^\s*- cron:/m);
    assert.match(workflow, /^\s*workflow_dispatch:/m);
});

test('Railway and a human are distinguished by trigger_source', () => {
    assert.match(workflow, /^run-name: Forever prices \(\$\{\{ inputs\.trigger_source \}\}\)$/m);
    const inputs = workflow.match(/inputs:\r?\n([\s\S]*?)\r?\n\r?\n/)[1];
    assert.match(inputs, /^\s+- manual$/m);
    assert.match(inputs, /^\s+- railway$/m);
});

test('each dispatched run downloads prices without a newest-region skip gate', () => {
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
