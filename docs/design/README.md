# OhMyBoop app icon

The approved design is `ohmyboop-icon-v2.png`: flat blue, yellow, and aqua braces and conversion arrows. The generated source contains a painted checkerboard, so it must not be used directly as the app icon.

`ohmyboop-icon-production.png` has a transparent exterior and three solid interior colors: blue `#2455FF`, yellow `#FFE500`, and aqua `#00F0C8`. Boundary pixels use coverage antialiasing only; there are no gradients, shadows, or material effects.

To regenerate the production PNG and all ten macOS icon slots, run `python3 scripts/generate-app-icon.py` with Pillow installed. The committed assets are in `Resources/Assets.xcassets/AppIcon.appiconset`; normal builds do not require Python or Pillow.

Both `project.yml` and the generated Xcode project include this asset catalog and select `AppIcon`. Build the application with `zsh scripts/build-app.sh`.
