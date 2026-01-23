/**
 * Alexa Scene Controller Handler.
 *
 * Handles Activate directives for the Alexa.SceneController interface
 * to activate user-defined lighting scenes.
 */

const { getUserIdFromToken, sendCommand, getUserScenes } = require('../utils/firebase');

/**
 * Handle scene activation request.
 */
async function handleActivateScene(request) {
  const directive = request.directive;
  const endpointId = directive.endpoint.endpointId;
  const accessToken = directive.endpoint.scope.token;

  // Extract scene ID from endpoint ID (format: "scene-{sceneId}")
  const sceneId = endpointId.replace('scene-', '');

  console.log(`Activate scene request: ${sceneId}`);

  try {
    const userId = await getUserIdFromToken(accessToken);

    // Get the scene from Firestore
    const scenes = await getUserScenes(userId);
    const scene = scenes.find((s) => s.id === sceneId);

    if (!scene) {
      console.error(`Scene not found: ${sceneId}`);
      return createErrorResponse(directive, 'NO_SUCH_ENDPOINT', 'Scene not found');
    }

    // Build the WLED payload from the scene
    let payload = scene.wled_payload || scene.wledPayload;

    // If no payload exists, build one from scene properties
    if (!payload) {
      payload = {
        on: true,
        bri: scene.brightness || 200,
      };

      // Add effect if present
      if (scene.effect_id || scene.effectId) {
        payload.seg = [
          {
            id: 0,
            fx: scene.effect_id || scene.effectId,
          },
        ];
      }
    }

    // Send the command
    await sendCommand(userId, {
      type: 'applyJson',
      payload: payload,
      controllerId: 'primary',
    });

    console.log(`Scene "${scene.name}" activated successfully`);

    return {
      event: {
        header: {
          namespace: 'Alexa.SceneController',
          name: 'ActivationStarted',
          payloadVersion: '3',
          messageId: generateMessageId(),
          correlationToken: directive.header.correlationToken,
        },
        endpoint: {
          endpointId: endpointId,
        },
        payload: {
          cause: {
            type: 'VOICE_INTERACTION',
          },
          timestamp: new Date().toISOString(),
        },
      },
    };
  } catch (error) {
    console.error('Scene activation error:', error);
    return createErrorResponse(directive, 'INTERNAL_ERROR', error.message);
  }
}

/**
 * Handle scene deactivation request (if supported).
 * For most lighting scenes, this would turn off the lights.
 */
async function handleDeactivateScene(request) {
  const directive = request.directive;
  const endpointId = directive.endpoint.endpointId;
  const accessToken = directive.endpoint.scope.token;

  console.log(`Deactivate scene request: ${endpointId}`);

  try {
    const userId = await getUserIdFromToken(accessToken);

    // Turn off lights when deactivating a scene
    await sendCommand(userId, {
      type: 'applyJson',
      payload: { on: false },
      controllerId: 'primary',
    });

    return {
      event: {
        header: {
          namespace: 'Alexa.SceneController',
          name: 'DeactivationStarted',
          payloadVersion: '3',
          messageId: generateMessageId(),
          correlationToken: directive.header.correlationToken,
        },
        endpoint: {
          endpointId: endpointId,
        },
        payload: {
          cause: {
            type: 'VOICE_INTERACTION',
          },
          timestamp: new Date().toISOString(),
        },
      },
    };
  } catch (error) {
    console.error('Scene deactivation error:', error);
    return createErrorResponse(directive, 'INTERNAL_ERROR', error.message);
  }
}

/**
 * Create an error response.
 */
function createErrorResponse(directive, errorType, message) {
  return {
    event: {
      header: {
        namespace: 'Alexa',
        name: 'ErrorResponse',
        payloadVersion: '3',
        messageId: generateMessageId(),
        correlationToken: directive.header.correlationToken,
      },
      endpoint: {
        endpointId: directive.endpoint.endpointId,
      },
      payload: {
        type: errorType,
        message: message,
      },
    },
  };
}

function generateMessageId() {
  return 'msg-' + Date.now() + '-' + Math.random().toString(36).substr(2, 9);
}

module.exports = { handleActivateScene, handleDeactivateScene };
