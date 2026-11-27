import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import test from 'node:test';
import worker, { ReleaseHub, releaseSignal } from './worker.mjs';

const secret = 'fixture-only-secret';
const payload = {
    action: 'published',
    repository: { full_name: '4ls4mi/super-booster' },
    release: {
        tag_name: 'v2.0.2',
        draft: false,
        prerelease: false,
        assets: [{ name: 'SuperBooster-2.0.2-windows-x64-setup.exe' }, { name: 'SHA256SUMS.txt' }],
    },
};

function webhook(body = JSON.stringify(payload), event = 'release', signingSecret = secret) {
    const signature = createHmac('sha256', signingSecret).update(body).digest('hex');
    return new Request('https://worker.test/github/webhook', {
        method: 'POST',
        headers: { 'X-Hub-Signature-256': `sha256=${signature}`, 'X-GitHub-Event': event },
        body,
    });
}

test('accepts only the exact repository, public release event, stable version, and unique Windows installer', () => {
    assert.deepEqual(releaseSignal('release', payload), { type: 'release', version: '2.0.2' });
    assert.equal(releaseSignal('push', payload), null);
    for (const change of [
        { action: 'released' },
        { action: 'edited' },
        { repository: { full_name: '4ls4mi/Auralis-Download-Manager' } },
        { repository: { full_name: 'someone/super-booster' } },
        { release: { ...payload.release, draft: true } },
        { release: { ...payload.release, prerelease: true } },
        { release: { ...payload.release, tag_name: 'v2.0.2-rc.1' } },
        { release: { ...payload.release, tag_name: 'v2.00.2' } },
        { release: { ...payload.release, tag_name: '2.0.2' } },
        { release: { ...payload.release, assets: [{ name: 'SuperBooster-2.0.1-windows-x64-setup.exe' }] } },
        { release: { ...payload.release, assets: [payload.release.assets[0], payload.release.assets[0]] } },
    ]) {
        assert.equal(releaseSignal('release', { ...payload, ...change }), null);
    }
});

test('verifies GitHub HMAC before dispatch and bounds the request body', async () => {
    const accepted = [];
    const env = {
        GITHUB_WEBHOOK_SECRET: secret,
        RELEASE_HUB: {
            getByName(name) {
                assert.equal(name, 'super-booster-releases');
                return { async fetch(request) {
                    assert.equal(new URL(request.url).pathname, '/publish');
                    accepted.push(await request.text());
                    return new Response(null, { status: 204 });
                } };
            },
        },
    };

    assert.equal((await worker.fetch(webhook(undefined, 'release', 'wrong'), env)).status, 401);
    assert.equal((await worker.fetch(webhook('{'), env)).status, 400);
    assert.equal((await worker.fetch(webhook('{"zen":"fixture"}', 'ping'), env)).status, 204);
    assert.equal((await worker.fetch(webhook('x'.repeat(512 * 1024 + 1)), env)).status, 413);
    assert.equal((await worker.fetch(webhook(), {})).status, 503);
    assert.deepEqual(accepted, []);
    assert.equal((await worker.fetch(webhook(), env)).status, 204);
    assert.deepEqual(accepted, ['2.0.2']);
});

test('routes only new WebSocket connections to the release hub', async () => {
    const url = 'https://worker.test/events';
    const env = { RELEASE_HUB: { getByName: () => ({ fetch: request => {
        assert.equal(request.url, url);
        assert.equal(request.headers.get('Upgrade'), 'websocket');
        return new Response('proxied');
    } }) } };

    assert.equal((await worker.fetch(new Request(url), env)).status, 426);
    const upgrade = new Request(url, { headers: { Upgrade: 'websocket' } });
    assert.equal(await (await worker.fetch(upgrade, env)).text(), 'proxied');
    const publish = new Request('https://worker.test/publish', { method: 'POST', body: '9.9.9' });
    assert.equal((await worker.fetch(publish, env)).status, 404);
});

test('broadcasts increasing versions and replays the stored hint to a reconnecting subscriber', async () => {
    const stored = new Map();
    const sockets = [];
    const state = {
        storage: { get: async key => stored.get(key), put: async (key, value) => stored.set(key, value) },
        acceptWebSocket: socket => sockets.push(socket),
        getWebSockets: () => sockets,
    };
    const first = new ReleaseHub(state);
    const live = [];
    await first.acceptSubscriber({ send: text => live.push(JSON.parse(text)) });
    assert.deepEqual(live, []);

    for (const version of ['2.0.2', '2.0.2', '2.0.1', '2.0.10']) {
        const publish = new Request('https://hub.internal/publish', { method: 'POST', body: version });
        assert.equal((await first.fetch(publish)).status, 204);
    }
    assert.deepEqual(live, [{ type: 'release', version: '2.0.2' }, { type: 'release', version: '2.0.10' }]);

    const reconnected = [];
    await new ReleaseHub(state).acceptSubscriber({ send: text => reconnected.push(JSON.parse(text)) });
    assert.deepEqual(reconnected, [{ type: 'release', version: '2.0.10' }]);
});
