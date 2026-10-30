# TABISAKI app icon

`app_icon.png` is the original artwork generated with the built-in image_gen tool.
The opaque green artwork combines a map pin, mountains, sunrise, and a winding
trail to evoke the anticipation of travel.

Regenerate Android, iOS, and Web launcher assets from the project root:

```sh
dart run tool/generate_app_icons.dart
```

The script checks dimensions and RGB output for every generated file. Web
maskable icons include extra safe space. iOS sizes follow the existing asset
catalog. No runtime Flutter asset registration is needed for launcher icons.

## Generation prompt

Use case: logo-brand
Asset type: production square mobile app launcher icon for a travel discovery app.
Primary request: a beautiful green-based icon that makes people want to travel. A single bold cream-white map pin enclosing a simple emerald mountain landscape and a warm small sunrise, with a gently winding cream trail leading toward the mountain. Clean minimal premium flat illustration with subtly rounded geometric shapes, friendly adventurous mood, exceptional legibility at 32px.
Composition: one centered cohesive symbol within the central 62% of the canvas, generous safe margins. Rich forest-green full-bleed solid background extending to all four edges. Square 1024x1024 artwork, NO rounded outer corners or app mockup framing.
Color palette: forest green, fresh emerald, mint highlights, warm cream and a small golden sunrise accent.
Constraints: no text, letters, watermark, border, drop shadow, gradients, tiny details, or extra objects. Opaque background.
