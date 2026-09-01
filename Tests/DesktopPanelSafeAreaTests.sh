#!/bin/sh

set -eu

support_file="DigitalWall/App/DesktopPanelSupport.swift"
expected='rootView: content().ignoresSafeArea(edges: .top)'

if ! grep -Fq "$expected" "$support_file"; then
    echo "FAIL: the shared desktop widget root still honors the hidden title-bar safe area"
    exit 1
fi

echo "PASS: the shared desktop widget root neutralizes the hidden title-bar safe area"
