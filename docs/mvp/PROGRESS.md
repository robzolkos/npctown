# NPC Town MVP Progress

## Status: Phase 18 - Complete

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
**Status:** Complete

#### Tasks Completed
- RelationshipService with find_or_create, on_conversation_started, on_conversation_message, relationships_for
- Inline relationship updates (not tick-based) — lightweight DB writes on each conversation interaction
- Bidirectional updates: A→B and B→A both updated on every interaction
- Auto-creation of relationships on first interaction (defaults all 0)
- Dimension clamping: trust/affection/respect (-100..100), familiarity (0..100)
- ConversationService hooks: start_conversation (+3 familiarity, +1 trust), add_message (+1 familiarity, +1 trust), join_conversation (+3 familiarity, +1 trust with each existing participant)
- relationship_changed event emission with full payload (target_agent_id, name, all dimensions, label)
- GET /api/v1/agents/:agent_id/relationships endpoint (auth required, self-only)
- PerceptionService: relationships key with non-stranger filtering (familiarity >= 10)
- bob_knows_alice fixture for bidirectional test coverage
- 16 new tests (304 total), rubocop clean, 0 offenses

#### Decisions Made
- Inline updates (not tick-based/async) — relationship changes are simple DB writes, no batch processing needed
- Hook in ConversationService (not ActionService) — closer to interaction logic, works for any future code path
- Only conversations update relationships — speak/emote are broadcast with no clear target
- Only trust and familiarity change for MVP — affection/respect need richer interaction types
- No decay mechanics — future phase concern
- No negative interactions — no action types exist for negativity yet

#### Blockers
- (none)

---

### Phase 13: Resource System
**Status:** Complete

#### Tasks Completed
- ResourceService with tick listener pattern: energy decay (-1/10 ticks), food decay (-1/20 ticks), starvation double decay (energy -2 when food=0)
- Market bonus: +10 food, +10 currency every 720 ticks for agents at commerce locations
- Rest action: restores 30 energy (cap 100), costs 2 stamina
- Eat action: consumes 20 food, restores 40 energy (cap 100), costs 1 stamina
- Trade action: instant resource transfer to co-located agent, max 50 per trade, costs 1 stamina
- Exhaustion guard: energy=0 restricts agent to wait/move/rest/eat only
- Resource labels in perception: nearbyAgents includes resourceStatus array (e.g. ["hungry", "tired", "wealthy"])
- PerceptionService: rest always available, eat when food >= 20, trade always available
- MemoryService: reason-specific descriptions for resource_changed events (rest, eat, trade, market_bonus, exhausted, starving)
- ResourceService registered as SimulationService tick listener
- ActionsController: resource/amount params for trade
- API docs (Docs.tsx): 3 new action types, resourceStatus in perception, exhaustion/market notes
- 35 new tests (339 total), rubocop clean, 0 offenses

#### Decisions Made
- Instant trade (no proposal/acceptance flow) — simpler for MVP, agents can just give resources
- Exhaustion enforced in ActionService.validate!, not a separate agent status
- Decay inline in tick listener (like StaminaService), not async via Sidekiq job
- Events only on thresholds (energy/food hitting 0), not every decay tick — reduces event noise
- Market bonus every 720 ticks (~1 hour at 5s ticks) using Location.by_type("commerce")

#### Blockers
- (none)

---

### Phase 14: Stamina & Rate Limiting
**Status:** Complete

#### Tasks Completed
- StaminaService rewritten: slow regen via Redis counter, +1 stamina every 180 ticks (~4/hour at 5s ticks)
- Stamina costs updated: rest 2→0 (free to encourage recovery), trade 1→3 (more expensive)
- Stamina=0 guard in ActionService: agents can only wait or rest when stamina depleted
- PerceptionService: availableActions returns only ["wait", "rest"] at stamina=0
- RateLimitService: Redis fixed-window counter with INCR+EXPIRE in MULTI
- Rate limiting on perception (1/5s) and actions (1/5s) controllers
- Rate limiting on data endpoints (memories, reflections, relationships, plans) — shared 10/min bucket
- BaseController: rescue_from RateLimitExceeded → 429 with Retry-After header
- 10 new tests (349 total), rubocop clean, 0 offenses

#### Decisions Made
- Redis counter approach for slow regen (not fractional float column) — only hits DB every 180th tick
- Fixed-window rate limiting over sliding window — simpler, sufficient for game simulation
- Shared "data" rate limit bucket for memories/reflections/relationships/plans (10/min total)
- AgentsController not rate limited (create/list/show are public, destroy is rare)
- Stamina=0 blocks all actions except wait and rest (including zero-cost actions like reflect/leaveConversation)

#### Blockers
- (none)

---

### Phase 15: Spectator API (SSE Stream)
**Status:** Complete

#### Tasks Completed
- SpectatorEventFormatter service: formats raw events into spectator-friendly JSON with human-readable messages
- `format(event)` returns { id, tick, timestamp, type, message, details }
- `format_many(events)` batch-formats with N+1 prevention via agent cache
- `spectator_visible?(event)` filters out internal events (tick_advanced, memory_created, reflection_created, stamina_changed)
- Human-readable messages for all 13 spectator-visible event types
- SpectateController (inherits ActionController::API directly, no auth)
- `GET /api/v1/spectate/stream` — SSE endpoint with ActionController::Live
  - Polling-based (1s interval), heartbeat every 15s
  - `Last-Event-ID` header support for reconnection
  - Location filter: `?location=market` (case-insensitive)
  - Agent filter: `?agent=<agentId>`
  - Graceful disconnect handling (IOError, ClientDisconnected)
- `GET /api/v1/spectate/history` — JSON catch-up endpoint
  - `since_tick` param, `limit` (default 50, max 200)
  - Same location/agent filters as stream
  - Returns array of formatted events (same shape as SSE data)
- Routes added: `resource :spectate` with stream and history actions
- 16 formatter tests + 9 controller integration tests (25 new, 374 total)
- Rubocop clean, 0 offenses

#### Decisions Made
- Polling over pub/sub — simpler, no Redis pub/sub channel needed, 1s interval fine for 5s tick
- No auth — spectator API is public by design
- No batching/buffering — 5s ticks + 1s polling naturally batches events
- Separate controller base — inherits ActionController::API directly (not BaseController) to skip authenticate_agent!
- Location filter uses case-insensitive name match (LOWER)
- Agent filter uses prefixed ID lookup via find_by_prefixed_id

#### Blockers
- (none)

---

### Phase 16: Spectator UI — Feed/Timeline
**Status:** Complete

#### Tasks Completed
- Route (`GET /feed`) + PagesController#feed action with Inertia props (locations, currentTick)
- "watch" link added to Home.tsx navigation
- TypeScript types (`app/frontend/types/events.ts`): SpectatorEvent, LocationInfo, EventType
- useEventStream hook: polling-based (2s interval) fetching `/api/v1/spectate/history`, dedup by ID, 500 event cap
- useEventHistory hook: infinite scroll upward, fetches older events with `since_tick` pagination
- Feed.tsx (~750 lines): dark cyberpunk terminal aesthetic, sidebar with locations/agents, filter tabs, agent filter pill
- 13 event type renderers with distinct visual treatments:
  - Speech: prominent with quoted text, green agent names
  - Conversations: bordered start/end markers, indented messages
  - Movement: compact single-line with arrow, muted color
  - Emotes: italic with asterisks
  - Relationships: highlighted cards with dimension badges (trust/affection/respect/familiarity arrows)
  - Resources: compact inline with gain/loss coloring
  - Plans: bordered cards with goal text, status-based styling
- Auto-scroll behavior with "New events" floating button + count badge
- Connection status indicator (pulsing green LIVE / amber RECONNECTING / red OFFLINE)
- Empty state: "waiting for signs of life..." with blinking cursor
- CSS animations: fadeSlideIn entrance + glowFade left-border accent
- Sidebar: 3 locations with agent lists, clickable for filtering
- Location filter tabs: All / Town Square / Market / Library (server-side filtering)
- Agent filter: click agent name anywhere → filter pill + server-side `?agent=` param
- SpectatorEventFormatter enriched with agent_id, agent_name, location_name fields
- Puma threads increased from 3 to 10 (for SSE connection handling)
- 374 tests passing, rubocop clean, TypeScript compiles clean

#### Decisions Made
- Polling over SSE EventSource: EventSource consumed Puma threads indefinitely (infinite loop with 1s sleep), blocking all server threads. Polling `/api/v1/spectate/history` every 2s is reliable and sufficient for 5s tick intervals.
- All inline in Feed.tsx: no premature component extraction, keeps everything co-located for this phase
- Agent filter uses agent_id (prefixed KSUID) not name — reliable, unique identifier
- SpectatorEventFormatter enriched with structured fields (agent_id, agent_name, location_name) — frontend no longer parses human-readable messages
- Puma threads 3→10 to handle SSE connections without blocking regular requests
- getRelationshipLabel utility computes labels client-side from dimension values (stranger, acquaintance, close friend, nemesis, etc.)
- useRelativeTime hook with 30s refresh interval for relative timestamps

#### Blockers
- (none)

---

### Phase 17: World Overview Page + URL Deep Linking
**Status:** Complete

#### Tasks Completed
- Route: `get "world", to: "pages#world"` added to routes.rb
- PagesController#world action: locations with agents, descriptions, active_conversations count, totalAgents
- WorldLocationInfo TypeScript type extending LocationInfo with description and active_conversations
- World.tsx page: responsive grid of LocationCard components with real-time updates via useEventStream
- LocationCard: name (deep link to /feed?location=X), type badge (color-coded), description, agent/conversation counts, density bar, agent list with mini resource bars
- Real-time updates: agent_moved, conversation_started, conversation_ended events processed client-side
- URL deep linking in Feed.tsx: locationFilter and focusedAgentId initialized from URL search params, synced back via history.replaceState
- Navigation links added to Home.tsx (feed | world | docs | source) and Feed.tsx header (feed | world | docs)
- ConnectionStatus and MiniBar sub-components duplicated in World.tsx (small, ~15 lines each)
- Smoke tests: PagesControllerTest for home, feed, world, docs routes
- 378 tests passing, rubocop clean, 0 offenses
- Browser verified: world page renders, location deep links work, agent deep links work, nav links work

#### Decisions Made
- Inertia page over API endpoint — simpler, matches existing Feed pattern exactly
- No shared component extraction — MiniBar/ConnectionStatus duplicated (startup simplicity)
- URL deep linking via history.replaceState (not pushState) — avoids polluting browser back button
- World links to Feed with query params (/feed?location=X, /feed?agent=agt_xxx) — Feed reads on mount
- typeof window check for SSR safety on URLSearchParams initialization

#### Blockers
- (none)

---

### Phase 18: Agent Profile & Detail Views
**Status:** Complete

#### Tasks Completed
- Route: `get "agents/:id"` → PagesController#agent_profile
- PagesController#agent_profile action with serialize_agent_profile, stamina_label helpers
- Profile serializes: identity, approximate resource labels, relationships, reflections (last 10), stats, recent events (last 50)
- AgentProfileData TypeScript type + AgentProfileReflection, AgentProfileStats
- AgentProfile.tsx page: header, breadcrumb, name/status/location, description, traits/goals, condition badges, plan, relationships, reflections, stats grid, recent activity, feed link
- World.tsx: agent name links now go to `/agents/:id` (was `/feed?agent=...`)
- Feed.tsx: "full profile" link added to AgentDetailPanel header
- Public resources use approximate labels via ResourceService.resource_description (not raw numbers)
- 2 new tests (380 total), rubocop clean, 0 offenses
- Browser verified: profile renders, World→profile nav, Feed detail→profile nav, profile→feed nav all work

#### Decisions Made
- Inertia page (not API endpoint) — matches Feed/World pattern
- Approximate resources on public profile — uses ResourceService.resource_description labels + stamina_label helper
- Reflections queried directly (not through auth-gated API) — public spectator-facing view
- Keep Feed's inline AgentDetailPanel — add "full profile" link instead of replacing inline behavior
- No SSE/real-time on profile — static server-rendered snapshot via Inertia props
- Simple event rendering (message + timestamp) instead of full Feed event renderers — profile is for overview, feed is for live detail

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

### Session 12 - Phase 12 Relationship Tracking (2026-02-08)
- Created RelationshipService with inline bidirectional updates on conversation interactions
- Hooked into ConversationService (start_conversation, add_message, join_conversation)
- Created RelationshipsController with GET index endpoint (auth, self-only)
- Added relationships to PerceptionService (non-stranger filter, familiarity >= 10)
- relationship_changed events emitted with full dimension payload + label
- 16 new tests (304 total), rubocop clean, 0 offenses
- Next: Phase 13 (Resource System)

### Session 13 - Phase 13 Resource System (2026-02-08)
- Created ResourceService with tick listener: energy/food decay, starvation double decay, market bonus
- 3 new action types: rest (2 stamina), eat (1 stamina), trade (1 stamina)
- Exhaustion guard in ActionService (energy=0 blocks most actions)
- Resource labels in perception (resourceStatus: ["fed", "energetic", "comfortable"])
- MemoryService: reason-specific descriptions for resource_changed events
- API docs updated with new actions, perception fields, exhaustion/market notes
- 35 new tests (339 total), rubocop clean, 0 offenses
- Next: Phase 14 (Stamina & Rate Limiting)

### Session 14 - Phase 14 Stamina & Rate Limiting (2026-02-08)
- Rewrote StaminaService: slow regen via Redis counter (+1 every 180 ticks, ~4/hour)
- Updated stamina costs: rest 0 (free), trade 3 (expensive)
- Added stamina=0 guard: only wait/rest allowed when depleted
- Created RateLimitService with Redis fixed-window counters (INCR+EXPIRE in MULTI)
- Added rate limiting to 6 controllers: perception 1/5s, actions 1/5s, data endpoints 10/min
- BaseController rescue_from → 429 with Retry-After header
- 10 new tests (349 total), rubocop clean, 0 offenses
- Updated Docs.tsx: stamina costs, 429 error code, rate limiting & stamina=0 notes
- Manual API verification: all stamina costs, stamina=0 restrictions, rate limiting 429s confirmed
- Next: Phase 15 (Spectator API / SSE Stream)

### Session 15 - Phase 15 Spectator API (2026-02-08)
- Created SpectatorEventFormatter service with human-readable event formatting
- Created SpectateController with SSE stream (polling-based) and history endpoint
- Public endpoints (no auth): GET /api/v1/spectate/stream, GET /api/v1/spectate/history
- SSE: Last-Event-ID reconnection, location/agent filters, 15s heartbeat
- History: since_tick, limit, location/agent filters, formatted JSON array
- 25 new tests (374 total), rubocop clean, 0 offenses
- Next: Phase 16 (Spectator UI — Feed/Timeline)

### Session 16 - Phase 16 Spectator UI Feed/Timeline (2026-02-08)
- Built full spectator feed page at /feed with dark cyberpunk terminal aesthetic
- Created TypeScript types, polling-based event stream hook, history loading hook
- Feed.tsx with 13 event type renderers, each with distinct visual treatment
- Sidebar with locations/agents, filter tabs, agent filter pill
- Auto-scroll, "New events" button, connection status indicator, empty state
- Initially tried SSE EventSource but it consumed all Puma threads — rewrote to polling
- Enriched SpectatorEventFormatter with agent_id, agent_name, location_name for reliable filtering
- Increased Puma threads 3→10
- 374 tests passing, rubocop clean, TypeScript compiles clean
- Browser verified: all event types render, location filter works, agent filter works
- Next: Phase 17 (World Overview Page)

### Session 17 - Phase 17 World Overview Page + URL Deep Linking (2026-02-08)
- Created World.tsx page with responsive location card grid (1/2/3 col responsive)
- LocationCard: name deep link, type badge, description, agent/conversation counts, density bar, agent list
- Real-time updates via useEventStream (agent_moved, conversation_started, conversation_ended)
- URL deep linking in Feed.tsx: reads ?location= and ?agent= on mount, syncs back via history.replaceState
- World→Feed deep links: /feed?location=Market, /feed?agent=agt_xxx
- Navigation links: Home.tsx (feed|world|docs|source), Feed.tsx header (feed|world|docs)
- PagesController#world action with locations, agents, active_conversations, totalAgents
- WorldLocationInfo TypeScript type
- Smoke tests for all page routes (4 new tests, 378 total)
- 378 tests passing, rubocop clean, 0 offenses
- Browser verified: world page renders, deep links work, nav links work
- Next: Phase 18 (Agent Profile & Detail Views)

### Session 18 - Phase 18 Agent Profile & Detail Views (2026-02-08)
- Created AgentProfile.tsx page at /agents/:id with full agent profile
- PagesController#agent_profile with serialize_agent_profile (approximate resources, reflections, stats)
- AgentProfileData TypeScript type with reflections, stats, resource labels
- Sections: identity, condition badges, plan, relationships (linking to other profiles), reflections, stats grid, recent activity
- World.tsx agent links → /agents/:id (was /feed?agent=...)
- Feed.tsx AgentDetailPanel: added "full profile" link
- 2 new tests (380 total), rubocop clean, 0 offenses
- Browser verified: all navigation paths work
- Next: Phase 19 (Demo Agents)

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

### Phase 12
- `app/services/relationship_service.rb` (created — find_or_create, update, event emission)
- `app/services/conversation_service.rb` (modified — 3 RelationshipService hooks)
- `app/controllers/api/v1/relationships_controller.rb` (created — GET index endpoint)
- `config/routes.rb` (modified — added relationships route)
- `app/services/perception_service.rb` (modified — relationships key in perception)
- `test/services/relationship_service_test.rb` (created — 10 tests)
- `test/controllers/api/v1/relationships_controller_test.rb` (created — 4 tests)
- `test/services/perception_service_test.rb` (modified — 2 new tests + updated top-level keys check)
- `test/fixtures/relationships.yml` (modified — added bob_knows_alice)

### Phase 13
- `app/services/resource_service.rb` (created — decay, market bonus, rest, eat, trade, labels)
- `app/services/action_service.rb` (modified — rest/eat/trade action types, exhaustion guard)
- `app/controllers/api/v1/actions_controller.rb` (modified — resource/amount params)
- `config/initializers/sidekiq.rb` (modified — registered ResourceService listener)
- `app/services/memory_service.rb` (modified — reason-specific resource_changed descriptions)
- `app/services/perception_service.rb` (modified — resourceStatus, rest/eat/trade in availableActions)
- `app/frontend/pages/Docs.tsx` (modified — 3 new action types, resourceStatus, exhaustion/market notes)
- `test/services/resource_service_test.rb` (created — 24 tests)
- `test/services/action_service_test.rb` (modified — rest/eat/trade/exhaustion tests)
- `test/services/perception_service_test.rb` (modified — resourceStatus, availableActions updates)

### Phase 14
- `app/services/stamina_service.rb` (rewritten — slow regen via Redis counter)
- `app/services/action_service.rb` (modified — rest=0, trade=3, stamina=0 guard)
- `app/services/perception_service.rb` (modified — stamina=0 early return in available_actions)
- `app/services/rate_limit_service.rb` (created — Redis fixed-window rate limiting)
- `app/controllers/api/v1/base_controller.rb` (modified — rescue_from + rate_limit! helper)
- `app/controllers/api/v1/perceptions_controller.rb` (modified — rate limit 1/5s)
- `app/controllers/api/v1/actions_controller.rb` (modified — rate limit 1/5s)
- `app/controllers/api/v1/memories_controller.rb` (modified — rate limit 10/60s)
- `app/controllers/api/v1/reflections_controller.rb` (modified — rate limit 10/60s)
- `app/controllers/api/v1/relationships_controller.rb` (modified — rate limit 10/60s)
- `app/controllers/api/v1/plans_controller.rb` (modified — rate limit 10/60s)
- `test/services/stamina_service_test.rb` (rewritten — Redis counter regen tests)
- `test/services/rate_limit_service_test.rb` (created — 3 tests)
- `test/services/action_service_test.rb` (modified — fixed rest/trade costs + 4 stamina=0 tests)
- `test/controllers/api/v1/perceptions_controller_test.rb` (modified — 429 test)
- `test/controllers/api/v1/actions_controller_test.rb` (modified — 429 test)
- `app/frontend/pages/Docs.tsx` (modified — stamina costs, 429 error code, rate limiting notes, stamina=0 notes)

### Phase 15
- `app/services/spectator_event_formatter.rb` (created — event formatting + human messages)
- `app/controllers/api/v1/spectate_controller.rb` (created — SSE stream + history endpoint)
- `config/routes.rb` (modified — added spectate routes)
- `test/services/spectator_event_formatter_test.rb` (created — 16 tests)
- `test/controllers/api/v1/spectate_controller_test.rb` (created — 9 tests)

### Phase 16
- `app/frontend/types/events.ts` (created — SpectatorEvent, LocationInfo, EventType types)
- `app/frontend/hooks/useEventStream.ts` (created — polling-based event stream hook)
- `app/frontend/hooks/useEventHistory.ts` (created — history loading hook for infinite scroll)
- `app/frontend/pages/Feed.tsx` (created — full spectator feed page ~750 lines)
- `app/frontend/pages/Home.tsx` (modified — added "watch" link)
- `app/controllers/pages_controller.rb` (modified — added feed action with Inertia props)
- `config/routes.rb` (modified — added feed route)
- `app/services/spectator_event_formatter.rb` (modified — added agent_id, agent_name, location_name)
- `config/puma.rb` (modified — threads 3→10)

### Phase 17
- `app/frontend/pages/World.tsx` (created — world overview page with location cards grid)
- `app/controllers/pages_controller.rb` (modified — added world action)
- `config/routes.rb` (modified — added world route)
- `app/frontend/types/events.ts` (modified — added WorldLocationInfo type)
- `app/frontend/pages/Feed.tsx` (modified — URL deep linking + nav links)
- `app/frontend/pages/Home.tsx` (modified — added feed/world/docs/source nav links)
- `test/controllers/pages_controller_test.rb` (created — 4 smoke tests)

### Phase 18
- `app/frontend/pages/AgentProfile.tsx` (created — agent profile page)
- `app/controllers/pages_controller.rb` (modified — agent_profile action + serialize_agent_profile + stamina_label)
- `config/routes.rb` (modified — added agents/:id route)
- `app/frontend/types/events.ts` (modified — AgentProfileData, AgentProfileReflection, AgentProfileStats types)
- `app/frontend/pages/World.tsx` (modified — agent links to /agents/:id)
- `app/frontend/pages/Feed.tsx` (modified — "full profile" link in AgentDetailPanel)
- `test/controllers/pages_controller_test.rb` (modified — 2 new tests)

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
- Inline relationship updates (not tick-based) — lightweight DB writes, no batch processing needed
- ConversationService hooks (not ActionService) — closer to interaction logic, reusable across code paths
- `reflected_upon` flag coordinates both paths: agent reflects → marks observed, platform skips already-reflected
- Platform fallback uses simple template patterns (no LLM) — location frequency + agent interaction frequency
- Instant trade (no proposal/acceptance) — simpler for MVP, agents can just give resources to co-located agents
- Exhaustion enforced in ActionService.validate! (not a separate agent status) — energy=0 restricts to wait/move/rest/eat
- Resource decay inline in tick listener, events only on thresholds (energy/food hitting 0) to reduce noise
- Market bonus every 720 ticks using Location.by_type("commerce")
- Redis counter for slow stamina regen — only DB query every 180th tick, 179/180 ticks cost just a Redis INCR
- Fixed-window rate limiting (INCR+EXPIRE in MULTI) over sliding window — simpler, sufficient for game simulation
- Shared "data" rate limit bucket across data endpoints — simpler than per-endpoint limits
- Stamina=0 guard separate from energy=0 exhaustion guard — different allowed action sets
- Polling-based SSE (1s DB poll) over Redis pub/sub — simpler, no channel infrastructure, 1s latency fine for 5s tick
- SpectateController inherits ActionController::API directly (not BaseController) — avoids authenticate_agent! for public endpoints
- Frontend polling (2s fetch) over SSE EventSource — EventSource holds Puma threads indefinitely via ActionController::Live blocking loop, consuming all threads and making server unresponsive
- SpectatorEventFormatter enriched with structured agent_id/agent_name/location_name — frontend uses IDs for filtering instead of parsing human-readable messages
- Inertia page over API endpoint for World Overview — reuses existing PagesController + serialize_agent pattern, no new endpoint needed
- URL deep linking via history.replaceState (not pushState) — avoids polluting back button history with every filter change
- MiniBar/ConnectionStatus duplicated in World.tsx rather than extracted to shared components — startup simplicity, extract when needed

## Lessons Learned
- Parallel tests sharing Redis need process-scoped keys for isolation
- sidekiq-scheduler is not designed for sub-minute precision (polls every ~5s itself)
- DB schema already had left_at_tick/ended_at_tick columns — always check schema before planning migrations
- PostgreSQL triggers defined in migrations don't carry into test DB via schema.rb — need to backfill tsvector in test setup
- ts_rank returns very small values (0.03-0.1 range) — must normalize within candidate set for scoring weights to work meaningfully
- ActionController::Live SSE endpoints with blocking loops (sleep in loop) consume Puma threads permanently — each browser tab/reconnect burns a thread. With default 3 threads, 3 SSE connections = completely unresponsive server. Polling is the safer approach for Puma.
