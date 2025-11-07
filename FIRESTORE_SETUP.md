# Firestore Security Rules Setup

## Problem
You're getting a `permission-denied` error because Firestore security rules are not configured.

## Solution

### Step 1: Deploy Firestore Rules

You need to deploy the `firestore.rules` file to your Firebase project. You can do this in two ways:

#### Option A: Using Firebase Console (Recommended for quick setup)

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project: `voicecallingflutter-bb16d`
3. Navigate to **Firestore Database** → **Rules** tab
4. Copy and paste the contents from `firestore.rules` file
5. Click **Publish**

#### Option B: Using Firebase CLI

1. Install Firebase CLI if not already installed:
   ```bash
   npm install -g firebase-tools
   ```

2. Login to Firebase:
   ```bash
   firebase login
   ```

3. Initialize Firebase in your project (if not already done):
   ```bash
   cd /Users/ratnesh.singh/MysaFlutter/mysa_flutter
   firebase init firestore
   ```

4. Deploy the rules:
   ```bash
   firebase deploy --only firestore:rules
   ```

### Step 2: Verify Rules are Active

After deploying, the rules should be active immediately. You can verify by:
- Checking the Firebase Console → Firestore → Rules tab
- The rules should show as "Published"

### Step 3: Test the App

After deploying the rules, restart your app and try making a call again. The permission error should be resolved.

## Security Rules Overview

The rules allow:
- **Authenticated users** to read/write calls where they are the caller or callee
- **Users** to read/write their own FCM tokens
- **Authenticated users** to create FCM notifications

This ensures that:
- Only authenticated users can use the calling feature
- Users can only access calls they're involved in
- Users can only manage their own FCM tokens

## Troubleshooting

If you still get permission errors after deploying:

1. **Check authentication**: Make sure the user is signed in with Firebase Auth
2. **Check user ID**: Verify the user ID matches in both caller and callee
3. **Wait a few seconds**: Rules deployment can take a few seconds to propagate
4. **Check Firebase Console**: Verify the rules are actually published

## Important Notes

- These rules allow any authenticated user to create calls. For production, you may want to add additional validation.
- The rules allow users to read their own FCM tokens, which is necessary for the app to function.
- ICE candidates are accessible to any authenticated user in a call, which is necessary for WebRTC to work.


