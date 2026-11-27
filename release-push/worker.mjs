const repository = '4ls4mi/super-booster';
const hubName = 'super-booster-releases';
const storageKey = 'latest-version';
const maximumBodySize = 512 * 1024;
const maximumSubscribers = 2048;
const versionPattern = /^(?:0|[1-9]\d{0,8})\.(?:0|[1-9]\d{0,8})\.(?:0|[1-9]\d{0,8})$/;

export async function validSignature(secret, body, header) {
    if (!secret || !/^sha256=[0-9a-fA-F]{64}$/.test(header ?? '')) return false;

    const algorithm = { name: 'HMAC', hash: 'SHA-256' };
    const key = await crypto.subtle.importKey(
        'raw', new TextEncoder().encode(secret), algorithm, false, ['verify'],
    );
    const signature = Uint8Array.from(header.slice(7).match(/../g), byte => Number.parseInt(byte, 16));
    return crypto.subtle.verify(algorithm, key, signature, body);
}

export function releaseSignal(event, payload) {
    if (event !== 'release' || payload?.action !== 'published' ||
        payload.repository?.full_name !== repository) return null;

    const release = payload.release;
    const tag = release?.tag_name;
    if (typeof tag !== 'string' || !tag.startsWith('v') ||
        release.draft !== false || release.prerelease !== false || !Array.isArray(release.assets)) {
        return null;
    }

    const version = tag.slice(1);
    if (!versionPattern.test(version)) return null;

    const installer = `SuperBooster-${version}-windows-x64-setup.exe`;
    if (release.assets.filter(asset => asset?.name === installer).length !== 1) return null;

    return { type: 'release', version };
}

async function readWebhookBody(request) {
    if (Number(request.headers.get('content-length')) > maximumBodySize) return null;
    if (!request.body) return new Uint8Array();

    const reader = request.body.getReader();
    const chunks = [];
    let length = 0;
    while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        length += value.byteLength;
        if (length > maximumBodySize) {
            await reader.cancel();
            return null;
        }
        chunks.push(value);
    }

    const body = new Uint8Array(length);
    let offset = 0;
    for (const chunk of chunks) {
        body.set(chunk, offset);
        offset += chunk.byteLength;
    }
    return body;
}

function isWebSocketRequest(request) {
    return request.method === 'GET' && request.headers.get('upgrade')?.toLowerCase() === 'websocket';
}

export default {
    async fetch(request, env) {
        const { pathname } = new URL(request.url);
        if (pathname === '/events' && request.method === 'GET') {
            if (!isWebSocketRequest(request)) return new Response('WebSocket required', { status: 426 });
            return env.RELEASE_HUB.getByName(hubName).fetch(request);
        }

        if (pathname !== '/github/webhook' || request.method !== 'POST') {
            return new Response('Not found', { status: 404 });
        }
        if (!env.GITHUB_WEBHOOK_SECRET) return new Response('Service not configured', { status: 503 });

        const bytes = await readWebhookBody(request);
        if (bytes === null) return new Response('Payload too large', { status: 413 });
        if (!await validSignature(env.GITHUB_WEBHOOK_SECRET, bytes, request.headers.get('x-hub-signature-256'))) {
            return new Response('Invalid signature', { status: 401 });
        }

        let payload;
        try {
            payload = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes));
        } catch {
            return new Response('Invalid JSON', { status: 400 });
        }

        const signal = releaseSignal(request.headers.get('x-github-event'), payload);
        if (!signal) return new Response(null, { status: 204 });

        return env.RELEASE_HUB.getByName(hubName).fetch(new Request('https://hub.internal/publish', {
            method: 'POST',
            body: signal.version,
        }));
    },
};

function isNewer(version, current) {
    const previous = current.split('.').map(Number);
    const next = version.split('.').map(Number);
    return (next[0] - previous[0] || next[1] - previous[1] || next[2] - previous[2]) > 0;
}

function sendVersion(socket, version) {
    try {
        socket.send(JSON.stringify({ type: 'release', version }));
    } catch {
        try { socket.close(); } catch { /* The subscriber already disconnected. */ }
    }
}

export class ReleaseHub {
    constructor(state) {
        this.state = state;
    }

    async acceptSubscriber(socket) {
        const current = await this.state.storage.get(storageKey);
        this.state.acceptWebSocket(socket);
        if (current) sendVersion(socket, current);
    }

    async fetch(request) {
        const { pathname } = new URL(request.url);
        if (pathname === '/events' && isWebSocketRequest(request)) {
            if (this.state.getWebSockets().length >= maximumSubscribers) {
                return new Response('Connection limit reached', { status: 503 });
            }
            const [client, server] = Object.values(new WebSocketPair());
            await this.acceptSubscriber(server);
            return new Response(null, { status: 101, webSocket: client });
        }

        if (pathname === '/publish' && request.method === 'POST') {
            const version = await request.text();
            if (!versionPattern.test(version)) return new Response('Invalid version', { status: 400 });

            const current = await this.state.storage.get(storageKey);
            // Durable Object storage gates serialize this read and write. A redelivery or
            // older release must never replace the current reconnect hint.
            if (!current || isNewer(version, current)) {
                await this.state.storage.put(storageKey, version);
                for (const socket of this.state.getWebSockets()) sendVersion(socket, version);
            }
            return new Response(null, { status: 204 });
        }

        return new Response('Not found', { status: 404 });
    }

    webSocketMessage(socket) {
        socket.close(1008, 'Client messages are not accepted');
    }
}
