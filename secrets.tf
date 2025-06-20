# Working with NGINX+ images usually requires a JWT from F5. If provided
# Create a secret for the NGINX+ JWT
module "nginx_jwt" {
  for_each   = coalesce(var.nginx_jwt, "unspecified") == "unspecified" ? {} : { secret = var.nginx_jwt }
  source     = "memes/secret-manager/google"
  version    = "2.2.2"
  project_id = var.project_id
  id         = format("%s-nginx-jwt", var.name)
  secret     = each.value
  accessors = [
    format("serviceAccount:%s", module.bootstrap.ar_sa),
  ]
}
