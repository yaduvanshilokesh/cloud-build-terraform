terraform {
  backend "gcs" {
    bucket = var.projectName
  }
}