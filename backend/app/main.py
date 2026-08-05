from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .config import get_settings

from .routers import balances, payment_requests, profile, transfers, saved_users


app = FastAPI(
    title="MegaPay API",
    description="手軽に送金できるスマホアプリ MegaPay のバックエンド API（MVP）",
    version="0.1.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=get_settings().cors_origin_list,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(profile.router)
app.include_router(balances.router)
app.include_router(payment_requests.router)
app.include_router(transfers.router)
app.include_router(saved_users.router)


@app.get("/health", tags=["meta"])
def health() -> dict[str, str]:
    return {"status": "ok"}
