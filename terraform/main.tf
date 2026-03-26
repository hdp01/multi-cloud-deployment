terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] 

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

provider "aws" {
  region = "us-east-1"
}

provider "azurerm" {
  features {}
}

module "aws_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.0.0"

  name = "multi-cloud-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "19.15.3"

  cluster_name    = "multi-cloud-eks"
  cluster_version = "1.30" 

  vpc_id                         = module.aws_vpc.vpc_id
  subnet_ids                     = module.aws_vpc.private_subnets
  cluster_endpoint_public_access = true

  eks_managed_node_groups = {
    general = {
      desired_size = 1
      min_size     = 1
      max_size     = 1
      instance_types = ["t3.medium"] 
    }
  }
}

resource "azurerm_resource_group" "mc_rg" {
  name     = "multi-cloud-rg"
  location = "East US"
}

resource "azurerm_virtual_network" "mc_vnet" {
  name                = "mc-vnet"
  address_space       = ["10.1.0.0/16"]
  location            = azurerm_resource_group.mc_rg.location
  resource_group_name = azurerm_resource_group.mc_rg.name
}

resource "azurerm_subnet" "mc_subnet" {
  name                 = "mc-subnet"
  resource_group_name  = azurerm_resource_group.mc_rg.name
  virtual_network_name = azurerm_virtual_network.mc_vnet.name
  address_prefixes     = ["10.1.1.0/24"]
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = "multi-cloud-aks"
  location            = azurerm_resource_group.mc_rg.location
  resource_group_name = azurerm_resource_group.mc_rg.name
  dns_prefix          = "mc-aks"

  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = "Standard_B2s"
    vnet_subnet_id = azurerm_subnet.mc_subnet.id
  }

  identity {
    type = "SystemAssigned"
  }
}

resource "aws_key_pair" "deployer" {
  key_name   = "mc-deployer-key"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCv0gjIudop2F03oOnIYpCrL5gkTvmTWEpDr2gdf7Gul/MlFylxwGvzCatJwcWqkBwrNUvnaVxafPj+3wQuqzDpwebPbePn1HSxN5kA0BElCBX9vdrrP/yKOmK/3ta9+AbasvG6yaJo9YVIcg1aSKVqoxPR6YNK9U7VVnL7qVpw3iOmXQcZCY8xXJ020waslMXwztAQnToHY5VjiprCgyMHqnpgJiSovD1ey6v/iL96NryPYlxPGLw2PdcxuR3RhffTD4c7g1Alj5IYl2gJe+fVlcnBwiBr7axAXCqs6hDCv4ARLDBcFBeanCz4fdydSp26r5LcSWa6MQgbfx+uApZZcKIN3JmDj3zf0g6+vsoZ6doi2uqIvThEypOWPtOhjd00c1xNYVLM7wFKipAnCpzt6x9yKgVtEcdrhkK8jaJ/dpFXkBP+kK/mvreSit2ZeK9O14VV3MlKwvFY2COd87bFy+SgVECt3N8XmHeRJn+q5jpHmTESONlyUhNptpt7M0plW2hqZP0Av+QET01oByTjg2iKCMNGZZxb0zD14xtTsAFS1rMWiGdrbPFbwhieqV/MIi6wKyk3RB5SwLg3nOF9o7XJz+y4UGsS+r8j3rUYdDfhi4KFeznjBunZpLeiDW6ZvkgsrZ+rKHsJKZRbiMwbCZ7jiuDq1xbWhPTYbm/5Bw== harsshhh@HP-Lenovo-15IHU"
}

resource "aws_security_group" "nginx_sg" {
  name        = "nginx_sg"
  vpc_id      = module.aws_vpc.vpc_id
  description = "Allow HTTP and SSH"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "nginx_gateway" {
  ami                    = data.aws_ami.ubuntu.id 
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.nginx_sg.id]
  subnet_id              = module.aws_vpc.public_subnets[0]
  associate_public_ip_address = true 

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file("../mc-key") 
    host        = self.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt update -y",
      "sudo apt install nginx -y",
      "sudo systemctl start nginx",
      "sudo bash -c 'echo \"Waiting for K8s endpoints...\" > /var/www/html/index.html'"
    ]
  }
}

output "nginx_public_ip" {
  description = "The Public IP of the Nginx Gateway. Use this as your Single URL."
  value       = aws_instance.nginx_gateway.public_ip
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "aks_cluster_name" {
  value = azurerm_kubernetes_cluster.aks.name
}