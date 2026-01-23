/**
 * Alexa Smart Home Discovery Handler.
 *
 * Handles the Alexa.Discovery namespace to discover the user's
 * lighting endpoints (main system and scenes).
 */

const {
  getUserIdFromToken,
  getUserProfile,
  getUserScenes,
} = require('../utils/firebase');

/**
 * Handle discovery request from Alexa.
 * Returns a list of endpoints (devices) that the user can control.
 */
async function handleDiscovery(request) {
  console.log('Discovery request received');

  try {
    // Get user ID from the access token
    const accessToken = request.directive.payload.scope.token;
    const userId = await getUserIdFromToken(accessToken);

    // Get user profile for device naming
    const profile = await getUserProfile(userId);
    const propertyName = profile.propertyName || 'House Lights';

    // Get user's scenes
    const scenes = await getUserScenes(userId);

    // Build the list of endpoints
    const endpoints = [];

    // Main lighting system endpoint
    endpoints.push({
      endpointId: 'lumina-main',
      manufacturerName: 'Nex-Gen Lumina',
      friendlyName: propertyName,
      description: 'Permanent outdoor LED lighting system',
      displayCategories: ['LIGHT'],
      cookie: {
        userId: userId,
        type: 'main',
      },
      capabilities: [
        {
          type: 'AlexaInterface',
          interface: 'Alexa',
          version: '3',
        },
        {
          type: 'AlexaInterface',
          interface: 'Alexa.PowerController',
          version: '3',
          properties: {
            supported: [{ name: 'powerState' }],
            proactivelyReported: false,
            retrievable: true,
          },
        },
        {
          type: 'AlexaInterface',
          interface: 'Alexa.BrightnessController',
          version: '3',
          properties: {
            supported: [{ name: 'brightness' }],
            proactivelyReported: false,
            retrievable: true,
          },
        },
        {
          type: 'AlexaInterface',
          interface: 'Alexa.EndpointHealth',
          version: '3',
          properties: {
            supported: [{ name: 'connectivity' }],
            proactivelyReported: false,
            retrievable: true,
          },
        },
      ],
    });

    // Add scenes as activatable endpoints
    for (const scene of scenes) {
      // Skip system scenes (they're handled by the main endpoint)
      if (scene.type === 'system') continue;

      endpoints.push({
        endpointId: `scene-${scene.id}`,
        manufacturerName: 'Nex-Gen Lumina',
        friendlyName: scene.name,
        description: `Lighting scene: ${scene.name}`,
        displayCategories: ['SCENE_TRIGGER'],
        cookie: {
          userId: userId,
          type: 'scene',
          sceneId: scene.id,
          sceneName: scene.name,
        },
        capabilities: [
          {
            type: 'AlexaInterface',
            interface: 'Alexa',
            version: '3',
          },
          {
            type: 'AlexaInterface',
            interface: 'Alexa.SceneController',
            version: '3',
            supportsDeactivation: false,
            proactivelyReported: false,
          },
        ],
      });
    }

    console.log(`Discovered ${endpoints.length} endpoints for user ${userId}`);

    // Return the discovery response
    return {
      event: {
        header: {
          namespace: 'Alexa.Discovery',
          name: 'Discover.Response',
          payloadVersion: '3',
          messageId: generateMessageId(),
        },
        payload: {
          endpoints: endpoints,
        },
      },
    };
  } catch (error) {
    console.error('Discovery error:', error);

    return {
      event: {
        header: {
          namespace: 'Alexa',
          name: 'ErrorResponse',
          payloadVersion: '3',
          messageId: generateMessageId(),
        },
        payload: {
          type: 'INTERNAL_ERROR',
          message: 'Failed to discover devices',
        },
      },
    };
  }
}

/**
 * Generate a unique message ID for Alexa responses.
 */
function generateMessageId() {
  return 'msg-' + Date.now() + '-' + Math.random().toString(36).substr(2, 9);
}

module.exports = { handleDiscovery };
