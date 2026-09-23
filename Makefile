.PHONY: build test tidy docker-bake

BIN_DIR := bin

build:
	go build -o $(BIN_DIR)/hubd ./cmd/hubd
	go build -o $(BIN_DIR)/hub ./cmd/hub
	go build -o $(BIN_DIR)/sealhub-operator ./operator/cmd

test:
	go test ./...

tidy:
	go mod tidy

docker-bake:
	docker buildx bake -f docker-bake.hcl
