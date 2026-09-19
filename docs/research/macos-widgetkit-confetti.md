# macOS WidgetKit and full-screen confetti

Research date: 2026-09-19
Scope: a native macOS WidgetKit widget whose `Button(intent:)` logs a deep-work hour and celebrates the transition from three to four hours.

## Executive conclusion

A WidgetKit interaction **cannot use a supported Apple API to draw full-screen or system-wide confetti while leaving the containing app unopened and unactivated**.

This follows from WidgetKit's execution and rendering model:

- Widget code runs in an extension process separate from the containing app. WidgetKit archives the view produced for a timeline entry, and the system renders that representation. The widget extension is not a continuously running view process. [Apple: Adding interactivity to widgets and Live Activities](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities), [Apple: Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)
- By default, the `AppIntent` behind a widget button runs in the widget-extension process. It can update shared state; after `perform()` returns, WidgetKit guarantees a timeline reload. It does not grant the extension an app-owned desktop window or a system visual-effect surface. [Apple: Adding interactivity to widgets and Live Activities](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)
- Moving an intent into a foreground execution mode is the supported route when work needs the app's interface. Apple's current `supportedModes` API says the immediate foreground mode brings the app to the foreground; dynamic and deferred modes can transition it there. That would no longer satisfy the requirement that the app remain unopened/unactivated. [Apple: `AppIntent.supportedModes`](https://developer.apple.com/documentation/appintents/appintent/supportedmodes), [Apple: `IntentModes`](https://developer.apple.com/documentation/appintents/intentmodes)

Apple documents no WidgetKit or App Intents capability for drawing beyond the widget's system-managed presentation. Therefore the no-full-screen conclusion is an inference from the documented process, rendering, and foreground-mode boundaries, not a statement that Apple publishes as a single prohibition sentence.

## What WidgetKit does support

The supported celebration surface is the widget itself. After the fourth-hour intent saves the new value and returns, the guaranteed timeline reload can produce a completed entry that differs from the previous one. WidgetKit then animates the changed views.

Apple supports:

- default animations when views change between timeline entries;
- built-in SwiftUI transitions and animations, including `opacity`, `move(edge:)`, `slide`, `push(from:)`, and combinations;
- `transition(_:)`, `contentTransition(_:)`, and `animation(_:value:)`;
- numeric text transitions, useful for animating `3 / 4` into `4 / 4`;
- `invalidatableContent(_:)` on the important value while a button-triggered reload is pending.

Widget and Live Activity animations have a maximum duration of **two seconds**. Widget views do not hold ordinary live state while displayed; the animation is driven by differences between timeline entries. [Apple: Animating data updates in widgets and Live Activities](https://developer.apple.com/documentation/widgetkit/animating-data-updates-in-widgets-and-live-activities), [Apple WWDC23: Bring widgets to life](https://developer.apple.com/videos/play/wwdc2023/10028/)

Only App-Intent-backed `Button` and `Toggle` controls provide direct widget interactivity. A button acknowledges the press but does not remain pressed; the updated timeline should communicate success. [Apple: Adding interactivity to widgets and Live Activities](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)

## Recommended supported fallback

On the first transition from three to four hours:

1. Persist `4` before the intent returns.
2. Reload to an entry that shows `4 / 4`, a checkmark, and the completed-day color.
3. Animate the number with `.contentTransition(.numericText())` and a short spring.
4. Briefly add a bounded celebratory burst inside the widget — for example, a small set of colored marks or SF Symbols using opacity, scale, move, and rotation transitions.
5. Keep the entire effect at roughly 1–2 seconds and retain the completed visual state after the burst ends.

This delivers immediate reward without opening the app and stays within Apple's documented WidgetKit model. It should be described as an **in-widget celebration**, not a free-running particle system.

If true desktop-wide confetti remains a requirement, make it an explicit second mode: the interaction must bring the containing macOS app forward so the app can create and manage its own overlay window. That is a different experience from a widget-only interaction and should be opt-in rather than hidden behind the ordinary `+1 hour` button.

## Project decision

Digital Wall uses that explicit app-opening mode only for the winning fourth hour. Hours one through three and hours beyond the goal remain ordinary in-widget actions. At three hours, the widget's next `+1` control opens a Digital Wall URL; the app reloads shared state, records hour four, and presents an app-owned full-screen celebration using the same high-level route as the immersive Vision Board.

## Sources

- [Apple: Adding interactivity to widgets and Live Activities](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)
- [Apple: Animating data updates in widgets and Live Activities](https://developer.apple.com/documentation/widgetkit/animating-data-updates-in-widgets-and-live-activities)
- [Apple: Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)
- [Apple: Creating a widget extension](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension)
- [Apple: `AppIntent.supportedModes`](https://developer.apple.com/documentation/appintents/appintent/supportedmodes)
- [Apple: `IntentModes`](https://developer.apple.com/documentation/appintents/intentmodes)
- [Apple WWDC23: Bring widgets to life](https://developer.apple.com/videos/play/wwdc2023/10028/)
