/**
 * Alexa Brightness Controller Handler.
 *
 * Handles SetBrightness and AdjustBrightness directives for the
 * Alexa.BrightnessController interface.
 */

const { getUserIdFromToken, sendCommand, getDeviceState } = require('../utils/firebase');

/**
 * Handle SetBrightness request.
 * Sets brightness to an absolute percentage (0-100).
 */
async function handleSetBrightness(request) {
  const directive = request.directive;
  const endpointId = directive.endpoint.endpointId;
  const accessToken = directive.endpoint.scope.token;
  const brightnessPercent = directive.payload.brightness;

  console.log(`SetBrightness request: ${brightnessPercent}% for endpoint ${endpointId}`);

  try {
    const userId = await getUserIdFromToken(accessToken);

    // Convert percentage (0-100) to WLED brightness (0-255)
    const wledBrightness = Math.round((brightnessPercent / 100) * 255);

    // Send the brightness command
    await sendCommand(userId, {
      type: 'applyJson',
      payload: { on: true, bri: wledBrightness },
      controllerId: 'primary',
    });

    return {
      event: {
        header: {
          namespace: 'Alexa',
          name: 'Response',
          payloadVersion: '3',
          messageId: generateMessageId(),
          correlationToken: directive.header.correlationToken,
        },
        endpoint: {
          endpointId: endpointId,
        },
        payload: {},
      },
      context: {
        properties: [
          {
            namespace: 'Alexa.BrightnessController',
            name: 'brightness',
            value: brightnessPercent,
            timeOfSample: new Date().toISOString(),
            uncertaintyInMilliseconds: 500,
          },
          {
            namespace: 'Alexa.PowerController',
            name: 'powerState',
            value: 'ON',
            timeOfSample: new Date().toISOString(),
            uncertaintyInMilliseconds: 500,
          },
        ],
      },
    };
  } catch (error) {
    console.error('SetBrightness error:', error);
    return createErrorResponse(directive, 'INTERNAL_ERROR', error.message);
  }
}

/**
 * Handle AdjustBrightness request.
 * Adjusts brightness by a relative percentage (-100 to 100).
 */
async function handleAdjustBrightness(request) {
  const directive = request.directive;
  const endpointId = directive.endpoint.endpointId;
  const accessToken = directive.endpoint.scope.token;
  const brightnessDelta = directive.payload.brightnessDelta;

  console.log(`AdjustBrightness request: ${brightnessDelta}% for endpoint ${endpointId}`);

  try {
    const userId = await getUserIdFromToken(accessToken);

    // Get current state
    const currentState = await getDeviceState(userId);
    const currentPercent = Math.round((currentState.brightness / 255) * 100);

    // Calculate new brightness
    const newPercent = Math.max(0, Math.min(100, currentPercent + brightnessDelta));
    const wledBrightness = Math.round((newPercent / 100) * 255);

    // Send the brightness command
    await sendCommand(userId, {
      type: 'applyJson',
      payload: { on: true, bri: wledBrightness },
      controllerId: 'primary',
    });

    return {
      event: {
        header: {
          namespace: 'Alexa',
          name: 'Response',
          payloadVersion: '3',
          messageId: generateMessageId(),
          correlationToken: directive.header.correlationToken,
        },
        endpoint: {
          endpointId: endpointId,
        },
        payload: {},
      },
      context: {
        properties: [
          {
            namespace: 'Alexa.BrightnessController',
            name: 'brightness',
            value: newPercent,
            timeOfSample: new Date().toISOString(),
            uncertaintyInMilliseconds: 500,
          },
          {
            namespace: 'Alexa.PowerController',
            name: 'powerState',
            value: 'ON',
            timeOfSample: new Date().toISOString(),
            uncertaintyInMilliseconds: 500,
          },
        ],
      },
    };
  } catch (error) {
    console.error('AdjustBrightness error:', error);
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

module.exports = { handleSetBrightness, handleAdjustBrightness };
