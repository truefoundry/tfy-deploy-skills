import { useState, useEffect } from "react";

export default function App() {
  const [items, setItems] = useState([]);
  const apiUrl = import.meta.env.VITE_API_URL || "http://localhost:8000";

  useEffect(() => {
    fetch(`${apiUrl}/items`)
      .then((res) => res.json())
      .then(setItems)
      .catch(console.error);
  }, [apiUrl]);

  return (
    <div style={{ maxWidth: 600, margin: "2rem auto", fontFamily: "sans-serif" }}>
      <h1>React Frontend Example</h1>
      <p>Connected to: {apiUrl}</p>
      <h2>Items</h2>
      {items.length === 0 ? (
        <p>No items found.</p>
      ) : (
        <ul>
          {items.map((item) => (
            <li key={item.name}>
              {item.name} — ${item.price}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
