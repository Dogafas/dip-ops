output "s3_bucket_name" {
  value       = yandex_storage_bucket.terraform_state.id
  description = "The name (ID) of the Terraform state S3 bucket"
}
