import { useEffect, useRef, useCallback, useState } from "react"
import type { SpectatorEvent } from "@/types/events"

const MAX_EVENTS = 500
const POLL_INTERVAL = 2000

interface UseEventStreamOptions {
  location?: string | null
  agent?: string | null
}

interface EventStreamState {
  events: SpectatorEvent[]
  connected: boolean
  reconnecting: boolean
}

export function useEventStream(options?: UseEventStreamOptions): EventStreamState {
  const [state, setState] = useState<EventStreamState>({
    events: [],
    connected: false,
    reconnecting: true,
  })

  const seenIds = useRef(new Set<string>())
  const lastTickRef = useRef(0)
  const pollTimer = useRef<ReturnType<typeof setTimeout> | null>(null)
  const isFirstPoll = useRef(true)

  const addEvents = useCallback((newEvents: SpectatorEvent[]) => {
    const unseen = newEvents.filter((e) => !seenIds.current.has(e.id))
    if (unseen.length === 0) return

    for (const e of unseen) seenIds.current.add(e.id)

    setState((prev) => {
      const merged = [...prev.events, ...unseen]
      if (merged.length > MAX_EVENTS) {
        const removed = merged.splice(0, merged.length - MAX_EVENTS)
        for (const r of removed) seenIds.current.delete(r.id)
      }
      return { ...prev, events: merged }
    })
  }, [])

  useEffect(() => {
    let disposed = false
    isFirstPoll.current = true
    seenIds.current.clear()
    lastTickRef.current = 0
    setState({ events: [], connected: false, reconnecting: true })

    const poll = async () => {
      if (disposed) return

      try {
        const params = new URLSearchParams()
        // On first poll, get recent events; on subsequent polls, get events since last tick
        if (isFirstPoll.current) {
          params.set("limit", "100")
        } else {
          params.set("since_tick", String(Math.max(0, lastTickRef.current - 1)))
          params.set("limit", "100")
        }
        if (options?.location) params.set("location", options.location)
        if (options?.agent) params.set("agent", options.agent)

        const res = await fetch(`/api/v1/spectate/history?${params}`)
        if (!res.ok) throw new Error(`HTTP ${res.status}`)

        const data = (await res.json()) as SpectatorEvent[]

        if (!disposed) {
          if (data.length > 0) {
            const maxTick = Math.max(...data.map((e) => e.tick))
            lastTickRef.current = maxTick
            addEvents(data)
          }

          isFirstPoll.current = false
          setState((prev) => ({
            ...prev,
            connected: true,
            reconnecting: false,
          }))
        }
      } catch {
        if (!disposed) {
          setState((prev) => ({ ...prev, connected: false, reconnecting: true }))
        }
      }

      if (!disposed) {
        pollTimer.current = setTimeout(poll, POLL_INTERVAL)
      }
    }

    poll()

    return () => {
      disposed = true
      if (pollTimer.current) clearTimeout(pollTimer.current)
    }
  }, [options?.location, options?.agent, addEvents])

  return state
}
