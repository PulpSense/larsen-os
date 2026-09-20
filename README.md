# Digital Wall

A privacy-first, native macOS vision board and deep-work tracker built with SwiftUI and WidgetKit. It turns the desktop into a lightweight place for goals, focus hours, phrases, year progress, and world clocks without requiring an account or cloud service.

## Run locally

1. Open `DigitalWall.xcodeproj` in Xcode 16 or newer.
2. Select the **DigitalWall** target, open **Signing & Capabilities**, and choose your development team.
3. Select the **DigitalWallWidget** target and choose the same team.
4. Confirm both targets use the `group.com.santileoni.DigitalWall` App Group. If that identifier is unavailable for your team, change it in both entitlement files and in `AppConfiguration.swift`.
5. Run the **DigitalWall** scheme on **My Mac**.
6. Add **Vision Board**, **Deep Work Hours**, or **Phrases** from macOS’s widget gallery.

## Installed app

The signed Release archive is created at `build/DigitalWall.xcarchive`. Install its `Digital Wall.app` product in `/Applications` so macOS can register the bundled widgets and native login item from a stable location.

On its first installed launch, Digital Wall enables **Open Digital Wall at login**. Login launches are quiet: the saved desktop panels return without opening the editor or adding an icon to the Dock. This can be changed later in **Digital Wall → Settings** or in macOS **System Settings → General → Login Items & Extensions**.

## How to use it

### Track deep work

1. Open **Deep Work Hours** in the app or place its panel/widget on the desktop.
2. At the end of each completed hour, click **+**. Deep work is intentionally recorded in whole hours.
3. The calendar distinguishes zero-hour days from partial days. Hours one through three become progressively stronger indigo cells.
4. The fourth hour wins the day, advances the day streak, changes the calendar into its earned-color range, and launches the full-screen **DAY WON** celebration.
5. Keep logging after four hours to get distinct 5H, 6H, 7H, 8H, and evolving 9H+ celebrations. The calendar color continues progressing so an exceptional day remains visually different from a minimum win.

Use **Edit deep work** to correct or backfill a selected date. Incrementing today from that control still celebrates a newly reached milestone; historical corrections remain quiet. Reduce Motion keeps the milestone message visible while removing the large movement effects.

### Use the vision board

- Add images on the **Vision Boards** screen and optionally give each image a short caption.
- Click **Show board**, press **Shift-Command-V**, or click the desktop widget to open the board full screen on the display under the pointer.
- Press any key or click anywhere to dismiss it.
- To choose images for a particular Vision Board widget, Control-click the widget, choose **Edit Widget**, then select **Images**. An empty selection shows every image; captions become the names shown in the picker.

### Arrange the desktop

- Show Deep Work Hours, Vision Boards, Phrases, Year Elapsed, or World Clocks as floating desktop panels from the app.
- Drag panels into position. They keep a small gap from one another and remember their placement.
- Hover over a panel and open its **•••** menu to edit it, close it, or return to the main Digital Wall app.
- Add the native Vision Board, Deep Work Hours, or Phrases widgets from macOS’s widget gallery when a WidgetKit version is more convenient.

## Data and privacy

Digital Wall stores its JSON state and copied vision-board images locally in the `group.com.santileoni.DigitalWall` App Group container. The app has no network client, account system, analytics, or cloud dependency. Removing the app does not automatically remove that App Group data.
