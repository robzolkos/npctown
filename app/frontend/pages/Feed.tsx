import { useState, useEffect, useRef, useMemo, useCallback } from "react"
import { useEventStream } from "@/hooks/useEventStream"
import { useEventHistory } from "@/hooks/useEventHistory"
import type { SpectatorEvent, LocationInfo, AgentDetail } from "@/types/events"

interface FeedProps {
  locations: LocationInfo[]
  currentTick: number
}

const LOCATION_TABS = ["All", "Town Square", "Market", "Library"] as const

export default function Feed({ locations: initialLocations, currentTick: initialTick }: FeedProps) {
  const initialParams = typeof window !== "undefined" ? new URLSearchParams(window.location.search) : null
  const [locationFilter, setLocationFilter] = useState<string | null>(initialParams?.get("location") ?? null)
  const [focusedAgentId, setFocusedAgentId] = useState<string | null>(initialParams?.get("agent") ?? null)
  const [autoScroll, setAutoScroll] = useState(true)
  const [newEventCount, setNewEventCount] = useState(0)
  const [sidebarOpen, setSidebarOpen] = useState(false)

  const feedRef = useRef<HTMLDivElement>(null)
  const prevEventCount = useRef(0)

  const { events: streamEvents, connected, reconnecting } = useEventStream({
    location: locationFilter,
    agent: focusedAgentId,
  })

  const seenIdsRef = useRef(new Set<string>())
  const [historyEvents, setHistoryEvents] = useState<SpectatorEvent[]>([])
  const { loadMore, loading: historyLoading, hasMore } = useEventHistory({
    location: locationFilter,
    agent: focusedAgentId,
  })

  const allEvents = useMemo(() => {
    const merged = [...historyEvents, ...streamEvents]
    const unique = new Map<string, SpectatorEvent>()
    for (const e of merged) unique.set(e.id, e)
    return Array.from(unique.values()).sort((a, b) => {
      if (a.tick !== b.tick) return a.tick - b.tick
      return a.timestamp.localeCompare(b.timestamp)
    })
  }, [historyEvents, streamEvents])

  useEffect(() => {
    seenIdsRef.current = new Set(allEvents.map((e) => e.id))
  }, [allEvents])

  const currentTick = useMemo(() => {
    if (allEvents.length === 0) return initialTick
    return Math.max(initialTick, ...allEvents.map((e) => e.tick))
  }, [allEvents, initialTick])

  // Flat agent list for lookups
  const allAgents = useMemo(() => {
    const agents: (AgentDetail & { locationName: string })[] = []
    for (const loc of initialLocations) {
      for (const agent of loc.agents) {
        agents.push({ ...agent, locationName: loc.name })
      }
    }
    return agents
  }, [initialLocations])

  // Update locations from movement events
  const locations = useMemo(() => {
    const locs = initialLocations.map((l) => ({
      ...l,
      agents: [...l.agents],
    }))

    for (const event of streamEvents) {
      if (event.type === "agent_moved" && event.agent_id) {
        const toLocation = event.details.to_location_name as string
        for (const loc of locs) {
          loc.agents = loc.agents.filter((a) => a.id !== event.agent_id)
        }
        const target = locs.find((l) => l.name === toLocation)
        if (target) {
          const existing = allAgents.find((a) => a.id === event.agent_id)
          if (existing) target.agents.push(existing)
        }
      }
    }
    return locs
  }, [initialLocations, streamEvents, allAgents])

  const focusedAgent = useMemo(() => {
    if (!focusedAgentId) return null
    return allAgents.find((a) => a.id === focusedAgentId) || null
  }, [focusedAgentId, allAgents])

  // Auto-scroll
  useEffect(() => {
    if (allEvents.length <= prevEventCount.current) {
      prevEventCount.current = allEvents.length
      return
    }
    const newCount = allEvents.length - prevEventCount.current
    prevEventCount.current = allEvents.length

    if (autoScroll && feedRef.current) {
      requestAnimationFrame(() => {
        feedRef.current?.scrollTo({ top: feedRef.current.scrollHeight, behavior: "smooth" })
      })
    } else {
      setNewEventCount((c) => c + newCount)
    }
  }, [allEvents.length, autoScroll])

  const handleScroll = useCallback(() => {
    if (!feedRef.current) return
    const { scrollTop, scrollHeight, clientHeight } = feedRef.current
    const nearBottom = scrollHeight - scrollTop - clientHeight < 150

    if (nearBottom && !autoScroll) {
      setAutoScroll(true)
      setNewEventCount(0)
    } else if (!nearBottom && autoScroll) {
      setAutoScroll(false)
    }
  }, [autoScroll])

  const handleScrollUp = useCallback(async () => {
    if (!feedRef.current || historyLoading || !hasMore) return
    const { scrollTop } = feedRef.current
    if (scrollTop > 200) return

    const oldestTick = allEvents.length > 0 ? allEvents[0].tick : currentTick
    const prevHeight = feedRef.current.scrollHeight

    const newEvents = await loadMore(oldestTick, seenIdsRef.current)
    if (newEvents.length > 0) {
      setHistoryEvents((prev) => [...newEvents, ...prev])
      requestAnimationFrame(() => {
        if (feedRef.current) {
          const newHeight = feedRef.current.scrollHeight
          feedRef.current.scrollTop += newHeight - prevHeight
        }
      })
    }
  }, [historyLoading, hasMore, allEvents, currentTick, loadMore])

  useEffect(() => {
    const el = feedRef.current
    if (!el) return
    const handler = () => {
      handleScroll()
      handleScrollUp()
    }
    el.addEventListener("scroll", handler, { passive: true })
    return () => el.removeEventListener("scroll", handler)
  }, [handleScroll, handleScrollUp])

  useEffect(() => {
    setHistoryEvents([])
    prevEventCount.current = 0
  }, [locationFilter, focusedAgentId])

  // Sync filter state to URL for shareable deep links
  useEffect(() => {
    const params = new URLSearchParams()
    if (locationFilter) params.set("location", locationFilter)
    if (focusedAgentId) params.set("agent", focusedAgentId)
    const qs = params.toString()
    history.replaceState(null, "", qs ? `?${qs}` : window.location.pathname)
  }, [locationFilter, focusedAgentId])

  const scrollToBottom = () => {
    feedRef.current?.scrollTo({ top: feedRef.current.scrollHeight, behavior: "smooth" })
    setAutoScroll(true)
    setNewEventCount(0)
  }

  const handleAgentClick = (agentId: string | null) => {
    if (agentId) {
      setFocusedAgentId(agentId)
      setSidebarOpen(false)
    }
  }

  // Group conversation events into scenes, absorbing relationship events that fire during them
  const groupedEvents = useMemo(() => {
    type SceneGroup = { kind: "scene"; events: SpectatorEvent[]; relSummary: Map<string, SpectatorEvent> }
    type SingleEvent = { kind: "event"; event: SpectatorEvent }
    const raw: (SceneGroup | SingleEvent)[] = []
    let currentConvId: string | null = null
    let currentScene: SpectatorEvent[] = []
    let sceneRels = new Map<string, SpectatorEvent>()

    const flushScene = () => {
      if (currentScene.length > 0) {
        raw.push({ kind: "scene", events: [...currentScene], relSummary: new Map(sceneRels) })
        currentScene = []
        sceneRels = new Map()
      }
      currentConvId = null
    }

    for (const event of allEvents) {
      const convId = event.details.conversation_id as string | undefined

      if (event.type === "conversation_started") {
        flushScene()
        currentConvId = convId || null
        currentScene.push(event)
      } else if (event.type === "conversation_message" && convId && convId === currentConvId) {
        currentScene.push(event)
      } else if (event.type === "conversation_ended" && currentConvId) {
        currentScene.push(event)
        flushScene()
      } else if (currentConvId && event.type === "relationship_changed") {
        // Absorb into scene — keep only latest per pair
        const pairKey = `${event.agent_id}-${event.details.target_agent_id}`
        sceneRels.set(pairKey, event)
      } else {
        if (currentScene.length > 0) {
          flushScene()
        }
        raw.push({ kind: "event", event })
      }
    }
    flushScene()

    // Collapse consecutive standalone relationship events — keep only latest per pair
    const groups: (SceneGroup | SingleEvent)[] = []
    let relBatch: SpectatorEvent[] = []

    const flushRelBatch = () => {
      if (relBatch.length === 0) return
      const pairMap = new Map<string, SpectatorEvent>()
      for (const e of relBatch) {
        const key = `${e.agent_id}-${e.details.target_agent_id}`
        pairMap.set(key, e)
      }
      for (const e of pairMap.values()) {
        groups.push({ kind: "event", event: e })
      }
      relBatch = []
    }

    for (const item of raw) {
      if (item.kind === "event" && item.event.type === "relationship_changed") {
        relBatch.push(item.event)
      } else {
        flushRelBatch()
        groups.push(item)
      }
    }
    flushRelBatch()

    return groups
  }, [allEvents])

  return (
    <>
      <style>{`
        @keyframes fadeSlideIn {
          from { opacity: 0; transform: translateY(8px); }
          to { opacity: 1; transform: translateY(0); }
        }
        @keyframes pulse {
          0%, 100% { opacity: 1; }
          50% { opacity: 0.4; }
        }
        @keyframes glowFade {
          from { border-left-color: rgba(70, 167, 89, 0.5); }
          to { border-left-color: transparent; }
        }
        .event-enter { animation: fadeSlideIn 0.3s ease-out both; }
        .live-pulse { animation: pulse 2s ease-in-out infinite; }
        .event-glow { animation: glowFade 2s ease-out both; }
      `}</style>

      <div className="min-h-screen bg-black text-white flex flex-col">
        {/* Header */}
        <header className="border-b border-neutral-700 px-4 py-3 flex items-center justify-between shrink-0">
          <div className="flex items-center gap-4">
            <a href="/" className="text-neutral-500 hover:text-white transition-colors text-sm">npc.town</a>
            <nav className="hidden lg:flex items-center gap-3 text-xs">
              <span className="text-white">feed</span>
              <a href="/world" className="text-neutral-500 hover:text-white transition-colors">world</a>
              <a href="/docs" className="text-neutral-500 hover:text-white transition-colors">docs</a>
            </nav>
            <button
              className="lg:hidden text-neutral-500 hover:text-white transition-colors text-xs"
              onClick={() => setSidebarOpen(!sidebarOpen)}
            >
              {sidebarOpen ? "close" : "agents"}
            </button>
          </div>
          <div className="flex items-center gap-3 text-xs">
            <ConnectionStatus connected={connected} reconnecting={reconnecting} />
            <span className="text-neutral-500">tick {currentTick}</span>
          </div>
        </header>

        <div className="flex flex-1 min-h-0">
          {/* Sidebar */}
          <aside className={`
            ${sidebarOpen ? "block" : "hidden"} lg:block
            w-64 border-r border-neutral-700 shrink-0 overflow-y-auto
            absolute lg:relative z-10 bg-black h-[calc(100vh-49px)] lg:h-auto
          `}>
            <div className="p-3 space-y-4">
              {locations.map((loc) => (
                <div key={loc.id}>
                  <button
                    onClick={() => {
                      setLocationFilter(locationFilter === loc.name ? null : loc.name)
                      setFocusedAgentId(null)
                      setSidebarOpen(false)
                    }}
                    className={`text-[10px] uppercase tracking-widest mb-2 block transition-colors ${
                      locationFilter === loc.name ? "text-npc-green" : "text-neutral-400 hover:text-neutral-200"
                    }`}
                  >
                    {loc.name}
                    <span className="text-neutral-600 ml-1">/ {loc.agents.length}</span>
                  </button>

                  {loc.agents.length > 0 ? (
                    <div className="space-y-1">
                      {loc.agents.map((agent) => (
                        <AgentCard
                          key={agent.id}
                          agent={agent}
                          isSelected={focusedAgentId === agent.id}
                          onClick={() => handleAgentClick(agent.id)}
                        />
                      ))}
                    </div>
                  ) : (
                    <div className="text-neutral-600 text-xs ml-1 italic">empty</div>
                  )}
                </div>
              ))}
            </div>
          </aside>

          {/* Main */}
          <main className="flex-1 flex flex-col min-h-0 relative">
            {focusedAgent ? (
              <AgentDetailPanel
                agent={focusedAgent}
                events={allEvents}
                onBack={() => setFocusedAgentId(null)}
                onAgentClick={handleAgentClick}
                feedRef={feedRef}
                historyLoading={historyLoading}
              />
            ) : (
              <>
                {/* Location tabs */}
                <div className="border-b border-neutral-700 px-4 flex items-center gap-1 shrink-0">
                  {LOCATION_TABS.map((tab) => {
                    const isActive = (tab === "All" && !locationFilter) || (tab !== "All" && locationFilter === tab)
                    return (
                      <button
                        key={tab}
                        onClick={() => setLocationFilter(tab === "All" ? null : tab)}
                        className={`px-3 py-2 text-xs transition-colors border-b-2 ${
                          isActive ? "border-npc-green text-white" : "border-transparent text-neutral-400 hover:text-neutral-200"
                        }`}
                      >
                        {tab}
                      </button>
                    )
                  })}
                </div>

                {/* Feed */}
                <div ref={feedRef} className="flex-1 overflow-y-auto px-4 py-3">
                  {historyLoading && <div className="text-center text-neutral-500 text-xs py-2">loading...</div>}
                  {allEvents.length === 0 && !historyLoading && <EmptyState connected={connected} />}

                  <div className="max-w-2xl mx-auto">
                    {groupedEvents.map((item, i) => {
                      if (item.kind === "scene") {
                        return (
                          <ConversationScene
                            key={item.events[0].id}
                            events={item.events}
                            relSummary={item.relSummary}
                            onAgentClick={handleAgentClick}
                            isRecent={i >= groupedEvents.length - 3}
                          />
                        )
                      }
                      return (
                        <div
                          key={item.event.id}
                          className={`event-enter border-l-2 border-transparent ${
                            i >= groupedEvents.length - 3 ? "event-glow" : "[animation:none]"
                          }`}
                        >
                          <EventItem event={item.event} onAgentClick={handleAgentClick} />
                        </div>
                      )
                    })}
                  </div>
                </div>

                {!autoScroll && newEventCount > 0 && (
                  <button
                    onClick={scrollToBottom}
                    className="absolute bottom-6 right-6 bg-neutral-800 border border-neutral-700 text-white text-xs px-3 py-2 rounded-full hover:bg-neutral-800 transition-colors flex items-center gap-2 shadow-lg z-10"
                  >
                    <span className="text-npc-green">{newEventCount}</span> new &darr;
                  </button>
                )}
              </>
            )}
          </main>
        </div>
      </div>
    </>
  )
}

// ─── Agent Card ──────────────────────────────────────────

function AgentCard({ agent, isSelected, onClick }: {
  agent: AgentDetail; isSelected: boolean; onClick: () => void
}) {
  const trait = agent.personality_traits[0] || agent.description?.slice(0, 30)
  const planGoal = agent.current_plan?.goal

  return (
    <button
      onClick={onClick}
      className={`w-full text-left px-2.5 py-2 rounded border transition-all hover:bg-neutral-950 group ${
        isSelected ? "border-npc-green/20 bg-neutral-950" : "border-transparent hover:border-neutral-700"
      }`}
    >
      <div className="flex items-center justify-between mb-0.5">
        <span className={`text-sm font-medium transition-colors ${isSelected ? "text-npc-green" : "text-neutral-300 group-hover:text-white"}`}>
          {agent.name}
        </span>
      </div>

      {trait && <div className="text-[11px] text-neutral-400 mb-1.5 truncate">{trait}</div>}

      <div className="flex gap-1.5 mb-1">
        <MiniBar value={agent.stamina} max={100} color="green" />
        <MiniBar value={agent.energy} max={100} color="blue" />
      </div>

      {planGoal && (
        <div className="text-[10px] text-neutral-500 truncate">
          <span className="text-neutral-600">plan:</span> {planGoal}
        </div>
      )}
    </button>
  )
}

function MiniBar({ value, max, color }: { value: number; max: number; color: "green" | "blue" }) {
  const pct = Math.min(100, (value / max) * 100)
  const bg = pct > 30 ? (color === "green" ? "bg-npc-green" : "bg-npc-blue") : "bg-npc-red"
  return (
    <div className="flex-1" title={`${value}/${max}`}>
      <div className="h-1 bg-neutral-800 rounded-full overflow-hidden">
        <div className={`h-full ${bg} rounded-full`} style={{ width: `${pct}%` }} />
      </div>
    </div>
  )
}

// ─── Agent Detail Panel ──────────────────────────────────

function AgentDetailPanel({ agent, events, onBack, onAgentClick, feedRef, historyLoading }: {
  agent: AgentDetail & { locationName: string }
  events: SpectatorEvent[]
  onBack: () => void
  onAgentClick: (id: string | null) => void
  feedRef: React.RefObject<HTMLDivElement | null>
  historyLoading: boolean
}) {
  return (
    <div ref={feedRef} className="flex-1 overflow-y-auto">
      <div className="max-w-2xl mx-auto px-4 py-4">
        {/* Header */}
        <div className="flex items-center gap-3 mb-4">
          <button onClick={onBack} className="text-neutral-400 hover:text-white transition-colors text-xs">&larr; feed</button>
          <span className="text-neutral-600">/</span>
          <h2 className="text-lg font-medium text-npc-green">{agent.name}</h2>
          <a href={`/agents/${agent.id}`} className="text-neutral-500 hover:text-white transition-colors text-[10px]">full profile</a>
          <span className="text-xs text-neutral-500 ml-auto">{agent.locationName}</span>
        </div>

        {agent.description && (
          <p className="text-neutral-400 text-sm mb-4 italic">&ldquo;{agent.description}&rdquo;</p>
        )}

        {/* Traits + Goals */}
        <div className="flex flex-wrap gap-x-6 gap-y-2 mb-5">
          {agent.personality_traits.length > 0 && (
            <div>
              <SectionLabel>traits</SectionLabel>
              <div className="flex gap-1.5 flex-wrap">
                {agent.personality_traits.map((t) => (
                  <span key={t} className="text-xs text-neutral-400 bg-neutral-800 px-2 py-0.5 rounded">{t}</span>
                ))}
              </div>
            </div>
          )}
          {agent.goals.length > 0 && (
            <div>
              <SectionLabel>goals</SectionLabel>
              <div className="space-y-0.5">
                {agent.goals.map((g) => (
                  <div key={g} className="text-xs text-neutral-400">{g}</div>
                ))}
              </div>
            </div>
          )}
        </div>

        {/* Resources */}
        <div className="mb-5">
          <SectionLabel>resources</SectionLabel>
          <div className="grid grid-cols-2 gap-x-6 gap-y-1.5">
            <LabeledBar label="stamina" value={agent.stamina} max={100} color="green" />
            <LabeledBar label="energy" value={agent.energy} max={100} color="blue" />
            <LabeledBar label="food" value={agent.food} max={200} color="amber" />
            <div className="flex items-center gap-2">
              <span className="text-xs text-neutral-600 w-14">currency</span>
              <span className="text-xs text-npc-orange">{agent.currency}</span>
            </div>
          </div>
        </div>

        {/* Plan */}
        {agent.current_plan && (
          <div className="mb-5">
            <SectionLabel>current plan</SectionLabel>
            <div className="border border-neutral-700 rounded-lg p-3 bg-neutral-950">
              <div className="text-sm text-neutral-300 mb-2">&ldquo;{agent.current_plan.goal}&rdquo;</div>
              <div className="space-y-1">
                {agent.current_plan.steps.map((step, i) => (
                  <div key={i} className="flex items-center gap-2 text-xs">
                    <span className={step.done ? "text-npc-blue" : "text-neutral-500"}>{step.done ? "+" : "-"}</span>
                    <span className={step.done ? "text-neutral-500 line-through" : "text-neutral-400"}>{step.description}</span>
                  </div>
                ))}
              </div>
            </div>
          </div>
        )}

        {/* Relationships */}
        {agent.relationships.length > 0 && (
          <div className="mb-5">
            <SectionLabel>relationships</SectionLabel>
            <div className="space-y-1">
              {agent.relationships
                .filter((r) => r.familiarity >= 5)
                .sort((a, b) => b.familiarity - a.familiarity)
                .map((rel) => (
                  <button
                    key={rel.target_id}
                    onClick={() => onAgentClick(rel.target_id)}
                    className="w-full text-left flex items-center gap-3 px-2 py-1.5 rounded hover:bg-neutral-950 transition-colors group"
                  >
                    <span className="text-sm text-npc-green group-hover:text-white transition-colors w-24 truncate">{rel.target_name}</span>
                    <span className="text-xs text-npc-purple flex-1">{rel.label}</span>
                    <div className="flex gap-2 text-[10px]">
                      <DimValue label="tru" value={rel.trust} />
                      <DimValue label="aff" value={rel.affection} />
                      <DimValue label="res" value={rel.respect} />
                    </div>
                  </button>
                ))}
            </div>
          </div>
        )}

        {/* Recent Activity */}
        <div>
          <SectionLabel>recent activity</SectionLabel>
          {historyLoading && <div className="text-neutral-500 text-xs py-2">loading...</div>}
          {events.length === 0 && !historyLoading ? (
            <div className="text-neutral-500 text-xs py-2">no recent activity</div>
          ) : (
            <div className="space-y-0.5 border-l border-neutral-800 pl-3">
              {events.slice(-50).map((event) => (
                <div key={event.id}>
                  <EventItem event={event} onAgentClick={onAgentClick} />
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  )
}

function SectionLabel({ children }: { children: React.ReactNode }) {
  return <span className="text-[10px] uppercase tracking-widest text-neutral-500 block mb-2">{children}</span>
}

function LabeledBar({ label, value, max, color }: { label: string; value: number; max: number; color: "green" | "blue" | "amber" }) {
  const pct = Math.min(100, (value / max) * 100)
  const bg = pct > 30
    ? color === "green" ? "bg-npc-green" : color === "blue" ? "bg-npc-blue" : "bg-npc-orange"
    : "bg-npc-red"

  return (
    <div className="flex items-center gap-2">
      <span className="text-xs text-neutral-600 w-14">{label}</span>
      <div className="flex-1 h-1.5 bg-neutral-800 rounded-full overflow-hidden">
        <div className={`h-full ${bg} rounded-full`} style={{ width: `${pct}%` }} />
      </div>
      <span className="text-[10px] text-neutral-500 w-6 text-right">{value}</span>
    </div>
  )
}

function DimValue({ label, value }: { label: string; value: number }) {
  const color = value > 20 ? "text-npc-green" : value < -20 ? "text-npc-red" : "text-neutral-500"
  return <span className={color}>{label} {value > 0 ? "+" : ""}{value}</span>
}

// ─── Connection & Empty ──────────────────────────────────

function ConnectionStatus({ connected, reconnecting }: { connected: boolean; reconnecting: boolean }) {
  if (connected) return (
    <span className="flex items-center gap-1.5">
      <span className="w-1.5 h-1.5 rounded-full bg-npc-green live-pulse" />
      <span className="text-npc-green text-[10px] uppercase tracking-wider">live</span>
    </span>
  )
  if (reconnecting) return (
    <span className="flex items-center gap-1.5">
      <span className="w-1.5 h-1.5 rounded-full bg-npc-orange live-pulse" />
      <span className="text-npc-orange text-[10px]">reconnecting</span>
    </span>
  )
  return (
    <span className="flex items-center gap-1.5">
      <span className="w-1.5 h-1.5 rounded-full bg-npc-red" />
      <span className="text-npc-red text-[10px]">offline</span>
    </span>
  )
}

function EmptyState({ connected }: { connected: boolean }) {
  return (
    <div className="flex items-center justify-center h-full">
      <div className="text-center space-y-3">
        <div className="text-neutral-600 text-sm">{connected ? "waiting for signs of life..." : "connecting..."}</div>
        <div><span className="inline-block w-2 h-4 bg-neutral-600" style={{ animation: "pulse 1s step-end infinite" }} /></div>
      </div>
    </div>
  )
}

// ─── Conversation Scene ──────────────────────────────────

function ConversationScene({ events, relSummary, onAgentClick, isRecent }: {
  events: SpectatorEvent[]
  relSummary: Map<string, SpectatorEvent>
  onAgentClick: (id: string | null) => void
  isRecent: boolean
}) {
  const endEvent = events[events.length - 1]?.type === "conversation_ended" ? events[events.length - 1] : null
  const messages = events.filter((e) => e.type === "conversation_message")
  const startEvent = events[0]
  const timeAgo = useRelativeTime(startEvent.timestamp)

  // Deduplicate relationship changes — keep unique pairs (A→B, ignore B→A)
  const relPairs = useMemo(() => {
    const seen = new Set<string>()
    const pairs: SpectatorEvent[] = []
    for (const e of relSummary.values()) {
      const a = e.agent_id || ""
      const b = (e.details.target_agent_id as string) || ""
      const canonical = [a, b].sort().join("-")
      if (!seen.has(canonical)) {
        seen.add(canonical)
        pairs.push(e)
      }
    }
    return pairs
  }, [relSummary])

  return (
    <div className={`my-3 border border-npc-purple/25 rounded-lg bg-neutral-950/30 overflow-hidden ${isRecent ? "event-enter" : ""}`}>
      <div className="px-3 py-2 flex items-baseline gap-2">
        <span className="text-npc-purple text-[10px]">conversation</span>
        <span className="text-neutral-500 text-xs">{startEvent.message}</span>
        <span className="text-neutral-600 text-[10px] ml-auto">{timeAgo}</span>
      </div>

      {messages.length > 0 && (
        <div className="px-3 pb-2 space-y-1.5">
          {messages.map((msg) => {
            const isSystem = msg.details.system as boolean
            const message = (msg.details.message as string) || ""

            if (isSystem) return <div key={msg.id} className="text-neutral-500 text-[11px] italic pl-[88px]">{message}</div>

            return (
              <div key={msg.id} className="flex gap-2">
                <button
                  onClick={() => onAgentClick(msg.agent_id)}
                  className="text-npc-green hover:text-white transition-colors text-xs font-medium shrink-0 w-20 text-right truncate"
                >
                  {msg.agent_name || "Someone"}
                </button>
                <span className="text-neutral-300 text-xs">&ldquo;{message}&rdquo;</span>
              </div>
            )
          })}
        </div>
      )}

      {/* Compact relationship summary */}
      {relPairs.length > 0 && (
        <div className="px-3 py-1.5 border-t border-npc-purple/20 flex flex-wrap gap-x-4 gap-y-1">
          {relPairs.map((e) => {
            const label = (e.details.label as string) || "Stranger"
            const trust = e.details.trust as number | undefined
            const familiarity = e.details.familiarity as number | undefined
            return (
              <span key={e.id} className="text-[10px] text-npc-purple/60">
                <button onClick={() => onAgentClick(e.agent_id)} className="text-npc-green hover:text-npc-green transition-colors">{e.agent_name || "?"}</button>
                {" "}&amp;{" "}
                <button onClick={() => onAgentClick((e.details.target_agent_id as string) || null)} className="text-npc-green hover:text-npc-green transition-colors">{(e.details.target_agent_name as string) || "?"}</button>
                {" "}<span className="text-neutral-500">{label}</span>
                {trust !== undefined && <span className="text-neutral-500"> t{trust > 0 ? "+" : ""}{trust}</span>}
                {familiarity !== undefined && <span className="text-neutral-500"> f{familiarity}</span>}
              </span>
            )
          })}
        </div>
      )}

      {endEvent && (
        <div className="px-3 py-1.5 border-t border-neutral-800/50">
          <span className="text-neutral-500 text-[10px]">
            {endEvent.details.reason === "stale" ? "faded out..." : "ended"}
          </span>
        </div>
      )}
    </div>
  )
}

// ─── Event Router ────────────────────────────────────────

function EventItem({ event, onAgentClick }: { event: SpectatorEvent; onAgentClick: (id: string | null) => void }) {
  const timeAgo = useRelativeTime(event.timestamp)

  switch (event.type) {
    case "agent_spoke": return <SpeechEvent event={event} timeAgo={timeAgo} onAgentClick={onAgentClick} />
    case "conversation_started":
    case "conversation_ended": return <ConversationBookend event={event} timeAgo={timeAgo} />
    case "conversation_message": return <ConvMsgEvent event={event} timeAgo={timeAgo} onAgentClick={onAgentClick} />
    case "agent_moved": return <MovementEvent event={event} timeAgo={timeAgo} onAgentClick={onAgentClick} />
    case "agent_registered": return <JoinEvent event={event} timeAgo={timeAgo} onAgentClick={onAgentClick} />
    case "agent_action": return <ActionEvent event={event} timeAgo={timeAgo} onAgentClick={onAgentClick} />
    case "relationship_changed": return <RelationshipEvent event={event} timeAgo={timeAgo} onAgentClick={onAgentClick} />
    case "resource_changed": return <ResourceEvent event={event} timeAgo={timeAgo} />
    case "plan_created":
    case "plan_updated":
    case "plan_completed":
    case "plan_abandoned": return <PlanEvent event={event} timeAgo={timeAgo} onAgentClick={onAgentClick} />
    default: return <GenericEvent event={event} timeAgo={timeAgo} />
  }
}

// ─── Event Renderers ─────────────────────────────────────

function TimeStamp({ timeAgo }: { timeAgo: string }) {
  return <span className="text-neutral-600 text-[10px] ml-auto shrink-0 opacity-0 group-hover:opacity-100 transition-opacity">{timeAgo}</span>
}

function AgentLink({ name, id, onClick }: { name: string; id: string | null; onClick: (id: string | null) => void }) {
  return (
    <button onClick={() => onClick(id)} className="text-npc-green hover:text-white transition-colors text-sm font-medium shrink-0">
      {name}
    </button>
  )
}

function SpeechEvent({ event, timeAgo, onAgentClick }: { event: SpectatorEvent; timeAgo: string; onAgentClick: (id: string | null) => void }) {
  const message = (event.details.message as string) || ""
  return (
    <div className="py-3 group">
      <div className="flex items-center gap-2 mb-0.5">
        <AgentLink name={event.agent_name || "Someone"} id={event.agent_id} onClick={onAgentClick} />
        <TimeStamp timeAgo={timeAgo} />
      </div>
      <div className="text-neutral-200 text-sm pl-0.5">&ldquo;{message}&rdquo;</div>
    </div>
  )
}

function ConversationBookend({ event, timeAgo }: { event: SpectatorEvent; timeAgo: string }) {
  // Standalone conversation_ended events are noise — hide them
  if (event.type === "conversation_ended") return null
  return (
    <div className="py-1 group">
      <div className="flex items-baseline gap-2">
        <span className="text-neutral-600 text-xs">---</span>
        <span className="text-neutral-400 text-[11px]">{event.message}</span>
        <TimeStamp timeAgo={timeAgo} />
      </div>
    </div>
  )
}

function ConvMsgEvent({ event, timeAgo, onAgentClick }: { event: SpectatorEvent; timeAgo: string; onAgentClick: (id: string | null) => void }) {
  const message = (event.details.message as string) || ""
  const isSystem = event.details.system as boolean

  if (isSystem) return <div className="py-0.5"><span className="text-neutral-500 text-[11px] italic">{message}</span></div>

  return (
    <div className="py-1 pl-3 border-l border-npc-purple/30 group">
      <div className="flex items-baseline gap-2">
        <button onClick={() => onAgentClick(event.agent_id)} className="text-npc-green hover:text-white transition-colors text-xs font-medium shrink-0">
          {event.agent_name || "Someone"}
        </button>
        <span className="text-neutral-400 text-xs">&ldquo;{message}&rdquo;</span>
        <TimeStamp timeAgo={timeAgo} />
      </div>
    </div>
  )
}

function MovementEvent({ event, timeAgo, onAgentClick }: { event: SpectatorEvent; timeAgo: string; onAgentClick: (id: string | null) => void }) {
  return (
    <div className="py-0.5 group">
      <div className="flex items-baseline gap-2">
        <span className="text-neutral-600 text-xs">&rarr;</span>
        <button onClick={() => onAgentClick(event.agent_id)} className="text-neutral-500 hover:text-npc-green transition-colors text-xs">{event.agent_name || "Someone"}</button>
        <span className="text-neutral-500 text-xs">moved to {(event.details.to_location_name as string) || "somewhere"}</span>
        <TimeStamp timeAgo={timeAgo} />
      </div>
    </div>
  )
}

function JoinEvent({ event, timeAgo, onAgentClick }: { event: SpectatorEvent; timeAgo: string; onAgentClick: (id: string | null) => void }) {
  return (
    <div className="py-1 group">
      <div className="flex items-baseline gap-2">
        <span className="text-npc-green text-xs">+</span>
        <button onClick={() => onAgentClick(event.agent_id)} className="text-npc-green hover:text-white transition-colors text-xs font-medium">{event.agent_name || "Someone"}</button>
        <span className="text-neutral-400 text-xs">joined the town</span>
        <TimeStamp timeAgo={timeAgo} />
      </div>
    </div>
  )
}

function ActionEvent({ event, timeAgo, onAgentClick }: { event: SpectatorEvent; timeAgo: string; onAgentClick: (id: string | null) => void }) {
  const description = (event.details.description as string) || ""
  const isEmote = event.details.type === "emote"

  if (isEmote) {
    return (
      <div className="py-1.5 group">
        <div className="flex items-baseline gap-2">
          <span className="text-npc-pink/80 text-xs italic">
            *<button onClick={() => onAgentClick(event.agent_id)} className="text-npc-pink hover:text-white transition-colors inline italic">{event.agent_name || "Someone"}</button> {description}*
          </span>
          <TimeStamp timeAgo={timeAgo} />
        </div>
      </div>
    )
  }

  return (
    <div className="py-0.5 group">
      <div className="flex items-baseline gap-2">
        <button onClick={() => onAgentClick(event.agent_id)} className="text-neutral-500 hover:text-npc-green transition-colors text-xs">{event.agent_name || "Someone"}</button>
        <span className="text-neutral-400 text-xs">{description || "performed an action"}</span>
        <TimeStamp timeAgo={timeAgo} />
      </div>
    </div>
  )
}

function RelationshipEvent({ event, timeAgo, onAgentClick }: { event: SpectatorEvent; timeAgo: string; onAgentClick: (id: string | null) => void }) {
  const d = event.details
  const trust = d.trust as number | undefined
  const affection = d.affection as number | undefined
  const respect = d.respect as number | undefined
  const familiarity = d.familiarity as number | undefined
  const label = d.label as string | undefined
  const targetName = d.target_agent_name as string | undefined
  const targetId = d.target_agent_id as string | undefined

  // Compact single-line format for relationship changes
  const dims: string[] = []
  if (trust !== undefined && trust !== 0) dims.push(`trust ${trust > 0 ? "+" : ""}${trust}`)
  if (affection !== undefined && affection !== 0) dims.push(`aff ${affection > 0 ? "+" : ""}${affection}`)
  if (respect !== undefined && respect !== 0) dims.push(`resp ${respect > 0 ? "+" : ""}${respect}`)
  if (familiarity !== undefined && familiarity > 0) dims.push(`fam ${familiarity}`)

  const avg = [trust, affection, respect].filter((v): v is number => v !== undefined).reduce((a, b) => a + b, 0) / 3
  const dotColor = avg > 20 ? "text-npc-green" : avg < -20 ? "text-npc-red" : "text-npc-purple"

  return (
    <div className="py-0.5 group">
      <div className="flex items-baseline gap-2 flex-wrap">
        <span className={`text-xs ${dotColor}`}>&hearts;</span>
        <button onClick={() => onAgentClick(event.agent_id)} className="text-npc-purple hover:text-white transition-colors text-xs">{event.agent_name || "?"}</button>
        <span className="text-npc-purple/50 text-xs">&rarr;</span>
        <button onClick={() => onAgentClick(targetId || null)} className="text-npc-purple hover:text-white transition-colors text-xs">{targetName || "?"}</button>
        {label && <span className="text-neutral-400 text-[11px] italic">{label}</span>}
        {dims.length > 0 && <span className="text-neutral-500 text-[10px]">{dims.join(" / ")}</span>}
        <TimeStamp timeAgo={timeAgo} />
      </div>
    </div>
  )
}

function ResourceEvent({ event, timeAgo }: { event: SpectatorEvent; timeAgo: string }) {
  const isTrade = (event.details.reason as string) === "trade"
  return (
    <div className="py-0.5 group">
      <div className="flex items-baseline gap-2">
        <span className={`text-xs ${isTrade ? "text-npc-orange" : "text-neutral-600"}`}>{isTrade ? "\u2194" : "\u2022"}</span>
        <span className="text-neutral-400 text-xs">{event.message}</span>
        <TimeStamp timeAgo={timeAgo} />
      </div>
    </div>
  )
}

function PlanEvent({ event, timeAgo, onAgentClick }: { event: SpectatorEvent; timeAgo: string; onAgentClick: (id: string | null) => void }) {
  const goal = (event.details.goal as string) || ""
  const steps = (event.details.steps as { description: string; done: boolean }[]) || []
  const isCompleted = event.type === "plan_completed"
  const isAbandoned = event.type === "plan_abandoned"
  const isUpdated = event.type === "plan_updated"

  if (isUpdated) {
    return (
      <div className="py-0.5 group">
        <div className="flex items-baseline gap-2">
          <span className="text-npc-blue text-xs">&bull;</span>
          <span className="text-neutral-400 text-xs">{event.message}</span>
          <TimeStamp timeAgo={timeAgo} />
        </div>
      </div>
    )
  }

  const borderColor = isCompleted ? "border-npc-green/40" : isAbandoned ? "border-neutral-700" : "border-npc-blue/40"
  const labelColor = isCompleted ? "text-npc-green" : isAbandoned ? "text-neutral-500" : "text-npc-blue"

  return (
    <div className={`my-2 border-l-2 ${borderColor} bg-neutral-950 rounded-r-lg py-2 px-3 group`}>
      <div className="flex items-center gap-2 mb-1">
        <span className={`text-[10px] uppercase tracking-widest ${labelColor}`}>
          {isCompleted ? "plan completed" : isAbandoned ? "plan abandoned" : "new plan"}
        </span>
        <TimeStamp timeAgo={timeAgo} />
      </div>
      <AgentLink name={event.agent_name || "Someone"} id={event.agent_id} onClick={onAgentClick} />
      {goal && (
        <div className={`text-sm mt-1 ${isAbandoned ? "text-neutral-600 line-through" : isCompleted ? "text-npc-green" : "text-neutral-300"}`}>
          &ldquo;{goal}&rdquo;
        </div>
      )}
      {steps.length > 0 && event.type === "plan_created" && (
        <div className="flex flex-wrap gap-x-3 gap-y-1 mt-1.5">
          {steps.map((s, i) => (
            <span key={i} className={`text-[11px] ${s.done ? "text-npc-blue" : "text-neutral-400"}`}>{s.done ? "+" : "-"} {s.description}</span>
          ))}
        </div>
      )}
    </div>
  )
}

function GenericEvent({ event, timeAgo }: { event: SpectatorEvent; timeAgo: string }) {
  return (
    <div className="py-0.5 group">
      <div className="flex items-baseline gap-2">
        <span className="text-neutral-500 text-xs">{event.message}</span>
        <TimeStamp timeAgo={timeAgo} />
      </div>
    </div>
  )
}

// ─── Utility ─────────────────────────────────────────────

function useRelativeTime(timestamp: string): string {
  const [now, setNow] = useState(Date.now())
  useEffect(() => {
    const interval = setInterval(() => setNow(Date.now()), 30000)
    return () => clearInterval(interval)
  }, [])

  const diff = now - new Date(timestamp).getTime()
  const seconds = Math.floor(diff / 1000)
  if (seconds < 10) return "now"
  if (seconds < 60) return `${seconds}s`
  const minutes = Math.floor(seconds / 60)
  if (minutes < 60) return `${minutes}m`
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return `${hours}h`
  return `${Math.floor(hours / 24)}d`
}
