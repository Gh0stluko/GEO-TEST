import os
from typing import Any, Dict, List

import httpx
import psycopg2
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, StreamingResponse


def get_env(name: str, default: str | None = None) -> str:
    val = os.getenv(name, default)
    if val is None:
        raise RuntimeError(f"Missing env var: {name}")
    return val


POSTGRES_DB = get_env("POSTGRES_DB", "gis")
POSTGRES_USER = get_env("POSTGRES_USER", "gis")
POSTGRES_PASSWORD = get_env("POSTGRES_PASSWORD", "gis")
POSTGRES_HOST = get_env("POSTGRES_HOST", "db")
POSTGRES_PORT = int(get_env("POSTGRES_PORT", "5432"))

GEOSERVER_WORKSPACE = get_env("GEOSERVER_WORKSPACE", "gis_test")
GEOSERVER_BASE_URL = get_env("GEOSERVER_BASE_URL", "http://geoserver:8080/geoserver")
GEOSERVER_USER = get_env("GEOSERVER_USER", "admin")
GEOSERVER_PASSWORD = get_env("GEOSERVER_PASSWORD", "geoserver")

PUBLIC_API_BASE = get_env("PUBLIC_API_BASE", "http://localhost:8000")

app = FastAPI(title="GIS Test API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def db_connect():
    return psycopg2.connect(
        dbname=POSTGRES_DB,
        user=POSTGRES_USER,
        password=POSTGRES_PASSWORD,
        host=POSTGRES_HOST,
        port=POSTGRES_PORT,
    )


@app.get("/layers")
def get_layers() -> Dict[str, Any]:
    bbox: List[float]
    try:
        with db_connect() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    SELECT
                        COALESCE(ST_XMin(ext), -180) AS minx,
                        COALESCE(ST_YMin(ext), -90) AS miny,
                        COALESCE(ST_XMax(ext), 180) AS maxx,
                        COALESCE(ST_YMax(ext), 90) AS maxy
                    FROM (SELECT ST_Extent(geom) AS ext FROM public.regions) q;
                    """
                )
                row = cur.fetchone()
                if not row:
                    raise HTTPException(status_code=404, detail="No bbox available")
                bbox = [float(row[0]), float(row[1]), float(row[2]), float(row[3])]
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"DB error: {e}") from e

    layer_name = "regions"
    workspace = GEOSERVER_WORKSPACE
    wms_proxy_url = f"{PUBLIC_API_BASE.rstrip('/')}/wms"

    return {
        "name": layer_name,
        "title": "Regions",
        "srs": "EPSG:4326",
        "bbox": bbox,
        "wms": {
            "url": wms_proxy_url,  # Proxy URL for browser access
            "layer": f"{workspace}:{layer_name}",
        },
    }


@app.get("/wms")
async def wms_proxy(request: Request):
    params = dict(request.query_params)
    workspace = GEOSERVER_WORKSPACE
    target_wms = f"{GEOSERVER_BASE_URL.rstrip('/')}/{workspace}/wms"

    auth = (GEOSERVER_USER, GEOSERVER_PASSWORD)
    timeout = httpx.Timeout(30.0)

    try:
        async with httpx.AsyncClient(timeout=timeout, auth=auth) as client:
            resp = await client.get(target_wms, params=params)
            headers = {
                "Content-Type": resp.headers.get("Content-Type", "application/octet-stream"),
                "Cache-Control": "no-cache",
            }
            return StreamingResponse(resp.aiter_bytes(), status_code=resp.status_code, headers=headers)
    except httpx.HTTPError as e:
        raise HTTPException(status_code=502, detail=f"Proxy error: {e}") from e


@app.get("/")
def root():
    return JSONResponse({"ok": True, "service": "GIS Test API"})
