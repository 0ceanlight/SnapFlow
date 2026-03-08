# SnapFocus

A lightweight macOS time-tracking sidebar that syncs with your calendar, visualizes your schedule in real-time, and keeps your current focus in view. A productivity HUD for people who want time to feel tangible.

> **Note:** This project was created as part of the [**SIUE Hackathon 2026**](https://ehacks.cs.siue.edu/) in St. Louis. Watch the trailer [here](https://youtu.be/dDavFPFlbJc)!

![Screenshot](./Thumbnail.png)

---

## Features

- **Real-Time Schedule Visualization:** An always-on-top sidebar that displays your calendar events for the day on a vertical timeline.
- **Dynamic "Now" Indicator:** A clear line shows your current position in the day's schedule.
- **Interactive Time Shifting:**
    - **Nudge:** Use keyboard shortcuts (`Up`/`Down` arrows) to extend or shorten the currently active task.
    - **Open in Calendar:** Click on an event to open it in Apple Calendar.
    - **Resize or Move Events**: Super convenient resizing right from the expanded calendar view - just click and drag any event.
- **Agentic Scheduling with Gemini:** Use natural language to describe your tasks for the day (e.g., "work on my thesis for 3 hours and go for a run"), and let AI generate and save a detailed schedule directly to your calendar. This can be done both with voice recognition or text input.
- **Customizable & Persistent Settings:** Configure your Gemini API key securely in the app's preferences.

## Getting Started

### Prerequisites

- macOS
- Xcode

### Installation

1.  **Clone the repository:**
    ```sh
    git clone https://github.com/your-username/SnapFocus.git
    cd SnapFocus
    ```

2.  **Open the project in Xcode:**
    ```sh
    open SnapFocus.xcodeproj
    ```

3.  **Add Package Dependencies:**
    - In Xcode, go to `File > Add Package Dependencies...`.
    - Paste the following URL into the search bar: `https://github.com/google/generative-ai-swift`
    - Follow the prompts to add the package to the `SnapFocus` target.

4.  **Configure API Key:**
    - Open the app's preferences by pressing `Cmd+,` or going to `SnapFocus > Preferences...`.
    - Enter your Gemini API key and click "Save". You can get a key from [Google AI Studio](https://aistudio.google.com/).

5.  **Build and Run:**
    - Press `Cmd+R` to build and run the application.

## Usage

- **Ruler Overlay:** The main timeline view appears on the left side of your screen. Hover over it to expand and see event details.
- **Nudge Task:** While hovering over the ruler, use the `Up Arrow` and `Down Arrow` keys to adjust the duration of the currently active task.
- **Agentic Scheduler:**
    - Open the scheduler window with `Cmd+Shift+S` or via `Show Agentic Scheduler` in the menu bar.
- **Resize or Move Events**: Either click and drag an event to move it, or click and drag the bottom edge of an event to change its duration.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
