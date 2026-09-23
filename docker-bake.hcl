group "default" {
  targets = ["hubd", "operator"]
}

target "hubd" {
  dockerfile = "Dockerfile.hubd"
  platforms  = ["linux/amd64", "linux/arm64", "linux/arm/v7"]
  tags       = ["sealhub/hubd:local"]
}

target "operator" {
  dockerfile = "Dockerfile.operator"
  platforms  = ["linux/amd64", "linux/arm64", "linux/arm/v7"]
  tags       = ["sealhub/operator:local"]
}
