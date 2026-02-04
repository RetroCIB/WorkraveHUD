# WorkraveHUD

A lightweight, Workrave-inspired break reminder built with **Rainmeter**.  
It provides a compact always-on HUD and a fullscreen overlay for enforced breaks, with idle detection and configurable policies.

---

## Features

- 🕒 **Micro / Rest / Daily timers**
- 🖥️ **Compact HUD** (always visible)
- 🚫 **Fullscreen break overlay** when a break is due
- 💤 **Idle-aware break detection**
- ⚙️ **STRICT / RELAXED break policies**
- 🔊 **Audio notifications** (start / end of break)
- ⏭️ **Skip break** action (configurable logic)
- 🎨 Visual style inspired by *taboo_vision*

---

## Preview

> HUD: compact widget showing Micro / Rest / Daily progress  

<img src="Screenshot 2026-02-04 111539.png"/>

   
> Overlay: fullscreen break screen with countdown and progress bar

<img src="Screenshot 2026-02-04 111917.png"/> 

---

## Installation

### Recommended (rmskin)

1. Download `WorkraveHUD_1.0.0.rmskin`
2. Double-click the file
3. Rainmeter Skin Installer will open
4. Click **Install**
5. Load the skin from Rainmeter

This will install all required files automatically.

---

### Manual Installation

1. Copy the `WorkraveHUD` folder into:
```

Documents\Rainmeter\Skins\

```

2. Ensure the structure looks like this:

```

WorkraveHUD
├── README.md
├── WorkraveHUD.ini
├── WorkraveHUD_1.0.0.rmskin
│
├── @Resources
│   ├── Images
│   │   └── W-Dot.png
│   ├── Scripts
│   │   └── workrave.lua
│   └── Sounds
│       ├── break_start.wav
│       └── break_end.wav
│
└── Overlay
└── Overlay.ini

````

3. Refresh Rainmeter and load **WorkraveHUD.ini**

---

## How It Works

- The **HUD** runs continuously and tracks:
- Active work time
- Micro break interval
- Rest break interval
- Daily limit

- When a break is due:
- A **fullscreen overlay** appears
- A countdown and progress bar are shown
- User must remain idle for the required duration

- When the break completes:
- Overlay closes automatically
- Work counters resume

- The **Skip** button allows bypassing a break (behavior configurable in Lua).

---

## Break Types

| Type  | Purpose            | Default |
|------|--------------------|---------|
| Micro | Short eye / posture breaks | 3 min work / 30 sec break |
| Rest  | Longer rest breaks | 45 min work / 10 min break |
| Daily | Daily work limit   | ~6 hours |

*(All values are configurable)*

---

## Configuration

Main settings are located in **`WorkraveHUD.ini`**:

```ini
MicroInterval=180
MicroRequiredIdle=30

RestInterval=2700
RestRequiredIdle=600

DailyLimit=21600
IdleThreshold=2

BreakPolicy=STRICT
RelaxedBreakTimeout=1200
````

### Break Policies

* **STRICT**

  * Any activity during a break resets the break timer
* **RELAXED**

  * Idle time accumulates
  * Break can be enforced again after a timeout

---

## Sounds

Break notifications are played using:

* `@Resources/Sounds/break_start.wav`
* `@Resources/Sounds/break_end.wav`

You can replace these files with your own `.wav` sounds.

---

## Overlay

The fullscreen overlay is defined in:

```
Overlay/Overlay.ini
```

It is:

* Loaded once at startup
* Shown / hidden dynamically by the Lua script
* Always on top
* Clickable (Skip button)

---

## Development Notes

* Logic is implemented in **Lua** using a simple FSM (finite state machine)
* UI is fully handled by Rainmeter meters
* No external dependencies
* Designed to be extensible and easy to tweak

---

## Known Limitations

* Rainmeter cannot fully block keyboard or mouse input
* Overlay is a visual enforcement only
* True OS-level blocking would require a native application

---

## License

MIT License (or adjust as needed)

---

## Credits

Inspired by:

* [Workrave](https://workrave.org/)
* taboo_vision Rainmeter theme

Built with ❤️ using Rainmeter + Lua.

``` 

