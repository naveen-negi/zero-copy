# GCP Zero-Copy Architecture for Adobe Experience Platform Integration

**Document Version:** 2.0
**Last Updated:** 2025-10-16
**Target Environment:** EU Regulated Environment (GDPR compliant)

**MAJOR UPDATE:** Adobe Experience Platform now supports **Federated Audience Composition** with BigQuery, enabling TRUE zero-copy architecture. This fundamentally changes the integration paradigm - see Pattern D in Section 2.4.

---

## Executive Summary

This document outlines four architectural approaches for implementing a zero-copy integration between Google Cloud Platform (GCP) and Adobe Experience Platform (AEP) for an EU-based enterprise. The core principle: **keep raw data in GCP, minimize or eliminate data transfer to AEP**.

### Game-Changer: Federated Audience Composition

**Adobe's new Federated Audience Composition capability fundamentally changes the GCP-AEP integration paradigm.** Instead of pushing data to AEP (even minimal segments), AEP can now query BigQuery directly in federated mode. Your raw data never leaves BigQuery - AEP only receives query results (audience membership lists).

**This is TRUE zero-copy architecture.**

**What this means:**
- Raw customer profiles, transactions, and PII stay in BigQuery (europe-west3)
- AEP sends SQL queries to your BigQuery datasets
- BigQuery returns only customer identifiers matching audience criteria
- No data duplication, no batch exports, no streaming pipelines for segmentation
- Superior data governance: your data warehouse remains the single source of truth

**The catch:**
- Query latency: 5-30 seconds (vs <1 second for push patterns)
- Cost: €50-500/month for query processing (vs €25/month for event-driven push)
- Complexity: Requires BigQuery optimization (materialized views, partitioning, clustering)
- AEP feature limitations: Some AEP capabilities may not work with external audiences

**When to use Federated Composition:**
- Audience segmentation for campaigns (80% of marketing use cases)
- Complex multi-dimensional targeting (lifecycle stage + product affinity + lead score)
- Data governance mandates (data residency, PII protection, audit requirements)
- Exploratory audience discovery in AEP UI

**When NOT to use it:**
- Real-time activation <1 second required (hot lead instant follow-up, fraud alerts)
- Use event-driven push (Pattern A) for these critical real-time scenarios

### Key Architectural Thesis (Updated)

Zero-copy now has TWO meanings:

1. **TRUE zero-copy (Federated Composition - Pattern D):**
   - Raw data NEVER leaves BigQuery
   - AEP queries data in-place, receives only results
   - Best for data governance and compliance
   - Trade-off: 5-30 second query latency

2. **Practical zero-copy (Push/Pull Patterns A-C):**
   - Send only actionable signals to AEP (segment membership, propensity scores)
   - Keep raw data and comprehensive profiles in GCP
   - Compute everything possible in GCP before sending results
   - Best for real-time activation (<1 second latency)

**Recommended Hybrid Strategy:**
- **80% of use cases:** Federated Composition (Pattern D) for audience segmentation
- **15% of use cases:** Event-driven push (Pattern A) for real-time hot lead activation
- **5% of use cases:** Batch sync (Pattern C) for reconciliation and compliance reporting

**Critical Challenge Addressed:** Previously, zero-copy with AEP was a contradiction - AEP needed data to activate audiences. Federated Composition solves this by inverting the paradigm: instead of "push minimal data to AEP," it's "let AEP query data in GCP." This is architecturally superior for regulated environments where data residency and governance are paramount.

---

## 1. GCP Foundation: Data Platform Architecture

### 1.1 Core Data Storage Strategy

For an EU regulated environment with zero-copy principles, I recommend a **medallion architecture** on GCP with strict data residency controls:

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
- **Mature audit logging:** Essential for regulatory compliance

**Regional Choice - Critical for EU Data Residency:**
- **Primary:** `europe-west3` (Frankfurt, Germany) - for data residency compliance
- **DO NOT use:** Multi-region EU (includes UK post-Brexit, potential non-EU processing)
- **Backup/DR:** `europe-west1` (Belgium) if cross-region HA is required, document in data processing agreements

### 1.2 Event Streaming Architecture

For real-time lead scoring and campaign triggering, you need a robust event backbone:

```
┌──────────────────┐
│  Event Sources   │
│ - Web/Mobile     │
│ - Mobile Apps    │──┐
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

1. **`customer-events-raw`**: All customer interactions (page views, transactions, app events)
2. **`customer-events-enriched`**: Events joined with customer profile data
3. **`customer-leads-scored`**: Lead classification changes (Cold→Warm, Warm→Hot)
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
  "segment": "hot_lead_enterprise_services",
  "propensity_score": 0.87,
  "recommended_product": "business_service_premium",
  "data_reference": "gs://company-profiles-eu/customers/DE12345/profile.json",
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
   - Write score changes to `customer-leads-scored` Pub/Sub topic
   - Only publish when lead status **changes** (Cold→Warm, Warm→Hot) to minimize noise

2. **Filtering & Routing (Cloud Function or Cloud Run):**
   - Subscribe to `customer-leads-scored` topic
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

**EU Regulatory Compliance Considerations:**
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
bq_client = bigquery.Client(project="company-project", location="europe-west3")

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
        FROM `company-project.gold.customer_lead_scores`
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
        FROM `company-project.gold.customer_lead_scores`
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
  --service-account=aep-integration-sa@company-project.iam.gserviceaccount.com \
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
  uri='gs://company-aep-exports-eu/lead-scores/export_*.csv',
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
FROM `company-project.gold.customer_lead_scores`
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

---

### 2.4 Pattern D: Federated Audience Composition (TRUE Zero-Copy)

**Best for:** Audience segmentation, complex multi-dimensional targeting, data governance-first architectures

**This is the game-changer.** Adobe Experience Platform now supports Federated Audience Composition with BigQuery, enabling **genuine zero-copy architecture**. Unlike Patterns A-C which push data (minimal or not) to AEP, this pattern keeps all raw data in BigQuery while AEP queries it in-place.

#### 2.4.1 How Federated Audience Composition Works

```
┌──────────────────────────────────────────────────────────────┐
│                    Adobe Experience Platform                 │
│                                                              │
│  ┌────────────────────────────────────────────┐             │
│  │  Federated Audience Composition            │             │
│  │  - Define audience rules in AEP UI         │             │
│  │  - AEP generates SQL query                 │             │
│  │  - Query sent to BigQuery (via connector)  │             │
│  └────────────────┬───────────────────────────┘             │
└───────────────────┼─────────────────────────────────────────┘
                    │ SQL Query (secure connection)
                    ↓
┌──────────────────────────────────────────────────────────────┐
│               Google Cloud Platform (europe-west3)           │
│                                                              │
│  ┌────────────────────────────────────────────┐             │
│  │         BigQuery Datasets                  │             │
│  │                                            │             │
│  │  gold.customer_profiles                    │             │
│  │  gold.customer_lead_scores                 │             │
│  │  gold.customer_features                    │             │
│  │  gold.identity_mapping ← AEP Identity Map  │             │
│  │                                            │             │
│  │  Views exposed to AEP:                     │             │
│  │  - aep_federated.hot_leads                 │             │
│  │  - aep_federated.customer_segments         │             │
│  │  - aep_federated.product_affinity          │             │
│  └────────────────────────────────────────────┘             │
│                                                              │
│  Query executes in BigQuery, only audience                  │
│  membership results sent back to AEP                        │
└──────────────────────────────────────────────────────────────┘
                    ↑
                    │ Results: customer_id list + segment metadata
                    │ (NOT raw data, just "who's in this audience")
                    ↓
┌──────────────────────────────────────────────────────────────┐
│                    Adobe Experience Platform                 │
│                                                              │
│  External Audience: "Hot Leads - Enterprise Banking"        │
│  - 45,234 profiles                                           │
│  - Source: BigQuery (federated)                              │
│  - Last refreshed: 2025-10-16 08:00 UTC                      │
│  - Activatable to all AEP destinations                       │
└──────────────────────────────────────────────────────────────┘
```

**Key Principle:** AEP asks "who matches this criteria?" BigQuery answers with a list of customer_ids. The raw data (transactions, profiles, PII) **never leaves BigQuery**.

#### 2.4.2 Data Architecture for Federated Queries

To optimize for AEP's federated query patterns, structure your BigQuery datasets as follows:

**A. Dataset Organization**

```sql
-- Dedicated dataset for AEP federated access
-- Isolated from production analytics to prevent query interference
CREATE SCHEMA IF NOT EXISTS `company-project.aep_federated`
OPTIONS(
  location="europe-west3",
  description="Federated views for Adobe Experience Platform audience composition",
  labels=[("purpose", "aep_integration"), ("compliance", "gdpr")]
);
```

**B. Identity Mapping Table (Critical)**

AEP needs to map BigQuery customer identifiers to AEP identity namespaces. This is the bridge between systems:

```sql
-- Identity resolution table
CREATE OR REPLACE TABLE `company-project.aep_federated.identity_mapping`
PARTITION BY DATE(last_updated)
CLUSTER BY customer_id, email_sha256
AS
SELECT
  -- GCP identifier (your system of record)
  customer_id,

  -- AEP identity namespaces
  email_sha256,  -- SHA-256 hash of email (privacy-preserving)
  phone_sha256,  -- SHA-256 hash of phone
  ecid,          -- Adobe Experience Cloud ID (if available)

  -- Identity metadata
  identity_status,  -- ACTIVE, MERGED, DELETED
  primary_identity, -- TRUE if this is primary identity
  last_updated,

  -- DO NOT include raw PII (plain email/phone)
  -- AEP will use hashed identities for matching
FROM `company-project.gold.customer_master`
WHERE customer_status = 'ACTIVE'
  AND gdpr_consent_marketing = TRUE  -- Only expose customers who consented
;

-- Grant AEP service account read access
GRANT `roles/bigquery.dataViewer`
ON TABLE `company-project.aep_federated.identity_mapping`
TO "serviceAccount:aep-federated@company-adobe.iam.gserviceaccount.com";
```

**C. Materialized Views for Lead Scores**

Instead of exposing raw gold tables, create optimized views that pre-compute expensive operations:

```sql
-- Materialized view: Hot leads for AEP consumption
-- Refreshed every 1 hour to balance freshness and cost
CREATE MATERIALIZED VIEW `company-project.aep_federated.hot_leads`
PARTITION BY score_date
CLUSTER BY lead_category, propensity_score
OPTIONS(
  enable_refresh = true,
  refresh_interval_minutes = 60,
  description = "Pre-computed hot lead scores for AEP federated queries"
)
AS
SELECT
  -- Identity
  c.customer_id,
  i.email_sha256,
  i.ecid,

  -- Lead scoring results (computed in GCP)
  s.lead_category,
  s.propensity_score,
  s.recommended_product,
  s.score_confidence,

  -- Segmentation attributes (high-level only)
  c.customer_tier,  -- RETAIL, PREMIUM, PRIVATE_BANKING
  c.customer_lifecycle_stage,  -- PROSPECT, ONBOARDING, ACTIVE, AT_RISK, DORMANT

  -- Temporal
  s.score_date,
  s.score_timestamp,

  -- DO NOT include:
  -- - Raw transaction amounts
  -- - Account balances
  -- - Credit scores
  -- - PII beyond hashed identifiers
FROM `company-project.gold.customer_lead_scores` s
INNER JOIN `company-project.gold.customers` c
  ON s.customer_id = c.customer_id
INNER JOIN `company-project.aep_federated.identity_mapping` i
  ON c.customer_id = i.customer_id
WHERE s.lead_category = 'HOT'
  AND s.propensity_score >= 0.70
  AND s.score_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
  AND c.gdpr_consent_marketing = TRUE
;
```

**Why Materialized Views?**
- **Performance:** AEP queries execute in <5 seconds vs 30+ seconds on base tables
- **Cost optimization:** Refresh on schedule (hourly) rather than computing on every AEP query
- **Access control:** Expose only what AEP needs, hiding sensitive columns
- **Query predictability:** Partitioning and clustering ensure consistent performance

**D. Dynamic Segmentation Views**

Create views for common segmentation patterns AEP will query:

```sql
-- Example: Product affinity segments
CREATE OR REPLACE VIEW `company-project.aep_federated.product_affinity_segments` AS
SELECT
  i.email_sha256,
  i.ecid,
  p.affinity_product_category,
  p.affinity_score,
  p.last_interaction_date,
  CASE
    WHEN p.affinity_score >= 0.8 THEN 'HIGH_AFFINITY'
    WHEN p.affinity_score >= 0.5 THEN 'MEDIUM_AFFINITY'
    ELSE 'LOW_AFFINITY'
  END as affinity_level
FROM `company-project.gold.product_affinity` p
INNER JOIN `company-project.aep_federated.identity_mapping` i
  ON p.customer_id = i.customer_id
WHERE p.calculation_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
;

-- Example: Customer lifecycle stages
CREATE OR REPLACE VIEW `company-project.aep_federated.lifecycle_segments` AS
SELECT
  i.email_sha256,
  c.customer_lifecycle_stage,
  c.lifecycle_days_in_stage,
  c.lifecycle_last_transition_date,
  c.customer_tier
FROM `company-project.gold.customers` c
INNER JOIN `company-project.aep_federated.identity_mapping` i
  ON c.customer_id = i.customer_id
WHERE c.customer_status = 'ACTIVE'
;
```

#### 2.4.3 Service Account & IAM Configuration

**A. Create Dedicated Service Account for AEP**

```bash
# Create service account for AEP federated queries
gcloud iam service-accounts create aep-federated-query \
  --display-name="AEP Federated Audience Composition" \
  --description="Service account for Adobe Experience Platform to query BigQuery in federated mode" \
  --project=company-project

# Generate and download JSON key (required by AEP connector)
gcloud iam service-accounts keys create aep-federated-key.json \
  --iam-account=aep-federated-query@company-project.iam.gserviceaccount.com

# IMPORTANT: Store this key in Secret Manager, do NOT commit to git
gcloud secrets create aep-federated-sa-key \
  --data-file=aep-federated-key.json \
  --replication-policy=user-managed \
  --locations=europe-west3

# Shred local copy after storing in Secret Manager
shred -u aep-federated-key.json
```

**B. Grant Minimum Required Permissions**

Adobe documentation states `bigquery.jobs.create` and `bigquery.tables.create` are required, but here's what you **actually** need for production:

```bash
# 1. BigQuery Job User (to run queries)
gcloud projects add-iam-policy-binding company-project \
  --member="serviceAccount:aep-federated-query@company-project.iam.gserviceaccount.com" \
  --role="roles/bigquery.jobUser" \
  --condition=None

# 2. BigQuery Data Viewer (read-only on specific datasets)
# DO NOT grant project-level dataViewer - too broad!
gcloud projects add-iam-policy-binding company-project \
  --member="serviceAccount:aep-federated-query@company-project.iam.gserviceaccount.com" \
  --role="roles/bigquery.dataViewer" \
  --condition='expression=resource.name.startsWith("projects/company-project/datasets/aep_federated"),title=aep_federated_dataset_only'

# 3. Create temporary tables for query results
# AEP needs to create temp tables in a dedicated dataset
gcloud projects add-iam-policy-binding company-project \
  --member="serviceAccount:aep-federated-query@company-project.iam.gserviceaccount.com" \
  --role="roles/bigquery.dataEditor" \
  --condition='expression=resource.name == "projects/company-project/datasets/aep_query_temp",title=temp_dataset_only'
```

**Create the temporary dataset:**

```sql
-- AEP writes temporary query results here
CREATE SCHEMA IF NOT EXISTS `company-project.aep_query_temp`
OPTIONS(
  location="europe-west3",
  default_table_expiration_ms=3600000,  -- Auto-delete tables after 1 hour
  description="Temporary tables for AEP federated queries"
);
```

**C. Table-Level Permissions (Principle of Least Privilege)**

Instead of dataset-level access, grant table-level permissions for fine-grained control:

```sql
-- Grant access to specific views only
GRANT `roles/bigquery.dataViewer`
ON TABLE `company-project.aep_federated.hot_leads`
TO "serviceAccount:aep-federated-query@company-project.iam.gserviceaccount.com";

GRANT `roles/bigquery.dataViewer`
ON TABLE `company-project.aep_federated.identity_mapping`
TO "serviceAccount:aep-federated-query@company-project.iam.gserviceaccount.com";

GRANT `roles/bigquery.dataViewer`
ON TABLE `company-project.aep_federated.product_affinity_segments`
TO "serviceAccount:aep-federated-query@company-project.iam.gserviceaccount.com";

-- Document in audit log
INSERT INTO `company-project.audit.iam_changes` (
  timestamp, action, principal, resource, justification
)
VALUES (
  CURRENT_TIMESTAMP(),
  'GRANT_BIGQUERY_ACCESS',
  'aep-federated-query@company-project.iam.gserviceaccount.com',
  'aep_federated dataset',
  'AEP Federated Audience Composition integration - Ticket AEP-2025-01'
);
```

**D. Terraform Configuration for IAM (Recommended)**

```hcl
# terraform/aep_federated_iam.tf

# Service account for AEP federated queries
resource "google_service_account" "aep_federated" {
  account_id   = "aep-federated-query"
  display_name = "AEP Federated Audience Composition"
  description  = "Service account for Adobe Experience Platform federated BigQuery access"
  project      = var.project_id
}

# BigQuery Job User (project-level, required to run queries)
resource "google_project_iam_member" "aep_bigquery_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.aep_federated.email}"
}

# Data Viewer on aep_federated dataset only
resource "google_bigquery_dataset_iam_member" "aep_dataset_viewer" {
  dataset_id = "aep_federated"
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:${google_service_account.aep_federated.email}"
}

# Data Editor on temp dataset (for query result tables)
resource "google_bigquery_dataset_iam_member" "aep_temp_editor" {
  dataset_id = "aep_query_temp"
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.aep_federated.email}"
}

# Generate key and store in Secret Manager
resource "google_service_account_key" "aep_federated_key" {
  service_account_id = google_service_account.aep_federated.name
}

resource "google_secret_manager_secret" "aep_sa_key" {
  secret_id = "aep-federated-sa-key"

  replication {
    user_managed {
      replicas {
        location = "europe-west3"
      }
    }
  }

  labels = {
    purpose    = "aep_integration"
    compliance = "gdpr"
  }
}

resource "google_secret_manager_secret_version" "aep_sa_key_version" {
  secret      = google_secret_manager_secret.aep_sa_key.id
  secret_data = base64decode(google_service_account_key.aep_federated_key.private_key)
}

# Access logging for all AEP queries
resource "google_bigquery_dataset" "aep_federated" {
  dataset_id  = "aep_federated"
  location    = "europe-west3"
  description = "Federated views for AEP audience composition"

  access {
    role          = "roles/bigquery.dataViewer"
    user_by_email = google_service_account.aep_federated.email
  }

  # Enable audit logging
  default_table_expiration_ms = null  # Tables don't expire

  labels = {
    purpose        = "aep_federated"
    data_residency = "eu"
    compliance     = "gdpr"
  }
}
```

#### 2.4.4 Network Security & AEP Connectivity

**A. IP Allowlisting (If Required)**

Adobe's federated query engine connects from specific IP ranges. You need to allowlist these in VPC firewall rules:

```bash
# Create firewall rule to allow AEP BigQuery connector IPs
# (Replace with actual Adobe IP ranges - request from Adobe support)

gcloud compute firewall-rules create allow-aep-bigquery-federated \
  --direction=INGRESS \
  --priority=1000 \
  --network=company-vpc-eu \
  --action=ALLOW \
  --rules=tcp:443 \
  --source-ranges=52.85.0.0/16,34.210.0.0/16 \
  --description="Allow Adobe Experience Platform federated BigQuery queries" \
  --target-tags=bigquery-endpoint
```

**Important:** BigQuery is a serverless service, so firewall rules apply to Private Google Access endpoints if you're using VPC Service Controls (recommended for EU compliance).

**B. VPC Service Controls (Strongly Recommended)**

To prevent data exfiltration and satisfy regulatory requirements, enforce VPC Service Controls:

```bash
# Create service perimeter for BigQuery
gcloud access-context-manager perimeters create aep_bigquery_perimeter \
  --title="AEP BigQuery Federated Access" \
  --resources=projects/123456789 \
  --restricted-services=bigquery.googleapis.com \
  --ingress-policies=aep_ingress_policy.yaml \
  --policy=company_access_policy

# Ingress policy (aep_ingress_policy.yaml)
# Allows AEP service account to query BigQuery from outside VPC
```

**aep_ingress_policy.yaml:**

```yaml
- ingressFrom:
    identities:
      - serviceAccount:aep-federated-query@company-project.iam.gserviceaccount.com
    sources:
      - resource: "*"  # AEP queries from Adobe infrastructure
  ingressTo:
    resources:
      - projects/company-project
    operations:
      - serviceName: bigquery.googleapis.com
        methodSelectors:
          - method: google.cloud.bigquery.v2.JobService.Query
          - method: google.cloud.bigquery.v2.JobService.GetQueryResults
          - method: google.cloud.bigquery.v2.TableDataService.List
```

**C. VPN Connection (Optional, High Security)**

For maximum security, Adobe supports VPN tunnels between AEP and your GCP environment:

```
Adobe AEP ←→ VPN Tunnel ←→ Cloud VPN (europe-west3) ←→ BigQuery
```

**When to use VPN:**
- Highly regulated data (BaFin Tier 1 critical systems)
- Need to audit/log every query at network layer
- Contractual requirement for private connectivity
- Want to avoid public internet entirely

**Cost:** Cloud VPN tunnel: ~€60/month + egress costs

**Trade-off:** Adds latency (~20-50ms) and operational complexity. Only implement if compliance mandates it.

#### 2.4.5 BigQuery Optimization for Federated Queries

**A. Query Performance Tuning**

AEP's federated queries typically follow these patterns. Optimize for them:

**Pattern 1: Audience Membership Lookup**

```sql
-- AEP asks: "Which customers are hot leads with propensity > 0.8?"
SELECT email_sha256, ecid
FROM `company-project.aep_federated.hot_leads`
WHERE propensity_score > 0.8
  AND score_date >= CURRENT_DATE() - 7
;
```

**Optimization:**
- **Partition** by `score_date` (AEP always filters recent data)
- **Cluster** by `propensity_score` (common filter in WHERE clause)
- **Materialized view** refreshed hourly (pre-computed, instant query)

**Pattern 2: Multi-Attribute Segmentation**

```sql
-- AEP asks: "Customers in lifecycle stage X with product affinity Y"
SELECT DISTINCT i.email_sha256
FROM `company-project.aep_federated.lifecycle_segments` l
INNER JOIN `company-project.aep_federated.product_affinity_segments` p
  ON l.email_sha256 = p.email_sha256
WHERE l.customer_lifecycle_stage = 'ACTIVE'
  AND l.customer_tier = 'PREMIUM'
  AND p.affinity_product_category = 'INVESTMENT_PRODUCTS'
  AND p.affinity_score >= 0.6
;
```

**Optimization:**
- **Denormalize** common joins into single materialized view (avoid JOIN overhead)
- **Cluster** by frequently filtered columns (`customer_lifecycle_stage`, `customer_tier`)
- **Monitor** query patterns in BigQuery audit logs, adjust clustering accordingly

**B. Partition & Clustering Strategy**

```sql
-- Optimal table design for AEP federated queries
CREATE TABLE `company-project.aep_federated.customer_segments_optimized`
PARTITION BY score_date
CLUSTER BY customer_tier, lifecycle_stage, propensity_score
OPTIONS(
  partition_expiration_days=90,  -- Auto-delete old partitions
  require_partition_filter=true  -- Force AEP to always filter by date
)
AS
SELECT
  email_sha256,
  ecid,
  score_date,
  customer_tier,
  lifecycle_stage,
  propensity_score,
  recommended_product,
  affinity_category
FROM ...
;
```

**Why this works:**
- **Partition pruning:** AEP queries only scan recent partitions (7-30 days typical), reducing cost by 95%
- **Clustering:** Within partition, data sorted by most common filter columns → 10-50x faster queries
- **Partition expiration:** Old data auto-deleted, reduces storage costs and query surface area

**C. Materialized Views vs Regular Views**

| View Type | Refresh Cost | Query Cost | Latency | When to Use |
|-----------|--------------|------------|---------|-------------|
| **Materialized View** | €5-20/day (refresh hourly) | €0.001/query (pre-computed) | <1 second | Hot data, queried frequently by AEP |
| **Regular View** | €0 (no pre-compute) | €0.05-0.50/query (compute on-demand) | 5-30 seconds | Cold data, queried rarely |

**Recommendation:** Use materialized views for:
- `hot_leads` (AEP queries this constantly for campaign activation)
- `identity_mapping` (every AEP query needs this for identity resolution)
- `lifecycle_segments` (common segmentation criteria)

Use regular views for:
- `product_affinity_segments` (queried occasionally, expensive to maintain)
- `transaction_history_aggregates` (rare use, complex query)

**Cost Example:**
- Materialized view refreshed every hour: 24 refreshes/day × €0.25/refresh = €6/day
- AEP queries the view 10,000 times/day: 10,000 × €0.001 = €10/day
- **Total: €16/day = €480/month**

- Regular view (no refresh): €0/day
- AEP queries 10,000 times/day: 10,000 × €0.10 = €1,000/day
- **Total: €30,000/month**

**Materialized views are 62x cheaper for frequently queried data.**

**D. Slot Reservations vs On-Demand**

For predictable AEP query workloads, consider BigQuery slot reservations:

**On-Demand Pricing:**
- €5 per TB scanned
- Subject to slot availability (can be throttled during peak)
- Unpredictable costs if AEP query volume spikes

**Slot Reservations (Flex Slots):**
- €0.04 per slot-hour (minimum 100 slots)
- 100 slots = €0.04 × 100 × 24 = €96/day = €2,880/month
- **Guaranteed performance** (no throttling, queries run immediately)
- Cost-effective if scanning >600 TB/month on-demand

**Recommendation for AEP Federated Queries:**
- **Start with on-demand** to establish baseline (1-3 months)
- **Monitor query costs** in BigQuery billing dashboard
- **Switch to flex slots** if monthly query cost exceeds €2,500-3,000
- **Use slot reservations for production**, on-demand for dev/test

#### 2.4.6 Data Preparation for AEP Consumption

**A. Exposing Lead Scores to AEP**

Create a single, AEP-optimized view that combines all segmentation signals:

```sql
-- Master view for AEP federated audience composition
CREATE MATERIALIZED VIEW `company-project.aep_federated.audience_master`
PARTITION BY score_date
CLUSTER BY lead_category, customer_tier, propensity_score
OPTIONS(
  enable_refresh = true,
  refresh_interval_minutes = 60,
  description = "Master view for AEP federated audience composition - all signals combined"
)
AS
SELECT
  -- Identity resolution
  i.email_sha256,
  i.phone_sha256,
  i.ecid,

  -- Lead scoring (Cold/Warm/Hot)
  s.lead_category,
  s.propensity_score,
  s.recommended_product,
  s.score_confidence,
  s.score_date,

  -- Customer attributes (high-level only)
  c.customer_tier,              -- RETAIL, PREMIUM, PRIVATE_BANKING
  c.customer_lifecycle_stage,   -- PROSPECT, ONBOARDING, ACTIVE, AT_RISK, DORMANT
  c.customer_tenure_months,
  c.customer_age_group,         -- 18-25, 26-35, 36-45, 46-55, 56-65, 65+
  c.customer_region,            -- DE-BY, DE-BE, DE-HH, etc.

  -- Product affinity (top 3 categories)
  pa.affinity_1_category,
  pa.affinity_1_score,
  pa.affinity_2_category,
  pa.affinity_2_score,
  pa.affinity_3_category,
  pa.affinity_3_score,

  -- Engagement indicators (aggregated, not raw events)
  e.days_since_last_login,
  e.mobile_app_sessions_last_30d,
  e.web_sessions_last_30d,
  e.rm_interactions_last_90d,
  e.email_engagement_score,     -- 0.0-1.0 (open rate, click rate)

  -- Campaign history (summary only)
  ch.campaigns_received_last_90d,
  ch.campaigns_responded_last_90d,
  ch.last_campaign_response_date,

  -- Risk indicators (for exclusion rules)
  r.credit_risk_flag,           -- BOOLEAN: high risk customers to exclude
  r.fraud_risk_score,           -- 0.0-1.0
  r.collections_flag,           -- BOOLEAN: in collections, exclude from marketing

  -- Compliance flags
  c.gdpr_consent_marketing,     -- BOOLEAN: only TRUE customers exposed
  c.gdpr_consent_profiling,
  c.data_processing_restriction, -- BOOLEAN: if TRUE, exclude from automated decisions

  -- Metadata
  s.last_updated as data_freshness_timestamp

FROM `company-project.gold.customer_lead_scores` s
INNER JOIN `company-project.gold.customers` c
  ON s.customer_id = c.customer_id
INNER JOIN `company-project.aep_federated.identity_mapping` i
  ON c.customer_id = i.customer_id
LEFT JOIN `company-project.gold.product_affinity_top3` pa
  ON c.customer_id = pa.customer_id
LEFT JOIN `company-project.gold.customer_engagement_metrics` e
  ON c.customer_id = e.customer_id
LEFT JOIN `company-project.gold.campaign_history_summary` ch
  ON c.customer_id = ch.customer_id
LEFT JOIN `company-project.gold.risk_indicators` r
  ON c.customer_id = r.customer_id

WHERE s.score_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
  AND c.customer_status = 'ACTIVE'
  AND c.gdpr_consent_marketing = TRUE  -- Only expose consented customers
  AND COALESCE(c.data_processing_restriction, FALSE) = FALSE
;
```

**Key Design Decisions:**

1. **Hashed Identities Only:** `email_sha256`, `phone_sha256` - never plain PII
2. **Aggregated Metrics:** "sessions last 30 days" not raw session events
3. **Categorical Attributes:** `customer_age_group` not exact date of birth
4. **Compliance Filters:** Only customers with `gdpr_consent_marketing = TRUE`
5. **Temporal Partitioning:** Last 90 days only, older data not exposed

**B. Identity Mapping Strategy**

AEP's identity graph needs to resolve BigQuery customer_id to AEP namespaces. Create robust mapping:

```sql
-- Comprehensive identity mapping with conflict resolution
CREATE OR REPLACE TABLE `company-project.aep_federated.identity_mapping`
PARTITION BY DATE(last_updated)
CLUSTER BY customer_id, email_sha256
AS
WITH latest_identities AS (
  SELECT
    customer_id,
    email,
    phone,
    adobe_ecid,  -- If you have Adobe Analytics integrated
    ROW_NUMBER() OVER (
      PARTITION BY customer_id
      ORDER BY last_updated DESC
    ) as rn
  FROM `company-project.silver.customer_identities`
  WHERE customer_status = 'ACTIVE'
)
SELECT
  customer_id,

  -- Hashed identities (privacy-preserving)
  SHA256(LOWER(TRIM(email))) as email_sha256,
  SHA256(REGEXP_REPLACE(phone, r'[^0-9]', '')) as phone_sha256,

  -- Adobe identifiers (if available)
  adobe_ecid as ecid,

  -- Identity metadata
  'ACTIVE' as identity_status,
  TRUE as primary_identity,
  CURRENT_TIMESTAMP() as last_updated,

  -- Identity sources (for debugging)
  'GCP_CRM' as source_system

FROM latest_identities
WHERE rn = 1  -- Most recent identity only
  AND email IS NOT NULL
  AND email LIKE '%@%'  -- Basic email validation
;

-- Create index for fast lookups
CREATE INDEX idx_customer_id ON `company-project.aep_federated.identity_mapping`(customer_id);
CREATE INDEX idx_email_sha256 ON `company-project.aep_federated.identity_mapping`(email_sha256);
```

**C. Data Freshness Strategies**

| Refresh Pattern | Latency | Cost | Use Case |
|----------------|---------|------|----------|
| **Real-time (CDC)** | <1 minute | High (€500+/month) | Transaction fraud, hot lead instant follow-up |
| **Micro-batch (15 min)** | 15 minutes | Medium (€200/month) | Behavior-triggered campaigns |
| **Hourly** | 1 hour | Low (€50/month) | Daily marketing campaigns |
| **Daily** | 24 hours | Very Low (€10/month) | Weekly newsletters, batch campaigns |

**For lead scoring, I recommend hourly refresh:**

```sql
-- Schedule materialized view refresh
ALTER MATERIALIZED VIEW `company-project.aep_federated.audience_master`
SET OPTIONS (
  enable_refresh = true,
  refresh_interval_minutes = 60  -- Hourly refresh
);
```

**Why hourly?**
- Lead scores don't change minute-by-minute (behavioral patterns are slower)
- Balances freshness with cost (€50/month vs €500+ for real-time)
- AEP campaigns typically activate hourly/daily, not real-time

**For true real-time needs** (e.g., fraud detection), use Pattern A (Event-Driven Push) instead of federated queries.

#### 2.4.7 Security & Compliance for Federated Queries

**A. EU Data Residency**

**Critical Question:** Where does AEP execute federated queries from?

**Answer:** Adobe's federated query engine runs in **AEP's data center region**. For EU customers, this should be Adobe's EU region (NLD2 - Netherlands or IRL1 - Ireland).

**Verify with Adobe:**
```
Request: "Which data center region will execute BigQuery federated queries for our tenant?"
Required Answer: "EU region (NLD2 or IRL1)"
Unacceptable: "US region" - this would violate data residency requirements
```

**If AEP queries from EU region:**
- **Data stays in europe-west3 (BigQuery)** ✓
- **Query execution in EU (AEP)** ✓
- **Results transmitted within EU** ✓
- **Compliance satisfied** ✓

**If AEP queries from US region:**
- **Data stays in europe-west3** ✓
- **Query execution in US (AEP)** ✗ - potential GDPR violation
- **Results transmitted EU→US** ✗ - data export issue
- **Need Standard Contractual Clauses** with Adobe

**Recommendation:** Document AEP's query execution region in your data processing agreement with Adobe. If US-based, ensure SCCs are in place.

**B. Audit Logging for AEP Access**

Enable comprehensive audit logging for every AEP query:

```bash
# Enable BigQuery data access logs (not enabled by default)
gcloud logging sinks create aep-bigquery-audit-sink \
  bigquery.googleapis.com/projects/company-project/datasets/audit_logs \
  --log-filter='protoPayload.serviceName="bigquery.googleapis.com"
    AND protoPayload.authenticationInfo.principalEmail="aep-federated-query@company-project.iam.gserviceaccount.com"' \
  --project=company-project
```

**Create audit dashboard:**

```sql
-- Query to monitor AEP's BigQuery access
SELECT
  TIMESTAMP(protopayload_auditlog.authenticationInfo.principalEmail) as query_time,
  protopayload_auditlog.authenticationInfo.principalEmail as querying_principal,
  protopayload_auditlog.resourceName as table_queried,
  protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalBilledBytes as bytes_billed,
  protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalSlotMs as slot_ms_consumed,
  protopayload_auditlog.request as query_text
FROM `company-project.audit_logs.cloudaudit_googleapis_com_data_access_*`
WHERE protopayload_auditlog.authenticationInfo.principalEmail = 'aep-federated-query@company-project.iam.gserviceaccount.com'
  AND protopayload_auditlog.methodName = 'jobservice.query'
ORDER BY query_time DESC
LIMIT 100;
```

**Alert on suspicious activity:**

```yaml
# Cloud Monitoring alert policy
displayName: "AEP Federated Query - Excessive Data Access"
conditions:
  - displayName: "AEP queried >100GB in 1 hour"
    conditionThreshold:
      filter: |
        resource.type="bigquery_project"
        protoPayload.authenticationInfo.principalEmail="aep-federated-query@company-project.iam.gserviceaccount.com"
      aggregations:
        - alignmentPeriod: 3600s
          perSeriesAligner: ALIGN_SUM
          crossSeriesReducer: REDUCE_SUM
          groupByFields:
            - protoPayload.authenticationInfo.principalEmail
      comparison: COMPARISON_GT
      thresholdValue: 107374182400  # 100 GB in bytes
notificationChannels:
  - projects/company-project/notificationChannels/security-team-email
```

**C. Row-Level Security (If Needed)**

For multi-tenant scenarios (e.g., different business units), implement row-level security:

```sql
-- Create row access policy (BigQuery row-level security)
CREATE ROW ACCESS POLICY aep_premium_customers_only
ON `company-project.aep_federated.audience_master`
GRANT TO ("serviceAccount:aep-federated-query@company-project.iam.gserviceaccount.com")
FILTER USING (customer_tier IN ('PREMIUM', 'PRIVATE_BANKING'));
```

**Use case:** If AEP should only access premium customer segments, not retail customers.

**D. PII Protection Strategies**

**Never expose in federated views:**
- Full names (first name, last name)
- Exact dates of birth
- Precise geolocation (street address)
- Account balances, transaction amounts
- Credit scores (exact values)
- Social security numbers, tax IDs

**Safe to expose:**
- Hashed identifiers (SHA-256 of email/phone)
- Age groups (18-25, 26-35, etc.)
- Region codes (DE-BY, DE-BE)
- Customer tier (RETAIL, PREMIUM, PRIVATE_BANKING)
- Propensity scores (0.0-1.0)
- Product category affinities (not specific products viewed)

**Pseudonymization technique:**

```sql
-- Create pseudonymous customer identifiers for AEP
SELECT
  -- Pseudonymous ID (deterministic hash, but not reversible)
  TO_BASE64(SHA256(CONCAT(customer_id, 'salt_secret_2025'))) as aep_customer_id,

  -- Hashed PII
  SHA256(email) as email_sha256,

  -- Aggregated metrics only
  propensity_score,
  customer_tier
FROM ...
```

**E. GDPR Compliance When Data Stays in BigQuery**

**Right to Access (Article 15):**
- Customer requests: "What data do you share with Adobe?"
- Query audit logs for that customer's AEP access history
- Return: "Your propensity score and segment membership were queried 47 times in the last 30 days"

**Right to Erasure (Article 17):**
- Customer requests deletion
- Steps:
  1. Delete from BigQuery tables (including identity_mapping)
  2. Materialized views auto-refresh (customer disappears from AEP queries)
  3. Notify AEP to delete external audience memberships (AEP API call)

**Implementation:**

```sql
-- GDPR deletion procedure
CREATE OR REPLACE PROCEDURE `company-project.gdpr.delete_customer_data`(customer_email STRING)
BEGIN
  -- 1. Find customer_id from email
  DECLARE customer_id_to_delete STRING;
  SET customer_id_to_delete = (
    SELECT customer_id
    FROM `company-project.silver.customers`
    WHERE email = customer_email
    LIMIT 1
  );

  -- 2. Delete from identity mapping (removes from AEP exposure)
  DELETE FROM `company-project.aep_federated.identity_mapping`
  WHERE customer_id = customer_id_to_delete;

  -- 3. Delete from lead scores
  DELETE FROM `company-project.gold.customer_lead_scores`
  WHERE customer_id = customer_id_to_delete;

  -- 4. Mark in customers table as deleted (retain for regulatory period)
  UPDATE `company-project.silver.customers`
  SET
    customer_status = 'DELETED',
    gdpr_deletion_date = CURRENT_TIMESTAMP(),
    email = NULL,
    phone = NULL
  WHERE customer_id = customer_id_to_delete;

  -- 5. Log deletion for audit
  INSERT INTO `company-project.audit.gdpr_deletions` (
    deletion_timestamp, customer_id, customer_email, deletion_reason
  )
  VALUES (
    CURRENT_TIMESTAMP(), customer_id_to_delete, customer_email, 'GDPR_RIGHT_TO_ERASURE'
  );

  -- 6. TODO: Call AEP API to remove from external audiences (implement separately)
  -- Requires Cloud Function to invoke AEP's Profile API DELETE endpoint
END;
```

#### 2.4.8 Integration Patterns: When to Use Federated vs Push/Pull

**Pattern Decision Matrix:**

| Use Case | Recommended Pattern | Rationale |
|----------|---------------------|-----------|
| **Audience segmentation for campaigns** | **Federated (D)** | Data stays in BigQuery, AEP only gets audience membership lists |
| **Hot lead instant activation (<1 min)** | **Event-Driven Push (A)** | Federated queries have 5-30s latency, too slow for real-time |
| **Daily segment sync (batch campaigns)** | **Batch Sync (C)** | Cheaper than federated for full-table exports |
| **On-demand profile enrichment** | **API Pull (B)** | AEP calls GCP when needed, better for unpredictable access |
| **Multi-attribute complex segmentation** | **Federated (D)** | AEP's federated query engine handles complex WHERE clauses |
| **Real-time personalization (web/mobile)** | **Event-Driven Push (A)** | Sub-second latency required, federated too slow |
| **Regulatory compliance (data minimization)** | **Federated (D)** | Raw data never leaves BigQuery, only results transmitted |
| **Cost optimization (high query volume)** | **Federated (D)** with materialized views | Pre-computed views eliminate per-query costs |

**Hybrid Strategy (Recommended for Production):**

```
┌─────────────────────────────────────────────────────────────┐
│                     AEP Integration Strategy                │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. Federated Audience Composition (Pattern D)              │
│     - Batch/scheduled campaigns (daily, weekly)             │
│     - Complex multi-dimensional segmentation                │
│     - Audience discovery and exploration                    │
│     → Cost: €50-200/month                                   │
│                                                             │
│  2. Event-Driven Push (Pattern A)                           │
│     - Hot lead instant activation (propensity > 0.9)        │
│     - Transaction-triggered campaigns (fraud, upsell)       │
│     - Real-time behavioral responses                        │
│     → Cost: €25-100/month                                   │
│                                                             │
│  3. Batch Reconciliation (Pattern C)                        │
│     - Weekly full segment refresh (validate federated)      │
│     - Fallback if federated queries fail                    │
│     - Historical audience snapshots for reporting           │
│     → Cost: €10-20/month                                    │
│                                                             │
│  TOTAL: €85-320/month for comprehensive integration         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Specific Use Case Recommendations:**

**Use Federated Composition (Pattern D) when:**
- Building audiences in AEP UI (drag-drop segmentation)
- Segmentation criteria change frequently (no need to re-export data)
- Data governance requires data to stay in GCP
- You want to leverage AEP's audience builder without data duplication
- Query volume is predictable (<10,000 queries/day)

**Use Event-Driven Push (Pattern A) when:**
- Latency <1 second required (real-time triggers)
- AEP needs to react to events immediately (hot lead follow-up)
- Specific trigger events (callback request, application started)
- Query pattern is simple (segment membership only, no complex WHERE clauses)

**Use API Pull (Pattern B) when:**
- AEP needs on-demand data enrichment (rare)
- Access pattern is unpredictable (can't pre-compute)
- Want to avoid egress costs (AEP pulls, GCP doesn't push)
- Need fine-grained access control per query

**Use Batch Sync (Pattern C) when:**
- Daily/weekly campaign cadence is acceptable
- Full segment export needed (not just changes)
- Want lowest cost option (€10/month)
- Federated queries are too expensive for your volume

#### 2.4.9 Cost Analysis: Federated vs Push Patterns

**Scenario: 1 million customers, 50 segments updated daily**

**Federated Audience Composition (Pattern D):**

```
Costs:
- Materialized view refresh (hourly): 24 × €0.25 = €6/day
- AEP queries (10,000 queries/day × €0.001) = €10/day
- BigQuery storage (1 TB audience data): €20/month
- Total: €500/month

Data Transfer: 0 GB (raw data stays in BigQuery, only results sent)
Latency: 5-30 seconds per query
Complexity: Medium (requires BigQuery optimization)
```

**Event-Driven Push (Pattern A):**

```
Costs:
- Pub/Sub (1M events/day × 2KB): €0.24/day
- Cloud Functions (1M invocations): €0.40/day
- Egress to AEP (2 GB/day): €0.17/day
- Total: €25/month

Data Transfer: 60 GB/month (only segment membership + scores)
Latency: <1 second
Complexity: Medium (requires event pipeline)
```

**Batch Sync (Pattern C):**

```
Costs:
- BigQuery query (100 GB scanned/day): €0.50/day
- Cloud Storage (100 GB/day): €2/month
- Egress (3 GB/day): €0.25/day
- Total: €10/month

Data Transfer: 90 GB/month (full segment exports)
Latency: 24 hours
Complexity: Low (simple scheduled query)
```

**Cost Comparison Table:**

| Pattern | Monthly Cost | Data Transfer | Latency | Best For |
|---------|-------------|---------------|---------|----------|
| **Federated (D)** | €500 | 0 GB (raw data) | 5-30s | Complex segmentation, data governance |
| **Event-Driven (A)** | €25 | 60 GB (scores only) | <1s | Real-time activation |
| **Batch (C)** | €10 | 90 GB (full export) | 24h | Daily campaigns |
| **API Pull (B)** | €200 | 0 GB (AEP pulls) | <500ms | On-demand enrichment |

**Cost Optimization Strategies:**

1. **Use federated for discovery, push for activation:**
   - Explore segments in AEP using federated queries (ad-hoc)
   - Once segment defined, switch to event-driven push (production)
   - Saves €475/month vs using only federated

2. **Materialized views are essential:**
   - Without: €10,000/month (10K queries × €1/query)
   - With: €300/month (materialized view refresh + minimal query cost)
   - **Savings: €9,700/month**

3. **Partition/cluster aggressively:**
   - Unoptimized: scan 1 TB per query = €5/query
   - Optimized (partitioned): scan 1 GB per query = €0.005/query
   - **1000x cost reduction**

#### 2.4.10 Operational Considerations

**A. Monitoring Federated Query Performance**

Create monitoring dashboard for AEP query health:

```sql
-- Query performance monitoring
WITH query_stats AS (
  SELECT
    TIMESTAMP_TRUNC(timestamp, HOUR) as hour,
    COUNT(*) as query_count,
    AVG(CAST(JSON_EXTRACT_SCALAR(protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalSlotMs) AS INT64)) as avg_slot_ms,
    AVG(CAST(JSON_EXTRACT_SCALAR(protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalBilledBytes) AS INT64)) as avg_bytes_billed,
    AVG(TIMESTAMP_DIFF(
      TIMESTAMP(JSON_EXTRACT_SCALAR(protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.endTime)),
      TIMESTAMP(JSON_EXTRACT_SCALAR(protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.startTime)),
      MILLISECOND
    )) as avg_query_duration_ms
  FROM `company-project.audit_logs.cloudaudit_googleapis_com_data_access_*`
  WHERE protopayload_auditlog.authenticationInfo.principalEmail = 'aep-federated-query@company-project.iam.gserviceaccount.com'
    AND protopayload_auditlog.methodName = 'jobservice.query'
    AND timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
  GROUP BY hour
)
SELECT
  hour,
  query_count,
  avg_query_duration_ms / 1000 as avg_query_duration_seconds,
  avg_bytes_billed / 1024 / 1024 / 1024 as avg_gb_scanned,
  (avg_bytes_billed / 1024 / 1024 / 1024 / 1024) * 5 as estimated_cost_per_query_eur
FROM query_stats
ORDER BY hour DESC;
```

**Set up alerts:**

```yaml
# Cloud Monitoring alert: Slow AEP queries
displayName: "AEP Federated Query - Slow Performance"
conditions:
  - displayName: "Average query duration >30 seconds"
    conditionThreshold:
      filter: |
        resource.type="bigquery_project"
        protoPayload.serviceName="bigquery.googleapis.com"
        protoPayload.authenticationInfo.principalEmail="aep-federated-query@company-project.iam.gserviceaccount.com"
      aggregations:
        - alignmentPeriod: 300s
          perSeriesAligner: ALIGN_MEAN
      comparison: COMPARISON_GT
      thresholdValue: 30000  # 30 seconds in milliseconds
notificationChannels:
  - projects/company-project/notificationChannels/data-engineering-team
```

**B. Alerting on Failed AEP Queries**

```sql
-- Detect failed queries
SELECT
  timestamp,
  JSON_EXTRACT_SCALAR(protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatus.error, '$.message') as error_message,
  JSON_EXTRACT_SCALAR(protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobConfiguration.query, '$.query') as failed_query
FROM `company-project.audit_logs.cloudaudit_googleapis_com_data_access_*`
WHERE protopayload_auditlog.authenticationInfo.principalEmail = 'aep-federated-query@company-project.iam.gserviceaccount.com'
  AND protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatus.error IS NOT NULL
  AND timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
ORDER BY timestamp DESC;
```

**Common failure modes and fixes:**

| Error | Cause | Fix |
|-------|-------|-----|
| `Resources exceeded during query execution` | Query scans too much data | Add partition filter, use materialized view |
| `Access Denied: Table company-project:dataset.table` | IAM permissions missing | Grant `bigquery.dataViewer` on table |
| `Exceeded rate limits` | Too many queries in short time | Implement query throttling, use caching |
| `Table not found` | Materialized view still refreshing | Increase refresh interval, use base table as fallback |

**C. Schema Evolution Management**

**Challenge:** What happens when you change BigQuery schema and AEP expects old schema?

**Strategy: Versioned Views**

```sql
-- Version 1 (current, AEP uses this)
CREATE OR REPLACE VIEW `company-project.aep_federated.audience_master_v1` AS
SELECT
  email_sha256,
  lead_category,
  propensity_score,
  recommended_product
FROM `company-project.aep_federated.audience_master`;

-- Version 2 (new schema, testing phase)
CREATE OR REPLACE VIEW `company-project.aep_federated.audience_master_v2` AS
SELECT
  email_sha256,
  lead_category,
  propensity_score,
  recommended_product,
  -- NEW COLUMNS
  affinity_score,
  customer_lifetime_value_predicted
FROM `company-project.aep_federated.audience_master`;

-- Migration plan:
-- 1. Deploy v2 view
-- 2. Test with AEP in dev environment
-- 3. Update AEP connection to point to v2
-- 4. Deprecate v1 after 30 days
```

**Backward compatibility:**

```sql
-- Ensure backward compatibility with NULL defaults for new columns
CREATE OR REPLACE VIEW `company-project.aep_federated.audience_master_v2_compatible` AS
SELECT
  email_sha256,
  lead_category,
  propensity_score,
  recommended_product,
  COALESCE(affinity_score, 0.0) as affinity_score,  -- Default for old queries
  COALESCE(customer_lifetime_value_predicted, 0.0) as customer_lifetime_value_predicted
FROM `company-project.aep_federated.audience_master`;
```

**D. Troubleshooting AEP Connection Issues**

**Issue 1: AEP can't connect to BigQuery**

**Diagnosis:**
```bash
# Verify service account key is valid
gcloud iam service-accounts keys list \
  --iam-account=aep-federated-query@company-project.iam.gserviceaccount.com

# Test authentication from local machine (simulates AEP)
gcloud auth activate-service-account \
  --key-file=aep-federated-key.json

bq query --use_legacy_sql=false \
  'SELECT COUNT(*) FROM `company-project.aep_federated.audience_master`'
```

**Fix:**
- Regenerate service account key
- Verify IAM permissions (`roles/bigquery.jobUser`, `roles/bigquery.dataViewer`)
- Check VPC Service Controls aren't blocking access

**Issue 2: Queries timeout after 30 seconds**

**Diagnosis:**
- Check if table is partitioned/clustered
- Verify materialized view is refreshed

**Fix:**
```sql
-- Force refresh materialized view
CALL BQ.REFRESH_MATERIALIZED_VIEW('company-project.aep_federated.audience_master');

-- Verify refresh status
SELECT
  creation_time,
  last_refresh_time,
  refresh_watermark
FROM `company-project.aep_federated.INFORMATION_SCHEMA.MATERIALIZED_VIEWS`
WHERE table_name = 'audience_master';
```

**Issue 3: Costs spike unexpectedly**

**Diagnosis:**
```sql
-- Identify expensive queries
SELECT
  TIMESTAMP_TRUNC(timestamp, DAY) as date,
  SUM(CAST(JSON_EXTRACT_SCALAR(protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalBilledBytes) AS INT64)) / 1024 / 1024 / 1024 / 1024 as total_tb_billed,
  SUM(CAST(JSON_EXTRACT_SCALAR(protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalBilledBytes) AS INT64)) / 1024 / 1024 / 1024 / 1024 * 5 as estimated_cost_eur
FROM `company-project.audit_logs.cloudaudit_googleapis_com_data_access_*`
WHERE protopayload_auditlog.authenticationInfo.principalEmail = 'aep-federated-query@company-project.iam.gserviceaccount.com'
  AND timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
GROUP BY date
ORDER BY date DESC;
```

**Fix:**
- Implement query result caching (BigQuery caches results for 24 hours)
- Add `require_partition_filter=true` to force AEP to filter by date
- Switch to slot reservations for cost predictability

#### 2.4.11 Example Implementation: Complete Setup

**Step-by-step implementation guide:**

**Step 1: Create BigQuery Infrastructure**

```bash
# Set environment variables
export PROJECT_ID="company-project"
export REGION="europe-west3"
export AEP_SA_EMAIL="aep-federated-query@${PROJECT_ID}.iam.gserviceaccount.com"

# Create datasets
bq mk --location=${REGION} --description="Federated views for AEP" ${PROJECT_ID}:aep_federated
bq mk --location=${REGION} --description="Temporary query results for AEP" \
  --default_table_expiration=3600 ${PROJECT_ID}:aep_query_temp
```

**Step 2: Deploy Identity Mapping & Lead Score Views**

```sql
-- File: deploy_aep_federated_views.sql

-- 1. Identity mapping
CREATE OR REPLACE TABLE `company-project.aep_federated.identity_mapping`
PARTITION BY DATE(last_updated)
CLUSTER BY customer_id, email_sha256
AS
SELECT
  customer_id,
  SHA256(LOWER(TRIM(email))) as email_sha256,
  SHA256(REGEXP_REPLACE(phone, r'[^0-9]', '')) as phone_sha256,
  adobe_ecid as ecid,
  'ACTIVE' as identity_status,
  TRUE as primary_identity,
  CURRENT_TIMESTAMP() as last_updated
FROM `company-project.silver.customers`
WHERE customer_status = 'ACTIVE'
  AND email IS NOT NULL;

-- 2. Hot leads materialized view
CREATE MATERIALIZED VIEW `company-project.aep_federated.hot_leads`
PARTITION BY score_date
CLUSTER BY propensity_score
OPTIONS(
  enable_refresh = true,
  refresh_interval_minutes = 60
)
AS
SELECT
  i.email_sha256,
  i.ecid,
  s.lead_category,
  s.propensity_score,
  s.recommended_product,
  s.score_date,
  c.customer_tier
FROM `company-project.gold.customer_lead_scores` s
INNER JOIN `company-project.silver.customers` c ON s.customer_id = c.customer_id
INNER JOIN `company-project.aep_federated.identity_mapping` i ON c.customer_id = i.customer_id
WHERE s.lead_category = 'HOT'
  AND c.gdpr_consent_marketing = TRUE
  AND s.score_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY);
```

**Deploy:**

```bash
bq query --use_legacy_sql=false < deploy_aep_federated_views.sql
```

**Step 3: Create Service Account & Grant Permissions**

```bash
# Create service account
gcloud iam service-accounts create aep-federated-query \
  --display-name="AEP Federated Audience Composition" \
  --project=${PROJECT_ID}

# Grant permissions
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
  --member="serviceAccount:${AEP_SA_EMAIL}" \
  --role="roles/bigquery.jobUser"

bq add-iam-policy-binding \
  --member="serviceAccount:${AEP_SA_EMAIL}" \
  --role="roles/bigquery.dataViewer" \
  ${PROJECT_ID}:aep_federated

bq add-iam-policy-binding \
  --member="serviceAccount:${AEP_SA_EMAIL}" \
  --role="roles/bigquery.dataEditor" \
  ${PROJECT_ID}:aep_query_temp

# Generate key
gcloud iam service-accounts keys create aep-federated-key.json \
  --iam-account=${AEP_SA_EMAIL}

# Store in Secret Manager
gcloud secrets create aep-federated-sa-key \
  --data-file=aep-federated-key.json \
  --replication-policy=user-managed \
  --locations=${REGION}

# Clean up local key
rm aep-federated-key.json
```

**Step 4: Configure AEP Connection**

In Adobe Experience Platform UI:

1. Navigate to **Sources** → **Google BigQuery**
2. Click **Add data**
3. Configure connection:
   - **Connection name:** `GCP BigQuery - Federated Audiences`
   - **Project ID:** `company-project`
   - **Service account email:** `aep-federated-query@company-project.iam.gserviceaccount.com`
   - **Service account key:** (paste JSON key from Secret Manager)
   - **Dataset:** `aep_federated`
4. Test connection (AEP will query BigQuery to verify)
5. Configure data flow:
   - **Source table:** `hot_leads`
   - **Target dataset:** `Federated Leads`
   - **Scheduling:** Real-time (federated queries on-demand)

**Step 5: Create Federated Audience in AEP**

1. Navigate to **Audiences** → **Browse**
2. Click **Create audience** → **Build rule**
3. Select **Federated Audience Composition**
4. Select BigQuery source: `GCP BigQuery - Federated Audiences`
5. Build audience rule:
   ```
   WHERE propensity_score > 0.8
   AND customer_tier IN ('PREMIUM', 'PRIVATE_BANKING')
   AND score_date >= (TODAY - 7 DAYS)
   ```
6. Save audience: `Hot Leads - Premium Banking`
7. AEP executes query against BigQuery and creates external audience

**Step 6: Monitor & Validate**

```sql
-- Verify AEP queries are being logged
SELECT
  timestamp,
  protopayload_auditlog.authenticationInfo.principalEmail as principal,
  JSON_EXTRACT_SCALAR(protopayload_auditlog.request, '$.query') as query,
  CAST(JSON_EXTRACT_SCALAR(protopayload_auditlog.servicedata_v1_bigquery.jobCompletedEvent.job.jobStatistics.totalBilledBytes) AS INT64) / 1024 / 1024 as mb_billed
FROM `company-project.audit_logs.cloudaudit_googleapis_com_data_access_*`
WHERE protopayload_auditlog.authenticationInfo.principalEmail = 'aep-federated-query@company-project.iam.gserviceaccount.com'
  AND timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
ORDER BY timestamp DESC
LIMIT 10;
```

**Sample AEP Federated Query (what AEP sends to BigQuery):**

```sql
-- This is what AEP's federated query engine generates
SELECT
  email_sha256,
  ecid
FROM `company-project.aep_federated.hot_leads`
WHERE propensity_score > 0.8
  AND customer_tier IN ('PREMIUM', 'PRIVATE_BANKING')
  AND score_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
LIMIT 1000000;
```

**Result:** AEP receives list of customer identifiers (email_sha256, ecid) matching the criteria. Raw data stays in BigQuery.

---

### 2.5 Pattern Comparison Matrix

| Criterion | Event-Driven (A) | API Pull (B) | Batch Sync (C) | **Federated (D)** |
|-----------|------------------|--------------|----------------|-------------------|
| **Latency** | <1 second | <500ms per request | 24 hours | 5-30 seconds |
| **Cost (monthly, 1M updates)** | ~€25 | ~€200 | ~€10 | ~€500 (optimized) |
| **Complexity** | Medium | High | Low | Medium-High |
| **Data transfer** | 60 GB/month | 0 GB (pull) | 90 GB/month | **0 GB raw data** |
| **Raw data location** | Partial copy to AEP | Stays in GCP | Full copy to AEP | **Stays in BigQuery** |
| **Egress costs** | Moderate | Zero (AEP pulls) | Low (batch) | Minimal (results only) |
| **Compliance audit** | Good (event logs) | Excellent (per-request logs) | Excellent (batch manifests) | Excellent (query logs) |
| **Data governance** | Good (pre-filtered) | Excellent (on-demand control) | Moderate (batch exports) | **Excellent (data never leaves)** |
| **Scalability** | Excellent (Pub/Sub) | Good (Cloud Run autoscale) | Excellent (BigQuery) | Excellent (BigQuery) |
| **Failure handling** | Retry + DLQ | AEP retries | Manual rerun | AEP retries query |
| **Query flexibility** | Pre-defined segments | API-defined | Pre-defined batches | **AEP defines queries** |
| **Schema evolution** | Update Cloud Function | Update API | Update export query | Update views (versioned) |
| **Best for** | Real-time activation | On-demand enrichment | Daily batch campaigns | **Complex segmentation** |
| **Recommended for** | Hot leads <1s latency | Unpredictable access | Weekly newsletters | **Multi-dimensional audiences** |

**Updated Recommendation - Federated Composition Changes the Game:**

**For zero-copy architecture, prioritize Pattern D (Federated Audience Composition)** as your primary integration method. This is the **only true zero-copy pattern** where raw data never leaves BigQuery. AEP queries your data in-place and only receives audience membership results.

**Recommended Hybrid Strategy:**

1. **Pattern D (Federated)** - PRIMARY for 80% of use cases:
   - All audience segmentation and campaign targeting
   - Complex multi-dimensional queries (lifecycle stage + product affinity + propensity score)
   - Exploratory audience discovery in AEP UI
   - Data governance requirements (raw data stays in GCP)
   - Cost: €50-500/month depending on query volume

2. **Pattern A (Event-Driven Push)** - SECONDARY for real-time only:
   - Critical hot lead instant activation (<1 second required)
   - Transaction-triggered campaigns (fraud alerts, upsell moments)
   - Only when federated query latency (5-30s) is unacceptable
   - Cost: €25-100/month

3. **Pattern C (Batch Sync)** - FALLBACK for reconciliation:
   - Weekly full segment refresh to validate federated queries
   - Historical audience snapshots for compliance/reporting
   - Backup if federated queries fail
   - Cost: €10-20/month

**Do NOT implement Pattern B (API Pull)** unless AEP explicitly requires on-demand profile enrichment (rare in practice).

**Key Insight:** Federated Composition shifts the paradigm from "minimize what we send to AEP" to "send nothing to AEP, let them query in-place." This is superior for data governance, compliance, and cost (no egress for raw data). The trade-off is query latency (5-30s vs <1s for push), which is acceptable for 95% of marketing campaigns.

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

CREATE OR REPLACE TABLE `company-project.gold.lead_scoring_features` AS
WITH customer_base AS (
  SELECT DISTINCT customer_id
  FROM `company-project.silver.customers`
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
  FROM `company-project.silver.customer_events`
  WHERE event_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
  GROUP BY customer_id
),

rm_interaction_features AS (
  SELECT
    customer_id,
    DATE_DIFF(CURRENT_DATE(), MAX(interaction_date), DAY) as days_since_rm_contact,
    COUNT(*) as rm_interactions_last_90d,
    MAX(CASE WHEN interaction_type = 'callback_request' THEN 1 ELSE 0 END) as has_callback_request
  FROM `company-project.silver.rm_interactions`
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
  FROM `company-project.silver.customer_financials`
  WHERE snapshot_date = CURRENT_DATE()
  GROUP BY customer_id, current_balance, credit_score, snapshot_date
),

application_features AS (
  SELECT
    customer_id,
    MAX(CASE WHEN application_status = 'STARTED' THEN 1 ELSE 0 END) as has_started_application,
    MAX(CASE WHEN application_status = 'SUBMITTED' THEN 1 ELSE 0 END) as has_submitted_application
  FROM `company-project.silver.product_applications`
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
  --destination_table=company-project:gold.lead_scoring_features \
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

CREATE OR REPLACE MODEL `company-project.ml_models.lead_classifier_v1`
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

FROM `company-project.gold.lead_scoring_features_historical`
WHERE feature_timestamp >= '2024-01-01'  -- 1 year of training data
  AND historical_lead_category IS NOT NULL;
```

**Model Evaluation:**

```sql
-- Evaluate model performance
SELECT
  *
FROM ML.EVALUATE(MODEL `company-project.ml_models.lead_classifier_v1`,
  (
    SELECT * FROM `company-project.gold.lead_scoring_features_historical`
    WHERE feature_timestamp >= '2024-01-01'
      AND historical_lead_category IS NOT NULL
  )
);

-- Expected output: precision, recall, accuracy, f1_score, roc_auc
```

**Batch Scoring (Daily):**

```sql
-- Score all active customers daily
CREATE OR REPLACE TABLE `company-project.gold.customer_lead_scores` AS
SELECT
  customer_id,
  predicted_lead_category as lead_category,
  predicted_lead_category_probs[OFFSET(0)].prob as cold_probability,
  predicted_lead_category_probs[OFFSET(1)].prob as warm_probability,
  predicted_lead_category_probs[OFFSET(2)].prob as hot_probability,
  -- Use HOT probability as propensity score
  predicted_lead_category_probs[OFFSET(2)].prob as propensity_score,
  CURRENT_TIMESTAMP() as scored_at
FROM ML.PREDICT(MODEL `company-project.ml_models.lead_classifier_v1`,
  (
    SELECT * FROM `company-project.gold.lead_scoring_features`
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

PROJECT_ID = "company-project"
REGION = "europe-west3"
BUCKET = "gs://company-ml-artifacts-eu"

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

    job.run(service_account="ml-pipeline-sa@company-project.iam.gserviceaccount.com")
```

**Schedule pipeline to run weekly:**

```bash
# Create Cloud Scheduler job to trigger Vertex AI pipeline
gcloud scheduler jobs create http lead-scoring-weekly-training \
  --location=europe-west3 \
  --schedule="0 2 * * 0" \
  --time-zone="Europe/Berlin" \
  --uri="https://europe-west3-aiplatform.googleapis.com/v1/projects/company-project/locations/europe-west3/pipelineJobs" \
  --http-method=POST \
  --message-body='{"displayName":"lead-scoring-training-scheduled","runtimeConfig":{...}}' \
  --oauth-service-account-email="scheduler-sa@company-project.iam.gserviceaccount.com"
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
        project='company-project',
        region='europe-west3',
        staging_location='gs://company-dataflow-eu/staging',
        temp_location='gs://company-dataflow-eu/temp',
        streaming=True,
        autoscaling_algorithm='THROUGHPUT_BASED',
        max_num_workers=10,
        service_account_email='dataflow-sa@company-project.iam.gserviceaccount.com'
    )

    with beam.Pipeline(options=pipeline_options) as pipeline:
        (
            pipeline
            | 'Read from Pub/Sub' >> beam.io.ReadFromPubSub(
                subscription='projects/company-project/subscriptions/customer-events-enriched-sub'
            )
            | 'Parse JSON' >> beam.Map(json.loads)
            | 'Filter High-Value Events' >> beam.Filter(
                lambda x: x['event_type'] in ['credit_application_started', 'callback_request']
            )
            | 'Score with Vertex AI' >> beam.ParDo(PredictLeadCategory())
            | 'Filter Hot Leads' >> beam.Filter(lambda x: x['lead_category'] == 'HOT')
            | 'Format for Pub/Sub' >> beam.Map(lambda x: json.dumps(x).encode('utf-8'))
            | 'Publish to Scored Leads Topic' >> beam.io.WriteToPubSub(
                topic='projects/company-project/topics/customer-leads-scored'
            )
        )

if __name__ == '__main__':
    run_pipeline()
```

**Deploy Dataflow pipeline:**

```bash
python dataflow_realtime_scoring.py \
  --runner DataflowRunner \
  --project company-project \
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
  "recommended_campaign": "q4_enterprise_services_promo",
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
    → Pub/Sub (customer-leads-scored)
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
    ('HOT', 'business_service_premium'): 'campaign_123_enterprise_services',
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

## 4. Data Governance & Compliance (EU Regulations)

### 4.1 Regulatory Framework

Your GCP-AEP architecture must satisfy:

**GDPR (General Data Protection Regulation):**
- **Data minimization (Article 5):** Only send necessary data to AEP
- **Purpose limitation:** Data used only for specified marketing purposes
- **Right to be forgotten (Article 17):** Customer data deletion in GCP AND AEP
- **Data portability (Article 20):** Customer can request their data from GCP
- **Data Processing Agreements (Article 28):** Required with Adobe for AEP

**DORA (Digital Operational Resilience Act):**
- **ICT risk management:** Monitor GCP-AEP integration for failures
- **Third-party risk:** Adobe (AEP) is a critical third-party provider
- **Incident reporting:** Report AEP outages to regulatory authorities within required timeframes if material

**Industry-Specific Regulations:**
- **Risk-based IT controls and outsourcing governance**
- **Data security, business continuity, change management**
- **Customer data protection with comprehensive audit trails**

### 4.2 Data Residency Requirements

**Critical Compliance Requirement:** Regulated customer data must stay in EU/Germany unless explicitly allowed by customer consent and contracts.

**GCP Regional Configuration:**

```bash
# All resources MUST use europe-west3 (Frankfurt) or europe-west1 (Belgium)

# BigQuery dataset with location enforcement
bq mk \
  --dataset \
  --location=europe-west3 \
  --default_table_expiration=0 \
  --description="Customer data - EU regulatory compliance" \
  company-project:silver

# Cloud Storage bucket with regional constraint
gsutil mb \
  -l europe-west3 \
  -c STANDARD \
  --pap=enforced \
  gs://company-data-eu/

# Pub/Sub topic (regional)
gcloud pubsub topics create customer-events-raw \
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

All data must be encrypted. GCP provides default encryption, but for highly regulated environments, use **Customer-Managed Encryption Keys (CMEK)** with Cloud KMS:

```bash
# Create KMS key ring in Frankfurt
gcloud kms keyrings create company-encryption-ring \
  --location=europe-west3

# Create encryption key
gcloud kms keys create company-data-key \
  --location=europe-west3 \
  --keyring=company-encryption-ring \
  --purpose=encryption \
  --rotation-period=90d \
  --next-rotation-time=2025-12-01T00:00:00Z

# Grant BigQuery service account access to key
gcloud kms keys add-iam-policy-binding company-data-key \
  --location=europe-west3 \
  --keyring=company-encryption-ring \
  --member=serviceAccount:bq-PROJECT_NUMBER@bigquery-encryption.iam.gserviceaccount.com \
  --role=roles/cloudkms.cryptoKeyEncrypterDecrypter
```

**Use CMEK for BigQuery datasets:**

```bash
bq update \
  --default_kms_key=projects/company-project/locations/europe-west3/keyRings/company-encryption-ring/cryptoKeys/company-data-key \
  company-project:silver
```

**Use CMEK for Cloud Storage:**

```bash
gsutil kms encryption \
  -k projects/company-project/locations/europe-west3/keyRings/company-encryption-ring/cryptoKeys/company-data-key \
  gs://company-data-eu/
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
  project = "company-project"
  role    = "roles/bigquery.dataViewer"
  member  = "group:data-scientists@company.com"

  condition {
    title       = "EU data only"
    description = "Only access EU datasets"
    expression  = "resource.name.startsWith('projects/company-project/datasets/silver')"
  }
}

# ML Engineers: Train models in Vertex AI
resource "google_project_iam_member" "ml_engineers_vertex" {
  project = "company-project"
  role    = "roles/aiplatform.user"
  member  = "group:ml-engineers@company.com"
}

# AEP Integration Service Account: Minimal permissions
resource "google_service_account" "aep_integration" {
  account_id   = "aep-integration-sa"
  display_name = "AEP Integration Service Account"
  description  = "Used by Cloud Functions to send data to AEP"
}

resource "google_project_iam_member" "aep_sa_pubsub_subscriber" {
  project = "company-project"
  role    = "roles/pubsub.subscriber"
  member  = "serviceAccount:${google_service_account.aep_integration.email}"
}

resource "google_project_iam_member" "aep_sa_secret_accessor" {
  project = "company-project"
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.aep_integration.email}"
}

# NO access to BigQuery data (Cloud Function only reads from Pub/Sub)
```

**VPC Service Controls:**

For maximum security, use VPC Service Controls to create a security perimeter:

```yaml
# vpc_service_controls.yaml
- name: regulated_data_perimeter
  title: "EU Regulated Data Perimeter"
  description: "Restricts data egress from GCP"
  resources:
    - projects/company-project
  restrictedServices:
    - bigquery.googleapis.com
    - storage.googleapis.com
    - pubsub.googleapis.com
  egressPolicies:
    - egressFrom:
        identityType: SERVICE_ACCOUNT
        identities:
          - serviceAccount:aep-integration-sa@company-project.iam.gserviceaccount.com
      egressTo:
        operations:
          - serviceName: storage.googleapis.com
            methodSelectors:
              - method: "google.storage.objects.get"
        resources:
          - "projects/company-project"
```

**This prevents:**
- Unauthorized data exfiltration from BigQuery
- Accidental bucket public access
- Data egress to non-approved services

### 4.5 Audit Trails & Monitoring

**Cloud Audit Logs (Always On):**

```bash
# Enable all audit log types
gcloud logging sinks create regulatory-audit-logs \
  bigquery.googleapis.com/projects/company-project/datasets/audit_logs \
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
FROM `company-project.audit_logs.cloudaudit_googleapis_com_data_access_*`
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
          AND NOT protoPayload.authenticationInfo.principalEmail=~".*@company.com"
        comparison: COMPARISON_GT
        thresholdValue: 0
        duration: 0s
  notificationChannels:
    - "projects/company-project/notificationChannels/security-team-email"
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
    - "projects/company-project/notificationChannels/compliance-team"
```

**Regulatory Documentation Requirements:**

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
DELETE FROM `company-project.silver.customers` WHERE customer_id = 'DE12345';
DELETE FROM `company-project.silver.customer_events` WHERE customer_id = 'DE12345';
DELETE FROM `company-project.gold.customer_lead_scores` WHERE customer_id = 'DE12345';

-- Delete from Cloud Storage (if storing customer-specific files)
-- gsutil rm -r gs://company-data-eu/customers/DE12345/
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

**Audit Trail:** Retain logs of deletion requests for required retention period (regulatory requirement), even though customer data is deleted.

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
FROM `company-project.gold.customer_lead_scores` curr
LEFT JOIN `company-project.gold.customer_lead_scores_yesterday` prev
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
CREATE TABLE `company-project.silver.customer_events` (
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
SELECT * FROM `company-project.silver.customer_events`
WHERE event_type = 'credit_application';

-- GOOD: Uses partition filter (scans only 7 days)
SELECT * FROM `company-project.silver.customer_events`
WHERE DATE(event_timestamp) >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
  AND event_type = 'credit_application';
```

**Cost Savings:** If table has 2 years of data (730 GB), bad query costs €3.65. Good query (7 days = 7 GB) costs €0.035 → **99% savings**.

2. **Use Materialized Views for Repeated Queries:**

If you're scoring leads daily and always need the same feature aggregations:

```sql
-- Create materialized view (precomputed, auto-refreshed)
CREATE MATERIALIZED VIEW `company-project.gold.customer_engagement_metrics`
AS
SELECT
  customer_id,
  COUNT(*) as total_events_30d,
  COUNT(DISTINCT event_type) as unique_event_types_30d,
  MAX(event_timestamp) as last_event_timestamp
FROM `company-project.silver.customer_events`
WHERE event_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
GROUP BY customer_id;
```

**Query the view instead of raw table:**

```sql
-- This is cheap (queries precomputed view, not raw table)
SELECT * FROM `company-project.gold.customer_engagement_metrics`
WHERE total_events_30d > 10;
```

**Cost Savings:** Materialized views are incrementally updated (only new data processed). If raw query scans 100 GB, materialized view query scans <1 GB → **99% savings** on repeated queries.

3. **BigQuery BI Engine (For Interactive Dashboards):**

If you're building Looker dashboards on lead scores, enable BI Engine:

```bash
# Reserve 10 GB of BI Engine capacity (in-memory acceleration)
bq mk --reservation \
  --project=company-project \
  --location=europe-west3 \
  --bi_engine_capacity=10

# Cost: €0.06 per GB per hour = €432/month for 10 GB reservation
```

**Trade-off:** Expensive, but makes dashboards instant (no query costs). Only use if business users run hundreds of ad-hoc queries daily.

4. **Use Clustered Tables:**

```sql
-- Clustering reduces data scanned when filtering on cluster keys
CREATE TABLE `company-project.gold.customer_lead_scores` (
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
SELECT * FROM `company-project.gold.customer_lead_scores`
WHERE lead_category = 'HOT';
```

**Savings:** Clustering can reduce scanned data by 30-70% depending on data distribution.

5. **Avoid SELECT * (Specify Columns):**

```sql
-- BAD: Scans all columns (expensive if table is wide)
SELECT * FROM `company-project.silver.customers`;

-- GOOD: Only scans needed columns
SELECT customer_id, lead_category, propensity_score
FROM `company-project.silver.customers`;
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
gsutil lifecycle set lifecycle.json gs://company-data-eu/
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
FROM `company-project.region-eu`.INFORMATION_SCHEMA.JOBS_BY_PROJECT
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
FROM `company-project.logs.cloudaudit_googleapis_com_activity_*`
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

If your primary use case is <100ms website personalization (mobile app shows offer as customer opens app), zero-copy GCP→AEP is too slow.

**Alternative Architecture:**
- GCP for batch ML (train models, compute scores daily)
- Export scores to **Google Cloud CDN** or **Firestore** (ultra-low latency)
- Mobile app calls GCP API directly (bypass AEP)
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
- Complete regulatory audit documentation
- Implement automated compliance checks (DLP scanning, audit log analysis)
- Conduct third-party security assessment of GCP→AEP integration
- **Goal:** Pass regulatory audit, achieve production certification

**Don't try to build Phases 1-5 simultaneously.** Start simple, prove value, iterate.

### 6.6 When to Push Back on Zero-Copy

**Be honest with stakeholders:** Zero-copy is not always the right answer. Push back if:

1. **Business case is weak:** "We want zero-copy because it sounds innovative" → No. Show ROI (cost savings, latency improvement) or don't do it.

2. **Team lacks GCP skills:** Building this architecture requires senior data engineers. If your team is junior or Adobe-focused, you'll fail. Hire/train first.

3. **AEP contract already includes data ingress:** Some AEP contracts have unlimited data ingress. If you're already paying for it, zero-copy saves egress costs (€50-200/month) but adds complexity (€50k in engineering time). Not worth it.

4. **Regulatory interpretation is unclear:** If your compliance team says "we're not sure if GCP→AEP satisfies regulatory requirements," don't proceed. Get legal sign-off first.

**My opinionated take:** Zero-copy is the right pattern for large-scale (10M+ customers), data-intensive (100+ GB), ML-driven use cases where GCP is the authoritative data platform. For smaller deployments or AEP-centric architectures, it's over-engineered.

---

## 7. Summary & Decision Framework

### 7.1 Recommended Architecture (Updated for Federated Composition)

For an EU enterprise client with 10M customers, strict compliance requirements, and need for both real-time and batch activation:

**Data Platform:**
- **BigQuery (europe-west3)** as data warehouse
- **Medallion architecture** (Bronze/Silver/Gold layers)
- **Dedicated `aep_federated` dataset** with optimized materialized views
- **Pub/Sub** for event streaming (real-time use cases only)
- **Vertex AI** for ML (training + batch scoring)
- **Cloud Storage** with lifecycle policies for raw data retention

**ML Pipeline:**
- **BigQuery ML** for initial lead scoring model (MVP in 2 weeks)
- **Migrate to Vertex AI** for production (XGBoost, better accuracy)
- **Hourly lead score refresh** (materialized views for AEP federated queries)
- **Real-time scoring** for Hot lead triggers only (credit app, callback)

**GCP→AEP Integration (UPDATED):**

**PRIMARY: Federated Composition (Pattern D) - 80% of use cases:**
- **All audience segmentation** for campaigns (lifecycle, product affinity, lead scoring)
- AEP queries BigQuery directly via federated connector
- Create materialized views: `hot_leads`, `identity_mapping`, `audience_master`
- **Data stays in BigQuery** - AEP only receives customer identifiers
- Hourly materialized view refresh (balances freshness and cost)
- **Cost:** €200-500/month (BigQuery queries + materialized view refresh)

**SECONDARY: Event-Driven Push (Pattern A) - 15% of use cases:**
- **Only for critical real-time Hot leads** (<1 minute latency required)
- Pub/Sub → Cloud Function → AEP Profile API
- Triggers: callback request, credit application started, high-value transaction
- **Cost:** €25-50/month

**FALLBACK: Batch Sync (Pattern C) - 5% of use cases:**
- Weekly full segment export for reconciliation
- Historical audience snapshots for compliance reporting
- Backup if federated queries fail
- **Cost:** €10-20/month

**Compliance:**
- **Data residency:** All GCP resources in europe-west3 (Frankfurt)
- **AEP query region:** Verify AEP queries from EU region (NLD2/IRL1)
- **Encryption:** CMEK with Cloud KMS
- **Audit:** Cloud Audit Logs → BigQuery (retained 7 years)
- **Query logging:** All AEP BigQuery queries logged and monitored
- **Access control:** VPC Service Controls, least-privilege IAM (table-level grants)
- **GDPR:** Implement deletion workflow (GCP + AEP external audience removal)

**Cost (Monthly) - UPDATED:**
- BigQuery storage: €200 (1 TB + 100 GB materialized views)
- BigQuery queries: €300 (federated query processing + scoring)
- Materialized view refresh: €150 (hourly refresh of 3 views)
- Pub/Sub + Cloud Functions: €25 (real-time hot leads only)
- Vertex AI (batch scoring): €100 (daily full scoring + hourly incremental)
- Cloud Storage: €100 (raw data retention)
- Egress to AEP: €50 (minimal - only hot lead events, federated uses internal network)
- **Total: ~€925/month** (excluding AEP license)

**Cost Savings vs Pure Push Architecture:** €275/month (reduced egress costs)
**Cost Increase vs Original:** -€75/month (federated queries more expensive but eliminates egress)

### 7.2 Decision Matrix: Which Integration Pattern to Use (UPDATED)

| Use Case | Lead Type | Latency Requirement | Volume | Recommended Pattern | Cost/Month |
|----------|-----------|---------------------|--------|---------------------|------------|
| **Audience segmentation for campaigns** | All | <1 hour | 10M customers | **Federated (D)** | €200-500 |
| **Complex multi-dimensional targeting** | All | <30 minutes | 5M customers | **Federated (D)** | €200-500 |
| **Exploratory audience discovery** | All | <5 minutes | Ad-hoc | **Federated (D)** | €50-200 |
| **Hot lead instant activation** | HOT | <1 minute | 1k/day | Event-Driven (A) | €25 |
| **Transaction-triggered campaigns** | HOT | <30 seconds | 5k/day | Event-Driven (A) | €50 |
| **Weekly full segment reconciliation** | All | <24 hours | 10M/week | Batch Sync (C) | €10 |
| **Historical audience snapshots** | All | <7 days | Monthly | Batch Sync (C) | €3 |
| **AEP-initiated profile enrichment** | Any | <500ms | Rare | API Pull (B) | €50-200 |

**Key Decision Criteria:**

**Use Federated (Pattern D) when:**
- Audience criteria changes frequently (no need to re-export)
- Multi-dimensional segmentation (3+ attributes combined)
- Data governance requires data to stay in GCP
- Query latency 5-30 seconds is acceptable
- Estimated query volume <10,000/day

**Use Event-Driven Push (Pattern A) when:**
- Latency <1 second is REQUIRED (not "nice to have")
- Specific trigger events (callback, application, fraud alert)
- Simple segment membership (Hot lead yes/no)
- Volume <10k events/day

**Use Batch Sync (Pattern C) when:**
- Daily/weekly cadence is acceptable
- Full segment export needed (not just queries)
- Cheapest option required
- Reconciliation and compliance reporting

**Do NOT use API Pull (Pattern B)** unless AEP explicitly requires on-demand enrichment

### 7.3 Key Questions to Answer Before Implementation (UPDATED)

**Critical Questions for Federated Composition:**

1. **Does AEP support federated queries from EU region?**
   - **Ask Adobe:** "Which data center region will execute BigQuery federated queries for our tenant?"
   - **Required answer:** EU region (NLD2 Netherlands or IRL1 Ireland)
   - **If US region:** Need Standard Contractual Clauses, potential GDPR violation

2. **What is AEP's federated query volume estimate?**
   - How many audience segments will be active?
   - How frequently will segments refresh?
   - Use this to estimate BigQuery query costs (€5 per TB scanned)

3. **What is acceptable audience refresh latency?**
   - If <1 minute required → Use Event-Driven Push (Pattern A)
   - If <1 hour acceptable → Use Federated (Pattern D)
   - If <24 hours acceptable → Use Batch Sync (Pattern C)

4. **Which AEP features require local data vs federated?**
   - Some AEP capabilities may not work with external audiences
   - Ask Adobe for limitations of federated audiences

5. **What is BigQuery optimization maturity?**
   - Do you have expertise in materialized views, partitioning, clustering?
   - Federated requires aggressive BigQuery optimization to control costs
   - If no expertise, start with simpler push patterns

**General Questions:**

6. **Is AEP deployment in EU or US?** (If US, additional SCCs and consent required)
7. **What is AEP API rate limit?** (Negotiate if needed for push patterns)
8. **Who owns data governance (GCP vs AEP)?** (Federated makes GCP primary, AEP secondary)
9. **Does team have Vertex AI expertise?** (If no, start with BigQuery ML)
10. **What is regulatory audit timeline?** (Prioritize compliance features)
11. **What is budget for BigQuery query costs?** (Federated can be expensive if not optimized)
12. **Do you need AEP at all?** (Consider GCP-native activation alternative)

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
- **Regulatory audit findings:** 0 critical, <3 minor

### 7.5 Final Recommendations (UPDATED)

**Do:**
1. **START WITH FEDERATED COMPOSITION** (Pattern D) as your primary integration method
   - Proves integration works with zero raw data transfer
   - Superior data governance and compliance posture
   - AEP queries your data in-place, no duplication

2. **Create optimized materialized views from day 1**
   - `identity_mapping` (critical for all queries)
   - `hot_leads` (most frequently queried)
   - `audience_master` (comprehensive segmentation view)
   - Hourly refresh balances freshness and cost

3. **Implement comprehensive monitoring**
   - Cloud Audit Logs for all AEP queries
   - Alert on slow queries (>30 seconds)
   - Alert on expensive queries (>10 GB scanned)
   - Dashboard for query volume and cost trends

4. **Add Event-Driven Push only for real-time**
   - Only implement if <1 minute latency is business-critical
   - Use for hot lead instant activation, fraud alerts
   - Don't build real-time streaming without proven business case

5. **Use BigQuery ML for MVP lead scoring**
   - Fast iteration (model deployed in 2 weeks)
   - Migrate to Vertex AI for production

6. **Document data flows for regulatory compliance**
   - Especially important for federated queries
   - Log which AEP queries accessed which customer data

7. **Verify AEP query region with Adobe**
   - Ensure federated queries execute from EU region
   - Document in data processing agreement

**Don't:**
1. **Don't use push patterns for segmentation** (use federated instead)
2. **Don't expose raw tables to AEP** (use views with filtered columns)
3. **Don't grant project-level BigQuery permissions** (table-level grants only)
4. **Don't skip materialized view optimization** (will cost 60x more)
5. **Don't send raw PII to AEP** (defeats zero-copy, compliance risk)
6. **Don't use US regions for data processing** (regulatory violation)
7. **Don't skip encryption** (CMEK is mandatory for highly regulated environments)
8. **Don't implement all patterns at once** (start with federated + real-time push)

**Updated Challenge to Leadership:**

"Adobe's Federated Audience Composition changes everything for our zero-copy architecture. Instead of minimizing what we send to AEP, we can now send NOTHING - AEP queries our BigQuery data in-place. This is superior for data governance, compliance, and audit requirements.

However, I still need to ask: why are we using AEP? If the primary value is audience segmentation and campaign activation, we could:

**Option A: Federated Composition + AEP (Recommended if AEP is mandatory)**
- Cost: €925/month GCP + AEP license
- Data stays in GCP, AEP queries in-place
- Leverage AEP's destination ecosystem (Adobe Target, email platforms, etc.)
- Superior compliance posture (raw data never leaves europe-west3)

**Option B: GCP-Native Activation (If AEP not mandatory)**
- Cost: €600/month GCP (no AEP license, save €300k/year)
- Build activation directly: BigQuery → Pub/Sub → Google Ads Data Hub, DV360, SendGrid, etc.
- Full control, but requires custom integrations

**Federated Composition makes Option A viable.** If the business case for AEP is destination ecosystem and ease of use, federated composition is the right integration pattern. If the business case is weak, Option B saves significant money.

**This question still needs answering before we commit to the architecture.**"

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
- **Federated Audience Composition:** https://experienceleague.adobe.com/docs/experience-platform/segmentation/ui/federated-audience-composition.html
- **BigQuery Source Connector:** https://experienceleague.adobe.com/docs/experience-platform/sources/connectors/databases/bigquery.html

**BigQuery Optimization:**
- Materialized Views: https://cloud.google.com/bigquery/docs/materialized-views-intro
- Partitioned Tables: https://cloud.google.com/bigquery/docs/partitioned-tables
- Clustered Tables: https://cloud.google.com/bigquery/docs/clustered-tables
- Query Optimization Best Practices: https://cloud.google.com/bigquery/docs/best-practices-performance-overview
- Cost Optimization: https://cloud.google.com/bigquery/docs/best-practices-costs

**EU Regulatory Resources:**
- GDPR Compliance: https://gdpr.eu/
- DORA Framework: https://www.digital-operational-resilience-act.com/
- GDPR Full Text: https://gdpr-info.eu/
- DORA Regulation: https://www.digital-operational-resilience-act.com/

**Books & Papers:**
- "Designing Data-Intensive Applications" by Martin Kleppmann
- "Building Machine Learning Pipelines" by Hannes Hapke & Catherine Nelson
- "Data Mesh" by Zhamak Dehghani
- Google's "Site Reliability Engineering" book (SRE)

---

**Document Status:** Version 2.0 - Updated with Federated Audience Composition

**Next Steps:**
1. **Validate with Adobe:** Confirm Federated Audience Composition support for EU region queries
2. **Pilot Federated Integration:**
   - Create `aep_federated` dataset in BigQuery
   - Build `identity_mapping` and `hot_leads` materialized views
   - Configure AEP BigQuery connector with service account
   - Create test audience in AEP using federated query
   - Measure query performance and cost for 1 week
3. **Review with GCP architect team:** Validate BigQuery optimization strategy
4. **Get legal sign-off:** Ensure federated query pattern satisfies data residency requirements
5. **Estimate engineering effort:**
   - Phase 1: Federated composition (4 weeks)
   - Phase 2: Real-time push for hot leads (2 weeks)
   - Phase 3: Batch reconciliation (1 week)

**Critical Adobe Questions to Ask:**
1. Which data center region executes BigQuery federated queries for EU tenants?
2. What are the limitations of federated audiences vs native AEP audiences?
3. What is the query timeout limit for federated queries?
4. Are there rate limits on federated query volume?
5. How do federated audiences integrate with AEP's activation destinations?

**Questions or feedback? Challenge my assumptions. I'm opinionated but not dogmatic. Let's build the right architecture, not just the trendy one.**

**The game has changed. Federated Audience Composition is the future of zero-copy GCP-AEP integration.**
