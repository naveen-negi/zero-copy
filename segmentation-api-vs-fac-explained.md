# Segmentation: External Audiences API vs FAC
## Practical Guide for Hot/Cold/Warm Leads Use Case

**Last Updated**: October 22, 2025

---

## Your Question: Do I need separate audiences for Hot, Cold, and Warm?

### Short Answer:

| Approach | Hot/Cold/Warm Handling |
|----------|------------------------|
| **External Audiences API** | ❌ **YES** - Create 3 separate audiences (Hot, Cold, Warm) |
| **FAC** | ✅ **NO** - Create 1 federated source, then segment in AEP UI |

---

## Detailed Explanation

### Option 1: External Audiences API (Static Audiences)

With External Audiences API, you must create **separate audiences** for Hot, Cold, and Warm because:
- ⚠️ **Enrichment attributes CANNOT be used for segmentation in AEP**
- Each audience is a "static list" that you activate as-is
- You cannot create NEW segments in AEP Segment Builder using the `lead_classification` field

#### Example: Email Campaign with External Audiences API

**Step 1: Create 3 Separate Audiences in BigQuery**

```sql
-- Query 1: Extract HOT leads
SELECT
  customer_id,
  email,
  first_name,
  last_name,
  lead_score,
  'Hot' as lead_classification,  -- Include as enrichment, but can't segment on it
  product_interest,
  engagement_index
FROM `my-project.crm.leads`
WHERE lead_classification = 'Hot'
  AND email IS NOT NULL;
-- Export to: hot-leads.csv

-- Query 2: Extract WARM leads
SELECT
  customer_id,
  email,
  first_name,
  last_name,
  lead_score,
  'Warm' as lead_classification,
  product_interest,
  engagement_index
FROM `my-project.crm.leads`
WHERE lead_classification = 'Warm'
  AND email IS NOT NULL;
-- Export to: warm-leads.csv

-- Query 3: Extract COLD leads
SELECT
  customer_id,
  email,
  first_name,
  last_name,
  lead_score,
  'Cold' as lead_classification,
  product_interest,
  engagement_index
FROM `my-project.crm.leads`
WHERE lead_classification = 'Cold'
  AND email IS NOT NULL;
-- Export to: cold-leads.csv
```

**Step 2: Upload 3 Separate Audiences via API**

```python
# You MUST create 3 separate audiences in AEP

# 1. Hot Leads Audience
hot_audience_id = create_external_audience(
    audience_name="Hot Leads - External",
    description="High-intent leads for aggressive email campaigns"
)
upload_audience_data(hot_audience_id, "gs://bucket/hot-leads.csv")

# 2. Warm Leads Audience
warm_audience_id = create_external_audience(
    audience_name="Warm Leads - External",
    description="Moderate-intent leads for nurture campaigns"
)
upload_audience_data(warm_audience_id, "gs://bucket/warm-leads.csv")

# 3. Cold Leads Audience
cold_audience_id = create_external_audience(
    audience_name="Cold Leads - External",
    description="Low-intent leads for awareness campaigns"
)
upload_audience_data(cold_audience_id, "gs://bucket/cold-leads.csv")
```

**Step 3: In AEP - You Have 3 Separate, Static Audiences**

```
AEP Audiences View:
├── Hot Leads - External (42,000 profiles)
├── Warm Leads - External (125,000 profiles)
└── Cold Leads - External (380,000 profiles)

Each audience is INDEPENDENT and STATIC.
```

**Step 4: Activate to Email Campaign**

```
In Adobe Journey Optimizer (or Campaign):

Campaign 1: "Hot Leads - Product Launch"
  └── Select audience: "Hot Leads - External"
  └── Email: Aggressive offer (20% discount)

Campaign 2: "Warm Leads - Educational Nurture"
  └── Select audience: "Warm Leads - External"
  └── Email: Educational content + 10% discount

Campaign 3: "Cold Leads - Awareness"
  └── Select audience: "Cold Leads - External"
  └── Email: Brand awareness, no discount
```

**⚠️ What You CANNOT Do with External Audiences API:**

```
❌ DOES NOT WORK:
In AEP Segment Builder, you CANNOT create:
- "All Hot Leads OR Warm Leads" (combine audiences)
- "Hot Leads WHERE product_interest = 'Credit Card'" (segment on enrichment)
- "Hot Leads WHO clicked email in last 7 days" (combine with AEP behavioral data)

The enrichment attribute "lead_classification" is sent to destinations
(e.g., email tool receives "lead_classification: Hot") but CANNOT be used
for NEW segmentation in AEP.
```

---

### Option 2: Federated Audience Composition (FAC) (Dynamic Segmentation)

With FAC, you create **ONE federated connection** and then segment dynamically in AEP:

#### Example: Email Campaign with FAC

**Step 1: Create Federated Connection (One-Time Setup)**

In AEP UI:
1. Navigate to: Connections > Federated Connections > New Connection
2. Select: Google BigQuery
3. Upload service account key
4. Test connection to `my-project.crm.leads` table

**Step 2: Create Audiences in AEP UI (Dynamic SQL Queries)**

You can now create multiple audiences in AEP using federated queries:

```sql
-- In AEP Segment Builder, create Audience 1:
-- Name: "Hot Leads - FAC"
SELECT customer_id
FROM federated_bq_connection.leads
WHERE lead_classification = 'Hot'
  AND email IS NOT NULL;

-- In AEP Segment Builder, create Audience 2:
-- Name: "Warm Leads - FAC"
SELECT customer_id
FROM federated_bq_connection.leads
WHERE lead_classification = 'Warm'
  AND email IS NOT NULL;

-- In AEP Segment Builder, create Audience 3:
-- Name: "Cold Leads - FAC"
SELECT customer_id
FROM federated_bq_connection.leads
WHERE lead_classification = 'Cold'
  AND email IS NOT NULL;
```

**Alternatively, you can create COMBINED audiences:**

```sql
-- Audience: "Hot OR Warm Leads - FAC"
SELECT customer_id
FROM federated_bq_connection.leads
WHERE lead_classification IN ('Hot', 'Warm')
  AND email IS NOT NULL;

-- Audience: "Hot Leads - Credit Card Interest"
SELECT customer_id
FROM federated_bq_connection.leads
WHERE lead_classification = 'Hot'
  AND product_interest = 'Credit Card'
  AND email IS NOT NULL;

-- Audience: "High-Value Hot Leads"
SELECT customer_id
FROM federated_bq_connection.leads
WHERE lead_classification = 'Hot'
  AND lead_score > 90
  AND total_lifetime_value > 10000
  AND email IS NOT NULL;
```

**Step 3: In AEP - You Have 1 Federated Source + Dynamic Audiences**

```
AEP Data Sources:
└── Federated Connection: "BigQuery CRM" (Connected to my-project.crm.leads)

AEP Audiences (dynamically created from federated source):
├── Hot Leads - FAC (42,000 profiles)
├── Warm Leads - FAC (125,000 profiles)
├── Cold Leads - FAC (380,000 profiles)
├── Hot OR Warm Leads - FAC (167,000 profiles)  ← Combined!
├── Hot Leads - Credit Card Interest (18,500 profiles)  ← Filtered!
└── High-Value Hot Leads (8,200 profiles)  ← Complex logic!
```

**Step 4: Activate to Email Campaign**

Same as External Audiences API, but now you have MORE FLEXIBILITY:

```
In Adobe Journey Optimizer:

Campaign 1: "Hot Leads - Product Launch"
  └── Select audience: "Hot Leads - FAC"
  └── Email: Aggressive offer (20% discount)

Campaign 2: "Warm Leads - Educational Nurture"
  └── Select audience: "Warm Leads - FAC"
  └── Email: Educational content + 10% discount

Campaign 3: "Hot OR Warm Leads - Special Promo"
  └── Select audience: "Hot OR Warm Leads - FAC"  ← Combined audience!
  └── Email: Limited-time offer (15% discount)
```

**✅ What You CAN Do with FAC:**

```
✅ WORKS:
In AEP Segment Builder:
- Create NEW audiences using federated data (no code changes)
- Combine multiple conditions (Hot OR Warm)
- Filter by any BigQuery column (product_interest, lead_score, etc.)
- Combine federated data with AEP behavioral data:

  Example: "Hot Leads WHO clicked email in last 7 days"
  SELECT customer_id
  FROM federated_bq_connection.leads
  WHERE lead_classification = 'Hot'
    AND customer_id IN (
      SELECT profile_id FROM aep_experience_events
      WHERE event_type = 'email.click'
        AND timestamp >= NOW() - INTERVAL 7 DAY
    );
```

---

## Can You Upload One File with All Leads via API?

### Your Question: "Can I just create a file with 'hot' cold and warm .. and upload it via api .. and AEP takes care of it?"

**Short Answer: ⚠️ YES, you CAN upload one file with a `lead_classification` column, BUT you CANNOT segment on that field in AEP.**

### What Happens If You Upload One File:

```csv
customer_id,email,first_name,last_name,lead_classification,product_interest
12345,john@example.com,John,Doe,Hot,Credit Card
67890,jane@example.com,Jane,Smith,Warm,Personal Loan
11111,bob@example.com,Bob,Johnson,Cold,Savings Account
```

**Step 1: Upload via External Audiences API**

```python
# Create ONE audience with ALL leads
all_leads_audience_id = create_external_audience(
    audience_name="All Leads - External",
    description="All leads with classification enrichment",
    enrichment_attributes=[
        {"name": "email", "type": "string"},
        {"name": "first_name", "type": "string"},
        {"name": "last_name", "type": "string"},
        {"name": "lead_classification", "type": "string"},  # ← Enrichment field
        {"name": "product_interest", "type": "string"}
    ]
)

upload_audience_data(all_leads_audience_id, "gs://bucket/all-leads.csv")
```

**Step 2: In AEP - You Have 1 Audience with 547,000 Profiles**

```
AEP Audiences:
└── All Leads - External (547,000 profiles)
    ├── Enrichment: lead_classification (values: Hot, Warm, Cold)
    └── Enrichment: product_interest
```

**Step 3: What You CAN Do**

✅ **Activate the ENTIRE audience to a destination**, and the destination receives the enrichment fields:

```json
// Email tool (e.g., Salesforce Marketing Cloud) receives:
{
  "customer_id": "12345",
  "email": "john@example.com",
  "first_name": "John",
  "last_name": "Doe",
  "lead_classification": "Hot",  // ← Enrichment sent to destination
  "product_interest": "Credit Card"
}
```

Now, **in your EMAIL TOOL** (not AEP), you can segment by `lead_classification`:

```
In Salesforce Marketing Cloud:
- Create email campaign "Hot Leads Only"
- Filter: WHERE lead_classification = 'Hot'
- This filtering happens IN THE EMAIL TOOL, not in AEP
```

**Step 4: What You CANNOT Do**

❌ **In AEP Segment Builder**, you CANNOT create:

```
❌ DOES NOT WORK in AEP:
- "All Leads - External WHERE lead_classification = 'Hot'"
- "All Leads - External WHERE product_interest = 'Credit Card'"

The "lead_classification" field is NOT available in AEP Segment Builder.
```

**Why This Limitation?**

External Audiences enrichment attributes are **metadata ONLY**:
- They are sent to destinations (email tool receives them)
- They are NOT indexed in AEP Profile Store
- They are NOT queryable in AEP Segment Builder

**Workaround**: Do the segmentation **BEFORE** uploading to AEP, OR use FAC instead.

---

## Side-by-Side Comparison: Email Campaign Workflow

### Scenario: Send 3 different email campaigns to Hot, Cold, and Warm leads

| Step | External Audiences API | FAC |
|------|------------------------|-----|
| **1. BigQuery Setup** | Create 3 separate SQL queries | Create 1 federated connection (one-time) |
| **2. Data Extraction** | Export 3 CSV files (hot-leads.csv, warm-leads.csv, cold-leads.csv) | No export - AEP queries in-place |
| **3. Upload to AEP** | Upload 3 separate audiences via API | Create 3 audiences in AEP UI (SQL queries) |
| **4. AEP State** | 3 independent, static audiences | 3 dynamic audiences (auto-refresh on schedule) |
| **5. Email Campaign** | Create 3 campaigns, select 3 audiences | Create 3 campaigns, select 3 audiences |
| **6. Change Criteria** | ⚠️ Re-run BigQuery queries, re-upload 3 CSV files, redeploy Cloud Run code | ✅ Edit SQL in AEP UI (no code changes) |
| **7. Add New Segment** | ⚠️ Write new BigQuery query, new CSV, new API upload | ✅ Create new audience in AEP UI (1 minute) |
| **8. Combine Segments** | ❌ Not possible in AEP | ✅ Create "Hot OR Warm" in AEP UI |
| **9. Data Freshness** | ⚠️ Manual refresh (Cloud Scheduler) | ✅ Auto-refresh (hourly/daily/weekly) |
| **10. Cost** | $112K-$292K/year | $247K-$701K/year |

---

## Recommended Approach for Your Use Case

### Use Case: Email campaigns for Hot/Cold/Warm leads

#### If Security Allows (BigQuery can be exposed to AEP):
**Recommendation: Use FAC**

**Why?**
- ✅ **No code changes needed** - Marketing team can create/edit audiences in AEP UI
- ✅ **Dynamic segmentation** - Easy to create "Hot OR Warm", "Hot + Credit Card Interest", etc.
- ✅ **Auto-refresh** - Schedule daily refresh, no manual CSV uploads
- ✅ **Production-ready** - Adobe-recommended for long-term use

**Setup**:
1. Create federated connection to BigQuery (1 week)
2. Marketing team creates audiences in AEP UI (self-service)
3. Schedule daily refresh (6 AM UTC)

#### If Security Blocks BigQuery Exposure:
**Recommendation: Use External Audiences API for POC, then lobby for FAC approval**

**Why?**
- ⚠️ External Audiences API requires **separate audiences** for Hot/Cold/Warm
- ⚠️ Any segmentation changes require **code changes + redeployment**
- ⚠️ Not recommended for production long-term

**Better Approach**:
1. **Phase 1 (Weeks 1-2)**: POC with External Audiences API
   - Create 3 audiences (Hot, Cold, Warm) via API
   - Test email campaigns
   - Prove ROI
2. **Phase 2 (Weeks 2-3)**: Lobby for FAC approval
   - Show security team the limitations of External Audiences API
   - Present FAC as more secure (no data transfer, query-only)
   - Get written approval
3. **Phase 3 (Weeks 3-6)**: Migrate to FAC
   - Set up federated connection
   - Migrate audiences from External Audiences API to FAC
   - Empower marketing team with self-service segmentation

---

## Code Example: External Audiences API with 3 Separate Audiences

```python
"""
External Audiences API: Create Hot, Cold, Warm audiences separately
"""

def create_lead_audiences():
    """
    Create 3 separate audiences for Hot, Cold, Warm leads
    """

    # Define 3 audience configurations
    audiences = [
        {
            "name": "Hot Leads - External",
            "description": "High-intent leads (score > 80)",
            "bq_query": """
                SELECT
                  customer_id, email, first_name, last_name,
                  lead_score, 'Hot' as lead_classification,
                  product_interest, engagement_index
                FROM `my-project.crm.leads`
                WHERE lead_classification = 'Hot' AND email IS NOT NULL
            """,
            "csv_path": "gs://bucket/hot-leads.csv"
        },
        {
            "name": "Warm Leads - External",
            "description": "Moderate-intent leads (score 50-80)",
            "bq_query": """
                SELECT
                  customer_id, email, first_name, last_name,
                  lead_score, 'Warm' as lead_classification,
                  product_interest, engagement_index
                FROM `my-project.crm.leads`
                WHERE lead_classification = 'Warm' AND email IS NOT NULL
            """,
            "csv_path": "gs://bucket/warm-leads.csv"
        },
        {
            "name": "Cold Leads - External",
            "description": "Low-intent leads (score < 50)",
            "bq_query": """
                SELECT
                  customer_id, email, first_name, last_name,
                  lead_score, 'Cold' as lead_classification,
                  product_interest, engagement_index
                FROM `my-project.crm.leads`
                WHERE lead_classification = 'Cold' AND email IS NOT NULL
            """,
            "csv_path": "gs://bucket/cold-leads.csv"
        }
    ]

    # Process each audience
    for aud in audiences:
        logger.info(f"Processing audience: {aud['name']}")

        # 1. Extract from BigQuery to GCS
        bq_client = bigquery.Client()
        extract_job = bq_client.query(f"""
            EXPORT DATA OPTIONS(
              uri='{aud['csv_path']}',
              format='CSV',
              overwrite=true,
              header=true
            ) AS
            {aud['bq_query']}
        """)
        extract_job.result()
        logger.info(f"Exported to: {aud['csv_path']}")

        # 2. Create audience in AEP
        audience_id = create_external_audience(
            audience_name=aud['name'],
            description=aud['description']
        )
        logger.info(f"Created audience: {audience_id}")

        # 3. Upload data
        run_id = upload_audience_data(audience_id, aud['csv_path'])
        logger.info(f"Upload started: {run_id}")

        # 4. Wait for completion
        result = wait_for_ingestion(audience_id, run_id)
        logger.info(f"Ingested {result['profilesIngested']} profiles")

    logger.info("✅ All 3 audiences created successfully!")

if __name__ == "__main__":
    create_lead_audiences()
```

**Output**:
```
Processing audience: Hot Leads - External
Exported to: gs://bucket/hot-leads.csv
Created audience: aud_12345
Upload started: run_67890
Ingested 42,000 profiles

Processing audience: Warm Leads - External
Exported to: gs://bucket/warm-leads.csv
Created audience: aud_12346
Upload started: run_67891
Ingested 125,000 profiles

Processing audience: Cold Leads - External
Exported to: gs://bucket/cold-leads.csv
Created audience: aud_12347
Upload started: run_67892
Ingested 380,000 profiles

✅ All 3 audiences created successfully!
```

---

## Code Example: FAC with Dynamic Segmentation

```sql
-- In AEP UI, create federated connection (one-time):
-- Connection Name: "BigQuery CRM Connection"
-- BigQuery Table: my-project.crm.leads

-- Then, in AEP Segment Builder, create audiences (no code!):

-- Audience 1: Hot Leads
SELECT customer_id
FROM federated_bq_connection.leads
WHERE lead_classification = 'Hot' AND email IS NOT NULL;

-- Audience 2: Warm Leads
SELECT customer_id
FROM federated_bq_connection.leads
WHERE lead_classification = 'Warm' AND email IS NOT NULL;

-- Audience 3: Cold Leads
SELECT customer_id
FROM federated_bq_connection.leads
WHERE lead_classification = 'Cold' AND email IS NOT NULL;

-- ✅ BONUS: Create combined audiences (not possible with External Audiences API)

-- Audience 4: Hot OR Warm Leads (Combined)
SELECT customer_id
FROM federated_bq_connection.leads
WHERE lead_classification IN ('Hot', 'Warm') AND email IS NOT NULL;

-- Audience 5: Hot Leads - Credit Card Interest (Filtered)
SELECT customer_id
FROM federated_bq_connection.leads
WHERE lead_classification = 'Hot'
  AND product_interest = 'Credit Card'
  AND email IS NOT NULL;

-- Audience 6: High-Value Hot Leads (Complex Logic)
SELECT customer_id
FROM federated_bq_connection.leads
WHERE lead_classification = 'Hot'
  AND lead_score > 90
  AND total_lifetime_value > 10000
  AND engagement_index > 0.8
  AND email IS NOT NULL;
```

**No Python code needed!** Marketing team can create/edit audiences in AEP UI.

---

## Summary: Key Takeaways

### For Hot/Cold/Warm Leads Email Campaign:

| Question | External Audiences API | FAC |
|----------|------------------------|-----|
| **Do I need separate audiences?** | ✅ **YES** - Create 3 audiences | ❌ **NO** - Create 1 connection, segment in AEP |
| **Can I upload one file with all leads?** | ⚠️ Yes, but CANNOT segment on `lead_classification` in AEP | ✅ Yes, segment dynamically in AEP |
| **Where does segmentation happen?** | ⚠️ In BigQuery (before upload) OR in email tool (after activation) | ✅ In AEP Segment Builder (self-service) |
| **Flexibility for new segments** | ⚠️ Low - requires code changes | ✅ High - self-service in AEP UI |
| **Best for** | POC, testing, blocked security | Production, dynamic segmentation |

### Decision Tree:

```
Start: "I want to send emails to Hot, Cold, and Warm leads"
│
├─ Can BigQuery be exposed to AEP?
│  ├─ YES → Use FAC
│  │        ✅ Create 1 federated connection
│  │        ✅ Marketing team creates audiences in AEP UI (self-service)
│  │        ✅ Easy to add new segments (no code changes)
│  │
│  └─ NO → Use External Audiences API
│           ⚠️ Create 3 separate audiences (Hot, Cold, Warm)
│           ⚠️ Requires code changes for new segments
│           ⚠️ Use for POC only, then lobby for FAC approval
```

---

## Next Steps

1. **If you have FAC access**: Create federated connection, start creating audiences in AEP UI
2. **If security blocks FAC**: Use External Audiences API for POC, prove value, then lobby for FAC
3. **Need help deciding?** See [fac-vs-external-audiences-comparison.md](fac-vs-external-audiences-comparison.md) for detailed decision matrix

---

**Questions?** Please reach out via project issue tracker.
