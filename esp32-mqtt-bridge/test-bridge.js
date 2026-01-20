/**
 * Test script for ESP32 MQTT Bridge
 *
 * This sends a command to the bridge via HiveMQ Cloud to verify
 * the bridge can control WLED remotely.
 */

const mqtt = require('mqtt');

// HiveMQ Cloud configuration (same as bridge)
const MQTT_BROKER = 'mqtts://4429fe3219f64734b912d6bef5d6688b.s1.eu.hivemq.cloud:8883';
const MQTT_USERNAME = 'NexGen';
const MQTT_PASSWORD = 'Grayson8817*';
const DEVICE_ID = 'a55fbb4d-ecea-4c66-aaff-278985528588';

const COMMAND_TOPIC = `lumina/${DEVICE_ID}/command`;
const STATUS_TOPIC = `lumina/${DEVICE_ID}/status`;

// Connect to HiveMQ Cloud
console.log('Connecting to HiveMQ Cloud...');
const client = mqtt.connect(MQTT_BROKER, {
  username: MQTT_USERNAME,
  password: MQTT_PASSWORD,
  rejectUnauthorized: true
});

client.on('connect', () => {
  console.log('Connected to HiveMQ Cloud!');

  // Subscribe to status topic to see responses
  client.subscribe(STATUS_TOPIC, (err) => {
    if (err) {
      console.error('Subscribe error:', err);
    } else {
      console.log(`Subscribed to: ${STATUS_TOPIC}`);
    }
  });

  // Send test command after a short delay
  setTimeout(() => {
    // Toggle WLED on with brightness 128 and a red color
    const command = {
      action: 'setState',
      payload: {
        on: true,
        bri: 128,
        seg: [{ col: [[255, 0, 0]] }]  // Red color
      }
    };

    console.log('\n--- Sending test command ---');
    console.log(`Topic: ${COMMAND_TOPIC}`);
    console.log('Command:', JSON.stringify(command, null, 2));

    client.publish(COMMAND_TOPIC, JSON.stringify(command));
    console.log('Command sent! Waiting for response...\n');
  }, 1000);
});

client.on('message', (topic, message) => {
  console.log('--- Response received ---');
  console.log(`Topic: ${topic}`);
  try {
    const data = JSON.parse(message.toString());
    console.log('Data:', JSON.stringify(data, null, 2).substring(0, 500));
    if (data.on !== undefined) {
      console.log(`\n✓ WLED is ${data.on ? 'ON' : 'OFF'}, brightness: ${data.bri}`);
    }
  } catch (e) {
    console.log('Raw:', message.toString().substring(0, 200));
  }

  // Exit after receiving response
  setTimeout(() => {
    console.log('\nTest complete! Disconnecting...');
    client.end();
    process.exit(0);
  }, 2000);
});

client.on('error', (err) => {
  console.error('MQTT Error:', err.message);
  process.exit(1);
});

// Timeout after 30 seconds
setTimeout(() => {
  console.log('\nTimeout - no response received. Check if bridge is running.');
  client.end();
  process.exit(1);
}, 30000);
