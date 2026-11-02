# AWS Multi-Region Disaster Recovery Strategy (Warm Standby)

## Project Overview
This project implements and tests a production-grade Disaster Recovery (DR) strategy on AWS designed to protect an application against the loss of an entire region. Following the **Warm Standby** architectural pattern, the DR region is always ready to receive traffic, while the database is only restored when a failover actually happens—keeping running costs low while ensuring fast recovery.

Object data is replicated via S3 Cross-Region Replication (CRR), database backups are synced using native RDS cross-region backup replication, and Route 53 failover routing automatically shifts traffic to the DR region when the primary stops responding. Everything in this document was built, tested hands-on, and verified with timestamps.

## Architecture Topology

*   **Primary Region:** `eu-west-2` (London)
*   **Disaster Recovery Region:** `us-east-1` (N. Virginia)
*   **Technologies:** AWS S3 (CRR), AWS RDS MySQL, AWS EC2, Elastic IPs, Amazon Route 53, Apache HTTP Server

---

## Disaster Recovery Objectives & Measured Results

| Metric | Target | Measured Result | How It Is Achieved |
| :--- | :--- | :--- | :--- |
| **RTO** (Recovery Time) | **15 Minutes** | **15 - 20 Minutes** (Est. end-to-end) | Route 53 health-check failover (~90s) + RDS point-in-time restore (~11-12m) + App Cutover (~2-5m). |
| **RPO** (Recovery Point) | **1 Hour** | **~14 Minutes** | RDS uploads transaction logs ~every 5 minutes, copied to DR with automated snapshots. |
| **Failover Detection** | ~90 seconds | ~90 seconds | Route 53 config: 30-second interval × 3 consecutive failures. |
| **Object Replication** | Near real-time | Confirmed | S3 CRR verified by replication test. |
| **Delete Protection** | Must not happen | Confirmed | Delete marker replication disabled; replica kept the file. |

### Objective Validation Evidence
[RPO Source - Latest Restorable Time](./RPO%20Source.jpg)
*Proof of RPO: Latest restorable time captured just before the restore test, showing data is ~14 minutes behind real-time.*

![RTO - Database Restore Creating (10:05 PM)](./RTO%20Starting.jgp)

![RTO - Database Restore Completed (10:16 PM)](./RTO%20Completed.jpg)
*Proof of RTO: The database restore was initiated in us-east-1 at approximately 10:04 PM, entered the 'Creating' status at 10:05 PM , and became fully 'Available' at 10:16 PM. This 11-minute restore time comfortably supports the 15-minute RTO target.*

---

## Core Infrastructure Components

### 1. Amazon Route 53 (DNS Failover Routing)
Detects primary failure and moves traffic to the DR region automatically.
*   **Health Checks:** Polls the primary endpoint over HTTP (Port 80) every 30 seconds. Marks unhealthy after 3 consecutive failures (~90 seconds).
*   **Routing Records:** Primary record has the health check attached; secondary record is the always-available fallback.
*   **TTL:** Set to 60 seconds to keep propagation delay low during failover.

**DNS Failover Validation:**
![DNS Pre-Failover (Primary IP)](./DNS%20Failover.jpg)
![DNS After Failover (DR IP)](./SEC%20Addy.jpg)

### 2. Amazon RDS (Automated Cross-Region Backup)
Makes the database restorable in the DR region to within minutes of the failure.
*   **Replication:** Native backup replication to `us-east-1` (snapshots + transaction logs). No scripts or scheduled jobs involved.
*   **Retention:** 7-day retention, 03:00–04:00 UTC backup window.

**Database Replication Validation:**
![RDS Cross-Region Backup Replication](./DB%20Replication.jpg)

### 3. Amazon S3 (Cross-Region Replication)
Copies new objects to the DR region using the S3 account regional namespace.
*   **Versioning:** Enabled on both buckets (required for CRR).
*   **Delete Marker Protection:** Deliberately disabled. A deletion in the primary region, whether accidental or malicious, never reaches the DR copy.

### 4. Application Tier (EC2 & Elastic IP)
Stands in for the application tier to give Route 53 a real endpoint to health check.
*   **Elastic IPs:** Keeps each endpoint's public address fixed across stops and restarts, ensuring DNS records and health checks stay valid.
*   **Standby Node:** Runs continuously in the DR region, serving traffic immediately upon failover.

**Application Tier Validation:**

*1. Normal State (Both Regions Online):*
![Live Application - Primary Region](./DR%20Demo%20(Primary).jpg)
![Live Application - DR Region](./DR%20Demo%20(Backup).jpg)

*2. Failover State (Primary Outage Simulated):*
![Primary Instance Stopped](./new%20stopped%20primar%20instance.jpg)
*Simulating a regional disaster by manually stopping the primary eu-west-2 EC2 instance.*

![Primary Endpoint Timeout](./new%20pri%20not%20loading.jpg)
*The primary application endpoint correctly timing out and dropping traffic.*

![DR Endpoint Serving Traffic](./new%20sec%20still%20loading.jpg)
*The DR application in us-east-1 successfully handling the rerouted traffic with zero manual intervention.*

---

## Active Failover Runbook
This is the step-by-step procedure followed during a regional outage:

| Step | Action | Expected Time |
| :--- | :--- | :--- |
| **1** | Route 53 detects the primary failure and alerts the on-call engineer. | ~1.5 to 3 minutes (Automatic) |
| **2** | Immediately start the database restore in `us-east-1` from the replicated backup, to the latest restorable time. | ~11 to 12 minutes |
| **3** | While the restore runs, confirm DNS has moved to the DR endpoint and that it is serving traffic. | During the restore |
| **4** | When the database is *Available*, point the application at the restored instance. | ~2 to 5 minutes |
| **5** | Verify the application end-to-end. | 3 minutes |
| **6** | After the primary recovers, confirm failback and clean up the temporary database. | As needed |

> **Note:** Starting the restore first, and confirming DNS while it runs, keeps the two slowest steps overlapping instead of running one after the other.

---

## Key Design Decisions & Trade-offs

### Design Decisions
| Decision | Rationale |
| :--- | :--- |
| **Warm Standby** | Balances cost and recovery time. Hot Standby roughly doubles running cost for a small RTO improvement. |
| **Delete marker replication disabled** | Keeps the DR bucket independent. Deletions in the primary region never reach it. |
| **Native RDS backup replication** | Fully automated, with no scripts to maintain or forget during an incident. |
| **Point-in-time restore** | Replicating transaction logs gives an RPO of minutes instead of the daily snapshot interval. |
| **Elastic IPs on both instances** | A normal public IP changes on stop and start, which would break DNS records and health checks. |
| **TTL 60s, 30s checks, threshold 3** | Fast detection while avoiding false positives from brief network blips. |
| **S3 account regional namespace** | Bucket names are unique to the account, avoiding global name collisions. |

### Trade-offs and Enhancements
*   **Lower RPO/RTO:** A cross-region RDS read replica replicates continuously (bringing RPO to seconds and eliminating the 11-12 minute restore step), but significantly increases running costs.
*   **Automation:** Triggering the restore and the application cutover via EventBridge and Lambda from a health-check alarm would remove the human reaction time.
*   **Production Hardening:** Future iterations could implement Application Load Balancers in each region instead of single instances, add S3 Object Lock, and script the runbook with Infrastructure as Code.

---

## Cost Estimate
*(Note: All resources for this project were deleted after testing, making the total cost negligible.)*

| Service | Cost Estimation |
| :--- | :--- |
| **S3 Cross-Region Replication** | ~$0.015 per GB replicated + storage in both buckets |
| **RDS (db.t3.micro)** | Free tier eligible, otherwise standard hourly instance cost |
| **RDS Snapshot/Backup Storage** | ~$0.095 per GB-month, in both regions |
| **Route 53 (Health Check & Zone)** | ~$0.50 per month each |
| **Public IPv4 / Elastic IPs** | $0.005 per hour per address (first 750 hrs/month free on EC2) |