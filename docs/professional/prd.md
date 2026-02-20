# Product Requirements Document — Professional Area (Balansi)

## 1. Summary

The **Professional Area** enables healthcare professionals to manage patient profiles and review patient records in Balansi with clear ownership and access-control rules.

In v1, the module introduces:
- read-only access to patient records for authorized professionals,
- split profile ownership:
  - patient-managed personal fields,
  - owner professional-managed clinical goal fields,
- support for sharing patient access with additional professionals,
- professional-initiated patient onboarding via invite link,
- a professional patient list with ownership visibility (owner vs shared),
- and mandatory profile completion by the patient on first login before accessing the system.

---

## 2. Goals & Non-Goals

### 2.1 Goals

- Allow an authorized professional to view all records of their patient in read-only mode.
- Allow a patient to grant access to an additional professional without removing access from the existing one.
- Allow professionals to invite patients through a signup link for initial account creation (name, email, password).
- Provide a patient list for professionals with clear ownership status (owner vs shared access).
- Allow the owner professional to create and maintain only professional-managed profile fields.
- Allow the patient to edit only patient-managed personal fields.
- Enforce a first-login completion gate until required patient-managed fields are filled.
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
  - owner professional edits professional-managed clinical goal fields.
- Patient profile read-only access for additional professionals.
- Professional-generated invite link for patient initial signup.
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

- **FR-PM-01**: The owner professional can create and edit only professional-managed clinical goal fields:
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
- **FR-PM-06**: The owner professional cannot edit patient-managed personal fields.
- **FR-PM-07**: Profile updates must be visible immediately to all users with profile read access.

### 5.4 Ownership Rules

- **FR-OW-01**: Each patient has exactly one owner professional.
- **FR-OW-02**: Edit permission for professional-managed clinical goal fields is granted only to the owner professional.
- **FR-OW-03**: Edit permission for patient-managed personal fields is granted only to the patient.
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

### 5.6 Patient Onboarding via Professional Invite Link

- **FR-ON-01**: A professional must be able to generate or share an invite link for patient onboarding.
- **FR-ON-02**: The invite flow must collect at least name, email, and password.
- **FR-ON-03**: When signup is completed through this link, the inviting professional becomes the owner professional for that patient.

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
2. System shows editable form only for professional-managed clinical goal fields.
3. Professional updates one or more profile fields.
4. Professional saves changes.
5. System validates, persists, and confirms update.
6. Updated profile becomes visible in read-only views for patient and additional professionals.

### 6.2 Flow: Patient Grants Access to a New Professional

1. Patient opens sharing settings.
2. Patient selects or invites a new professional.
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

### 6.5 Flow: Patient Initial Signup via Professional Link

1. Professional shares invite link with a patient.
2. Patient opens link and fills name, email, and password.
3. System creates patient account and links ownership to inviting professional.
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
5. System validates and saves.
6. Patient can access the rest of the system only after successful completion.

---

## 7. Permissions Matrix

| Actor | Patient Records | Patient Profile (Read) | Edit Personal Fields (`gender`, `birth_date`, `weight_kg`, `height_cm`, `phone_e164`) | Edit Clinical Goal Fields (`daily_calorie_goal`, `bmr`, `steps_goal`, `hydration_goal`) | Share Access |
|---|---|---|---|---|---|
| Owner Professional | Yes (Read-only) | Yes | No | Yes | No |
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
- The owner professional cannot edit patient personal fields (`gender`, `birth_date`, `weight_kg`, `height_cm`, `phone_e164`).
- A professional can see a patient list with each patient marked as `owner` or `shared access`.
- A patient created through a professional invite link is linked to that professional as owner.
- On first login, patient access to the rest of the system is blocked until required personal fields are completed and valid.

---

## 10. Decisions for v1 and Future Versions

1. Initial owner assignment in v1: patient onboarding starts from a professional invite link, and the inviting professional is set as owner.
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

**Document Version**: 1.0  
**Last Updated**: 2026-02-20  
**Status**: Reviewed
