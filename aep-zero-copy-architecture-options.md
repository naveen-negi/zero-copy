# AEP Zero-Copy Architecture: Analysis & Recommendations

## Executive Summary

**MAJOR UPDATE (2025)**: Adobe has released **Federated Audience Composition**, which fundamentally changes the zero-copy story for AEP. TRUE zero-copy is NOW POSSIBLE for audience creation use cases.

**Bottom Line Up Front**: For your Cold/Warm/Hot lead classification use case, **Federated Audience Composition** (Section 2.6) should be your PRIMARY approach. This enables you to:
- Keep all lead scoring logic and data in BigQuery (zero vendor lock-in)
- Query BigQuery directly from AEP WITHOUT copying profile data (99.96% data transfer reduction)
- Activate audiences to Marketo, Google Ads, etc. at 50% lower cost than traditional ingestion
- Maintain complete data sovereignty (data never leaves GCP)

**What Changed**: Previously, AEP required full data ingestion for segmentation and activation. Federated Audience Composition now allows AEP to query external data warehouses (BigQuery, Snowflake, Databricks, etc.) in-place, transferring ONLY audience membership (customer IDs) to AEP, not full profile data.

**Key Findings**:

1. **Federated Audience Composition (Pattern 6)** is the RECOMMENDED approach for your use case:
   - Supports Google BigQuery natively
   - Queries data in-place (no data copying)
   - 99.96% data transfer reduction vs full ingestion
   - 50% cost reduction ($41K-$83K/year vs $82K-$145K/year)
   - Lower operational complexity (SQL + UI config, no custom pipelines)
   - Data sovereignty (data stays in BigQuery, only IDs transferred)

2. **Use Pattern 1 (Computed Attributes)** ONLY for edge cases:
   - Real-time triggers (<1 minute latency requirement)
   - Need for AEP AI features (Customer AI, Attribution AI)
   - Cross-device identity stitching via AEP Identity Graph
   - Web personalization requiring <100ms profile lookups

3. **Hybrid Approach** often delivers best results:
   - Federated Audiences for 99% of use cases (batch campaigns, daily/weekly activation)
   - Pattern 1 (Streaming Ingestion) for 1% of use cases (real-time sales alerts)

**Important Limitations of Federated Audience Composition**:
- Batch-only (minimum refresh: hourly, typical: daily)
- No real-time streaming segmentation
- No sub-100ms profile lookups (not suitable for web personalization)
- No AEP Identity Graph integration (must pre-compute identity resolution in BigQuery)
- No Customer AI or Attribution AI support (use BigQuery ML instead)

See Section 2.5 for historical context on why AEP historically didn't support federated queries, and Section 2.6 for comprehensive analysis of the NEW Federated Audience Composition capability.

---

## 1. Understanding AEP's Architectural Constraints

### 1.1 Why True Zero-Copy Fails with AEP

AEP's core value proposition creates fundamental barriers to zero-copy architecture:

1. **Real-Time Customer Profile Storage Requirement**
   - AEP must store profile data in its proprietary Profile Store to enable sub-second lookup
   - Identity graph construction requires data residency within AEP
   - Merge policies operate on stored data, not external references

2. **Segmentation Engine Dependencies**
   - Streaming segmentation evaluates against in-platform profile attributes
   - Batch segmentation queries the Profile Store directly via Query Service
   - Edge segmentation requires profile projection to Edge nodes

3. **No External Data Federation**
   - AEP cannot query external data sources (like BigQuery) during segment evaluation
   - No support for "virtual profiles" that reference external systems
   - Query Service only accesses AEP's Data Lake, not external databases

**Technical Reality**: AEP is designed as a centralized customer data platform, not a federated query engine like Google BigQuery or Snowflake.

### 1.2 What "Minimized Data Transfer" Actually Means

Given AEP's constraints, we redefine the goal:

- **Not Zero-Copy**: Eliminating all data transfer to AEP
- **But Data Minimization**: Transferring only essential attributes required for segmentation and activation
- **Target Reduction**: 60-85% less data vs. naive full-profile replication

---

## 2. Data Minimization Patterns for AEP

### 2.1 Pattern 1: Computed Attributes from GCP (RECOMMENDED for Lead Scoring)

**Concept**: Perform heavy computation in GCP, send only derived scores/classifications to AEP.

#### Architecture
```
GCP BigQuery (Source of Truth)
    |
    | 1. Run ML models, aggregations, complex joins
    V
Computed Attributes:
  - lead_classification: "cold" | "warm" | "hot"
  - propensity_score: 0.0 - 1.0
  - engagement_index: integer
  - last_interaction_date: timestamp
  - primary_product_interest: enum
    |
    | 2. Stream ONLY derived attributes via HTTP API
    V
AEP Real-Time Customer Profile
  - Minimal schema (5-10 fields vs 100+ raw fields)
  - Profiles updated via Streaming Ingestion API
    |
    | 3. Segment on computed attributes
    V
Segment: "Hot Leads" WHERE lead_classification = "hot"
    |
    | 4. Activate to destinations
    V
Marketo, Google Ads, Email ESP
```

#### Implementation Details

**XDM Schema Design** (Minimal Profile):
```json
{
  "title": "Minimal Lead Profile",
  "type": "object",
  "properties": {
    "_id": {
      "type": "string",
      "description": "Primary identifier"
    },
    "identityMap": {
      "email": [{"id": "user@example.com"}],
      "gcpCustomerId": [{"id": "gcp-12345"}]
    },
    "leadClassification": {
      "type": "string",
      "enum": ["cold", "warm", "hot"],
      "meta:usereditable": false
    },
    "propensityScore": {
      "type": "number",
      "minimum": 0,
      "maximum": 1
    },
    "engagementIndex": {
      "type": "integer",
      "description": "Pre-computed from GCP"
    },
    "lastInteractionTimestamp": {
      "type": "string",
      "format": "date-time"
    },
    "primaryProductInterest": {
      "type": "string",
      "enum": ["product_a", "product_b", "product_c", "product_d"]
    },
    "accountManagerId": {
      "type": "string"
    }
  }
}
```

**Data Transfer Comparison**:
- **Full Profile Replication**: 50-200 KB per profile (behavioral events, activity history, demographic data)
- **Computed Attributes Only**: 1-3 KB per profile (5-10 fields)
- **Reduction**: 95-98% less data per profile

**GCP to AEP Streaming Ingestion** (Python Example):
```python
import requests
import json
from google.cloud import bigquery

# Configuration
AEP_STREAMING_ENDPOINT = "https://dcs.adobedc.net/collection/{DATASET_ID}"
AEP_IMS_ORG = "{IMS_ORG_ID}"

def compute_lead_classification(customer_data):
    """
    Heavy computation happens in GCP, not AEP.
    This could be a BigQuery ML model prediction.
    """
    # Example: BigQuery ML prediction
    bq_client = bigquery.Client()
    query = f"""
    SELECT
      customer_id,
      CASE
        WHEN predicted_propensity < 0.3 THEN 'cold'
        WHEN predicted_propensity < 0.7 THEN 'warm'
        ELSE 'hot'
      END as classification,
      predicted_propensity,
      engagement_score
    FROM ML.PREDICT(MODEL `project.dataset.lead_scoring_model`,
      (SELECT * FROM `project.dataset.customer_features`
       WHERE customer_id = @customer_id))
    """
    job_config = bigquery.QueryJobConfig(
        query_parameters=[
            bigquery.ScalarQueryParameter("customer_id", "STRING", customer_data['id'])
        ]
    )
    result = bq_client.query(query, job_config=job_config).result()
    return list(result)[0]

def stream_to_aep(customer_id, email, computed_attrs):
    """
    Stream only computed attributes to AEP.
    """
    payload = {
        "header": {
            "schemaRef": {
                "id": "https://ns.adobe.com/{TENANT}/schemas/{SCHEMA_ID}",
                "contentType": "application/vnd.adobe.xed-full+json;version=1"
            },
            "imsOrgId": AEP_IMS_ORG,
            "datasetId": "{DATASET_ID}",
            "source": {
                "name": "GCP Lead Scoring Pipeline"
            }
        },
        "body": {
            "xdmMeta": {
                "schemaRef": {
                    "id": "https://ns.adobe.com/{TENANT}/schemas/{SCHEMA_ID}",
                    "contentType": "application/vnd.adobe.xed-full+json;version=1"
                }
            },
            "xdmEntity": {
                "_id": customer_id,
                "identityMap": {
                    "email": [{"id": email}],
                    "gcpCustomerId": [{"id": customer_id}]
                },
                "leadClassification": computed_attrs['classification'],
                "propensityScore": computed_attrs['predicted_propensity'],
                "engagementIndex": computed_attrs['engagement_score'],
                "lastInteractionTimestamp": computed_attrs['timestamp']
            }
        }
    }

    response = requests.post(
        AEP_STREAMING_ENDPOINT,
        headers={"Content-Type": "application/json"},
        data=json.dumps(payload)
    )
    return response

# Usage in Cloud Function or Dataflow pipeline
def process_customer(customer_id, email):
    # 1. Compute in GCP (heavy lifting)
    customer_data = {'id': customer_id, 'email': email}
    computed = compute_lead_classification(customer_data)

    # 2. Stream only results to AEP (minimal data)
    stream_to_aep(customer_id, email, computed)
```

**When to Update AEP**:
- **Real-time triggers**: When lead classification changes (cold -> warm -> hot)
- **Batch refresh**: Daily updates for engagement_index and propensity_score
- **Event-driven**: After significant interactions (webinar attendance, product inquiry)

**Pros**:
- **Minimal data transfer**: Only derived attributes, not raw events
- **Computation scalability**: Leverage GCP's compute (BigQuery, Dataflow, Vertex AI)
- **Flexibility**: Change scoring logic in GCP without AEP schema changes
- **Cost efficiency**: Avoid AEP Query Service costs for complex computations
- **Reduced vendor lock-in**: Business logic stays in GCP, not AEP

**Cons**:
- **Latency**: Scores computed in GCP, then streamed to AEP (adds 5-30 seconds)
- **Dual system complexity**: Maintain scoring pipelines in GCP and profiles in AEP
- **Limited AEP AI**: Can't use Customer AI (requires raw behavioral data in AEP)
- **Segment expressiveness**: Can only segment on computed attributes, not raw events

**Cost Implications**:
- **AEP Licensing**: Profile count-based. Minimal schema doesn't reduce profile count, but reduces storage costs.
- **AEP API**: Streaming Ingestion charged per API call. Batch updates (daily) cheaper than real-time.
- **GCP Compute**: BigQuery ML, Dataflow costs for scoring pipelines.

**Best Fit**:
- **Your use case**: Cold/Warm/Hot lead classification with complex scoring logic
- Organizations with existing ML/data science capabilities in GCP/Databricks/Snowflake
- Use cases where scoring logic changes frequently
- Scenarios requiring explainability (scoring logic in SQL, not AEP black box)

---

### 2.2 Pattern 2: Reference Architecture with External Profile Store

**Concept**: Store full profiles in GCP, send only identifiers + minimal attributes to AEP for activation.

#### Architecture
```
GCP BigQuery (Master Profile Store)
  - Full customer profiles (100+ attributes)
  - Activity history
  - Behavioral events
    |
    | NO bulk data transfer
    V
AEP Real-Time Customer Profile
  - Profile stub: ID + 3-5 key attributes for segmentation
  - Example: email, lead_status, product_interest
    |
    | Segment in AEP (limited criteria)
    V
Segment Qualified: customer_id list
    |
    | 1. Export segment membership via Destinations API
    V
GCP Cloud Function
    |
    | 2. Enrich with full profile from BigQuery
    V
Destination (Marketo, Google Ads)
  - Activated with full profile data
```

#### Implementation Details

**AEP Profile Stub Schema**:
```json
{
  "title": "Profile Reference Stub",
  "properties": {
    "_id": {"type": "string"},
    "identityMap": {
      "email": [{"id": "user@example.com"}],
      "gcpProfileId": [{"id": "bq-profile-12345"}]
    },
    "segmentationFlags": {
      "isHighValue": {"type": "boolean"},
      "productInterest": {"type": "string"}
    }
  }
}
```

**Enrichment Function** (GCP Cloud Function):
```python
from google.cloud import bigquery
import requests

def aep_segment_webhook(request):
    """
    Webhook triggered by AEP when segment membership changes.
    Enriches profile IDs with full data from BigQuery.
    """
    segment_payload = request.get_json()
    profile_ids = segment_payload.get('profiles', [])

    # Fetch full profiles from BigQuery
    bq_client = bigquery.Client()
    query = f"""
    SELECT *
    FROM `project.dataset.customer_profiles`
    WHERE customer_id IN UNNEST(@profile_ids)
    """
    job_config = bigquery.QueryJobConfig(
        query_parameters=[
            bigquery.ArrayQueryParameter("profile_ids", "STRING", profile_ids)
        ]
    )
    results = bq_client.query(query, job_config=job_config).result()

    # Activate enriched profiles to destination
    for row in results:
        activate_to_marketo(row)

    return {'status': 'success', 'processed': len(profile_ids)}

def activate_to_marketo(profile_data):
    # Send full profile to Marketo API
    marketo_payload = {
        'email': profile_data['email'],
        'firstName': profile_data['first_name'],
        'lastName': profile_data['last_name'],
        'customField1': profile_data['custom_field_1'],
        # ... all other fields from BigQuery
    }
    requests.post('https://marketo.com/rest/v1/leads.json', json=marketo_payload)
```

**Data Transfer**:
- **AEP Ingestion**: ~500 bytes per profile (ID + 2-3 flags)
- **Segment Export**: Only profile IDs (50-100 bytes per profile)
- **Enrichment**: Full profiles fetched from GCP only for qualified segment members

**Pros**:
- **Minimal AEP storage**: Only profile stubs, not full profiles
- **Data sovereignty**: Full profiles stay in GCP (GDPR, CCPA compliance easier)
- **Flexible enrichment**: Add new attributes without AEP schema changes
- **Cost optimization**: Avoid AEP storage costs for large attribute sets

**Cons**:
- **Segmentation limitations**: Can only segment on stub attributes in AEP
- **Latency**: Enrichment adds delay (5-30 seconds)
- **Complex architecture**: Requires external orchestration (Cloud Functions, webhooks)
- **AEP value dilution**: Not using AEP's profile management capabilities
- **Activation limitations**: Can't use AEP's native destination connectors with full profile data

**Cost Implications**:
- **Reduced AEP storage**: Lower data lake storage costs
- **Increased GCP costs**: BigQuery queries for enrichment
- **Operational overhead**: Maintain enrichment pipelines

**Honest Assessment**: This pattern undermines AEP's core value. If you're only using AEP for segment membership lists, consider:
- **Alternative 1**: Use GCP-native tools (BigQuery + Cloud Composer) for segmentation
- **Alternative 2**: Use a lighter CDP (Segment, mParticle) that's designed for data routing, not storage
- **Alternative 3**: Direct integrations from GCP to destinations (Google Ads, Marketo APIs)

**When This Makes Sense**:
- You're contractually obligated to use AEP but want to minimize vendor lock-in
- You need AEP's specific destination connectors but can't store full profiles in AEP (data residency requirements)
- You're evaluating AEP and want to pilot with minimal data commitment

---

### 2.3 Pattern 3: Event-Driven Architecture with Minimal Profile State

**Concept**: Stream events to AEP for real-time segmentation, but keep profile state minimal.

#### Architecture
```
GCP Pub/Sub (Event Stream)
  - Page views, clicks, activities (ephemeral)
    |
    | Stream events via AEP Streaming API
    V
AEP Experience Events (Time-Series Data)
  - Stored for 30-90 days (configurable)
  - NOT merged into profile (unless explicitly configured)
    |
    | Real-time segmentation on recent events
    V
Segment: "Viewed product page in last 24 hours"
    |
    V
Activation to Google Ads for retargeting
```

**Key Principle**: Use AEP as a **stateless event processor**, not a profile store.

#### Implementation

**Event Schema** (XDM ExperienceEvent):
```json
{
  "title": "Minimal Experience Event",
  "allOf": [
    {"$ref": "https://ns.adobe.com/xdm/context/experienceevent"}
  ],
  "properties": {
    "_id": {"type": "string"},
    "timestamp": {"type": "string", "format": "date-time"},
    "eventType": {"type": "string"},
    "identityMap": {
      "email": [{"id": "user@example.com"}]
    },
    "web": {
      "webPageDetails": {
        "URL": {"type": "string"},
        "name": {"type": "string"}
      }
    },
    "productListItems": [
      {
        "SKU": {"type": "string"},
        "name": {"type": "string"}
      }
    ]
  }
}
```

**Streaming Events from GCP**:
```python
import json
import requests
from google.cloud import pubsub_v1

def pubsub_to_aep(event, context):
    """
    Cloud Function triggered by Pub/Sub.
    Streams event to AEP without creating persistent profile.
    """
    pubsub_message = json.loads(base64.b64decode(event['data']).decode('utf-8'))

    aep_payload = {
        "header": {
            "schemaRef": {
                "id": "https://ns.adobe.com/{TENANT}/schemas/{EVENT_SCHEMA_ID}",
                "contentType": "application/vnd.adobe.xed-full+json;version=1"
            },
            "imsOrgId": "{IMS_ORG_ID}",
            "datasetId": "{EVENT_DATASET_ID}"
        },
        "body": {
            "xdmMeta": {
                "schemaRef": {
                    "id": "https://ns.adobe.com/{TENANT}/schemas/{EVENT_SCHEMA_ID}",
                    "contentType": "application/vnd.adobe.xed-full+json;version=1"
                }
            },
            "xdmEntity": {
                "_id": pubsub_message['event_id'],
                "timestamp": pubsub_message['timestamp'],
                "eventType": pubsub_message['event_type'],
                "identityMap": {
                    "email": [{"id": pubsub_message['email']}]
                },
                "web": {
                    "webPageDetails": {
                        "URL": pubsub_message['page_url']
                    }
                }
            }
        }
    }

    response = requests.post(
        f"https://dcs.adobedc.net/collection/{DATASET_ID}",
        headers={"Content-Type": "application/json"},
        data=json.dumps(aep_payload)
    )
    return response.status_code
```

**Profile Configuration** (Disable Profile for Events):
- In AEP UI, disable "Profile" toggle for the ExperienceEvent dataset
- Events stored in Data Lake, NOT merged into Real-Time Customer Profile
- Use Query Service for historical analysis, not Profile Store

**Segmentation Approach**:
- **Streaming segments on events**: "Viewed product X in last 24 hours"
- **No persistent profile attributes**: Segment membership based on recent events only
- **TTL-based**: Segments automatically expire (e.g., 24-hour window)

**Pros**:
- **True ephemeral data**: Events auto-delete after retention period (30-90 days)
- **Minimal storage**: No profile accumulation
- **Real-time segmentation**: Leverage AEP's streaming segment engine
- **GDPR-friendly**: Data naturally expires

**Cons**:
- **Limited segmentation**: Can't segment on "lifetime value" or historical patterns
- **No identity stitching**: Can't resolve cross-device identities without profile
- **Loses AEP's core value**: Not using Real-Time Customer Profile
- **Query Service costs**: If you need historical analysis, Query Service charges apply

**When This Makes Sense**:
- **Retargeting use cases**: "Viewed product but didn't purchase in last 24 hours"
- **Real-time triggers**: Abandoned cart recovery, browse abandonment
- **Privacy-first**: Minimize data retention
- **Pilot projects**: Test AEP's streaming capabilities without full commitment

**Honest Assessment**: If you're only using events without profiles, AEP is overkill. Consider:
- **Google Analytics 4 + BigQuery**: Native GCP integration, similar event streaming
- **Segment**: Better suited for event routing without profile storage
- **GCP Pub/Sub + Dataflow**: Build custom real-time segmentation logic

---

### 2.4 Pattern 4: Hybrid Batch + Streaming with Selective Profile Updates

**Concept**: Stream high-priority events in real-time, batch-update computed attributes daily.

#### Architecture
```
GCP Ecosystem:
  |
  +-- Real-time Events (Pub/Sub) ---> AEP Streaming API
  |     - Cart abandonment             (Latency: <5 seconds)
  |     - Product inquiries
  |
  +-- Batch Computation (Dataflow) --> AEP Batch Ingestion API
        - Daily lead score refresh     (Latency: daily)
        - Monthly lifetime value
        - Weekly engagement index
```

**XDM Schema** (Hybrid Profile):
```json
{
  "title": "Hybrid Lead Profile",
  "properties": {
    "_id": {"type": "string"},
    "identityMap": {...},

    "realtimeAttributes": {
      "lastPageView": {"type": "string", "format": "date-time"},
      "currentSessionProductInterest": {"type": "string"}
    },

    "batchComputedAttributes": {
      "leadClassification": {"type": "string", "enum": ["cold", "warm", "hot"]},
      "propensityScore": {"type": "number"},
      "lifetimeValue": {"type": "number"},
      "engagementIndex": {"type": "integer"}
    }
  }
}
```

**Implementation**:

**Real-time Events** (Python Cloud Function):
```python
def stream_critical_event(event_data):
    """
    Stream only business-critical events that require immediate action.
    """
    critical_events = ['cart_abandoned', 'product_inquiry', 'callback_requested']

    if event_data['event_type'] in critical_events:
        # Stream to AEP for real-time segmentation
        stream_to_aep_api(event_data)
    else:
        # Log to BigQuery for batch processing
        log_to_bigquery(event_data)
```

**Batch Updates** (Daily via Dataflow):
```python
import apache_beam as beam
from apache_beam.options.pipeline_options import PipelineOptions

def batch_update_aep_profiles():
    """
    Daily batch job to update computed lead scores.
    """
    pipeline_options = PipelineOptions(
        runner='DataflowRunner',
        project='your-gcp-project',
        region='us-central1'
    )

    with beam.Pipeline(options=pipeline_options) as pipeline:
        (pipeline
         | 'Read from BigQuery' >> beam.io.ReadFromBigQuery(
             query='''
                 SELECT
                   customer_id,
                   email,
                   computed_lead_classification,
                   propensity_score,
                   engagement_index
                 FROM `project.dataset.daily_lead_scores`
                 WHERE score_date = CURRENT_DATE()
             ''',
             use_standard_sql=True)
         | 'Transform to AEP format' >> beam.Map(transform_to_aep_batch_format)
         | 'Write to AEP Batch API' >> beam.ParDo(AEPBatchWriter())
        )

class AEPBatchWriter(beam.DoFn):
    def process(self, element):
        # AEP Batch Ingestion API
        # Upload to GCS -> Register batch with AEP -> AEP ingests from GCS
        # See: https://experienceleague.adobe.com/docs/experience-platform/ingestion/batch/api-overview.html
        pass
```

**Update Frequency Decision Matrix**:

| Attribute | Update Frequency | Method | Justification |
|-----------|------------------|--------|---------------|
| Lead Classification | Daily | Batch | Score stability, cost optimization |
| Cart Abandonment | Real-time | Streaming | Immediate action required (recovery email) |
| Propensity Score | Daily | Batch | ML model re-run nightly |
| Product Interest | Real-time | Streaming | Informs current session personalization |
| Lifetime Value | Weekly | Batch | Changes slowly, expensive to compute |
| Email Engagement | Batch (daily) | Batch | ESP webhook batching |

**Pros**:
- **Cost-optimized**: Batch for low-priority, streaming for high-priority
- **Latency balanced**: Real-time where needed, batch where acceptable
- **Reduced API calls**: Batch ingestion 100x cheaper than per-event streaming
- **Selective updates**: Only changed profiles in batch uploads

**Cons**:
- **Complexity**: Maintain both streaming and batch pipelines
- **Consistency challenges**: Real-time and batch attributes may conflict
- **Operational overhead**: Monitor two ingestion paths

**Cost Implications**:
- **AEP Batch Ingestion**: Flat rate per batch file (not per record)
- **AEP Streaming Ingestion**: Per API call (expensive at scale)
- **Rule of Thumb**: Batch is 100-1000x cheaper than streaming for bulk updates

---

### 2.5 Pattern 5: Federated Queries - Historical Context (OBSOLETE as of 2025)

**MAJOR UPDATE (2025)**: This entire section is now PARTIALLY OBSOLETE. Adobe has released **Federated Audience Composition** (Section 2.6), which DOES support federated queries for audience creation use cases. I'm keeping this section for historical context and to explain what limitations still exist.

**User Question**: Why didn't you consider federated queries where AEP directly connects to data warehouses (BigQuery, Snowflake) as a zero-copy option?

#### 2.5.1 The Short Answer: AEP NOW SUPPORTS Limited Federated Queries (as of 2025)

**UPDATE**: My original statement "AEP does NOT support federated queries" is now INCORRECT. As of 2025:

**What NOW WORKS**:
- **Federated Audience Composition** (NEW): AEP CAN query external warehouses for audience creation
- Supported warehouses: BigQuery, Snowflake, Databricks, Redshift, Azure Synapse, Oracle, Microsoft Fabric, Vertica
- Data stays in warehouse, only audience membership transferred to AEP
- See Section 2.6 for complete analysis

**What STILL DOESN'T WORK**:
- Real-Time Customer Profile: Still requires data in AEP for <100ms lookups
- Streaming Segmentation: Still requires data in AEP for <1 second evaluation
- Identity Graph: Still requires data in AEP Profile Store
- Customer AI / Attribution AI: Still requires data in AEP Data Lake
- Edge Segmentation: Still requires data in AEP

**Critical Limitation (UPDATED)**: Adobe Experience Platform NOW supports federated queries for **audience creation**, but NOT for real-time profile operations. This section explains the historical architectural constraints and what limitations still exist.

**What This Means (UPDATED for 2025)**:
- **NEW**: AEP CAN query BigQuery for audience creation via Federated Audience Composition
- **STILL TRUE**: AEP cannot create "virtual profiles" for real-time lookups
- **STILL TRUE**: AEP Query Service only queries the AEP Data Lake, not external data sources
- **UPDATED**: Data used for BATCH segmentation can stay in BigQuery (via Federated Audiences)
- **STILL TRUE**: Data used for REAL-TIME features must still be ingested into AEP

**Contrast with True Federated Query Systems**:

| Platform | Federated Query Support | Example |
|----------|------------------------|---------|
| **Snowflake** | Yes (External Tables) | Query S3/GCS data without copying via Snowflake External Tables |
| **Google BigQuery** | Yes (External Tables, BigLake) | Query GCS, Drive, Cloud Storage without ingestion via external tables |
| **Databricks** | Yes (Delta Sharing) | Query remote Delta Lake tables without data movement |
| **Trino/Presto** | Yes (Connectors) | Query MySQL, PostgreSQL, S3 simultaneously in one query |
| **Adobe AEP** | **NO** | Must ingest all data before querying |

#### 2.5.2 Technical Reasons Why AEP Cannot Support Federated Queries

**Architectural Constraint 1: Real-Time Customer Profile Store**

AEP's Real-Time Customer Profile is designed for sub-second lookup performance:

```
User Request: "Show me this customer's profile"
AEP Response Time: <100ms (profile lookup)

How it achieves this:
- Proprietary in-memory profile store (not standard SQL database)
- Pre-computed profile fragments stored on SSD
- Distributed hash-based lookup (not table scans)
```

**Why Federated Queries Would Break This**:
- BigQuery query latency: 1-30 seconds (even for indexed queries)
- External database queries require network round-trips (50-200ms minimum)
- Profile lookups would degrade from <100ms to 1-30 seconds
- AEP's personalization use case (real-time web/app personalization) requires <100ms

**Architectural Constraint 2: Segmentation Engine Design**

AEP's segmentation operates on pre-processed, indexed profile data:

```
Streaming Segmentation:
- Evaluates profile attributes against segment rules in <1 second
- Uses in-memory indexes for fast attribute lookup
- Cannot wait for external database queries (would violate latency SLA)

Batch Segmentation:
- Scans millions of profiles against complex segment rules
- Uses distributed processing across AEP cluster nodes
- Pre-computes attribute indexes (bloom filters, bitmaps)
- External queries would require scanning remote databases (prohibitively slow)
```

**Performance Math**:
```
Scenario: Evaluate segment "Hot Leads" (leadClassification = 'hot') for 10M profiles

AEP (Current Architecture):
- Data Location: AEP Profile Store (local SSD)
- Index: Pre-built bitmap index on leadClassification
- Evaluation Time: 5-30 minutes (batch job)
- Method: Parallel scan across AEP cluster nodes

Hypothetical Federated Query (if AEP supported it):
- Data Location: BigQuery (external, network latency)
- Query: SELECT customer_id FROM profiles WHERE leadClassification = 'hot'
- Network latency: 50-200ms per query batch
- BigQuery execution: 10-60 seconds
- Total Time: 10-60 seconds (seems faster!)

BUT: This breaks for complex segments:
- Segment: "Hot leads who viewed product X in last 7 days AND have LTV > $10K"
- Requires joining Profile data + ExperienceEvent data (time-series)
- AEP's time-series indexes: optimized for this query pattern
- Federated query: Would require joining BigQuery tables + AEP events (slow)
```

**Architectural Constraint 3: Identity Graph**

AEP's identity resolution requires all identity data to be stored within AEP:

```
Identity Graph Construction:
1. Ingest profile with identityMap: {email: "user@example.com", cookie: "abc123"}
2. Link identities in proprietary graph database (not SQL)
3. Merge profiles based on shared identities (instant lookup via graph traversal)

Why Federated Queries Don't Work:
- Identity graphs use specialized graph databases (not relational)
- Graph traversal algorithms (BFS, DFS) require low-latency local access
- Remote queries to BigQuery cannot provide <100ms identity lookups
- Merging profiles across external databases = prohibitively expensive joins
```

**Architectural Constraint 4: Data Model Differences**

AEP uses XDM (Experience Data Model), not standard SQL schemas:

```
XDM Profile Structure (hierarchical, nested):
{
  "identityMap": {...},
  "person": {
    "name": {...}
  },
  "_{TENANT}": {
    "customFields": {...}
  }
}

BigQuery Schema (flat or nested, but not XDM-compliant):
CREATE TABLE profiles (
  customer_id STRING,
  email STRING,
  first_name STRING,
  -- No native XDM structure
)
```

**Impedance Mismatch**:
- AEP segments written in PQL (Profile Query Language) expect XDM structure
- BigQuery uses SQL with different schema
- Translating PQL to SQL on arbitrary BigQuery schemas = unsolvable problem (would require custom mapping for every customer)
- Even if Adobe built SQL translation, customer BigQuery schemas don't match XDM (different field names, nesting, data types)

#### 2.5.3 What AEP Query Service Actually Does

**AEP Query Service** is often confused with federated queries, but it's NOT:

**What Query Service IS**:
```
AEP Query Service = SQL interface to AEP's Data Lake (already ingested data)

Architecture:
  AEP Data Lake (Azure Data Lake Storage)
    - Stores ingested datasets (Profile, ExperienceEvent)
    - Parquet files organized by dataset
    |
    V
  Query Service (PostgreSQL-compatible SQL engine)
    - Queries Parquet files in Data Lake
    - Used for analytics, data exploration, segment export
    - Timeout: 10 minutes per query

Use Cases:
- Ad-hoc data analysis (explore profiles, events)
- Export segment membership to GCS/S3 (for downstream processing)
- Create computed attributes (batch aggregations)
```

**What Query Service is NOT**:
- NOT a federated query engine (cannot query BigQuery, Snowflake directly)
- NOT used for real-time segmentation (too slow, 10-minute timeout)
- NOT a replacement for ETL (still need to ingest data into AEP first)

**Comparison**:

| Feature | AEP Query Service | BigQuery Federated Queries |
|---------|-------------------|----------------------------|
| Query External Data | No (only AEP Data Lake) | Yes (GCS, Drive, Cloud SQL) |
| Latency | 5-600 seconds | 1-30 seconds |
| Use Case | Analytics on ingested data | Query data in-place without ingestion |
| Cost | $$$ (premium add-on) | $ (included in BigQuery) |

#### 2.5.4 Adobe's Business Reasons for Not Supporting Federated Queries

Beyond technical constraints, there are business reasons Adobe doesn't support federated queries:

**1. Data Gravity = Platform Lock-in**

```
Adobe's Business Model:
- Get customers to ingest data into AEP
- Data residency creates switching costs (hard to migrate away)
- Federated queries would reduce lock-in (data stays in customer's warehouse)

Example:
- Customer A: Stores 100TB of data in AEP Data Lake
  - Switching cost: High (must migrate 100TB + rebuild pipelines)
  - Adobe retention: High

- Customer B (hypothetical federated model): Stores 100TB in BigQuery, AEP queries it
  - Switching cost: Low (just change which CDP queries BigQuery)
  - Adobe retention: Low (easy to switch to competitor)
```

**2. Revenue from Data Storage**

AEP charges for:
- Profile storage (per addressable profile)
- Data Lake storage (per GB ingested)
- Query Service compute (per query hour)

If AEP supported federated queries:
- Less data ingested into AEP Data Lake = lower storage revenue
- Customers use BigQuery for analytics = less Query Service revenue

**3. Competitive Differentiation**

AEP's value proposition:
- "Unified customer profile" (requires data ingestion to unify)
- "Real-time segmentation" (requires optimized local storage)
- "Identity resolution" (requires proprietary graph database)

Federated queries would commoditize AEP:
- If AEP just queries external data, what's different from Segment/mParticle?
- AEP becomes "just another activation API" (lower perceived value)

#### 2.5.5 Analysis: Federated Queries as a Zero-Copy Pattern (Hypothetical)

**If AEP supported federated queries, here's how it would work**:

**Hypothetical Architecture**:
```
GCP BigQuery (Master Profile Store)
  - Full customer profiles (100+ attributes)
  - Activity history
  - Behavioral events
    |
    | NO data transfer
    V
AEP Federated Query Layer (hypothetical)
  - Virtual profile schema (maps to BigQuery tables)
  - Segment definition: "leadClassification = 'hot'"
  - Translates to: SELECT customer_id FROM bigquery.profiles WHERE leadClassification = 'hot'
    |
    | Query results (customer IDs)
    V
AEP Destinations
  - Activate customer IDs to Marketo, Google Ads
  - (Optional) Enrich with full profiles from BigQuery
```

**Performance Implications** (hypothetical):

| Metric | AEP Current (Ingested Data) | AEP Hypothetical (Federated) |
|--------|----------------------------|------------------------------|
| **Segment Evaluation** | 5-30 minutes (batch), <1 sec (streaming) | 10-60 seconds (BigQuery query) |
| **Profile Lookup** | <100ms | 1-30 seconds (network + BigQuery) |
| **Data Transfer** | Full profile ingestion (GB-TB) | Zero (query in-place) |
| **Identity Resolution** | Real-time graph traversal (<100ms) | Not possible (requires local graph DB) |
| **Complex Segments** | Fast (pre-built indexes) | Slow (ad-hoc BigQuery joins) |

**Cost Implications** (hypothetical):

| Cost Category | AEP Current | AEP Hypothetical (Federated) |
|---------------|-------------|------------------------------|
| **AEP Licensing** | $50K-$150K/month | $20K-$50K/month (lower value = lower price) |
| **Data Storage** | AEP Data Lake ($$$) | BigQuery ($) - cheaper |
| **Query Compute** | AEP Query Service ($$$) | BigQuery ($) - cheaper |
| **Data Transfer** | GCP egress ($) | Zero |
| **Total** | High | Medium (but AEP offers less value) |

**Functionality Limitations** (hypothetical):

Even if AEP supported federated queries, these features would NOT work:

1. **Real-Time Customer Profile**: Cannot achieve <100ms lookup with remote queries
2. **Streaming Segmentation**: Cannot evaluate segments in <1 second with external DB queries
3. **Identity Graph**: Graph databases require local storage (cannot federate graph traversal)
4. **Edge Segmentation**: Edge nodes cannot query central BigQuery (latency, cost)
5. **Customer AI**: ML models require co-located data (cannot train on remote data efficiently)

**What Would Still Work**:

1. **Batch Segmentation**: BigQuery is fast enough for daily segment evaluation
2. **Destination Activation**: Customer IDs can be sent to destinations (enriched from BigQuery)
3. **Analytics**: Query Service equivalent (just query BigQuery directly)

#### 2.5.6 Comparison: Federated Queries vs Recommended Patterns

**Pattern Comparison Table**:

| Pattern | Data Location | Zero-Copy? | AEP Supported? | Performance | Cost | Functionality |
|---------|---------------|------------|----------------|-------------|------|---------------|
| **Federated Query (ideal)** | BigQuery only | Yes | **NO** | Slow (1-30s) | Low | Limited (no real-time profile, no identity graph) |
| **Computed Attributes (Pattern 1)** | BigQuery + AEP (minimal) | No (minimal transfer) | Yes | Fast (AEP optimized) | Medium | Full AEP features |
| **Reference Architecture (Pattern 2)** | BigQuery + AEP (stubs) | No (stubs only) | Yes | Medium (enrichment lag) | Medium | Limited (segment on stubs only) |
| **Event-Driven (Pattern 3)** | BigQuery + AEP (events) | No (events copied) | Yes | Fast (streaming) | Medium-High | Limited (no persistent profiles) |
| **Hybrid Batch+Stream (Pattern 4)** | BigQuery + AEP (selective) | No (selective transfer) | Yes | Fast (optimized) | Medium | Full AEP features |

**Decision Framework**:

```
Do you need <100ms profile lookups (web personalization)?
  |
  YES --> Federated queries won't work. Use Pattern 1 or 4 (ingest into AEP).
  |
  NO --> Continue
  |
Do you need real-time segmentation (<1 second)?
  |
  YES --> Federated queries won't work. Use Pattern 1 or 4 (streaming ingestion).
  |
  NO --> Continue
  |
Do you need identity resolution across devices/channels?
  |
  YES --> Federated queries won't work. Use Pattern 1 or 4 (AEP identity graph).
  |
  NO --> You don't need AEP. Use GCP-native (BigQuery + direct destination APIs).
```

#### 2.5.7 Workarounds and Alternatives

Since AEP doesn't support federated queries, here are alternatives to achieve similar goals:

**Workaround 1: Query Service + Scheduled Exports**

```
Architecture:
  BigQuery (Master Data)
    --> Daily batch ingestion to AEP Data Lake
    --> AEP Query Service: Create computed views
    --> Export results to GCS
    --> Destinations read from GCS

Pros:
- Minimal data in AEP (only aggregated views)
- Use SQL (familiar to data teams)

Cons:
- Still requires ingesting data into AEP (not zero-copy)
- Query Service is expensive
- 24-hour latency (daily batch)
```

**Workaround 2: External Data Enrichment via APIs**

```
Architecture:
  AEP Segment Membership
    --> Export to GCS (customer IDs)
    --> Cloud Function: Fetch full profiles from BigQuery
    --> Send to Destinations (enriched profiles)

Pros:
- Minimal data in AEP (just customer IDs + segment flags)
- Full profiles stay in BigQuery (data sovereignty)

Cons:
- Cannot use full profile data for segmentation (only IDs in AEP)
- Adds latency (enrichment step)
- Complex to maintain (external orchestration)
```

**Workaround 3: Reverse ETL Pattern (Census, Hightouch)**

```
Architecture:
  BigQuery (Source of Truth)
    --> Reverse ETL Tool (Census/Hightouch)
    --> Syncs computed attributes to AEP (via API)
    --> AEP segments on synced attributes
    --> Destinations

Pros:
- Business logic stays in SQL (BigQuery)
- Declarative sync (no custom code)
- Minimal data in AEP (only attributes needed for segmentation)

Cons:
- Third-party tool cost ($10K-$50K/year)
- Still requires copying data to AEP (not zero-copy)
- Another system to maintain
```

**Alternative: Skip AEP Entirely (GCP-Native)**

If federated queries are a requirement, consider:

```
Architecture:
  BigQuery (Segmentation Logic)
    --> Cloud Composer (Orchestration)
    --> Direct API integrations to Destinations:
        - Marketo API
        - Google Ads Customer Match API
        - Salesforce Bulk API

Pros:
- True zero-copy (no data movement to external CDP)
- Full control over data and logic
- Lower cost (no AEP licensing)
- BigQuery = federated query system (can query GCS, Drive, Cloud SQL)

Cons:
- Must build/maintain destination integrations (engineering effort)
- No unified identity resolution (unless you build it)
- No real-time profile store (cannot do <100ms lookups)
```

**When to Use Each Approach**:

| Your Requirement | Recommended Approach |
|------------------|----------------------|
| Must use AEP + minimize data transfer | Pattern 1: Computed Attributes (Section 2.1) |
| Need data sovereignty (data stays in BigQuery) | Pattern 2: Reference Architecture (Section 2.2) |
| Need real-time activation | Pattern 4: Hybrid Batch + Streaming (Section 2.4) |
| Want SQL-based segmentation | Workaround 1: Query Service or GCP-native |
| Want to avoid vendor lock-in | GCP-native (no AEP) |
| Need <100ms profile lookups | Must ingest into AEP (no alternative) |

#### 2.5.8 Should You Advocate for Federated Queries with Adobe?

**Short Answer**: Yes, but don't expect it soon.

**Adobe's Roadmap Reality**:

Adobe is aware of customer demand for federated queries, but:

1. **Technical Complexity**: Would require re-architecting core AEP components (Profile Store, Segmentation Engine, Identity Graph)
2. **Timeline**: If started today, 3-5 years to productionize (enterprise-scale is hard)
3. **Priority**: Adobe is focused on AI features (GenAI, Customer AI enhancements) over infrastructure changes
4. **Competitive Pressure**: Snowflake, Databricks are building CDP features with native federated queries (competitive threat)

**What You Can Do**:

1. **Provide Feedback to Adobe Account Team**:
   - "We want federated query support to reduce data transfer and vendor lock-in"
   - Explain your use case: "We have 100TB in BigQuery, ingesting into AEP is costly and slow"
   - Ask for roadmap visibility: "Is this on the roadmap? What's the timeline?"

2. **Feature Request via Adobe UserVoice**:
   - Adobe tracks feature requests via community forums
   - Upvote existing requests or create new one
   - More customer demand = higher priority

3. **Contract Negotiations**:
   - If federated queries are critical, negotiate:
     - Pilot period (3-6 months) to evaluate AEP with minimal commitment
     - Data export rights (ensure you can leave if federated queries never arrive)
     - Price concessions (argue that data ingestion costs should be lower)

**Honest Assessment**:

Don't hold your breath for federated queries in AEP. Adobe's business model depends on data ingestion, and the technical lift is massive. Instead:

- **Short-term (0-2 years)**: Use Pattern 1 (Computed Attributes) to minimize data transfer
- **Medium-term (2-5 years)**: Monitor Adobe roadmap, but have exit strategy ready
- **Long-term (5+ years)**: Consider alternatives (Snowflake Native App for CDPs, Databricks Delta Sharing) if AEP doesn't evolve

#### 2.5.9 Competitive Landscape: Platforms That DO Support Federated Queries

**Why This Matters**: Understanding what's possible elsewhere helps evaluate AEP's limitations.

**Snowflake Native Apps for CDP**:

```
Architecture:
  Snowflake (Customer Data Warehouse)
    --> Install CDP Native App (e.g., Hightouch, Census)
    --> Segmentation logic runs IN Snowflake (no data export)
    --> Activation to Destinations (via API)

Key Difference:
- Data NEVER leaves Snowflake
- CDP queries customer's tables directly (true federated query)
- Customer controls schema (no XDM lock-in)

Pros:
- True zero-copy (no data movement)
- Customer owns data and logic
- Lower cost (no CDP data storage fees)

Cons:
- No real-time profile store (<100ms lookups)
- No proprietary identity graph (must build yourself)
- Limited to batch segmentation (not streaming)
```

**Databricks Delta Sharing for CDPs**:

```
Architecture:
  Databricks (Customer Lakehouse)
    --> Delta Sharing: Share tables with CDP (read-only)
    --> CDP queries shared tables (no data copy)
    --> Activation to Destinations

Key Difference:
- CDP reads from customer's lakehouse via Delta Sharing protocol
- Customer controls access (can revoke at any time)
- Zero data replication

Pros:
- Zero-copy (true federated query)
- Customer maintains full control
- Works across clouds (share Databricks tables with GCP/Azure CDP)

Cons:
- Emerging ecosystem (fewer CDP vendors support Delta Sharing)
- Latency higher than AEP's local storage
```

**Google BigQuery + Reverse ETL**:

```
Architecture:
  BigQuery (Source of Truth)
    --> Hightouch/Census: Syncs ONLY computed attributes
    --> Destinations (Marketo, Google Ads, etc.)

Key Difference:
- Segmentation logic stays in BigQuery (SQL)
- Reverse ETL tool is thin sync layer (not full CDP)
- Minimal vendor lock-in (can swap Reverse ETL tools easily)

Pros:
- Business logic in SQL (portable, familiar)
- Cheap (Reverse ETL tools: $10K-$50K/year vs AEP: $50K-$150K/year)
- Flexible (no schema lock-in)

Cons:
- No identity resolution (must build yourself)
- No real-time activation (batch only, hourly at best)
- Must build destination integrations (or use Reverse ETL connectors)
```

**Comparison Table**:

| Platform | Zero-Copy? | Real-Time Profile? | Identity Graph? | Cost (10K profiles) | Vendor Lock-in |
|----------|------------|-------------------|-----------------|---------------------|----------------|
| **AEP** | No | Yes (<100ms) | Yes (proprietary) | $50K-$150K/year | High (XDM schema) |
| **Snowflake Native CDP** | Yes | No (seconds) | No (DIY) | $20K-$50K/year | Medium (SQL schema) |
| **Databricks Delta Share** | Yes | No (seconds) | No (DIY) | $20K-$50K/year | Low (open format) |
| **BigQuery + Reverse ETL** | Partial | No (minutes) | No (DIY) | $10K-$30K/year | Low (SQL, swap tools) |

#### 2.5.10 Key Takeaways: Federated Queries and AEP

**What You Need to Know**:

1. **AEP does NOT support federated queries** - This is a fundamental architectural limitation, not a feature gap that will be fixed soon.

2. **Technical Reasons**:
   - AEP's Real-Time Profile requires local storage for <100ms lookups
   - Segmentation engine relies on pre-built indexes (external queries too slow)
   - Identity graph requires specialized graph database (cannot federate)

3. **Business Reasons**:
   - Data ingestion creates vendor lock-in (Adobe's business model)
   - Federated queries would commoditize AEP (lower perceived value)

4. **Alternatives to Achieve Zero-Copy Goals**:
   - Pattern 1 (Computed Attributes): 95% data reduction vs full replication
   - GCP-native architecture: True zero-copy, but no AEP features
   - Reverse ETL (Hightouch/Census): Middle ground (SQL-based, portable logic)

5. **When AEP Still Makes Sense Despite No Federated Queries**:
   - You need <100ms profile lookups (web/app personalization)
   - You need streaming segmentation (<1 second evaluation)
   - You need cross-device identity resolution (proprietary graph)
   - You value Adobe-managed destination connectors (saves engineering effort)

6. **When to Avoid AEP**:
   - Your primary requirement is zero-copy (impossible with AEP)
   - You can build destination integrations in-house (GCP-native cheaper)
   - You want to avoid vendor lock-in (keep logic in BigQuery)
   - Budget-constrained (Reverse ETL tools 50-70% cheaper)

**Final Recommendation**:

For your GCP + BigQuery environment:

```
If you must use AEP:
  --> Use Pattern 1 (Computed Attributes from GCP)
  --> 95% data reduction (not zero-copy, but close)
  --> Keep scoring logic in BigQuery (portable, not locked into AEP)

If you can avoid AEP:
  --> Use BigQuery + Reverse ETL (Hightouch/Census)
  --> 50-70% cheaper than AEP
  --> True portability (swap Reverse ETL tools easily)
  --> Segmentation logic stays in SQL (familiar, maintainable)
```

The honest truth: If federated queries are a hard requirement, AEP is not the right platform. Advocate for the feature with Adobe, but plan your architecture assuming it won't exist for 3-5 years (if ever).

**IMPORTANT UPDATE**: As of 2025, Adobe has released **Federated Audience Composition**, which fundamentally changes this analysis. See Section 2.6 for complete details on this TRUE zero-copy capability.

---

### 2.6 Pattern 6: Federated Audience Composition - TRUE Zero-Copy (NEW)

**MAJOR UPDATE**: Adobe has released **Federated Audience Composition**, which enables TRUE zero-copy architecture with AEP - querying data directly in external data warehouses WITHOUT copying to AEP.

**What Changed**: Everything I wrote in Section 2.5 about AEP not supporting federated queries is now partially obsolete. Federated Audience Composition is Adobe's answer to zero-copy, and it fundamentally changes the architectural approach for BigQuery-to-AEP integration.

#### 2.6.1 What is Federated Audience Composition?

**Definition**: Federated Audience Composition is an AEP capability that enables building and enriching audiences from third-party data warehouses WITHOUT copying data to AEP. It queries data in-place in your external warehouse.

**Supported Data Warehouses** (8 platforms):
1. Amazon Redshift
2. Azure Synapse Analytics
3. Databricks
4. **Google BigQuery** (your use case!)
5. Microsoft Fabric
6. Oracle
7. Snowflake
8. Vertica Analytics

**How It Works**:
```
GCP BigQuery (Source of Truth)
  - Full customer profiles
  - Cold/Warm/Hot lead scores (computed in BigQuery)
  - Activity history
  - All raw behavioral data
    |
    | NO DATA COPYING TO AEP
    V
AEP Federated Audience Composition
  - Connects to BigQuery via secure service account
  - Queries BigQuery tables in-place (federated query execution)
  - Builds "External Audiences" based on BigQuery data
    |
    | Only audience membership is stored in AEP
    V
AEP Real-Time CDP / Journey Optimizer
  - External audiences available for activation
  - Can be combined with AEP-native audiences
  - Activated to destinations (Marketo, Google Ads, etc.)
```

**Key Distinction from Section 2.5 Analysis**:

| Capability | Section 2.5 (AEP Limitations) | Federated Audience Composition (NEW) |
|------------|------------------------------|--------------------------------------|
| Query external warehouse | NO | YES (BigQuery, Snowflake, etc.) |
| Zero data copying | Impossible | Possible (audience membership only) |
| Data remains in warehouse | NO | YES |
| Segmentation on warehouse data | NO | YES |
| Real-Time Profile lookups | Required AEP data | Still requires AEP profiles for <100ms lookups |
| Identity stitching | Required AEP data | Still requires AEP Identity Graph |

**Honest Assessment**: This is NOT full federated query support (like Snowflake External Tables), but it's a MAJOR step toward zero-copy for audience creation use cases.

#### 2.6.2 BigQuery-Specific Configuration

**Authentication Method**:
- Service account with JSON key file
- Secure credential storage in AEP

**Required BigQuery Permissions**:
```
bigquery.jobs.create   # Execute queries
bigquery.tables.create # Create result tables (if needed)
```

**Service Account Setup** (step-by-step):

1. **Create Service Account in GCP**:
```bash
# Create service account
gcloud iam service-accounts create aep-federated-access \
  --display-name="AEP Federated Audience Composition" \
  --description="Service account for Adobe AEP to query BigQuery"

# Grant BigQuery permissions
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:aep-federated-access@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/bigquery.jobUser"

gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:aep-federated-access@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/bigquery.dataViewer"

# Generate JSON key
gcloud iam service-accounts keys create aep-service-account-key.json \
  --iam-account=aep-federated-access@YOUR_PROJECT_ID.iam.gserviceaccount.com
```

2. **Configure Connection in AEP**:
```
AEP UI > Destinations > Catalog > Federated Audience Composition

Connection Parameters:
- Service Account Email: aep-federated-access@YOUR_PROJECT_ID.iam.gserviceaccount.com
- Project ID: YOUR_PROJECT_ID
- Dataset Name: customer_profiles (your BigQuery dataset)
- JSON Key File: [Upload aep-service-account-key.json]
```

**Security Options**:
- **VPN Support**: YES (secure VPN connections between AEP and GCP)
- **Proxy Support**: HTTP, http_no_tunnel, SOCKS4, SOCKS5
- **Data Residency**: Data stays in BigQuery (AEP only stores audience membership)
- **Audit Logging**: BigQuery audit logs capture all AEP queries

**Best Practices for Security**:
1. Use least-privilege service account (only necessary BigQuery permissions)
2. Enable VPC Service Controls to restrict BigQuery access
3. Monitor BigQuery audit logs for AEP query patterns
4. Rotate service account keys quarterly
5. Use separate dataset for AEP-accessible tables (limit blast radius)

#### 2.6.3 Technical Architecture: How Federated Audience Composition Works

**Query Execution Flow**:

```
Step 1: Audience Definition in AEP
  User defines audience: "Hot Leads for Q1 Campaign"
  Criteria: lead_classification = 'hot' AND last_interaction_date > '2025-01-01'
    |
    V
Step 2: AEP Translates to BigQuery SQL
  AEP generates BigQuery-compatible SQL:

  SELECT customer_id, email
  FROM `your-project.customer_profiles.leads`
  WHERE lead_classification = 'hot'
    AND last_interaction_date > '2025-01-01'
    |
    V
Step 3: Execute Query in BigQuery (NOT in AEP)
  Query runs in YOUR BigQuery environment
  You pay BigQuery query costs (not AEP compute)
  Results: 5,000 customer IDs
    |
    V
Step 4: Import ONLY Audience Membership to AEP
  AEP stores:
    - Audience name: "Hot Leads for Q1 Campaign"
    - Member list: [customer_id_1, customer_id_2, ..., customer_id_5000]
    - Metadata: Audience size, last refresh timestamp

  Data transfer: ~100 KB (5,000 IDs × 20 bytes)
  vs Full Profile Ingestion: ~50 MB (5,000 profiles × 10 KB)
  Reduction: 99.8%
    |
    V
Step 5: Activation to Destinations
  AEP activates audience to Marketo, Google Ads, etc.
  Destinations receive customer IDs (can be enriched from BigQuery if needed)
```

**Data Flow Diagram**:

```
┌─────────────────────────────────────────────────────────────┐
│ GCP BigQuery (Source of Truth)                             │
│                                                             │
│ ┌─────────────────────────────────────────────────────┐   │
│ │ Dataset: customer_profiles                          │   │
│ │                                                       │   │
│ │ Table: leads                                         │   │
│ │ - customer_id        (STRING)                        │   │
│ │ - email              (STRING)                        │   │
│ │ - lead_classification (STRING: cold/warm/hot)       │   │
│ │ - propensity_score   (FLOAT64)                       │   │
│ │ - last_interaction_date (DATE)                       │   │
│ │ - ... 95+ other attributes ...                       │   │
│ │                                                       │   │
│ │ 100K rows, 500 MB total                              │   │
│ └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                            |
                            | Federated Query (NO data copy)
                            | AEP executes: SELECT customer_id, email
                            |               WHERE lead_classification = 'hot'
                            V
┌─────────────────────────────────────────────────────────────┐
│ AEP Federated Audience Composition                          │
│                                                             │
│ Query Results:                                              │
│ - 5,000 customer IDs (hot leads)                            │
│ - Data transferred: ~100 KB (IDs only, not full profiles)  │
│                                                             │
│ Stored in AEP:                                              │
│ - External Audience: "Hot Leads Q1"                         │
│ - Members: [id_1, id_2, ..., id_5000]                       │
│ - Last refresh: 2025-10-16 10:00 UTC                        │
│                                                             │
│ Full profile data (500 MB) stays in BigQuery!               │
└─────────────────────────────────────────────────────────────┘
                            |
                            | Activation
                            V
┌─────────────────────────────────────────────────────────────┐
│ Destinations (Marketo, Google Ads, etc.)                    │
│                                                             │
│ Receives: 5,000 customer IDs + email addresses              │
│ Can enrich with full profiles from BigQuery if needed       │
└─────────────────────────────────────────────────────────────┘
```

**Performance Characteristics**:

| Metric | Federated Audience Composition | Traditional AEP Ingestion |
|--------|-------------------------------|---------------------------|
| **Initial Data Transfer** | ZERO (only audience IDs) | 500 MB (full profiles) |
| **Ongoing Data Transfer** | ~100 KB per refresh | 500 MB per full sync |
| **Query Latency** | 10-60 seconds (BigQuery execution) | 5-30 minutes (AEP batch segmentation) |
| **Refresh Frequency** | Configurable (hourly, daily, weekly) | Batch: daily, Streaming: real-time |
| **Cost (BigQuery)** | $5-$50 per query (slots + storage scan) | $0 (data already in AEP) |
| **Cost (AEP)** | Low (no data storage for profiles) | High (data storage + compute) |

**Query Performance Optimization**:

To ensure fast federated queries:

1. **Partition BigQuery Tables**:
```sql
-- Partition by date for time-based queries
CREATE TABLE `your-project.customer_profiles.leads`
PARTITION BY last_interaction_date
CLUSTER BY lead_classification
AS SELECT * FROM source_table;
```

2. **Create Materialized Views for Common Queries**:
```sql
-- Pre-compute hot leads for faster AEP queries
CREATE MATERIALIZED VIEW `your-project.customer_profiles.hot_leads`
AS
SELECT customer_id, email, lead_classification, propensity_score
FROM `your-project.customer_profiles.leads`
WHERE lead_classification = 'hot';

-- AEP queries this view instead of full table (faster + cheaper)
```

3. **Use Clustering for Common Filters**:
```sql
-- Cluster by commonly filtered columns
CREATE TABLE `your-project.customer_profiles.leads`
CLUSTER BY lead_classification, product_interest
AS SELECT * FROM source_table;
```

#### 2.6.4 Capabilities: Audience Creation, Enrichment, and Profile Enrichment

**Capability 1: Audience Creation from Warehouse Data** (Zero-Copy)

Create audiences directly from BigQuery without copying data to AEP.

**Example Use Case**: Create "Hot Leads" audience from BigQuery lead scoring

```sql
-- AEP Federated Audience Composition query (auto-generated from UI)
SELECT
  customer_id,
  email,
  lead_classification
FROM `your-project.customer_profiles.leads`
WHERE lead_classification = 'hot'
  AND last_interaction_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
```

**Result in AEP**:
- External Audience: "Hot Leads - Last 30 Days"
- Size: 5,000 members
- Data in AEP: Only customer IDs (not full profiles)
- Full data stays in BigQuery

**Capability 2: Audience Enrichment with Warehouse Attributes**

Enrich existing AEP audiences with additional attributes from BigQuery.

**Example Use Case**: Enrich AEP-native audience with BigQuery product affinity scores

```sql
-- Join AEP audience with BigQuery attributes
SELECT
  aep.customer_id,
  bq.product_affinity_score,
  bq.predicted_next_purchase_date,
  bq.customer_lifetime_value
FROM `aep_audience_export` aep
JOIN `your-project.customer_profiles.ml_scores` bq
  ON aep.customer_id = bq.customer_id
WHERE bq.product_affinity_score > 0.7
```

**Result**:
- AEP audience enriched with BigQuery ML scores
- No need to ingest ML scores into AEP
- Scores computed in BigQuery, used in AEP

**Capability 3: Profile Enrichment with Individual Customer Attributes**

Enrich AEP profiles with individual-level attributes from BigQuery.

**Example Use Case**: Add account manager assignment from BigQuery to AEP profiles

```sql
-- Lookup profile attributes from BigQuery
SELECT
  customer_id,
  account_manager_name,
  account_tier,
  contract_renewal_date
FROM `your-project.customer_profiles.account_details`
WHERE customer_id IN (SELECT customer_id FROM aep_activation_list)
```

**Use Case**: When activating to destinations, include account manager info from BigQuery.

**Important Limitation**: This is for activation enrichment, NOT for creating persistent profiles in AEP. The attributes are fetched at activation time, not stored in AEP Real-Time Customer Profile.

#### 2.6.5 What Works vs What Doesn't: Honest Limitations Assessment

**What WORKS with Federated Audience Composition**:

1. **Audience Creation from BigQuery** - WORKS
   - Create audiences based on ANY BigQuery data (no data copy)
   - Complex SQL logic supported (joins, subqueries, window functions)
   - Audience membership refreshed on schedule (hourly/daily/weekly)

2. **Activation to Destinations** - WORKS
   - External audiences can be activated to all AEP destinations
   - Marketo, Google Ads, Facebook, Salesforce, etc.
   - Same activation workflow as AEP-native audiences

3. **Combining External + Native Audiences** - WORKS
   - Create union/intersection of BigQuery audiences + AEP audiences
   - Example: (BigQuery: Hot Leads) AND (AEP: Email Subscribers)

4. **Scheduled Refresh** - WORKS
   - Audiences refresh automatically (hourly, daily, weekly)
   - AEP re-queries BigQuery to update membership
   - Stale data risk minimized with frequent refresh

5. **Multi-Table Queries** - WORKS
   - Join multiple BigQuery tables in single query
   - Example: leads JOIN product_interactions JOIN account_details

**What DOES NOT WORK with Federated Audience Composition**:

1. **Real-Time Profile Lookups** - DOES NOT WORK
   - Cannot achieve <100ms profile lookups from BigQuery
   - BigQuery queries take 10-60 seconds (not suitable for web personalization)
   - If you need real-time personalization, must ingest profiles into AEP

2. **Identity Stitching Across Devices** - DOES NOT WORK (Limited)
   - AEP Identity Graph cannot stitch identities from BigQuery-only data
   - Identity resolution requires profiles in AEP Profile Store
   - Workaround: Pre-compute identity resolution in BigQuery, then use deterministic IDs

3. **Streaming Segmentation** - DOES NOT WORK
   - External audiences are batch-only (no streaming evaluation)
   - Minimum refresh: ~1 hour (depends on BigQuery query complexity)
   - Cannot trigger journey orchestration in real-time based on BigQuery data

4. **AEP AI/ML on External Data** - DOES NOT WORK
   - Customer AI, Attribution AI require data in AEP Data Lake
   - Cannot train ML models on BigQuery data from AEP
   - Solution: Train models in BigQuery (Vertex AI, BigQuery ML), use scores in AEP

5. **Edge Segmentation** - DOES NOT WORK
   - Edge nodes cannot query BigQuery (latency too high)
   - Cannot use external audiences for edge decisioning
   - Must use AEP-native profiles for edge use cases

6. **ExperienceEvent Time-Series Queries** - LIMITED
   - Can query BigQuery event data, but no native XDM ExperienceEvent support
   - AEP's time-series optimizations (Timeseries indexes) don't apply
   - Complex time-series queries may be slow

**Feature Comparison Matrix**:

| Feature | AEP-Native Profiles | Federated Audiences (BigQuery) |
|---------|--------------------|---------------------------------|
| **Audience Creation** | YES | YES |
| **Destination Activation** | YES | YES |
| **Real-Time Lookup (<100ms)** | YES | NO |
| **Streaming Segmentation** | YES | NO (batch only) |
| **Identity Stitching** | YES (AEP Identity Graph) | NO (pre-compute in BigQuery) |
| **Customer AI / Attribution AI** | YES | NO |
| **Edge Segmentation** | YES | NO |
| **Journey Orchestration Triggers** | YES (real-time) | LIMITED (batch refresh) |
| **Data Transfer to AEP** | FULL (all profile data) | MINIMAL (audience IDs only) |
| **Cost (AEP Storage)** | HIGH | LOW |
| **Query Latency** | Low (seconds) | Medium (10-60 seconds) |
| **Data Sovereignty** | Data in AEP (US/EU regions) | Data stays in BigQuery (GCP) |

**Decision Framework: When to Use Federated Audiences vs AEP-Native Profiles**:

```
Do you need <100ms profile lookups (web/app personalization)?
  |
  YES --> Must use AEP-native profiles (ingest data)
  |
  NO --> Continue
  |
Do you need real-time streaming segmentation (<1 second)?
  |
  YES --> Must use AEP-native profiles
  |
  NO --> Continue
  |
Do you need AEP Identity Graph for cross-device stitching?
  |
  YES --> Must use AEP-native profiles
  |
  NO --> Continue
  |
Do you need to use Customer AI or Attribution AI?
  |
  YES --> Must use AEP-native profiles (AI requires AEP Data Lake)
  |
  NO --> Continue
  |
Do you need Edge Segmentation (Adobe Target, Offer Decisioning)?
  |
  YES --> Must use AEP-native profiles
  |
  NO --> Federated Audience Composition is PERFECT for your use case!
        |
        V
  Use Case: Batch audience creation + activation
  - Create audiences from BigQuery (zero data copy)
  - Activate to destinations (Marketo, Google Ads, etc.)
  - Refresh daily/hourly (no real-time requirement)
  - Keep data in BigQuery (data sovereignty, portability)
```

#### 2.6.6 Use Case Analysis: Your Cold/Warm/Hot Lead Scoring

**Your Requirements**:
1. Cold/Warm/Hot lead classification computed in BigQuery (BigQuery ML models)
2. Activate audiences to marketing destinations (Marketo, Google Ads)
3. Minimize data transfer (zero-copy ideal)
4. Keep scoring logic in BigQuery (portability, avoid AEP lock-in)

**Federated Audience Composition Fit: EXCELLENT (95% match)**

**Recommended Architecture for Your Use Case**:

```
┌────────────────────────────────────────────────────────────────┐
│ GCP BigQuery (Scoring Pipeline)                               │
│                                                                │
│ Step 1: Compute Lead Scores                                   │
│ ┌──────────────────────────────────────────────────────────┐ │
│ │ BigQuery ML Model: lead_propensity_model                 │ │
│ │                                                            │ │
│ │ CREATE OR REPLACE MODEL lead_propensity_model             │ │
│ │ OPTIONS(model_type='logistic_reg') AS                     │ │
│ │ SELECT                                                     │ │
│ │   customer_id,                                             │ │
│ │   engagement_score,                                        │ │
│ │   website_visits,                                          │ │
│ │   email_opens,                                             │ │
│ │   converted AS label                                       │ │
│ │ FROM customer_features;                                    │ │
│ └──────────────────────────────────────────────────────────┘ │
│                                                                │
│ Step 2: Generate Lead Classifications                         │
│ ┌──────────────────────────────────────────────────────────┐ │
│ │ CREATE OR REPLACE TABLE leads_classified AS              │ │
│ │ SELECT                                                     │ │
│ │   customer_id,                                             │ │
│ │   email,                                                   │ │
│ │   predicted_propensity,                                    │ │
│ │   CASE                                                     │ │
│ │     WHEN predicted_propensity >= 0.7 THEN 'hot'           │ │
│ │     WHEN predicted_propensity >= 0.4 THEN 'warm'          │ │
│ │     ELSE 'cold'                                            │ │
│ │   END AS lead_classification,                             │ │
│ │   CURRENT_TIMESTAMP() AS last_scored_at                   │ │
│ │ FROM ML.PREDICT(MODEL lead_propensity_model,              │ │
│ │   (SELECT * FROM customer_features));                     │ │
│ └──────────────────────────────────────────────────────────┘ │
│                                                                │
│ Result: 100K leads classified, stored in BigQuery            │
│         NO DATA LEAVES BIGQUERY                              │
└────────────────────────────────────────────────────────────────┘
                            |
                            | Federated Query (NO data copy)
                            V
┌────────────────────────────────────────────────────────────────┐
│ AEP Federated Audience Composition                            │
│                                                                │
│ Audience 1: "Hot Leads"                                       │
│ ┌──────────────────────────────────────────────────────────┐ │
│ │ SELECT customer_id, email                                 │ │
│ │ FROM `project.dataset.leads_classified`                   │ │
│ │ WHERE lead_classification = 'hot'                         │ │
│ └──────────────────────────────────────────────────────────┘ │
│ Result: 5,000 hot leads                                       │
│ Transferred to AEP: ~100 KB (IDs only)                        │
│                                                                │
│ Audience 2: "Warm Leads - Tech Product Interest"             │
│ ┌──────────────────────────────────────────────────────────┐ │
│ │ SELECT customer_id, email                                 │ │
│ │ FROM `project.dataset.leads_classified`                   │ │
│ │ WHERE lead_classification = 'warm'                        │ │
│ │   AND product_interest = 'technology'                     │ │
│ └──────────────────────────────────────────────────────────┘ │
│ Result: 3,000 warm tech leads                                 │
│ Transferred to AEP: ~60 KB                                    │
│                                                                │
│ Audience 3: "Cold Leads - Nurture Campaign"                  │
│ ┌──────────────────────────────────────────────────────────┐ │
│ │ SELECT customer_id, email                                 │ │
│ │ FROM `project.dataset.leads_classified`                   │ │
│ │ WHERE lead_classification = 'cold'                        │ │
│ │   AND last_interaction_date < DATE_SUB(CURRENT_DATE(),   │ │
│ │       INTERVAL 90 DAY)                                     │ │
│ └──────────────────────────────────────────────────────────┘ │
│ Result: 10,000 cold leads for re-engagement                   │
│ Transferred to AEP: ~200 KB                                   │
│                                                                │
│ Total Data Transfer: ~360 KB (vs 1 GB for full profiles)     │
│ Reduction: 99.96%                                             │
└────────────────────────────────────────────────────────────────┘
                            |
                            | Activate to Destinations
                            V
┌────────────────────────────────────────────────────────────────┐
│ Marketing Destinations                                         │
│                                                                │
│ Marketo:                                                       │
│ - "Hot Leads" → Sales outreach campaign                       │
│ - "Warm Tech Leads" → Product webinar invitations            │
│                                                                │
│ Google Ads:                                                    │
│ - "Hot Leads" → Retargeting with premium product ads          │
│ - "Cold Leads" → Brand awareness campaigns                    │
│                                                                │
│ Salesforce:                                                    │
│ - "Hot Leads" → Create high-priority tasks for sales reps     │
│                                                                │
│ Email ESP:                                                     │
│ - "Cold Leads" → 90-day nurture sequence                      │
└────────────────────────────────────────────────────────────────┘
```

**Implementation Walkthrough**:

**Step 1: Set Up BigQuery Tables** (one-time setup)

```sql
-- Create partitioned table for lead classifications
CREATE TABLE `your-project.customer_profiles.leads_classified`
(
  customer_id STRING,
  email STRING,
  first_name STRING,
  last_name STRING,
  lead_classification STRING,  -- 'hot', 'warm', 'cold'
  predicted_propensity FLOAT64,
  engagement_score INT64,
  product_interest STRING,
  last_interaction_date DATE,
  last_scored_at TIMESTAMP
)
PARTITION BY DATE(last_scored_at)
CLUSTER BY lead_classification, product_interest;

-- Create materialized views for common queries (faster + cheaper)
CREATE MATERIALIZED VIEW `your-project.customer_profiles.hot_leads`
AS
SELECT customer_id, email, predicted_propensity, last_scored_at
FROM `your-project.customer_profiles.leads_classified`
WHERE lead_classification = 'hot'
  AND last_scored_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY);

-- Refresh daily (automatic)
```

**Step 2: Configure Federated Connection in AEP**

```
AEP UI Navigation:
  Destinations > Catalog > Federated Audience Composition > Configure

Connection Details:
  Name: GCP BigQuery Production
  Service Account Email: aep-federated-access@your-project.iam.gserviceaccount.com
  Project ID: your-project
  Default Dataset: customer_profiles
  JSON Key: [Upload service account key]

Security:
  ☑ Enable VPN
  ☑ Use encrypted connection
  ☐ Enable proxy (if needed)

Test Connection:
  AEP will execute: SELECT 1 FROM `your-project.customer_profiles.leads_classified` LIMIT 1
  Status: ✓ Connection successful
```

**Step 3: Create Federated Audiences in AEP**

```
AEP UI Navigation:
  Audiences > Create Audience > Federated Audience Composition

Audience 1: "Hot Leads Q1 2025"
  Data Source: GCP BigQuery Production
  Query Builder (UI or SQL):
    SELECT customer_id, email
    FROM `your-project.customer_profiles.leads_classified`
    WHERE lead_classification = 'hot'
      AND last_scored_at >= TIMESTAMP('2025-01-01')

  Refresh Schedule: Daily at 2:00 AM UTC

  Preview Results: 5,234 members

  Save Audience

Audience 2: "Warm Tech Leads"
  Data Source: GCP BigQuery Production
  Query:
    SELECT customer_id, email
    FROM `your-project.customer_profiles.leads_classified`
    WHERE lead_classification = 'warm'
      AND product_interest = 'technology'

  Refresh Schedule: Daily at 2:00 AM UTC

  Preview Results: 3,102 members

  Save Audience
```

**Step 4: Activate Audiences to Destinations**

```
AEP UI Navigation:
  Audiences > "Hot Leads Q1 2025" > Activate to Destination

Destination: Marketo Engage
  Mapping:
    customer_id → Marketo Lead ID
    email → Email Address

  Activation Frequency: Daily (after audience refresh)

  Activate

Destination: Google Ads Customer Match
  Mapping:
    email → Email (hashed SHA256)

  Activation Frequency: Daily

  Activate
```

**Step 5: Monitor and Optimize**

```sql
-- BigQuery: Monitor AEP query costs
SELECT
  user_email,
  query,
  total_bytes_processed,
  total_slot_ms,
  (total_bytes_processed / 1024 / 1024 / 1024) AS gb_processed,
  (total_slot_ms / 1000 / 60 / 60) AS slot_hours
FROM `your-project.region-us.INFORMATION_SCHEMA.JOBS_BY_PROJECT`
WHERE user_email = 'aep-federated-access@your-project.iam.gserviceaccount.com'
  AND creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
ORDER BY creation_time DESC;

-- Optimize expensive queries
-- Example: If AEP queries full table repeatedly, create materialized view
```

**Data Transfer Metrics** (Your Use Case):

| Metric | Full Profile Ingestion (Pattern 1) | Federated Audiences (Pattern 6) |
|--------|-------------------------------------|----------------------------------|
| **Initial Transfer** | 1 GB (100K profiles × 10 KB) | 360 KB (18K IDs across 3 audiences) |
| **Daily Refresh** | 1 GB (full sync) | 360 KB (audience membership update) |
| **Monthly Transfer** | 30 GB | 10.8 MB |
| **Annual Transfer** | 365 GB | 131 MB |
| **Reduction** | Baseline | 99.96% |

**Cost Implications**:

| Cost Category | Pattern 1 (Computed Attributes) | Pattern 6 (Federated Audiences) |
|---------------|----------------------------------|----------------------------------|
| **AEP Licensing** | $70K-$120K/year (100K profiles) | $40K-$80K/year (no profile storage) |
| **AEP Data Storage** | $10K-$20K/year (1 GB × 365 days) | $500/year (audience metadata only) |
| **GCP Egress** | $2K-$5K/year (data transfer out) | $50/year (minimal transfer) |
| **BigQuery Query** | $0 (no queries from AEP) | $500-$2K/year (daily queries) |
| **Total Annual** | $82K-$145K | $41K-$83K |
| **Savings** | Baseline | 50% |

**Performance Comparison**:

| Metric | Pattern 1 (Computed Attributes) | Pattern 6 (Federated Audiences) |
|--------|----------------------------------|----------------------------------|
| **Audience Refresh Latency** | 5-15 seconds (streaming API) | 10-60 seconds (BigQuery query) |
| **Audience Availability in AEP** | Immediate (after API call) | After query completion |
| **Logic Change Deployment** | Redeploy GCP pipeline + API calls | Update BigQuery table (no AEP changes) |
| **Data Freshness** | Real-time (if streamed) | Batch (daily refresh) |
| **Complexity** | High (maintain GCP pipeline + AEP sync) | Low (BigQuery SQL + AEP UI config) |

#### 2.6.7 When to Use Federated Audience Composition vs Pattern 1 (Computed Attributes)

**Comparison Table**:

| Criteria | Pattern 1: Computed Attributes | Pattern 6: Federated Audience Composition |
|----------|-------------------------------|-------------------------------------------|
| **Data Transfer** | Minimal (5-10 fields per profile) | Near-Zero (audience IDs only) |
| **Real-Time Capability** | YES (streaming API) | NO (batch refresh, hourly min) |
| **AEP Profile Storage** | Required (minimal schema) | NOT required |
| **Identity Resolution** | AEP Identity Graph available | Must pre-compute in BigQuery |
| **Customer AI / Attribution AI** | Possible (if raw events ingested) | NOT possible |
| **Data Sovereignty** | Data copied to AEP (US/EU) | Data stays in BigQuery (GCP region) |
| **Vendor Lock-in** | Medium (scoring in GCP, activation in AEP) | Low (all logic in BigQuery) |
| **Cost (AEP)** | $70K-$120K/year | $40K-$80K/year |
| **Cost (GCP)** | Low (compute + minimal egress) | Medium (query costs) |
| **Complexity** | High (pipeline + API integration) | Low (SQL + UI configuration) |
| **Latency** | Low (5-15 seconds) | Medium (10-60 seconds) |
| **Use Case Fit** | Need real-time + AEP AI features | Batch activation + data sovereignty |

**Decision Framework**:

```
Do you need real-time audience updates (<1 minute)?
  |
  YES --> Use Pattern 1 (Computed Attributes via Streaming API)
          - Stream computed scores to AEP in real-time
          - Example: Lead score changes after webinar → immediate activation
  |
  NO --> Continue
  |
Do you need to use Customer AI or Attribution AI?
  |
  YES --> Use Pattern 1 (requires raw events in AEP Data Lake)
          - Ingest behavioral events to AEP
          - Use Customer AI for propensity scoring
  |
  NO --> Continue
  |
Do you need cross-device identity stitching (AEP Identity Graph)?
  |
  YES --> Use Pattern 1 (requires profiles in AEP)
          - Ingest profiles with identityMap
          - Let AEP stitch email ↔ cookie ↔ mobile IDs
  |
  NO --> Continue
  |
Is data sovereignty a hard requirement (data cannot leave GCP)?
  |
  YES --> Use Pattern 6 (Federated Audience Composition)
          - Data stays in BigQuery
          - Only audience membership transferred
  |
  NO --> Continue
  |
Do you want to minimize vendor lock-in (keep all logic in BigQuery)?
  |
  YES --> Use Pattern 6
          - All scoring, segmentation logic in BigQuery SQL
          - Easy to switch from AEP to alternative CDP (just change activation layer)
  |
  NO --> Continue
  |
Do you want lowest operational complexity?
  |
  YES --> Use Pattern 6
          - No custom pipelines (just SQL + UI config)
          - No API integration code to maintain
  |
  NO --> Either pattern works, choose based on cost/performance trade-offs
```

**Hybrid Approach** (Best of Both Worlds):

You can use BOTH patterns simultaneously:

```
Use Pattern 6 (Federated Audiences) for:
  - Batch campaigns (daily/weekly email, nurture sequences)
  - High-volume audiences (100K+ members, cost-sensitive)
  - Audiences that change infrequently

Use Pattern 1 (Computed Attributes) for:
  - Real-time triggers (lead score crosses threshold → immediate outreach)
  - Small, high-value audiences (VIP customers, hot leads)
  - Audiences requiring AEP AI features

Example Hybrid Architecture:

  BigQuery:
    - Compute all lead scores (Cold/Warm/Hot)
    - Store in BigQuery table

  AEP Federated Audiences:
    - "Warm Leads" (50K members) → Daily email nurture
    - "Cold Leads" (80K members) → Weekly re-engagement

  AEP Streaming Ingestion (Pattern 1):
    - "Hot Leads" (5K members) → Real-time sales alerts
    - Stream only hot lead IDs + scores to AEP
    - Trigger Journey Optimizer campaigns immediately
```

#### 2.6.8 Limitations and Trade-offs: What You Give Up

**Limitation 1: No Real-Time Streaming**

**What It Means**:
- External audiences refresh on schedule (minimum: hourly, typical: daily)
- Cannot trigger real-time journey orchestration based on BigQuery data changes
- If lead score changes in BigQuery, AEP won't know until next refresh

**Impact on Your Use Case**:
- If you need "lead becomes hot → sales alert within 1 minute": Use Pattern 1 (streaming)
- If daily activation is sufficient: Federated Audiences are fine

**Workaround**:
- Use hybrid approach: Federated for batch, Streaming API for real-time triggers

**Limitation 2: No Sub-100ms Profile Lookups**

**What It Means**:
- Cannot use federated audiences for web personalization (Adobe Target)
- BigQuery queries take 10-60 seconds, not <100ms
- Real-Time Customer Profile features don't work with external-only data

**Impact on Your Use Case**:
- You don't need web personalization (just audience activation)
- Not an issue for your use case

**Limitation 3: No AEP Identity Graph Integration**

**What It Means**:
- AEP cannot stitch identities (email ↔ cookie ↔ mobile) for external audiences
- Must pre-compute identity resolution in BigQuery

**Solution**:
```sql
-- Pre-compute identity resolution in BigQuery
CREATE TABLE customer_unified_ids AS
SELECT
  customer_id,
  email,
  ARRAY_AGG(DISTINCT cookie_id) AS cookie_ids,
  ARRAY_AGG(DISTINCT mobile_device_id) AS mobile_ids
FROM identity_mapping_table
GROUP BY customer_id, email;

-- Use deterministic customer_id in AEP queries
SELECT customer_id, email
FROM customer_unified_ids
WHERE lead_classification = 'hot';
```

**Limitation 4: No Customer AI or Attribution AI**

**What It Means**:
- Cannot use AEP's AI features on BigQuery data
- Customer AI requires data in AEP Data Lake (not external warehouse)

**Solution**:
- Use BigQuery ML or Vertex AI instead (likely better anyway)
- You already have lead scoring in BigQuery, so no loss

**Limitation 5: Query Performance Depends on BigQuery**

**What It Means**:
- Slow BigQuery queries = slow audience refreshes
- AEP has no control over query optimization

**Mitigation**:
- Partition tables by date
- Create materialized views for common queries
- Use clustering for frequently filtered columns
- Monitor BigQuery slot usage (avoid query queueing)

**Limitation 6: Refresh Frequency Limits**

**What It Means**:
- Cannot refresh audiences more frequently than hourly (practical limit)
- Daily refresh more common (cost optimization)

**Impact**:
- Audience membership can be 24 hours stale
- Fine for batch campaigns, not for real-time use cases

**Limitation 7: No Edge Segmentation**

**What It Means**:
- Cannot use external audiences for Adobe Target (Edge Decisioning)
- Edge nodes cannot query BigQuery (too slow)

**Impact on Your Use Case**:
- Not relevant (you're not doing web personalization)

#### 2.6.9 Security, Compliance, and Data Residency

**Data Residency** (KEY BENEFIT):

One of the biggest advantages of Federated Audience Composition is data sovereignty:

```
Traditional AEP Ingestion:
  - Customer data copied from GCP (e.g., europe-west1) to AEP (e.g., US East)
  - Data crosses geographic boundaries
  - GDPR risk if data leaves EU

Federated Audience Composition:
  - Customer data STAYS in BigQuery (europe-west1)
  - Only audience membership (IDs) transferred to AEP
  - IDs are not PII (customer_id ≠ email in AEP)
  - Full compliance with data residency requirements
```

**GDPR / Privacy Compliance**:

| Requirement | Traditional Ingestion | Federated Audiences |
|-------------|----------------------|---------------------|
| **Data Minimization** | Fails (copies all data) | Passes (only IDs transferred) |
| **Data Residency** | Risky (data crosses borders) | Safe (data stays in origin region) |
| **Right to Erasure** | Complex (delete from AEP + backups) | Simple (delete from BigQuery only) |
| **Data Processing Agreement** | Required (AEP = processor) | Simplified (AEP only processes IDs) |
| **Audit Trail** | AEP + BigQuery logs | BigQuery logs (full control) |

**Security Best Practices**:

1. **Least-Privilege Service Account**:
```bash
# Grant ONLY necessary permissions
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:aep-federated-access@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/bigquery.jobUser"

# Restrict to specific dataset (not entire project)
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
  --member="serviceAccount:aep-federated-access@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/bigquery.dataViewer" \
  --condition='expression=resource.name.startsWith("projects/YOUR_PROJECT_ID/datasets/customer_profiles"),title=AEP_Access_Restricted'
```

2. **VPC Service Controls** (for highly sensitive data):
```bash
# Create service perimeter to restrict BigQuery access
gcloud access-context-manager perimeters create aep_access_perimeter \
  --title="AEP Federated Access Perimeter" \
  --resources="projects/YOUR_PROJECT_NUMBER" \
  --restricted-services="bigquery.googleapis.com" \
  --ingress-policies=aep_ingress_policy.yaml
```

3. **Audit Logging**:
```sql
-- Monitor all AEP queries in BigQuery
SELECT
  principal_email,
  resource_name,
  method_name,
  request_metadata.caller_ip,
  timestamp
FROM `your-project.region-us.cloudaudit_googleapis_com_data_access`
WHERE principal_email = 'aep-federated-access@YOUR_PROJECT_ID.iam.gserviceaccount.com'
  AND timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
ORDER BY timestamp DESC;
```

4. **Row-Level Security** (for multi-tenant data):
```sql
-- Restrict AEP to specific customer segments
CREATE ROW ACCESS POLICY aep_access_policy
ON `your-project.customer_profiles.leads_classified`
GRANT TO ('serviceAccount:aep-federated-access@YOUR_PROJECT_ID.iam.gserviceaccount.com')
FILTER USING (customer_segment = 'marketing_approved');
```

5. **Key Rotation**:
```bash
# Rotate service account keys quarterly
gcloud iam service-accounts keys create new-key.json \
  --iam-account=aep-federated-access@YOUR_PROJECT_ID.iam.gserviceaccount.com

# Update key in AEP UI

# Revoke old key
gcloud iam service-accounts keys delete OLD_KEY_ID \
  --iam-account=aep-federated-access@YOUR_PROJECT_ID.iam.gserviceaccount.com
```

**Compliance Advantages for Regulated Industries**:

| Industry | Regulation | Federated Audience Benefit |
|----------|-----------|---------------------------|
| **Healthcare** | HIPAA | PHI stays in GCP (HIPAA-compliant environment), only de-identified IDs in AEP |
| **Finance** | PCI-DSS | Payment data stays in BigQuery, only customer IDs activated |
| **EU Companies** | GDPR | Customer data stays in EU region (BigQuery europe-west1), only IDs to AEP |
| **Government** | FedRAMP | Sensitive data in FedRAMP-authorized GCP, only metadata in AEP |

#### 2.6.10 Cost Analysis: Federated vs Traditional Ingestion

**BigQuery Query Costs** (Your Use Case):

Assumptions:
- 100K leads in BigQuery table
- 3 audiences refreshed daily
- Table size: 500 MB (partitioned by date, clustered by lead_classification)

```sql
-- Cost calculation for typical federated query
-- Query: SELECT customer_id, email FROM leads WHERE lead_classification = 'hot'

Scenario 1: No Optimization (full table scan)
  - Bytes processed: 500 MB
  - BigQuery cost: $0.0025 per MB
  - Cost per query: $1.25
  - Daily cost (3 queries): $3.75
  - Monthly cost: $112.50
  - Annual cost: $1,350

Scenario 2: With Partitioning + Clustering (recommended)
  - Bytes processed: 50 MB (10x reduction via clustering)
  - Cost per query: $0.125
  - Daily cost (3 queries): $0.375
  - Monthly cost: $11.25
  - Annual cost: $135

Scenario 3: Using Materialized Views (best optimization)
  - Bytes processed: 5 MB (materialized view is pre-computed)
  - Cost per query: $0.0125
  - Daily cost (3 queries): $0.0375
  - Monthly cost: $1.13
  - Annual cost: $13.56
```

**Total Cost of Ownership Comparison**:

| Cost Category | Pattern 1: Computed Attributes | Pattern 6: Federated Audiences (Optimized) |
|---------------|-------------------------------|-------------------------------------------|
| **AEP Licensing** | $70,000 - $120,000/year | $40,000 - $80,000/year |
| **AEP Profile Storage** | $10,000 - $20,000/year | $500/year (metadata only) |
| **AEP Query Service** | $0 (not used) | $0 (not used) |
| **GCP Egress (data transfer out)** | $2,000 - $5,000/year | $50/year |
| **BigQuery Storage** | $1,000/year (500 MB × 12 months) | $1,000/year |
| **BigQuery Compute** | $5,000/year (scoring pipelines) | $5,000/year (scoring) + $135/year (AEP queries) |
| **Engineering Effort** | $30,000/year (maintain pipelines) | $10,000/year (maintain SQL queries) |
| **Total Annual Cost** | $118,000 - $180,000 | $56,685 - $96,685 |
| **Savings vs Pattern 1** | Baseline | 52% - 46% |

**Break-Even Analysis**:

```
When does Federated Audience Composition become more expensive?

Variables:
- Query frequency (hourly vs daily)
- Table size (impacts bytes scanned)
- Number of audiences

Tipping Point:
  If you have 50+ audiences refreshing hourly:
    - BigQuery query costs: $50K+/year
    - May exceed AEP profile storage costs
    - Consider: Materialized views, query optimization, or hybrid approach

For typical use cases (3-10 audiences, daily refresh):
  - Federated Audiences = 50% cheaper than full ingestion
```

**Cost Optimization Strategies**:

1. **Use Materialized Views**:
```sql
-- Pre-compute common audience queries
CREATE MATERIALIZED VIEW hot_leads_mv AS
SELECT customer_id, email, propensity_score
FROM leads_classified
WHERE lead_classification = 'hot';

-- AEP queries materialized view (cheaper + faster)
SELECT customer_id, email FROM hot_leads_mv;
```

2. **Partition and Cluster Tables**:
```sql
-- Reduce bytes scanned by 10-100x
CREATE TABLE leads_classified
PARTITION BY DATE(last_scored_at)
CLUSTER BY lead_classification, product_interest
AS SELECT * FROM source_table;
```

3. **Schedule Queries During Off-Peak** (if using BigQuery flat-rate pricing):
```
Flat-rate pricing: $2,000/month for 100 slots
  - Run AEP queries during off-peak hours
  - Avoid slot contention with production workloads
  - Marginal cost = $0 (already paying for slots)
```

4. **Use BigQuery BI Engine** (for sub-second queries):
```
BI Engine: In-memory caching for frequently queried data
  - Cost: $0.06 per GB per hour
  - For 500 MB table: ~$20/month
  - Queries run in <1 second (vs 10-60 seconds)
  - Useful if hourly refresh needed
```

#### 2.6.11 Implementation Roadmap: Getting Started

**Phase 1: Proof of Concept (Weeks 1-2)**

Goal: Validate Federated Audience Composition with single audience

**Week 1: Setup and Configuration**
```
Day 1-2: GCP Setup
  - Create service account for AEP
  - Grant BigQuery permissions (jobUser, dataViewer)
  - Generate JSON key file
  - Test query: SELECT 1 FROM leads_table LIMIT 1

Day 3-4: AEP Configuration
  - Navigate to Destinations > Federated Audience Composition
  - Configure BigQuery connection
  - Upload service account key
  - Test connection

Day 5: Create Test Audience
  - Create simple audience: "Hot Leads"
  - Query: SELECT customer_id, email FROM leads WHERE lead_classification = 'hot'
  - Preview results (validate data)
  - Save audience (don't activate yet)
```

**Week 2: Validation and Testing**
```
Day 1-2: Audience Refresh Testing
  - Configure daily refresh schedule
  - Update BigQuery data (change lead classifications)
  - Wait for refresh
  - Validate audience membership updated in AEP

Day 3: Activation Testing
  - Activate test audience to non-production destination (e.g., test email list)
  - Validate customer IDs received by destination
  - Check data quality (no duplicates, correct IDs)

Day 4-5: Cost and Performance Monitoring
  - Review BigQuery audit logs (query costs)
  - Measure query latency (10s, 60s, or more?)
  - Identify optimization opportunities (partitioning, materialized views)

POC Success Criteria:
  ✓ Audience creates successfully
  ✓ Refresh completes within SLA (< 5 minutes)
  ✓ BigQuery query cost < $1 per refresh
  ✓ Activation to destination works
```

**Phase 2: Production Rollout (Weeks 3-6)**

**Week 3: Optimize BigQuery Tables**
```
Tasks:
  - Implement partitioning by last_scored_at
  - Add clustering on lead_classification, product_interest
  - Create materialized views for common audiences
  - Test query performance (target: <30 seconds)
```

**Week 4: Create Production Audiences**
```
Audiences to Create:
  1. "Hot Leads - Sales Outreach" (daily refresh)
  2. "Warm Tech Leads - Product Webinar" (weekly refresh)
  3. "Cold Leads - 90 Day Nurture" (monthly refresh)
  4. "High Propensity - Upsell Campaign" (daily refresh)
  5. "Churn Risk - Retention Campaign" (weekly refresh)

For Each Audience:
  - Define BigQuery query (SQL)
  - Test query in BigQuery Console (validate results + costs)
  - Create in AEP Federated Audience Composition UI
  - Configure refresh schedule
  - Validate preview results
```

**Week 5: Destination Activation**
```
Destinations:
  - Marketo: Hot Leads, Warm Tech Leads
  - Google Ads Customer Match: High Propensity
  - Email ESP: Cold Leads, Churn Risk
  - Salesforce: Hot Leads (create tasks for sales reps)

Activation Checklist per Destination:
  ✓ Map customer_id to destination identifier
  ✓ Configure activation frequency (daily, weekly)
  ✓ Test with small audience (100 members)
  ✓ Validate data quality in destination
  ✓ Enable for production audiences
```

**Week 6: Monitoring and Optimization**
```
Setup:
  - BigQuery audit log dashboard (query costs, latency)
  - AEP audience refresh monitoring (success rate, latency)
  - Destination activation monitoring (delivery rate, errors)

Optimization:
  - Review query costs (target: <$500/month)
  - Identify slow queries (>60 seconds) → optimize
  - Consolidate audiences if possible (reduce query count)
```

**Phase 3: Scale and Enhance (Weeks 7-12)**

**Week 7-8: Add Complex Audiences**
```
Examples:
  - Multi-table joins (leads × product_interactions × account_details)
  - Aggregations (customers with >5 interactions in 30 days)
  - Time-series (propensity score increasing over time)
```

**Week 9-10: Hybrid Approach (if needed)**
```
Identify real-time requirements:
  - If specific audiences need <1 minute latency:
    → Implement Pattern 1 (Streaming API) for those audiences
  - Keep batch audiences in Federated Audience Composition
```

**Week 11-12: Documentation and Handoff**
```
Deliverables:
  - Audience catalog (list of all audiences, queries, refresh schedules)
  - BigQuery table schema documentation
  - Service account permissions audit
  - Runbook for common tasks (create audience, update query, troubleshoot refresh failure)
  - Cost monitoring dashboard
```

**Success Metrics**:

| Metric | Target | Measurement Method |
|--------|--------|-------------------|
| **Data Transfer Reduction** | >99% vs full ingestion | AEP data usage reports |
| **Query Cost** | <$500/month | BigQuery billing |
| **Audience Refresh Latency** | <5 minutes | AEP audience logs |
| **Activation Delivery Rate** | >98% | Destination dashboards |
| **Engineering Time** | <10 hours/month | Time tracking |

#### 2.6.12 Key Takeaways: Federated Audience Composition

**What You Need to Know**:

1. **TRUE Zero-Copy is NOW Possible with AEP** (for audience creation use cases)
   - Data stays in BigQuery
   - Only audience membership transferred to AEP
   - 99.96% data transfer reduction vs full ingestion

2. **This is a Game-Changer for Your Use Case**:
   - Cold/Warm/Hot lead scoring stays in BigQuery (SQL + BigQuery ML)
   - AEP queries BigQuery to build audiences
   - Activate to Marketo, Google Ads without copying 100K profiles

3. **Limitations to Understand**:
   - NOT for real-time use cases (batch refresh only, hourly minimum)
   - NOT for web personalization (no <100ms profile lookups)
   - NOT compatible with Customer AI (requires data in AEP Data Lake)
   - Identity stitching must be pre-computed in BigQuery

4. **When to Use Federated Audiences**:
   - Batch audience activation (daily/weekly campaigns)
   - Data sovereignty requirements (data cannot leave GCP)
   - Cost optimization (50% cheaper than full ingestion)
   - Minimize vendor lock-in (logic stays in BigQuery SQL)

5. **When to Use Pattern 1 (Computed Attributes) Instead**:
   - Real-time triggers (lead score changes → immediate action)
   - Need AEP AI features (Customer AI, Attribution AI)
   - Need identity stitching (AEP Identity Graph)
   - Need web personalization (Adobe Target)

6. **Hybrid Approach is Often Best**:
   - Use Federated Audiences for bulk batch campaigns (99% of use cases)
   - Use Pattern 1 (Streaming API) for critical real-time triggers (1% of use cases)
   - Example: Federated for "Warm Leads Nurture", Streaming for "Hot Lead Alert"

7. **Cost Impact**:
   - 50% reduction in total cost vs Pattern 1
   - AEP licensing lower (no profile storage)
   - BigQuery query costs: $135-$1,350/year (highly dependent on optimization)
   - Optimization is critical: Use partitioning, clustering, materialized views

8. **Security and Compliance Benefits**:
   - Data residency: Data stays in GCP region
   - GDPR compliance: Data minimization principle satisfied
   - Audit trail: BigQuery logs all AEP queries
   - Right to erasure: Delete from BigQuery only (AEP only has IDs)

9. **Implementation Complexity**:
   - MUCH simpler than Pattern 1 (no custom pipelines, no API code)
   - UI-driven configuration in AEP
   - SQL queries (familiar to data teams)
   - 2 weeks POC, 6 weeks production rollout

10. **This Should Be Your PRIMARY Approach**:
    - For your BigQuery + Cold/Warm/Hot lead use case
    - Federated Audience Composition is the perfect fit
    - Start here, add Pattern 1 only if real-time requirements emerge

**Honest Assessment**:

Adobe has FINALLY addressed the zero-copy gap. Federated Audience Composition is not perfect (batch-only, no real-time), but for 80% of audience activation use cases, it's exactly what customers have been asking for.

**Your Action Plan**:

1. **Prioritize Federated Audience Composition** as your primary integration pattern
2. Use Pattern 1 (Computed Attributes) only for edge cases requiring real-time
3. Negotiate AEP pricing based on NO profile storage costs (leverage this in contract discussions)
4. Start with 2-week POC to validate performance and costs
5. Scale to production with confidence (this is the right approach for your use case)

---

## 3. GCP-to-AEP Integration Patterns

### 3.1 Integration Method Comparison

| Method | Latency | Cost (AEP) | Cost (GCP) | Complexity | Use Case |
|--------|---------|------------|------------|------------|----------|
| **Streaming HTTP API** | 5-15 seconds | High ($) | Low | Low | Real-time events, immediate segmentation |
| **Batch API (GCS -> AEP)** | Hours | Low | Low | Medium | Daily/weekly profile updates |
| **AEP Source Connector (BigQuery)** | Hours | Medium | Medium | Low | Initial profile load, periodic sync |
| **Cloud Functions + Pub/Sub** | 5-30 seconds | High ($) | Low | Medium | Event-driven updates |
| **Dataflow Streaming** | 10-60 seconds | High ($) | High ($$) | High | Complex transformations at scale |
| **Dataflow Batch** | Hours | Low | Medium | Medium | ETL with aggregations |

### 3.2 Recommended Integration Architecture for Your Use Case

```
GCP Architecture:

  1. Data Sources:
     - Web analytics (GA4) --> BigQuery (streaming)
     - CRM (Salesforce) --> Cloud SQL
     - Mobile app events --> Firebase --> BigQuery
     - Operational systems --> Cloud Spanner

  2. Unified Customer Profile (GCP):
     BigQuery:
       - Table: customer_master_profile (source of truth)
       - Table: behavioral_events (raw events)
       - Table: computed_lead_scores (daily refresh)

  3. Scoring Pipeline:
     Cloud Composer (Airflow):
       - DAG: daily_lead_scoring
       - Tasks:
         a. Aggregate events from last 30 days
         b. Run BigQuery ML model prediction
         c. Classify leads (cold/warm/hot)
         d. Write to computed_lead_scores table

  4. AEP Integration Layer:

     Option A - Batch (Daily):
       Dataflow Job (scheduled):
         - Read: computed_lead_scores WHERE updated_today = true
         - Transform: Convert to AEP XDM format
         - Write: AEP Batch Ingestion API (via GCS staging)

     Option B - Streaming (Real-time events):
       Cloud Function (triggered by Pub/Sub):
         - Filter: Only critical events (inquiries, callback requests)
         - Transform: Convert to AEP ExperienceEvent schema
         - Send: AEP Streaming HTTP API

  5. AEP Configuration:

     Real-Time Customer Profile:
       - Schema: Minimal Lead Profile (5-7 fields)
       - Datasets:
         a. Profile dataset (batch ingestion)
         b. Critical events dataset (streaming)
       - Identity: Email (primary), gcpCustomerId (cross-reference)

     Segments:
       - "Hot Leads": WHERE leadClassification = "hot"
       - "Warm Leads - High Propensity": WHERE leadClassification = "warm" AND propensityScore > 0.6
       - "Cold Leads - Recent Interaction": WHERE leadClassification = "cold" AND lastInteractionTimestamp > now() - 7 days

     Destinations:
       - Marketo (for nurture campaigns)
       - Google Ads (for retargeting)
       - Salesforce (for sales team routing)

  6. Activation Flow:
     AEP Segment Membership Change
       --> Destination (Marketo/Google Ads)
       --> (Optional) Webhook to GCP Cloud Function for enrichment
```

### 3.3 API vs SDK vs Connectors Decision Tree

**Use AEP Streaming HTTP API when**:
- Real-time events (latency < 30 seconds required)
- Custom transformation logic in GCP (Cloud Functions)
- Event volume < 10K events/second
- Direct control over payload format

**Use AEP Batch Ingestion API when**:
- Daily/weekly profile updates
- Large volume updates (millions of profiles)
- Cost optimization is priority
- Acceptable latency (hours)

**Use AEP Source Connector (BigQuery) when**:
- Initial profile load (one-time migration)
- Simple schema mapping (no complex transformations)
- You want AEP to manage ingestion scheduling
- You're okay with AEP reading from BigQuery (data egress costs)

**Avoid AEP SDK (Web/Mobile) when**:
- You already have event collection (GA4, Firebase)
- You don't need AEP's edge personalization
- Reduces vendor lock-in (SDK ties you to AEP's client-side architecture)

### 3.4 Data Residency and Compliance

**AEP Data Residency**:
- AEP data stored in Adobe-managed Azure regions (US, EU, APAC)
- **Critical**: Data leaves GCP, crosses cloud boundaries
- GDPR: Ensure Data Processing Agreement (DPA) with Adobe
- CCPA: AEP supports consumer deletion requests via API

**GCP-to-AEP Data Flow**:
```
GCP (Google Cloud Data Centers)
  |
  | HTTPS/TLS 1.3
  V
Adobe Experience Cloud (Azure-hosted)
  - US: Virginia (AWS East)
  - EU: Netherlands (Azure West Europe)
  - APAC: Australia (Azure Australia East)
```

**Minimizing Cross-Cloud Data Transfer**:
1. **Egress Costs**: GCP charges for data leaving GCP
   - Batch ingestion: Lower egress (fewer, larger transfers)
   - Streaming: Higher egress (many small transfers)
   - Cost: ~$0.12/GB egress from GCP to internet

2. **Compliance Strategy**:
   - Store PII in GCP (encrypted at rest)
   - Send only pseudonymized IDs + computed attributes to AEP
   - Example: Don't send `firstName`, `lastName`, `personalID` to AEP
   - Send: `hashedEmail`, `leadClassification`, `propensityScore`

---

## 4. Cold/Warm/Hot Lead Classification: Implementation Strategy

### 4.1 Recommended Architecture for Your Use Case

**Option 1: GCP-Computed Classification (RECOMMENDED)**

#### Why This Approach
- Your classification logic involves complex rules (account manager interactions, business activity patterns, engagement history)
- Changes frequently (business rules evolve)
- Requires explainability (sales teams need to understand why a lead is "hot")
- Leverages GCP's compute capabilities (BigQuery ML, complex joins)

#### Implementation

**Step 1: Define Classification Logic in BigQuery**

```sql
-- File: lead_classification_query.sql
-- Run daily in Cloud Composer

CREATE OR REPLACE TABLE `project.dataset.computed_lead_scores` AS
WITH
  -- Engagement metrics
  engagement AS (
    SELECT
      customer_id,
      COUNT(DISTINCT DATE(event_timestamp)) AS days_active_last_30d,
      SUM(CASE WHEN event_type = 'product_detail_view' THEN 1 ELSE 0 END) AS product_views,
      SUM(CASE WHEN event_type = 'webinar_registration' THEN 1 ELSE 0 END) AS webinar_registrations,
      MAX(event_timestamp) AS last_interaction_timestamp
    FROM `project.dataset.behavioral_events`
    WHERE event_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
    GROUP BY customer_id
  ),

  -- Account manager interactions
  am_interactions AS (
    SELECT
      customer_id,
      COUNT(*) AS am_touchpoints_last_90d,
      MAX(interaction_date) AS last_am_contact
    FROM `project.crm.account_manager_log`
    WHERE interaction_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
    GROUP BY customer_id
  ),

  -- Business activity patterns
  activities AS (
    SELECT
      customer_id,
      SUM(activity_value) AS total_activity_value_last_90d,
      AVG(activity_value) AS avg_activity_value,
      COUNT(*) AS activity_count
    FROM `project.business.activities`
    WHERE activity_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
    GROUP BY customer_id
  ),

  -- Propensity model prediction
  ml_predictions AS (
    SELECT
      customer_id,
      predicted_conversion_probability
    FROM ML.PREDICT(
      MODEL `project.dataset.lead_propensity_model`,
      (SELECT * FROM `project.dataset.customer_features`)
    )
  )

-- Classification logic
SELECT
  c.customer_id,
  c.email,
  c.account_manager_id,

  -- Raw metrics (for debugging/analysis, not sent to AEP)
  COALESCE(e.days_active_last_30d, 0) AS engagement_days,
  COALESCE(e.product_views, 0) AS product_views,
  COALESCE(am.am_touchpoints_last_90d, 0) AS am_touchpoints,
  COALESCE(a.total_activity_value_last_90d, 0) AS activity_value,
  COALESCE(ml.predicted_conversion_probability, 0.0) AS propensity_score,

  -- Computed classification (THIS is what gets sent to AEP)
  CASE
    -- HOT LEAD: High propensity + recent activity + explicit intent signals
    WHEN ml.predicted_conversion_probability > 0.7
         AND e.last_interaction_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
         AND (e.webinar_registrations > 0 OR am.am_touchpoints_last_90d > 2)
    THEN 'hot'

    -- WARM LEAD: Moderate propensity OR growing engagement
    WHEN ml.predicted_conversion_probability > 0.4
         OR (e.days_active_last_30d >= 3 AND e.product_views >= 5)
         OR (a.activity_count > 0 AND a.total_activity_value_last_90d > 10000)
    THEN 'warm'

    -- COLD LEAD: Low propensity and minimal engagement
    ELSE 'cold'
  END AS lead_classification,

  -- Engagement index (0-100 score, useful for sub-segmentation)
  CAST(
    LEAST(100,
      (COALESCE(e.days_active_last_30d, 0) * 2) +
      (COALESCE(e.product_views, 0) * 1) +
      (COALESCE(am.am_touchpoints_last_90d, 0) * 5) +
      (COALESCE(ml.predicted_conversion_probability, 0) * 50)
    ) AS INT64
  ) AS engagement_index,

  -- Primary product interest (derived from recent behavior)
  (
    SELECT product_category
    FROM `project.dataset.behavioral_events`
    WHERE customer_id = c.customer_id
      AND event_type = 'product_detail_view'
      AND event_timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
    GROUP BY product_category
    ORDER BY COUNT(*) DESC
    LIMIT 1
  ) AS primary_product_interest,

  CURRENT_TIMESTAMP() AS computed_at

FROM `project.dataset.customer_master_profile` c
LEFT JOIN engagement e ON c.customer_id = e.customer_id
LEFT JOIN am_interactions am ON c.customer_id = am.customer_id
LEFT JOIN activities a ON c.customer_id = a.customer_id
LEFT JOIN ml_predictions ml ON c.customer_id = ml.customer_id
WHERE c.is_active = true;
```

**Step 2: Orchestrate Daily Scoring (Cloud Composer DAG)**

```python
# File: dags/lead_scoring_to_aep_dag.py

from airflow import DAG
from airflow.providers.google.cloud.operators.bigquery import BigQueryInsertJobOperator
from airflow.providers.google.cloud.transfers.bigquery_to_gcs import BigQueryToGCSOperator
from airflow.providers.http.operators.http import SimpleHttpOperator
from datetime import datetime, timedelta

default_args = {
    'owner': 'data-team',
    'depends_on_past': False,
    'start_date': datetime(2024, 1, 1),
    'email_on_failure': True,
    'email': ['alerts@company.com'],
    'retries': 2,
    'retry_delay': timedelta(minutes=5),
}

dag = DAG(
    'lead_scoring_to_aep',
    default_args=default_args,
    description='Compute lead scores in BigQuery and sync to AEP',
    schedule_interval='0 2 * * *',  # 2 AM daily
    catchup=False,
)

# Task 1: Refresh BigQuery ML model (weekly)
refresh_ml_model = BigQueryInsertJobOperator(
    task_id='refresh_ml_model',
    configuration={
        "query": {
            "query": "CALL `project.dataset.refresh_lead_propensity_model`()",
            "useLegacySql": False,
        }
    },
    dag=dag,
)

# Task 2: Compute lead classifications
compute_lead_scores = BigQueryInsertJobOperator(
    task_id='compute_lead_scores',
    configuration={
        "query": {
            "query": "{% include 'sql/lead_classification_query.sql' %}",
            "useLegacySql": False,
        }
    },
    dag=dag,
)

# Task 3: Export to GCS (for AEP Batch Ingestion)
export_to_gcs = BigQueryToGCSOperator(
    task_id='export_to_gcs',
    source_project_dataset_table='project.dataset.computed_lead_scores',
    destination_cloud_storage_uris=['gs://aep-ingestion-bucket/lead-scores/{{ ds }}/data-*.json'],
    export_format='NEWLINE_DELIMITED_JSON',
    dag=dag,
)

# Task 4: Trigger AEP Batch Ingestion
# (Alternative: Use Dataflow for transformation + direct AEP API calls)
trigger_aep_ingestion = SimpleHttpOperator(
    task_id='trigger_aep_batch_ingestion',
    method='POST',
    http_conn_id='aep_http',  # Configure in Airflow connections
    endpoint='/data/foundation/import/batches',
    headers={
        'Authorization': 'Bearer {{ var.value.aep_access_token }}',
        'x-api-key': '{{ var.value.aep_api_key }}',
        'x-gw-ims-org-id': '{{ var.value.aep_ims_org }}'
    },
    data='''
    {
      "datasetId": "{{ var.value.aep_profile_dataset_id }}",
      "inputFormat": {
        "format": "json"
      },
      "files": {
        "cloudStorageUri": "gs://aep-ingestion-bucket/lead-scores/{{ ds }}/"
      }
    }
    ''',
    dag=dag,
)

# Task dependencies
refresh_ml_model >> compute_lead_scores >> export_to_gcs >> trigger_aep_ingestion
```

**Step 3: Transform to AEP XDM Format (Dataflow)**

```python
# File: dataflow_jobs/bq_to_aep_transform.py

import apache_beam as beam
from apache_beam.options.pipeline_options import PipelineOptions
import json

class TransformToAEPXDM(beam.DoFn):
    """
    Transform BigQuery row to AEP XDM Profile format.
    """
    def process(self, element):
        # element is a BigQuery row (dict)
        xdm_profile = {
            "_id": element['customer_id'],
            "identityMap": {
                "email": [
                    {
                        "id": element['email'],
                        "primary": True
                    }
                ],
                "gcpCustomerId": [
                    {
                        "id": element['customer_id'],
                        "primary": False
                    }
                ]
            },
            "leadClassification": element['lead_classification'],
            "propensityScore": float(element['propensity_score']),
            "engagementIndex": int(element['engagement_index']),
            "primaryProductInterest": element.get('primary_product_interest', 'unknown'),
            "accountManagerId": element.get('account_manager_id', ''),
            "lastComputedTimestamp": element['computed_at'].isoformat()
        }

        # Wrap in AEP Batch format
        aep_batch_record = {
            "header": {
                "schemaRef": {
                    "id": "https://ns.adobe.com/{TENANT}/schemas/{SCHEMA_ID}",
                    "contentType": "application/vnd.adobe.xed-full+json;version=1"
                },
                "imsOrgId": "{IMS_ORG_ID}",
                "datasetId": "{DATASET_ID}",
                "source": {
                    "name": "GCP Lead Scoring Pipeline"
                }
            },
            "body": {
                "xdmMeta": {
                    "schemaRef": {
                        "id": "https://ns.adobe.com/{TENANT}/schemas/{SCHEMA_ID}",
                        "contentType": "application/vnd.adobe.xed-full+json;version=1"
                    }
                },
                "xdmEntity": xdm_profile
            }
        }

        yield json.dumps(aep_batch_record)

def run_pipeline():
    pipeline_options = PipelineOptions(
        runner='DataflowRunner',
        project='your-gcp-project',
        region='us-central1',
        temp_location='gs://your-temp-bucket/temp',
        staging_location='gs://your-temp-bucket/staging'
    )

    with beam.Pipeline(options=pipeline_options) as pipeline:
        (pipeline
         | 'Read from BigQuery' >> beam.io.ReadFromBigQuery(
             table='project.dataset.computed_lead_scores',
             use_standard_sql=True)
         | 'Transform to AEP XDM' >> beam.ParDo(TransformToAEPXDM())
         | 'Write to GCS for AEP' >> beam.io.WriteToText(
             'gs://aep-ingestion-bucket/lead-scores-xdm/data',
             file_name_suffix='.json')
        )

if __name__ == '__main__':
    run_pipeline()
```

**Step 4: AEP Segment Configuration**

In AEP UI (or via Segment API):

```
Segment: "Hot Leads - Immediate Follow-up"
Definition:
  Profile.leadClassification = "hot"
  AND Profile.lastComputedTimestamp >= now() - 1 day

Segment: "Warm Leads - High Propensity"
Definition:
  Profile.leadClassification = "warm"
  AND Profile.propensityScore > 0.6

Segment: "Cold Leads - Re-engagement Campaign"
Definition:
  Profile.leadClassification = "cold"
  AND Profile.engagementIndex < 20
  AND Profile.lastComputedTimestamp >= now() - 7 days
```

**Data Transfer Summary**:
- **BigQuery -> GCS**: Full computed_lead_scores table (~1-5 MB for 10K customers)
- **GCS -> AEP**: Only XDM-formatted profiles (~2-3 KB per profile)
- **Daily Transfer**: ~20-30 MB for 10K customers
- **Frequency**: Once daily (not continuous replication)

---

**Option 2: AEP Customer AI (Alternative, NOT RECOMMENDED for your use case)**

**Why NOT Recommended**:
- Requires 12+ months of historical data in AEP (you'd need to backfill)
- Black box model (no control over classification logic)
- Expensive (Customer AI is a premium add-on)
- Less flexible (can't easily incorporate account manager interaction data)
- Vendor lock-in (scoring logic tied to AEP)

**When Customer AI Makes Sense**:
- You don't have data science capabilities
- You want Adobe to manage model training/maintenance
- Your use case is standard (churn, conversion propensity)
- You're already storing all behavioral data in AEP

**Implementation (if forced to use Customer AI)**:

```
1. Ingest 12 months of behavioral events to AEP (LARGE data transfer)
2. Configure Customer AI:
   - Goal: Predict "product_inquiry" event within 30 days
   - Influencing factors: web interactions, email engagement
3. Wait 24-48 hours for model training
4. Use AI-generated propensity scores in segments:
   Segment: Profile.customerAI.propensityScore > 0.7
```

**Cost**: Customer AI licensing (~$50K-$100K+ annually depending on profile volume)

---

### 4.2 Real-Time vs Batch Scoring Trade-offs

| Approach | Latency | Cost | Accuracy | Complexity | Best For |
|----------|---------|------|----------|------------|----------|
| **Batch (Daily)** | 24 hours | Low | High (full data) | Low | Lead nurturing, campaign planning |
| **Streaming (Real-time)** | <1 minute | High | Medium (recent data only) | High | Immediate follow-up, live chat routing |
| **Micro-batch (Hourly)** | 1 hour | Medium | High | Medium | Balance of cost and timeliness |
| **Hybrid (Batch + Trigger)** | 24h base + <1m for triggers | Medium | High | Medium | **RECOMMENDED** for your use case |

**Recommended: Hybrid Approach**

```
Batch (Daily):
  - Compute lead classification for ALL customers
  - Update AEP profiles once per day
  - Used for: Email campaigns, sales prioritization

Real-time Triggers (Event-driven):
  - Monitor for high-intent events:
    * Callback request submitted
    * Webinar registration
    * Service inquiry started
  - Immediately update lead classification to "hot"
  - Trigger: AEP destination (Salesforce alert to account manager)

Implementation:
  Cloud Function (Pub/Sub trigger):
    IF event_type IN ('callback_request', 'webinar_registration'):
      1. Stream event to AEP (real-time)
      2. Override lead_classification to "hot" (temporary)
      3. Next daily batch will recompute (permanent classification)
```

---

## 5. Honest Assessment: When AEP is (and isn't) the Right Choice

### 5.1 For Your Use Case (Lead Classification + Activation)

**AEP is a GOOD fit if**:
- You need to activate segments to multiple destinations (Marketo, Google Ads, Salesforce)
- You want Adobe-managed destination connectors (avoid building custom integrations)
- You're using other Adobe tools (Adobe Analytics, Target, Campaign) and want unified identity
- Your organization has already licensed AEP (sunk cost)

**AEP is a POOR fit if**:
- Your primary goal is lead scoring (GCP tools are more flexible and cost-effective)
- You need real-time scoring (AEP adds latency; direct GCP-to-destination is faster)
- You want to avoid vendor lock-in (AEP's proprietary XDM schema is hard to migrate from)
- Budget-constrained (AEP licensing is expensive; consider alternatives below)

### 5.2 Alternative Architectures to Consider

#### Alternative 1: GCP-Native (No AEP)

```
BigQuery (Scoring)
  --> Cloud Composer (Orchestration)
  --> Destinations (Direct API integrations):
      - Marketo API (lead scoring)
      - Google Ads Customer Match API
      - Salesforce Bulk API

Pros:
  - No AEP licensing costs
  - Full control over data and logic
  - No vendor lock-in
  - Lower latency (fewer hops)

Cons:
  - Build and maintain destination integrations
  - No unified identity resolution (unless you build it)
  - Requires engineering resources
```

**Cost Comparison** (10K profiles, monthly):
- AEP: $10K-$50K/month (licensing + compute)
- GCP-native: $500-$2K/month (BigQuery + Dataflow + Cloud Functions)

**Recommendation**: If you have engineering capacity, GCP-native is more cost-effective for lead scoring.

---

#### Alternative 2: Segment (CDP Alternative)

```
GCP BigQuery
  --> Segment Profiles API (sync computed scores)
  --> Segment Destinations (200+ pre-built integrations)

Pros:
  - Lighter than AEP (designed for data routing, not storage)
  - Faster implementation (no XDM schema design)
  - More flexible (supports custom traits)
  - Lower cost (~$5K-$20K/month vs $50K+ for AEP)

Cons:
  - Less sophisticated identity resolution than AEP
  - No built-in AI/ML (like Customer AI)
  - Limited Adobe ecosystem integration
```

**When to Use Segment Instead of AEP**:
- You don't need AEP's AI features (Customer AI, Attribution AI)
- You prioritize speed to market over advanced capabilities
- You want to avoid Adobe ecosystem lock-in
- Your use case is primarily "route data to destinations" (not profile unification)

---

#### Alternative 3: Hybrid (GCP + Lightweight CDP)

```
GCP BigQuery (Master Profile Store)
  |
  +-- Lead Scoring (Batch)
  |     --> mParticle / Segment (just for activation)
  |
  +-- Real-time Events
        --> Google Analytics 4
        --> Firebase (mobile)
        --> Direct to Google Ads API

Philosophy:
  - GCP = Source of truth (profile data, scoring logic)
  - CDP = Thin activation layer (routing scores to destinations)
  - No unnecessary data replication
```

**Data Minimization**:
- CDP stores: customer_id + lead_classification + propensity_score (3 fields)
- GCP stores: Full profile (100+ fields)
- Updates: Only when classification changes (not every event)

---

### 5.3 AEP Limitations You Must Understand

#### 5.3.1 Identity Resolution Limitations

**Identity Graph Limits**:
- Max 50 identities per person (email, phone, cookie IDs, etc.)
- Performance degrades above 20 identities per profile
- Cross-device stitching requires Adobe Analytics or third-party data (Liveramp)

**Impact**: If your customers have many devices/touchpoints, identity graph may be incomplete.

**Workaround**: Perform identity resolution in GCP (Dataflow + BigQuery), send stitched ID to AEP.

---

#### 5.3.2 Segmentation Latency

**Streaming Segmentation**:
- Evaluated in <1 minute (for qualifying events)
- **BUT**: Only ~20-30 attributes supported for streaming evaluation
- Complex segments (multi-entity, historical lookups) fall back to batch

**Batch Segmentation**:
- Evaluated every 24 hours (not configurable to more frequent)
- Can include full profile history and complex joins

**Impact**: "Hot lead" classification computed daily won't update in AEP until next batch run.

**Workaround**: Use streaming ingestion to override classification for critical events (see hybrid approach above).

---

#### 5.3.3 Query Service Performance

**Limitations**:
- 10-minute query timeout
- Limited compute resources (not designed for heavy analytics)
- Expensive ($$$) compared to BigQuery

**Impact**: Complex lead scoring queries may time out in Query Service.

**Recommendation**: Do NOT run ML or complex aggregations in AEP Query Service. Use BigQuery, send results to AEP.

---

#### 5.3.4 API Rate Limits

**Streaming Ingestion**:
- 20,000 requests/second per organization (seems high, but...)
- Throttling at 100 profiles/request recommended (20K profiles/sec max)
- **Real limit**: Concurrent connection limits (often hit before rate limit)

**Batch Ingestion**:
- No strict rate limit (file size limits: 512 MB per file)
- Processed asynchronously (1-2 hours typical)

**Impact**: Real-time event streaming at scale requires careful architecture (batching, retry logic).

---

#### 5.3.5 Cost Opacity

**AEP Pricing Model** (as of 2024):
- **Licensing**: Per "addressable profile" (profiles eligible for activation)
  - Tier 1: $10K-$50K/month (up to 100K profiles)
  - Tier 2: $50K-$150K/month (100K-1M profiles)
- **Add-ons**:
  - Customer AI: +$20K-$50K/month
  - Query Service: +$5K-$20K/month
  - Additional sandboxes: +$5K/month each
- **Overage Charges**: $0.50-$2.00 per profile above tier limit

**Hidden Costs**:
- Implementation services (Adobe charges $50K-$200K for Professional Services)
- Data Lake storage (charges per GB stored)
- Destination activation fees (some partners charge per activation)

**Cost Surprise**: Many organizations underestimate total cost by 2-3x.

**Example**:
- Expected: $50K/month licensing
- Actual: $50K licensing + $30K Customer AI + $10K Query Service + $40K implementation services = $130K/month

---

### 5.4 Vendor Lock-in Considerations

**High Lock-in Risk Areas**:

1. **XDM Schema**: Proprietary to Adobe, can't export to another CDP without re-mapping
2. **Customer AI Models**: Trained on AEP data, can't migrate to another platform
3. **Destination Connectors**: Some connectors (Adobe Advertising Cloud) only work with AEP
4. **Identity Graphs**: Proprietary format, can't export

**Mitigation Strategies**:

1. **Maintain Parallel Source of Truth**:
   - GCP BigQuery = master profile store
   - AEP = activation layer only
   - All business logic (scoring, segmentation) in GCP (portable)

2. **Avoid Proprietary Features**:
   - Don't use Customer AI (use GCP Vertex AI instead)
   - Don't use AEP's journey orchestration (use Campaign or Marketo)
   - Minimize use of AEP-specific schema extensions

3. **Design for Portability**:
   - Document XDM -> Standard mapping (e.g., XDM to Segment Traits)
   - Keep GCP pipelines independent of AEP
   - Test activation to non-Adobe destinations (Google Ads, Marketo) to prove portability

4. **Contract Negotiations**:
   - Negotiate data export rights in contract
   - Ensure API access to export profiles and segments
   - Avoid multi-year locks (annual renewals preferred)

---

## 6. Recommended Architecture for Your Use Case

**MAJOR UPDATE (2025)**: With Federated Audience Composition now available, the recommended approach has fundamentally changed.

### 6.1 Phase 1: Federated Audience Composition POC (2 weeks)

**Goal**: Validate TRUE zero-copy architecture with Federated Audience Composition.

**NEW RECOMMENDED ARCHITECTURE**:
```
GCP BigQuery (Source of Truth - ALL DATA STAYS HERE)
  - Compute lead classification (cold/warm/hot) daily
  - Store in partitioned, clustered table
  - NO DATA TRANSFER TO AEP

AEP Federated Audience Composition
  - Connect to BigQuery via service account
  - Query BigQuery directly (federated queries)
  - Store ONLY audience membership (customer IDs)

Federated Audiences (3 core audiences)
  - "Hot Leads" (query: WHERE lead_classification = 'hot')
  - "Warm Leads" (query: WHERE lead_classification = 'warm')
  - "Cold Leads - Re-engagement" (query: WHERE lead_classification = 'cold'
                                   AND last_interaction_date < DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY))

AEP Destinations (start with 2-3)
  - Marketo (nurture campaigns)
  - Google Ads (retargeting)
  - Salesforce (account manager notifications)
```

**Data Transfer**:
- **Initial**: ZERO (no profile ingestion)
- **Daily refresh**: ~360 KB (18K audience member IDs across 3 audiences)
- **Annual**: 131 MB (vs 365 GB for full ingestion)
- **Reduction**: 99.96%

**Cost**:
- **AEP Licensing**: $40K-$80K/year (no profile storage costs)
- **BigQuery Queries**: $135-$1,350/year (depending on optimization)
- **Total**: $41K-$83K/year (50% savings vs Pattern 1)

**Success Metrics**:
- Audience refresh completes in <5 minutes
- BigQuery query cost <$1 per refresh
- Activation to destinations works (>98% delivery rate)
- Lead conversion rate improvement (business value)

**Implementation Steps** (2 weeks):
1. **Week 1**: Set up service account, configure AEP connection, create 1 test audience
2. **Week 2**: Test refresh, activate to non-prod destination, measure costs

**Decision Point**: After 2 weeks POC, decide:
- **Success**: Scale to production (Phase 2)
- **Failure**: Evaluate Pattern 1 (Computed Attributes) or GCP-native

### 6.1-LEGACY: Pattern 1 Approach (Computed Attributes) - Use ONLY If Federated Fails

**IMPORTANT**: This is the OLD recommendation (before Federated Audience Composition). Use this ONLY if:
- You need real-time triggers (<1 minute latency)
- You need AEP AI features (Customer AI, Attribution AI)
- Federated Audience Composition POC fails for technical reasons

**LEGACY Architecture**:
```
GCP BigQuery (Source of Truth)
  - Compute lead classification (cold/warm/hot) daily
  - Batch update to AEP (via Dataflow + Batch API)

AEP Real-Time Customer Profile
  - Minimal schema (5-7 fields):
    * customer_id (identity)
    * email (identity)
    * leadClassification (enum)
    * propensityScore (number)
    * engagementIndex (integer)
    * primaryProductInterest (enum)
    * accountManagerId (string)

AEP Segments (3 core segments)
  - "Hot Leads" (for immediate account manager outreach)
  - "Warm Leads" (for nurture campaigns)
  - "Cold Leads - Re-engagement" (for win-back campaigns)

AEP Destinations (start with 2-3)
  - Marketo (nurture campaigns)
  - Google Ads (retargeting)
  - Salesforce (account manager notifications)
```

**Data Transfer** (Pattern 1):
- **Daily batch**: ~20-30 MB for 10K profiles
- **Annual**: 365 GB
- **No streaming** (start simple, add later if needed)

**Cost** (Pattern 1):
- **AEP Licensing**: $70K-$120K/year (profile storage included)
- **Total**: $82K-$145K/year

---

### 6.2 Phase 2: Scale Federated Audiences to Production (4-6 weeks)

**After successful POC**, scale to production with optimized BigQuery setup.

**NEW Architecture Enhancements**:
```
GCP BigQuery (Optimized for Federated Queries)
  - Partition tables by last_scored_at (reduce query costs)
  - Cluster by lead_classification, product_interest (faster queries)
  - Create materialized views for common audiences (sub-second queries)
  - Implement BigQuery audit logging (monitor AEP query costs)

AEP Federated Audiences (Expand to 5-10 audiences)
  - "Hot Leads - Sales Outreach" (daily refresh)
  - "Warm Tech Leads - Product Webinar" (weekly refresh)
  - "Cold Leads - 90 Day Nurture" (monthly refresh)
  - "High Propensity - Upsell Campaign" (daily refresh)
  - "Churn Risk - Retention Campaign" (weekly refresh)
  - [Add more based on business needs]

AEP Destinations (Expand to 5+ destinations)
  - Marketo (nurture campaigns)
  - Google Ads Customer Match (retargeting)
  - Email ESP (cold lead re-engagement)
  - Salesforce (sales task creation)
  - Facebook Custom Audiences (social retargeting)
```

**Optimization Checklist**:
- [ ] Implement BigQuery partitioning and clustering
- [ ] Create materialized views for high-frequency queries
- [ ] Set up BigQuery cost monitoring dashboard
- [ ] Configure VPC Service Controls for security
- [ ] Rotate service account keys (quarterly schedule)

**Cost at Scale**:
- **AEP Licensing**: $40K-$80K/year (unchanged)
- **BigQuery Queries**: $135-$1,350/year (optimized)
- **Engineering Effort**: <10 hours/month (low maintenance)
- **Total**: $41K-$83K/year

---

### 6.3 Phase 3 (OPTIONAL): Add Real-Time for Edge Cases

**Only if specific use cases require <1 minute latency**, add Pattern 1 (Streaming Ingestion) for those audiences.

**Hybrid Architecture** (Federated + Streaming):
```
PRIMARY: Federated Audiences (99% of use cases)
  - All batch campaigns (daily/weekly activation)
  - Cost: $40K-$80K/year

SECONDARY: Pattern 1 Streaming (1% of use cases - OPTIONAL)
  - GCP Pub/Sub (Real-time Events)
    * Monitor: webinar_registration, high_value_activity, callback_requested
    * Trigger: Cloud Function

  - Cloud Function
    * Stream critical events to AEP (Streaming API)
    * Update lead_classification to "hot" (real-time)

  - AEP Streaming Segment
    * "Hot Leads - Immediate Action" (evaluates in <1 minute)

  - Destination
    * Salesforce API (alert account manager in real-time)

  - Incremental Cost: +$10K-$20K/year (streaming API + engineering)
```

**Decision Criteria for Adding Real-Time**:
- Business requirement: Sales alerts must trigger <1 minute (not 24 hours)
- Value: Each real-time alert generates >$1K in incremental revenue
- Cost-benefit: Incremental $10K-$20K/year justified by business value

---

### 6.4 Phase 4: Evaluate and Optimize (After 6-12 months)

**After 6-12 months with Federated Audience Composition, decide**:

**Option A: Double Down on AEP**
- Expand federated audiences to more use cases (customer segmentation, churn prediction)
- Add Journey Orchestration (Customer Journey Optimizer) if needed
- Consider hybrid approach (add Pattern 1 for real-time use cases)
- Potential expansion: Adobe Analytics integration, additional destinations

**Option B: Optimize Federated Audience Composition**
- Consolidate audiences (reduce BigQuery query costs)
- Implement more materialized views (faster refreshes)
- Negotiate lower AEP pricing based on usage data
- Reduce refresh frequency for low-value audiences (weekly instead of daily)

**Option C: Migrate Away from AEP** (if value doesn't justify cost)
- Replace AEP with GCP-native activation (Cloud Composer + direct API integrations)
- OR migrate to Reverse ETL tool (Hightouch, Census) - cheaper than AEP
- **Exit strategy is SIMPLE**: All data and logic already in BigQuery
- **No vendor lock-in**: Just change activation layer, scoring logic unchanged

**Decision Criteria**:

**Stay with AEP if**:
- Federated Audiences deliver >$100K/year in value (lead conversion improvement)
- Destination connectors save >$20K/year in engineering effort vs building direct integrations
- Total cost ($41K-$83K/year) justified by business outcomes

**Leave AEP if**:
- Total cost > value delivered
- GCP-native or Reverse ETL can deliver same value at <$30K/year
- No need for AEP-specific features (Real-Time CDP, Journey Optimizer)

**Honest Assessment**:
- With Federated Audience Composition, AEP is MUCH more defensible (50% cheaper, true zero-copy)
- Exit risk is low (data stays in BigQuery, minimal migration effort)
- Start with 2-week POC, measure value, make data-driven decision

---

## 7. Implementation Checklist

### 7.1 Pre-Implementation (Weeks 1-2)

- [ ] **Data Audit**:
  - Inventory all customer attributes currently in GCP
  - Identify MINIMUM attributes needed for segmentation
  - Document data lineage (source systems -> GCP -> AEP)

- [ ] **AEP Sandbox Setup**:
  - Request development sandbox from Adobe
  - Configure IMS authentication
  - Create API credentials (JWT or OAuth Server-to-Server)

- [ ] **XDM Schema Design**:
  - Design minimal profile schema (5-10 fields)
  - Get schema reviewed by Adobe (avoid anti-patterns)
  - Create schema in AEP UI or via API

- [ ] **GCP Infrastructure**:
  - Set up Cloud Composer (Airflow) for orchestration
  - Create BigQuery dataset for computed scores
  - Set up GCS bucket for AEP batch ingestion staging

- [ ] **Cost Estimation**:
  - AEP licensing negotiation (get firm pricing)
  - GCP egress costs (data leaving GCP)
  - Dataflow compute costs

### 7.2 Development (Weeks 3-6)

- [ ] **Lead Scoring Pipeline**:
  - Implement BigQuery ML model or scoring query
  - Test on sample data (validate classification logic)
  - Set up Cloud Composer DAG for daily runs

- [ ] **GCP-to-AEP Integration**:
  - Build Dataflow job for XDM transformation
  - Test batch ingestion (GCS -> AEP Batch API)
  - Implement error handling and retry logic

- [ ] **AEP Configuration**:
  - Create Profile dataset and enable for Profile
  - Configure identity namespaces (email, gcpCustomerId)
  - Set up merge policy (timestamp-ordered preferred)

- [ ] **Segment Definition**:
  - Create 3 core segments (cold/warm/hot)
  - Test segment evaluation (check qualification timing)

- [ ] **Destination Setup**:
  - Configure 2-3 destinations (Marketo, Google Ads, Salesforce)
  - Test activation (end-to-end data flow)
  - Validate data arrives in destination correctly

### 7.3 Testing (Weeks 7-8)

- [ ] **Data Validation**:
  - Compare GCP computed scores vs AEP profile attributes (ensure accuracy)
  - Test identity resolution (email, customer ID matching)
  - Verify segment membership (sample profiles)

- [ ] **Performance Testing**:
  - Batch ingestion timing (how long to process 10K profiles?)
  - Segment evaluation latency (batch vs streaming)
  - Destination activation lag (AEP -> Marketo timing)

- [ ] **Failure Scenarios**:
  - Test batch ingestion failure (bad data, schema mismatch)
  - Test API rate limiting (throttling behavior)
  - Test data inconsistency (GCP vs AEP out of sync)

### 7.4 Production Rollout (Weeks 9-10)

- [ ] **Monitoring Setup**:
  - Cloud Monitoring alerts (pipeline failures)
  - AEP batch ingestion status checks
  - Segment membership tracking (sudden drops/spikes)

- [ ] **Documentation**:
  - Data flow diagram (GCP -> AEP -> Destinations)
  - Runbook for common issues (failed batch, segment not updating)
  - XDM schema documentation (field mappings)

- [ ] **Training**:
  - Train marketing team on AEP segments
  - Train data team on pipeline operations

- [ ] **Gradual Rollout**:
  - Start with 10% of profiles (pilot cohort)
  - Monitor activation rates and campaign performance
  - Scale to 100% over 2-4 weeks

### 7.5 Post-Launch (Ongoing)

- [ ] **Cost Monitoring**:
  - Track AEP profile count (watch for overage)
  - Monitor GCP egress costs (data leaving GCP)
  - Review destination activation costs

- [ ] **Performance Optimization**:
  - Identify slow segments (optimize PQL)
  - Batch ingestion timing (can we reduce latency?)
  - Consider streaming for high-priority events

- [ ] **Business Value Tracking**:
  - Lead conversion rate (before vs after AEP)
  - Campaign ROI (segment targeting effectiveness)
  - Operational efficiency (time saved for marketing team)

---

## 8. Key Takeaways and Decision Framework

### 8.1 Core Principles for Zero-Copy with AEP

1. **Accept Reality**: True zero-copy is impossible with AEP. Aim for data minimization instead.
2. **Compute in GCP, Activate in AEP**: Keep business logic portable, use AEP as activation layer.
3. **Start Minimal**: Begin with 5-7 profile attributes, not 100+. Add more only if necessary.
4. **Batch Over Streaming**: Default to daily batch updates (cheaper). Add streaming selectively.
5. **Maintain Parallel Systems**: GCP = source of truth. AEP = cache for activation.

### 8.2 Decision Tree: Should We Use AEP?

```
START: Do we need to activate segments to multiple destinations?
  |
  NO --> Don't use AEP. Use GCP-native (BigQuery + direct API integrations)
  |
  YES --> Continue
  |
  Do we have budget for AEP ($50K-$150K/year)?
  |
  NO --> Use Segment or mParticle (lighter CDP, $5K-$30K/year)
  |
  YES --> Continue
  |
  Do we need Adobe ecosystem integration (Analytics, Target, Campaign)?
  |
  YES --> AEP is a good fit (unified identity is valuable)
  |
  NO --> Continue
  |
  Can we build destination integrations in-house?
  |
  YES --> GCP-native is more cost-effective (avoid AEP)
  |
  NO --> Use AEP for destination connectors (value = saved engineering effort)
```

### 8.3 When to Walk Away from AEP

**Red Flags** (consider alternatives):
- Adobe pushing multi-year contract without pilot
- Implementation requires >6 months (AEP should be faster)
- Total cost > $200K/year and you're not using AI features
- Your use case is purely lead scoring (GCP Vertex AI is better)
- You need sub-second latency (AEP is not real-time enough)

### 8.4 Final Recommendation for Your Use Case

**My Honest Assessment**:

For your Cold/Warm/Hot lead classification use case:

**Best Architecture**:
```
GCP BigQuery (Lead Scoring)
  -> AEP (Minimal Profile)
  -> Destinations (Marketo, Google Ads, Salesforce)
```

**Why This Works**:
- GCP handles complex scoring logic (flexible, cost-effective)
- AEP provides destination connectors (saves engineering time)
- Minimal data in AEP (reduces vendor lock-in)
- Daily batch updates (cost-optimized)

**Data Transfer**:
- 20-30 MB/day for 10K profiles (5-7 fields per profile)
- 95% reduction vs full profile replication

**Cost Estimate** (annual):
- AEP licensing: $60K-$100K/year (10K profiles)
- GCP compute: $10K-$20K/year (BigQuery + Dataflow)
- Implementation: $50K-$100K (one-time)
- **Total Year 1**: $120K-$220K
- **Total Year 2+**: $70K-$120K/year

**ROI Calculation**:
- If destination integrations would cost >$50K/year to build (2-3 destinations), AEP pays for itself
- If lead conversion improves >5%, AEP likely justifies cost
- If you can't build/maintain integrations, AEP provides operational efficiency

**Alternative** (if budget-constrained):
```
GCP BigQuery (Lead Scoring)
  -> Segment (Activation Layer) - $20K-$40K/year
  -> Destinations
```
- 50-70% cheaper than AEP
- Faster implementation (weeks vs months)
- Less sophisticated identity resolution (acceptable for B2B lead scoring)

---

## 9. Technical Appendices

### 9.1 AEP API Reference for Your Use Case

**Streaming Ingestion API**:
```
POST https://dcs.adobedc.net/collection/{DATASET_ID}
Headers:
  Content-Type: application/json
  Authorization: Bearer {ACCESS_TOKEN}
  x-gw-ims-org-id: {IMS_ORG_ID}
  x-api-key: {API_KEY}

Body: See "Streaming Ingestion" examples above
Rate Limit: 20,000 requests/second (org-wide)
```

**Batch Ingestion API**:
```
1. Upload file to GCS or Azure Blob

2. Create Batch:
POST https://platform.adobe.io/data/foundation/import/batches
Body:
{
  "datasetId": "{DATASET_ID}",
  "inputFormat": {
    "format": "json"
  }
}

3. Register file:
PATCH https://platform.adobe.io/data/foundation/import/batches/{BATCH_ID}
Body:
{
  "files": {
    "cloudStorageUri": "gs://your-bucket/data.json"
  }
}

4. Complete batch:
POST https://platform.adobe.io/data/foundation/import/batches/{BATCH_ID}?action=COMPLETE

Processing Time: 30 minutes - 2 hours
```

**Segment Definition API**:
```
POST https://platform.adobe.io/data/core/ups/segment/definitions
Body:
{
  "name": "Hot Leads",
  "description": "Leads with hot classification",
  "expression": {
    "type": "PQL",
    "format": "pql/text",
    "value": "profile.leadClassification = \"hot\""
  },
  "schema": {
    "name": "_xdm.context.profile"
  },
  "evaluationInfo": {
    "batch": {
      "enabled": true
    },
    "continuous": {
      "enabled": false
    },
    "synchronous": {
      "enabled": false
    }
  }
}
```

**Segment Membership Export** (via Destinations):
- Configure destination in AEP UI (no direct API for ad-hoc export)
- Alternative: Query Service to export segment membership to GCS

### 9.2 XDM Schema Best Practices

**Minimal Profile Schema Template**:
```json
{
  "$schema": "http://json-schema.org/draft-06/schema#",
  "$id": "https://ns.adobe.com/{TENANT}/schemas/minimal-lead-profile",
  "title": "Minimal Lead Profile",
  "type": "object",
  "meta:extends": [
    "https://ns.adobe.com/xdm/context/profile"
  ],
  "allOf": [
    {
      "$ref": "https://ns.adobe.com/xdm/context/profile"
    },
    {
      "type": "object",
      "properties": {
        "_{TENANT}": {
          "type": "object",
          "properties": {
            "leadScoring": {
              "type": "object",
              "properties": {
                "classification": {
                  "type": "string",
                  "enum": ["cold", "warm", "hot"],
                  "meta:enum": {
                    "cold": "Low engagement or weak fit",
                    "warm": "Engaged but not yet in buying phase",
                    "hot": "Ready for product conversion or high intent"
                  },
                  "title": "Lead Classification",
                  "description": "Computed lead temperature (cold/warm/hot)"
                },
                "propensityScore": {
                  "type": "number",
                  "minimum": 0,
                  "maximum": 1,
                  "title": "Conversion Propensity Score",
                  "description": "ML-predicted likelihood of conversion (0.0-1.0)"
                },
                "engagementIndex": {
                  "type": "integer",
                  "minimum": 0,
                  "maximum": 100,
                  "title": "Engagement Index",
                  "description": "Composite engagement score (0-100)"
                },
                "lastComputedTimestamp": {
                  "type": "string",
                  "format": "date-time",
                  "title": "Last Score Computation Timestamp",
                  "description": "When this score was last computed"
                }
              }
            },
            "context": {
              "type": "object",
              "properties": {
                "primaryProductInterest": {
                  "type": "string",
                  "enum": ["product_a", "product_b", "product_c", "product_d", "unknown"],
                  "title": "Primary Product Interest",
                  "description": "Product category with highest engagement"
                },
                "accountManagerId": {
                  "type": "string",
                  "title": "Account Manager ID",
                  "description": "Assigned account manager identifier"
                }
              }
            }
          }
        }
      }
    }
  ]
}
```

**Design Principles**:
- **Namespace custom fields**: Use `_{TENANT}` prefix to avoid conflicts
- **Use enums for classifications**: Better for segment performance
- **Add descriptions**: Essential for marketing team to understand fields
- **Avoid nested arrays**: AEP segmentation performance degrades with complex nesting
- **Keep it flat**: Max 2-3 levels of nesting

### 9.3 Troubleshooting Common Issues

**Issue 1: Batch Ingestion Fails**
```
Error: "XDM schema validation failed"

Causes:
- Data type mismatch (e.g., string sent for number field)
- Missing required fields (_id, timestamp for events)
- Identity map format incorrect

Solution:
1. Validate JSON against schema before sending
2. Check AEP batch status API for detailed error:
   GET https://platform.adobe.io/data/foundation/catalog/batches/{BATCH_ID}
3. Review sample failed records in AEP UI (Monitoring tab)
```

**Issue 2: Segment Not Updating**
```
Symptom: Profile updated but segment membership unchanged

Causes:
- Batch segment evaluation runs once per 24 hours (not immediate)
- Profile not enabled for dataset (check dataset config)
- Merge policy issues (check profile merge timestamp)

Solution:
1. Check segment evaluation schedule:
   GET https://platform.adobe.io/data/core/ups/segment/jobs
2. Force segment evaluation (not recommended for production):
   POST https://platform.adobe.io/data/core/ups/segment/jobs
3. Switch to streaming segment (if <30 attributes)
```

**Issue 3: Identity Resolution Not Working**
```
Symptom: Same customer appearing as multiple profiles

Causes:
- Identity namespace not configured
- Identity map missing "primary": true flag
- Cross-device stitching requires Adobe Analytics or third-party data

Solution:
1. Verify identity namespaces exist:
   GET https://platform.adobe.io/data/core/idnamespace/identities
2. Check identity graph for a profile:
   GET https://platform.adobe.io/data/core/identity/cluster/members?{identity}
3. Review merge policy configuration (ensure correct identity precedence)
```

---

## 10. Conclusion

**MAJOR UPDATE (2025)**: The conclusion I wrote about zero-copy being impossible with AEP is now PARTIALLY OBSOLETE. Adobe's **Federated Audience Composition** (Section 2.6) enables TRUE zero-copy for audience creation use cases.

**What's Now Possible**:
- Query BigQuery directly from AEP (no data copying)
- Keep all customer data in BigQuery (data sovereignty)
- Transfer only audience membership to AEP (99.96% reduction)
- Activate to destinations at 50% lower cost than traditional ingestion

**Recommended Strategy for Your Cold/Warm/Hot Lead Use Case**:

**PRIMARY APPROACH: Federated Audience Composition (Pattern 6)**
- Compute lead scores in BigQuery (BigQuery ML models)
- Create audiences via federated queries (AEP queries BigQuery directly)
- Activate to Marketo, Google Ads without copying 100K profiles
- **Data transfer**: 99.96% reduction (360 KB vs 365 GB annually)
- **Cost**: $41K-$83K/year (50% savings vs Pattern 1)
- **Complexity**: LOW (SQL + AEP UI, no custom pipelines)
- **Vendor lock-in**: MINIMAL (all logic stays in BigQuery)

**SECONDARY APPROACH: Pattern 1 (Computed Attributes) - Use ONLY for Real-Time Edge Cases**
- If you need real-time triggers (<1 minute latency): Use for those specific audiences
- If you need AEP AI features: Pattern 1 required (Customer AI needs AEP Data Lake)
- If you need identity stitching: Pattern 1 provides AEP Identity Graph
- Example: "Hot lead becomes qualified → immediate sales alert" (real-time)

**HYBRID APPROACH (Best of Both Worlds)**:
```
Federated Audiences (99% of use cases):
  - "Warm Leads - Email Nurture" (50K members, daily refresh)
  - "Cold Leads - Re-engagement" (80K members, weekly refresh)
  - Cost: $40K-$80K/year (AEP licensing)

Pattern 1 Streaming (1% of use cases):
  - "Hot Leads - Immediate Sales Alert" (5K members, real-time)
  - Cost: Additional $10K-$20K/year
```

**Cost Comparison for Your Use Case** (100K leads, 3 audiences):

| Approach | Annual Cost | Data Transfer | Complexity | Vendor Lock-in |
|----------|-------------|---------------|------------|----------------|
| **Federated Audiences (Pattern 6)** | $41K-$83K | 131 MB (99.96% reduction) | LOW | MINIMAL |
| **Computed Attributes (Pattern 1)** | $82K-$145K | 365 GB | HIGH | MEDIUM |
| **Hybrid (Pattern 6 + Pattern 1)** | $51K-$103K | <1 GB | MEDIUM | MINIMAL |
| **GCP-Native (No AEP)** | $10K-$30K | ZERO | HIGH | ZERO |

**Final Advice**:

1. **Start with Federated Audience Composition** (2-week POC):
   - Set up BigQuery service account for AEP access
   - Create 1-2 test audiences (hot leads, warm leads)
   - Activate to non-production destination
   - Validate costs (<$1 per query) and performance (<5 min refresh)
   - **Success Criteria**: Audience creates, refreshes, activates successfully

2. **Scale to Production** (4-6 weeks):
   - Optimize BigQuery tables (partitioning, clustering, materialized views)
   - Create 3-5 production audiences
   - Activate to Marketo, Google Ads, Email ESP
   - Monitor costs ($135-$1,350/year for BigQuery queries)

3. **Add Real-Time ONLY If Needed** (optional):
   - If specific audiences require <1 minute latency: Add Pattern 1
   - Keep majority of audiences in Federated (cost optimization)
   - Example: Real-time sales alerts for hot leads (Pattern 1), batch nurture for warm/cold leads (Federated)

4. **Measure ROI After 3 Months**:
   - Lead conversion improvement (did hot lead campaigns work?)
   - Operational efficiency (time saved vs manual list management)
   - Cost savings (50% vs traditional AEP ingestion)
   - If ROI positive: Expand to more audiences
   - If ROI negative: Exit strategy is simple (data still in BigQuery, minimal sunk cost)

**Questions to Ask Adobe Sales**:
1. What's the total cost for 10K profiles (licensing + AI features + overages)?
2. Can we pilot with 1K profiles for 3 months? (test before commitment)
3. What's the data export process if we want to leave AEP? (contractual right to export)
4. What are batch segment evaluation SLAs? (understand latency limitations)
5. Can we bring our own ML models (instead of Customer AI)? (yes, via API)
6. Is federated query support on the roadmap? If not, why not? (understand Adobe's position on zero-copy)

**Red Flags in Adobe Sales Conversation**:
- Pressure to sign multi-year deal without pilot
- Vague pricing ("depends on use case" - demand firm pricing)
- Overselling Customer AI (most companies don't need it)
- Claiming "real-time" without clarifying batch vs streaming segment limits

**Good Signs**:
- Adobe offers sandbox access for POC
- Transparent about limitations (segment latency, API rate limits)
- Willing to start small (1K-10K profiles pilot)
- Solutions architect assigned (technical support, not just sales)

---

**Document Metadata**:
- **Created**: 2024 (analysis based on AEP as of January 2025)
- **Author**: AEP Solutions Architect (independent assessment)
- **Disclaimer**: Recommendations based on publicly available AEP documentation and industry best practices. Your specific use case may vary. Always validate with POC before production deployment.
- **Adobe Documentation References**:
  - AEP API Reference: https://experienceleague.adobe.com/docs/experience-platform/landing/api-guide.html
  - XDM Schema Design: https://experienceleague.adobe.com/docs/experience-platform/xdm/home.html
  - Batch Ingestion: https://experienceleague.adobe.com/docs/experience-platform/ingestion/batch/overview.html
  - Streaming Ingestion: https://experienceleague.adobe.com/docs/experience-platform/ingestion/streaming/overview.html
  - Segmentation Service: https://experienceleague.adobe.com/docs/experience-platform/segmentation/home.html
