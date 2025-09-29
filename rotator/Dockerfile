# syntax=docker/dockerfile:1

FROM golang:1.22 AS build
WORKDIR /src
COPY . ./rotator
WORKDIR /src/rotator
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /out/rotator ./cmd/rotator

FROM gcr.io/distroless/static:nonroot
USER 65534:65534
WORKDIR /
COPY --from=build /out/rotator /usr/local/bin/rotator
ENTRYPOINT ["/usr/local/bin/rotator"]
CMD ["--config=/etc/rotator/config.yaml", "--listen=:9102"]

