Place a rounded TTF font here for the full rounded look.

Bundled fallback: OpenSans-Regular.ttf is included from the Connect IQ SDK samples and is preferred before built-in faces when available.

Suggested: Nunito (SIL Open Font License). Filename expected by the code: Nunito-Regular.ttf

To add the font:
1. Download Nunito-Regular.ttf from an open-source source (Google Fonts).
2. Copy the file to this directory: resources/fonts/Nunito-Regular.ttf
3. Rebuild the project with the usual `monkeyc` command.

If the font file is present, the app will attempt to load it via Graphics.getVectorFont and use it for the chrono and bezel labels; otherwise the app falls back to system fonts.