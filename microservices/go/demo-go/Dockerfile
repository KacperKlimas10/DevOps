FROM golang:1.22-alpine AS builder

ARG TARGETOS

ARG TARGETARCH

WORKDIR /build

COPY go.mod go.sum ./

RUN go mod download

COPY *.go ./

RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -ldflags="-s -w" -o webservice .

FROM alpine:3.19 AS development

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

FROM alpine:3.19 AS release

WORKDIR /app

RUN addgroup -g 1001 webservice && \
    adduser -D -u 1001 -G webservice webservice && \
    chown -R webservice:webservice /app

COPY --from=builder /build/webservice .

EXPOSE 8080

USER webservice

ENTRYPOINT ["./webservice"]
CMD []