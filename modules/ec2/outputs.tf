output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.this.id
}

output "private_ip" {
  description = "Private IP address of the instance — use for internal service references"
  value       = aws_instance.this.private_ip
}

output "public_ip" {
  description = "Public IP address — Elastic IP if create_elastic_ip is true, otherwise null. Use this for Route 53 A records."
  value       = var.create_elastic_ip ? aws_eip.this[0].public_ip : null
}

output "security_group_id" {
  description = "ID of the instance security group — pass to RDS or other backends to allow traffic from this instance only"
  value       = aws_security_group.this.id
}

output "iam_role_arn" {
  description = "ARN of the IAM role attached to the instance — always present, includes AmazonSSMManagedInstanceCore plus any S3 read policies"
  value       = aws_iam_role.this.arn
}

output "availability_zone" {
  description = "Availability zone where the instance was placed — derived from the subnet"
  value       = aws_instance.this.availability_zone
}

output "data_volume_id" {
  description = "ID of the optional data EBS volume, or null if data_volume_size is 0"
  value       = var.data_volume_size > 0 ? aws_ebs_volume.data[0].id : null
}
