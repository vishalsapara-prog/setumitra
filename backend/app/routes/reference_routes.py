"""Portal Reference Data API — exposes the real Nature of Work checklist
and Gujarat district checklist extracted from the live Shramsetu portal."""
from fastapi import APIRouter

from ..reference_data import NATURE_OF_WORK_OPTIONS, GUJARAT_DISTRICT_OPTIONS

router = APIRouter(prefix="/api/reference", tags=["Reference Data"])


@router.get("/nature-of-work-options")
def get_nature_of_work_options():
    """
    The real portal's License FORM-25 page presents Nature of Work as an
    88-item checkbox checklist (natureOfWorkCheckbox_1..99), not free text.
    Each `id` here matches the portal's own checkbox value.
    """
    return {"options": NATURE_OF_WORK_OPTIONS}


@router.get("/gujarat-districts")
def get_gujarat_districts():
    """
    The real portal's License FORM-25 page has a separate 33-district
    checkbox checklist ("districts this license covers"), distinct from
    the single-select District dropdown used elsewhere in Establishment
    Master. Each `id` here matches districtCheckbox_<id> on the portal.
    """
    return {"options": GUJARAT_DISTRICT_OPTIONS}
