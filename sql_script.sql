-- ── 1. CREATE DATABASE ──────────────────────────────────────
DROP DATABASE IF EXISTS streampulse;
CREATE DATABASE streampulse
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;
 
USE streampulse;

-- ── 2. CREATE TABLES ────────────────────────────────────────
 
CREATE TABLE users (
    user_id               INT            NOT NULL,
    signup_date           DATE           NOT NULL,
    city_tier             VARCHAR(20)    NOT NULL,
    acquisition_channel   VARCHAR(50)    NOT NULL,
    PRIMARY KEY (user_id)
);

CREATE TABLE subscriptions (
    user_id               INT            NOT NULL,
    plan_type             VARCHAR(20)    NOT NULL,
    monthly_fee           DECIMAL(6,2)   NOT NULL,
    status                VARCHAR(20)    NOT NULL,
    churn_date            DATE               NULL,
    PRIMARY KEY (user_id),
    FOREIGN KEY (user_id) REFERENCES users(user_id)
);
#drop table users;
CREATE TABLE sessions (
    session_id            INT            NOT NULL,
    user_id               INT            NOT NULL,
    session_date          DATE           NOT NULL,
    duration_minutes      DECIMAL(8,2)   NOT NULL,
    device_type           VARCHAR(30)    NOT NULL,
    PRIMARY KEY (session_id),
    FOREIGN KEY (user_id) REFERENCES users(user_id)
);

-- Disable checks temporarily for faster bulk load
SET FOREIGN_KEY_CHECKS = 0;
SET UNIQUE_CHECKS = 0;
SET sql_log_bin = 0;

-- Re-enable after load
SET FOREIGN_KEY_CHECKS = 1;
SET UNIQUE_CHECKS = 1;
SET GLOBAL local_infile = 1;

USE streampulse;

SELECT 'users'         AS table_name, COUNT(*) AS row_count FROM users
UNION ALL
SELECT 'subscriptions' AS table_name, COUNT(*) AS row_count FROM subscriptions
UNION ALL
SELECT 'sessions'      AS table_name, COUNT(*) AS row_count FROM sessions;


-- ============================================================
--  StreamPulse Lite — SQL Analysis Queries (FIXED)
--  Database : streampulse
--  Tables   : users · subscriptions · sessions
-- ============================================================

USE streampulse;


-- ============================================================
-- Q1. TOTAL USERS
-- ============================================================
SELECT
    COUNT(DISTINCT user_id) AS total_users
FROM users;


-- ============================================================
-- Q2. ACTIVE vs CHURNED USERS
-- ============================================================
SELECT
    TRIM(status) AS status,
    COUNT(*) AS user_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS pct_of_total
FROM subscriptions
GROUP BY TRIM(status)
ORDER BY user_count DESC;

-- ============================================================
-- Q3. DAU — Daily Active Users (last 30 days)
-- ============================================================
WITH max_date AS (
    SELECT MAX(session_date) AS latest_date
    FROM sessions
)
SELECT
    s.session_date AS activity_date,
    COUNT(DISTINCT s.user_id) AS daily_active_users
FROM sessions s
CROSS JOIN max_date m
WHERE s.session_date >= DATE_SUB(m.latest_date, INTERVAL 30 DAY)
GROUP BY s.session_date
ORDER BY s.session_date DESC;

-- ============================================================
-- Q4. MAU — Monthly Active Users
-- ============================================================
SELECT
    DATE_FORMAT(session_date, '%Y-%m') AS activity_month,
    COUNT(DISTINCT user_id) AS monthly_active_users
FROM sessions
GROUP BY activity_month
ORDER BY activity_month;

-- ============================================================
-- Q5. MONTHLY CHURN RATE
-- ============================================================
WITH monthly_churn AS (
    SELECT
        DATE_FORMAT(churn_date, '%Y-%m') AS churn_month, COUNT(*) AS churned_users
    FROM subscriptions
    WHERE TRIM(status)='Churned' AND churn_date IS NOT NULL
    GROUP BY DATE_FORMAT(churn_date, '%Y-%m')
),
total_subs AS (
    SELECT COUNT(*) AS total_subscribers
    FROM subscriptions
)
SELECT
    mc.churn_month, mc.churned_users, ts.total_subscribers,
    ROUND(mc.churned_users * 100.0 / ts.total_subscribers, 2) AS churn_rate_pct,
    SUM(mc.churned_users) OVER (ORDER BY mc.churn_month) AS cumulative_churned
FROM monthly_churn mc
CROSS JOIN total_subs ts
ORDER BY mc.churn_month;

-- ============================================================
-- Q6. AVERAGE SESSION DURATION BY DEVICE
-- ============================================================
SELECT
    device_type, COUNT(*) AS total_sessions, ROUND(AVG(duration_minutes), 2) AS avg_duration_min,
    ROUND(MIN(duration_minutes), 2) AS min_duration_min, ROUND(MAX(duration_minutes), 2) AS max_duration_min
FROM sessions
GROUP BY device_type
UNION ALL
SELECT
    'ALL DEVICES' AS device_type, COUNT(*) AS total_sessions,
    ROUND(AVG(duration_minutes), 2) AS avg_duration_min, ROUND(MIN(duration_minutes), 2) AS min_duration_min, ROUND(MAX(duration_minutes), 2) AS max_duration_min
FROM sessions
ORDER BY device_type;

-- ============================================================
-- Q7. PLAN-WISE CHURN RATE
-- ============================================================
WITH plan_stats AS (
    SELECT
        TRIM(plan_type) AS plan_type, monthly_fee, COUNT(*) AS total_users,
        SUM(CASE WHEN TRIM(status) = 'Churned' THEN 1 ELSE 0 END)  AS churned_users,
        SUM(CASE WHEN TRIM(status) = 'Active'  THEN 1 ELSE 0 END)  AS active_users
    FROM subscriptions
    GROUP BY TRIM(plan_type), monthly_fee
)
SELECT
    plan_type, monthly_fee, total_users, active_users, churned_users, ROUND(churned_users * 100.0 / total_users, 2)   AS churn_rate_pct,
    CASE
        WHEN churned_users * 100.0 / total_users >= 35 THEN 'High Risk'
        WHEN churned_users * 100.0 / total_users >= 20 THEN 'Medium Risk'
        ELSE 'Low Risk'
    END AS risk_level
FROM plan_stats
ORDER BY churn_rate_pct DESC;

-- ============================================================
-- Q8. ACQUISITION CHANNEL PERFORMANCE
-- ============================================================
SELECT
    u.acquisition_channel, COUNT(DISTINCT u.user_id) AS total_users,
    SUM(CASE WHEN TRIM(s.status) = 'Active'  THEN 1 ELSE 0 END) AS active_users,
    SUM(CASE WHEN TRIM(s.status) = 'Churned' THEN 1 ELSE 0 END) AS churned_users,
    ROUND(AVG(s.monthly_fee), 2) AS avg_monthly_fee,
    ROUND(SUM(CASE WHEN TRIM(s.status) = 'Churned' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS churn_rate_pct,
    ROUND(SUM(CASE WHEN TRIM(s.status) = 'Active' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS retention_rate_pct
FROM users u
JOIN subscriptions s ON u.user_id = s.user_id
GROUP BY u.acquisition_channel
ORDER BY retention_rate_pct DESC;

-- ============================================================
-- Q9. CITY TIER ANALYSIS
-- ============================================================
WITH tier_sessions AS (
    SELECT
        u.city_tier, COUNT(DISTINCT se.user_id) AS active_session_users,
        COUNT(se.session_id) AS total_sessions, ROUND(AVG(se.duration_minutes), 2) AS avg_session_duration
    FROM users u 
    JOIN sessions se ON u.user_id = se.user_id
    GROUP BY u.city_tier
)
SELECT
    u.city_tier, COUNT(DISTINCT u.user_id) AS total_users,
    ts.total_sessions, ROUND(ts.total_sessions / COUNT(DISTINCT u.user_id), 1) AS sessions_per_user, ts.avg_session_duration,
    SUM(CASE WHEN TRIM(su.status) = 'Active'  THEN 1 ELSE 0 END) AS active_users,
    SUM(CASE WHEN TRIM(su.status) = 'Churned' THEN 1 ELSE 0 END) AS churned_users,
    ROUND(SUM(CASE WHEN TRIM(su.status) = 'Churned' THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT u.user_id), 2) AS churn_rate_pct
FROM users u
JOIN subscriptions su ON u.user_id  = su.user_id
JOIN tier_sessions  ts ON u.city_tier = ts.city_tier
GROUP BY u.city_tier, ts.total_sessions, ts.avg_session_duration
ORDER BY churn_rate_pct ASC;

-- ============================================================
-- Q10. TOP 10 MOST ACTIVE USERS
-- ============================================================
WITH user_activity AS (
    SELECT
        se.user_id, COUNT(se.session_id) AS total_sessions, ROUND(SUM(se.duration_minutes), 2) AS total_minutes,
        ROUND(AVG(se.duration_minutes), 2) AS avg_session_duration, MIN(se.session_date) AS first_session, MAX(se.session_date) AS last_session
    FROM sessions se
    GROUP BY se.user_id
)
SELECT
    RANK() OVER (ORDER BY ua.total_minutes DESC) AS activity_rank,
    ua.user_id, u.city_tier, u.acquisition_channel, TRIM(su.plan_type) AS plan_type,
    TRIM(su.status) AS status, ua.total_sessions, ua.total_minutes, ua.avg_session_duration, ua.first_session, ua.last_session
FROM user_activity ua
JOIN users u  ON ua.user_id = u.user_id
JOIN subscriptions su ON ua.user_id = su.user_id
ORDER BY activity_rank
LIMIT 10;
