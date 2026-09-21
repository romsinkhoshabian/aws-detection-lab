# AWS Detection Lab

Terraform-provisioned AWS infrastructure that feeds CloudTrail and VPC Flow Logs into Splunk, with authenticated vulnerability scanning and a POA&M remediation tracker. MITRE ATT&CK-mapped detections are next.

## Stack

Terraform → AWS (VPC, EC2, IAM, S3, SQS, CloudTrail, VPC Flow Logs) → Splunk Enterprise (free mode) → Nessus Essentials → MITRE ATT&CK detections (planned)

Infrastructure is created and destroyed with `terraform apply` / `terraform destroy` each session to keep costs down.

## Status

**Phase 1 (complete): Terraform foundation.** VPC, subnet, internet gateway, route table, security group, IAM role/instance profile, and EC2 instance provisioned as code. SSH access verified.

**Phase 2 (complete): Splunk log pipeline.** Splunk Enterprise deployed on the EC2 instance. Terraform provisions an S3 log bucket, CloudTrail, VPC Flow Logs, and two SQS queues. The AWS Add-on for Splunk ingests both CloudTrail and VPC Flow Logs through SQS-based S3 inputs, with live data verified in Splunk.

**Phase 3 (complete): Vulnerability assessment and POA&M.** Credentialed Nessus Essentials scan of the lab host (Amazon Linux 2023) over SSH with sudo escalation. No Critical, High, Medium, or Low findings; the remaining informational results were reviewed for actionable hardening items, which are tracked in a POA&M with remediation steps, status, and target dates (for example, SELinux running in permissive mode and SSH SHA-1 HMAC algorithms enabled). See [`scans/poam-session3.md`](scans/poam-session3.md), including the methodology note on diagnosing a privilege-escalation problem in the scan configuration.

**Phase 4 (planned):** Splunk searches mapped to MITRE ATT&CK techniques.

**Phase 5 (planned):** Architecture diagram and full write-up.

## Structure

```
terraform/   IaC for the VPC, EC2, IAM, S3, SQS, CloudTrail, and VPC Flow Logs
scans/       Vulnerability scan results and POA&M tracker
```
