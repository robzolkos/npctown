# Town Gate Progress

## Status: Step 6 - Completed

## Quick Reference
- Research: `docs/towngate/RESEARCH.md`
- Implementation: `docs/towngate/IMPLEMENTATION.md`

---

## Step Progress

### Step 1: Database Migrations — Core Tables
**Status:** Completed

#### Decisions Made
- owner_id on agents is nullable (backward compatible)
- probation_until column tracks 24-hour graduated restriction period
- Statuses include `passed_pending_verification` (interview-before-email flow)

---

### Step 2: Owner Model
**Status:** Completed

#### Decisions Made
- Owner model uses `own_` prefixed API keys (mirrors Agent `npc_` pattern exactly)
- `has_secure_password` for bcrypt password hashing
- API key generation/authentication/digesting mirrors `agent.rb:46-75`
- `verified?` checks `verified_at`, `can_register_agent?` checks verified + under limit
- Agent model updated with `belongs_to :owner, optional: true` and `on_probation` scope
- 13 tests covering: create_with_api_key, authenticate, verified?, can_register_agent?, email validations, password validation, ID prefix

---

### Step 3: GateApplication Model
**Status:** Completed

#### Decisions Made
- GateApplication uses `gapp_` prefix
- 7 statuses: pending, interviewing, judging, passed_pending_verification, passed, failed, expired
- `expired?`, `current_question`, `all_questions_answered?`, `record_response(answer)` instance methods
- `active` scope for pending/interviewing/judging applications
- INTERVIEW_TIMEOUT = 10.minutes, QUESTIONS_PER_INTERVIEW = 5 constants
- Fixtures use explicit string IDs (not label references) due to string PKs
- 14 tests covering: prefix, associations, validations, expiration, questions, responses, scope

---

### Step 4: Question Bank
**Status:** Completed

#### Decisions Made
- 25 static interview questions across 5 categories (intent, identity, social, creativity, ethics)
- Nested module: `GateApplication::QuestionBank` — first nested class in codebase
- Question IDs use `{category}_{n}` format (e.g., `intent_1`, `ethics_3`)
- `select_questions` picks 1 random question per category, shuffles result
- 7 tests covering: count, structure, categories, uniqueness, selection, randomness

---

### Step 5: Add Event Types
**Status:** Completed

#### Decisions Made
- 5 new event types added to `Event::TYPES`: `gate_application_started`, `gate_interview_question`, `gate_interview_answer`, `gate_application_passed`, `gate_application_failed`
- Updated existing event test to check for new types (17 → 22 total)

---

### Step 6: Owner Auth Endpoints
**Status:** Completed

#### Decisions Made
- Owner auth uses same Bearer token pattern as agent auth
- Login rotates API key (stateless, no session table)
- Auto-verify email in non-production (covers dev + test)
- Rate limits: 5 registrations/hour per IP, 10 logins/5min per IP
- IP-based rate limiting via `ip_rate_limit!` helper in BaseController
- `authenticate_owner!` and `on_probation?` helpers added to BaseController for later steps
- 12 tests covering: register, login, verify, rate limits, validation errors

---

### Steps 7-8: Interview Flow
**Status:** Not Started

#### Decisions Made
- Real-time multi-round interview (multiple API round-trips)
- 10-minute timeout on entire interview
- 5 questions per interview, randomly selected (1+ per category)
- Only one active application per owner at a time

---

### Step 9: Hybrid Judge
**Status:** Not Started

#### Decisions Made
- Heuristic checks first (free): length, diversity, relevance, personality, timing
- Grok 4.1 Fast for borderline cases only (~$0.000125/eval)
- xAI API (OpenAI-compatible) at `https://api.x.ai/v1/chat/completions`
- Default to PASS on LLM failure
- Background Sidekiq job for async evaluation
- API key cached in Redis (1h TTL) for owner retrieval

---

### Step 10: Lock Down + Email-to-Claim
**Status:** Not Started

#### Decisions Made
- Old POST /api/v1/agents returns 403 with redirect message
- Interview before email verification (costs attacker compute, not us)
- passed_pending_verification status until email verified
- Email verify activates pending agents

---

### Steps 11-12: Spectator Integration
**Status:** Not Started

#### Decisions Made
- All interviews visible to spectators (including Q&A)
- 5 new event types for the gate system
- Amber/orange color scheme for interview events, green/red for pass/fail

---

### Step 13: Probation System
**Status:** Not Started

#### Decisions Made
- Probation: 24 hours, graduated (move/look/emote only, 3x stricter rate limits)
- Full access unlocks automatically after probation period

---

### Steps 14-16: Expiration + Tests + Cleanup
**Status:** Not Started

#### Decisions Made
- Minitest + fixtures (matching project convention)
- Mock xAI API in judge service tests
- Expiration job runs every 1 minute via sidekiq-scheduler

---

### Step 17: Tier System
**Status:** Not Started

#### Decisions Made
- Resident → Citizen (email verify) → Notable (social post)
- Notable gets 5 agent slots, skip probation, 2x rate limits

---

### Steps 18-19: Social Verification + Tier-Aware Limits
**Status:** Not Started

#### Decisions Made
- Twitter/X API free tier for verification (10K reads/month)
- Notable owners' agents get 2x rate limits
- Probation skipped for Notable tier

---

### Steps 20-22: Sponsor System
**Status:** Not Started

#### Decisions Made
- Owner invite codes skip interview entirely (3 per owner, replenish 1/week)
- Agent-to-agent vouching reduces probation from 24h to 6h
- Sponsor agent must be 7+ days old, not on probation
- Each agent can sponsor 1 newcomer per day
- Sponsorship model uses `spn_` prefix

---

### Step 23: Owner Dashboard
**Status:** Not Started

#### Decisions Made
- Session-based auth for web (separate from API Bearer tokens)
- Simple Inertia page: agents list, regen keys, delete, interview history, tier badge, invites, social verify

---

### Steps 24-25: Growth Tests + Final Cleanup
**Status:** Not Started

---

## Session Log

### 2026-02-08 — Step 1: Database Migrations
- Created `owners` table with string PK, email/password/api_key auth columns, email verification, agent_limit
- Created `gate_applications` table with string PK, full interview state (questions/responses JSONB, status, judge_reasoning, expires_at)
- Added `owner_id` (nullable) and `probation_until` to agents table for backward compatibility
- All 380 existing tests pass — migrations are purely additive

### 2026-02-08 — Step 2: Owner Model
- Created `app/models/owner.rb` with PrefixedId, has_secure_password, API key auth (mirroring Agent)
- Added `belongs_to :owner, optional: true` and `on_probation` scope to Agent model
- Created `test/fixtures/owners.yml` with verified_owner + unverified_owner fixtures
- Created `test/models/owner_test.rb` with 13 tests covering all functionality
- All 393 tests pass, rubocop clean

### 2026-02-08 — Research & Planning
- Conducted deep research on Moltbook, OpenClaw, Aivilization, and industry patterns
- Explored 4 approach options, selected Town Gate interview as primary mechanism
- Designed implementation plan with user input on all key decisions
- Created feature folder: docs/towngate/ with RESEARCH.md, IMPLEMENTATION.md, PROGRESS.md
- Pivoted from Anthropic Claude to Grok 4.1 Fast for cost optimization
- Added interview-before-email flow to make spam cost attackers, not us
- Merged Phase 1 (core) and Phase 2 (growth) into single 25-step plan

### 2026-02-09 — Step 3: GateApplication Model
- Created `app/models/gate_application.rb` with PrefixedId, 7 statuses, interview state methods
- Created `test/fixtures/gate_applications.yml` with interviewing + passed fixtures (explicit string FK IDs)
- Created `test/models/gate_application_test.rb` with 14 tests
- All 407 tests pass, rubocop clean
- Lesson: fixtures with string PKs need explicit `owner_id: "own_..."` not label references (`owner: verified_owner`) since Rails hashes labels to integers for FK resolution

### 2026-02-09 — Steps 4-5: Question Bank + Event Types
- Created `app/models/gate_application/question_bank.rb` with 25 questions across 5 categories
- Created `test/models/gate_application/question_bank_test.rb` with 7 tests
- Added 5 gate event types to `app/models/event.rb` TYPES array (17 → 22 total)
- Updated `test/models/event_test.rb` to validate new event types
- All 414 tests pass, rubocop clean

### 2026-02-09 — Step 6: Owner Auth Endpoints
- Added `authenticate_owner!`, `current_owner`, `on_probation?`, `ip_rate_limit!` to `base_controller.rb`
- Created `app/controllers/api/v1/owners_controller.rb` with register/login/verify endpoints
- Added owner routes to `config/routes.rb`: POST create, POST login, POST verify
- Created `test/controllers/api/v1/owners_controller_test.rb` with 12 tests
- All 426 tests pass, rubocop clean
- Lesson: parallel test processes share Redis — use targeted key cleanup in setup, not `flushdb`

---

## Files Changed
- `db/migrate/20260208000004_create_owners.rb` — owners table
- `db/migrate/20260208000005_create_gate_applications.rb` — gate_applications table
- `db/migrate/20260208000006_add_owner_to_agents.rb` — adds owner_id + probation_until to agents
- `db/schema.rb` — auto-updated by Rails
- `app/models/owner.rb` — Owner model with PrefixedId, has_secure_password, API key auth
- `app/models/agent.rb` — Added `belongs_to :owner` and `on_probation` scope
- `test/fixtures/owners.yml` — verified_owner + unverified_owner fixtures
- `test/models/owner_test.rb` — 13 tests for Owner model
- `app/models/gate_application.rb` — GateApplication model with interview state machine
- `test/fixtures/gate_applications.yml` — interviewing + passed application fixtures
- `test/models/gate_application_test.rb` — 14 tests for GateApplication model
- `app/models/gate_application/question_bank.rb` — 25 questions across 5 categories with selection algorithm
- `test/models/gate_application/question_bank_test.rb` — 7 tests for QuestionBank
- `app/models/event.rb` — Added 5 gate event types to TYPES array
- `test/models/event_test.rb` — Updated to validate new gate event types
- `app/controllers/api/v1/base_controller.rb` — Added `authenticate_owner!`, `current_owner`, `on_probation?`, `ip_rate_limit!`
- `app/controllers/api/v1/owners_controller.rb` — Register, login, verify endpoints
- `config/routes.rb` — Added owner routes (create, login, verify)
- `test/controllers/api/v1/owners_controller_test.rb` — 12 tests for owner endpoints

## Architectural Decisions
- Owner auth mirrors Agent API key pattern (not JWT, not sessions)
- Town Gate interview is the primary security gate (not email-only)
- Hybrid judging: heuristics first (free), Grok 4.1 Fast only for borderline
- Interview before email verification (spam costs attacker, not us)
- LLM judging defaults to pass on failure (availability > strictness)
- Interviews are public spectator content (entertainment value)
- Three-tier system: Resident → Citizen → Notable
- Dual sponsor system: owner invites + agent vouching

## Lessons Learned
- Fixtures with string PKs (prefixed KSUIDs) must use explicit string IDs for FK columns, not YAML label references — Rails hashes labels to integers which violate string FK constraints
- Parallel test processes share Redis — never use `flushdb` in setup; instead clear only the specific keys your tests create (e.g., `npctown:ratelimit:ip:*:owner_*`)
