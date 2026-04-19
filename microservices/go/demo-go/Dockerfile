FROM golang:1.26-alpine AS builder

ARG TARGETOS

ARG TARGETARCH

WORKDIR /build

COPY go.mod go.sum ./
# Cache this layer to speed up workflow
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    go mod download

COPY *.go ./

RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -ldflags="-s -w" -o webservice .

FROM alpine:3.23.4 AS development

WORKDIR /app

RUN apk --no-cache add curl && \
    addgroup -g 1001 webservice && \
    adduser -D -u 1001 -G webservice webservice && \
    chown -R webservice:webservice /app

COPY --from=builder /build/webservice .

EXPOSE 8080

USER webservice

ENTRYPOINT ["./webservice"]
CMD []

FROM alpine:3.23.4 AS release

WORKDIR /app

RUN addgroup -g 1001 webservice && \
    adduser -D -u 1001 -G webservice webservice && \
    chown -R webservice:webservice /app

COPY --from=builder /build/webservice .

EXPOSE 8080

USER webservice

ENTRYPOINT ["./webservice"]
CMD []