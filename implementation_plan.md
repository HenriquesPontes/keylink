# Implementation Plan: Dynamic Island & Live Activities

The goal is to move the active Emulation countdown and status (and potentially OTA updates) into the **Dynamic Island** and Lock Screen using iOS Live Activities (`ActivityKit`). This allows you to close the app while the bridge is emulating and still see the remaining time and connection status at a glance.

## User Review Required

> [!IMPORTANT]
> Implementing Dynamic Island requires adding a new "Widget Extension" target to the Xcode project and configuring `NSSupportsLiveActivities` in the `Info.plist`. Please review the plan below.

## Proposed Changes

### 1. `Info.plist` Configuration
- Update the main app's `Info.plist` to include `NSSupportsLiveActivities` set to `YES`.

### 2. Xcode Target Setup
- Create a Ruby script (`setup_live_activity.rb`) to programmatically inject a new Widget Extension target (`keycardWidget`) into `keycard.xcodeproj`.
- Link `WidgetKit` and `ActivityKit` frameworks to this target.

### 3. `ActivityAttributes` Definition
- Create `EmulationAttributes.swift` (shared between the main app and widget).
- Define static properties (like the `cardName`) and dynamic properties (like `timeRemaining` and `status`).

### 4. Dynamic Island UI (`keycardWidget`)
- Implement a `Widget` conforming to `ActivityConfiguration`.
- Design the **Compact**, **Minimal**, and **Expanded** views for the Dynamic Island.
- Design the Lock Screen live activity banner.

### 5. `ActivityKit` Lifecycle Integration
#### [MODIFY] [EmulationView.swift](file:///Users/admin/Developer/keycard/keycard/Emulation/EmulationView.swift)
- Import `ActivityKit`.
- **Start Activity:** When `startEmulation()` is called, request a new `Activity<EmulationAttributes>`.
- **Update Activity:** Every second the timer ticks, update the activity's dynamic state.
- **End Activity:** When `stopEmulation()` is called or the timer expires, end the activity.

## Verification Plan

### Automated/Manual Verification
- Run the Ruby script to ensure the Xcode project parses and updates correctly.
- Compile the app with the new widget target.
- Verify through the iOS Simulator that starting an emulation session successfully spawns a Live Activity in the Dynamic Island.
