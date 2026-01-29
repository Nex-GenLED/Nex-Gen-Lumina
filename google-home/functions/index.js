/**
 * Google Smart Home Action for Nex-Gen Lumina.
 *
 * This Cloud Function handles Google Home Smart Home intents:
 * - SYNC: Returns available devices (light + scenes)
 * - QUERY: Returns current device state
 * - EXECUTE: Executes commands (on/off, brightness, scenes)
 * - DISCONNECT: Handles account unlinking
 *
 * Architecture:
 * 1. Google Home sends intent to this Cloud Function
 * 2. Function validates user via Firebase Auth (OAuth token)
 * 3. Function writes command to Firestore /users/{uid}/commands
 * 4. Existing Cloud Function (executeWledCommand) processes command
 * 5. Function returns response to Google Home
 */

const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { smarthome } = require('actions-on-google');

// Initialize Firebase Admin
admin.initializeApp();

const db = admin.firestore();

// Create Smart Home app instance
const app = smarthome({
  debug: true,
});

/**
 * SYNC Intent Handler
 * Called when user says "Hey Google, sync my devices" or links account
 * Returns all available devices (main light system + scenes)
 */
app.onSync(async (body, headers) => {
  const userId = await getUserIdFromHeaders(headers);
  console.log(`SYNC request for user: ${userId}`);

  try {
    const profile = await getUserProfile(userId);
    const scenes = await getUserScenes(userId);
    const propertyName = profile.propertyName || 'House Lights';

    const devices = [];

    // Main lighting system device
    devices.push({
      id: 'lumina-main',
      type: 'action.devices.types.LIGHT',
      traits: [
        'action.devices.traits.OnOff',
        'action.devices.traits.Brightness',
      ],
      name: {
        name: propertyName,
        defaultNames: ['Lumina Lights', 'House Lights'],
        nicknames: [propertyName, 'outdoor lights', 'house lights', 'LED lights'],
      },
      willReportState: true,
      roomHint: 'Outside',
      deviceInfo: {
        manufacturer: 'Nex-Gen Lumina',
        model: 'WLED Controller',
        hwVersion: '1.0',
        swVersion: '1.0',
      },
      customData: {
        userId: userId,
        type: 'main',
      },
    });

    // Add scenes as separate devices
    for (const scene of scenes) {
      if (scene.type === 'system') continue;

      devices.push({
        id: `scene-${scene.id}`,
        type: 'action.devices.types.SCENE',
        traits: ['action.devices.traits.Scene'],
        name: {
          name: scene.name,
          defaultNames: [scene.name],
          nicknames: [scene.name.toLowerCase()],
        },
        willReportState: false,
        attributes: {
          sceneReversible: false,
        },
        customData: {
          userId: userId,
          type: 'scene',
          sceneId: scene.id,
          sceneName: scene.name,
        },
      });
    }

    console.log(`SYNC returning ${devices.length} devices`);

    return {
      requestId: body.requestId,
      payload: {
        agentUserId: userId,
        devices: devices,
      },
    };
  } catch (error) {
    console.error('SYNC error:', error);
    throw error;
  }
});

/**
 * QUERY Intent Handler
 * Called when Google needs current state of devices
 */
app.onQuery(async (body, headers) => {
  const userId = await getUserIdFromHeaders(headers);
  console.log(`QUERY request for user: ${userId}`);

  const { devices } = body.inputs[0].payload;
  const deviceStates = {};

  try {
    // Get current device state from Firestore
    const state = await getDeviceState(userId);

    for (const device of devices) {
      if (device.id === 'lumina-main') {
        deviceStates[device.id] = {
          online: true,
          on: state.on ?? false,
          brightness: Math.round((state.brightness ?? 200) / 255 * 100),
        };
      } else if (device.id.startsWith('scene-')) {
        // Scenes don't have state
        deviceStates[device.id] = {
          online: true,
        };
      }
    }

    return {
      requestId: body.requestId,
      payload: {
        devices: deviceStates,
      },
    };
  } catch (error) {
    console.error('QUERY error:', error);

    // Return offline state on error
    for (const device of devices) {
      deviceStates[device.id] = {
        online: false,
        status: 'ERROR',
        errorCode: 'deviceOffline',
      };
    }

    return {
      requestId: body.requestId,
      payload: {
        devices: deviceStates,
      },
    };
  }
});

/**
 * EXECUTE Intent Handler
 * Called when user issues a command like "turn on the lights"
 */
app.onExecute(async (body, headers) => {
  const userId = await getUserIdFromHeaders(headers);
  console.log(`EXECUTE request for user: ${userId}`);

  const { commands } = body.inputs[0].payload;
  const results = [];

  for (const command of commands) {
    for (const device of command.devices) {
      for (const execution of command.execution) {
        try {
          const result = await executeCommand(userId, device, execution);
          results.push({
            ids: [device.id],
            status: 'SUCCESS',
            states: result,
          });
        } catch (error) {
          console.error(`Execute error for ${device.id}:`, error);
          results.push({
            ids: [device.id],
            status: 'ERROR',
            errorCode: error.code || 'hardError',
          });
        }
      }
    }
  }

  return {
    requestId: body.requestId,
    payload: {
      commands: results,
    },
  };
});

/**
 * DISCONNECT Intent Handler
 * Called when user unlinks their account
 */
app.onDisconnect(async (body, headers) => {
  const userId = await getUserIdFromHeaders(headers);
  console.log(`DISCONNECT request for user: ${userId}`);

  try {
    // Mark Google Home as unlinked in Firestore
    await db
      .collection('users')
      .doc(userId)
      .collection('integrations')
      .doc('google_home')
      .set({
        isLinked: false,
        unlinkedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

    return {};
  } catch (error) {
    console.error('DISCONNECT error:', error);
    throw error;
  }
});

/**
 * Execute a command on a device
 */
async function executeCommand(userId, device, execution) {
  const { command, params } = execution;
  let commandPayload = {};
  let newState = {};

  switch (command) {
    case 'action.devices.commands.OnOff':
      commandPayload = {
        type: 'power',
        payload: { on: params.on },
      };
      newState = { on: params.on };
      break;

    case 'action.devices.commands.BrightnessAbsolute':
      const bri = Math.round(params.brightness / 100 * 255);
      commandPayload = {
        type: 'brightness',
        payload: { brightness: bri, on: true },
      };
      newState = { on: true, brightness: params.brightness };
      break;

    case 'action.devices.commands.ActivateScene':
      const sceneId = device.customData?.sceneId;
      if (!sceneId) {
        throw { code: 'notSupported' };
      }
      commandPayload = {
        type: 'scene',
        payload: { sceneId: sceneId },
      };
      newState = { on: true };
      break;

    default:
      throw { code: 'notSupported' };
  }

  // Send command to Firestore for processing
  await sendCommand(userId, commandPayload);

  return newState;
}

/**
 * Get user ID from OAuth token in headers
 */
async function getUserIdFromHeaders(headers) {
  const authorization = headers.authorization;
  if (!authorization) {
    throw new Error('No authorization header');
  }

  const token = authorization.replace('Bearer ', '');

  try {
    const decodedToken = await admin.auth().verifyIdToken(token);
    return decodedToken.uid;
  } catch (error) {
    console.error('Token verification failed:', error);
    throw new Error('Invalid token');
  }
}

/**
 * Get user profile from Firestore
 */
async function getUserProfile(userId) {
  const doc = await db.collection('users').doc(userId).get();
  return doc.exists ? doc.data() : {};
}

/**
 * Get user's scenes from Firestore
 */
async function getUserScenes(userId) {
  const snapshot = await db
    .collection('users')
    .doc(userId)
    .collection('scenes')
    .get();

  return snapshot.docs.map((doc) => ({
    id: doc.id,
    ...doc.data(),
  }));
}

/**
 * Get current device state from Firestore
 */
async function getDeviceState(userId) {
  const doc = await db
    .collection('users')
    .doc(userId)
    .collection('device_state')
    .doc('current')
    .get();

  return doc.exists ? doc.data() : { on: false, brightness: 200 };
}

/**
 * Send command to Firestore for processing
 */
async function sendCommand(userId, command) {
  await db
    .collection('users')
    .doc(userId)
    .collection('commands')
    .add({
      type: command.type,
      payload: command.payload,
      controllerId: 'primary',
      status: 'pending',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      source: 'google_home',
      expiresAt: new Date(Date.now() + 60000),
    });
}

// Export the fulfillment webhook
exports.smarthome = functions.https.onRequest(app);

// Report state changes to Google
exports.reportState = functions.firestore
  .document('users/{userId}/device_state/current')
  .onWrite(async (change, context) => {
    const userId = context.params.userId;
    const state = change.after.data();

    if (!state) return;

    // Check if user has Google Home linked
    const integrationDoc = await db
      .collection('users')
      .doc(userId)
      .collection('integrations')
      .doc('google_home')
      .get();

    if (!integrationDoc.exists || !integrationDoc.data()?.isLinked) {
      return;
    }

    try {
      const { HomeGraphClient } = require('actions-on-google').smarthome;

      const homeGraphClient = new HomeGraphClient();

      await homeGraphClient.reportState({
        agentUserId: userId,
        payload: {
          devices: {
            states: {
              'lumina-main': {
                online: true,
                on: state.on ?? false,
                brightness: Math.round((state.brightness ?? 200) / 255 * 100),
              },
            },
          },
        },
      });

      console.log(`Reported state for user ${userId}`);
    } catch (error) {
      console.error('Failed to report state:', error);
    }
  });
