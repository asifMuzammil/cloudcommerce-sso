output "instance_id" {
  value = aws_instance.devbox.id
}

output "connect" {
  description = "Open a shell on the dev box (no SSH)"
  value       = "aws ssm start-session --target ${aws_instance.devbox.id}"
}

output "stop" {
  description = "Stop when you are done for the day (keeps the disk, stops compute billing)"
  value       = "aws ec2 stop-instances --instance-ids ${aws_instance.devbox.id}"
}

output "start" {
  value = "aws ec2 start-instances --instance-ids ${aws_instance.devbox.id}"
}
