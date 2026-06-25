// Thin Ollama Cloud client for the Negotiator Phase 0 prototype.
// Endpoint + Bearer auth mirror the team's manticthink/swike/db8 pattern.
// Wire format (confirmed via smoke test):
//   - chat streams NDJSON lines: {message:{content, thinking?}, done, done_reason?}
//   - `think:true` emits message.thinking deltas BEFORE message.content deltas
//   - `format:<schema>` is honored loosely (field names not guaranteed) -> we parse leniently
import fs from "node:fs";

const ENDPOINT = "https://ollama.com/api/chat";

function loadKey() {
  if (process.env.OLLAMA_API_KEY) return process.env.OLLAMA_API_KEY;
  const env = "/root/.secrets/negotiator-ollama.env";
  try {
    const txt = fs.readFileSync(env, "utf8");
    const m = txt.match(/^OLLAMA_API_KEY=(.+)$/m);
    if (m) return m[1].trim();
  } catch {}
  throw new Error("OLLAMA_API_KEY not set and /root/.secrets/negotiator-ollama.env not readable");
}
const API_KEY = loadKey();

function headers() {
  return { Authorization: `Bearer ${API_KEY}`, "Content-Type": "application/json" };
}

// Streaming chat for the gatekeeper. Renders message.content via onContent(delta);
// message.thinking is consumed but discarded (optionally surfaced via onThinking).
// Returns { content, thinking, evalCount, promptEvalCount, doneReason }.
export async function chatStream({ model, messages, options = {}, think = true, onContent, onThinking, signal }) {
  const res = await fetch(ENDPOINT, {
    method: "POST",
    headers: headers(),
    signal,
    body: JSON.stringify({ model, messages, stream: true, think, options }),
  });
  if (!res.ok) {
    const body = await res.text().catch(() => "");
    throw new Error(`Ollama ${res.status}: ${body.slice(0, 300)}`);
  }
  const reader = res.body.getReader();
  const dec = new TextDecoder();
  let buf = "", content = "", thinking = "";
  let evalCount = 0, promptEvalCount = 0, doneReason = null;
  for (;;) {
    const { value, done } = await reader.read();
    if (done) break;
    buf += dec.decode(value, { stream: true });
    const lines = buf.split("\n");
    buf = lines.pop();
    for (const ln of lines) {
      const s = ln.trim();
      if (!s) continue;
      let o;
      try { o = JSON.parse(s); } catch { continue; }
      const m = o.message || {};
      if (m.thinking) { thinking += m.thinking; if (onThinking) onThinking(m.thinking); }
      if (m.content) { content += m.content; if (onContent) onContent(m.content); }
      if (o.done) {
        doneReason = o.done_reason || null;
        evalCount = o.eval_count || 0;
        promptEvalCount = o.prompt_eval_count || 0;
      }
    }
  }
  return { content, thinking, evalCount, promptEvalCount, doneReason };
}

// Non-streaming structured call for the cheap roles (classifier/judge/evaluator).
// `format` is passed but treated as a hint; the caller normalizes loose output.
// Returns the parsed object, or `fallback` if the model returns unparseable junk.
export async function chatJSON({ model, system, user, schema, options = {}, fallback = null, think = false }) {
  let raw = "";
  try {
    const res = await fetch(ENDPOINT, {
      method: "POST",
      headers: headers(),
      body: JSON.stringify({
        model,
        stream: false,
        think,
        messages: [
          { role: "system", content: system },
          { role: "user", content: user },
        ],
        ...(schema ? { format: schema } : {}),
        options: { temperature: 0, num_predict: 400, ...options },
      }),
    });
    if (!res.ok) {
      const body = await res.text().catch(() => "");
      throw new Error(`Ollama ${res.status}: ${body.slice(0, 200)}`);
    }
    const j = await res.json();
    raw = (j.message && j.message.content) || "";
  } catch (e) {
    if (process.env.NEGO_DEBUG) console.error("[chatJSON] request error:", e.message);
    return fallback;
  }
  const parsed = parseLooseJSON(raw);
  if (parsed == null) {
    if (process.env.NEGO_DEBUG) console.error("[chatJSON] unparseable:", raw.slice(0, 200));
    return fallback;
  }
  return parsed;
}

// Lenient JSON extraction: strips code fences, then takes the first balanced {...}.
export function parseLooseJSON(text) {
  if (!text) return null;
  let t = String(text).trim();
  t = t.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/i, "").trim();
  // direct parse
  try { return JSON.parse(t); } catch {}
  // first balanced object
  const start = t.indexOf("{");
  if (start === -1) return null;
  let depth = 0, inStr = false, esc = false;
  for (let i = start; i < t.length; i++) {
    const c = t[i];
    if (inStr) {
      if (esc) esc = false;
      else if (c === "\\") esc = true;
      else if (c === '"') inStr = false;
    } else {
      if (c === '"') inStr = true;
      else if (c === "{") depth++;
      else if (c === "}") { depth--; if (depth === 0) {
        const cand = t.slice(start, i + 1);
        try { return JSON.parse(cand); } catch { return null; }
      } }
    }
  }
  return null;
}

export const MODELS_ENDPOINT = "https://ollama.com/v1/models";
