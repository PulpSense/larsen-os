# Digital Wall development notes

- Build and run the macOS app with code signing enabled. Do not pass `CODE_SIGNING_ALLOWED=NO` to `xcodebuild`.
- Local persistence uses the `group.com.santileoni.DigitalWall` App Group. An ad-hoc or unsigned build launches but cannot save `wall-state-v2.json` inside that container.
- Before handing off a build, verify that the app has a Team identifier and the `com.apple.security.application-groups` entitlement.
