#!/bin/sh
set -eu

presenter="DigitalWall/Features/VisionBoard/VisionBoardPresenter.swift"
state="DigitalWall/Shared/WallState.swift"

rg -q 'VisionBoardPresentation\.imagesForExpandedView\(images\)' "$presenter"

if rg -q 'images\.prefix\(' "$state"; then
    echo "FAIL: expanded vision board truncates the board image list"
    exit 1
fi

echo "PASS: expanded vision board keeps every board image"
