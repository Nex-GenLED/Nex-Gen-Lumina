# Lumina Security Implementation Guide

This document outlines all security measures implemented in the Lumina app and deployment instructions.

## Table of Contents
- [Critical Security Features](#critical-security-features)
- [Deployment Checklist](#deployment-checklist)
- [Security Monitoring](#security-monitoring)
- [Incident Response](#incident-response)

---

## Critical Security Features

### 1. OpenAI API Protection ✅

**Implementation:** `functions/index.js` - `openaiProxy` function

**Features:**
- **Rate Limiting:** 10 requests per user per hour
- **Token Limiting:** Max 2000 tokens per request
- **Cost Tracking:** Monitors spending per user
- **Input Sanitization:** Prevents prompt injection
- **Model Validation:** Only allows approved models (gpt-4o, gpt-4o-mini, gpt-3.5-turbo)

**Usage Tracking:**
```firestore
/users/{uid}/ai_usage/{usageId}
  - timestamp: Timestamp
  - status: "success" | "failed"
  - model: string
  - tokensUsed: number
  - estimatedCost: number
  - latency: number
```

**To Deploy:**
1. Set `OPENAI_API_KEY` in Firebase Functions environment:
   ```bash
   cd functions
   echo "OPENAI_API_KEY=sk-..." > .env
   firebase deploy --only functions:openaiProxy
   ```
2. Monitor costs in Firebase Console > Functions > Logs

---

### 2. Data Encryption at Rest ✅

**Implementation:** `lib/services/encryption_service.dart`

**Features:**
- **AES-256-CBC encryption** for sensitive fields
- **Device-specific keys** stored in secure storage
- **One-way hashing** for WiFi SSID (cannot be reversed)
- **Backward compatibility** with unencrypted legacy data

**Encrypted Fields:**
- `address` → `address_encrypted`
- `webhookUrl` → `webhook_url_encrypted`
- `homeSsid` → `home_ssid_hash` (hashed, not encrypted)

**Initialization:**
The encryption service is automatically initialized in `main.dart`:
```dart
await EncryptionService.initialize();
```

**Key Storage:**
- **Android:** Encrypted SharedPreferences
- **iOS:** Keychain with `first_unlock` accessibility

**To Test:**
1. Run `flutter pub get` to install dependencies (`encrypt`, `flutter_secure_storage`, `crypto`)
2. Check logs for "✅ Encryption service initialized"
3. Verify encrypted data in Firestore (should see `*_encrypted` fields)

---

### 3. Firestore Security Rules ✅

**Implementation:** `firestore.rules`

**Key Rules:**
- Users can only read/write their own data
- Critical fields (`owner_id`, `id`, `email`) cannot be modified after creation
- Dealer emails must be from authorized domains
- OAuth codes/tokens are server-side only (no client access)
- Usage logs support 90-day retention (old records can be deleted)

**Authorized Dealer Domains:**
Update in `firestore.rules` line 18:
```javascript
function isValidDealerEmail(email) {
  return email == null ||
         email.matches('.*@nexgenled.com') ||
         email.matches('.*@your-dealer-domain.com'); // ADD YOUR DOMAINS HERE
}
```

**To Deploy:**
```bash
firebase deploy --only firestore:rules
```

**To Test:**
```bash
firebase emulators:start --only firestore
# Run integration tests
```

---

### 4. Alexa OAuth Security ✅

**Implementation:** `functions/index.js` - Alexa OAuth endpoints

**Security Improvements:**
- **Cryptographically secure** authorization codes (32-byte random tokens)
- **Server-side storage** of auth codes in Firestore (not client-side base64)
- **One-time use** codes (marked as `used` after exchange)
- **5-minute expiration** for authorization codes
- **Refresh token revocation** on account unlink

**OAuth Collections:**
```firestore
/oauth_codes/{code}
  - userId: string
  - state: string
  - createdAt: Timestamp
  - expiresAt: Timestamp
  - used: boolean

/oauth_refresh_tokens/{token}
  - userId: string
  - createdAt: Timestamp
  - active: boolean
```

**To Deploy:**
1. Set Alexa credentials in `.env`:
   ```bash
   ALEXA_CLIENT_ID=amzn1.application-oa2-client...
   ALEXA_CLIENT_SECRET=...
   ```
2. Deploy functions:
   ```bash
   firebase deploy --only functions:alexaAuth,functions:alexaToken,functions:alexaUnlink,functions:generateAlexaAuthCode
   ```
3. Update Alexa Skill configuration with your function URLs

---

### 5. Data Retention Policy ✅

**Implementation:** `functions/index.js` - `cleanupOldData` function

**Retention Periods:**
- **AI Usage Logs:** 90 days
- **Pattern Usage Logs:** 90 days
- **Detected Habits:** 90 days
- **Suggestions:** 30 days
- **OAuth Codes:** 1 hour

**Manual Cleanup:**
Call the cleanup function manually (requires auth):
```javascript
const cleanup = firebase.functions().httpsCallable('cleanupOldData');
const result = await cleanup();
console.log(result.data.stats);
```

**Automated Cleanup (Recommended):**
Set up a scheduled Cloud Function:
1. Install Firebase Functions Scheduler extension
2. Schedule `cleanupOldData` to run daily at midnight UTC

**To Deploy:**
```bash
firebase deploy --only functions:cleanupOldData
```

---

### 6. Input Validation ✅

**Implementation:** `lib/utils/input_validation.dart` + `lib/models/user_model.dart`

**Validated Fields:**
- **Display Name:** 1-50 chars, no special characters
- **Email:** Valid format, max 320 chars
- **Phone:** 10-15 digits
- **Address:** Max 200 chars, alphanumeric only
- **Webhook URL:** HTTPS only, max 500 chars
- **WiFi SSID:** Max 32 chars (WiFi standard)
- **Latitude/Longitude:** Valid ranges
- **Build Year:** 1800 to current year + 2

**XSS Prevention:**
All string inputs are sanitized to remove `< > " ' / \` characters.

**No Code Changes Required:**
Validation is automatically applied in `UserModel` constructor.

---

### 7. Permission Rationale Dialogs ✅

**Implementation:** `lib/services/permission_rationale_service.dart`

**Permissions Explained:**
- **Location:** Network discovery, geofencing, sunrise/sunset
- **Background Location:** Arrival/departure automation
- **Camera:** House photos, AR preview
- **Microphone:** Voice commands, AI chat
- **Bluetooth:** Controller setup, BLE provisioning

**Usage:**
```dart
final status = await PermissionRationaleService.requestWithRationale(
  context,
  Permission.location,
);
```

**Shows:**
1. Explanation dialog BEFORE requesting permission
2. Clear reasons why permission is needed
3. Privacy assurances
4. Option to decline

---

### 8. Community Pattern Sharing Consent ✅

**Implementation:** `lib/features/patterns/community_sharing_consent_dialog.dart`

**Features:**
- **Explicit opt-in** (default is OFF)
- **Clear data disclosure** (what's shared vs. not shared)
- **Terms acceptance** checkbox
- **Revocable** at any time in settings

**Usage:**
```dart
final consented = await showCommunitySharingConsentDialog(context);
if (consented == true) {
  // User agreed to share patterns
}
```

---

## Deployment Checklist

### Pre-Launch Security Audit

- [ ] **Firebase Security Rules deployed**
  ```bash
  firebase deploy --only firestore:rules
  ```

- [ ] **Environment Variables Set**
  - [ ] `OPENAI_API_KEY` in functions/.env
  - [ ] `ALEXA_CLIENT_ID` in functions/.env
  - [ ] `ALEXA_CLIENT_SECRET` in functions/.env

- [ ] **Firebase Functions Deployed**
  ```bash
  firebase deploy --only functions
  ```

- [ ] **Encryption Service Initialized**
  - Check app logs for "✅ Encryption service initialized"

- [ ] **Update Firestore Rules for Your Dealer Domains**
  - Edit `firestore.rules` line 18-21
  - Add your authorized dealer email domains

- [ ] **Test Rate Limiting**
  - Make 11 AI requests in 1 hour
  - Verify 11th request is rejected with "rate limit exceeded"

- [ ] **Test Data Retention**
  - Call `cleanupOldData` function
  - Verify old data is deleted

- [ ] **Test Permission Dialogs**
  - Fresh install on device
  - Verify rationale dialogs appear before system permission prompts

- [ ] **Test Input Validation**
  - Try entering `<script>alert('xss')</script>` in profile fields
  - Verify it's sanitized to `scriptalertxssscript`

- [ ] **Enable Firebase App Check** (Recommended)
  - Follow: https://firebase.google.com/docs/app-check
  - Protects against API abuse from non-app clients

---

## Security Monitoring

### Key Metrics to Monitor

1. **OpenAI API Costs**
   - Check Firebase Functions logs for high-cost requests
   - Alert if daily cost > $50

2. **Failed Authentication Attempts**
   - Monitor Firebase Authentication logs
   - Alert on >10 failed logins from same IP

3. **Rate Limit Violations**
   - Search logs for "Rate limit exceeded"
   - Alert on repeated violations from same user

4. **OAuth Token Issues**
   - Monitor "Invalid authorization code" errors
   - May indicate attack or misconfiguration

### Firebase Console Monitoring

**Firestore Usage:**
- Functions > Dashboard > Invocations
- Firestore > Usage

**Function Logs:**
```bash
firebase functions:log --only openaiProxy
firebase functions:log --only cleanupOldData
```

**Set Up Alerts:**
1. Firebase Console > Functions > Metrics
2. Create alert for:
   - Error rate > 5%
   - Execution time > 30s
   - Invocations spike

---

## Incident Response

### Security Incident Types

#### 1. API Key Compromised

**Symptoms:**
- Unexpected OpenAI costs
- Unknown requests in logs

**Response:**
1. **Immediately rotate API key:**
   ```bash
   # Get new key from OpenAI
   cd functions
   echo "OPENAI_API_KEY=sk-NEW_KEY" > .env
   firebase deploy --only functions
   ```
2. Review Firebase Functions logs for unauthorized requests
3. Check if rate limiting prevented damage
4. Consider lowering rate limits temporarily

#### 2. User Data Breach

**Symptoms:**
- Unauthorized Firestore access
- Data exported without permission

**Response:**
1. **Verify Firestore rules are deployed:**
   ```bash
   firebase deploy --only firestore:rules --force
   ```
2. Check Firestore audit logs (Firebase Console > Firestore > Usage)
3. If encryption keys compromised, rotate:
   ```dart
   // In app, call this for affected users
   await EncryptionService.reEncryptUserData(userData);
   ```
4. Notify affected users

#### 3. OAuth Token Theft

**Symptoms:**
- Alexa commands from unknown devices
- Unexpected token refresh requests

**Response:**
1. **Revoke all refresh tokens** for affected user:
   ```javascript
   const tokens = await db.collection("oauth_refresh_tokens")
     .where("userId", "==", affectedUserId)
     .get();

   tokens.forEach(doc => doc.ref.update({ active: false }));
   ```
2. Force user to re-link Alexa skill
3. Check for suspicious commands in logs

#### 4. Denial of Service (DoS)

**Symptoms:**
- Unusual spike in function invocations
- Many requests from single IP/user

**Response:**
1. **Temporarily lower rate limits** in `functions/index.js`:
   ```javascript
   const RATE_LIMIT = 5; // Reduce from 10 to 5
   ```
2. Deploy immediately:
   ```bash
   firebase deploy --only functions:openaiProxy
   ```
3. Block abusive user IDs in Firebase Authentication
4. Consider enabling Firebase App Check

---

## Privacy Compliance

### GDPR / CCPA Requirements

**User Rights Implemented:**
- ✅ **Right to Access:** Users can view all their data in settings
- ✅ **Right to Delete:** Account deletion removes all user data
- ✅ **Right to Portability:** Export feature (implement if needed)
- ✅ **Right to be Forgotten:** Data is deleted, not archived
- ✅ **Consent Management:** Explicit opt-in for pattern sharing

**Data Retention:**
- Usage data: 90 days
- User profile: Until account deletion
- OAuth tokens: Until revoked

**Privacy Policy Updates Needed:**
- Disclose OpenAI API usage for Lumina AI chat
- Explain data encryption practices
- List third-party services (Firebase, OpenAI, Alexa)
- Provide contact for data requests

---

## Security Best Practices

### For Developers

1. **Never commit secrets to Git**
   - Use `.env` files (already in `.gitignore`)
   - Use Firebase Functions environment variables

2. **Always validate user input**
   - Use `InputValidation` class for all user data
   - Never trust client-side validation alone

3. **Keep dependencies updated**
   ```bash
   flutter pub outdated
   flutter pub upgrade
   cd functions && npm audit
   ```

4. **Test security rules locally**
   ```bash
   firebase emulators:start
   ```

5. **Review logs regularly**
   - Check for error spikes
   - Monitor API costs
   - Look for suspicious patterns

### For Users

1. **Strong passwords:**
   - Require 12+ characters
   - Consider implementing password strength checker

2. **Two-factor authentication:**
   - Enable in Firebase Authentication settings
   - Recommend to users in security settings

3. **Regular security audits:**
   - Schedule quarterly reviews
   - Update security rules as needed

---

## Contact

For security issues or questions:
- **Email:** security@nexgenled.com
- **Bug Bounty:** (Set up if needed)

**Report Format:**
```
Subject: [SECURITY] Brief description

Description:
- What the vulnerability is
- How to reproduce
- Potential impact
- Suggested fix (if any)

Please do NOT publicly disclose until patched.
```

---

## Changelog

### 2026-01-23 - Initial Security Implementation
- ✅ OpenAI rate limiting and cost tracking
- ✅ Data encryption for PII (address, webhook URL, SSID)
- ✅ Firestore security rules hardening
- ✅ Alexa OAuth security improvements
- ✅ Data retention policy (90 days)
- ✅ Input validation and XSS prevention
- ✅ Permission rationale dialogs
- ✅ Community sharing consent flow
- ✅ Security headers on all HTTP endpoints

### Future Enhancements
- [ ] Firebase App Check integration
- [ ] Automated security scanning (Dependabot, Snyk)
- [ ] Penetration testing
- [ ] Bug bounty program
- [ ] Two-factor authentication
- [ ] End-to-end encryption for cloud relay
