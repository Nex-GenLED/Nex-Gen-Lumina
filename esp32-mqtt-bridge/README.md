# Lumina ESP32 MQTT Bridge

This ESP32 firmware bridges MQTT messages from HiveMQ Cloud to local WLED devices via HTTP. It enables remote control without requiring WLED to support MQTT+TLS, and works with T-Mobile Home Internet and other CGNAT situations.

## How It Works

```
┌─────────────────┐      HTTPS       ┌─────────────────┐
│   Lumina App    │ ───────────────► │  Lumina Backend │
│   (Remote)      │                  │   (Node.js)     │
└─────────────────┘                  └────────┬────────┘
                                              │
                                              │ MQTT (TLS)
                                              ▼
                                     ┌─────────────────┐
                                     │  HiveMQ Cloud   │
                                     │   (Broker)      │
                                     └────────┬────────┘
                                              │
                                              │ MQTT (TLS)
                                              ▼
┌─────────────────┐      HTTP        ┌─────────────────┐
│  WLED Device    │ ◄─────────────── │  ESP32 Bridge   │
│  (Local)        │                  │  (This Device)  │
└─────────────────┘                  └─────────────────┘
```

1. **Lumina App** sends command to **Lumina Backend**
2. **Backend** publishes to **HiveMQ Cloud** MQTT broker
3. **ESP32 Bridge** receives message via TLS connection
4. **ESP32 Bridge** makes HTTP request to **WLED** on local network
5. **WLED** responds, **ESP32 Bridge** publishes status back to HiveMQ

## Why This Works with T-Mobile Home Internet

T-Mobile uses CGNAT, which blocks incoming connections. This bridge only makes **outbound** connections:
- Outbound to WiFi router
- Outbound to HiveMQ Cloud (TLS on port 8883)
- Outbound to WLED (HTTP on port 80)

No port forwarding or public IP required!

## Requirements

- ESP32 development board (any variant with WiFi)
- USB cable for programming
- PlatformIO IDE (VS Code extension recommended)
- Your WLED device's local IP address

## Setup

### 1. Install PlatformIO

Install the [PlatformIO IDE extension](https://platformio.org/install/ide?install=vscode) in VS Code.

### 2. Configure the Bridge

Edit `src/config.h` and update:

```cpp
// HiveMQ Cloud credentials (same as your Lumina Backend .env)
#define MQTT_BROKER "4429fe3219f64734b912d6bef5d6688b.s1.eu.hivemq.cloud"
#define MQTT_PORT 8883
#define MQTT_USERNAME "NexGen"
#define MQTT_PASSWORD "Grayson8817*"

// Your device ID from Lumina Backend
#define DEVICE_ID "a55fbb4d-ecea-4c66-aaff-278985528588"

// Your WLED's local IP address
#define WLED_IP "192.168.50.100"  // UPDATE THIS!
```

### 3. Find Your WLED IP

1. Open your WLED's web interface from your phone/computer
2. Go to **Config** → **WiFi Setup**
3. Note the IP address shown

Or check your router's connected devices list.

### 4. Build and Upload

1. Connect your ESP32 via USB
2. Open this folder in VS Code
3. Click the PlatformIO icon in the sidebar
4. Click "Build" to compile
5. Click "Upload" to flash the ESP32

### 5. Configure WiFi

On first boot (or if WiFi credentials are lost):

1. The ESP32 creates an AP called "Lumina-MQTT-Bridge"
2. Connect to it from your phone (password: `luminabridge`)
3. A configuration portal opens automatically
4. Select your home WiFi network and enter the password
5. The ESP32 saves the credentials and connects

### 6. Verify Operation

Open the Serial Monitor (115200 baud) to see status:

```
=========================================
   Lumina ESP32 MQTT Bridge v1.0
=========================================

Device ID: a55fbb4d-ecea-4c66-aaff-278985528588
WLED IP: 192.168.50.100

Setting up WiFi...
Connected! IP: 192.168.50.150

Setting up MQTT...
Connecting to HiveMQ Cloud... Connected!
Subscribing to: lumina/a55fbb4d-ecea-4c66-aaff-278985528588/command

Bridge initialized!
```

## LED Indicators

| Pattern | Meaning |
|---------|---------|
| Rapid blinks on startup | Initializing |
| Solid 1 second | Successfully initialized |
| Single blink every 5s | All systems OK |
| LED on during processing | Executing command |
| 2 blinks every 5s | WiFi OK, MQTT disconnected |
| 3 blinks every 5s | WiFi disconnected |

## Testing

Once the bridge is running, you can test from your Lumina Backend:

```bash
# Send a command via the backend API
curl -X POST http://localhost:3000/api/devices/a55fbb4d-ecea-4c66-aaff-278985528588/command \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -d '{"action": "setState", "payload": {"on": true, "bri": 128}}'
```

Or watch the ESP32 Serial Monitor and use the Lumina app remotely.

## MQTT Topics

| Topic | Direction | Purpose |
|-------|-----------|---------|
| `lumina/{deviceId}/command` | Backend → Bridge | Receive commands |
| `lumina/{deviceId}/status` | Bridge → Backend | Publish responses |

## Command Format

Commands sent to the bridge should be JSON with this structure:

```json
{
  "action": "setState",
  "payload": {
    "on": true,
    "bri": 128,
    "seg": [{"col": [[255, 0, 0]]}]
  }
}
```

Supported actions:
- `getState` - GET /json/state
- `getInfo` - GET /json/info
- `setState` - POST /json/state
- `applyJson` - POST /json/state
- `setConfig` - POST /json/cfg
- `applyConfig` - POST /json/cfg

## Troubleshooting

### "Connecting to HiveMQ Cloud... Failed"
- Check your MQTT credentials in config.h
- Verify the broker hostname is correct
- Check Serial Monitor for specific error code

### Commands not reaching WLED
- Verify WLED_IP is correct in config.h
- Make sure WLED is powered on and connected to WiFi
- Check that ESP32 and WLED are on the same network

### "ERROR: HTTP -1" or connection refused
- WLED might not be reachable
- Check WLED's IP hasn't changed (consider setting a static IP)
- Verify WLED is responding at http://WLED_IP/json/state

## Security Notes

- MQTT credentials are stored in the firmware (compile-time)
- Consider using device-specific MQTT credentials for production
- The ESP32 only accepts commands from authenticated MQTT topics
- All MQTT communication is encrypted via TLS
