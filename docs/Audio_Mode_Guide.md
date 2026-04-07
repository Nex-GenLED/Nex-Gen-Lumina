---
title: "Nex-Gen Lumina — Audio Mode Guide"
subtitle: "Make your lights react to music, speech, and ambient sound in real time"
author: "Nex-Gen LED"
date: "April 2026"
pdf_options:
  format: Letter
  margin: 20mm
  headerTemplate: '<div style="font-size:8px;width:100%;text-align:center;color:#666;">Nex-Gen Lumina — Audio Mode Guide</div>'
  footerTemplate: '<div style="font-size:8px;width:100%;text-align:center;color:#666;">Page <span class="pageNumber"></span> of <span class="totalPages"></span></div>'
stylesheet: []
body_class: guide
---

<style>
  body { font-family: 'Segoe UI', Arial, sans-serif; color: #222; line-height: 1.6; }
  h1 { color: #00B8D4; border-bottom: 2px solid #00B8D4; padding-bottom: 8px; }
  h2 { color: #00E5FF; margin-top: 28px; }
  h3 { color: #333; }
  table { border-collapse: collapse; width: 100%; margin: 12px 0; }
  th, td { border: 1px solid #ccc; padding: 8px 12px; text-align: left; }
  th { background: #00B8D4; color: white; }
  .tip { background: #E0F7FA; border-left: 4px solid #00B8D4; padding: 10px 14px; margin: 12px 0; border-radius: 4px; }
  .warning { background: #FFF3E0; border-left: 4px solid #FF9800; padding: 10px 14px; margin: 12px 0; border-radius: 4px; }
  .step-box { background: #F5F5F5; border: 1px solid #ddd; border-radius: 8px; padding: 14px; margin: 10px 0; }
</style>

# Nex-Gen Lumina — Audio Mode Guide

Audio Mode turns your permanent LED lighting system into a real-time sound-reactive display. Music, speech, or any ambient sound picked up by your controller's onboard microphone drives the colors, brightness, and movement of your lights — no extra hardware or wiring required.

---

## 1. What Is Audio Mode?

Audio Mode uses a microphone built into your Nex-Gen controller to listen to nearby sound. The controller analyzes the audio signal on-device and translates it into lighting effects — bass hits trigger flashes, melodies drive color sweeps, and ambient noise creates gentle pulses.

Everything happens locally on the controller. No audio is recorded, streamed, or stored.

---

## 2. Requirements

Before using Audio Mode, make sure your system meets these requirements:

| Requirement | Detail |
|-------------|--------|
| **Controller firmware** | SR WLED (Sound Reactive WLED) with the AudioReactive usermod installed |
| **Microphone** | Onboard MEMS microphone or external I2S mic (INMP441, SPH0645) |
| **Compatible hardware** | Nex-Gen NGL-CTRL-P1 comes pre-installed with AudioReactive firmware and an onboard microphone |
| **App version** | Nex-Gen Lumina v2.1 or later |

<div class="tip">
<strong>Tip:</strong> If you have a Nex-Gen NGL-CTRL-P1 controller, Audio Mode is ready to go out of the box. No additional setup is needed.
</div>

The app automatically detects whether your controller supports Audio Mode when you connect. If the firmware or microphone is missing, the Audio Mode screen will display a clear message explaining what is needed.

---

## 3. Opening Audio Mode

There are three ways to access Audio Mode:

### From the Dashboard

1. Open the Nex-Gen Lumina app
2. On the **Home** dashboard, locate the **Audio Mode** button (speaker/equalizer icon)
3. Tap it to open the Audio Mode screen

### Using Lumina AI (Voice or Text)

Say or type any of these to activate Audio Mode through the AI assistant:

- "Turn on audio mode"
- "Make the lights react to music"
- "Pulse to the beat"
- "Start sound reactive mode"
- "Sync to music"

Lumina AI will automatically select the best available audio effect and activate it.

### Direct Navigation

Navigate to **Audio Mode** from any screen using the app's navigation.

---

## 4. The Audio Mode Screen

When you open Audio Mode with a compatible controller connected, you will see four main controls:

### Status Header

At the top of the screen, a status indicator shows whether audio is active:

| State | Indicator | Message |
|-------|-----------|---------|
| **Standby** | Grey mic icon | "Select an audio effect to begin" |
| **Listening** | Pulsing cyan mic icon with animated waveform bars | "LEDs are reacting to sound" |

When active, the mic icon pulses with a glowing cyan animation and a waveform visualizer shows real-time audio activity.

---

### Microphone Sensitivity

A slider labeled **Mic Sensitivity** controls how responsive the system is to sound.

| Setting | Range | Use when |
|---------|-------|----------|
| **Quiet** (left) | 0 | The room is very quiet — increases sensitivity to pick up soft sounds |
| **Middle** (default) | 128 | Normal volume — a good starting point for most environments |
| **Loud** (right) | 255 | The room is very loud — reduces sensitivity to prevent constant triggering |

<div class="tip">
<strong>Tip:</strong> Start with the slider in the middle. If the lights are reacting to background noise (air conditioning, conversations) when you want them to respond only to music, slide toward "Loud." If the lights are barely reacting, slide toward "Quiet."
</div>

Adjustments take effect immediately — no need to tap a save button.

---

### Audio Effects Grid

Below the sensitivity slider, a grid of effect cards shows all available audio-reactive effects on your controller. Each card displays:

- The **effect name**
- An animated **waveform** visualizer
- A **cyan highlight** when the effect is active

Tap any card to apply that effect immediately. Your lights will begin reacting to sound using the selected pattern.

**Popular effects include:**

| Effect | Description |
|--------|-------------|
| **GEQ** | Graphic equalizer — frequency bands displayed as colored columns |
| **Gravimeter** | Gravity-based volume meter — a ball bounces with the beat |
| **Waverly** | Smooth rolling waves driven by audio amplitude |
| **DJ Light** | Color-shifting spotlight that follows bass and treble |
| **Ripple Peak** | Ripples emanate from peak audio moments |
| **Freqwave** | Frequency spectrum displayed as a moving wave |
| **Puddles** | Color puddles expand and contract with the beat |
| **Rocktaves** | Octave-based color mapping — each note gets its own hue |

<div class="tip">
<strong>Tip:</strong> The available effects depend on your controller's firmware version. If you do not see many options, updating to the latest SR WLED firmware will add more audio-reactive effects.
</div>

---

### Brightness

A **Brightness** slider at the bottom sets the overall LED brightness level (0 to 255). This works the same as the brightness control on the main dashboard — it affects the maximum brightness of the audio-reactive effect.

---

### Stop Audio Mode

A red **Stop Audio Mode** button appears at the bottom of the screen when an audio effect is active. Tapping it:

1. Switches the lights back to a solid warm white
2. Returns the status indicator to **Standby**
3. Your lights resume normal (non-audio) operation

If no audio effect is currently active, this button is greyed out.

---

## 5. Using Audio Mode with Lumina AI

Lumina AI understands audio-related commands in natural language. Here are examples of what you can say:

| What you say | What happens |
|--------------|--------------|
| "Turn on audio mode" | Activates the best available audio effect (prefers GEQ or Gravimeter) |
| "Make my lights pulse to music" | Same as above |
| "React to the bass" | Activates an audio-reactive effect |
| "Stop audio mode" | Returns lights to normal |
| "Switch to DJ Light effect" | Activates the specific named effect (if available) |

<div class="warning">
<strong>Note:</strong> Audio Mode requires an active controller connection. If your system is offline, Lumina AI will let you know that a connected controller is needed.
</div>

---

## 6. Tips for Best Results

### Speaker Placement

- Place your music source **near the controller** for the strongest signal
- The onboard microphone picks up sound within the room — it does not need to be right next to the speaker, but closer is better
- Bass-heavy music produces the most dramatic effects

### Environment

- Audio Mode works best in rooms with a single dominant sound source (your music)
- In noisy environments with lots of background sound, increase the sensitivity slider toward "Loud" to filter out ambient noise
- Outdoor installations work well when the speaker is aimed toward the controller

### Effect Selection

- **GEQ** and **Gravimeter** are great all-around choices for most music
- **DJ Light** works well for dance music and parties
- **Waverly** creates a calmer, more ambient experience
- Try different effects to find what works best for your music style and space

### Performance

- Audio processing happens entirely on the controller — there is no lag between sound and light response
- The app does not need to stay open for Audio Mode to continue working once activated
- Audio Mode will stay active until you stop it manually, switch to a different effect, or a schedule event overrides it

---

## 7. Troubleshooting

| Problem | Solution |
|---------|----------|
| **"Audio Mode Not Available" message** | Your controller does not have AudioReactive firmware or a microphone. The Nex-Gen NGL-CTRL-P1 supports Audio Mode out of the box. Contact support if you believe your controller should be compatible. |
| **No audio effects listed** | The firmware has AudioReactive support but no audio effects were detected. Update your controller to the latest SR WLED firmware. |
| **Lights not reacting to sound** | Check the Mic Sensitivity slider — it may be set too far toward "Loud." Move it toward "Quiet" and test again. Also verify the music source is near the controller. |
| **Lights constantly flickering** | The sensitivity is too high for your environment. Move the slider toward "Loud" to reduce responsiveness to background noise. |
| **Effect looks different than expected** | Different effects respond to different audio frequencies. Try a few effects to find one that matches your music. Bass-heavy tracks work best with GEQ and Gravimeter. |
| **Audio Mode stopped unexpectedly** | A scheduled event may have overridden the manual audio effect. Check your schedule for any events that trigger around this time. |

---

## 8. Quick Reference

| Action | How |
|--------|-----|
| **Open Audio Mode** | Dashboard → **Audio Mode** button |
| **Activate via voice** | Say "Turn on audio mode" or "Pulse to the beat" to Lumina AI |
| **Select an effect** | Tap any effect card in the grid |
| **Adjust sensitivity** | Drag the **Mic Sensitivity** slider (Quiet ← → Loud) |
| **Adjust brightness** | Drag the **Brightness** slider |
| **Stop Audio Mode** | Tap the red **Stop Audio Mode** button |

---

*Nex-Gen Lumina v2.1 — Audio Mode Guide — April 2026*
