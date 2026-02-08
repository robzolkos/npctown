# NPC Town MVP Progress

## Status: Phase 11 - Complete

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
**Status:** Complete

#### Tasks Completed
- `POST /api/v1/agents/:agent_id/actions` endpoint with auth
- ActionService with 4 action types: move, speak, emote, wait
- Stamina costs: move (5), speak (1), emote (1), wait (0)
- Validation, stamina deduction, event emission
- Transaction-safe execution with rollback
- 25 new tests (141 total), rubocop clean

#### Decisions Made
- ActionService uses class methods with private_class_method pattern
- Transaction wraps stamina deduction + action execution for rollback safety
- Events emitted inside the transaction

#### Blockers
- (none)

---

### Phase 7: Conversation System
**Status:** Complete

#### Tasks Completed
- ConversationService with full lifecycle: start, join, message, leave, end
- 4 new action types: startConversation (2 stamina), joinConversation (1), leaveConversation (0), conversationMessage (1)
- Same-location validation for starting/joining conversations
- Max 2 active conversations per agent
- Auto-leave conversations when agent moves to a different location
- Auto-end conversations when all participants leave (reason: all_left)
- Auto-end stale conversations with no messages for 5+ ticks via tick listener (reason: stale)
- ConversationService registered as SimulationService tick listener
- Model helpers: Conversation#active_participants, #last_message_tick, #stale?
- ConversationParticipant.active scope
- PerceptionService updated with conversation actions in availableActions
- ActionsController updated with conversation params (targetAgentId, conversationId)
- Charlie fixture added (agent at Town Square for conversation tests)
- 33 new tests (174 total), rubocop clean, 0 offenses

#### Decisions Made
- ConversationService as separate service (not inside ActionService) for clean separation
- ActionService delegates to ConversationService for all conversation logic
- leaveConversation costs 0 stamina (free to leave)
- No migration needed — left_at_tick and ended_at_tick columns already existed in schema
- Tick listener registered in config/initializers/simulation.rb (alongside existing Sidekiq shutdown hook)
- System messages (join/leave) emitted as conversation_message events with system: true in payload

#### Blockers
- (none)

---

### Phase 8: Memory Storage (Observation Stream)
**Status:** Complete

#### Tasks Completed
- MemoryService with create_memory, observe_event, memories_for, on_tick, process_events_into_memories
- ProcessMemoriesJob for async Sidekiq-based batch memory processing
- Redis-backed state tracking (last_processed_tick, distributed lock with 30s TTL)
- Importance scoring: rule-based mapping (agent_moved=2, stamina_changed=2, resource_changed=3, agent_action=3, agent_spoke=4, conversation_started=5, conversation_message=5, conversation_ended=6, agent_registered=7, relationship_changed=7) with self-discount of 1
- Human-readable event descriptions for all event types
- Memory trimming (max 1000 per agent, keeps high-importance and recent)
- Skip logic for tick_advanced, memory_created, reflection_created events (prevents infinite loops)
- GET /api/v1/agents/:agent_id/memories endpoint (auth required, paginated, filterable by type/importance/tick)
- PerceptionService updated with recentMemories (last 10 ticks)
- Agent cache for N+1 prevention during batch processing
- Tests for MemoryService (observe_event, importance, descriptions, Redis state, trimming)

#### Decisions Made
- Async processing via Sidekiq (ProcessMemoriesJob) instead of inline — prevents tick delays
- Redis lock (SETNX + TTL) for concurrent processing safety across workers
- Location-based observation: agents at a location observe all events at that location
- Self-importance discount of 1 point for agent's own events
- Memory cap of 1000 per agent with automatic trimming of low-importance old memories
- Skip memory_created/reflection_created/tick_advanced events to prevent infinite loops

#### Blockers
- (none)

---

### Phase 9: Memory Retrieval
**Status:** Complete

#### Tasks Completed
- Migration: added `search_vector` tsvector column with GIN index + database trigger for auto-population
- MemoryRetrievalService with `get_relevant_memories(agent:, query:, limit:, weights:)`
- Combined scoring: recency (exponential decay) + importance (normalized 1-10) + relevance (PostgreSQL full-text search via ts_rank)
- Relevance scores normalized to 0-1 within candidate set so weights work as intended
- Default weights: recency 0.3, importance 0.3, relevance 0.4
- Helper queries: `get_recent_memories`, `get_memories_about_agent`, `get_memories_at_location`
- PerceptionService updated with `relevantMemories` (top 5 context-relevant memories)
- Context query built from current location name + nearby agent names
- API docs page (`/docs`) updated with `relevantMemories` in perception response example + note
- Additional test fixtures for diverse memory content (market/trading, library/books)
- 15 new tests (224 total), rubocop clean, 0 offenses

#### Decisions Made
- PostgreSQL full-text search over embeddings/pgvector — zero external cost at any scale, no API dependency
- tsvector with English dictionary for stemming ("trading" matches "trade", "trader")
- Database trigger auto-populates `search_vector` on INSERT/UPDATE (dev/production); test setup backfills fixtures
- Normalized relevance scoring: ts_rank values divided by max rank in candidate set, ensuring 0-1 scale
- Candidate limit of 200 memories per retrieval query to keep scoring fast
- `relevantMemories` added alongside `recentMemories` in perception (different purposes: context relevance vs raw recency)

#### Blockers
- (none)

---

### Phase 10: Reflection System (Hybrid)
**Status:** Complete

#### Tasks Completed
- Migration: `reflected_upon` boolean on memories with partial index for unreflected observations
- Memory model: added `unreflected` scope
- ActionService: `reflect` action type (0 stamina cost, importance 9, marks observations as reflected)
- ActionsController: added `content` param for reflect action
- ReflectionService: platform fallback tick listener (every 100 ticks, importance 7)
  - Location frequency pattern detection (3+ observations at same location)
  - Agent interaction frequency pattern detection (3+ observations mentioning same agent)
  - Max 2 template reflections per agent per cycle
- ProcessReflectionsJob: Sidekiq job for async reflection processing
- Registered ReflectionService as SimulationService tick listener
- PerceptionService: unreflectedObservations (count + top 20), recentReflections (last 5), dynamic availableActions (reflect appears when >= 5 unreflected)
- ReflectionsController: GET /api/v1/agents/:id/reflections (auth required, self-only)
- Route: `resources :reflections, only: [:index]` nested under agents
- API docs (Docs.tsx): reflect action type, reflections endpoint, perception updates, How Agents Work, Agent Loop
- 25 new tests (249 total), rubocop clean, 0 offenses

#### Decisions Made
- **Hybrid approach**: Agent-driven reflections (preferred, importance 9) + platform template fallback (importance 7)
- Agent incentive: higher importance score = stronger influence on future perception/retrieval
- `reflected_upon` flag coordinates both paths — if agent reflects first, platform skips those observations
- Platform fallback runs every 100 ticks (slow, gives agents time to reflect on their own)
- Template-based pattern detection (no LLM) for platform fallback — simple location/agent frequency analysis
- Reflect action costs 0 stamina (free to encourage usage)
- `source: "agent"` vs `source: "system"` in reflection_created event payloads for tracking
- Partial index on `(agent_id, reflected_upon) WHERE reflected_upon = FALSE AND memory_type = 'observation'` for fast unreflected lookups

#### Blockers
- (none)

---

### Phase 11: Planning System
**Status:** Complete

#### Tasks Completed
- Migration: `plans` table with string PK (KSUID), agent_id FK, goal (text), steps (JSONB), status, created_at_tick, last_updated_at_tick
- Plan model with PrefixedId (`plan_`), validations, scopes (active, for_agent, recent), `stale?` method
- Agent model: `has_many :plans, dependent: :destroy` + `active_plan` convenience method
- Event model: 4 new event types (plan_created, plan_updated, plan_completed, plan_abandoned)
- PlanService: create_plan, update_plan, complete_plan, abandon_plan, on_tick auto-abandon (200 tick threshold), normalize_steps
- PlansController: GET show (active plan), POST create (new plan, auto-abandons existing), PATCH update (update/complete/abandon)
- Routes: `resource :plan, only: [:show, :create, :update]` nested under agents
- Registered PlanService as SimulationService tick listener in sidekiq.rb
- MemoryService: plan event importance scoring (5/3/6/4) and human-readable descriptions for all 4 plan event types
- PerceptionService: `currentPlan` key added to perception payload (goal, steps, ticks)
- Plan fixtures (alice_active_plan, bob_completed_plan)
- Tests: 12 model tests, 17 service tests, 10 controller integration tests
- API docs (Docs.tsx): 3 plan endpoints, perception update, How Agents Work update, Agent Loop update
- 288 tests passing, rubocop clean, 0 offenses

#### Decisions Made
- Dedicated Plan model (not Memory) — needs structured fields (goal, steps[], status, lifecycle ticks) that Memory doesn't have
- Dedicated REST endpoints (resource :plan) instead of adding action types — matches resource :perception singular pattern, cleaner and more RESTful
- PATCH update handles three operations via action_type param: "complete", "abandon", or default update
- Auto-abandons existing active plan when creating a new one (only one active plan per agent)
- Plan events NOT skipped by MemoryService — they are meaningful observable events that nearby agents should form memories about
- PlanService registered as tick listener for auto-abandoning stale plans (200 tick threshold)
- normalize_steps converts both string arrays and object arrays to consistent `[{ description, done }]` format

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

### Session 7 - Phase 7 Conversation System (2026-02-08)
- Created ConversationService with full conversation lifecycle (start, join, message, leave, end)
- Extended ActionService with 4 new conversation action types
- Auto-leave on move, auto-end on all-left, auto-end stale via tick listener
- Max 2 active conversations per agent enforced
- Updated PerceptionService, ActionsController, Conversation model, ConversationParticipant model
- Added charlie fixture for conversation tests
- 33 new tests (174 total), rubocop clean, 0 offenses
- Next: Phase 8 (Memory Storage)

### Session 8 - Phase 8 Memory Storage (2026-02-08)
- Created MemoryService with async event-to-memory processing via ProcessMemoriesJob
- Redis-backed state tracking and distributed lock for concurrent safety
- Rule-based importance scoring (2-7) with self-discount
- Human-readable event descriptions for all 13 event types
- Memory trimming (max 1000 per agent)
- GET /api/v1/agents/:agent_id/memories API endpoint (auth, paginated, filterable)
- PerceptionService updated with recentMemories
- Tests for MemoryService
- Next: Phase 9 (Memory Retrieval)

### Session 9 - Phase 9 Memory Retrieval (2026-02-08)
- Created MemoryRetrievalService with combined scoring (recency + importance + relevance)
- PostgreSQL full-text search via tsvector/tsquery/ts_rank (zero external cost)
- Migration: search_vector column + GIN index + database trigger
- Normalized relevance scoring within candidate set for balanced weights
- Helper queries: get_recent_memories, get_memories_about_agent, get_memories_at_location
- PerceptionService updated with relevantMemories (top 5 context-relevant)
- API docs page updated with relevantMemories in perception example
- 15 new tests (224 total), rubocop clean, 0 offenses
- Next: Phase 10 (Reflection System)

### Session 10 - Phase 10 Reflection System (2026-02-08)
- Hybrid reflection system: agent-driven (importance 9) + platform fallback (importance 7)
- `reflect` action type in ActionService (0 stamina, creates reflection, marks observations reflected)
- ReflectionService tick listener with template-based pattern detection (location freq + agent interaction freq)
- ProcessReflectionsJob for async platform reflections every 100 ticks
- PerceptionService: unreflectedObservations, recentReflections, dynamic availableActions with reflect
- ReflectionsController + route for listing agent reflections
- API docs updated with reflect action, reflections endpoint, perception changes, agent loop
- 25 new tests (249 total), rubocop clean, 0 offenses
- Next: Phase 11 (Planning System)

### Session 11 - Phase 11 Planning System (2026-02-08)
- Created Plan model with PrefixedId (plan_), validations, scopes, stale? method
- Migration: plans table with JSONB steps, status lifecycle, tick tracking
- PlanService: full lifecycle (create, update, complete, abandon) + tick listener for stale auto-abandon
- PlansController: GET show, POST create, PATCH update (with complete/abandon action_type)
- 4 new event types: plan_created, plan_updated, plan_completed, plan_abandoned
- MemoryService: plan event importance scoring + human-readable descriptions
- PerceptionService: currentPlan added to perception payload
- API docs: 3 plan endpoints, perception currentPlan, How Agents Work + Agent Loop updates
- 39 new tests (288 total), rubocop clean, 0 offenses
- Next: Phase 12 (Relationship Tracking)

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

### Phase 7
- `app/services/conversation_service.rb` (created)
- `app/services/action_service.rb` (modified — added 4 conversation action types + auto-leave on move)
- `app/controllers/api/v1/actions_controller.rb` (modified — conversation params + error handling)
- `app/services/perception_service.rb` (modified — conversation actions in AVAILABLE_ACTIONS)
- `app/models/conversation.rb` (modified — active_participants, last_message_tick, stale?)
- `app/models/conversation_participant.rb` (modified — active scope)
- `config/initializers/simulation.rb` (modified — registered ConversationService tick listener)
- `test/services/conversation_service_test.rb` (created)
- `test/services/action_service_test.rb` (modified — conversation action tests)
- `test/services/perception_service_test.rb` (modified — updated expected actions)
- `test/fixtures/agents.yml` (modified — added charlie)

### Phase 8
- `app/services/memory_service.rb` (created)
- `app/jobs/process_memories_job.rb` (created)
- `app/controllers/api/v1/memories_controller.rb` (created)
- `app/services/perception_service.rb` (modified — added recentMemories)
- `config/routes.rb` (modified — added memories route)
- `test/services/memory_service_test.rb` (created)

### Phase 9
- `db/migrate/20260208000001_add_search_vector_to_memories.rb` (created — tsvector + GIN index + trigger)
- `app/services/memory_retrieval_service.rb` (created — scoring + retrieval)
- `test/services/memory_retrieval_service_test.rb` (created — 15 tests)
- `app/services/perception_service.rb` (modified — added relevantMemories)
- `test/services/perception_service_test.rb` (modified — verify relevantMemories key)
- `test/fixtures/memories.yml` (modified — added 3 diverse fixtures)
- `app/frontend/pages/Docs.tsx` (modified — relevantMemories in perception example + note)

### Phase 10
- `db/migrate/20260208000002_add_reflected_upon_to_memories.rb` (created — reflected_upon boolean + partial index)
- `app/models/memory.rb` (modified — added unreflected scope)
- `app/services/action_service.rb` (modified — reflect action type, execute_reflect)
- `app/controllers/api/v1/actions_controller.rb` (modified — content param)
- `app/services/reflection_service.rb` (created — platform fallback tick listener)
- `app/jobs/process_reflections_job.rb` (created — Sidekiq job)
- `config/initializers/sidekiq.rb` (modified — registered ReflectionService listener)
- `app/services/perception_service.rb` (modified — unreflectedObservations, recentReflections, dynamic availableActions)
- `app/controllers/api/v1/reflections_controller.rb` (created — GET reflections endpoint)
- `config/routes.rb` (modified — added reflections route)
- `app/frontend/pages/Docs.tsx` (modified — reflect action, reflections endpoint, perception updates)
- `test/services/reflection_action_test.rb` (created — 6 tests)
- `test/services/reflection_service_test.rb` (created — 10 tests)
- `test/controllers/api/v1/reflections_controller_test.rb` (created — 4 tests)
- `test/services/perception_service_test.rb` (modified — 5 new tests for reflection data)

### Phase 11
- `db/migrate/20260208000003_create_plans.rb` (created — plans table with JSONB steps)
- `app/models/plan.rb` (created — PrefixedId, validations, scopes, stale?)
- `app/models/agent.rb` (modified — has_many :plans, active_plan method)
- `app/models/event.rb` (modified — 4 new plan event types)
- `app/services/plan_service.rb` (created — plan lifecycle + tick listener)
- `app/controllers/api/v1/plans_controller.rb` (created — show, create, update)
- `config/routes.rb` (modified — added plan resource)
- `config/initializers/sidekiq.rb` (modified — registered PlanService listener)
- `app/services/memory_service.rb` (modified — plan event importance + descriptions)
- `app/services/perception_service.rb` (modified — currentPlan in perception)
- `app/frontend/pages/Docs.tsx` (modified — plan endpoints, perception, agent loop)
- `test/fixtures/plans.yml` (created — 2 fixtures)
- `test/models/plan_test.rb` (created — 12 tests)
- `test/services/plan_service_test.rb` (created — 17 tests)
- `test/controllers/api/v1/plans_controller_test.rb` (created — 10 tests)
- `test/models/event_test.rb` (modified — updated TYPES count + plan type assertions)

## Architectural Decisions
- concurrent-ruby TimerTask over sidekiq-scheduler for tick advancement (precision, zero overhead)
- Derive current tick from Events table rather than separate storage
- Redis for simulation state via Sidekiq connection pool
- ConversationService as separate service from ActionService for clean separation of concerns
- System messages (join/leave) use conversation_message event type with system: true payload flag
- Async memory processing via Sidekiq (ProcessMemoriesJob) to avoid blocking tick advancement
- Redis SETNX lock for distributed memory processing safety across workers
- Location-based observation: all agents at a location observe all location events
- Memory cap of 1000 per agent with automatic low-importance trimming
- PostgreSQL full-text search (tsvector/ts_rank) over vector embeddings for memory retrieval — zero external cost, scales with database
- Normalized relevance scoring: ts_rank values divided by max in candidate set to ensure 0-1 scale matching recency/importance
- Hybrid reflection: agent-driven (importance 9) + platform fallback (importance 7) — agents bring their own compute, platform catches stragglers
- `reflected_upon` flag coordinates both paths: agent reflects → marks observed, platform skips already-reflected
- Platform fallback uses simple template patterns (no LLM) — location frequency + agent interaction frequency

## Lessons Learned
- Parallel tests sharing Redis need process-scoped keys for isolation
- sidekiq-scheduler is not designed for sub-minute precision (polls every ~5s itself)
- DB schema already had left_at_tick/ended_at_tick columns — always check schema before planning migrations
- PostgreSQL triggers defined in migrations don't carry into test DB via schema.rb — need to backfill tsvector in test setup
- ts_rank returns very small values (0.03-0.1 range) — must normalize within candidate set for scoring weights to work meaningfully
