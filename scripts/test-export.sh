#!/bin/bash
# Compiles the Markdown/export code with Tests/ExportTests and runs it.
set -euo pipefail
cd "$(dirname "$0")/.."
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
swiftc -o "$out/export-tests" Tests/ExportTests/main.swift NewMediaWriter/Markdown/*.swift
"$out/export-tests"
