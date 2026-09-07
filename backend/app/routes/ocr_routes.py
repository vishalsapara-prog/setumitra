"""OCR / Document Upload & Extraction API."""
import os
import uuid
from datetime import datetime

from fastapi import APIRouter, UploadFile, File, Form, Depends, HTTPException
from sqlalchemy.orm import Session

from ..database import get_db
from ..engine import ShramsetuDocParser
from ..models import DocumentDB, EstablishmentDB, OCRExtractResponse

router = APIRouter(prefix="/api/ocr", tags=["OCR"])

UPLOAD_ROOT = os.path.join(os.path.dirname(__file__), "..", "..", "uploads")
os.makedirs(UPLOAD_ROOT, exist_ok=True)

ALLOWED_MIME = {"application/pdf", "image/jpeg", "image/png", "image/jpg"}
MAX_FILE_SIZE_MB = 15


@router.get("/document-checklist/{role}")
def get_document_checklist(role: str):
    """
    Returns the exhaustive list of documents required for auto-fill, per
    the Shramsetu Exhaustive AutoFill Documents Checklist. `role` is
    CONTRACTOR or PRINCIPAL_EMPLOYER.
    """
    key = role.upper()
    if key not in ShramsetuDocParser.DOCUMENT_CHECKLIST:
        raise HTTPException(status_code=404, detail="Unknown role; use CONTRACTOR or PRINCIPAL_EMPLOYER")
    return {"role": key, "documents": ShramsetuDocParser.DOCUMENT_CHECKLIST[key]}


@router.post("/extract", response_model=OCRExtractResponse)
async def extract_document(
    doc_type: str = Form(...),
    establishment_id: int = Form(None),
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
):
    if file.content_type not in ALLOWED_MIME:
        raise HTTPException(status_code=400, detail=f"Unsupported file type: {file.content_type}")

    raw_bytes = await file.read()
    size_mb = len(raw_bytes) / (1024 * 1024)
    if size_mb > MAX_FILE_SIZE_MB:
        raise HTTPException(status_code=400, detail=f"File exceeds {MAX_FILE_SIZE_MB}MB limit")

    if file.content_type == "application/pdf":
        text = ShramsetuDocParser.extract_text(raw_bytes)
    else:
        text = ShramsetuDocParser.extract_text_from_image(raw_bytes)
        if not text:
            # Tesseract unavailable or produced nothing useful — surface a
            # clear, actionable error rather than silently returning empty
            # extracted_fields that look like a successful-but-blank scan.
            raise HTTPException(
                status_code=422,
                detail="Image OCR returned no text. Ensure the photo is clear and well-lit, "
                       "or install/verify the Tesseract OCR binary on the server "
                       "(see ShramsetuDocParser.extract_text_from_image docstring)."
            )

    fields = ShramsetuDocParser.route_by_doc_type(doc_type, text)

    if establishment_id is not None:
        establishment = db.query(EstablishmentDB).filter(EstablishmentDB.id == establishment_id).first()
        if not establishment:
            raise HTTPException(status_code=404, detail="Establishment not found")

        year_dir = os.path.join(UPLOAD_ROOT, doc_type.lower(), str(establishment_id))
        os.makedirs(year_dir, exist_ok=True)
        safe_name = f"{uuid.uuid4().hex}_{file.filename}"
        dest_path = os.path.join(year_dir, safe_name)
        with open(dest_path, "wb") as f:
            f.write(raw_bytes)

        import json
        record = DocumentDB(
            establishment_id=establishment_id,
            doc_type=doc_type.upper(),
            file_path=dest_path,
            mime_type=file.content_type,
            file_size=len(raw_bytes),
            ocr_extracted_json=json.dumps(fields, ensure_ascii=False),
            uploaded_at=datetime.utcnow(),
        )
        try:
            db.add(record)
            db.commit()
        except Exception:
            db.rollback()
            raise HTTPException(status_code=500, detail="Failed to persist document metadata")

    return OCRExtractResponse(
        doc_type=doc_type.upper(),
        extracted_fields=fields,
        raw_text_preview=text[:500],
    )
