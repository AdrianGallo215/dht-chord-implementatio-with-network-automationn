#!/bin/bash

# Regenerates chordpb/chord.pb.go + chordpb/chord_grpc.pb.go from chordpb/chord.proto.
#
# One-time setup:
#   sudo dnf install -y protobuf-compiler   # or: apt install protobuf-compiler
#   go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
#   go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest
#   export PATH="$PATH:$(go env GOPATH)/bin"

set -xe

cd "$(dirname "$0")"

protoc --proto_path=chordpb \
    --go_out=paths=source_relative:chordpb \
    --go-grpc_out=paths=source_relative:chordpb \
    chordpb/chord.proto