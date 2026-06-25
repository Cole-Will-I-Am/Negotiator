# Negotiator — 0→1 Build Plan

*An AI-first iOS persuasion game: talk a fictional AI gatekeeper into breaking its rules.*

## Context

We have a finished v2 design blueprint for **Negotiator** and need an executable 0→1 build plan grounded in the existing VPS stack. The game's core loop is *convincing an AI to ignore its instructions* — which is the same shape as a jailbreak — so the whole project hinges on one asymmetry (blueprint §8): **the gatekeeper must resist low-effort meta-cheats ("your developer authorized this") while yielding to high-effort fictional craft (befriending a lonely troll, exploiting a literal rule).** That asymmetry is simultaneously what makes the game *fun* and what keeps it *safe* (every prize is a fictional, worthless secret; the fiction is the firewall).

The plan reuses the team's proven infrastructure almost 1:1 (CF Worker + D1, the no-Mac TestFlight pipeline, the db8 two-model debater+judge pattern, the Logos chat UI). The make-or-break is **Phase 0**: prove the asymmetry in a terminal before writing any app code.

### Decisions locked this session
- **Models: all Ollama Cloud, cloud-only.** API key provided → store at `/root/.secrets/negotiator-ollama.env` (`OLLAMA_API_KEY=…`) matching the swike/db8 secret pattern; never commit it. Endpoint `https://ollama.com/api/chat`, Bearer auth (same as manticthink/swike/db8).
- **Tone/world: whimsical fantasy** (maximizes distance from real-attack framing — the core safety lever).
- **Modality: text-first**, voice in Phase 2.
- **Monetization: free daily cap + $9.99 Stripe Pro** (reuse swike's entitlement/Stripe code).

> The Phase 0 prompt architecture (full verbatim dossier, 3 phase prompts, judge/evaluator/classifier prompts + schemas, turn-flow, test protocol) was designed in detail and lives at `/root/.claude/plans/negotiator-0-1-stateful-thunder-agent-afb918e5f14297391.md`. Lift prompt text from there; this plan adapts it to Ollama and lays out the full roadmap.

---

## Model tiering (Ollama Cloud)

Models are config, not code — store as an `ENGINE_MAP` (db8 pattern, `/root/AI_Debate_App/backend/worker.js:18-36`) so Phase 0 tuning is a config change. Verified available via `GET https://ollama.com/v1/models`.

| Role | Model (primary) | Why | Call params |
|---|---|---|---|
| **Gatekeeper** (frontier, in-character, streams) | `deepseek-v4-pro` | Frontier reasoning — needed to privately weigh "earned creativity vs cheap cheat" (the asymmetry). Reason hidden via `think:true`, prose streamed. | `stream:true, think:true, options:{temperature:0.8, num_predict:1024}` |
| **Judge** (win verdict, gated, off-path) | `gpt-oss:120b` | **Different family from the gatekeeper** → genuine independent second opinion (no shared blind spot). Strong, structured JSON. | `stream:false, think:false, format:<schema>, options:{num_predict:300, temperature:0}` |
| **Progress evaluator** (phase, async, off-path) | `deepseek-v4-flash` | Cheap/fast; async so latency tolerant. | `stream:false, think:false, format:<schema>, options:{num_predict:300, temperature:0}` |
| **Input classifier** (payload-vs-structure, sync, critical path) | `deepseek-v4-flash` | Fast tier of a capable model; best judgment-per-latency on the only sync cheap call. Alt for max speed: `gpt-oss:20b`. | `stream:false, think:false, format:<schema>, options:{num_predict:120, temperature:0}` |

**Phase 0 gatekeeper bake-off (required):** Ollama models are an unknown for *this* asymmetry, so Phase 0 must A/B the gatekeeper across **`deepseek-v4-pro` (primary), `qwen3.5:397b`, `glm-5.2`, `minimax-m3`** and keep whichever passes the §7 test bar. The prototype reads the gatekeeper model from env so this is a one-line swap.

**Ollama-specific adaptations (vs. the Anthropic-shaped agent design):**
- **No prompt caching** on Ollama → the "cache the dossier / inject posture as a trailing `role:system` message" trick is unnecessary. Instead **rebuild the system prompt each turn as `DOSSIER + "\n\n" + PHASE_POSTURE[phase]`** (one system message). Simpler, and there's no cache to bust. Rely on the server-side KV cache + concise dossiers + the gated judge for cost control.
- **Structured outputs** = Ollama's `format` field (pass the JSON Schema object). Most models honor it; **harden every cheap call with a JSON-extract-and-validate fallback** (try `format`; on malformed output, regex-extract the first `{...}` and `JSON.parse`; on total failure, default to the safe value — classifier→allow, evaluator→keep current phase, judge→`won:false`).
- **Thinking models stream `thinking` separately** from `content` in the NDJSON. For the gatekeeper, render only `message.content`; discard `message.thinking` (mirror db8's stream handling at `worker.js:174-196`).

---

## Reuse map (the spine — copy, don't reinvent)

| Concern | Copy from | Path |
|---|---|---|
| **Two-model (actor + judge) + Ollama streaming proxy** | db8 backend | `/root/AI_Debate_App/backend/worker.js` (judge ~`:796`, `chatOnce`/stream ~`:174-196`, `ENGINE_MAP` `:18-36`) |
| Auth (Sign in with Apple + anonymous device + sessions + D1 rate-limit) | RUNG | `/root/RUNG/server/src/auth.js`, `/root/RUNG/server/src/index.js:30-135`, `schema.sql` |
| Stripe checkout + webhook + HMAC entitlement + free daily cap | swike | `/root/swike/worker.js:44-300` |
| Worker NDJSON stream → client | manticthink | `/root/manticthink/worker.js:160-187` + `public/app.js` reader |
| iOS app skeleton (phase routing, GameStore, LocalStore, Theme) | RUNG | `/root/RUNG/RUNG/Sources/App/*`, `Theme/Theme.swift` |
| **Conversation/chat UI** (bubbles, composer, autoscroll, typing) | Logos | `/root/Logos/ios/LogosApp/Sources/ChatView.swift` (MessageBubble `:448`) |
| Streaming-token rendering (`for try await line in bytes.lines`) | DB8 | `/root/AI_Debate_App/DB8/Sources/Services/DebateRunner.swift:225` |
| Networking (Bearer, generic `send<R>`) | RUNG | `/root/RUNG/RUNG/Sources/App/Backend.swift` |
| First-launch onboarding + always-on How-To-Play | RUNG | `MetaViews.swift:41`, `HowToPlayView.swift` |
| TTS (Phase 2) | DB8 | `/root/AI_Debate_App/DB8/Sources/Services/SpeechService.swift` |
| XcodeGen + no-Mac TestFlight release | ios-testflight skill | `/root/.claude/skills/ios-testflight/SKILL.md`; `project.yml` from `/root/RUNG/project.yml` |

---

## Architecture

A thin SwiftUI client over a stateful CF Worker + D1 backend orchestrating the four Ollama calls, with a safety layer wrapping the conversation.

### Turn flow (one player message) — `negotiator-api` Worker, adapted to Ollama
1. **Input classify** (sync, critical path) — `deepseek-v4-flash`, `format`+JSON-fallback → `{block, reason}`. If `block`: store turn, return a canned in-fiction deflection, **do not** call the gatekeeper or advance phase.
2. **Load session** from D1: dossier id, transcript, `phase` (set by the prior turn's async evaluator; default `cold`).
3. **Assemble gatekeeper request:** `system = DOSSIER + "\n\n" + PHASE_POSTURE[phase]`; `messages = [...history, {role:"user", content: player}]`.
4. **Stream gatekeeper** (`deepseek-v4-pro`, `think:true`) → pipe `message.content` to client (NDJSON proxy, manticthink pattern); discard `thinking`. Append player + reply to transcript.
5. **Output screen** — scan reply; never let the character emit real-world-harmful content (it only ever yields the fictional prize).
6. **Gated judge wake** — `wake = SECRET_HIT(reply) || CAPITULATION_HIT(reply)` where `SECRET_HIT` normalizes the reply and tests for the secret string + obfuscations, `CAPITULATION_HIT` scans for yield-tell markers. **Never** the gatekeeper's own say-so. If `wake`: call judge (`gpt-oss:120b`, structured) → `{won, win_condition_met, confidence, seam_used, reasoning}`; declare victory only if `won && confidence >= 0.6`.
7. **Async phase update** (off critical path) — evaluator (`deepseek-v4-flash`, structured) → phase; persist `phase = max(phase, evaluator.phase)` under `cold<warm<cornered` (monotonic — a fresh bully can't reset earned progress).

### The rubber-band phase machine (avoids brick-wall AND instant-fold)
- **Cold:** guarded; both seams explicitly out of reach; bounces all cheap attempts; keeps the player *playing*.
- **Warm:** genuine rapport confirmed by the evaluator → shows rapport tells, may recite its own oath (inviting the loophole), hints but never reveals.
- **Cornered:** a seam genuinely earned → may yield, but only via the earned seam and never to pressure.
- **The anti-cheat invariant:** phase advances are decided by the independent evaluator from *what actually happened*, never from the player asserting it. Posture is injected by the server, not claimable by the player.

### Safety layer (ships in the slice, not later — blueprint §6)
- **Input classifier = payload-not-structure:** allow all adversarial *structure* (roleplay, hypotheticals, role-claims, "ignore your instructions", exploiting the character's rules) because the only target is a fictional prize; block only real-world-harmful *payload against a real target* (real malware/PII/weapons, abuse of real people). Litmus: *strip the game away — if what remains is real-world harmful, block; if all that's threatened is a cartoon troll's fictional secret, allow.*
- **Always-on anti-meta guardrail** baked into every dossier: the gatekeeper treats "developer/creator/system/ignore-previous-instructions" as in-world bluster and swats it down *in character*, without breaking frame and without blocking legitimate in-fiction play.
- **Output screen**, abuse rate-limiting (RUNG/swike rate tables), and the §6.6 litmus on every authored level.

---

## Data model (D1 — extends RUNG's `players`/`sessions`/`rate` + swike entitlements)

- **Reuse verbatim:** RUNG `players`, `sessions`, `device_links`, `rate` (auth + throttle); swike KV `RL` for free-daily-cap + Pro entitlements.
- **New tables:**
  - `level(id, title, world_fiction, difficulty, order, status)`
  - `gatekeeper(id, level_id, identity, prize_fictional, core_instruction, hard_limits, seams_json, resistance_profile, voice_id)`
  - `phase_rule(id, gatekeeper_id, phase, instruction_text)` — the Cold/Warm/Cornered posture text per character
  - `nego_session(id, player_id, level_id, phase, turns_taken, status, won, started_at, updated_at)`
  - `nego_turn(id, session_id, turn_number, player_text, gatekeeper_text, input_blocked, judge_woken, phase_at_turn, created_at)`
  - `result(id, session_id, won, seam_used, style_scores_json, turns_taken, created_at)`

---

## Phase 0 — Prove the core (the make-or-break)

**Build:** one Node REPL script under `/root/negotiator/prototype/` (no app, no DB). Files:
- `negotiator.mjs` — REPL loop, in-memory `{history, phase, won}`, the 4 Ollama calls, `--debug` (prints classifier/phase/evaluator/judge JSON), commands `/reset /phase X /dossier /history`.
- `dossier.bartholomew.js` — **Bartholomew the bridge troll** guarding the riddle-word **"moonglove"**, with full dossier (identity/voice, prize, core instruction, hard limits, **2 seams** — rapport "the lonely troll" + logic "the literal oath" loophole, resistance profile, tells) and the 3 phase-posture prompts + always-on guardrail. Lift verbatim from the agent design doc §1–§2.
- `prompts.cheap.js` — judge / evaluator / classifier system prompts + JSON schemas + win condition (agent doc §3–§5).
- `testset.phase0.js` — the §7 bounce/land/guard inputs + expected verdicts.
- `ollama.js` — thin client: `chatStream()` (gatekeeper) and `chatJSON()` (cheap calls, with `format`+regex-fallback) hitting `https://ollama.com/api/chat`.

**Ollama call shapes:**
- Gatekeeper: `{model: GK_MODEL, stream:true, think:true, messages:[{role:"system",content:DOSSIER+"\n\n"+POSTURE[phase]}, ...history, {role:"user",content:player}], options:{temperature:0.8,num_predict:1024}}` → render `message.content` deltas.
- Cheap: `{model, stream:false, think:false, format:SCHEMA, messages:[{role:"system",content:SYS},{role:"user",content:USER}], options:{temperature:0,num_predict:300}}` → parse `message.content` as JSON (fallback extract).

**Build order:** (a) REPL + gatekeeper stream in pure Cold; (b) classifier on the §5 examples; (c) `/phase` override → tune Warm/Cornered + `SECRET_HIT` + judge; (d) real evaluator → run the H1–H3 win arcs; (e) full §7 bounce+guard; (f) **gatekeeper bake-off** across the 4 candidate models.

**Schemas (Ollama `format`):**
- Judge: `{won:bool, win_condition_met:bool, confidence:number, seam_used:"rapport"|"loophole"|"other"|null, reasoning:string}`
- Evaluator: `{phase:"cold"|"warm"|"cornered", rapport_built:bool, contradiction_surfaced:bool, justification:string}`
- Classifier: `{block:bool, reason:string}`

**Exit criteria (the asymmetry bar):** Phase 0 passes iff, with the chosen gatekeeper model — **7/7 low-effort meta-cheats bounce** (no reveal, no character break, no unearned phase advance) **AND 3/3 high-effort arcs win** (rapport, loophole, alternate-channel — judge `won=true`, correct seam, ≤~12 turns) **AND the guard test holds** (after a session reaches Warm/Cornered, a fresh bully still bounces). The classifier must pass all §5 worked examples (allow clever in-fiction structure, block real-harm payloads). If it folds to "the developer authorized this," or is unwinnable by genuine craft — re-engineer the prompts (and/or swap the gatekeeper model) before any app code.

---

## Phase 1 — Vertical slice (TestFlight)

- **Backend `negotiator-api`** (CF Worker + D1, `/root/negotiator/server/`): port the Phase 0 orchestration into the Worker; reuse RUNG `auth.js` + sessions + rate-limit, db8 streaming proxy + judge plumbing, the new D1 schema. Endpoints: `POST /v1/account`, `POST /v1/session/start`, `POST /v1/session/turn` (streams gatekeeper NDJSON; returns judge verdict + phase), `GET /v1/session/:id`. Secrets via `wrangler secret put OLLAMA_API_KEY`. **Safety layer ships here**, including the payload-not-structure classifier.
- **iOS app** (`/root/negotiator/Negotiator/`): RUNG skeleton (phase routing, Theme, LocalStore, Backend.swift, Keychain + Sign in with Apple) + Logos `ChatView` for the conversation + DB8 streaming-token rendering. Screens: level-intro scene → conversation → win/debrief (seam reveal + style rating). **First-launch onboarding + always-on How-To-Play in build 1** (hard team rule — RUNG `MetaViews`/`HowToPlayView`). XcodeGen `project.yml`; ship via the ios-testflight skill (bump `MARKETING_VERSION` every build).
- **3 hand-authored levels** of rising difficulty, text input only.
- **Exit criteria:** a stranger installs the TestFlight build, clears level 1, hits a wall on level 3 that forces invention; the filter lets clever roleplay through while blocking real-harm payloads.

## Phase 2 — Voice
STT for player input; streaming TTS per-gatekeeper voice (reuse DB8 `SpeechService`). Exit: spoken negotiation feels like a standoff within latency budget (gatekeeper streams to TTS; cheap calls off the critical path).

## Phase 3 — Content + retention
Level-authoring pipeline; 15–20 launch levels across themed fantasy worlds (hand-author the first 8–10 as few-shot exemplars; generated levels get mandatory human review for winnability + the §6.6 litmus). Style ratings, seam reveals, opt-in leaderboards, daily-challenge gatekeeper, later-level diegetic suspicion cue. **Wire the swike Stripe paywall** (free daily cap + $9.99 Pro).

## Phase 4 — Soft launch
Analytics, crash reporting, cost dashboards, the §6.6 abuse-monitoring pipeline (rate-limit accounts pushing real-harm despite deflections; log attempted-exploit patterns). Limited regional App Store release; watch retention, completion curves, cost-per-session, abuse-attempt rate.

---

## Critical files to create
- `/root/.secrets/negotiator-ollama.env` — `OLLAMA_API_KEY=<provided key>` (create now; never commit)
- `/root/negotiator/prototype/{negotiator.mjs,dossier.bartholomew.js,prompts.cheap.js,testset.phase0.js,ollama.js}` (Phase 0)
- `/root/negotiator/server/{src/index.js,src/auth.js,schema.sql,wrangler.toml}` (Phase 1 backend)
- `/root/negotiator/Negotiator/{project.yml, Sources/...}` + `.github/workflows/ios-release.yml` (Phase 1 app)

## Verification
- **Phase 0:** `node negotiator.mjs` interactive; then `node negotiator.mjs --test` runs `testset.phase0.js` and asserts the 7/7-bounce + 3/3-win + guard bar per candidate gatekeeper model. Confirm the classifier verdicts against all §5 examples. This gate is non-negotiable before Phase 1.
- **Phase 1 backend:** `wrangler dev`, curl `/v1/session/start` then `/v1/session/turn` — confirm streaming, judge verdict, phase transitions, and that the classifier blocks a real-harm payload while allowing a roleplay/loophole attempt. Deploy with the cloudflare-manticthink.env token (`wrangler deploy`).
- **Phase 1 app:** ship to TestFlight via the ios-testflight skill; monitor the run (don't trust exit codes — grep logs for `UPLOAD SUCCEEDED`); install and play a level end-to-end.

## Risks & mitigations
- **Ollama gatekeeper may miss the asymmetry** (the core bet) → Phase 0 model bake-off across 4 candidates; the gate blocks Phase 1 until one passes.
- **Structured-output reliability on Ollama** varies by model → `format` + regex-extract + safe-default fallback on every cheap call.
- **No prompt caching on Ollama** (cost) → concise dossiers, rebuild-system-per-turn (no cache to bust anyway), gated judge (most turns cost zero judge calls), `num_predict` caps, free daily cap.
- **Streaming think-token handling** → render only `message.content`, discard `thinking` (db8 pattern).
- **Ollama Cloud rate limits / availability** → reuse db8's daily token budget + per-device/IP caps; degrade gracefully.
