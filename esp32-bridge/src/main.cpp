/**
 * Lumina ESP32 Bridge v1.3.0
 *
 * This firmware runs on an ESP32 and acts as a bridge between
 * Firebase Firestore and WLED devices on the local network.
 *
 * How it works:
 * 1. Connects to local WiFi network
 * 2. Starts local HTTP API + mDNS so the Lumina app can discover & pair
 * 3. Signs in to Firebase Auth to get an ID token
 * 4. Polls Firestore for pending commands (using Bearer token auth)
 * 5. Executes commands by making HTTP requests to WLED devices
 * 6. Updates command status in Firestore
 *
 * Tasks (1.3.0). Before 1.3.0 everything ran in loop(), so a loop() blocked
 * in a network call also stopped the heartbeat and the watchdog (#109), and
 * every heartbeat stalled command polling for ~5 s of each 30 s.
 *   loopTask   (Arduino, core 1, prio 1) — command polling, pairing, OTA,
 *                                          local web server
 *   heartbeat  (core 0, prio 1)          — bridge_status + bridge_registry
 *                                          writes, off the poll path
 *   supervisor (core 1, prio 5)          — progress watchdog; restarts the
 *                                          chip without loop()'s help
 *   console    (core 1, prio 1)          — serial provisioning of the
 *                                          per-bridge credential
 * The ESP-IDF task watchdog (a hardware timer interrupt, not a task) watches
 * loopTask, heartbeat and supervisor.
 */

#include <Arduino.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <WiFiManager.h>
#include <WebServer.h>
#include <ESPmDNS.h>
#include <Preferences.h>
#include <time.h>
#include <sys/time.h>
#include <esp_attr.h>
#include <esp_system.h>
#include <esp_task_wdt.h>
#include <esp_ota_ops.h>
#include <esp_sntp.h>
#include <esp_core_dump.h>
#include <mbedtls/pk.h>
#include <mbedtls/sha256.h>
#include <mbedtls/base64.h>

#include "config.h"

// ============================================================================
// Build-time configuration (1.3.0)
// ============================================================================
// Every new tunable has a default here so an existing config.h keeps
// compiling unchanged. Override in config.h or with -D build flags.

#ifndef BRIDGE_FIRMWARE_VERSION
#define BRIDGE_FIRMWARE_VERSION "1.3.0"
#endif

// Hardware task watchdog for loopTask / heartbeat / supervisor. Must exceed
// the longest legitimate gap between feeds: one command is bounded by
// 2 Firestore PATCHes (30 s handshake + 15 s I/O each) + one WLED request
// (5 s connect + 10 s) ≈ 105 s, and loop() feeds between commands.
#ifndef BRIDGE_LOOP_WDT_TIMEOUT_S
#define BRIDGE_LOOP_WDT_TIMEOUT_S 180
#endif

// Progress watchdog (supervisor task): no proof of useful work for this long
// → restart. Paired: a successful command-queue query. Unpaired: a successful
// registry/pairing Firestore call. Doubles after each consecutive no-progress
// restart (capped at 16×) so an orphaned bridge does not reboot every 5 min.
#ifndef BRIDGE_PROGRESS_TIMEOUT_MS
#define BRIDGE_PROGRESS_TIMEOUT_MS 300000UL
#endif

// setup() must finish within this. Covers the WiFiManager portal (it reboots
// itself at 300 s), the NTP wait (unbounded before 1.3.0) and first sign-in.
#ifndef BRIDGE_BOOT_DEADLINE_MS
#define BRIDGE_BOOT_DEADLINE_MS 600000UL
#endif

// The heartbeat task writes only while the poll loop is demonstrably alive,
// so a fresh bridge_status/current still means "commands are being picked
// up" — the Neighborhood Sync liveness gate and the app's online check rely
// on exactly that.
#ifndef HEARTBEAT_POLL_FRESH_MS
#define HEARTBEAT_POLL_FRESH_MS 90000UL
#endif

// Neighborhood Sync timebase. WLED resets strip.timebase when a POST turns a
// dark strip on, so tb goes in a SEPARATE bare {"tb":N} POST after the apply.
// 300 ms is the gap bench-verified on 2026-09-22.
#ifndef TB_FOLLOWUP_DELAY_MS
#define TB_FOLLOWUP_DELAY_MS 300
#endif

// SNTP re-sync interval. Crystal drift is 10–20 ppm, so 15 min bounds the
// drift between two bridges' clocks to ~20–40 ms between syncs (the IDF
// default of 3 h allows ~0.4 s).
#ifndef SNTP_SYNC_INTERVAL_MS
#define SNTP_SYNC_INTERVAL_MS 900000UL
#endif

// Per-bridge identity whose user queue keeps answering 403 for this long
// falls back to the legacy shared identity for the rest of this boot.
#ifndef PER_BRIDGE_DENIED_SWITCH_MS
#define PER_BRIDGE_DENIED_SWITCH_MS 120000UL
#endif

// 1 while the fleet migrates: the compiled shared FIREBASE_AUTH_EMAIL/PASSWORD
// stay available as a fallback. The end-of-migration image builds with 0,
// which also keeps the shared credential out of the binary.
#ifndef BRIDGE_LEGACY_SHARED_AUTH
#define BRIDGE_LEGACY_SHARED_AUTH 1
#endif
#if !BRIDGE_LEGACY_SHARED_AUTH
#undef FIREBASE_AUTH_EMAIL
#undef FIREBASE_AUTH_PASSWORD
#endif
#ifndef FIREBASE_AUTH_EMAIL
#define FIREBASE_AUTH_EMAIL ""
#endif
#ifndef FIREBASE_AUTH_PASSWORD
#define FIREBASE_AUTH_PASSWORD ""
#endif

// OTA
#ifndef OTA_CHANNEL
#define OTA_CHANNEL "stable"
#endif
#ifndef OTA_BOARD
#define OTA_BOARD "esp32dev"
#endif
#ifndef OTA_FIRST_CHECK_DELAY_MS
#define OTA_FIRST_CHECK_DELAY_MS 600000UL
#endif
#ifndef OTA_CHECK_INTERVAL_MS
#define OTA_CHECK_INTERVAL_MS 21600000UL
#endif
#ifndef OTA_CHECK_JITTER_MS
#define OTA_CHECK_JITTER_MS 1800000UL
#endif
#ifndef OTA_PROBATION_MS
#define OTA_PROBATION_MS 600000UL
#endif

// The OTA signing PUBLIC key. Release builds use src/ota_pubkey.h; the bench
// build points BRIDGE_OTA_PUBKEY_FILE at a bench key so bench-signed images
// can never install on a fielded bridge. See ota_pubkey.h.example.
#if defined(BRIDGE_OTA_PUBKEY_FILE)
#include BRIDGE_OTA_PUBKEY_FILE
#elif __has_include("ota_pubkey.h")
#include "ota_pubkey.h"
#endif
#ifdef OTA_SIGNING_PUBKEY_PEM
#define BRIDGE_OTA_ENABLED 1
#else
#define BRIDGE_OTA_ENABLED 0
#ifdef BRIDGE_REQUIRE_OTA_KEY
#error "This environment requires the OTA signing public key (src/ota_pubkey.h). See src/ota_pubkey.h.example -- a release image without OTA would need another USB visit to every bridge."
#endif
#endif

#define BRIDGE_UID_PREFIX "bridge_"

// Markers the signing tool looks for, so a manifest can only claim the
// version and board the image was actually built as.
__attribute__((used)) static const char kVersionMarker[] =
    "LUMINA_BRIDGE_FW_VERSION=" BRIDGE_FIRMWARE_VERSION;
__attribute__((used)) static const char kBoardMarker[] =
    "LUMINA_BRIDGE_FW_BOARD=" OTA_BOARD;

// ============================================================================
// Global Variables
// ============================================================================

WiFiClientSecure secureClient;   // loopTask only
WebServer server(80);
Preferences prefs;
// True when setup() loaded a UID from NVS (i.e. bridge was paired by the app
// at some point, not just running on compile-time defaults). Surfaced via
// /api/info so the app can detect whether the bridge needs initial pairing.
bool nvsUidFound = false;
volatile bool firebaseReady = false;
unsigned long lastPollTime = 0;
unsigned long lastBlinkTime = 0;
unsigned long lastPairingPollTime = 0;
unsigned long nextBootSignInRetryMs = 0;
unsigned long lastCommandExecutedMs = 0;
volatile unsigned long commandsProcessed = 0;
volatile unsigned long commandErrors = 0;
unsigned long bootTime = 0;

// Liveness timestamps (millis). 32-bit aligned, so reads from other tasks
// are atomic on the ESP32.
volatile unsigned long g_loopTickMs = 0;        // every loop() pass
volatile unsigned long g_lastPollOkMs = 0;      // command-queue runQuery == 200
volatile unsigned long g_lastProgressMs = 0;    // what the supervisor watches
volatile unsigned long g_lastHbTaskOkMs = 0;    // heartbeat task: any write 200
volatile unsigned long g_lastNtpSyncMs = 0;
volatile unsigned long g_setupDoneMs = 0;
volatile bool g_setupDone = false;

// Cross-task requests, applied by loopTask (the only task that signs in).
volatile bool g_credReloadRequested = false;
volatile bool g_identityFallbackRequested = false;
volatile bool g_otaCheckRequested = false;
volatile bool g_otaBusy = false;

// Registry self-registration cadence
#define REGISTRY_HEARTBEAT_INTERVAL_MS 30000
#define PAIRING_POLL_INTERVAL_MS 5000

// Firebase Auth tokens — guarded by authMutex (the heartbeat task reads them).
SemaphoreHandle_t authMutex = nullptr;
String firebaseIdToken = "";
String firebaseRefreshToken = "";
unsigned long tokenExpiresAt = 0;  // millis() when token expires
unsigned long nextSignInAllowedMs = 0;
volatile bool firebaseAuthenticated = false;

// Which Firebase identity this bridge signs in as (#5 per-bridge credential).
enum AuthMode : uint8_t {
  AUTH_NONE = 0,
  AUTH_PER_BRIDGE,        // this bridge's own account, uid bridge_<deviceId>
  AUTH_LEGACY,            // the shared account; no per-bridge credential stored
  AUTH_LEGACY_FALLBACK,   // has a per-bridge credential, but it was refused
};
volatile AuthMode authMode = AUTH_NONE;
String authModeReason = "";        // guarded by authMutex
String activeBridgeEmail = "";     // guarded by authMutex
String reportedBridgeUid = "";     // guarded by authMutex
bool perBridgeCredPresent = false; // written by loopTask only
String perBridgeUid = "";
String perBridgeEmail = "";
String perBridgePassword = "";
unsigned long perBridgeDeniedSinceMs = 0;
// Static string literals only — set by one task, read by another.
const char* volatile pendingFallbackReason = "";

// Pairing state — initial values come from compile-time config, then are
// overwritten in setup() with NVS-saved values if a previous pair occurred.
// pairedUserId is written by loopTask under stateMutex and copied by the
// heartbeat task.
SemaphoreHandle_t stateMutex = nullptr;
volatile bool isPaired = false;
String pairedUserId = FIREBASE_USER_UID;
String pairedWledIp = DEFAULT_WLED_IP;

// OTA state
bool otaProbation = false;
unsigned long otaProbationDeadline = 0;
unsigned long nextOtaCheckMs = 0;
String otaStatus = "";             // guarded by stateMutex

// Device identity
String deviceName = "Lumina-";
// MAC address with colons stripped (e.g. "D4E9F4FA54B8"). Used as the
// document ID under /bridge_registry — stable across reboots and unique
// per chip, so the app can find this bridge in Firestore without mDNS
// or local network scanning.
String deviceId = "";

// ============================================================================
// Boot diagnostics — survive a watchdog or panic reset (#109)
// ============================================================================
// RTC slow memory is not cleared by a software, panic or watchdog reset, so
// the phase each task was in when the chip went down is readable after the
// reboot and published in the heartbeat. That names the call a blocked
// loop() was stuck in — the one thing the 2026-09-16 field stall could not.

enum BridgePhase : uint32_t {
  PH_IDLE = 0, PH_SETUP_WIFI, PH_SETUP_NTP, PH_SIGNIN, PH_TOKEN_REFRESH,
  PH_POLL_QUERY, PH_CMD_STATUS, PH_WLED_HTTP, PH_TB_STAMP, PH_WEB_CLIENT,
  PH_PAIRING_POLL, PH_REGISTRY, PH_HEARTBEAT, PH_OTA_MANIFEST, PH_OTA_DOWNLOAD,
  PH_COUNT
};
static const char* const kPhaseNames[PH_COUNT] = {
  "idle", "setup_wifi", "setup_ntp", "signin", "token_refresh",
  "poll_query", "cmd_status", "wled_http", "tb_stamp", "web_client",
  "pairing_poll", "registry", "heartbeat", "ota_manifest", "ota_download",
};

enum RestartCause : uint32_t {
  CAUSE_NONE = 0, CAUSE_BOOT_DEADLINE, CAUSE_NO_POLL, CAUSE_NO_FIRESTORE,
  CAUSE_OTA_INSTALL, CAUSE_API_REBOOT, CAUSE_API_RESET, CAUSE_WIFI_SETUP,
  CAUSE_COUNT
};
static const char* const kCauseNames[CAUSE_COUNT] = {
  "none", "boot_deadline", "no_poll_progress", "no_firestore_progress",
  "ota_install", "api_reboot", "api_reset", "wifi_setup",
};

#define RTC_DIAG_MAGIC 0x4C554D31u  // "LUM1"
RTC_NOINIT_ATTR uint32_t rtcMagic;
RTC_NOINIT_ATTR uint32_t rtcLoopPhase;
RTC_NOINIT_ATTR uint32_t rtcHbPhase;
RTC_NOINIT_ATTR uint32_t rtcRestartCause;
RTC_NOINIT_ATTR uint32_t rtcNoProgressRestarts;

String bootResetReason = "";
String prevLoopPhase = "";
String prevHbPhase = "";
String prevRestartCause = "";
volatile uint32_t noProgressRestarts = 0;
bool coreDumpPresent = false;

#ifdef BRIDGE_BENCH
volatile bool g_benchBlockHeartbeat = false;
volatile bool g_benchFailPoll = false;
#endif

TaskHandle_t heartbeatTaskHandle = nullptr;
TaskHandle_t supervisorTaskHandle = nullptr;
TaskHandle_t consoleTaskHandle = nullptr;

// Firestore base URL
String firestoreBaseUrl() {
  return "https://firestore.googleapis.com/v1/projects/" + String(FIREBASE_PROJECT_ID) +
         "/databases/(default)/documents/users/" + pairedUserId;
}

String userDocUrl(const String& uid) {
  return "https://firestore.googleapis.com/v1/projects/" + String(FIREBASE_PROJECT_ID) +
         "/databases/(default)/documents/users/" + uid;
}

// URL of this bridge's document under /bridge_registry/{deviceId}.
// Top-level path so the bridge can register itself before it knows
// which user it belongs to.
String bridgeRegistryUrl() {
  return "https://firestore.googleapis.com/v1/projects/" + String(FIREBASE_PROJECT_ID) +
         "/databases/(default)/documents/bridge_registry/" + deviceId;
}

String expectedBridgeUid() {
  return String(BRIDGE_UID_PREFIX) + deviceId;
}

// ============================================================================
// Function Declarations
// ============================================================================

void setupWiFi();
void setupMDNS();
void setupWebServer();
void setupFirebase();
bool signInFirebase();
bool signInWithBackoff();
bool refreshFirebaseToken();
bool ensureValidToken();
void pollCommands();
void executeCommand(const String& commandId, JsonObject& fields);
String makeWledRequest(const String& ip, const String& method,
                       const String& endpoint, const String& body);
struct TbStamp;
void updateCommandStatus(const String& commandId, const String& status,
                         const String& error = "",
                         const String& result = "",
                         const TbStamp* tb = nullptr);
bool writeHeartbeat(WiFiClientSecure& client, const String& token,
                    const String& uid);
bool registerBridgeInRegistry(WiFiClientSecure& client, const String& token);
bool updateRegistryHeartbeat(WiFiClientSecure& client, const String& token);
bool pollPairingRequest();
void blinkLed(int times, int delayMs);
void statusBlink();
String convertFirestorePayloadToJson(JsonObject& fields);
void restartWithCause(uint32_t cause);
void otaBootCheck();
void otaProbationTick();
void otaMaybeRun();

// Web server handlers
void handleApiInfo();
void handleBridgeStatus();
void handleBridgePair();
void handleBridgeAuth();
void handleReboot();
void handleReset();
void handleOtaCheck();
void handleNotFound();

// ============================================================================
// Small helpers — phases, clock, shared state
// ============================================================================

inline void setLoopPhase(uint32_t p) { rtcLoopPhase = p; }
inline void setHbPhase(uint32_t p) { rtcHbPhase = p; }

const char* phaseName(uint32_t p) {
  return p < PH_COUNT ? kPhaseNames[p] : "unknown";
}

const char* causeName(uint32_t c) {
  return c < CAUSE_COUNT ? kCauseNames[c] : "unknown";
}

const char* resetReasonName(esp_reset_reason_t r) {
  switch (r) {
    case ESP_RST_POWERON:   return "poweron";
    case ESP_RST_EXT:       return "external";
    case ESP_RST_SW:        return "software";
    case ESP_RST_PANIC:     return "panic";
    case ESP_RST_INT_WDT:   return "int_wdt";
    case ESP_RST_TASK_WDT:  return "task_wdt";
    case ESP_RST_WDT:       return "other_wdt";
    case ESP_RST_DEEPSLEEP: return "deepsleep";
    case ESP_RST_BROWNOUT:  return "brownout";
    case ESP_RST_SDIO:      return "sdio";
    default:                return "unknown";
  }
}

const char* authModeName(AuthMode m) {
  switch (m) {
    case AUTH_PER_BRIDGE:      return "per_bridge";
    case AUTH_LEGACY:          return "legacy";
    case AUTH_LEGACY_FALLBACK: return "legacy_fallback";
    default:                   return "none";
  }
}

// Wall clock in epoch milliseconds (SNTP-disciplined).
long long epochNowMs() {
  struct timeval tv;
  gettimeofday(&tv, nullptr);
  return (long long)tv.tv_sec * 1000LL + tv.tv_usec / 1000;
}

bool clockValid() {
  struct timeval tv;
  gettimeofday(&tv, nullptr);
  return tv.tv_sec > 1700000000;  // after 2023-11
}

void onNtpSync(struct timeval* tv) {
  g_lastNtpSyncMs = millis();
}

String currentIdToken() {
  xSemaphoreTake(authMutex, portMAX_DELAY);
  String t = firebaseIdToken;
  xSemaphoreGive(authMutex);
  return t;
}

String currentBridgeEmail() {
  xSemaphoreTake(authMutex, portMAX_DELAY);
  String e = activeBridgeEmail;
  xSemaphoreGive(authMutex);
  return e;
}

String currentBridgeUid() {
  xSemaphoreTake(authMutex, portMAX_DELAY);
  String u = reportedBridgeUid;
  xSemaphoreGive(authMutex);
  return u;
}

String currentAuthReason() {
  xSemaphoreTake(authMutex, portMAX_DELAY);
  String r = authModeReason;
  xSemaphoreGive(authMutex);
  return r;
}

bool snapshotPairing(String& uidOut) {
  xSemaphoreTake(stateMutex, portMAX_DELAY);
  uidOut = pairedUserId;
  bool paired = isPaired;
  xSemaphoreGive(stateMutex);
  return paired;
}

void setPairing(const String& uid, bool paired) {
  xSemaphoreTake(stateMutex, portMAX_DELAY);
  pairedUserId = uid;
  isPaired = paired;
  xSemaphoreGive(stateMutex);
}

void setOtaStatus(const String& s) {
  xSemaphoreTake(stateMutex, portMAX_DELAY);
  otaStatus = s;
  xSemaphoreGive(stateMutex);
}

String currentOtaStatus() {
  xSemaphoreTake(stateMutex, portMAX_DELAY);
  String s = otaStatus;
  xSemaphoreGive(stateMutex);
  return s;
}

// Proof of useful work for the supervisor's progress watchdog. A paired
// bridge only counts a successful command-queue query: a heartbeat landing
// while polling is dead is exactly the #109 "looks healthy, executes
// nothing" state.
void noteProgress() {
  g_lastProgressMs = millis();
  if (noProgressRestarts != 0) noProgressRestarts = 0;
  if (rtcNoProgressRestarts != 0) rtcNoProgressRestarts = 0;
}

void restartWithCause(uint32_t cause) {
  rtcRestartCause = cause;
  Serial.printf("[Restart] cause=%s loopPhase=%s hbPhase=%s\n",
                causeName(cause), phaseName(rtcLoopPhase), phaseName(rtcHbPhase));
  Serial.flush();
  delay(200);
  esp_restart();
}

void captureBootDiagnostics() {
  esp_reset_reason_t rr = esp_reset_reason();
  bootResetReason = resetReasonName(rr);
  if (rtcMagic == RTC_DIAG_MAGIC && rr != ESP_RST_POWERON) {
    prevLoopPhase = phaseName(rtcLoopPhase);
    prevHbPhase = phaseName(rtcHbPhase);
    prevRestartCause = causeName(rtcRestartCause);
    noProgressRestarts = rtcNoProgressRestarts;
  } else {
    noProgressRestarts = 0;
  }
  rtcMagic = RTC_DIAG_MAGIC;
  rtcLoopPhase = PH_IDLE;
  rtcHbPhase = PH_IDLE;
  rtcRestartCause = CAUSE_NONE;
  rtcNoProgressRestarts = noProgressRestarts;

  size_t cdAddr = 0, cdSize = 0;
  coreDumpPresent = (esp_core_dump_image_get(&cdAddr, &cdSize) == ESP_OK);

  Serial.printf("[Boot] reset=%s prevCause=%s prevLoopPhase=%s prevHbPhase=%s "
                "noProgressRestarts=%u coreDump=%d\n",
                bootResetReason.c_str(), prevRestartCause.c_str(),
                prevLoopPhase.c_str(), prevHbPhase.c_str(),
                (unsigned)noProgressRestarts, coreDumpPresent ? 1 : 0);
}

unsigned long progressTimeoutMs() {
  uint32_t n = noProgressRestarts;
  if (n > 4) n = 4;
  return BRIDGE_PROGRESS_TIMEOUT_MS << n;
}

// ============================================================================
// Supervisor task — the watchdog loop() cannot block (#109)
// ============================================================================
// Before 1.3.0 the 5-minute check lived inside loop(), so a loop() stuck in
// a call that never returns never reached it (2026-09-16: ICMP alive, HTTP,
// heartbeats and polling dead for 11 min until a power cycle). Two layers
// now sit outside loop():
//   1. the ESP-IDF task watchdog — a hardware timer interrupt that panics and
//      reboots if loopTask, the heartbeat task or this task stops feeding it
//      for BRIDGE_LOOP_WDT_TIMEOUT_S (catches a loop() that never returns);
//   2. this task — reboots if loop() keeps returning but does no useful work
//      (expired token, failing query) for the progress timeout. It runs at a
//      higher priority than loopTask on the same core, so a spinning loop()
//      cannot starve it.

void supervisorTask(void* arg) {
  esp_task_wdt_add(nullptr);
  for (;;) {
    esp_task_wdt_reset();
    if (!g_setupDone) {
      if (millis() > BRIDGE_BOOT_DEADLINE_MS) {
        Serial.println("[Supervisor] setup() did not finish in time");
        restartWithCause(CAUSE_BOOT_DEADLINE);
      }
    } else {
      // Read the progress stamp BEFORE the clock, and compare signed: another
      // task may stamp progress at any moment, and an unsigned now - ref
      // with ref > now would wrap and reboot a healthy bridge.
      unsigned long ref = g_lastProgressMs;
      if (ref == 0) ref = g_setupDoneMs;
      const unsigned long now = millis();
      if ((long)(now - ref) > (long)progressTimeoutMs()) {
        const bool paired = isPaired;
        Serial.printf("[Supervisor] no %s for %lus — restarting\n",
                      paired ? "successful command poll" : "successful Firestore call",
                      (now - ref) / 1000);
        rtcNoProgressRestarts = noProgressRestarts + 1;
        restartWithCause(paired ? CAUSE_NO_POLL : CAUSE_NO_FIRESTORE);
      }
    }
    vTaskDelay(pdMS_TO_TICKS(5000));
  }
}

// ============================================================================
// Setup
// ============================================================================

void startConsoleTask();
void startHeartbeatTask();

void setup() {
  Serial.begin(115200);
  delay(1000);

  Serial.println();
  Serial.println("=========================================");
  Serial.println("   Lumina ESP32 Bridge v" BRIDGE_FIRMWARE_VERSION);
  Serial.println("=========================================");
  // Also keeps the markers the signing tool checks from being discarded.
  Serial.println(kVersionMarker);
  Serial.println(kBoardMarker);
  Serial.println();

  captureBootDiagnostics();

  authMutex = xSemaphoreCreateMutex();
  stateMutex = xSemaphoreCreateMutex();

  // The core arms the task watchdog at 5 s for the idle task; reconfigure it
  // for the bridge's own tasks (ESP-IDF 4.4 updates an initialised TWDT).
  // loopTask is subscribed only at the end of setup() — the captive portal
  // may legitimately block setup() for minutes — and the supervisor's boot
  // deadline covers setup() until then.
  esp_err_t wdtInit = esp_task_wdt_init(BRIDGE_LOOP_WDT_TIMEOUT_S, true);
  xTaskCreatePinnedToCore(supervisorTask, "bridgeSup", 4096, nullptr, 5,
                          &supervisorTaskHandle, 1);
  Serial.printf("[WDT] task watchdog %us (init=%d); supervisor started\n",
                (unsigned)BRIDGE_LOOP_WDT_TIMEOUT_S, (int)wdtInit);

  pinMode(STATUS_LED_PIN, OUTPUT);
  digitalWrite(STATUS_LED_PIN, LOW);

  blinkLed(5, 100);

  // Build device name from MAC
  uint8_t mac[6];
  WiFi.macAddress(mac);
  char suffix[5];
  snprintf(suffix, sizeof(suffix), "%02X%02X", mac[4], mac[5]);
  deviceName += String(suffix);

  // Stable per-chip ID for /bridge_registry/{deviceId}
  char idBuf[13];
  snprintf(idBuf, sizeof(idBuf), "%02X%02X%02X%02X%02X%02X",
           mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
  deviceId = String(idBuf);

  Serial.print("Device name: ");
  Serial.println(deviceName);
  Serial.print("Device ID: ");
  Serial.println(deviceId);

  // Serial provisioning is available from here on — before Wi-Fi, so a
  // bench unit sitting in the captive portal can still be provisioned.
  startConsoleTask();

  // Mark as paired if a user UID is configured
  isPaired = (strlen(FIREBASE_USER_UID) > 0);

  setLoopPhase(PH_SETUP_WIFI);
  setupWiFi();

  // Load NVS-saved pairing values, if any. These override the compile-time
  // defaults so each customer install can be paired at deploy time without
  // a custom firmware build per UID.
  prefs.begin("bridge", false);
  String savedUid = prefs.getString("uid", String(FIREBASE_USER_UID));
  String savedIp = prefs.getString("wledIp", String(DEFAULT_WLED_IP));
  // We consider the UID "from NVS" only when a value was actually stored
  // (i.e. distinct from the compile-time default). isKey() is the precise
  // check; getString-with-default can't distinguish the two cases.
  nvsUidFound = prefs.isKey("uid");
  prefs.end();

  pairedWledIp = savedIp;
  // isPaired requires an actual NVS-stored UID, not just a non-empty default.
  // Defends against the bug class where a non-empty FIREBASE_USER_UID compile-time
  // default would cause fresh bridges to falsely report as paired and self-register
  // with an orphan UID. See Item #47 in MEMORY.md.
  setPairing(savedUid, nvsUidFound && savedUid.length() > 0);

  if (nvsUidFound) {
    Serial.println("[Bridge] Loaded UID from NVS: " + pairedUserId);
    Serial.println("[Bridge] Loaded WLED IP from NVS: " + pairedWledIp);
  } else {
    Serial.println("[Bridge] No NVS data, using compile-time defaults");
    Serial.println("[Bridge] UID: " + pairedUserId);
    Serial.println("[Bridge] WLED IP: " + pairedWledIp);
  }

  setupMDNS();
  setupWebServer();
  setupFirebase();
  otaBootCheck();

  // Self-register in /bridge_registry/{deviceId} so the Lumina app can find
  // this bridge via Firestore — no mDNS or LAN scanning needed. Runs after
  // Firebase Auth so the bridge already has an ID token. If sign-in failed,
  // skip — loop() retries sign-in every 30 s and registers on success.
  if (firebaseReady) {
    setLoopPhase(PH_REGISTRY);
    registerBridgeInRegistry(secureClient, currentIdToken());
  }
  setLoopPhase(PH_IDLE);

  bootTime = millis();

#if BRIDGE_OTA_ENABLED
  // Spread the fleet's checks so a neighbourhood-wide power restore does not
  // pull the image from every bridge in the same minute.
  uint32_t jitter = 0;
#if OTA_CHECK_JITTER_MS > 0
  for (size_t i = 0; i < deviceId.length(); i++) jitter = jitter * 31 + deviceId[i];
  jitter %= OTA_CHECK_JITTER_MS;
#endif
  nextOtaCheckMs = millis() + OTA_FIRST_CHECK_DELAY_MS + jitter;
#endif

  g_setupDoneMs = millis();
  g_lastProgressMs = 0;
  g_setupDone = true;

  startHeartbeatTask();
  enableLoopWDT();

  Serial.println();
  Serial.println("Bridge initialized and ready!");
  Serial.println("Polling for commands...");
  Serial.println();

  digitalWrite(STATUS_LED_PIN, HIGH);
  delay(1000);
  digitalWrite(STATUS_LED_PIN, LOW);
}

// ============================================================================
// Main Loop
// ============================================================================

void fallbackToLegacy(const String& reason);
void selectInitialIdentity();

void loop() {
  g_loopTickMs = millis();

  setLoopPhase(PH_WEB_CLIENT);
  server.handleClient();
  setLoopPhase(PH_IDLE);
  statusBlink();

  // Identity changes requested by other tasks are applied here, the only
  // task that signs in.
  if (g_credReloadRequested) {
    g_credReloadRequested = false;
    selectInitialIdentity();
  }
  if (g_identityFallbackRequested) {
    const char* reason = pendingFallbackReason;
    g_identityFallbackRequested = false;
    fallbackToLegacy(String(reason));
  }

  // Initial sign-in failed (e.g. the internet was down at boot). Before
  // 1.3.0 firebaseReady stayed false forever and nothing retried.
  if (!firebaseReady && WiFi.status() == WL_CONNECTED &&
      (long)(millis() - nextBootSignInRetryMs) >= 0) {
    nextBootSignInRetryMs = millis() + 30000;
    if (signInWithBackoff()) {
      Serial.println("Firebase Auth: signed in on retry");
      firebaseReady = true;
      setLoopPhase(PH_REGISTRY);
      registerBridgeInRegistry(secureClient, currentIdToken());
      setLoopPhase(PH_IDLE);
    }
  }

  otaProbationTick();

  if (millis() - lastPollTime >= POLL_INTERVAL_MS) {
    lastPollTime = millis();

    if (firebaseReady && isPaired && WiFi.status() == WL_CONNECTED) {
      if (ensureValidToken()) {
        esp_task_wdt_reset();
        pollCommands();
      } else {
        DEBUG_PRINTLN("Token refresh failed, skipping poll");
      }
    }
  }

  // While unpaired, poll the registry doc for an app-initiated pairing
  // request. Stops automatically once isPaired becomes true.
  if (!isPaired &&
      millis() - lastPairingPollTime >= PAIRING_POLL_INTERVAL_MS) {
    lastPairingPollTime = millis();
    if (firebaseReady && WiFi.status() == WL_CONNECTED) {
      setLoopPhase(PH_PAIRING_POLL);
      pollPairingRequest();
      setLoopPhase(PH_IDLE);
    }
  }

  // Heartbeat and registry refresh run in heartbeatTask (see below).

  otaMaybeRun();

  delay(10);
}

// ============================================================================
// WiFi Setup
// ============================================================================

void setupWiFi() {
  Serial.println("Setting up WiFi...");

  WiFi.mode(WIFI_STA);
  WiFi.disconnect(true);
  delay(1000);

  // If no hardcoded SSID, use WiFiManager captive portal
  if (strlen(WIFI_SSID) == 0) {
    Serial.println("No WiFi credentials configured — starting captive portal");
    Serial.print("Connect to AP: ");
    Serial.println(deviceName);

    WiFiManager wm;
    wm.setConfigPortalTimeout(300); // 5 min timeout, then reboot
    wm.setAPCallback([](WiFiManager* wm) {
      Serial.println("Captive portal started");
      blinkLed(3, 200);
    });

    if (!wm.autoConnect(deviceName.c_str())) {
      Serial.println("WiFi config timed out — rebooting");
      delay(3000);
      restartWithCause(CAUSE_WIFI_SETUP);
    }
  } else {
    Serial.print("Connecting to ");
    Serial.println(WIFI_SSID);

    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

    int attempts = 0;
    while (WiFi.status() != WL_CONNECTED && attempts < 40) {
      delay(500);
      Serial.print(".");
      Serial.print(WiFi.status());
      attempts++;
    }

    if (WiFi.status() != WL_CONNECTED) {
      Serial.println();
      Serial.print("Failed! WiFi status: ");
      Serial.println(WiFi.status());
      Serial.println("Restarting in 5 seconds...");
      delay(5000);
      restartWithCause(CAUSE_WIFI_SETUP);
    }
  }

  Serial.println();
  Serial.print("Connected! IP: ");
  Serial.println(WiFi.localIP());
}

// ============================================================================
// mDNS Setup — advertise _lumina._tcp so the app can discover us
// ============================================================================

void setupMDNS() {
  String hostname = deviceName;
  hostname.toLowerCase();

  if (MDNS.begin(hostname.c_str())) {
    // Advertise _lumina._tcp for bridge discovery
    MDNS.addService("lumina", "tcp", 80);
    // Also advertise _http._tcp as fallback
    MDNS.addService("http", "tcp", 80);
    Serial.print("mDNS started: ");
    Serial.print(hostname);
    Serial.println(".local");
  } else {
    Serial.println("mDNS failed to start");
  }
}

// ============================================================================
// Local Web Server — API endpoints for app pairing/status
// ============================================================================

#ifdef BRIDGE_BENCH
void handleBenchState();
#endif

void setupWebServer() {
  server.on("/api/info", HTTP_GET, handleApiInfo);
  server.on("/api/bridge/status", HTTP_GET, handleBridgeStatus);
  server.on("/api/bridge/pair", HTTP_POST, handleBridgePair);
  server.on("/api/bridge/auth", HTTP_POST, handleBridgeAuth);
  server.on("/api/reboot", HTTP_POST, handleReboot);
  server.on("/api/reset", HTTP_POST, handleReset);
  // Asks for an OTA check at the next idle moment. Harmless on an open LAN:
  // it can only install a newer image signed with the OTA key.
  server.on("/api/ota/check", HTTP_POST, handleOtaCheck);
#ifdef BRIDGE_BENCH
  // BENCH-ONLY routes. The release esp32dev image does not contain them;
  // tools/sign_firmware.py refuses to sign an image that does unless told
  // --allow-bench.
  server.on("/api/debug/block-loop", HTTP_POST, []() {
    server.send(200, "application/json", "{\"blocking\":\"loop\"}");
    Serial.println("[BENCH] blocking loop() forever");
    setLoopPhase(PH_WEB_CLIENT);
    for (;;) delay(1000);
  });
  server.on("/api/debug/block-heartbeat", HTTP_POST, []() {
    g_benchBlockHeartbeat = true;
    server.send(200, "application/json", "{\"blocking\":\"heartbeat\"}");
  });
  server.on("/api/debug/fail-poll", HTTP_POST, []() {
    g_benchFailPoll = true;
    server.send(200, "application/json", "{\"failing\":\"poll\"}");
  });
  server.on("/api/debug/state", HTTP_GET, handleBenchState);
#endif
  server.onNotFound(handleNotFound);

  server.begin();
  Serial.println("HTTP server started on port 80");
}

void handleApiInfo() {
  JsonDocument doc;
  doc["name"] = deviceName;
  doc["version"] = BRIDGE_FIRMWARE_VERSION;
  doc["type"] = "bridge";
  doc["ip"] = WiFi.localIP().toString();
  doc["mdns"] = deviceName + ".local";
  doc["ap"] = deviceName;
  // Stable per-chip ID — the app uses this to look up this bridge in
  // /bridge_registry without needing to know the IP or hostname.
  doc["deviceId"] = deviceId;
  doc["savedSSID"] = String(WIFI_SSID);
  // "nvs" → bridge has been paired by the app and the UID was loaded from
  // flash; "default" → no pairing on file, running on compile-time defaults.
  // The setup wizard uses this to decide whether the bridge needs initial pairing.
  doc["pairingSource"] = nvsUidFound ? "nvs" : "default";
  // Self-declare the Firebase Auth email this bridge signs in with. The
  // wizard writes this into the user's bridge_email field so Firestore
  // rules can grant the bridge read/write on the user's commands. Since
  // 1.3.0 it is the ACTIVE identity — the per-bridge account once
  // provisioned — so whatever the app records is what the bridge presents.
  doc["bridgeEmail"] = currentBridgeEmail();
  doc["bridgeUid"] = currentBridgeUid();
  doc["authMode"] = authModeName(authMode);
  doc["otaEnabled"] = (bool)BRIDGE_OTA_ENABLED;
  doc["otaChannel"] = OTA_CHANNEL;

  String body;
  serializeJson(doc, body);
  server.send(200, "application/json", body);
}

void handleBridgeStatus() {
  JsonDocument doc;
  doc["paired"] = (bool)isPaired;
  doc["authenticated"] = (bool)firebaseAuthenticated;
  doc["wifi"] = (WiFi.status() == WL_CONNECTED);
  doc["userId"] = pairedUserId;
  doc["wledIp"] = pairedWledIp;
  doc["commands"] = (unsigned long)commandsProcessed;
  doc["errors"] = (unsigned long)commandErrors;
  doc["uptime"] = (millis() - bootTime) / 1000;
  doc["version"] = BRIDGE_FIRMWARE_VERSION;
  doc["authMode"] = authModeName(authMode);
  doc["ota"] = currentOtaStatus();

  String body;
  serializeJson(doc, body);
  server.send(200, "application/json", body);
}

void handleBridgePair() {
  if (!server.hasArg("plain")) {
    server.send(400, "application/json", "{\"error\":\"No body\"}");
    return;
  }

  JsonDocument doc;
  DeserializationError error = deserializeJson(doc, server.arg("plain"));
  if (error) {
    server.send(400, "application/json", "{\"error\":\"Invalid JSON\"}");
    return;
  }

  String userId = doc["userId"] | "";
  String wledIp = doc["wledIp"] | "";

  if (userId.isEmpty()) {
    server.send(400, "application/json", "{\"error\":\"userId required\"}");
    return;
  }

  if (!wledIp.isEmpty()) {
    pairedWledIp = wledIp;
  }
  setPairing(userId, true);
  // A fresh pairing starts a fresh progress window.
  noteProgress();

  // Persist to NVS so the values survive reboots — without this every
  // power cycle reverts to the compile-time FIREBASE_USER_UID macro.
  prefs.begin("bridge", false);
  prefs.putString("uid", pairedUserId);
  prefs.putString("wledIp", pairedWledIp);
  prefs.end();
  nvsUidFound = true;

  Serial.println("[Bridge] Paired and saved to NVS");
  Serial.println("[Bridge] UID: " + pairedUserId);
  Serial.println("[Bridge] WLED IP: " + pairedWledIp);

  server.send(200, "application/json", "{\"ok\":true}");
}

// /api/bridge/auth — confirms the bridge is paired to the requesting UID.
// Body: {"userId": "<firebase-uid>"}
//   200 {"ok":true,"uid":...}    → match, this bridge is the caller's
//   403 {"ok":false,"error":...}  → paired to a different account
//   400 {"ok":false,"error":...}  → malformed body or missing userId
void handleBridgeAuth() {
  if (!server.hasArg("plain")) {
    server.send(400, "application/json", "{\"ok\":false,\"error\":\"No body\"}");
    return;
  }

  JsonDocument doc;
  DeserializationError error = deserializeJson(doc, server.arg("plain"));
  if (error) {
    server.send(400, "application/json", "{\"ok\":false,\"error\":\"Invalid JSON\"}");
    return;
  }

  String requestedUid = doc["userId"] | "";

  if (requestedUid.isEmpty()) {
    server.send(400, "application/json", "{\"ok\":false,\"error\":\"userId required\"}");
    return;
  }

  if (pairedUserId != requestedUid) {
    server.send(403, "application/json",
        "{\"ok\":false,\"error\":\"bridge paired to different account\"}");
    return;
  }

  server.send(200, "application/json",
      "{\"ok\":true,\"uid\":\"" + pairedUserId + "\"}");
}

void handleReboot() {
  server.send(200, "application/json", "{\"ok\":true}");
  delay(500);
  restartWithCause(CAUSE_API_REBOOT);
}

void handleReset() {
  // Clear all NVS-stored pairing so the bridge boots fresh on next start.
  // The per-bridge credential lives in its own namespace ("bcred") and is
  // deliberately kept: moving a bridge to another house must not strip it
  // of its identity.
  prefs.begin("bridge", false);
  prefs.clear();
  prefs.end();

  Serial.println("[Bridge] Factory reset — NVS cleared, rebooting");

  server.send(200, "application/json",
              "{\"ok\":true,\"message\":\"Resetting...\"}");
  delay(500);
  restartWithCause(CAUSE_API_RESET);
}

void handleOtaCheck() {
  g_otaCheckRequested = true;
  server.send(200, "application/json",
              BRIDGE_OTA_ENABLED ? "{\"ok\":true,\"ota\":\"check_scheduled\"}"
                                 : "{\"ok\":false,\"ota\":\"disabled\"}");
}

void handleNotFound() {
  server.send(404, "application/json", "{\"error\":\"Not found\"}");
}

// ============================================================================
// Firebase Setup & Auth
// ============================================================================

bool legacyAvailable() {
  return BRIDGE_LEGACY_SHARED_AUTH && strlen(FIREBASE_AUTH_EMAIL) > 0 &&
         strlen(FIREBASE_AUTH_PASSWORD) > 0;
}

// Per-bridge credential (#5). Stored by the serial console under NVS
// namespace "bcred", which /api/reset does not clear. The uid must be
// bridge_<this chip's deviceId>, so a credential flashed onto the wrong
// unit is ignored rather than used.
bool loadPerBridgeCredential() {
  Preferences p;
  if (!p.begin("bcred", true)) return false;  // namespace absent → none
  String uid = p.getString("uid", "");
  String email = p.getString("email", "");
  String pass = p.getString("pass", "");
  p.end();
  if (uid != expectedBridgeUid() || email.isEmpty() || pass.isEmpty()) {
    if (!uid.isEmpty() && uid != expectedBridgeUid()) {
      Serial.println("[Auth] Stored credential is for a different device — ignored");
    }
    return false;
  }
  perBridgeUid = uid;
  perBridgeEmail = email;
  perBridgePassword = pass;
  return true;
}

void setIdentity(AuthMode mode, const String& reason) {
  xSemaphoreTake(authMutex, portMAX_DELAY);
  authMode = mode;
  authModeReason = reason;
  reportedBridgeUid = perBridgeCredPresent ? perBridgeUid : String("");
  if (mode == AUTH_PER_BRIDGE) {
    activeBridgeEmail = perBridgeEmail;
  } else if (mode == AUTH_LEGACY || mode == AUTH_LEGACY_FALLBACK) {
    activeBridgeEmail = String(FIREBASE_AUTH_EMAIL);
  } else {
    activeBridgeEmail = "";
  }
  // Force a fresh sign-in as the new identity on the next ensureValidToken().
  firebaseIdToken = "";
  firebaseRefreshToken = "";
  tokenExpiresAt = 0;
  xSemaphoreGive(authMutex);
  nextSignInAllowedMs = millis();
  perBridgeDeniedSinceMs = 0;
  Serial.printf("[Auth] identity=%s%s%s\n", authModeName(mode),
                reason.isEmpty() ? "" : " reason=", reason.c_str());
}

void selectInitialIdentity() {
  perBridgeCredPresent = loadPerBridgeCredential();
  if (perBridgeCredPresent) {
    setIdentity(AUTH_PER_BRIDGE, "");
  } else if (legacyAvailable()) {
    setIdentity(AUTH_LEGACY, "no_per_bridge_credential");
  } else {
    setIdentity(AUTH_NONE, "no_credential");
  }
}

// Called on loopTask only. A per-bridge identity that is refused falls back
// to the shared account for the rest of this boot, so a bridge whose user
// still delegates to the shared account keeps working. The next boot tries
// the per-bridge identity again — the user doc decides, the bridge follows.
void fallbackToLegacy(const String& reason) {
  if (authMode != AUTH_PER_BRIDGE || !legacyAvailable()) return;
  setIdentity(AUTH_LEGACY_FALLBACK, reason);
}

void requestFallbackFromOtherTask(const char* reason) {
  if (authMode != AUTH_PER_BRIDGE || g_identityFallbackRequested) return;
  pendingFallbackReason = reason;  // a string literal: no allocation to race on
  g_identityFallbackRequested = true;
}

void setupFirebase() {
  Serial.println("Setting up Firebase connection...");

  // SSL configuration for ESP32
  secureClient.setInsecure();
  secureClient.setHandshakeTimeout(30);
  secureClient.setTimeout(15);

  // Sync time for timestamps and for the Neighborhood Sync timebase. The
  // notification callback records each sync so the heartbeat can report
  // clock freshness. This wait is bounded by the supervisor's boot deadline.
  setLoopPhase(PH_SETUP_NTP);
  sntp_set_sync_interval(SNTP_SYNC_INTERVAL_MS);
  sntp_set_time_sync_notification_cb(onNtpSync);
  configTime(0, 0, "pool.ntp.org", "time.nist.gov");
  Serial.print("Syncing time");
  time_t now = time(nullptr);
  while (now < 8 * 3600 * 2) {
    delay(500);
    Serial.print(".");
    now = time(nullptr);
  }
  Serial.println(" Done!");

  Serial.print("Free heap: ");
  Serial.println(ESP.getFreeHeap());

  selectInitialIdentity();

  // Sign in to Firebase Auth
  setLoopPhase(PH_SIGNIN);
  if (signInFirebase()) {
    Serial.println("Firebase Auth: signed in successfully");
    firebaseReady = true;
    firebaseAuthenticated = true;
  } else {
    Serial.println("Firebase Auth: FAILED to sign in");
    Serial.println("Bridge will retry every 30 s");
    firebaseAuthenticated = false;
    nextBootSignInRetryMs = millis() + 30000;
  }
  setLoopPhase(PH_IDLE);
}

static bool isCredentialRejection(const String& msg) {
  return msg.startsWith("EMAIL_NOT_FOUND") || msg.startsWith("INVALID_PASSWORD") ||
         msg.startsWith("INVALID_LOGIN_CREDENTIALS") || msg.startsWith("INVALID_EMAIL");
}

/**
 * Sign in to Firebase Auth using email/password.
 * Returns the ID token needed for authenticated Firestore access.
 * loopTask only.
 */
bool signInFirebase() {
  const AuthMode mode = authMode;
  if (mode == AUTH_NONE) {
    Serial.println("Signing in to Firebase... no credential available");
    firebaseAuthenticated = false;
    return false;
  }
  Serial.printf("Signing in to Firebase as %s...\n", authModeName(mode));

  const String email =
      (mode == AUTH_PER_BRIDGE) ? perBridgeEmail : String(FIREBASE_AUTH_EMAIL);
  const String password =
      (mode == AUTH_PER_BRIDGE) ? perBridgePassword : String(FIREBASE_AUTH_PASSWORD);

  uint32_t prevPhase = rtcLoopPhase;
  setLoopPhase(PH_SIGNIN);

  HTTPClient http;
  String url = "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=" +
               String(FIREBASE_API_KEY);

  JsonDocument doc;
  doc["email"] = email;
  doc["password"] = password;
  doc["returnSecureToken"] = true;

  String body;
  serializeJson(doc, body);

  http.begin(secureClient, url);
  http.addHeader("Content-Type", "application/json");

  int httpCode = http.POST(body);
  setLoopPhase(prevPhase);

  if (httpCode == 200) {
    String response = http.getString();
    http.end();

    JsonDocument respDoc;
    DeserializationError error = deserializeJson(respDoc, response);
    if (error) {
      Serial.print("Auth JSON parse error: ");
      Serial.println(error.c_str());
      return false;
    }

    // A per-bridge credential must belong to THIS chip's account.
    if (mode == AUTH_PER_BRIDGE &&
        respDoc["localId"].as<String>() != expectedBridgeUid()) {
      Serial.println("  Per-bridge credential signed in as a different uid");
      if (legacyAvailable()) {
        setIdentity(AUTH_LEGACY_FALLBACK, "uid_mismatch");
        return signInFirebase();
      }
      firebaseAuthenticated = false;
      return false;
    }

    int expiresIn = respDoc["expiresIn"].as<String>().toInt();

    xSemaphoreTake(authMutex, portMAX_DELAY);
    firebaseIdToken = respDoc["idToken"].as<String>();
    firebaseRefreshToken = respDoc["refreshToken"].as<String>();
    // Set expiry 5 minutes early to avoid edge cases
    tokenExpiresAt = millis() + ((unsigned long)expiresIn - 300) * 1000UL;
    xSemaphoreGive(authMutex);

    firebaseAuthenticated = true;

    Serial.print("  Token obtained, expires in ");
    Serial.print(expiresIn);
    Serial.println("s");
    return true;
  } else {
    String response = http.getString();
    http.end();
    Serial.print("  Auth failed: HTTP ");
    Serial.print(httpCode);
    Serial.print(" - ");
    Serial.println(response.substring(0, 200));
    firebaseAuthenticated = false;

    // A per-bridge credential the server does not recognise (never created,
    // wrong password) → keep the house working on the shared account while
    // it still exists. USER_DISABLED is a deliberate revocation: no fallback.
    if (mode == AUTH_PER_BRIDGE && httpCode == 400 && legacyAvailable()) {
      JsonDocument errDoc;
      if (!deserializeJson(errDoc, response)) {
        String msg = errDoc["error"]["message"].as<String>();
        if (isCredentialRejection(msg)) {
          setIdentity(AUTH_LEGACY_FALLBACK, "signin_" + msg.substring(0, 32));
          return signInFirebase();
        }
      }
    }
    return false;
  }
}

// Sign-in with a 15 s back-off after a failure, so a broken or revoked
// credential does not hit the Auth endpoint on every 1 s poll tick.
bool signInWithBackoff() {
  if ((long)(millis() - nextSignInAllowedMs) < 0) return false;
  if (signInFirebase()) return true;
  nextSignInAllowedMs = millis() + 15000;
  return false;
}

/**
 * Refresh the Firebase ID token using the refresh token. loopTask only.
 */
bool refreshFirebaseToken() {
  DEBUG_PRINTLN("Refreshing Firebase token...");

  xSemaphoreTake(authMutex, portMAX_DELAY);
  String refreshToken = firebaseRefreshToken;
  xSemaphoreGive(authMutex);
  if (refreshToken.isEmpty()) return signInWithBackoff();

  uint32_t prevPhase = rtcLoopPhase;
  setLoopPhase(PH_TOKEN_REFRESH);

  HTTPClient http;
  String url = "https://securetoken.googleapis.com/v1/token?key=" +
               String(FIREBASE_API_KEY);

  String body = "grant_type=refresh_token&refresh_token=" + refreshToken;

  http.begin(secureClient, url);
  http.addHeader("Content-Type", "application/x-www-form-urlencoded");

  int httpCode = http.POST(body);
  setLoopPhase(prevPhase);

  if (httpCode == 200) {
    String response = http.getString();
    http.end();

    JsonDocument respDoc;
    DeserializationError error = deserializeJson(respDoc, response);
    if (error) {
      DEBUG_PRINT("Refresh JSON parse error: ");
      DEBUG_PRINTLN(error.c_str());
      return false;
    }

    int expiresIn = respDoc["expires_in"].as<String>().toInt();

    xSemaphoreTake(authMutex, portMAX_DELAY);
    firebaseIdToken = respDoc["id_token"].as<String>();
    firebaseRefreshToken = respDoc["refresh_token"].as<String>();
    tokenExpiresAt = millis() + ((unsigned long)expiresIn - 300) * 1000UL;
    xSemaphoreGive(authMutex);
    firebaseAuthenticated = true;

    DEBUG_PRINTLN("  Token refreshed");
    return true;
  } else {
    http.end();
    DEBUG_PRINT("  Token refresh failed: HTTP ");
    DEBUG_PRINTLN(httpCode);
    // Fall back to full re-sign-in
    return signInWithBackoff();
  }
}

/**
 * Ensure we have a valid (non-expired) Firebase ID token. loopTask only —
 * the heartbeat task uses whatever token is current and never refreshes.
 */
bool ensureValidToken() {
  xSemaphoreTake(authMutex, portMAX_DELAY);
  bool empty = firebaseIdToken.isEmpty();
  unsigned long expiresAt = tokenExpiresAt;
  xSemaphoreGive(authMutex);

  if (empty) {
    return signInWithBackoff();
  }
  if ((long)(millis() - expiresAt) >= 0) {
    return refreshFirebaseToken();
  }
  return true;
}

// ============================================================================
// Command Polling
// ============================================================================

void pollCommands() {
  DEBUG_PRINTLN("Polling for commands...");

#ifdef BRIDGE_BENCH
  if (g_benchFailPoll) {
    DEBUG_PRINTLN("[BENCH] poll forced to fail");
    commandErrors++;
    return;
  }
#endif

  HTTPClient http;
  String url = firestoreBaseUrl() + ":runQuery";

  // Build query: SELECT * FROM commands WHERE status == "pending" LIMIT 5
  JsonDocument queryDoc;
  queryDoc["structuredQuery"]["from"][0]["collectionId"] = "commands";
  queryDoc["structuredQuery"]["where"]["fieldFilter"]["field"]["fieldPath"] = "status";
  queryDoc["structuredQuery"]["where"]["fieldFilter"]["op"] = "EQUAL";
  queryDoc["structuredQuery"]["where"]["fieldFilter"]["value"]["stringValue"] = "pending";
  queryDoc["structuredQuery"]["limit"] = MAX_COMMANDS_PER_POLL;

  String queryBody;
  serializeJson(queryDoc, queryBody);

  setLoopPhase(PH_POLL_QUERY);
  http.begin(secureClient, url);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("Authorization", "Bearer " + currentIdToken());

  int httpCode = http.POST(queryBody);

  if (httpCode == 200) {
    String response = http.getString();
    http.end();
    setLoopPhase(PH_IDLE);
    esp_task_wdt_reset();

    // The query itself succeeded: the poll path is alive.
    g_lastPollOkMs = millis();
    perBridgeDeniedSinceMs = 0;
    noteProgress();

    JsonDocument doc;
    DeserializationError error = deserializeJson(doc, response);

    if (error) {
      DEBUG_PRINT("JSON parse error: ");
      DEBUG_PRINTLN(error.c_str());
      return;
    }

    JsonArray results = doc.as<JsonArray>();
    int pendingCount = 0;

    for (JsonObject result : results) {
      JsonObject document = result["document"];
      if (document.isNull()) continue;

      pendingCount++;
      digitalWrite(STATUS_LED_PIN, HIGH);

      const char* docName = document["name"];
      String fullPath = String(docName);
      int lastSlash = fullPath.lastIndexOf('/');
      String commandId = fullPath.substring(lastSlash + 1);

      JsonObject fields = document["fields"];
      executeCommand(commandId, fields);
      // Feed the task watchdog between commands — each command is bounded
      // by its own network timeouts (see BRIDGE_LOOP_WDT_TIMEOUT_S).
      esp_task_wdt_reset();

      digitalWrite(STATUS_LED_PIN, LOW);
    }

    if (pendingCount == 0) {
      DEBUG_PRINTLN("No pending commands");
    } else {
      DEBUG_PRINTF("Processed %d command(s)\n", pendingCount);
    }
  } else if (httpCode == 401 || httpCode == 403) {
    http.end();
    setLoopPhase(PH_IDLE);
    Serial.print("Auth error on poll (HTTP ");
    Serial.print(httpCode);
    Serial.println("), refreshing token...");
    // Per-bridge identity refused by the user's queue for long enough that it
    // is not the pairing window (the app writes bridge_email seconds after
    // the bridge confirms) → this user still delegates to the shared
    // account. Switch; the next tick signs in as it.
    if (httpCode == 403 && authMode == AUTH_PER_BRIDGE && legacyAvailable()) {
      if (perBridgeDeniedSinceMs == 0) {
        perBridgeDeniedSinceMs = millis();
      } else if (millis() - perBridgeDeniedSinceMs > PER_BRIDGE_DENIED_SWITCH_MS) {
        fallbackToLegacy("user_queue_denied");
        return;
      }
    }
    refreshFirebaseToken();
  } else {
    DEBUG_PRINT("HTTP error: ");
    DEBUG_PRINTLN(httpCode);
    http.end();
    setLoopPhase(PH_IDLE);
    commandErrors++;
  }
}

// ============================================================================
// Neighborhood Sync timebase (#3)
// ============================================================================
// A command carrying tbEpochMs asks the bridge to stamp WLED's effect
// timebase at the moment it executes, so a moving effect is in phase across
// houses: tb = (this bridge's NTP clock now) − tbEpochMs, the same shared
// epoch for every house in the fire. Firmware older than 1.3.0 ignores the
// field and applies without alignment, exactly as before.
//
// Two WLED facts (bench-verified 2026-09-22) shape this:
//   • a tb in the same POST that turns a dark strip on is discarded
//     (stateUpdated → resetTimebase), so tb goes in a SEPARATE bare POST;
//   • WLED parses tb as a signed 32-bit long, so tb must be in [0, 2^31) —
//     never raw epoch milliseconds.

struct TbStamp {
  bool requested = false;
  bool ok = false;
  long long tb = 0;
  long long stampedAtMs = 0;
  String error;
};

void stampTimebase(const String& controllerIp, long long epochMs, TbStamp& out) {
  out.requested = true;
  if (!clockValid()) {
    out.error = "clock_unsynced";
    return;
  }

  delay(TB_FOLLOWUP_DELAY_MS);
  setLoopPhase(PH_TB_STAMP);

  String host = controllerIp;
  uint16_t port = 80;
  int colon = host.indexOf(':');
  if (colon > 0) {
    port = (uint16_t)host.substring(colon + 1).toInt();
    host = host.substring(0, colon);
  }

  // Raw request so tb is computed AFTER the TCP connect — a dropped SYN
  // retried by the stack would otherwise add a second of phase error.
  WiFiClient c;
  c.setTimeout(5);
  if (!c.connect(host.c_str(), port, 5000)) {
    out.error = "connect_failed";
    setLoopPhase(PH_IDLE);
    return;
  }

  const long long now = epochNowMs();
  const long long tb = now - epochMs;
  if (tb < 0 || tb >= 2147483648LL) {
    c.stop();
    out.error = "tb_out_of_range";
    setLoopPhase(PH_IDLE);
    return;
  }

  char body[40];
  snprintf(body, sizeof(body), "{\"tb\":%lld}", tb);
  String req = "POST /json/state HTTP/1.1\r\nHost: " + host +
               "\r\nContent-Type: application/json\r\nContent-Length: " +
               String(strlen(body)) + "\r\nConnection: close\r\n\r\n" + body;
  c.print(req);

  String statusLine = "";
  unsigned long start = millis();
  while (millis() - start < 5000) {
    if (c.available()) {
      statusLine = c.readStringUntil('\n');
      break;
    }
    delay(2);
  }
  c.stop();
  setLoopPhase(PH_IDLE);

  if (statusLine.startsWith("HTTP/1.1 200") || statusLine.startsWith("HTTP/1.0 200")) {
    out.ok = true;
    out.tb = tb;
    out.stampedAtMs = now;
  } else {
    out.error = statusLine.isEmpty() ? String("no_response")
                                     : "http_" + statusLine.substring(9, 12);
  }
}

// ============================================================================
// Command Execution
// ============================================================================

void executeCommand(const String& commandId, JsonObject& fields) {
  Serial.println();
  Serial.print("Executing command: ");
  Serial.println(commandId);
  lastCommandExecutedMs = millis();

  String commandType = "";
  String controllerIp = "";

  if (fields["type"]["stringValue"]) {
    commandType = fields["type"]["stringValue"].as<String>();
  }

  if (fields["controllerIp"]["stringValue"]) {
    controllerIp = fields["controllerIp"]["stringValue"].as<String>();
  }

  Serial.print("  Type: ");
  Serial.println(commandType);
  Serial.print("  Controller IP: ");
  Serial.println(controllerIp);

  // Handle ping command — no WLED request needed, just acknowledge
  if (commandType == "ping") {
    Serial.println("  PING — acknowledging");
    updateCommandStatus(commandId, "completed");
    commandsProcessed++;
    return;
  }

  // Ask for an OTA check at the next idle moment (it can only install an
  // image signed with the OTA key). Old firmware POSTs "{}" to WLED instead.
  if (commandType == "otaCheck") {
    g_otaCheckRequested = true;
    updateCommandStatus(commandId, "completed", "",
                        BRIDGE_OTA_ENABLED ? "{\"ota\":\"check_scheduled\"}"
                                           : "{\"ota\":\"disabled\"}");
    commandsProcessed++;
    return;
  }

  if (controllerIp.isEmpty()) {
    controllerIp = pairedWledIp;
    Serial.print("  Using paired WLED IP: ");
    Serial.println(controllerIp);
  }

  if (controllerIp.isEmpty()) {
    Serial.println("  ERROR: No controller IP specified");
    updateCommandStatus(commandId, "failed", "No controller IP specified");
    commandErrors++;
    return;
  }

  updateCommandStatus(commandId, "executing");

  String endpoint;
  String method;
  String body = "";

  if (commandType == "getState") {
    endpoint = "/json/state";
    method = "GET";
  } else if (commandType == "getInfo") {
    endpoint = "/json/info";
    method = "GET";
  } else {
    endpoint = "/json/state";
    method = "POST";
    body = convertFirestorePayloadToJson(fields);
  }

  Serial.print("  -> ");
  Serial.print(method);
  Serial.print(" http://");
  Serial.print(controllerIp);
  Serial.println(endpoint);

  setLoopPhase(PH_WLED_HTTP);
  String response = makeWledRequest(controllerIp, method, endpoint, body);
  setLoopPhase(PH_IDLE);

  if (response.startsWith("ERROR:")) {
    Serial.print("  ERROR: ");
    Serial.println(response);
    updateCommandStatus(commandId, "failed", response);
    commandErrors++;
  } else {
    TbStamp tb;
    if (method == "POST" && fields["tbEpochMs"]["integerValue"]) {
      const char* raw = fields["tbEpochMs"]["integerValue"];
      long long epochMs = strtoll(raw, nullptr, 10);
      if (epochMs > 0) {
        stampTimebase(controllerIp, epochMs, tb);
        Serial.printf("  tb: %s %lld%s%s\n", tb.ok ? "stamped" : "NOT stamped",
                      tb.tb, tb.error.isEmpty() ? "" : " ", tb.error.c_str());
      }
    }
    Serial.println("  SUCCESS!");
    updateCommandStatus(commandId, "completed", "", response,
                        tb.requested ? &tb : nullptr);
    commandsProcessed++;
  }
}

// ============================================================================
// Convert Firestore Payload to WLED JSON
// ============================================================================

String convertFirestorePayloadToJson(JsonObject& fields) {
  if (fields["payload"]["stringValue"]) {
    String payloadStr = fields["payload"]["stringValue"].as<String>();
    DEBUG_PRINT("  Payload (string): ");
    DEBUG_PRINTLN(payloadStr);
    return payloadStr;
  }

  JsonObject payload = fields["payload"]["mapValue"]["fields"];
  if (payload.isNull()) {
    return "{}";
  }

  JsonDocument doc;

  for (JsonPair kv : payload) {
    const char* key = kv.key().c_str();
    JsonObject val = kv.value().as<JsonObject>();

    if (val["booleanValue"]) {
      doc[key] = val["booleanValue"].as<bool>();
    } else if (val["integerValue"]) {
      doc[key] = val["integerValue"].as<int>();
    } else if (val["doubleValue"]) {
      doc[key] = val["doubleValue"].as<double>();
    } else if (val["stringValue"]) {
      doc[key] = val["stringValue"].as<String>();
    }
  }

  String result;
  serializeJson(doc, result);
  return result;
}

// ============================================================================
// HTTP Request to WLED
// ============================================================================

String makeWledRequest(const String& ip, const String& method,
                       const String& endpoint, const String& body) {
  HTTPClient http;
  String url = "http://" + ip + endpoint;

  DEBUG_PRINT("HTTP Request: ");
  DEBUG_PRINT(method);
  DEBUG_PRINT(" ");
  DEBUG_PRINTLN(url);

  http.begin(url);
  http.setTimeout(WLED_HTTP_TIMEOUT_MS);
  http.addHeader("Content-Type", "application/json");

  int httpCode;
  if (method == "GET") {
    httpCode = http.GET();
  } else if (method == "POST") {
    DEBUG_PRINT("Body: ");
    DEBUG_PRINTLN(body);
    httpCode = http.POST(body);
  } else {
    http.end();
    return "ERROR: Unsupported method";
  }

  if (httpCode > 0 && (httpCode == 200 || httpCode == HTTP_CODE_OK)) {
    String response = http.getString();
    http.end();
    return response;
  } else {
    String error = "ERROR: HTTP " + String(httpCode);
    http.end();
    return error;
  }
}

// ============================================================================
// Update Command Status in Firestore
// ============================================================================

void updateCommandStatus(const String& commandId, const String& status,
                         const String& error, const String& result,
                         const TbStamp* tb) {
  HTTPClient http;
  String url = firestoreBaseUrl() + "/commands/" + commandId +
               "?updateMask.fieldPaths=status";

  JsonDocument doc;
  doc["fields"]["status"]["stringValue"] = status;

  if (status == "completed" || status == "failed") {
    time_t now = time(nullptr);
    char timestamp[30];
    strftime(timestamp, sizeof(timestamp), "%Y-%m-%dT%H:%M:%SZ", gmtime(&now));
    doc["fields"]["completedAt"]["timestampValue"] = timestamp;
    url += "&updateMask.fieldPaths=completedAt";
  }

  if (!error.isEmpty()) {
    doc["fields"]["error"]["stringValue"] = error;
    url += "&updateMask.fieldPaths=error";
  }

  if (!result.isEmpty()) {
    doc["fields"]["result"]["stringValue"] = result;
    url += "&updateMask.fieldPaths=result";
  }

  // Timebase outcome, so the fire record can say which houses are in phase.
  if (tb != nullptr && tb->requested) {
    if (tb->ok) {
      char num[24];
      snprintf(num, sizeof(num), "%lld", tb->tb);
      doc["fields"]["tb"]["integerValue"] = num;
      snprintf(num, sizeof(num), "%lld", tb->stampedAtMs);
      doc["fields"]["tbStampedAtMs"]["integerValue"] = num;
      url += "&updateMask.fieldPaths=tb&updateMask.fieldPaths=tbStampedAtMs";
    } else {
      doc["fields"]["tbError"]["stringValue"] = tb->error;
      url += "&updateMask.fieldPaths=tbError";
    }
  }

  String body;
  serializeJson(doc, body);

  uint32_t prevPhase = rtcLoopPhase;
  setLoopPhase(PH_CMD_STATUS);
  http.begin(secureClient, url);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("Authorization", "Bearer " + currentIdToken());

  int httpCode = http.PATCH(body);
  setLoopPhase(prevPhase);

  if (httpCode == 200) {
    DEBUG_PRINTLN("Status updated");
  } else {
    DEBUG_PRINT("Status update failed: ");
    DEBUG_PRINTLN(httpCode);
    commandErrors++;
  }

  http.end();
}

// ============================================================================
// Heartbeat task — writes bridge status to Firestore every 30 s (#2)
// ============================================================================
// Before 1.3.0 the two heartbeat PATCHes (each a TLS round trip of ~1.5 s)
// ran inside loop(), so for ~5–6 s of every 30 s no command was picked up
// (measured 2026-09-23: write→light 5.7 / 7.0 s vs 2.3–3.4 s otherwise, the
// largest source of house-to-house Sync spread). This task owns its own TLS
// client and runs beside the poll loop on the other core.
//
// It writes only while the poll loop has recently succeeded (paired) or is
// ticking (unpaired). A fresh heartbeat therefore still means commands are
// being picked up, and a bridge whose polling died goes visibly stale — it
// no longer looks healthy while executing nothing (#109 stall path B).
// It never refreshes the token: loopTask owns sign-in; an expired token
// here just fails the write.

bool writeHeartbeat(WiFiClientSecure& client, const String& token,
                    const String& uid) {
  DEBUG_PRINTLN("Writing heartbeat...");

  HTTPClient http;
  String url = userDocUrl(uid) + "/bridge_status/current"
               "?updateMask.fieldPaths=uptime"
               "&updateMask.fieldPaths=ip"
               "&updateMask.fieldPaths=commands"
               "&updateMask.fieldPaths=errors"
               "&updateMask.fieldPaths=version"
               "&updateMask.fieldPaths=wifi"
               "&updateMask.fieldPaths=heap"
               "&updateMask.fieldPaths=minHeap"
               "&updateMask.fieldPaths=pollAgeS"
               "&updateMask.fieldPaths=authMode"
               "&updateMask.fieldPaths=ntpAgeS"
               "&updateMask.fieldPaths=ota"
               "&updateMask.fieldPaths=resetReason"
               "&updateMask.fieldPaths=prevCause"
               "&updateMask.fieldPaths=prevLoopPhase"
               "&updateMask.fieldPaths=prevHbPhase"
               "&updateMask.fieldPaths=coreDump";

  const unsigned long lastPollOk = g_lastPollOkMs;
  const unsigned long lastNtp = g_lastNtpSyncMs;
  const unsigned long nowMs = millis();
  unsigned long uptimeSec = (nowMs - bootTime) / 1000;
  unsigned long pollAge = lastPollOk ? (nowMs - lastPollOk) / 1000 : 0;
  long ntpAge = lastNtp ? (long)((nowMs - lastNtp) / 1000) : -1;

  JsonDocument doc;
  doc["fields"]["uptime"]["integerValue"] = String(uptimeSec);
  doc["fields"]["ip"]["stringValue"] = WiFi.localIP().toString();
  doc["fields"]["commands"]["integerValue"] = String(commandsProcessed);
  doc["fields"]["errors"]["integerValue"] = String(commandErrors);
  doc["fields"]["version"]["stringValue"] = BRIDGE_FIRMWARE_VERSION;
  doc["fields"]["wifi"]["booleanValue"] = (WiFi.status() == WL_CONNECTED);
  doc["fields"]["heap"]["integerValue"] = String(ESP.getFreeHeap());
  // 1.3.0 diagnostics
  doc["fields"]["minHeap"]["integerValue"] = String(ESP.getMinFreeHeap());
  doc["fields"]["pollAgeS"]["integerValue"] = String(pollAge);
  doc["fields"]["authMode"]["stringValue"] = authModeName(authMode);
  doc["fields"]["ntpAgeS"]["integerValue"] = String(ntpAge);
  doc["fields"]["ota"]["stringValue"] = currentOtaStatus();
  doc["fields"]["resetReason"]["stringValue"] = bootResetReason;
  doc["fields"]["prevCause"]["stringValue"] = prevRestartCause;
  doc["fields"]["prevLoopPhase"]["stringValue"] = prevLoopPhase;
  doc["fields"]["prevHbPhase"]["stringValue"] = prevHbPhase;
  doc["fields"]["coreDump"]["booleanValue"] = coreDumpPresent;

  String body;
  serializeJson(doc, body);

  http.begin(client, url);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("Authorization", "Bearer " + token);

  int httpCode = http.PATCH(body);

  if (httpCode == 200) {
    DEBUG_PRINTLN("Heartbeat OK");
  } else {
    DEBUG_PRINT("Heartbeat failed: ");
    DEBUG_PRINTLN(httpCode);
  }

  http.end();
  return httpCode == 200;
}

void heartbeatTask(void* arg) {
  esp_task_wdt_add(nullptr);

  WiFiClientSecure hbClient;
  hbClient.setInsecure();
  hbClient.setHandshakeTimeout(30);
  hbClient.setTimeout(15);

  unsigned long lastBeat = 0;
  bool beatOnce = false;

  for (;;) {
    esp_task_wdt_reset();
#ifdef BRIDGE_BENCH
    if (g_benchBlockHeartbeat) {
      Serial.println("[BENCH] blocking heartbeat task forever");
      setHbPhase(PH_HEARTBEAT);
      for (;;) delay(1000);
    }
#endif
    if (g_otaBusy) {
      // Free this task's TLS session while an OTA download needs the heap.
      hbClient.stop();
      vTaskDelay(pdMS_TO_TICKS(500));
      continue;
    }

    // Stamps first, clock second (see supervisorTask).
    const unsigned long lastPollOk = g_lastPollOkMs;
    const unsigned long loopTick = g_loopTickMs;
    const unsigned long now = millis();
    const bool due = !beatOnce || now - lastBeat >= REGISTRY_HEARTBEAT_INTERVAL_MS;
    if (due && firebaseReady && WiFi.status() == WL_CONNECTED) {
      String uid;
      const bool paired = snapshotPairing(uid);
      const bool pollFresh = paired && lastPollOk != 0 &&
                             (long)(now - lastPollOk) < (long)HEARTBEAT_POLL_FRESH_MS;
      const bool loopAlive = (long)(now - loopTick) < 60000L;
      const bool eligible = paired ? pollFresh : loopAlive;
      String token = currentIdToken();

      if (eligible && !token.isEmpty()) {
        lastBeat = now;
        beatOnce = true;

        if (paired) {
          setHbPhase(PH_HEARTBEAT);
          if (writeHeartbeat(hbClient, token, uid)) g_lastHbTaskOkMs = millis();
        }

        // Refresh the registry doc on the same cadence — runs whether paired
        // or not, so the app sees lastSeen ticking even on freshly-flashed
        // bridges sitting at the install site waiting to be claimed.
        setHbPhase(PH_REGISTRY);
        if (updateRegistryHeartbeat(hbClient, token)) {
          g_lastHbTaskOkMs = millis();
          if (!isPaired) noteProgress();
        }
        setHbPhase(PH_IDLE);
      }
    }
    vTaskDelay(pdMS_TO_TICKS(250));
  }
}

void startHeartbeatTask() {
  // Core 0 (beside the Wi-Fi stack), so a heartbeat's TLS handshake does not
  // take CPU from the poll loop on core 1.
  xTaskCreatePinnedToCore(heartbeatTask, "bridgeHb", 10240, nullptr, 1,
                          &heartbeatTaskHandle, 0);
}

// ============================================================================
// Bridge Registry — self-registration & pairing handshake
// ============================================================================
//
// The bridge writes its own document at /bridge_registry/{deviceId} so the
// Lumina app can discover and pair it via Firestore — no mDNS, no manual
// IP entry, no "phone and bridge on same WiFi" requirement. The pairing
// handshake is also Firestore-driven: app writes status="pairing" +
// pendingUid, the bridge sees it on the next pollPairingRequest() and
// promotes itself to status="paired".

// Build the JSON body containing every field the registry doc supports.
// Used for the initial full-doc write at boot.
static String buildRegistryFullPayload() {
  String uid;
  const bool paired = snapshotPairing(uid);

  JsonDocument doc;
  doc["fields"]["deviceId"]["stringValue"] = deviceId;
  doc["fields"]["deviceName"]["stringValue"] = deviceName;
  doc["fields"]["apName"]["stringValue"] = deviceName;
  doc["fields"]["bridgeEmail"]["stringValue"] = currentBridgeEmail();
  doc["fields"]["bridgeUid"]["stringValue"] = currentBridgeUid();
  doc["fields"]["authMode"]["stringValue"] = authModeName(authMode);
  doc["fields"]["ip"]["stringValue"] = WiFi.localIP().toString();
  doc["fields"]["status"]["stringValue"] = paired ? "paired" : "unpaired";
  doc["fields"]["pairedUid"]["stringValue"] = paired ? uid : "";
  // Empty string means "no pairing request pending" — see Part 7 of the
  // self-registration design (we deliberately avoid Firestore field
  // deletion in favor of a simple sentinel value).
  doc["fields"]["pendingUid"]["stringValue"] = "";
  doc["fields"]["firmwareVersion"]["stringValue"] = BRIDGE_FIRMWARE_VERSION;

  time_t now = time(nullptr);
  char ts[30];
  strftime(ts, sizeof(ts), "%Y-%m-%dT%H:%M:%SZ", gmtime(&now));
  doc["fields"]["lastSeen"]["timestampValue"] = ts;

  doc["fields"]["rssi"]["integerValue"] = String(WiFi.RSSI());
  doc["fields"]["heap"]["integerValue"] = String(ESP.getFreeHeap());
  doc["fields"]["freeHeap"]["integerValue"] = String(ESP.getFreeHeap());
  doc["fields"]["flashSize"]["integerValue"] = String(ESP.getFlashChipSize());

  String body;
  serializeJson(doc, body);
  return body;
}

// Called from loopTask (boot, pairing poll) and from the heartbeat task (404
// on a heartbeat). The caller supplies its own TLS client and token.
bool registerBridgeInRegistry(WiFiClientSecure& client, const String& token) {
  if (token.isEmpty()) {
    Serial.println("[Registry] Cannot register — no valid token");
    return false;
  }

  HTTPClient http;
  // Write every field via updateMask so the PATCH creates the doc on
  // first run and overwrites stale fields on subsequent boots.
  String url = bridgeRegistryUrl() +
               "?updateMask.fieldPaths=deviceId" +
               "&updateMask.fieldPaths=deviceName" +
               "&updateMask.fieldPaths=apName" +
               "&updateMask.fieldPaths=bridgeEmail" +
               "&updateMask.fieldPaths=bridgeUid" +
               "&updateMask.fieldPaths=authMode" +
               "&updateMask.fieldPaths=ip" +
               "&updateMask.fieldPaths=status" +
               "&updateMask.fieldPaths=pairedUid" +
               "&updateMask.fieldPaths=pendingUid" +
               "&updateMask.fieldPaths=firmwareVersion" +
               "&updateMask.fieldPaths=lastSeen" +
               "&updateMask.fieldPaths=rssi" +
               "&updateMask.fieldPaths=heap" +
               "&updateMask.fieldPaths=freeHeap" +
               "&updateMask.fieldPaths=flashSize";

  String body = buildRegistryFullPayload();

  http.begin(client, url);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("Authorization", "Bearer " + token);

  int httpCode = http.PATCH(body);

  if (httpCode == 200) {
    Serial.print("[Registry] Self-registered as ");
    Serial.print(deviceId);
    Serial.print(" (status=");
    Serial.print(isPaired ? "paired" : "unpaired");
    Serial.println(")");
    // Counts as progress for an unpaired bridge so the watchdog doesn't
    // reboot a freshly-installed unpaired bridge sitting idle.
    if (!isPaired) noteProgress();
  } else {
    String response = http.getString();
    Serial.print("[Registry] Self-registration failed: HTTP ");
    Serial.print(httpCode);
    Serial.print(" - ");
    Serial.println(response.substring(0, 200));
    // Rules that predate per-bridge identities refuse its own registry doc.
    if (httpCode == 403) requestFallbackFromOtherTask("registry_denied");
  }

  http.end();
  return httpCode == 200;
}

bool updateRegistryHeartbeat(WiFiClientSecure& client, const String& token) {
  String uid;
  const bool paired = snapshotPairing(uid);

  HTTPClient http;
  // Only the dynamic fields — keep deviceId/apName/firmwareVersion immutable
  // across heartbeats so a corrupted payload can't rewrite identity.
  // Status + pairedUid are included so the doc reflects pairing changes
  // (e.g. immediately after pollPairingRequest promotes us). bridgeEmail
  // and authMode are included because the active identity can change
  // within a boot (per-bridge → legacy fallback).
  String url = bridgeRegistryUrl() +
               "?updateMask.fieldPaths=lastSeen" +
               "&updateMask.fieldPaths=ip" +
               "&updateMask.fieldPaths=rssi" +
               "&updateMask.fieldPaths=heap" +
               "&updateMask.fieldPaths=freeHeap" +
               "&updateMask.fieldPaths=status" +
               "&updateMask.fieldPaths=pairedUid" +
               "&updateMask.fieldPaths=bridgeEmail" +
               "&updateMask.fieldPaths=authMode";

  JsonDocument doc;
  doc["fields"]["ip"]["stringValue"] = WiFi.localIP().toString();
  doc["fields"]["status"]["stringValue"] = paired ? "paired" : "unpaired";
  doc["fields"]["pairedUid"]["stringValue"] = paired ? uid : "";
  doc["fields"]["bridgeEmail"]["stringValue"] = currentBridgeEmail();
  doc["fields"]["authMode"]["stringValue"] = authModeName(authMode);

  time_t now = time(nullptr);
  char ts[30];
  strftime(ts, sizeof(ts), "%Y-%m-%dT%H:%M:%SZ", gmtime(&now));
  doc["fields"]["lastSeen"]["timestampValue"] = ts;

  doc["fields"]["rssi"]["integerValue"] = String(WiFi.RSSI());
  doc["fields"]["heap"]["integerValue"] = String(ESP.getFreeHeap());
  doc["fields"]["freeHeap"]["integerValue"] = String(ESP.getFreeHeap());

  String body;
  serializeJson(doc, body);

  http.begin(client, url);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("Authorization", "Bearer " + token);

  int httpCode = http.PATCH(body);

  if (httpCode == 200) {
    DEBUG_PRINTLN("[Registry] Heartbeat OK");
  } else if (httpCode == 404) {
    // Registry doc missing — re-create it. Happens if an admin deleted
    // the doc to force re-pairing, or on a brand-new project.
    Serial.println("[Registry] Heartbeat 404 — re-registering");
    http.end();
    return registerBridgeInRegistry(client, token);
  } else {
    DEBUG_PRINT("[Registry] Heartbeat failed: HTTP ");
    DEBUG_PRINTLN(httpCode);
    if (httpCode == 403) requestFallbackFromOtherTask("registry_denied");
  }

  http.end();
  return httpCode == 200;
}

bool pollPairingRequest() {
  if (!ensureValidToken()) return false;

  HTTPClient http;
  http.begin(secureClient, bridgeRegistryUrl());
  http.addHeader("Authorization", "Bearer " + currentIdToken());

  int httpCode = http.GET();

  if (httpCode == 404) {
    // Doc doesn't exist yet — the initial registerBridgeInRegistry() call
    // probably failed (e.g. token wasn't ready). Try again now.
    http.end();
    Serial.println("[Registry] Doc missing — re-registering");
    registerBridgeInRegistry(secureClient, currentIdToken());
    return false;
  }

  if (httpCode != 200) {
    DEBUG_PRINT("[Registry] Pairing poll failed: HTTP ");
    DEBUG_PRINTLN(httpCode);
    http.end();
    return false;
  }

  String response = http.getString();
  http.end();

  JsonDocument doc;
  if (deserializeJson(doc, response)) {
    DEBUG_PRINTLN("[Registry] Pairing poll JSON parse error");
    return false;
  }

  String pendingUid =
      doc["fields"]["pendingUid"]["stringValue"].as<String>();
  String currentStatus =
      doc["fields"]["status"]["stringValue"].as<String>();

  // Empty pendingUid (sentinel) or non-pairing status → nothing to do.
  if (pendingUid.length() == 0 || currentStatus != "pairing") {
    noteProgress();
    return false;
  }

  Serial.println();
  Serial.print("[Registry] Pairing request received — UID: ");
  Serial.println(pendingUid);

  // Persist the new UID to NVS before confirming, so a power loss between
  // the local commit and the Firestore confirm leaves the bridge in a
  // recoverable state (next boot will see itself as paired and the app's
  // pending request will resolve naturally on reconnect).
  prefs.begin("bridge", false);
  prefs.putString("uid", pendingUid);
  prefs.end();

  setPairing(pendingUid, true);
  nvsUidFound = true;
  // A fresh pairing starts a fresh progress window for the command poll.
  noteProgress();

  // Confirm the pairing in the registry doc — clears pendingUid and flips
  // status to "paired" so the app's poll completes.
  HTTPClient confirmHttp;
  String confirmUrl = bridgeRegistryUrl() +
                      "?updateMask.fieldPaths=status" +
                      "&updateMask.fieldPaths=pairedUid" +
                      "&updateMask.fieldPaths=pendingUid" +
                      "&updateMask.fieldPaths=lastSeen";

  JsonDocument confirmDoc;
  confirmDoc["fields"]["status"]["stringValue"] = "paired";
  confirmDoc["fields"]["pairedUid"]["stringValue"] = pendingUid;
  confirmDoc["fields"]["pendingUid"]["stringValue"] = "";

  time_t now = time(nullptr);
  char ts[30];
  strftime(ts, sizeof(ts), "%Y-%m-%dT%H:%M:%SZ", gmtime(&now));
  confirmDoc["fields"]["lastSeen"]["timestampValue"] = ts;

  String confirmBody;
  serializeJson(confirmDoc, confirmBody);

  confirmHttp.begin(secureClient, confirmUrl);
  confirmHttp.addHeader("Content-Type", "application/json");
  confirmHttp.addHeader("Authorization", "Bearer " + currentIdToken());

  int confirmCode = confirmHttp.PATCH(confirmBody);
  confirmHttp.end();

  if (confirmCode == 200) {
    Serial.println("[Registry] Pairing confirmed in Firestore");
    return true;
  } else {
    Serial.print("[Registry] Pairing confirmation failed: HTTP ");
    Serial.println(confirmCode);
    // Local NVS already updated — the next heartbeat cycle will retry the
    // status PATCH and the app's pairing poll will eventually see "paired".
    return false;
  }
}

// ============================================================================
// OTA — signed pull, bootloader rollback (#4)
// ============================================================================
// 1. PULL. Every OTA_CHECK_INTERVAL_MS (first check 10 min after boot plus
//    per-device jitter), or when asked (otaCheck command, POST
//    /api/ota/check), read Firestore bridge_firmware/{OTA_CHANNEL}:
//      { version, url, size, sha256, sig, devices[], minVersion, enabled }
//    Install only if enabled, this device is targeted ("*" or its deviceId),
//    the version is newer, the running version ≥ minVersion, and this
//    version has not already failed here twice.
// 2. VERIFY. sig is an ECDSA P-256 / SHA-256 signature over
//      "lumina-bridge-fw|v1|<board>|<version>|<size>|<sha256>"
//    checked against the public key compiled into this image BEFORE any
//    download; the download's size and SHA-256 must then match; ESP-IDF's
//    esp_ota_end() validates the image structure. TLS is not trusted for
//    integrity (the client runs setInsecure); the signature is.
// 3. ROLLBACK. The new image boots PENDING_VERIFY. verifyRollbackLater()
//    stops the Arduino core from confirming it at boot; otaProbationTick()
//    confirms it only after a successful command poll AND a successful
//    heartbeat-task write within OTA_PROBATION_MS. Any reset before that —
//    crash, task watchdog, supervisor, power loss — makes the bootloader
//    boot the previous image; a missed deadline rolls back explicitly.
//    The previous image then records the version as failed.

extern "C" bool verifyRollbackLater() { return true; }

static int compareVersions(const String& a, const String& b) {
  int pa[3] = {0, 0, 0}, pb[3] = {0, 0, 0};
  sscanf(a.c_str(), "%d.%d.%d", &pa[0], &pa[1], &pa[2]);
  sscanf(b.c_str(), "%d.%d.%d", &pb[0], &pb[1], &pb[2]);
  for (int i = 0; i < 3; i++) {
    if (pa[i] != pb[i]) return pa[i] < pb[i] ? -1 : 1;
  }
  return 0;
}

void otaBootCheck() {
  Preferences p;
  p.begin("ota", false);
  String pend = p.getString("pend", "");
  String last = p.getString("last", "");

  const esp_partition_t* running = esp_ota_get_running_partition();
  esp_ota_img_states_t state;
  if (running && esp_ota_get_state_partition(running, &state) == ESP_OK &&
      state == ESP_OTA_IMG_PENDING_VERIFY) {
    otaProbation = true;
    otaProbationDeadline = millis() + OTA_PROBATION_MS;
    setOtaStatus("probation:" BRIDGE_FIRMWARE_VERSION);
    Serial.println("[OTA] new image on probation until it polls and heartbeats");
  } else if (!pend.isEmpty() && pend != BRIDGE_FIRMWARE_VERSION) {
    // An install of `pend` was switched to, but the previous image is the one
    // running: the bootloader rolled it back (or it never became valid).
    String failVer = p.getString("failVer", "");
    uint32_t failCnt = (failVer == pend) ? p.getUInt("failCnt", 0) + 1 : 1;
    p.putString("failVer", pend);
    p.putUInt("failCnt", failCnt);
    last = "rolled_back:" + pend;
    p.putString("last", last);
    p.remove("pend");
    setOtaStatus(last);
    Serial.printf("[OTA] %s (failure %u for that version)\n", last.c_str(),
                  (unsigned)failCnt);
  } else {
    if (!pend.isEmpty()) p.remove("pend");
    setOtaStatus(last);
  }
  p.end();

  // An image that was USB-flashed without the two-slot partition table can
  // never take an update — say so loudly instead of failing at the first
  // download. The runbook checks this field before leaving a site.
  if (!otaProbation && esp_ota_get_next_update_partition(nullptr) == nullptr) {
    setOtaStatus("no_ota_partition");
    Serial.println("[OTA] WARNING: no second app slot — this unit cannot take OTA");
  }
}

void otaProbationTick() {
  if (!otaProbation) return;

#if defined(BRIDGE_BENCH_BAD_IMAGE) && BRIDGE_BENCH_BAD_IMAGE == 1
  // BENCH rollback test A: crash during probation → bootloader rollback.
  if (millis() - g_setupDoneMs > 45000) {
    Serial.println("[BENCH] bad image: aborting during probation");
    abort();
  }
#endif

  bool healthy = WiFi.status() == WL_CONNECTED && firebaseAuthenticated &&
                 g_lastHbTaskOkMs != 0 &&
                 (isPaired ? g_lastPollOkMs != 0 : g_lastProgressMs != 0);
#if defined(BRIDGE_BENCH_BAD_IMAGE) && BRIDGE_BENCH_BAD_IMAGE == 2
  // BENCH rollback test B: never healthy → explicit rollback at the deadline.
  healthy = false;
#endif

  if (healthy) {
    esp_ota_mark_app_valid_cancel_rollback();
    otaProbation = false;
    Preferences p;
    p.begin("ota", false);
    p.remove("pend");
    if (p.getString("failVer", "") == BRIDGE_FIRMWARE_VERSION) {
      p.remove("failVer");
      p.remove("failCnt");
    }
    p.putString("last", "ok:" BRIDGE_FIRMWARE_VERSION);
    p.end();
    setOtaStatus("ok:" BRIDGE_FIRMWARE_VERSION);
    Serial.println("[OTA] new image confirmed healthy — rollback cancelled");
  } else if ((long)(millis() - otaProbationDeadline) > 0) {
    Serial.println("[OTA] probation deadline missed — rolling back");
    Serial.flush();
    esp_ota_mark_app_invalid_rollback_and_reboot();
  }
}

#if BRIDGE_OTA_ENABLED

struct OtaManifest {
  String version;
  String url;
  String sha256;
  String sig;
  String minVersion;
  uint32_t size = 0;
  bool enabled = false;
  bool targeted = false;
};

static void toHex(const uint8_t* in, size_t n, char* out) {
  static const char* digits = "0123456789abcdef";
  for (size_t i = 0; i < n; i++) {
    out[2 * i] = digits[in[i] >> 4];
    out[2 * i + 1] = digits[in[i] & 0x0f];
  }
  out[2 * n] = '\0';
}

bool fetchOtaManifest(OtaManifest& m) {
  HTTPClient http;
  String url = "https://firestore.googleapis.com/v1/projects/" + String(FIREBASE_PROJECT_ID) +
               "/databases/(default)/documents/bridge_firmware/" OTA_CHANNEL;
  setLoopPhase(PH_OTA_MANIFEST);
  http.begin(secureClient, url);
  http.addHeader("Authorization", "Bearer " + currentIdToken());
  int code = http.GET();
  setLoopPhase(PH_IDLE);
  if (code != 200) {
    Serial.printf("[OTA] manifest %s: HTTP %d\n", OTA_CHANNEL, code);
    http.end();
    return false;
  }
  String response = http.getString();
  http.end();

  JsonDocument doc;
  if (deserializeJson(doc, response)) return false;
  JsonObject f = doc["fields"];
  m.version = f["version"]["stringValue"] | "";
  m.url = f["url"]["stringValue"] | "";
  m.sha256 = f["sha256"]["stringValue"] | "";
  m.sig = f["sig"]["stringValue"] | "";
  m.minVersion = f["minVersion"]["stringValue"] | "";
  m.size = (uint32_t)strtoul(f["size"]["integerValue"] | "0", nullptr, 10);
  m.enabled = f["enabled"]["booleanValue"] | false;
  for (JsonObject v : f["devices"]["arrayValue"]["values"].as<JsonArray>()) {
    String d = v["stringValue"] | "";
    if (d == "*" || d == deviceId) m.targeted = true;
  }
  m.sha256.toLowerCase();
  return !m.version.isEmpty();
}

bool verifyManifestSignature(const OtaManifest& m) {
  String msg = "lumina-bridge-fw|v1|" OTA_BOARD "|" + m.version + "|" +
               String(m.size) + "|" + m.sha256;
  uint8_t hash[32];
  mbedtls_sha256_ret((const unsigned char*)msg.c_str(), msg.length(), hash, 0);

  uint8_t sig[80];
  size_t sigLen = 0;
  if (mbedtls_base64_decode(sig, sizeof(sig), &sigLen,
                            (const unsigned char*)m.sig.c_str(), m.sig.length()) != 0) {
    return false;
  }

  static const char kPem[] = OTA_SIGNING_PUBKEY_PEM;
  mbedtls_pk_context pk;
  mbedtls_pk_init(&pk);
  bool ok = mbedtls_pk_parse_public_key(&pk, (const unsigned char*)kPem,
                                        sizeof(kPem)) == 0 &&
            mbedtls_pk_verify(&pk, MBEDTLS_MD_SHA256, hash, sizeof(hash),
                              sig, sigLen) == 0;
  mbedtls_pk_free(&pk);
  return ok;
}

bool otaInstall(const OtaManifest& m) {
  const esp_partition_t* target = esp_ota_get_next_update_partition(nullptr);
  if (target == nullptr || m.size == 0 || m.size > target->size) {
    Serial.println("[OTA] no suitable partition (is this image on the OTA layout?)");
    return false;
  }

  // Quiesce: pause the heartbeat task (it drops its TLS session) and close
  // the poll session, so the download has the heap to itself.
  g_otaBusy = true;
  for (int i = 0; i < 60 && rtcHbPhase != PH_IDLE; i++) {
    esp_task_wdt_reset();
    delay(500);
  }
  secureClient.stop();
  delay(600);
  if (ESP.getMaxAllocHeap() < 40000) {
    Serial.printf("[OTA] largest free block %u too small — skipping\n",
                  (unsigned)ESP.getMaxAllocHeap());
    g_otaBusy = false;
    return false;
  }

  setLoopPhase(PH_OTA_DOWNLOAD);
  setOtaStatus("downloading:" + m.version);
  Serial.printf("[OTA] downloading %s (%u bytes) to %s\n", m.version.c_str(),
                (unsigned)m.size, target->label);

  WiFiClientSecure dl;
  dl.setInsecure();  // integrity comes from the signature + SHA-256
  dl.setHandshakeTimeout(30);
  dl.setTimeout(15);
  HTTPClient http;
  http.begin(dl, m.url);
  http.setTimeout(15000);
  http.addHeader("Authorization", "Firebase " + currentIdToken());

  bool ok = false;
  esp_ota_handle_t handle = 0;
  bool otaOpen = false;
  uint8_t* buf = nullptr;
  mbedtls_sha256_context sha;
  mbedtls_sha256_init(&sha);

  do {
    int code = http.GET();
    if (code != 200) {
      Serial.printf("[OTA] download HTTP %d\n", code);
      break;
    }
    int len = http.getSize();
    if (len != (int)m.size) {
      Serial.printf("[OTA] size %d != manifest %u\n", len, (unsigned)m.size);
      break;
    }
    esp_task_wdt_reset();
    if (esp_ota_begin(target, OTA_WITH_SEQUENTIAL_WRITES, &handle) != ESP_OK) break;
    otaOpen = true;
    buf = (uint8_t*)malloc(4096);
    if (buf == nullptr) break;
    mbedtls_sha256_starts_ret(&sha, 0);

    WiFiClient* stream = http.getStreamPtr();
    uint32_t got = 0;
    unsigned long lastData = millis();
    bool streamOk = true;
    while (got < m.size) {
      esp_task_wdt_reset();
      int avail = stream->available();
      if (avail > 0) {
        size_t want = min((size_t)avail, (size_t)4096);
        want = min(want, (size_t)(m.size - got));
        int n = stream->read(buf, want);
        if (n > 0) {
          if (esp_ota_write(handle, buf, n) != ESP_OK) { streamOk = false; break; }
          mbedtls_sha256_update_ret(&sha, buf, n);
          got += n;
          lastData = millis();
        }
      } else if (millis() - lastData > 20000) {
        Serial.println("[OTA] download stalled");
        streamOk = false;
        break;
      } else {
        delay(2);
      }
    }
    if (!streamOk || got != m.size) break;

    uint8_t digest[32];
    char hex[65];
    mbedtls_sha256_finish_ret(&sha, digest);
    toHex(digest, sizeof(digest), hex);
    if (m.sha256 != hex) {
      Serial.println("[OTA] SHA-256 mismatch — discarding");
      break;
    }
    esp_err_t endErr = esp_ota_end(handle);  // IDF validates the image
    otaOpen = false;
    if (endErr != ESP_OK) {
      Serial.printf("[OTA] image rejected by esp_ota_end: %d\n", (int)endErr);
      break;
    }
    ok = true;
  } while (false);

  if (otaOpen) esp_ota_abort(handle);
  free(buf);
  mbedtls_sha256_free(&sha);
  http.end();
  dl.stop();
  setLoopPhase(PH_IDLE);

  if (!ok) {
    setOtaStatus("download_failed:" + m.version);
    g_otaBusy = false;
    return false;
  }

  Preferences p;
  p.begin("ota", false);
  p.putString("pend", m.version);
  p.end();

  if (esp_ota_set_boot_partition(target) != ESP_OK) {
    Serial.println("[OTA] could not set boot partition");
    Preferences q;
    q.begin("ota", false);
    q.remove("pend");
    q.end();
    setOtaStatus("set_boot_failed:" + m.version);
    g_otaBusy = false;
    return false;
  }

  Serial.printf("[OTA] %s verified and staged — rebooting into probation\n",
                m.version.c_str());
  restartWithCause(CAUSE_OTA_INSTALL);
  return true;  // not reached
}

void runOtaCheck() {
  if (!ensureValidToken()) return;
  OtaManifest m;
  if (!fetchOtaManifest(m)) return;

  if (!m.enabled || !m.targeted) {
    Serial.printf("[OTA] %s not offered to this bridge\n", m.version.c_str());
    return;
  }
  if (compareVersions(m.version, BRIDGE_FIRMWARE_VERSION) <= 0) {
    DEBUG_PRINTLN("[OTA] up to date");
    return;
  }
  if (!m.minVersion.isEmpty() &&
      compareVersions(BRIDGE_FIRMWARE_VERSION, m.minVersion) < 0) {
    Serial.printf("[OTA] %s needs >= %s first\n", m.version.c_str(), m.minVersion.c_str());
    return;
  }
  {
    Preferences p;
    p.begin("ota", true);
    String failVer = p.getString("failVer", "");
    uint32_t failCnt = p.getUInt("failCnt", 0);
    p.end();
    if (failVer == m.version && failCnt >= 2) {
      Serial.printf("[OTA] %s already failed here %u times — skipping\n",
                    m.version.c_str(), (unsigned)failCnt);
      return;
    }
  }
  if (!m.url.startsWith("https://firebasestorage.googleapis.com/") ||
      m.sha256.length() != 64) {
    Serial.println("[OTA] manifest url/sha256 malformed");
    return;
  }
  if (!verifyManifestSignature(m)) {
    Serial.println("[OTA] manifest signature INVALID — refusing");
    setOtaStatus("bad_signature:" + m.version);
    return;
  }
  otaInstall(m);
}

#endif  // BRIDGE_OTA_ENABLED

void otaMaybeRun() {
#if BRIDGE_OTA_ENABLED
  if (otaProbation || !g_setupDone) return;
  const bool asked = g_otaCheckRequested;
  const bool due = nextOtaCheckMs != 0 && (long)(millis() - nextOtaCheckMs) >= 0;
  if (!asked && !due) return;
  if (!firebaseReady || WiFi.status() != WL_CONNECTED) return;
  // A scheduled check waits until the bridge has been idle for a minute, so
  // it never lands in the middle of someone using their lights.
  if (!asked && lastCommandExecutedMs != 0 && millis() - lastCommandExecutedMs < 60000) return;

  g_otaCheckRequested = false;
  nextOtaCheckMs = millis() + OTA_CHECK_INTERVAL_MS;
  runOtaCheck();
#else
  g_otaCheckRequested = false;
#endif
}

// ============================================================================
// Serial console — per-bridge credential provisioning (#5)
// ============================================================================
// The trust anchor for a per-bridge credential is physical possession: it is
// delivered over USB by tools/provision_bridge_serial.py, never over the
// network (anything the bridge could fetch with the shared account, anyone
// holding the shared account could fetch too). Lines, 115200 baud:
//   LUMINA-ID
//     → LUMINA-ID {"deviceId":…,"version":…,"credential":bool,"authMode":…}
//   LUMINA-PROVISION {"uid":"bridge_<deviceId>","email":…,"password":…[,"force":true]}
//     → LUMINA-PROVISION OK <deviceId>  |  LUMINA-PROVISION ERR <reason>
//   LUMINA-CRED-CLEAR
//     → LUMINA-CRED-CLEAR OK
// The password is never echoed or logged.

static void consoleReply(const String& s) {
  Serial.println(s);
}

static void handleConsoleLine(String line) {
  line.trim();
  if (line.isEmpty()) return;

  if (line == "LUMINA-ID") {
    Preferences p;
    bool cred = false;
    if (p.begin("bcred", true)) {
      cred = p.getString("uid", "") == expectedBridgeUid();
      p.end();
    }
    JsonDocument doc;
    doc["deviceId"] = deviceId;
    doc["version"] = BRIDGE_FIRMWARE_VERSION;
    doc["credential"] = cred;
    doc["authMode"] = authModeName(authMode);
    doc["otaEnabled"] = (bool)BRIDGE_OTA_ENABLED;
    String out;
    serializeJson(doc, out);
    consoleReply("LUMINA-ID " + out);
    return;
  }

  if (line.startsWith("LUMINA-PROVISION ")) {
    JsonDocument doc;
    if (deserializeJson(doc, line.substring(17))) {
      consoleReply("LUMINA-PROVISION ERR bad_json");
      return;
    }
    String uid = doc["uid"] | "";
    String email = doc["email"] | "";
    String pass = doc["password"] | "";
    bool force = doc["force"] | false;
    if (uid != expectedBridgeUid()) {
      consoleReply("LUMINA-PROVISION ERR uid_not_this_device");
      return;
    }
    if (email.indexOf('@') < 1 || email.length() > 128) {
      consoleReply("LUMINA-PROVISION ERR bad_email");
      return;
    }
    if (pass.length() < 16 || pass.length() > 128) {
      consoleReply("LUMINA-PROVISION ERR bad_password_length");
      return;
    }
    Preferences p;
    if (!p.begin("bcred", false)) {
      consoleReply("LUMINA-PROVISION ERR nvs_open");
      return;
    }
    if (!force && p.getString("uid", "") == expectedBridgeUid()) {
      p.end();
      consoleReply("LUMINA-PROVISION ERR exists (send force:true to replace)");
      return;
    }
    p.putString("uid", uid);
    p.putString("email", email);
    p.putString("pass", pass);
    bool readBack = p.getString("uid", "") == uid &&
                    p.getString("email", "") == email &&
                    p.getString("pass", "") == pass;
    p.end();
    if (!readBack) {
      consoleReply("LUMINA-PROVISION ERR nvs_readback");
      return;
    }
    g_credReloadRequested = true;
    consoleReply("LUMINA-PROVISION OK " + deviceId);
    return;
  }

  if (line == "LUMINA-CRED-CLEAR") {
    Preferences p;
    if (p.begin("bcred", false)) {
      p.clear();
      p.end();
    }
    g_credReloadRequested = true;
    consoleReply("LUMINA-CRED-CLEAR OK");
    return;
  }
}

void consoleTask(void* arg) {
  String line;
  line.reserve(512);
  for (;;) {
    while (Serial.available() > 0) {
      char c = (char)Serial.read();
      if (c == '\r') continue;
      if (c == '\n') {
        handleConsoleLine(line);
        line = "";
      } else if (line.length() < 511) {
        line += c;
      }
    }
    vTaskDelay(pdMS_TO_TICKS(20));
  }
}

void startConsoleTask() {
  xTaskCreatePinnedToCore(consoleTask, "bridgeCon", 6144, nullptr, 1,
                          &consoleTaskHandle, 1);
}

#ifdef BRIDGE_BENCH
void handleBenchState() {
  JsonDocument doc;
  const unsigned long now = millis();
  doc["version"] = BRIDGE_FIRMWARE_VERSION;
  doc["uptimeS"] = now / 1000;
  doc["authMode"] = authModeName(authMode);
  doc["authReason"] = currentAuthReason();
  doc["bridgeEmail"] = currentBridgeEmail();
  doc["paired"] = (bool)isPaired;
  doc["pollAgeMs"] = g_lastPollOkMs ? now - g_lastPollOkMs : 0;
  doc["progressAgeMs"] = g_lastProgressMs ? now - g_lastProgressMs : 0;
  doc["hbTaskOkAgeMs"] = g_lastHbTaskOkMs ? now - g_lastHbTaskOkMs : 0;
  doc["ntpAgeMs"] = g_lastNtpSyncMs ? now - g_lastNtpSyncMs : 0;
  doc["epochMs"] = (double)epochNowMs();
  doc["progressTimeoutMs"] = progressTimeoutMs();
  doc["loopPhase"] = phaseName(rtcLoopPhase);
  doc["hbPhase"] = phaseName(rtcHbPhase);
  doc["resetReason"] = bootResetReason;
  doc["prevCause"] = prevRestartCause;
  doc["prevLoopPhase"] = prevLoopPhase;
  doc["prevHbPhase"] = prevHbPhase;
  doc["noProgressRestarts"] = (uint32_t)noProgressRestarts;
  doc["ota"] = currentOtaStatus();
  doc["otaProbation"] = otaProbation;
  const esp_partition_t* running = esp_ota_get_running_partition();
  doc["partition"] = running ? running->label : "?";
  doc["heap"] = ESP.getFreeHeap();
  doc["minHeap"] = ESP.getMinFreeHeap();
  doc["maxAlloc"] = ESP.getMaxAllocHeap();
  doc["stackFreeLoop"] = uxTaskGetStackHighWaterMark(nullptr);
  doc["stackFreeHb"] = heartbeatTaskHandle ? uxTaskGetStackHighWaterMark(heartbeatTaskHandle) : 0;
  doc["stackFreeSup"] = supervisorTaskHandle ? uxTaskGetStackHighWaterMark(supervisorTaskHandle) : 0;
  doc["stackFreeCon"] = consoleTaskHandle ? uxTaskGetStackHighWaterMark(consoleTaskHandle) : 0;
  doc["coreDump"] = coreDumpPresent;
  String body;
  serializeJson(doc, body);
  server.send(200, "application/json", body);
}
#endif

// ============================================================================
// LED Status Functions
// ============================================================================

void blinkLed(int times, int delayMs) {
  for (int i = 0; i < times; i++) {
    digitalWrite(STATUS_LED_PIN, HIGH);
    delay(delayMs);
    digitalWrite(STATUS_LED_PIN, LOW);
    delay(delayMs);
  }
}

void statusBlink() {
  if (millis() - lastBlinkTime >= 5000) {
    lastBlinkTime = millis();

    if (firebaseReady && WiFi.status() == WL_CONNECTED) {
      blinkLed(1, 50);
    } else if (WiFi.status() == WL_CONNECTED) {
      blinkLed(2, 100);
    } else {
      blinkLed(3, 100);
    }
  }
}
