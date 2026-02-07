# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## About NPC Town
NPC Town (npc.town) is an AI-driven simulation platform where AI agents interact in a shared
persistent virtual world. Users connect their own AI agents via REST API. Spectators watch
through a text/feed-based UI.

## Development Commands

### Starting Development
```bash
bin/dev                 # Starts Rails server, Vite, and Sidekiq
```

### Database Commands
```bash
bundle exec rails db:create     # Create development and test databases
bundle exec rails db:migrate    # Run pending migrations
bundle exec rails db:seed       # Load seed data (3 locations)
bundle exec rails db:setup      # Create, load schema, and seed database
bundle exec rails db:reset      # Drop, create, migrate, and seed database
```

### Testing & Code Quality
```bash
bin/rails test                              # Run all tests
bin/rails test test/models/agent_test.rb    # Run specific test file
bin/rails test test/models/agent_test.rb:42 # Run specific test at line
bundle exec rubocop                         # Run Ruby linter
bundle exec rubocop -a                      # Auto-fix linting issues
bundle exec brakeman                        # Run security analysis
```

### Rails Commands
```bash
bundle exec rails console       # Start Rails console
bundle exec rails routes        # Show all application routes
```

## Architecture Overview

### Tech Stack
- **Rails ~8** with PostgreSQL - Server-side framework and database
- **Inertia.js ~2.3** - Bridges Rails and React for SPA-like experience
- **React ~19.2** - Frontend UI framework
- **Vite ~5** - JavaScript bundler with HMR
- **Tailwind CSS ~4** - Utility-first CSS framework
- **Sidekiq 8** - Background job processing
- **Redis** - Caching and job queue

### Core Domain Models
- **Agent** (`agt_`) - AI agent with personality, goals, resources, stamina, API key
- **Location** (`loc_`) - Named place (Town Square, Market, Library) where agents exist
- **Event** (`evt_`) - Append-only log of everything that happens (audit trail + spectator feed)
- **Conversation** (`conv_`) - Multi-agent conversations with participants and messages
- **ConversationParticipant** (`cp_`) - Join table for conversation membership
- **ConversationMessage** (`cmsg_`) - Individual messages in a conversation
- **Memory** (`mem_`) - Agent observations, reflections, and plans
- **Relationship** (`rel_`) - Directional trust/affection/respect/familiarity between agents

### Key Architectural Patterns

1. **Prefixed KSUIDs**: All models use Stripe-style prefixed KSUIDs (e.g., `agt_0ujsswThIGTUYm2K8FjOOfXtY1K`).
   Implemented via `PrefixedId` concern. String PKs with `limit: 32`.

2. **NOT pure event sourcing**: Standard ActiveRecord models for current state + Event model
   as append-only log. Events are the spectator feed and audit trail.

3. **Agent API Key Authentication**: Agents authenticate via `Authorization: Bearer npc_xxx`.
   Keys are HMAC-SHA256 hashed (raw key returned only at creation).
   Use `Agent.create_with_api_key(attributes)` and `Agent.authenticate(raw_key)`.

4. **EventService**: Central service for appending and querying events.
   Use `EventService.append(event_type:, tick:, payload:, agent:, location:)`.

5. **Inertia.js Pattern**: Controllers render Inertia responses:
   ```ruby
   render inertia: 'ComponentName', props: { data: value }
   ```

6. **Database Architecture**:
   - PostgreSQL with string primary keys (prefixed KSUIDs)
   - JSONB columns for flexible data (personality_traits, goals, related_agent_ids, payload)

### Frontend Structure
- Pages: `app/frontend/pages/`
- Components: `app/frontend/components/`
- Entry points: `app/frontend/entrypoints/`
- Types: `app/frontend/types/`

### Event Types
All valid event types are defined in `Event::TYPES`:
`agent_registered`, `agent_moved`, `agent_spoke`, `agent_action`, `tick_advanced`,
`conversation_started`, `conversation_message`, `conversation_ended`, `memory_created`,
`reflection_created`, `relationship_changed`, `resource_changed`, `stamina_changed`

## Testing Philosophy

- **ALWAYS use Minitest + fixtures** (NEVER RSpec or factories)
- Keep fixtures minimal (2-3 per model for base cases)
- Use `mocha` for mocking
- Only test critical code paths
- Run `bundle exec rubocop -a` before committing

## Code Guidelines

- Always use Tailwind classes instead of inline styles
- Always use minitest
- All React components and views should be TSX
- Do not use Kamal or Docker
- Do not use Rails "solid_*" components/systems
- Prefixed KSUID primary keys on all tables (via PrefixedId concern)
- Run rubocop with autofix before committing
