# Volt Guard - App Icons & Splash Screen

## Generated Assets

This directory contains the app icons and splash screen for the Volt Guard application.

### Files

- **icon.png** (1024x1024px) - Main app icon used for generating launcher icons
- **icon.svg** - Vector version of the app icon for future edits
- **splash.png** (1242x2208px) - Splash/launcher screen image
- **loading.png** - Loading indicator (original asset)

### Design

The Volt Guard icon features:
- **Shield symbol** - Represents protection and security
- **Lightning bolt** - Represents electrical power and energy
- **Blue gradient background** - Modern, tech-focused color scheme
- **Energy orbs** - Accent elements suggesting power monitoring

Colors used:
- Primary Blue: `#4A90E2` to `#2563EB`
- Accent Gold: `#FBBF24` to `#F59E0B`
- White/Light Blue for shield: `#FFFFFF` to `#E0E7FF`

## Regenerating Icons

If you need to regenerate the icons:

### 1. Modify the source icon
Edit `icon.png` or regenerate using:
```bash
python generate_icon.py
```

### 2. Update splash screen
Edit `splash.png` or regenerate using:
```bash
python generate_splash.py
```

### 3. Generate launcher icons
After modifying `icon.png`, run:
```bash
flutter pub run flutter_launcher_icons
```

This will automatically generate all required icon sizes for:
- Android (mdpi, hdpi, xhdpi, xxhdpi, xxxhdpi)
- Android Adaptive Icons
- iOS icons (all required sizes)

## Configuration

The launcher icons are configured in `pubspec.yaml`:

```yaml
flutter_launcher_icons:
  android: true
  ios: true
  image_path: "assets/images/icon.png"
  adaptive_icon_background: "#4A90E2"
  adaptive_icon_foreground: "assets/images/icon.png"
  remove_alpha_ios: true
```

## Generated Icon Locations

### Android
- `android/app/src/main/res/mipmap-*/ic_launcher.png`
- `android/app/src/main/res/mipmap-*/ic_launcher_foreground.png` (adaptive)
- `android/app/src/main/res/values/colors.xml` (adaptive background color)

### iOS
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/`

## Requirements

To regenerate icons from Python scripts:
```bash
pip install Pillow
```

## Notes

- Icon design follows Material Design and iOS Human Interface Guidelines
- Adaptive icons provide dynamic theming support on Android 8.0+
- The splash screen can be integrated with `flutter_native_splash` package for native splash screens
- All generated icons are production-ready and optimized
