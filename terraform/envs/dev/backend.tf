terraform {
  backend "gcs" {
    prefix = "envs/dev/network"
  }
}
