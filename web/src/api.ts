export type LayerInfo = {
  name: string
  title: string
  srs: string
  bbox: [number, number, number, number]
  wms: { url: string; layer: string }
}

const API_BASE = (import.meta as any).env?.VITE_API_BASE ?? window.location.origin.replace(/:\d+$/, ':8000')

export async function fetchLayer(): Promise<LayerInfo> {
  const res = await fetch(`${API_BASE}/layers`)
  if (!res.ok) throw new Error(`Failed to fetch layer: ${res.status}`)
  return res.json()
}
