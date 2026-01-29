# Amazon Alexa Skill Deployment Guide

This guide covers deploying the Nex-Gen Lumina Alexa Smart Home Skill.

## Prerequisites

1. **Amazon Developer Account** - https://developer.amazon.com
2. **AWS Account** - For Lambda function hosting
3. **Firebase Project** - For authentication and command relay

## Step 1: Create the Alexa Skill

1. Go to [Alexa Developer Console](https://developer.amazon.com/alexa/console/ask)
2. Click **Create Skill**
3. Enter skill name: `Nex-Gen Lumina`
4. Choose **Smart Home** as the skill type
5. Click **Create Skill**

## Step 2: Configure Smart Home Skill

1. In the skill configuration, note your **Skill ID** (starts with `amzn1.ask.skill.`)
2. Go to **Smart Home** section
3. Set the **Default endpoint** to your Lambda ARN (from Step 3)

## Step 3: Deploy Lambda Function

### Option A: AWS Console

1. Go to [AWS Lambda Console](https://console.aws.amazon.com/lambda)
2. Click **Create Function**
3. Choose **Author from scratch**
4. Configure:
   - Function name: `lumina-alexa-handler`
   - Runtime: Node.js 18.x
   - Architecture: x86_64
5. Upload the `lambda` folder as a ZIP file
6. Set environment variables:
   - `FIREBASE_SERVICE_ACCOUNT`: Your Firebase service account JSON (stringified)
7. Add Alexa Smart Home trigger:
   - Application ID: Your Skill ID from Step 2

### Option B: Serverless Framework

```bash
cd alexa-skill/lambda
npm install
serverless deploy
```

## Step 4: Configure Account Linking

In the Alexa Developer Console, go to **Account Linking**:

1. **Authorization URI**: `https://YOUR_FIREBASE_PROJECT.firebaseapp.com/__/auth/handler`
2. **Access Token URI**: `https://securetoken.googleapis.com/v1/token?key=YOUR_FIREBASE_API_KEY`
3. **Client ID**: Your Firebase Web Client ID
4. **Client Secret**: Leave empty or use Firebase client secret
5. **Scope**: `email`, `openid`, `profile`
6. **Authorization Grant Type**: Auth Code Grant

### Firebase Auth Configuration

1. In Firebase Console, go to **Authentication** → **Sign-in method**
2. Enable **Email/Password** and any other providers
3. Go to **Settings** → **Authorized domains**
4. Add `pitangui.amazon.com` and `layla.amazon.com`

## Step 5: Update Flutter App

Update the skill ID in `lib/features/voice/alexa_service.dart`:

```dart
static const String skillId = 'amzn1.ask.skill.YOUR_ACTUAL_SKILL_ID';
```

## Step 6: Test the Skill

1. In Alexa Developer Console, go to **Test**
2. Enable testing for **Development**
3. Try commands:
   - "Alexa, discover my devices"
   - "Alexa, turn on the house lights"
   - "Alexa, set house lights to 50%"

## Step 7: Submit for Certification

1. Complete all skill information in **Distribution**
2. Provide privacy policy URL
3. Submit for Amazon certification review

## Troubleshooting

### "No devices found"
- Check Lambda CloudWatch logs
- Verify Firebase service account permissions
- Ensure user has completed account linking

### "Device is not responding"
- Check Cloud Function `executeWledCommand` is deployed
- Verify Firestore rules allow command writes
- Check WLED controller is online

### Account linking fails
- Verify Firebase authorized domains include Amazon domains
- Check OAuth configuration matches Firebase setup
- Test Firebase auth independently

## Lambda Function Structure

```
lambda/
├── index.js           # Main router
├── handlers/
│   ├── discovery.js   # Device discovery
│   ├── power.js       # On/Off control
│   ├── brightness.js  # Brightness control
│   └── scenes.js      # Scene activation
├── utils/
│   └── firebase.js    # Firebase Admin SDK
└── package.json
```

## Security Notes

- Never commit Firebase service account keys to git
- Use AWS Secrets Manager for production credentials
- Enable Lambda function logging for debugging
- Set appropriate Firestore security rules
