"""
Comprehensive Pipeline Self-Tests for Shramsetu Automation Engine.
Run: pytest -v
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import pytest
from fastapi.testclient import TestClient

os.environ["DATABASE_URL"] = "sqlite:///./test_shramsetu.db"

from app.main import app  # noqa: E402
from app.engine import ShramsetuDocParser, BankGuaranteeCalculator  # noqa: E402
from app.models import ShramsetuFormModel  # noqa: E402

client = TestClient(app)


def test_health_check():
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"


def test_parse_pan_regex():
    sample = "INCOME TAX DEPARTMENT\nGOVT. OF INDIA\nRAHUL SHARMA\nABCDE1234F\n01/01/1990"
    result = ShramsetuDocParser.parse_pan(sample)
    assert result["pan_number"] == "ABCDE1234F"
    assert result["legal_name"] == "RAHUL SHARMA"


def test_parse_gst_regex():
    sample = "Legal Name: ABC ENTERPRISES\nTrade Name: ABC TRADERS\nGSTIN 24ABCDE1234F1Z5\nAddress: Anand, 388001"
    result = ShramsetuDocParser.parse_gst(sample)
    assert result["gstin"] == "24ABCDE1234F1Z5"
    assert result["legal_name"] == "ABC ENTERPRISES"
    assert result["pincode"] == "388001"


def test_cross_check_names_match():
    assert ShramsetuDocParser.cross_check_names("RAHUL SHARMA", "RAHUL K SHARMA") is True


def test_cross_check_names_mismatch():
    assert ShramsetuDocParser.cross_check_names("RAHUL SHARMA", "SUNIL PATEL") is False


def test_bank_guarantee_calculator_minimum():
    amount = BankGuaranteeCalculator.calculate(total_labour=5, contract_value=0)
    assert amount == BankGuaranteeCalculator.MIN_BG_AMOUNT


def test_bank_guarantee_calculator_by_labour():
    amount = BankGuaranteeCalculator.calculate(total_labour=100, contract_value=0)
    assert amount == 100 * BankGuaranteeCalculator.BASE_RATE_PER_WORKER


def test_extract_text_from_image_degrades_gracefully_on_invalid_bytes():
    """
    Passes garbage (not a real image) into extract_text_from_image: PIL's
    Image.open() will raise, and the function must catch that and return
    '' rather than crash, regardless of whether Tesseract itself is present
    on the host running this test.
    """
    fake_jpg_bytes = b"\xff\xd8\xff\xe0" + b"\x00" * 100  # not a real image; forces the except path
    result = ShramsetuDocParser.extract_text_from_image(fake_jpg_bytes)
    assert result == ""


def test_parse_epf_esic_tolerates_real_tesseract_ocr_noise():
    """
    This exact text is what Tesseract 5.3.4 actually produced (verified
    during development, not hand-crafted) from a synthetic test image
    reading "EPF Registration No: GJ/AND/0012345" / "ESIC Code:
    31-00-987654-000-1001": the leading "E" of "EPF" was dropped and a
    handful of characters were misread. The original strict-prefix regex
    silently returned empty strings against this; the fuzzy-line-match
    fallback must recover both codes.
    """
    ocr_noisy_text = "PF Registration No. GJ/ANDI0012345\n\nESIC Cade: 31-00-887654-000-1001"
    result = ShramsetuDocParser.parse_epf_esic(ocr_noisy_text)
    assert result["epf_registration"] == "GJ/ANDI0012345"
    assert result["esi_registration"] == "31-00-887654-000-1001"


def test_parse_epf_esic_still_works_on_clean_pdf_text():
    clean_text = "EPF Registration No: GJ/AND/0012345\nESIC Code: 31-00-987654-000-1001"
    result = ShramsetuDocParser.parse_epf_esic(clean_text)
    assert result["epf_registration"] == "GJ/AND/0012345"
    assert result["esi_registration"] == "31-00-987654-000-1001"


def test_parse_epf_esic_no_cross_contamination_between_epf_and_esic():
    """
    Regression test for a real bug found by re-running the OCR pipeline
    repeatedly (a fresh synthetic image + fresh Tesseract OCR each time):
    with "ESI Registration No" in the ESIC keyword list, its shared
    "Registration No" phrase with the EPF keyword scored HIGHER (89.5)
    against the WRONG (EPF) line than the correct ESIC-specific keyword
    scored (88.9) against the RIGHT line when Tesseract mangled "EPF" ->
    "EF" -- silently returning the EPF number as BOTH fields. Both fields
    were non-empty, so a bool()-only check passed; only comparing exact
    values (and asserting the two results differ) catches this class of
    bug. The eventual fix was a two-stage extractor
    (_identity_prefix_line_extract tried before fuzzy matching) rather
    than further keyword tweaks -- see
    test_parse_epf_esic_abbreviated_registration_no_no_collision below for
    why keyword patching alone proved insufficient.
    """
    noisy_variant = "EF Registration No. Gu/ANDI0012345\n\nESIC Cade: 31-00-987654.000-1001"
    result = ShramsetuDocParser.parse_epf_esic(noisy_variant)
    assert result["epf_registration"] == "Gu/ANDI0012345"
    assert result["esi_registration"] == "31-00-987654.000-1001"
    assert result["epf_registration"] != result["esi_registration"]


def test_parse_epf_esic_abbreviated_registration_no_no_collision():
    """
    Discovered by deliberately stress-testing the FIX for the previous bug
    with synthetic edge cases (not just re-running the same scenario):
    with keyword-only fuzzy matching, "PF Registration" scored HIGHER
    (86.7) against an unrelated "ESIC Registration No..." line than
    against its OWN correctly-but-differently-abbreviated line "PF Reg
    No..." (53.3) -- because "Registration" is a large shared substring
    while "Reg No" is only a shorter partial match of it. This proved
    keyword-list patching alone was whack-a-mole; the real fix is the
    two-stage identity-prefix-first extractor
    (_identity_prefix_line_extract), which matches on the line's short,
    specific leading identity token ("PF"/"EPF"/"EPFO" vs "ESI"/"ESIC")
    before ever falling back to fuzzy phrase matching, sidestepping the
    generic-shared-word collision entirely.
    """
    text = "PF Reg No GJANDI0055443\nESIC Registration No 3100998877000112"
    result = ShramsetuDocParser.parse_epf_esic(text)
    assert result["epf_registration"] == "GJANDI0055443"
    assert result["esi_registration"] == "3100998877000112"
    assert result["epf_registration"] != result["esi_registration"]


def test_manpower_matrix_row_and_grand_totals():
    model = ShramsetuFormModel(
        manpower_direct_male=10, manpower_direct_female=2, manpower_direct_trans=0,
        manpower_contractor_male=20, manpower_contractor_female=5, manpower_contractor_trans=1,
        manpower_fixed_term_male=3, manpower_fixed_term_female=0, manpower_fixed_term_trans=0,
        manpower_interstate_migrant_male=8, manpower_interstate_migrant_female=1, manpower_interstate_migrant_trans=0,
        manpower_motor_transport_male=0, manpower_motor_transport_female=0, manpower_motor_transport_trans=0,
    )
    assert model.manpower_direct_total == 12
    assert model.manpower_contractor_total == 26
    assert model.manpower_total_male == 41
    assert model.manpower_total_female == 8
    assert model.manpower_total_trans == 1
    assert model.computed_manpower_total == 50


def test_manpower_render_context_matches_properties():
    model = ShramsetuFormModel(manpower_direct_male=5, manpower_direct_female=3)
    ctx = model.manpower_render_context()
    assert ctx["manpower_direct_total"] == 8
    assert ctx["manpower_total"] == 8


def test_apprentice_manpower_excluded_from_grand_total():
    """
    Confirmed from the real portal's own JS: the grand-total summation
    (sum1..sum5) spans only Direct/Contract/FixTerm/Migrant/Others -- it
    never includes Apprentice counts. This must NOT change
    computed_manpower_total.
    """
    model = ShramsetuFormModel(
        manpower_direct_male=10,
        manpower_apprentice_male=50, manpower_apprentice_female=20, manpower_apprentice_trans=5,
    )
    assert model.computed_manpower_total == 10
    assert model.manpower_apprentice_total == 75


def test_reference_routes_nature_of_work():
    resp = client.get("/api/reference/nature-of-work-options")
    assert resp.status_code == 200
    data = resp.json()
    assert len(data["options"]) == 88
    ids = {o["id"] for o in data["options"]}
    assert 1 in ids and 99 in ids  # "Allied services" and "Other" catch-all


def test_reference_routes_gujarat_districts():
    resp = client.get("/api/reference/gujarat-districts")
    assert resp.status_code == 200
    data = resp.json()
    assert len(data["options"]) == 34
    labels = {o["label"] for o in data["options"]}
    assert "Anand" in labels


def test_document_checklist_contractor():
    resp = client.get("/api/ocr/document-checklist/CONTRACTOR")
    assert resp.status_code == 200
    data = resp.json()
    assert len(data["documents"]) == 11
    doc_types = {d["doc_type"] for d in data["documents"]}
    assert "PE_FORM3" in doc_types
    assert "EXECUTED_BG" in doc_types


def test_document_checklist_principal_employer():
    resp = client.get("/api/ocr/document-checklist/PRINCIPAL_EMPLOYER")
    assert resp.status_code == 200
    data = resp.json()
    assert len(data["documents"]) == 10
    doc_types = {d["doc_type"] for d in data["documents"]}
    assert "CONTRACTOR_LIST" in doc_types
    assert "FACTORY_DETAILS" in doc_types


def test_document_checklist_unknown_role():
    resp = client.get("/api/ocr/document-checklist/UNKNOWN_ROLE")
    assert resp.status_code == 404


def test_route_by_doc_type_pe_form3():
    sample = "EIN: EIN2021AND009988\nRegistration No: REG/AND/2021/778\nEstablishment Name: Gujarat Auto Components Ltd\nAddress: GIDC Phase II, Anand\n388121"
    result = ShramsetuDocParser.route_by_doc_type("PE_FORM3", sample)
    assert result["pe_ein_selected"] == "EIN2021AND009988"
    assert result["pe_pincode"] == "388121"


def test_route_by_doc_type_epf_esic():
    sample = "EPF Registration No: GJ/AND/0012345\nESIC Code: 31-00-987654-000-1001"
    result = ShramsetuDocParser.route_by_doc_type("EPF_ESIC", sample)
    assert result["epf_registration"] == "GJ/AND/0012345"
    assert result["esi_registration"] == "31-00-987654-000-1001"


def test_form_model_validates_pan():
    with pytest.raises(Exception):
        ShramsetuFormModel(pan_number="INVALID")


def test_form_model_accepts_valid_pan():
    model = ShramsetuFormModel(pan_number="abcde1234f", establishment_name="Test Co")
    assert model.pan_number == "ABCDE1234F"


def test_create_establishment_endpoint():
    payload = {
        "name": "Test Contractor Pvt Ltd",
        "pan": "ABCDE1234F",
        "gstin": "24ABCDE1234F1Z5",
        "district": "Anand",
    }
    resp = client.post("/api/forms/establishments", json=payload)
    assert resp.status_code == 200
    data = resp.json()
    assert data["pan"] == "ABCDE1234F"
    assert data["id"] > 0


def test_create_application_requires_valid_establishment():
    resp = client.post("/api/forms/applications", json={"establishment_id": 999999})
    assert resp.status_code == 404


def teardown_module(module):
    db_path = "./test_shramsetu.db"
    if os.path.exists(db_path):
        os.remove(db_path)
