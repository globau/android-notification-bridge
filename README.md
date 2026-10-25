# <img src="icons/mac/AppIcon128.png" alt="" width="48" height="48" align="absmiddle"> Notification Bridge

See your Android phone's notifications on your Mac while the phone sits
charging with its screen off, so you can tell at a glance whether something
needs you without picking the phone up.

When your phone's screen is off and it's plugged into a charger, Notification
Bridge forwards each new notification to your Mac, where it appears as a normal
macOS notification. Dismiss it on the phone and it disappears from the Mac too.
As soon as you turn the screen on (or unplug it), forwarding stops, so you don't
get everything twice.

It's most useful when your phone is in silent mode: the Mac shows you what
arrived, so you can ignore what can wait and pick up the phone for what can't.

Everything stays on your local network. There's no account, no cloud service,
and the phone talks directly to the Mac over an encrypted connection.

## Requirements

- A Mac running macOS 14 (Sonoma) or later.
- An Android phone running Android 14 or later.
- Both on the same Wi-Fi network.

## Installing

Download the latest `notification-bridge-<version>.zip` from the
[Releases](https://github.com/globau/android-notification-bridge/releases) page
and unzip it. Inside are both apps.

### Mac

Move `Notification Bridge.app` to your Applications folder and open it. macOS
will check that you want to open an app downloaded from the internet; click
**Open**.

### Android

Copy `Notification Bridge.apk` to your phone (for example over USB, or by
emailing it to yourself) and open it. Android will ask whether to allow the app
you opened it from to install apps; allow it, then tap **Install**.

To update either app later, download the new release and install it over the
top. Your pairing and settings are kept.

## Setting up the Mac

Notification Bridge lives in the menu bar; there's no Dock icon or window.

The first time it runs, macOS will ask for two permissions. Allow both:

- **Notifications**, so it can show your phone's notifications.
- **Local network**, so your phone can find it and connect.

To have it start automatically, turn on **Launch at Login** in its menu.

## Setting up the phone

Open Notification Bridge on the phone. The **Setup** section lists the
permissions it needs; tap each button and allow it:

- **Grant notification access** lets the app read your notifications so it can
  forward them.
- **Grant local network access** lets it find and connect to your Mac (only
  asked for on newer versions of Android).
- **Allow background running** stops Android from putting the app to sleep
  while the screen is off, which is exactly when it needs to work.

Each line changes from "missing" to "granted" once it's done.

## Pairing the phone with your Mac

Make sure the Mac app is running, then on the phone tap **Send test
notification**.

1. The phone looks for your Mac on the network and remembers it.
2. Your Mac shows an **Allow (phone name)?** notification, with a fingerprint
   such as `3F2A-91C0-7B4E`.
3. Check that fingerprint matches the **This phone:** line in the phone app. If
   you want to be thorough, also check that the fingerprint shown next to your
   Mac's name on the phone matches **This Mac:** in the Mac app's menu.
4. Click **Allow** on the Mac notification (or choose **Pair (phone name)** >
   **Allow** from the menu bar).

The test notification then appears on your Mac, and the phone's **Last:** line
reads "Delivered to (your Mac)". You're done.

The fingerprints are there so you can be sure the phone and the Mac are talking
to each other and not to some other device on the network. Once paired, the
phone ignores any other Mac, and the Mac ignores any phone you haven't allowed.

If you have more than one Mac running Notification Bridge on the same network,
the phone pairs with whichever it finds first. Quit it on the others while
pairing.

## Everyday use

Just plug your phone in and let the screen turn off. New notifications will
show up on your Mac.

Click a notification on the Mac to open it in a window showing its full text,
which you can select and copy.

Some notifications are never forwarded, because they would only be noise:

- ongoing notifications, such as music playback, navigation or downloads in
  progress;
- minimised notifications that only appear when you expand the notification
  shade;
- notifications with no title or text.

Silent notifications are held back for five seconds before being forwarded, and
dropped if in that time they've gone away or turned into an ongoing
notification. This keeps out brief status messages such as "Backing up...".
Notifications that would normally make a sound arrive straight away.

### Choosing which apps are forwarded

The **Apps** section of the phone app lists every app that has posted a
notification since Notification Bridge was installed. Switch off any app you
don't want to see on your Mac. Apps appear in the list the first time they post
a notification, so the list grows over time.

## Unpairing

- **On the phone:** tap **Forget Mac**. The next time it sends a notification
  it will pair with whichever Mac it finds, and you'll need to allow it again.
- **On the Mac:** choose **Paired Phones** > **Forget "(phone name)"**. The next
  notification from that phone will ask for permission again.

If you click **Deny** when a phone asks to pair, that phone is blocked for good
and won't ask again. To clear the list of blocked phones, quit the Mac app, run
this in Terminal, and reopen it:

```sh
defaults delete au.glob.NotificationBridge deniedPhones
```

## Troubleshooting

The **Last:** line in the phone app shows what happened to the most recent
notification it tried to send.

**"Failed: no mac found"**: the phone couldn't find your Mac. Check that the Mac
app is running and says **Listening** in its menu, that both devices are on the
same Wi-Fi network, and that the Mac app has local network access (System
Settings > Privacy & Security > Local Network). Some networks, such as guest or
office Wi-Fi, block devices from seeing each other.

**"Waiting for approval on (your Mac)"**: the Mac hasn't allowed this phone yet.
Look for the **Allow** notification, or use **Pair** in the menu bar.

**"Denied by (your Mac)"**: this phone was denied. See
[Unpairing](#unpairing) to clear it.

**"Rejected by (your Mac)"**: the Mac couldn't accept the message. The most
likely cause is that the phone's and Mac's clocks differ by more than five
minutes; make sure both set their time automatically.

**The test works, but real notifications don't arrive**: the test is sent
straight away, but real notifications are only forwarded while the screen is
off and the phone is plugged in. Also check that the app isn't switched off in
the **Apps** list and that **Allow background running** is granted. Some phones
have extra battery-saving settings of their own that can stop background apps;
if yours does, exclude Notification Bridge from them.

**Nothing appears on the Mac, but the phone says "Delivered"**: check that
notifications for Notification Bridge are allowed in System Settings >
Notifications, and that a Focus mode isn't hiding them.

## Reporting bugs

If something isn't working and the troubleshooting tips above don't help,
please start a
[discussion](https://github.com/globau/android-notification-bridge/discussions)
on GitHub. Describe what you expected to happen, what happened instead, and the
versions of macOS, Android and Notification Bridge you're running.

Issues are reserved for confirmed, actionable work. Once we've talked it
through and confirmed it's a bug, I'll open an issue to track the fix.

## Licence

The code is released under the [MIT License](LICENSE).

The app icons are modified from the
[Material Symbols](https://github.com/google/material-design-icons) by Google
and are released under the [Apache License 2.0](icons/LICENSE). This covers
`icons/` and the copies built into both apps (under `mac/Resources/` and
`android/app/src/main/res/`).
