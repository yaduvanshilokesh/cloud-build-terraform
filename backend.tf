terraform {
  backend "gcs" {
    bucket = "storeterraformstate"
  }
}
