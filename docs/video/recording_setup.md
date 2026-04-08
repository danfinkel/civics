# CivicLens — Screen Recording Setup Guide

**Purpose:** Technical guide for capturing demo videos  
**Date:** April 7, 2026  
**Agent:** Agent 4

---

## Overview

This guide covers multiple methods for recording CivicLens demo scenarios. Choose based on equipment availability and quality requirements.

**Preferred Method:** iOS device with built-in screen recording (highest quality, most authentic)

**Backup Methods:** Android screen recording, iOS Simulator, Android Emulator

---

## Method 1: iOS Device (Preferred)

### Prerequisites

- iPhone or iPad with iOS 11 or later
- CivicLens app installed (from Agent 1)
- Test documents loaded in Photos app

### Setup Steps

**1. Enable Screen Recording**

1. Open **Settings** → **Control Center**
2. Tap **Screen Recording** (add to Included Controls if not present)
3. Exit Settings

**2. Prepare Documents**

1. Transfer spike artifacts to device:
   ```bash
   # From your Mac
   open /spike/artifacts/
   # AirDrop D12, D05, D06, D13, D14 to iPhone
   ```

2. Verify all 5 documents appear in Photos app

**3. Recording Settings**

- Do Not Disturb: **ON** (prevent notifications)
- Orientation Lock: **OFF** (allow rotation if needed)
- Brightness: **Maximum** (clearer video)
- Auto-Lock: **Never** (Settings → Display & Brightness)

**4. Start Recording**

1. Open CivicLens app
2. Swipe down from top-right corner (Control Center)
3. Long-press Screen Recording button
4. Tap **Start Recording**
5. Wait for 3-second countdown
6. Begin demo scenario

**5. Stop Recording**

1. Tap red status bar at top of screen
2. Tap **Stop**
3. Video saves automatically to Photos app

**6. Transfer to Computer**

```bash
# Method A: AirDrop
# Select video in Photos → Share → AirDrop to Mac

# Method B: Image Capture (USB)
open -a Image\ Capture
# Select iPhone, import video

# Method C: iCloud Photos
# Enable iCloud Photos, download from Photos app on Mac
```

### Quality Settings

- Resolution: Matches device screen (typically 1170×2532 for iPhone 14)
- Frame rate: 60fps (smooth scrolling)
- Format: MOV (H.264)

### Tips

- Use a physical device, not simulator (better performance)
- Keep battery above 50% (recording is intensive)
- Clean screen before recording
- Use guided access mode to prevent accidental taps

---

## Method 2: Android Device

### Prerequisites

- Android 11 or later (for built-in screen recording)
- CivicLens APK installed (from Agent 1)

### Setup Steps

**1. Enable Screen Recording**

Most Android devices (Android 11+):
1. Swipe down twice from top of screen
2. Tap **Screen Record**
3. Choose audio settings (none needed for demo)
4. Tap **Start**

Samsung devices:
1. Swipe down for Quick Settings
2. Tap **Screen Recorder**
3. Configure settings → Start

**2. Recording Settings**

- Do Not Disturb: **ON**
- Brightness: **Maximum**
- Screen timeout: **10 minutes**

**3. Transfer Files**

```bash
# ADB method
adb pull /sdcard/DCIM/ScreenRecorder/scenario_b1.mp4 ./recordings/

# Or use Android File Transfer app
```

---

## Method 3: iOS Simulator (macOS)

### Prerequisites

- macOS with Xcode installed
- iOS Simulator with CivicLens app

### Recording Commands

```bash
# Start recording (booted simulator)
xcrun simctl io booted recordVideo scenario_b1.mov

# Stop recording
# Press Ctrl+C in terminal

# Recording saves to current directory
```

### Alternative: QuickTime Player

1. Open **QuickTime Player**
2. File → New Movie Recording
3. Click dropdown next to record button → Select iPhone
4. Click record button
5. Perform demo on simulator
6. Click stop button
7. File → Save

### Pros/Cons

**Pros:**
- No physical device needed
- Easy to control
- Direct file output

**Cons:**
- Slower performance than real device
- May not show realistic timing
- No finger/touch indicators

---

## Method 4: Android Emulator

### Prerequisites

- Android Studio installed
- Emulator with CivicLens APK

### Recording Steps

1. Open Android Emulator
2. Click **More** (three dots) in emulator toolbar
3. Select **Record and Playback**
4. Click **Start Recording**
5. Perform demo
6. Click **Stop Recording**
7. Save video file

---

## Post-Processing

### Recommended Edits

1. **Trim start/end:** Remove app launch and home screen navigation
2. **Remove loading pauses:** If analysis takes >10 seconds, trim middle
3. **Add captions:** If audio narration is unclear
4. **Stabilize:** No shaky camera (not applicable for screen recording)

### Target Durations

| Scenario | Raw Recording | Final Edit |
|----------|---------------|------------|
| B1 Happy Path | 60-90 sec | 45 sec |
| B4 Warning | 45-60 sec | 30 sec |
| Combined | 105-150 sec | 75 sec |

### Export Settings

**For Video Editing Software:**
- Format: MP4 (H.264)
- Resolution: 1080p minimum
- Frame rate: 30fps (sufficient for screen recording)
- Bitrate: 5-10 Mbps

**For Direct Submission:**
- Format: MP4
- Resolution: 1920×1080 (upscale if needed)
- File size: Under 500MB for 3-minute video

---

## Recording Checklist

### Before Recording

- [ ] Device charged above 50%
- [ ] Do Not Disturb enabled
- [ ] Brightness at maximum
- [ ] CivicLens app opens successfully
- [ ] All 5 test documents accessible
- [ ] Screen recording tested (30-second test)
- [ ] Quiet environment confirmed
- [ ] Script printed for reference

### During Recording

- [ ] Record B1 scenario first
- [ ] Pause, review, then record B4
- [ ] Speak clearly if narrating live
- [ ] Tap deliberately (not too fast)
- [ ] Let loading screens play out

### After Recording

- [ ] Transfer files to computer
- [ ] Review both recordings
- [ ] Note timestamps for editing
- [ ] Backup raw files
- [ ] Hand off to editing (Week 3)

---

## Troubleshooting

### Recording Won't Start

**iOS:**
- Check Control Center settings
- Restart device
- Free up storage space

**Android:**
- Check Android version (need 11+)
- Use third-party app (AZ Screen Recorder) if built-in fails

### Video Quality Poor

- Increase brightness
- Clean screen
- Record in landscape if app supports it
- Use physical device over simulator

### App Crashes During Recording

- Close other apps
- Restart device
- Check with Agent 1 for app stability
- Use simulator as backup

### Files Won't Transfer

- Use cloud storage (Google Drive, iCloud)
- Email to yourself (if small enough)
- Use USB cable + file manager

---

## File Organization

```
docs/video/
├── recordings/
│   ├── raw/
│   │   ├── b1_take1.mov
│   │   ├── b1_take2.mov
│   │   ├── b4_take1.mov
│   │   └── b4_take2.mov
│   └── edited/
│       ├── b1_final.mp4
│       └── b4_final.mp4
├── script.md
├── scenarios.md
└── recording_setup.md (this file)
```

---

## Equipment Recommendations

### Best Setup

- **Device:** iPhone 14 or newer (smooth performance, good screen)
- **Computer:** Mac with QuickTime (easy transfer and editing)
- **Storage:** 5GB free space minimum

### Minimum Setup

- **Device:** Any iOS 11+ or Android 11+ device
- **Transfer:** USB cable or cloud storage
- **Editing:** Free software (iMovie, DaVinci Resolve)

---

## Contact for Issues

- **App not working:** Contact Agent 1 (Flutter)
- **Documents missing:** Check `/spike/artifacts/`
- **Recording technical issues:** Try alternate method

---

**Guide Version:** 1.0  
**Last Updated:** April 7, 2026  
**Status:** Ready for recording session
