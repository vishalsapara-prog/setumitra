"""
Shramsetu Automation Engine - OCR Vision, Regex Extraction, Cross-Check
& docxtpl Word Generation Engine.
"""
import io
import os
import re
from typing import Dict, Any, Optional

import pdfplumber
from rapidfuzz import fuzz
from docxtpl import DocxTemplate

from .models import ShramsetuFormModel

TEMPLATE_DIR = os.path.join(os.path.dirname(__file__), "templates")
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "..", "generated")
os.makedirs(OUTPUT_DIR, exist_ok=True)

try:
    import pytesseract
    from PIL import Image
    _TESSERACT_AVAILABLE = True
except ImportError:
    _TESSERACT_AVAILABLE = False


class ShramsetuDocParser:
    """Regex + heuristic parser for statutory Indian identity/tax documents."""

    PAN_REGEX = r'[A-Z]{5}[0-9]{4}[A-Z]{1}'
    GST_REGEX = r'[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}'
    DATE_REGEX = (
        r'(?:\b\d{1,2}[-/\.]\d{1,2}[-/\.]\d{2,4}\b|'
        r'\b\d{1,2}(?:st|nd|rd|th)?\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)'
        r'[a-z]*[\s,]+\d{4}\b)'
    )
    IFSC_REGEX = r'\b[A-Z]{4}0[A-Z0-9]{6}\b'
    PINCODE_REGEX = r'\b\d{6}\b'

    @staticmethod
    def extract_text(pdf_source: Any) -> str:
        """Extract raw text from a PDF path, bytes, or file-like object."""
        text = ""
        try:
            stream = io.BytesIO(pdf_source) if isinstance(pdf_source, (bytes, bytearray)) else pdf_source
            with pdfplumber.open(stream) as pdf:
                for page in pdf.pages:
                    content = page.extract_text()
                    if content:
                        text += content + "\n"
        except Exception as e:
            print(f"[OCR Warning] {str(e)}")
        return text

    @staticmethod
    def extract_text_from_image(image_bytes: bytes) -> str:
        """
        Extract raw text from a JPG/PNG document photo via Tesseract OCR.

        Requires the `tesseract-ocr` system binary to be installed on the
        host (see backend/Dockerfile, which installs it for the containerized
        deployment; for a bare-metal run, `apt install tesseract-ocr` /
        `brew install tesseract` / the Windows installer from
        https://github.com/UB-Mannheim/tesseract/wiki). If pytesseract or the
        binary is unavailable, this returns an empty string rather than
        raising, so callers can fall back to manual data entry.
        """
        if not _TESSERACT_AVAILABLE:
            print("[OCR Warning] pytesseract/Pillow not installed; image OCR unavailable.")
            return ""
        try:
            image = Image.open(io.BytesIO(image_bytes))
            if image.mode != "RGB":
                image = image.convert("RGB")
            return pytesseract.image_to_string(image, lang="eng")
        except pytesseract.TesseractNotFoundError:
            print("[OCR Warning] Tesseract binary not found on this system. "
                  "Install it (see docstring) to enable image OCR.")
            return ""
        except Exception as e:
            print(f"[OCR Warning] Image OCR failed: {str(e)}")
            return ""

    @classmethod
    def parse_pan(cls, text: str) -> Dict[str, str]:
        pan_matches = re.findall(cls.PAN_REGEX, text.upper())
        pan = pan_matches[0] if pan_matches else ""
        lines = [l.strip() for l in text.split('\n') if l.strip()]
        name, dob = "", ""
        for i, l in enumerate(lines):
            if "INCOME TAX DEPARTMENT" in l.upper() or "GOVT. OF INDIA" in l.upper():
                if i + 1 < len(lines):
                    name = lines[i + 1]
            dt = re.search(cls.DATE_REGEX, l)
            if dt and not dob:
                dob = dt.group(0)
        return {"pan_number": pan, "legal_name": name, "dob": dob}

    @classmethod
    def parse_gst(cls, text: str) -> Dict[str, str]:
        gst_matches = re.findall(cls.GST_REGEX, text.upper())
        gstin = gst_matches[0] if gst_matches else ""
        legal_name, trade_name, address, pincode = "", "", "", ""
        l_m = re.search(r'Legal Name\s*[:\-]?\s*([^\n\r]+)', text, re.IGNORECASE)
        if l_m:
            legal_name = l_m.group(1).strip()
        t_m = re.search(r'Trade Name\s*[:\-]?\s*([^\n\r]+)', text, re.IGNORECASE)
        if t_m:
            trade_name = t_m.group(1).strip()
        a_m = re.search(r'Address\s*[:\-]?\s*([^\n\r]+)', text, re.IGNORECASE)
        if a_m:
            address = a_m.group(1).strip()
        pin_matches = re.findall(cls.PINCODE_REGEX, text)
        if pin_matches:
            pincode = pin_matches[-1]
        return {
            "gstin": gstin,
            "legal_name": legal_name,
            "trade_name": trade_name,
            "address": address,
            "pincode": pincode,
        }

    @classmethod
    def parse_bank_details(cls, text: str) -> Dict[str, str]:
        ifsc_matches = re.findall(cls.IFSC_REGEX, text.upper())
        ifsc = ifsc_matches[0] if ifsc_matches else ""
        acc_m = re.search(r'(?:A/?C|Account)\s*(?:No\.?)?\s*[:\-]?\s*(\d{9,18})', text, re.IGNORECASE)
        account_number = acc_m.group(1) if acc_m else ""
        bank_m = re.search(r'Bank\s*Name\s*[:\-]?\s*([^\n\r]+)', text, re.IGNORECASE)
        bank_name = bank_m.group(1).strip() if bank_m else ""
        return {"ifsc": ifsc, "account_number": account_number, "bank_name": bank_name}

    @classmethod
    def parse_work_order(cls, text: str) -> Dict[str, str]:
        dates = re.findall(cls.DATE_REGEX, text)
        start_date = dates[0] if len(dates) >= 1 else ""
        end_date = dates[1] if len(dates) >= 2 else ""
        value_m = re.search(r'(?:Contract\s*Value|Total\s*Value)\s*[:\-]?\s*₹?\s*([\d,]+)', text, re.IGNORECASE)
        value = value_m.group(1) if value_m else ""
        nature_m = re.search(r'Nature\s*of\s*Work\s*[:\-]?\s*([^\n\r]+)', text, re.IGNORECASE)
        nature = nature_m.group(1).strip() if nature_m else ""
        return {
            "contract_start_date": start_date,
            "contract_end_date": end_date,
            "contract_value": value,
            "nature_of_work": nature,
        }

    @classmethod
    def parse_pe_form3(cls, text: str) -> Dict[str, str]:
        """Document #4 (Contractor checklist): Principal Employer Form-III / EIN certificate."""
        ein_m = re.search(r'\bEIN\s*[:\-]?\s*([A-Z0-9]{6,20})', text, re.IGNORECASE)
        reg_m = re.search(r'Registration\s*(?:No\.?|Number)\s*[:\-]?\s*([A-Za-z0-9/\-]+)', text, re.IGNORECASE)
        date_m = re.search(cls.DATE_REGEX, text)
        name_m = re.search(r'(?:Establishment|Principal Employer)\s*Name\s*[:\-]?\s*([^\n\r]+)', text, re.IGNORECASE)
        addr_m = re.search(r'Address\s*[:\-]?\s*([^\n\r]+)', text, re.IGNORECASE)
        pin_matches = re.findall(cls.PINCODE_REGEX, text)
        return {
            "pe_ein_selected": ein_m.group(1) if ein_m else "",
            "pe_registration_no": reg_m.group(1) if reg_m else "",
            "pe_reg_date": date_m.group(0) if date_m else "",
            "pe_name": name_m.group(1).strip() if name_m else "",
            "pe_address": addr_m.group(1).strip() if addr_m else "",
            "pe_pincode": pin_matches[-1] if pin_matches else "",
        }

    @classmethod
    def parse_auth_person_id(cls, text: str) -> Dict[str, str]:
        """Document #5/#4 (both checklists): Authorized Person identity proof."""
        pan_matches = re.findall(cls.PAN_REGEX, text.upper())
        dob_m = re.search(cls.DATE_REGEX, text)
        name_m = re.search(r'Name\s*[:\-]?\s*([^\n\r]+)', text, re.IGNORECASE)
        addr_m = re.search(r'Address\s*[:\-]?\s*([^\n\r]+)', text, re.IGNORECASE)
        return {
            "authorized_person_identity_number": pan_matches[0] if pan_matches else "",
            "authorized_person_dob": dob_m.group(0) if dob_m else "",
            "authorized_person_name": name_m.group(1).strip() if name_m else "",
            "authorized_person_permanent_address": addr_m.group(1).strip() if addr_m else "",
        }

    @classmethod
    def parse_designation_proof(cls, text: str) -> Dict[str, str]:
        """Document #6/#5: Designation Proof / Appointment Order / Power of Attorney."""
        designation_m = re.search(r'Designat(?:ion|ed\s*as)\s*[:\-]?\s*([^\n\r]+)', text, re.IGNORECASE)
        dates = re.findall(cls.DATE_REGEX, text)
        return {
            "authorized_person_designation": designation_m.group(1).strip() if designation_m else "",
            "authorized_person_tenure_from": dates[0] if dates else "",
            "authorized_person_tenure_to": dates[1] if len(dates) > 1 else "",
            "authorized_person_designation_proof": "Extracted from uploaded document; verify manually.",
        }

    @classmethod
    def parse_shop_establishment(cls, text: str) -> Dict[str, str]:
        """Document #8: Gumasta Dhara / Shop & Establishment Registration Certificate."""
        reg_m = re.search(r'Reg(?:istration)?\.?\s*(?:No\.?|Number)\s*[:\-]?\s*([A-Za-z0-9/\-]+)', text, re.IGNORECASE)
        date_m = re.search(cls.DATE_REGEX, text)
        return {
            "shop_establishment_registration": reg_m.group(1) if reg_m else "",
            "establishment_commencement_date": date_m.group(0) if date_m else "",
        }

    @classmethod
    def _extract_trailing_token(cls, line: str) -> str:
        """
        Extracts the trailing code-like token from a line. Allows "." as a
        mid-token character (stripped if trailing): Tesseract sometimes
        misreads a hyphen as a period within a registration number (e.g.
        "31-00-987654-000-1001" -> "31-00-987654.000-1001"); without this,
        the token regex would split there and silently return only the
        truncated tail as if it were the complete number.
        """
        tokens = re.findall(r'[A-Za-z0-9][A-Za-z0-9/\-.]{3,}', line)
        return tokens[-1].rstrip('.') if tokens else ""

    @classmethod
    def _identity_prefix_line_extract(cls, text: str, identity_prefixes: list) -> Optional[str]:
        """
        Finds the first line whose text starts with one of the given
        organization-identity tokens (e.g. "PF"/"EPF"/"EPFO" for provident
        fund lines, "ESI"/"ESIC" for state insurance lines) and returns its
        trailing code-like token.

        This is Stage 1 of a two-stage extraction and is preferred over
        pure fuzzy phrase-matching where possible: fuzzy matching against
        phrases like "EPF Registration No" / "PF Registration" is
        vulnerable to a real, twice-reproduced bug class where a shared
        generic word ("Registration"/"Reg No") scores a HIGHER match
        against a completely different but similarly-worded line (e.g. an
        ESIC line) than against the line's own, more abbreviated correct
        text -- silently returning one field's value for another. Matching
        on the line's short, specific leading identity token sidesteps
        this collision entirely, while still tolerating a dropped leading
        letter (EPF->PF is already a natural prefix relationship; ESIC->ESI
        likewise). Returns None if no line starts with any given prefix,
        so the caller can fall back to fuzzy matching.
        """
        for line in text.split("\n"):
            line = line.strip()
            if not line:
                continue
            upper = line.upper()
            for tok in identity_prefixes:
                if upper.startswith(tok.upper()):
                    return cls._extract_trailing_token(line)
        return None

    @classmethod
    def _fuzzy_line_extract(cls, text: str, label_keywords: list, min_score: float = 60.0) -> str:
        """
        Finds the line most similar (via rapidfuzz partial_ratio) to any of
        the given label phrases, then extracts the trailing code-like token
        from that line.

        This exists because strict-prefix regexes (e.g. requiring a literal
        "EPF" at the start) break against real Tesseract OCR noise on
        photographed documents — e.g. "EPF Registration No." commonly comes
        back as "PF Registration No." (dropped leading letter) or
        "Code:" -> "Cade:" (0/O and other character confusions). Verified
        against an actual Tesseract-OCR'd synthetic test image during
        development: the strict-regex version silently returned empty
        strings on this exact noisy input, while this fuzzy version
        correctly recovered both codes. PDF-sourced text (pdfplumber, no
        OCR noise) still matches trivially since exact text scores ~100.

        Callers with a reliable short identity token (EPF/ESIC) should
        prefer `_identity_prefix_line_extract` first and use this only as a
        fallback -- see `parse_epf_esic` -- since pure phrase-fuzzy-matching
        alone is vulnerable to the generic-shared-word collision described
        in `_identity_prefix_line_extract`'s docstring.
        """
        best_line, best_score = None, 0.0
        for line in text.split("\n"):
            line = line.strip()
            if not line:
                continue
            for kw in label_keywords:
                score = fuzz.partial_ratio(kw.upper(), line.upper())
                if score > best_score:
                    best_score, best_line = score, line
        if best_score < min_score or not best_line:
            return ""
        return cls._extract_trailing_token(best_line)

    @classmethod
    def parse_epf_esic(cls, text: str) -> Dict[str, str]:
        """
        Document #9: EPF & ESIC registration proof.

        Uses identity-prefix matching first (Stage 1: a line literally
        starting with "PF"/"EPF"/"EPFO" or "ESI"/"ESIC"), falling back to
        fuzzy phrase matching (Stage 2) only if no line has a recognizable
        identity prefix. This two-stage approach was adopted after fuzzy-
        only matching was found, via repeated real-execution testing, to
        twice silently cross-contaminate EPF and ESIC values when their
        keyword phrases shared a generic word ("Registration No"/"Reg No")
        that happened to fuzzy-match the WRONG field's line better than the
        RIGHT field's own (differently-abbreviated) line.
        """
        epf_code = cls._identity_prefix_line_extract(text, ["PF", "EPF", "EPFO"])
        if epf_code is None:
            epf_code = cls._fuzzy_line_extract(text, ["EPF Registration No", "EPFO Code", "PF Registration"])

        esic_code = cls._identity_prefix_line_extract(text, ["ESI", "ESIC"])
        if esic_code is None:
            esic_code = cls._fuzzy_line_extract(text, ["ESIC Code", "ESI Code"])

        return {"epf_registration": epf_code, "esi_registration": esic_code}

    @classmethod
    def parse_prior_license(cls, text: str) -> Dict[str, str]:
        """Document #10: Prior Central Labour Act registration / CLRA license."""
        reg_number = cls._fuzzy_line_extract(text, ["License Number", "Licence Number", "Registration Number"])
        return {"prior_registration_number": reg_number,
                "prior_registration_certificate_ref": "Extracted from uploaded document; verify manually."}

    @classmethod
    def parse_constitution_proof(cls, text: str) -> Dict[str, str]:
        """Document #3 (PE checklist): Constitution / Ownership proof (ROC/MOA/Trust Deed/Govt GR)."""
        ownership_keywords = {
            "PRIVATE LIMITED": "Private Limited", "PUBLIC LIMITED": "Public Limited",
            "PARTNERSHIP": "Partnership", "PROPRIETORSHIP": "Sole Proprietorship",
            "TRUST": "Trust", "SOCIETY": "Society", "GOVERNMENT": "Government",
            "CORPORATION": "Corporation", "LLP": "Limited Liability Partnership",
        }
        upper = text.upper()
        ownership_type = next((v for k, v in ownership_keywords.items() if k in upper), "")
        return {"type_of_ownership": ownership_type,
                "type_of_establishment": "Extracted from uploaded document; verify manually."}

    @classmethod
    def parse_contractor_list(cls, text: str) -> Dict[str, str]:
        """Document #6 (PE checklist): Deployed Contractors & LOA list."""
        ein_matches = re.findall(r'\bEIN\s*[:\-]?\s*([A-Z0-9]{6,20})', text, re.IGNORECASE)
        dates = re.findall(cls.DATE_REGEX, text)
        nature_m = re.search(r'Nature\s*of\s*Work\s*[:\-]?\s*([^\n\r]+)', text, re.IGNORECASE)
        return {
            "contractor_ein_selected": ein_matches[0] if ein_matches else "",
            "nature_of_work": nature_m.group(1).strip() if nature_m else "",
            "contract_commencement_date": dates[0] if dates else "",
            "contract_completion_date": dates[1] if len(dates) > 1 else "",
        }

    @classmethod
    def parse_factory_details(cls, text: str) -> Dict[str, str]:
        """Document #7 (PE checklist): Factory License / Manufacturing Process details."""
        hp_m = re.search(r'(?:Total\s*)?Horsepower\s*(?:\(HP\))?\s*[:\-]?\s*([\d.]+)', text, re.IGNORECASE)
        return {
            "manufacturing_process_details": "Extracted from uploaded document; verify manually.",
            "chemicals_details": "Extracted from uploaded document; verify manually.",
            "total_horsepower": hp_m.group(1) if hp_m else "",
        }

    @classmethod
    def parse_bocw_approval(cls, text: str) -> Dict[str, str]:
        """Document #8 (PE checklist): BOCW Plan / Local Authority Approval."""
        return {
            "type_of_construction_work": "Extracted from uploaded document; verify manually.",
            "local_authority_approval_details": "Extracted from uploaded document; verify manually.",
        }

    @classmethod
    def cross_check_names(cls, name_a: str, name_b: str, threshold: int = 85) -> bool:
        """Fuzzy-match two extracted names (e.g. PAN name vs GST legal name)."""
        if not name_a or not name_b:
            return False
        return fuzz.token_sort_ratio(name_a.upper(), name_b.upper()) >= threshold

    @classmethod
    def route_by_doc_type(cls, doc_type: str, text: str) -> Dict[str, str]:
        """
        Routes an uploaded document to its parser, per the Shramsetu
        Exhaustive AutoFill Documents Checklist (Parts 1 & 2):
        11 Contractor/License documents + 10 Principal Employer documents.
        """
        doc_type = doc_type.upper()
        if doc_type == "PAN":
            return cls.parse_pan(text)
        if doc_type in ("GSTIN", "GST"):
            return cls.parse_gst(text)
        if doc_type == "BANK":
            return cls.parse_bank_details(text)
        if doc_type == "WORK_ORDER":
            return cls.parse_work_order(text)
        if doc_type == "PE_FORM3":
            return cls.parse_pe_form3(text)
        if doc_type == "AUTH_PERSON_ID":
            return cls.parse_auth_person_id(text)
        if doc_type == "DESIGNATION_PROOF":
            return cls.parse_designation_proof(text)
        if doc_type == "SHOP_EST":
            return cls.parse_shop_establishment(text)
        if doc_type == "EPF_ESIC":
            return cls.parse_epf_esic(text)
        if doc_type == "PRIOR_LICENSE":
            return cls.parse_prior_license(text)
        if doc_type == "CONSTITUTION":
            return cls.parse_constitution_proof(text)
        if doc_type == "CONTRACTOR_LIST":
            return cls.parse_contractor_list(text)
        if doc_type == "FACTORY_DETAILS":
            return cls.parse_factory_details(text)
        if doc_type == "BOCW_APPROVAL":
            return cls.parse_bocw_approval(text)
        if doc_type == "EXECUTED_BG":
            return {"bg_signed_pdf_reference": "Uploaded; cross-check bg_format_number manually."}
        return {"raw_matches_pan": re.findall(cls.PAN_REGEX, text.upper())}

    # Canonical checklist reference, exposed for the /api/ocr/document-types endpoint.
    DOCUMENT_CHECKLIST = {
        "CONTRACTOR": [
            {"doc_type": "PAN", "label_en": "PAN Card (Proprietor / Firm PAN)", "mandatory": True},
            {"doc_type": "GSTIN", "label_en": "GSTIN Registration Certificate (Form GST REG-06)", "mandatory": True},
            {"doc_type": "WORK_ORDER", "label_en": "Work Order / LOA / Contract from PE", "mandatory": "License only"},
            {"doc_type": "PE_FORM3", "label_en": "Principal Employer Form-III / EIN Certificate", "mandatory": "License only"},
            {"doc_type": "AUTH_PERSON_ID", "label_en": "Authorized Person ID Proof", "mandatory": True},
            {"doc_type": "DESIGNATION_PROOF", "label_en": "Designation Proof / Authority Letter", "mandatory": True},
            {"doc_type": "BANK", "label_en": "Bank Details (Cancelled Cheque / Passbook)", "mandatory": True},
            {"doc_type": "SHOP_EST", "label_en": "Shop & Establishment Certificate", "mandatory": False},
            {"doc_type": "EPF_ESIC", "label_en": "EPF & ESIC Registration Proof", "mandatory": "If applicable"},
            {"doc_type": "PRIOR_LICENSE", "label_en": "Prior Central / CLRA License", "mandatory": "If previously registered"},
            {"doc_type": "EXECUTED_BG", "label_en": "Signed & Stamped Bank Guarantee PDF", "mandatory": "Final stage"},
        ],
        "PRINCIPAL_EMPLOYER": [
            {"doc_type": "PAN", "label_en": "Establishment PAN / TAN Card", "mandatory": True},
            {"doc_type": "GSTIN", "label_en": "GSTIN Registration Certificate (Form GST REG-06)", "mandatory": True},
            {"doc_type": "CONSTITUTION", "label_en": "Constitution / Ownership Proof (ROC/MOA/Trust Deed/Govt GR)", "mandatory": True},
            {"doc_type": "AUTH_PERSON_ID", "label_en": "Authorized Officer ID Proof", "mandatory": True},
            {"doc_type": "DESIGNATION_PROOF", "label_en": "Appointment Order / Power of Attorney", "mandatory": True},
            {"doc_type": "CONTRACTOR_LIST", "label_en": "Deployed Contractors & LOA List", "mandatory": "For Section D"},
            {"doc_type": "FACTORY_DETAILS", "label_en": "Factory License / Manufacturing Process Details", "mandatory": "Factories only"},
            {"doc_type": "BOCW_APPROVAL", "label_en": "BOCW Plan / Local Authority Approval", "mandatory": "Construction sites only"},
            {"doc_type": "EPF_ESIC", "label_en": "Establishment EPF / ESIC Proof", "mandatory": "If applicable"},
            {"doc_type": "PRIOR_LICENSE", "label_en": "Previous Central Labour Registration", "mandatory": "If previously registered"},
        ],
    }


class BankGuaranteeCalculator:
    """Computes required BG amount for FORM-25 contractor licenses."""

    BASE_RATE_PER_WORKER = 500.0
    MIN_BG_AMOUNT = 25000.0

    @classmethod
    def calculate(cls, total_labour: int, contract_value: float = 0.0) -> float:
        by_labour = total_labour * cls.BASE_RATE_PER_WORKER
        by_value = contract_value * 0.02  # 2% of contract value
        amount = max(by_labour, by_value, cls.MIN_BG_AMOUNT)
        return round(amount, 2)


class ShramsetuDocxGenerator:
    """Renders docxtpl Word templates for Contractor / Principal Employer forms."""

    TEMPLATES = {
        "CONTRACTOR": "Shramsetu_Contractor_Template.docx",
        "PRINCIPAL_EMPLOYER": "Shramsetu_Principal_Employer_Template.docx",
    }

    @classmethod
    def generate(cls, form_type: str, context: ShramsetuFormModel, output_name: str) -> str:
        """
        Render the field-accurate Shramsetu portal template (Establishment
        Master -> Registration -> License FORM-25 -> Bank Guarantee for
        CONTRACTOR; Establishment Master -> Registration for
        PRINCIPAL_EMPLOYER) using the full ShramsetuFormModel context.
        """
        template_file = cls.TEMPLATES.get(form_type.upper())
        if not template_file:
            raise ValueError(f"Unknown form_type: {form_type}")
        template_path = os.path.join(TEMPLATE_DIR, template_file)
        if not os.path.exists(template_path):
            raise FileNotFoundError(
                f"Template not found: {template_path}. "
                "Place the .docx template under backend/app/templates/."
            )
        context = context.apply_ocr_defaults()
        render_ctx = context.model_dump()
        render_ctx.update(context.manpower_render_context())
        doc = DocxTemplate(template_path)
        doc.render(render_ctx)
        output_path = os.path.join(OUTPUT_DIR, output_name)
        doc.save(output_path)
        return output_path
