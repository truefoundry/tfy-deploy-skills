import os
from contextlib import asynccontextmanager

import psycopg2
from psycopg2.extras import RealDictCursor
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

DATABASE_URL = os.environ.get(
    "DATABASE_URL", "postgresql://weather:changeme@localhost:5432/weatherdb"
)

INIT_SQL = """
CREATE TABLE IF NOT EXISTS cities (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) UNIQUE NOT NULL,
    country VARCHAR(100) NOT NULL
);

CREATE TABLE IF NOT EXISTS weather_records (
    id SERIAL PRIMARY KEY,
    city_id INTEGER REFERENCES cities(id),
    temperature FLOAT NOT NULL,
    humidity FLOAT,
    description VARCHAR(200),
    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO cities (name, country) VALUES
    ('San Francisco', 'US'),
    ('London', 'UK'),
    ('Tokyo', 'JP'),
    ('Berlin', 'DE'),
    ('Mumbai', 'IN')
ON CONFLICT (name) DO NOTHING;

INSERT INTO weather_records (city_id, temperature, humidity, description)
SELECT c.id, w.temperature, w.humidity, w.description
FROM (VALUES
    ('San Francisco', 18.5, 72.0, 'Partly cloudy'),
    ('London', 12.0, 85.0, 'Overcast'),
    ('Tokyo', 25.0, 60.0, 'Clear sky'),
    ('Berlin', 8.5, 78.0, 'Light rain'),
    ('Mumbai', 32.0, 80.0, 'Humid and sunny')
) AS w(city_name, temperature, humidity, description)
JOIN cities c ON c.name = w.city_name
WHERE NOT EXISTS (
    SELECT 1 FROM weather_records wr WHERE wr.city_id = c.id
);
"""


def init_db():
    try:
        conn = psycopg2.connect(DATABASE_URL)
        conn.autocommit = True
        with conn.cursor() as cur:
            cur.execute(INIT_SQL)
        conn.close()
        print("Database initialized successfully")
    except Exception as e:
        print(f"Database init failed: {e}")


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    yield


app = FastAPI(title="Weather API", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/cities")
def list_cities():
    try:
        conn = psycopg2.connect(DATABASE_URL, cursor_factory=RealDictCursor)
        with conn.cursor() as cur:
            cur.execute("SELECT id, name, country FROM cities ORDER BY name")
            rows = cur.fetchall()
        conn.close()
        return rows
    except Exception as e:
        raise HTTPException(500, detail=str(e))


@app.get("/weather/{city_name}")
def get_weather(city_name: str):
    try:
        conn = psycopg2.connect(DATABASE_URL, cursor_factory=RealDictCursor)
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT c.name, c.country, w.temperature, w.humidity,
                       w.description, w.recorded_at
                FROM cities c
                JOIN weather_records w ON w.city_id = c.id
                WHERE LOWER(c.name) = LOWER(%s)
                ORDER BY w.recorded_at DESC
                LIMIT 1
                """,
                (city_name,),
            )
            row = cur.fetchone()
            if not row:
                raise HTTPException(404, f"No weather data for {city_name}")
            return row
        conn.close()
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(500, detail=str(e))
