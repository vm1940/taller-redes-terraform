terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "admin_password" {
  type = string
  sensitive = true
}

variable "location" {
  type = string
  default = "eastus"
}

variable "vm_size" {
  type = string
  default = "Standard_B1s"
}

locals {
  maquinas = {
    "maquina-1" = "10.0.0.4"
    "maquina-2" = "10.0.0.5"
  }
}

resource "azurerm_resource_group" "rg" {
  name = "rg-laboratorio-final"
  location = var.location
}

resource "azurerm_virtual_network" "vnet" {
  name = "red-clase-final"
  address_space = ["10.0.0.0/16"]
  location = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "subnet" {
  name = "subnet-28"
  resource_group_name = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes = ["10.0.0.0/28"]
}

resource "azurerm_network_security_group" "nsg" {
  name = "nsg-lab"
  location = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name = "AllowSSH"
    priority = 100
    direction = "Inbound"
    access = "Allow"
    protocol = "Tcp"
    source_port_range = "*"
    destination_port_range = "22"
    source_address_prefix = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name = "DenyPingDesdeHost"
    priority = 200
    direction = "Inbound"
    access = "Deny"
    protocol = "Icmp"
    source_port_range = "*"
    destination_port_range = "*"
    source_address_prefix = "Internet"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "assoc" {
  subnet_id = azurerm_subnet.subnet.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_public_ip" "pip" {
  for_each = local.maquinas
  name = "pip-${each.key}"
  location = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method = "Static"
  sku = "Standard"
}

resource "azurerm_network_interface" "nic" {
  for_each = local.maquinas
  name = "nic-${each.key}"
  location = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name = "ipconfig"
    subnet_id = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Static"
    private_ip_address = each.value
    public_ip_address_id = azurerm_public_ip.pip[each.key].id
  }
}

resource "azurerm_linux_virtual_machine" "vm" {
  for_each = local.maquinas
  name = each.key
  location = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  size = var.vm_size
  admin_username = "azureuser"
  admin_password = var.admin_password
  disable_password_authentication = false
  network_interface_ids = [azurerm_network_interface.nic[each.key].id]

  os_disk {
    caching = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer = "ubuntu-24_04-lts"
    sku = "server"
    version = "latest"
  }
}

output "ip_maquina_1" {
  value = azurerm_public_ip.pip["maquina-1"].ip_address
}

output "ip_maquina_2" {
  value = azurerm_public_ip.pip["maquina-2"].ip_address
}