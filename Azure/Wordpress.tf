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
  name     = "rg-wordpress-prod-northeu-001"
  location = "northeurope"
}

# Create a virtual network
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-wordpress-prod-northeu-001"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Create the first subnet for the database
resource "azurerm_subnet" "vsub1" {
  name                 = "vsub-wordpress-prod-northeu-001"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Create the second subnet for the app service
resource "azurerm_subnet" "vsub2" {
  name                 = "vsub-wordpress-prod-northeu-002"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}

# Create a MySQL Server
resource "azurerm_mysql_server" "database-server" {
  name                = "db-srv-wordpress-prod-northeu-001"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  administrator_login          = "deradmin"
  administrator_login_password = "J6USO4lyvnzV96mT"

  sku_name   = "B_Gen5_2"
  storage_mb = 5120
  version    = "8.0"

  auto_grow_enabled                 = true
  backup_retention_days             = 7
  geo_redundant_backup_enabled      = false
  infrastructure_encryption_enabled = false
  public_network_access_enabled     = true
  ssl_enforcement_enabled           = true
}

# Create a MySQL Database
resource "azurerm_mysql_database" "database" {
  name                = "db-wordpress-prod-northeu-001"
  resource_group_name = azurerm_resource_group.rg.name
  server_name         = azurerm_mysql_server.database-server.name
  charset             = "utf8"
  collation           = "utf8_general_ci"
}

# Create an App Service Plan
resource "azurerm_app_service_plan" "app-plan" {
  name                = "app-plan-wordpress-prod-northeu-001"
  location            = azurerm_resource_group.rg.location
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
  name                = "app-wordpress-prod-northeu-001"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  app_service_plan_id = azurerm_app_service_plan.app-plan.id
  https_only          = true

    site_config {
    always_on        = true
    linux_fx_version = "DOCKER|wordpress:latest"
  }

  app_settings = {
    "WEBSITES_ENABLE_APP_SERVICE_STORAGE" = "false"
    "DOCKER_REGISTRY_SERVER_URL" = "https://index.docker.io"
    "WORDPRESS_DB_HOST" = azurerm_mysql_server.database-server.fqdn
    "WORDPRESS_DB_NAME" = azurerm_mysql_database.database.name
    "WORDPRESS_DB_USER" = "${azurerm_mysql_server.database-server.administrator_login}@${azurerm_mysql_server.database-server.name}"
    "WORDPRESS_DB_PASSWORD" = azurerm_mysql_server.database-server.administrator_login_password
    "WORDPRESS_DEBUG" = "1"
  }

  connection_string {
    name  = "Database"
    type  = "MySQL"
    value = "Server=${azurerm_mysql_server.database-server.fqdn};Database=${azurerm_mysql_database.database.name};Uid=${azurerm_mysql_server.database-server.administrator_login}@${azurerm_mysql_server.database-server.name};Pwd=${azurerm_mysql_server.database-server.administrator_login_password};"
  }
}