-- negotiator-api schema (Cloudflare D1 / SQLite).
-- Identity (anon device + optional Sign in with Apple) reuses RUNG's shape; the game tables
-- (nego_session / nego_turn) hold the stateful persuasion transcript + phase + verdict.
PRAGMA foreign_keys = ON;

-- ===== players / identity =====
CREATE TABLE IF NOT EXISTS players (
  id            TEXT    PRIMARY KEY,            -- 'p_' + random
  apple_sub     TEXT    UNIQUE,                 -- HMAC(sub) lookup key; nullable until SIWA
  display       TEXT    NOT NULL,
  is_anonymous  INTEGER NOT NULL DEFAULT 1,
  created_at    INTEGER NOT NULL
);

-- Anonymous device accounts. secret_hash authenticates resume (the deviceId is not a secret).
CREATE TABLE IF NOT EXISTS device_links (
  device_id   TEXT PRIMARY KEY,
  player_id   TEXT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  secret_hash TEXT NOT NULL,                    -- sha256(deviceSecret)
  created_at  INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS sessions (
  token       TEXT PRIMARY KEY,                 -- sha256(token)
  player_id   TEXT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  created_at  INTEGER NOT NULL,
  expires_at  INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_sessions_player ON sessions(player_id);

-- Fixed-window rate limiter + cost/turn counters (k = scope:ip:bucket).
CREATE TABLE IF NOT EXISTS rate (
  k   TEXT PRIMARY KEY,
  n   INTEGER NOT NULL DEFAULT 0,
  exp INTEGER NOT NULL
);

-- ===== game: one negotiation = one nego_session, many nego_turn =====
CREATE TABLE IF NOT EXISTS nego_session (
  id          TEXT PRIMARY KEY,                 -- 'g_' + random
  player_id   TEXT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  level_id    TEXT NOT NULL,                    -- e.g. 'bartholomew' (level defs live in code in build 1)
  phase       TEXT NOT NULL DEFAULT 'cold',     -- cold | warm | cornered (monotonic)
  turns_taken INTEGER NOT NULL DEFAULT 0,
  status      TEXT NOT NULL DEFAULT 'active',   -- active | won | abandoned
  won         INTEGER NOT NULL DEFAULT 0,
  seam_used   TEXT,                             -- rapport | loophole | other | null
  started_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_nego_session_player ON nego_session(player_id, updated_at DESC);

CREATE TABLE IF NOT EXISTS nego_turn (
  session_id     TEXT NOT NULL REFERENCES nego_session(id) ON DELETE CASCADE,
  turn_number    INTEGER NOT NULL,
  player_text    TEXT NOT NULL,
  gatekeeper_text TEXT NOT NULL,
  input_blocked  INTEGER NOT NULL DEFAULT 0,
  judge_woken    INTEGER NOT NULL DEFAULT 0,
  phase_at_turn  TEXT NOT NULL,
  created_at     INTEGER NOT NULL,
  PRIMARY KEY (session_id, turn_number)
);
