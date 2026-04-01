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
    ('Mumbai', 'IN');

INSERT INTO weather_records (city_id, temperature, humidity, description) VALUES
    (1, 18.5, 72.0, 'Partly cloudy'),
    (2, 12.0, 85.0, 'Overcast'),
    (3, 25.0, 60.0, 'Clear sky'),
    (4, 8.5, 78.0, 'Light rain'),
    (5, 32.0, 80.0, 'Humid and sunny');
