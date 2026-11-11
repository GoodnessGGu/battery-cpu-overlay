# Battery & CPU Wattage Overlay

An ultra-lightweight, battery-efficient real-time overlay for Windows laptops that monitors power draw (Watts), battery percentage, CPU temperature, estimated battery life, and an **automatic battery session counter**.

Designed specifically to be sleek, distraction-free, and consume virtually zero system resources (<0.05% CPU).

---

## ✨ Features

- **⚡ Real-Time Wattage Draw:** Live power consumption in Watts calculated directly from the motherboard's ACPI battery controller.
  - **Cyan** (≤ 8.5 W): Low power draw / optimal battery life.
  - **Amber** (8.5 W – 15 W): Normal / moderate usage.
  - **Red** (> 15 W): Heavy energy consumption.
  - **Emerald Green**: Plugged into AC (displays live `+X.X W` charging rate).
- **📊 Dynamic Battery Session Counter Card:**
  - **Auto-Trigger on Battery:** Activates automatically the moment AC power is unplugged and resets to track the new session.
  - **Running Stopwatch:** Live elapsed timer (`HH:MM:SS`) tracking your active battery session in both the primary status bar and the detailed session card.
  - **Active Awake Time Only:** Smart sleep / Modern Standby detection pauses the counter while the laptop is asleep or suspended, counting true screen-on active time only.
  - **Starting Charge Tracker:** Captures and displays the exact battery percentage and timestamp when AC power was disconnected (e.g. `Started at: 85% (11:30 AM)`).
  - **Power Consumed:** Live percentage dropped (e.g. `Used: 12%`).
  - **Energy Telemetry:** Real-time energy drained in Watt-hours (`-3.8 Wh`) and live discharge rate in Watts.
  - **AC Final Session Summary:** When plugged back into AC, displays the complete session summary until your next battery run.
  - **Persistent Session State:** Remembers elapsed time and initial percentages across overlay minimizations, toggles, and app restarts during the same battery run.
  - **Collapsible:** Toggle the card open or closed via the `▾` button or right-click menu.
- **🌡️ Live CPU Temperature:** Real-time thermal sensor reading (`°C`) via Windows ACPI Thermal Zone, with dynamic thermal color alerts.
- **🔋 Battery Percentage & Health State:** Shows remaining capacity and shifts to low-battery indicators when needed.
- **⏱️ Dynamic Time Remaining:** Constantly calculated based on your immediate real-time discharge rate.
- **🪟 Sleek Floating Pill Overlay:**
  - Modern dark acrylic UI with subtle drop shadow and rounded corners.
  - **Always on Top:** Floats over full-screen browser tabs, IDEs, documents, and games.
  - **Draggable:** Click and drag anywhere on the widget to place it wherever you want. Position is remembered across restarts.
  - **Compact Mode:** Double-click to collapse into a minimal wattage & temperature badge.
- **📌 System Tray ("Hidden Icons") Integration:**
  - **Zero Taskbar Clutter:** Does not occupy space on your main taskbar.
  - Lives quietly in your Windows notification area / hidden icons tray (`^`).
  - Hovering displays a live status tooltip (`Bat: 40% (8.4 W) | 01:24:35 (-15%) | CPU: 55°C`).
  - Left-click tray icon to show/hide the floating overlay instantly.
  - Clicking `✕` on the overlay minimizes it directly to the tray.

---

## 🚀 Quick Start

### 1. Clone the repository
```bash
git clone https://github.com/GoodnessGGu/battery-cpu-overlay.git
cd battery-cpu-overlay
```

### 2. Launch the Overlay
Simply double-click **`Launch.bat`** (or `Launch.vbs` for silent background start).

### 3. (Optional) Create a Desktop Shortcut
Run the included shortcut generator in PowerShell:
```powershell
powershell -ExecutionPolicy Bypass -File .\Create-Shortcut.ps1
```
This creates a **Battery Overlay** shortcut directly on your Desktop with native battery icons.

---

## 🎮 Controls & Interactions

| Action | Result |
| :--- | :--- |
| **Left Click + Drag** | Move overlay anywhere on screen (auto-saves position). |
| **Double Click** | Toggle between **Full View** (with Session Card) and **Compact View** (`⚡ 8.4 W  •  🌡️ 55°C`). |
| **Click `▾` / `▴`** | Collapse or expand the Battery Session Counter Card. |
| **Right Click (Overlay)** | Open settings menu (Compact Mode, Show/Hide Session Card, Reset Counter, Always On Top, Opacity, Refresh Rate, Reset Position, Exit). |
| **Click `✕`** | Minimize / hide overlay to the Hidden Icons tray. |
| **Tray Icon (Left Click)** | Toggle overlay visibility (Show / Hide). |
| **Tray Icon (Right Click)** | Access quick controls, toggle session card, or **Exit Completely**. |

---

## ⚡ Battery & Resource Efficiency

Unlike Electron or Webview-based widgets that consume hundreds of megabytes of RAM and constantly keep CPU cores awake, this app:
- Uses **native Windows Presentation Foundation (WPF)** and .NET.
- Uses **no third-party drivers or external dependencies**.
- Idles with **< 0.05% CPU usage**.
- Consumes virtually 0 mW of battery itself.

---

## 📋 Requirements

- Windows 10 or Windows 11 (64-bit or 32-bit).
- Built-in Windows PowerShell 5.1+ (pre-installed on all modern Windows machines).
- No administrator privileges required.

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).
