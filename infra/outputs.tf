output "server_ipv4" {
  description = "Public IPv4 address of the task host."
  value       = hcloud_server.task_host.ipv4_address
}

output "server_ipv6" {
  description = "Public IPv6 address of the task host."
  value       = hcloud_server.task_host.ipv6_address
}
