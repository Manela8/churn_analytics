# StreamPulse Lite — SaaS User Engagement & Churn Analytics

![Project Status](https://img.shields.io/badge/Status-Complete-brightgreen)
![SQL](https://img.shields.io/badge/SQL-MySQL-blue)
![Python](https://img.shields.io/badge/Python-3.12-yellow)
![Power BI](https://img.shields.io/badge/PowerBI-Dashboard-orange)

> A end-to-end Data Analyst portfolio project simulating a music streaming SaaS platform — covering data cleaning, SQL analysis, and an interactive Power BI dashboard.

---

## Table of Contents

- [Project Overview](#project-overview)
- [Business Problem](#business-problem)
- [Dataset](#dataset)
- [Project Structure](#project-structure)
- [Tech Stack](#tech-stack)
- [Step 1 — Business Understanding](#step-1--business-understanding)
- [Step 2 — Data Cleaning](#step-2--data-cleaning)
- [Step 3 — SQL Analysis](#step-3--sql-analysis)
- [Step 4 — Power BI Dashboard](#step-4--power-bi-dashboard)
- [Step 5 — Business Insights](#step-5--business-insights)
- [How to Run This Project](#how-to-run-this-project)
- [Key Learnings](#key-learnings)

---

## Project Overview

**StreamPulse** is a fictional music streaming platform with 10,000 users. Leadership has flagged rising monthly churn and wants a data-driven view of user engagement and subscription performance.

This project builds a complete analytics pipeline from raw data to executive dashboard using SQL, Python, and Power BI.

---

## Business Problem

- Monthly churn has been increasing with no clear root cause identified
- Leadership has no unified view of user engagement and subscription performance
- It is unclear which subscription plans are most at risk
- Acquisition channel ROI is unknown — are paid channels worth the spend?

---

## Dataset

Three tables simulating a real SaaS product database:

| Table | Rows | Description |
|---|---|---|
| `users` | 10,000 | User demographics — signup date, city tier, acquisition channel |
| `subscriptions` | 10,000 | Plan details — plan type, monthly fee, status, churn date |
| `sessions` | 125,448 | Usage logs — session date, duration, device type |

### Subscription Plans

| Plan | Monthly Fee | Users |
|---|---|---|
| Free | $0.00 | 5,027 |
| Basic | $9.99 | 2,435 |
| Premium | $19.99 | 1,838 |
| Family | $29.99 | 700 |

---

## Project Structure

```
StreamPulse-Lite/
│
├── raw_data/
│   ├── streampulse_users.csv
│   ├── streampulse_subscriptions.csv
│   └── streampulse_sessions.csv
│
├── cleaned_data/
│   ├── users.csv
│   ├── subscriptions.csv
│   └── sessions.csv
│
├── scripts.sql
│
├── clean_data.py
│
├── visuals.pbix
│
└── README.md
```

---

## Tech Stack

| Tool | Purpose |
|---|---|
| Python 3.12 | Data cleaning & MySQL loading |
| pandas | Data manipulation |
| SQLAlchemy + PyMySQL | Database connection |
| MySQL 8.0 | Data storage & SQL analysis |
| MySQL Workbench | Query execution & verification |
| Power BI Desktop | Interactive dashboard |

---

## Step 1 — Business Understanding

### Success Metrics (KPIs)

| KPI | Target |
|---|---|
| Monthly Churn Rate | < 5% |
| DAU | > 3,000 |
| MAU | > 7,000 |
| DAU / MAU Stickiness | > 40% |
| Avg Session Duration | > 25 min |
| Premium Plan Retention | > 80% |

### Key Stakeholder Questions

**CEO**
- What is the overall monthly churn rate trend?
- Which subscription plan is driving the most revenue?

**Product Team**
- Which device types are most popular among active users?
- What is the avg session duration before churn?

**Marketing Team**
- Which acquisition channel brings the most retained users?
- Which city tier should we focus campaigns on?

---

## Step 2 — Data Cleaning

### Issues Found & Fixed

| Table | Issue | Fix Applied |
|---|---|---|
| users | 191 nulls in acquisition_channel | Filled with 'Unknown' |
| users | signup_date stored as string | Converted to datetime |
| subscriptions | monthly_fee stored as integers (0, 99, 199, 299) | Mapped to decimals (0, 9.99, 19.99, 29.99) |
| subscriptions | churn_date null for active users causing load errors | Explicit NaT → None conversion |
| sessions | 1,254 duplicate rows | Removed |
| sessions | 1,223 nulls in duration_minutes | Filled with median (24 min) |
| sessions | 2,545 nulls in device_type | Filled with 'Unknown' |
| sessions | Extreme outlier durations | Capped via IQR Winsorisation |
| all tables | Trailing whitespace in text columns | Applied str.strip() before MySQL load |

### Run the cleaning script

```bash
pip install pandas sqlalchemy pymysql
python python/clean_data.py
```

---

## Step 3 — SQL Analysis

### 15 queries covering key business questions:

| # | Query | SQL Concepts |
|---|---|---|
| Q1 | Total users | COUNT DISTINCT |
| Q2 | Active vs churned breakdown | GROUP BY, Window Function |
| Q3 | DAU — daily active users | CTE, CROSS JOIN, DATE_SUB |
| Q4 | MAU — monthly active users | DATE_FORMAT, GROUP BY |
| Q5 | Monthly churn rate | CTE, CROSS JOIN, Cumulative SUM |
| Q6 | Avg session duration by device | UNION ALL, GROUP BY |
| Q7 | Plan-wise churn rate | CTE, CASE WHEN, Risk labelling |
| Q8 | Acquisition channel performance | JOIN, CASE WHEN |
| Q9 | City tier analysis | CTE, 3-table JOIN |
| Q10 | Top 10 most active users | CTE, RANK() Window Function |
| Q11 | Cohort retention analysis | CTE, DATE_FORMAT, RANK() |
| Q12 | Revenue analysis (MRR) | CTE, CASE WHEN, Revenue calc |
| Q13 | User engagement segments | CTE, Nested CASE WHEN |
| Q14 | Device trend month-over-month | LAG() Window Function, PARTITION BY |
| Q15 | Churn risk flag | CTE, DATEDIFF, Risk scoring |

### Sample Query — Plan-wise Churn Rate

```sql
WITH plan_stats AS (
    SELECT
        TRIM(plan_type)                                              AS plan_type,
        monthly_fee,
        COUNT(*)                                                     AS total_users,
        SUM(CASE WHEN TRIM(status) = 'Churned' THEN 1 ELSE 0 END)   AS churned_users,
        SUM(CASE WHEN TRIM(status) = 'Active'  THEN 1 ELSE 0 END)   AS active_users
    FROM subscriptions
    GROUP BY TRIM(plan_type), monthly_fee
)
SELECT
    plan_type,
    monthly_fee,
    total_users,
    active_users,
    churned_users,
    ROUND(churned_users * 100.0 / total_users, 2)   AS churn_rate_pct,
    CASE
        WHEN churned_users * 100.0 / total_users >= 35 THEN 'High Risk'
        WHEN churned_users * 100.0 / total_users >= 20 THEN 'Medium Risk'
        ELSE                                               'Low Risk'
    END                                             AS risk_level
FROM plan_stats
ORDER BY churn_rate_pct DESC;
```

---

## Step 4 — Power BI Dashboard

4-page interactive dashboard connected live to MySQL:

| Page | Title | Audience |
|---|---|---|
| 1 | Executive Overview | CEO / Leadership |
| 2 | Churn Analysis | Product / Retention Team |
| 3 | Engagement Analysis | Product Team |
| 4 | Acquisition & Geography | Marketing Team |

### Page 1 — Executive Overview
- KPIs: Total users, Active users, Churned users, Churn Rate %, Total MRR, Lost Revenue
- Visuals: MAU trend line, Active vs Churned donut, MRR by plan bar, Monthly churn trend line
- Slicers: Date range, Plan type, City tier

### Page 2 — Churn Analysis
- KPIs: Churn Rate %, Avg monthly churn, High risk users, Cumulative churned
- Visuals: Plan-wise churn bar, Monthly churn trend, Cohort retention matrix heatmap, Churn risk users table
- Slicers: Plan type, Churn month, Risk level, City tier

### Page 3 — Engagement Analysis
- KPIs: DAU, Avg session duration, Total sessions, DAU/MAU stickiness ratio
- Visuals: DAU trend line, Sessions by device donut, Avg duration by device bar, Engagement segments bar, Device trend MoM line, Top 10 active users table
- Slicers: Date range, Device type, Plan type

### Page 4 — Acquisition & Geography
- KPIs: Best channel, Worst channel, Best city tier, Avg sessions per user
- Visuals: Channel retention bar, Channel churn bar, Users by channel donut, City tier engagement bar, City tier churn bar
- Slicers: Acquisition channel, City tier, Plan type

---

## Step 5 — Business Insights

Based on real data analysis across 10,000 users and 125,448 sessions:

### Churn & Retention

**1. Basic plan is the biggest churn threat at 20.66%**
With 2,435 users and a 20.66% churn rate, Basic is losing 503 subscribers — nearly 2× the churned users of Free and Premium combined. This represents ~$5,025/month in lost MRR.
> **Action:** Investigate the value gap between Free and Basic. Add exclusive features to justify the $9.99/month upgrade.

**2. Premium churns more than Free — a counterintuitive red flag**
Premium users churn at 13.22% vs Free at only 4.85%. Paid users who invested $19.99/month are leaving faster than free users — suggesting Premium may not deliver enough perceived value.
> **Action:** Survey churned Premium users. Add exclusive perks — offline listening, early features, priority support — to increase top-tier stickiness.

**3. Family plan shows the healthiest churn at 7.71%**
With only 700 users, the Family plan at $29.99 churns at just 7.71% — lower than both Basic and Premium. Multi-user plans create household lock-in, making cancellation a group decision.
> **Action:** Promote Family plan to Basic and Premium users. Growing this segment from 7% to 15% could significantly reduce overall churn.

**4. Overall 10.44% churn rate is above SaaS benchmark**
StreamPulse retains 8,956 of 10,000 users (89.56% retention). A 10.44% churn rate means the platform loses roughly 1 in 10 users every cycle — industry benchmark for music streaming is under 5-6%.
> **Action:** Set a 6-month target to bring churn below 7% by focusing retention efforts on Basic plan users first.

### Acquisition & Channels

**5. Referral brings the highest quality users at 90.59% retention**
Referral channel has the best retention (90.59%) with 2,040 users and only 9.41% churn. Referred users come pre-sold on the product by someone they trust.
> **Action:** Launch a referral rewards program. Even a small incentive ($1 credit per referral) could double referral volume at low cost.

**6. Google Ads and Influencer channels have the highest churn — poor ROI**
Google Ads (11.17% churn) and Influencer (11.42% churn) are the worst performing channels yet likely the most expensive. These users sign up impulsively and disengage quickly.
> **Action:** Reallocate 20-30% of paid ad budget toward Organic SEO and Referral programs which retain users better at a fraction of the cost.

**7. Organic is the sweet spot — high volume AND high retention**
Organic brings the most users (2,828 — 28.3% of total) with the second best retention (90.49%). SEO and word-of-mouth are driving both scale and quality simultaneously.
> **Action:** Double down on content marketing and SEO investment. Organic is already the top channel — scaling it could shift the overall retention curve meaningfully.

### Geography & Engagement

**8. All city tiers show dangerously high churn — pricing likely the cause**
Churn across tiers: Tier 1 (47.52%), Tier 2 (44.26%), Tier 3 (47.85%). Nearly half of users in every tier are churning. However engagement metrics are similar across tiers (~27.9 min avg duration, ~12.6 sessions/user) — meaning churn is not driven by low engagement but likely by pricing or competition.
> **Action:** Investigate pricing sensitivity by tier. Tier 3 cities may need a lower price point or localised content to improve retention.

**9. Tier 2 cities are the most balanced market — best retention with highest volume**
Tier 2 has the most users (3,999), best churn rate (44.26%), and solid engagement (12.6 sessions/user, 27.77 min avg). With the largest user base and lowest churn, Tier 2 represents the most stable revenue segment.
> **Action:** Focus next marketing campaign on Tier 2 expansion. These cities have proven product-market fit — scaling here is lower risk than investing in Tier 1 or Tier 3 markets.

### Device & Sessions

**10. Android dominates usage but iOS and Web drive equal session depth**
Android leads with 61,575 sessions across 9,890 users. However iOS (27.94 min avg) and Web (27.94 min avg) match Android (27.86 min) in depth. Smart TV has the lowest reach (3,868 users) but comparable depth (27.81 min) — an untapped high-engagement segment.
> **Action:** Invest in Smart TV app experience. Users who stream on TV tend to have longer passive listening sessions — ideal for Premium and Family plan upsell.

---

## How to Run This Project

### Prerequisites
- Python 3.8+
- MySQL 8.0+
- MySQL Workbench (optional)
- Power BI Desktop (free)

### Step 1 — Clone the repo
```bash
git clone https://github.com/yourusername/streampulse-lite.git
cd streampulse-lite
```

### Step 2 — Install Python dependencies
```bash
pip install pandas sqlalchemy pymysql
```

### Step 3 — Clean the data
```bash
python python/clean_data.py
```

### Step 4 — Load into MySQL
Open MySQL Workbench → load data into tables

### Step 5 — Run SQL queries
Open MySQL Workbench → connect to `streampulse` database → run queries from `sql/` folder

### Step 6 — Open Power BI dashboard
Open `dashboard/StreamPulse_Dashboard.pbix` → update MySQL connection → refresh data

---

## Key Learnings

- Real-world data always has issues — trailing whitespace, wrong data types, foreign key mismatches, and partial loads all appeared in this project
- `TRIM()` every text column before comparing in SQL — invisible characters cause silent bugs that are hard to debug
- Power BI DAX measures are context-sensitive — the same measure can return different values depending on which visual uses it
- The DAU/MAU stickiness ratio is a Silicon Valley standard metric that shows product thinking beyond basic counts
- Cohort retention matrix is the most impactful single visual in any SaaS dashboard

---

## Connect With Me

- LinkedIn: https://linkedin.com/in/manela-nandi/
- GitHub: https://github.com/Manela8/
- Email: manelanandi@gmail.com

---

