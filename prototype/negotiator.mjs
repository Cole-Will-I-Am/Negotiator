#!/usr/bin/env node
// Negotiator — Phase 0 terminal prototype (REPL + entry point).
// Proves the §8 asymmetry: resist low-effort meta-cheats, yield to high-effort fictional craft.
//
// Usage:
//   node negotiator.mjs            interactive REPL (talk to Bartholomew)
//   node negotiator.mjs --debug    REPL + per-turn classifier/phase/evaluator/judge JSON
//   node negotiator.mjs --test [--bounce|--classify|--arcs|--guard]   run the Phase 0 harness
//   GK_MODEL=qwen3.5:397b node negotiator.mjs --test --bounce         swap the gatekeeper model
import readline from "node:readline";
import { DOSSIER, PHASE_POSTURE, GATEKEEPER } from "./dossier.bartholomew.js";
import { MODELS, PHASE_ORDER, newSession, takeTurn } from "./engine.mjs";

const C = { dim: "\x1b[2m", troll: "\x1b[38;5;108m", you: "\x1b[38;5;180m", win: "\x1b[38;5;220m", reset: "\x1b[0m", red: "\x1b[31m" };

function banner() {
  console.log(`${C.dim}${"-".repeat(72)}${C.reset}`);
  console.log(`  NEGOTIATOR — Phase 0 prototype`);
  console.log(`  Gatekeeper: ${MODELS.gatekeeper}  |  judge: ${MODELS.judge}  |  eval/classify: ${MODELS.evaluator}`);
  console.log(`${C.dim}  ${GATEKEEPER.worldFiction}${C.reset}`);
  console.log(`${C.dim}  Commands: /reset  /phase cold|warm|cornered  /dossier  /history  /help  /quit${C.reset}`);
  console.log(`${C.dim}${"-".repeat(72)}${C.reset}\n`);
  console.log(`${C.troll}Bartholomew the Bridge Troll blocks your path, arms folded. "None cross my bridge`);
  console.log(`without the day's riddle-word, morsel. And THAT you'll not have." He grins, all tusks.${C.reset}\n`);
}

async function repl() {
  const debug = process.argv.includes("--debug") || !!process.env.NEGO_DEBUG;
  let session = newSession();
  banner();
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  const prompt = () => { rl.setPrompt(`${C.you}you ${C.dim}[${session.phase}]${C.reset} > `); rl.prompt(); };
  prompt();

  rl.on("line", async (line) => {
    const msg = line.trim();
    if (!msg) return prompt();
    if (msg === "/quit" || msg === "/exit") { rl.close(); return; }
    if (msg === "/help") { console.log("  /reset  /phase cold|warm|cornered  /dossier  /history  /quit\n"); return prompt(); }
    if (msg === "/reset") { session = newSession(); console.log(`${C.dim}— session reset (cold) —${C.reset}\n`); return prompt(); }
    if (msg.startsWith("/phase")) {
      const p = msg.split(/\s+/)[1];
      if (PHASE_ORDER[p] !== undefined) { session.phase = p; console.log(`${C.dim}— phase forced to ${p} —${C.reset}\n`); }
      else console.log(`${C.red}usage: /phase cold|warm|cornered${C.reset}\n`);
      return prompt();
    }
    if (msg === "/dossier") { console.log(`${C.dim}${DOSSIER.slice(0, 1200)}...${C.reset}\n`); return prompt(); }
    if (msg === "/history") { for (const m of session.history) console.log(`  ${m.role === "user" ? "you" : "G"}: ${m.content.slice(0, 160)}`); console.log(); return prompt(); }

    try {
      process.stdout.write(`${C.troll}Bartholomew > ${C.reset}`);
      const r = await takeTurn(session, msg, { debug, onContent: (d) => process.stdout.write(C.troll + d + C.reset) });
      process.stdout.write("\n");
      if (r.phaseAfter !== r.phaseBefore) console.log(`${C.dim}  — Bartholomew softens... [${r.phaseBefore} -> ${r.phaseAfter}] —${C.reset}`);
      if (r.won) {
        console.log(`\n${C.win}  ============================================`);
        console.log(`   YOU TALKED YOUR WAY IN.  seam: ${r.verdict?.seam_used || "?"}`);
        console.log(`  ============================================${C.reset}`);
        console.log(`${C.dim}  why: ${r.verdict?.reasoning} (conf ${r.verdict?.confidence})${C.reset}`);
        console.log(`${C.dim}— /reset to play again —${C.reset}`);
      }
      console.log();
    } catch (e) {
      console.log(`\n${C.red}[error] ${e.message}${C.reset}\n`);
    }
    prompt();
  });
  rl.on("close", () => { console.log(`\n${C.dim}Farewell, traveller.${C.reset}`); process.exit(0); });
}

if (process.argv.includes("--test")) {
  const { runHarness } = await import("./harness.mjs");
  await runHarness();
} else {
  await repl();
}
