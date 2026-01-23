/**
 * Alexa Smart Home Skill Lambda Handler for Nex-Gen Lumina.
 *
 * This Lambda function handles all Alexa Smart Home directives including:
 * - Device Discovery (Alexa.Discovery)
 * - Power Control (Alexa.PowerController)
 * - Brightness Control (Alexa.BrightnessController)
 * - Scene Activation (Alexa.SceneController)
 * - State Reporting (Alexa.ReportState)
 *
 * Architecture:
 * 1. Alexa sends directive to this Lambda
 * 2. Lambda validates user via Firebase Auth (account linking)
 * 3. Lambda writes command to Firestore /users/{uid}/commands
 * 4. Existing Firebase Cloud Function (executeWledCommand) processes command
 * 5. Lambda returns response to Alexa
 */

const { handleDiscovery } = require('./handlers/discovery');
const { handlePower, reportPowerState } = require('./handlers/power');
const { handleSetBrightness, handleAdjustBrightness } = require('./handlers/brightness');
const { handleActivateScene, handleDeactivateScene } = require('./handlers/scenes');

/**
 * Main Lambda handler.
 */
exports.handler = async (event, context) => {
  console.log('Received Alexa directive:', JSON.stringify(event, null, 2));

  const directive = event.directive;
  const namespace = directive.header.namespace;
  const name = directive.header.name;

  console.log(`Processing: ${namespace}.${name}`);

  try {
    // Route to appropriate handler based on namespace and name
    switch (namespace) {
      case 'Alexa.Discovery':
        return handleDiscovery(event);

      case 'Alexa.PowerController':
        return handlePower(event);

      case 'Alexa.BrightnessController':
        if (name === 'SetBrightness') {
          return handleSetBrightness(event);
        } else if (name === 'AdjustBrightness') {
          return handleAdjustBrightness(event);
        }
        break;

      case 'Alexa.SceneController':
        if (name === 'Activate') {
          return handleActivateScene(event);
        } else if (name === 'Deactivate') {
          return handleDeactivateScene(event);
        }
        break;

      case 'Alexa':
        if (name === 'ReportState') {
          return reportPowerState(event);
        }
        break;

      case 'Alexa.Authorization':
        // Handle account linking grant
        return handleAuthorizationGrant(event);

      default:
        console.log(`Unhandled namespace: ${namespace}`);
    }

    // If we get here, the directive wasn't handled
    return {
      event: {
        header: {
          namespace: 'Alexa',
          name: 'ErrorResponse',
          payloadVersion: '3',
          messageId: generateMessageId(),
        },
        payload: {
          type: 'INVALID_DIRECTIVE',
          message: `Unsupported directive: ${namespace}.${name}`,
        },
      },
    };
  } catch (error) {
    console.error('Handler error:', error);

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
          message: error.message || 'An internal error occurred',
        },
      },
    };
  }
};

/**
 * Handle authorization grant from account linking.
 */
function handleAuthorizationGrant(event) {
  const directive = event.directive;

  console.log('Authorization grant received');

  // The grant contains the access code that can be exchanged for tokens
  // In production, you might want to store this or validate it

  return {
    event: {
      header: {
        namespace: 'Alexa.Authorization',
        name: 'AcceptGrant.Response',
        payloadVersion: '3',
        messageId: generateMessageId(),
      },
      payload: {},
    },
  };
}

/**
 * Generate a unique message ID.
 */
function generateMessageId() {
  return 'msg-' + Date.now() + '-' + Math.random().toString(36).substr(2, 9);
}
