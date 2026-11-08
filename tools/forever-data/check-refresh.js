'use strict';

// Read-only check. Unlike a manual dispatch, this verifies automatic delivery.
const { execFileSync } = require('node:child_process');

function evaluateScheduledRun(runs, now = Date.now(), maxAgeMinutes = 195, after = 0, source = 'github') {
    const scheduled = runs.filter(run => source === 'railway'
        ? run.event === 'workflow_dispatch' && run.display_title === 'Forever prices (railway)'
        : run.event === 'schedule')
        .sort((a, b) => Date.parse(b.created_at) - Date.parse(a.created_at));
    const run = scheduled[0];
    if (!run) return { ok: false, reason: 'No automatic schedule run exists.' };
    if (Date.parse(run.created_at) < after) {
        return { ok: false, reason: 'No automatic run has been created since the requested cutoff.', run };
    }
    if (run.status !== 'completed' || run.conclusion !== 'success') {
        return { ok: false, reason: `Latest automatic run is ${run.status}/${run.conclusion || 'pending'}.`, run };
    }
    const ageMinutes = (now - Date.parse(run.updated_at)) / 60000;
    if (!Number.isFinite(ageMinutes) || ageMinutes < 0 || ageMinutes > maxAgeMinutes) {
        return { ok: false, reason: `Last automatic success is ${ageMinutes.toFixed(1)} minutes old (limit ${maxAgeMinutes}).`, run };
    }
    return { ok: true, reason: `Automatic success completed ${ageMinutes.toFixed(1)} minutes ago.`, run };
}

function main() {
    const args = process.argv.slice(2);
    const getArg = (flag, fallback) => args.includes(flag) ? args[args.indexOf(flag) + 1] : fallback;
    const repo = getArg('--repo', 'ZiiMs/OribosExchange-Forever');
    const source = getArg('--source', 'github');
    if (!['github', 'railway'].includes(source)) throw new Error('--source must be github or railway');
    const afterText = getArg('--after', '1970-01-01T00:00:00Z');
    const after = Date.parse(afterText);
    if (!Number.isFinite(after)) throw new Error('--after must be an ISO timestamp');
    const api = endpoint => JSON.parse(execFileSync('gh', ['api', `repos/${repo}/${endpoint}`], { encoding: 'utf8' }));
    const event = source === 'railway' ? 'workflow_dispatch' : 'schedule';
    const { workflow_runs: runs } = api(`actions/workflows/refresh-data.yml/runs?event=${event}&per_page=100`);
    const result = evaluateScheduledRun(runs, Date.now(), 195, after, source);
    console.log(`Checked at ${new Date().toISOString()}`);
    console.log(`Source: ${source}${source === 'railway' ? ' (check Railway cron logs separately for unattended timing)' : ''}`);
    if (result.run) {
        console.log(`Automatic run: ${result.run.html_url}`);
        console.log(`Created ${result.run.created_at}; started ${result.run.run_started_at}; updated ${result.run.updated_at}`);
    }
    if (result.ok) {
        const { jobs } = api(`actions/runs/${result.run.id}/jobs?per_page=100`);
        const built = jobs.some(job => job.steps?.some(step => step.name === 'Build Forever data' && step.conclusion === 'success'));
        if (!built) {
            result.ok = false;
            result.reason = 'Automatic run succeeded but the data build did not run successfully.';
        }
    }
    const release = api('releases/latest');
    console.log(`Latest release: ${release.tag_name} (${release.published_at})`);
    console.log(`${result.ok ? 'PASS' : 'FAIL'}: ${result.reason}`);
    if (!result.ok) process.exitCode = 1;
}

module.exports = { evaluateScheduledRun };
if (require.main === module) main();
