import React, { useEffect, useMemo, useRef, useState } from 'react'
import Map from 'ol/Map'
import View from 'ol/View'
import TileLayer from 'ol/layer/Tile'
import TileWMS from 'ol/source/TileWMS'
import OSM from 'ol/source/OSM'
import { ScaleLine } from 'ol/control'
import { fromLonLat, get as getProjection } from 'ol/proj'
import type { LayerInfo } from './api'

type Props = { layer: LayerInfo }

export default function MapView({ layer }: Props) {
  const mapEl = useRef<HTMLDivElement | null>(null)
  const [info, setInfo] = useState<any>(null)

  const wmsSource = useMemo(() => {
    return new TileWMS({
      url: layer.wms.url,
      params: {
        LAYERS: layer.wms.layer,
        TILED: true,
        TRANSPARENT: true,
        FORMAT: 'image/png',
      },
      crossOrigin: 'anonymous',
    })
  }, [layer])

  useEffect(() => {
    if (!mapEl.current) return
    const [minx, miny, maxx, maxy] = layer.bbox
    const layer4326 = [minx, miny, maxx, maxy]

    const map = new Map({
      target: mapEl.current,
      layers: [
        new TileLayer({ source: new OSM() }),
        new TileLayer({ source: wmsSource })
      ],
      view: new View({
        projection: 'EPSG:3857',
        center: fromLonLat([(minx + maxx) / 2, (miny + maxy) / 2]),
        zoom: 4,
      }),
      controls: [new ScaleLine()],
    })

    // Fit to bbox
    try {
      const proj = getProjection('EPSG:3857')!
      map.getView().fit([
        ...fromLonLat([minx, miny], proj),
        ...fromLonLat([maxx, maxy], proj),
      ], { duration: 300 })
    } catch {}

    // Identify on click
    map.on('singleclick', async (evt) => {
      const url = wmsSource.getFeatureInfoUrl(
        evt.coordinate,
        map.getView().getResolution()!,
        map.getView().getProjection(),
        {
          INFO_FORMAT: 'application/json',
          FEATURE_COUNT: 5,
          QUERY_LAYERS: layer.wms.layer,
        },
      )
      if (!url) return
      try {
        const res = await fetch(url)
        const data = await res.json()
        setInfo(data)
      } catch (e) {
        setInfo({ error: String(e) })
      }
    })

    return () => {
      map.setTarget(undefined)
    }
  }, [layer, wmsSource])

  const legendUrl = `${layer.wms.url}?SERVICE=WMS&REQUEST=GetLegendGraphic&FORMAT=image/png&LAYER=${encodeURIComponent(layer.wms.layer)}`

  return (
    <div style={{ height: '100%', position: 'relative' }}>
      <div ref={mapEl} style={{ height: '100%' }} />
      <div className="legend">
        <div style={{ fontWeight: 600, marginBottom: 6 }}>Legend</div>
        <img src={legendUrl} alt="Legend" crossOrigin="anonymous" />
      </div>
      <div className="identify">
        <div style={{ fontWeight: 600, marginBottom: 6 }}>Identify</div>
        <pre style={{ margin: 0, whiteSpace: 'pre-wrap' }}>{JSON.stringify(info, null, 2)}</pre>
      </div>
    </div>
  )
}
