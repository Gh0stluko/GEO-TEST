#!/usr/bin/env bash
set -euo pipefail

if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs -d '\n' -I {} echo {})
fi

DATA_FILE="./data/regions.geojson"

if [ ! -f "$DATA_FILE" ]; then
  echo "[seed] Missing $DATA_FILE. Place your dataset at ./data/regions.geojson" >&2
  exit 1
fi

echo "[seed] Ensuring DB is up (db must be healthy)..."
docker compose up -d db

echo "[seed] Importing regions.geojson into PostGIS using GDAL (ogr2ogr)..."
docker compose --profile seed run --rm --entrypoint "" gdal \
  ogr2ogr -f PostgreSQL \
  "PG:host=db dbname=${POSTGRES_DB:-gis} user=${POSTGRES_USER:-gis} password=${POSTGRES_PASSWORD:-gis} port=5432" \
  /data/regions.geojson \
  -nln regions \
  -nlt PROMOTE_TO_MULTI \
  -lco GEOMETRY_NAME=geom \
  -lco FID=gid \
  -lco PRECISION=NO \
  -overwrite

echo "[seed] Fixing SRID (EPSG:4326) and creating GIST index..."
docker compose exec -T db psql -U "${POSTGRES_USER:-gis}" -d "${POSTGRES_DB:-gis}" -v ON_ERROR_STOP=1 <<'SQL'
DO $$
BEGIN
  IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns 
      WHERE table_schema='public' AND table_name='regions' AND column_name='geom'
  ) THEN
    RAISE EXCEPTION 'Table public.regions or column geom missing';
  END IF;
END$$;

UPDATE public.regions SET geom = ST_SetSRID(geom, 4326) WHERE COALESCE(ST_SRID(geom),0) <> 4326;
CREATE INDEX IF NOT EXISTS regions_geom_idx ON public.regions USING GIST (geom);
ANALYZE public.regions;
SQL

echo "[seed] Row count in public.regions:"
docker compose exec -T db psql -U "${POSTGRES_USER:-gis}" -d "${POSTGRES_DB:-gis}" -c "SELECT COUNT(*) FROM public.regions;"

echo "[seed] Done."