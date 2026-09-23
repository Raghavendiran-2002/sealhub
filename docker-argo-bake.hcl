variable "GITHUB_RUN_NUMBER" {
  default = "0"
}

variable "IMAGE_VERSION" {
  default = "0.1"
}

variable "IMAGE_PREFIX" {
  default = "ghcr.io/raghavendiran/sealhub"
}

variable "GITHUB_REF_NAME" {
  default = ""
}

variable "GITHUB_BASE_REF" {
  default = ""
}

target "hubd" {
  dockerfile = "Dockerfile.hubd"
  platforms  = ["linux/amd64", "linux/arm64", "linux/arm/v7"]
  tags = [
    "${IMAGE_PREFIX}/hubd:${IMAGE_VERSION}.${GITHUB_RUN_NUMBER}",
  ]
}

target "operator" {
  dockerfile = "Dockerfile.operator"
  platforms  = ["linux/amd64", "linux/arm64", "linux/arm/v7"]
  tags = [
    "${IMAGE_PREFIX}/operator:${IMAGE_VERSION}.${GITHUB_RUN_NUMBER}",
  ]
}

group "default" {
  targets = ["hubd", "operator"]
}
