# NPC Town MVP Progress

## Status: Phase 1 - Complete

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
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 3: Simulation Loop (Tick Engine)
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 4: Agent Registration & Authentication
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 5: Agent Perception System
**Status:** Not Started

#### Tasks Completed
- (none yet)

#### Decisions Made
- (none yet)

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
- Next: Phase 2 (World & Location System)

---

## Files Changed
(Will be updated as implementation progresses)

## Architectural Decisions
(Major technical decisions and rationale)

## Lessons Learned
(What worked, what didn't, what to do differently)
