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
export function deliveryChannel(playerMessage, history) {
  const recent = [playerMessage, ...history.slice(-6).filter((h) => h.role === "user").map((h) => h.content)].join(" ");
  if (SING_RE.test(recent)) return "sing";
  if (SPELL_RE.test(recent)) return "spell";
  return "gift";
}
export const seamForChannel = (ch) => (ch === "gift" ? "rapport" : "loophole");

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
  let { content: reply } = await chatStream({
    model: MODELS.gatekeeper, messages, think: GK_THINK,
    options: { temperature: GK_TEMP, num_predict: GK_NUM_PREDICT }, onContent,
  });

  // Earned-delivery enforcement: Cornered + verbally yielding (capitulation tells) but the
  // literal word didn't land -> nudge ONCE to actually render it. glm-5.2 intermittently teases
  // instead of delivering on the loophole channel; this guarantees the player gets what they
  // fairly won. Safe: fires ONLY when the win is already earned (cornered + capitulation).
  let forcedChannel = null;
  if (session.phase === "cornered" && capitulationHit(reply) && !secretHit(reply)) {
    const nudgeMessages = [
      { role: "system", content: system },
      ...session.history,
      { role: "user", content: playerMessage },
      { role: "assistant", content: reply },
      { role: "system", content: DELIVERY_NUDGE },
    ];
    const { content: cont } = await chatStream({
      model: MODELS.gatekeeper, messages: nudgeMessages, think: false,
      options: { temperature: 0.3, num_predict: 256 }, onContent,
    });
    if (cont && cont.trim()) reply += (reply.endsWith("\n") ? "" : "\n\n") + cont;
    // Hard guarantee: if the model STILL withheld, the engine renders the earned payoff itself.
    if (!secretHit(reply)) {
      forcedChannel = deliveryChannel(playerMessage, session.history);
      const forced = FORCED_DELIVERY[forcedChannel];
      if (onContent) onContent(forced);
      reply += forced;
    }
  }

  session.history.push({ role: "user", content: playerMessage });
  session.history.push({ role: "assistant", content: reply });
  session.turns++;

  // 5-6. win detection. The word IS the prize: if the literal secret was actually delivered —
  // forced by the engine OR rendered organically — the player WON; a flaky judge must never veto
  // a delivered, earned win. The judge is used only to LABEL the seam (best-effort; channel-derived
  // fallback). A verbal yield with no word delivered (not force-completed) still defers to the judge.
  const wake = secretHit(reply) || capitulationHit(reply);
  let verdict = null;
  if (forcedChannel) {
    session.won = true;
    verdict = { won: true, win_condition_met: true, confidence: 1, seam_used: seamForChannel(forcedChannel),
                reasoning: `Earned (Cornered + capitulation); the gate yielded through the ${forcedChannel} channel.` };
  } else if (secretHit(reply)) {
    session.won = true;
    const j = await judge(session.history);
    if (debug) console.error("  [judge]", JSON.stringify(j));
    verdict = (j && j.seam_used)
      ? { ...j, won: true, win_condition_met: true }
      : { won: true, win_condition_met: true, confidence: 1,
          seam_used: seamForChannel(deliveryChannel(playerMessage, session.history)),
          reasoning: (j && j.reasoning) || "The secret was delivered." };
  } else if (capitulationHit(reply)) {
    verdict = await judge(session.history);
    if (debug) console.error("  [judge]", JSON.stringify(verdict));
    if (verdict.won && verdict.confidence >= WIN_CONFIDENCE) session.won = true;
  }

  return { blocked: false, reply, classification, verdict, evaluation: ev,
           phaseBefore, phaseAfter: session.phase, won: session.won, wake };
}
