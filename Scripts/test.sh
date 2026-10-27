#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
xcrun swiftc -swift-version 6 -warnings-as-errors -O Sources/Domain.swift Sources/Camera.swift Sources/Store.swift Tests/DomainTests.swift -o .build/PoseboardTests
.build/PoseboardTests
