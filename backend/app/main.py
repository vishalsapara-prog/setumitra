"""
Shramsetu Automation Engine - FastAPI Application Entrypoint
"""
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .database import init_db
from .routes import ocr_routes, form_routes, reference_routes

app = FastAPI(
    title="Shramsetu Automation Engine",
    description="Contractor / Principal Employer registration OCR auto-fill & document generation API.",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
def on_startup() -> None:
    init_db()


@app.get("/health", tags=["System"])
def health_check():
    return {"status": "ok", "service": "shramsetu-automation-engine"}


app.include_router(ocr_routes.router)
app.include_router(form_routes.router)
app.include_router(reference_routes.router)
