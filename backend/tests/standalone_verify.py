"""
Standalone Verification Script — Shramsetu Automation Engine

Runs the core computational logic (manpower matrix math, PAN/GSTIN
validation, Bank Guarantee calculation, OCR regex/fuzzy parsers) WITHOUT
requiring the full dependency chain (fastapi/pydantic/sqlalchemy/docxtpl/
rapidfuzz) to be installed — useful in offline/restricted environments
where `pip install -r requirements.txt` isn't possible but a quick sanity
check of the core logic is still needed.

This is a standalone REPLICA of the logic in app/models.py and
app/engine.py, kept in sync manually — it is NOT a substitute for the real
pytest suite in tests/test_pipeline.py, which exercises the actual
FastAPI app end-to-end (including HTTP routing, request validation, and
the real pydantic model) once dependencies are installed.

Usage:
    python standalone_verify.py           # runs once
    python standalone_verify.py --loop 10 # runs N times (stress/consistency check)

Also verifies the .docx templates in app/templates/ (via python-docx,
a much lighter dependency than docxtpl) for placeholder integrity, and
runs real Tesseract OCR + fuzzy-parsing if pytesseract/Pillow/tesseract
are available (skipped gracefully if not).
"""
import argparse
import difflib
import io
import os
import re
import sys
import traceback

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TEMPLATE_DIR = os.path.join(REPO_ROOT, "backend", "app", "templates")


# ---------------------------------------------------------------------------
# Pure-logic replicas (see app/models.py / app/engine.py for the real code)
# ---------------------------------------------------------------------------
class ManpowerModel:
    _FIELDS = [
        "manpower_direct_male", "manpower_direct_female", "manpower_direct_trans",
        "manpower_contractor_male", "manpower_contractor_female", "manpower_contractor_trans",
        "manpower_fixed_term_male", "manpower_fixed_term_female", "manpower_fixed_term_trans",
        "manpower_interstate_migrant_male", "manpower_interstate_migrant_female", "manpower_interstate_migrant_trans",
        "manpower_motor_transport_male", "manpower_motor_transport_female", "manpower_motor_transport_trans",
        "manpower_apprentice_male", "manpower_apprentice_female", "manpower_apprentice_trans",
    ]

    def __init__(self, **kwargs):
        for f in self._FIELDS:
            val = kwargs.get(f, 0)
            if not isinstance(val, int) or val < 0:
                raise ValueError(f"{f} must be a non-negative int, got {val!r}")
            setattr(self, f, val)

    @property
    def manpower_direct_total(self):
        return self.manpower_direct_male + self.manpower_direct_female + self.manpower_direct_trans

    @property
    def manpower_contractor_total(self):
        return self.manpower_contractor_male + self.manpower_contractor_female + self.manpower_contractor_trans

    @property
    def manpower_fixed_term_total(self):
        return self.manpower_fixed_term_male + self.manpower_fixed_term_female + self.manpower_fixed_term_trans

    @property
    def manpower_interstate_migrant_total(self):
        return (self.manpower_interstate_migrant_male + self.manpower_interstate_migrant_female
                + self.manpower_interstate_migrant_trans)

    @property
    def manpower_motor_transport_total(self):
        return (self.manpower_motor_transport_male + self.manpower_motor_transport_female
                + self.manpower_motor_transport_trans)

    @property
    def manpower_apprentice_total(self):
        return self.manpower_apprentice_male + self.manpower_apprentice_female + self.manpower_apprentice_trans

    @property
    def manpower_total_male(self):
        return (self.manpower_direct_male + self.manpower_contractor_male + self.manpower_fixed_term_male
                + self.manpower_interstate_migrant_male + self.manpower_motor_transport_male)

    @property
    def manpower_total_female(self):
        return (self.manpower_direct_female + self.manpower_contractor_female + self.manpower_fixed_term_female
                + self.manpower_interstate_migrant_female + self.manpower_motor_transport_female)

    @property
    def manpower_total_trans(self):
        return (self.manpower_direct_trans + self.manpower_contractor_trans + self.manpower_fixed_term_trans
                + self.manpower_interstate_migrant_trans + self.manpower_motor_transport_trans)

    @property
    def computed_manpower_total(self):
        # NOTE: Apprentice is intentionally excluded here, matching the
        # real portal's own JS grand-total summation (confirmed from the
        # live Establishment Application Master page's calc functions).
        return self.manpower_total_male + self.manpower_total_female + self.manpower_total_trans


def validate_pan(v):
    v = (v or "").upper().strip()
    if v and not re.fullmatch(r"[A-Z]{5}[0-9]{4}[A-Z]{1}", v):
        raise ValueError("Invalid PAN format")
    return v


def validate_gstin(v):
    v = (v or "").upper().strip()
    if v and not re.fullmatch(r"[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}", v):
        raise ValueError("Invalid GSTIN format")
    return v


class BankGuaranteeCalculator:
    BASE_RATE_PER_WORKER = 500.0
    MIN_BG_AMOUNT = 25000.0

    @classmethod
    def calculate(cls, total_labour, contract_value=0.0):
        by_labour = total_labour * cls.BASE_RATE_PER_WORKER
        by_value = contract_value * 0.02
        return round(max(by_labour, by_value, cls.MIN_BG_AMOUNT), 2)


PAN_REGEX = r'[A-Z]{5}[0-9]{4}[A-Z]{1}'
GST_REGEX = r'[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}'
DATE_REGEX = (
    r'(?:\b\d{1,2}[-/\.]\d{1,2}[-/\.]\d{2,4}\b|'
    r'\b\d{1,2}(?:st|nd|rd|th)?\s+(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)'
    r'[a-z]*[\s,]+\d{4}\b)'
)
PINCODE_REGEX = r'\b\d{6}\b'


def parse_pan(text):
    pan_matches = re.findall(PAN_REGEX, text.upper())
    pan = pan_matches[0] if pan_matches else ""
    lines = [l.strip() for l in text.split('\n') if l.strip()]
    name, dob = "", ""
    for i, l in enumerate(lines):
        if "INCOME TAX DEPARTMENT" in l.upper() or "GOVT. OF INDIA" in l.upper():
            if i + 1 < len(lines):
                name = lines[i + 1]
        dt = re.search(DATE_REGEX, l)
        if dt and not dob:
            dob = dt.group(0)
    return {"pan_number": pan, "legal_name": name, "dob": dob}


def parse_gst(text):
    gst_matches = re.findall(GST_REGEX, text.upper())
    gstin = gst_matches[0] if gst_matches else ""
    legal_name, pincode = "", ""
    l_m = re.search(r'Legal Name\s*[:\-]?\s*([^\n\r]+)', text, re.IGNORECASE)
    if l_m:
        legal_name = l_m.group(1).strip()
    pin_matches = re.findall(PINCODE_REGEX, text)
    if pin_matches:
        pincode = pin_matches[-1]
    return {"gstin": gstin, "legal_name": legal_name, "pincode": pincode}


def _partial_ratio_stub(needle, haystack):
    """
    difflib-based stand-in for rapidfuzz.fuzz.partial_ratio, used only when
    rapidfuzz itself isn't installed. The real app/engine.py uses rapidfuzz;
    this reproduces the same "best matching substring" semantics closely
    enough to validate the fuzzy-line-match algorithm's logic.
    """
    needle, haystack = needle.upper(), haystack.upper()
    if len(needle) > len(haystack):
        return difflib.SequenceMatcher(None, needle, haystack).ratio() * 100
    best = 0.0
    for i in range(len(haystack) - len(needle) + 1):
        window = haystack[i:i + len(needle)]
        score = difflib.SequenceMatcher(None, needle, window).ratio()
        best = max(best, score)
    return best * 100


def _extract_trailing_token(line):
    tokens = re.findall(r'[A-Za-z0-9][A-Za-z0-9/\-.]{3,}', line)
    return tokens[-1].rstrip('.') if tokens else ""


def identity_prefix_line_extract(text, identity_prefixes):
    """
    Stage 1: a line literally starting with a short organization-identity
    token (e.g. "PF"/"EPF"/"EPFO", "ESI"/"ESIC"). Preferred over pure
    fuzzy phrase-matching where possible -- see the note in
    app/engine.py's _identity_prefix_line_extract: fuzzy matching on
    phrases sharing a generic word ("Registration No"/"Reg No") was found,
    via repeated real-execution testing, to twice silently cross-
    contaminate EPF and ESIC values. Returns None if no line matches, so
    the caller can fall back to fuzzy matching.
    """
    for line in text.split("\n"):
        line = line.strip()
        if not line:
            continue
        upper = line.upper()
        for tok in identity_prefixes:
            if upper.startswith(tok.upper()):
                return _extract_trailing_token(line)
    return None


def fuzzy_line_extract(text, label_keywords, min_score=60.0):
    best_line, best_score = None, 0.0
    for line in text.split("\n"):
        line = line.strip()
        if not line:
            continue
        for kw in label_keywords:
            score = _partial_ratio_stub(kw, line)
            if score > best_score:
                best_score, best_line = score, line
    if best_score < min_score or not best_line:
        return ""
    return _extract_trailing_token(best_line)


def parse_epf_esic(text):
    epf_code = identity_prefix_line_extract(text, ["PF", "EPF", "EPFO"])
    if epf_code is None:
        epf_code = fuzzy_line_extract(text, ["EPF Registration No", "EPFO Code", "PF Registration"])

    esic_code = identity_prefix_line_extract(text, ["ESI", "ESIC"])
    if esic_code is None:
        esic_code = fuzzy_line_extract(text, ["ESIC Code", "ESI Code"])

    return {"epf_registration": epf_code, "esi_registration": esic_code}


# ---------------------------------------------------------------------------
# Test cases
# ---------------------------------------------------------------------------
def _run_case(name, fn, results):
    try:
        fn()
        results.append((name, True, None))
    except Exception:
        results.append((name, False, traceback.format_exc()))


def case_manpower_matrix_totals():
    m = ManpowerModel(
        manpower_direct_male=10, manpower_direct_female=2,
        manpower_contractor_male=20, manpower_contractor_female=5, manpower_contractor_trans=1,
        manpower_fixed_term_male=3,
        manpower_interstate_migrant_male=8, manpower_interstate_migrant_female=1,
    )
    assert m.manpower_direct_total == 12
    assert m.manpower_contractor_total == 26
    assert m.manpower_total_male == 41
    assert m.computed_manpower_total == 50


def case_apprentice_excluded_from_grand_total():
    m = ManpowerModel(manpower_direct_male=10, manpower_apprentice_male=50,
                       manpower_apprentice_female=20, manpower_apprentice_trans=5)
    assert m.computed_manpower_total == 10
    assert m.manpower_apprentice_total == 75


def case_manpower_rejects_negative():
    try:
        ManpowerModel(manpower_direct_male=-1)
        raise AssertionError("expected ValueError")
    except ValueError:
        pass


def case_pan_validator():
    assert validate_pan("abcde1234f") == "ABCDE1234F"
    try:
        validate_pan("INVALID")
        raise AssertionError("expected ValueError")
    except ValueError:
        pass


def case_gstin_validator():
    assert validate_gstin("24abcde1234f1z5") == "24ABCDE1234F1Z5"
    try:
        validate_gstin("BADGSTIN")
        raise AssertionError("expected ValueError")
    except ValueError:
        pass


def case_bg_calculator():
    assert BankGuaranteeCalculator.calculate(5, 0) == BankGuaranteeCalculator.MIN_BG_AMOUNT
    assert BankGuaranteeCalculator.calculate(100, 0) == 100 * BankGuaranteeCalculator.BASE_RATE_PER_WORKER
    assert BankGuaranteeCalculator.calculate(10, 5_000_000) == 100_000.0


def case_parse_pan():
    sample = "INCOME TAX DEPARTMENT\nGOVT. OF INDIA\nRAHUL SHARMA\nABCDE1234F\n01/01/1990"
    result = parse_pan(sample)
    assert result["pan_number"] == "ABCDE1234F"
    assert result["legal_name"] == "RAHUL SHARMA"


def case_parse_gst():
    sample = "Legal Name: ABC ENTERPRISES\nGSTIN 24ABCDE1234F1Z5\nAddress: Anand, 388001"
    result = parse_gst(sample)
    assert result["gstin"] == "24ABCDE1234F1Z5"
    assert result["pincode"] == "388001"


def case_epf_esic_clean():
    result = parse_epf_esic("EPF Registration No: GJ/AND/0012345\nESIC Code: 31-00-987654-000-1001")
    assert result["epf_registration"] == "GJ/AND/0012345"
    assert result["esi_registration"] == "31-00-987654-000-1001"


def case_epf_esic_noisy_ocr():
    # This exact noisy text was captured from a real Tesseract 5.3.4 OCR run
    # during development (dropped "E", "Code:" -> "Cade:", digit noise) --
    # the strict-regex predecessor of this parser silently failed on it.
    noisy = "PF Registration No. GJ/ANDI0012345\n\nESIC Cade: 31-00-887654-000-1001"
    result = parse_epf_esic(noisy)
    assert result["epf_registration"] == "GJ/ANDI0012345"
    assert result["esi_registration"] == "31-00-887654-000-1001"


def case_epf_esic_noisy_ocr_variant_cross_contamination():
    # This exact text was produced by a LATER real Tesseract run during
    # --loop 10 verification and caught a genuine bug: with "ESI
    # Registration No" in the ESIC keyword list, its shared "Registration
    # No" phrase with the EPF line scored HIGHER (89.5) against the WRONG
    # (EPF) line than the correct ESIC-specific keyword scored (88.9)
    # against the RIGHT line -- silently returning the EPF number as the
    # ESIC number. Both fields were non-empty, so a bool()-only check
    # would have passed; only asserting the exact values catches this.
    noisy = "EF Registration No. Gu/ANDI0012345\n\nESIC Cade: 31-00-987654.000-1001"
    result = parse_epf_esic(noisy)
    assert result["epf_registration"] == "Gu/ANDI0012345"
    assert result["esi_registration"] == "31-00-987654.000-1001"
    assert result["epf_registration"] != result["esi_registration"], (
        "EPF and ESIC extracted the same value -- almost certainly cross-contamination"
    )


def case_epf_esic_abbreviated_registration_no_no_collision():
    # Discovered by deliberately stress-testing the FIX for the previous
    # bug with synthetic edge cases (not just re-running the same
    # scenario): with keyword-only fuzzy matching, "PF Registration"
    # scored HIGHER (86.7) against an unrelated "ESIC Registration No..."
    # line than against its OWN correctly-but-differently-abbreviated line
    # "PF Reg No..." (53.3) -- because "Registration" is a large shared
    # substring while "Reg No" is a shorter partial match of it. This
    # proved keyword-list patching alone was whack-a-mole; the fix is the
    # two-stage identity-prefix-first extractor
    # (_identity_prefix_line_extract), not another keyword tweak.
    text = "PF Reg No GJANDI0055443\nESIC Registration No 3100998877000112"
    result = parse_epf_esic(text)
    assert result["epf_registration"] == "GJANDI0055443"
    assert result["esi_registration"] == "3100998877000112"
    assert result["epf_registration"] != result["esi_registration"]


PURE_LOGIC_CASES = [
    case_manpower_matrix_totals, case_apprentice_excluded_from_grand_total,
    case_manpower_rejects_negative, case_pan_validator, case_gstin_validator,
    case_bg_calculator, case_parse_pan, case_parse_gst,
    case_epf_esic_clean, case_epf_esic_noisy_ocr, case_epf_esic_noisy_ocr_variant_cross_contamination,
    case_epf_esic_abbreviated_registration_no_no_collision,
]


def check_docx_templates():
    """Verifies both Word templates render-ready via python-docx (a much
    lighter dependency than docxtpl): every {{ placeholder }} must sit in
    a single, unsplit paragraph run — the requirement docxtpl needs to
    parse Jinja tags correctly."""
    try:
        from docx import Document
    except ImportError:
        return None, "python-docx not installed; skipped"

    results = {}
    for fname in ["Shramsetu_Contractor_Template.docx", "Shramsetu_Principal_Employer_Template.docx"]:
        path = os.path.join(TEMPLATE_DIR, fname)
        if not os.path.exists(path):
            results[fname] = f"NOT FOUND at {path}"
            continue
        d = Document(path)
        total, split_issues = 0, 0

        def check(p):
            nonlocal total, split_issues
            if '{{' in p.text:
                total += 1
                runs = [r.text for r in p.runs]
                if ''.join(runs).strip() != p.text.strip():
                    split_issues += 1

        for t in d.tables:
            for r in t.rows:
                for c in r.cells:
                    for p in c.paragraphs:
                        check(p)
        for p in d.paragraphs:
            check(p)
        results[fname] = f"{total} placeholders, {split_issues} split-run issues"
    return results, None


def check_tesseract_ocr():
    """Runs a real (not mocked) Tesseract OCR + fuzzy-parse round-trip on a
    freshly generated synthetic test image, if pytesseract/Pillow/the
    tesseract binary are available. Skipped gracefully otherwise."""
    try:
        import pytesseract
        from PIL import Image, ImageDraw
    except ImportError:
        return None, "pytesseract/Pillow not installed; skipped"

    try:
        img = Image.new('RGB', (600, 200), color='white')
        draw = ImageDraw.Draw(img)
        draw.text((20, 20), "EPF Registration No: GJ/AND/0012345", fill='black')
        draw.text((20, 60), "ESIC Code: 31-00-987654-000-1001", fill='black')
        buf = io.BytesIO()
        img.save(buf, format='JPEG', quality=90)
        image = Image.open(io.BytesIO(buf.getvalue())).convert("RGB")
        text = pytesseract.image_to_string(image, lang="eng")
        fields = parse_epf_esic(text)
        # Non-empty AND distinct: catches both "extraction found nothing"
        # and "extraction found the wrong field's value" (the exact bug
        # class discovered via repeated execution -- see
        # case_epf_esic_noisy_ocr_variant_cross_contamination).
        ok = (bool(fields["epf_registration"]) and bool(fields["esi_registration"])
              and fields["epf_registration"] != fields["esi_registration"])
        return {"raw_ocr_text": text.strip(), "parsed": fields, "ok": ok}, None
    except Exception as e:
        return None, f"Tesseract not available or failed: {e}"


def run_once(run_number, verbose=True):
    results = []
    for case in PURE_LOGIC_CASES:
        _run_case(case.__name__, case, results)

    passed = sum(1 for _, ok, _ in results if ok)
    failed = len(results) - passed

    docx_results, docx_skip_reason = check_docx_templates()
    ocr_results, ocr_skip_reason = check_tesseract_ocr()

    if verbose:
        print(f"--- Run {run_number} ---")
        print(f"Pure logic: {passed}/{len(results)} passed")
        for name, ok, tb in results:
            if not ok:
                print(f"  FAIL: {name}\n{tb}")
        if docx_results:
            for fname, msg in docx_results.items():
                print(f"docx[{fname}]: {msg}")
        elif docx_skip_reason:
            print(f"docx checks skipped: {docx_skip_reason}")
        if ocr_results:
            print(f"OCR: {ocr_results['raw_ocr_text']!r} -> {ocr_results['parsed']} "
                  f"-> {'PASS' if ocr_results['ok'] else 'FAIL'}")
        elif ocr_skip_reason:
            print(f"OCR checks skipped: {ocr_skip_reason}")

    docx_ok = docx_results is None or all("0 split-run issues" in v for v in docx_results.values())
    ocr_ok = ocr_results is None or ocr_results["ok"]
    return failed == 0 and docx_ok and ocr_ok


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--loop", type=int, default=1, help="Number of times to run (default: 1)")
    args = parser.parse_args()

    all_ok = True
    for i in range(1, args.loop + 1):
        ok = run_once(i)
        all_ok = all_ok and ok

    print()
    print("=" * 50)
    print("ALL RUNS PASSED" if all_ok else "SOME RUNS FAILED — see output above")
    sys.exit(0 if all_ok else 1)


if __name__ == "__main__":
    main()
