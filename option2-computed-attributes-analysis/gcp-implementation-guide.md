# Option 2: GCP Implementation Guide

**Audience**: GCP data engineers implementing the computed attributes pattern for AEP integration

**Companion to**: [failure-modes-and-edge-cases.md](failure-modes-and-edge-cases.md) (covers risks/failures)

This document provides concrete BigQuery/GCP implementation examples showing:
1. How to pre-compute customer attributes in BigQuery
2. SQL complexity comparison: FAC (Adobe queries BigQuery) vs Pre-Compute (you query BigQuery)
3. Complete end-to-end pipelines
4. Performance and cost considerations

---

## Table of Contents

1. [Raw Data Structure](#1-raw-data-structure)
2. [Option 2: Pre-Compute Pattern](#2-option-2-pre-compute-pattern)
3. [Option 1: FAC Pattern (For Comparison)](#3-option-1-fac-pattern-for-comparison)
4. [Complexity Assessment](#4-complexity-assessment)
5. [End-to-End Pipelines](#5-end-to-end-pipelines)
6. [Performance & Cost Analysis](#6-performance--cost-analysis)
7. [Banking Security Considerations](#7-banking-security-considerations)
8. [Recommendations](#8-recommendations)

---

## 1. Raw Data Structure

### Typical Banking Data Model in BigQuery

```sql
-- Customer events (clickstream, app usage, transactions)
CREATE TABLE `banking_data.customer_events` (
  event_id STRING,
  customer_id STRING,
  event_type STRING,  -- 'login', 'product_view', 'application_submit', 'transaction'
  event_timestamp TIMESTAMP,
  event_properties JSON,  -- Additional event metadata
  session_id STRING,
  device_type STRING,
  channel STRING  -- 'web', 'mobile_app', 'branch', 'call_center'
)
PARTITION BY DATE(event_timestamp)
CLUSTER BY customer_id, event_type;

-- Customer master data
CREATE TABLE `banking_data.customer_master` (
  customer_id STRING,
  email STRING,
  phone STRING,
  registration_date DATE,
  customer_segment STRING,  -- 'retail', 'premium', 'corporate'
  kyc_status STRING,
  last_updated TIMESTAMP
)
PARTITION BY DATE(registration_date)
CLUSTER BY customer_id;

-- Product holdings
CREATE TABLE `banking_data.product_holdings` (
  customer_id STRING,
  product_type STRING,  -- 'checking', 'savings', 'credit_card', 'mortgage', 'investment'
  product_id STRING,
  balance NUMERIC,
  account_status STRING,
  opened_date DATE,
  last_transaction_date DATE
)
PARTITION BY opened_date
CLUSTER BY customer_id;
```

---

## 2. Option 2: Pre-Compute Pattern

**Philosophy**: You compute everything in BigQuery, store results in a table, export to AEP.

### 2.1 Scheduled Query: Compute Customer Profiles

```sql
-- Scheduled query runs every 8 hours
CREATE OR REPLACE TABLE `banking_data.computed_customer_profiles`
PARTITION BY last_updated_date
CLUSTER BY lead_temperature, customer_segment
AS
WITH
-- Step 1: Calculate recent activity metrics (last 30 days)
recent_activity AS (
  SELECT
    customer_id,
    COUNT(DISTINCT DATE(event_timestamp)) as active_days_last_30,
    COUNT(*) as total_events_last_30,
    MAX(event_timestamp) as last_activity_timestamp,
    COUNTIF(event_type = 'login') as login_count_last_30,
    COUNTIF(event_type = 'product_view') as product_view_count_last_30,
    COUNTIF(event_type = 'application_submit') as application_count_last_30,
    COUNTIF(event_type = 'transaction') as transaction_count_last_30
  FROM `banking_data.customer_events`
  WHERE event_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
  GROUP BY customer_id
),

-- Step 2: Calculate engagement score
engagement_scores AS (
  SELECT
    customer_id,
    -- Weighted engagement scoring
    (login_count_last_30 * 2)
    + (product_view_count_last_30 * 5)
    + (application_count_last_30 * 20)
    + (transaction_count_last_30 * 10) as engagement_score,
    active_days_last_30,
    DATE_DIFF(CURRENT_DATE(), DATE(last_activity_timestamp), DAY) as days_since_last_interaction
  FROM recent_activity
),

-- Step 3: Classify leads (HOT/WARM/COLD)
lead_classification AS (
  SELECT
    customer_id,
    engagement_score,
    active_days_last_30,
    days_since_last_interaction,
    CASE
      WHEN engagement_score >= 60
        AND days_since_last_interaction <= 3
        AND active_days_last_30 >= 7
      THEN 'HOT'

      WHEN engagement_score >= 30
        AND days_since_last_interaction <= 14
        AND active_days_last_30 >= 3
      THEN 'WARM'

      ELSE 'COLD'
    END as lead_temperature,

    -- Additional computed attributes
    CASE
      WHEN engagement_score >= 80 THEN 'VERY_HIGH'
      WHEN engagement_score >= 60 THEN 'HIGH'
      WHEN engagement_score >= 30 THEN 'MEDIUM'
      ELSE 'LOW'
    END as engagement_level
  FROM engagement_scores
),

-- Step 4: Add product affinity scores
product_affinity AS (
  SELECT
    customer_id,
    COUNTIF(event_properties.product_category = 'credit_card') as credit_card_interest_score,
    COUNTIF(event_properties.product_category = 'mortgage') as mortgage_interest_score,
    COUNTIF(event_properties.product_category = 'investment') as investment_interest_score
  FROM `banking_data.customer_events`,
    UNNEST([PARSE_JSON(event_properties)]) as event_properties
  WHERE event_type = 'product_view'
    AND event_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY)
  GROUP BY customer_id
),

-- Step 5: Join with customer master data
final_profiles AS (
  SELECT
    c.customer_id,
    c.email,
    c.phone,
    c.customer_segment,
    c.kyc_status,
    lc.lead_temperature,
    lc.engagement_score,
    lc.engagement_level,
    lc.active_days_last_30,
    lc.days_since_last_interaction,
    pa.credit_card_interest_score,
    pa.mortgage_interest_score,
    pa.investment_interest_score,
    CURRENT_TIMESTAMP() as computed_at,
    CURRENT_DATE() as last_updated_date
  FROM `banking_data.customer_master` c
  LEFT JOIN lead_classification lc USING (customer_id)
  LEFT JOIN product_affinity pa USING (customer_id)
  WHERE c.kyc_status = 'APPROVED'  -- Only export KYC-approved customers
)

SELECT * FROM final_profiles;
```

### 2.2 Incremental Export: Detect Changes

**Goal**: Only send changed profiles to AEP (reduces API calls and costs).

```sql
-- Incremental export: Find profiles that changed since last export
CREATE OR REPLACE TABLE `banking_data.profiles_to_export` AS
WITH
current_profiles AS (
  SELECT * FROM `banking_data.computed_customer_profiles`
  WHERE last_updated_date = CURRENT_DATE()
),

previous_profiles AS (
  SELECT * FROM `banking_data.computed_customer_profiles_history`
  WHERE export_date = (
    SELECT MAX(export_date)
    FROM `banking_data.computed_customer_profiles_history`
  )
),

-- Detect changes using EXCEPT
changed_profiles AS (
  SELECT customer_id, 'UPDATED' as change_type
  FROM current_profiles
  EXCEPT DISTINCT
  SELECT customer_id, 'UPDATED' as change_type
  FROM previous_profiles
),

-- Detect new profiles
new_profiles AS (
  SELECT customer_id, 'NEW' as change_type
  FROM current_profiles
  WHERE customer_id NOT IN (SELECT customer_id FROM previous_profiles)
),

-- Union all changes
all_changes AS (
  SELECT * FROM changed_profiles
  UNION ALL
  SELECT * FROM new_profiles
)

-- Select full profile data for changed/new customers only
SELECT
  cp.*,
  ac.change_type,
  CURRENT_TIMESTAMP() as export_timestamp
FROM current_profiles cp
INNER JOIN all_changes ac USING (customer_id);

-- Archive current profiles to history
INSERT INTO `banking_data.computed_customer_profiles_history`
SELECT *, CURRENT_DATE() as export_date
FROM `banking_data.computed_customer_profiles`
WHERE last_updated_date = CURRENT_DATE();
```

### 2.3 Export to AEP (Batch or Streaming)

#### Option A: Batch Export via Cloud Storage

```sql
-- Export changed profiles to GCS as JSON
EXPORT DATA OPTIONS(
  uri='gs://banking-aep-exports/profiles/batch_*.json',
  format='JSON',
  overwrite=true
) AS
SELECT
  -- AEP XDM schema mapping
  STRUCT(
    customer_id as _id,
    email as personalEmail,
    phone as mobilePhone,
    customer_segment as segmentMembership,
    lead_temperature as customAttributes.leadTemperature,
    engagement_score as customAttributes.engagementScore,
    engagement_level as customAttributes.engagementLevel,
    credit_card_interest_score as customAttributes.creditCardAffinityScore,
    mortgage_interest_score as customAttributes.mortgageAffinityScore,
    investment_interest_score as customAttributes.investmentAffinityScore,
    computed_at as _timestamp
  ) as xdm_profile
FROM `banking_data.profiles_to_export`
WHERE export_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR);
```

**Then**: GCS → AEP Batch Ingestion API (via Cloud Function or Dataflow)

#### Option B: Streaming Export via Pub/Sub

```sql
-- Use Dataflow or Cloud Function to stream to Pub/Sub
-- This is triggered by the scheduled query completion

-- Cloud Function pseudocode:
-- 1. Query `profiles_to_export` table
-- 2. For each profile:
--    - Transform to AEP XDM format
--    - Publish to Pub/Sub topic: `aep-profile-updates`
-- 3. Pub/Sub → AEP Streaming Ingestion API
```

---

## 3. Option 1: FAC Pattern (For Comparison)

**Philosophy**: Adobe queries your BigQuery directly. You just create materialized views for performance.

### 3.1 Lightweight Materialized View

```sql
-- Materialized view for query performance (auto-refreshed by BigQuery)
CREATE MATERIALIZED VIEW `banking_data.customer_activity_summary`
PARTITION BY activity_date
CLUSTER BY customer_id
AS
SELECT
  customer_id,
  DATE(event_timestamp) as activity_date,
  COUNT(*) as event_count,
  COUNTIF(event_type = 'login') as login_count,
  COUNTIF(event_type = 'product_view') as product_view_count,
  COUNTIF(event_type = 'application_submit') as application_count,
  COUNTIF(event_type = 'transaction') as transaction_count,
  MAX(event_timestamp) as last_event_timestamp
FROM `banking_data.customer_events`
WHERE event_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY)
GROUP BY customer_id, DATE(event_timestamp);
```

### 3.2 FAC Query (Generated by Adobe)

**Adobe translates your segment rules** (defined in AEP UI) **to BigQuery SQL**:

```sql
-- Adobe generates this query when evaluating segment "Hot Leads"
-- User defines segment rule in AEP UI: "Lead Temperature = HOT"
-- Adobe translates to BigQuery SQL on-the-fly

WITH customer_engagement AS (
  SELECT
    customer_id,
    SUM(login_count) * 2
    + SUM(product_view_count) * 5
    + SUM(application_count) * 20
    + SUM(transaction_count) * 10 as engagement_score,
    MAX(last_event_timestamp) as last_activity_timestamp,
    COUNT(DISTINCT activity_date) as active_days_last_30
  FROM `banking_data.customer_activity_summary`
  WHERE activity_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
  GROUP BY customer_id
),

classified_customers AS (
  SELECT
    customer_id,
    engagement_score,
    DATE_DIFF(CURRENT_DATE(), DATE(last_activity_timestamp), DAY) as days_since_last_interaction,
    active_days_last_30,
    CASE
      WHEN engagement_score >= 60
        AND DATE_DIFF(CURRENT_DATE(), DATE(last_activity_timestamp), DAY) <= 3
        AND active_days_last_30 >= 7
      THEN 'HOT'

      WHEN engagement_score >= 30
        AND DATE_DIFF(CURRENT_DATE(), DATE(last_activity_timestamp), DAY) <= 14
        AND active_days_last_30 >= 3
      THEN 'WARM'

      ELSE 'COLD'
    END as lead_temperature
  FROM customer_engagement
)

-- Return customer IDs for "Hot Leads" segment
SELECT customer_id
FROM classified_customers
WHERE lead_temperature = 'HOT';
```

**Key Difference**:
- **Option 2**: You write the scheduled query to compute lead_temperature, store it, export it
- **Option 1 (FAC)**: Adobe generates the query on-demand when segment is evaluated

---

## 4. Complexity Assessment

### Option 2: Pre-Compute Pattern

**GCP Components**:
- 1 scheduled query (300+ lines SQL)
- 1 incremental export query (100+ lines SQL)
- 1 export orchestration (Cloud Function or Dataflow)
- 1 history table for change detection
- 1 Pub/Sub topic (if streaming)
- 1 Cloud Storage bucket (if batch)
- 1 AEP ingestion pipeline (API integration)

**Total Complexity**: ~500 lines SQL + ~200 lines orchestration code

**Operational Overhead**:
- Monitor scheduled query failures
- Handle API rate limits (20K profiles/sec)
- Manage schema evolution (XDM changes require code updates)
- Maintain history table (cleanup old snapshots)
- Debug sync issues (BigQuery vs AEP inconsistencies)

---

### Option 1: FAC Pattern

**GCP Components**:
- 1 materialized view (50 lines SQL)
- 1 service account for AEP access
- 1 BigQuery dataset with controlled access

**Total Complexity**: ~50 lines SQL (no orchestration code)

**Operational Overhead**:
- Monitor materialized view refresh
- Optimize query performance (if Adobe queries are slow)
- Manage access controls (IAM policies)

---

### Complexity Comparison Table

| Aspect | Option 2 (Pre-Compute) | Option 1 (FAC) |
|--------|------------------------|----------------|
| **SQL Code** | ~500 lines | ~50 lines |
| **Orchestration Code** | ~200 lines (Python/Go) | 0 lines |
| **GCP Services** | 7-8 components | 2 components |
| **Monitoring Surfaces** | 5+ (query, export, API, sync, history) | 2 (view refresh, query perf) |
| **Schema Changes** | Update SQL + XDM mapping + AEP | Update materialized view |
| **Failure Modes** | 10+ (see [failure-modes-and-edge-cases.md](failure-modes-and-edge-cases.md)) | 2-3 (access denied, query timeout) |
| **Debugging Complexity** | HIGH (multi-system) | LOW (single system) |

---

## 5. End-to-End Pipelines

### Option 2: Complete Pipeline

```
┌─────────────────────────────────────────────────────────────────────┐
│                         GCP Data Pipeline                           │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  [Raw Events] ──→ [BigQuery Tables]                                │
│                         │                                           │
│                         ↓                                           │
│                  [Scheduled Query]                                  │
│                  (Compute Profiles)                                 │
│                  Every 8 hours                                      │
│                         │                                           │
│                         ↓                                           │
│          [computed_customer_profiles]                               │
│                         │                                           │
│                         ↓                                           │
│              [Incremental Export Query]                             │
│              (Detect changes via EXCEPT)                            │
│                         │                                           │
│                         ↓                                           │
│            [profiles_to_export] ──→ [History Table]                 │
│                         │                                           │
│                         ↓                                           │
│         ┌───────────────┴───────────────┐                           │
│         ↓                               ↓                           │
│  [Cloud Function]               [EXPORT DATA]                       │
│  Transform to XDM               GCS JSON files                      │
│         │                               │                           │
│         ↓                               ↓                           │
│    [Pub/Sub Topic]           [Cloud Storage Bucket]                 │
│  aep-profile-updates        banking-aep-exports/                    │
│         │                               │                           │
└─────────┼───────────────────────────────┼───────────────────────────┘
          │                               │
          ↓                               ↓
┌─────────────────────────────────────────────────────────────────────┐
│                      Adobe Experience Platform                      │
├─────────────────────────────────────────────────────────────────────┤
│         │                               │                           │
│         ↓                               ↓                           │
│  [Streaming Ingestion API]    [Batch Ingestion API]                │
│  20K profiles/sec limit        Unlimited (hourly batches)           │
│         │                               │                           │
│         └───────────────┬───────────────┘                           │
│                         ↓                                           │
│                [Real-Time Customer Profile]                         │
│                         │                                           │
│                         ↓                                           │
│                  [Segmentation Engine]                              │
│                  (Streaming or Batch)                               │
│                         │                                           │
│                         ↓                                           │
│                    [Segments]                                       │
│             "Hot Leads", "Warm Leads", etc.                         │
│                         │                                           │
│                         ↓                                           │
│                  [Destinations]                                     │
│          Google Ads, Facebook, Salesforce, etc.                     │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

### Option 1 (FAC): Complete Pipeline

```
┌─────────────────────────────────────────────────────────────────────┐
│                         GCP Data Pipeline                           │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  [Raw Events] ──→ [BigQuery Tables]                                │
│                         │                                           │
│                         ↓                                           │
│          [Materialized View]                                        │
│      customer_activity_summary                                      │
│      (Auto-refreshed by BigQuery)                                   │
│                         │                                           │
│                         │ (Query access via IAM)                    │
│                         │                                           │
└─────────────────────────┼───────────────────────────────────────────┘
                          │
                          ↓ (Federated Query)
┌─────────────────────────────────────────────────────────────────────┐
│                      Adobe Experience Platform                      │
├─────────────────────────────────────────────────────────────────────┤
│                         │                                           │
│                         ↓                                           │
│           [Federated Audience Composition]                          │
│           Adobe generates BigQuery SQL                              │
│           Queries materialized view directly                        │
│                         │                                           │
│                         ↓                                           │
│                [Segment Evaluation]                                 │
│            (Computed in BigQuery, results cached)                   │
│                         │                                           │
│                         ↓                                           │
│                    [Segments]                                       │
│             "Hot Leads", "Warm Leads", etc.                         │
│             (Audience IDs only, no profile data copied)             │
│                         │                                           │
│                         ↓                                           │
│                  [Destinations]                                     │
│          Google Ads, Facebook, Salesforce, etc.                     │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Key Difference**: FAC has NO data copying, NO export pipeline, NO sync issues.

---

## 6. Performance & Cost Analysis

### Option 2: Pre-Compute

**BigQuery Costs** (monthly, assuming 10M customers):

| Operation | Volume | Cost |
|-----------|--------|------|
| Scheduled query (compute profiles) | 3x/day, 500GB scanned | $75/month |
| Incremental export query | 3x/day, 200GB scanned | $30/month |
| Storage (computed_customer_profiles) | 100GB (10M rows × 10KB/row) | $2/month |
| Storage (history table, 30 days) | 3TB (100GB × 30 snapshots) | $60/month |
| Export to GCS | 50GB/day × 30 days = 1.5TB | $30/month |
| **Total BigQuery** | | **$197/month** |

**Data Transfer Costs**:

| Transfer | Volume | Cost |
|----------|--------|------|
| GCS → AEP (egress to Adobe) | 1.5TB/month | $180/month |

**AEP Ingestion Costs**:

| Ingestion Type | Volume | Cost |
|----------------|--------|------|
| Streaming API (if using Pub/Sub) | 100K profiles/day × 30 days = 3M profiles/month | Included in AEP license |
| Batch ingestion (if using GCS) | 1.5TB/month | Included in AEP license |

**Total Option 2 Monthly Cost (GCP Only)**: ~$377/month

**NOT included**: AEP license ($250K-$600K/year), operational overhead (2 FTE), incident debugging.

---

### Option 1: FAC

**BigQuery Costs** (monthly, assuming 10M customers):

| Operation | Volume | Cost |
|-----------|--------|------|
| Materialized view refresh | Auto, 50GB scanned | $7.50/month |
| Storage (materialized view) | 20GB | $0.40/month |
| Adobe queries (segment evaluation) | 10x/day, 10GB scanned/query | $150/month |
| **Total BigQuery** | | **$157.90/month** |

**Data Transfer Costs**: $0 (no egress, Adobe queries in-place)

**AEP Costs**: FAC license ($100K-$300K/year, cheaper than full Real-Time CDP)

**Total Option 1 Monthly Cost (GCP Only)**: ~$158/month

---

### Cost Comparison (GCP Infrastructure Only)

| | Option 2 (Pre-Compute) | Option 1 (FAC) | Savings |
|------------|------------------------|----------------|---------|
| **Monthly** | $377 | $158 | **$219/month** |
| **Annual** | $4,524 | $1,896 | **$2,628/year** |

**Note**: This is GCP infrastructure only. Add AEP license costs for total TCO.

---

### Performance Comparison

**Segment Evaluation Latency**:

| | Option 2 (Pre-Compute) | Option 1 (FAC) |
|-----------------|------------------------|----------------|
| **Streaming** | 2-10 minutes | NOT AVAILABLE |
| **Batch** | 8 hours (scheduled query frequency) | 8-24 hours (query on-demand) |
| **Real-time Use Cases** | ✅ Supported (if streaming) | ❌ Not supported |

**Query Performance** (for "Hot Leads" segment, 10M customers):

| | Option 2 | Option 1 (FAC) |
|------------|----------|----------------|
| **Query Time** | < 1 sec (simple SELECT from pre-computed table) | 10-30 sec (compute on-the-fly from materialized view) |
| **Data Scanned** | 100GB (full table scan) | 10GB (materialized view, last 30 days) |
| **Latency** | Sub-second | 10-30 seconds |

**Winner for Query Performance**: Option 2 (but only if you need sub-second responses for segments)

**Winner for Cost/Simplicity**: Option 1 (FAC)

---

## 7. Banking Security Considerations

### Why FAC Might Be Blocked by BaFin Compliance

**Concern**: Adobe queries BigQuery directly → external system access to production database

**BaFin Requirements**:
1. **Data Residency**: Customer data must stay in Germany/EU
2. **Audit Logs**: All data access must be logged and auditable
3. **Access Control**: Third-party access must be approved and monitored
4. **Data Minimization**: Only necessary data should be accessible

### FAC Security Controls (If Approved)

```sql
-- 1. Create dedicated dataset for FAC (read-only view)
CREATE SCHEMA `banking_data_fac_readonly`;

-- 2. Create view that exposes ONLY necessary fields
CREATE VIEW `banking_data_fac_readonly.customer_activity` AS
SELECT
  -- Anonymized customer ID (no PII)
  SHA256(customer_id) as customer_hash,
  activity_date,
  event_count,
  login_count,
  product_view_count,
  application_count,
  transaction_count,
  last_event_timestamp
FROM `banking_data.customer_activity_summary`
WHERE activity_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY);

-- 3. Grant Adobe service account read-only access
GRANT `roles/bigquery.dataViewer`
ON SCHEMA `banking_data_fac_readonly`
TO 'serviceAccount:adobe-fac@aep.iam.gserviceaccount.com';

-- 4. Enable BigQuery audit logs
-- (Already enabled by default for banking workloads)

-- 5. Set up VPC Service Controls (optional)
-- Restrict BigQuery access to specific IP ranges (Adobe's)
```

**Audit Log Example**:

```json
{
  "protoPayload": {
    "serviceName": "bigquery.googleapis.com",
    "methodName": "jobservice.query",
    "authenticationInfo": {
      "principalEmail": "adobe-fac@aep.iam.gserviceaccount.com"
    },
    "resourceName": "projects/banking-gcp/datasets/banking_data_fac_readonly/tables/customer_activity",
    "request": {
      "query": "SELECT customer_hash FROM banking_data_fac_readonly.customer_activity WHERE lead_temperature = 'HOT'"
    }
  },
  "timestamp": "2025-10-21T10:15:30Z",
  "severity": "INFO"
}
```

**Questions for Security Team**:
1. Is Adobe's service account allowed to query BigQuery (even read-only)?
2. Can we use VPC Service Controls to restrict access to Adobe's IP ranges only?
3. Is data anonymization (SHA256 customer ID) acceptable, or do we need full PII?
4. Are audit logs sufficient for compliance, or do we need additional monitoring?

---

### Option 2 Security (Push-Based, More Likely Approved)

**Why Push Is Safer**:
- You control what data leaves GCP (audit before export)
- No external system queries your production database
- Can add PII tokenization/encryption before export
- Granular control over export frequency and volume

**Implementation**:

```python
# Cloud Function: Export to AEP with PII tokenization
import hashlib
from google.cloud import bigquery

def export_to_aep(request):
    client = bigquery.Client()

    query = """
    SELECT
      -- Tokenize PII before export
      SHA256(customer_id) as customer_hash,
      SHA256(email) as email_hash,
      lead_temperature,
      engagement_score
    FROM `banking_data.profiles_to_export`
    WHERE export_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 HOUR)
    """

    results = client.query(query).result()

    for row in results:
        # Send to AEP Streaming API
        aep_payload = {
            "header": {
                "datasetId": "banking_customer_profiles",
                "imsOrgId": "YOUR_IMS_ORG_ID"
            },
            "body": {
                "xdmMeta": {
                    "schemaRef": {
                        "id": "https://ns.adobe.com/banking/schemas/profile"
                    }
                },
                "xdmEntity": {
                    "_id": row.customer_hash,
                    "personalEmail": {"address": row.email_hash},
                    "customAttributes": {
                        "leadTemperature": row.lead_temperature,
                        "engagementScore": row.engagement_score
                    }
                }
            }
        }

        # POST to AEP Streaming Ingestion API
        response = requests.post(
            "https://dcs.adobedc.net/collection/YOUR_STREAMING_ENDPOINT",
            json=aep_payload,
            headers={"Authorization": f"Bearer {aep_access_token}"}
        )

        if response.status_code != 200:
            # Handle errors, retry, log to Cloud Logging
            logging.error(f"AEP ingestion failed: {response.text}")
```

**BaFin Compliance Checklist** (Option 2):
- ✅ Data stays in GCP until explicitly exported
- ✅ PII tokenization before export
- ✅ Audit logs for all exports (Cloud Logging)
- ✅ Rate limiting and volume controls
- ✅ No external system access to production database
- ✅ Data residency (export from EU region only)

---

## 8. Recommendations

### For Your Banking Use Case

**Recommended: Option 2 (Pre-Compute + Batch/Streaming Export)**

**Reasons**:
1. **Regulatory Control**: You own the export process, can audit before sending
2. **Security Approval**: Push-based easier to get approved than pull-based (FAC)
3. **Real-Time Capability**: Can add streaming export for time-sensitive use cases
4. **Complexity Manageable**: Standard BigQuery scheduled query pattern
5. **Cost Predictability**: Fixed costs, no surprise query charges from Adobe

**Trade-offs Accepted**:
1. **More Code**: ~500 lines SQL + ~200 lines orchestration (vs ~50 lines for FAC)
2. **Operational Overhead**: 2 FTE to maintain long-term
3. **Sync Risk**: BigQuery and AEP can get out of sync (mitigated by incremental exports)
4. **Vendor Lock-In**: AEP XDM schema migration costs $200K-$500K if you switch vendors

---

### Implementation Phases

**Phase 1: Batch Export (Months 1-3)**
- Scheduled query every 8 hours
- Incremental export to GCS
- Batch ingestion to AEP
- **Goal**: Prove the pattern works, validate data quality

**Phase 2: Streaming Export (Months 4-6, if needed)**
- Add Pub/Sub topic for high-priority profiles (e.g., Hot Leads)
- Cloud Function for real-time transformation
- Streaming ingestion to AEP
- **Goal**: Enable real-time use cases (<5 min latency)

**Phase 3: Optimization (Months 7-12)**
- Tune BigQuery queries (partitioning, clustering, materialized views)
- Implement error handling and retry logic
- Set up monitoring and alerting
- **Goal**: Production-grade reliability (99.9% uptime)

---

### When to Reconsider FAC

**Reconsider FAC if**:
1. Security team approves external queries to BigQuery
2. You DON'T have real-time use cases (<5 min latency)
3. You want to minimize operational overhead (prefer simplicity over control)
4. Cost savings ($2,628/year GCP costs) matter more than regulatory control

**Migration Path**:
- Start with Option 2 (safe, approved)
- Prove value with AEP
- Ask security team for FAC approval in 6-12 months
- Migrate to FAC if approved (reduces complexity, saves costs)

---

## Appendix: Complete Code Examples

### Scheduled Query Orchestration (Cloud Composer / Airflow)

```python
from airflow import DAG
from airflow.providers.google.cloud.operators.bigquery import BigQueryInsertJobOperator
from airflow.providers.google.cloud.transfers.bigquery_to_gcs import BigQueryToGCSOperator
from datetime import datetime, timedelta

default_args = {
    'owner': 'data-engineering',
    'depends_on_past': False,
    'start_date': datetime(2025, 10, 21),
    'email_on_failure': True,
    'email_on_retry': False,
    'retries': 2,
    'retry_delay': timedelta(minutes=5),
}

dag = DAG(
    'aep_customer_profile_export',
    default_args=default_args,
    description='Compute customer profiles and export to AEP',
    schedule_interval='0 */8 * * *',  # Every 8 hours
    catchup=False
)

# Task 1: Run scheduled query to compute profiles
compute_profiles = BigQueryInsertJobOperator(
    task_id='compute_customer_profiles',
    configuration={
        "query": {
            "query": "{% include 'sql/compute_customer_profiles.sql' %}",
            "useLegacySql": False,
            "destinationTable": {
                "projectId": "banking-gcp",
                "datasetId": "banking_data",
                "tableId": "computed_customer_profiles"
            },
            "writeDisposition": "WRITE_TRUNCATE"
        }
    },
    dag=dag
)

# Task 2: Detect changes and create export table
detect_changes = BigQueryInsertJobOperator(
    task_id='detect_profile_changes',
    configuration={
        "query": {
            "query": "{% include 'sql/incremental_export.sql' %}",
            "useLegacySql": False,
            "destinationTable": {
                "projectId": "banking-gcp",
                "datasetId": "banking_data",
                "tableId": "profiles_to_export"
            },
            "writeDisposition": "WRITE_TRUNCATE"
        }
    },
    dag=dag
)

# Task 3: Export to GCS
export_to_gcs = BigQueryToGCSOperator(
    task_id='export_to_gcs',
    source_project_dataset_table='banking-gcp.banking_data.profiles_to_export',
    destination_cloud_storage_uris=['gs://banking-aep-exports/profiles/batch_*.json'],
    export_format='NEWLINE_DELIMITED_JSON',
    dag=dag
)

# Task 4: Trigger Cloud Function to send to AEP
# (Use CloudFunctionInvokeFunctionOperator or HTTP request)

compute_profiles >> detect_changes >> export_to_gcs
```

---

## Summary

| Aspect | Option 2 (Pre-Compute) | Option 1 (FAC) |
|--------|------------------------|----------------|
| **Complexity** | HIGH (~700 lines code) | LOW (~50 lines code) |
| **Security Approval** | ✅ Easier (push-based) | ⚠️ Harder (pull-based) |
| **Real-Time Capability** | ✅ Yes (streaming export) | ❌ No (batch only) |
| **Operational Overhead** | HIGH (2+ FTE) | LOW (0.5 FTE) |
| **GCP Cost (Annual)** | $4,524 | $1,896 |
| **Vendor Lock-In** | HIGH (AEP XDM schemas) | MEDIUM (FAC queries) |
| **Recommended For** | Banking, real-time needs, regulatory control | Non-regulated, batch-only, simplicity |

**For your banking use case**: **Option 2** is the pragmatic choice given security constraints and real-time requirements.

---

**Last Updated**: October 21, 2025
**Author**: GCP Data/ML Architect + AEP Solutions Architect
**Related Docs**: [failure-modes-and-edge-cases.md](failure-modes-and-edge-cases.md), [../aep-zero-copy-executive-summary.md](../aep-zero-copy-executive-summary.md)
