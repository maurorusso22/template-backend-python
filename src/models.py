from pydantic import BaseModel, Field


class ItemCreate(BaseModel):
    name: str = Field(min_length=1, max_length=255)
    description: str | None = None
    price: float = Field(gt=0)


class Item(BaseModel):
    id: int
    name: str
    description: str | None = None
    price: float
