# syntax = docker/dockerfile-upstream:1.2.0-labs

# THIS FILE WAS AUTOMATICALLY GENERATED, PLEASE DO NOT EDIT.
#
# Generated on 2021-05-07T20:00:58Z by kres a7a00ec-dirty.

ARG JS_TOOLCHAIN
ARG TOOLCHAIN

FROM ghcr.io/talos-systems/ca-certificates:v0.3.0-12-g90722c3 AS image-ca-certificates

FROM ghcr.io/talos-systems/fhs:v0.3.0-12-g90722c3 AS image-fhs

# base toolchain image
FROM ${JS_TOOLCHAIN} AS js-toolchain
RUN apk --update --no-cache add bash curl protoc protobuf-dev go
COPY ./go.mod .
COPY ./go.sum .
ENV GOPATH /go

# runs markdownlint
FROM node:14.8.0-alpine AS lint-markdown
RUN npm i -g markdownlint-cli@0.23.2
RUN npm i sentences-per-line@0.2.1
WORKDIR /src
COPY .markdownlint.json .
COPY ./README.md ./README.md
RUN markdownlint --ignore "**/node_modules/**" --ignore '**/hack/chglog/**' --rules /node_modules/sentences-per-line/index.js .

# collects proto specs
FROM scratch AS proto-specs
ADD api/socket/message.proto /api/socket/message/
ADD api/common/theila.proto /api/common/
ADD api/rpc/resource.proto /api/rpc/
ADD https://raw.githubusercontent.com/googleapis/googleapis/master/google/rpc/status.proto /api/google/rpc/
ADD https://raw.githubusercontent.com/talos-systems/talos/master/api/common/common.proto /api/common/
ADD https://raw.githubusercontent.com/talos-systems/talos/master/api/resource/resource.proto /api/talos/resource/

# collects proto specs
FROM scratch AS proto-specs-frontend
ADD api/common/theila.proto /frontend/src/common/
ADD api/socket/message.proto /frontend/src/api/
ADD api/rpc/resource.proto /frontend/src/api/
ADD https://raw.githubusercontent.com/googleapis/googleapis/master/google/rpc/status.proto /frontend/src/google/rpc/
ADD https://raw.githubusercontent.com/talos-systems/talos/master/api/resource/resource.proto /frontend/src/talos/resource/
ADD https://raw.githubusercontent.com/talos-systems/talos/master/api/common/common.proto /frontend/src/common/

# base toolchain image
FROM ${TOOLCHAIN} AS toolchain
RUN apk --update --no-cache add bash curl build-base protoc protobuf-dev

# tools and sources
FROM js-toolchain AS js
WORKDIR /src
ARG PROTOBUF_TS_VERSION
RUN npm install -g ts-proto@^${PROTOBUF_TS_VERSION}
ARG PROTOBUF_GRPC_GATEWAY_TS_VERSION
RUN go get github.com/grpc-ecosystem/protoc-gen-grpc-gateway-ts@v${PROTOBUF_GRPC_GATEWAY_TS_VERSION}
RUN mv /go/bin/protoc-gen-grpc-gateway-ts /bin
COPY frontend/package.json ./
COPY frontend/package-lock.json ./
RUN --mount=type=cache,target=/src/node_modules npm version ${VERSION}
RUN --mount=type=cache,target=/src/node_modules npm install
COPY .eslintrc.yaml ./
COPY .babelrc ./babel.config.js
COPY .jestrc ./jest.config.js
COPY .tsconfig ./tsconfig.json
COPY ./frontend/src ./src
COPY ./frontend/tests ./tests
COPY ./frontend/public ./public
COPY ./frontend/postcss.config.js ./postcss.config.js
COPY ./frontend/tailwind.config.js ./tailwind.config.js

# build tools
FROM toolchain AS tools
ENV GO111MODULE on
ENV CGO_ENABLED 0
ENV GOPATH /go
RUN curl -sfL https://install.goreleaser.com/github.com/golangci/golangci-lint.sh | bash -s -- -b /bin v1.38.0
ARG GOFUMPT_VERSION
RUN cd $(mktemp -d) \
	&& go mod init tmp \
	&& go get mvdan.cc/gofumpt/gofumports@${GOFUMPT_VERSION} \
	&& mv /go/bin/gofumports /bin/gofumports
ARG PROTOBUF_GO_VERSION
RUN go install google.golang.org/protobuf/cmd/protoc-gen-go@v${PROTOBUF_GO_VERSION}
RUN mv /go/bin/protoc-gen-go /bin
ARG GRPC_GO_VERSION
RUN go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@v${GRPC_GO_VERSION}
RUN mv /go/bin/protoc-gen-go-grpc /bin
ARG GRPC_GATEWAY_VERSION
RUN go install github.com/grpc-ecosystem/grpc-gateway/v2/protoc-gen-grpc-gateway@v${GRPC_GATEWAY_VERSION}
RUN mv /go/bin/protoc-gen-grpc-gateway /bin

# builds frontend
FROM js AS frontend
RUN --mount=type=cache,target=/src/node_modules npm run build
RUN mkdir -p /internal/frontend/dist
RUN cp -rf ./dist/* /internal/frontend/dist

# runs eslint
FROM js AS lint-eslint
RUN --mount=type=cache,target=/src/node_modules npm run lint

# runs protobuf compiler
FROM js AS proto-compile-frontend
COPY --from=proto-specs-frontend / /
RUN protoc -I/frontend/src --grpc-gateway-ts_out=source_relative:/frontend/src --plugin=/root/.npm-global/.bin/protoc-gen-ts_proto.cmd --ts_proto_out=paths=source_relative:/frontend/src --ts_proto_opt=returnObservable=false --ts_proto_opt=outputClientImpl=false /frontend/src/common/theila.proto
RUN protoc -I/frontend/src --plugin=/root/.npm-global/.bin/protoc-gen-ts_proto.cmd --ts_proto_out=paths=source_relative:/frontend/src --ts_proto_opt=returnObservable=false --ts_proto_opt=outputClientImpl=false /frontend/src/api/message.proto
RUN protoc -I/frontend/src --grpc-gateway-ts_out=source_relative:/frontend/src --plugin=/root/.npm-global/.bin/protoc-gen-ts_proto.cmd --ts_proto_out=paths=source_relative:/frontend/src --ts_proto_opt=returnObservable=false --ts_proto_opt=outputClientImpl=false /frontend/src/api/resource.proto
RUN protoc -I/frontend/src --grpc-gateway-ts_out=source_relative:/frontend/src --plugin=/root/.npm-global/.bin/protoc-gen-ts_proto.cmd --ts_proto_out=paths=source_relative:/frontend/src --ts_proto_opt=returnObservable=false --ts_proto_opt=outputClientImpl=false /frontend/src/google/rpc/status.proto
RUN protoc -I/frontend/src --grpc-gateway-ts_out=source_relative:/frontend/src --plugin=/root/.npm-global/.bin/protoc-gen-ts_proto.cmd --ts_proto_out=paths=source_relative:/frontend/src --ts_proto_opt=returnObservable=false --ts_proto_opt=outputClientImpl=false /frontend/src/talos/resource/resource.proto
RUN protoc -I/frontend/src --grpc-gateway-ts_out=source_relative:/frontend/src --plugin=/root/.npm-global/.bin/protoc-gen-ts_proto.cmd --ts_proto_out=paths=source_relative:/frontend/src --ts_proto_opt=returnObservable=false --ts_proto_opt=outputClientImpl=false /frontend/src/common/common.proto
RUN rm /frontend/src/common/theila.proto
RUN rm /frontend/src/api/message.proto
RUN rm /frontend/src/api/resource.proto

# runs js unit-tests
FROM js AS unit-tests-frontend
RUN --mount=type=cache,target=/src/node_modules CI=true npm run test

# runs protobuf compiler
FROM tools AS proto-compile
COPY --from=proto-specs / /
RUN protoc -I/api --go_out=paths=source_relative:/api --go-grpc_out=paths=source_relative:/api /api/socket/message/message.proto
RUN protoc -I/api --go_out=paths=source_relative:/api --go-grpc_out=paths=source_relative:/api /api/common/theila.proto
RUN protoc -I/api --grpc-gateway_out=paths=source_relative:/api --grpc-gateway_opt=generate_unbound_methods=true --go_out=paths=source_relative:/api --go-grpc_out=paths=source_relative:/api /api/rpc/resource.proto
RUN protoc -I/api --grpc-gateway_out=paths=source_relative:/api --grpc-gateway_opt=generate_unbound_methods=true --grpc-gateway_opt=standalone=true /api/google/rpc/status.proto
RUN protoc -I/api --grpc-gateway_out=paths=source_relative:/api --grpc-gateway_opt=generate_unbound_methods=true --grpc-gateway_opt=standalone=true /api/common/common.proto
RUN protoc -I/api --grpc-gateway_out=paths=source_relative:/api --grpc-gateway_opt=generate_unbound_methods=true --grpc-gateway_opt=standalone=true /api/talos/resource/resource.proto
RUN rm /api/socket/message/message.proto
RUN rm /api/common/theila.proto
RUN rm /api/rpc/resource.proto

# tools and sources
FROM tools AS base
WORKDIR /src
COPY ./go.mod .
COPY ./go.sum .
RUN --mount=type=cache,target=/go/pkg go mod download
RUN --mount=type=cache,target=/go/pkg go mod verify
COPY ./internal ./internal
COPY ./cmd ./cmd
COPY ./api ./api
COPY --from=frontend /internal/frontend/dist ./internal/frontend/dist
RUN --mount=type=cache,target=/go/pkg go list -mod=readonly all >/dev/null

# cleaned up specs and compiled versions
FROM scratch AS generate-frontend
COPY --from=proto-compile-frontend frontend/ frontend/

# cleaned up specs and compiled versions
FROM scratch AS generate
COPY --from=proto-compile /api/ /api/

# runs gofumpt
FROM base AS lint-gofumpt
RUN find . -name '*.pb.go' | xargs -r rm
RUN find . -name '*.pb.gw.go' | xargs -r rm
RUN FILES="$(gofumports -l -local github.com/talos-systems/theila .)" && test -z "${FILES}" || (echo -e "Source code is not formatted with 'gofumports -w -local github.com/talos-systems/theila .':\n${FILES}"; exit 1)

# runs golangci-lint
FROM base AS lint-golangci-lint
COPY .golangci.yml .
ENV GOGC 50
RUN --mount=type=cache,target=/root/.cache/go-build --mount=type=cache,target=/root/.cache/golangci-lint --mount=type=cache,target=/go/pkg golangci-lint run --config .golangci.yml

# runs unit-tests with race detector
FROM base AS unit-tests-race
ARG TESTPKGS
RUN --mount=type=cache,target=/root/.cache/go-build --mount=type=cache,target=/go/pkg --mount=type=cache,target=/tmp CGO_ENABLED=1 go test -v -race -count 1 ${TESTPKGS}

# runs unit-tests
FROM base AS unit-tests-run
ARG TESTPKGS
RUN --mount=type=cache,target=/root/.cache/go-build --mount=type=cache,target=/go/pkg --mount=type=cache,target=/tmp go test -v -covermode=atomic -coverprofile=coverage.txt -coverpkg=${TESTPKGS} -count 1 ${TESTPKGS}

# builds theila
FROM base AS theila-build
COPY --from=generate / /
WORKDIR /src/cmd/theila
RUN --mount=type=cache,target=/root/.cache/go-build --mount=type=cache,target=/go/pkg go build -ldflags "-s -w" -o /theila

FROM scratch AS unit-tests
COPY --from=unit-tests-run /src/coverage.txt /coverage.txt

FROM scratch AS theila
COPY --from=theila-build /theila /theila

FROM scratch AS image-theila
COPY --from=theila / /
COPY --from=image-fhs / /
COPY --from=image-ca-certificates / /
LABEL org.opencontainers.image.source https://github.com/talos-systems/theila
ENTRYPOINT ["/theila"]

