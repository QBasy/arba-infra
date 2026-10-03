# Эталонный Dockerfile сервиса Arba. Правила: docs/rules/build.md
ARG GO_VERSION=1.27

FROM golang:${GO_VERSION}-alpine AS build
ARG VERSION=dev
ARG COMMIT=none
ARG MODULE
ARG GIT_TOKEN
ENV CGO_ENABLED=0 GOFLAGS=-mod=readonly GOINSECURE=*.arba.kz GOPRIVATE=*.arba.kz
RUN apk add --no-cache git
WORKDIR /src

# зависимости отдельным слоем; токен живёт только внутри этой команды
COPY go.mod go.sum* ./
RUN if [ -n "$GIT_TOKEN" ]; then \
      git config --global url."http://gitlab-ci-token:${GIT_TOKEN}@gitlab.arba.kz/".insteadOf "http://gitlab.arba.kz/"; \
    fi \
 && go mod download \
 ; rm -f /root/.gitconfig

COPY . .
RUN for b in server worker migrate; do \
      if [ -d "cmd/$b" ]; then \
        go build -trimpath \
          -ldflags "-s -w -X ${MODULE}/internal/buildinfo.Version=${VERSION} -X ${MODULE}/internal/buildinfo.Commit=${COMMIT}" \
          -o "/out/$b" "./cmd/$b" || exit 1; \
      fi; \
    done

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/ /app/
COPY --from=build /src/migrations /migrations
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["/app/server"]
