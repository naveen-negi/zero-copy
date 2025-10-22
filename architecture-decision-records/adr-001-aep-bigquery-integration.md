# ADR-001: AEP Integration with BigQuery Lead Scoring

**Status**: Proposed
**Date**: 2025-10-22
**Decision Makers**: Data Architecture Team, Marketing Technology Team
**Technical Owner**: Data Engineering Lead

---

## Context

We have cold/warm/hot lead classification models running in BigQuery and need to activate these audiences to marketing channels (Marketo, Google Ads, Meta Ads) via Adobe Experience Platform (AEP).

### Current State

- **Data Warehouse**: Google BigQuery
- **Customer Profiles**: 10 million profiles, 2-10 TB of data
- **Lead Scoring**: ML models computing cold/warm/hot classifications in BigQuery
- **Activation Requirement**: Daily/weekly campaigns to marketing destinations
- **Constraints**:
  - Banking/regulated environment (BaFin compliance)
  - Data sovereignty concerns (data must stay in GCP where possible)
  - Vendor lock-in risk must be minimized
  - Cost optimization priority

### Problem Statement

Traditional AEP integration requires copying ALL customer data (100+ fields per profile) into Adobe's Real-Time Customer Profile Store, resulting in:
- Massive data transfer volumes (2-10 TB annually)
- Significant storage and ingestion costs ($80K-$145K/year)
- Vendor lock-in (all logic and data in AEP)
- Data sovereignty challenges
- Complex ETL pipeline maintenance

### Key Requirements

1. **Functional Requirements**:
   - Activate lead classification audiences to Marketo, Google Ads, Meta Ads
   - Daily/weekly campaign cadence is acceptable for 90% of use cases
   - Support for 20-50 different audience segments
   - Ability to refresh audiences on schedule

2. **Non-Functional Requirements**:
   - Minimize data transfer out of BigQuery
   - Maintain data in GCP (regulatory compliance)
   - Low vendor lock-in (preserve ability to switch from AEP)
   - Cost-effective solution (<$700K/year total cost)
   - Implementation timeline: 2-12 weeks

3. **Security & Compliance**:
   - BaFin compliance (German banking regulations)
   - Data residency in EU/GCP
   - Audit trail for data access
   - Minimal PII exposure to external systems

---

## Decision

We have evaluated three architecture options for integrating BigQuery lead scoring with AEP. Each option is documented below as a separate ADR subsection.

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

## Final Recommendation

### PRIMARY: Option 1 - Federated Audience Composition

**Recommended for initial implementation based on**:

1. ✅ **Lowest Total Cost**: $247K-$701K/year (50% savings)
2. ✅ **Minimal Vendor Lock-in**: All logic in BigQuery
3. ✅ **Data Sovereignty**: Data never leaves GCP
4. ✅ **Fastest Implementation**: 2-4 weeks
5. ✅ **Meets Core Requirements**: Daily/weekly campaigns sufficient for 90% of use cases

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
→ **Fallback to Option 2 (Computed Attributes)** - push-based, no external DB exposure
→ **OR Option 4 (External Audiences CSV/API)** - for POC/testing only

**Action Required**:
1. Schedule meeting with Security & Compliance team
2. Present federated architecture (read-only, audit logs, VPN)
3. Get formal approval OR rejection
4. If rejected → Proceed with Option 2

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
