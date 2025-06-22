# Google Cloud Vision API Setup Guide

## Step 1: Create a Google Cloud Project

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select an existing one
3. Note your Project ID

## Step 2: Enable Vision API

1. In the Google Cloud Console, go to "APIs & Services" > "Library"
2. Search for "Cloud Vision API"
3. Click on it and press "Enable"

## Step 3: Create Service Account

1. Go to "IAM & Admin" > "Service Accounts"
2. Click "Create Service Account"
3. Name it "safemad-vision" (or any name you prefer)
4. Grant it the "Cloud Vision API User" role
5. Click "Done"

## Step 4: Generate Service Account Key

1. Click on your newly created service account
2. Go to the "Keys" tab
3. Click "Add Key" > "Create New Key"
4. Choose "JSON" format
5. Download the JSON file

## Step 5: Set Up Authentication

### Option A: Environment Variable (Recommended for Development)
```bash
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/your/service-account-key.json"
```

### Option B: Place in Project Root
1. Rename the downloaded JSON file to `google-credentials.json`
2. Place it in your project root (same level as `backend/` folder)
3. Add to `.gitignore`:
```
google-credentials.json
```

## Step 6: Update Backend Configuration

In `backend/services/vision_service.py`, change:
```python
self.use_dummy = False  # Enable real Google Vision API
```

## Step 7: Install Dependencies

```bash
pip install google-cloud-vision==3.4.5
```

## Step 8: Test the Setup

1. Start your FastAPI server:
```bash
python3 -m uvicorn backend.main:app --reload
```

2. Test the endpoint with Postman:
- POST to `http://localhost:8000/api/analyze-floor-plan`
- Upload a floor plan image
- Check if `processing_method` in response is "google_vision"

## Pricing

- **Free Tier**: 1,000 requests per month
- **After Free Tier**: $1.50 per 1,000 requests
- Perfect for development and testing

## Troubleshooting

1. **Authentication Error**: Make sure `GOOGLE_APPLICATION_CREDENTIALS` points to the correct JSON file
2. **API Not Enabled**: Ensure Cloud Vision API is enabled in your project
3. **Billing**: You may need to enable billing on your Google Cloud project

## Security Notes

- Never commit your service account JSON file to version control
- Use environment variables in production
- Consider using Google Cloud IAM for more granular permissions 