# On-Site Only CMI processing route — implementation contract

Status: specification / QA gate only. Application implementation NOT complete. Production deployment prohibited until acceptance criteria pass.

## Authoritative model

The master Register is the full population of CMI register rows, sourced through the application's SOURCE.records / state.records pathway. The Delivery Plan is a subset, not the Register master, because some CMIs were submitted or agreed before team mobilisation. Do not derive master Register rows from cmi_delivery_activities or the empty public.cmis table.

Maintain immutable register row IDs to disambiguate duplicate displayed CMI numbers. Do not deduplicate values when accounting rules call for row-wise amounts.

## New register attribute

- processingRoute: 'Off-Site + On-Site' (default) or 'On-Site Only'.
- Editable for CMIs assigned to the CMI Team, not for historical pre-team agreed/submitted records.
- Persist using the same authoritative mechanism as the Register; avoid storing only in public.cmis because it currently has no rows.
- Changing route MUST NOT change Submission Classification, agreed amounts, submitted amounts, register row count, or Delivery Plan membership.
- Route changes must be reversible and must preserve recorded dates, progress and resource history.
- Before switching to On-Site Only, prompt or preserve archival linkage when Measurement & Valuation has entered progress/dates.

## Delivery Plan

- Standard route: retain all five existing activities and weights: Measurement Works & Valuation 80%; Review of Valuation and Compilation of all Documents 5%; Technical and Commercial Clearance 5%; Final Review of the Submission 5%; Submission to DGJ 5%.
- On-Site Only: Measurement Works & Valuation is non-applicable and omitted from the UI, activity counts, and pending KPI denominators, not deleted from historical storage.
- On-Site Only remaining activities: Review / Compilation of Documents, Technical and Commercial Clearance, Final Review of the Submission, Submission to DGJ. Proposed weighting 25% each, subject to final confirmation before go-live.
- All progress aggregates renormalize to applicable activity weights. Preserve existing submission automation when DGJ submission completes.

## CMI Readiness

- Filter to processingRoute = 'Off-Site + On-Site', across rows, cards, denominators and graphs.
- Preserve excluded readiness records for reversible reclassification.

## Resources

- On-Site Only CMIs are excluded from Off-Site resource capacity and allocation, without being excluded from CMI Team portfolio count or other on-site resource measures.
- Review existing off-site assignments before reclassification; do not silently wipe them.

## Dashboards

- Internal: add Off-Site + On-Site / On-Site Only breakdown, reconciling exactly to team-scope CMI count. Submission Classification remains independent of route.
- Executive Part 4: commencement based on first applicable activity, measurement KPI only standard route, Tech/Commercial and DGJ submission both routes, separately displayed team workload.
- No changes to the other executive or internal reporting financial totals, agreed-before-team and submitted-before-team status criteria, visual palette or charts outside Part 4 and the agreed route breakdown.

## Verified Supabase snapshot (2026-10-20)

- public.cmis: 0 rows (a processing_route column was previously added but it is not authoritative).
- public.cmi_delivery_activities: 2,315 activity rows; 463 record IDs; 453 distinct displayed CMI numbers.
- public.cmi_document_readiness: 198 rows.
- public.rfi_information_holds: 18 rows.
- Production's master Register source has NOT been fully fetched or reconciled.

## Acceptance tests (must all pass prior to deployment)

1. Existing CMIs default to standard route without changing visual totals.
2. An On-Site Only record keeps its master Register entry and Delivery Plan membership while dropping Measurement from applicable Delivery Plan UI.
3. On-Site Only record is absent from all Readiness KPIs and from Off-Site capacity calculations.
4. On-Site Only record progresses to 100% using only applicable activities.
5. Route toggled standard -> on-site -> standard retains original Measurement record and dates.
6. A pre-mobilisation agreed/submitted Register record remains outside Delivery Plan.
7. Duplicate displayed CMI numbers preserve independent rows and correct count/value rules.
8. All existing agreed, submitted, and team totals reconcile to a captured pre-change production snapshot.
9. Executive Part 4 and Internal route breakdown reconcile to team-scope count, with no double counting.
10. Reconciliation, UI tests, database backup/restore test, and rollback procedure documented before merge/deployment.
