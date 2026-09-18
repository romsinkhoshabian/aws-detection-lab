terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# --- Networking ---
resource "aws_vpc" "lab" {
  cidr_block           = "10.10.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "detection-lab-vpc" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = "10.10.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a"
  tags = { Name = "detection-lab-public" }
}

resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id
  tags = { Name = "detection-lab-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.lab.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab.id
  }
  tags = { Name = "detection-lab-public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# --- Security ---
resource "aws_security_group" "lab" {
  name        = "detection-lab-sg"
  description = "Lab access - SSH restricted to my IP"
  vpc_id      = aws_vpc.lab.id

  ingress {
    description = "SSH from my IP only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.my_ip}/32"]
  }

  ingress {
    description = "Splunk Web from my IP only"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["${var.my_ip}/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "detection-lab-sg" }
}

# --- IAM (instance role, pre-wired for session 2's log shipping) ---
resource "aws_iam_role" "lab_instance" {
  name = "detection-lab-instance-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cloudwatch" {
  role       = aws_iam_role.lab_instance.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "lab_instance" {
  name = "detection-lab-instance-profile"
  role = aws_iam_role.lab_instance.name
}

# --- Compute ---
resource "aws_key_pair" "lab" {
  key_name   = "detection-lab-key"
  public_key = file("~/.ssh/detection-lab.pub")
}

resource "aws_instance" "lab" {
  ami                    = "ami-05dee78f58650ed2c" # Amazon Linux 2023, us-east-1 - confirm current AMI in console
  instance_type          = "t3.large"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.lab.id]
  key_name               = aws_key_pair.lab.key_name
  iam_instance_profile   = aws_iam_instance_profile.lab_instance.name

  tags = { Name = "detection-lab-host" }

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }
}

output "instance_public_ip" {
  value = aws_instance.lab.public_ip
}
# --- Logging infrastructure (session 2) ---
data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "logs" {
  bucket        = "detection-lab-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = true # lab convenience - lets terraform destroy clean up even with log objects inside
  tags          = { Name = "detection-lab-logs" }
}

data "aws_iam_policy_document" "logs_bucket_policy" {
  statement {
    sid     = "AWSCloudTrailAclCheck"
    effect  = "Allow"
    actions = ["s3:GetBucketAcl"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    resources = [aws_s3_bucket.logs.arn]
  }

  statement {
    sid     = "AWSCloudTrailWrite"
    effect  = "Allow"
    actions = ["s3:PutObject"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    resources = ["${aws_s3_bucket.logs.arn}/cloudtrail/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }

  statement {
    sid     = "AWSLogDeliveryAclCheck"
    effect  = "Allow"
    actions = ["s3:GetBucketAcl"]
    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
    resources = [aws_s3_bucket.logs.arn]
  }

  statement {
    sid     = "AWSLogDeliveryWrite"
    effect  = "Allow"
    actions = ["s3:PutObject"]
    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
    resources = ["${aws_s3_bucket.logs.arn}/vpc-flow-logs/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id
  policy = data.aws_iam_policy_document.logs_bucket_policy.json
}

resource "aws_cloudtrail" "lab" {
  name                          = "detection-lab-trail"
  s3_bucket_name                = aws_s3_bucket.logs.id
  s3_key_prefix                 = "cloudtrail"
  include_global_service_events = true
  is_multi_region_trail         = false
  enable_logging                = true

  depends_on = [aws_s3_bucket_policy.logs]
}

resource "aws_flow_log" "lab" {
  log_destination      = "${aws_s3_bucket.logs.arn}/vpc-flow-logs"
  log_destination_type = "s3"
  traffic_type          = "ALL"
  vpc_id                = aws_vpc.lab.id

  depends_on = [aws_s3_bucket_policy.logs]
}

resource "aws_iam_role_policy" "read_logs_bucket" {
  name = "detection-lab-read-logs-bucket"
  role = aws_iam_role.lab_instance.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:ListBucket"]
      Resource = [
        aws_s3_bucket.logs.arn,
        "${aws_s3_bucket.logs.arn}/*"
      ]
    }]
  })
}
# --- SQS for CloudTrail S3 event notifications (session 2) ---
resource "aws_sqs_queue" "cloudtrail" {
  name                      = "detection-lab-cloudtrail-queue"
  message_retention_seconds = 345600 # 4 days
  tags                      = { Name = "detection-lab-cloudtrail-queue" }
}

data "aws_iam_policy_document" "cloudtrail_queue_policy" {
  statement {
    effect  = "Allow"
    actions = ["sqs:SendMessage"]
    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
    resources = [aws_sqs_queue.cloudtrail.arn]
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.logs.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "cloudtrail" {
  queue_url = aws_sqs_queue.cloudtrail.id
  policy    = data.aws_iam_policy_document.cloudtrail_queue_policy.json
}

resource "aws_s3_bucket_notification" "logs" {
  bucket = aws_s3_bucket.logs.id

  queue {
    queue_arn     = aws_sqs_queue.cloudtrail.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "cloudtrail/"
  }
  queue {
    queue_arn     = aws_sqs_queue.vpc_flow_logs.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "vpc-flow-logs/"
  }
  depends_on = [aws_sqs_queue_policy.cloudtrail, aws_sqs_queue_policy.vpc_flow_logs]
}
# --- SQS for VPC Flow Log S3 event notifications (session 2) ---
resource "aws_sqs_queue" "vpc_flow_logs" {
  name                      = "detection-lab-vpcflow-queue"
  message_retention_seconds = 345600
  tags                      = { Name = "detection-lab-vpcflow-queue" }
}

data "aws_iam_policy_document" "vpc_flow_logs_queue_policy" {
  statement {
    effect  = "Allow"
    actions = ["sqs:SendMessage"]
    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
    resources = [aws_sqs_queue.vpc_flow_logs.arn]
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.logs.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "vpc_flow_logs" {
  queue_url = aws_sqs_queue.vpc_flow_logs.id
  policy    = data.aws_iam_policy_document.vpc_flow_logs_queue_policy.json
}
