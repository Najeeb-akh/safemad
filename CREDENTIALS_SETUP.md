# Setting Up Google Cloud Credentials

You've already created a Google Cloud project and downloaded your credentials JSON file. Now you need to place it in the correct location for the application to use it.

## Option 1: Place in Project Root (Recommended for Development)

1. Take the JSON file you downloaded from Google Cloud Console
2. Rename it to `google-credentials.json`
3. Place it in the root directory of the project (at `/Users/najeebakh/Desktop/safemad/google-credentials.json`)

```bash
# From your Downloads folder or wherever the file is located
mv ~/Downloads/your-credentials-file.json /Users/najeebakh/Desktop/safemad/google-credentials.json
```

The application will automatically detect the file and use the real Vision API.

## Option 2: Set Environment Variable

Alternatively, you can set the `GOOGLE_APPLICATION_CREDENTIALS` environment variable:

```bash
export GOOGLE_APPLICATION_CREDENTIALS="/Users/najeebakh/Desktop/safemad/google-credentials.json"
```

Add this to your shell profile (e.g., `~/.zshrc` or `~/.bash_profile`) to make it permanent.

## Checking Your Setup

You can verify that credentials are properly set up by running:

```bash
cd /Users/najeebakh/Desktop/safemad
python3 backend/test_vision_api.py /path/to/your/floorplan.jpg
```

If you see "Google Cloud Vision credentials found. Using real Vision API." in the output, it's working correctly.

## Security Note

The `google-credentials.json` file has already been added to `.gitignore` to prevent it from being accidentally committed to version control. Never share this file as it contains sensitive authentication information. 