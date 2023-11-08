resource "aws_s3_bucket" "adminui_static_s3" {
  bucket = "tf-adminui-static-s3"

  tags = {
    Name                 = "tf-adminui-static-s3"
    Environment          = "qa"
    c7n_s3_public_access = "yes"
  }
}
module "clientlog_codepipeline" {
  source = "./codepipeline"
  #common variables
  providers = {
    aws.internal = aws.tk
  }
  aws_region = local.aws_region
  ecs_region = local.ecs_region

  project_name    = local.project_name
  project_account = local.project_account
  environment     = local.environment
  vpc_id          = data.aws_vpc.selected.id
  nat_subnets     = local.nat_subnets
  #  codebuild_ci_sg = local.codebuild_ci_sg
  ecr_tag_mutability = "MUTABLE"

  cicd_cache_bucket = module.init_once.cicd_cache_bucket
  cicd_subnetid     = local.nat_subnets[random_integer.priority.result]
  cicd_subnets      = local.nat_subnets
  sns_topic_arn     = module.init_once.devops_sns_arn


  #custom variable
  biz_title           = local.clientlog.title
  source_location     = local.clientlog.source_location
  secondary_source_db = local.clientlog.secondary_source_db
  ci_buildspec_path   = local.clientlog.ci_buildspec_path
  cd_buildspec_path   = local.clientlog.cd_buildspec_path
  internal_domain     = local.internal_domain


  deploycode               = local.clientlog.deploycode
  use_codecommit_poll_mode = false
  #production_approval = true
  #two_approval = true
  #upload image to s3

  cicd_cache_permission = templatefile("${path.module}/policies/codepipeline.json", { s3_arn : module.init_once.cicd_cache_bucket_arn })

}


module "clientlog_farget" {
  source  = "ztsstakingtfe.toolsfdg.net/zts/ecs-fargate/module"
  version = "0.1.0"
  #common variables
  providers = {
    aws.internal = aws.tk
  }

  aws_region      = local.aws_region
  project_name    = local.project_name
  project_account = local.project_account
  environment     = local.environment
  vpc_id          = data.aws_vpc.selected.id


  ecs_nat_subnets = local.ecs_nat_subnets
  biz_title       = local.clientlog.title
  albin_subnets   = local.albex_subnets

  namespace_id  = module.init_once.namespace_id
  sns_topic_arn = module.init_once.devops_sns_arn

  alb_log_bucket = module.init_once.alb_log_bucket
  alb_certs_arn  = local.alb_certs_arn

  #custom
  if_internal        = true
  desired_count      = 2
  container_port     = local.clientlog.container_port
  hc_path            = "/api/v1/health"
  hc_response        = "200"
  secrets_permission = local.secrets_arn_list.clientlog
  ecs_cpu            = 1024
  ecs_memory         = 2048
}

### security group rules

locals {
  clientlog_farget_sg_rules = {
    sg1 = {
      sg_source   = module.clientlog_farget.farget_alb_sg_id
      sg_id       = module.clientlog_farget.farget_sg_id
      from_port   = 8000
      to_port     = 8000
      source_type = "sgid"
      protocol    = "tcp"
      description = "clientlog_allow_alb_sg"
    }
  }

}

module "clientlog_farget_sg_rules" {
  source = "./sgrule"
  providers = {
    aws.internal = aws.tk
  }
  for_each    = local.clientlog_farget_sg_rules
  sg_source   = each.value.sg_source
  sg_id       = each.value.sg_id
  protocol    = each.value.protocol
  from_port   = each.value.from_port
  to_port     = each.value.to_port
  description = each.value.description
}


locals {
  clientlog_alb_ex_sg_rules = {
    sg_source   = ["sg-075dd465c4f8fff88"]
    sg_id       = module.clientlog_farget.farget_alb_sg_id
    from_port   = 80
    to_port     = 80
    source_type = "sgid"
    protocol    = "tcp"
    description = "clientlog_alb_allow_dispatcher_ec2_access"
  }
}

module "clientlog_alb_ex_sg_rules" {
  source = "./sgrule"
  providers = {
    aws.internal = aws.tk
  }
  for_each    = { for s in local.clientlog_alb_ex_sg_rules.sg_source : s => s }
  sg_source   = each.value
  sg_id       = local.clientlog_alb_ex_sg_rules.sg_id
  protocol    = local.clientlog_alb_ex_sg_rules.protocol
  from_port   = local.clientlog_alb_ex_sg_rules.from_port
  to_port     = local.clientlog_alb_ex_sg_rules.to_port
  description = local.clientlog_alb_ex_sg_rules.description
}

module "clientlog_alb_dispatcher_sg_rules" {
  source = "./sgrule"
  providers = {
    aws.internal = aws.tk
  }
  sg_source   = module.dispatcher_private.sg_id
  sg_id       = module.clientlog_farget.farget_alb_sg_id
  protocol    = "tcp"
  from_port   = 80
  to_port     = 80
  description = "clientlog_alb_allow_dispatcher_ec2_access"
}


