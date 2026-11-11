module "networking" {
  source       = "./modules/networking"
  project      = var.project
  region       = var.region
  vpc_cidr     = var.vpc.cidr
  subnets      = var.vpc.subnets
  cluster_name = var.eks_cluster.name
}

locals {
  cluster_subnet_ids = [for name in var.eks_cluster.subnets : module.networking.sn_ids[name]]
}

module "eks" {
  source      = "./modules/eks"
  project     = var.project
  region      = var.region
  name        = var.eks_cluster.name
  k8s_version = var.eks_cluster.version
  vpc_id      = module.networking.vpc_id
  vpc_cidr    = var.vpc.cidr
  subnet_ids  = local.cluster_subnet_ids

  node_groups = [
    for ng in var.eks_cluster.node_groups : {
      name       = ng.name
      labels     = ng.labels
      subnet_ids = [for sn in ng.subnets : module.networking.sn_ids[sn]]
    }
  ]

  configure_kubectl = { region = var.region }
}

module "ecr" {
  source   = "./modules/ecr"
  for_each = { for r in var.ecr_registries : r.name => r }

  region          = var.region
  repository_name = each.value.name
  image_path      = each.value.image_path
  image_tag       = each.value.image_tag
}
