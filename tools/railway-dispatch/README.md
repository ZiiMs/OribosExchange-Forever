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
- Watch paths: `/tools/railway-dispatch/**` and `/.dockerignore`, so price-data commits do not
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
different from a human pressing Run workflow. Railway is the only unattended
scheduler; GitHub's native cron is disabled so it cannot duplicate a slot.
Concurrent builds are serialized and unchanged data does not publish another
release.

Configured service: [OribosExchange-Forever on Railway](https://railway.com/project/94e6ecfb-44e5-4d45-be7f-6c6fddae9d0a).
Project: `gregarious-kindness`, environment: `production`. Settings are applied
directly to this existing service; no deprecated `railway.json` is required.
An idle cron service with zero running replicas is expected, not an outage.
Rotate the GitHub token privately before its expiry.

## Deployment verification (2026-11-08 UTC)

- Docker build deployed successfully on Railway using the repository image.
- A manually started service run at 00:13:53 dispatched GitHub run
  [42428800877](https://github.com/ZiiMs/OribosExchange-Forever/actions/runs/42428800877),
  which built data and published release `v1.3.20261106-forever2.20261108001432`.
- The timer was tested on a temporary five-minute cadence. Without another
  manual start, Railway ran at 00:20:10; its cron history recorded
  `succeeded` at 00:20:12. The matching GitHub run
  [42429280247](https://github.com/ZiiMs/OribosExchange-Forever/actions/runs/42429280247)
  also completed successfully. The container exited with zero running replicas.
- The production cron was restored to `37 2-23/3 * * *` afterward. This verifies
  a real timed execution and the configured three-hour interval, not a guarantee
  of future runs or exact-to-the-minute delivery.

## Verify

```
node --test tools/railway-dispatch/dispatch.test.js
node tools/forever-data/check-refresh.js --source railway
```

After deploying, run the Railway cron once, verify that its logs say GitHub
accepted the dispatch, and follow the matching **Forever prices (railway)**
Actions run to completion. Also verify the first unattended Railway cron run;
a manually started cron verifies the connection, not the schedule itself.
