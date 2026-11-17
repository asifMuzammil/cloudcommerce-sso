variable "region" {
  description = "AWS region for the dev box"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "16 GB RAM: ForgeRock AM + DS + Medusa + Postgres + Redis together"
  type        = string
  default     = "t3.xlarge"
}

variable "root_volume_gb" {
  description = "Docker images (AM ~1.4 GB, DS ~0.6 GB) + Medusa node_modules need room"
  type        = number
  default     = 40
}
