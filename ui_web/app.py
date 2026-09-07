"""
Shramsetu Automation Engine - Local Web UI (Streamlit)
Talks to the FastAPI backend for OCR extraction, establishment/application
creation, and Word document generation.
"""
import os
import requests
import streamlit as st

API_BASE = os.getenv("SHRAMSETU_API_URL", "http://localhost:8000")

st.set_page_config(page_title="Shramsetu Automation Engine", page_icon="🏛️", layout="wide")

st.title("🏛️ Shramsetu Automation Engine — Local Dashboard")

tab_establish, tab_ocr, tab_application, tab_docx = st.tabs(
    ["1️⃣ Establishment", "2️⃣ Document OCR", "3️⃣ FORM-25 Application", "4️⃣ Generate Word Doc"]
)

with tab_establish:
    st.subheader("Create / Register Establishment")
    with st.form("establishment_form"):
        name = st.text_input("Establishment / Firm Name")
        pan = st.text_input("PAN Number").upper()
        gstin = st.text_input("GSTIN (optional)").upper()
        district = st.text_input("District", value="Anand")
        address = st.text_area("Head Office Address")
        submitted = st.form_submit_button("Create Establishment")
        if submitted:
            payload = {"name": name, "pan": pan, "gstin": gstin or None,
                       "district": district, "head_address": address}
            try:
                resp = requests.post(f"{API_BASE}/api/forms/establishments", json=payload, timeout=15)
                if resp.status_code == 200:
                    st.success(f"Establishment created: ID {resp.json()['id']}")
                    st.json(resp.json())
                else:
                    st.error(f"Error {resp.status_code}: {resp.text}")
            except requests.RequestException as e:
                st.error(f"Cannot reach backend at {API_BASE}: {e}")

with tab_ocr:
    st.subheader("Upload Document for OCR Auto-Extraction")
    doc_type = st.selectbox("Document Type", ["PAN", "GSTIN", "WORK_ORDER", "BANK"])
    establishment_id = st.number_input("Establishment ID (optional)", min_value=0, step=1, value=0)
    uploaded_file = st.file_uploader("Upload PDF", type=["pdf"])
    if uploaded_file and st.button("Extract Fields"):
        files = {"file": (uploaded_file.name, uploaded_file.getvalue(), "application/pdf")}
        data = {"doc_type": doc_type}
        if establishment_id:
            data["establishment_id"] = str(establishment_id)
        try:
            resp = requests.post(f"{API_BASE}/api/ocr/extract", files=files, data=data, timeout=30)
            if resp.status_code == 200:
                st.success("Extraction complete")
                st.json(resp.json())
            else:
                st.error(f"Error {resp.status_code}: {resp.text}")
        except requests.RequestException as e:
            st.error(f"Cannot reach backend at {API_BASE}: {e}")

with tab_application:
    st.subheader("Create FORM-25 License Application")
    with st.form("application_form"):
        est_id = st.number_input("Establishment ID", min_value=1, step=1)
        pe_name = st.text_input("Principal Employer Name")
        pe_ein = st.text_input("Principal Employer EIN")
        nature = st.text_input("Nature of Work")
        c1, c2 = st.columns(2)
        with c1:
            start_date = st.text_input("Contract Start Date (DD/MM/YYYY)")
        with c2:
            end_date = st.text_input("Contract End Date (DD/MM/YYYY)")
        m1, m2, m3 = st.columns(3)
        with m1:
            male = st.number_input("Male Labour", min_value=0, step=1)
        with m2:
            female = st.number_input("Female Labour", min_value=0, step=1)
        with m3:
            trans = st.number_input("Trans Labour", min_value=0, step=1)
        submitted = st.form_submit_button("Create Application")
        if submitted:
            payload = {
                "establishment_id": int(est_id), "pe_name": pe_name, "pe_ein": pe_ein,
                "nature_of_work": nature, "contract_start_date": start_date,
                "contract_end_date": end_date, "male_labour": int(male),
                "female_labour": int(female), "trans_labour": int(trans),
            }
            try:
                resp = requests.post(f"{API_BASE}/api/forms/applications", json=payload, timeout=15)
                if resp.status_code == 200:
                    data = resp.json()
                    st.success(f"Application created: {data['application_number']}")
                    st.json(data)
                else:
                    st.error(f"Error {resp.status_code}: {resp.text}")
            except requests.RequestException as e:
                st.error(f"Cannot reach backend at {API_BASE}: {e}")

with tab_docx:
    st.subheader("Generate Word Document")
    form_type = st.selectbox("Form Type", ["CONTRACTOR", "PRINCIPAL_EMPLOYER"])
    est_name = st.text_input("Establishment Name", key="docx_name")
    pan_val = st.text_input("PAN", key="docx_pan").upper()
    gstin_val = st.text_input("GSTIN", key="docx_gst").upper()
    if st.button("Generate & Download"):
        payload = {"establishment_name": est_name, "pan_number": pan_val, "gstin": gstin_val}
        try:
            resp = requests.post(f"{API_BASE}/api/forms/generate-docx/{form_type}", json=payload, timeout=30)
            if resp.status_code == 200:
                st.download_button(
                    "Download Generated Document",
                    data=resp.content,
                    file_name=f"{form_type}_generated.docx",
                    mime="application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                )
            else:
                st.error(f"Error {resp.status_code}: {resp.text}")
        except requests.RequestException as e:
            st.error(f"Cannot reach backend at {API_BASE}: {e}")

st.sidebar.info(f"Backend API: {API_BASE}\n\nOverride with env var `SHRAMSETU_API_URL`.")
