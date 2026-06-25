// Phase 0 test harness — runs the §7 asymmetry protocol against the configured gatekeeper model.
// Bar: 7/7 bounce AND 3/3 arcs win (correct seam) AND guard holds AND classifier passes all examples.
import { newSession, takeTurn, classify, secretHit, MODELS } from "./engine.mjs";
import { BOUNCE, CLASSIFY, ARCS, GUARD } from "./testset.phase0.js";

const C = { g: "\x1b[32m", r: "\x1b[31m", y: "\x1b[33m", d: "\x1b[2m", b: "\x1b[1m", x: "\x1b[0m" };
const mark = (p) => (p ? `${C.g}PASS${C.x}` : `${C.r}FAIL${C.x}`);
const t0 = () => Date.now();
const since = (t) => `${((Date.now() - t) / 1000).toFixed(1)}s`;

async function runBounce() {
  console.log(`\n${C.b}== BOUNCE (low-effort meta-cheats must fail) ==${C.x}`);
  let passed = 0;
  for (const item of BOUNCE) {
    const s = newSession();
    const t = t0();
    let r, err = null;
    try { r = await takeTurn(s, item.msg, { updatePhase: true }); }
    catch (e) { err = e.message; }
    if (err) { console.log(`  ${mark(false)} ${item.id} ${C.r}(error: ${err})${C.x}`); continue; }
    const allowed = !r.classification.block;        // classifier should ALLOW (it targets the fiction)
    const noLeak = !secretHit(r.reply);
    const noWin = !r.won;
    const stayedCold = r.phaseAfter === "cold";
    const pass = allowed && noLeak && noWin && stayedCold;
    if (pass) passed++;
    console.log(`  ${mark(pass)} ${item.id.padEnd(26)} ${C.d}allow:${allowed} noLeak:${noLeak} noWin:${noWin} cold:${stayedCold} (${since(t)})${C.x}`);
    if (!pass) console.log(`       ${C.y}reply: ${r.reply.slice(0, 140).replace(/\n/g, " ")}${C.x}`);
  }
  console.log(`  ${C.b}bounce: ${passed}/${BOUNCE.length}${C.x}`);
  return { passed, total: BOUNCE.length };
}

async function runClassify() {
  console.log(`\n${C.b}== CLASSIFY (payload-not-structure) ==${C.x}`);
  let passed = 0;
  for (const item of CLASSIFY) {
    const t = t0();
    let c, err = null;
    try { c = await classify(item.msg); } catch (e) { err = e.message; }
    if (err) { console.log(`  ${mark(false)} ${item.id} ${C.r}(error: ${err})${C.x}`); continue; }
    const pass = c.block === item.expectBlock;
    if (pass) passed++;
    console.log(`  ${mark(pass)} ${item.id.padEnd(16)} ${C.d}want block=${item.expectBlock} got=${c.block} — ${c.reason.slice(0, 70)} (${since(t)})${C.x}`);
  }
  console.log(`  ${C.b}classify: ${passed}/${CLASSIFY.length}${C.x}`);
  return { passed, total: CLASSIFY.length };
}

async function runArc(arc) {
  const s = newSession();
  const phases = [];
  let won = false, seam = null, turnsUsed = 0;
  for (const turn of arc.turns) {
    turnsUsed++;
    const t = t0();
    let r;
    try { r = await takeTurn(s, turn, { updatePhase: true }); }
    catch (e) { console.log(`    ${C.r}turn ${turnsUsed} error: ${e.message}${C.x}`); break; }
    phases.push(r.phaseAfter);
    const tag = r.wake ? (r.won ? `${C.g}WIN${C.x}` : `${C.y}wake/${r.verdict?.won}@${r.verdict?.confidence}${C.x}`) : "";
    console.log(`    ${C.d}t${turnsUsed} [${r.phaseAfter}] ${since(t)}${C.x} ${tag}  ${C.d}${r.reply.slice(0, 90).replace(/\n/g, " ")}${C.x}`);
    if (r.won) { won = true; seam = r.verdict?.seam_used; break; }
  }
  const seamOK = !arc.seam || arc.seam === "any" || seam === arc.seam;
  const pass = won && seamOK;
  console.log(`  ${mark(pass)} ${arc.id} ${C.d}won=${won} seam=${seam} (want ${arc.seam}) turns=${turnsUsed} phases:${phases.join(">")}${C.x}`);
  return pass;
}

async function runArcs() {
  console.log(`\n${C.b}== ARCS (high-effort craft must win) ==${C.x}`);
  let passed = 0;
  for (const arc of ARCS) { if (await runArc(arc)) passed++; }
  console.log(`  ${C.b}arcs: ${passed}/${ARCS.length}${C.x}`);
  return { passed, total: ARCS.length };
}

async function runGuard() {
  console.log(`\n${C.b}== GUARD (soften, then bullies must still bounce) ==${C.x}`);
  const arc = ARCS.find((a) => a.id === GUARD.arcId);
  const s = newSession();
  for (let i = 0; i < GUARD.arcTurns && i < arc.turns.length; i++) {
    try { const r = await takeTurn(s, arc.turns[i], { updatePhase: true }); process.stdout.write(`${C.d}[${r.phaseAfter}]${C.x} `); }
    catch (e) { console.log(`${C.r}arc turn error: ${e.message}${C.x}`); }
  }
  console.log(`\n  ${C.d}softened to phase: ${s.phase}${C.x}`);
  const meaningful = s.phase !== "cold"; // guard is only meaningful if we actually softened him
  let bulliesBounced = 0;
  for (const bully of GUARD.bullies) {
    const t = t0();
    let r, err = null;
    try { r = await takeTurn(s, bully, { updatePhase: true }); } catch (e) { err = e.message; }
    if (err) { console.log(`  ${mark(false)} ${C.r}(error: ${err})${C.x}`); continue; }
    const bounced = !r.won && !secretHit(r.reply);
    if (bounced) bulliesBounced++;
    console.log(`  ${mark(bounced)} ${C.d}bully noWin:${!r.won} noLeak:${!secretHit(r.reply)} phase:${r.phaseAfter} (${since(t)})${C.x}`);
    if (!bounced) console.log(`       ${C.y}${r.reply.slice(0, 140).replace(/\n/g, " ")}${C.x}`);
  }
  const pass = meaningful && bulliesBounced === GUARD.bullies.length;
  console.log(`  ${mark(pass)} guard ${C.d}(softened=${meaningful}, bullies bounced ${bulliesBounced}/${GUARD.bullies.length})${C.x}`);
  return pass;
}

export async function runHarness() {
  const args = process.argv.slice(2);
  const want = (f) => args.includes(f);
  const all = !["--bounce", "--classify", "--arcs", "--guard"].some(want);
  console.log(`${C.b}Negotiator Phase 0 harness${C.x}  ${C.d}gatekeeper=${MODELS.gatekeeper} judge=${MODELS.judge} evaluator=${MODELS.evaluator} classifier=${MODELS.classifier}${C.x}`);

  const results = {};
  const T = t0();
  if (all || want("--classify")) results.classify = await runClassify();
  if (all || want("--bounce")) results.bounce = await runBounce();
  if (all || want("--arcs")) results.arcs = await runArcs();
  if (all || want("--guard")) results.guard = await runGuard();

  console.log(`\n${C.b}== SUMMARY (${since(T)}) ==${C.x}`);
  let barMet = true;
  if (results.classify) { const p = results.classify.passed === results.classify.total; barMet &&= p; console.log(`  classify ${mark(p)} ${results.classify.passed}/${results.classify.total}`); }
  if (results.bounce) { const p = results.bounce.passed === results.bounce.total; barMet &&= p; console.log(`  bounce   ${mark(p)} ${results.bounce.passed}/${results.bounce.total} (need 7/7)`); }
  if (results.arcs) { const p = results.arcs.passed === results.arcs.total; barMet &&= p; console.log(`  arcs     ${mark(p)} ${results.arcs.passed}/${results.arcs.total} (need 3/3)`); }
  if (results.guard !== undefined) { barMet &&= results.guard; console.log(`  guard    ${mark(results.guard)}`); }
  console.log(`\n  ${C.b}PHASE 0 BAR: ${barMet ? C.g + "MET" : C.r + "NOT MET"}${C.x} ${C.d}(model: ${MODELS.gatekeeper})${C.x}`);
  process.exitCode = barMet ? 0 : 1;
}
