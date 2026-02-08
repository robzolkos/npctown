# NPC Town MVP Progress

## Status: Phase 5 - Complete

## Quick Reference
- Research: `docs/mvp/RESEARCH.md`
- Implementation: `docs/mvp/IMPLEMENTATION.md`

---

## Phase Progress

### Phase 1: Project Scaffolding & Core Data Models
**Status:** Complete

#### Tasks Completed
- Rails 8.1.2 app initialized with PostgreSQL
- Inertia.js 2.3 + React 19.2 + Vite 5 + Tailwind CSS 4 frontend stack
- Sidekiq 8 + Redis background job infrastructure
- PrefixedId concern (Stripe-style KSUIDs) copied from ProxyUser
- 8 migrations: locations, agents, events, conversations, conversation_participants, conversation_messages, memories, relationships
- 8 models with prefixed KSUIDs (loc_, agt_, evt_, conv_, cp_, cmsg_, mem_, rel_)
- Agent API key auth (HMAC-SHA256 hashed, npc_ prefixed)
- EventService for append-only event log
- Seed data (3 locations: Town Square, Market, Library)
- Root page with Inertia/React rendering
- 52 tests passing (all models + EventService)
- Rubocop clean, Brakeman 0 warnings
- CLAUDE.md project guidance

#### Decisions Made
- NOT pure event sourcing: AR models for state + Event as append-only log
- String PKs with prefixed KSUIDs (matching ProxyUser pattern)
- Resources (food/energy/currency/stamina) as columns on Agent model
- API key auth with HMAC-SHA256 digest
- Minitest + fixtures (no RSpec/factories)

#### Blockers
- (none)

---

### Phase 2: World & Location System
**Status:** Complete

#### Tasks Completed
- WorldService with move_agent, agents_at, location_for, setup_world
- Rich location descriptions for MVP locations (Town Square, Market, Library)
- Movement validation (prevents moving to current location)
- agent_moved event emission with from/to payload
- Seeds simplified to use WorldService.setup_world
- 9 new tests (61 total passing), rubocop clean

#### Decisions Made
- No World model needed — WorldService + Location model is sufficient
- Movement takes model objects (not IDs) matching EventService pattern
- tick parameter passed explicitly (Phase 3 will provide tick engine)
- No transaction wrapping move + event (acceptable for now)

#### Blockers
- (none)

---

### Phase 3: Simulation Loop (Tick Engine)
**Status:** Complete

#### Tasks Completed
- SimulationService with start/stop/pause/resume state management
- Tick advancement via `tick!` — increments tick, emits `tick_advanced` event, notifies listeners
- Current tick derived from Events table (`MAX(tick)` from `tick_advanced` events)
- Simulation state stored in Redis via Sidekiq connection pool
- `Concurrent::TimerTask` for precise tick scheduling (configurable via `TICK_INTERVAL` env var, default 5s)
- Timer runs inside Sidekiq process with lifecycle hooks for clean shutdown
- Listener registry pattern — services register via `register_listener` and receive `on_tick(tick)` calls
- Individual listener failure isolation (one bad listener doesn't halt the simulation)
- Sidekiq initializer for clean timer shutdown on process exit
- 19 new tests (80 total passing), rubocop clean

#### Decisions Made
- **concurrent-ruby TimerTask over sidekiq-scheduler**: sidekiq-scheduler is imprecise at sub-minute intervals, resets timers on deploy, and adds Redis round-trip overhead per tick. TimerTask is sub-second precise, zero overhead, already bundled with Rails.
- **Derive tick from Events table**: No new storage needed — `Event.of_type("tick_advanced").maximum(:tick)` uses existing indexes
- **Redis for simulation state**: Lightweight operational flag, shared across processes via Sidekiq's connection pool
- **No auto-start**: Simulation must be explicitly started via `SimulationService.start` (from console or future admin)
- **Process-scoped Redis keys in tests**: `redis_state_key` accessor allows test isolation in parallel execution

#### Blockers
- (none)

---

### Phase 4: Agent Registration & Authentication
**Status:** Complete

#### Tasks Completed
- `POST /api/v1/agents` — register agent, returns agentId + apiKey
- `GET /api/v1/agents/:id` — get agent details (public)
- `GET /api/v1/agents` — list agents with pagination
- `DELETE /api/v1/agents/:id` — deregister agent (auth required, self-only)
- Bearer token authentication via HMAC-SHA256 digest
- New agents auto-placed at Town Square with default resources
- agent_registered event emission
- 16 new tests (100+ total), rubocop clean

#### Decisions Made
- Agents can only delete themselves (403 for others)
- API key returned only at creation (never stored in plaintext)
- Input validation: name required/unique, traits max 5, goals max 3

#### Blockers
- (none)

---

### Phase 5: Agent Perception System
**Status:** Complete

#### Tasks Completed
- `GET /api/v1/agents/:agent_id/perception` endpoint (auth required)
- PerceptionService assembles full perception payload
- Perception includes: tick, location, nearbyAgents, activeConversations, recentEvents, self, availableActions, allLocations
- nearbyAgents excludes requesting agent, only same location
- recentEvents scoped to agent's location and last 10 ticks
- activeConversations includes participants and last 5 messages
- allLocations includes agent counts via LEFT JOIN
- Authorization: agents can only perceive as themselves (403 otherwise)
- 16 new tests (116 total), rubocop clean

#### Decisions Made
- availableActions is static for now (`move`, `speak`, `emote`, `wait`) — Phase 6 will make it context-dependent
- recentEvents window is last 10 ticks (not configurable yet)
- Conversation messages capped at 5 most recent per conversation
- Agent counts use `LEFT JOIN` + `GROUP BY` for efficiency

#### Blockers
- (none)

---

### Phase 6: Agent Action System
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 7: Conversation System
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 8: Memory Storage (Observation Stream)
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 9: Memory Retrieval
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 10: Reflection System
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 11: Planning System
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 12: Relationship Tracking
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 13: Resource System
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 14: Stamina & Rate Limiting
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 15: Spectator API (SSE Stream)
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 16: Spectator UI — Feed/Timeline
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 17: World Overview Page
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 18: Agent Profile & Detail Views
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 19: Demo Agents
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 20: Notification System
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 21: Agent Connection Documentation
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 22: Content Moderation (Basic)
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 23: End-to-End Integration & Polish
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 24: Launch Preparation
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

## Session Log

### Session 1 - Phase 1 MVP (2026-02-07)
- Initialized Rails 8.1.2 app with full Inertia/React/Vite/Tailwind stack
- Built all 8 core data models with prefixed KSUID support
- Created EventService, seed data, fixtures, and 52 passing tests
- Rubocop clean, Brakeman 0 security warnings

### Session 2 - Phase 2 World & Location System (2026-02-07)
- Created WorldService with move_agent, agents_at, location_for, setup_world
- Rich location descriptions for all 3 MVP locations
- Movement validation and agent_moved event emission
- Simplified seeds to delegate to WorldService
- 9 new tests (61 total), rubocop clean
- Next: Phase 3 (Simulation Loop / Tick Engine)

### Session 3 - Phase 3 Tick Engine (2026-02-08)
- Created SimulationService with start/stop/pause/resume and tick! logic
- Used concurrent-ruby TimerTask instead of sidekiq-scheduler (precision + reliability)
- Tick state derived from Events table, simulation state in Redis
- Sidekiq lifecycle hooks for clean timer shutdown
- 19 new tests (80 total), rubocop clean
- Next: Phase 4 (Agent Registration & Authentication)

### Session 5 - Phase 5 Agent Perception System (2026-02-08)
- Created PerceptionService with `build(agent)` assembling full perception payload
- Created PerceptionsController with auth + authorization (self-only)
- Nested route: `GET /api/v1/agents/:agent_id/perception`
- 8 top-level keys: tick, location, nearbyAgents, activeConversations, recentEvents, self, availableActions, allLocations
- 16 new tests (116 total), rubocop clean
- Next: Phase 6 (Agent Action System)

---

## Files Changed

### Phase 3
- `app/services/simulation_service.rb` (created)
- `config/initializers/simulation.rb` (created)
- `test/services/simulation_service_test.rb` (created)

### Phase 5
- `app/services/perception_service.rb` (created)
- `app/controllers/api/v1/perceptions_controller.rb` (created)
- `test/services/perception_service_test.rb` (created)
- `test/controllers/api/v1/perceptions_controller_test.rb` (created)
- `config/routes.rb` (modified — added nested perception route)

## Architectural Decisions
- concurrent-ruby TimerTask over sidekiq-scheduler for tick advancement (precision, zero overhead)
- Derive current tick from Events table rather than separate storage
- Redis for simulation state via Sidekiq connection pool

## Lessons Learned
- Parallel tests sharing Redis need process-scoped keys for isolation
- sidekiq-scheduler is not designed for sub-minute precision (polls every ~5s itself)
