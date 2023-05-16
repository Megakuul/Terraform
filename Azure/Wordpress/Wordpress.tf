terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.0.0"
    }
  }
}

# Configure the Azure Provider
# To set the subscription enter following:
# az account set --subscription "subscriptionid"
provider "azurerm" {
  features {
  }
}

# Create a resource group
resource "azurerm_resource_group" "rg" {
  name     = "rg-wordpress-prod-${var.region}-${var.inf_version}"
  location = var.region
}

# Create a vnet
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-wordpress-prod-${var.region}-${var.inf_version}"
  address_space       = ["10.0.0.0/16"]
  location            = var.region
  resource_group_name = azurerm_resource_group.rg.name
}

# Create the first subnet for the database
resource "azurerm_subnet" "vsub1" {
  name                 = "vsub-wordpress-db-prod-${var.region}-${var.inf_version}"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
  service_endpoints = ["Microsoft.Storage"]
  delegation {
    name = "flexible-srv"
    service_delegation {
      name = "Microsoft.DBforMySQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action"
      ]
    }
  }
}

# Create the second subnet for the app service
resource "azurerm_subnet" "vsub2" {
  name                 = "vsub-wordpress-app-prod-${var.region}-${var.inf_version}"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]
  delegation {
    name = "server-farms"
    service_delegation {
      name = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# Create the Network injector for the app service
resource "azurerm_app_service_virtual_network_swift_connection" "vsub2-integration" {
  app_service_id    = azurerm_app_service.app.id
  subnet_id         = azurerm_subnet.vsub2.id
}

# Create a MySQL Server
resource "azurerm_mysql_flexible_server" "database-server" {
  name                    = "db-srv-wordpress-prod-${var.region}-${var.inf_version}"
  location                = var.region
  resource_group_name     = azurerm_resource_group.rg.name

  administrator_login     = "deradmin"
  administrator_password  = "J6USO4lyvnzV96mT"
  sku_name                = "GP_Standard_D2ds_v4"

  backup_retention_days   = 7

  delegated_subnet_id     = azurerm_subnet.vsub1.id
}

# Configuration for MySQL Server
# Disable SSL enforcement
resource "azurerm_mysql_flexible_server_configuration" "require_secure_transport" {
  name                = "require_secure_transport"
  resource_group_name = azurerm_resource_group.rg.name
  server_name         = azurerm_mysql_flexible_server.database-server.name
  value               = "OFF"
}

# Create a MySQL Database
resource "azurerm_mysql_flexible_database" "database" {
  name                = "db-wordpress-prod-${var.region}-${var.inf_version}"
  resource_group_name = azurerm_resource_group.rg.name
  server_name         = azurerm_mysql_flexible_server.database-server.name
  charset             = "utf8"
  collation           = "utf8_general_ci"
}

# Create an App Service Plan
resource "azurerm_app_service_plan" "app-plan" {
  name                = "app-plan-wordpress-prod-${var.region}-${var.inf_version}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg.name
  kind                = "Linux"
  reserved            = true
  sku {
    tier = "Basic"
    size = "B1"
  }
}

# Create an App Service
resource "azurerm_app_service" "app" {
  name                = "app-wordpress-prod-${var.region}-${var.inf_version}"
  location            = var.region
  resource_group_name = azurerm_resource_group.rg.name
  app_service_plan_id = azurerm_app_service_plan.app-plan.id
  https_only          = true

    site_config {
    always_on        = true
    linux_fx_version = "DOCKER|wordpress:latest"
  }

  app_settings = {
    "WEBSITES_ENABLE_APP_SERVICE_STORAGE" = "false"
    "DOCKER_REGISTRY_SERVER_URL"          = "https://index.docker.io"
    "WORDPRESS_DB_HOST"                   = azurerm_mysql_flexible_server.database-server.fqdn
    "WORDPRESS_DB_NAME"                   = azurerm_mysql_flexible_database.database.name
    "WORDPRESS_DB_USER"                   = azurerm_mysql_flexible_server.database-server.administrator_login
    "WORDPRESS_DB_PASSWORD"               = azurerm_mysql_flexible_server.database-server.administrator_password
    "WORDPRESS_DEBUG"                     = "1"
  }

  connection_string {
    name  = "Database"
    type  = "MySQL"
    value = "Server=${azurerm_mysql_flexible_server.database-server.fqdn};Database=${azurerm_mysql_flexible_database.database.name};Uid=${azurerm_mysql_flexible_server.database-server.administrator_login}@${azurerm_mysql_flexible_server.database-server.name};Pwd=${azurerm_mysql_flexible_server.database-server.administrator_password};"
  }
}