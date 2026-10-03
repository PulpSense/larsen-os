#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p build/tests
sources=(DigitalWall/**/*.swift)
sources=(${sources:#DigitalWall/App/DigitalWallApp.swift})
swiftc -parse-as-library -o build/tests/hour-check-ins "${sources[@]}" Tests/HourCheckInTests.swift
build/tests/hour-check-ins
swiftc -parse-as-library -o build/tests/wall-content DigitalWall/Shared/WallState.swift DigitalWall/Shared/HourCheckIn.swift Tests/WallContentTests.swift
build/tests/wall-content
