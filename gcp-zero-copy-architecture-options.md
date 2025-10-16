# GCP Zero-Copy Architecture for Adobe Experience Platform Integration

**Document Version:** 1.0
**Last Updated:** 2025-10-16
**Target Environment:** German Banking (BaFin/MaRisk/GDPR compliant)

---

## Executive Summary

This document outlines multiple architectural approaches for implementing a zero-copy integration between Google Cloud Platform (GCP) and Adobe Experience Platform (AEP) for a German banking client. The core principle: **minimize data egress from GCP while maximizing AEP's activation capabilities**.

### Key Architectural Thesis

Zero-copy doesn't mean "zero data transfer" - that's impossible if AEP needs to activate audiences. Instead, it means:

1. **Keep raw data and comprehensive profiles in GCP** (the system of record)
2. **Send only actionable signals to AEP** (segment membership, propensity scores, next-best-action recommendations)
3. **Compute everything possible in GCP** before sending results to AEP
4. **Use reference-based patterns** where AEP triggers actions but GCP remains the data authority

**Critical Challenge to Address Upfront:** Why are you using AEP at all if you're trying to minimize data transfer? AEP is fundamentally a customer data platform designed to ingest, unify, and activate customer data. A true zero-copy architecture suggests you should be questioning whether AEP is the right tool, or whether you should be building activation capabilities directly on GCP using tools like Google Ads Data Hub, DV360 integration, or custom activation via Cloud Functions.

That said, if the business requirement for AEP is fixed (existing contracts, specific Adobe ecosystem needs), here's how to architect this optimally.

---

## 1. GCP Foundation: Data Platform Architecture

### 1.1 Core Data Storage Strategy

For a German banking environment with zero-copy principles, I recommend a **medallion architecture** on GCP with strict data residency controls:

#### Architecture: Bronze → Silver → Gold

```
┌─────────────────────────────────────────────────────────────────┐
│                       BRONZE LAYER (Raw)                        │
│  Cloud Storage (europe-west3) - Regional Bucket                 │
│  - Raw event streams from sources                               │
│  - Immutable, append-only                                       │
│  - Lifecycle: 90 days hot → Nearline → Coldline → Archive      │
│  - Format: Avro/Parquet with schema evolution support          │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                    SILVER LAYER (Cleansed)                      │
│  BigQuery (europe-west3) - Multi-region for HA                 │
│  - Validated, deduplicated, normalized data                     │
│  - Customer 360 tables with slowly changing dimensions (SCD2)   │
│  - Event tables partitioned by event_timestamp                  │
│  - Clustered by customer_id, event_type                         │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                     GOLD LAYER (Analytics)                      │
│  BigQuery (europe-west3) - Materialized Views                  │
│  - Customer aggregations (RFM, lifetime value, propensity)      │
│  - Lead scoring tables (Cold/Warm/Hot classification)           │
│  - Campaign response history                                    │
│  - Feature store for ML (pre-computed features)                 │
└─────────────────────────────────────────────────────────────────┘
```

**Why BigQuery as the Core Warehouse:**

- **Serverless and elastic:** No capacity planning, scales to petabytes
- **Separation of storage and compute:** Pay only for data stored and queries run
- **Native ML capabilities:** BigQuery ML for in-database model training
- **Excellent for analytical workloads:** Your lead scoring and segmentation queries will fly
- **Regional data residency:** europe-west3 (Frankfurt) keeps data in Germany
- **Mature audit logging:** Essential for BaFin compliance

**Regional Choice - Critical for German Banking:**
- **Primary:** `europe-west3` (Frankfurt, Germany) - for data residency compliance
- **DO NOT use:** Multi-region EU (includes UK post-Brexit, potential non-EU processing)
- **Backup/DR:** `europe-west1` (Belgium) if cross-region HA is required, document in data processing agreements

### 1.2 Event Streaming Architecture

For real-time lead scoring and campaign triggering, you need a robust event backbone:

```
┌──────────────────┐
│  Event Sources   │
│ - Web/Mobile     │
│ - Banking Apps   │──┐
│ - CRM Systems    │  │
│ - Transactions   │  │
└──────────────────┘  │
                      ↓
              ┌──────────────┐
              │   Pub/Sub    │ (europe-west3)
              │  Topic Tiers │
              │  - raw.*     │
              │  - enriched.*│
              │  - scored.*  │
              └──────────────┘
                      ↓
         ┌────────────┴────────────┐
         ↓                         ↓
┌─────────────────┐       ┌─────────────────┐
│  Dataflow Jobs  │       │  BigQuery       │
│  (Streaming)    │       │  Streaming      │
│                 │       │  Inserts        │
│ - Enrichment    │       └─────────────────┘
│ - Validation    │
│ - Routing       │
└─────────────────┘
         ↓
┌─────────────────┐
│  Cloud Storage  │
│  (Landing Zone) │
│  + BigQuery     │
│  (Analytical)   │
└─────────────────┘
```

**Pub/Sub Topic Design for Lead Scoring:**

1. **`banking-events-raw`**: All customer interactions (page views, transactions, app events)
2. **`banking-events-enriched`**: Events joined with customer profile data
3. **`banking-leads-scored`**: Lead classification changes (Cold→Warm, Warm→Hot)
4. **`aep-activation-commands`**: Instructions to send to AEP (minimal payload)

**Why Pub/Sub over Kafka (Cloud-managed or self-hosted):**
- **Fully managed, true serverless:** No cluster sizing, no rebalancing hell
- **Global message routing:** Can route to multiple regions if needed (though keep in europe-west3 for compliance)
- **At-least-once delivery guarantees:** With message deduplication patterns in Dataflow
- **Native GCP integration:** Trivial to connect to Dataflow, Cloud Functions, BigQuery
- **Cost-effective at scale:** Pay per GB ingested/delivered, no idle cluster costs

**Caveat:** If you need exactly-once semantics end-to-end with complex stream processing, Dataflow with Pub/Sub achieves this, but it's more expensive than batch. Budget €0.05-0.10 per GB processed for streaming Dataflow workers.

### 1.3 Reference Data Pattern for Zero-Copy

Here's a key pattern for minimizing data sent to AEP:

**Instead of sending:**
```json
{
  "customer_id": "DE12345",
  "attributes": {
    "account_balance": 125000,
    "transaction_history": [...],
    "credit_score": 780,
    "product_holdings": [...]
  }
}
```

**Send only:**
```json
{
  "customer_id": "DE12345",
  "segment": "hot_lead_commercial_banking",
  "propensity_score": 0.87,
  "recommended_product": "business_credit_line",
  "data_reference": "gs://bank-profiles-eu/customers/DE12345/profile.json",
  "expires_at": "2025-10-17T10:00:00Z"
}
```

**The reference data stays in GCP.** AEP uses it for activation decisions, but if AEP needs to "enrich" its understanding, it calls back to GCP APIs (see Section 2).

**Storage for Reference Data:**
- **Cloud Storage signed URLs:** Generate time-limited, read-only URLs for specific customer profiles
- **Firestore in Native mode (europe-west3):** For low-latency profile lookups via API
- **BigQuery external tables:** If AEP has BigQuery connector (unlikely, but possible)

---

## 2. GCP-to-AEP Integration Patterns

### 2.1 Pattern A: Event-Driven Activation (Recommended for Real-Time)

**Best for:** Hot lead detection, transaction-triggered campaigns, real-time propensity scoring

```
┌──────────────┐      ┌─────────────┐      ┌──────────────┐      ┌─────────┐
│   BigQuery   │──┬──→│   Pub/Sub   │──┬──→│Cloud Function│─────→│   AEP   │
│Lead Scoring  │  │   │ scored.*    │  │   │ (Filtering)  │ HTTP │ Profile │
│   Queries    │  │   └─────────────┘  │   └──────────────┘ POST │   API   │
└──────────────┘  │                    │                          └─────────┘
                  │   ┌─────────────┐  │
                  └──→│  Dataflow   │──┘
                      │ (Streaming) │
                      └─────────────┘
```

**Implementation Details:**

1. **Scoring Pipeline (Dataflow Streaming or Scheduled BigQuery):**
   - Continuously score leads based on real-time events
   - Write score changes to `banking-leads-scored` Pub/Sub topic
   - Only publish when lead status **changes** (Cold→Warm, Warm→Hot) to minimize noise

2. **Filtering & Routing (Cloud Function or Cloud Run):**
   - Subscribe to `banking-leads-scored` topic
   - Apply business rules: "Only send Hot leads to AEP if propensity > 0.75"
   - Transform to AEP's Profile API format
   - POST to AEP HTTP Streaming Ingestion API
   - **Critical:** Implement exponential backoff, dead-letter queue for failures

3. **AEP Activation:**
   - AEP receives segment membership changes
   - AEP's Real-Time CDP activates audiences to destinations (Adobe Target, email platforms, etc.)

**Code Skeleton (Cloud Function):**

```python
import functions_framework
import requests
import google.cloud.logging
from google.cloud import secretmanager

# Initialize
logging_client = google.cloud.logging.Client()
logging_client.setup_logging()
secret_client = secretmanager.SecretManagerServiceClient()

AEP_INLET_URL = "https://dcs.adobedc.net/collection/{IMS_ORG_ID}"
AEP_API_KEY = secret_client.access_secret_version(
    name="projects/PROJECT_ID/secrets/aep-api-key/versions/latest"
).payload.data.decode("UTF-8")

@functions_framework.cloud_event
def process_lead_score(cloud_event):
    """Triggered by Pub/Sub message with lead score change."""

    import base64
    import json

    # Decode Pub/Sub message
    message_data = base64.b64decode(cloud_event.data["message"]["data"]).decode()
    lead_event = json.loads(message_data)

    # Extract critical fields
    customer_id = lead_event["customer_id"]
    lead_category = lead_event["lead_category"]  # COLD, WARM, HOT
    propensity_score = lead_event["propensity_score"]
    product_recommendation = lead_event["recommended_product"]

    # Business rule: Only send Hot leads with high propensity
    if lead_category != "HOT" or propensity_score < 0.75:
        logging.info(f"Skipping customer {customer_id}: {lead_category}, score {propensity_score}")
        return

    # Transform to AEP format (minimal payload)
    aep_payload = {
        "header": {
            "schemaRef": {
                "id": "https://ns.adobe.com/{TENANT}/schemas/lead-score-schema",
                "contentType": "application/vnd.adobe.xed-full+json;version=1"
            },
            "imsOrgId": "{IMS_ORG_ID}",
            "datasetId": "{DATASET_ID}"
        },
        "body": {
            "xdmMeta": {"schemaRef": {"id": "..."}},
            "xdmEntity": {
                "_id": customer_id,
                "leadCategory": lead_category,
                "propensityScore": propensity_score,
                "recommendedProduct": product_recommendation,
                "scoredAt": lead_event["scored_at"],
                # DO NOT SEND: raw transaction data, PII beyond identifier
            }
        }
    }

    # Send to AEP with retry logic
    headers = {
        "Content-Type": "application/json",
        "x-api-key": AEP_API_KEY,
        "x-gw-ims-org-id": "{IMS_ORG_ID}"
    }

    try:
        response = requests.post(
            AEP_INLET_URL,
            json=aep_payload,
            headers=headers,
            timeout=10
        )
        response.raise_for_status()
        logging.info(f"Successfully sent lead score for {customer_id} to AEP")
    except requests.exceptions.RequestException as e:
        logging.error(f"Failed to send to AEP: {e}")
        raise  # Let Cloud Functions retry mechanism handle it
```

**Cost Analysis:**
- **Pub/Sub:** ~€0.040 per GB ingested, €0.080 per GB delivered
- **Cloud Functions (2nd gen):** €0.40 per million invocations + compute time
- **Egress to AEP (Adobe's infrastructure, likely US/EU):** €0.085-0.12 per GB (GCP premium network tier)

**For 1 million lead score updates/day (assuming 2KB payloads):**
- Pub/Sub: ~€0.24/day
- Cloud Functions: ~€0.40/day
- Egress: ~€0.17/day (2GB total)
- **Total: ~€25/month** - extremely cost-effective

**German Banking Compliance Considerations:**
- **Encryption in transit:** TLS 1.3 for all API calls to AEP
- **Audit logging:** Enable Cloud Audit Logs for Cloud Functions, log every AEP API call
- **Data minimization (GDPR):** Only send segment membership and scores, not raw PII
- **Right to be forgotten:** Implement customer_id purge logic that triggers AEP profile deletion
- **Data residency:** Cloud Functions must run in europe-west3, but egress to AEP (external) is acceptable if covered by SCCs (Standard Contractual Clauses) with Adobe

### 2.2 Pattern B: API-Based Pull (AEP Queries GCP)

**Best for:** On-demand profile enrichment, AEP-initiated workflows

Instead of pushing data to AEP, expose GCP data via secure APIs that AEP calls when needed.

```
┌─────────────┐                    ┌──────────────────┐
│     AEP     │────HTTP GET───────→│   Cloud Run      │
│ (Activation)│  (OAuth 2.0)       │  (Profile API)   │
│             │←────JSON───────────│                  │
└─────────────┘                    └──────────────────┘
                                            ↓
                                   ┌──────────────────┐
                                   │    BigQuery      │
                                   │  (Customer 360)  │
                                   └──────────────────┘
```

**Implementation:**

Deploy a Cloud Run service (europe-west3) with these endpoints:

1. **GET /customers/{customer_id}/profile**
   - Returns current lead score, segment, propensity
   - Does NOT return raw PII or transaction history
   - Implements rate limiting (Cloud Armor)

2. **GET /customers/{customer_id}/recommendations**
   - Returns next-best-action for the customer
   - Based on real-time BigQuery query or cached in Firestore

3. **POST /customers/batch-scores**
   - Accepts list of customer IDs from AEP
   - Returns lead scores for batch processing
   - Max 1000 customers per request

**Authentication:**
- **OAuth 2.0 with Workload Identity Federation:** AEP authenticates as a service account
- **API Keys (fallback):** Store in Secret Manager, rotate every 90 days
- **Cloud Armor:** Rate limiting (100 requests/second per AEP tenant), DDoS protection

**Code Skeleton (Cloud Run - FastAPI):**

```python
from fastapi import FastAPI, HTTPException, Depends, Security
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from google.cloud import bigquery
from google.auth import default
import logging

app = FastAPI(title="GCP Customer Profile API for AEP")
security = HTTPBearer()
bq_client = bigquery.Client(project="bank-project", location="europe-west3")

def verify_token(credentials: HTTPAuthorizationCredentials = Security(security)):
    """Verify OAuth 2.0 token from AEP."""
    # Implement Google OAuth 2.0 verification
    # or validate AEP-specific API key
    token = credentials.credentials
    # ... verification logic ...
    return {"client": "aep", "validated": True}

@app.get("/customers/{customer_id}/profile")
async def get_customer_profile(customer_id: str, auth=Depends(verify_token)):
    """Return minimal customer profile for AEP activation."""

    # Query BigQuery for current lead score
    query = f"""
        SELECT
            customer_id,
            lead_category,
            propensity_score,
            recommended_product,
            last_updated
        FROM `bank-project.gold.customer_lead_scores`
        WHERE customer_id = @customer_id
        LIMIT 1
    """

    job_config = bigquery.QueryJobConfig(
        query_parameters=[
            bigquery.ScalarQueryParameter("customer_id", "STRING", customer_id)
        ]
    )

    query_job = bq_client.query(query, job_config=job_config)
    results = list(query_job.result())

    if not results:
        raise HTTPException(status_code=404, detail="Customer not found")

    row = results[0]

    # Return minimal payload
    return {
        "customer_id": row.customer_id,
        "lead_category": row.lead_category,
        "propensity_score": float(row.propensity_score),
        "recommended_product": row.recommended_product,
        "last_updated": row.last_updated.isoformat(),
        # NO raw PII, NO transaction history
    }

@app.post("/customers/batch-scores")
async def batch_customer_scores(request: dict, auth=Depends(verify_token)):
    """Batch endpoint for AEP to request multiple customer scores."""

    customer_ids = request.get("customer_ids", [])

    if len(customer_ids) > 1000:
        raise HTTPException(status_code=400, detail="Max 1000 customers per batch")

    # Use parameterized query with UNNEST for batch lookup
    query = """
        SELECT
            customer_id,
            lead_category,
            propensity_score,
            recommended_product
        FROM `bank-project.gold.customer_lead_scores`
        WHERE customer_id IN UNNEST(@customer_ids)
    """

    job_config = bigquery.QueryJobConfig(
        query_parameters=[
            bigquery.ArrayQueryParameter("customer_ids", "STRING", customer_ids)
        ]
    )

    query_job = bq_client.query(query, job_config=job_config)
    results = [dict(row) for row in query_job.result()]

    return {
        "count": len(results),
        "profiles": results
    }
```

**Deployment:**

```bash
# Deploy Cloud Run in europe-west3 with IAM restrictions
gcloud run deploy customer-profile-api \
  --source . \
  --region=europe-west3 \
  --platform=managed \
  --no-allow-unauthenticated \
  --service-account=aep-integration-sa@bank-project.iam.gserviceaccount.com \
  --vpc-connector=aep-connector \
  --ingress=internal-and-cloud-load-balancing \
  --min-instances=1 \
  --max-instances=100 \
  --memory=2Gi \
  --cpu=2
```

**Cost Analysis (API Pull Pattern):**
- **Cloud Run:** €0.00002400 per vCPU-second, €0.00000250 per GiB-second
- **BigQuery queries:** €5 per TB scanned (use partitioning/clustering to minimize)
- **No egress costs** (AEP pulls from GCP, ingress is free)

**For 10 million API calls/month (avg 100ms response time, 100KB response):**
- Cloud Run compute: ~€144/month
- BigQuery queries (assuming 1 GB scanned per 1000 queries): ~€50/month
- **Total: ~€200/month**

**Trade-off vs Pattern A (Push):**
- **Pro:** Zero egress costs, AEP only pulls what it needs
- **Pro:** GCP maintains full control, can implement fine-grained access controls
- **Con:** Higher latency (AEP must wait for GCP response)
- **Con:** More complex for AEP integration (they need to implement pull logic)
- **Con:** Requires robust authentication and rate limiting

**When to use this pattern:** If AEP usage is unpredictable or sporadic, or if compliance requires you to maintain strict control over data access (every query logged, attributed to specific AEP use case).

### 2.3 Pattern C: Batch Synchronization (Lowest Cost, Acceptable Latency)

**Best for:** Daily/hourly segment updates, non-real-time campaigns

```
┌──────────────┐      ┌─────────────┐      ┌──────────────┐      ┌─────────┐
│  Cloud       │──┬──→│Cloud Storage│─────→│ Cloud Run    │─────→│   AEP   │
│  Scheduler   │  │   │ (CSV/JSON)  │      │ (Batch       │ SFTP │  Batch  │
│  (Cron)      │  │   └─────────────┘      │  Uploader)   │  or  │ Ingress │
└──────────────┘  │                        └──────────────┘ HTTP │         │
                  │                                               └─────────┘
                  │   ┌─────────────┐
                  └──→│  BigQuery   │
                      │  Scheduled  │
                      │   Queries   │
                      └─────────────┘
```

**Implementation:**

1. **Scheduled BigQuery Query (runs daily at 2 AM CET):**

```sql
-- Export changed lead scores to Cloud Storage
EXPORT DATA OPTIONS(
  uri='gs://bank-aep-exports-eu/lead-scores/export_*.csv',
  format='CSV',
  overwrite=true,
  header=true,
  compression='GZIP'
) AS
SELECT
    customer_id,
    lead_category,
    propensity_score,
    recommended_product,
    CURRENT_TIMESTAMP() as exported_at
FROM `bank-project.gold.customer_lead_scores`
WHERE last_updated >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 24 HOUR)
  AND lead_category IN ('WARM', 'HOT')  -- Only export actionable leads
ORDER BY propensity_score DESC
LIMIT 100000;  -- Cap at 100k leads per day to control egress
```

2. **Cloud Function triggered by Cloud Storage finalize event:**
   - Reads exported CSV from Cloud Storage
   - Transforms to AEP batch ingestion format (JSON Lines)
   - Uploads to AEP via Bulk Ingestion API or SFTP

3. **AEP processes batch overnight**
   - Segments updated by morning
   - Campaigns activated for the day

**Cost Analysis:**
- **BigQuery query:** €5 per TB scanned (with partitioning, likely <10 GB/day = €0.05/day)
- **Cloud Storage:** €0.020 per GB per month
- **Egress (assuming 100k records × 1KB = 100 MB/day):** €0.30/month
- **Cloud Function:** €0.40 per million invocations (~€0.01/day)
- **Total: ~€10/month** - cheapest option by far

**Trade-offs:**
- **Pro:** Extremely cost-effective, simple to implement
- **Pro:** Easy to audit (export files retained in Cloud Storage for compliance)
- **Con:** 24-hour latency not suitable for real-time use cases (transaction fraud, hot lead instant follow-up)
- **Con:** All-or-nothing (can't incrementally update single customer profiles)

**When to use:** For non-urgent campaigns (weekly newsletter segmentation, monthly product recommendations), or as a fallback/reconciliation mechanism alongside real-time patterns.

### 2.4 Pattern Comparison Matrix

| Criterion | Event-Driven (A) | API Pull (B) | Batch Sync (C) |
|-----------|------------------|--------------|----------------|
| **Latency** | <1 second | <500ms per request | 24 hours |
| **Cost (monthly, 1M updates)** | ~€25 | ~€200 | ~€10 |
| **Complexity** | Medium | High | Low |
| **Egress costs** | Moderate | Zero (AEP pulls) | Low (batch) |
| **Compliance audit** | Good (event logs) | Excellent (per-request logs) | Excellent (batch manifests) |
| **Scalability** | Excellent (Pub/Sub) | Good (Cloud Run autoscale) | Excellent (BigQuery) |
| **Failure handling** | Retry + DLQ | AEP retries | Manual rerun |
| **Recommended for** | Hot leads, real-time | On-demand enrichment | Daily campaigns |

**My opinionated recommendation:** Start with **Pattern A (Event-Driven)** for hot lead activation and **Pattern C (Batch)** for daily segment synchronization. This hybrid approach balances cost, latency, and complexity. Only implement Pattern B (API Pull) if AEP specifically requires on-demand profile enrichment (rare in practice).

---

## 3. Lead Scoring & Classification on GCP

### 3.1 ML Pipeline Architecture for Lead Scoring

Based on the Cold/Warm/Hot framework from your requirements, here's a production-grade ML architecture on GCP:

```
┌─────────────────────────────────────────────────────────────────┐
│                     FEATURE ENGINEERING                         │
│  BigQuery (Scheduled Queries) → Feature Store Tables            │
│  - RFM metrics (Recency, Frequency, Monetary value)             │
│  - Engagement scores (page views, app opens, RM interactions)   │
│  - Product affinity (which products customer browses)           │
│  - Transaction velocity (growth in balance/transactions)        │
│  - Credit profile strength                                      │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                    MODEL TRAINING (Vertex AI)                   │
│  - Algorithm: XGBoost or TensorFlow (tabular data)              │
│  - Target: Multi-class classification (Cold/Warm/Hot)           │
│  - Training frequency: Weekly (AutoML or custom training)       │
│  - Hyperparameter tuning: Vertex AI Hyperparameter Tuning      │
│  - Model versioning: Vertex AI Model Registry                   │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                    MODEL SERVING (2 Options)                    │
│  Option 1: Vertex AI Prediction Endpoints (real-time)          │
│  Option 2: BigQuery ML PREDICT (batch scoring)                 │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│               SCORE STORAGE & CHANGE DETECTION                  │
│  BigQuery table: customer_lead_scores (Gold layer)             │
│  - Compare new scores to previous scores                        │
│  - Publish CHANGED scores to Pub/Sub (see Section 2.1)         │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 Feature Engineering for Lead Scoring

Based on the Cold/Warm/Hot definitions in your screenshot, here are the critical features to engineer:

**Cold Lead Indicators:**
- Low engagement: `days_since_last_login > 30`
- Weak fit: `credit_score < threshold`, `account_balance < threshold`
- Minimal contact: `rm_interactions_last_90d = 0`
- Low transaction velocity: `transaction_growth_30d < 0`

**Warm Lead Indicators:**
- Recent interaction: `days_since_rm_contact < 14`
- Growing engagement: `mobile_app_sessions_last_7d > 3`
- Product browsing: `product_detail_page_views_last_7d > 0`
- Balance growth: `account_balance_growth_30d > 0.05` (5% growth)

**Hot Lead Indicators:**
- Explicit inquiry: `callback_request = TRUE` or `credit_application_started = TRUE`
- High intent: `product_comparison_tool_used = TRUE`
- Strong credit profile: `credit_score > 750`
- High value: `projected_lifetime_value > 50000`

**BigQuery Feature Engineering Query:**

```sql
-- Create feature table for lead scoring
-- Runs daily via Cloud Scheduler → BigQuery Data Transfer Service

CREATE OR REPLACE TABLE `bank-project.gold.lead_scoring_features` AS
WITH customer_base AS (
  SELECT DISTINCT customer_id
  FROM `bank-project.silver.customers`
  WHERE customer_status = 'ACTIVE'
    AND country_code = 'DE'
),

engagement_features AS (
  SELECT
    customer_id,
    DATE_DIFF(CURRENT_DATE(), MAX(event_date), DAY) as days_since_last_interaction,
    COUNT(DISTINCT CASE WHEN event_type = 'page_view' THEN event_date END) as page_views_last_30d,
    COUNT(DISTINCT CASE WHEN event_type = 'mobile_app_open' THEN event_date END) as app_sessions_last_30d,
    COUNT(DISTINCT CASE WHEN event_type = 'product_detail_view' THEN event_date END) as product_views_last_30d,
    COUNT(DISTINCT CASE WHEN event_type = 'calculator_usage' THEN event_date END) as calculator_uses_last_30d
  FROM `bank-project.silver.customer_events`
  WHERE event_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
  GROUP BY customer_id
),

rm_interaction_features AS (
  SELECT
    customer_id,
    DATE_DIFF(CURRENT_DATE(), MAX(interaction_date), DAY) as days_since_rm_contact,
    COUNT(*) as rm_interactions_last_90d,
    MAX(CASE WHEN interaction_type = 'callback_request' THEN 1 ELSE 0 END) as has_callback_request
  FROM `bank-project.silver.rm_interactions`
  WHERE interaction_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
  GROUP BY customer_id
),

financial_features AS (
  SELECT
    customer_id,
    current_balance,
    credit_score,
    -- Growth metrics
    SAFE_DIVIDE(
      current_balance - LAG(current_balance) OVER (PARTITION BY customer_id ORDER BY snapshot_date),
      LAG(current_balance) OVER (PARTITION BY customer_id ORDER BY snapshot_date)
    ) as balance_growth_rate_30d,
    COUNT(DISTINCT product_id) as num_products_held
  FROM `bank-project.silver.customer_financials`
  WHERE snapshot_date = CURRENT_DATE()
  GROUP BY customer_id, current_balance, credit_score, snapshot_date
),

application_features AS (
  SELECT
    customer_id,
    MAX(CASE WHEN application_status = 'STARTED' THEN 1 ELSE 0 END) as has_started_application,
    MAX(CASE WHEN application_status = 'SUBMITTED' THEN 1 ELSE 0 END) as has_submitted_application
  FROM `bank-project.silver.product_applications`
  WHERE application_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
  GROUP BY customer_id
)

SELECT
  cb.customer_id,

  -- Engagement features
  COALESCE(ef.days_since_last_interaction, 999) as days_since_last_interaction,
  COALESCE(ef.page_views_last_30d, 0) as page_views_last_30d,
  COALESCE(ef.app_sessions_last_30d, 0) as app_sessions_last_30d,
  COALESCE(ef.product_views_last_30d, 0) as product_views_last_30d,
  COALESCE(ef.calculator_uses_last_30d, 0) as calculator_uses_last_30d,

  -- RM interaction features
  COALESCE(rm.days_since_rm_contact, 999) as days_since_rm_contact,
  COALESCE(rm.rm_interactions_last_90d, 0) as rm_interactions_last_90d,
  COALESCE(rm.has_callback_request, 0) as has_callback_request,

  -- Financial features
  COALESCE(ff.current_balance, 0) as current_balance,
  COALESCE(ff.credit_score, 0) as credit_score,
  COALESCE(ff.balance_growth_rate_30d, 0) as balance_growth_rate_30d,
  COALESCE(ff.num_products_held, 0) as num_products_held,

  -- Application features
  COALESCE(af.has_started_application, 0) as has_started_application,
  COALESCE(af.has_submitted_application, 0) as has_submitted_application,

  CURRENT_TIMESTAMP() as feature_timestamp

FROM customer_base cb
LEFT JOIN engagement_features ef USING (customer_id)
LEFT JOIN rm_interaction_features rm USING (customer_id)
LEFT JOIN financial_features ff USING (customer_id)
LEFT JOIN application_features af USING (customer_id);
```

**Schedule this query to run daily at 1 AM CET:**

```bash
# Create scheduled query via gcloud
bq query \
  --use_legacy_sql=false \
  --destination_table=bank-project:gold.lead_scoring_features \
  --display_name="Daily Lead Scoring Feature Engineering" \
  --schedule="0 1 * * *" \
  --location=europe-west3 \
  --time_zone="Europe/Berlin" \
  "$(cat feature_engineering.sql)"
```

### 3.3 Model Training: BigQuery ML vs Vertex AI

**Option 1: BigQuery ML (Recommended for MVP/Proof of Concept)**

**Why BigQuery ML:**
- Train models directly in SQL (no Python/TensorFlow expertise required)
- Data never leaves BigQuery (compliance-friendly)
- Extremely fast iteration (train model in minutes)
- Good enough for tabular classification (XGBoost, Logistic Regression)

**Training Query:**

```sql
-- Train lead classification model using BigQuery ML
-- Multi-class logistic regression

CREATE OR REPLACE MODEL `bank-project.ml_models.lead_classifier_v1`
OPTIONS(
  model_type='LOGISTIC_REG',
  auto_class_weights=TRUE,  -- Handle class imbalance
  input_label_cols=['lead_category'],
  max_iterations=50,
  l1_reg=0.01,
  l2_reg=0.01,
  data_split_method='RANDOM',
  data_split_eval_fraction=0.2
) AS
SELECT
  -- Features (from feature engineering query)
  days_since_last_interaction,
  page_views_last_30d,
  app_sessions_last_30d,
  product_views_last_30d,
  calculator_uses_last_30d,
  days_since_rm_contact,
  rm_interactions_last_90d,
  has_callback_request,
  current_balance,
  credit_score,
  balance_growth_rate_30d,
  num_products_held,
  has_started_application,
  has_submitted_application,

  -- Label (historical lead category from past campaigns)
  historical_lead_category as lead_category

FROM `bank-project.gold.lead_scoring_features_historical`
WHERE feature_timestamp >= '2024-01-01'  -- 1 year of training data
  AND historical_lead_category IS NOT NULL;
```

**Model Evaluation:**

```sql
-- Evaluate model performance
SELECT
  *
FROM ML.EVALUATE(MODEL `bank-project.ml_models.lead_classifier_v1`,
  (
    SELECT * FROM `bank-project.gold.lead_scoring_features_historical`
    WHERE feature_timestamp >= '2024-01-01'
      AND historical_lead_category IS NOT NULL
  )
);

-- Expected output: precision, recall, accuracy, f1_score, roc_auc
```

**Batch Scoring (Daily):**

```sql
-- Score all active customers daily
CREATE OR REPLACE TABLE `bank-project.gold.customer_lead_scores` AS
SELECT
  customer_id,
  predicted_lead_category as lead_category,
  predicted_lead_category_probs[OFFSET(0)].prob as cold_probability,
  predicted_lead_category_probs[OFFSET(1)].prob as warm_probability,
  predicted_lead_category_probs[OFFSET(2)].prob as hot_probability,
  -- Use HOT probability as propensity score
  predicted_lead_category_probs[OFFSET(2)].prob as propensity_score,
  CURRENT_TIMESTAMP() as scored_at
FROM ML.PREDICT(MODEL `bank-project.ml_models.lead_classifier_v1`,
  (
    SELECT * FROM `bank-project.gold.lead_scoring_features`
  )
);
```

**Cost:** BigQuery ML training is charged at standard query pricing (~€5 per TB scanned). For a feature table with 1 million rows × 20 columns, training costs <€1 per iteration.

**Option 2: Vertex AI (Recommended for Production/Advanced Models)**

**Why Vertex AI:**
- More sophisticated algorithms (AutoML Tables, custom TensorFlow/PyTorch)
- Better hyperparameter tuning
- Real-time prediction endpoints (sub-100ms latency)
- MLOps features: model monitoring, drift detection, A/B testing
- Vertex AI Feature Store for online/offline feature serving

**Vertex AI Pipeline (using Kubeflow Pipelines DSL):**

```python
# vertex_ai_lead_scoring_pipeline.py
from kfp.v2 import dsl
from kfp.v2.dsl import component, Dataset, Model, Output, Input
from google.cloud import aiplatform

PROJECT_ID = "bank-project"
REGION = "europe-west3"
BUCKET = "gs://bank-ml-artifacts-eu"

@component(
    base_image="gcr.io/deeplearning-platform-release/tf2-cpu.2-11:latest",
    packages_to_install=["google-cloud-bigquery", "pandas", "scikit-learn"]
)
def extract_features(
    project_id: str,
    dataset_id: str,
    table_id: str,
    output_dataset: Output[Dataset]
):
    """Extract features from BigQuery to CSV."""
    from google.cloud import bigquery
    import pandas as pd

    client = bigquery.Client(project=project_id, location="europe-west3")

    query = f"""
    SELECT * FROM `{project_id}.{dataset_id}.{table_id}`
    WHERE feature_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 365 DAY)
    """

    df = client.query(query).to_dataframe()
    df.to_csv(output_dataset.path, index=False)
    print(f"Extracted {len(df)} rows to {output_dataset.path}")

@component(
    base_image="gcr.io/deeplearning-platform-release/tf2-cpu.2-11:latest",
    packages_to_install=["google-cloud-aiplatform", "xgboost", "scikit-learn"]
)
def train_xgboost_model(
    training_data: Input[Dataset],
    model_artifact: Output[Model],
    learning_rate: float = 0.1,
    max_depth: int = 6
):
    """Train XGBoost model for lead classification."""
    import pandas as pd
    import xgboost as xgb
    from sklearn.model_selection import train_test_split
    from sklearn.metrics import classification_report
    import pickle

    # Load data
    df = pd.read_csv(training_data.path)

    # Separate features and labels
    label_col = 'lead_category'
    X = df.drop(columns=[label_col, 'customer_id', 'feature_timestamp'])
    y = df[label_col].map({'COLD': 0, 'WARM': 1, 'HOT': 2})

    # Train/test split
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42, stratify=y
    )

    # Train model
    model = xgb.XGBClassifier(
        objective='multi:softmax',
        num_class=3,
        learning_rate=learning_rate,
        max_depth=max_depth,
        n_estimators=100,
        random_state=42
    )

    model.fit(X_train, y_train)

    # Evaluate
    y_pred = model.predict(X_test)
    print(classification_report(y_test, y_pred, target_names=['COLD', 'WARM', 'HOT']))

    # Save model
    with open(model_artifact.path + '/model.pkl', 'wb') as f:
        pickle.dump(model, f)

    print(f"Model saved to {model_artifact.path}")

@component(
    base_image="gcr.io/google.com/cloudsdktool/cloud-sdk:latest",
    packages_to_install=["google-cloud-aiplatform"]
)
def deploy_model_to_endpoint(
    project_id: str,
    region: str,
    model_artifact: Input[Model],
    endpoint_display_name: str = "lead-scoring-endpoint"
):
    """Deploy model to Vertex AI Prediction Endpoint."""
    from google.cloud import aiplatform

    aiplatform.init(project=project_id, location=region)

    # Upload model to Vertex AI Model Registry
    uploaded_model = aiplatform.Model.upload(
        display_name="lead-classifier-xgboost",
        artifact_uri=model_artifact.uri,
        serving_container_image_uri="europe-docker.pkg.dev/vertex-ai/prediction/xgboost-cpu.1-6:latest"
    )

    # Create or get endpoint
    endpoints = aiplatform.Endpoint.list(
        filter=f'display_name="{endpoint_display_name}"',
        order_by="create_time desc"
    )

    if endpoints:
        endpoint = endpoints[0]
    else:
        endpoint = aiplatform.Endpoint.create(display_name=endpoint_display_name)

    # Deploy model to endpoint
    endpoint.deploy(
        model=uploaded_model,
        deployed_model_display_name="lead-classifier-v1",
        machine_type="n1-standard-4",
        min_replica_count=1,
        max_replica_count=10,
        traffic_percentage=100
    )

    print(f"Model deployed to endpoint: {endpoint.resource_name}")

@dsl.pipeline(
    name="lead-scoring-training-pipeline",
    description="Train and deploy lead scoring model on Vertex AI"
)
def lead_scoring_pipeline(
    project_id: str = PROJECT_ID,
    region: str = REGION,
    dataset_id: str = "gold",
    table_id: str = "lead_scoring_features_historical"
):
    """End-to-end lead scoring ML pipeline."""

    # Step 1: Extract features from BigQuery
    extract_task = extract_features(
        project_id=project_id,
        dataset_id=dataset_id,
        table_id=table_id
    )

    # Step 2: Train model
    train_task = train_xgboost_model(
        training_data=extract_task.outputs['output_dataset'],
        learning_rate=0.1,
        max_depth=6
    )

    # Step 3: Deploy to endpoint
    deploy_task = deploy_model_to_endpoint(
        project_id=project_id,
        region=region,
        model_artifact=train_task.outputs['model_artifact'],
        endpoint_display_name="lead-scoring-endpoint"
    )

# Compile and run pipeline
if __name__ == "__main__":
    from kfp.v2 import compiler

    compiler.Compiler().compile(
        pipeline_func=lead_scoring_pipeline,
        package_path='lead_scoring_pipeline.json'
    )

    # Submit to Vertex AI Pipelines
    aiplatform.init(project=PROJECT_ID, location=REGION)

    job = aiplatform.PipelineJob(
        display_name="lead-scoring-training",
        template_path="lead_scoring_pipeline.json",
        pipeline_root=f"{BUCKET}/pipeline_runs",
        enable_caching=True
    )

    job.run(service_account="ml-pipeline-sa@bank-project.iam.gserviceaccount.com")
```

**Schedule pipeline to run weekly:**

```bash
# Create Cloud Scheduler job to trigger Vertex AI pipeline
gcloud scheduler jobs create http lead-scoring-weekly-training \
  --location=europe-west3 \
  --schedule="0 2 * * 0" \
  --time-zone="Europe/Berlin" \
  --uri="https://europe-west3-aiplatform.googleapis.com/v1/projects/bank-project/locations/europe-west3/pipelineJobs" \
  --http-method=POST \
  --message-body='{"displayName":"lead-scoring-training-scheduled","runtimeConfig":{...}}' \
  --oauth-service-account-email="scheduler-sa@bank-project.iam.gserviceaccount.com"
```

**Cost Analysis (Vertex AI):**
- **Training:** ~€1-5 per training run (n1-standard-4 for 1 hour)
- **Prediction endpoint:** ~€40/month per replica (24/7 uptime, n1-standard-4)
- **Vertex AI Feature Store:** €0.32 per GB per month + €0.035 per 10,000 online serving requests

**When to use Vertex AI over BigQuery ML:**
- You need <100ms real-time predictions (not batch)
- You want advanced algorithms (deep learning, AutoML)
- You need model monitoring and drift detection
- You're scoring >10 million customers per day in real-time

### 3.4 Real-Time vs Batch Scoring Architecture

**Batch Scoring (Recommended for most use cases):**

```
Cloud Scheduler (daily 2 AM)
    → BigQuery ML PREDICT query
    → Write to customer_lead_scores table
    → Compare to previous scores
    → Pub/Sub publish (only changed scores)
    → Cloud Function → AEP
```

**Latency:** 24 hours (acceptable for most campaigns)
**Cost:** ~€1/day (BigQuery query + Pub/Sub)

**Real-Time Scoring (For high-value, time-sensitive leads):**

```
Customer Event (e.g., credit application started)
    → Pub/Sub
    → Dataflow (stream processing)
    → Vertex AI Prediction Endpoint (model inference)
    → Pub/Sub (scored leads)
    → Cloud Function → AEP (immediate activation)
```

**Latency:** <500ms end-to-end
**Cost:** ~€100-200/day (Dataflow + Vertex AI endpoints)

**Hybrid Approach (Recommended):**

- **Batch scoring daily** for all 10 million customers
- **Real-time scoring** for specific triggers:
  - Credit application started
  - High-value transaction (>€50,000)
  - Callback request submitted
  - Product comparison tool used

**Dataflow Real-Time Scoring Pipeline:**

```python
# dataflow_realtime_scoring.py
import apache_beam as beam
from apache_beam.options.pipeline_options import PipelineOptions
from google.cloud import aiplatform
import json

class PredictLeadCategory(beam.DoFn):
    """Call Vertex AI Prediction Endpoint for real-time scoring."""

    def setup(self):
        """Initialize Vertex AI client."""
        self.endpoint = aiplatform.Endpoint(
            endpoint_name="projects/123/locations/europe-west3/endpoints/456"
        )

    def process(self, element):
        """Score a single customer event."""
        customer_id = element['customer_id']
        features = self._extract_features(element)

        # Call Vertex AI endpoint
        prediction = self.endpoint.predict(instances=[features])

        lead_category = prediction.predictions[0]['predicted_class']
        propensity_score = prediction.predictions[0]['probabilities'][2]  # HOT prob

        yield {
            'customer_id': customer_id,
            'lead_category': lead_category,
            'propensity_score': propensity_score,
            'scored_at': element['event_timestamp']
        }

    def _extract_features(self, event):
        """Extract features for scoring (lookup from BigQuery or cache)."""
        # Implementation: Query BigQuery for customer features
        # Or maintain feature cache in Redis/Firestore
        pass

def run_pipeline():
    """Run Dataflow streaming pipeline for real-time lead scoring."""

    pipeline_options = PipelineOptions(
        runner='DataflowRunner',
        project='bank-project',
        region='europe-west3',
        staging_location='gs://bank-dataflow-eu/staging',
        temp_location='gs://bank-dataflow-eu/temp',
        streaming=True,
        autoscaling_algorithm='THROUGHPUT_BASED',
        max_num_workers=10,
        service_account_email='dataflow-sa@bank-project.iam.gserviceaccount.com'
    )

    with beam.Pipeline(options=pipeline_options) as pipeline:
        (
            pipeline
            | 'Read from Pub/Sub' >> beam.io.ReadFromPubSub(
                subscription='projects/bank-project/subscriptions/banking-events-enriched-sub'
            )
            | 'Parse JSON' >> beam.Map(json.loads)
            | 'Filter High-Value Events' >> beam.Filter(
                lambda x: x['event_type'] in ['credit_application_started', 'callback_request']
            )
            | 'Score with Vertex AI' >> beam.ParDo(PredictLeadCategory())
            | 'Filter Hot Leads' >> beam.Filter(lambda x: x['lead_category'] == 'HOT')
            | 'Format for Pub/Sub' >> beam.Map(lambda x: json.dumps(x).encode('utf-8'))
            | 'Publish to Scored Leads Topic' >> beam.io.WriteToPubSub(
                topic='projects/bank-project/topics/banking-leads-scored'
            )
        )

if __name__ == '__main__':
    run_pipeline()
```

**Deploy Dataflow pipeline:**

```bash
python dataflow_realtime_scoring.py \
  --runner DataflowRunner \
  --project bank-project \
  --region europe-west3 \
  --streaming
```

### 3.5 Sending Only Scores to AEP (Not Raw Data)

This is the **core of the zero-copy architecture**. Here's what you send vs what you keep:

**Send to AEP (Minimal Payload):**
```json
{
  "customer_id": "DE12345",
  "lead_category": "HOT",
  "propensity_score": 0.89,
  "recommended_product": "business_credit_line",
  "recommended_campaign": "q4_commercial_banking_promo",
  "scored_at": "2025-10-16T08:30:00Z",
  "ttl": "2025-10-17T08:30:00Z"
}
```

**Keep in GCP (Never Send to AEP):**
- Raw transaction history
- Account balances
- Credit scores (aggregate into propensity_score only)
- PII beyond customer_id (email, phone, address)
- Detailed interaction logs

**AEP Activation Logic:**

AEP receives lead category changes and activates campaigns:
- **HOT lead with propensity > 0.8** → Send to Adobe Target for website personalization
- **HOT lead with business_credit_line recommendation** → Trigger email via Journey Optimizer
- **WARM lead** → Add to nurture campaign, suppress aggressive outreach

**The key insight:** AEP becomes a lightweight "activation engine," not a data warehouse. All heavy computation (feature engineering, model training, scoring) happens in GCP.

### 3.6 Triggering AEP Campaigns from GCP Scores

**Architecture:**

```
GCP Lead Score Change
    → Pub/Sub (banking-leads-scored)
    → Cloud Function (campaign_trigger)
    → AEP Campaign API (POST /campaigns/{id}/trigger)
```

**Cloud Function for Campaign Triggering:**

```python
# campaign_trigger_function.py
import functions_framework
import requests
from google.cloud import secretmanager
import logging

AEP_CAMPAIGN_API = "https://platform.adobe.io/data/core/activation/disflowprovider/campaigns"
AEP_API_KEY = "..."  # Fetch from Secret Manager

CAMPAIGN_MAPPING = {
    ('HOT', 'business_credit_line'): 'campaign_123_commercial_banking',
    ('HOT', 'investment_advisory'): 'campaign_456_wealth_management',
    ('WARM', 'savings_account'): 'campaign_789_nurture_savings',
}

@functions_framework.cloud_event
def trigger_aep_campaign(cloud_event):
    """Trigger AEP campaign based on lead score change."""

    import base64
    import json

    message_data = base64.b64decode(cloud_event.data["message"]["data"]).decode()
    score_event = json.loads(message_data)

    customer_id = score_event['customer_id']
    lead_category = score_event['lead_category']
    recommended_product = score_event['recommended_product']

    # Lookup campaign to trigger
    campaign_id = CAMPAIGN_MAPPING.get((lead_category, recommended_product))

    if not campaign_id:
        logging.info(f"No campaign mapping for {lead_category} + {recommended_product}")
        return

    # Trigger AEP campaign
    payload = {
        "profileId": customer_id,
        "campaignId": campaign_id,
        "customAttributes": {
            "propensityScore": score_event['propensity_score'],
            "recommendedProduct": recommended_product
        }
    }

    headers = {
        "Authorization": f"Bearer {AEP_API_KEY}",
        "x-api-key": "...",
        "x-gw-ims-org-id": "..."
    }

    try:
        response = requests.post(
            f"{AEP_CAMPAIGN_API}/{campaign_id}/trigger",
            json=payload,
            headers=headers,
            timeout=10
        )
        response.raise_for_status()
        logging.info(f"Triggered campaign {campaign_id} for customer {customer_id}")
    except requests.exceptions.RequestException as e:
        logging.error(f"Failed to trigger AEP campaign: {e}")
        raise
```

**This achieves the goal:** GCP computes who should be targeted (Hot lead for business credit), AEP executes the campaign (sends email, shows banner), but GCP never sends the underlying data (account balances, transaction history) to AEP.

---

## 4. Data Governance & Compliance (German Banking)

### 4.1 Regulatory Framework

Your GCP-AEP architecture must satisfy:

**BaFin (Bundesanstalt für Finanzdienstleistungsaufsicht):**
- **MaRisk (Minimum Requirements for Risk Management):** Risk-based IT controls, outsourcing governance
- **BAIT (Supervisory Requirements for IT):** Data security, business continuity, change management
- **KWG (German Banking Act):** Customer data protection, audit trails

**GDPR (General Data Protection Regulation):**
- **Data minimization (Article 5):** Only send necessary data to AEP
- **Purpose limitation:** Data used only for specified marketing purposes
- **Right to be forgotten (Article 17):** Customer data deletion in GCP AND AEP
- **Data portability (Article 20):** Customer can request their data from GCP
- **Data Processing Agreements (Article 28):** Required with Adobe for AEP

**DORA (Digital Operational Resilience Act):**
- **ICT risk management:** Monitor GCP-AEP integration for failures
- **Third-party risk:** Adobe (AEP) is a critical third-party provider
- **Incident reporting:** Report AEP outages to BaFin within 24 hours if material

### 4.2 Data Residency Requirements

**Critical Compliance Requirement:** German banking data must stay in EU/Germany unless explicitly allowed by customer consent and contracts.

**GCP Regional Configuration:**

```bash
# All resources MUST use europe-west3 (Frankfurt) or europe-west1 (Belgium)

# BigQuery dataset with location enforcement
bq mk \
  --dataset \
  --location=europe-west3 \
  --default_table_expiration=0 \
  --description="Customer data - German banking compliance" \
  bank-project:silver

# Cloud Storage bucket with regional constraint
gsutil mb \
  -l europe-west3 \
  -c STANDARD \
  --pap=enforced \
  gs://bank-data-eu/

# Pub/Sub topic (regional)
gcloud pubsub topics create banking-events-raw \
  --message-storage-policy-allowed-regions=europe-west3

# Vertex AI Prediction Endpoint (must specify region)
gcloud ai endpoints create \
  --region=europe-west3 \
  --display-name=lead-scoring-endpoint
```

**Organization Policy Constraints:**

Enforce data residency at the GCP Organization level:

```yaml
# org_policies.yaml
constraints:
  - constraint: constraints/gcp.resourceLocations
    listPolicy:
      allowedValues:
        - in:eu-locations  # Only EU regions
      deniedValues:
        - in:us-locations
        - in:asia-locations

  - constraint: constraints/storage.allowedBucketLocations
    listPolicy:
      allowedValues:
        - in:europe-west3-locations
        - in:europe-west1-locations
```

Apply via Terraform or gcloud:

```bash
gcloud resource-manager org-policies set-policy org_policies.yaml \
  --organization=123456789
```

**AEP Data Residency Challenge:**

Adobe Experience Platform may store data in US or EU regions depending on your contract. **You must:**

1. **Verify AEP deployment region** with Adobe (request EU instance)
2. **Implement Standard Contractual Clauses (SCCs)** for GDPR compliance if data leaves EU
3. **Minimize data sent to AEP** (hence zero-copy architecture) to reduce cross-border transfer risk
4. **Document data flows** in your GDPR Article 30 processing register

**If AEP is US-based (worst case):**
- Only send anonymized/pseudonymized identifiers and scores (not raw PII)
- Implement additional encryption (customer-managed encryption keys in Cloud KMS)
- Get explicit customer consent for US data transfer (marketing opt-in)

### 4.3 Encryption & Key Management

**Encryption at Rest (GCP):**

All data must be encrypted. GCP provides default encryption, but for German banking, use **Customer-Managed Encryption Keys (CMEK)** with Cloud KMS:

```bash
# Create KMS key ring in Frankfurt
gcloud kms keyrings create bank-encryption-ring \
  --location=europe-west3

# Create encryption key
gcloud kms keys create bank-data-key \
  --location=europe-west3 \
  --keyring=bank-encryption-ring \
  --purpose=encryption \
  --rotation-period=90d \
  --next-rotation-time=2025-12-01T00:00:00Z

# Grant BigQuery service account access to key
gcloud kms keys add-iam-policy-binding bank-data-key \
  --location=europe-west3 \
  --keyring=bank-encryption-ring \
  --member=serviceAccount:bq-PROJECT_NUMBER@bigquery-encryption.iam.gserviceaccount.com \
  --role=roles/cloudkms.cryptoKeyEncrypterDecrypter
```

**Use CMEK for BigQuery datasets:**

```bash
bq update \
  --default_kms_key=projects/bank-project/locations/europe-west3/keyRings/bank-encryption-ring/cryptoKeys/bank-data-key \
  bank-project:silver
```

**Use CMEK for Cloud Storage:**

```bash
gsutil kms encryption \
  -k projects/bank-project/locations/europe-west3/keyRings/bank-encryption-ring/cryptoKeys/bank-data-key \
  gs://bank-data-eu/
```

**Encryption in Transit:**

- **Within GCP:** All traffic uses Google's private network (encrypted by default)
- **GCP to AEP:** HTTPS (TLS 1.3) for all API calls
- **Verify AEP certificate:** Ensure Adobe uses valid TLS certificates

**Key Rotation:**
- Rotate CMEK keys every 90 days (automated in Cloud KMS)
- Rotate AEP API keys every 90 days (manual, set Cloud Scheduler reminder)

### 4.4 Access Controls & IAM

**Principle of Least Privilege:**

```yaml
# IAM roles for GCP-AEP integration (Terraform)

# Data Scientists: Read-only access to BigQuery
resource "google_project_iam_member" "data_scientists_bq_viewer" {
  project = "bank-project"
  role    = "roles/bigquery.dataViewer"
  member  = "group:data-scientists@bank.com"

  condition {
    title       = "EU data only"
    description = "Only access EU datasets"
    expression  = "resource.name.startsWith('projects/bank-project/datasets/silver')"
  }
}

# ML Engineers: Train models in Vertex AI
resource "google_project_iam_member" "ml_engineers_vertex" {
  project = "bank-project"
  role    = "roles/aiplatform.user"
  member  = "group:ml-engineers@bank.com"
}

# AEP Integration Service Account: Minimal permissions
resource "google_service_account" "aep_integration" {
  account_id   = "aep-integration-sa"
  display_name = "AEP Integration Service Account"
  description  = "Used by Cloud Functions to send data to AEP"
}

resource "google_project_iam_member" "aep_sa_pubsub_subscriber" {
  project = "bank-project"
  role    = "roles/pubsub.subscriber"
  member  = "serviceAccount:${google_service_account.aep_integration.email}"
}

resource "google_project_iam_member" "aep_sa_secret_accessor" {
  project = "bank-project"
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.aep_integration.email}"
}

# NO access to BigQuery data (Cloud Function only reads from Pub/Sub)
```

**VPC Service Controls:**

For maximum security, use VPC Service Controls to create a security perimeter:

```yaml
# vpc_service_controls.yaml
- name: banking_data_perimeter
  title: "German Banking Data Perimeter"
  description: "Restricts data egress from GCP"
  resources:
    - projects/bank-project
  restrictedServices:
    - bigquery.googleapis.com
    - storage.googleapis.com
    - pubsub.googleapis.com
  egressPolicies:
    - egressFrom:
        identityType: SERVICE_ACCOUNT
        identities:
          - serviceAccount:aep-integration-sa@bank-project.iam.gserviceaccount.com
      egressTo:
        operations:
          - serviceName: storage.googleapis.com
            methodSelectors:
              - method: "google.storage.objects.get"
        resources:
          - "projects/bank-project"
```

**This prevents:**
- Unauthorized data exfiltration from BigQuery
- Accidental bucket public access
- Data egress to non-approved services

### 4.5 Audit Trails & Monitoring

**Cloud Audit Logs (Always On):**

```bash
# Enable all audit log types
gcloud logging sinks create bafin-audit-logs \
  bigquery.googleapis.com/projects/bank-project/datasets/audit_logs \
  --log-filter='protoPayload.serviceName="bigquery.googleapis.com" OR protoPayload.serviceName="storage.googleapis.com" OR protoPayload.serviceName="pubsub.googleapis.com"'
```

**What to Log:**

1. **Data Access Logs:** Every BigQuery query, Cloud Storage file access
2. **Admin Activity Logs:** IAM changes, encryption key usage
3. **System Event Logs:** Dataflow pipeline starts/stops
4. **Custom Application Logs:** Every AEP API call (log request/response, customer_id, timestamp)

**BigQuery Audit Log Analysis:**

```sql
-- Query to find all BigQuery queries accessing customer PII
SELECT
  protopayload_auditlog.authenticationInfo.principalEmail as user,
  protopayload_auditlog.resourceName as table_accessed,
  protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query.query as sql_query,
  timestamp
FROM `bank-project.audit_logs.cloudaudit_googleapis_com_data_access_*`
WHERE protopayload_auditlog.serviceName = 'bigquery.googleapis.com'
  AND protopayload_auditlog.resourceName LIKE '%silver.customers%'
ORDER BY timestamp DESC
LIMIT 100;
```

**Alerting for Compliance Violations:**

```yaml
# alerting_policy.yaml (Cloud Monitoring)
- displayName: "Unauthorized BigQuery Access"
  conditions:
    - displayName: "Query on customer table by non-authorized user"
      conditionThreshold:
        filter: |
          resource.type="bigquery_resource"
          AND protoPayload.resourceName=~".*silver.customers.*"
          AND NOT protoPayload.authenticationInfo.principalEmail=~".*@bank.com"
        comparison: COMPARISON_GT
        thresholdValue: 0
        duration: 0s
  notificationChannels:
    - "projects/bank-project/notificationChannels/security-team-email"
  alertStrategy:
    autoClose: 86400s

- displayName: "High Egress to AEP"
  conditions:
    - displayName: "More than 1 GB egress to AEP in 1 hour"
      conditionThreshold:
        filter: |
          resource.type="cloud_function"
          AND resource.labels.function_name="aep-integration"
          AND metric.type="cloudfunctions.googleapis.com/function/network_egress"
        aggregations:
          - alignmentPeriod: 3600s
            perSeriesAligner: ALIGN_SUM
        comparison: COMPARISON_GT
        thresholdValue: 1073741824  # 1 GB
  notificationChannels:
    - "projects/bank-project/notificationChannels/compliance-team"
```

**BaFin-Required Documentation:**

Maintain these documents (outside GCP, in your GRC tool):

1. **Data Processing Register (GDPR Article 30):** All GCP services processing customer data
2. **Third-Party Risk Assessment:** Adobe AEP risk evaluation
3. **Data Flow Diagrams:** Visual representation of GCP→AEP data flow
4. **Incident Response Plan:** What to do if AEP is breached
5. **Audit Reports:** Quarterly review of Cloud Audit Logs, access reviews

### 4.6 Right to Be Forgotten (GDPR Article 17)

**When a customer requests deletion:**

1. **Delete from GCP:**

```sql
-- Delete customer from all tables
DELETE FROM `bank-project.silver.customers` WHERE customer_id = 'DE12345';
DELETE FROM `bank-project.silver.customer_events` WHERE customer_id = 'DE12345';
DELETE FROM `bank-project.gold.customer_lead_scores` WHERE customer_id = 'DE12345';

-- Delete from Cloud Storage (if storing customer-specific files)
-- gsutil rm -r gs://bank-data-eu/customers/DE12345/
```

2. **Delete from AEP:**

Call AEP's Privacy API:

```python
import requests

AEP_PRIVACY_API = "https://platform.adobe.io/data/core/privacy/jobs"

def delete_customer_from_aep(customer_id):
    """Submit GDPR deletion request to AEP."""

    payload = {
        "companyContexts": [{
            "namespace": "imsOrgID",
            "value": "{IMS_ORG_ID}"
        }],
        "users": [{
            "key": customer_id,
            "action": ["delete"],
            "userIDs": [{
                "namespace": "customer_id",
                "value": customer_id,
                "type": "standard"
            }]
        }],
        "regulation": "gdpr"
    }

    headers = {
        "Authorization": f"Bearer {AEP_API_KEY}",
        "x-api-key": "...",
        "x-gw-ims-org-id": "...",
        "Content-Type": "application/json"
    }

    response = requests.post(AEP_PRIVACY_API, json=payload, headers=headers)
    response.raise_for_status()

    return response.json()  # Returns job ID to track deletion status
```

3. **Log Deletion Event:**

```python
import logging
logging.info(f"GDPR deletion completed for customer_id={customer_id}, aep_job_id={job_id}")
```

**Audit Trail:** Retain logs of deletion requests for 7 years (BaFin requirement), even though customer data is deleted.

---

## 5. Cost Optimization

### 5.1 Minimizing Data Egress from GCP to AEP

**Egress pricing (GCP to internet, which includes AEP):**
- First 1 GB/month: Free
- 1 GB - 10 TB: €0.085 per GB (premium tier)
- 10 TB - 150 TB: €0.065 per GB
- 150 TB+: €0.045 per GB

**Cost Optimization Strategies:**

1. **Send Only Deltas (Not Full Profiles):**

Instead of sending complete customer profiles daily (wasteful), send only changes:

```sql
-- Identify customers whose lead category CHANGED in last 24 hours
SELECT
  curr.customer_id,
  curr.lead_category,
  curr.propensity_score
FROM `bank-project.gold.customer_lead_scores` curr
LEFT JOIN `bank-project.gold.customer_lead_scores_yesterday` prev
  ON curr.customer_id = prev.customer_id
WHERE curr.lead_category != prev.lead_category
  OR ABS(curr.propensity_score - prev.propensity_score) > 0.1;
```

**Savings:** If only 1% of customers change categories daily (100k out of 10M), you send 100k updates instead of 10M. At 2KB per update, that's 200 MB vs 20 GB → **99% egress reduction**.

2. **Compress Payloads:**

Always use gzip compression for API calls:

```python
import gzip
import requests

def send_to_aep_compressed(payload):
    """Send compressed payload to AEP."""

    payload_json = json.dumps(payload).encode('utf-8')
    payload_gzipped = gzip.compress(payload_json)

    headers = {
        "Content-Encoding": "gzip",
        "Content-Type": "application/json",
        # ... other headers
    }

    response = requests.post(AEP_INLET_URL, data=payload_gzipped, headers=headers)
    return response
```

**Savings:** Typically 70-80% compression ratio for JSON. 1 GB uncompressed → 250 MB compressed = €0.064 saved per GB.

3. **Batch Instead of Real-Time (Where Acceptable):**

As shown in Section 2.3, batch synchronization costs 96% less than real-time (€10/month vs €250/month).

**Decision Tree:**
- Hot leads requiring <5 min action (callback requests): Real-time
- Warm leads for nurture campaigns: Daily batch
- Cold leads for quarterly re-engagement: Weekly batch

4. **Use Standard Tier Networking (If AEP Latency Acceptable):**

GCP offers two network service tiers:
- **Premium (default):** €0.085/GB, uses Google's global network (low latency)
- **Standard:** €0.045/GB, uses public internet (higher latency)

For non-critical batch exports to AEP:

```bash
# Create Cloud NAT with standard tier for Cloud Functions
gcloud compute routers create aep-router \
  --network=default \
  --region=europe-west3

gcloud compute routers nats create aep-nat \
  --router=aep-router \
  --region=europe-west3 \
  --nat-all-subnet-ip-ranges \
  --network-tier=STANDARD  # Use standard tier (cheaper egress)
```

**Caveat:** Standard tier has no SLA for latency or packet loss. Only use for batch, non-urgent exports.

5. **Negotiate with Adobe for Reverse ETL:**

**Challenge the architecture:** Ask Adobe if AEP can pull data from GCP (Pattern B in Section 2.2) instead of GCP pushing. This eliminates egress costs entirely (GCP ingress is free).

If Adobe resists, make the business case: "We're sending 10 TB/month to AEP at €850/month egress cost. If AEP pulls from our GCP API, we save €10k/year and you get fresher data on-demand."

### 5.2 Efficient Use of BigQuery

**Cost Model:**
- **Storage:** €0.020 per GB per month (active), €0.010 per GB per month (long-term storage, 90+ days untouched)
- **Queries:** €5.00 per TB scanned
- **Streaming inserts:** €0.05 per GB

**Optimization Strategies:**

1. **Partition Tables by Date:**

```sql
-- Create partitioned table (only scans relevant partitions)
CREATE TABLE `bank-project.silver.customer_events` (
  customer_id STRING,
  event_type STRING,
  event_timestamp TIMESTAMP,
  event_data JSON
)
PARTITION BY DATE(event_timestamp)
CLUSTER BY customer_id, event_type
OPTIONS(
  partition_expiration_days=730,  -- Auto-delete partitions older than 2 years
  require_partition_filter=true   -- Force queries to specify partition filter
);
```

**Query optimization:**

```sql
-- BAD: Scans entire table (expensive)
SELECT * FROM `bank-project.silver.customer_events`
WHERE event_type = 'credit_application';

-- GOOD: Uses partition filter (scans only 7 days)
SELECT * FROM `bank-project.silver.customer_events`
WHERE DATE(event_timestamp) >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
  AND event_type = 'credit_application';
```

**Cost Savings:** If table has 2 years of data (730 GB), bad query costs €3.65. Good query (7 days = 7 GB) costs €0.035 → **99% savings**.

2. **Use Materialized Views for Repeated Queries:**

If you're scoring leads daily and always need the same feature aggregations:

```sql
-- Create materialized view (precomputed, auto-refreshed)
CREATE MATERIALIZED VIEW `bank-project.gold.customer_engagement_metrics`
AS
SELECT
  customer_id,
  COUNT(*) as total_events_30d,
  COUNT(DISTINCT event_type) as unique_event_types_30d,
  MAX(event_timestamp) as last_event_timestamp
FROM `bank-project.silver.customer_events`
WHERE event_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
GROUP BY customer_id;
```

**Query the view instead of raw table:**

```sql
-- This is cheap (queries precomputed view, not raw table)
SELECT * FROM `bank-project.gold.customer_engagement_metrics`
WHERE total_events_30d > 10;
```

**Cost Savings:** Materialized views are incrementally updated (only new data processed). If raw query scans 100 GB, materialized view query scans <1 GB → **99% savings** on repeated queries.

3. **BigQuery BI Engine (For Interactive Dashboards):**

If you're building Looker dashboards on lead scores, enable BI Engine:

```bash
# Reserve 10 GB of BI Engine capacity (in-memory acceleration)
bq mk --reservation \
  --project=bank-project \
  --location=europe-west3 \
  --bi_engine_capacity=10

# Cost: €0.06 per GB per hour = €432/month for 10 GB reservation
```

**Trade-off:** Expensive, but makes dashboards instant (no query costs). Only use if business users run hundreds of ad-hoc queries daily.

4. **Use Clustered Tables:**

```sql
-- Clustering reduces data scanned when filtering on cluster keys
CREATE TABLE `bank-project.gold.customer_lead_scores` (
  customer_id STRING,
  lead_category STRING,
  propensity_score FLOAT64,
  last_updated TIMESTAMP
)
PARTITION BY DATE(last_updated)
CLUSTER BY lead_category, customer_id;
```

**Query optimization:**

```sql
-- Only scans Hot lead blocks (clustering benefit)
SELECT * FROM `bank-project.gold.customer_lead_scores`
WHERE lead_category = 'HOT';
```

**Savings:** Clustering can reduce scanned data by 30-70% depending on data distribution.

5. **Avoid SELECT * (Specify Columns):**

```sql
-- BAD: Scans all columns (expensive if table is wide)
SELECT * FROM `bank-project.silver.customers`;

-- GOOD: Only scans needed columns
SELECT customer_id, lead_category, propensity_score
FROM `bank-project.silver.customers`;
```

**Savings:** If table has 50 columns but you need 3, you scan 94% less data.

### 5.3 Pub/Sub vs Direct API Calls

**Cost Comparison (1M lead score updates/day):**

| Approach | Cost Components | Monthly Cost |
|----------|----------------|--------------|
| **Pub/Sub + Cloud Functions** | Pub/Sub: €2.40<br>Cloud Functions: €12<br>Egress: €5 | **€19.40** |
| **Direct API calls from BigQuery** | BigQuery query: €5<br>Cloud Functions: €12<br>Egress: €5 | **€22** |
| **Dataflow streaming + Pub/Sub** | Pub/Sub: €2.40<br>Dataflow workers: €180<br>Egress: €5 | **€187.40** |

**Recommendation:** Use **Pub/Sub + Cloud Functions** for most use cases. It's decoupled (Pub/Sub acts as buffer if AEP is down), scalable, and cost-effective.

**Only use Dataflow if:**
- You need complex stream processing (windowing, sessionization, joins with state)
- You need exactly-once processing semantics
- You're processing >100M events/day (Dataflow's fixed overhead amortizes at scale)

### 5.4 Storage Tiering Strategies

**Cloud Storage Lifecycle Policies:**

```json
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "SetStorageClass", "storageClass": "NEARLINE"},
        "condition": {
          "age": 30,
          "matchesPrefix": ["raw-events/"]
        }
      },
      {
        "action": {"type": "SetStorageClass", "storageClass": "COLDLINE"},
        "condition": {
          "age": 90,
          "matchesPrefix": ["raw-events/"]
        }
      },
      {
        "action": {"type": "SetStorageClass", "storageClass": "ARCHIVE"},
        "condition": {
          "age": 365,
          "matchesPrefix": ["raw-events/"]
        }
      },
      {
        "action": {"type": "Delete"},
        "condition": {
          "age": 2555,
          "matchesPrefix": ["raw-events/"]
        }
      }
    ]
  }
}
```

**Apply lifecycle policy:**

```bash
gsutil lifecycle set lifecycle.json gs://bank-data-eu/
```

**Storage Class Pricing (per GB per month):**
- **Standard:** €0.020 (frequent access)
- **Nearline:** €0.010 (access <1/month)
- **Coldline:** €0.004 (access <1/quarter)
- **Archive:** €0.0012 (access <1/year, for compliance retention)

**Cost Savings Example (1 TB raw events per month for 7 years retention):**

| Tiering Strategy | Total Cost (7 years) |
|------------------|----------------------|
| All Standard | €0.020 × 84 TB = **€1,680** |
| With Lifecycle (30d Standard, 60d Nearline, rest Archive) | €0.020×1 TB + €0.010×2 TB + €0.0012×81 TB = **€117** |

**Savings: 93%** - this is why lifecycle policies are mandatory.

**BigQuery Long-Term Storage:**

BigQuery automatically moves tables to long-term pricing if untouched for 90 days:
- **Active storage:** €0.020 per GB per month
- **Long-term storage:** €0.010 per GB per month (automatic, no action needed)

**Strategy:** Keep historical data in BigQuery partitions (auto long-term pricing), use for compliance queries. Don't delete unless legally allowed.

### 5.5 Cost Monitoring & Alerting

**Set Budget Alerts:**

```bash
# Create budget alert for GCP project
gcloud billing budgets create \
  --billing-account=0X0X0X-0X0X0X-0X0X0X \
  --display-name="Monthly GCP Budget" \
  --budget-amount=10000EUR \
  --threshold-rule=percent=50 \
  --threshold-rule=percent=75 \
  --threshold-rule=percent=90 \
  --threshold-rule=percent=100 \
  --notification-channel-ids=channel-id-1,channel-id-2
```

**BigQuery Cost Dashboard (Looker Studio):**

Query to analyze BigQuery costs:

```sql
-- Analyze BigQuery query costs by user/table
SELECT
  user_email,
  project_id,
  referenced_tables,
  ROUND(total_bytes_billed / POW(10, 12), 2) as tb_billed,
  ROUND((total_bytes_billed / POW(10, 12)) * 5, 2) as cost_eur,
  COUNT(*) as query_count
FROM `bank-project.region-eu`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
WHERE creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
  AND job_type = 'QUERY'
  AND state = 'DONE'
GROUP BY user_email, project_id, referenced_tables
ORDER BY tb_billed DESC
LIMIT 100;
```

Export to Looker Studio for visualization. **Alert if any user scans >1 TB/day** (likely unoptimized query).

**Cloud Functions Cost Monitoring:**

```sql
-- Identify expensive Cloud Function invocations
SELECT
  resource.labels.function_name,
  COUNT(*) as invocations,
  SUM(CAST(jsonPayload.executionTimeMs AS INT64)) as total_execution_ms,
  ROUND(SUM(CAST(jsonPayload.executionTimeMs AS INT64)) / 1000 / 3600, 2) as execution_hours
FROM `bank-project.logs.cloudaudit_googleapis_com_activity_*`
WHERE resource.type = 'cloud_function'
  AND timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
GROUP BY function_name
ORDER BY execution_hours DESC;
```

**If function execution hours are high:** Optimize function code, increase memory allocation (faster execution), or move to Cloud Run for more control.

---

## 6. Honest Assessment & Alternative Approaches

### 6.1 Trade-offs of Zero-Copy Architecture

Let me be blunt about the challenges:

**Challenge 1: Increased Complexity**

Zero-copy requires maintaining two systems:
- **GCP:** Data warehouse, ML pipelines, feature engineering, scoring
- **AEP:** Activation engine, campaign management, audience orchestration

**Implication:** More operational overhead. If AEP goes down, campaigns fail even though GCP is healthy. If GCP scoring pipeline breaks, AEP receives stale scores.

**Mitigation:**
- Implement comprehensive monitoring (see Section 4.5)
- Build fallback mechanisms (AEP uses last-known scores if GCP doesn't update)
- Strong SLAs with Adobe (99.9% uptime, <1 hour incident resolution)

**Challenge 2: Latency in Real-Time Use Cases**

Even with event-driven architecture, there's latency:
- Customer action → GCP event ingestion: ~10-100ms
- GCP scoring (Vertex AI): ~50-200ms
- GCP → AEP push: ~100-500ms
- AEP activation: ~500-2000ms
- **Total: 1-3 seconds** best case

**Implication:** For use cases like real-time website personalization (show offer banner immediately when customer lands on page), 2-3 second latency may be too slow.

**Alternative:** If <500ms latency is critical, consider:
- Pre-compute propensity scores and cache in Firestore (low-latency reads)
- Use Google Optimize (GCP-native A/B testing) instead of Adobe Target
- Build custom activation layer in GCP (Cloud Functions + SendGrid for email, not AEP)

**Challenge 3: Limited AEP Functionality Without Full Profiles**

AEP's strength is its unified customer profile with rich attributes (CDP capabilities). If you send only scores, you lose:
- AEP's identity resolution (merging cross-device IDs)
- AEP's segment builder (business users creating segments in UI)
- AEP's predictive audiences (AEP's own ML models)

**Implication:** You're using AEP as a "dumb" activation tool, not leveraging its full capabilities.

**Counter-Argument:** If GCP can do ML better (Vertex AI > AEP's models), and GCP has cleaner data (you control pipelines), why pay for AEP's redundant features? **Consider whether you need AEP at all.**

### 6.2 When NOT to Use This Architecture

**Scenario 1: Small Data Volume (<1M customers)**

If you have <1M customers and <100 GB data, zero-copy is over-engineered. Just:
- Send full customer profiles to AEP (egress cost: €0.085 × 0.1 GB = €0.0085/day, trivial)
- Use AEP's native segmentation and activation
- Avoid complexity of dual-system maintenance

**Scenario 2: AEP is Primary System of Record**

If your organization has already invested heavily in AEP and it's the source of truth, don't fight it. Use GCP for:
- Data lake (staging area before AEP ingestion)
- Heavy analytics (BigQuery for queries AEP can't handle)
- Compliance (data residency in GCP, replicate to AEP)

But let AEP be the system of record. Zero-copy makes sense when **GCP is the authoritative system**.

**Scenario 3: Real-Time Personalization is Critical**

If your primary use case is <100ms website personalization (banking app shows offer as customer opens app), zero-copy GCP→AEP is too slow.

**Alternative Architecture:**
- GCP for batch ML (train models, compute scores daily)
- Export scores to **Google Cloud CDN** or **Firestore** (ultra-low latency)
- Banking app calls GCP API directly (bypass AEP)
- Use AEP only for email/offline channels (where latency is acceptable)

**Scenario 4: Limited GCP Expertise in Organization**

Zero-copy architecture requires deep GCP skills:
- Dataflow for stream processing
- Vertex AI for ML
- BigQuery optimization
- Pub/Sub architecture
- IAM and security

If your team is primarily Adobe-skilled (AEP, Adobe Analytics, Target), you'll struggle to maintain GCP pipelines.

**Recommendation:** Start with simpler architecture (GCP as data lake, AEP as CDP), build GCP expertise over 6-12 months, then transition to zero-copy.

### 6.3 Alternative: Build Activation in GCP (No AEP)

**Radical Alternative:** If the goal is minimizing data to AEP, why use AEP?

**GCP-Native Activation Stack:**

```
┌─────────────────────────────────────────────────────────────────┐
│                         GCP Data Platform                        │
│  BigQuery (warehouse) + Vertex AI (ML) + Pub/Sub (events)      │
└─────────────────────────────────────────────────────────────────┘
                              ↓
        ┌─────────────────────┴─────────────────────┐
        ↓                     ↓                     ↓
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│   SendGrid   │    │Google Ads API│    │  Twilio SMS  │
│  (Email)     │    │(Paid Ads)    │    │ (Messaging)  │
└──────────────┘    └──────────────┘    └──────────────┘
```

**How it works:**
1. GCP scores leads (as before)
2. Cloud Functions trigger activation directly:
   - Hot lead → Send email via SendGrid API
   - Hot lead → Upload to Google Ads Customer Match (push audience to Google Ads)
   - Hot lead → Send SMS via Twilio
3. No AEP license fee (~$100k-500k/year saved)
4. Zero egress to AEP (data stays in GCP)

**Cost Comparison (1M customers, 10k campaigns/month):**

| Component | AEP-Based | GCP-Native |
|-----------|-----------|------------|
| **Platform License** | €300k/year (AEP) | €0 (GCP-native) |
| **GCP Costs** | €3k/month | €3k/month |
| **Egress Costs** | €600/month (to AEP) | €0 |
| **SendGrid/Twilio** | Included in AEP | €2k/month |
| **Total Annual** | **€336k** | **€60k** |

**Savings: 82%** - this is why I'm challenging the AEP requirement.

**When to consider GCP-native activation:**
- You have no existing AEP investment (greenfield project)
- Your activation needs are simple (email, SMS, paid ads)
- You have strong GCP engineering team
- Cost is a primary concern

**When AEP still makes sense:**
- You need Adobe ecosystem integration (Adobe Analytics, Adobe Target, Adobe Campaign)
- Business users need self-service segmentation UI
- You require AEP's identity graph (cross-device stitching)
- Regulatory requirement for separate activation platform (separation of duties)

### 6.4 Potential Bottlenecks & Limitations

**Bottleneck 1: BigQuery Query Concurrency**

BigQuery has concurrent query limits:
- 100 concurrent queries per project (default)
- 50 concurrent DML statements (INSERT, UPDATE, DELETE)

**Problem:** If you have 10 teams all querying customer data simultaneously, you hit limits.

**Mitigation:**
- Use BigQuery Reservations (dedicated query slots)
- Implement query queuing in application layer
- Split workloads across multiple projects (not ideal for governance)

**Bottleneck 2: Vertex AI Prediction Endpoint Latency**

Vertex AI endpoints typically have:
- P50 latency: ~50ms
- P99 latency: ~500ms (cold start if replicas scale up)

**Problem:** If scoring 1M customers in batch via endpoint, it takes ~14 hours (1M × 50ms / 3600).

**Mitigation:**
- Use BigQuery ML for batch scoring (much faster, vectorized operations)
- Only use Vertex AI endpoints for real-time individual predictions
- Scale prediction endpoint to 50+ replicas for high throughput (expensive)

**Bottleneck 3: AEP Ingestion Rate Limits**

Adobe imposes rate limits on API ingestion:
- HTTP Streaming Ingestion: ~2000 messages/second
- Bulk Batch Ingestion: ~100 GB/hour

**Problem:** If you have 1M lead score changes per day and try to send in 1 hour, you exceed rate limit (277 messages/second → OK for streaming, but AEP may throttle).

**Mitigation:**
- Spread ingestion over 24 hours (not just after daily scoring run)
- Use batch ingestion for large updates (overnight)
- Negotiate higher rate limits with Adobe (enterprise tier)

**Bottleneck 4: Cloud Functions Concurrency**

Cloud Functions (2nd gen) have limits:
- 1000 concurrent instances per region (default quota)
- Can be increased to 10,000 with quota request

**Problem:** If Pub/Sub publishes 10k lead score updates simultaneously, Cloud Functions may not scale fast enough.

**Mitigation:**
- Use Cloud Run instead of Cloud Functions (higher default concurrency)
- Implement Pub/Sub message batching (process 100 messages per function invocation)
- Increase function timeout to allow for retries

### 6.5 Recommended Phased Approach

Don't implement everything at once. Here's a pragmatic rollout:

**Phase 1 (Months 1-2): Foundation - Batch Sync**
- Set up GCP data platform (BigQuery, Cloud Storage)
- Implement medallion architecture (Bronze/Silver/Gold)
- Build basic lead scoring in BigQuery ML
- Implement daily batch export to AEP (Pattern C from Section 2.3)
- **Goal:** Prove GCP→AEP integration works, minimal complexity

**Phase 2 (Months 3-4): Event-Driven Hot Leads**
- Add Pub/Sub + Dataflow for event streaming
- Implement real-time scoring for Hot lead triggers (credit applications, callback requests)
- Deploy Cloud Function to push Hot leads to AEP immediately (Pattern A)
- **Goal:** Reduce latency for high-value leads from 24 hours to <1 minute

**Phase 3 (Months 5-6): Advanced ML & Feature Store**
- Migrate from BigQuery ML to Vertex AI for advanced models
- Implement Vertex AI Feature Store for online/offline feature serving
- Add model monitoring and drift detection
- **Goal:** Improve lead scoring accuracy, productionize ML pipelines

**Phase 4 (Months 7-9): API Pull & Optimization**
- Implement Cloud Run API for AEP to pull data (Pattern B)
- Optimize costs (compression, clustering, tiering)
- Implement VPC Service Controls and advanced security
- **Goal:** Minimize egress costs, harden security for production

**Phase 5 (Months 10-12): Governance & Compliance**
- Complete BaFin audit documentation
- Implement automated compliance checks (DLP scanning, audit log analysis)
- Conduct third-party security assessment of GCP→AEP integration
- **Goal:** Pass BaFin audit, achieve production certification

**Don't try to build Phases 1-5 simultaneously.** Start simple, prove value, iterate.

### 6.6 When to Push Back on Zero-Copy

**Be honest with stakeholders:** Zero-copy is not always the right answer. Push back if:

1. **Business case is weak:** "We want zero-copy because it sounds innovative" → No. Show ROI (cost savings, latency improvement) or don't do it.

2. **Team lacks GCP skills:** Building this architecture requires senior data engineers. If your team is junior or Adobe-focused, you'll fail. Hire/train first.

3. **AEP contract already includes data ingress:** Some AEP contracts have unlimited data ingress. If you're already paying for it, zero-copy saves egress costs (€50-200/month) but adds complexity (€50k in engineering time). Not worth it.

4. **Regulatory interpretation is unclear:** If your compliance team says "we're not sure if GCP→AEP satisfies BaFin," don't proceed. Get legal sign-off first.

**My opinionated take:** Zero-copy is the right pattern for large-scale (10M+ customers), data-intensive (100+ GB), ML-driven use cases where GCP is the authoritative data platform. For smaller deployments or AEP-centric architectures, it's over-engineered.

---

## 7. Summary & Decision Framework

### 7.1 Recommended Architecture (Balanced Approach)

For a German banking client with 10M customers, strict compliance requirements, and need for both real-time and batch activation:

**Data Platform:**
- **BigQuery (europe-west3)** as data warehouse
- **Medallion architecture** (Bronze/Silver/Gold layers)
- **Pub/Sub** for event streaming
- **Vertex AI** for ML (training + batch scoring)
- **Cloud Storage** with lifecycle policies for raw data retention

**ML Pipeline:**
- **BigQuery ML** for initial lead scoring model (MVP in 2 weeks)
- **Migrate to Vertex AI** for production (XGBoost, better accuracy)
- **Daily batch scoring** for all customers (runs at 2 AM)
- **Real-time scoring** for Hot lead triggers (credit app, callback)

**GCP→AEP Integration:**
- **Event-Driven (Pattern A)** for Hot leads (real-time)
- **Batch Sync (Pattern C)** for Warm/Cold leads (daily)
- **Send only:** customer_id, lead_category, propensity_score, recommended_product (NOT raw data)

**Compliance:**
- **Data residency:** All GCP resources in europe-west3 (Frankfurt)
- **Encryption:** CMEK with Cloud KMS
- **Audit:** Cloud Audit Logs → BigQuery (retained 7 years)
- **Access control:** VPC Service Controls, least-privilege IAM
- **GDPR:** Implement deletion workflow (GCP + AEP)

**Cost (Monthly):**
- BigQuery: €500 (queries + storage)
- Pub/Sub + Cloud Functions: €50
- Vertex AI (batch scoring): €100
- Cloud Storage: €100
- Egress to AEP: €200
- **Total: ~€1,000/month** (excluding AEP license)

### 7.2 Decision Matrix: Which Integration Pattern to Use

| Use Case | Lead Type | Latency Requirement | Volume | Recommended Pattern | Cost/Month |
|----------|-----------|---------------------|--------|---------------------|------------|
| Hot lead callback request | HOT | <1 minute | 1k/day | Event-Driven (A) | €25 |
| Warm lead nurture campaign | WARM | <24 hours | 100k/day | Batch Sync (C) | €10 |
| Cold lead quarterly re-engagement | COLD | <7 days | 5M/quarter | Batch Sync (C) | €3 |
| AEP-initiated profile enrichment | Any | <500ms | 10k/day | API Pull (B) | €200 |
| Daily segment refresh | All | <24 hours | 10M/day | Batch Sync (C) | €10 |

### 7.3 Key Questions to Answer Before Implementation

1. **Is AEP deployment in EU or US?** (If US, additional SCCs and consent required)
2. **What is AEP API rate limit?** (Negotiate if needed)
3. **Who owns data governance (GCP vs AEP)?** (Clarify system of record)
4. **What is acceptable latency for campaigns?** (Real-time vs batch decision)
5. **Does team have Vertex AI expertise?** (If no, start with BigQuery ML)
6. **What is BaFin audit timeline?** (Prioritize compliance features)
7. **What is budget for egress costs?** (If tight, use batch + compression)
8. **Do you need AEP at all?** (Consider GCP-native activation alternative)

### 7.4 Success Metrics

**Technical Metrics:**
- **Lead scoring accuracy:** >85% precision/recall for Hot leads
- **Latency (real-time):** <2 seconds end-to-end (event → AEP activation)
- **Latency (batch):** <4 hours (scoring → AEP ingestion complete)
- **Egress cost:** <€500/month (data minimization working)
- **System availability:** >99.9% uptime (GCP + AEP combined)

**Business Metrics:**
- **Conversion rate:** Hot leads convert at >15% (vs <5% for untargeted)
- **Campaign ROI:** €5 revenue per €1 spent on activation
- **Time to activation:** <24 hours from lead score change to campaign delivery

**Compliance Metrics:**
- **Audit log completeness:** 100% of data access logged
- **Data residency violations:** 0 (all data in europe-west3)
- **GDPR deletion time:** <7 days from request to completion
- **BaFin audit findings:** 0 critical, <3 minor

### 7.5 Final Recommendations

**Do:**
1. Start with batch synchronization (prove integration works)
2. Use BigQuery ML for MVP (fast iteration)
3. Implement comprehensive monitoring from day 1 (Cloud Logging, Audit Logs)
4. Document data flows for BaFin compliance
5. Challenge whether you need AEP (consider GCP-native activation)

**Don't:**
1. Build real-time streaming without proven business case (expensive)
2. Send raw PII to AEP (defeats zero-copy, compliance risk)
3. Use US regions for data processing (BaFin violation)
4. Skip encryption (CMEK is mandatory for German banking)
5. Implement all patterns at once (start simple, iterate)

**Challenge to Leadership:**

"We're proposing zero-copy architecture to minimize data sent to AEP. But I need to ask: why are we using AEP? If the goal is data minimization, and GCP can handle ML + activation, we could save €300k/year in AEP licenses by building activation natively in GCP. Before we invest €200k in engineering time for zero-copy integration, let's validate the business case for AEP."

**This question needs answering before you write a single line of code.**

---

## Appendix: Reference Links & Tools

**GCP Services:**
- BigQuery: https://cloud.google.com/bigquery
- Vertex AI: https://cloud.google.com/vertex-ai
- Dataflow: https://cloud.google.com/dataflow
- Pub/Sub: https://cloud.google.com/pubsub
- Cloud Functions: https://cloud.google.com/functions
- Cloud Run: https://cloud.google.com/run

**Adobe Experience Platform:**
- AEP Documentation: https://experienceleague.adobe.com/docs/experience-platform.html
- AEP API Reference: https://www.adobe.io/experience-platform-apis/
- HTTP Streaming Ingestion: https://experienceleague.adobe.com/docs/experience-platform/ingestion/streaming/overview.html

**German Banking Regulations:**
- BaFin MaRisk: https://www.bafin.de/EN/Aufsicht/BankenFinanzdienstleister/Risikomanagement/risikomanagement_node_en.html
- GDPR Full Text: https://gdpr-info.eu/
- DORA Regulation: https://www.digital-operational-resilience-act.com/

**Books & Papers:**
- "Designing Data-Intensive Applications" by Martin Kleppmann
- "Building Machine Learning Pipelines" by Hannes Hapke & Catherine Nelson
- "Data Mesh" by Zhamak Dehghani
- Google's "Site Reliability Engineering" book (SRE)

---

**Document Status:** Draft for Review
**Next Steps:**
1. Review with GCP architect team
2. Validate AEP integration requirements with Adobe
3. Get legal sign-off on data residency approach
4. Estimate engineering effort for Phase 1 implementation

**Questions or feedback? Challenge my assumptions. I'm opinionated but not dogmatic. Let's build the right architecture, not just the trendy one.**
