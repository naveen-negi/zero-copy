# ADR-001: Zero-Copy Architecture Options for AEP and BigQuery Integration

**Status**: Proposed
**Date**: 2025-10-22
**Decision Makers**: Data Architecture Team, Marketing Technology Team
**Technical Owner**: Data Engineering Lead

---

## Context

We need to activate audiences from BigQuery to marketing channels (Marketo, Google Ads, Meta Ads, email platforms) via Adobe Experience Platform (AEP) while minimizing data transfer, maintaining data sovereignty, and avoiding vendor lock-in.

### Current State

- **Data Warehouse**: Google BigQuery (source of truth)
- **Customer Profiles**: Millions of profiles, multi-TB datasets
- **Data Processing**: Analytics, ML models, segmentation logic in BigQuery
- **Activation Requirement**: Activate audiences to marketing destinations via AEP
- **Environment Constraints**:
  - Banking/regulated environment (BaFin compliance, GDPR)
  - Data sovereignty concerns (data must stay in GCP where possible)
  - Vendor lock-in risk must be minimized
  - Cost optimization priority
  - Security policies may restrict external database access

**Example Use Cases**:
- Lead scoring (cold/warm/hot classifications) → Email campaigns
- Churn prediction → Retention campaigns
- Product recommendations → Personalized ads
- Customer segmentation (RFM, CLV) → Multi-channel activation
- VIP customer identification → Special offers

### Problem Statement

Traditional AEP integration requires copying ALL customer data (100+ fields per profile) into Adobe's Real-Time Customer Profile Store, resulting in:

❌ **Massive Data Transfer**: 2-10 TB annually from BigQuery to AEP
❌ **High Costs**: $80K-$145K/year for storage and ingestion alone
❌ **Vendor Lock-in**: All segmentation logic and data stored in AEP
❌ **Data Sovereignty Issues**: Customer data leaves GCP, stored in Adobe cloud
❌ **Complex ETL**: Custom pipelines to sync BigQuery → AEP
❌ **Dual Maintenance**: Schema evolution, data quality rules in both systems

**Key Question**: How can we leverage AEP's activation capabilities (destinations, journey orchestration) WITHOUT copying all data from BigQuery to AEP?

### Key Requirements

1. **Functional Requirements**:
   - Activate audiences from BigQuery to marketing destinations (Marketo, Google Ads, Meta Ads, etc.)
   - Support for 20-50+ different audience segments
   - Ability to refresh audiences on schedule (hourly/daily/weekly)
   - Daily/weekly campaign cadence acceptable for majority of use cases

2. **Non-Functional Requirements**:
   - **Minimize data transfer** out of BigQuery (target: >95% reduction)
   - **Maintain data sovereignty** in GCP (regulatory compliance)
   - **Low vendor lock-in** (preserve ability to switch from AEP to alternatives)
   - **Cost-effective** solution (<$700K/year total cost)
   - **Fast implementation** timeline: 2-12 weeks
   - **Operational simplicity** (minimize custom code and dual-system maintenance)

3. **Security & Compliance**:
   - BaFin compliance (German banking regulations)
   - GDPR compliance (data residency in EU/GCP)
   - Audit trail for all data access
   - Minimal PII exposure to external systems
   - Respect "no external database access" policies if applicable

---

## Decision

We have evaluated **FOUR zero-copy architecture options** for integrating BigQuery with AEP. Each option minimizes data transfer while enabling audience activation to marketing destinations.

**Summary Table**:

| Option | Approach | Data Transfer Reduction | Cost/Year | Best For |
|--------|----------|------------------------|-----------|----------|
| **1. Federated Audience Composition (FAC)** | Pull-based, query in-place | **99.96%** | $247K-$701K | Batch use cases, low vendor lock-in |
| **2. Computed Attributes** | Push-based, derived fields only | **85-95%** | $248K-$858K | Real-time requirements |
| **3. Hybrid Selective** | 99% FAC + 1% streaming | **95-99%** | $286K-$693K | Mixed batch + real-time |
| **4. External Audiences API** | Push-based, IDs + enrichment | **99.6-99.93%** | $112K-$292K | POC/testing only |

Each option is documented below with:
- Architecture diagrams
- Complete GCP implementation (BigQuery, Cloud Run, service accounts)
- Cost analysis
- Limitations and trade-offs
- Decision criteria

---

# Option 1: Federated Audience Composition (RECOMMENDED)

## Status: **RECOMMENDED** for Production

## Decision

Implement **Federated Audience Composition** using AEP's native BigQuery connector to query data in-place, transferring only audience IDs (customer identifiers) to AEP for activation.

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│  GOOGLE CLOUD PLATFORM (GCP)                                    │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  BigQuery Dataset: marketing_analytics                    │ │
│  │                                                            │ │
│  │  ┌──────────────────────────────────────────────────────┐ │ │
│  │  │  Table: customer_profiles                            │ │ │
│  │  │  • customer_id (PRIMARY KEY)                         │ │ │
│  │  │  • email                                             │ │ │
│  │  │  • lead_score                                        │ │ │
│  │  │  • lead_classification (cold/warm/hot)               │ │ │
│  │  │  • last_interaction_date                             │ │ │
│  │  │  • 95+ other behavioral attributes                   │ │ │
│  │  │  (10M rows, ~2 TB)                                   │ │ │
│  │  └──────────────────────────────────────────────────────┘ │ │
│  │                                                            │ │
│  │  ┌──────────────────────────────────────────────────────┐ │ │
│  │  │  External Table/View: customers_for_aep (Read-Only)  │ │ │
│  │  │  • Exposes only necessary columns                    │ │ │
│  │  │  • Service account: aep-reader@project.iam           │ │ │
│  │  │  • Permissions: bigquery.dataViewer                  │ │ │
│  │  └──────────────────────────────────────────────────────┘ │ │
│  └────────────────────────────────────────────────────────────┘ │
│                           ↑                                      │
│                           │ Federated Query (SELECT customer_id) │
│                           │ VPN / IP Allowlist                   │
└───────────────────────────┼──────────────────────────────────────┘
                            │
┌───────────────────────────┼──────────────────────────────────────┐
│  ADOBE EXPERIENCE PLATFORM│                                      │
│                           ↓                                      │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  Federated Audience Composition                           │ │
│  │  • Executes SQL queries against BigQuery                  │ │
│  │  • Returns ONLY customer IDs matching criteria            │ │
│  │  • No full profiles copied                                │ │
│  └────────────────────────────────────────────────────────────┘ │
│                           ↓                                      │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  External Audiences                                        │ │
│  │  • "Hot Leads": 500K customer IDs (~10 MB)                │ │
│  │  • "Warm Leads": 1.5M customer IDs (~30 MB)               │ │
│  │  • "Dormant VIPs": 200K customer IDs (~4 MB)              │ │
│  │  • 30-day TTL, auto-refresh daily                         │ │
│  └────────────────────────────────────────────────────────────┘ │
│                           ↓                                      │
│  Activate to: Marketo, Google Ads, Meta Ads                     │
└──────────────────────────────────────────────────────────────────┘

Data Transfer: 50-500 MB/year (99.96% reduction vs full ingestion)
```

### GCP Implementation Details

#### Step 1: Create Read-Only BigQuery View

```sql
-- Create dedicated dataset for AEP access
CREATE SCHEMA IF NOT EXISTS `banking-project.aep_federated`;

-- Create materialized view for performance
CREATE MATERIALIZED VIEW `banking-project.aep_federated.customers_for_aep`
PARTITION BY DATE(last_interaction_date)
CLUSTER BY lead_classification, region
AS
SELECT
  customer_id,
  email,
  first_name,
  last_name,
  lead_score,
  lead_classification,
  product_interest,
  region,
  last_interaction_date,
  total_lifetime_value
FROM `banking-project.marketing_analytics.customer_profiles`
WHERE
  -- Only include active customers (compliance)
  account_status = 'ACTIVE'
  AND consent_marketing = TRUE
  -- Data freshness (within last 90 days)
  AND last_interaction_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY);

-- Refresh materialized view daily
-- (Scheduled query runs automatically)
```

#### Step 2: Create Service Account for AEP

```bash
# Create service account
gcloud iam service-accounts create aep-federated-reader \
  --display-name="AEP Federated Audience Composition Reader" \
  --project=banking-project

# Grant BigQuery Data Viewer role (read-only)
gcloud projects add-iam-policy-binding banking-project \
  --member="serviceAccount:aep-federated-reader@banking-project.iam.gserviceaccount.com" \
  --role="roles/bigquery.dataViewer"

# Grant BigQuery Job User role (to run queries)
gcloud projects add-iam-policy-binding banking-project \
  --member="serviceAccount:aep-federated-reader@banking-project.iam.gserviceaccount.com" \
  --role="roles/bigquery.jobUser"

# Restrict access to specific dataset only
bq add-iam-policy-binding \
  --member="serviceAccount:aep-federated-reader@banking-project.iam.gserviceaccount.com" \
  --role="roles/bigquery.dataViewer" \
  banking-project:aep_federated

# Generate JSON key for AEP configuration
gcloud iam service-accounts keys create aep-key.json \
  --iam-account=aep-federated-reader@banking-project.iam.gserviceaccount.com
```

#### Step 3: Configure Network Access

```bash
# Create firewall rule for AEP IP allowlist
# (AEP IP addresses obtained from Adobe documentation)
gcloud compute firewall-rules create allow-aep-bigquery \
  --direction=INGRESS \
  --priority=1000 \
  --network=default \
  --action=ALLOW \
  --rules=tcp:443 \
  --source-ranges=<AEP_IP_RANGES> \
  --target-tags=bigquery-access

# Alternative: Use Cloud VPN for more secure connection
# (Recommended for production banking environments)
```

#### Step 4: AEP Configuration

In AEP UI:

1. **Create Federated Database Connection**:
   - Connection Type: Google BigQuery
   - Project ID: `banking-project`
   - Dataset ID: `aep_federated`
   - Service Account Key: Upload `aep-key.json`
   - Test Connection

2. **Create Audience Composition** (Example: "Hot Leads"):

```sql
-- AEP generates this SQL and executes on BigQuery
SELECT
  customer_id,
  email,
  first_name,
  last_name
FROM `banking-project.aep_federated.customers_for_aep`
WHERE
  lead_classification = 'hot'
  AND last_interaction_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
  AND product_interest IN ('Enterprise Plan', 'Premium Plan')
```

3. **Schedule Refresh**: Daily at 6:00 AM UTC

4. **Activate to Destinations**:
   - Marketo: Full profile (email, firstName, lastName)
   - Google Ads: Hashed email only
   - Meta Ads: Hashed email only

### Consequences

#### Positive

✅ **TRUE Zero-Copy Architecture**:
- Data never leaves GCP
- Only customer IDs transferred to AEP (~50 MB vs 2 TB)
- 99.96% data reduction

✅ **Near-Zero Vendor Lock-in**:
- All scoring logic remains in BigQuery SQL
- Easy to switch from AEP to alternatives (Segment, mParticle, Braze)
- Migration cost: <$50K (vs $300K for full profile migration)

✅ **Cost Efficiency**:
- AEP Licensing: $190K-$530K/year
- BigQuery Incremental: $7K-$61K/year
- **Total: $247K-$701K/year** (50% lower than alternatives)

✅ **Data Sovereignty & Compliance**:
- Data stays in GCP EU region
- BaFin compliant (no data transfer to US)
- Full audit trail via BigQuery audit logs
- Granular access control (dataset-level permissions)

✅ **Operational Simplicity**:
- No custom ETL pipelines
- No dual-system sync complexity
- No schema evolution headaches
- Single source of truth in BigQuery

✅ **Fast Implementation**:
- 2-4 weeks to production
- Minimal code (just SQL views + AEP configuration)

#### Negative

❌ **Batch-Only Processing**:
- Minimum refresh: Hourly (typically daily)
- Cannot achieve <5 minute latency
- Not suitable for real-time personalization

❌ **No AEP AI Features**:
- Cannot use Customer AI (requires full profiles)
- Cannot use Attribution AI
- No edge segmentation
- No AEP Identity Graph

❌ **Query Latency**:
- Audience composition takes 5-30 minutes
- BigQuery query execution overhead
- Not suitable for sub-second lookups

❌ **Feature Limitations**:
- Cannot combine with AEP profile-based segmentation
- Limited to SQL capabilities (no drag-and-drop UI advantages)
- Cannot leverage real-time event streams

❌ **Security Approval Required**:
- **CRITICAL BLOCKER**: Requires exposing BigQuery to external system (AEP)
- Security team must approve IP allowlist or VPN connection
- May violate "no external DB access" policies in some banks
- Risk assessment required for pull-based data access pattern

### Cost Analysis

| Component | Annual Cost | Notes |
|-----------|-------------|-------|
| **AEP Licensing** |
| RT-CDP (Foundation) | $100K-$300K | Base platform |
| Journey Optimizer Prime | $50K-$150K | Multi-channel orchestration |
| Federated Audience Composition add-on | $40K-$80K | Zero-copy capability |
| **Subtotal AEP** | **$190K-$530K** | |
| **GCP Costs** |
| BigQuery Storage (1TB) | $240/year | Existing data |
| BigQuery Queries (daily audiences) | $5K-$15K/year | 20-50 queries/day |
| Materialized View Refresh | $2K-$6K/year | Daily refresh |
| VPN Connection | $1.2K/year | Secure connectivity |
| Network Egress (IDs only) | <$100/year | Minimal data transfer |
| **Subtotal GCP** | **$7K-$61K** | |
| **Implementation** |
| Initial Setup | $20K-$50K | 2-4 weeks consulting |
| Ongoing Maintenance | $30K-$60K/year | 0.25-0.5 FTE |
| **TOTAL FIRST YEAR** | **$247K-$701K** | |
| **TOTAL SUBSEQUENT YEARS** | **$227K-$651K** | |

**ROI Comparison**:
- vs Full Profile Ingestion: **50% cost savings** ($400K saved annually)
- vs Computed Attributes: **15% cost savings** ($60K saved annually)

### Risks & Mitigations

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Security team blocks BigQuery exposure | **HIGH** | Critical | 1. Use VPN instead of IP allowlist<br>2. Dataset-level access control<br>3. Audit logs monitoring<br>4. If blocked → Use Option 2 (push-based) |
| BigQuery query costs exceed budget | Medium | Medium | 1. Set query cost quotas<br>2. Use materialized views<br>3. Monitor with budget alerts |
| AEP query timeout (>60s) | Low | Medium | 1. Optimize BigQuery queries<br>2. Use partition pruning<br>3. Pre-aggregate in materialized views |
| Audience refresh failures | Low | Low | 1. Enable AEP alerts<br>2. Monitor BigQuery audit logs<br>3. Retry logic in AEP |

### Decision Criteria Met

| Requirement | Met? | Evidence |
|-------------|------|----------|
| Minimize data transfer | ✅ Yes | 99.96% reduction (50 MB vs 2 TB) |
| Data sovereignty | ✅ Yes | Data never leaves GCP |
| Low vendor lock-in | ✅ Yes | All logic in BigQuery |
| Cost <$700K/year | ✅ Yes | $247K-$701K/year |
| 2-12 week implementation | ✅ Yes | 2-4 weeks typical |
| Daily/weekly campaigns | ✅ Yes | Batch refresh supported |
| BaFin compliance | ✅ Yes | Data in EU, audit logs |
| Real-time (<5 min) | ❌ No | Batch-only, use Option 3 if needed |

### When to Choose This Option

**Choose Federated Audience Composition IF**:
- ✅ Daily/weekly campaign cadence is acceptable (not real-time)
- ✅ Vendor lock-in is a major concern
- ✅ Data sovereignty is critical (regulatory requirement)
- ✅ Cost optimization is a priority
- ✅ Strong BigQuery/SQL capabilities in team
- ✅ Security team approves BigQuery external access (via VPN/IP allowlist)

**DO NOT Choose IF**:
- ❌ Need real-time activation (<5 min latency)
- ❌ Require Customer AI or Attribution AI features
- ❌ Need web personalization (<100ms profile lookups)
- ❌ Security policy blocks external database access → Use Option 2 instead

### Implementation Timeline

| Week | Milestone | Owner |
|------|-----------|-------|
| 1 | Security approval for BigQuery access | Security Team |
| 1-2 | Create service account, configure IAM | Data Engineering |
| 2 | Create materialized views in BigQuery | Data Engineering |
| 2-3 | Configure AEP federated connection | AEP Admin |
| 3 | Build first 3 audience compositions | Marketing Ops |
| 3-4 | Configure destinations (Marketo, Google Ads) | AEP Admin |
| 4 | End-to-end testing | QA Team |
| 4 | Production rollout | All Teams |

---

# Option 2: Computed Attributes Pattern

## Status: Alternative (For Real-Time Requirements)

## Decision

Stream ONLY derived lead scoring attributes (5-10 fields) from BigQuery to AEP Real-Time Customer Profile, keeping raw data (100+ fields) in BigQuery.

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│  GOOGLE CLOUD PLATFORM (GCP)                                    │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  BigQuery: Raw Data (STAYS IN GCP)                        │ │
│  │  • 100+ behavioral attributes per customer                │ │
│  │  • Historical events (2-10 TB)                            │ │
│  │  • ML models execute here                                 │ │
│  └────────────────────────────────────────────────────────────┘ │
│                           ↓ Daily Scoring                        │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  Scheduled Query: Compute Derived Attributes              │ │
│  │  SELECT                                                    │ │
│  │    customer_id,                                           │ │
│  │    lead_classification,  -- 'hot', 'warm', 'cold'        │ │
│  │    propensity_score,     -- 0.87                          │ │
│  │    engagement_index,     -- 42                            │ │
│  │    product_interest,     -- 'Enterprise Plan'             │ │
│  │    churn_risk            -- 'low'                         │ │
│  │  FROM ml_model_predictions                                │ │
│  │  WHERE score_date = CURRENT_DATE()                        │ │
│  └────────────────────────────────────────────────────────────┘ │
│                           ↓                                      │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  Cloud Function / Cloud Run                               │ │
│  │  • Reads scoring results from BigQuery                    │ │
│  │  • Transforms to AEP XDM format                           │ │
│  │  • Calls AEP Streaming Ingestion API                      │ │
│  │  • Batch size: 1000 profiles per request                  │ │
│  └────────────────────────────────────────────────────────────┘ │
│                           ↓ HTTPS API                            │
└───────────────────────────┼──────────────────────────────────────┘
                            │
┌───────────────────────────┼──────────────────────────────────────┐
│  ADOBE EXPERIENCE PLATFORM│                                      │
│                           ↓                                      │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  Streaming Ingestion API                                  │ │
│  │  • Receives minimal profiles (5-10 fields only)           │ │
│  │  • 500 MB/day (vs 50-100 GB for full profiles)           │ │
│  └────────────────────────────────────────────────────────────┘ │
│                           ↓                                      │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  Real-Time Customer Profile Store                         │ │
│  │  • 10M profiles × 5 fields = 500 MB storage               │ │
│  │  • Fast lookups (<100ms)                                  │ │
│  │  • Supports streaming segmentation                        │ │
│  └────────────────────────────────────────────────────────────┘ │
│                           ↓                                      │
│  Segmentation: "Hot Leads" WHERE lead_classification = 'hot'    │
│                           ↓                                      │
│  Activate to: Marketo, Google Ads (2-10 min latency)            │
└──────────────────────────────────────────────────────────────────┘

Data Transfer: 500 MB - 2 GB/year (85-95% reduction)
```

### GCP Implementation Details

#### Step 1: Create Computed Attributes Table

```sql
-- Scheduled query runs daily at 2:00 AM
CREATE OR REPLACE TABLE `banking-project.marketing_analytics.computed_attributes`
PARTITION BY score_date
AS
SELECT
  customer_id,
  email,
  first_name,
  last_name,

  -- Computed attributes (derived from 100+ raw fields)
  lead_classification,  -- ML model output
  CAST(lead_score AS FLOAT64) as propensity_score,
  engagement_index,
  product_interest,
  churn_risk_tier,

  CURRENT_DATE() as score_date,
  CURRENT_TIMESTAMP() as computed_at
FROM `banking-project.ml_models.lead_scoring_predictions`
WHERE score_date = CURRENT_DATE();
```

#### Step 2: Create Streaming Service (Cloud Run)

**Dockerfile**:
```dockerfile
FROM python:3.11-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt

COPY app.py .
CMD ["python", "app.py"]
```

**requirements.txt**:
```
google-cloud-bigquery==3.11.0
requests==2.31.0
google-auth==2.23.0
```

**app.py**:
```python
import os
import time
import requests
from google.cloud import bigquery
from google.auth import default

# AEP Configuration
AEP_ENDPOINT = os.environ['AEP_STREAMING_ENDPOINT']
AEP_IMS_ORG_ID = os.environ['AEP_IMS_ORG_ID']
AEP_DATASET_ID = os.environ['AEP_DATASET_ID']

# BigQuery client
bq_client = bigquery.Client()

def fetch_computed_attributes(batch_size=1000, offset=0):
    """Fetch computed attributes from BigQuery."""
    query = f"""
    SELECT
        customer_id,
        email,
        first_name,
        last_name,
        lead_classification,
        propensity_score,
        engagement_index,
        product_interest,
        churn_risk_tier
    FROM `banking-project.marketing_analytics.computed_attributes`
    WHERE score_date = CURRENT_DATE()
    LIMIT {batch_size} OFFSET {offset}
    """

    results = bq_client.query(query).result()
    return [dict(row) for row in results]

def transform_to_xdm(profile):
    """Transform BigQuery row to AEP XDM format."""
    return {
        "header": {
            "schemaRef": {
                "id": "https://ns.adobe.com/banking/schemas/profile",
                "contentType": "application/vnd.adobe.xed-full+json;version=1"
            },
            "imsOrgId": AEP_IMS_ORG_ID,
            "datasetId": AEP_DATASET_ID,
            "source": {
                "name": "BigQuery Lead Scoring"
            }
        },
        "body": {
            "xdmMeta": {
                "schemaRef": {
                    "id": "https://ns.adobe.com/banking/schemas/profile",
                    "contentType": "application/vnd.adobe.xed-full+json;version=1"
                }
            },
            "xdmEntity": {
                "_id": profile['customer_id'],
                "identityMap": {
                    "email": [{
                        "id": profile['email'],
                        "primary": True
                    }],
                    "customer_id": [{
                        "id": profile['customer_id'],
                        "primary": True
                    }]
                },
                "person": {
                    "name": {
                        "firstName": profile['first_name'],
                        "lastName": profile['last_name']
                    }
                },
                "banking:leadScoring": {
                    "classification": profile['lead_classification'],
                    "propensityScore": profile['propensity_score'],
                    "engagementIndex": profile['engagement_index'],
                    "productInterest": profile['product_interest'],
                    "churnRisk": profile['churn_risk_tier']
                }
            }
        }
    }

def send_to_aep(profiles, retry_count=3):
    """Send batch of profiles to AEP Streaming Ingestion API."""
    payload = {
        "messages": [transform_to_xdm(p) for p in profiles]
    }

    headers = {
        "Content-Type": "application/json",
        "x-gw-ims-org-id": AEP_IMS_ORG_ID
    }

    for attempt in range(retry_count):
        try:
            response = requests.post(
                AEP_ENDPOINT,
                json=payload,
                headers=headers,
                timeout=30
            )

            if response.status_code == 200:
                print(f"✓ Sent {len(profiles)} profiles to AEP")
                return True
            elif response.status_code == 429:
                # Rate limit - exponential backoff
                wait_time = 2 ** attempt
                print(f"⚠ Rate limited. Waiting {wait_time}s...")
                time.sleep(wait_time)
            else:
                print(f"✗ Error {response.status_code}: {response.text}")

        except Exception as e:
            print(f"✗ Exception: {e}")
            time.sleep(2 ** attempt)

    return False

def main():
    """Main sync loop."""
    batch_size = 1000
    offset = 0
    total_sent = 0

    while True:
        profiles = fetch_computed_attributes(batch_size, offset)

        if not profiles:
            print(f"✓ Completed. Total sent: {total_sent}")
            break

        if send_to_aep(profiles):
            total_sent += len(profiles)
            offset += batch_size
        else:
            print("✗ Failed to send batch. Stopping.")
            break

        # Rate limiting: max 1 request/second
        time.sleep(1)

if __name__ == "__main__":
    main()
```

#### Step 3: Deploy to Cloud Run

```bash
# Build and deploy
gcloud run deploy aep-profile-sync \
  --source=. \
  --region=europe-west1 \
  --platform=managed \
  --memory=512Mi \
  --timeout=3600 \
  --set-env-vars="AEP_STREAMING_ENDPOINT=https://dcs.adobedc.net/collection/...,AEP_IMS_ORG_ID=...,AEP_DATASET_ID=..." \
  --service-account=aep-sync@banking-project.iam.gserviceaccount.com \
  --no-allow-unauthenticated

# Schedule daily execution via Cloud Scheduler
gcloud scheduler jobs create http aep-daily-sync \
  --location=europe-west1 \
  --schedule="0 3 * * *" \
  --uri="https://aep-profile-sync-...-ew.a.run.app" \
  --http-method=POST \
  --oidc-service-account-email=aep-sync@banking-project.iam.gserviceaccount.com
```

### Consequences

#### Positive

✅ **Real-Time Capability**:
- 2-10 minute latency (vs 24 hours for federated)
- Supports streaming segmentation
- Fast profile lookups (<100ms)

✅ **Full AEP Features**:
- Customer AI, Attribution AI available
- Identity Graph for cross-device stitching
- Edge segmentation supported
- Web personalization enabled

✅ **Significant Data Reduction**:
- 85-95% less data vs full profile ingestion
- Only 5-10 fields streamed (not 100+)
- 500 MB/day vs 50-100 GB/day

✅ **Business User Friendly**:
- Marketing ops can build segments in AEP UI
- No SQL knowledge required
- Faster iteration on audience definitions

#### Negative

❌ **Vendor Lock-in**:
- Segment logic stored in AEP
- Profile data in Adobe's cloud
- Migration cost: $100K-$300K

❌ **Higher Cost**:
- $248K-$858K/year (15-30% more than Option 1)
- Profile ingestion API costs
- Profile storage costs

❌ **Operational Complexity**:
- Dual-system management (BigQuery + AEP)
- Streaming pipeline maintenance
- Schema evolution in both systems
- Monitoring multiple components

❌ **Data Sovereignty**:
- Profiles stored in Adobe cloud (not GCP)
- May not meet strict data residency requirements

### Cost Analysis

| Component | Annual Cost |
|-----------|-------------|
| RT-CDP (Select) | $150K-$400K |
| Journey Optimizer | $50K-$150K |
| Streaming Ingestion (10M profiles/day) | $10K-$30K |
| Profile Storage | $20K-$50K |
| GCP (BigQuery + Cloud Run) | $8K-$28K |
| Implementation + Maintenance | $100K-$200K |
| **TOTAL FIRST YEAR** | **$248K-$858K** |

### When to Choose This Option

**Choose Computed Attributes IF**:
- ✅ Need real-time activation (<5 min latency)
- ✅ Require Customer AI or Attribution AI
- ✅ Need web personalization (<100ms lookups)
- ✅ Cross-device identity stitching required
- ✅ >50% of use cases need real-time

**DO NOT Choose IF**:
- ❌ Batch campaigns are sufficient (use Option 1)
- ❌ Vendor lock-in is unacceptable
- ❌ Cost optimization is priority
- ❌ Strict data sovereignty requirements

---

# Option 3: Hybrid Selective Pattern

## Status: Alternative (For Mixed Requirements)

## Decision

Combine Federated Audience Composition (99% of profiles, batch) with Computed Attributes (1% of profiles, real-time) to optimize cost while maintaining real-time capability for critical use cases.

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│  GOOGLE CLOUD PLATFORM (GCP)                                    │
│                                                                  │
│  ┌──────────────────────────┬──────────────────────────────┐   │
│  │  Batch Data (99%)        │  Real-Time Subset (1%)       │   │
│  │  • 9.9M profiles         │  • 100K profiles             │   │
│  │  • Lead classifications  │  • VIP customers             │   │
│  │  • Campaign audiences    │  • High-value leads          │   │
│  └──────────┬───────────────┴───────────┬──────────────────┘   │
│             │                           │                       │
│             │ PATH 1: Federated         │ PATH 2: Streaming    │
│             │ (Query in-place)          │ (Push attributes)    │
└─────────────┼───────────────────────────┼───────────────────────┘
              │                           │
┌─────────────┼───────────────────────────┼───────────────────────┐
│  AEP        ↓                           ↓                       │
│  ┌────────────────────┐    ┌────────────────────────────┐      │
│  │ Federated Audiences│    │ Profile Store (1% only)    │      │
│  │ (99% of volume)    │    │ • 100K profiles            │      │
│  │ • Cost: $40K-80K   │    │ • Real-time scores         │      │
│  │ • Daily refresh    │    │ • Cost: $10K-30K           │      │
│  └────────────────────┘    └────────────────────────────┘      │
│             │                           │                       │
│             └───────────┬───────────────┘                       │
│                         ↓                                       │
│        Activate to: Marketo, Google Ads, Meta Ads              │
└─────────────────────────────────────────────────────────────────┘

Data Transfer: 100 MB - 1 GB/year (95-99% reduction)
Cost: $286K-$693K/year (20-30% less than full real-time)
```

### GCP Implementation Details

#### Batch Path (99%): Use Federated Audience Composition

```sql
-- View for batch audiences (same as Option 1)
CREATE MATERIALIZED VIEW `banking-project.aep_federated.batch_customers`
PARTITION BY DATE(last_interaction_date)
AS
SELECT
  customer_id,
  email,
  lead_classification,
  product_interest
FROM `banking-project.marketing_analytics.customer_profiles`
WHERE is_vip = FALSE;  -- Exclude VIPs (they use real-time path)
```

#### Real-Time Path (1%): Stream Computed Attributes

```sql
-- Only VIP/high-value customers get real-time treatment
CREATE OR REPLACE TABLE `banking-project.marketing_analytics.realtime_subset`
AS
SELECT
  customer_id,
  email,
  lead_classification,
  propensity_score,
  engagement_index
FROM `banking-project.marketing_analytics.computed_attributes`
WHERE
  (is_vip = TRUE OR total_lifetime_value > 100000)
  AND score_date = CURRENT_DATE();

-- Result: ~100K profiles (1% of 10M total)
```

### Consequences

#### Positive

✅ **Cost Optimization**:
- 99% uses federated (cheap)
- 1% uses streaming (expensive but targeted)
- 20-30% savings vs full streaming

✅ **Best of Both Worlds**:
- Batch for campaigns (sufficient for 99%)
- Real-time for critical use cases (sales alerts, VIP treatment)

✅ **Minimal Lock-in**:
- 99% of logic stays in BigQuery
- Only 1% dependent on AEP features

✅ **Incremental Adoption**:
- Start with federated (fast, low-risk)
- Add real-time selectively based on ROI

#### Negative

❌ **Operational Complexity**:
- Dual architecture to manage
- Two skillsets required (BigQuery + AEP)
- More moving parts to monitor

❌ **Higher Than Federated Alone**:
- 15-25% more expensive than pure Option 1
- Complexity overhead

❌ **Decision Fatigue**:
- Every new use case requires "batch or real-time?" decision
- Governance overhead

### Cost Analysis

| Component | Annual Cost |
|-----------|-------------|
| RT-CDP (Foundation) | $100K-$250K |
| Journey Optimizer Prime | $50K-$150K |
| Federated add-on | $40K-$80K |
| Streaming (1% profiles) | $3K-$8K |
| GCP (both paths) | $13K-$35K |
| Implementation + Maintenance | $80K-$170K |
| **TOTAL FIRST YEAR** | **$286K-$693K** |

### When to Choose This Option

**Choose Hybrid IF**:
- ✅ Need BOTH batch campaigns AND real-time triggers
- ✅ Can identify specific high-ROI real-time use cases (<10% of volume)
- ✅ Want to minimize vendor lock-in while keeping strategic real-time capability
- ✅ Comfortable managing architectural complexity

**DO NOT Choose IF**:
- ❌ Pure batch use cases (use Option 1)
- ❌ Pure real-time use cases (use Option 2)
- ❌ Small team (complexity overhead too high)

---

# Option 4: External Audiences (Push-Based, Minimal Storage)

## Status: POC/Testing Only (NOT for Long-Term Production)

## Decision

Use AEP's External Audiences API to push pre-built audience IDs from BigQuery to AEP with minimal storage (IDs + enrichment fields only, 30-day TTL). This is a push-based alternative when Federated Audience Composition is blocked by security.

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│  GOOGLE CLOUD PLATFORM (GCP)                                    │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  BigQuery: Build Audiences (Scheduled Query)              │ │
│  │  • Query runs daily at 5:00 AM                            │ │
│  │  • Computes "Hot Leads" segment in BigQuery               │ │
│  │  • Results stored in staging table                        │ │
│  └────────────────────────────────────────────────────────────┘ │
│                           ↓                                      │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  Cloud Scheduler → Cloud Run Service                      │ │
│  │  • Triggered daily at 6:00 AM                             │ │
│  │  • Reads audience from BigQuery                           │ │
│  │  • Calls AEP External Audiences API                       │ │
│  │  • Pushes IDs + enrichment fields                         │ │
│  └────────────────────────────────────────────────────────────┘ │
│                           ↓ HTTPS POST                           │
└───────────────────────────┼──────────────────────────────────────┘
                            │
┌───────────────────────────┼──────────────────────────────────────┐
│  ADOBE EXPERIENCE PLATFORM│                                      │
│                           ↓                                      │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  External Audiences API (/core/ais/external-audience/)    │ │
│  │  • Receives audience IDs + enrichment                     │ │
│  │  • Max 25 columns (1 ID + 24 enrichment fields)           │ │
│  │  • Max 1 GB per upload                                    │ │
│  └────────────────────────────────────────────────────────────┘ │
│                           ↓                                      │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  External Audience Storage (MINIMAL)                      │ │
│  │  • "Hot Leads": 50K IDs + 10 enrichment fields           │ │
│  │  • Storage: ~10 MB (vs 2.5 GB full profiles)             │ │
│  │  • 30-day TTL (auto-expires, requires refresh)           │ │
│  │  • ⚠️ Enrichment NOT usable in segmentation              │ │
│  └────────────────────────────────────────────────────────────┘ │
│                           ↓                                      │
│  Activate to: Marketo, Google Ads, Meta Ads                     │
│  (Can use enrichment fields for personalization only)           │
└──────────────────────────────────────────────────────────────────┘

Data Storage: 36 MB - 200 MB (99.6-99.93% reduction vs full profiles)
Push-Based: ✅ Security-friendly (no BigQuery exposure)
```

### GCP Implementation Details

#### Step 1: Create Audience Staging Table

```sql
-- Scheduled query runs daily at 5:00 AM
CREATE OR REPLACE TABLE `banking-project.aep_audiences.hot_leads_staging`
AS
SELECT
  customer_id,                  -- Required: Primary identity
  email,                        -- Enrichment field 1
  first_name,                   -- Enrichment field 2
  last_name,                    -- Enrichment field 3
  lead_score,                   -- Enrichment field 4
  lead_classification,          -- Enrichment field 5
  product_interest,             -- Enrichment field 6
  engagement_index,             -- Enrichment field 7
  total_lifetime_value,         -- Enrichment field 8
  last_interaction_date         -- Enrichment field 9
  -- Max 24 enrichment fields allowed
FROM `banking-project.marketing_analytics.customer_profiles`
WHERE
  lead_classification = 'hot'
  AND consent_marketing = TRUE
  AND last_interaction_date > DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
LIMIT 1000000;  -- Max rows per upload (practical limit)
```

#### Step 2: Create Cloud Run Service for API Push

**app.py**:
```python
import os
import requests
from google.cloud import bigquery
from typing import List, Dict

# AEP Configuration
AEP_API_BASE = "https://platform.adobe.io/data/core/ais"
AEP_ACCESS_TOKEN = os.environ['AEP_ACCESS_TOKEN']
AEP_CLIENT_ID = os.environ['AEP_CLIENT_ID']
AEP_IMS_ORG_ID = os.environ['AEP_IMS_ORG_ID']
AEP_SANDBOX = os.environ.get('AEP_SANDBOX', 'prod')

def create_external_audience(audience_name: str, description: str) -> str:
    """
    Create external audience definition in AEP.
    Returns: audience_id
    """
    url = f"{AEP_API_BASE}/external-audience/"
    headers = {
        "Authorization": f"Bearer {AEP_ACCESS_TOKEN}",
        "x-api-key": AEP_CLIENT_ID,
        "x-gw-ims-org-id": AEP_IMS_ORG_ID,
        "x-sandbox-name": AEP_SANDBOX,
        "Content-Type": "application/json"
    }

    payload = {
        "audienceName": audience_name,
        "description": description,
        "audienceType": "people",
        "identityType": "customer_id",
        "ttl": 30,  # 30-day expiration
        "enrichmentAttributes": [
            {"name": "email", "type": "string"},
            {"name": "first_name", "type": "string"},
            {"name": "last_name", "type": "string"},
            {"name": "lead_score", "type": "number"},
            {"name": "lead_classification", "type": "string"},
            {"name": "product_interest", "type": "string"},
            {"name": "engagement_index", "type": "number"},
            {"name": "total_lifetime_value", "type": "number"},
            {"name": "last_interaction_date", "type": "date"}
        ]
    }

    response = requests.post(url, json=payload, headers=headers)
    response.raise_for_status()

    operation_data = response.json()
    operation_id = operation_data.get("operationId")

    # Poll for completion
    status_url = f"{AEP_API_BASE}/external-audiences/operations/{operation_id}"
    import time
    for _ in range(30):  # Max 5 minutes
        status_response = requests.get(status_url, headers=headers)
        status_data = status_response.json()

        if status_data.get("status") == "SUCCESS":
            return status_data.get("audienceId")
        elif status_data.get("status") == "FAILED":
            raise Exception(f"Audience creation failed: {status_data}")

        time.sleep(10)

    raise Exception("Audience creation timeout")


def generate_csv_export(audience_id: str, gcs_path: str):
    """Export BigQuery audience to GCS as CSV."""
    client = bigquery.Client()

    # Export to GCS (CSV format, max 1GB)
    destination_uri = f"gs://{gcs_path}"
    table_ref = "banking-project.aep_audiences.hot_leads_staging"

    extract_job = client.extract_table(
        table_ref,
        destination_uri,
        location="EU",
        job_config=bigquery.ExtractJobConfig(
            destination_format=bigquery.DestinationFormat.CSV,
            print_header=True
        )
    )
    extract_job.result()  # Wait for completion
    return destination_uri


def trigger_ingestion(audience_id: str, csv_path: str) -> str:
    """
    Trigger data ingestion for external audience.
    Returns: run_id
    """
    url = f"{AEP_API_BASE}/external-audience/{audience_id}/runs"
    headers = {
        "Authorization": f"Bearer {AEP_ACCESS_TOKEN}",
        "x-api-key": AEP_CLIENT_ID,
        "x-gw-ims-org-id": AEP_IMS_ORG_ID,
        "x-sandbox-name": AEP_SANDBOX,
        "Content-Type": "application/json"
    }

    payload = {
        "filePath": csv_path,
        "format": "csv"
    }

    response = requests.post(url, json=payload, headers=headers)
    response.raise_for_status()

    return response.json().get("runId")


def check_ingestion_status(audience_id: str, run_id: str) -> Dict:
    """Check ingestion job status."""
    url = f"{AEP_API_BASE}/external-audience/{audience_id}/runs/{run_id}"
    headers = {
        "Authorization": f"Bearer {AEP_ACCESS_TOKEN}",
        "x-api-key": AEP_CLIENT_ID,
        "x-gw-ims-org-id": AEP_IMS_ORG_ID,
        "x-sandbox-name": AEP_SANDBOX
    }

    response = requests.get(url, headers=headers)
    response.raise_for_status()
    return response.json()


def main_sync_workflow(request):
    """Main workflow for Cloud Run service."""

    # Step 1: Create or get existing audience
    audience_id = os.environ.get('AEP_AUDIENCE_ID')
    if not audience_id:
        audience_id = create_external_audience(
            audience_name="Hot Leads - BigQuery Daily",
            description="High propensity leads from BigQuery lead scoring model"
        )
        print(f"✓ Created audience: {audience_id}")

    # Step 2: Export BigQuery table to GCS as CSV
    gcs_bucket = os.environ['GCS_BUCKET']
    csv_path = f"{gcs_bucket}/aep-audiences/hot-leads-{time.strftime('%Y%m%d')}.csv"
    generate_csv_export(audience_id, csv_path)
    print(f"✓ Exported to: {csv_path}")

    # Step 3: Trigger AEP ingestion
    run_id = trigger_ingestion(audience_id, csv_path)
    print(f"✓ Ingestion started: {run_id}")

    # Step 4: Poll for completion
    import time
    for _ in range(60):  # Max 10 minutes
        status = check_ingestion_status(audience_id, run_id)

        if status.get("status") == "COMPLETED":
            print(f"✓ Ingestion completed: {status.get('profilesIngested')} profiles")
            return {"status": "success", "profiles": status.get("profilesIngested")}
        elif status.get("status") == "FAILED":
            raise Exception(f"Ingestion failed: {status}")

        time.sleep(10)

    raise Exception("Ingestion timeout")


if __name__ == "__main__":
    # For Cloud Run
    from flask import Flask, request
    app = Flask(__name__)

    @app.route("/", methods=["POST"])
    def handle_request():
        result = main_sync_workflow(request)
        return result, 200

    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
```

#### Step 3: Deploy and Schedule

```bash
# Deploy Cloud Run service
gcloud run deploy aep-external-audiences \
  --source=. \
  --region=europe-west1 \
  --memory=1Gi \
  --timeout=600 \
  --set-env-vars="AEP_ACCESS_TOKEN=...,AEP_CLIENT_ID=...,AEP_IMS_ORG_ID=...,GCS_BUCKET=banking-audiences" \
  --service-account=aep-sync@banking-project.iam.gserviceaccount.com \
  --no-allow-unauthenticated

# Schedule daily execution
gcloud scheduler jobs create http aep-external-audience-daily \
  --location=europe-west1 \
  --schedule="0 6 * * *" \
  --time-zone="Europe/Berlin" \
  --uri="https://aep-external-audiences-...-ew.a.run.app" \
  --http-method=POST \
  --oidc-service-account-email=aep-sync@banking-project.iam.gserviceaccount.com
```

### API Endpoints Reference

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/core/ais/external-audience/` | POST | Create audience definition |
| `/core/ais/external-audiences/operations/{ID}` | GET | Check creation status |
| `/core/ais/external-audience/{AUDIENCE_ID}` | PATCH | Update audience metadata |
| `/core/ais/external-audience/{AUDIENCE_ID}/runs` | POST | Trigger data ingestion |
| `/core/ais/external-audience/{AUDIENCE_ID}/runs/{RUN_ID}` | GET | Check ingestion status |
| `/core/ais/external-audience/{AUDIENCE_ID}` | DELETE | Delete audience |

### Consequences

#### Positive

✅ **Push-Based (Security-Friendly)**:
- No external BigQuery exposure required
- Compliant with "no external DB access" policies
- Security team approval easier

✅ **Significant Data Reduction**:
- 99.6-99.93% reduction vs full profiles
- 1M profiles: 36 MB (IDs only) or 200 MB (IDs + 10 enrichment fields)
- vs 50 GB for full profiles

✅ **Uses AEP Destinations**:
- Can activate to Marketo, Google Ads, Meta Ads
- Enrichment fields available for personalization
- Same destination connectors as full AEP

✅ **Lower Cost Than Full Profiles**:
- $112K-$292K/year vs $500K+ for full profile ingestion
- Minimal storage and API costs

✅ **Good for POC/Testing**:
- Fast setup (1-2 weeks)
- Validate AEP activation workflows
- Test destination integrations

#### Negative

❌ **CRITICAL: No AEP Segmentation**:
- **Enrichment attributes CANNOT be used in Segment Builder**
- Cannot build segments in AEP: `(lead_score > 80) AND (visited_pricing_page)`
- Must build ALL segments in BigQuery
- **Loses AEP's core value proposition**

❌ **30-90 Day TTL Requirement**:
- Data expires after TTL (default 30 days)
- Requires automated refresh every 30 days
- If automation fails, audiences become inactive
- Operational burden

❌ **Batch-Only (Effectively)**:
- Only one ingestion at a time per audience
- Cannot run concurrent uploads
- Not suitable for sub-hour refresh
- Minimum practical refresh: Daily

❌ **Limited Enrichment (25 Columns Max)**:
- 1 identity field + max 24 enrichment fields
- Cannot send full customer profiles
- Must prioritize most important fields

❌ **No Journey Optimizer Integration**:
- Enrichment attributes not yet available in AJO journeys
- Limits personalization in multi-channel journeys

❌ **File Size Constraint**:
- Max 1 GB per CSV upload
- Large audiences may need splitting

❌ **Enrichment Attributes Are Transient**:
- Not stored durably in Profile Store
- Tied to uploaded audience lifecycle
- Cannot combine with AEP behavioral data

❌ **NOT Recommended for Long-Term Production**:
- Adobe's official zero-copy solution is FAC (Option 1)
- External Audiences designed for POC/testing
- Lacks robustness for enterprise production

### Cost Analysis

| Component | Annual Cost | Notes |
|-----------|-------------|-------|
| **AEP Licensing** |
| RT-CDP (Foundation) | $80K-$200K | Minimal profile usage |
| Journey Optimizer (Optional) | $30K-$80K | If needed |
| **Subtotal AEP** | **$110K-$280K** | |
| **GCP Costs** |
| BigQuery (audience queries) | $1K-$5K/year | Daily staging queries |
| Cloud Storage (CSV staging) | $120/year | Minimal |
| Cloud Run (API service) | $240/year | Minimal compute |
| Cloud Scheduler | $12/year | Daily trigger |
| **Subtotal GCP** | **$1.4K-$5.4K** | |
| **Implementation & Maintenance** |
| Initial Setup | $5K-$15K | 1-2 weeks |
| Ongoing Maintenance | $15K-$30K/year | Automation monitoring |
| **TOTAL FIRST YEAR** | **$112K-$292K** | |
| **TOTAL SUBSEQUENT YEARS** | **$107K-$277K** | |

**Cost Comparison**:
- 50-60% cheaper than Computed Attributes (Option 2): $248K-$858K
- 15-30% cheaper than Federated (Option 1): $247K-$701K (but loses segmentation!)

### Critical Limitations Summary

| Limitation | Impact | Workaround |
|------------|--------|------------|
| **No segmentation with enrichment** | ❌ CRITICAL | Build all segments in BigQuery |
| **30-day TTL** | ❌ HIGH | Automate refresh, monitor failures |
| **25 column limit** | ⚠️ MEDIUM | Prioritize most important fields |
| **1 GB file size** | ⚠️ MEDIUM | Split large audiences |
| **One ingestion at a time** | ⚠️ MEDIUM | Schedule non-overlapping uploads |
| **Batch-only** | ⚠️ MEDIUM | Use Option 2 if real-time needed |

### When to Choose This Option

**Choose External Audiences IF**:
- ✅ Security blocks BigQuery external access (FAC impossible)
- ✅ POC/testing only (validate AEP destinations)
- ✅ Can build all segments in BigQuery (no AEP segmentation needed)
- ✅ Batch campaigns sufficient (daily/weekly)
- ✅ Budget constraint (<$300K/year)
- ✅ Short-term project (3-6 months)

**DO NOT Choose IF**:
- ❌ Need AEP segmentation features (Segment Builder)
- ❌ Want to combine BigQuery + AEP behavioral data in segments
- ❌ Need real-time activation (<5 min)
- ❌ Long-term production use (use Computed Attributes or lobby for FAC)
- ❌ >25 enrichment fields needed

### Recommended Usage

**External Audiences is ONLY recommended for**:

1. **POC/Pilot Phase** (3-6 months):
   - Validate AEP destination integrations
   - Test activation workflows
   - Prove business value
   - **Then migrate to FAC (Option 1) or Computed Attributes (Option 2)**

2. **Interim Solution While Lobbying for FAC**:
   - Security hasn't approved BigQuery exposure yet
   - Use External Audiences to deliver immediate value
   - Continue security discussions for FAC approval
   - Migrate to FAC once approved

3. **Very Simple ID-Only Activation**:
   - Pre-built audiences from BigQuery
   - No need for AEP segmentation
   - Pure activation use case
   - But consider Reverse ETL (Census/Hightouch) as alternative

### Implementation Timeline

| Week | Milestone | Owner |
|------|-----------|-------|
| 1 | Create BigQuery staging queries | Data Engineering |
| 1 | Build Cloud Run service | Data Engineering |
| 1-2 | Configure AEP service account, API access | AEP Admin |
| 2 | Test API integration (create, upload, activate) | Data Engineering + AEP Admin |
| 2 | Configure Cloud Scheduler automation | Data Engineering |
| 2 | End-to-end testing | QA Team |
| 2 | Production rollout (POC) | All Teams |

**Note**: Only 2 weeks because it's simpler than FAC (no security approval needed for push-based approach)

---

## Final Recommendation

### Decision Summary: Zero-Copy Architecture Options

This ADR evaluated **four zero-copy architecture options** for activating BigQuery audiences via AEP:

1. **Federated Audience Composition (FAC)**: Pull-based, query in-place, 99.96% data reduction
2. **Computed Attributes**: Push-based, stream derived fields only, 85-95% data reduction
3. **Hybrid Selective**: Combination of FAC (99%) + streaming (1%), 95-99% data reduction
4. **External Audiences API**: Push-based IDs + enrichment, 99.6-99.93% data reduction

All four options are **zero-copy** architectures compared to traditional full profile ingestion (which would require copying 100+ fields per profile).

### PRIMARY: Option 1 - Federated Audience Composition

**Recommended for initial implementation based on**:

1. ✅ **Lowest Total Cost**: $247K-$701K/year (50% savings vs full ingestion)
2. ✅ **Minimal Vendor Lock-in**: All segmentation logic remains in BigQuery
3. ✅ **Data Sovereignty**: Data never leaves GCP
4. ✅ **Fastest Implementation**: 2-4 weeks
5. ✅ **Meets Core Requirements**: Daily/weekly campaigns sufficient for 90% of use cases
6. ✅ **TRUE Zero-Copy**: Only customer IDs transferred to AEP, not full profiles

### UPGRADE PATH: Option 3 - Hybrid (If Real-Time Needed)

**Recommended migration path**:

```
Phase 1 (Months 1-3): Deploy Option 1 (Federated)
  → Prove AEP works for 80-90% of use cases
  → Low risk, fast ROI

Phase 2 (Months 4-6): Identify Real-Time Needs
  → Measure business value of <5 min latency
  → Quantify ROI: "Sales alerts = $500K/year revenue"

Phase 3 (Months 7-12): Add Option 3 (Hybrid) if justified
  → Stream 1% high-value profiles only
  → Keep 99% on federated path
  → Best economics + strategic real-time capability
```

### CRITICAL BLOCKER: Security Approval

⚠️ **MUST RESOLVE BEFORE PROCEEDING WITH OPTION 1**:

**Blocker**: Federated Audience Composition requires exposing BigQuery to external system (AEP) via:
- IP allowlist OR
- Cloud VPN connection

**Current Status**: **BLOCKED**
- Security policy may prohibit external database access
- BaFin compliance review required
- Pull-based data access needs risk assessment

**IF SECURITY BLOCKS OPTION 1**:
→ **Primary Fallback: Option 4 (External Audiences)** - for POC/immediate value (3-6 months)
→ **Long-term Solution: Option 2 (Computed Attributes)** - push-based production architecture
→ **OR Continue lobbying for FAC approval** - best long-term solution

**Decision Matrix When FAC is Blocked**:

```
Security Blocks FAC
↓
Need real-time (<5 min)?
├─ YES → Option 2 (Computed Attributes)
│         • $248K-$858K/year
│         • Full AEP features
│         • Production-ready
│
└─ NO (Batch OK) → Option 4 (External Audiences) for POC
                    • $112K-$292K/year
                    • Fast setup (2 weeks)
                    • Validate destinations
                    • Then migrate to Option 2 or lobby for FAC
```

**Action Required**:
1. Schedule meeting with Security & Compliance team
2. Present federated architecture (read-only, audit logs, VPN)
3. Get formal approval OR rejection
4. If rejected:
   - **Short-term**: Deploy Option 4 (POC, 3-6 months)
   - **Long-term**: Plan Option 2 (production) OR continue FAC lobbying

---

## References

- [AEP Zero-Copy Executive Summary](../aep-zero-copy-executive-summary.md)
- [GCP Zero-Copy Architecture Options](../gcp-zero-copy-architecture-options.md)
- [Adobe Federated Audience Composition Documentation](https://experienceleague.adobe.com/en/docs/federated-audience-composition/using/start/get-started)
- [BigQuery External Connections](https://cloud.google.com/bigquery/docs/external-data-sources)

---

## Approval & Sign-Off

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Data Architecture Lead | ___________ | _________ | _________ |
| Marketing Technology Lead | ___________ | _________ | _________ |
| Security & Compliance | ___________ | _________ | _________ |
| Finance (Budget Approval) | ___________ | _________ | _________ |

---

**ADR Status**: Proposed
**Next Review Date**: 2025-11-22
**Supersedes**: None
**Superseded By**: None

---

**END OF ADR-001**
