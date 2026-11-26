<p align="center"><img src="MeetingBar/Assets.xcassets/AppIcon.appiconset/256x256@2x.png" width="128" height="128" alt="Soon"></p>

[![GitHub license](https://img.shields.io/github/license/allison-fang/Soon.svg)](https://github.com/allison-fang/Soon/blob/master/LICENSE)
[![Github all releases](https://img.shields.io/github/downloads/allison-fang/Soon/total.svg)](https://github.com/allison-fang/Soon/releases/)

**Soon** is a lightweight macOS menu bar app that shows your day as a timeline and lets you join meetings in one click. It's a redesigned fork of [MeetingBar](https://github.com/leits/MeetingBar) by [leits](https://github.com/leits).

It keeps meetings visible in the status bar, detects meeting links from calendar events, supports macOS Calendar and Google Calendar, and works with 50+ meeting services including Google Meet, Zoom, Microsoft Teams, Webex, and Discord.

Soon is free, open source, and privacy-respecting.

## Install

Soon requires **macOS 12.0 or later**.

1. Open **Terminal**: press ⌘ Space, type `Terminal`, and press Return.
2. Paste this command and press Return:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/allison-fang/Soon/master/Scripts/install.sh | bash
   ```

   It downloads the latest release, checks that it's signed by Soon and isn't damaged, puts Soon in Applications, and opens it.
3. In the setup window, choose where Soon reads your calendars from:
   * **macOS Calendar**: when macOS asks, allow Soon to access your calendars.
   * **Google Calendar**: sign in to Google in your browser. Google warns that it hasn't verified the app; choose **Advanced**, then **Go to Soon**. Then return to Soon.
4. Choose which calendars to show, and finish setup.

Soon lives in the menu bar, not the Dock. Click it to see your day.

Soon is separate from MeetingBar and can be installed alongside it. Its settings start fresh.

### Update

When a new version is out, Soon shows **Update available** at the bottom of its menu. To update, run the install command again in Terminal (you can also copy it from Preferences › General):

```bash
curl -fsSL https://raw.githubusercontent.com/allison-fang/Soon/master/Scripts/install.sh | bash
```

It quits Soon, replaces it with the latest version, and reopens it. Your settings are kept.

### Uninstall

Quit Soon from its menu, then move Soon from Applications to the Trash.

### Why Terminal?

macOS only opens apps downloaded in a browser if Apple has notarized them, which requires a paid Apple Developer account. Soon isn't notarized, so a copy downloaded in a browser won't open. The install command downloads Soon without that restriction.

## Calendar providers

Soon works with:

* **macOS Calendar**: use any calendar account synchronized with Calendar.app, including iCloud, Google, Exchange, Office 365, Yahoo, AOL, and others.
* **Google Calendar**: connect Google Calendar directly from Soon.

## Features

### See what is next

* Show the current or next meeting in the macOS status bar.
* Display meeting title, time, countdown, icon, or meeting service.
* See today's and tomorrow's events on a timeline, color-coded by calendar and response.
* Hover an event to see its meeting link, guests, and notes.
* Filter all-day, declined, tentative, pending, or linkless events.
* Shorten long meeting titles to keep the menu bar readable.

### Join meetings faster

* Join any upcoming online meeting with one click.
* Join the nearest meeting with a global keyboard shortcut.
* Move between events with the arrow keys and join with Return.
* Create ad-hoc meetings from your preferred meeting service with a keyboard shortcut.
* Open meeting links in a preferred browser or native app per service.
* Open events in Google Calendar, Calendar, or Fantastical.

### Get meeting reminders

* Receive macOS notifications before meetings.
* Use full-screen reminders for important meeting starts.
* Disable notifications for a single meeting.
* Configure reminders around your own workflow.

### Customize and automate

* Launch Soon automatically at login.
* Use Shortcuts and AppleScript integrations.
* Run custom AppleScript, for example to pause music when joining a meeting.

## Supported meeting services

Soon supports more than 50 meeting services, including:

Google Meet, Zoom, Microsoft Teams, Webex, GoToMeeting, Skype, Discord, Jitsi, RingCentral, BlueJeans, Whereby, Slack Huddle, FaceTime, LiveKit Meet, Meetecho, StreamYard, and many others.

See MeetingBar's [full supported services list](https://github.com/leits/MeetingBar/discussions/108).

## Privacy

Soon does not collect personal data.

Calendar data is used by the app to show your meetings, detect meeting links, and open the correct meeting action. Google Calendar access is read-only.

Once a day, Soon asks GitHub for the latest release version. The request contains no personal or calendar data; GitHub sees your IP address, as with any web request. You can turn it off in Preferences › General.

## Troubleshooting

If meetings do not appear, links are not detected, or Google Calendar needs reconnecting, run the install command again to get the latest version, or [open an issue](https://github.com/allison-fang/Soon/issues/new).

Useful details for bug reports:

* Soon version
* macOS version
* Calendar provider: macOS Calendar or Google Calendar
* Meeting service: Zoom, Google Meet, Microsoft Teams, Webex, etc.
* Whether the event is recurring or one-off
* Whether the event is accepted, tentative, pending, declined, or canceled
* Sanitized event title, description, location, and URL fields
* Whether manual refresh changes the behavior
* Screenshots or logs when available

## Release history

Read [Soon's releases](https://github.com/allison-fang/Soon/releases) for what changed in each version.

## Contributing

Soon is open source under the [Apache 2.0 license](LICENSE). See [CONTRIBUTING.md](CONTRIBUTING.md) to build it from source.

## Credits

Soon is built on [MeetingBar](https://github.com/leits/MeetingBar) by [leits](https://github.com/leits). Written in Swift 6.

Soon also uses these resources:

* [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) for managing global keyboard shortcuts
* [Defaults](https://github.com/sindresorhus/Defaults) for managing user settings
* [LaunchAtLogin](https://github.com/sindresorhus/LaunchAtLogin) for launch-at-login integration
* [AppAuth-iOS](https://github.com/openid/AppAuth-iOS) for Google Calendar OAuth

If you encounter any bugs or have a feature request, [open an issue](https://github.com/allison-fang/Soon/issues/new). Soon is a personal project, so issues may not get a reply.
