import { useState, useEffect } from "react";

const API_URL = import.meta.env.VITE_API_URL || "http://localhost:8000";

export default function App() {
  const [cities, setCities] = useState([]);
  const [selected, setSelected] = useState(null);
  const [weather, setWeather] = useState(null);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    fetch(`${API_URL}/cities`)
      .then((r) => r.json())
      .then(setCities)
      .catch(console.error);
  }, []);

  const fetchWeather = async (cityName) => {
    setSelected(cityName);
    setLoading(true);
    try {
      const res = await fetch(`${API_URL}/weather/${encodeURIComponent(cityName)}`);
      setWeather(await res.json());
    } catch (err) {
      console.error(err);
      setWeather(null);
    }
    setLoading(false);
  };

  return (
    <div style={{ maxWidth: 600, margin: "2rem auto", fontFamily: "sans-serif" }}>
      <h1>Weather App</h1>
      <h2>Cities</h2>
      <div style={{ display: "flex", gap: "0.5rem", flexWrap: "wrap" }}>
        {cities.map((c) => (
          <button
            key={c.id}
            onClick={() => fetchWeather(c.name)}
            style={{
              padding: "0.5rem 1rem",
              cursor: "pointer",
              background: selected === c.name ? "#0070f3" : "#eee",
              color: selected === c.name ? "#fff" : "#000",
              border: "none",
              borderRadius: 4,
            }}
          >
            {c.name}
          </button>
        ))}
      </div>

      {loading && <p>Loading...</p>}

      {weather && !loading && (
        <div style={{ marginTop: "1.5rem", padding: "1rem", background: "#f5f5f5", borderRadius: 8 }}>
          <h3>{weather.name}, {weather.country}</h3>
          <p>Temperature: {weather.temperature}°C</p>
          <p>Humidity: {weather.humidity}%</p>
          <p>Conditions: {weather.description}</p>
          <p style={{ fontSize: "0.8rem", color: "#666" }}>
            Recorded: {new Date(weather.recorded_at).toLocaleString()}
          </p>
        </div>
      )}
    </div>
  );
}
