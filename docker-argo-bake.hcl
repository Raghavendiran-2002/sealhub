# CI bake file — no HCL `variable` blocks (not supported by all buildx parsers).
# Tags are overridden in .github/workflows/build.yaml via `set:`.

target "hubd" {
  dockerfile = "Dockerfile.hubd"
  platforms  = ["linux/amd64", "linux/arm64", "linux/arm/v7"]
  tags       = ["ghcr.io/raghavendiran-2002/sealhub/hubd:0.1.0"]
}

target "operator" {
  dockerfile = "Dockerfile.operator"
  platforms  = ["linux/amd64", "linux/arm64", "linux/arm/v7"]
  tags       = ["ghcr.io/raghavendiran-2002/sealhub/operator:0.1.0"]
}

group "default" {
  targets = ["hubd", "operator"]
}
