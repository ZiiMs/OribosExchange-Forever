'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const { evaluateScheduledRun } = require('./check-refresh');
const now = Date.parse('2026-11-07T20:24:46Z');
const automatic = {
    event: 'schedule', status: 'completed', conclusion: 'success',
    created_at: '2026-11-07T09:44:58Z', updated_at: '2026-11-07T16:41:54Z',
};

test('the reported incident is overdue even with a recent manual success', () => {
    const manual = { ...automatic, event: 'workflow_dispatch', updated_at: '2026-11-07T20:23:00Z' };
    const result = evaluateScheduledRun([automatic, manual], now);
    assert.equal(result.ok, false);
    assert.match(result.reason, /222.9 minutes old/);
});

test('only a recent successful automatic run passes', () => {
    assert.equal(evaluateScheduledRun([], now).ok, false);
    const recent = { ...automatic, created_at: '2026-11-07T20:00:00Z', updated_at: '2026-11-07T20:01:00Z' };
    assert.equal(evaluateScheduledRun([recent], now).ok, true);
    assert.equal(evaluateScheduledRun([{ ...recent, event: 'workflow_dispatch' }], now).ok, false);
    assert.equal(evaluateScheduledRun([{ ...recent, conclusion: 'failure' }], now).ok, false);
    assert.equal(evaluateScheduledRun([{ ...recent, status: 'queued', conclusion: null }], now).ok, false);
});

test('an old success cannot verify a newly deployed schedule', () => {
    const cutoff = Date.parse('2026-11-07T17:00:00Z');
    assert.equal(evaluateScheduledRun([automatic], now, 600, cutoff).ok, false);
});

test('Railway health only accepts a Railway-labelled dispatch, not a human manual run', () => {
    const dispatched = { ...automatic, event: 'workflow_dispatch', display_title: 'Forever prices (railway)',
        created_at: '2026-11-07T20:00:00Z', updated_at: '2026-11-07T20:01:00Z' };
    assert.equal(evaluateScheduledRun([dispatched], now, 195, 0, 'railway').ok, true);
    assert.equal(evaluateScheduledRun([{ ...dispatched, display_title: 'Forever prices (manual)' }], now, 195, 0, 'railway').ok, false);
    assert.equal(evaluateScheduledRun([dispatched], now).ok, false);
});
