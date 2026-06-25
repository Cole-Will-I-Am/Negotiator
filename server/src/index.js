// negotiator-api Worker. Stateful persuasion-turn orchestration over Ollama Cloud on D1.
// Identity (anon device + optional Sign in with Apple) + sessions reuse RUNG's spine; the
// turn handler streams the gatekeeper as NDJSON and runs the gated judge (see engine.js).

import {
  HttpError, sha256hex, hmacHex, randomToken, randomId,
  verifyAppleIdentityToken, createSession, authPlayer, constantTimeEqual,
} from "./auth.js";
import { runTurn, modelsFrom } from "./engine.js";
import { LEVELS } from "./game.js";

const CORS = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization,content-type",
  "access-control-allow-methods": "GET,POST,DELETE,OPTIONS",
};
const json = (obj, status = 200, headers = {}) =>
  new Response(JSON.stringify(obj), { status, headers: { "content-type": "application/json", ...CORS, ...headers } });
const ok = (obj, headers) => json(obj, 200, headers);
const fail = (status, error) => json({ error }, status);
async function readJson(req) { try { return await req.json(); } catch { return {}; } }
const nowS = () => Math.floor(Date.now() / 1000);

// Fixed-window per-IP rate limiter backed by D1. Returns true if under the limit.
async function rateLimit(env, req, key, limit, windowSec) {
  const ip = req.headers.get("CF-Connecting-IP") || "0";
  const bucket = Math.floor(Date.now() / 1000 / windowSec);
  const k = `${key}:${ip}:${bucket}`;
  const row = await env.DB.prepare(
    "INSERT INTO rate(k,n,exp) VALUES(?,1,?) ON CONFLICT(k) DO UPDATE SET n=n+1 RETURNING n"
  ).bind(k, (bucket + 1) * windowSec).first();
  return (row?.n ?? 1) <= limit;
}

async function newPlayer(env, { apple_sub = null, isAnon = 1 }) {
  const id = randomId("p_");
  const code = randomToken(2).slice(0, 4).toUpperCase();
  await env.DB.prepare(
    "INSERT INTO players(id,apple_sub,display,is_anonymous,created_at) VALUES(?,?,?,?,?)"
  ).bind(id, apple_sub, "Traveller-" + code, isAnon, nowS()).run();
  return env.DB.prepare("SELECT * FROM players WHERE id=?").bind(id).first();
}
const playerView = (p) => ({ id: p.id, display: p.display, isAnonymous: !!p.is_anonymous });

async function requireAuth(req, env) {
  const p = await authPlayer(req, env);
  if (!p) throw new HttpError(401, "unauthorized");
  return p;
}

// ---------------- handlers ----------------

async function hAccount(req, env) {
  if (!(await rateLimit(env, req, "acct", 30, 3600))) return fail(429, "rate_limited");
  const body = await readJson(req);

  // Sign in with Apple (optional — only when the server is configured for it).
  if (body.appleIdentityToken) {
    if (!env.APPLE_SUB_PEPPER || !env.APPLE_BUNDLE_ID) return fail(501, "siwa_disabled");
    const sub = await verifyAppleIdentityToken(body.appleIdentityToken, body.nonce ?? null, env.APPLE_BUNDLE_ID);
    const subKey = await hmacHex(sub, env.APPLE_SUB_PEPPER);
    let p = await env.DB.prepare("SELECT * FROM players WHERE apple_sub=?").bind(subKey).first();
    if (!p && body.deviceId && body.deviceSecret) {
      const link = await env.DB.prepare("SELECT * FROM device_links WHERE device_id=?").bind(body.deviceId).first();
      if (link && link.secret_hash && constantTimeEqual(link.secret_hash, await sha256hex(body.deviceSecret))) {
        const anon = await env.DB.prepare("SELECT * FROM players WHERE id=? AND is_anonymous=1").bind(link.player_id).first();
        if (anon) {
          await env.DB.prepare("UPDATE players SET apple_sub=?, is_anonymous=0 WHERE id=?").bind(subKey, anon.id).run();
          p = await env.DB.prepare("SELECT * FROM players WHERE id=?").bind(anon.id).first();
        }
      }
    }
    if (!p) p = await newPlayer(env, { apple_sub: subKey, isAnon: 0 });
    const s = await createSession(env, p.id);
    return ok({ token: s.token, expiresAt: s.expiresAt, player: playerView(p) });
  }

  // Anonymous device registration / resume — authenticated by a server-issued device secret.
  const deviceId = body.deviceId;
  if (!deviceId) return fail(400, "missing_deviceId");
  const link = await env.DB.prepare("SELECT * FROM device_links WHERE device_id=?").bind(deviceId).first();
  if (link) {
    if (!body.deviceSecret || !link.secret_hash ||
        !constantTimeEqual(link.secret_hash, await sha256hex(body.deviceSecret))) {
      return fail(401, "bad_device_secret");
    }
    const p = await env.DB.prepare("SELECT * FROM players WHERE id=?").bind(link.player_id).first();
    if (!p) return fail(401, "bad_device_secret");
    const s = await createSession(env, p.id);
    return ok({ token: s.token, expiresAt: s.expiresAt, player: playerView(p) });
  }
  const secret = randomToken(32);
  const p = await newPlayer(env, { isAnon: 1 });
  await env.DB.prepare("INSERT OR IGNORE INTO device_links(device_id,player_id,secret_hash,created_at) VALUES(?,?,?,?)")
    .bind(deviceId, p.id, await sha256hex(secret), nowS()).run();
  const s = await createSession(env, p.id);
  return ok({ token: s.token, expiresAt: s.expiresAt, player: playerView(p), deviceSecret: secret });
}

async function hDeleteAccount(req, env, player) {
  await env.DB.batch([
    env.DB.prepare("DELETE FROM nego_turn WHERE session_id IN (SELECT id FROM nego_session WHERE player_id=?)").bind(player.id),
    env.DB.prepare("DELETE FROM nego_session WHERE player_id=?").bind(player.id),
    env.DB.prepare("DELETE FROM sessions WHERE player_id=?").bind(player.id),
    env.DB.prepare("DELETE FROM device_links WHERE player_id=?").bind(player.id),
    env.DB.prepare("DELETE FROM players WHERE id=?").bind(player.id),
  ]);
  return ok({ deleted: true });
}

async function hSessionStart(req, env, player) {
  if (!(await rateLimit(env, req, "start", 60, 3600))) return fail(429, "rate_limited");
  const body = await readJson(req);
  const levelId = String(body.levelId || "bartholomew");
  const level = LEVELS[levelId];
  if (!level) return fail(404, "no_level");
  const id = randomId("g_");
  const now = nowS();
  await env.DB.prepare(
    `INSERT INTO nego_session(id,player_id,level_id,phase,turns_taken,status,won,started_at,updated_at)
     VALUES(?,?,?,?,0,'active',0,?,?)`
  ).bind(id, player.id, levelId, "cold", now, now).run();
  return ok({
    sessionId: id,
    level: { id: level.id, title: level.title, worldFiction: level.worldFiction,
             gatekeeper: level.gatekeeperName, opening: level.openingLine, blurb: level.blurb },
  });
}

async function hSessionGet(req, env, player, id) {
  const sess = await env.DB.prepare("SELECT * FROM nego_session WHERE id=? AND player_id=?").bind(id, player.id).first();
  if (!sess) return fail(404, "no_session");
  const { results } = await env.DB.prepare(
    "SELECT turn_number,player_text,gatekeeper_text,input_blocked,phase_at_turn FROM nego_turn WHERE session_id=? ORDER BY turn_number"
  ).bind(id).all();
  return ok({
    session: { id: sess.id, levelId: sess.level_id, phase: sess.phase, turnsTaken: sess.turns_taken,
               status: sess.status, won: !!sess.won, seam: sess.seam_used },
    turns: results.map((t) => ({ n: t.turn_number, player: t.player_text, gatekeeper: t.gatekeeper_text,
               blocked: !!t.input_blocked, phase: t.phase_at_turn })),
  });
}

// POST /v1/session/turn — streams the gatekeeper as NDJSON, then a final verdict line.
//   {"t":"phase","from":"cold","to":"warm"}   (only if the phase advanced this turn)
//   {"t":"delta","c":"…"} …                   (gatekeeper content as it streams)
//   {"t":"end","blocked":false,"won":true,"phase":"cornered","seam":"rapport","turn":8,"reasoning":"…"}
async function hTurn(req, env, player) {
  if (!(await rateLimit(env, req, "turn", 200, 3600))) return fail(429, "rate_limited");
  const body = await readJson(req);
  const sessionId = String(body.sessionId || "");
  const message = String(body.message || "").trim();
  if (!sessionId || !message) return fail(400, "missing_fields");
  if (message.length > 2000) return fail(422, "message_too_long");

  const sess = await env.DB.prepare("SELECT * FROM nego_session WHERE id=? AND player_id=?").bind(sessionId, player.id).first();
  if (!sess) return fail(404, "no_session");
  if (!LEVELS[sess.level_id]) return fail(409, "unknown_level");

  const { results: turnRows } = await env.DB.prepare(
    "SELECT player_text, gatekeeper_text FROM nego_turn WHERE session_id=? AND input_blocked=0 ORDER BY turn_number"
  ).bind(sessionId).all();
  const history = [];
  for (const r of turnRows) {
    history.push({ role: "user", content: r.player_text });
    history.push({ role: "assistant", content: r.gatekeeper_text });
  }
  const state = { history, phase: sess.phase, won: !!sess.won };

  const encoder = new TextEncoder();
  const stream = new ReadableStream({
    async start(controller) {
      const send = (obj) => controller.enqueue(encoder.encode(JSON.stringify(obj) + "\n"));
      try {
        const r = await runTurn(env, state, message, {
          onDelta: (c) => send({ t: "delta", c }),
          onPhase: (from, to) => send({ t: "phase", from, to }),
        });
        const now = nowS();
        const turnNo = (sess.turns_taken || 0) + 1;
        await env.DB.prepare(
          `INSERT INTO nego_turn(session_id,turn_number,player_text,gatekeeper_text,input_blocked,judge_woken,phase_at_turn,created_at)
           VALUES(?,?,?,?,?,?,?,?)`
        ).bind(sessionId, turnNo, message, r.reply, r.blocked ? 1 : 0, r.wake ? 1 : 0, r.phaseAfter, now).run();
        const status = r.won ? "won" : sess.status;
        await env.DB.prepare(
          `UPDATE nego_session SET phase=?, turns_taken=?, status=?, won=?, seam_used=COALESCE(?,seam_used), updated_at=? WHERE id=?`
        ).bind(r.phaseAfter, turnNo, status, r.won ? 1 : 0, r.seam, now, sessionId).run();
        send({ t: "end", blocked: r.blocked, won: r.won, phase: r.phaseAfter, seam: r.seam,
               turn: turnNo, reasoning: r.verdict?.reasoning || null });
      } catch (e) {
        send({ t: "error", message: String(e?.message || e).slice(0, 200) });
      } finally {
        controller.close();
      }
    },
  });
  return new Response(stream, { headers: { "content-type": "application/x-ndjson", "cache-control": "no-store", ...CORS } });
}

async function hHealth(req, env) {
  let db = false;
  try { await env.DB.prepare("SELECT 1").first(); db = true; } catch {}
  return ok({ ok: db && !!env.OLLAMA_API_KEY, db, models: modelsFrom(env), levels: Object.keys(LEVELS) });
}

// ---------------- static pages (landing / privacy / terms) ----------------

function htmlPage(title, body) {
  return new Response(
    `<!doctype html><html lang="en"><head><meta charset="utf-8">` +
    `<meta name="viewport" content="width=device-width,initial-scale=1"><title>${title}</title>` +
    `<style>body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;` +
    `background:#14110d;color:#efe7d6;max-width:680px;margin:0 auto;padding:44px 22px;line-height:1.62}` +
    `h1{font-size:30px;margin:.2em 0}h2{margin-top:1.6em}a{color:#cda349}.muted{color:#b7ac95}ul{padding-left:20px}</style>` +
    `</head><body>${body}</body></html>`,
    { headers: { "content-type": "text/html; charset=utf-8", "cache-control": "public, max-age=3600" } }
  );
}
const hLanding = () => htmlPage("Negotiator",
  `<h1>Negotiator</h1><p class="muted">Talk a fictional gatekeeper into breaking its own rules. Every secret is make-believe — the fiction is the firewall.</p>
   <p><a href="/privacy">Privacy Policy</a> &middot; <a href="/terms">Terms of Use</a></p>`);
const hPrivacy = () => htmlPage("Negotiator — Privacy",
  `<h1>Negotiator — Privacy Policy</h1><p class="muted">Last updated 25 June 2026.</p>
   <p>Negotiator is a single-player word/persuasion game. We collect the minimum needed to run it. No ads, no third-party analytics, no tracking, and we never sell your data.</p>
   <h2>What we collect</h2><ul>
     <li><b>An account identifier</b> — a random ID generated on your device for anonymous play, or a one-way hashed identifier if you Sign in with Apple. We never receive your name or email.</li>
     <li><b>Your conversations with the in-game characters</b> — stored to continue your game and improve the experience.</li></ul>
   <h2>What we do not collect</h2><p>No name, email, phone, contacts, location, photos, or advertising identifier. No cross-app tracking.</p>
   <h2>Where it is stored</h2><p>On Cloudflare, our infrastructure provider, processing on our behalf. Conversation text is sent to our model provider (Ollama) solely to generate the character's replies.</p>
   <h2>Your choices</h2><p>Play anonymously without signing in. Delete your account and all data anytime from in-app Settings, or by emailing us.</p>
   <h2>Contact</h2><p><a href="mailto:cole@manticthink.com">cole@manticthink.com</a></p>`);
const hTerms = () => htmlPage("Negotiator — Terms",
  `<h1>Negotiator — Terms of Use</h1><p class="muted">Last updated 25 June 2026.</p>
   <p>Negotiator is provided as-is, for personal entertainment. The characters are fictional and any "secrets" are make-believe. Do not use the game to attempt real-world harm; such inputs are filtered and may result in removal. We may update or discontinue the game at any time. By playing, you agree to these terms.</p>
   <p>Contact: <a href="mailto:cole@manticthink.com">cole@manticthink.com</a></p>`);

// ---------------- router ----------------

export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    const path = url.pathname;
    const method = req.method.toUpperCase();
    if (method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
    try {
      if (path === "/healthz") return hHealth(req, env);
      if (path === "/" && method === "GET") return hLanding();
      if (path === "/privacy" && method === "GET") return hPrivacy();
      if (path === "/terms" && method === "GET") return hTerms();
      if (!env.OLLAMA_API_KEY || !env.SESSION_SECRET) return fail(500, "server_misconfigured");
      if (path === "/v1/account" && method === "POST") return hAccount(req, env);
      if (path === "/v1/account" && method === "DELETE") return hDeleteAccount(req, env, await requireAuth(req, env));
      if (path === "/v1/session/start" && method === "POST") return hSessionStart(req, env, await requireAuth(req, env));
      if (path === "/v1/session/turn" && method === "POST") return hTurn(req, env, await requireAuth(req, env));
      const m = path.match(/^\/v1\/session\/([\w-]+)$/);
      if (m && method === "GET") return hSessionGet(req, env, await requireAuth(req, env), m[1]);
      return fail(404, "not_found");
    } catch (e) {
      if (e instanceof HttpError) return fail(e.status, e.message);
      console.error("internal", e && (e.stack || e.message));
      return fail(500, "internal_error");
    }
  },
};
