import { useState, useCallback, useRef } from "react"
import type { SpectatorEvent } from "@/types/events"

interface UseEventHistoryOptions {
  location?: string | null
  agent?: string | null
}

export function useEventHistory(options?: UseEventHistoryOptions) {
  const [loading, setLoading] = useState(false)
  const [hasMore, setHasMore] = useState(true)
  const loadingRef = useRef(false)

  const loadMore = useCallback(
    async (
      oldestTick: number,
      existingIds: Set<string>
    ): Promise<SpectatorEvent[]> => {
      if (loadingRef.current || !hasMore) return []
      loadingRef.current = true
      setLoading(true)

      try {
        const params = new URLSearchParams()
        params.set("since_tick", String(Math.max(0, oldestTick - 100)))
        params.set("limit", "50")
        if (options?.location) params.set("location", options.location)
        if (options?.agent) params.set("agent", options.agent)

        const res = await fetch(`/api/v1/spectate/history?${params}`)
        if (!res.ok) return []

        const data = (await res.json()) as SpectatorEvent[]

        // Filter out events we already have
        const newEvents = data.filter((e) => !existingIds.has(e.id))

        if (data.length < 50) setHasMore(false)

        return newEvents
      } catch {
        return []
      } finally {
        loadingRef.current = false
        setLoading(false)
      }
    },
    [hasMore, options?.location, options?.agent]
  )

  return { loadMore, loading, hasMore }
}
