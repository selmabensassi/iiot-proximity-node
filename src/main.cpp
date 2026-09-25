#include <Arduino.h>
#include <WiFi.h>
#include <PubSubClient.h>
#include <time.h>
#include "secrets.h"

const char* NTP_SERVER      = "pool.ntp.org";
const long  GMT_OFFSET      = 0;
const int   DAYLIGHT_OFFSET = 0;

const int   MQTT_PORT      = 1883;
const char* MQTT_TOPIC         = "iiot/node1/distance";
const char* MQTT_TOPIC_RSSI    = "iiot/node1/rssi";
const char* MQTT_TOPIC_LATENCY = "iiot/node1/latency";
const char* MQTT_TOPIC_SEQ     = "iiot/node1/seq";
const char* MQTT_TOPIC_RETX    = "iiot/node1/retransmissions";

#define TRIG_PIN 5
#define ECHO_PIN 18

// Event-driven thresholds
const float CHANGE_THRESHOLD = 5.0;   
const float SAFETY_THRESHOLD = 30.0;  

// Check interval
const unsigned long CHECK_INTERVAL = 100; 

// State
float         lastPublishedDistance = -1;
unsigned long seqNumber             = 0;
unsigned long retransmissions       = 0;
unsigned long lastPublish           = 0;

WiFiClient espClient;
PubSubClient mqtt(espClient);

float readDistance() {
  digitalWrite(TRIG_PIN, LOW);
  delayMicroseconds(2);
  digitalWrite(TRIG_PIN, HIGH);
  delayMicroseconds(10);
  digitalWrite(TRIG_PIN, LOW);
  long duration = pulseIn(ECHO_PIN, HIGH, 23200);
  if (duration == 0) return -1;
  return (duration * 0.034f) / 2.0f;
}

void connectWiFi() {
  Serial.println("Connecting to WiFi...");
  WiFi.disconnect(true);
  delay(500);
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 20) {
    delay(500);
    attempts++;
    Serial.print("Status: ");
    Serial.println(WiFi.status());
  }
  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("WiFi connected!");
    Serial.println(WiFi.localIP());
  } else {
    Serial.println("WiFi failed, restarting...");
    ESP.restart();
  }
}

void connectMQTT() {
  int attempts = 0;
  while (!mqtt.connected() && attempts < 5) {
    Serial.print("Connecting to MQTT broker...");
    if (mqtt.connect("ESP32_IIoT_Node")) {
      Serial.println("connected!");
    } else {
      Serial.print("failed rc=");
      Serial.println(mqtt.state());
      attempts++;
      for (int i = 0; i < 20; i++) { delay(100); yield(); }
    }
  }
  if (!mqtt.connected()) ESP.restart();
}

bool publishWithRetx(const char* topic, const char* payload) {
  bool success = mqtt.publish(topic, payload);
  if (!success) {
    retransmissions++;
    Serial.printf("Retransmission #%lu on topic %s\n", retransmissions, topic);
    delay(100);
    success = mqtt.publish(topic, payload);
  }
  return success;
}

void setup() {
  Serial.begin(115200);
  pinMode(TRIG_PIN, OUTPUT);
  pinMode(ECHO_PIN, INPUT);
  connectWiFi();

  configTime(GMT_OFFSET, DAYLIGHT_OFFSET, NTP_SERVER);
  Serial.println("Waiting for NTP...");
  struct tm timeinfo;
  int ntpAttempts = 0;
  while (!getLocalTime(&timeinfo) && ntpAttempts < 20) {
    delay(500);
    Serial.print(".");
    ntpAttempts++;
  }
  if (ntpAttempts >= 20) {
    Serial.println("\nNTP timeout - continuing");
  } else {
    Serial.println("\nNTP synced!");
  }

  struct timeval tv;
  gettimeofday(&tv, NULL);
  unsigned long long esp_ms = (unsigned long long)tv.tv_sec * 1000ULL + tv.tv_usec / 1000ULL;
  Serial.printf("ESP32 Unix ms: %llu\n", esp_ms);

  mqtt.setServer(MQTT_BROKER, MQTT_PORT);
  mqtt.setSocketTimeout(5);
  connectMQTT();
  Serial.println("System ready!");
  lastPublish = millis();
}

void loop() {
  if (!mqtt.connected()) connectMQTT();
  mqtt.loop();

  unsigned long now = millis();
  if (now - lastPublish < CHECK_INTERVAL) return;
  lastPublish = now;

  float distance = readDistance();
  int rssi = WiFi.RSSI();

  if (distance < 2 || distance >= 400) {
    Serial.println("Out of range - skipping");
    return;
  }

  bool distanceChanged = abs(distance - lastPublishedDistance) > CHANGE_THRESHOLD;
  bool safetyAlert     = distance < SAFETY_THRESHOLD;

  if (!distanceChanged && !safetyAlert) {
    Serial.printf("No change (%.1f cm) - skipping\n", distance);
    return;
  }

  struct timeval tv;
  gettimeofday(&tv, NULL);
  unsigned long long esp_unix_ms = (unsigned long long)tv.tv_sec * 1000ULL + tv.tv_usec / 1000ULL;

  unsigned long t0 = millis();

  char distStr[48], rssiStr[10], latStr[10], seqStr[16], retxStr[16];
  snprintf(distStr,  sizeof(distStr),  "%.1f,%llu,%lu", distance, esp_unix_ms, seqNumber);
  snprintf(rssiStr,  sizeof(rssiStr),  "%d", rssi);
  snprintf(seqStr,   sizeof(seqStr),   "%lu", seqNumber);
  snprintf(retxStr,  sizeof(retxStr),  "%lu", retransmissions);

  publishWithRetx(MQTT_TOPIC, distStr);
  publishWithRetx(MQTT_TOPIC_RSSI, rssiStr);
  publishWithRetx(MQTT_TOPIC_SEQ, seqStr);
  publishWithRetx(MQTT_TOPIC_RETX, retxStr);

  unsigned long latency = millis() - t0;
  snprintf(latStr, sizeof(latStr), "%lu", latency);
  mqtt.publish(MQTT_TOPIC_LATENCY, latStr);

  Serial.printf("Dist: %.1f cm | RSSI: %d dBm | Lat: %lu ms | Seq: %lu | Retx: %lu | %s\n",
                distance, rssi, latency, seqNumber, retransmissions,
                safetyAlert ? "SAFETY ALERT" : "changed");

  if (!safetyAlert) lastPublishedDistance = distance;
  seqNumber++;
  yield();
}