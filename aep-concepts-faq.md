# Adobe Experience Platform (AEP) - Concepts, FAQ & Glossary

**Purpose:** Explain AEP concepts for business stakeholders, marketing ops, and anyone new to Adobe Experience Platform.

**Audience:** Executives, marketing managers, business analysts, and technical teams evaluating or implementing AEP.

**Last Updated:** October 2025

---

## Table of Contents

1. [Key Concepts & Glossary](#key-concepts--glossary)
2. [Identity Stitching - Deep Dive](#identity-stitching---deep-dive)
3. [Edge Segmentation - Deep Dive](#edge-segmentation---deep-dive)
4. [Segments vs Audiences - What's the Difference?](#segments-vs-audiences---whats-the-difference)
5. [Frequently Asked Questions](#frequently-asked-questions)
   - [AEP Basics](#aep-basics)
   - [Data & Integration](#data--integration)
   - [Identity & Profiles](#identity--profiles)
   - [Segmentation & Activation](#segmentation--activation)
   - [Zero-Copy Architecture](#zero-copy-architecture)
   - [Costs & Licensing](#costs--licensing)

---

## Key Concepts & Glossary

### Real-Time Customer Data Platform (RT-CDP)

**What it is:** Adobe's cloud platform that unifies customer data from multiple sources (website, mobile app, CRM, email) into a single view of each customer, enabling you to create audiences and activate them to marketing channels.

**Why it matters:** Instead of having customer data scattered across 10+ systems, RT-CDP creates one profile per customer that updates in real-time. Marketing can then target the right people with the right message at the right time.

**Example:** A customer browses your website (anonymous), then logs in (now known), then opens your mobile app. RT-CDP stitches these interactions into one profile, so you know this person viewed Product X on web and can send them a personalized push notification about it.

**Related to:** Customer Profile, Identity Graph, Segmentation, Activation

---

### Customer Profile (Real-Time Customer Profile)

**What it is:** A unified view of an individual customer that combines data from all sources - demographics, behaviors, transactions, preferences - updated in real-time or near-real-time.

**Why it matters:** Enables personalization. If you know a customer is a "high-value lead interested in enterprise products," you can show them relevant offers instead of generic messaging.

**Example:** Profile for customer ID "12345" contains:
- Email: john@company.com
- Last purchase: $5,000 software license (3 months ago)
- Website visits: 12 in last 30 days
- Lead score: 87 (hot lead)
- Preferred channel: Email

Marketing can use this to send John a personalized upgrade offer via email.

**Related to:** XDM Schema, Identity Stitching, Profile Store

---

### Experience Data Model (XDM)

**What it is:** Adobe's standardized data format for customer data. Think of it as a template that defines what fields your customer profiles contain and what types of data they are (text, number, date, etc.).

**Why it matters:** Ensures consistency. If 5 different teams send customer data to AEP, XDM makes sure "email address" is stored the same way for everyone, not as "email", "Email", "email_address", etc.

**Example:** Instead of each team defining customer data differently:
- Team A: `{customer_name, emailAddr, phone}`
- Team B: `{name, email, phoneNumber}`

XDM provides a standard schema:
```json
{
  "person": {
    "name": "John Doe",
    "email": "john@company.com",
    "phone": "+1-555-0100"
  }
}
```

**Related to:** Schemas, Datasets, Profile Store

---

### Identity and Identity Namespace

**What it is:**
- **Identity:** A unique identifier for a customer (email, phone, CRM ID, cookie ID, mobile device ID)
- **Identity Namespace:** The "type" of identifier (e.g., "Email", "CRM ID", "Mobile Device ID")

**Why it matters:** Customers interact with you through multiple channels using different identifiers. Identity namespaces help AEP connect these dots. Email "john@company.com" and Cookie ID "abc123" might be the same person.

**Example:**
- Identity: `john@company.com`, Namespace: `Email`
- Identity: `abc123`, Namespace: `ECID` (Adobe cookie)
- Identity: `CRM-12345`, Namespace: `CRM_ID`

AEP's Identity Graph links these together into one profile.

**Related to:** Identity Graph, Identity Stitching, Cross-Device Tracking

---

### Identity Graph

**What it is:** A map showing how different identities (email, cookie, mobile ID, CRM ID) relate to each other and belong to the same person.

**Why it matters:** Without an identity graph, you treat anonymous website visitor "Cookie ABC" and known customer "john@company.com" as two different people. With an identity graph, you know they're the same person and can provide a seamless experience.

**Example:**
```
john@company.com (Email) ←→ Cookie ABC (Web) ←→ Device XYZ (Mobile App) ←→ CRM-12345 (CRM ID)
```
All four identities = ONE customer profile.

**Related to:** Identity Stitching, Cross-Device Tracking

**Note:** Federated Audience Composition does NOT use the Identity Graph. You must pre-compute identity resolution in your data warehouse.

---

### Sources and Destinations

**Sources (What it is):** Systems that SEND data TO AEP (e.g., website, mobile app, CRM like Salesforce, email platform like Marketo, data warehouse like BigQuery).

**Destinations (What it is):** Systems that RECEIVE data FROM AEP (e.g., ad platforms like Google Ads, email tools like Marketo, analytics tools, your own APIs).

**Why it matters:** AEP sits in the middle, collecting data from sources, creating unified profiles, and activating audiences to destinations.

**Example Flow:**
```
Sources → AEP Profile → Segments → Destinations
(Salesforce, Website) → Unified Profile → "Hot Leads" Segment → (Google Ads, Marketo)
```

**Related to:** Data Ingestion, Activation

---

### Data Ingestion (Batch vs Streaming)

**What it is:**
- **Batch Ingestion:** Upload data files on a schedule (e.g., daily CSV of yesterday's transactions)
- **Streaming Ingestion:** Send data to AEP in real-time as events occur (e.g., user clicked a button → event sent to AEP immediately)

**Why it matters:**
- Batch: Cheaper, simpler, but delayed (data is hours/days old)
- Streaming: Real-time, enables instant personalization, but more expensive and complex

**Example:**
- **Batch:** Every night at midnight, export CRM contacts and upload to AEP
- **Streaming:** User adds item to cart → event sent to AEP within 1 second → profile updated → personalized email sent

**Related to:** Sources, Profile Store, Real-Time Customer Profile

---

### Segmentation

**What it is:** The process of grouping customers based on criteria. A segment is a subset of your customer base matching specific conditions.

**Why it matters:** Marketing rarely wants to message ALL customers. Segmentation lets you target specific groups: "High-value customers in California who haven't purchased in 90 days."

**Example Segment:**
- **Name:** "Dormant High-Value Customers"
- **Criteria:**
  - Last purchase > 90 days ago
  - Total lifetime value > $10,000
  - Location: California
- **Result:** 5,432 customers qualify

You can then activate this segment to an email campaign.

**Related to:** Audiences, Segment Builder, Streaming/Batch/Edge Segmentation

---

### Activation

**What it is:** The process of sending audience/segment data to marketing channels (destinations) so you can actually USE the data for campaigns, ads, personalization, etc.

**Why it matters:** Building a perfect segment of "Hot Leads" is useless if you can't send it to Google Ads or your email tool. Activation is where the value gets realized.

**Example:**
1. Create segment: "Hot Leads interested in Product X" (10,000 people)
2. Activate to Google Ads → Google Ads creates a custom audience with these 10,000 people
3. Run ad campaign targeting only this audience
4. Result: Higher conversion rate, lower wasted ad spend

**Related to:** Destinations, Segments, Audiences

---

### Sandboxes

**What it is:** Isolated environments within your AEP instance. Like having separate "test" and "production" databases.

**Why it matters:** You can test configurations, build segments, try new features in a "dev" sandbox without risking your production data or campaigns.

**Example:**
- **Prod Sandbox:** Live customer data, active campaigns
- **Dev Sandbox:** Test data, experimental segments, training environment
- **QA Sandbox:** Validate changes before promoting to production

**Related to:** Environments, Data Governance

---

### Journey Optimizer

**What it is:** Adobe's tool for creating multi-step, multi-channel customer journeys. Goes beyond simple "send email" to orchestrate complex workflows like "If user clicks email, send SMS next day, if no response, assign to sales rep."

**Why it matters:** Enables sophisticated marketing automation across email, SMS, push notifications, in-app messages, and more.

**Example Journey:**
1. User abandons cart → Wait 1 hour
2. Send email reminder → If opened → Wait 24 hours → Send discount code
3. If discount code used → Send "Thank you" push notification
4. If not used after 3 days → Assign to sales rep for personal outreach

**Related to:** RT-CDP, Activation, Personalization

---

### External Audiences

**What it is:** Audience lists created OUTSIDE of AEP (e.g., in your data warehouse, via CSV upload, or using Federated Audience Composition) and imported into AEP as a list of customer IDs.

**Why it matters:** You can leverage complex segmentation logic in your data warehouse (BigQuery, Snowflake) and bring just the results (audience IDs) into AEP for activation, without copying all the underlying data.

**Example:**
- You build a complex lead scoring model in BigQuery using ML
- BigQuery identifies 50,000 "Hot Leads"
- You import these 50,000 customer IDs to AEP as an "External Audience"
- AEP activates them to Google Ads

**Related to:** Federated Audience Composition, Zero-Copy Architecture

---

### Federated Audience Composition

**What it is:** NEW capability (2024/2025) that lets AEP query your data warehouse (BigQuery, Snowflake, etc.) DIRECTLY to create audiences, without copying your data into AEP.

**Why it matters:** **TRUE zero-copy architecture.** Your customer data stays in your warehouse under your control. AEP just queries it and retrieves customer IDs matching your criteria.

**Example:**
1. You have 10 million customer profiles in BigQuery (2 TB of data)
2. You use AEP's drag-and-drop UI to build a query: "Customers who viewed pricing page 3+ times in last 7 days"
3. AEP executes this query against BigQuery
4. BigQuery returns 50,000 customer IDs
5. AEP transfers only these 50,000 IDs (~1 MB) to create an audience
6. **Result:** 10 million profiles stay in BigQuery, only 50K IDs in AEP

**Related to:** External Audiences, BigQuery, Zero-Copy Architecture

**Limitations:**
- Batch-only (no real-time streaming)
- No Identity Graph
- No Customer AI/Attribution AI
- Requires Federated Audience Composition add-on license

---

## Identity Stitching - Deep Dive

### What is Identity Stitching?

**Simple Definition:** The process of connecting multiple identifiers (email, cookie, mobile device ID, CRM ID) that belong to the same person into a single unified customer profile.

**The Problem It Solves:**

Imagine a customer's journey:
1. **Monday:** Visits your website on laptop (anonymous cookie ID: `ABC123`)
2. **Tuesday:** Clicks email link, logs in (email: `john@company.com`, same cookie `ABC123`)
3. **Wednesday:** Downloads mobile app (mobile device ID: `XYZ789`)
4. **Thursday:** Calls customer service, gives phone number (phone: `+1-555-0100`)

Without identity stitching, AEP sees 4 different people:
- Person 1: Cookie ABC123
- Person 2: john@company.com
- Person 3: Mobile XYZ789
- Person 4: +1-555-0100

With identity stitching, AEP knows all 4 identifiers = 1 person.

---

### How Does Identity Stitching Work in AEP?

**AEP's Identity Graph** uses two methods:

#### Method 1: Deterministic Stitching (100% Accurate)

When you explicitly tell AEP two identities belong together:
- User logs in → Cookie ABC123 + Email john@company.com are linked
- User enters phone in app → Email john@company.com + Phone +1-555-0100 are linked

**Example Event:**
```json
{
  "identities": [
    {"id": "ABC123", "namespace": "ECID"},
    {"id": "john@company.com", "namespace": "Email"}
  ],
  "event": "login"
}
```

AEP's Identity Graph now knows: `ABC123 ↔ john@company.com`

#### Method 2: Probabilistic Stitching (AI-Based, Optional)

AEP's "Private Identity Graph" can use AI to make educated guesses:
- Same device + same browsing patterns + same location = probably the same person

**Note:** Most enterprises rely on deterministic stitching only for accuracy.

---

### Why is Identity Stitching Important?

**Use Case 1: Consistent Customer Experience**

**Without stitching:**
- Customer browses product on laptop → Abandons cart
- Opens mobile app next day → Sees generic homepage (AEP doesn't know they're interested in that product)

**With stitching:**
- Customer browses product on laptop → Abandons cart
- Opens mobile app next day → App shows: "Complete your purchase! Product X is still in your cart"

**Business Impact:** Higher conversion rates, better customer satisfaction

---

**Use Case 2: Attribution (Understanding Marketing ROI)**

**Without stitching:**
- Customer sees Facebook ad on phone → Doesn't click
- Searches Google on laptop → Clicks ad → Visits website
- Receives email → Clicks link → Makes purchase

**Without identity stitching:** Email gets 100% credit (last click)
**With identity stitching:** Credit is distributed: Facebook (awareness), Google (consideration), Email (conversion)

**Business Impact:** Accurate marketing spend allocation, better budget decisions

---

**Use Case 3: Personalization Across Channels**

**Without stitching:**
- Customer downloads whitepaper via email (shows interest in Topic X)
- Visits website later → Sees generic banner (AEP doesn't know about the download)

**With stitching:**
- Customer downloads whitepaper via email
- Visits website later → Sees banner: "Since you liked our Topic X guide, check out our webinar!"

**Business Impact:** Relevant messaging, higher engagement

---

### When is Identity Stitching NOT Needed?

**Scenario 1: Simple Email-Only Campaigns**
- You only send batch email campaigns
- You use email address as the sole identifier
- No cross-device tracking needed

**Verdict:** Identity stitching adds no value. Just use email as your primary ID.

---

**Scenario 2: Anonymous Analytics Only**
- You're just tracking website traffic patterns
- You don't care WHO the person is, just what pages they view
- No personalization needed

**Verdict:** Use Adobe Analytics, not AEP. Identity stitching is overkill.

---

**Scenario 3: Using Federated Audience Composition**
- Your data warehouse (BigQuery) already has identity resolution logic
- You've pre-computed which cookie/email/mobile IDs belong together
- AEP just queries your warehouse and gets customer IDs

**Verdict:** Identity stitching in AEP is not needed. You've already done it in BigQuery.

---

### Identity Stitching and Zero-Copy Architecture

**Key Question:** If I use Federated Audience Composition (Option 1), do I lose identity stitching?

**Answer:** You don't "lose" it, but you must handle it YOURSELF in your data warehouse.

**Federated Audience Composition:**
- ✅ Data stays in BigQuery
- ✅ Zero vendor lock-in
- ❌ No AEP Identity Graph
- ✅ But you can build your own identity resolution in BigQuery

**Computed Attributes Pattern (Option 2) or Hybrid (Option 3):**
- ❌ Data copied to AEP
- ❌ Some vendor lock-in
- ✅ AEP Identity Graph available
- ✅ Cross-device tracking out-of-the-box

**Bottom Line:** If cross-device identity stitching is critical AND you don't want to build it yourself, use Option 2 or 3. If you can do identity resolution in BigQuery (or don't need it), use Option 1.

---

## Edge Segmentation - Deep Dive

### What is Edge Segmentation?

**Simple Definition:** Creating and evaluating segments at the "edge" (close to the user, on Adobe's edge servers near their location) to enable ultra-fast personalization with <50 milliseconds latency.

**Regular Segmentation:**
- User visits website → Request goes to AEP data center (e.g., Virginia, USA)
- AEP Profile Store looks up customer profile
- Segmentation engine evaluates: "Is this user in 'Hot Leads' segment?"
- Response sent back to website
- **Total time:** 100-500 milliseconds

**Edge Segmentation:**
- User visits website → Request goes to Adobe Edge server (e.g., London, UK - close to user)
- Edge server has cached profile data and segment definitions
- Segment evaluation happens locally on edge server
- Response sent back to website
- **Total time:** <50 milliseconds

---

### Why Would You Use Edge Segmentation?

**Use Case 1: Real-Time Website Personalization**

**Scenario:** E-commerce site wants to show personalized hero banner based on customer segment:
- "New Visitors" → Show "Welcome! Get 10% off first order"
- "Returning Customers" → Show "Welcome back! Here are your favorite categories"
- "VIP Customers" → Show "Exclusive VIP Sale - 20% off everything"

**Without Edge Segmentation:**
- Page loads → Wait 200ms for AEP to respond → Banner appears (slow, bad UX)

**With Edge Segmentation:**
- Page loads → Wait 20ms for edge response → Banner appears instantly (smooth UX)

**Business Impact:** Higher engagement, lower bounce rate

---

**Use Case 2: Adobe Target Integration**

**Scenario:** Running A/B tests with Adobe Target. You want to show Test Variant A to "High-Value Leads" and Variant B to everyone else.

**Without Edge Segmentation:**
- Target queries AEP Profile Store for every visitor → Slow
- May timeout under high traffic

**With Edge Segmentation:**
- Target queries Adobe Edge → Fast, scalable
- Works even with millions of concurrent visitors

**Business Impact:** Reliable A/B testing at scale

---

**Use Case 3: Mobile App In-Session Personalization**

**Scenario:** Banking app shows different screens based on customer segment:
- "New Customers" → Onboarding flow
- "Active Customers" → Dashboard with recent transactions
- "Dormant Customers" → Re-engagement offer

**With Edge Segmentation:**
- App queries edge server → Gets segment membership in <30ms
- User sees personalized screen immediately

**Business Impact:** Better mobile app experience, higher retention

---

### How is Edge Segmentation Different from Regular Segmentation?

| Aspect | Regular Segmentation | Edge Segmentation |
|--------|---------------------|-------------------|
| **Location** | AEP data centers (centralized) | Adobe Edge servers (distributed globally) |
| **Latency** | 100-500ms | <50ms |
| **Use Case** | Batch campaigns, scheduled activations | Real-time web/mobile personalization |
| **Profile Data** | Full profile (100+ attributes) | Subset of attributes (5-20 key fields) |
| **Segment Complexity** | Complex logic supported | Simple logic only (no lookback windows >14 days) |
| **Data Freshness** | Real-time (streaming updates) | Near real-time (minutes delay) |
| **Cost** | Standard AEP pricing | Premium feature (additional cost) |

**Key Limitation:** Edge segments can only use attributes that are "edge-enabled" (marked in schema). You can't use all 100+ profile attributes due to performance constraints.

---

### Technical Requirements for Edge Segmentation

**1. Profile Attributes Must Be Edge-Enabled**
- In your XDM schema, mark attributes as "edge projection enabled"
- Example: `lead_score`, `customer_tier`, `last_purchase_date`
- NOT: Complex nested objects or historical event arrays

**2. Simple Segment Logic**
- ✅ Allowed: `lead_score > 80 AND customer_tier = 'gold'`
- ✅ Allowed: `last_purchase_date < 30 days ago`
- ❌ Not allowed: `COUNT(purchases in last 12 months) > 10` (requires full event history)

**3. Streaming Profile Updates**
- Edge relies on real-time profile updates
- Batch-only profiles may be stale on edge (minutes delay)

**4. Adobe Target or Web SDK Integration**
- Edge segmentation is accessed via Adobe Target or Web SDK
- Not available for backend API integrations

---

### Can You Use Edge Segmentation with Federated Audience Composition?

**Short Answer:** No.

**Why:** Edge segmentation requires profiles to be in AEP's Profile Store with real-time updates. Federated Audience Composition doesn't store profiles in AEP, so there's nothing to evaluate at the edge.

**Alternatives:**
- Use Option 2 (Computed Attributes) for the subset of customers needing edge personalization
- Use Option 3 (Hybrid): Federated for 99% + Streaming for 1% that need edge capabilities

---

## Segments vs Audiences - What's the Difference?

### The Confusion

In Adobe Experience Platform, "segment" and "audience" are often used interchangeably, but there are subtle differences.

### Definitions

**Segment:**
- A **definition** or **rule** that describes a group of customers
- Example: "Customers who purchased in last 30 days AND total spend > $1,000"
- Think of it as a SQL query or a filter

**Audience:**
- The **actual list** of customer IDs that match a segment definition at a specific point in time
- Example: 5,432 customer IDs who currently meet the segment criteria
- Think of it as the query results

**Analogy:**
- **Segment** = Recipe (instructions)
- **Audience** = Cake (finished product)

---

### Types of Segments/Audiences in AEP

#### 1. Batch Segments
- **Evaluation:** Once per day (scheduled, typically midnight)
- **Data:** Uses full profile data
- **Latency:** Updates daily
- **Use Case:** Weekly email campaigns, monthly reports
- **Example:** "Dormant customers who haven't purchased in 90 days"

#### 2. Streaming Segments
- **Evaluation:** Real-time, as profile updates occur
- **Data:** Uses streaming profile updates
- **Latency:** <5 minutes
- **Use Case:** Real-time triggers, urgent alerts
- **Example:** "Hot lead score just increased above 90 → Alert sales rep"

#### 3. Edge Segments
- **Evaluation:** At the edge (Adobe edge servers)
- **Data:** Subset of profile attributes (edge-enabled only)
- **Latency:** <50 milliseconds
- **Use Case:** Website personalization, Adobe Target A/B tests
- **Example:** "VIP customers → Show exclusive offers"

#### 4. External Audiences
- **Evaluation:** Outside AEP (in your data warehouse)
- **Data:** Your warehouse data
- **Latency:** Depends on refresh schedule (daily/hourly)
- **Use Case:** Leverage existing warehouse logic, zero-copy architecture
- **Example:** "BigQuery identifies hot leads → Import to AEP as audience"

#### 5. Static Audiences
- **Evaluation:** None (fixed list)
- **Data:** Manually uploaded CSV or API import
- **Latency:** Updated when you upload a new file
- **Use Case:** One-time campaigns, test audiences
- **Example:** "500 customers for VIP event invitation"

---

### Comparison Table

| Type | Where Evaluated | Update Frequency | Latency | Data Source | Use Case |
|------|----------------|------------------|---------|-------------|----------|
| **Batch Segment** | AEP Profile Store | Daily | 24 hours | AEP profiles | Weekly campaigns |
| **Streaming Segment** | AEP Profile Store | Real-time | <5 min | AEP profiles | Real-time triggers |
| **Edge Segment** | Adobe Edge servers | Real-time | <50ms | Edge-enabled attributes | Web personalization |
| **External Audience** | Your data warehouse | On-demand | Custom | BigQuery/Snowflake | Zero-copy, ML models |
| **Static Audience** | N/A (fixed list) | Manual upload | N/A | CSV/API | One-time campaigns |

---

### When to Use "Segment" vs "Audience"

**In Adobe's UI:**
- You BUILD a "Segment" (the definition/rule)
- You ACTIVATE an "Audience" (the resulting customer list)

**Common Usage:**
- "I created a segment for hot leads" = You defined the criteria
- "I activated the hot leads audience to Google Ads" = You sent the customer IDs

**External Audiences Terminology:**
- Adobe calls them "External Audiences" (not "External Segments")
- Because they're pre-computed lists, not dynamic rules

---

## Frequently Asked Questions

### AEP Basics

#### Q1: What's the difference between Adobe Analytics and AEP?

**Adobe Analytics:**
- Focuses on **website/app analytics** - tracking clicks, page views, conversions
- Answers questions like: "How many people visited our pricing page?"
- Data is aggregated, not individual-level
- Reports and dashboards for insights

**Adobe Experience Platform (AEP):**
- Focuses on **customer data management** - creating unified customer profiles
- Answers questions like: "Which specific customers are interested in Product X?"
- Data is individual-level (one profile per customer)
- Used for personalization, segmentation, and activation

**Analogy:**
- **Analytics** = Looking at a map (aggregate view of traffic patterns)
- **AEP** = GPS tracking individual cars (specific customer journeys)

**Can you use both?** Yes! Many companies use Analytics for reporting and AEP for activation.

---

#### Q2: Do I need to send ALL my customer data to AEP?

**Short Answer:** No, especially with Federated Audience Composition.

**Long Answer:**
- **Traditional AEP approach:** Yes, you send all customer data to create profiles in AEP's Profile Store
- **Zero-copy approach (Federated Audience Composition):** No, you can keep data in your warehouse and AEP just queries it

**What you MUST send (minimum):**
- Customer identifiers (email, CRM ID) for audience activation
- Any attributes needed for segmentation in AEP

**What you CAN keep in your warehouse:**
- Raw behavioral events
- Historical transactional data
- Sensitive PII you don't want in a third-party platform

**See also:** [Zero-Copy Architecture Options](#zero-copy-architecture)

---

#### Q3: How much does AEP cost? (Order of magnitude)

**Rough Pricing (2025):**

**RT-CDP Tiers:**
- **Foundation:** $100K-$150K/year (base features, lower profile limits)
- **Select:** $150K-$300K/year (more profiles, streaming segmentation)
- **Prime:** $250K-$500K/year (advanced features, higher limits)
- **Ultimate:** $500K-$1M+/year (enterprise scale, all features)

**Add-Ons:**
- **Journey Optimizer:** +$50K-$150K/year
- **Federated Audience Composition:** +$40K-$80K/year
- **Customer AI:** +$30K-$60K/year

**Pricing Factors:**
- Number of customer profiles (10M, 50M, 100M+)
- API call volume (streaming ingestion)
- Destinations (number of marketing channels)
- Company size and negotiation leverage

**Bottom Line:** Expect $200K-$700K/year for a typical mid-market implementation with RT-CDP + Journey Optimizer + Federated Audience Composition.

---

#### Q4: What's the difference between RT-CDP Foundation, Select, Prime, Ultimate?

**Foundation (Entry Tier):**
- Up to 10M profiles
- Batch segmentation only
- Limited destinations
- Basic identity graph
- **Best for:** Small companies, simple use cases

**Select (Mid Tier):**
- Up to 50M profiles
- Streaming segmentation
- More destinations
- Standard identity graph
- **Best for:** Mid-market companies, moderate complexity

**Prime (Advanced Tier):**
- Up to 100M profiles
- All segmentation types (batch, streaming, edge)
- All destinations
- Advanced identity graph features
- Customer AI, Attribution AI included
- **Best for:** Large enterprises, complex use cases

**Ultimate (Enterprise Tier):**
- Unlimited profiles (within reason)
- All Prime features
- Dedicated support
- Custom SLAs
- Priority feature access
- **Best for:** Fortune 500, global enterprises

**Note:** Exact limits and features vary by contract negotiation.

---

#### Q5: Can I use AEP without Journey Optimizer? Or vice versa?

**Yes, they're separate products:**

**RT-CDP alone:**
- Use if you only need audience creation and activation to destinations
- Don't need multi-step journey orchestration
- Example: Create "Hot Leads" segment → Activate to Google Ads (done)

**Journey Optimizer alone:**
- Technically possible but rare
- Most value comes from combining it with RT-CDP's audience capabilities

**RT-CDP + Journey Optimizer (Recommended):**
- RT-CDP creates unified profiles and segments
- Journey Optimizer orchestrates multi-step, multi-channel campaigns based on those segments
- Example: Hot Leads segment → Journey: Email Day 1 → SMS Day 3 → Sales call Day 7

**Bottom Line:** Most enterprises license both, but you can start with just RT-CDP.

---

### Data & Integration

#### Q6: How do I get data into AEP? (Sources)

**Method 1: Web/Mobile SDK (Real-Time Streaming)**
- Install Adobe Web SDK or Mobile SDK in your website/app
- Automatically sends events (page views, clicks, etc.) to AEP as they happen
- **Latency:** <1 second
- **Best for:** Real-time personalization

**Method 2: Batch File Upload**
- Upload CSV/Parquet files to AEP (via UI or API)
- Scheduled daily/weekly
- **Latency:** Hours to days
- **Best for:** CRM exports, offline data

**Method 3: Source Connectors (Pre-Built Integrations)**
- AEP provides 100+ connectors: Salesforce, Marketo, Google Ads, BigQuery, Snowflake, etc.
- Configure once, data syncs automatically (batch or streaming depending on connector)
- **Latency:** Varies by connector
- **Best for:** Connecting existing marketing tools

**Method 4: Streaming API (Custom Integration)**
- Your systems send data to AEP via HTTP API
- Real-time streaming
- **Latency:** <1 second
- **Best for:** Custom applications, real-time scoring systems

**Method 5: Federated Queries (No Data Upload)**
- AEP queries your BigQuery/Snowflake directly
- No data copied to AEP
- **Latency:** N/A (query on-demand)
- **Best for:** Zero-copy architecture

---

#### Q7: Where does AEP send data? (Destinations)

**Pre-Built Destinations (100+ supported):**

**Advertising Platforms:**
- Google Ads, Meta (Facebook/Instagram), LinkedIn Ads, TikTok, Pinterest, etc.

**Email & Marketing Automation:**
- Marketo, Eloqua, HubSpot, Salesforce Marketing Cloud, Braze, etc.

**Analytics & Data Warehouses:**
- Google Analytics, Adobe Analytics, BigQuery, Snowflake, Databricks, etc.

**CRM & Sales:**
- Salesforce, Dynamics 365, etc.

**Custom Destinations:**
- Your own APIs via webhook/HTTP streaming
- SFTP for file exports

**How it works:**
1. Create segment in AEP: "Hot Leads" (10,000 customers)
2. Activate to Google Ads
3. AEP sends 10,000 customer IDs (or emails) to Google Ads
4. Google Ads creates a custom audience
5. Your ads target only these 10,000 people

---

#### Q8: What's the Profile Store and do I have to use it?

**What it is:** AEP's database that stores unified customer profiles (all attributes, identities, segment memberships for each customer).

**Do you have to use it?**

**Traditional AEP:** Yes
- All data must be in Profile Store for segmentation
- Real-time lookups require profiles in the store
- Identity Graph, Customer AI, edge segmentation all require Profile Store

**With Federated Audience Composition:** No
- Profiles stay in your BigQuery/Snowflake
- AEP just queries your warehouse
- Profile Store only holds audience IDs (minimal data)

**Trade-Offs:**
- **Using Profile Store:** Full AEP features, vendor lock-in, higher cost
- **Skipping Profile Store (Federated):** Zero vendor lock-in, lower cost, limited features

---

#### Q9: Can AEP query my data warehouse directly? (Federated Audience Composition)

**Yes! This is the Federated Audience Composition feature (NEW in 2024/2025).**

**Supported Warehouses:**
- Google BigQuery ✅
- Snowflake ✅
- Databricks ✅
- Azure Synapse ✅
- Amazon Redshift ✅
- Oracle ✅
- Vertica ✅
- Microsoft Fabric ✅

**How it works:**
1. Configure secure connection from AEP to your warehouse (service account, VPN)
2. Build audience composition in AEP UI (drag-and-drop, like building SQL visually)
3. AEP executes query against your warehouse
4. Warehouse returns customer IDs matching criteria
5. AEP creates "External Audience" with just the IDs
6. Activate to destinations

**Data stays in your warehouse:** TRUE zero-copy architecture

**See also:** [Option 1: Federated Audience Composition](aep-zero-copy-executive-summary.md)

---

#### Q10: What happens to my data if I stop using AEP?

**If using Profile Store (traditional approach):**
- Profiles and historical data stored in AEP are LOST when you cancel
- You can export data before cancellation (via API or batch exports), but it's painful
- Segment definitions are AEP-specific, must rebuild in new platform

**If using Federated Audience Composition:**
- All data stays in your warehouse (BigQuery/Snowflake)
- You lose access to AEP's UI and activation capabilities
- But your data, models, and segmentation logic remain intact
- Easy to point a different platform at the same data

**Recommendation:** If vendor lock-in is a concern, use Federated Audience Composition or keep all business logic in your warehouse.

---

### Identity & Profiles

#### Q11: Why is identity stitching important?

**See full deep dive:** [Identity Stitching - Deep Dive](#identity-stitching---deep-dive)

**Quick Answer:**
- Customers interact via multiple devices/channels (web, mobile, email, phone)
- Identity stitching connects these touchpoints into ONE unified profile
- Enables: Personalization, attribution, consistent experience

**Without identity stitching:**
- Anonymous visitor on laptop ≠ Known customer on mobile app (treated as 2 people)

**With identity stitching:**
- Same person recognized across laptop, mobile, email → Unified experience

**When NOT needed:**
- Single-channel campaigns (email-only)
- No cross-device tracking required
- Using Federated Audience Composition (do identity resolution in your warehouse instead)

---

#### Q12: What if I don't need cross-device tracking?

**Great news:** You can simplify significantly.

**Scenarios where cross-device tracking is NOT needed:**

**1. B2B Email Campaigns Only**
- You only send emails to business contacts
- Email address is the sole identifier
- No website personalization, no mobile app

**Recommendation:** Skip AEP Identity Graph. Use email as primary ID.

**2. Anonymous Website Analytics**
- You track website traffic patterns (not individual users)
- No personalization needed

**Recommendation:** Use Adobe Analytics instead of AEP.

**3. Server-Side Lead Scoring**
- You score leads in your CRM or data warehouse
- No need to track individual web sessions

**Recommendation:** Use Federated Audience Composition to query your warehouse.

---

#### Q13: How does AEP handle anonymous visitors?

**Flow:**

**1. First Visit (Anonymous):**
- User visits website for the first time
- Adobe SDK assigns a cookie ID (ECID - Experience Cloud ID): `abc123`
- Profile created with ECID only
- No email, name, or known attributes yet

**2. User Takes Action (Becomes Known):**
- User fills out form, providing email: `john@company.com`
- OR user logs in with existing account

**3. Identity Stitching Happens:**
- AEP links ECID `abc123` ↔ Email `john@company.com`
- Anonymous profile merges with known profile
- All past anonymous activity now attributed to John

**4. Future Visits:**
- User returns (cookie still present OR logs in)
- AEP recognizes: "This is John, our hot lead!"
- Personalized experience starts

**Example:**
- **Monday (Anonymous):** Visitor `abc123` views Product X pricing page
- **Tuesday (Becomes Known):** Visitor fills form, provides email `john@company.com`
- **Wednesday (Personalized):** John returns → Website shows: "Welcome back! Still interested in Product X?"

---

#### Q14: Can I use my own customer IDs instead of AEP's Identity Graph?

**Yes! Two approaches:**

**Approach 1: Use Your CRM ID as Primary Identity**
- Skip AEP's Identity Graph entirely
- Use your existing CRM customer ID as the primary identifier
- All data keyed by CRM ID
- **Pro:** Simple, you control the logic
- **Con:** No automatic cross-device stitching

**Approach 2: Hybrid (Your ID + AEP Identity Graph)**
- Use your CRM ID as primary
- Let AEP Identity Graph link cookie/mobile IDs to your CRM ID
- **Pro:** Best of both worlds
- **Con:** More complex setup

**Approach 3: Federated Audience Composition**
- Do ALL identity resolution in your BigQuery/Snowflake
- AEP doesn't handle identities at all, just queries your data
- **Pro:** Complete control, zero vendor lock-in
- **Con:** You build and maintain identity logic yourself

**Most common:** Approach 2 (Hybrid) for enterprises with existing CRM systems.

---

### Segmentation & Activation

#### Q15: What's the difference between segments and audiences?

**See full explanation:** [Segments vs Audiences](#segments-vs-audiences---whats-the-difference)

**Quick Answer:**
- **Segment:** The rule/definition (e.g., "Customers who purchased in last 30 days")
- **Audience:** The actual list of customer IDs matching that rule at a specific time

**Think of it like:**
- Segment = Recipe
- Audience = Finished cake

**In practice:** You BUILD a segment, you ACTIVATE an audience.

---

#### Q16: How fast can I create and activate an audience?

**Depends on the type:**

**Batch Segment:**
- **Create:** 5-30 minutes (design segment in UI)
- **Evaluate:** 24 hours (overnight batch job)
- **Activate:** 1-2 hours (send to destination)
- **Total:** ~26-27 hours from creation to activation

**Streaming Segment:**
- **Create:** 5-30 minutes
- **Evaluate:** Real-time (as profiles update)
- **Activate:** <5 minutes
- **Total:** <1 hour from creation to first activation

**Federated Audience (External):**
- **Create:** 10-60 minutes (build query in AEP or SQL in warehouse)
- **Evaluate:** Depends on warehouse query speed (minutes to hours)
- **Activate:** 30 min - 2 hours
- **Total:** 1-4 hours

**Edge Segment:**
- **Create:** 5-30 minutes
- **Evaluate:** <50 milliseconds (at edge)
- **Activate:** Immediate (for web/Target use cases)
- **Total:** Same day

---

#### Q17: What's edge segmentation and when do I need it?

**See full deep dive:** [Edge Segmentation - Deep Dive](#edge-segmentation---deep-dive)

**Quick Answer:**
- **What:** Ultra-fast segmentation (<50ms) on edge servers near the user
- **When:** Real-time website personalization, Adobe Target A/B tests, mobile app in-session experiences

**Examples:**
- Show different homepage hero based on VIP status
- A/B test personalized for customer segment
- Mobile app shows different screen for new vs returning users

**When NOT needed:**
- Batch email campaigns (no one cares if segment evaluation takes 24 hours)
- Backend processing (doesn't need <50ms latency)

---

#### Q18: Can I use SQL to create segments?

**Not directly in AEP's UI, but YES via Federated Audience Composition:**

**Traditional AEP Segment Builder:**
- Drag-and-drop UI (no SQL)
- Build conditions like: `lead_score > 80 AND region = 'California'`
- No SQL knowledge required

**AEP Query Service (Advanced):**
- Write SQL queries against AEP's data lake
- For data exploration, not real-time segmentation

**Federated Audience Composition (BEST for SQL users):**
- Write SQL directly in your BigQuery/Snowflake
- AEP executes your query and imports results as an audience
- **Example:**
```sql
SELECT customer_id
FROM `project.dataset.customers`
WHERE lead_score > 80
  AND last_purchase_date > DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
  AND total_lifetime_value > 10000
```
- AEP imports the customer IDs as an External Audience

**Bottom Line:** If you love SQL, use Federated Audience Composition. If you prefer UI, use Segment Builder.

---

#### Q19: What are External Audiences?

**Definition:** Audience lists created OUTSIDE of AEP (in your data warehouse, via CSV, or using Federated Audience Composition) and imported into AEP.

**How they work:**
1. You identify customers in your system (BigQuery, Snowflake, CSV)
2. Upload list of customer IDs to AEP (via API, file upload, or Federated Audience Composition)
3. AEP creates an "External Audience" with these IDs
4. Activate to destinations like any other audience

**Key Difference from Regular Segments:**
- Regular segments: AEP defines the logic, evaluates against Profile Store
- External audiences: YOU define the logic, AEP just receives the results

**Use Cases:**
- Complex ML models in your warehouse
- Leverage existing data pipelines
- Zero-copy architecture (Federated Audience Composition)

**Limitations:**
- Static (not re-evaluated by AEP automatically)
- 30-day TTL by default (must refresh periodically)
- Can't use AEP segment builder to modify the logic

---

#### Q33: What is audience composition? What's actually happening underneath? What does an audience look like when activated?

**Short Answer:** Audience composition is the process of evaluating segment rules against your data to produce a list of customer IDs. When activated, an audience typically contains customer IDs + optional enrichment fields (email, name, etc.) sent to destinations.

---

### What is Audience Composition?

**Definition:** The process of taking a segment definition (rules/criteria) and executing it against your customer data to produce an **audience** (the actual list of customer IDs that match).

**Think of it like:**
- **Segment Definition** = SQL WHERE clause: `WHERE lead_score > 80 AND region = 'California'`
- **Audience Composition** = Running the query and getting results: 5,432 customer IDs

---

### What's Actually Happening Underneath?

**Step-by-Step Process:**

**1. Segment Evaluation (Composition)**

**Traditional AEP (Profile Store):**
```
User clicks "Build Audience" in AEP UI
  ↓
AEP Segmentation Engine evaluates rules against Profile Store
  ↓
Example Rule: "lead_score > 80 AND last_purchase_date < 30 days ago"
  ↓
Segmentation Engine scans 10 million profiles
  ↓
Finds 50,000 profiles matching criteria
  ↓
Audience created with 50,000 customer IDs
```

**Federated Audience Composition (BigQuery):**
```
User clicks "Build Audience" in AEP UI
  ↓
AEP generates SQL query from visual composition
  ↓
Example SQL:
  SELECT partnerId, email, firstName
  FROM `project.dataset.customers`
  WHERE lead_score > 80 AND last_purchase_date > DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
  ↓
AEP sends query to BigQuery
  ↓
BigQuery executes query (2-10 seconds)
  ↓
BigQuery returns 50,000 rows (partnerId, email, firstName)
  ↓
AEP creates "External Audience" with these 50,000 IDs + enrichment fields
```

---

**2. Audience Storage**

**What AEP stores:**
- Customer IDs (partnerId, email, ECID, etc.)
- Optional enrichment fields (first name, last name, phone, etc.)
- Segment membership metadata (when customer joined audience, last qualification time)

**Example Audience Record in AEP:**
```json
{
  "audienceId": "aud_12345",
  "audienceName": "Hot Leads - California",
  "members": [
    {
      "partnerId": "P123456",
      "email": "john@example.com",
      "firstName": "John",
      "lastName": "Doe",
      "phone": "+1-555-0100",
      "qualifiedAt": "2025-10-22T10:30:00Z"
    },
    {
      "partnerId": "P123457",
      "email": "jane@example.com",
      "firstName": "Jane",
      "lastName": "Smith",
      "qualifiedAt": "2025-10-22T10:30:00Z"
    }
    // ... 49,998 more members
  ],
  "totalMembers": 50000,
  "lastEvaluated": "2025-10-22T10:30:00Z"
}
```

---

### Is It Just About Selecting Customer IDs?

**Short Answer:** Mostly YES, but you can include additional enrichment fields.

**Minimum Required:**
- **Customer identifier** (partnerId, email, ECID, phone, etc.)
  - At least ONE identifier that the destination platform can use

**Optional Enrichment Fields:**
- First name, last name
- Email address (if not the primary identifier)
- Phone number
- Custom attributes (VIP tier, lead score, product interests, etc.)

**Example Scenarios:**

**Scenario 1: Just IDs (Minimal)**
```sql
-- Federated Audience Composition Query
SELECT partnerId
FROM `project.dataset.customers`
WHERE lead_score > 80
```

**Result:** Audience contains ONLY customer IDs
```
partnerId
---------
P123456
P123457
P123458
...
```

**When to use:** Destination already has customer data (e.g., activating to your own CRM or data warehouse)

---

**Scenario 2: IDs + Enrichment Fields (Common)**
```sql
-- Federated Audience Composition Query
SELECT
  partnerId,
  email,
  firstName,
  lastName,
  leadScore,
  productInterest
FROM `project.dataset.customers`
WHERE lead_score > 80
```

**Result:** Audience contains IDs + enrichment data
```
partnerId | email              | firstName | lastName | leadScore | productInterest
----------|-------------------|-----------|----------|-----------|------------------
P123456   | john@example.com  | John      | Doe      | 92        | Enterprise Plan
P123457   | jane@example.com  | Jane      | Smith    | 85        | Pro Plan
...
```

**When to use:** Destination needs additional fields for personalization (e.g., email campaigns that use firstName in subject line)

---

### How Does an Audience Look When Activated?

**Activation = Sending audience data to a destination (Google Ads, Marketo, Salesforce, etc.)**

**What gets sent depends on the destination:**

---

**Example 1: Email Campaign Activation (Marketo)**

**Use Case:** Send email to "Hot Leads" audience

**What AEP Sends to Marketo:**
```json
{
  "audienceName": "Hot Leads - California",
  "members": [
    {
      "email": "john@example.com",
      "firstName": "John",
      "lastName": "Doe",
      "leadScore": 92,
      "productInterest": "Enterprise Plan"
    },
    {
      "email": "jane@example.com",
      "firstName": "Jane",
      "lastName": "Smith",
      "leadScore": 85,
      "productInterest": "Pro Plan"
    }
    // ... 49,998 more
  ]
}
```

**What Marketo Does:**
1. Receives 50,000 email addresses + enrichment fields
2. Creates a static list: "Hot Leads - California"
3. Marketing team creates email campaign
4. Email template uses `{{firstName}}` and `{{productInterest}}` for personalization
5. Email sent: "Hi John, interested in our Enterprise Plan? Here's a special offer..."

**Activation Frequency:**
- One-time upload OR
- Daily/hourly sync (audience membership refreshes)

---

**Example 2: Google Ads Activation**

**Use Case:** Target ads to "Hot Leads" audience

**What AEP Sends to Google Ads:**

**Option A: Hashed Emails (Most Common)**
```json
{
  "audienceName": "Hot Leads - California",
  "matchKeys": "EMAIL",
  "members": [
    "a665a45920422f9d417e4867efdc4fb8a04a1f3fff1fa07e998e86f7f7a27ae3",  // SHA256(john@example.com)
    "96d9632f363564cc3032521409cf22a852f2032eec099ed5967c0d000cec607a",  // SHA256(jane@example.com)
    // ... 49,998 more hashed emails
  ]
}
```

**Option B: Mobile Advertising IDs**
```json
{
  "audienceName": "Hot Leads - California",
  "matchKeys": "MOBILE_ADVERTISING_ID",
  "members": [
    "38400000-8cf0-11bd-b23e-10b96e40000d",  // Google Advertising ID (GAID)
    "a8f3b2c1-9d4e-4567-8901-2b3c4d5e6f7a",  // GAID
    // ...
  ]
}
```

**What Google Ads Does:**
1. Receives hashed emails or mobile IDs
2. Matches against Google's user database
3. Creates custom audience in Google Ads
4. Estimated match rate: 40-70% (many emails won't match Google users)
5. Ads target the matched users

**Key Point:** Google Ads doesn't receive enrichment fields (leadScore, firstName, etc.). It only receives identifiers for matching.

---

**Example 3: Webhook/API Activation (Custom Destination)**

**Use Case:** Send audience to your own API for custom processing

**What AEP Sends to Your API:**
```http
POST https://your-api.com/audiences/activate
Content-Type: application/json

{
  "audienceId": "aud_12345",
  "audienceName": "Hot Leads - California",
  "timestamp": "2025-10-22T10:30:00Z",
  "members": [
    {
      "partnerId": "P123456",
      "email": "john@example.com",
      "firstName": "John",
      "lastName": "Doe",
      "leadScore": 92,
      "productInterest": "Enterprise Plan",
      "customField1": "value1",
      "customField2": "value2"
    },
    {
      "partnerId": "P123457",
      "email": "jane@example.com",
      "firstName": "Jane",
      "lastName": "Smith",
      "leadScore": 85,
      "productInterest": "Pro Plan"
    }
    // ... 49,998 more
  ]
}
```

**Flexibility:** You control the payload structure and can include as many enrichment fields as needed.

---

### Can There Be More Fields? How Many?

**Yes! You can include enrichment fields, but there are practical limits:**

**Typical Limits:**

**1. AEP Profile Store Approach:**
- You can select ANY profile attributes for activation
- Common: 5-20 enrichment fields
- Maximum: 100+ fields (technically possible, but rare)
- **Limitation:** Destination APIs may have field limits (e.g., Marketo limits ~100 custom fields per record)

**2. Federated Audience Composition:**
- You SELECT which fields to include in your SQL query
- **Example:**
```sql
SELECT
  partnerId,
  email,
  firstName,
  lastName,
  leadScore,
  productInterest,
  industrySegment,
  companySize,
  lastPurchaseDate,
  totalLifetimeValue
FROM `project.dataset.customers`
WHERE lead_score > 80
```
- You can include as many fields as your SQL query returns
- **Best Practice:** Only include fields the destination actually needs (reduces data transfer costs)

**3. Destination Limits:**
- Each destination has its own limits:
  - **Google Ads:** Only accepts identifiers (email, phone, mobile ID) - NO enrichment fields
  - **Marketo:** Accepts 100+ fields for personalization
  - **Salesforce:** Accepts standard + custom fields (depends on your Salesforce schema)
  - **Custom Webhooks:** You define the schema (unlimited fields)

---

### Real-World Example: Email Campaign Activation

**Use Case:** Send personalized email to Hot Leads with product recommendations

**Step 1: Build Audience in AEP (Federated Audience Composition)**

```sql
SELECT
  customer_id,
  email,
  first_name,
  last_name,
  lead_score,
  product_interest,
  industry,
  company_size,
  last_interaction_date
FROM `banking-project.marketing.customer_profiles`
WHERE
  lead_score > 80
  AND last_interaction_date > DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
  AND product_interest IN ('Enterprise Plan', 'Pro Plan')
  AND region = 'California'
```

**Result:** 5,432 customer IDs + enrichment fields

---

**Step 2: Audience Composition Completes**

AEP creates "Hot Leads - California" audience with 5,432 members:

```
customer_id | email            | first_name | lead_score | product_interest | industry | company_size
------------|------------------|------------|------------|------------------|----------|-------------
C001        | john@example.com | John       | 92         | Enterprise Plan  | Finance  | 500-1000
C002        | jane@example.com | Jane       | 85         | Pro Plan         | Healthcare | 100-500
...
```

---

**Step 3: Activate to Marketo**

AEP sends audience to Marketo via API:

```json
POST https://marketo-api.com/lists/import
{
  "listName": "Hot Leads - California",
  "members": [
    {
      "email": "john@example.com",
      "firstName": "John",
      "lastName": "Doe",
      "leadScore": 92,
      "productInterest": "Enterprise Plan",
      "industry": "Finance",
      "companySize": "500-1000"
    },
    {
      "email": "jane@example.com",
      "firstName": "Jane",
      "lastName": "Smith",
      "leadScore": 85,
      "productInterest": "Pro Plan",
      "industry": "Healthcare",
      "companySize": "100-500"
    }
    // ... 5,430 more
  ]
}
```

---

**Step 4: Marketo Processes Audience**

- Marketo creates static list: "Hot Leads - California" (5,432 contacts)
- Marketing team creates email template:

```html
<h1>Hi {{firstName}},</h1>
<p>We noticed you're interested in our {{productInterest}}.</p>
<p>As a {{industry}} company with {{companySize}} employees,
   here's a personalized offer just for you...</p>
<a href="https://example.com/offer?plan={{productInterest}}">
  View Offer
</a>
```

---

**Step 5: Email Sent**

Each customer receives personalized email:

**John's Email:**
```
Hi John,

We noticed you're interested in our Enterprise Plan.
As a Finance company with 500-1000 employees, here's a
personalized offer just for you...

[View Offer]
```

**Jane's Email:**
```
Hi Jane,

We noticed you're interested in our Pro Plan.
As a Healthcare company with 100-500 employees, here's a
personalized offer just for you...

[View Offer]
```

---

### Key Takeaways

**1. Audience Composition = Execution of Segment Rules**
- Segment = Recipe (rules/criteria)
- Audience Composition = Cooking the recipe (execution)
- Audience = Finished dish (list of customer IDs + optional enrichment)

**2. What Gets Sent to Destinations:**
- **Minimum:** Customer identifiers (partnerId, email, phone, etc.)
- **Common:** IDs + 5-20 enrichment fields (name, score, interests, etc.)
- **Depends on destination:** Google Ads only accepts IDs; Marketo accepts 100+ fields

**3. Federated Audience Composition:**
- You control what fields to include in SQL SELECT clause
- Only selected fields are transferred to AEP
- TRUE zero-copy: All other data stays in BigQuery

**4. Traditional AEP (Profile Store):**
- All profile attributes available for activation
- Select which fields to send to each destination
- Data already in AEP, so no query latency

**5. Practical Example Flow:**
```
Build Audience (SQL or UI rules)
  ↓
Evaluate against data (BigQuery or AEP Profile Store)
  ↓
Audience Created (customer IDs + enrichment fields)
  ↓
Activate to Destination (Marketo, Google Ads, etc.)
  ↓
Destination uses IDs to match users + enrichment for personalization
```

**6. Best Practice:**
- Only include enrichment fields that the destination actually uses
- Too many fields = unnecessary data transfer costs
- Too few fields = missed personalization opportunities
- Sweet spot: 5-10 enrichment fields for most use cases

---

### Zero-Copy Architecture

#### Q20: Can I use AEP without copying all my data into it?

**Yes! Federated Audience Composition enables TRUE zero-copy architecture.**

**The Problem:**
- Traditional AEP: Copy all customer data (100+ fields per profile, millions of profiles) from your systems to AEP
- Result: Massive data transfer, duplication, sync complexity, vendor lock-in

**The Solution (Federated Audience Composition):**
- Keep ALL data in your warehouse (BigQuery, Snowflake)
- AEP queries your warehouse when you build audiences
- Only audience IDs transferred to AEP (not full profiles)
- **Result:** 99.96% data reduction, zero vendor lock-in

**See:** [Option 1: Federated Audience Composition](aep-zero-copy-executive-summary.md)

---

#### Q21: What's Federated Audience Composition?

**See full glossary entry:** [Federated Audience Composition](#federated-audience-composition)

**Elevator Pitch:**
- NEW AEP capability (2024/2025)
- AEP queries your BigQuery/Snowflake DIRECTLY
- No data copied to AEP
- Build audiences using drag-and-drop UI
- AEP executes query, gets customer IDs, activates to destinations
- **TRUE zero-copy architecture**

**Supported Warehouses:** BigQuery, Snowflake, Databricks, Azure Synapse, Redshift, Oracle, Vertica, Microsoft Fabric

**Cost:** $40K-$80K/year add-on (on top of RT-CDP license)

---

#### Q22: If I use Federated Audience Composition, what AEP features do I lose?

**Features NOT Available with Federated Audience Composition:**

❌ **Real-Time Customer Profile lookups** (<100ms)
- Can't power website personalization requiring instant profile data

❌ **AEP Identity Graph**
- Must do identity stitching in your warehouse yourself

❌ **Customer AI / Attribution AI**
- Adobe's AI services require profiles in AEP Profile Store

❌ **Edge Segmentation**
- Requires profiles on edge servers

❌ **Streaming Segmentation**
- Federated audiences are batch-only (daily/hourly refresh)

❌ **Profile Enrichment from Multiple Sources**
- If you query BigQuery, you can't also enrich with Salesforce data in real-time (unless you join it in BigQuery)

**Features STILL Available:**

✅ **Batch Segmentation**
- Daily/weekly audience creation

✅ **Activation to Destinations**
- Google Ads, Marketo, Meta, etc. work fine

✅ **Journey Optimizer**
- Can use External Audiences in journeys

✅ **Audience Composition UI**
- Drag-and-drop query builder

**Bottom Line:** If you need real-time (<5 min) or Customer AI, use Option 2 or 3. If batch campaigns (daily/weekly) are sufficient, Federated Audience Composition (Option 1) is perfect.

---

#### Q23: Should I use Federated Audience Composition or stream computed attributes?

**Use Decision Tree:**

**Choose Federated Audience Composition (Option 1) if:**
- ✅ Batch campaigns (daily/weekly) are sufficient
- ✅ Vendor lock-in is a major concern
- ✅ Data sovereignty is critical (data must stay in your region/cloud)
- ✅ Cost optimization is a priority
- ✅ You have strong data engineering in BigQuery/Snowflake
- ✅ You don't need Customer AI or Identity Graph

**Choose Computed Attributes (Option 2) if:**
- ✅ Real-time (<5 min) activation is required
- ✅ You need Customer AI or Attribution AI
- ✅ Cross-device identity stitching via AEP Identity Graph is valuable
- ✅ You want business users to build segments in AEP UI (not SQL)
- ✅ Website personalization requiring <100ms lookups

**Choose Hybrid (Option 3) if:**
- ✅ You need BOTH batch (99%) and real-time (1%)
- ✅ Most use cases are batch, but a few critical flows need real-time
- ✅ You want cost efficiency of Federated for bulk + real-time for high-value segments

**See full comparison:** [AEP Zero-Copy Executive Summary](aep-zero-copy-executive-summary.md)

---

#### Q24: Can I start with Federated and add real-time later?

**Yes! This is the "Hybrid Selective" approach (Option 3).**

**Phased Rollout:**

**Phase 1 (Weeks 1-4): Federated Only**
- Implement Federated Audience Composition for ALL use cases
- Daily/weekly batch audiences
- Low cost, fast implementation
- Prove value with 80-90% of use cases

**Phase 2 (Months 2-3): Identify Real-Time Needs**
- Audit use cases: Which ones would benefit from <5 min latency?
- Quantify ROI: "Sales alerts for hot leads generate $500K/year"
- Select 1-3 critical real-time use cases

**Phase 3 (Months 3-6): Add Streaming for Real-Time Subset**
- Stream computed attributes for <10% of profiles
- Enable real-time segmentation for specific use cases
- Keep 90%+ as federated (cost-efficient)

**Result:** Best of both worlds - 99% federated (low cost, low lock-in) + 1% real-time (high value, targeted)

**See:** [Option 3: Hybrid Selective Pattern](aep-zero-copy-executive-summary.md)

---

### Costs & Licensing

#### Q25: How is AEP priced? (Profiles, API calls, storage?)

**Primary Pricing Dimension: Number of Addressable Profiles**

**What's an "Addressable Profile"?**
- A customer profile that can be activated to marketing channels
- Excludes: Anonymous visitors who never identified themselves, test profiles, deleted profiles

**Tiers:**
- 0-10M profiles: Foundation/Select tier
- 10M-50M profiles: Select/Prime tier
- 50M-100M profiles: Prime tier
- 100M+ profiles: Ultimate tier (custom pricing)

**Additional Costs (May Apply):**
- **API Calls (Streaming Ingestion):** Some contracts charge per 1K API calls (~$0.10-$0.50 per 1K)
- **Storage:** Profile storage costs (typically bundled, but can be metered at very high volumes)
- **Compute (Query Service):** If using AEP Query Service heavily, compute hours may be charged
- **Destinations:** Some destination connectors have per-activation fees
- **Add-Ons:** Customer AI, Federated Audience Composition, Attribution AI (separate SKUs)

**Typical Contract Structure:**
- Base RT-CDP license: $200K/year (includes X million profiles, Y API calls)
- Journey Optimizer: +$100K/year
- Federated Audience Composition: +$50K/year
- Overage charges if you exceed profile/API limits

**Bottom Line:** Pricing is primarily profile-based, with add-ons for premium features. Negotiate your contract carefully.

---

#### Q26: What's the minimum commitment for AEP?

**Typical Minimum:**
- **1-year contract** for Foundation/Select tiers
- **3-year contract** for Prime/Ultimate tiers (with better pricing)

**Profile Minimums:**
- Foundation: Often starts at 1M-5M profiles (though you may have fewer)
- Select: 5M-10M profiles
- Prime: 10M+ profiles

**Dollar Minimums:**
- Expect $150K-$200K/year MINIMUM total spend (RT-CDP + add-ons)
- Smaller companies might negotiate lower, but Adobe targets enterprise

**What happens if you're below minimums?**
- You still pay for the minimum tier (e.g., if you have 2M profiles but license is 5M minimum, you pay for 5M)

**Can you cancel early?**
- Usually NO - contracts are binding
- Early termination fees apply (often 50-100% of remaining contract value)

**Bottom Line:** AEP is an enterprise platform with enterprise commitments. Not ideal for small businesses or short-term experiments.

---

#### Q27: Are there hidden costs I should know about?

**Yes, watch out for these:**

**1. Professional Services / Implementation**
- Adobe may require or strongly recommend their Professional Services team
- Cost: $50K-$200K for implementation (6-12 weeks)
- Includes: Schema design, data ingestion setup, segment building, training

**2. API Overage Charges**
- If you exceed your contracted API call limit, overage fees kick in
- Example: Contract includes 100M API calls/month, you use 150M → Pay for 50M overage
- Rate: ~$0.10-$0.50 per 1,000 extra calls

**3. Profile Overage Charges**
- Similar to API overages
- If licensed for 10M profiles but have 12M → Pay for 2M overage
- Rate: Varies by tier and contract

**4. Destination Connector Fees**
- Some destinations (especially enterprise ones) may have per-activation fees
- Example: Activating to Salesforce Marketing Cloud might incur SFMC API costs

**5. Data Egress (Network Transfer)**
- If AEP sends large volumes of data to destinations, network egress fees may apply
- Usually not significant unless sending TBs

**6. Training & Enablement**
- Adobe University courses, workshops, certifications
- Cost: $5K-$20K for team training

**7. Ongoing Support**
- Standard support included
- Premium support (faster response times, dedicated CSM): +$20K-$50K/year

**Bottom Line:** Budget 20-30% on top of license costs for these hidden expenses. First-year total cost is often 2x the license fee.

---

#### Q28: How can I reduce AEP costs?

**Strategy 1: Use Federated Audience Composition**
- Avoid copying all data to AEP (Profile Store costs)
- Reduce API ingestion costs (no streaming)
- **Savings:** 30-50% vs full profile ingestion

**Strategy 2: Start with Lower Tier**
- Begin with Foundation or Select instead of jumping to Prime
- Upgrade later when you prove ROI

**Strategy 3: Optimize Profile Counts**
- Remove inactive/churned customers from Profile Store
- Don't create profiles for every anonymous visitor (use thresholds: e.g., only create profile if visitor engages 3+ times)
- **Savings:** 10-20% by reducing billable profiles

**Strategy 4: Batch Instead of Streaming**
- Use batch ingestion where real-time isn't required
- Reduces API call costs significantly
- **Savings:** 40-60% on ingestion costs

**Strategy 5: Limit Edge Segmentation**
- Only enable edge projection for critical attributes (not all 100+ fields)
- Reduces edge server costs

**Strategy 6: Negotiate Multi-Year Contracts**
- 3-year commit often gets 15-25% discount vs 1-year

**Strategy 7: Challenge the Need for AEP**
- If your use case is simple (batch email campaigns only), consider cheaper alternatives:
  - Segment.com: 50% cheaper
  - Reverse ETL tools (Census, Hightouch): 70% cheaper
  - DIY with BigQuery + Dataflow: 80% cheaper

**Strategy 8: Hybrid Approach (Option 3)**
- Federated for 99% of use cases
- Streaming for 1% high-value real-time needs
- **Savings:** 20-40% vs full streaming approach

**Bottom Line:** The biggest savings come from NOT storing full profiles in AEP (use Federated Audience Composition).

#### Q29: Where did Pattern 2 (Reference Architecture with External Profile Store) come from? Who's using it?

**Honest Answer:** Pattern 2 is a **conceptual pattern** I described based on general data minimization principles, NOT an officially documented Adobe pattern with published case studies.

**Origins:**
- This pattern combines concepts from "profile stubs" and "external enrichment" architectures
- Similar approaches are discussed in CDP/data architecture circles (conferences, consulting engagements)
- NOT a named Adobe pattern with official documentation

**Who Might Use This?**
- Organizations exploring AEP but wanting to minimize vendor lock-in
- Companies with strict data residency requirements (can't store full profiles in US/EU Adobe data centers)
- POC/pilot projects where teams want to test AEP activation capabilities without full commitment

**Sources / Evidence:**
- **Conceptual basis:** General data architecture best practices (external systems of record, profile enrichment patterns)
- **No public case studies:** Adobe doesn't publish case studies of customers using this "profile stub" approach (likely because it undermines AEP's core value proposition)
- **Anecdotal:** I've seen variations of this in architecture discussions, but no formal documentation

**Honest Assessment:**
- If you're primarily using this pattern, you're probably NOT getting good value from AEP
- Adobe would likely recommend either:
  1. Use Federated Audience Composition (Option 1) instead - officially supported zero-copy approach
  2. Commit to full profile ingestion (Option 2) to unlock all AEP features

**Alternative with Official Support:**
- **Use Federated Audience Composition (Option 1)** instead of Pattern 2
- It's Adobe's official zero-copy solution (launched 2024/2025)
- Better supported, documented, and more reliable than the conceptual "profile stub" pattern

**Bottom Line:** Pattern 2 is a theoretical approach, not a widely adopted or Adobe-blessed pattern. For production zero-copy architecture, use Federated Audience Composition (Option 1).

---

#### Q30: If I use a single partnerId in both AEP and BigQuery, do I still need identity stitching?

**Short Answer:** No, you likely DON'T need AEP's Identity Graph if you already have a deterministic single ID.

**Context of Your Architecture:**
- You use `partnerId` as the primary key in BigQuery
- You send `partnerId` + email + minimal attributes to AEP
- All systems (web, mobile, CRM, email) already use this same `partnerId`

**When Identity Stitching is NOT Needed:**

**Scenario 1: Single Deterministic ID (Your Case)**
```
Your Architecture:
  Web visit → User logs in → partnerId assigned → All subsequent events tagged with partnerId
  Mobile app → User logs in → Same partnerId → All events tagged
  Email click → partnerId in URL parameter → Event tagged

Result: ONE identifier across all channels = partnerId
```

**No identity stitching needed because:**
- You already have a deterministic single ID (`partnerId`)
- No need to link email ↔ cookie ↔ mobile device ID (they all already have `partnerId`)
- Identity resolution is ALREADY done in your systems before data reaches AEP

**With Federated Audience Composition:**
- You query BigQuery using `partnerId`
- AEP gets customer IDs (partnerId values)
- AEP activates these IDs to destinations
- **Identity Graph not needed at all**

**When Identity Stitching IS Needed:**

**Scenario 2: Multiple Disparate Identifiers**
```
E-commerce Architecture (No Single ID):
  Web visit → Anonymous cookie: abc123
  User fills form → Email: john@example.com (but still cookie abc123)
  Mobile app download → Device ID: xyz789 (AEP doesn't know this is same person as cookie abc123)
  Call center → Phone: +1-555-0100 (AEP doesn't know this is john@example.com)

Problem: 4 identifiers, no linkage = AEP sees 4 different people
Solution: AEP Identity Graph links abc123 ↔ john@example.com ↔ xyz789 ↔ +1-555-0100
```

**Your Situation (Minimal Profile with partnerId + Email):**

If you send to AEP:
```json
{
  "partnerId": "12345",
  "email": "john@example.com",
  "leadScore": 85,
  "lastInteractionDate": "2025-10-21"
}
```

**Identity linking scenarios:**

**Case A: You only use partnerId for activation**
- Destinations receive: `partnerId=12345`
- No email linking needed
- **Identity Graph: NOT NEEDED**

**Case B: You want to activate with email to some destinations**
- Destinations receive: `email=john@example.com` OR `partnerId=12345` (depending on destination)
- AEP needs to know: partnerId 12345 = john@example.com (but you already provided this in same record!)
- **Identity Graph: NOT NEEDED** (identity map in record is sufficient)

**Case C: You have anonymous web visitors that later become known**
- Web visitor → Cookie abc123 (no partnerId yet)
- User logs in → Cookie abc123 + partnerId 12345 linked
- Now you want past anonymous behavior (abc123 events) attributed to partnerId 12345
- **Identity Graph: NEEDED** (to link cookie → partnerId)

**Recommendation for Your Use Case:**

**If ALL data already has partnerId:**
- ✅ Skip AEP Identity Graph
- ✅ Use partnerId as primary identifier everywhere
- ✅ With Federated Audience Composition: No identity stitching in AEP needed
- ✅ Simpler architecture, less cost

**If you have anonymous visitors (web/mobile) before they identify:**
- ⚠️ You might need Identity Graph to link: Anonymous cookie → partnerId (after login)
- But this only matters if you care about pre-login behavior attribution

**Bottom Line:**
- Your use of a single `partnerId` across systems is IDEAL for zero-copy architecture
- You've already solved identity resolution in your systems (before AEP)
- With Federated Audience Composition, AEP just queries BigQuery using `partnerId` - no identity graph needed
- **Save money**: Don't pay for Identity Graph features you don't need

---

#### Q31: What are real-world use cases for edge segmentation?

**See also:** [Edge Segmentation - Deep Dive](#edge-segmentation---deep-dive)

**Concrete Use Cases:**

**1. E-Commerce Homepage Personalization**

**Scenario:**
- Customer visits homepage
- Edge segment evaluated in <30ms: "Is this customer a VIP?"
- If YES → Show: "Welcome back, VIP! Your exclusive 20% discount code: VIP2025"
- If NO → Show: Generic "Welcome! Browse our latest products"

**Why edge matters:**
- Homepage loads in 1-2 seconds total
- Can't wait 200-500ms for AEP Profile Store query (bad UX, slow page load)
- Edge responds in <30ms → seamless experience

**Business Impact:** Higher VIP engagement, increased conversion

---

**2. Adobe Target A/B Testing with Segmentation**

**Scenario:**
- Running A/B test: Two different product recommendation algorithms
- Want Test A shown to "High-Value Customers" and Test B to everyone else
- Adobe Target needs to decide in <50ms which variant to show

**Without Edge:**
- Target queries AEP Profile Store → 100-300ms delay
- Under high traffic (10K concurrent users), queries can time out
- A/B test becomes unreliable

**With Edge:**
- Target queries edge server → <30ms response
- Scales to millions of concurrent visitors
- Reliable A/B test results

**Business Impact:** Accurate experimentation, reliable at scale

---

**3. Mobile Banking App - In-Session Personalization**

**Scenario:**
- User opens banking app
- Edge evaluates: "Is this a new customer (< 30 days)?"
- If YES → Show onboarding checklist: "Set up direct deposit", "Link external accounts"
- If NO → Show dashboard with account balances and recent transactions

**Why edge matters:**
- Mobile app loads in 1-2 seconds
- Can't afford 200-500ms delay to query AEP Profile Store (users perceive as "slow app")
- Edge responds in <30ms → app feels instant

**Business Impact:** Better mobile UX, higher retention

---

**4. SaaS Product - Feature Gate Based on Customer Tier**

**Scenario:**
- SaaS product has Free, Pro, Enterprise tiers
- Want to show/hide features in real-time based on customer tier
- Edge segment: "Is this customer Enterprise tier?"
- If YES → Enable advanced analytics dashboard
- If NO → Show upgrade prompt

**Why edge matters:**
- Feature gates evaluated on every page load
- Hundreds of evaluations per user session
- Edge caching prevents repeated API calls to AEP Profile Store

**Business Impact:** Fast feature gating, lower API costs

---

**5. Content Paywall - Subscriber vs Non-Subscriber**

**Scenario:**
- News website with paywall
- Edge segment: "Is this user an active subscriber?"
- If YES → Show full article
- If NO → Show first 3 paragraphs + paywall

**Why edge matters:**
- Decision must happen BEFORE article content loads (can't show full article then hide it)
- Needs <30ms latency to avoid page load delays
- Edge decision happens server-side (can't be bypassed by client-side tricks)

**Business Impact:** Effective paywall, fast page loads

---

**When Edge Segmentation is NOT Needed:**

❌ **Email Campaigns**
- Email sent once per day/week
- No one cares if segment evaluation takes 5 minutes or 24 hours
- Use batch segmentation instead (cheaper)

❌ **Nightly Data Exports**
- Exporting customer lists to data warehouse
- Latency doesn't matter
- Use batch segmentation

❌ **Monthly Reports**
- Segment for "Customers acquired in Q4"
- Evaluated once, results don't change in real-time
- Batch segmentation

**Key Criteria for Edge Segmentation:**
1. ✅ Latency requirement <100ms (ideally <50ms)
2. ✅ User-facing decision (web personalization, mobile app, A/B tests)
3. ✅ Evaluated frequently (many times per session)
4. ✅ Simple segment logic (no complex historical lookback windows)

---

#### Q32: Can we truly not achieve real-time lookup with Federated Audience Composition?

**Short Answer:** Correct, you CANNOT achieve real-time (<100ms) profile lookups with FAC.

**Technical Reality:**

**What "Real-Time Lookup" Means:**
- User visits website → Website queries AEP: "Who is this customer? What's their VIP status?"
- AEP response time: <100 milliseconds (ideally <50ms)
- Personalize page content based on response

**Why FAC Cannot Achieve This:**

**Latency Breakdown for FAC Query:**

```
User visits website → AEP receives request
  ↓ (Network latency: 10-50ms)
AEP receives request → Federate query to BigQuery
  ↓ (Network latency to BigQuery: 20-100ms)
BigQuery receives query → Execute query
  ↓ (Query execution: 1-10 seconds, even for indexed queries)
BigQuery returns results → AEP processes
  ↓ (Network latency back to AEP: 20-100ms)
AEP sends response to website
  ↓ (Network latency to user: 10-50ms)
Total latency: 1-12 seconds (far from <100ms requirement)
```

**Even Best-Case Scenario:**
- Highly optimized BigQuery query (partition pruning, clustering)
- Pre-computed materialized view
- Low network latency
- **Still**: 500ms - 2 seconds (5-20x slower than <100ms requirement)

**Why BigQuery is Inherently Too Slow:**
1. **Query Planning Overhead**: BigQuery must parse SQL, optimize query plan, allocate slots (100-500ms)
2. **Network Round-Trips**: Data travels: Website → AEP (US-East) → BigQuery (US-Central) → AEP → Website
3. **Storage Architecture**: BigQuery reads from columnar storage (Parquet files in GCS), not in-memory cache
4. **No Sub-Second Guarantees**: BigQuery is optimized for analytical queries (minutes scale), not operational lookups (milliseconds scale)

**What AEP's Profile Store Provides (Real-Time Lookups):**

```
User visits website → AEP Profile Store lookup
  ↓ (In-memory cache hit: <10ms)
AEP returns profile data → Website
  ↓ (Network latency: 10-50ms)
Total latency: 20-60ms ✅ Meets <100ms requirement
```

**Profile Store Architecture:**
- Distributed in-memory cache (similar to Redis)
- Hash-based lookup (O(1) complexity)
- Co-located with edge servers (low network latency)
- Optimized for <100ms p99 latency

**Comparison Table:**

| Metric | AEP Profile Store (Real-Time) | FAC (BigQuery Federated) |
|--------|-------------------------------|--------------------------|
| **Typical Latency** | 20-100ms | 1-10 seconds |
| **Best-Case Latency** | <10ms (cache hit) | 500ms (optimized query) |
| **Worst-Case Latency** | 200ms (cache miss) | 30-60 seconds (complex query) |
| **Use Case** | Web personalization, Adobe Target, mobile app | Batch audience creation, daily/hourly refresh |
| **Scalability** | Millions of requests/second | Thousands of queries/minute (BigQuery concurrency limits) |
| **Cost per Lookup** | Included in AEP license | $0.01-$0.10 per query (BigQuery slot time) |

**Real-World Example:**

**Scenario: VIP Homepage Banner**
- Requirement: Show "Welcome back, VIP!" banner if customer is VIP tier
- Page load budget: <2 seconds total (including profile lookup)

**Option A: AEP Profile Store (Real-Time)**
```
Page loads → AEP lookup (30ms) → Banner shows "Welcome back, VIP!"
User experience: ✅ Seamless (banner appears immediately)
```

**Option B: FAC (BigQuery Federated)**
```
Page loads → FAC query to BigQuery (2-5 seconds) → Banner shows
User experience: ❌ BAD (page loads, then banner appears 3 seconds later = jarring UX)
```

**When FAC Latency is Acceptable:**

✅ **Batch Audience Creation**
- Build audience: "VIP customers who purchased in last 30 days"
- Evaluated once per day (overnight batch job)
- 5-minute BigQuery query is FINE (no one waiting in real-time)

✅ **Scheduled Email Campaigns**
- Daily email to "Hot Leads"
- Audience evaluated at 6 AM, email sent at 9 AM
- 10-minute query runtime is acceptable

✅ **Hourly Audience Refresh**
- Audience updated every hour for Google Ads targeting
- 2-minute BigQuery query is fine

❌ **Web Personalization**
- User waiting for page to load
- 2-second delay is unacceptable UX
- Must use AEP Profile Store, not FAC

**Workarounds (Hybrid Approach - Option 3):**

**Solution: Use FAC for batch + Profile Store for real-time**

```
99% of customers (general population):
  → Federated Audience Composition (batch, daily refresh)
  → Use cases: Email campaigns, Google Ads targeting

1% of customers (VIPs, high-value, active leads):
  → Stream to AEP Profile Store (real-time)
  → Use cases: Website personalization, Adobe Target A/B tests, real-time alerts
```

**Example:**
- 1 million total customers
- 10,000 VIPs (1%)
- VIP profiles streamed to AEP → Real-time homepage personalization
- Other 990,000 customers → FAC only → Batch campaigns

**Result:**
- ✅ Real-time personalization for VIPs (Profile Store)
- ✅ Cost savings for general population (FAC, no profile storage)
- ✅ Best of both worlds

**Bottom Line:**
- FAC is for **batch** use cases (daily/hourly audience refresh)
- Real-time lookups (<100ms) require **AEP Profile Store**
- If you need both: Use **Hybrid Approach (Option 3)**

**Physics Can't Be Cheated:**
- No amount of optimization makes BigQuery queries <100ms for operational lookups
- BigQuery is an analytical database, not an operational datastore
- For sub-100ms latency: Must use in-memory cache (AEP Profile Store, Redis, Memcached, etc.)

---

## About This Document

**Created:** October 2025
**Purpose:** Educate business stakeholders on AEP concepts without requiring deep technical expertise
**Target Audience:** Executives, marketing managers, business analysts, product managers, data teams evaluating AEP

**Related Documents:**
- [AEP Zero-Copy Executive Summary](aep-zero-copy-executive-summary.md) - Strategic decision guide for architecture options
- [AEP Zero-Copy Architecture Options](aep-zero-copy-architecture-options.md) - Detailed technical implementation guide
- [GCP Zero-Copy Architecture Options](gcp-zero-copy-architecture-options.md) - GCP-specific implementation guide

**Feedback:** This is a living document. If you have questions not covered here, please add them to the FAQ section.

---

**End of Document** | Total Length: ~2,800 lines
