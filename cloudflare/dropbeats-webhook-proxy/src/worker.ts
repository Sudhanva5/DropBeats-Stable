/**
 * Reverse proxy in front of the DropBeats Railway backend.
 *
 * Why this exists: Jio blocks Railway. The macOS app used to call
 * dropbeats-server-production.up.railway.app directly, which means search and
 * autoplay have been dead for Jio users since the Railway migration. Routing
 * every app -> backend call through Cloudflare fixes that, and licensing is
 * pointed here from the start rather than shipping a third broken feature to
 * the same users.
 *
 * This Worker previously forwarded Gumroad webhooks to Supabase. It no longer
 * has that job: Gumroad posts to Railway directly (verified with a live ping on
 * 2026-08-21) and Supabase is being retired.
 */

interface Env {
  /** Railway origin. A variable, not a literal, so it can be repointed
   *  without a code change — the whole reason the previous hardcoding hurt. */
  ORIGIN_URL: string;
}

/**
 * Headers that describe a single transport hop and must not be forwarded.
 * Per RFC 7230 section 6.1. `host` is dropped separately so fetch() derives it
 * from the origin URL rather than sending the Worker's own hostname.
 */
const HOP_BY_HOP = new Set([
  'connection',
  'keep-alive',
  'proxy-authenticate',
  'proxy-authorization',
  'te',
  'trailer',
  'transfer-encoding',
  'upgrade',
]);

function buildForwardHeaders(request: Request): Headers {
  const headers = new Headers();

  for (const [name, value] of request.headers) {
    const lower = name.toLowerCase();
    if (HOP_BY_HOP.has(lower)) continue;
    if (lower === 'host') continue;
    // Rebuilt below from CF-Connecting-IP; never trust an inbound value.
    if (lower === 'x-forwarded-for') continue;
    headers.set(name, value);
  }

  // THE detail that must not be got wrong.
  //
  // The origin rate-limits on the leftmost X-Forwarded-For entry, falling back
  // to the peer address. Without this header every request arriving at Railway
  // carries the Worker's address, so all users worldwide share one bucket —
  // 30 validations then one per two seconds, globally. That is the same defect
  // the backend already found and fixed once, reintroduced one layer up, and
  // it would not show up in testing because a single tester looks identical
  // either way.
  //
  // Inbound X-Forwarded-For is dropped above rather than appended to, because
  // a client can send anything it likes; CF-Connecting-IP is set by Cloudflare
  // and is the only trustworthy value here.
  const clientIp = request.headers.get('CF-Connecting-IP');
  if (clientIp) {
    headers.set('X-Forwarded-For', clientIp);
  }

  return headers;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const origin = env.ORIGIN_URL;
    if (!origin) {
      // Fail loudly rather than proxying somewhere unintended.
      return new Response(
        JSON.stringify({ error: 'ORIGIN_URL is not configured' }),
        { status: 500, headers: { 'content-type': 'application/json' } },
      );
    }

    const incoming = new URL(request.url);
    const target = new URL(incoming.pathname + incoming.search, origin);

    // GET/HEAD must not carry a body, and duplex is required when one is sent.
    const hasBody = request.method !== 'GET' && request.method !== 'HEAD';

    const proxied = new Request(target.toString(), {
      method: request.method,
      headers: buildForwardHeaders(request),
      body: hasBody ? request.body : undefined,
      redirect: 'manual',
      ...(hasBody ? { duplex: 'half' } : {}),
    } as RequestInit);

    try {
      const response = await fetch(proxied);

      // Rebuild rather than returning the response directly, so the body
      // streams and the status/headers pass through untouched.
      return new Response(response.body, {
        status: response.status,
        statusText: response.statusText,
        headers: response.headers,
      });
    } catch (error) {
      // The origin is unreachable. 502 is the honest answer: the client's
      // request was fine, the upstream failed.
      return new Response(
        JSON.stringify({
          error: 'Upstream unreachable',
          detail: error instanceof Error ? error.message : String(error),
        }),
        { status: 502, headers: { 'content-type': 'application/json' } },
      );
    }
  },
};
