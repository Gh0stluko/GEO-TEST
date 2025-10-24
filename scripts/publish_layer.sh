#!/usr/bin/env bash
set -euo pipefail

if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs -d '\n' -I {} echo {})
fi

GEOSERVER_BASE="${GEOSERVER_BASE_URL:-http://localhost:${GEOSERVER_PORT:-8080}/geoserver}"
AUTH_USER="${GEOSERVER_USER:-admin}"
AUTH_PASS="${GEOSERVER_PASSWORD:-geoserver}"
WORKSPACE="${GEOSERVER_WORKSPACE:-gis_test}"
DATASTORE="${GEOSERVER_DATASTORE:-gis_store}"
STYLE_NAME="regions"
LAYER_NAME="regions"

STYLE_FILE="./data/styles/regions.sld"
if [ ! -f "$STYLE_FILE" ]; then
  echo "[publish] Missing $STYLE_FILE. Place your style at ./data/styles/regions.sld" >&2
  exit 1
fi

echo "[publish] GeoServer base: $GEOSERVER_BASE"

auth=(-u "$AUTH_USER:$AUTH_PASS")
jsonH=(-H "Content-Type: application/json")

echo "[publish] Ensuring workspace '$WORKSPACE' exists..."
WS_URL="$GEOSERVER_BASE/rest/workspaces/$WORKSPACE"
code=$(curl -s -o /dev/null -w "%{http_code}" "${auth[@]}" "$WS_URL.json")
if [ "$code" != "200" ]; then
  curl -sS "${auth[@]}" "${jsonH[@]}" -X POST "$GEOSERVER_BASE/rest/workspaces" \
    -d '{"workspace": {"name": "'"$WORKSPACE"'"}}' >/dev/null
  echo "[publish] Workspace created."
else
  echo "[publish] Workspace exists."
fi

echo "[publish] Ensuring datastore '$DATASTORE' exists..."
DS_URL="$GEOSERVER_BASE/rest/workspaces/$WORKSPACE/datastores/$DATASTORE"
code=$(curl -s -o /dev/null -w "%{http_code}" "${auth[@]}" "$DS_URL.json")
if [ "$code" != "200" ]; then
  response=$(curl -s -w "\n%{http_code}" "${auth[@]}" "${jsonH[@]}" -X POST "$GEOSERVER_BASE/rest/workspaces/$WORKSPACE/datastores" \
    -d '{"dataStore": {"name": "'"$DATASTORE"'", "type": "PostGIS", "enabled": true, "connectionParameters": {"entry": [
      {"@key":"host","$":"db"},
      {"@key":"port","$":"5432"},
      {"@key":"database","$":"'"${POSTGRES_DB:-gis}"'"},
      {"@key":"schema","$":"public"},
      {"@key":"user","$":"'"${POSTGRES_USER:-gis}"'"},
      {"@key":"passwd","$":"'"${POSTGRES_PASSWORD:-gis}"'"},
      {"@key":"dbtype","$":"postgis"}
    ]}}}')
  http_code=$(echo "$response" | tail -n1)
  body=$(echo "$response" | sed '$d')
  if [ "$http_code" = "201" ]; then
    echo "[publish] Datastore created."
  else
    echo "[publish] ERROR: Failed to create datastore (HTTP $http_code): $body" >&2
    exit 1
  fi
else
  echo "[publish] Datastore exists."
fi

echo "[publish] Ensuring layer '$LAYER_NAME' is published..."
LAYER_URL="$GEOSERVER_BASE/rest/layers/$WORKSPACE:$LAYER_NAME"
code=$(curl -s -o /dev/null -w "%{http_code}" "${auth[@]}" "$LAYER_URL.json")
if [ "$code" != "200" ]; then
  response=$(curl -s -w "\n%{http_code}" "${auth[@]}" "${jsonH[@]}" -X POST "$GEOSERVER_BASE/rest/workspaces/$WORKSPACE/datastores/$DATASTORE/featuretypes" \
    -d '{"featureType": {"name": "'"$LAYER_NAME"'", "srs": "EPSG:4326"}}')
  http_code=$(echo "$response" | tail -n1)
  body=$(echo "$response" | sed '$d')
  if [ "$http_code" = "201" ]; then
    echo "[publish] Layer created."
  else
    echo "[publish] ERROR: Failed to create layer (HTTP $http_code): $body" >&2
    exit 1
  fi
else
  echo "[publish] Layer exists."
fi

echo "[publish] Uploading style '$STYLE_NAME' and setting as default..."
STYLE_URL="$GEOSERVER_BASE/rest/workspaces/$WORKSPACE/styles/$STYLE_NAME"
code=$(curl -s -o /dev/null -w "%{http_code}" "${auth[@]}" "$STYLE_URL")
if [ "$code" = "200" ]; then
  # Update existing style content
  curl -sS "${auth[@]}" -H "Content-Type: application/vnd.ogc.sld+xml" -X PUT "$STYLE_URL" --data-binary @"$STYLE_FILE" >/dev/null
else
  # Create style then upload content
  curl -sS "${auth[@]}" "${jsonH[@]}" -X POST "$GEOSERVER_BASE/rest/workspaces/$WORKSPACE/styles" \
    -d '{"style": {"name": "'"$STYLE_NAME"'", "filename": "'"$STYLE_NAME"'.sld"}}' >/dev/null
  curl -sS "${auth[@]}" -H "Content-Type: application/vnd.ogc.sld+xml" -X PUT "$STYLE_URL" --data-binary @"$STYLE_FILE" >/dev/null
fi

echo "[publish] Setting default style on layer..."
curl -sS "${auth[@]}" "${jsonH[@]}" -X PUT "$LAYER_URL" \
  -d '{"layer": {"defaultStyle": {"name": "'"$STYLE_NAME"'", "workspace": "'"$WORKSPACE"'"}}}' >/dev/null

CAPS_URL="$GEOSERVER_BASE/$WORKSPACE/wms?service=WMS&request=GetCapabilities"
echo "[publish] Success. WMS GetCapabilities: $CAPS_URL"