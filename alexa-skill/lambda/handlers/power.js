/**
 * Alexa Power Controller Handler.
 *
 * Handles TurnOn and TurnOff directives for the
 * Alexa.PowerController interface.
 */

const { getUserIdFromToken, sendCommand, getDeviceState } = require('../utils/firebase');

/**
 * Handle power control request (TurnOn/TurnOff).
 */
async function handlePower(request) {
  const directive = request.directive;
  const directiveName = directive.header.name;
  const endpointId = directive.endpoint.endpointId;
  const accessToken = directive.endpoint.scope.token;

  console.log(`Power request: ${directiveName} for endpoint ${endpointId}`);

  try {
    // Get user ID from token
    const userId = await getUserIdFromToken(accessToken);
    const turnOn = directiveName === 'TurnOn';

    // Send the power command
    await sendCommand(userId, {
      type: 'applyJson',
      payload: { on: turnOn },
      controllerId: 'primary',
    });

    // Return success response
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
            namespace: 'Alexa.PowerController',
            name: 'powerState',
            value: turnOn ? 'ON' : 'OFF',
            timeOfSample: new Date().toISOString(),
            uncertaintyInMilliseconds: 500,
          },
        ],
      },
    };
  } catch (error) {
    console.error('Power control error:', error);
    return createErrorResponse(directive, 'INTERNAL_ERROR', error.message);
  }
}

/**
 * Handle ReportState request for power state.
 */
async function reportPowerState(request) {
  const directive = request.directive;
  const endpointId = directive.endpoint.endpointId;
  const accessToken = directive.endpoint.scope.token;

  console.log(`Report state request for endpoint ${endpointId}`);

  try {
    const userId = await getUserIdFromToken(accessToken);
    const state = await getDeviceState(userId);

    return {
      event: {
        header: {
          namespace: 'Alexa',
          name: 'StateReport',
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
            namespace: 'Alexa.PowerController',
            name: 'powerState',
            value: state.on ? 'ON' : 'OFF',
            timeOfSample: new Date().toISOString(),
            uncertaintyInMilliseconds: 1000,
          },
          {
            namespace: 'Alexa.BrightnessController',
            name: 'brightness',
            value: Math.round((state.brightness / 255) * 100),
            timeOfSample: new Date().toISOString(),
            uncertaintyInMilliseconds: 1000,
          },
          {
            namespace: 'Alexa.EndpointHealth',
            name: 'connectivity',
            value: { value: 'OK' },
            timeOfSample: new Date().toISOString(),
            uncertaintyInMilliseconds: 1000,
          },
        ],
      },
    };
  } catch (error) {
    console.error('Report state error:', error);
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

module.exports = { handlePower, reportPowerState };
