# AWS Automated Cost Optimization & FinOps Dashboard

## Project Overview
This project implements a serverless FinOps cost monitoring and alerting pipeline on AWS. Instead of manually logging into the Billing console to check for unexpected spend spikes, this pipeline automates daily budget tracking, trend visualization, and proactive alerting while keeping infrastructure overhead near zero.

Once per day, Amazon EventBridge Scheduler triggers an AWS Lambda function that queries the AWS Cost Explorer API for Month-to-Date (MTD) spend, ranks the top three cost-driving services, and pulls a month-end spend forecast. Lambda publishes these figures as custom metrics to an Amazon CloudWatch Dashboard and triggers an actionable Amazon SNS email report whenever actual spend reaches 80% of the configured budget threshold or projected spend exceeds 100%. Everything in this document was built and validated hands-on in the AWS Console, and codified using AWS CloudFormation.

## Architecture Topology

![Cost Optimization Architecture Map](architecture-map.png)

-   **Region:** `us-east-1` (N. Virginia)
-   **Technologies:** Amazon EventBridge Scheduler, AWS Lambda (Python 3.12), AWS Cost Explorer API, Amazon CloudWatch, Amazon SNS, AWS CloudFormation

---

## Pipeline Objectives & Measured Results

| Metric | Target | Implemented Result | How It Is Achieved |
| :--- | :--- | :--- | :--- |
| **Idle Compute Cost** | **$0.00** | **Confirmed** | Lambda scales to zero between scheduled runs. No EC2 instances or persistent servers are provisioned. |
| **Execution Latency** | **< 5 seconds** | **~1.0 to 1.5 seconds** | Lambda runs colocated in `us-east-1` alongside the global Cost Explorer endpoint, completing API queries, metric writes, and SNS dispatch in a single short invocation. |
| **Security Scope** | **Least Privilege** | **Confirmed** | Custom IAM inline policy (`cost-opt-least-privilege`) restricts Lambda to read-only Cost Explorer actions, CloudWatch metric publishing, and `sns:Publish` scoped to the single topic ARN. |
| **Observability** | **Proactive & Self-Monitoring** | **Confirmed** | Custom CloudWatch metrics power trend dashboards while a dedicated CloudWatch Alarm monitors Lambda `Errors >= 1` to prevent silent monitoring failures. |

---

## Implementation Proof & Verification

The following visual evidence documents the successful deployment and end-to-end execution of the FinOps monitoring pipeline.

### 1. EventBridge Scheduler & Lambda Target
*The daily recurring schedule is enabled in `us-east-1` on a 1-day rate expression and mapped directly to the `cost-opt-monitor-fn` Lambda target.*
![EventBridge Scheduler](eventbridge%20scheduler.jpg)
![Schedule Rate](schedule%20rate.jpg)
![Lambda Target](lambda%20target.jpg)

### 2. Lambda Execution & CloudWatch Logs
*Manual test invocation confirms a `200` JSON response with calculated MTD spend, top cost-driving services, and `alert_sent: true`. CloudWatch Logs verify a clean execution with zero errors.*
![Lambda Test Details](Lambda%20Test%20Details.jpg)
![CloudWatch Log Streams](cloudwatch%20log%20streams.jpg)

### 3. Proactive SNS FinOps Email Alert
*Threshold breach testing confirms end-to-end SNS delivery containing the billing period, MTD spend, budget utilization percentage, forecast status, and top cost drivers.*
![AWS Alert Manual Test](aws%20alert%20manual%20test.jpg)

### 4. CloudWatch Dashboard & Error Alarm
*Custom metrics populate `Cost-Optimization-Dashboard` for ongoing trend analysis, while `cost-opt-lambda-errors-alarm` stays in the `OK` state to monitor pipeline health.*
![CloudWatch Dashboard](cloudwatch%20dashboard.jpg)
![CloudWatch Alarm](cloudwatch%20alarm.jpg)

---

## Active Pipeline Flow
This is the step-by-step procedure the architecture follows on each daily cycle:

| Step | Action | Expected Time |
| :--- | :--- | :--- |
| **1** | EventBridge Scheduler (`cost-opt-daily-trigger`) fires on its `rate(1 day)` schedule. | Scheduled (Daily) |
| **2** | EventBridge assumes its scoped IAM role and invokes `cost-opt-monitor-fn`. | Milliseconds |
| **3** | Lambda queries the Cost Explorer API in `us-east-1` for MTD spend grouped by service and requests a month-end forecast. | ~0.5 to 1 second |
| **4** | Lambda pushes `MonthToDateSpend`, `ForecastedMonthEndSpend`, and `BudgetUtilizationPercent` to CloudWatch (`Custom/CostOptimization`). | Milliseconds |
| **5** | Lambda checks MTD spend (>= 80% threshold) and forecasted spend (> 100% threshold) and publishes the formatted report to SNS if breached. | Milliseconds |
| **6** | SNS delivers the FinOps email alert to subscribed stakeholders. | ~1 second |

---

## Key Design Decisions & Trade-offs

### Design Decisions
| Decision | Rationale |
| :--- | :--- |
| **Deploying in `us-east-1`** | The AWS Cost Explorer API is a global service hosted exclusively in `us-east-1`. Colocating Lambda, CloudWatch, and SNS in the same region follows standard FinOps practice and avoids cross-region configuration complexity. |
| **EventBridge Scheduler over Legacy Rules** | Uses the modern `AWS::Scheduler::Schedule` service with a dedicated least-privilege IAM execution role instead of legacy scheduled EventBridge Rules. |
| **Scheduled Lambda vs. Native AWS Budgets** | Cost Explorer is a pull-only API that refreshes roughly every 24 hours. Polling daily with Lambda unlocks custom CloudWatch trend dashboards and top-3 service breakdowns that rigid native budget alerts do not provide. |
| **Graceful Forecast Fallback & Missing Data Treatment** | New or low-spend accounts can trigger a `DataUnavailableException` on `GetCostForecast`; the Python handler catches this cleanly without crashing. The CloudWatch Error Alarm uses `TreatMissingData: notBreaching` so quiet hours between daily runs stay in the `OK` state. |
| **Custom IAM Inline Policy** | Avoids broad managed billing policies by granting only `ce:GetCostAndUsage`, `ce:GetCostForecast`, `cloudwatch:PutMetricData`, and `sns:Publish` restricted to the exact SNS Topic ARN. |

### Trade-offs and Enhancements
-   **Daily Refresh Granularity:** Because Cost Explorer billing data updates roughly once every 24 hours, this pipeline detects spend trends daily rather than in real time. Increasing the schedule frequency would incur extra API fees without yielding fresher billing data.
-   **Automated Remediation & ChatOps:** Currently, alerts route to email via SNS. Extending the SNS topic or Lambda handler to post alerts into Slack or Microsoft Teams, or to automatically stop untagged non-production EC2 instances upon severe breaches, would turn monitoring into active cost control.
-   **Infrastructure as Code:** The full stack (SNS, IAM roles, Lambda, EventBridge Scheduler, CloudWatch Dashboard, and Error Alarm) is codified in a `template.yaml` CloudFormation template so it can be deployed or torn down with a single command.

---

## Cost Estimate
*(Note: Compute, scheduling, notifications, and dashboards fall within AWS Free Tier limits. The only recurring charge is the AWS Cost Explorer API at $0.01 per request, totaling roughly $0.60/month for daily runs.)*

| Service | Cost Estimation |
| :--- | :--- |
| **AWS Cost Explorer API** | $0.01 per API request (2 requests/day = ~$0.60/month). |
| **Amazon EventBridge Scheduler** | First 14 million invocations/month free. |
| **AWS Lambda** | $0.20 per 1M requests (First 1M requests/month free). |
| **Amazon CloudWatch** | First 3 dashboards, 10 custom metrics, and 10 alarms/month free. |
| **Amazon SNS** | $2.00 per 100,000 email deliveries (First 1,000 emails/month free). |

---
**Author:** Olabanji Badru  
**Portfolio:** [github.com/Olabadmanji](https://github.com/Olabadmanji)