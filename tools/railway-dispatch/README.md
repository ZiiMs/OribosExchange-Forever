# Railway cron dispatcher

This one-shot service asks GitHub to run `refresh-data.yml` on `main` and exits.
It does not download price data, run a web server, or stay alive between runs.
An accepted dispatch means GitHub received the request; inspect the resulting
Actions run to verify build/release completion.

## Service settings

- Source: `ZiiMs/OribosExchange-Forever`, branch `main`, repository root `/`.
- Dockerfile path: `tools/railway-dispatch/Dockerfile` (build context: repo root).
- Start command: image default (`node dispatch.js`).
- Cron schedule: `37 2-23/3 * * *` — every three hours at :37 UTC.
- Restart policy: **Never**. No healthcheck, domain, database or volume needed.
- Watch paths: `/tools/railway-dispatch/**` only, so price-data commits do not
  redeploy the dispatcher and trigger a feedback loop.

Railway cron has approximate timing, not a precise SLA. It skips a slot if the
previous process is still running. This script uses a 20-second HTTP timeout
and exits after one request. HTTP/authentication errors exit nonzero; it does
not silently call a failed request successful.

## Private variables

Create a fine-grained GitHub personal access token:
<https://github.com/settings/personal-access-tokens/new>

Select resource owner **ZiiMs**, repository access **Only select repositories**,
repository **OribosExchange-Forever**, and repository permission
**Actions: Read and write**. Choose an expiry and rotate it before it expires.
Store the value as **GITHUB_TOKEN** on this Railway service's Variables tab.
Seal it if Railway offers that option. Do not paste it into chat, commit it,
put it in a URL, or copy an unrelated broad-scope token.

Optional non-secret settings (defaults shown):

```
GITHUB_REPOSITORY=ZiiMs/OribosExchange-Forever
GITHUB_WORKFLOW=refresh-data.yml
GITHUB_REF=main
```

The workflow accepts `trigger_source=railway`, making these runs visibly
different from a human pressing Run workflow. Native GitHub cron can remain a
fallback until Railway execution is verified.

## Verify

```
node --test tools/railway-dispatch/dispatch.test.js
node tools/forever-data/check-refresh.js --source railway
```

After deploying, run the Railway cron once, verify that its logs say GitHub
accepted the dispatch, and follow the matching **Forever prices (railway)**
Actions run to completion. Also verify the first unattended Railway cron run;
a manually started cron verifies the connection, not the schedule itself.
