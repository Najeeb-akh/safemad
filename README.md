# SafeMad - AI-Powered Emergency Shelter Finder

SafeMad helps Israeli families without a Mamad find the safest location in their home during emergencies by analyzing building structure and materials.

## Core Features (Phase 1)

- Home mapping and floor plan creation
- Material detection through photos
- Safety scoring algorithm
- User authentication and profile management
- Basic safety recommendations

## Project Structure

```
safemad/
├── mobile/           # Flutter mobile application
├── backend/          # FastAPI backend service
└── docs/            # Project documentation
```

## Setup Instructions

### Backend Setup
1. Navigate to the backend directory:
   ```bash
   cd backend
   ```
2. Create a virtual environment:
   ```bash
   python -m venv venv
   source venv/bin/activate  # On Windows: venv\Scripts\activate
   ```
3. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```
4. Run the development server:
   ```bash
   uvicorn main:app --reload
   ```

### Mobile App Setup
1. Navigate to the mobile directory:
   ```bash
   cd mobile
   ```
2. Install Flutter dependencies:
   ```bash
   flutter pub get
   ```
3. Run the app:
   ```bash
   flutter run
   ```

## Development Status

Currently in Phase 1 development, focusing on core features:
- [x] Project structure setup
- [ ] Basic home mapping
- [ ] Material detection
- [ ] Safety scoring
- [ ] User authentication
- [ ] Basic recommendations

## Contributing

Please read our contributing guidelines before submitting pull requests.

## License

This project is licensed under the MIT License - see the LICENSE file for details. 