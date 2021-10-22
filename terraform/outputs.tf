output "linux_vm_public_name" {
  value = module.linuxservers.public_ip_dns_name[0]
}

output "cart_service_host" {
  value = module.linuxservers.network_interface_private_ip[0]
}

output "redis_host" {
  value = azurerm_private_dns_a_record.a_record.fqdn
}

output "redis_password" {
  value = substr(split(",", azurerm_redis_cache.redis.primary_connection_string)[1], 9, length(azurerm_redis_cache.redis.primary_connection_string) - 9)
}
