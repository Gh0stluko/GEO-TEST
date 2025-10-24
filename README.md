# GeoServer Test Assignment

This is my implementation of the test task: **"Spin up a tiny GIS stack, publish the provided dataset in GeoServer (backed by PostGIS), expose a small FastAPI API, and render the layer with a React + OpenLayers viewer (legend, scale bar, identify)"**

## What's Built

**Backend:**
- PostgreSQL 17 + PostGIS 3.4
- GeoServer 2.24.2 with WMS/WFS
- FastAPI with layer metadata endpoint + WMS proxy

**Frontend:**
- React 18 + TypeScript
- Vite dev server
- OpenLayers 9.2 with OSM base layer
- Legend, scale bar, and feature identification on click

**Automation:**
- Seed script to import GeoJSON → PostGIS
- Publish script to configure GeoServer via REST API
- Docker Compose orchestration with health checks

## Installation

1. **Clone and configure**

```bash
cp .env.example .env
```

2. **Add dataset files**

```
data/regions.geojson    # GeoJSON
data/styles/regions.sld # SLD style
```

3. **Start stack**

```bash
docker compose up -d --build
```

4. **Import data**

```bash
bash scripts/seed.sh
```

5. **Publish layer**

```bash
bash scripts/publish_layer.sh
```

## Usage

**Map Viewer:** http://localhost:5173

**API Endpoint:** http://localhost:8000/layers

**GeoServer Admin:** http://localhost:8080/geoserver  
*Credentials:* admin / geoserver

## Verification

The implementation meets all acceptance criteria:

```bash
# 1. Check PostGIS contains data
docker compose exec db psql -U gis -d gis -c "SELECT COUNT(*) FROM public.regions;"

# 2. Verify WMS layer published
curl -s "http://localhost:8080/geoserver/gis_test/wms?request=GetCapabilities" | grep regions

# 3. Test GetMap returns PNG
curl -s "http://localhost:8000/wms?REQUEST=GetMap&SERVICE=WMS&VERSION=1.3.0&FORMAT=image/png&LAYERS=gis_test:regions&WIDTH=100&HEIGHT=100&CRS=EPSG:4326&BBOX=50,-10,61,2" --output test.png
file test.png

# 4. Check API response format
curl -s http://localhost:8000/layers | jq .
```

Expected API response:
```json
{
  "name": "regions",
  "bbox": [-8.14, 50.02, 1.74, 60.83],
  "wms": {
    "url": "http://localhost:8000/wms",
    "layer": "gis_test:regions"
  }
}
```

## Architecture Highlights

- **CORS handling:** API proxies WMS to avoid browser restrictions
- **Health checks:** Services wait for dependencies before starting
- **Idempotent scripts:** Safe to re-run without breaking state
- **SLD styling:** Custom symbolization via GeoServer REST API

View `ARCHITECTURE.md` for detailed component documentation.

## Stack Versions

- PostgreSQL 17 + PostGIS 3.4
- GeoServer 2.24.2
- Python 3.11 + FastAPI 0.115
- React 18.3 + OpenLayers 9.2
- GDAL 3.6.3