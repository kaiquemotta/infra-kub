provider "aws" {
  region = "us-east-1"
}

# Verificação e Criação do Papel IAM do EKS Cluster
data "aws_iam_role" "eks_cluster_role_new" {
  name = "eks_cluster_role_new"
}

resource "aws_iam_role" "eks_cluster_role_new" {
  # Só cria o papel se ele não existir
  count = length(data.aws_iam_role.eks_cluster_role_new.id) == 0 ? 1 : 0

  name = "eks_cluster_role_new"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })
}

resource "null_resource" "create_cluster_policy_attachments" {
  count = length(aws_iam_role.eks_cluster_role_new) > 0 ? 1 : 0

  provisioner "local-exec" {
    command = <<EOT
      aws iam attach-role-policy --role-name eks_cluster_role_new --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
      aws iam attach-role-policy --role-name eks_cluster_role_new --policy-arn arn:aws:iam::aws:policy/AmazonEKSVPCResourceController
    EOT
  }

  triggers = {
    cluster_role_created = aws_iam_role.eks_cluster_role_new[count.index].id
  }
}

# Verificação e Criação do Papel IAM do EKS Node
data "aws_iam_role" "eks_node_role_new" {
  name = "eks_node_role_new"
}

resource "aws_iam_role" "eks_node_role_new" {
  count = length(data.aws_iam_role.eks_node_role_new.id) == 0 ? 1 : 0

  name = "eks_node_role_new"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "null_resource" "create_node_policy_attachments" {
  count = length(aws_iam_role.eks_node_role_new) > 0 ? 1 : 0

  provisioner "local-exec" {
    command = <<EOT
      aws iam attach-role-policy --role-name eks_node_role_new --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
      aws iam attach-role-policy --role-name eks_node_role_new --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
    EOT
  }

  triggers = {
    node_role_created = aws_iam_role.eks_node_role_new[count.index].id
  }
}

# Utilizando uma VPC existente
data "aws_vpc" "selected" {
  id = "vpc-015416e2606ea05dc"
}

# Declarando as sub-redes existentes dentro da VPC
variable "subnet_ids" {
  description = "List of subnet IDs"
  type        = list(string)
  default     = ["subnet-0d03fd1174a3d8e42", "subnet-0e5b69a0f2630bad1"]
}

resource "aws_eks_cluster" "my_cluster" {
  name     = "my-cluster"
  role_arn = try(aws_iam_role.eks_cluster_role_new[0].arn, data.aws_iam_role.eks_cluster_role_new.arn)

  vpc_config {
    subnet_ids = var.subnet_ids
  }

  depends_on = [
    null_resource.create_cluster_policy_attachments,
  ]
}

resource "aws_eks_node_group" "my_node_group" {
  cluster_name    = aws_eks_cluster.my_cluster.name
  node_group_name = "my-node-group"
  node_role_arn   = try(aws_iam_role.eks_node_role_new[0].arn, data.aws_iam_role.eks_node_role_new.arn)
  subnet_ids      = var.subnet_ids

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  depends_on = [
    null_resource.create_node_policy_attachments,
  ]
}
