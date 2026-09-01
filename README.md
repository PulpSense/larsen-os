# Digital Wall

A private, native macOS vision board and work-consistency tracker built with SwiftUI and WidgetKit.

## Run locally

1. Open `DigitalWall.xcodeproj` in Xcode 16 or newer.
2. Select the **DigitalWall** target, open **Signing & Capabilities**, and choose your development team.
3. Select the **DigitalWallWidget** target and choose the same team.
4. Confirm both targets use the `group.com.santileoni.DigitalWall` App Group. If that identifier is unavailable for your team, change it in both entitlement files and in `AppConfiguration.swift`.
5. Run the **DigitalWall** scheme on **My Mac**.
6. Add **Vision Board**, **Year Consistency**, or **Phrases** from macOS’s widget gallery.

The app copies selected images and stores all state as JSON inside the shared local App Group container. It has no network client, accounts, analytics, or cloud dependency.

## Installed app

The signed Release archive is created at `build/DigitalWall.xcarchive`. Install its `Digital Wall.app` product in `/Applications` so macOS can register the bundled widgets and native login item from a stable location.

On its first installed launch, Digital Wall enables **Open Digital Wall at login**. Login launches are quiet: the saved desktop panels return without opening the editor or adding an icon to the Dock. This can be changed later in **Digital Wall → Settings** or in macOS **System Settings → General → Login Items & Extensions**.

## Using the wall

- Add images on the **Vision board** screen and optionally add a short caption to each one.
- Click **Show board**, press **Shift-Command-V**, or click the desktop widget to show the borderless overlay on the screen under the pointer.
- Press any key or click anywhere to dismiss it.
- Mark days from the **Consistency** screen and edit Markdown reminders from **Phrases**.
- To choose the images for one Vision Board widget, Control-click it on the desktop, choose **Edit Widget**, then select **Images**. Leaving the selection empty shows every image. The image captions are used as names in the picker.
