# Digital Wall development notes

- Build and run the macOS app with code signing enabled. Do not pass `CODE_SIGNING_ALLOWED=NO` to `xcodebuild`.
- Local persistence uses the App Group configured by `DIGITAL_WALL_APP_GROUP_ID` in the ignored `Config/Signing.local.xcconfig`. An ad-hoc or unsigned build launches but cannot save `wall-state-v2.json` inside that container.
- Before handing off a build, verify that the app has a Team identifier and the `com.apple.security.application-groups` entitlement.
