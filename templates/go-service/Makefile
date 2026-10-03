# Единый набор целей для всех сервисов Arba (docs/rules/go.md). CI вызывает эти же цели.
SERVICE  ?= $(notdir $(CURDIR))
GO_VERSION ?= $(shell awk '/^go /{split($$2,a,"."); print a[1]"."a[2]}' go.mod)
VERSION  ?= dev
MODULE   := $(shell go list -m)

.PHONY: lint test test-integration build image helm-lint hooks

lint:
	golangci-lint run ./...
	go run github.com/fe3dback/go-arch-lint@latest check --project-path .

test:
	go test -race -covermode=atomic -coverprofile=cover.out ./...
	go tool cover -func=cover.out | tail -n 1

# БД берётся из TEST_DATABASE_URL (в CI — сервис postgres, локально — любой PostgreSQL)
test-integration:
	@test -n "$$TEST_DATABASE_URL" || (echo "set TEST_DATABASE_URL"; exit 1)
	go test -race -tags=integration ./...

build:
	mkdir -p bin
	for b in server worker migrate; do [ -d cmd/$$b ] && CGO_ENABLED=0 go build -trimpath -ldflags "-s -w -X $(MODULE)/internal/buildinfo.Version=$(VERSION)" -o bin/$$b ./cmd/$$b; done; true

# только для локальной проверки; в registry пушит CI
image:
	docker build --build-arg GO_VERSION=$(GO_VERSION) --build-arg VERSION=$(VERSION) --build-arg MODULE=$(MODULE) -t arba-local/$(SERVICE):dev .

helm-lint:
	helm lint .helm --set image.tag=0.0.0
	helm template $(SERVICE) .helm --set image.tag=0.0.0 --set worker.enabled=true --set migrate.enabled=true > /dev/null

hooks:
	@printf '#!/bin/sh\ngitleaks protect --staged --redact && gofmt -l . | (! grep .)\n' > .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
