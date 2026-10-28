# Local Laptop Access

This allows you to access your computer from another computer (like a Chromebook) so it's almost like you have the power of your MacBook on your Chromebook.

## Required materials
You need:
- Laptop
- iPhone (hasn't been tested with an android)
- USB-C cable (maybe other) that can transmit data so the host computer can have internet access

## Set it up

If you're hosting on an Apple laptop, paste this into Terminal:

```
git clone https://github.com/zivzancoeli-commits/host-internet.git "$HOME/host-internet" && open "$HOME/host-internet/Setup.command"
```

If the Mac asks to install the command line tools, click Install, wait until that finishes, and paste the command again. Those tools are only there so `git` can download this folder. Setup itself downloads Sunshine, then asks for the Wi-Fi name, the Wi-Fi password, the website username, the website password, and the address.

On a Windows laptop that hose, paste this into PowerShell:

```
git clone https://github.com/zivzancoeli-commits/host-internet.git "$env:USERPROFILE\host-internet"; Start-Process "$env:USERPROFILE\host-internet\Setup.bat"
```

Allow the administrator window. Setup downloads Sunshine and asks the same questions.

Use the paste command rather than the green Code button's Download ZIP. A ZIP from the browser can make the Mac refuse to open Setup.

## What setup asks for

- Wi-Fi name: 1 to 32 letters, numbers, spaces, or hyphens. It cannot start or end with a space.
- Wi-Fi password: 8 to 63 letters, numbers, or symbols. No spaces.
- Website username: 1 to 32 letters and numbers.
- Website password: 4 to 64 letters, numbers, or symbols. No spaces.
- Address: `http://` plus this computer's hotspot address. On an Apple laptop that address is `192.168.2.1`. On a Windows laptop it is `192.168.137.1`. The port has to be 8080 through 8099. One short path such as `/play` is allowed. `http://192.168.2.1:8080` is the usual choice. `https` and any other address will not work, because the other computer has no internet.

Setup puts **Turn On**, **Turn Off**, and `How to join.txt` on the desktop. It does not turn the hotspot on. Running it again asks whether to keep the choices.

An Apple laptop needs macOS Sequoia. An Apple silicon laptop may ask to install Rosetta the first time. Click to allow it.

## Turn it on

1. Plug an iPhone into this computer with a data cable. Unlock the phone and tap Trust if it asks.
2. On the iPhone, turn on Personal Hotspot.
3. Click **Turn On**.
4. Leave the phone plugged in.

On the other computer, follow `How to join.txt`.

The first time the page has no computer yet:

1. Add a computer with the address `127.0.0.1`
2. Click that computer. The page shows a number.
3. On the computer that runs the games, type that number into Sunshine.
4. Click **Desktop**

The first time the computer asks, allow Sunshine to record the screen and control the computer.

If the computer running the games is an Apple laptop, hold Control and Option together on the other computer when you want the Command key.

## Turn it off

Click **Turn Off** when this computer should sleep or use its normal Wi-Fi again.

## While it is on

- On an Apple laptop, the other computer does not get normal internet. The page still opens at the address in `How to join.txt`. If the browser says the network has no internet, type that address anyway.
- On a Windows laptop, Windows may still share internet through its hotspot. The page opens at that address either way.
- On an Apple laptop, do not click Wi-Fi in Control Center. That turns the hotspot off. The menu bar looks disconnected because this computer is hosting the Wi-Fi.
- On an Apple laptop, the lid can be closed. The screen goes dark and the computer stays on. If the mouse sticks in the top-left after the lid closes, open the lid.
- Plug the computer into a wall charger. The phone cable is for internet. It does not charge the computer.
- If an Apple laptop starts charging from the phone instead of the other way around, unplug the cable. Put a USB-C female to USB-A adapter on the computer, then use a USB-A to USB-C cable to the phone.

## If Turn On says the cable is not sharing

Unlock the phone, turn Personal Hotspot on, and use a cable that carries data. Then click Turn On again. On an Apple laptop, Wi-Fi is left as it was.
