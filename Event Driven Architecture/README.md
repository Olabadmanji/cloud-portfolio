# AWS Serverless Event-Driven Data Processing Pipeline

## Project Overview
This project implements a fully decoupled, asynchronous Event-Driven Architecture on AWS. When a JSON payload is uploaded to S3, it triggers Amazon EventBridge, which routes the event to an AWS Lambda function. The Lambda extracts the file's metadata, writes a structured audit record to Amazon DynamoDB, and pushes a real-time email alert via Amazon SNS. Everything in this document was built and tested hands-on in the AWS console, and codified using Terraform.

## Architecture Topology

![Event-Driven Architecture Map](architecture-map.png)

-   **Region:** `eu-west-2` (London)
-   **Technologies:** Amazon S3, Amazon EventBridge, AWS Lambda (Python 3.12), Amazon DynamoDB, Amazon SNS, Terraform

---

## Pipeline Objectives & Measured Results

| Metric | Target | Implemented Result | How It Is Achieved |
| :--- | :--- | :--- | :--- |
| **Idle Compute Cost** | **$0.00** | **Confirmed** | Lambda and DynamoDB scale to zero. No EC2 instances are kept running. |
| **Processing Latency** | **< 5 seconds** | **~2 to 3 seconds** | EventBridge routes the S3 event to Lambda instantly; SNS delivers the email immediately upon the database write. |
| **Security Scope** | **Least Privilege** | **Confirmed** | Custom IAM inline policy restricts the Lambda execution role to exact ARNs for the single bucket, table, and topic. |
| **Extensibility** | **High** | **Confirmed** | Using EventBridge allows adding multiple downstream targets (e.g., SQS, Step Functions) without touching the S3 bucket configuration. |

---

## Implementation Proof & Verification

The following visual evidence documents the successful deployment and end-to-end execution of the pipeline.

### 1. S3 Ingestion Trigger
*Test file uploaded to the S3 ingestion bucket to trigger the pipeline.*
![S3 Uploaded object](S3%20Uploaded%20object.jpg)

### 2. EventBridge Rule & Target Routing
*EventBridge rule configured to filter 'Object Created' events for the ingestion bucket and route them to the Lambda target.*
![EventBridge Rule](Eventbridge%20rule.jpg)
![EventBridge Target](Eventbridge%20target.jpg)

### 3. Lambda Configuration & Execution Observability
*Lambda function confirming EventBridge as the trigger, alongside CloudWatch logs showing the script read the S3 file, wrote to DynamoDB, and published to SNS.*
![Lambda Configuration](Lambda%20SS.jpg)
![CloudWatch Logs](Cloudwatch%20log%20SS.jpg)

### 4. DynamoDB Audit Record
*Processed record stored in the EventProcessingRecords table, displaying the generated RecordId, timestamps, payload preview, and PROCESSED_SUCCESS status.*
![DynamoDB Table Part 1](DDB%20Table%201.jpg)
![DynamoDB Table Part 2](DDB%20Table%202.jpg)

### 5. SNS Real-Time Delivery
*Confirmation email delivered by SNS seconds after the S3 upload, containing the execution metadata and payload summary.*
![SNS Notification](SNS%20SS.jpg)

---

## Active Pipeline Flow
This is the step-by-step procedure the architecture follows when data arrives:

| Step | Action | Expected Time |
| :--- | :--- | :--- |
| **1** | User or application uploads a file to the S3 ingestion bucket. | Instant |
| **2** | S3 fires an `Object Created` event to the EventBridge default bus. | Milliseconds |
| **3** | EventBridge matches the bucket name and triggers the Lambda function. | Milliseconds |
| **4** | Lambda reads the S3 file, formats the data, and writes the `RecordId` to DynamoDB. | ~1 to 2 seconds |
| **5** | Lambda publishes the execution summary to SNS. | Milliseconds |
| **6** | SNS delivers the real-time alert to the subscribed email address. | ~1 second |

---

## Key Design Decisions & Trade-offs

### Design Decisions
| Decision | Rationale |
| :--- | :--- |
| **EventBridge over Direct S3 Triggers** | Decouples storage from compute. Allows adding new services to react to the same upload later without modifying the S3 bucket. |
| **DynamoDB On-Demand Capacity** | Fits the serverless EDA model perfectly by scaling to zero when no files are being processed. |
| **Custom IAM Inline Policy** | Using the standard `AWSLambdaExecute` managed policy grants access to *all* S3 buckets. Writing a custom policy ensures a compromised Lambda can't read unauthorized data. |
| **Converting floats in Python** | DynamoDB throws a serialization error when saving Python floats. The Lambda code intercepts and formats these into strings/integers to prevent pipeline failures. |

### Trade-offs and Enhancements
-   **Cold Starts:** Because Lambda scales to zero, the very first file uploaded after a period of inactivity might take slightly longer to process. Provisioned Concurrency eliminates this but adds a fixed hourly cost.
-   **Dead-Letter Queues (DLQ):** Currently, if Lambda fails to process a file (e.g., due to a code error), the event is dropped. Adding an SQS DLQ to the EventBridge target would catch failed events for reprocessing.
-   **Infrastructure as Code:** The architecture is currently designed to be deployed via Terraform (or AWS CloudFormation) to ensure exact environment replication for production deployments.

---

## Cost Estimate
*(Note: All resources used in this architecture are fully covered under the AWS Free Tier, making the running cost for this portfolio project $0.00.)*

| Service | Cost Estimation |
| :--- | :--- |
| **Amazon S3** | Standard storage rates (First 5GB/month free). |
| **Amazon EventBridge** | $1.00 per million custom events (Free tier covers this). |
| **AWS Lambda** | $0.20 per 1M requests (First 1M requests/month free). |
| **Amazon DynamoDB** | $1.25 per million write request units (First 25GB and 2.5M writes/month free). |
| **Amazon SNS** | $2.00 per 100,000 email deliveries (First 1,000 emails/month free). |

---
**Author:** Olabanji Badru  
**Portfolio:** [github.com/Olabadmanji](https://github.com/Olabadmanji)