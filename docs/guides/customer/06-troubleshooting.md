# Troubleshooting

*Describes build: 2.5.10+116 · Last verified: 2026-10-09*

Find your problem below and follow the steps in order. Each ends with what to do if it still is not fixed. Contact for anything else: **System → Support & Resources → Contact Nex-Gen Support**, which shows your installer's phone and email.

## My lights are dark

1. Is the controller plugged in and its outlet on? If not, fix that first.
2. Is your phone on your home Wi-Fi? Open Lumina. The badge on Home should read **Direct**.
   - If it reads **Via Bridge** at home: open **System → System & Device Management → Remote Access** and tap **Detect Home Network**.
3. Does the Now Playing bar say "Can't reach your lights"? Tap **Reconnect** and wait a minute.
4. Tap the power button. Do the lights come on?
   - Yes: a schedule turned them off. Check the Schedule tab for an off time, and the **Turn lights off at sunrise daily** switch under System.
   - No: did the power go out recently? See [After a power outage](05-power-outage-and-recovery.md).
5. Still dark: contact your installer. Tell them the date, the time, and what Home said.

## The lights look wrong, or only part of the house changed

1. On Home, are all the channel chips selected? Tap **All Channels On**.
2. Is a chip marked as left out? Tap it and choose to include it.
3. Did the power go out recently? The controller forgets the channel split until the app reconnects at home. See [After a power outage](05-power-outage-and-recovery.md).
4. Did a schedule or Game Day change one run only? Tap a favorite on Home to put one look on the whole house.
5. Still wrong: contact your installer.

## The app says I'm away from home

The app decides from your Wi-Fi network's name. At home, Home reads **Direct**.

1. Is your phone on Wi-Fi, and on your home network (not a guest network or mobile data)?
2. Did you change your Wi-Fi name or router? Open **System → System & Device Management → Remote Access** and tap **Detect Home Network** while on the new network.
3. Did you say no to the Location prompt? The app needs it to read the network name. In your phone's Settings, allow Location for Lumina "While Using the App".
4. If it still reads **Via Bridge** at home, the app works anyway, just a few seconds slower. Tell your installer.

## Away from home, nothing responds or it is slow

1. "You're away from home. Control from anywhere requires a Lumina Bridge." means your home has no bridge paired. Ask your installer about one.
2. "Couldn't reach your home from here" or "Your Lumina Bridge hasn't checked in": the bridge is unplugged, your home internet is down, or the bridge is in its quiet window. About every seven hours the bridge is quiet for roughly ten minutes. Wait ten minutes and try again.
3. Remote commands normally take a few seconds. Wait before tapping again.
4. "You're away from home and remote access isn't set up for this controller": open **System → System & Device Management → Controllers** and check that your controller shows ACTIVE. If not, tap it and choose **Set as Active**.
5. Still nothing after ten minutes: contact your installer.

## Game Day didn't switch back

1. Wait until an hour after the final. The game decides when the look ends.
2. Open the app at home. On the Schedule tab tap your everyday schedule, or on Home turn the lights off and on.
3. Does the Game Day screen say "Your everyday lighting settings need repairing"? Contact your installer; this cannot be fixed from the app today.
4. Tell your installer which game it was and the time.

## Game Day didn't light the house

1. Did you open the app at home in the two days before kickoff? The app sets the controller then. If not, tap **Light Up Now** on the team card now.
2. On the Game Day screen, does the banner read **Game Day runs from this phone**? If it reads "setup needed", tap it and follow what it says.
3. Is **Autopilot** on for that team, and is the game listed on the card?
4. Still nothing: contact your installer with the date and time.

## Nothing responds on a new phone, or after switching accounts

1. Sign in with the same email as before.
2. Open **System → System & Device Management → Controllers**.
3. Tap your controller and choose **Set as Active**. You'll see it marked ACTIVE.
4. Go back to Home and tap the power button.

On the current build the app does this for you after an account switch; on older builds you may have to do it once by hand.

## Voice isn't available

Siri Shortcuts work on iPhone: open **System → Voice Assistants**, save a look, then tap **Add to Siri**. On Android, long-press the Lumina icon for app shortcuts. Google and Alexa options on that screen do not complete today; they are not available.

## A schedule didn't run

1. On the Schedule tab, is the schedule in the list and is the header "Schedules synced to controller"? If it reads "Not synced", go home and tap **Sync**.
2. Did you edit it away from home? It applies the next time your phone is on the home Wi-Fi.
3. Did you see "controller timer slots are full (8/8)"? Delete or pause an old schedule and tap **Sync**.
4. Is it a sunrise or sunset schedule? Make sure your home address is set under **System → My Profile → Edit Profile**.
5. Do you see "Controller clock isn't set"? Open the app at home and leave it on Home for a minute; the app sets the controller's clock. If the message stays the next day, contact your installer.

## I changed my Wi-Fi password or router

Your controller and bridge need the new network. This is an installer task: contact your installer from **System → Support & Resources**. Do not try to reconfigure the controller through its own web pages.

## I want to remove a controller

Open **System → System & Device Management → Controllers**, tap the controller and choose to remove it. The app warns that this deletes all saved settings for that controller. Ask your installer before doing this.

*Facts: T-X20, T-R10, T-P1, T-P2, T-R1, T-R2, T-R3, T-R6, T-R7, T-S1, T-S2, T-GD3, T-GD5, T-GD6, T-VA1, T-VA2, T-X21, T-D2, T-R9, T-SU1.*
