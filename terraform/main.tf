locals {
  tags = {
    ArchitectVersion = "1.0.0"
  }
}

resource "azurerm_resource_group" "architect" {
  name     = "architect-azure-resource-group"
  location = "East US"

  tags = local.tags
}

module "linuxservers" {
  vm_hostname = "architect-vm"

  source              = "Azure/compute/azurerm"
  resource_group_name = azurerm_resource_group.architect.name
  vm_os_simple        = "UbuntuServer"
  public_ip_dns       = ["architect"]
  vnet_subnet_id      = module.network.vnet_subnets[0]

  storage_account_type = "Standard_LRS"

  depends_on = [azurerm_resource_group.architect]

  tags = local.tags
}

module "network" {
  vnet_name = "architect-vnet"

  source              = "Azure/network/azurerm"
  resource_group_name = azurerm_resource_group.architect.name
  subnet_prefixes     = ["10.0.1.0/24"]
  subnet_names        = ["subnet1"]

  depends_on = [azurerm_resource_group.architect]

  subnet_enforce_private_link_endpoint_network_policies = { subnet1 = true }

  tags = local.tags
}

data "azurerm_network_security_group" "vm_nsg" {
  name                = "architect-vm-nsg"
  resource_group_name = azurerm_resource_group.architect.name
}

resource "azurerm_network_security_rule" "ssh" {
  name                        = "architect-ssh-rule"
  resource_group_name         = azurerm_resource_group.architect.name
  network_security_group_name = data.azurerm_network_security_group.vm_nsg.name

  priority                   = 100
  direction                  = "Inbound"
  access                     = "Allow"
  protocol                   = "Tcp"
  source_port_range          = "*"
  destination_port_range     = "22"
  source_address_prefix      = "*"
  destination_address_prefix = "*"
}

resource "azurerm_network_security_rule" "app" { # TODO: update for source only inside of network
  name                        = "architect-app-rule"
  resource_group_name         = azurerm_resource_group.architect.name
  network_security_group_name = data.azurerm_network_security_group.vm_nsg.name

  priority                   = 101
  direction                  = "Inbound"
  access                     = "Allow"
  protocol                   = "Tcp"
  source_port_range          = "*"
  destination_port_range     = "7070"
  source_address_prefix      = "*"
  destination_address_prefix = "*"
}

resource "azurerm_redis_cache" "redis" {
  name                = "architect-redis"
  location            = azurerm_resource_group.architect.location
  resource_group_name = azurerm_resource_group.architect.name

  family   = "C"
  sku_name = "Basic"

  enable_non_ssl_port = true # enable 6379
  shard_count         = 0
  capacity            = 1

  redis_version = 4

  depends_on = [
    module.network
  ]

  tags = local.tags
}

resource "azurerm_redis_firewall_rule" "redis_firewall_rule" {
  name = "architect_redis_firewall_rule"

  redis_cache_name    = azurerm_redis_cache.redis.name
  resource_group_name = azurerm_resource_group.architect.name

  start_ip = cidrhost(module.network.vnet_address_space[0], 0)
  end_ip   = cidrhost(module.network.vnet_address_space[0], -1)
}

resource "azurerm_private_endpoint" "redis_private_endpoint" {
  name                = "architect-private-endpoint"
  location            = azurerm_resource_group.architect.location
  resource_group_name = azurerm_resource_group.architect.name
  subnet_id           = module.network.vnet_subnets[0]
  tags                = local.tags

  private_service_connection {
    name                           = "architect-rediscache-privatelink"
    is_manual_connection           = false
    private_connection_resource_id = azurerm_redis_cache.redis.id
    subresource_names              = ["redisCache"]
  }

  private_dns_zone_group {
    name = azurerm_private_dns_zone.dns_zone.name
    private_dns_zone_ids = [azurerm_private_dns_zone.dns_zone.id]
  }
}

data "azurerm_private_endpoint_connection" "private-ip" {
  name                = azurerm_private_endpoint.redis_private_endpoint.name
  resource_group_name = azurerm_resource_group.architect.name
  depends_on          = [azurerm_redis_cache.redis]
}

resource "azurerm_private_dns_zone" "dns_zone" {
  name                = "architect.privatelink.redis.cache.windows.net"
  resource_group_name = azurerm_resource_group.architect.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "vnet_link" {
  name                  = "architect-vnet-private-zone-link"
  resource_group_name   = azurerm_resource_group.architect.name
  private_dns_zone_name = azurerm_private_dns_zone.dns_zone.name
  virtual_network_id    = module.network.vnet_id
  tags                  = local.tags
}

resource "azurerm_private_dns_a_record" "a_record" {
  name                = azurerm_redis_cache.redis.name
  zone_name           = azurerm_private_dns_zone.dns_zone.name
  resource_group_name = azurerm_resource_group.architect.name
  ttl                 = 300
  records             = [data.azurerm_private_endpoint_connection.private-ip.private_service_connection.0.private_ip_address]
}

# Enabling preview features for the Azure subscription is currently required due to https://github.com/hashicorp/terraform-provider-azurerm/issues/11396
# https://docs.microsoft.com/en-us/azure/aks/upgrade-cluster#set-auto-upgrade-channel
module "aks" {
  source                           = "Azure/aks/azurerm"
  resource_group_name              = azurerm_resource_group.architect.name
  prefix                           = "architect"
  cluster_name                     = "architect-kubernetes-cluster"
  network_plugin                   = "azure"
  sku_tier                         = "Paid"
  vnet_subnet_id                   = module.network.vnet_subnets[0]
  os_disk_size_gb                  = 50
  enable_http_application_routing  = true
  enable_auto_scaling              = true
  agents_min_count                 = 1
  agents_max_count                 = 2
  agents_count                     = null # null to avoid possible agents_count changes
  agents_max_pods                  = 100
  agents_pool_name                 = substr("architect", 0, 12)
  agents_availability_zones        = ["1", "2"]

  agents_labels = {
    "nodepool": "architect-default-node-pool"
  }

  agents_tags = merge(local.tags, { "Agent": "architect-default-node-pool-agent" })

  network_policy                 = "azure"
  net_profile_dns_service_ip     = "20.0.0.10"
  net_profile_docker_bridge_cidr = "170.10.0.1/16"
  net_profile_service_cidr       = "20.0.0.0/16"

  tags = local.tags

  depends_on = [module.network]
}

resource "local_file" "kubeconfig" {
  filename = "${path.module}/architect-kubeconfig"
  sensitive_content = module.aks.kube_config_raw
}
