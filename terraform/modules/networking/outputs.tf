output "vpc_id" {
  value = aws_vpc.this.id
}

output "sn_ids" {
  description = "Map of subnet name -> subnet id"
  value       = local.all_sn_ids
}
