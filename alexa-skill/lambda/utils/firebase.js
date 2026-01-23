/**
 * Firebase Admin SDK initialization for Alexa Skill.
 *
 * This module handles:
 * - Firebase Admin SDK initialization
 * - User lookup from Alexa access token
 * - Controller and scene retrieval from Firestore
 */

const admin = require('firebase-admin');

// Initialize Firebase Admin SDK
// In production, use environment variables or AWS Secrets Manager for credentials
let firebaseInitialized = false;

function initializeFirebase() {
  if (firebaseInitialized) return;

  // For Lambda, credentials can be set via environment variables
  // or by including a service account JSON file
  if (process.env.FIREBASE_SERVICE_ACCOUNT) {
    const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });
  } else {
    // Try to use default credentials (for local development)
    admin.initializeApp({
      credential: admin.credential.applicationDefault(),
    });
  }

  firebaseInitialized = true;
}

/**
 * Get user ID from Alexa access token.
 * The access token contains the Firebase UID after account linking.
 */
async function getUserIdFromToken(accessToken) {
  initializeFirebase();

  try {
    // The access token is a Firebase custom token or ID token
    // We need to verify it and extract the user ID
    const decodedToken = await admin.auth().verifyIdToken(accessToken);
    return decodedToken.uid;
  } catch (error) {
    console.error('Error verifying access token:', error);
    throw new Error('Invalid access token');
  }
}

/**
 * Get user's controllers from Firestore.
 */
async function getUserControllers(userId) {
  initializeFirebase();

  const db = admin.firestore();
  const snapshot = await db
    .collection('users')
    .doc(userId)
    .collection('controllers')
    .get();

  return snapshot.docs.map((doc) => ({
    id: doc.id,
    ...doc.data(),
  }));
}

/**
 * Get user's scenes from Firestore.
 */
async function getUserScenes(userId) {
  initializeFirebase();

  const db = admin.firestore();
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
 * Get user profile from Firestore.
 */
async function getUserProfile(userId) {
  initializeFirebase();

  const db = admin.firestore();
  const doc = await db.collection('users').doc(userId).get();

  if (!doc.exists) {
    throw new Error('User not found');
  }

  return doc.data();
}

/**
 * Send a command to the user's lighting system via Firestore.
 * The command will be picked up by a Cloud Function and executed.
 */
async function sendCommand(userId, command) {
  initializeFirebase();

  const db = admin.firestore();

  // Create a command document that the executeWledCommand Cloud Function will process
  const commandRef = await db
    .collection('users')
    .doc(userId)
    .collection('commands')
    .add({
      type: command.type,
      payload: command.payload,
      controllerId: command.controllerId || 'primary',
      status: 'pending',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      source: 'alexa',
      expiresAt: new Date(Date.now() + 60000), // Expire in 1 minute
    });

  console.log(`Command sent: ${commandRef.id}`);
  return commandRef.id;
}

/**
 * Get the current state of the user's lighting system.
 */
async function getDeviceState(userId) {
  initializeFirebase();

  const db = admin.firestore();

  // Get the most recent state snapshot
  const snapshot = await db
    .collection('users')
    .doc(userId)
    .collection('device_state')
    .doc('current')
    .get();

  if (!snapshot.exists) {
    // Return default state if no state exists
    return {
      on: false,
      brightness: 200,
      lastUpdated: new Date(),
    };
  }

  return snapshot.data();
}

module.exports = {
  initializeFirebase,
  getUserIdFromToken,
  getUserControllers,
  getUserScenes,
  getUserProfile,
  sendCommand,
  getDeviceState,
};
