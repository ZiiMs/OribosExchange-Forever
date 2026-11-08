'use strict';

// A one-shot Railway Cron job. No HTTP server, interval, or background worker.
async function dispatchRefresh(env = process.env, fetchImpl = fetch, log = console.log) {
    const token = env.GITHUB_TOKEN?.trim();
    if (!token) throw new Error('Set GITHUB_TOKEN in the Railway service variables (repository Actions: write).');
    const repository = env.GITHUB_REPOSITORY || 'ZiiMs/OribosExchange-Forever';
    const workflow = env.GITHUB_WORKFLOW || 'refresh-data.yml';
    const ref = env.GITHUB_REF || 'main';
    if (!/^[\w.-]+\/[\w.-]+$/.test(repository)) throw new Error('Invalid GITHUB_REPOSITORY; expected owner/repo.');
    if (!/^[\w.-]+\.ya?ml$/.test(workflow)) throw new Error('Invalid GITHUB_WORKFLOW; expected a workflow filename.');
    if (!ref.trim() || /[\x00-\x1f\x7f]/.test(ref)) throw new Error('Invalid GITHUB_REF.');

    const url = `https://api.github.com/repos/${repository}/actions/workflows/${encodeURIComponent(workflow)}/dispatches`;
    log(`Requesting ${repository}/${workflow} on ${ref} at ${new Date().toISOString()}`);
    let response;
    try {
        response = await fetchImpl(url, {
            method: 'POST',
            redirect: 'error',
            signal: AbortSignal.timeout(20000),
            headers: {
                Authorization: `Bearer ${token}`,
                Accept: 'application/vnd.github+json',
                'Content-Type': 'application/json',
                'X-GitHub-Api-Version': '2022-11-28',
                'User-Agent': 'OribosExchange-Forever-Railway-Cron',
            },
            body: JSON.stringify({ ref, inputs: { trigger_source: 'railway' } }),
        });
    } catch {
        // Do not log request objects, exception bodies or headers: they can contain tokens.
        // Do not blindly retry POST: the request may have succeeded before a timeout.
        throw new Error('GitHub dispatch timed out or the network request failed; inspect Actions before retrying.');
    }
    if (response.status !== 204 && response.status !== 200) {
        const hint = response.status === 401 || response.status === 403
            ? ' Check token expiry, repository access and Actions: write permission.'
            : response.status === 404
                ? ' Check repository access and the workflow filename.'
                : response.status === 422
                    ? ' Check the branch and workflow_dispatch inputs.' : '';
        throw new Error(`GitHub rejected dispatch (HTTP ${response.status}).${hint}`);
    }
    // Drain the bounded API response without printing its contents.
    await response.text();
    log('GitHub accepted the Railway dispatch. This confirms submission, not build completion.');
    log(`Follow the run: https://github.com/${repository}/actions/workflows/${workflow}`);
    return response.status;
}

module.exports = { dispatchRefresh };
if (require.main === module) {
    dispatchRefresh().catch(error => {
        console.error(error.message);
        process.exitCode = 1;
    });
}
