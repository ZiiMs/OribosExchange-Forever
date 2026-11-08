'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const { dispatchRefresh } = require('./dispatch');

const env = { GITHUB_TOKEN: 'test-token-not-a-real-secret' };

test('missing credentials fail without sending a request', async () => {
    let called = false;
    await assert.rejects(dispatchRefresh({}, async () => { called = true; }), /Set GITHUB_TOKEN/);
    assert.equal(called, false);
});

for (const status of [204, 200]) {
    test(`submits exactly one authenticated Railway-labelled dispatch (HTTP ${status})`, async () => {
        const calls = [];
        const logs = [];
        const result = await dispatchRefresh(env, async (url, options) => {
            calls.push({ url, options });
            return new Response(status === 200 ? '{}' : null, { status });
        }, line => logs.push(line));
        assert.equal(result, status);
        assert.equal(calls.length, 1);
        assert.equal(calls[0].url, 'https://api.github.com/repos/ZiiMs/OribosExchange-Forever/actions/workflows/refresh-data.yml/dispatches');
        assert.equal(calls[0].options.method, 'POST');
        assert.equal(calls[0].options.redirect, 'error');
        assert.equal(calls[0].options.headers.Authorization, `Bearer ${env.GITHUB_TOKEN}`);
        assert.deepEqual(JSON.parse(calls[0].options.body), { ref: 'main', inputs: { trigger_source: 'railway' } });
        assert.ok(logs.some(line => line.includes('not build completion')));
        assert.ok(logs.every(line => !line.includes(env.GITHUB_TOKEN)));
    });
}

for (const status of [401, 403, 404, 422, 429, 500]) {
    test(`HTTP ${status} fails visibly without logging response contents`, async () => {
        const logs = [];
        await assert.rejects(dispatchRefresh(env, async () => new Response(env.GITHUB_TOKEN, { status }), line => logs.push(line)), new RegExp(`HTTP ${status}`));
        assert.ok(logs.every(line => !line.includes(env.GITHUB_TOKEN)));
    });
}

test('network errors do not leak credentials or blindly duplicate POSTs', async () => {
    let calls = 0;
    await assert.rejects(dispatchRefresh(env, async () => {
        calls++;
        throw new Error(env.GITHUB_TOKEN);
    }, () => {}), error => !error.message.includes(env.GITHUB_TOKEN) && /network request failed/.test(error.message));
    assert.equal(calls, 1);
});

test('bad repository configuration is rejected before sending a credential', async () => {
    await assert.rejects(dispatchRefresh({ ...env, GITHUB_REPOSITORY: 'https://example.com' }), /Invalid GITHUB_REPOSITORY/);
});
