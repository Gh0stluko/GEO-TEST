import React, { useEffect, useState } from 'react'
import { fetchLayer, type LayerInfo } from './api'
import MapView from './Map'

export default function App() {
  const [layer, setLayer] = useState<LayerInfo | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    fetchLayer().then(setLayer).catch((e) => setError(String(e)))
  }, [])

  if (error) return <div style={{ padding: 16 }}>Error: {error}</div>
  if (!layer) return <div style={{ padding: 16 }}>Loading…</div>

  return <MapView layer={layer} />
}
