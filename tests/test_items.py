from fastapi.testclient import TestClient

import src.main
from src.main import app, items

client = TestClient(app)


def setup_function():
    items.clear()
    src.main._next_id = 1


def test_create_item():
    response = client.post(
        "/items",
        json={"name": "Widget", "description": "A useful widget", "price": 9.99},
    )
    assert response.status_code == 201
    data = response.json()
    assert data["id"] == 1
    assert data["name"] == "Widget"
    assert data["description"] == "A useful widget"
    assert data["price"] == 9.99


def test_create_item_minimal():
    response = client.post("/items", json={"name": "Gadget", "price": 4.50})
    assert response.status_code == 201
    data = response.json()
    assert data["name"] == "Gadget"
    assert data["description"] is None


def test_create_item_invalid_payload():
    response = client.post("/items", json={"name": "Bad"})
    assert response.status_code == 422


def test_create_item_invalid_price():
    response = client.post("/items", json={"name": "Bad", "price": -1})
    assert response.status_code == 422


def test_get_item():
    client.post("/items", json={"name": "Thing", "price": 5.00})
    response = client.get("/items/1")
    assert response.status_code == 200
    assert response.json()["name"] == "Thing"


def test_get_item_not_found():
    response = client.get("/items/999")
    assert response.status_code == 404
    assert response.json()["detail"] == "Item not found"
