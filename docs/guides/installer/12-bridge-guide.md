# The Lumina Bridge

*Describes build: 2.5.10+116 · Bridge firmware 1.2 · Last verified: 2026-10-09 · For installers*

The bridge is a small box that stays plugged in at the customer's house, on their Wi-Fi. It lets the app control the lights from anywhere. Bridges are installed, paired, replaced and moved by installers only; customers do not pair a bridge.

## What it can and cannot do

- It relays light changes (power, brightness, looks, Game Day looks) from the cloud to the controller. A change takes a few seconds.
- It cannot change controller settings or schedules. Schedule edits made away from home apply when the customer's phone is next at home.
- It has no web page. The only page it ever shows is its Wi-Fi setup page during first setup. Status and testing are in the app.
- It checks in every 30 seconds. About every seven hours it goes quiet for roughly ten minutes; during that window remote commands fail and the app may say the bridge has not checked in. Home Wi-Fi control is unaffected. This is known; the fix is on the server side and is coming.
- Its firmware is updated only by Nex-Gen, by cable, at the bench. Never try to update a bridge in the field.

## Pair a bridge

**At the house, step 1: put the bridge on the home Wi-Fi.**

1. Plug the bridge in. Within a minute it broadcasts its own setup network; the name starts with "Lumina-".
2. On your phone, join that network. The setup page opens by itself; if not, open `http://192.168.4.1`.
3. Choose the customer's Wi-Fi, enter its password, save. The bridge restarts and joins the home Wi-Fi; its setup network disappears.

You have five minutes on the setup page before the bridge restarts and shows it again.

**Step 2: pair it to the customer's account, in the app.**

1. In Installer Mode tap **Existing Customer** and open the customer's account, or sign in as the customer on their phone. Your phone must be on the same home Wi-Fi as the bridge.
2. Open **System → System & Device Management → Remote Access** and tap **Set Up Bridge**.
3. **Find**: the bridge appears as "Ready to pair". If it does not, tap the advanced option and enter the bridge's address from the router's device list.
4. **Pair**: check that the controller target shows the customer's controller, then tap **Pair Bridge**.
5. **Verify**: the app runs a round trip through the cloud. You'll see "Bridge is working!".
6. Back on Remote Access, turn on **Enable Remote Access** and tap **Detect Home Network** so the app knows this Wi-Fi is home.
7. Switch your phone to mobile data and change the brightness. The lights follow within a few seconds and the Home badge reads **Via Bridge**.

**If Verify fails:** "The bridge has not heartbeated to Firestore in the last 60 seconds" means it is not on the Wi-Fi or has no internet; check the router and repeat step 1. "This bridge is paired to a different Nex-Gen account" means the previous owner's pairing was never cleared; see *Reset* below.

## Test a bridge later

**System → System & Device Management → Remote Access → Test Bridge**. It waits ten seconds. **Bridge Connected** is good. **Bridge Not Responding** means unplugged, no internet, or the quiet window: wait ten minutes and test again. **No Bridge Paired** means pair it.

## Status light

The bridge blinks every five seconds: one blink, Wi-Fi and cloud are up; two blinks, Wi-Fi only (no internet); three blinks, no Wi-Fi. It blinks fast five times when it starts.

## Reset a bridge

A reset clears the pairing and keeps the Wi-Fi settings. Use it before moving a bridge to a different account.

From a computer or phone on the same Wi-Fi as the bridge, send an HTTP POST to the bridge's address with the path `/api/reset`. It replies ok and restarts. The app has no reset button today.

## Replace a bridge

1. Reset the old bridge (above) if it still works, so it stops claiming the account.
2. Pair the new bridge as above. The old pairing is replaced in the account.

## Move a bridge to another house

1. Reset it at the old house.
2. At the new house its old Wi-Fi is absent, so the setup network comes back by itself. Set the new Wi-Fi and pair it to the new account.

## The customer changed their router or Wi-Fi

1. The bridge's setup network reappears when the old Wi-Fi is gone. Join it and set the new Wi-Fi. The pairing is kept.
2. The controller needs the new Wi-Fi too (see the [install checklist](10-install-checklist.md), step 3). If the controller got a new address, open System & Device Management → Controllers, tap the controller and re-sync it.
3. In the app tap **Detect Home Network** on the new network.

## Do not

- Do not reset a working customer bridge "to check it". It wipes the pairing.
- Do not use the Webhook (Dynamic DNS) connection mode for an install. It is a do-it-yourself path that needs port forwarding; leave **Connection Mode** on the bridge.
- Do not describe a bridge web page or dashboard to a customer. There is none.

*Facts: T-R1, T-R4, T-R5, T-R6, T-R7, T-R8, T-R9, T-R10, T-X1, T-X2, T-O9.*
