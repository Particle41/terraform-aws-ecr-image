/**
* Creates an ECR repository and pushes a container image using local bash scripts.
*
* ## Pre-requisites
*
* The following programs must be available on the `PATH` to be able to run the local scripts:
* 
* - `bash`
* - `docker`
* - `aws`
* - `find`
* - `sort`
* - `md5sum`
*/

terraform {
  required_providers {

    aws = {
      source  = "hashicorp/aws"
      version = ">= 3.46.0"
    }

    external = {
      source  = "hashicorp/external"
      version = ">= 2.1.0"
    }

    null = {
      source  = "hashicorp/null"
      version = ">= 3.1.0"
    }

  }
}

locals {
  hash = data.external.hash.result["hash"]
  repo_name = var.ecr_namespace != null && var.ecr_namespace != "" ? "${var.ecr_namespace}/${var.image_suffix}" : var.image_suffix
  lifecycle_policy = var.lifecycle_policy != null && var.lifecycle_policy != "" ? var.lifecycle_policy : templatefile("${path.module}/tpl/ecr-lifecycle-policy.json.tpl", {
    image_tag = var.image_default_tag
  })  
}

# Calculate hash of the container image source contents
data "external" "hash" {
  program = [coalesce(var.hash_script, "${path.module}/scripts/hash.bash"), var.source_path]
}

resource "aws_ecr_repository" "this" {
  name                 = local.repo_name
  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name
  policy = local.lifecycle_policy
}


# Build and push the container image whenever the hash changes
resource "null_resource" "push" {
  triggers = {
    hash = local.hash
  }

  provisioner "local-exec" {
    command     = "${coalesce(var.push_script, "${path.module}/scripts/push.bash")} ${var.source_path} ${aws_ecr_repository.this.repository_url} ${var.image_default_tag} ${local.hash}"
    interpreter = ["bash", "-c"]
  }
}
