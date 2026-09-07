"""Word Form Generation & Bank Guarantee Calculation API."""
import os
import uuid
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from ..database import get_db
from ..engine import ShramsetuDocxGenerator, BankGuaranteeCalculator
from ..models import (
    ShramsetuFormModel, EstablishmentCreate, EstablishmentOut,
    ApplicationCreate, ApplicationOut,
    EstablishmentDB, ContractorApplicationDB,
)

router = APIRouter(prefix="/api/forms", tags=["Forms"])


def _next_application_number(db: Session) -> str:
    year = datetime.utcnow().year
    fy_tag = f"{year}-{str(year + 1)[-2:]}"
    count = db.query(ContractorApplicationDB).count() + 1
    return f"SHRM/APP/{fy_tag}/{count:04d}"


@router.post("/establishments", response_model=EstablishmentOut)
def create_establishment(payload: EstablishmentCreate, db: Session = Depends(get_db)):
    existing = db.query(EstablishmentDB).filter(EstablishmentDB.pan == payload.pan.upper()).first()
    if existing:
        raise HTTPException(status_code=409, detail="Establishment with this PAN already exists")
    row = EstablishmentDB(
        name=payload.name,
        pan=payload.pan.upper(),
        gstin=(payload.gstin or "").upper() or None,
        ownership_type=payload.ownership_type,
        head_address=payload.head_address,
        district=payload.district,
        pincode=payload.pincode,
    )
    try:
        db.add(row)
        db.commit()
        db.refresh(row)
    except Exception:
        db.rollback()
        raise HTTPException(status_code=500, detail="Could not create establishment")
    return row


@router.get("/establishments/{establishment_id}", response_model=EstablishmentOut)
def get_establishment(establishment_id: int, db: Session = Depends(get_db)):
    row = db.query(EstablishmentDB).filter(EstablishmentDB.id == establishment_id).first()
    if not row:
        raise HTTPException(status_code=404, detail="Establishment not found")
    return row


@router.post("/applications", response_model=ApplicationOut)
def create_application(payload: ApplicationCreate, db: Session = Depends(get_db)):
    establishment = db.query(EstablishmentDB).filter(
        EstablishmentDB.id == payload.establishment_id
    ).first()
    if not establishment:
        raise HTTPException(status_code=404, detail="Establishment not found")

    total_labour = payload.male_labour + payload.female_labour + payload.trans_labour
    bg_amount = payload.total_bg_amount or BankGuaranteeCalculator.calculate(total_labour)

    row = ContractorApplicationDB(
        establishment_id=payload.establishment_id,
        application_number=_next_application_number(db),
        pe_ein=payload.pe_ein,
        pe_name=payload.pe_name,
        nature_of_work=payload.nature_of_work,
        contract_start_date=payload.contract_start_date,
        contract_end_date=payload.contract_end_date,
        male_labour=payload.male_labour,
        female_labour=payload.female_labour,
        trans_labour=payload.trans_labour,
        total_bg_amount=bg_amount,
        status="DRAFT",
    )
    try:
        db.add(row)
        db.commit()
        db.refresh(row)
    except Exception:
        db.rollback()
        raise HTTPException(status_code=500, detail="Could not create application")

    out = ApplicationOut.model_validate(row)
    out.total_labour = total_labour
    return out


@router.post("/generate-docx/{form_type}")
def generate_docx(form_type: str, payload: ShramsetuFormModel):
    output_name = f"{form_type.upper()}_{uuid.uuid4().hex[:8]}.docx"
    try:
        path = ShramsetuDocxGenerator.generate(form_type, payload, output_name)
    except FileNotFoundError as e:
        raise HTTPException(status_code=422, detail=str(e))
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    return FileResponse(
        path,
        media_type="application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        filename=output_name,
    )


@router.post("/calculate-bg")
def calculate_bg(total_labour: int, contract_value: float = 0.0):
    amount = BankGuaranteeCalculator.calculate(total_labour, contract_value)
    return {"total_labour": total_labour, "contract_value": contract_value, "bg_amount": amount}
