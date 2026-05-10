# Product Requirements Document — Professional Area (Balansi)

## 1. Summary

The **Professional Area** enables healthcare professionals to manage patient profiles and review patient records in Balansi with clear ownership and access-control rules.

In v1, the module introduces:
- read-only access to patient records for authorized professionals,
- split profile ownership with temporary owner flexibility:
  - patient-managed personal fields,
  - owner professional-managed clinical goal fields,
  - owner professional can also edit personal fields in this phase,
- support for sharing patient access with additional professionals,
- patient onboarding via signup link (professional context optional in this phase),
- a professional patient list with ownership visibility (owner vs shared),
- profile metadata showing the latest profile update timestamp,
- and mandatory profile completion by the patient on first login before accessing the system.

---

## 2. Goals & Non-Goals

### 2.1 Goals

- Allow an authorized professional to view all records of their patient in read-only mode.
- Allow a patient to grant access to an additional professional without removing access from the existing one.
- Allow professionals to share a signup link for initial patient account creation (name, email, password).
- Provide a patient list for professionals with clear ownership status (owner vs shared access).
- Allow the owner professional to create and maintain professional-managed profile fields and, temporarily in this phase, patient-managed personal fields.
- Allow the patient to edit only patient-managed personal fields.
- Enforce a first-login completion gate until required patient-managed fields are filled.
- Track and display the latest profile update timestamp.
- Ensure non-owner professionals can only view the patient profile.

### 2.2 Non-Goals (for v1)

- Billing or subscription logic for professionals.
- Inter-professional chat or collaboration workflows.
- Audit dashboard UI (full history can be added in a later version).
- Automated migration of ownership between professionals.

---

## 3. Users & Personas

### 3.1 Owner Professional

- Wants: full control over patient profile setup and updates.
- Needs:
  - edit permission for professional-managed clinical goal fields,
  - temporary edit permission for patient-managed personal fields in this phase,
  - read-only access to all patient records.

### 3.2 Additional Professional (Shared Access)

- Wants: visibility into patient history and profile for continuity of care.
- Needs:
  - read-only access to all patient records,
  - read-only access to patient profile.

### 3.3 Patient

- Wants: transparency into their profile and ability to share access with another professional.
- Needs:
  - read access to own full profile,
  - edit permission for patient-managed personal fields,
  - a way to grant access to a new professional while preserving current access.

---

## 4. Scope

### 4.1 In Scope

- Access-control model for owner and additional professionals.
- Professional read-only access to patient records.
- Split profile edit ownership:
  - patient edits patient-managed personal fields,
  - owner professional edits professional-managed clinical goal fields,
  - owner professional can also edit patient-managed personal fields (temporary v1 phase decision).
- Patient profile read-only access for additional professionals.
- Signup link for patient initial signup (without invite lifecycle table), with owner assignment defaulting to the first professional when context is not provided.
- Patient action to grant access to a new professional without revoking prior grants.
- Professional patient list showing relationship type:
  - owner patients
  - shared-access patients
- Mandatory patient-managed personal fields:
  - `gender` (allowed values: `male` or `female`)
  - `birth_date` (formatted date input, no calendar date picker)
  - `weight_kg` (kg, with min/max validation)
  - `height_cm` (cm, with min/max validation)
  - `phone_e164` (single phone field including country code, stored in E.164 format, e.g. `+5511999999999`)
- Owner professional-managed clinical goal fields:
  - `daily_calorie_goal`
  - `bmr`
  - `steps_goal`
  - `hydration_goal`
- First-login profile completion gate for patient-managed personal fields.
- Profile metadata fields:
  - `profile_last_updated_at` (last update to any profile field)
- Phone number parsing/validation/normalization strategy in v1:
  - use `phonelib` gem (libphonenumber-based)
  - normalize and persist phone as single `phone_e164` field
  - UI can start with country default `BR`, but stored value remains a single international field

### 4.2 Out of Scope (v1)

- Access expiration windows and temporary sharing.
- Fine-grained field-level sharing controls.
- AI-generated profile recommendations.
- Owner transfer initiated by patient UI.
- Patient revocation of professional access.
- Invite lifecycle management (token issuance, expiry, reminders).

---

## 5. Functional Requirements

### 5.1 Records Access

- **FR-RA-01**: An authorized professional must be able to view all records of patients they are linked to.
- **FR-RA-02**: Professional access to patient records is read-only in v1.
- **FR-RA-03**: Unauthorized professionals must not access patient records.

### 5.2 Patient Access Sharing

- **FR-AS-01**: The patient must be able to grant access to a new professional.
- **FR-AS-02**: Granting new access must not remove existing professional access.
- **FR-AS-03**: The system must support multiple professionals linked to the same patient.

### 5.3 Patient Profile Management

- **FR-PM-01**: The owner professional can create and edit professional-managed clinical goal fields:
  - `daily_calorie_goal`
  - `bmr`
  - `steps_goal`
  - `hydration_goal`
- **FR-PM-02**: Additional professionals can only view patient profile data.
- **FR-PM-03**: The patient can view all fields in their own profile.
- **FR-PM-04**: The patient can create and edit only patient-managed personal fields:
  - `gender` (must be `male` or `female`)
  - `birth_date` (formatted date input, no calendar)
  - `weight_kg` (kg, minimum and maximum enforced)
  - `height_cm` (cm, minimum and maximum enforced)
  - `phone_e164` (single international number including country code, validated and normalized)
- **FR-PM-05**: The patient cannot edit professional-managed clinical goal fields.
- **FR-PM-06**: In this phase, the owner professional can also edit patient-managed personal fields (`gender`, `birth_date`, `weight_kg`, `height_cm`, `phone_e164`).
- **FR-PM-07**: Profile updates must be visible immediately to all users with profile read access.
- **FR-PM-08**: The system must track the latest profile update timestamp in `profile_last_updated_at`.
- **FR-PM-09**: The profile screen must display `profile_last_updated_at` to users with profile read access.

### 5.4 Ownership Rules

- **FR-OW-01**: Each patient has exactly one owner professional.
- **FR-OW-02**: Edit permission for professional-managed clinical goal fields is granted only to the owner professional.
- **FR-OW-03**: Edit permission for patient-managed personal fields is granted to the patient and, temporarily in this phase, to the owner professional.
- **FR-OW-04**: Read permission for patient profile is granted to:
  - owner professional
  - additional linked professionals
  - the patient

### 5.5 Professional Patient List

- **FR-PL-01**: A professional must be able to view a list of all linked patients.
- **FR-PL-02**: Each patient in the list must be clearly labeled as:
  - owner (professional is the patient owner), or
  - shared access (professional has read-only shared access).
- **FR-PL-03**: The ownership label must be available in both list and detail entry points.

### 5.6 Patient Onboarding via Professional Signup Link

- **FR-ON-01**: A professional must be able to share a signup link for patient onboarding.
- **FR-ON-02**: The signup flow must collect at least name, email, and password.
- **FR-ON-03**: In this phase, when signup is completed, owner assignment defaults to the first professional when no professional context is provided in the link.
- **FR-ON-04**: In v1, no invite token lifecycle is required; onboarding can rely on a direct signup link.

### 5.7 First-Login Mandatory Profile Completion

- **FR-FL-01**: On the patient first login, the system must check whether all required patient-managed personal fields are filled.
- **FR-FL-02**: If any required field is missing, the patient must be redirected to a mandatory completion form.
- **FR-FL-03**: The patient must not access other system areas until all required fields are valid and saved.
- **FR-FL-04**: The mandatory form must use:
  - `gender` as a fixed choice (`male` or `female`)
  - `birth_date` as a formatted date field (no calendar picker)
  - phone input collected as a single number and persisted as `phone_e164` (international format with country code)
  - default country context `BR` for parsing assistance
  - `weight_kg` and `height_cm` with minimum and maximum validation limits

---

## 6. User Flows

### 6.1 Flow: Owner Professional Updates Patient Profile

1. Owner professional opens patient profile.
2. System shows editable form for professional-managed clinical goal fields and, in this phase, patient-managed personal fields.
3. Professional updates one or more profile fields.
4. Professional saves changes.
5. System validates, persists, updates `profile_last_updated_at`, and confirms update.
6. Updated profile becomes visible in read-only views for patient and additional professionals.

### 6.2 Flow: Patient Grants Access to a New Professional

1. Patient opens sharing settings.
2. Patient selects a new professional.
3. Patient confirms access grant.
4. System creates additional professional-to-patient access link.
5. Existing professional links remain active.
6. New professional can view all patient records and profile (read-only).

### 6.3 Flow: Additional Professional Reviews Patient Data

1. Additional professional opens linked patient.
2. System displays patient records and profile in read-only mode.
3. Edit actions are blocked and not available.

### 6.4 Flow: Professional Views Patient List

1. Professional opens patient list.
2. System displays all linked patients.
3. Each patient entry shows relationship type (`owner` or `shared access`).
4. Professional selects a patient and navigates to the patient detail page.

### 6.5 Flow: Patient Initial Signup via Professional Signup Link

1. Professional shares signup link (professional context optional in this phase).
2. Patient opens link and fills name, email, and password.
3. System creates patient account and links ownership to the professional from link context when present; otherwise, links to the first professional.
4. On first login, patient is sent to mandatory profile completion.
5. Professional sees the new patient in the list as `owner`.

### 6.6 Flow: First Login Mandatory Profile Completion

1. Patient signs in for the first time.
2. System checks required personal fields: `gender`, `birth_date`, `weight_kg`, `height_cm`, `phone_e164`.
3. If any field is missing/invalid, patient is redirected to the completion form.
4. Patient fills:
   - gender (`male` or `female`)
   - birth date (formatted date field, no calendar)
   - phone number as a single international field (country context default `BR`, persisted as `phone_e164`)
   - weight (kg) and height (cm), each validated by min/max rules
5. System validates, saves, and updates `profile_last_updated_at`.
6. Patient can access the rest of the system only after successful completion.

---

## 7. Permissions Matrix

| Actor | Patient Records | Patient Profile (Read) | Edit Personal Fields (`gender`, `birth_date`, `weight_kg`, `height_cm`, `phone_e164`) | Edit Clinical Goal Fields (`daily_calorie_goal`, `bmr`, `steps_goal`, `hydration_goal`) | Share Access |
|---|---|---|---|---|---|
| Owner Professional | Yes (Read-only) | Yes | Yes (temporary in this phase) | Yes | No |
| Additional Professional | Yes (Read-only) | Yes | No | No | No |
| Patient | Own records (as defined in Journal/Auth modules) | Yes | Yes | No | Yes |

---

## 8. Non-Functional Requirements

### 8.1 Security

- All access decisions must be enforced server-side.
- Ownership and sharing checks must run on every protected request.
- Access changes and professional patient-access events must be traceable (actor, patient, timestamp, action), initially using Rails logs and CloudWatch reports.

### 8.2 Performance

- Patient profile read endpoints should respond under 500ms at p95 under expected load.
- Access-check logic must not materially degrade existing journal read latency.

### 8.3 Reliability

- Access grants must be transactional to avoid partial linkage states.
- Concurrent profile updates must preserve data consistency.

---

## 9. Acceptance Criteria

- An owner professional can edit professional-managed clinical goal fields successfully.
- A non-owner linked professional cannot edit any patient profile fields.
- A linked professional can view all patient records in read-only mode.
- A patient can grant access to a new professional.
- After granting new access, previously linked professionals still retain access.
- A patient can edit `gender`, `birth_date`, `weight_kg`, `height_cm`, and `phone_e164`.
- A patient cannot edit `daily_calorie_goal`, `bmr`, `steps_goal`, or `hydration_goal`.
- The owner professional can edit patient personal fields (`gender`, `birth_date`, `weight_kg`, `height_cm`, `phone_e164`) in this phase.
- A professional can see a patient list with each patient marked as `owner` or `shared access`.
- A patient created through signup is linked to the professional from link context when provided; otherwise linked to the first professional.
- On first login, patient access to the rest of the system is blocked until required personal fields are completed and valid.
- The profile screen shows `profile_last_updated_at`.

---

## 10. Decisions for v1 and Future Versions

1. Initial owner assignment in this phase: patient onboarding can use signup link context when available; otherwise ownership defaults to the first professional.
2. Patient revocation of professional access: out of scope for v1, planned for a future version.
3. Required patient personal fields in v1: `gender`, `birth_date`, `weight_kg`, `height_cm`, `phone_e164`.
4. Field input rules in v1:
   - `gender`: `male` or `female`
   - `birth_date`: formatted date field (no calendar)
   - `phone_e164`: single field including country code, validated/normalized with `phonelib`
   - input assistance can default to `BR`
   - `weight_kg` and `height_cm`: min/max validation
5. Owner professional delegation/transfer: planned for a future version.

---

## 11. Success Metrics

- Number of owner patients per professional (distribution and average).
- Number of shared-access patients per professional (distribution and average).
- Ratio of owner vs shared patients per professional.
- Number of traceable professional access events to patient data (profile/journal views) per day/week.
- Number of distinct patients accessed per professional per week.
- % of linked patients with at least one professional access event in the last 7 and 30 days.
- Initial observability implementation: extract events from Rails logs and publish CloudWatch reports/dashboards.

---

## 12. References

- Linear Ticket: [BAL-15 — Professional features](https://linear.app/balansi/issue/BAL-15/professional-features)
- PRD: [Professional PRD](./prd.md)
- ERD: [Professional ERD](./erd.md)

---

**Document Version**: 1.1  
**Last Updated**: 2026-02-26  
**Status**: Reviewed
