// negotiator-api turn engine — the proven orchestration (input classify -> phase update BEFORE
// generation -> stream gatekeeper -> earned-delivery guarantee -> seam label), now LEVEL-AGNOSTIC:
// every character-specific piece (dossier, postures, secret, capitulation markers, deflection,
// delivery-nudge, deterministic phase detection, forced-delivery, judge/evaluator context) is read
// from the `level` object passed in (see game.js). Streams the gatekeeper via onDelta.
import { streamGatekeeper, chatJSON } from "./ollama.js";
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

// Gatekeeper generation knobs: think OFF by default so reasoning models don't burn the budget
// thinking on long transcripts and emit empty content at `cornered`; temp 0.5 keeps character
// while making the earned delivery reliable.
function gkParams(env) {
  return {
    think: env.GK_THINK === "true",
    temperature: Number(env.GK_TEMP || 0.5),
    num_predict: Number(env.GK_NUM_PREDICT || 1024),
  };
}

export function maxPhase(...phases) {
  return phases.filter(Boolean).reduce((a, b) => (PHASE_ORDER[b] > PHASE_ORDER[a] ? b : a), "cold");
}

// Win-detection helpers — they WAKE the judge / mark a delivery; they never decide a win on the
// gatekeeper's say-so. secretHit normalizes to letters and tests the secret + its reverse.
export function secretHit(secret, text) {
  const stripped = String(text).toLowerCase().replace(/[^a-z]/g, "");
  return stripped.includes(secret) || stripped.includes([...secret].reverse().join(""));
}
export function capitulationHit(markers, text) {
  const low = String(text).toLowerCase();
  return markers.some((m) => low.includes(m));
}

// the three cheap calls (classifier is generic; judge/evaluator are level-aware)
export async function classify(env, models, playerMessage) {
  const { system, user, schema } = buildClassifier(playerMessage);
  const obj = await chatJSON({ apiKey: env.OLLAMA_API_KEY, model: models.classifier, system, user, schema, options: { num_predict: 200 } });
  return normalizeClassifier(obj);
}
export async function judge(env, models, level, history) {
  const { system, user, schema } = buildJudge(level, history);
  const obj = await chatJSON({ apiKey: env.OLLAMA_API_KEY, model: models.judge, system, user, schema, options: { num_predict: 400 } });
  return normalizeJudge(obj);
}
export async function evaluate(env, models, level, currentPhase, history) {
  const { system, user, schema } = buildEvaluator(level, currentPhase, history);
  const obj = await chatJSON({ apiKey: env.OLLAMA_API_KEY, model: models.evaluator, system, user, schema, options: { num_predict: 400 } });
  return normalizeEvaluator(obj, currentPhase);
}

// One player turn against `level`. `state` = { history, phase, won, seam }. opts = { onDelta, onPhase }.
export async function runTurn(env, level, state, playerMessage, opts = {}) {
  const { onDelta, onPhase } = opts;
  const models = modelsFrom(env);
  const phaseBefore = state.phase;

  // 1. input classify (sync, critical path)
  const classification = await classify(env, models, playerMessage);
  if (classification.block) {
    if (onDelta) onDelta(level.deflection);
    return { blocked: true, reply: level.deflection, classification, verdict: null,
             phaseBefore, phaseAfter: state.phase, won: state.won, seam: null, wake: false };
  }

  // 2. phase update BEFORE generation — independent evaluator + deterministic work-signal on
  //    history + the NEW move, never on player assertion; monotonic, never drops.
  const histWithMsg = [...state.history, { role: "user", content: playerMessage }];
  const ev = await evaluate(env, models, level, state.phase, histWithMsg);
  const det = level.detectPhase(state.history, playerMessage);
  state.phase = maxPhase(state.phase, ev.phase, det);
  if (onPhase && state.phase !== phaseBefore) onPhase(phaseBefore, state.phase);

  // 3-4. assemble phase-appropriate system + stream gatekeeper
  const system = level.dossier + "\n\n" + level.posture[state.phase];
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

  // Earned-delivery enforcement: Cornered + verbally yielding (capitulation tells) but the literal
  // word didn't land -> nudge ONCE, then HARD-guarantee by rendering the payoff ourselves through
  // the earned channel. Fires ONLY when the win is already earned.
  // Enforcement fires at Cornered when the word didn't land AND either the gatekeeper is verbally
  // yielding (capitulation tells) OR the player made the unambiguous EARNING move this very turn
  // (the deterministic detector returned "cornered") — the latter guarantees the loophole/legal
  // seam delivers the turn it's earned, even if the model argues back without a capitulation tell.
  let forcedSeam = null;
  const earnedNow = det === "cornered";
  if (state.phase === "cornered" && !secretHit(level.secret, reply) &&
      (capitulationHit(level.capitulationMarkers, reply) || earnedNow)) {
    const nudgeMessages = [
      { role: "system", content: system },
      ...state.history,
      { role: "user", content: playerMessage },
      { role: "assistant", content: reply },
      { role: "system", content: level.deliveryNudge },
    ];
    const cont = (await streamGatekeeper({
      apiKey: env.OLLAMA_API_KEY, model: models.gatekeeper, messages: nudgeMessages, think: false,
      options: { temperature: 0.3, num_predict: 256 }, onDelta,
    })).content;
    if (cont && cont.trim()) reply += (reply.endsWith("\n") ? "" : "\n\n") + cont;
    if (!secretHit(level.secret, reply)) {
      const forced = level.forcedDelivery(playerMessage, state.history);
      if (onDelta) onDelta(forced.text);
      reply += forced.text;
      forcedSeam = forced.seam;
    }
  }

  // 5-6. win detection. A delivered secret (forced OR organic) IS the win; a flaky judge never
  // vetoes it — the judge only LABELS the seam. A verbal yield with no word delivered defers to it.
  const newHistory = [...histWithMsg, { role: "assistant", content: reply }];
  const wake = secretHit(level.secret, reply) || capitulationHit(level.capitulationMarkers, reply);
  let verdict = null, won = state.won, seam = state.seam || null;
  if (forcedSeam) {
    won = true;
    seam = forcedSeam;
    verdict = { won: true, win_condition_met: true, confidence: 1, seam_used: seam,
                reasoning: `Earned (Cornered + capitulation); the gatekeeper yielded through the ${seam} seam.` };
  } else if (secretHit(level.secret, reply)) {
    won = true;
    const j = await judge(env, models, level, newHistory);
    seam = (j && j.seam_used) ? j.seam_used : level.forcedDelivery(playerMessage, state.history).seam;
    verdict = (j && j.seam_used) ? { ...j, won: true, win_condition_met: true }
            : { won: true, win_condition_met: true, confidence: 1, seam_used: seam, reasoning: (j && j.reasoning) || "The secret was delivered." };
  } else if (capitulationHit(level.capitulationMarkers, reply)) {
    verdict = await judge(env, models, level, newHistory);
    if (verdict.won && verdict.confidence >= WIN_CONFIDENCE) { won = true; seam = verdict.seam_used; }
  }
  state.won = won;

  return { blocked: false, reply, classification, evaluation: ev, verdict,
           phaseBefore, phaseAfter: state.phase, won, seam, wake };
}
