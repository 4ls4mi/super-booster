# Super Booster release notifications

The dedicated Cloudflare Worker accepts signed release webhooks from `4ls4mi/super-booster` and sends a version hint to running Super Booster apps. It accepts published stable tags such as `v2.0.2` that include exactly one `SuperBooster-2.0.2-windows-x64-setup.exe` asset. The Durable Object stores the highest accepted version and sends it to each client that reconnects.

The public WebSocket is `wss://<deployed-worker-host>/events`. Each text message contains a type and version.

```json
{"type":"release","version":"2.0.2"}
```

The app uses the hint to check its own GitHub releases and verifies the Windows installer's SHA-256 and size against GitHub's release metadata. If the API is unavailable, it uses the `super-booster-update.json` asset attached to the GitHub release. The app can also check GitHub when the WebSocket is unavailable. The Worker only supplies the version hint.

## Deploy

Run these commands in `release-push` with Node.js and npm installed. Enable Workers and workers.dev on the Cloudflare account first. Sign in with `npx --yes wrangler@4.166.0 login` if `whoami` reports no login. An account-scoped **Edit Cloudflare Workers** API token is another option for provisioning the Worker.

```powershell
node --test worker.test.mjs
npx --yes wrangler@4.166.0 whoami
npx --yes wrangler@4.166.0 deploy
npx --yes wrangler@4.166.0 secret put GITHUB_WEBHOOK_SECRET
```

Use a new randomly generated webhook secret and enter it interactively. Keep it in a password manager. Deploy to the dedicated `super-booster-release-push` Worker specified in `wrangler.toml`.

1. In the `4ls4mi/super-booster` repository, open **Settings → Webhooks → Add webhook**.
2. Set the payload URL to `https://<deployed-worker-host>/github/webhook` and content type to `application/json`. Enter the same secret, select the **Releases** event, and keep SSL verification enabled.
3. Confirm the GitHub `ping` delivery returns `204`. Use the deployed hostname for the app's `wss://<deployed-worker-host>/events` endpoint.
4. After the next intended stable release, confirm the `release` delivery returns `204` and an app listening to `/events` receives that version. Reconnect to verify the stored hint. Review failed deliveries and use GitHub's redelivery after correcting the problem.

[Cloudflare deployment](https://developers.cloudflare.com/workers/wrangler/commands/#deploy) · [GitHub webhook setup](https://docs.github.com/en/webhooks/using-webhooks/creating-webhooks)
