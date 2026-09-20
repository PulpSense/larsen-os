# Digital Wall

A privacy-first, native macOS vision board and deep-work tracker built with SwiftUI. It turns the desktop into a lightweight place for goals, focus hours, phrases, year progress, and world clocks without requiring an account or cloud service.

## Run locally

1. Open `DigitalWall.xcodeproj` in Xcode 16 or newer.
2. Copy `Config/Signing.local.xcconfig.example` to `Config/Signing.local.xcconfig`.
3. In that local file, enter your Apple development-team ID and unique reverse-domain bundle and App Group identifiers. The file is ignored by Git.
4. Register the App Group identifier for your Apple development team and enable it for the app identifier.
5. Run the **DigitalWall** scheme on **My Mac**.

## Installed app

The signed Release archive is created at `build/DigitalWall.xcarchive`. Install its `Digital Wall.app` product in `/Applications` so macOS can register the native login item from a stable location.

On its first installed launch, Digital Wall enables **Open Digital Wall at login**. Login launches are quiet: the saved desktop panels return without opening the editor or adding an icon to the Dock. This can be changed later in **Digital Wall → Settings** or in macOS **System Settings → General → Login Items & Extensions**.

## How to use it

### Track deep work

1. Open **Deep Work Hours** in the app or place its floating panel on the desktop.
2. At the end of each completed hour, click **+**. Deep work is intentionally recorded in whole hours.
3. The calendar distinguishes zero-hour days from partial days. Hours one through three become progressively stronger indigo cells.
4. The fourth hour wins the day, advances the day streak, changes the calendar into its earned-color range, and launches the full-screen **DAY WON** celebration.
5. Keep logging after four hours to get distinct 5H, 6H, 7H, 8H, and evolving 9H+ celebrations. The calendar color continues progressing so an exceptional day remains visually different from a minimum win.

Use **Edit deep work** to correct or backfill a selected date. Incrementing today from that control still celebrates a newly reached milestone; historical corrections remain quiet. Reduce Motion keeps the milestone message visible while removing the large movement effects.

### Use the vision board

- Add images on the **Vision Boards** screen and optionally give each image a short caption.
- Click **Show board**, press **Shift-Command-V**, or click the floating vision-board panel to open the board full screen on the display under the pointer.
- Press any key or click anywhere to dismiss it.
- Create multiple boards in the app and choose which images remain visible on each floating vision-board panel.

### Arrange the desktop

- Show Deep Work Hours, Vision Boards, Phrases, Year Elapsed, or World Clocks as floating desktop panels from the app.
- Drag panels into position. They keep a small gap from one another and remember their placement.
- Hover over a panel and open its **•••** menu to edit it, close it, or return to the main Digital Wall app.

## Data and privacy

Digital Wall stores its JSON state and copied vision-board images locally in the App Group container configured in your private `Signing.local.xcconfig`. The checked-in example identifiers are placeholders and are not tied to any person or development team. The app has no network client, account system, analytics, or cloud dependency. Removing the app does not automatically remove that App Group data.
