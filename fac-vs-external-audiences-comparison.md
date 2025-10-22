# Federated Audience Composition vs External Audiences API
## Comprehensive Comparison for AEP BigQuery Integration

**Document Version**: 1.0
**Last Updated**: October 2025
**Author**: Architecture Team
**Target Audience**: Solutions Architects, Data Engineers, Product Managers

---

## Executive Summary

This document provides a detailed comparison between **Federated Audience Composition (FAC)** and **External Audiences API** for Adobe Experience Platform (AEP) integration with BigQuery. Both approaches enable audience activation while minimizing data storage in AEP, but they differ fundamentally in architecture, capabilities, and use cases.

**Quick Recommendation**:
- ✅ **FAC**: Best for batch use cases when BigQuery can be exposed to AEP (true zero-copy)
- ✅ **External Audiences API**: Best when security blocks BigQuery exposure or for POC/testing
- ✅ **Hybrid**: Use both for different audiences based on requirements

---

## 1. Maturity and State Information

### Federated Audience Composition (FAC)

| Attribute | Details |
|-----------|---------|
| **Current State** | **General Availability (GA)** |
| **GA Release Date** | **July 2024** |
| **Previous State** | Limited Availability (LA) - Q4 2023 to Q2 2024 |
| **Production Ready** | ✅ Yes - Fully supported, SLA-backed |
| **Documentation Status** | Complete and actively maintained |
| **Adobe Support** | Full enterprise support available |
| **Known Limitations** | None blocking production use |
| **Future Roadmap** | Real-time FAC capabilities under development |

**Key Milestones**:
- **Q4 2023**: Limited Availability launch with select customers
- **Q1 2024**: Beta testing with Fortune 500 banking/retail customers
- **Q2 2024**: Performance optimizations, added Databricks/Fabric support
- **July 2024**: General Availability announcement
- **Q4 2024**: Enhanced query optimization, materialized views support

**Latest Capabilities (2024)**:
- ✅ Audience Creation from federated data sources
- ✅ Audience Enrichment (add attributes to existing audiences)
- ✅ Profile Enrichment (enrich profiles with federated attributes)
- ✅ Multi-source federation (combine BigQuery + Snowflake + Redshift)
- ✅ Scheduled refresh (hourly, daily, weekly)
- ✅ Materialized views optimization

### External Audiences API

| Attribute | Details |
|-----------|---------|
| **Current State** | **Production Ready** |
| **Initial Release** | Q2 2023 |
| **Latest API Update** | **October 6, 2025** |
| **API Version** | v1 (stable) |
| **Documentation Status** | Complete with OpenAPI specification |
| **Adobe Support** | Full enterprise support available |
| **Known Limitations** | Enrichment attributes NOT usable in Segment Builder |
| **Future Roadmap** | Real-time streaming ingestion planned for 2026 |

**Key Milestones**:
- **Q2 2023**: Initial release as "External Audiences" feature
- **Q4 2023**: API endpoints moved from `/core/ups/` to `/core/ais/`
- **Q1 2024**: Added bulk operations support
- **Q2 2024**: Increased file size limit to 1 GB
- **October 2025**: Documentation refresh, added examples for banking/retail

**Latest Capabilities (2025)**:
- ✅ CSV upload (manual or automated)
- ✅ API-based ingestion (programmatic)
- ✅ Enrichment attributes (up to 24 fields)
- ✅ TTL management (30-90 days)
- ✅ Status monitoring APIs
- ⚠️ **NOT supported**: Enrichment attributes in Segment Builder

---

## 2. Architecture Comparison

### 2.1 Data Flow

#### Federated Audience Composition (FAC)
```
┌─────────────────────────────────────────────────────────────┐
│ PULL-BASED ARCHITECTURE (Query Federation)                  │
└─────────────────────────────────────────────────────────────┘

   BigQuery                    AEP                    Destinations
┌────────────┐              ┌────────┐              ┌────────────┐
│            │              │        │              │            │
│  Raw Data  │◄─────────────│  FAC   │              │  Facebook  │
│  100M rows │  SQL Query   │ Query  │              │    Ads     │
│  50 cols   │              │ Engine │              │            │
│            │              │        │              │            │
│            │──────────────►│ Store  │──────────────►│  Google   │
│            │ Return IDs   │ 40K    │ Send IDs    │    Ads     │
│            │ (40K rows)   │ IDs    │              │            │
└────────────┘              └────────┘              └────────────┘
     │                           │                         │
     │ NO data transfer          │ Minimal metadata       │
     │ Query executed in BQ      │ only (IDs + refs)      │
     └───────────────────────────┴─────────────────────────┘

KEY CHARACTERISTICS:
✓ Data NEVER leaves BigQuery
✓ AEP executes SQL queries via federated connection
✓ Only Identity IDs returned to AEP (e.g., 40K out of 100M)
✓ 99.96% data reduction at source
✓ TRUE zero-copy architecture
```

#### External Audiences API
```
┌─────────────────────────────────────────────────────────────┐
│ PUSH-BASED ARCHITECTURE (Data Upload)                       │
└─────────────────────────────────────────────────────────────┘

   BigQuery               Cloud Run/Workflow         AEP
┌────────────┐          ┌──────────────────┐    ┌────────────┐
│            │          │                  │    │            │
│  Raw Data  │──────────►│ Query BigQuery   │───►│  External  │
│  100M rows │ Trigger  │                  │    │  Audience  │
│  50 cols   │          │ SELECT id,       │    │   Store    │
│            │          │   email,         │    │            │
│            │          │   first_name,    │    │  40K IDs + │
│            │          │   lead_score     │    │  9 fields  │
│            │          │ WHERE            │    │            │
│            │          │   lead = 'Hot'   │    │  360K rows │
│            │          │                  │    │  total     │
└────────────┘          │ Transform to     │    │            │
                        │ CSV/JSON         │    │            │
                        │                  │    │            │
                        │ POST /core/ais/  │    │            │
                        │  external-       │    │            │
                        │  audience/       │    │            │
                        │  {ID}/runs       │    │            │
                        └──────────────────┘    └────────────┘
     │                          │                      │
     │ Query executes           │ Minimal data push   │ 30-day TTL
     │ Extract IDs + attributes │ (IDs + enrichment)  │ Must refresh
     └──────────────────────────┴─────────────────────┘

KEY CHARACTERISTICS:
✓ You control what data is extracted from BigQuery
✓ Data pushed to AEP (IDs + enrichment attributes)
✓ ~99.64% data reduction (you choose fields)
✓ Data stored in AEP for 30-90 days (TTL)
✓ Automated refresh required before expiration
```

### 2.2 Connection Model

| Aspect | FAC | External Audiences API |
|--------|-----|------------------------|
| **Connection Type** | AEP → BigQuery (pull) | BigQuery → AEP (push) |
| **Network Requirement** | BigQuery exposed to AEP IPs | GCP Cloud Run/Functions call AEP |
| **Authentication** | GCP Service Account in AEP | AEP API credentials in GCP |
| **Firewall Rules** | Allowlist AEP IP ranges | Allowlist AEP API endpoints |
| **Data Transit** | Query execution only | CSV/JSON payload upload |
| **Connection Persistence** | Persistent federated connection | Ephemeral (per-upload) |

---

## 3. Feature Comparison Matrix

### 3.1 Core Capabilities

| Feature | FAC | External Audiences API |
|---------|-----|------------------------|
| **Audience Creation** | ✅ Yes - in AEP UI via SQL | ✅ Yes - via API or CSV upload |
| **Audience Enrichment** | ✅ Yes - add federated attributes | ✅ Yes - up to 24 enrichment fields |
| **Profile Enrichment** | ✅ Yes - enrich profiles with BQ data | ❌ No - audience-level only |
| **AEP Segment Builder** | ✅ Yes - build segments on top of FAC audiences | ⚠️ **NO** - enrichment attributes NOT usable |
| **Real-Time Activation** | ⚠️ Batch only (planned for future) | ⚠️ Batch only (planned for 2026) |
| **Scheduled Refresh** | ✅ Yes - hourly/daily/weekly | ✅ Yes - via Cloud Scheduler + API |
| **Multi-Source Join** | ✅ Yes - join BQ + Snowflake + Redshift | ❌ No - single source per audience |
| **Identity Resolution** | ✅ Yes - leverage AEP Identity Graph | ⚠️ Limited - must provide resolved IDs |

### 3.2 Data Management

| Feature | FAC | External Audiences API |
|---------|-----|------------------------|
| **Data Storage in AEP** | ❌ **None** - only metadata | ⚠️ IDs + enrichment (minimal) |
| **Data Expiration** | ✅ Configurable (30-90 days) | ⚠️ **30-90 day TTL** (must refresh) |
| **Data Volume Limit** | ❌ No limit (queries BigQuery) | ⚠️ 1 GB per upload |
| **Column Limit** | ❌ No limit (query any columns) | ⚠️ **25 columns max** (1 ID + 24 enrichment) |
| **Row Limit** | ❌ No limit | ⚠️ Practical limit ~5M rows per audience |
| **Historical Data** | ✅ Yes - query any time range in BQ | ❌ No - only current snapshot in AEP |

### 3.3 Query and Transformation

| Feature | FAC | External Audiences API |
|---------|-----|------------------------|
| **SQL Queries** | ✅ Yes - full SQL in AEP UI | ⚠️ Must query in BigQuery, then upload results |
| **Complex Aggregations** | ✅ Yes - leverage BigQuery engine | ✅ Yes - but in BigQuery, not AEP |
| **Window Functions** | ✅ Yes - BigQuery capabilities | ✅ Yes - but in BigQuery |
| **Machine Learning Integration** | ✅ Yes - BQML models accessible | ✅ Yes - but must export scores |
| **Custom Transformations** | ✅ Yes - SQL-based | ✅ Yes - via Cloud Run/Dataflow |

### 3.4 Operational Capabilities

| Feature | FAC | External Audiences API |
|---------|-----|------------------------|
| **UI-Based Creation** | ✅ Yes - AEP Segment Builder | ⚠️ Partial - must use API for ingestion |
| **API-Based Creation** | ✅ Yes - AEP Segmentation API | ✅ Yes - External Audiences API |
| **Status Monitoring** | ✅ Yes - AEP UI + API | ✅ Yes - status endpoints |
| **Error Handling** | ✅ Automatic retries | ⚠️ Manual retry logic required |
| **Audit Logs** | ✅ Full AEP audit trail | ✅ API call logs + AEP audit |
| **Alerting** | ✅ AEP native alerts | ⚠️ Custom alerts via Cloud Monitoring |

---

## 4. Technical Requirements

### 4.1 Security and Compliance

| Requirement | FAC | External Audiences API |
|-------------|-----|------------------------|
| **BigQuery Exposure** | ⚠️ **REQUIRED** - AEP must access BQ | ✅ **NOT REQUIRED** - push-based |
| **IP Allowlisting** | ⚠️ Required - AEP IP ranges | ✅ Optional - AEP API endpoints |
| **VPN/Private Connectivity** | ⚠️ Recommended - via Private Service Connect | ✅ Optional - public API calls OK |
| **Service Account Permissions** | Required in BigQuery (viewer + jobUser) | Not required (credentials in GCP only) |
| **Data Residency** | ⚠️ Query execution in BQ region | ⚠️ Data uploaded to AEP region |
| **BaFin Compliance** | ⚠️ May require approval | ✅ Easier approval - no BQ exposure |
| **Data Encryption** | ✅ In-transit (TLS) + at-rest (BQ native) | ✅ In-transit (TLS) + at-rest (AEP native) |
| **Audit Trail** | ✅ BigQuery audit logs + AEP logs | ✅ Cloud Run logs + AEP logs |

**Critical for Banking/Regulated Environments**:
- FAC requires **security/compliance approval** to expose BigQuery to Adobe's IPs
- External Audiences API is **push-based**, often easier to approve (you control what data leaves GCP)

### 4.2 Implementation Complexity

| Aspect | FAC | External Audiences API |
|--------|-----|------------------------|
| **Initial Setup Time** | ⏱️ 2-4 weeks | ⏱️ 1-2 weeks |
| **Service Account Creation** | Required in GCP | Not required |
| **AEP Configuration** | Federated connection setup | API credentials setup |
| **GCP Infrastructure** | None (uses existing BQ) | Cloud Run/Scheduler/Cloud Functions |
| **Code Development** | None - UI-based | Python/Node.js ETL code |
| **Testing Effort** | Low - SQL validation | Medium - API integration tests |
| **Maintenance** | Low - AEP-managed | Medium - Cloud Run deployments |

### 4.3 Performance

| Metric | FAC | External Audiences API |
|--------|-----|------------------------|
| **Query Latency** | 10 sec - 5 min (depends on BQ query) | N/A (batch upload) |
| **Upload Latency** | N/A (no upload) | 30 sec - 2 min (depends on payload size) |
| **Refresh Frequency** | Hourly, Daily, Weekly | As needed (via Cloud Scheduler) |
| **Concurrent Queries** | Limited by BigQuery quotas | N/A |
| **Concurrent Uploads** | N/A | 1 upload at a time per audience |
| **Throughput** | High (BigQuery-native) | Medium (API rate limits) |

---

## 5. Cost Analysis

### 5.1 Cost Components Breakdown

#### Federated Audience Composition (FAC)

**Assumptions**:
- 100M profiles in BigQuery
- 10 federated audiences
- Daily refresh schedule
- Average query scans 50 GB per audience per day

| Cost Component | Monthly Cost | Annual Cost | Notes |
|----------------|--------------|-------------|-------|
| **AEP Audience Activation** | $5,000 - $15,000 | $60,000 - $180,000 | Based on activated profiles (40K-200K) |
| **BigQuery Query Costs** | $1,500 - $5,000 | $18,000 - $60,000 | $5/TB scanned, 10 audiences × 50 GB × 30 days |
| **BigQuery Storage** | $2,000 - $4,000 | $24,000 - $48,000 | Existing cost (unchanged) |
| **AEP Storage** | $0 | $0 | **No profile storage** for FAC audiences |
| **Network Egress** | $0 - $100 | $0 - $1,200 | Minimal (only IDs returned) |
| **Engineering** | $15,000 - $30,000 | $180,000 - $360,000 | SQL query development, monitoring |
| **TOTAL** | **$20,600 - $58,400** | **$247,200 - $700,800** | **50% cheaper than full ingestion** |

**Cost Optimization Tips**:
- Use **partitioned tables** in BigQuery to reduce scan costs
- Use **clustered columns** for common filters (e.g., `lead_classification`)
- Use **materialized views** for frequently-accessed aggregations
- Schedule refreshes based on business needs (hourly vs daily)

#### External Audiences API

**Assumptions**:
- 100M profiles in BigQuery
- 10 external audiences
- Daily refresh schedule
- 40K profiles per audience × 10 audiences = 400K total activated profiles
- 9 enrichment fields per profile

| Cost Component | Monthly Cost | Annual Cost | Notes |
|----------------|--------------|-------------|-------|
| **AEP Audience Activation** | $5,000 - $15,000 | $60,000 - $180,000 | Based on activated profiles (400K) |
| **BigQuery Query Costs** | $500 - $1,500 | $6,000 - $18,000 | Smaller queries (SELECT id + 9 cols) |
| **BigQuery Storage** | $2,000 - $4,000 | $24,000 - $48,000 | Existing cost (unchanged) |
| **AEP Storage** | $1,000 - $3,000 | $12,000 - $36,000 | IDs + enrichment (400K × 10 fields) |
| **Cloud Run** | $50 - $150 | $600 - $1,800 | Serverless API orchestration |
| **Cloud Scheduler** | $10 - $20 | $120 - $240 | Cron jobs for refresh |
| **Network Egress** | $100 - $300 | $1,200 - $3,600 | CSV/JSON upload to AEP |
| **Engineering** | $1,500 - $4,000 | $18,000 - $48,000 | Python API code, monitoring |
| **TOTAL** | **$9,360 - $24,370** | **$112,320 - $292,440** | **~55% cheaper than FAC** |

**Cost Optimization Tips**:
- **Build audiences in BigQuery** first (use materialized views)
- **Upload only IDs** if enrichment not needed
- **Increase TTL** to reduce refresh frequency (if business allows)
- **Batch multiple audiences** in single Cloud Run execution

### 5.2 Cost Comparison Summary

| Scenario | FAC Annual Cost | External Audiences Annual Cost | Savings |
|----------|----------------|-------------------------------|---------|
| **Low Volume** (10 audiences, 40K profiles each) | $247K | $112K | **$135K (55%)** |
| **Medium Volume** (20 audiences, 100K profiles each) | $475K | $185K | **$290K (61%)** |
| **High Volume** (50 audiences, 200K profiles each) | $701K | $292K | **$409K (58%)** |

**Key Insight**: External Audiences API is **50-60% cheaper** than FAC for equivalent activated profiles, BUT:
- ⚠️ **NO Segment Builder** for enrichment attributes
- ⚠️ **Manual refresh automation** required
- ⚠️ **NOT suitable for production long-term** (Adobe recommendation)

---

## 6. API Reference

### 6.1 Federated Audience Composition (FAC) APIs

FAC uses standard **AEP Segmentation APIs** (`/segment/definitions`), but with federated data sources.

#### Create Federated Audience

**Endpoint**: `POST /data/core/ups/segment/definitions`

**Request**:
```json
{
  "name": "Hot Leads - BigQuery",
  "description": "Leads with score > 80 from BigQuery",
  "expression": {
    "type": "PQL",
    "format": "pql/text",
    "value": "SELECT customerId FROM federated_bq_connection WHERE lead_classification = 'Hot'"
  },
  "schema": {
    "name": "_xdm.context.profile"
  },
  "segmentStatus": "ACTIVE",
  "dataSource": {
    "type": "federated",
    "connectionId": "abc123-bq-connection"
  }
}
```

**Response**:
```json
{
  "id": "seg_12345",
  "status": "EVALUATING",
  "estimatedSize": 42000
}
```

#### Check Audience Status

**Endpoint**: `GET /data/core/ups/segment/jobs/{JOB_ID}`

**Response**:
```json
{
  "id": "job_67890",
  "status": "SUCCEEDED",
  "segmentId": "seg_12345",
  "profileCount": 42150,
  "completedAt": "2025-10-22T10:30:00Z"
}
```

### 6.2 External Audiences API

#### 1. Create External Audience Definition

**Endpoint**: `POST /core/ais/external-audience/`

**Headers**:
```
Authorization: Bearer {ACCESS_TOKEN}
x-api-key: {API_KEY}
x-gw-ims-org-id: {IMS_ORG_ID}
x-sandbox-name: {SANDBOX_NAME}
Content-Type: application/json
```

**Request**:
```json
{
  "audienceName": "Hot Leads - External",
  "description": "High-value leads from BigQuery",
  "audienceType": "people",
  "identityType": "customer_id",
  "ttl": 30,
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
```

**Response**:
```json
{
  "operationId": "op_abc123",
  "status": "IN_PROGRESS",
  "message": "Creating external audience definition"
}
```

#### 2. Check Creation Status

**Endpoint**: `GET /core/ais/external-audiences/operations/{OPERATION_ID}`

**Response**:
```json
{
  "operationId": "op_abc123",
  "status": "COMPLETED",
  "audienceId": "ext_aud_456789",
  "completedAt": "2025-10-22T10:25:00Z"
}
```

#### 3. Upload Audience Data (Trigger Ingestion)

**Endpoint**: `POST /core/ais/external-audience/{AUDIENCE_ID}/runs`

**Request**:
```json
{
  "dataLocation": "gs://my-bucket/hot-leads.csv",
  "dataFormat": "CSV",
  "mappings": {
    "customer_id": 0,
    "email": 1,
    "first_name": 2,
    "last_name": 3,
    "lead_score": 4,
    "lead_classification": 5,
    "product_interest": 6,
    "engagement_index": 7,
    "total_lifetime_value": 8,
    "last_interaction_date": 9
  }
}
```

**Response**:
```json
{
  "runId": "run_xyz789",
  "status": "PROCESSING",
  "startedAt": "2025-10-22T10:30:00Z"
}
```

#### 4. Check Ingestion Status

**Endpoint**: `GET /core/ais/external-audience/{AUDIENCE_ID}/runs/{RUN_ID}`

**Response**:
```json
{
  "runId": "run_xyz789",
  "status": "COMPLETED",
  "profilesIngested": 42150,
  "profilesFailed": 5,
  "completedAt": "2025-10-22T10:32:00Z",
  "errors": [
    {"row": 1234, "reason": "Invalid email format"},
    {"row": 5678, "reason": "Missing customer_id"}
  ]
}
```

#### 5. Update Audience Metadata

**Endpoint**: `PATCH /core/ais/external-audience/{AUDIENCE_ID}`

**Request**:
```json
{
  "description": "Updated: Hot leads from BigQuery (daily refresh)",
  "ttl": 60
}
```

#### 6. Delete External Audience

**Endpoint**: `DELETE /core/ais/external-audience/{AUDIENCE_ID}`

**Response**:
```json
{
  "message": "External audience deleted successfully",
  "deletedAt": "2025-10-22T10:35:00Z"
}
```

#### 7. List All External Audiences

**Endpoint**: `GET /core/ais/external-audiences`

**Query Parameters**:
- `limit`: Number of results (default: 20)
- `offset`: Pagination offset
- `orderBy`: Sort field (e.g., `createdAt`)

**Response**:
```json
{
  "audiences": [
    {
      "audienceId": "ext_aud_456789",
      "audienceName": "Hot Leads - External",
      "status": "ACTIVE",
      "profileCount": 42150,
      "lastUpdated": "2025-10-22T10:32:00Z"
    }
  ],
  "totalCount": 1,
  "hasMore": false
}
```

---

## 7. Supported Data Warehouses

### Federated Audience Composition (FAC)

FAC supports **8 enterprise data warehouses** as of October 2025:

| Data Warehouse | Support Status | Notes |
|----------------|----------------|-------|
| **Google BigQuery** | ✅ GA | Full support, best performance |
| **Snowflake** | ✅ GA | Full support |
| **Amazon Redshift** | ✅ GA | Full support |
| **Azure Synapse Analytics** | ✅ GA | Full support |
| **Databricks** | ✅ GA | Added Q2 2024 |
| **Microsoft Fabric** | ✅ GA | Added Q2 2024 |
| **Oracle Autonomous Database** | ✅ GA | Enterprise only |
| **Vertica** | ✅ GA | Enterprise only |

**Authentication Methods**:
- Service Account (GCP BigQuery)
- OAuth 2.0 (Snowflake, Databricks)
- IAM Roles (AWS Redshift)
- Azure AD (Azure Synapse, Microsoft Fabric)

**Multi-Source Federation**:
- ✅ **Yes** - Can join data across multiple warehouses in a single audience
- Example: `SELECT a.customerId FROM bigquery.leads a JOIN snowflake.transactions b ON a.id = b.customer_id`

### External Audiences API

External Audiences API is **source-agnostic** - any system that can generate CSV/JSON files:

| Source Type | Support | Implementation |
|-------------|---------|----------------|
| **BigQuery** | ✅ Yes | Export query results to GCS, upload via API |
| **Snowflake** | ✅ Yes | Export to S3/GCS, upload via API |
| **PostgreSQL** | ✅ Yes | Custom ETL script, upload via API |
| **MySQL** | ✅ Yes | Custom ETL script, upload via API |
| **CSV Files** | ✅ Yes | Direct upload via API or AEP UI |
| **CRM Systems** | ✅ Yes | Export to CSV, upload via API |
| **Custom Applications** | ✅ Yes | Generate CSV/JSON, upload via API |

**Key Difference**: FAC requires native connector, External Audiences API works with any data source.

---

## 8. Limitations and Constraints

### 8.1 Federated Audience Composition (FAC)

| Limitation | Impact | Workaround |
|------------|--------|------------|
| **Batch Only** | No real-time activation (<5 min) | Use Computed Attributes for real-time |
| **BigQuery Exposure Required** | Security approval may be blocked | Use External Audiences API |
| **Query Performance** | Slow queries delay activation | Optimize with materialized views |
| **No Write-Back** | Cannot update BigQuery from AEP | Use Reverse ETL for write-back |
| **30-Day Default TTL** | Audiences expire, require refresh | Schedule daily/weekly refreshes |
| **BigQuery Quotas** | May hit concurrent query limits | Request quota increase |

### 8.2 External Audiences API

| Limitation | Impact | Workaround |
|------------|--------|------------|
| ⚠️ **NO Segment Builder for Enrichment** | **Cannot use enrichment attributes in AEP segmentation** | Build segments in BigQuery before upload |
| **30-90 Day TTL** | **Must refresh before expiration** | Automate refresh via Cloud Scheduler |
| **25 Column Limit** | Max 1 ID + 24 enrichment fields | Prioritize most important fields |
| **1 GB File Limit** | ~5M rows max per upload | Split large audiences |
| **Batch Upload Only** | No real-time streaming (until 2026) | Use Streaming Ingestion API for real-time |
| **Single Upload at a Time** | Cannot batch multiple audiences | Queue uploads sequentially |
| **No Multi-Source Join** | One source per audience | Pre-join in BigQuery, then upload |

### 8.3 Critical Limitation: Segment Builder

**⚠️ IMPORTANT: External Audiences Enrichment Attributes NOT Usable in Segment Builder**

**What this means**:
```
✅ WORKS:
- Upload external audience with IDs + enrichment (e.g., lead_score, product_interest)
- Activate that EXACT audience to destinations (as-is)
- Use audience in Journey Optimizer (as-is)

❌ DOES NOT WORK:
- Create NEW segments in AEP Segment Builder using enrichment attributes
- Example: "All profiles in External Audience A WHERE lead_score > 80"
- Example: "Profiles in External Audience A OR External Audience B"
- Combine external audience attributes with other AEP data for segmentation
```

**Business Impact**:
- If you need to build segments in AEP UI, you MUST use FAC or full profile ingestion
- External Audiences are "static" - you activate the exact audience you uploaded
- Any segmentation logic must be done in BigQuery BEFORE uploading

**Recommendation**:
- Use External Audiences for **simple, pre-defined audiences** (e.g., "Hot Leads", "VIP Customers")
- Use FAC if you need **dynamic segmentation in AEP** (e.g., "Hot Leads who clicked email in last 7 days")

---

## 9. Use Cases and Decision Matrix

### 9.1 When to Use FAC

✅ **Best for**:
1. **Batch use cases** with no real-time requirement (<5 min)
2. **Dynamic segmentation** in AEP Segment Builder
3. **Security-approved** environments (BigQuery can be exposed to AEP)
4. **Complex SQL logic** (joins, window functions, ML models)
5. **Frequent changes** to audience criteria (no code changes needed)
6. **Cost optimization** with large datasets (query-based, no upload costs)
7. **Multi-source federation** (combine BigQuery + Snowflake + Redshift)

✅ **Example Use Cases**:
- **Lead scoring activation**: Query BigQuery for hot leads, activate to Google Ads daily
- **Churn prediction**: Use BQML churn model, activate high-risk customers to email campaigns
- **Product recommendations**: Join transaction history + ML scores, activate to Facebook Ads
- **Customer segmentation**: Complex SQL segments (RFM, CLV, engagement scores) for AEP

❌ **NOT suitable for**:
- Real-time use cases (<5 min latency)
- Environments where BigQuery exposure is blocked by security
- Simple ID-only audiences (External Audiences API is cheaper)

### 9.2 When to Use External Audiences API

✅ **Best for**:
1. **Security-blocked** environments (cannot expose BigQuery to AEP)
2. **POC/Testing** (quick validation before lobbying for FAC approval)
3. **Simple, pre-defined audiences** (no dynamic segmentation needed)
4. **Low refresh frequency** (weekly/monthly campaigns)
5. **Cost optimization** (50-60% cheaper than FAC for small audiences)
6. **Non-BigQuery sources** (PostgreSQL, CRM exports, CSV files)
7. **Temporary campaigns** (30-90 day validity is acceptable)

✅ **Example Use Cases**:
- **POC for AEP activation**: Test activation to Facebook Ads before full FAC setup
- **Static campaign audiences**: Upload "VIP Customers" list for exclusive product launch
- **Partner data integration**: Upload 3rd-party audience data (e.g., credit bureau segments)
- **CSV-based workflows**: Marketing team uploads manually-curated lists

❌ **NOT suitable for**:
- **Production long-term use** (Adobe recommends FAC for production)
- **Dynamic segmentation** (enrichment attributes NOT usable in Segment Builder)
- **Real-time use cases** (batch upload only)
- **Large audiences** (>5M profiles per audience due to 1 GB file limit)

### 9.3 When to Use Both (Hybrid)

✅ **Recommended for**:
1. **Mixed use cases**: Some audiences need dynamic segmentation (FAC), others are static (External Audiences)
2. **Phased rollout**: Start with External Audiences API for POC, migrate to FAC for production
3. **Cost optimization**: Use External Audiences for small, infrequent audiences; FAC for large, frequent audiences
4. **Security transition**: Use External Audiences while lobbying for FAC approval

✅ **Example Architecture**:
```
BigQuery
   ├── Hot Leads (10K) ────► External Audiences API ──► Facebook Ads (POC)
   ├── Warm Leads (50K) ───► FAC ─────────────────────► Google Ads (Production)
   ├── Churn Risk (100K) ──► FAC ─────────────────────► Email Campaign
   └── VIP Customers (2K) ─► External Audiences API ──► Exclusive Offers
```

### 9.4 Decision Matrix

| Criteria | FAC | External Audiences API | Hybrid |
|----------|-----|------------------------|--------|
| **BigQuery can be exposed to AEP** | ✅ Required | ❌ Not required | ⚠️ Partial |
| **Need dynamic segmentation in AEP** | ✅ Yes | ❌ No | ⚠️ Some audiences |
| **Batch latency acceptable (>5 min)** | ✅ Yes | ✅ Yes | ✅ Yes |
| **Real-time needed (<5 min)** | ❌ Not yet | ❌ Not yet | ❌ Use Computed Attributes |
| **Budget: <$200K/year** | ❌ No | ✅ Yes | ⚠️ Mixed |
| **Budget: $200K-$500K/year** | ✅ Yes | ✅ Yes | ✅ Yes |
| **POC/Testing phase** | ⚠️ Slower setup | ✅ Faster setup | ✅ Faster setup |
| **Production long-term** | ✅ Recommended | ⚠️ NOT recommended by Adobe | ✅ Use FAC for production |
| **Simple ID-only audiences** | ⚠️ Overkill | ✅ Best fit | ✅ Use External Audiences |
| **Complex SQL logic** | ✅ Best fit | ⚠️ Must run in BigQuery first | ✅ Use FAC |

---

## 10. Implementation Examples

### 10.1 Federated Audience Composition (FAC) - BigQuery Setup

#### Step 1: Create Service Account in GCP

```bash
# 1. Create service account
gcloud iam service-accounts create aep-fac-service-account \
  --display-name="AEP Federated Audience Composition" \
  --project=my-banking-project

# 2. Grant BigQuery permissions
gcloud projects add-iam-policy-binding my-banking-project \
  --member="serviceAccount:aep-fac-service-account@my-banking-project.iam.gserviceaccount.com" \
  --role="roles/bigquery.dataViewer"

gcloud projects add-iam-policy-binding my-banking-project \
  --member="serviceAccount:aep-fac-service-account@my-banking-project.iam.gserviceaccount.com" \
  --role="roles/bigquery.jobUser"

# 3. Create and download key
gcloud iam service-accounts keys create aep-fac-key.json \
  --iam-account=aep-fac-service-account@my-banking-project.iam.gserviceaccount.com
```

#### Step 2: Create Optimized BigQuery View

```sql
-- Create materialized view for performance (refreshed hourly)
CREATE MATERIALIZED VIEW `my-banking-project.crm.hot_leads_view`
PARTITION BY DATE(last_interaction_date)
CLUSTER BY lead_classification, product_interest
AS
SELECT
  customer_id,
  email,
  first_name,
  last_name,
  lead_score,
  lead_classification,
  product_interest,
  engagement_index,
  total_lifetime_value,
  last_interaction_date
FROM `my-banking-project.crm.leads`
WHERE
  lead_classification = 'Hot'
  AND lead_score > 80
  AND last_interaction_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
  AND email IS NOT NULL;

-- Schedule automatic refresh (hourly)
-- This ensures AEP queries always hit fresh data
```

#### Step 3: Configure Federated Connection in AEP UI

1. **Navigate to**: Connections > Federated Connections > New Connection
2. **Select**: Google BigQuery
3. **Upload**: `aep-fac-key.json`
4. **Configure**:
   - Project ID: `my-banking-project`
   - Dataset: `crm`
   - Connection Name: `bq-prod-crm-connection`
5. **Test Connection** → Should show "Success"

#### Step 4: Create Federated Audience in AEP

```sql
-- In AEP Segment Builder, use federated query:
SELECT customer_id
FROM federated_bq_prod_crm_connection.hot_leads_view
WHERE
  product_interest IN ('Credit Card', 'Personal Loan')
  AND engagement_index > 0.7
```

**Activation**:
- AEP will execute this query in BigQuery
- Return ~10K customer IDs to AEP
- Activate those IDs to Google Ads, Facebook Ads, Email campaigns

### 10.2 External Audiences API - Cloud Run Implementation

#### Step 1: BigQuery Query (Extract Audience)

```sql
-- Query to extract hot leads from BigQuery
SELECT
  customer_id,
  email,
  first_name,
  last_name,
  lead_score,
  lead_classification,
  product_interest,
  engagement_index,
  total_lifetime_value,
  last_interaction_date
FROM `my-banking-project.crm.leads`
WHERE
  lead_classification = 'Hot'
  AND lead_score > 80
  AND last_interaction_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
  AND email IS NOT NULL
LIMIT 50000;  -- Max ~1 GB payload

-- Export results to GCS
EXPORT DATA OPTIONS(
  uri='gs://my-bucket/audiences/hot-leads-*.csv',
  format='CSV',
  overwrite=true,
  header=true
) AS
SELECT * FROM hot_leads_query;
```

#### Step 2: Python Cloud Run Service

```python
"""
External Audiences API - Cloud Run Service
Handles AEP audience creation and upload
"""
import os
import requests
from google.cloud import bigquery, storage
from datetime import datetime
import logging

# AEP Configuration
AEP_API_BASE = "https://platform.adobe.io/data/core/ais"
AEP_IMS_ORG_ID = os.getenv("AEP_IMS_ORG_ID")
AEP_CLIENT_ID = os.getenv("AEP_CLIENT_ID")
AEP_CLIENT_SECRET = os.getenv("AEP_CLIENT_SECRET")
AEP_ACCESS_TOKEN = os.getenv("AEP_ACCESS_TOKEN")  # Refresh via OAuth
AEP_SANDBOX = "prod"

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def create_external_audience(audience_name: str, description: str) -> str:
    """
    Step 1: Create external audience definition in AEP
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

    logger.info(f"Creating external audience: {audience_name}")
    response = requests.post(url, json=payload, headers=headers)
    response.raise_for_status()

    operation_id = response.json()["operationId"]
    logger.info(f"Operation ID: {operation_id}")

    # Poll for completion (operation may take 10-30 seconds)
    audience_id = wait_for_operation(operation_id)
    logger.info(f"Audience created: {audience_id}")
    return audience_id


def wait_for_operation(operation_id: str, timeout: int = 300) -> str:
    """
    Step 2: Poll operation status until completion
    Returns: audience_id
    """
    url = f"{AEP_API_BASE}/external-audiences/operations/{operation_id}"
    headers = {
        "Authorization": f"Bearer {AEP_ACCESS_TOKEN}",
        "x-api-key": AEP_CLIENT_ID,
        "x-gw-ims-org-id": AEP_IMS_ORG_ID,
        "x-sandbox-name": AEP_SANDBOX
    }

    import time
    start_time = time.time()

    while time.time() - start_time < timeout:
        response = requests.get(url, headers=headers)
        response.raise_for_status()
        data = response.json()

        status = data["status"]
        logger.info(f"Operation status: {status}")

        if status == "COMPLETED":
            return data["audienceId"]
        elif status == "FAILED":
            raise Exception(f"Operation failed: {data.get('message')}")

        time.sleep(5)  # Poll every 5 seconds

    raise TimeoutError(f"Operation timed out after {timeout} seconds")


def upload_audience_data(audience_id: str, gcs_csv_path: str) -> str:
    """
    Step 3: Trigger ingestion run with CSV data from GCS
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
        "dataLocation": gcs_csv_path,  # e.g., "gs://my-bucket/audiences/hot-leads-000000000000.csv"
        "dataFormat": "CSV",
        "mappings": {
            "customer_id": 0,
            "email": 1,
            "first_name": 2,
            "last_name": 3,
            "lead_score": 4,
            "lead_classification": 5,
            "product_interest": 6,
            "engagement_index": 7,
            "total_lifetime_value": 8,
            "last_interaction_date": 9
        }
    }

    logger.info(f"Uploading audience data: {gcs_csv_path}")
    response = requests.post(url, json=payload, headers=headers)
    response.raise_for_status()

    run_id = response.json()["runId"]
    logger.info(f"Ingestion run started: {run_id}")
    return run_id


def wait_for_ingestion(audience_id: str, run_id: str, timeout: int = 600) -> dict:
    """
    Step 4: Poll ingestion status until completion
    Returns: ingestion stats
    """
    url = f"{AEP_API_BASE}/external-audience/{audience_id}/runs/{run_id}"
    headers = {
        "Authorization": f"Bearer {AEP_ACCESS_TOKEN}",
        "x-api-key": AEP_CLIENT_ID,
        "x-gw-ims-org-id": AEP_IMS_ORG_ID,
        "x-sandbox-name": AEP_SANDBOX
    }

    import time
    start_time = time.time()

    while time.time() - start_time < timeout:
        response = requests.get(url, headers=headers)
        response.raise_for_status()
        data = response.json()

        status = data["status"]
        logger.info(f"Ingestion status: {status} ({data.get('profilesIngested', 0)} profiles)")

        if status == "COMPLETED":
            return {
                "status": "COMPLETED",
                "profilesIngested": data["profilesIngested"],
                "profilesFailed": data["profilesFailed"],
                "completedAt": data["completedAt"]
            }
        elif status == "FAILED":
            raise Exception(f"Ingestion failed: {data.get('errors')}")

        time.sleep(10)  # Poll every 10 seconds

    raise TimeoutError(f"Ingestion timed out after {timeout} seconds")


def main_workflow(audience_name: str, bq_query: str, gcs_bucket: str):
    """
    End-to-end workflow: BigQuery → GCS → AEP External Audiences API
    """
    logger.info("=" * 80)
    logger.info(f"Starting External Audiences workflow: {audience_name}")
    logger.info("=" * 80)

    # Step 1: Extract data from BigQuery
    logger.info("Step 1: Querying BigQuery...")
    bq_client = bigquery.Client()
    gcs_path = f"gs://{gcs_bucket}/audiences/{audience_name}-*.csv"

    job_config = bigquery.QueryJobConfig(
        destination_format=bigquery.DestinationFormat.CSV,
        write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE
    )

    # Export to GCS
    extract_job = bq_client.query(f"""
        EXPORT DATA OPTIONS(
          uri='{gcs_path}',
          format='CSV',
          overwrite=true,
          header=true
        ) AS
        {bq_query}
    """, job_config=job_config)
    extract_job.result()  # Wait for completion

    # Get exact CSV file path (BigQuery appends shard number)
    storage_client = storage.Client()
    bucket = storage_client.bucket(gcs_bucket)
    blobs = list(bucket.list_blobs(prefix=f"audiences/{audience_name}-"))
    csv_file_path = f"gs://{gcs_bucket}/{blobs[0].name}"
    logger.info(f"Exported to: {csv_file_path}")

    # Step 2: Create external audience in AEP
    logger.info("Step 2: Creating external audience in AEP...")
    audience_id = create_external_audience(
        audience_name=audience_name,
        description=f"Hot leads from BigQuery - Refreshed {datetime.now().strftime('%Y-%m-%d')}"
    )

    # Step 3: Upload data
    logger.info("Step 3: Uploading audience data to AEP...")
    run_id = upload_audience_data(audience_id, csv_file_path)

    # Step 4: Wait for ingestion completion
    logger.info("Step 4: Waiting for ingestion to complete...")
    result = wait_for_ingestion(audience_id, run_id)

    logger.info("=" * 80)
    logger.info(f"✅ External Audience workflow completed!")
    logger.info(f"   Audience ID: {audience_id}")
    logger.info(f"   Profiles Ingested: {result['profilesIngested']:,}")
    logger.info(f"   Profiles Failed: {result['profilesFailed']}")
    logger.info(f"   Completed At: {result['completedAt']}")
    logger.info("=" * 80)

    return audience_id, result


if __name__ == "__main__":
    # Example usage
    BQ_QUERY = """
    SELECT
      customer_id,
      email,
      first_name,
      last_name,
      lead_score,
      lead_classification,
      product_interest,
      engagement_index,
      total_lifetime_value,
      last_interaction_date
    FROM `my-banking-project.crm.leads`
    WHERE
      lead_classification = 'Hot'
      AND lead_score > 80
      AND last_interaction_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
      AND email IS NOT NULL
    """

    audience_id, result = main_workflow(
        audience_name="hot-leads-external",
        bq_query=BQ_QUERY,
        gcs_bucket="my-aep-audiences"
    )
```

#### Step 3: Deploy to Cloud Run

```bash
# 1. Create Dockerfile
cat > Dockerfile <<EOF
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY external_audiences.py .
CMD ["python", "external_audiences.py"]
EOF

# 2. Deploy to Cloud Run
gcloud run deploy external-audiences-service \
  --source . \
  --region us-central1 \
  --platform managed \
  --allow-unauthenticated \
  --set-env-vars AEP_IMS_ORG_ID=$AEP_IMS_ORG_ID,AEP_CLIENT_ID=$AEP_CLIENT_ID \
  --set-secrets AEP_ACCESS_TOKEN=aep-access-token:latest \
  --memory 1Gi \
  --timeout 900
```

#### Step 4: Schedule with Cloud Scheduler

```bash
# Daily refresh at 6 AM UTC
gcloud scheduler jobs create http external-audiences-daily \
  --schedule="0 6 * * *" \
  --uri="https://external-audiences-service-xyz.run.app" \
  --http-method=POST \
  --message-body='{"audience":"hot-leads-external"}' \
  --time-zone="UTC"
```

---

## 11. Migration Path

### Scenario: Moving from External Audiences API (POC) to FAC (Production)

**Timeline**: 4-6 weeks

#### Phase 1: POC with External Audiences API (Weeks 1-2)

**Goal**: Validate AEP activation with minimal setup

1. ✅ Create External Audience via API (1 day)
2. ✅ Test activation to Google Ads, Facebook Ads (3 days)
3. ✅ Measure campaign performance (1 week)
4. ✅ Build business case for FAC (2 days)

**Success Criteria**:
- Audiences activate successfully to destinations
- Campaign performance meets KPIs
- Stakeholder buy-in for production rollout

#### Phase 2: Lobby for FAC Approval (Weeks 2-3)

**Goal**: Get security/compliance approval to expose BigQuery to AEP

1. 📋 Document security requirements:
   - AEP IP allowlisting
   - Private Service Connect (VPC peering)
   - Service account permissions (read-only)
   - Audit logging
2. 📋 Present to security team:
   - Risk assessment
   - Compliance checklist (BaFin, GDPR)
   - Cost-benefit analysis (FAC vs full ingestion)
3. 📋 Get written approval

**Output**: Security approval document

#### Phase 3: FAC Setup (Weeks 3-4)

**Goal**: Configure federated connection in AEP

1. ✅ Create service account in GCP (1 day)
2. ✅ Configure firewall rules (IP allowlist) (2 days)
3. ✅ Create federated connection in AEP (1 day)
4. ✅ Test connection (1 day)
5. ✅ Optimize BigQuery views (materialized views, partitioning) (2 days)

#### Phase 4: Parallel Run (Weeks 4-5)

**Goal**: Run both External Audiences API and FAC in parallel to validate

1. ✅ Create same audience via FAC
2. ✅ Compare results (profile counts, activation success rates)
3. ✅ Measure performance (query latency, activation latency)
4. ✅ Monitor costs (BigQuery query costs, AEP activation costs)

**Success Criteria**:
- FAC audience matches External Audiences API audience (±5%)
- Activation success rate ≥99%
- Query latency <2 minutes

#### Phase 5: Cutover to FAC (Week 6)

**Goal**: Migrate production traffic to FAC, retire External Audiences API

1. ✅ Update documentation (runbooks, architecture diagrams)
2. ✅ Train team on FAC usage
3. ✅ Cutover production audiences to FAC
4. ✅ Monitor for 1 week
5. ✅ Delete External Audiences (if no longer needed)

**Post-Cutover Monitoring**:
- Activation success rates
- Query performance
- BigQuery costs
- User feedback

---

## 12. Best Practices

### 12.1 Federated Audience Composition (FAC)

#### Performance Optimization

1. **Use Materialized Views**:
   ```sql
   -- Refresh hourly for best performance
   CREATE MATERIALIZED VIEW `project.dataset.hot_leads_view`
   PARTITION BY DATE(last_interaction_date)
   CLUSTER BY lead_classification, product_interest
   AS
   SELECT * FROM leads WHERE lead_classification = 'Hot';
   ```

2. **Partition Tables**:
   - Partition by date columns (e.g., `last_interaction_date`)
   - Reduces data scanned = lower costs

3. **Cluster Tables**:
   - Cluster by frequently-filtered columns (e.g., `lead_classification`)
   - Improves query performance

4. **Limit Query Complexity**:
   - Avoid deeply nested subqueries
   - Pre-aggregate in materialized views
   - Test queries in BigQuery console first

#### Cost Optimization

1. **Schedule Smartly**:
   - Daily refresh for most audiences (not hourly unless needed)
   - Use AEP's "scheduled evaluation" feature
   - Avoid peak hours (for better BigQuery slot availability)

2. **Query Optimization**:
   ```sql
   -- BAD: Scans entire table
   SELECT customer_id FROM leads WHERE lead_score > 80;

   -- GOOD: Scans only relevant partition
   SELECT customer_id FROM leads
   WHERE lead_score > 80
     AND last_interaction_date >= '2025-10-01';  -- Partition filter
   ```

3. **Monitor BigQuery Quotas**:
   - Set up alerts for query costs
   - Request quota increases if needed

#### Security

1. **Least Privilege**:
   - Service account should have ONLY `bigquery.dataViewer` and `bigquery.jobUser`
   - Do NOT grant write permissions

2. **IP Allowlisting**:
   - Allowlist only AEP IP ranges (not 0.0.0.0/0)
   - Use Private Service Connect for VPC peering (more secure)

3. **Audit Logging**:
   - Enable BigQuery audit logs
   - Monitor for unexpected queries

### 12.2 External Audiences API

#### Data Quality

1. **Validate Before Upload**:
   ```python
   # Check for duplicates
   df = pd.read_csv("hot-leads.csv")
   duplicates = df[df.duplicated(subset=['customer_id'], keep=False)]
   if len(duplicates) > 0:
       logger.warning(f"Found {len(duplicates)} duplicate customer IDs")

   # Check for nulls
   nulls = df.isnull().sum()
   if nulls['customer_id'] > 0:
       raise ValueError("customer_id cannot be null")
   ```

2. **Handle Errors Gracefully**:
   ```python
   # Retry logic for transient errors
   from tenacity import retry, stop_after_attempt, wait_exponential

   @retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=4, max=10))
   def upload_with_retry(audience_id, csv_path):
       return upload_audience_data(audience_id, csv_path)
   ```

#### Automation

1. **Automated Refresh**:
   - Use Cloud Scheduler to trigger refresh before TTL expiration
   - Set alerts for ingestion failures

2. **Monitoring**:
   ```python
   # Log metrics to Cloud Monitoring
   from google.cloud import monitoring_v3
   client = monitoring_v3.MetricServiceClient()

   # Log profiles ingested
   client.create_time_series(
       name=project_name,
       time_series=[{
           "metric": {"type": "custom.googleapis.com/aep/profiles_ingested"},
           "points": [{"value": {"int64_value": profiles_ingested}}]
       }]
   )
   ```

3. **Cost Tracking**:
   - Tag Cloud Run services with `cost-center` labels
   - Monitor BigQuery export costs
   - Monitor AEP API costs

#### Limitations Mitigation

1. **25 Column Limit**:
   - Prioritize most important fields
   - Use multiple audiences if needed (e.g., "Hot Leads" + "Hot Leads Extended")

2. **1 GB File Limit**:
   - Split large audiences into multiple files
   - Upload sequentially (not parallel)

3. **30-Day TTL**:
   - Schedule refresh at day 28 (2-day buffer)
   - Use Cloud Scheduler cron: `0 6 28 * *`

---

## 13. Troubleshooting

### 13.1 Federated Audience Composition (FAC)

#### Issue: "Connection Failed" Error

**Symptoms**: AEP cannot connect to BigQuery

**Root Causes**:
1. ❌ Service account key expired or invalid
2. ❌ IP allowlist missing AEP IPs
3. ❌ Service account lacks permissions

**Solutions**:
```bash
# 1. Verify service account has correct roles
gcloud projects get-iam-policy my-project \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:aep-fac@my-project.iam.gserviceaccount.com"

# Expected output:
# roles/bigquery.dataViewer
# roles/bigquery.jobUser

# 2. Check firewall rules
gcloud compute firewall-rules list --filter="name:aep-allowlist"

# 3. Regenerate service account key
gcloud iam service-accounts keys create new-key.json \
  --iam-account=aep-fac@my-project.iam.gserviceaccount.com
```

#### Issue: Slow Query Performance (>5 minutes)

**Symptoms**: FAC audiences take too long to evaluate

**Root Causes**:
1. ❌ Query scans large tables without partitioning
2. ❌ Complex joins or subqueries
3. ❌ BigQuery slots exhausted

**Solutions**:
```sql
-- 1. Add partition filter
SELECT customer_id FROM leads
WHERE last_interaction_date >= '2025-10-01'  -- Partition filter
  AND lead_score > 80;

-- 2. Use materialized views
CREATE MATERIALIZED VIEW leads_hot AS
SELECT * FROM leads WHERE lead_score > 80;

-- Then query the materialized view in FAC:
SELECT customer_id FROM leads_hot
WHERE last_interaction_date >= '2025-10-01';

-- 3. Request more BigQuery slots (if quotas exhausted)
-- Contact GCP support to increase reservation
```

#### Issue: "Audience Size Mismatch"

**Symptoms**: FAC audience has different profile count than BigQuery query

**Root Causes**:
1. ❌ Query timing (data changed between test and production)
2. ❌ Identity resolution in AEP (some IDs don't match profiles)
3. ❌ Duplicates in BigQuery

**Solutions**:
```sql
-- 1. Check for duplicates
SELECT customer_id, COUNT(*) as cnt
FROM leads
WHERE lead_score > 80
GROUP BY customer_id
HAVING cnt > 1;

-- 2. Use DISTINCT
SELECT DISTINCT customer_id FROM leads WHERE lead_score > 80;

-- 3. Check AEP Identity Graph for unresolved IDs
-- (use AEP Identity API)
```

### 13.2 External Audiences API

#### Issue: "Operation Failed" During Audience Creation

**Symptoms**: `create_external_audience()` returns "FAILED" status

**Root Causes**:
1. ❌ Invalid enrichment attribute type
2. ❌ Duplicate audience name
3. ❌ Invalid authentication token

**Solutions**:
```python
# 1. Verify attribute types
VALID_TYPES = ["string", "number", "boolean", "date"]

for attr in enrichment_attributes:
    if attr["type"] not in VALID_TYPES:
        raise ValueError(f"Invalid type: {attr['type']}")

# 2. Check for existing audiences
existing = requests.get(
    f"{AEP_API_BASE}/external-audiences",
    headers=headers
).json()

if audience_name in [a["audienceName"] for a in existing["audiences"]]:
    logger.warning(f"Audience '{audience_name}' already exists")

# 3. Refresh OAuth token
# (implement token refresh logic)
```

#### Issue: "Ingestion Run Stuck in PROCESSING"

**Symptoms**: `wait_for_ingestion()` times out, status never changes to COMPLETED

**Root Causes**:
1. ❌ Large file size (>1 GB)
2. ❌ Invalid CSV format (encoding, delimiters)
3. ❌ AEP backend issue (rare)

**Solutions**:
```python
# 1. Check file size
import os
file_size_gb = os.path.getsize("hot-leads.csv") / (1024**3)
if file_size_gb > 1.0:
    logger.error(f"File too large: {file_size_gb:.2f} GB (max 1 GB)")

# 2. Validate CSV format
import pandas as pd
df = pd.read_csv("hot-leads.csv", encoding="utf-8")
logger.info(f"Rows: {len(df)}, Columns: {len(df.columns)}")

# 3. Contact Adobe Support if stuck >1 hour
# Provide: audience_id, run_id, timestamp
```

#### Issue: "Enrichment Attributes Not Showing in Segment Builder"

**Symptoms**: Uploaded enrichment attributes (e.g., `lead_score`) not available in AEP Segment Builder

**Root Cause**: ⚠️ **EXPECTED BEHAVIOR** - External Audiences enrichment attributes are NOT usable in Segment Builder

**Solution**: This is a **known limitation** (not a bug):
- External Audiences enrichment attributes are metadata only
- They are sent to destinations (e.g., Facebook Ads) but NOT available for segmentation in AEP
- **Workaround**: Use FAC if you need dynamic segmentation in AEP

---

## 14. Frequently Asked Questions (FAQ)

### Q1: Can I use both FAC and External Audiences API in the same AEP instance?

✅ **Yes!** You can use both approaches for different audiences:
- FAC for production, dynamic segmentation use cases
- External Audiences API for POC, static lists, or when security blocks FAC

**Example**:
- Hot Leads (dynamic, complex SQL) → FAC
- VIP Customers (static list from CRM) → External Audiences API

---

### Q2: Does FAC work with Snowflake or Redshift, or only BigQuery?

✅ **Yes!** FAC supports 8 data warehouses:
- Google BigQuery
- Snowflake
- Amazon Redshift
- Azure Synapse Analytics
- Databricks
- Microsoft Fabric
- Oracle Autonomous Database
- Vertica

You can even **federate across multiple warehouses** in a single audience (e.g., join BigQuery leads + Snowflake transactions).

---

### Q3: What happens if my External Audience expires (30-day TTL)?

⚠️ **The audience becomes inactive**:
- It will no longer activate to destinations
- Historical activations are NOT retroactively deleted (e.g., Facebook Ads audience remains)
- You must re-upload to reactivate

**Best Practice**: Schedule automated refresh at day 28 (2-day buffer before expiration).

---

### Q4: Can I use FAC for real-time activation (<5 min latency)?

❌ **Not yet** (as of October 2025):
- FAC is **batch-only** (hourly/daily/weekly refresh)
- Real-time FAC is on Adobe's roadmap (no ETA)

**Alternatives for real-time**:
- **Computed Attributes Pattern** (stream derived scores to AEP)
- **AEP Streaming Ingestion API** (stream events to AEP)

---

### Q5: How much does FAC cost vs External Audiences API?

**Quick Answer**:
- **FAC**: $247K-$701K/year (medium-large audiences, frequent refresh)
- **External Audiences API**: $112K-$292K/year (small-medium audiences, infrequent refresh)

**Key Insight**: External Audiences API is **50-60% cheaper** for small audiences, BUT not recommended for production long-term by Adobe.

---

### Q6: Can I use External Audiences enrichment attributes in AEP Segment Builder?

❌ **NO** - This is a **critical limitation**:
- Enrichment attributes (e.g., `lead_score`, `product_interest`) are sent to destinations
- They are **NOT available** in AEP Segment Builder for dynamic segmentation
- You must build segments in BigQuery **before** uploading

**Workaround**: Use FAC if you need dynamic segmentation in AEP.

---

### Q7: Does FAC store any customer data in AEP?

❌ **NO** - FAC is **true zero-copy**:
- AEP only stores **metadata** (audience name, query definition, schedule)
- Customer data **never leaves BigQuery**
- AEP executes queries via federated connection, returns only IDs

---

### Q8: Can I use External Audiences API for real-time streaming?

❌ **Not yet** (as of October 2025):
- External Audiences API is **batch-only** (upload CSV/JSON)
- Real-time streaming ingestion is planned for **2026**

**Alternatives for real-time**:
- **AEP Streaming Ingestion API** (stream events to AEP Profile Store)
- **Event Forwarding** (pass-through via AEP Edge Network)

---

### Q9: What's the maximum audience size for FAC vs External Audiences API?

| Approach | Max Audience Size | Notes |
|----------|-------------------|-------|
| **FAC** | ❌ **No limit** | Queries BigQuery directly (100M+ profiles OK) |
| **External Audiences API** | ⚠️ **~5M profiles** | Limited by 1 GB file size |

**For very large audiences (>5M)**:
- Use FAC (no upload limits)
- OR split into multiple External Audiences

---

### Q10: How do I migrate from External Audiences API to FAC?

**See Section 11: Migration Path** for detailed timeline and steps.

**Quick Summary**:
1. POC with External Audiences API (2 weeks)
2. Lobby for FAC approval (1-2 weeks)
3. FAC setup (1 week)
4. Parallel run (1 week)
5. Cutover to FAC (1 week)

**Total timeline**: 4-6 weeks

---

## 15. Summary and Recommendations

### Quick Decision Guide

**Choose FAC if**:
- ✅ BigQuery can be exposed to AEP (security approval obtained)
- ✅ Need dynamic segmentation in AEP Segment Builder
- ✅ Large audiences (>5M profiles)
- ✅ Production long-term use
- ✅ Frequent refresh (hourly/daily)
- ✅ Complex SQL logic (joins, window functions, ML models)

**Choose External Audiences API if**:
- ✅ Security blocks BigQuery exposure (push-based OK)
- ✅ POC/testing phase (quick validation)
- ✅ Small audiences (<5M profiles)
- ✅ Simple, pre-defined audiences (no dynamic segmentation needed)
- ✅ Infrequent refresh (weekly/monthly)
- ✅ Cost-sensitive (50-60% cheaper than FAC)

**Choose Hybrid (Both) if**:
- ✅ Some audiences need dynamic segmentation (FAC), others are static (External Audiences)
- ✅ Phased rollout (start with External Audiences, migrate to FAC)
- ✅ Mixed requirements (real-time + batch, large + small audiences)

### Final Recommendations

1. **For Banking/Regulated Environments**:
   - Start with **External Audiences API** for POC (2-4 weeks)
   - Lobby for FAC approval in parallel
   - Migrate to **FAC for production** (6-8 weeks)
   - Keep External Audiences API for edge cases (partner data, CRM exports)

2. **For Cost Optimization**:
   - Use **External Audiences API** for small, infrequent audiences
   - Use **FAC** for large, frequent audiences
   - Monitor costs monthly, adjust strategy as needed

3. **For Real-Time Use Cases**:
   - ⚠️ **Neither FAC nor External Audiences API supports real-time** (as of October 2025)
   - Use **Computed Attributes Pattern** (stream derived scores to AEP)
   - OR use **Hybrid Selective Pattern** (99% FAC batch + 1% streaming)

4. **For Simplicity**:
   - If you just need to activate audiences (no segmentation), **External Audiences API** is simpler
   - If you need dynamic segmentation, **FAC** is worth the setup effort

---

## 16. Additional Resources

### Adobe Documentation

- **FAC Official Docs**: https://experienceleague.adobe.com/docs/experience-platform/segmentation/ui/audience-composition.html
- **External Audiences API**: https://experienceleague.adobe.com/docs/experience-platform/segmentation/api/external-audiences.html
- **AEP Segmentation API**: https://experienceleague.adobe.com/docs/experience-platform/segmentation/api/overview.html

### GCP Documentation

- **BigQuery Federated Queries**: https://cloud.google.com/bigquery/docs/federated-queries-intro
- **Cloud Run**: https://cloud.google.com/run/docs
- **Cloud Scheduler**: https://cloud.google.com/scheduler/docs

### Related Documents

- **[aep-zero-copy-executive-summary.md](aep-zero-copy-executive-summary.md)**: Executive decision guide
- **[architecture-decision-records/adr-001-aep-bigquery-integration.md](architecture-decision-records/adr-001-aep-bigquery-integration.md)**: Formal ADR with all 4 options
- **[aep-concepts-faq.md](aep-concepts-faq.md)**: Business-friendly FAQ (Q33: FAC mechanics, Q34: Push-based alternatives)

---

**Document End**

**Last Updated**: October 22, 2025
**Version**: 1.0
**Feedback**: Please submit issues or questions via project issue tracker
