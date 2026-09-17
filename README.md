# AWS Detection/Security Home-Lab

A hands-on cloud security lab built to close a real gap: practical AWS/Terraform experience backing up RMF/ISSO/compliance-focused DoD contracting work.

## Stack
Terraform → AWS (VPC/EC2/IAM) → Splunk Free → Nessus/OpenVAS → MITRE ATT&CK detections

## Status
**Phase 1 complete:** VPC, subnet, IGW, route table, security group, IAM role/instance profile, and EC2 instance provisioned via Terraform. SSH access verified.

## Roadmap
1. Terraform + AWS foundation (VPC, EC2, IAM) - done
2. Splunk Free deployment + CloudTrail/VPC Flow Log ingestion
3. Vulnerability scanning (Nessus/OpenVAS) + POA&M remediation tracker
4. Detections mapped to MITRE ATT&CK techniques
5. Full documentation pass (architecture diagram, write-up)

## Structure
terraform/    - IaC for VPC/EC2/IAM
splunk/       - SIEM config (session 2)
scans/        - vulnerability scan reports + POA&M tracker (session 3)
detections/   - Splunk searches + ATT&CK mapping (session 4)
docs/         - architecture diagram + write-up (session 5)
