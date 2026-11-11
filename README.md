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
- **🔋 Battery Percentage & Capacity Telemetry:**
  - Displays remaining battery percentage (`%`) or switchable to Watt-hours (`Wh`).
  - **Clickable:** Left-click the battery percentage slot to toggle between `%` and remaining `Wh` directly.
- **📊 Dedicated Capacity Slot (Toggleable):**
  - Displays live Watt-hours telemetry (e.g. `18.9 Wh`, `18.9 / 31.8 Wh`, or `Cap 31.8 Wh`).
  - **Toggle on/off:** Easily show or hide the slot via right-click context menu (`Show Capacity Slot (Wh)`) or tray icon menu.
  - **Cycle Formats:** Left-click on the Capacity slot to cycle through:
    1. *Remaining Wh* (`18.9 Wh`)
    2. *Remaining / Full Capacity* (`18.9 / 31.8 Wh`)
    3. *Full Charge Capacity* (`Cap 31.8 Wh`)
- **🌡️ Live CPU Temperature:** Real-time thermal sensor reading (`°C`) via Windows ACPI Thermal Zone, with dynamic thermal color alerts.
- **🔥 CPU Power Consumption / TDP Meter (New!):**
  - Live CPU package power draw in Watts measured directly from Intel RAPL (Running Average Power Limit) hardware energy counters.
  - Sits right beside CPU Temperature (`🌡️ 52°C | 🔥 4.2 W`).
  - **Dynamic Thermal Coloring:** Sky Blue (≤ 12 W), Amber (12 W – 25 W), Red (> 25 W boost).
  - **Cycle Formats:** Left-click on the TDP slot to cycle between Compact (`4.2 W`), With Label (`4.2 W TDP`), or Detailed breakdown (`PKG 4.2W / 2.9W`).
  - **Toggle on/off:** Easily show or hide via the overlay right-click context menu (`Show CPU Power Meter (TDP)`) or tray icon menu.
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
| **Click Capacity Slot** | Cycle capacity format: Remaining (`18.9 Wh`) → Detailed (`18.9 / 31.8 Wh`) → Full (`Cap 31.8 Wh`). |
| **Click CPU TDP Slot** | Cycle TDP format: Compact (`4.2 W`) → With Label (`4.2 W TDP`) → Detailed (`PKG 4.2W / Core 2.9W`). |
| **Click Battery % Slot** | Toggle percentage display between `%` and `Wh`. |
| **Click `▾` / `▴`** | Collapse or expand the Battery Session Counter Card (persists across restarts). |
| **Right Click (Overlay)** | Open settings menu (Toggle TDP Slot, TDP Format, Toggle Capacity Slot, Capacity Format, Compact Mode, Show/Hide Session Card, Reset Counter, Always On Top, Opacity, Reset Position, Exit). |
| **Click `✕`** | Minimize / hide overlay to the Hidden Icons tray. |
| **Tray Icon (Left Click)** | Toggle overlay visibility (Show / Hide). |
| **Tray Icon (Right Click)** | Access quick controls, toggle capacity slot, toggle session card, or **Exit Completely**. |
| **Re-launching App** | If already running in tray or background, re-launching immediately brings the window to the front. |

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
