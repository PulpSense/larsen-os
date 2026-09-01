# macOS WidgetKit, App Group authorization, and Digital Wall

Research date: 2026-08-30  
Scope: native sandboxed macOS SwiftUI app with a WidgetKit extension, an App Group shared store, `widgetURL(_:)`, and `Button(intent:)`.

## Executive conclusion

The permission dialog and the consistency-widget failure have the same root cause: Digital Wall is accessing an App Group that appears in the app and extension code-signing entitlements, but the exact App Group is **not authorized by either embedded provisioning profile**.

This is not primarily a `widgetURL` problem, a WidgetKit refresh-budget limitation, or an undiscovered App Intent. The system log proves that WidgetKit discovers and invokes `ToggleTodayV3Intent.perform()`, then the widget extension receives `EPERM`/Cocoa error 513 while saving `wall-state-v2.json` in the App Group. Because `perform()` throws before returning, the state is not updated and the normal post-interaction reload cannot display a change.

Apple changed App Group container enforcement in macOS 15. App Group containers under `~/Library/Group Containers` are now protected by System Integrity Protection. An unauthorized main app can receive the exact “would like to access data from other apps” prompt seen here; consent lasts only for that running app instance. An app extension is not prompted and is simply denied. This precisely explains why Digital Wall prompts while the widget silently fails. [macOS Sequoia 15 release notes — System Integrity Protection](https://developer.apple.com/documentation/macos-release-notes/macos-15-release-notes)

The fix is to repair App Group authorization/signing first. Reinstalling the same improperly provisioned build or assigning more widget-kind version numbers cannot fix it.

## 1. What triggers the “access data from other apps” prompt

### macOS 15 App Group protection

Apple documents three relevant requirements for App Group container access:

1. Resolve the container with `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`.
2. Claim the same `com.apple.security.application-groups` identifier in each process that uses the container.
3. Satisfy at least one authorization route: Mac App Store distribution, a Team-ID-prefixed App Group identifier, or an embedded provisioning profile that authorizes the App Group identifier.

If those conditions are not met, macOS may prompt the main app. For an extension, it denies access without offering a prompt. [macOS Sequoia 15 release notes](https://developer.apple.com/documentation/macos-release-notes/macos-15-release-notes), [Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox), [Accessing App Group containers in an existing macOS app](https://developer.apple.com/documentation/xcode/accessing-app-group-containers)

The prompt is therefore an App Group authorization prompt, not evidence that Digital Wall is still trying to read the original imported photos. The prompt’s folder icon and wording refer to protected application/container data.

### Why the custom URL is not the cause

Apple explicitly supports opening an app from a widget with `widgetURL(_:)`. WidgetKit activates the containing app and passes the URL to `onOpenURL(perform:)` for a SwiftUI app. The URL is a routing mechanism; it does not itself grant or request file access. [Linking to specific app scenes from a widget or Live Activity](https://developer.apple.com/documentation/widgetkit/linking-to-specific-app-scenes-from-your-widget-or-live-activity)

In Digital Wall, clicking the Vision Board launches the app, app initialization loads the shared App Group store, and that read triggers the authorization check. This timing makes the dialog look like it belongs to the widget link.

### Imported image architecture

The current image approach is conceptually correct:

- Use `NSOpenPanel` or SwiftUI `fileImporter` to let the person select multiple images.
- While that user-selected access is active, copy each image into the authorized App Group container.
- Persist only the copied filename/identifier.
- Have the app and widget read only those App Group copies afterward.

Apple says the Open panel extends the sandbox to the selected URLs, and the app should stop security-scoped access when finished. A persistent security-scoped bookmark is only necessary when the app intends to keep reading the original external file after relaunch. Digital Wall does not need bookmarks when it imports a copy. [Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox), [NSOpenPanel](https://developer.apple.com/documentation/appkit/nsopenpanel)

The widget extension does not need the `com.apple.security.files.user-selected.read-only` entitlement if it only reads App Group copies. Keeping that entitlement in the widget is unnecessary privilege, though it is not the source of this particular prompt.

## 2. Project-specific evidence

### Entitlements in source and code signatures

Both targets declare the same group:

```text
group.com.santileoni.DigitalWall
```

Both built code signatures also claim it. The app and extension are signed by Team ID `2S64P663Y2`.

However, decoding the embedded provisioning profiles shows that their authorized entitlements contain only:

```text
com.apple.application-identifier
com.apple.developer.team-identifier
keychain-access-groups
```

Neither profile contains `com.apple.security.application-groups`. Thus the restricted entitlement claimed by the executables is not authorized by their profiles. This is the exact configuration Apple warns about: older or automatically generated macOS profiles may not include App Group authorization. Apple says all restricted entitlements must be present and matching in the process’s provisioning profile. [Accessing App Group containers in an existing macOS app](https://developer.apple.com/documentation/xcode/accessing-app-group-containers)

The project uses Xcode 26.6 and automatic signing, but `REGISTER_APP_GROUPS` is absent from the effective build settings. Apple’s current instructions say that automatic signing obtains updated profiles for `group.*` identifiers when the App Group capability is configured and `REGISTER_APP_GROUPS = YES`. [Accessing App Group containers in an existing macOS app](https://developer.apple.com/documentation/xcode/accessing-app-group-containers)

### System log: the intent runs and the write is denied

The local unified log records this sequence for the user’s button click:

```text
Starting to run action: ToggleTodayV3Intent
Found ToggleTodayV3Intent ... registered with AppManager
Invoking ToggleTodayV3Intent.perform()
You don’t have permission to save the file “wall-state-v2.json”
NSPOSIXErrorDomain Code=1 “Operation not permitted”
Failed to execute LNAction
```

The denied location is:

```text
~/Library/Group Containers/group.com.santileoni.DigitalWall/wall-state-v2.json
```

This proves all of the following:

- the button receives the click;
- App Intents metadata is registered;
- the correct intent is discovered;
- `perform()` executes in the widget extension;
- the failure occurs specifically at App Group persistence.

The existing persistence loader uses `try?` and returns `.empty` on any read failure. Consequently, a denied read can still produce a “successful” widget timeline containing default/stale-looking data, which hides the real authorization error.

## 3. How interactive widgets are supposed to update

### Process and target membership

WidgetKit extensions run independently from the containing app. The displayed widget is an archived representation of timeline entries; arbitrary SwiftUI closures and bindings do not run in the rendered widget. Interactive controls therefore use `Button(intent:)` or `Toggle(intent:)` with an `AppIntent`. [Adding interactivity to widgets and Live Activities](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities), [WWDC23: Bring widgets to life](https://developer.apple.com/videos/play/wwdc2023/10028/)

Apple instructs developers to compile a widget `AppIntent` into both the containing app target and the widget-extension target. By default, an ordinary `AppIntent` invoked from a widget executes in the widget extension process. Intents that opt into opening/foregrounding the app or adopt certain specialized protocols can execute in the app process instead. [Adding interactivity to widgets and Live Activities](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)

Digital Wall already compiles `WallPersistence.swift`, including `ToggleTodayV3Intent`, into both targets. The system log confirms discovery, so target membership is not the current failure.

### Persistence must complete before `perform()` returns

Apple requires all state needed by the next timeline to be saved before `perform()` returns. When a widget button or toggle’s intent completes, WidgetKit guarantees a timeline reload. [Adding interactivity to widgets and Live Activities](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities), [WWDC23: Bring widgets to life](https://developer.apple.com/videos/play/wwdc2023/10028/)

Digital Wall attempts this in the correct order—save, request reload, return—but the save throws. The manual `reloadTimelines` call and `.result()` return are never reached. Repairing App Group access should allow the same interaction flow to work; the explicit reload inside `perform()` is optional because WidgetKit already guarantees a reload after a successful interaction.

For on/off state, Apple recommends `Toggle(intent:)` because it gives immediate optimistic visual feedback. A `Button(intent:)` is still valid, but only flashes its pressed state and then waits for the new timeline. [Adding interactivity to widgets and Live Activities](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)

### Updates originating in the app

When the app changes shared data, it should finish saving and call:

```swift
WidgetCenter.shared.reloadTimelines(ofKind: exactWidgetKind)
```

This asks WidgetKit to request a new timeline; it does not directly mutate the rendered view. The `kind` must exactly match the installed widget configuration. [Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date), [WidgetCenter](https://developer.apple.com/documentation/widgetkit/widgetcenter)

Digital Wall already calls the current consistency kind after app-originated changes. The extension then needs to read the newly saved App Group state. Because its profile does not authorize the App Group, it cannot reliably do so and falls back to `.empty`. That is why app-originated changes also appear not to refresh.

### Reload budgets are not the root cause

WidgetKit budgets ordinary scheduled refreshes, typically allocating roughly 40–70 refreshes per day to a frequently viewed widget. Apple excludes reloads while the containing app is foregrounded and reloads caused by a widget App Intent from that budget. A button/toggle interaction specifically guarantees a reload. [Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date), [Adding interactivity to widgets and Live Activities](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)

Therefore, neither reported consistency failure is explained by normal refresh throttling.

## 4. Correct architecture and repair paths

### Preferred: properly provision the existing `group.*` identifier

This avoids moving the existing state and four imported images.

1. Register `group.com.santileoni.DigitalWall` for the developer team if it is not already registered.
2. Enable the identical App Groups capability for both the app and widget extension targets.
3. Keep automatic signing enabled.
4. Set `REGISTER_APP_GROUPS = YES` for every relevant build configuration of both targets.
5. Regenerate/download profiles and clean-rebuild.
6. Verify both embedded profiles authorize the exact group, not merely that `codesign` reports the entitlement on the executable.
7. Verify the running process reports `entitlements validated` with `sudo launchctl procinfo <pid>` as Apple recommends.

Apple’s current provisioning procedure and runtime validation check are documented in [Accessing App Group containers in an existing macOS app](https://developer.apple.com/documentation/xcode/accessing-app-group-containers). General signing diagnostics are in [Diagnosing issues with entitlements](https://developer.apple.com/documentation/bundleresources/diagnosing-issues-with-entitlements).

### Alternative for a macOS-only app: Team-ID-prefixed group

Apple also supports a macOS App Group named with the developer Team ID, for example:

```text
2S64P663Y2.com.santileoni.DigitalWall
```

This form does not require provisioning-profile authorization because macOS validates the prefix against the signing team. It is not supported on iOS, iPadOS, tvOS, visionOS, or watchOS, and it does not serve as a keychain access group. [Accessing App Group containers in an existing macOS app](https://developer.apple.com/documentation/xcode/accessing-app-group-containers), [Configuring App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups)

Because this identifier maps to a different group container, choosing it requires a deliberate one-time migration of `wall-state-v2.json` and `VisionImages`, or backing up and restoring those files during development. For this project, properly provisioning the existing `group.*` identifier is less disruptive.

## 5. Verification checklist after the signing repair

Do not change widget kinds again before running these checks.

1. Decode the app and widget extension’s embedded provisioning profiles and confirm each profile contains:

   ```text
   com.apple.security.application-groups = [group.com.santileoni.DigitalWall]
   ```

2. Confirm both executable entitlements contain the identical group.
3. Launch the app and verify that opening the Vision Board produces no App Data prompt.
4. Click the consistency control and inspect the unified log:
   - `perform()` should run;
   - no Cocoa 513/`EPERM` should occur;
   - the save should finish before `.result()`;
   - WidgetKit should request the current consistency timeline.
5. Toggle today in the app and confirm a new timeline is requested for the exact installed consistency kind.
6. Only after those pass, diagnose any remaining Vision Board show/dismiss animation issue separately. The current permission interruption makes that UI behavior impossible to evaluate reliably.

## Sources

- [Apple: macOS Sequoia 15 release notes](https://developer.apple.com/documentation/macos-release-notes/macos-15-release-notes)
- [Apple: Accessing App Group containers in an existing macOS app](https://developer.apple.com/documentation/xcode/accessing-app-group-containers)
- [Apple: Protecting local app data using containers on macOS](https://developer.apple.com/documentation/xcode/protecting-local-app-data-using-containers)
- [Apple: Configuring App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups)
- [Apple: App Groups entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.application-groups)
- [Apple: Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)
- [Apple: Linking to specific app scenes from a widget or Live Activity](https://developer.apple.com/documentation/widgetkit/linking-to-specific-app-scenes-from-your-widget-or-live-activity)
- [Apple: Adding interactivity to widgets and Live Activities](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)
- [Apple: Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)
- [Apple: WidgetCenter](https://developer.apple.com/documentation/widgetkit/widgetcenter)
- [Apple WWDC23: Bring widgets to life](https://developer.apple.com/videos/play/wwdc2023/10028/)
- [Apple Developer Forums, DTS engineer: App Group not working after macOS 15](https://developer.apple.com/forums/thread/758375)
