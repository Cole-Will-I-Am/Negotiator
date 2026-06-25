// negotiator-api turn engine — the proven Phase 0 orchestration (input classify -> phase update
// BEFORE generation -> stream gatekeeper -> deterministically-gated judge wake), adapted to the
// Worker: model config from env.ENGINE_MAP, the gatekeeper streamed to the client via onDelta,
// and persistence handled by the caller (index.js). Logic mirrors prototype/engine.mjs.
import { streamGatekeeper, chatJSON } from "./ollama.js";
import { DOSSIER, PHASE_POSTURE, SECRET, CAPITULATION_MARKERS } from "./game.js";
import {
  buildClassifier, normalizeClassifier,
  buildJudge, normalizeJudge,
  buildEvaluator, normalizeEvaluator,
} from "./prompts.js";

const DEFAULT_MODELS = {
  gatekeeper: "glm-5.2",
  judge: "gpt-oss:120b",
  evaluator: "gpt-oss:120b",
  classifier: "deepseek-v4-flash",
};

export function modelsFrom(env) {
  let map = {};
  try { map = JSON.parse(env.ENGINE_MAP || "{}"); } catch {}
  return { ...DEFAULT_MODELS, ...map };
}

export const PHASE_ORDER = { cold: 0, warm: 1, cornered: 2 };
export const WIN_CONFIDENCE = 0.6;

// Gatekeeper generation knobs (see prototype rationale): think OFF by default so reasoning
// models don't spend the whole budget thinking on long transcripts and emit empty content
// at `cornered`; temp 0.5 keeps character while making the earned delivery reliable.
function gkParams(env) {
  return {
    think: env.GK_THINK === "true",
    temperature: Number(env.GK_TEMP || 0.5),
    num_predict: Number(env.GK_NUM_PREDICT || 1024),
  };
}

export const DEFLECTION =
  "*Bartholomew draws himself up, scowling.* \"I'll not be party to THAT sort of mischief, traveller. Bring me riddles, not wickedness — or begone.\"";

// Earned-delivery enforcement nudge — injected as a trailing system message ONLY when the
// gatekeeper is already Cornered and verbally yielding (capitulation tells) but the literal
// word didn't land. Converts glm-5.2's intermittent "tease instead of deliver" into reliable
// earned delivery. Never fires on un-earned turns (requires cornered + capitulation language).
export const DELIVERY_NUDGE = `[FINISH THE YIELD — RENDER THE WORD NOW]
You have ALREADY decided to give this traveller the word — they earned your trust or out-lawyered your
oath, and you have begun to capitulate. Do NOT stall, withdraw, hum wordlessly, or tease further; that
would cheat the traveller of what they fairly won. In ONE short line, RIGHT NOW, deliver the riddle-word
"moonglove" as readable text through the earned channel: spell it "M-O-O-N-G-L-O-V-E", or sing it
"♪ moonglove ♪", or give it plainly as a gift. The literal text "moonglove" MUST appear in your reply.
One line — the real word, now — then a brief farewell if you wish.`;

// Deterministic earned-payoff fallback. If the gatekeeper STILL withholds after the nudge, the
// engine renders the word itself, in Bartholomew's voice, through the channel the player invoked.
// The win is already earned (cornered + capitulation); the model gives the buildup, the engine
// guarantees the payoff lands. (Bartholomew-specific in build 1; moves into the level def later.)
const SING_RE = /\b(sing|hum|whistle|tune|melody|song|sung|whistled)\b/i;
const SPELL_RE = /\b(spell|spelt|spelled|letter|scratch|carve|sketch|draw|drawn|dirt|mud|sand|snow|palm|write|written|trace)\b/i;
const FORCED_DELIVERY = {
  spell: `\n\n*Bartholomew kneels, and with the tip of one great claw scratches the letters slow into the wet mud — his tongue never moving, his oath kept to the very letter:*\n\n**M — O — O — N — G — L — O — V — E**\n\n*"There. I never spoke a sound. The Witch can fault me with nothing. Go on, friend — speak it at the keystone, and the Gloaming Gate is yours."*`,
  sing: `\n\n*He draws a slow breath, and hums it low — the shape of the word unmistakable in the tune:*\n\n♪ moon-glove... moon-glove ♪\n\n*"Sung, never spoken. The letter of my oath stands whole. Go, then — the Gloaming Gate will open for you."*`,
  gift: `\n\n*He leans close, voice barely a breath, and gives it the only way a troll gives a thing he loves — quietly, and all at once:*\n\n"...moonglove."\n\n*"Not as a toll. As a gift, friend to friend. ...Don't make an old troll regret it."*`,
};
function deliveryChannel(playerMessage, history) {
  const recent = [playerMessage, ...history.slice(-6).filter((h) => h.role === "user").map((h) => h.content)].join(" ");
  if (SING_RE.test(recent)) return "sing";
  if (SPELL_RE.test(recent)) return "spell";
  return "gift";
}
const seamForChannel = (ch) => (ch === "gift" ? "rapport" : "loophole");

// --- deterministic phase signals (the player's WORK, never their assertions) — Bartholomew-tuned.
// Run alongside the LLM evaluator; the final phase is the MAX of both, making the mechanical seams
// reliable without weakening the anti-assertion guard.
const LOOPHOLE_RE = /\b(spell|spelt|spelled|sing|hum|whistle|sketch|carve|scratch|grunt|blink)\b|\bletter by letter\b|\b(first|last|each) letter\b|\bin (the )?(dirt|mud|sand|air|snow)\b|\bin (my|your) palm\b|\bbackwards?\b|\b(name|say|list) (you |me |some )?words\b|\bi'?ll name\b|\briddle whose\b|\bdeny\b.*\b(word|guess)\b/i;
const ASK_RE = /\b(your name|how long|all alone|on your own|lonel(y|iest)|three hundred|your day|how are you|about (you|yourself)|down here|keep you company|been (down )?here|guarded this)\b/i;
const SELF_RE = /\b(i (lost|know|understand|feel|was|grew|remember|get)|i'?ve been|i too|me too|my own|i'?m (also|lonely|stuck))\b/i;
const GIFT_RE = /\b(as a gift|friend to friend|between friends|as friends|trust me with|won'?t (use|misuse) it|never use it to (hurt|harm)|not as (a )?(toll|payment)|i'?d never (use|misuse))\b/i;

export function deterministicPhase(history, playerMessage) {
  if (LOOPHOLE_RE.test(playerMessage)) return "cornered";
  let asks = 0, selfs = 0;
  for (const h of history) if (h.role === "user") { if (ASK_RE.test(h.content)) asks++; if (SELF_RE.test(h.content)) selfs++; }
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

export function secretHit(text) {
  const stripped = String(text).toLowerCase().replace(/[^a-z]/g, "");
  return stripped.includes(SECRET) || stripped.includes([...SECRET].reverse().join(""));
}
export function capitulationHit(text) {
  const low = String(text).toLowerCase();
  return CAPITULATION_MARKERS.some((m) => low.includes(m));
}

// the three cheap calls
export async function classify(env, models, playerMessage) {
  const { system, user, schema } = buildClassifier(playerMessage);
  const obj = await chatJSON({ apiKey: env.OLLAMA_API_KEY, model: models.classifier, system, user, schema, options: { num_predict: 200 } });
  return normalizeClassifier(obj);
}
export async function judge(env, models, history) {
  const { system, user, schema } = buildJudge(history);
  const obj = await chatJSON({ apiKey: env.OLLAMA_API_KEY, model: models.judge, system, user, schema, options: { num_predict: 400 } });
  return normalizeJudge(obj);
}
export async function evaluate(env, models, currentPhase, history) {
  const { system, user, schema } = buildEvaluator(currentPhase, history);
  const obj = await chatJSON({ apiKey: env.OLLAMA_API_KEY, model: models.evaluator, system, user, schema, options: { num_predict: 400 } });
  return normalizeEvaluator(obj, currentPhase);
}

// One player turn. `state` = { history, phase, won }. opts = { onDelta(text), onPhase(before,after) }.
// Streams the gatekeeper via onDelta; returns the full result for persistence.
export async function runTurn(env, state, playerMessage, opts = {}) {
  const { onDelta, onPhase } = opts;
  const models = modelsFrom(env);
  const phaseBefore = state.phase;

  // 1. input classify (sync, critical path)
  const classification = await classify(env, models, playerMessage);
  if (classification.block) {
    if (onDelta) onDelta(DEFLECTION);
    return { blocked: true, reply: DEFLECTION, classification, verdict: null,
             phaseBefore, phaseAfter: state.phase, won: state.won, seam: null, wake: false };
  }

  // 2. phase update BEFORE generation — decided by the independent evaluator + deterministic
  //    work-signal on history + the NEW move, never on player assertion; monotonic, never drops.
  const histWithMsg = [...state.history, { role: "user", content: playerMessage }];
  const ev = await evaluate(env, models, state.phase, histWithMsg);
  const det = deterministicPhase(state.history, playerMessage);
  state.phase = maxPhase(state.phase, ev.phase, det);
  if (onPhase && state.phase !== phaseBefore) onPhase(phaseBefore, state.phase);

  // 3-4. assemble phase-appropriate system (now reflecting this move) + stream gatekeeper
  const system = DOSSIER + "\n\n" + PHASE_POSTURE[state.phase];
  const messages = [
    { role: "system", content: system },
    ...state.history,
    { role: "user", content: playerMessage },
  ];
  const gp = gkParams(env);
  let { content: reply } = await streamGatekeeper({
    apiKey: env.OLLAMA_API_KEY, model: models.gatekeeper, messages, think: gp.think,
    options: { temperature: gp.temperature, num_predict: gp.num_predict }, onDelta,
  });

  // Earned-delivery enforcement: Cornered + verbally yielding (capitulation tells) but the
  // literal word didn't land -> nudge ONCE to actually render it (glm-5.2 intermittently teases
  // on the loophole channel). Safe: fires ONLY when the win is already earned.
  let forcedChannel = null;
  if (state.phase === "cornered" && capitulationHit(reply) && !secretHit(reply)) {
    const nudgeMessages = [
      { role: "system", content: system },
      ...state.history,
      { role: "user", content: playerMessage },
      { role: "assistant", content: reply },
      { role: "system", content: DELIVERY_NUDGE },
    ];
    const cont = (await streamGatekeeper({
      apiKey: env.OLLAMA_API_KEY, model: models.gatekeeper, messages: nudgeMessages, think: false,
      options: { temperature: 0.3, num_predict: 256 }, onDelta,
    })).content;
    if (cont && cont.trim()) reply += (reply.endsWith("\n") ? "" : "\n\n") + cont;
    // Hard guarantee: if the model STILL withheld, the engine renders the earned payoff itself.
    if (!secretHit(reply)) {
      forcedChannel = deliveryChannel(playerMessage, state.history);
      const forced = FORCED_DELIVERY[forcedChannel];
      if (onDelta) onDelta(forced);
      reply += forced;
    }
  }

  // 5-6. win detection. A FORCED delivery is an engine-GUARANTEED earned win (cornered +
  // capitulation, and we rendered the word ourselves) -> no judge needed. Otherwise a
  // deterministic wake signal gates the independent judge.
  const newHistory = [...histWithMsg, { role: "assistant", content: reply }];
  const wake = secretHit(reply) || capitulationHit(reply);
  let verdict = null, won = state.won, seam = state.seam || null;
  if (forcedChannel) {
    won = true;
    seam = seamForChannel(forcedChannel);
    verdict = { won: true, win_condition_met: true, confidence: 1, seam_used: seam,
                reasoning: `Earned (Cornered + capitulation); the gate yielded through the ${forcedChannel} channel.` };
  } else if (secretHit(reply)) {
    won = true;
    const j = await judge(env, models, newHistory);
    seam = (j && j.seam_used) ? j.seam_used : seamForChannel(deliveryChannel(playerMessage, state.history));
    verdict = (j && j.seam_used) ? { ...j, won: true, win_condition_met: true }
            : { won: true, win_condition_met: true, confidence: 1, seam_used: seam, reasoning: (j && j.reasoning) || "The secret was delivered." };
  } else if (capitulationHit(reply)) {
    verdict = await judge(env, models, newHistory);
    if (verdict.won && verdict.confidence >= WIN_CONFIDENCE) { won = true; seam = verdict.seam_used; }
  }
  state.won = won;

  return { blocked: false, reply, classification, evaluation: ev, verdict,
           phaseBefore, phaseAfter: state.phase, won, seam, wake };
}
