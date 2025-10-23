# ADR-001: Zero-Copy Architecture Options for AEP and BigQuery Integration

**Status**: Proposed
**Date**: 2025-10-22
**Decision Makers**: Data Architecture Team, Marketing Technology Team
**Technical Owner**: Data Engineering Lead

---

## Context

We need to activate audiences from BigQuery to email marketing platforms (primarily Marketo) via Adobe Experience Platform (AEP) while minimizing data transfer, maintaining data sovereignty, and avoiding vendor lock-in.

### Current State

- **Data Warehouse**: Google BigQuery (source of truth for all customer data)
- **Customer Profiles**: Large volume of profiles with extensive behavioral data
- **Data Processing**: Analytics, ML models, and segmentation logic executed in BigQuery
- **Primary Activation Channel**: Marketo (email campaigns)
- **Future Channels**: Potential expansion to other destinations via AEP

**Example Use Cases**:
- Lead scoring and classification → Email nurture campaigns
- Churn prediction → Retention email campaigns
- Product recommendations → Personalized email offers
- Customer segmentation (RFM, CLV, behavioral) → Multi-segment email campaigns
- VIP customer identification → Exclusive email communications

### Problem Statement

Traditional AEP integration requires copying ALL customer data (100+ fields per profile) into Adobe's Real-Time Customer Profile Store, resulting in:

❌ **Massive Data Transfer**: Large volumes of data replicated from BigQuery to AEP
❌ **Vendor Lock-in**: All segmentation logic and data stored in AEP proprietary format
❌ **Data Sovereignty Issues**: Customer data leaves GCP, stored in Adobe's cloud
❌ **Complex ETL**: Custom pipelines required to sync BigQuery → AEP
❌ **Dual Maintenance**: Schema evolution and data quality rules managed in both systems
❌ **High Operational Costs**: Significant licensing, storage, and data transfer expenses

**Key Question**: How can we leverage AEP's activation capabilities (Marketo integration, destination connectors) WITHOUT copying all data from BigQuery to AEP?

### Key Requirements

1. **Functional Requirements**:
   - Activate audiences from BigQuery to Marketo for email campaigns
   - Support for multiple audience segments (20-50+ different segments)
   - Ability to refresh audiences on schedule (daily/weekly)
   - Daily/weekly campaign cadence acceptable for majority of use cases

2. **Non-Functional Requirements**:
   - **Minimize data transfer** out of BigQuery (target: >95% reduction)
   - **Maintain data sovereignty** in GCP (regulatory and compliance requirements)
   - **Low vendor lock-in** (preserve ability to switch from AEP to alternatives)
   - **Operational simplicity** (minimize custom code and dual-system maintenance)

3. **Security & Compliance**:
   - Data residency in GCP preferred
   - Audit trail for all data access
   - Minimal PII exposure to external systems
   - Compliance with internal security policies

### **CRITICAL CONSTRAINT: BigQuery Exposure Policy**

⚠️ **Security policies may permanently prohibit exposing BigQuery to external systems** (including AEP):

- **Pull-based data access** (AEP querying BigQuery) may violate "no external database access" policies
- **IP allowlisting** or **VPN connections** to external systems may be blocked
- **Risk assessment** for federated queries may not pass security review
- **This constraint may NEVER be lifted** due to regulatory or organizational policy

**Implication**: Architecture options that require BigQuery exposure (Federated Audience Composition) **may be permanently unavailable**. We must have robust fallback options that work within security constraints.

---

## Decision

We have evaluated **FOUR zero-copy architecture options** for integrating BigQuery with AEP. Each option minimizes data transfer while enabling audience activation to Marketo.

### Architecture Options Summary

| Option | Approach | Data Reduction | BigQuery Exposure Required? | Best For |
|--------|----------|----------------|----------------------------|----------|
| **1. Federated Audience Composition (FAC)** | Pull-based: AEP queries BigQuery in-place | **>99%** | ⚠️ **YES** - May be blocked | Batch use cases, minimal vendor lock-in |
| **2. Computed Attributes** | Push-based: Stream derived fields only | **85-95%** | ✅ **NO** - Push-based | Real-time requirements, full AEP features |
| **3. Hybrid Selective** | Combined: FAC (99%) + Streaming (1%) | **95-99%** | ⚠️ **YES** - Partial exposure | Mixed batch + real-time needs |
| **4. External Audiences API** | Push-based: IDs + enrichment fields | **>99%** | ✅ **NO** - Push-based | POC/testing, when FAC is blocked |

---

## Option 1: Federated Audience Composition (FAC)

### Architecture Overview

**Approach**: AEP executes SQL queries directly against BigQuery to identify audience members. Only customer IDs are transferred to AEP for activation.

```
BigQuery (GCP)                     AEP                    Marketo
┌─────────────────┐               ┌───────────┐          ┌──────────┐
│ Customer Data   │               │ Federated │          │          │
│ (Large volume)  │◄──SQL Query───│  Audience │          │  Email   │
│ 100+ fields     │               │  Composer │          │ Campaign │
│                 │               │           │          │          │
│                 │───IDs Only───►│ Store IDs │─────────►│          │
└─────────────────┘               └───────────┘          └──────────┘
     Data stays                    Minimal               Activate
     in BigQuery                   metadata              audiences
```

### How It Works

1. **Setup**: Create federated connection from AEP to BigQuery (one-time)
2. **Segmentation**: Define audiences in AEP UI using SQL queries
3. **Query Execution**: AEP executes queries against BigQuery (scheduled)
4. **Data Transfer**: Only customer IDs returned to AEP (minimal data transfer)
5. **Activation**: AEP activates IDs to Marketo with profile enrichment

### Consequences

#### ✅ Positive

- **TRUE Zero-Copy**: Data never leaves BigQuery
- **Minimal Vendor Lock-in**: All segmentation logic remains in BigQuery SQL
- **Data Sovereignty**: Data stays in GCP
- **Operational Simplicity**: No custom ETL pipelines, no dual-system sync
- **Significant Data Reduction**: >99% reduction in data transfer

#### ❌ Negative

- **⚠️ CRITICAL: Requires BigQuery Exposure**: AEP must be able to query BigQuery
  - Requires IP allowlisting OR VPN connection
  - May violate "no external database access" policies
  - **Security approval may be permanently blocked**
- **Batch-Only**: Minimum refresh hourly (typically daily/weekly)
- **No AEP AI Features**: Cannot use Customer AI, Attribution AI
- **Limited AEP Features**: Cannot combine with AEP behavioral data for segmentation

### When to Choose

**Choose FAC IF**:
- ✅ Daily/weekly email campaigns are sufficient (batch processing acceptable)
- ✅ Vendor lock-in is a major concern
- ✅ Data sovereignty is critical
- ✅ **Security team approves BigQuery external access**

**DO NOT Choose IF**:
- ❌ **Security policy blocks external database access** → Use Option 2 or 4 instead
- ❌ Need real-time activation (<5 min latency)
- ❌ Require AEP AI features (Customer AI, Attribution AI)

---

## Option 2: Computed Attributes (Streaming Minimal Profiles)

### Architecture Overview

**Approach**: Stream ONLY derived scoring attributes (5-10 fields) from BigQuery to AEP Real-Time Profile Store, keeping raw data (100+ fields) in BigQuery.

```
BigQuery (GCP)                     AEP                    Marketo
┌─────────────────┐               ┌───────────┐          ┌──────────┐
│ Raw Data        │               │ Streaming │          │          │
│ (STAYS IN GCP)  │               │ Ingestion │          │  Email   │
│ 100+ fields     │               │    API    │          │ Campaign │
│                 │               │           │          │          │
│ ML Models   ────┼──Push 5-10───►│  Profile  │─────────►│          │
│ Scoring Logic   │   fields      │   Store   │          │          │
└─────────────────┘               └───────────┘          └──────────┘
  Cloud Run/                       Minimal               Activate
  Cloud Function                   profiles              audiences
  (orchestration)                  stored
```

### How It Works

1. **Compute**: BigQuery executes ML models, generates derived attributes
2. **Extract**: Cloud Run service extracts minimal profile data (5-10 fields)
3. **Transform**: Transform to AEP XDM format
4. **Stream**: Push to AEP Streaming Ingestion API
5. **Segment**: Create segments in AEP UI using derived attributes
6. **Activate**: AEP activates to Marketo

### Consequences

#### ✅ Positive

- **✅ Security-Friendly**: Push-based, no BigQuery exposure required
- **Real-Time Capability**: 2-10 minute latency (vs 24 hours for FAC)
- **Full AEP Features**: Customer AI, Attribution AI, Identity Graph available
- **Significant Data Reduction**: 85-95% reduction (only 5-10 fields vs 100+)
- **Business User Friendly**: Marketing can build segments in AEP UI

#### ❌ Negative

- **Vendor Lock-in**: Segment logic stored in AEP, profiles in Adobe cloud
- **Operational Complexity**: Dual-system management (BigQuery + AEP)
- **Data Sovereignty**: Profiles stored in Adobe cloud (not GCP)
- **Higher Cost**: More expensive than FAC due to profile storage and ingestion

### When to Choose

**Choose Computed Attributes IF**:
- ✅ **Security blocks BigQuery exposure** (push-based acceptable)
- ✅ Need real-time activation (<5 min latency)
- ✅ Require AEP AI features (Customer AI, Attribution AI)
- ✅ Marketing team needs self-service segmentation in AEP UI

**DO NOT Choose IF**:
- ❌ Batch campaigns are sufficient (use Option 1 or 4 instead)
- ❌ Vendor lock-in is unacceptable
- ❌ Strict data sovereignty requirements (data must stay in GCP)

---

## Option 3: Hybrid Selective Pattern

### Architecture Overview

**Approach**: Combine FAC (99% of profiles, batch) with Computed Attributes (1% of profiles, real-time) to optimize cost while maintaining real-time capability for critical use cases.

```
BigQuery (GCP)
┌─────────────────────────────────────┐
│ Batch Profiles (99%)  Real-Time (1%)│
│ ┌─────────────────┐   ┌───────────┐│
│ │ Campaign        │   │ VIP / High│││
│ │ Audiences       │   │   Value   │││
│ └────────┬────────┘   └─────┬─────┘│
│          │                  │      │
│          │ FAC              │ Push │
│          │ (Query)          │ (Stream)
└──────────┼──────────────────┼──────┘
           │                  │
           ↓                  ↓
         AEP                AEP
    Federated          Profile Store
    Audiences          (1% only)
           │                  │
           └─────────┬────────┘
                     ↓
                  Marketo
```

### How It Works

1. **Batch Path (99%)**: Use FAC for bulk campaign audiences
2. **Real-Time Path (1%)**: Stream computed attributes for VIP/high-value customers
3. **Activate**: Both paths activate to Marketo

### Consequences

#### ✅ Positive

- **Best of Both Worlds**: Batch for campaigns (cheap), real-time for VIPs (targeted)
- **Cost Optimization**: Minimal profiles in AEP, majority stays in BigQuery
- **Minimal Lock-in**: 99% of logic in BigQuery, only 1% in AEP
- **Incremental Adoption**: Start with FAC, add streaming selectively

#### ❌ Negative

- **⚠️ CRITICAL: Requires BigQuery Exposure**: FAC component requires external access
- **Operational Complexity**: Dual architecture to manage
- **Decision Overhead**: Every use case requires "batch or real-time?" decision

### When to Choose

**Choose Hybrid IF**:
- ✅ Need BOTH batch campaigns AND real-time triggers
- ✅ Can identify specific high-value real-time use cases (<10% of volume)
- ✅ **Security team approves BigQuery exposure**
- ✅ Comfortable managing architectural complexity

**DO NOT Choose IF**:
- ❌ **Security policy blocks BigQuery exposure** → Cannot use FAC component
- ❌ Pure batch use cases (use Option 1)
- ❌ Pure real-time use cases (use Option 2)

---

## Option 4: External Audiences API

### Architecture Overview

**Approach**: Push pre-built audience IDs from BigQuery to AEP with minimal storage (IDs + enrichment fields only, 30-day TTL). This is a push-based alternative when FAC is blocked by security.

```
BigQuery (GCP)                     AEP                    Marketo
┌─────────────────┐               ┌───────────┐          ┌──────────┐
│ Build Audiences │               │ External  │          │          │
│ (SQL Query)     │               │ Audiences │          │  Email   │
│                 │               │    API    │          │ Campaign │
│                 │               │           │          │          │
│ Cloud Run   ────┼──Push IDs+───►│  Store    │─────────►│          │
│ (API client)    │   enrichment  │  IDs      │          │          │
└─────────────────┘               │ (30-day   │          └──────────┘
  Scheduled daily                 │   TTL)    │
                                  └───────────┘
                                   Minimal
                                   storage
```

### How It Works

1. **Segment**: Build audiences in BigQuery using SQL
2. **Extract**: Query results (IDs + enrichment fields)
3. **Upload**: Push to AEP External Audiences API via Cloud Run
4. **Store**: AEP stores IDs + enrichment with 30-day TTL
5. **Activate**: AEP activates to Marketo

### Consequences

#### ✅ Positive

- **✅ Security-Friendly**: Push-based, no BigQuery exposure required
- **Significant Data Reduction**: >99% reduction (IDs + enrichment only)
- **Uses AEP Destinations**: Can activate to Marketo, enrichment fields available
- **Fast Setup**: Simpler than FAC (no security approval needed)

#### ❌ Negative

- **❌ CRITICAL: No AEP Segmentation**: Enrichment attributes CANNOT be used in AEP Segment Builder
  - Must build ALL segments in BigQuery BEFORE uploading
  - Cannot combine with AEP behavioral data
  - Loses AEP's core value proposition
- **30-Day TTL**: Data expires, requires automated refresh every 30 days
- **Limited Enrichment**: Max 25 columns (1 ID + 24 enrichment fields)
- **Batch-Only**: One ingestion at a time per audience
- **❌ NOT Recommended for Long-Term Production**: Adobe's official zero-copy solution is FAC

### When to Choose

**Choose External Audiences IF**:
- ✅ **Security blocks BigQuery exposure** (push-based required)
- ✅ POC/testing phase (validate AEP → Marketo integration)
- ✅ Can build all segments in BigQuery (no AEP segmentation needed)
- ✅ Short-term project (3-6 months)
- ✅ Interim solution while lobbying for FAC approval

**DO NOT Choose IF**:
- ❌ Need AEP segmentation features (Segment Builder)
- ❌ Want to combine BigQuery + AEP behavioral data
- ❌ Long-term production use (use Option 2 instead)

---

## Final Recommendation

### Decision Framework

The choice between options depends on **ONE CRITICAL FACTOR**:

#### **Can BigQuery be exposed to AEP?**

```
┌─────────────────────────────────────────────────────────────┐
│ Security Policy: Can BigQuery be exposed to AEP?            │
└─────────────────────┬───────────────────────────────────────┘
                      │
        ┌─────────────┴──────────────┐
        │                            │
      YES                          NO (or UNKNOWN)
        │                            │
        ├─ Batch-only use cases?     ├─ Need real-time (<5 min)?
        │  └─ YES → Option 1 (FAC)   │  ├─ YES → Option 2 (Computed Attributes)
        │           RECOMMENDED       │  │         Production-ready
        │                             │  │
        ├─ Mixed batch + real-time?  │  └─ NO (Batch OK)
        │  └─ Option 3 (Hybrid)       │     ├─ POC/Testing → Option 4 (External Audiences)
        │                             │     │                Short-term only
        │                             │     │
        │                             │     └─ Production → Option 2 (Computed Attributes)
        │                             │                     Long-term fallback
        │                             │
        └─ Future unknown?            └─ Continue lobbying for FAC approval
           └─ Start with Option 4          Use Option 4 interim
              (POC, 3-6 months)             (POC while negotiating)
```

### PRIMARY Recommendation: Assume BigQuery Exposure May Be Permanently Blocked

**Given the critical security constraint**, we recommend a **fallback-first strategy**:

#### Phase 1: POC with Option 4 (External Audiences API) - 3-6 months
- ✅ **Push-based** (no BigQuery exposure required)
- ✅ **Fast setup** (validate AEP → Marketo integration)
- ✅ **Deliver immediate value** (prove ROI to stakeholders)
- ⚠️ Understand limitations (no AEP segmentation, 30-day TTL)

#### Phase 2: Parallel Security Negotiation
- Present FAC architecture to security team (read-only access, audit logs, VPN)
- Get formal approval **OR** formal rejection

#### Phase 3: Production Architecture Decision

**IF Security Approves FAC** (Ideal State):
- Migrate from Option 4 → **Option 1 (FAC)** for production
- Best long-term solution (minimal vendor lock-in, data sovereignty)
- Consider Option 3 (Hybrid) if real-time needs emerge

**IF Security Permanently Blocks FAC** (Fallback State):
- Migrate from Option 4 → **Option 2 (Computed Attributes)** for production
- Push-based, production-ready, full AEP features
- Accept trade-offs (higher vendor lock-in, data in Adobe cloud)

### Why Not Default to Option 1 (FAC)?

**⚠️ Risk**: If we design for Option 1 and security permanently blocks it:
- Wasted architecture design effort
- Delayed time-to-market
- Stakeholder disappointment
- Emergency migration to fallback option

**Strategy**: Start with fallback option (Option 4 for POC, Option 2 for production if FAC blocked), negotiate for Option 1 in parallel.

---

## Approval & Sign-Off

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Data Architecture Lead | ___________ | _________ | _________ |
| Marketing Technology Lead | ___________ | _________ | _________ |
| Security & Compliance | ___________ | _________ | _________ |

---

## References

- [AEP Zero-Copy Executive Summary](../aep-zero-copy-executive-summary.md)
- [FAC vs External Audiences API Comparison](../fac-vs-external-audiences-comparison.md)
- [Segmentation: API vs FAC Explained](../segmentation-api-vs-fac-explained.md)
- [Adobe Federated Audience Composition Documentation](https://experienceleague.adobe.com/en/docs/federated-audience-composition/using/start/get-started)

---

**ADR Status**: Proposed
**Next Review Date**: 2025-11-22
**Supersedes**: None
**Superseded By**: None

---

**END OF ADR-001**
