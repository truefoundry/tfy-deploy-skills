from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

app = FastAPI(title="Example API")

items: dict[str, dict] = {}


class Item(BaseModel):
    name: str
    description: str = ""
    price: float


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/items")
def list_items():
    return list(items.values())


@app.post("/items")
def create_item(item: Item):
    if item.name in items:
        raise HTTPException(400, "Item already exists")
    items[item.name] = item.model_dump()
    return items[item.name]


@app.get("/items/{name}")
def get_item(name: str):
    if name not in items:
        raise HTTPException(404, "Item not found")
    return items[name]


@app.delete("/items/{name}")
def delete_item(name: str):
    if name not in items:
        raise HTTPException(404, "Item not found")
    return items.pop(name)
