# Automatic refresh investigation — 2026-11-07

## Status: automatic execution is not verified

The repository's Actions setting is enabled, `refresh-data.yml` is active on
the default branch (`main`), and manual builds successfully publish releases.
This does not establish that GitHub delivers scheduled events.

Evidence collected through **20:52 UTC**:

- The only recorded `schedule` run was created at 09:44:58 UTC, started at
  16:41:07 UTC, and completed successfully at 16:41:54 UTC:
  <https://github.com/ZiiMs/OribosExchange-Forever/actions/runs/42361030112>.
- No scheduled events were recorded after that one, including during the
  hourly minute-zero configuration. They did not reach the build/skip logic.
- Manual run 42411256889 passed the configuration tests, built all regions,
  committed changed data, packaged the addon, and published release
  `v1.3.20261106-forever2.20261107202940` at 20:29:44 UTC:
  <https://github.com/ZiiMs/OribosExchange-Forever/actions/runs/42411256889>.
- After deploying the revised schedule at 20:28 UTC, the requested
  **20:37 UTC** event still had not appeared by **20:52 UTC**. A manual
  dispatch was not used to stand in for that test.

## Configuration corrections

- Request eight evenly spaced builds: `37 2-23/3 * * *` (UTC), avoiding minute
  zero. GitHub documents that top-of-hour load can delay or drop scheduled
  jobs. This reduces a known risk; it does not prove the cause of this incident.
- Remove the newest-region age gate. It could skip refreshing stale regions
  merely because a different region had a recent source timestamp.
- Serialize refreshes without cancelling an active release.
- Check out current `main` and tag a release at the exact packaged commit.
- Write the trigger, outcome and all four region timestamps in the run summary.

The configuration tests and actionlint pass. No workflow/build error explains
why GitHub has not created the subsequent scheduled events. The platform-side
cause cannot be determined from repository/API access alone. GitHub's status
page reported Actions operational during this investigation.

## Recheck

```
node --test tools/forever-data/*.test.js
node tools/forever-data/check-refresh.js --after 2026-11-07T20:28:31Z
```

The first command tests configuration and health-check regressions. The second
checks the live API and **must remain failing** until a new successful automatic
run actually builds data. Later manual runs cannot make it pass.

Next requested slot after this observation: **23:37 UTC**. If delivery remains
unreliable, an independent authenticated scheduler can dispatch this same
workflow; that is not installed or configured by this change. It requires a
separate scheduler and an appropriately scoped GitHub credential. Do not put
a token in the public repository or an unauthenticated dispatch URL.

GitHub reference:
<https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule>
