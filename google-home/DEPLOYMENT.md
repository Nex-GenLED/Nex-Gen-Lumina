# Google Smart Home Action Deployment Guide

This guide covers deploying the Nex-Gen Lumina Google Smart Home Action.

## Prerequisites

1. **Google Cloud Project** - https://console.cloud.google.com
2. **Actions on Google Project** - https://console.actions.google.com
3. **Firebase Project** - Same project as your Flutter app

## Step 1: Create Actions on Google Project

1. Go to [Actions Console](https://console.actions.google.com)
2. Click **New Project**
3. Select your existing Firebase/GCP project
4. Choose **Smart Home** as the action type
5. Click **Start Building**

## Step 2: Configure Smart Home Action

1. In Actions Console, go to **Develop** → **Actions**
2. Add a fulfillment URL (from Step 3)
3. Go to **Account Linking**:
   - Linking type: **OAuth and Google Sign In**
   - OAuth Client ID: Your Firebase Web Client ID
   - OAuth Client Secret: Your client secret (or leave empty)
   - Authorization URL: `https://YOUR_PROJECT.firebaseapp.com/__/auth/handler`
   - Token URL: `https://securetoken.googleapis.com/v1/token?key=YOUR_API_KEY`

## Step 3: Deploy Cloud Functions

### Using Firebase CLI

```bash
cd google-home/functions
npm install

# Deploy to Firebase
firebase deploy --only functions
```

### Verify Deployment

After deployment, you'll get a URL like:
```
https://us-central1-YOUR_PROJECT.cloudfunctions.net/smarthome
```

Enter this URL in the Actions Console fulfillment configuration.

## Step 4: Configure OAuth Credentials

1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Navigate to **APIs & Services** → **Credentials**
3. Create or select an OAuth 2.0 Client ID
4. Add authorized redirect URIs:
   - `https://oauth-redirect.googleusercontent.com/r/YOUR_PROJECT_ID`
   - `https://oauth-redirect-sandbox.googleusercontent.com/r/YOUR_PROJECT_ID`

## Step 5: Enable Home Graph API

1. In Google Cloud Console, go to **APIs & Services** → **Library**
2. Search for "HomeGraph API"
3. Click **Enable**
4. This allows your action to proactively report state changes

## Step 6: Test the Action

### Using the Simulator

1. In Actions Console, go to **Test**
2. Click **Start Testing**
3. Use the simulator or link to your Google Home app

### Using Google Home App

1. Open Google Home app on your phone
2. Tap **+** → **Set up device** → **Works with Google**
3. Search for `[test] Nex-Gen Lumina`
4. Sign in with your Lumina account
5. Try commands:
   - "Hey Google, turn on the house lights"
   - "Hey Google, set the lights to 50%"
   - "Hey Google, activate [scene name]"

## Step 7: Submit for Certification

1. Complete all information in **Deploy** section
2. Provide:
   - Privacy policy URL
   - Terms of service URL
   - App description and images
3. Submit for Google certification review

## Firestore Security Rules

Add these rules to allow the Cloud Function to read/write:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Users collection
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;

      // Commands subcollection
      match /commands/{commandId} {
        allow read, write: if request.auth != null && request.auth.uid == userId;
      }

      // Device state subcollection
      match /device_state/{stateId} {
        allow read, write: if request.auth != null && request.auth.uid == userId;
      }

      // Integrations subcollection
      match /integrations/{integrationId} {
        allow read, write: if request.auth != null && request.auth.uid == userId;
      }

      // Scenes subcollection
      match /scenes/{sceneId} {
        allow read, write: if request.auth != null && request.auth.uid == userId;
      }
    }
  }
}
```

## Cloud Function Structure

```
functions/
├── index.js        # Main Smart Home handlers
└── package.json    # Dependencies
```

## Intents Handled

| Intent | Description |
|--------|-------------|
| `SYNC` | Returns list of devices (light + scenes) |
| `QUERY` | Returns current device state |
| `EXECUTE` | Executes commands (power, brightness, scenes) |
| `DISCONNECT` | Handles account unlinking |

## Supported Device Traits

### Main Light Device
- `action.devices.traits.OnOff` - Turn on/off
- `action.devices.traits.Brightness` - Set brightness 0-100%

### Scene Devices
- `action.devices.traits.Scene` - Activate scene

## Troubleshooting

### "I couldn't find that device"
- Run SYNC: "Hey Google, sync my devices"
- Check Cloud Function logs in Firebase Console
- Verify user has linked account

### "Something went wrong"
- Check Cloud Function logs for errors
- Verify Firestore rules allow access
- Ensure Firebase Admin SDK is properly initialized

### Account linking fails
- Verify OAuth credentials are correct
- Check redirect URIs include Google domains
- Test Firebase auth independently

### Commands don't execute
- Verify `executeWledCommand` Cloud Function is deployed
- Check Firestore `/users/{uid}/commands` collection
- Ensure WLED controller is online and reachable

## State Reporting

The `reportState` function automatically reports state changes to Google when device state updates in Firestore. This keeps Google Home in sync with actual device state.

To trigger state reports:
1. Update `/users/{uid}/device_state/current` in Firestore
2. The function will automatically notify Google Home

## Security Notes

- Keep Firebase service account credentials secure
- Use environment variables for sensitive data
- Enable Cloud Function logging for debugging
- Set appropriate IAM permissions for Cloud Functions
