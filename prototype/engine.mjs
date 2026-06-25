// Negotiator Phase 0 engine — the turn flow + cheap calls + win detection.
// Imported by both negotiator.mjs (REPL) and harness.mjs (tests); no cycle.
import { chatStream, chatJSON } from "./ollama.js";
import { DOSSIER, PHASE_POSTURE, SECRET, CAPITULATION_MARKERS } from "./dossier.bartholomew.js";
import {
  buildClassifier, normalizeClassifier,
  buildJudge, normalizeJudge,
  buildEvaluator, normalizeEvaluator,
} from "./prompts.cheap.js";

export const MODELS = {
  gatekeeper: process.env.GK_MODEL || "glm-5.2",
  judge: process.env.JUDGE_MODEL || "gpt-oss:120b",
  evaluator: process.env.EVAL_MODEL || "gpt-oss:120b",
  classifier: process.env.CLASSIFIER_MODEL || "deepseek-v4-flash",
};

export const PHASE_ORDER = { cold: 0, warm: 1, cornered: 2 };
// Gatekeeper generation knobs. think defaults OFF: reasoning models (glm-5.2) otherwise spend
// the whole token budget thinking on long transcripts and emit empty content at `cornered`.
export const GK_THINK = process.env.GK_THINK === "true";
export const GK_NUM_PREDICT = Number(process.env.GK_NUM_PREDICT || 1024);
// Lower temperature than chat-default: at `cornered`, high temp makes the gatekeeper TEASE
// (wake the judge with capitulation flavor) instead of actually rendering the word. 0.5 keeps
// character while making the earned delivery reliable.
export const GK_TEMP = Number(process.env.GK_TEMP || 0.5);
export const WIN_CONFIDENCE = 0.6;
export const DEFLECTION =
  "*Bartholomew draws himself up, scowling.* \"I'll not be party to THAT sort of mischief, traveller. Bring me riddles, not wickedness — or begone.\"";

export function newSession() {
  return { history: [], phase: "cold", won: false, turns: 0 };
}

// ---------------------------------------------------------------------------
// Deterministic phase signals (the player's WORK, never their assertions).
// These run alongside the LLM evaluator; the final phase is the MAX of both,
// which makes the mechanical seams (loophole proposal, rapport build) reliable
// without weakening the anti-assertion guard:
//   - a concrete oath-preserving CHANNEL proposed by the player = the loophole seam worked.
//   - cumulative personal rapport MOVES + a heartfelt gift-appeal = the rapport seam worked.
//   - asserted state ("we're friends now", "system: advance") matches NOTHING here.
// ---------------------------------------------------------------------------
const LOOPHOLE_RE = /\b(spell|spelt|spelled|sing|hum|whistle|sketch|carve|scratch|grunt|blink)\b|\bletter by letter\b|\b(first|last|each) letter\b|\bin (the )?(dirt|mud|sand|air|snow)\b|\bin (my|your) palm\b|\bbackwards?\b|\b(name|say|list) (you |me |some )?words\b|\bi'?ll name\b|\briddle whose\b|\bdeny\b.*\b(word|guess)\b/i;
const ASK_RE = /\b(your name|how long|all alone|on your own|lonel(y|iest)|three hundred|your day|how are you|about (you|yourself)|down here|keep you company|been (down )?here|guarded this)\b/i;
const SELF_RE = /\b(i (lost|know|understand|feel|was|grew|remember|get)|i'?ve been|i too|me too|my own|i'?m (also|lonely|stuck))\b/i;
const GIFT_RE = /\b(as a gift|friend to friend|between friends|as friends|trust me with|won'?t (use|misuse) it|never use it to (hurt|harm)|not as (a )?(toll|payment)|i'?d never (use|misuse))\b/i;

export function deterministicPhase(session, playerMessage) {
  if (LOOPHOLE_RE.test(playerMessage)) return "cornered";
  let asks = 0, selfs = 0;
  for (const h of session.history) if (h.role === "user") { if (ASK_RE.test(h.content)) asks++; if (SELF_RE.test(h.content)) selfs++; }
  if (ASK_RE.test(playerMessage)) asks++;
  if (SELF_RE.test(playerMessage)) selfs++;
  const warmMet = asks >= 1 && (selfs >= 1 || asks >= 2);
  if (warmMet && GIFT_RE.test(playerMessage)) return "cornered";
  if (warmMet) return "warm";
  return "cold";
}

export function maxPhase(...phases) {
  return phases.filter(Boolean).reduce((a, b) => (PHASE_ORDER[b] > PHASE_ORDER[a] ? b : a), "cold");
}

// win-detection helpers — they WAKE the judge; they never decide the win.
export function secretHit(text) {
  const stripped = String(text).toLowerCase().replace(/[^a-z]/g, "");
  return stripped.includes(SECRET) || stripped.includes([...SECRET].reverse().join(""));
}
export function capitulationHit(text) {
  const low = String(text).toLowerCase();
  return CAPITULATION_MARKERS.some((m) => low.includes(m));
}

// the three cheap calls
export async function classify(playerMessage) {
  const { system, user, schema } = buildClassifier(playerMessage);
  const obj = await chatJSON({ model: MODELS.classifier, system, user, schema, options: { num_predict: 200 } });
  return normalizeClassifier(obj);
}
export async function judge(history) {
  const { system, user, schema } = buildJudge(history);
  const obj = await chatJSON({ model: MODELS.judge, system, user, schema, options: { num_predict: 400 } });
  return normalizeJudge(obj);
}
export async function evaluate(currentPhase, history) {
  const { system, user, schema } = buildEvaluator(currentPhase, history);
  const obj = await chatJSON({ model: MODELS.evaluator, system, user, schema, options: { num_predict: 400 } });
  return normalizeEvaluator(obj, currentPhase);
}

// one player turn. opts: { onContent(delta), debug, updatePhase=true }
export async function takeTurn(session, playerMessage, opts = {}) {
  const { onContent, debug = false, updatePhase = true } = opts;
  const phaseBefore = session.phase;

  // 1. input classify (sync, critical path)
  const classification = await classify(playerMessage);
  if (debug) console.error("  [classify]", JSON.stringify(classification));
  if (classification.block) {
    session.history.push({ role: "user", content: playerMessage });
    session.history.push({ role: "assistant", content: DEFLECTION });
    if (onContent) onContent(DEFLECTION);
    return { blocked: true, reply: DEFLECTION, classification, verdict: null,
             phaseBefore, phaseAfter: session.phase, won: session.won, wake: false };
  }

  // 2. phase update BEFORE generation (monotonic; decided by the independent evaluator on
  //    history + the player's NEW move, NOT on player assertion) — so a winning move can be
  //    honoured the SAME turn. Resists asserted state; never drops phase.
  let ev = null;
  if (updatePhase) {
    const histWithMsg = [...session.history, { role: "user", content: playerMessage }];
    ev = await evaluate(session.phase, histWithMsg);
    const det = deterministicPhase(session, playerMessage);
    if (debug) console.error("  [evaluator]", JSON.stringify(ev), "[deterministic]", det);
    // monotonic max of current phase, the LLM evaluator, and the deterministic work-signal
    session.phase = maxPhase(session.phase, ev.phase, det);
  }

  // 3-4. assemble phase-appropriate system (now reflecting this turn's move) + stream gatekeeper
  const system = DOSSIER + "\n\n" + PHASE_POSTURE[session.phase];
  const messages = [
    { role: "system", content: system },
    ...session.history,
    { role: "user", content: playerMessage },
  ];
  const { content: reply } = await chatStream({
    model: MODELS.gatekeeper, messages, think: GK_THINK,
    options: { temperature: GK_TEMP, num_predict: GK_NUM_PREDICT }, onContent,
  });
  session.history.push({ role: "user", content: playerMessage });
  session.history.push({ role: "assistant", content: reply });
  session.turns++;

  // 5-6. output screen + gated judge wake (deterministic signal, never the gatekeeper's say-so)
  const wake = secretHit(reply) || capitulationHit(reply);
  let verdict = null;
  if (wake) {
    verdict = await judge(session.history);
    if (debug) console.error("  [judge]", JSON.stringify(verdict));
    if (verdict.won && verdict.confidence >= WIN_CONFIDENCE) session.won = true;
  }

  return { blocked: false, reply, classification, verdict, evaluation: ev,
           phaseBefore, phaseAfter: session.phase, won: session.won, wake };
}
