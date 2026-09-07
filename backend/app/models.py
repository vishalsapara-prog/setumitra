"""
Shramsetu Automation Engine - Data Contract
SQLAlchemy ORM tables + Pydantic request/response schemas.

ShramsetuFormModel below mirrors the field structure of the official
Shramsetu Portal as documented in the "Shramsetu User Manual for
Registration and License" (Establishment Master -> Registration
Application -> License FORM-25 -> Bank Guarantee). Field names were
extracted directly from the office's verified reference forms
(Contractor_Updated_Shramsetu_Complete_Form / Principal_Employer_Updated
_Shramsetu_Complete_Form) -- no fields were invented.
"""
from datetime import datetime
from typing import Optional

from sqlalchemy import (
    Column, Integer, String, Float, DateTime, ForeignKey, Text, Boolean
)
from sqlalchemy.orm import declarative_base, relationship
from pydantic import BaseModel, Field, field_validator

Base = declarative_base()


# ---------------------------------------------------------------------------
# SQLAlchemy Database Tables (persistence layer for the API/mobile client)
# ---------------------------------------------------------------------------
class EstablishmentDB(Base):
    __tablename__ = "establishments"

    id = Column(Integer, primary_key=True, autoincrement=True)
    ein = Column(String(50), unique=True, index=True, nullable=True)
    lin = Column(String(50), nullable=True)
    name = Column(String(200), nullable=False)
    pan = Column(String(10), index=True, nullable=False)
    gstin = Column(String(15), nullable=True)
    ownership_type = Column(String(100), default="Sole Proprietorship")
    risk_category = Column(String(50), default="Medium")
    head_address = Column(Text, nullable=True)
    district = Column(String(100), nullable=True)
    pincode = Column(String(10), nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, nullable=True)
    is_active = Column(Boolean, default=True)

    applications = relationship(
        "ContractorApplicationDB", back_populates="establishment",
        cascade="all, delete-orphan"
    )
    documents = relationship(
        "DocumentDB", back_populates="establishment",
        cascade="all, delete-orphan"
    )


class ContractorApplicationDB(Base):
    __tablename__ = "contractor_applications"

    id = Column(Integer, primary_key=True, autoincrement=True)
    establishment_id = Column(Integer, ForeignKey("establishments.id"), nullable=False)
    application_number = Column(String(50), unique=True, index=True)
    pe_ein = Column(String(50), nullable=True)
    pe_name = Column(String(200), nullable=True)
    nature_of_work = Column(String(250), nullable=True)
    contract_start_date = Column(String(20), nullable=True)
    contract_end_date = Column(String(20), nullable=True)
    total_labour = Column(Integer, default=0)
    male_labour = Column(Integer, default=0)
    female_labour = Column(Integer, default=0)
    trans_labour = Column(Integer, default=0)
    total_bg_amount = Column(Float, default=0.0)
    status = Column(String(50), default="DRAFT")  # DRAFT, VERIFIED, SUBMITTED, APPROVED, REJECTED
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, nullable=True)

    establishment = relationship("EstablishmentDB", back_populates="applications")


class DocumentDB(Base):
    __tablename__ = "documents"

    id = Column(Integer, primary_key=True, autoincrement=True)
    establishment_id = Column(Integer, ForeignKey("establishments.id"), nullable=False)
    doc_type = Column(String(100), nullable=False)   # PAN, GSTIN, WORK_ORDER, BANK, etc.
    file_path = Column(String(500), nullable=False)
    mime_type = Column(String(100), nullable=True)
    file_size = Column(Integer, nullable=True)
    ocr_extracted_json = Column(Text, nullable=True)
    uploaded_at = Column(DateTime, default=datetime.utcnow)

    establishment = relationship("EstablishmentDB", back_populates="documents")


# ---------------------------------------------------------------------------
# Pydantic Schemas
# ---------------------------------------------------------------------------
class ShramsetuFormModel(BaseModel):
    """
    Unified auto-fill data contract shared by backend, mobile & webview.
    Every field below corresponds 1:1 to a field documented in the official
    Shramsetu Portal manual (Establishment Master, Registration Application,
    License FORM-25, Bank Guarantee) and to the docxtpl Word templates in
    backend/app/templates/Shramsetu_Contractor_Template.docx and
    Shramsetu_Principal_Employer_Template.docx.
    """

    # --- Convenience OCR-extraction fields (not portal fields themselves;
    #     used to auto-populate tan_pan_registration / other_registration_gst) ---
    pan_number: Optional[str] = Field(default="")
    gstin: Optional[str] = Field(default="")

    already_holding_crla_license: Optional[str] = Field(default="")
    already_registered_central_labour_laws: Optional[str] = Field(default="")
    applicant_remark: Optional[str] = Field(default="")
    application_date: Optional[str] = Field(default="")
    application_number: Optional[str] = Field(default="")
    application_status: Optional[str] = Field(default="")
    area: Optional[str] = Field(default="")
    authorized_person_designation: Optional[str] = Field(default="")
    authorized_person_designation_proof: Optional[str] = Field(default="")
    authorized_person_dob: Optional[str] = Field(default="")
    authorized_person_email: Optional[str] = Field(default="")
    authorized_person_identity_number: Optional[str] = Field(default="")
    authorized_person_mobile: Optional[str] = Field(default="")
    authorized_person_name: Optional[str] = Field(default="")
    authorized_person_permanent_address: Optional[str] = Field(default="")
    authorized_person_registered_email: Optional[str] = Field(default="")
    authorized_person_secondary_address: Optional[str] = Field(default="")
    authorized_person_tenure_from: Optional[str] = Field(default="")
    authorized_person_tenure_to: Optional[str] = Field(default="")
    bg_application_status: Optional[str] = Field(default="")
    bg_area: Optional[str] = Field(default="")
    bg_authority_name: Optional[str] = Field(default="")
    bg_bank_address: Optional[str] = Field(default="")
    bg_bank_ifsc: Optional[str] = Field(default="")
    bg_bank_name: Optional[str] = Field(default="")
    bg_contractor_name_address: Optional[str] = Field(default="")
    bg_contractor_reg_number: Optional[str] = Field(default="")
    bg_date: Optional[str] = Field(default="")
    bg_district: Optional[str] = Field(default="")
    bg_format_number: Optional[str] = Field(default="")
    bg_license_app_number: Optional[str] = Field(default="")
    bg_license_certificate: Optional[str] = Field(default="")
    bg_pe_name_address: Optional[str] = Field(default="")
    bg_pe_reg_number: Optional[str] = Field(default="")
    bg_security_deposit_per_labour: Optional[str] = Field(default="")
    bg_state: Optional[str] = Field(default="")
    bg_status_email: Optional[str] = Field(default="")
    bg_total_amount: Optional[str] = Field(default="")
    bg_total_contract_labour: int = Field(default=0, ge=0)
    bg_validity_period: Optional[str] = Field(default="")
    bg_zone: Optional[str] = Field(default="")
    chemicals_details: Optional[str] = Field(default="")
    contract_commencement_date: Optional[str] = Field(default="")
    contract_completion_date: Optional[str] = Field(default="")
    contractor_address: Optional[str] = Field(default="")
    contractor_apprentices: int = Field(default=0, ge=0)
    contractor_commencement_date2: Optional[str] = Field(default="")
    contractor_corporate_office_address: Optional[str] = Field(default="")
    contractor_district: Optional[str] = Field(default="")
    contractor_district2: Optional[str] = Field(default="")
    contractor_ein_selected: Optional[str] = Field(default="")
    contractor_email2: Optional[str] = Field(default="")
    contractor_head_office_address: Optional[str] = Field(default="")
    contractor_identification_number: Optional[str] = Field(default="")
    contractor_manpower_contractor2: int = Field(default=0, ge=0)
    contractor_manpower_establishment: int = Field(default=0, ge=0)
    contractor_manpower_fixed_term2: int = Field(default=0, ge=0)
    contractor_manpower_interstate2: int = Field(default=0, ge=0)
    contractor_manpower_motor_transport2: int = Field(default=0, ge=0)
    contractor_manpower_total2: int = Field(default=0, ge=0)
    contractor_mobile: Optional[str] = Field(default="")
    contractor_mobile2: Optional[str] = Field(default="")
    contractor_name: Optional[str] = Field(default="")
    contractor_name2: Optional[str] = Field(default="")
    contractor_nic_code: Optional[str] = Field(default="")
    contractor_ownership_type: Optional[str] = Field(default="")
    contractor_pincode: Optional[str] = Field(default="")
    contractor_pincode2: Optional[str] = Field(default="")
    contractor_reg_number: Optional[str] = Field(default="")
    contractor_registration_no: Optional[str] = Field(default="")
    contractor_risk_category: Optional[str] = Field(default="")
    contractor_taluka: Optional[str] = Field(default="")
    contractor_taluka2: Optional[str] = Field(default="")
    corporate_office_address: Optional[str] = Field(default="")
    district: Optional[str] = Field(default="")
    do_you_intend_employee: Optional[str] = Field(default="")
    documents_list: Optional[str] = Field(default="")
    ein: Optional[str] = Field(default="")
    email_id: Optional[str] = Field(default="")
    epf_registration: Optional[str] = Field(default="")
    esi_registration: Optional[str] = Field(default="")
    establishment_commencement_date: Optional[str] = Field(default="")
    establishment_name: Optional[str] = Field(default="")
    expected_completion_date: Optional[str] = Field(default="")
    factory_registration: Optional[str] = Field(default="")
    first_name: Optional[str] = Field(default="")
    head_office_address: Optional[str] = Field(default="")
    investor_type: Optional[str] = Field(default="")
    last_name: Optional[str] = Field(default="")
    license_additional_documents: Optional[str] = Field(default="")
    license_application_type: Optional[str] = Field(default="")
    license_area: Optional[str] = Field(default="")
    license_authorized_email: Optional[str] = Field(default="")
    license_commencement_date: Optional[str] = Field(default="")
    license_completion_date: Optional[str] = Field(default="")
    license_documents_list: Optional[str] = Field(default="")
    license_fee: Optional[str] = Field(default="")
    license_nature_of_work: Optional[str] = Field(default="")
    license_office_location: Optional[str] = Field(default="")
    license_otp: Optional[str] = Field(default="")
    license_total_contract_labour: int = Field(default=0, ge=0)
    license_zone: Optional[str] = Field(default="")

    # --- Fields confirmed from the real License FORM-25 page HTML
    #     (Application_for_License_form_25_for_contractor.html) that were
    #     missing from the original model: Nature of Work and covered
    #     Districts are checkbox CHECKLISTS on the real portal (88 and 33
    #     options respectively -- see backend/app/reference_data.py), not
    #     free text. Selections are stored here as comma-separated portal
    #     checkbox IDs (matching the portal's own natureOfWorkCheckbox_<id>
    #     / districtCheckbox_<id> convention) so they can be submitted
    #     straight into the live portal. license_nature_of_work above is
    #     kept as a free-text summary for Word-doc narrative purposes only.
    nature_of_work_ids: Optional[str] = Field(default="")
    license_covered_district_ids: Optional[str] = Field(default="")

    # Declaration/undertaking checkboxes (labourLawsCheckbox,
    # convictionCheckbox, orderCheckbox on the real portal), each with a
    # bilingual (Gujarati/English) statement and, for the latter two, a
    # conditional free-text remarks field shown only when checked.
    labour_laws_undertaking: bool = Field(default=False)
    conviction_declaration: bool = Field(default=False)
    conviction_remarks: Optional[str] = Field(default="")
    prior_order_declaration: bool = Field(default=False)
    prior_order_remarks: Optional[str] = Field(default="")

    # File-upload reference fields (DOC6 = Work Order, DOC7 = Others on the
    # real portal); stored here as filename/path references, not file
    # bytes -- the actual upload happens via the mobile OCR upload flow.
    license_work_order_doc_ref: Optional[str] = Field(default="")
    license_other_doc_ref: Optional[str] = Field(default="")

    # "Max Workmen Count" on the License FORM-25 page (MaxEmployerCount) --
    # distinct from pe_max_workmen_count, which is the Principal Employer's
    # own establishment-level cap surfaced on the License auto-populated
    # PE section; this one is the license-specific ceiling. Also confirmed
    # to appear under the same real field name on the OSHWC Code
    # Registration Application page (Step B).
    license_max_workmen_count: int = Field(default=0, ge=0)

    # Confirmed field on the OSHWC Code Registration Application page
    # (EstablismentContlabmax) with no recovered <label> text -- likely a
    # cap on total contract labour permitted for the establishment, but
    # this is inferred from the field name alone, not a confirmed label.
    # Flagged for manual verification against the live portal.
    establishment_contract_labour_max: int = Field(default=0, ge=0)

    # Confirmed field (real portal name "Name", label "Name / નામ") on the
    # OSHWC Code Registration Application page. Kept distinct from
    # authorized_person_name since its exact role (applicant vs.
    # authorized person vs. establishment contact) wasn't confirmable from
    # the captured HTML alone -- no surrounding section header was
    # recovered to disambiguate.
    applicant_name: Optional[str] = Field(default="")

    lin: Optional[str] = Field(default="")
    local_authority_approval_details: Optional[str] = Field(default="")
    login_user_id: Optional[str] = Field(default="")
    # --- Section B: Manpower Distribution Matrix (Male/Female/Trans per
    #     category, per the Shramsetu Exhaustive AutoFill Documents
    #     Checklist Part 3). Row and grand totals are "[ Auto ]" cells on
    #     the portal — computed here, not user-entered. ---
    manpower_direct_male: int = Field(default=0, ge=0)
    manpower_direct_female: int = Field(default=0, ge=0)
    manpower_direct_trans: int = Field(default=0, ge=0)
    manpower_contractor_male: int = Field(default=0, ge=0)
    manpower_contractor_female: int = Field(default=0, ge=0)
    manpower_contractor_trans: int = Field(default=0, ge=0)
    manpower_fixed_term_male: int = Field(default=0, ge=0)
    manpower_fixed_term_female: int = Field(default=0, ge=0)
    manpower_fixed_term_trans: int = Field(default=0, ge=0)
    manpower_interstate_migrant_male: int = Field(default=0, ge=0)
    manpower_interstate_migrant_female: int = Field(default=0, ge=0)
    manpower_interstate_migrant_trans: int = Field(default=0, ge=0)
    manpower_motor_transport_male: int = Field(default=0, ge=0)
    manpower_motor_transport_female: int = Field(default=0, ge=0)
    manpower_motor_transport_trans: int = Field(default=0, ge=0)

    # 6th manpower category confirmed live in the real portal's JS
    # (calcValother/AJAX/XML builders reference ApprenticeMaleWorker etc.),
    # but NOT summed into TotalEmpWorkersCount/manpower_total by the
    # portal's own JS -- tracked as a separate quad, per real observed
    # calc logic (sum1..sum5 spans only Direct/Contract/FixTerm/Migrant/
    # Others; Apprentice is excluded from that grand-total array).
    manpower_apprentice_male: int = Field(default=0, ge=0)
    manpower_apprentice_female: int = Field(default=0, ge=0)
    manpower_apprentice_trans: int = Field(default=0, ge=0)

    # Section C — per-registration-type checkboxes ("Is this registration
    # applicable?") that gate the corresponding number/date/authority
    # fields on the real portal. Sent as "on"/"" (portal's own checkbox
    # value convention observed in the HTML) rather than a Python bool,
    # since the webview JS sets `.checked` directly from truthiness.
    is_pan_registered: bool = Field(default=False)
    is_tan_registered: bool = Field(default=False)
    is_other_registered: bool = Field(default=False)
    is_gumasta_registered: bool = Field(default=False)
    is_epf_registered: bool = Field(default=False)
    is_factory_registered: bool = Field(default=False)
    is_esi_registered: bool = Field(default=False)

    # Section C — per-registration date-of-issue / issuing-authority
    # sub-fields (the real portal's PanDateofIssue/PanIssuedbyAuthority
    # pattern, repeated per registration type).
    tan_registration_no: Optional[str] = Field(default="")
    pan_date_of_issue: Optional[str] = Field(default="")
    pan_issuing_authority: Optional[str] = Field(default="")
    other_registration_date_of_issue: Optional[str] = Field(default="")
    other_registration_issuing_authority: Optional[str] = Field(default="")
    shop_establishment_date_of_issue: Optional[str] = Field(default="")
    shop_establishment_issuing_authority: Optional[str] = Field(default="")
    epf_date_of_issue: Optional[str] = Field(default="")
    epf_issuing_authority: Optional[str] = Field(default="")
    factory_date_of_issue: Optional[str] = Field(default="")
    factory_issuing_authority: Optional[str] = Field(default="")
    esi_date_of_issue: Optional[str] = Field(default="")
    esi_issuing_authority: Optional[str] = Field(default="")

    manufacturing_process_details: Optional[str] = Field(default="")
    middle_name: Optional[str] = Field(default="")
    mobile_number: Optional[str] = Field(default="")
    nature_of_work: Optional[str] = Field(default="")
    nic_code: Optional[str] = Field(default="")
    office_address: Optional[str] = Field(default="")
    office_location_area: Optional[str] = Field(default="")
    other_registration_gst: Optional[str] = Field(default="")
    pe_address: Optional[str] = Field(default="")
    pe_address2: Optional[str] = Field(default="")
    pe_approval_date: Optional[str] = Field(default="")
    pe_authorized_person_details: Optional[str] = Field(default="")
    pe_district: Optional[str] = Field(default="")
    pe_district2: Optional[str] = Field(default="")
    pe_ein_selected: Optional[str] = Field(default="")
    pe_email2: Optional[str] = Field(default="")
    pe_est_name: Optional[str] = Field(default="")
    pe_max_workmen_count: int = Field(default=0, ge=0)
    pe_mobile: Optional[str] = Field(default="")
    pe_mobile2: Optional[str] = Field(default="")
    pe_name: Optional[str] = Field(default="")
    pe_nic_code: Optional[str] = Field(default="")
    pe_ownership_type: Optional[str] = Field(default="")
    pe_pincode: Optional[str] = Field(default="")
    pe_pincode2: Optional[str] = Field(default="")
    pe_reg_date: Optional[str] = Field(default="")
    pe_reg_number: Optional[str] = Field(default="")
    pe_registration_no: Optional[str] = Field(default="")
    pe_risk_category: Optional[str] = Field(default="")
    pe_selected_ein: Optional[str] = Field(default="")
    pe_taluka: Optional[str] = Field(default="")
    pe_taluka2: Optional[str] = Field(default="")
    pe_type_establishment: Optional[str] = Field(default="")
    pe_type_industry: Optional[str] = Field(default="")
    pincode: Optional[str] = Field(default="")
    probable_commencement_date: Optional[str] = Field(default="")
    reg_email: Optional[str] = Field(default="")
    reg_mobile_number: Optional[str] = Field(default="")
    registration_certificate_no: Optional[str] = Field(default="")
    registration_fee_details: Optional[str] = Field(default="")
    registration_otp: Optional[str] = Field(default="")
    risk_category: Optional[str] = Field(default="")
    shop_establishment_registration: Optional[str] = Field(default="")
    size_of_firm: Optional[str] = Field(default="")
    taluka: Optional[str] = Field(default="")
    tan_pan_registration: Optional[str] = Field(default="")
    total_contract_labour: int = Field(default=0, ge=0)
    total_horsepower: Optional[str] = Field(default="")
    type_of_construction_work: Optional[str] = Field(default="")
    type_of_establishment: Optional[str] = Field(default="")
    type_of_industry: Optional[str] = Field(default="")
    type_of_ownership: Optional[str] = Field(default="")

    prior_registration_number: Optional[str] = Field(default="")
    prior_registration_certificate_ref: Optional[str] = Field(default="")
    bg_signed_pdf_reference: Optional[str] = Field(default="")

    @field_validator("pan_number")
    @classmethod
    def validate_pan(cls, v: str) -> str:
        import re
        v = (v or "").upper().strip()
        if v and not re.fullmatch(r"[A-Z]{{5}}[0-9]{{4}}[A-Z]{{1}}", v):
            raise ValueError("Invalid PAN format")
        return v

    @field_validator("gstin")
    @classmethod
    def validate_gstin(cls, v: str) -> str:
        import re
        v = (v or "").upper().strip()
        if v and not re.fullmatch(r"[0-9]{{2}}[A-Z]{{5}}[0-9]{{4}}[A-Z]{{1}}[1-9A-Z]{{1}}Z[0-9A-Z]{{1}}", v):
            raise ValueError("Invalid GSTIN format")
        return v

    def apply_ocr_defaults(self) -> "ShramsetuFormModel":
        """Populate portal registration-proof fields from OCR-extracted PAN/GSTIN."""
        if self.pan_number and not self.tan_pan_registration:
            self.tan_pan_registration = self.pan_number
        if self.gstin and not self.other_registration_gst:
            self.other_registration_gst = self.gstin
        return self

    @property
    def manpower_direct_total(self) -> int:
        return self.manpower_direct_male + self.manpower_direct_female + self.manpower_direct_trans

    @property
    def manpower_contractor_total(self) -> int:
        return self.manpower_contractor_male + self.manpower_contractor_female + self.manpower_contractor_trans

    @property
    def manpower_fixed_term_total(self) -> int:
        return self.manpower_fixed_term_male + self.manpower_fixed_term_female + self.manpower_fixed_term_trans

    @property
    def manpower_interstate_migrant_total(self) -> int:
        return (self.manpower_interstate_migrant_male + self.manpower_interstate_migrant_female
                + self.manpower_interstate_migrant_trans)

    @property
    def manpower_motor_transport_total(self) -> int:
        return (self.manpower_motor_transport_male + self.manpower_motor_transport_female
                + self.manpower_motor_transport_trans)

    @property
    def manpower_total_male(self) -> int:
        return (self.manpower_direct_male + self.manpower_contractor_male + self.manpower_fixed_term_male
                + self.manpower_interstate_migrant_male + self.manpower_motor_transport_male)

    @property
    def manpower_total_female(self) -> int:
        return (self.manpower_direct_female + self.manpower_contractor_female + self.manpower_fixed_term_female
                + self.manpower_interstate_migrant_female + self.manpower_motor_transport_female)

    @property
    def manpower_total_trans(self) -> int:
        return (self.manpower_direct_trans + self.manpower_contractor_trans + self.manpower_fixed_term_trans
                + self.manpower_interstate_migrant_trans + self.manpower_motor_transport_trans)

    @property
    def manpower_apprentice_total(self) -> int:
        """
        Tracked separately from computed_manpower_total by design: the real
        portal's own JS grand-total summation (sum1..sum5 across
        Direct/Contract/FixTerm/Migrant/Others) never includes Apprentice
        counts in TotalEmpWorkersCount.
        """
        return self.manpower_apprentice_male + self.manpower_apprentice_female + self.manpower_apprentice_trans

    @property
    def computed_manpower_total(self) -> int:
        """Grand total across all 5 categories x 3 genders (Section B footer cell)."""
        return self.manpower_total_male + self.manpower_total_female + self.manpower_total_trans

    def manpower_render_context(self) -> dict:
        """Auto-computed cells for the Section B matrix, merged into the docxtpl context."""
        return {
            "manpower_direct_total": self.manpower_direct_total,
            "manpower_contractor_total": self.manpower_contractor_total,
            "manpower_fixed_term_total": self.manpower_fixed_term_total,
            "manpower_interstate_migrant_total": self.manpower_interstate_migrant_total,
            "manpower_motor_transport_total": self.manpower_motor_transport_total,
            "manpower_total_male": self.manpower_total_male,
            "manpower_total_female": self.manpower_total_female,
            "manpower_total_trans": self.manpower_total_trans,
            "manpower_total": self.computed_manpower_total,
            "manpower_apprentice_total": self.manpower_apprentice_total,
        }


class EstablishmentCreate(BaseModel):
    name: str
    pan: str
    gstin: Optional[str] = None
    ownership_type: Optional[str] = "Sole Proprietorship"
    head_address: Optional[str] = None
    district: Optional[str] = None
    pincode: Optional[str] = None


class EstablishmentOut(EstablishmentCreate):
    id: int
    ein: Optional[str] = None
    risk_category: Optional[str] = None
    created_at: datetime

    class Config:
        from_attributes = True


class ApplicationCreate(BaseModel):
    establishment_id: int
    pe_ein: Optional[str] = None
    pe_name: Optional[str] = None
    nature_of_work: Optional[str] = None
    contract_start_date: Optional[str] = None
    contract_end_date: Optional[str] = None
    male_labour: int = 0
    female_labour: int = 0
    trans_labour: int = 0
    total_bg_amount: float = 0.0


class ApplicationOut(ApplicationCreate):
    id: int
    application_number: str
    total_labour: int
    status: str
    created_at: datetime

    class Config:
        from_attributes = True


class OCRExtractResponse(BaseModel):
    doc_type: str
    extracted_fields: dict
    raw_text_preview: str
    confidence_note: str = "Auto-extracted; verify before final submission."
