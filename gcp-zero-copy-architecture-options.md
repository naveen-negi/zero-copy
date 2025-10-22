# GCP Zero-Copy Architecture Patterns

**Universal Guide for Minimizing Data Duplication Across Any Integration**

**Not AEP-Specific** | Applicable to: Databases, Analytics Tools, ML Platforms, External Vendors, Internal Systems

---

## Executive Summary

This document analyzes the **top 3 GCP architecture patterns** for achieving zero-copy or minimal data duplication when integrating with external or internal systems.

### The Three Patterns

| Pattern | Data Movement | Latency | Cost | Complexity | Best For |
|---------|--------------|---------|------|------------|----------|
| **1. Federated Query (BigQuery External Connections)** | ZERO (query in-place) | Medium (10-60s) | LOW | Low | Read-only analytics, batch reporting, BI tools |
| **2. Shared Data Lake (Cloud Storage + IAM)** | ZERO (shared pointers) | Low (1-5s) | VERY LOW | Very Low | Multi-team access, data science, ML training |
| **3. Change Data Capture (Datastream CDC)** | MINIMAL (only deltas) | Very Low (<1s) | MEDIUM | Medium | Real-time sync, transactional systems, event-driven |

---

## Quick Decision Tree

```
What's your primary integration need?

┌─ Read-only analytics / BI dashboards?
│  └─ Use Pattern 1: Federated Query
│     → External system queries BigQuery directly
│     → TRUE zero-copy, no data duplication
│
┌─ Multi-team data access (data science, ML, analytics)?
│  └─ Use Pattern 2: Shared Data Lake
│     → Everyone reads from same Cloud Storage bucket
│     → TRUE zero-copy, shared pointers only
│
└─ Real-time synchronization with transactional database?
   └─ Use Pattern 3: Change Data Capture (CDC)
      → Only replicate changes (inserts/updates/deletes)
      → Minimal-copy, not zero-copy
```

---

## Pattern 1: Federated Query (BigQuery External Connections)

**Philosophy**: Don't copy data. Let the external system query your data warehouse directly.

### How It Works

```
┌──────────────────────────────────────────────────────────────────┐
│                         Your GCP Project                         │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │              BigQuery Data Warehouse                       │ │
│  │                                                            │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │ │
│  │  │   customers  │  │    orders    │  │   products   │   │ │
│  │  │  (10M rows)  │  │  (100M rows) │  │  (50K rows)  │   │ │
│  │  └──────────────┘  └──────────────┘  └──────────────┘   │ │
│  │                                                            │ │
│  └────────────────────────────────────────────────────────────┘ │
│                              ↑                                   │
│                              │ (Federated Query)                 │
│                              │ BigQuery Connection              │
│                              │ Service Account: bigquery.dataViewer │
└──────────────────────────────┼──────────────────────────────────┘
                               │
                               ↓
┌──────────────────────────────────────────────────────────────────┐
│                       External System                            │
│                                                                  │
│  Examples:                                                       │
│  • Tableau / Looker / Power BI                                  │
│  • Snowflake (via External Tables)                              │
│  • Apache Spark / Databricks                                    │
│  • Custom analytics platform                                    │
│  • Partner vendor system                                        │
│                                                                  │
│  System generates SQL:                                          │
│  SELECT customer_id, SUM(order_total)                           │
│  FROM \`your-project.dataset.orders\`                             │
│  WHERE order_date >= '2025-01-01'                               │
│  GROUP BY customer_id                                           │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘

Data Movement: ZERO bytes copied
Data Duplication: 0%
```

### Implementation Examples

See the complete implementation guide in: [option2-computed-attributes-analysis/gcp-implementation-guide.md](option2-computed-attributes-analysis/gcp-implementation-guide.md) for detailed BigQuery federated query examples.

**Key Steps**:
1. Create service account with `bigquery.dataViewer` + `bigquery.jobUser` roles
2. Create read-only views for security (expose only necessary columns)
3. Configure external system with service account credentials
4. Optimize with materialized views for frequently queried data

### When to Use

✅ **Ideal For**:
- Read-only analytics and BI dashboards (Tableau, Power BI, Looker)
- Batch reporting (daily/weekly/monthly)
- Partner integrations requiring query access
- Multi-cloud analytics (AWS tools querying GCP data)

❌ **NOT Suitable For**:
- Real-time operational workloads (10-60s latency too high)
- Write-heavy integrations
- Regulated environments blocking external DB access (use Pattern 2/3 instead)

### Cost Example

**Assumptions**: 10M customers, 100M orders, 100 queries/day

| Component | Monthly Cost |
|-----------|--------------|
| BigQuery Storage (1TB) | $20 |
| External Queries (100/day × 10GB scanned) | $50 |
| **Total** | **$70/month** |

**Savings**: No duplication storage, no ETL pipeline costs

---

## Pattern 2: Shared Data Lake (Cloud Storage + IAM)

**Philosophy**: Store data once in Cloud Storage. Grant read access to multiple teams/systems via IAM.

### How It Works

```
┌──────────────────────────────────────────────────────────────────┐
│                    GCP Cloud Storage Bucket                      │
│                  gs://company-data-lake/                         │
│                                                                  │
│  customers/                                                      │
│    └── year=2025/month=10/customers_20251021.parquet            │
│  orders/                                                         │
│    └── year=2025/month=10/day=21/orders_20251021.parquet        │
│  products/                                                       │
│    └── products_latest.parquet                                  │
│                                                                  │
└───────────┬──────────────────────────────────────────────────────┘
            │ (All teams read SAME files - zero-copy)
     ┌──────┼──────┬──────────┬────────────┐
     │      │      │          │            │
     ↓      ↓      ↓          ↓            ↓
┌─────────┬─────┬──────┬────────────┬──────────┐
│BigQuery │Spark│Pandas│ Vertex AI  │ External │
│External │     │      │ Notebooks  │ Partner  │
│ Tables  │     │      │            │          │
└─────────┴─────┴──────┴────────────┴──────────┘
```

### Implementation

**Create Shared Bucket**:
```bash
# Create bucket with uniform IAM
gsutil mb -c STANDARD -l US gs://company-data-lake
gsutil uniformbucketlevelaccess set on gs://company-data-lake

# Organize with Hive partitioning
gs://company-data-lake/
  customers/year=2025/month=10/*.parquet
  orders/year=2025/month=10/day=21/*.parquet
```

**Grant Team Access**:
```bash
# Team A: Read-only for analytics
gsutil iam ch \
  serviceAccount:team-a@project.iam.gserviceaccount.com:roles/storage.objectViewer \
  gs://company-data-lake/customers/

# Team B: Data science (all data)
gsutil iam ch \
  group:data-science@company.com:roles/storage.objectViewer \
  gs://company-data-lake

# Team C: ML engineering (read-write for predictions)
gsutil iam ch \
  serviceAccount:vertex-ai@project.iam.gserviceaccount.com:roles/storage.objectAdmin \
  gs://company-data-lake/ml_predictions/
```

**Query from BigQuery**:
```sql
-- External table (no data copying)
CREATE EXTERNAL TABLE `project.dataset.customers`
OPTIONS (
  format = 'PARQUET',
  uris = ['gs://company-data-lake/customers/year=*/month=*/*.parquet'],
  hive_partition_uri_prefix = 'gs://company-data-lake/customers/'
);

-- Query with partition pruning
SELECT * FROM `project.dataset.customers`
WHERE year = 2025 AND month = 10;  -- Scans only 1 file
```

**Read from Spark**:
```python
# Read Parquet directly (no copying)
df = spark.read.parquet("gs://company-data-lake/customers/year=2025/month=10/*.parquet")
df.show()
```

**Read from Pandas**:
```python
import pandas as pd
df = pd.read_parquet("gs://company-data-lake/customers/year=2025/month=10/*.parquet")
```

### When to Use

✅ **Ideal For**:
- Multi-team data access (analytics, ML, data science)
- Data science workloads (need full data access, not just queries)
- Cost-sensitive projects (Cloud Storage is 10x cheaper than BigQuery)
- Unstructured data (images, videos, logs)

❌ **NOT Suitable For**:
- Transactional workloads (Cloud Storage is not a database)
- Real-time updates (eventual consistency)

### Cost Example

**Assumptions**: 1TB data, 5 teams accessing, 100GB egress to external partner

| Component | Monthly Cost |
|-----------|--------------|
| Cloud Storage (1TB Standard) | $20 |
| BigQuery External Queries | $50 |
| Egress to Internet (100GB) | $12 |
| **Total** | **$82/month** |

**Savings vs Duplication**:
- Without sharing: 5 teams × 1TB = 5TB = $100
- With shared lake: 1TB = $20
- **Savings: $80/month (80% reduction)**

### Best Practices

1. **Use Parquet format** (5-10x faster than CSV, built-in compression)
2. **Partition by date** (year=/month=/day= - prunes 99% of files)
3. **Cluster within partitions** (sort by commonly filtered columns)
4. **Compact small files** (100-500MB per file optimal)
5. **Enable versioning** (data recovery if accidentally deleted)

---

## Pattern 3: Change Data Capture (Datastream CDC)

**Philosophy**: Replicate only changed data (inserts/updates/deletes), not full snapshots.

### How It Works

```
┌─────────────────────────────────────────────────────────────┐
│          Source Database (PostgreSQL / MySQL)               │
│                                                             │
│  customers table:                                           │
│  ┌────┬──────────┬─────────────┬──────────────┐            │
│  │ id │ name     │ email       │ updated_at   │            │
│  ├────┼──────────┼─────────────┼──────────────┤            │
│  │ 1  │ Alice    │ a@ex.com    │ 10:00:00     │ ← UPDATE   │
│  │ 2  │ Bob      │ b@ex.com    │ 09:00:00     │            │
│  │ 3  │ Charlie  │ c@ex.com    │ 11:00:00     │ ← INSERT   │
│  └────┴──────────┴─────────────┴──────────────┘            │
│                                                             │
│  Binary Log / WAL (Change Stream):                         │
│  [10:00:01] UPDATE customers SET name='Alice Smith' WHERE id=1 │
│  [11:00:05] INSERT INTO customers VALUES (3, 'Charlie', ...) │
└──────────────────────────────┬──────────────────────────────┘
                               │ Datastream reads change log
                               ↓
┌───────────────────────────────────────────────────────────────┐
│                   GCP Datastream Service                      │
│                                                               │
│  • Reads change log continuously                             │
│  • Transforms to Avro/JSON                                   │
│  • Writes to BigQuery/Cloud Storage/Pub/Sub                  │
└──────────────────────────────┬────────────────────────────────┘
                               ↓
┌───────────────────────────────────────────────────────────────┐
│              Target: BigQuery (CDC Table)                     │
│                                                               │
│  customers_cdc:                                               │
│  ┌────┬──────┬────────┬──────────────┬────────────────────┐  │
│  │ id │ name │ email  │_change_type  │ _metadata_timestamp│  │
│  ├────┼──────┼────────┼──────────────┼────────────────────┤  │
│  │ 1  │Alice │a@ex.com│ INSERT       │ 09:00:00           │  │
│  │ 1  │AliceS│a@ex.com│ UPDATE       │ 10:00:01           │← Only 2 changes  │
│  │ 3  │Charli│c@ex.com│ INSERT       │ 11:00:05           │← Not full table │
│  └────┴──────┴────────┴──────────────┴────────────────────┘  │
│                                                               │
│  Data Movement: MINIMAL (only 2 changed rows, not 1M total)  │
└───────────────────────────────────────────────────────────────┘
```

### Implementation

**Prepare Source Database (PostgreSQL)**:
```sql
-- Enable logical replication
-- Edit postgresql.conf: wal_level = logical

-- Create replication user
CREATE USER datastream_user WITH REPLICATION PASSWORD 'password';
GRANT SELECT ON ALL TABLES IN SCHEMA public TO datastream_user;

-- Create publication
CREATE PUBLICATION datastream_pub FOR ALL TABLES;
```

**Create Datastream**:
```bash
# Connection profile for source
gcloud datastream connection-profiles create postgres-source \
  --location=us-central1 \
  --type=postgresql \
  --postgresql-username=datastream_user \
  --postgresql-password=password \
  --postgresql-hostname=10.0.0.5 \
  --postgresql-database=production_db

# Connection profile for destination
gcloud datastream connection-profiles create bigquery-dest \
  --location=us-central1 \
  --type=bigquery

# Create stream
gcloud datastream streams create postgres-to-bq \
  --location=us-central1 \
  --source=postgres-source \
  --destination=bigquery-dest \
  --backfill-all  # Copy existing data first, then stream changes
```

**Query Latest State in BigQuery**:
```sql
-- Deduplicate CDC table to get current state
WITH latest_changes AS (
  SELECT
    *,
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY _metadata_timestamp DESC) as rn
  FROM `project.cdc_public.customers`
  WHERE _metadata_deleted = FALSE
)
SELECT * EXCEPT(rn, _metadata_timestamp, _metadata_deleted, _metadata_change_type)
FROM latest_changes
WHERE rn = 1;  -- Only latest version of each row
```

**Automate Deduplication**:
```sql
-- Scheduled query (every 15 min)
CREATE OR REPLACE TABLE `project.analytics.customers_current`
PARTITION BY DATE(_last_modified)
AS
WITH latest AS (
  SELECT * EXCEPT(rn)
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (PARTITION BY id ORDER BY _metadata_timestamp DESC) as rn
    FROM `project.cdc_public.customers`
    WHERE _metadata_deleted = FALSE
  )
  WHERE rn = 1
)
SELECT *, CURRENT_TIMESTAMP() as _last_modified
FROM latest;
```

### When to Use

✅ **Ideal For**:
- Real-time sync between transactional DB and analytics DWH (<15 sec latency)
- Event-driven architectures (trigger actions on data changes)
- Database migration (continuous sync during cutover)
- Disaster recovery / active-passive replication

❌ **NOT Suitable For**:
- Batch workloads (Pattern 1/2 simpler and cheaper)
- Append-only data (just write directly to BigQuery)
- Unstructured data (CDC only for SQL databases)

### Cost Example

**Assumptions**: 1TB source database, 10GB changes/day (1% churn)

| Component | Monthly Cost |
|-----------|--------------|
| Datastream (10GB/day × 30 × $0.02/GB) | $6 |
| BigQuery Storage (1TB current + 300GB deltas) | $26 |
| BigQuery Deduplication Queries | $5 |
| **Total** | **$37/month** |

**Savings vs Full Daily Snapshot**:
- Full snapshot: 1TB/day × 30 = 30TB = $300/month
- CDC (deltas): 10GB/day × 30 = 300GB = $11/month
- **Savings: $289/month (96% reduction)**

### Performance

| Metric | Value |
|--------|-------|
| Replication Latency | 1-15 seconds |
| Throughput | 10,000 changes/second |
| Data Freshness | Configurable (0s to 900s) |

---

## Comparison Summary

| Criteria | Pattern 1: Federated | Pattern 2: Shared Lake | Pattern 3: CDC |
|----------|---------------------|------------------------|----------------|
| **Data Movement** | ZERO | ZERO | MINIMAL (deltas) |
| **Latency** | 10-60s | 1-5s | <15s |
| **Cost** | LOW ($70/mo) | VERY LOW ($82/mo) | MEDIUM ($37/mo) |
| **Complexity** | Low | Very Low | Medium |
| **Real-Time** | ❌ No | ❌ No | ✅ Yes |
| **Best For** | Analytics/BI | Multi-team access | Transactional sync |

---

## Decision Framework

```
What is your primary integration need?

├─ SQL Analytics / BI Dashboards?
│  └─ Use Pattern 1: Federated Query
│     (External system queries BigQuery directly)
│
├─ Multi-Team Data Access (data science, ML, analytics)?
│  └─ Use Pattern 2: Shared Data Lake
│     (Everyone reads same Cloud Storage files)
│
└─ Real-Time Sync with Transactional Database?
   └─ Use Pattern 3: CDC
      (Replicate only changes via Datastream)
```

---

## Common Pitfalls & Solutions

### Pattern 1: Federated Query

**Problem**: Slow queries (60+ seconds)
**Solution**: Create materialized views with partitioning

**Problem**: Unexpected BigQuery costs
**Solution**: Set BigQuery quotas (max bytes scanned per query)

**Problem**: Security team blocks external DB access
**Solution**: Use Pattern 2/3 instead (push-based, not pull-based)

### Pattern 2: Shared Data Lake

**Problem**: Slow file reads (5+ seconds)
**Solution**: Compact small files to 100-500MB Parquet

**Problem**: Schema evolution breaks readers
**Solution**: Use Parquet schema evolution mode

**Problem**: Accidental data deletion
**Solution**: Enable versioning + lifecycle management

### Pattern 3: CDC

**Problem**: BigQuery table grows unbounded
**Solution**: Partition by timestamp, auto-delete old partitions

**Problem**: Replication lag (15+ minutes)
**Solution**: Reduce Datastream parallelism or scale source DB

**Problem**: Schema changes break replication
**Solution**: Pause stream, update BigQuery schema, resume

---

## Implementation Checklist

### Pattern 1: Federated Query
- [ ] Create service account with `bigquery.dataViewer` role
- [ ] Create read-only views (expose only necessary columns)
- [ ] Enable BigQuery audit logs
- [ ] Test query from external system
- [ ] Create materialized views for performance
- [ ] Set budget alerts

### Pattern 2: Shared Data Lake
- [ ] Create Cloud Storage bucket with uniform IAM
- [ ] Organize data with Hive partitioning (year=/month=/day=/)
- [ ] Convert data to Parquet format
- [ ] Grant IAM permissions to teams (roles/storage.objectViewer)
- [ ] Create BigQuery external tables
- [ ] Enable versioning and lifecycle policies
- [ ] Document schema conventions

### Pattern 3: CDC
- [ ] Configure source DB for logical replication
- [ ] Create replication user with SELECT privileges
- [ ] Create Datastream connection profiles
- [ ] Create Datastream stream with backfill
- [ ] Create scheduled query for deduplication
- [ ] Monitor replication lag
- [ ] Enable Datastream audit logs
- [ ] Document schema evolution process

---

## Conclusion

**Key Takeaways**:

1. **Pattern 1 (Federated Query)**: Best for read-only analytics, TRUE zero-copy
2. **Pattern 2 (Shared Data Lake)**: Most versatile, works with any tool, TRUE zero-copy
3. **Pattern 3 (CDC)**: Best for real-time, minimal-copy (only deltas)

**Cost Savings**:
- Shared Data Lake reduces storage costs by 75-96%
- CDC reduces sync costs by 96% vs full snapshots

**For Banking/Regulated Environments**:
- Prefer Pattern 2/3 (push-based) over Pattern 1 (pull-based)
- Pattern 2 offers best security control (you decide what leaves GCP)

**Recommended Approach**:
1. Start with Pattern 2 (Shared Data Lake) for maximum flexibility
2. Add Pattern 1 (Federated Query) for SQL analytics use cases
3. Use Pattern 3 (CDC) only when real-time (<15s) is required

---

**Last Updated**: October 22, 2025
**Author**: GCP Data/ML Architect
**Related Docs**:
- [aep-zero-copy-executive-summary.md](aep-zero-copy-executive-summary.md) - AEP-specific integration patterns
- [option2-computed-attributes-analysis/gcp-implementation-guide.md](option2-computed-attributes-analysis/gcp-implementation-guide.md) - Detailed BigQuery implementation examples
