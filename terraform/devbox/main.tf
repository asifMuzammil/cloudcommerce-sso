# ---------------------------------------------------------------------------
# Dev box: one EC2 instance, reachable ONLY through SSM Session Manager.
# No SSH key, no inbound ports. Uses the default VPC on purpose (dev only);
# the production stack later gets its own VPC.
# ---------------------------------------------------------------------------

# Latest Ubuntu 24.04 AMI, published by Canonical as a public SSM parameter
# (no hard-coded AMI IDs that go stale or differ per region).
data "aws_ssm_parameter" "ubuntu_2404" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

data "aws_vpc" "default" {
  default = true
}

# --- IAM: let the instance register with Systems Manager -------------------
# Name must start with "cloudcommerce-" -> matches our scoped IAM policy.
resource "aws_iam_role" "devbox" {
  name = "cloudcommerce-devbox-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.devbox.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "devbox" {
  name = "cloudcommerce-devbox-profile"
  role = aws_iam_role.devbox.name
}

# --- Security group: NO inbound rules at all --------------------------------
# SSM agent dials OUT to AWS, so we never open 22/8080/9000 to the internet.
resource "aws_security_group" "devbox" {
  name        = "cloudcommerce-devbox-sg"
  description = "Dev box: no inbound, all outbound (SSM, docker pulls, npm)"
  vpc_id      = data.aws_vpc.default.id

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- The instance -----------------------------------------------------------
resource "aws_instance" "devbox" {
  ami                    = data.aws_ssm_parameter.ubuntu_2404.value
  instance_type          = var.instance_type
  iam_instance_profile   = aws_iam_instance_profile.devbox.name
  vpc_security_group_ids = [aws_security_group.devbox.id]

  # Public IP only so it can reach the internet without a NAT Gateway (~$32/month).
  # Nothing can come IN because the security group has no ingress rules.
  associate_public_ip_address = true

  user_data = file("${path.module}/user_data.sh")

  # IMDSv2 only: blocks SSRF-style credential theft via the metadata endpoint.
  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_size = var.root_volume_gb
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name = "cloudcommerce-devbox"
  }

  # A new Ubuntu AMI is published every few weeks; don't recreate the box
  # (and lose our ForgeRock config) just because of that.
  lifecycle {
    # user_data only runs on first boot; changing it must not replace or
    # restart this box (the ForgeRock config lives on it).
    ignore_changes = [ami, user_data]
  }
}
