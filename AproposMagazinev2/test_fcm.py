#!/usr/bin/env python3
import json
import requests
import time
import jwt
from datetime import datetime, timedelta

# Configuration
PROJECT_ID = "apropos-magazine-6004a"  # From your Firebase project
FCM_TOKEN = "dBQTcDXlpEJMkyCwSei5mN:APA91bE79THKV1CJT9R7R7pcTkalkIwIbNJcGU5jOExegoZh3w1D7YG8wSMBmYXYnMhjuINZR2qGg35xbY_AtnOXINGyQF_JTAJbjdZJhXTxrF3BvnwSumA"

# You need to replace this with the path to your downloaded service account JSON file
SERVICE_ACCOUNT_PATH = "serviceAccountKey.json"

def load_service_account():
    """Load the service account credentials from JSON file"""
    try:
        with open(SERVICE_ACCOUNT_PATH, 'r') as f:
            return json.load(f)
    except FileNotFoundError:
        print(f"❌ Error: Could not find service account file at {SERVICE_ACCOUNT_PATH}")
        print("Please update SERVICE_ACCOUNT_PATH with the correct path to your JSON file")
        return None

def create_jwt_token(service_account):
    """Create a JWT token for Firebase Admin SDK authentication"""
    now = datetime.utcnow()
    payload = {
        'iss': service_account['client_email'],
        'sub': service_account['client_email'],
        'aud': 'https://oauth2.googleapis.com/token',
        'iat': now,
        'exp': now + timedelta(hours=1),
        'scope': 'https://www.googleapis.com/auth/firebase.messaging'
    }
    
    return jwt.encode(payload, service_account['private_key'], algorithm='RS256')

def get_access_token(jwt_token):
    """Get access token from Google OAuth2"""
    url = 'https://oauth2.googleapis.com/token'
    data = {
        'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        'assertion': jwt_token
    }
    
    response = requests.post(url, data=data)
    if response.status_code == 200:
        return response.json()['access_token']
    else:
        print(f"❌ Error getting access token: {response.text}")
        return None

def send_fcm_notification(access_token):
    """Send FCM notification"""
    url = f'https://fcm.googleapis.com/v1/projects/{PROJECT_ID}/messages:send'
    headers = {
        'Authorization': f'Bearer {access_token}',
        'Content-Type': 'application/json'
    }
    
    message = {
        'message': {
            'token': FCM_TOKEN,
            'notification': {
                'title': 'Test FCM Notification',
                'body': 'This is a test notification from Firebase Cloud Messaging!'
            },
            'data': {
                'click_action': 'FLUTTER_NOTIFICATION_CLICK',
                'id': '1',
                'status': 'done',
                'message': 'This is a test FCM notification from Firebase Cloud Messaging!'
            }
        }
    }
    
    response = requests.post(url, headers=headers, json=message)
    
    if response.status_code == 200:
        print("✅ Successfully sent FCM notification!")
        print(f"Response: {response.json()}")
    else:
        print(f"❌ Error sending notification: {response.status_code}")
        print(f"Response: {response.text}")

def main():
    print("🚀 Testing FCM Notifications...")
    print(f"Project ID: {PROJECT_ID}")
    print(f"FCM Token: {FCM_TOKEN[:50]}...")
    print()
    
    # Load service account
    service_account = load_service_account()
    if not service_account:
        return
    
    print("📋 Service account loaded successfully")
    
    # Create JWT token
    print("🔑 Creating JWT token...")
    jwt_token = create_jwt_token(service_account)
    
    # Get access token
    print("🔐 Getting access token...")
    access_token = get_access_token(jwt_token)
    if not access_token:
        return
    
    print("✅ Access token obtained successfully")
    
    # Send notification
    print("📱 Sending FCM notification...")
    send_fcm_notification(access_token)

if __name__ == "__main__":
    main()
