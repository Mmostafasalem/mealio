# Bowl mascot app icon

The owner approved the almond breakfast-bowl mascot with banana and strawberries,
then requested a finished app logo and its application to the iOS app.

## Reference lock

- Primary source: approved `output/mascot/bowl-with-food-v1.png`.
- Preserve: almond bowl, dusty pink rim and strawberries, navy eyes/smile,
  cream banana/oatmeal, friendly matte clay finish.
- The owner requested the complete mascot after seeing the first close-up icon.
  Preserve both arms, both feet and all food within the icon's safe area; use a
  navy background and softly illuminated navy feet to retain the silhouette.
- Refero research: Headspace (warm, soft illustration and restrained elevation)
  and Finn (navy/pink brand contrast). Their character designs, fonts, palettes
  and page layouts were not copied.
- Reject: letters, slogans, extra characters, icon frames and baked-in outer
  rounded corners. iOS supplies the home-screen icon mask.

## Applied assets

- `smartmarket/Assets.xcassets/AppIcon.appiconset/icon_1024.png`: 1024×1024 RGB,
  opaque PNG; existing AppIcon catalog remains the target's primary icon.
- `smartmarket/Assets.xcassets/BrandLogo.imageset/brand-logo.png`: 288×288
  companion asset for the 96-point welcome-screen brand mark.
- The welcome mark is decorative beside the existing visible app name and is
  hidden from VoiceOver to avoid duplicate announcements.

Generated using the built-in image generator with the approved mascot as an
identity reference. Native image export resized the generated artwork for the
asset catalog. Original master, previous icon backup and generation prompt are
retained locally in `output/brand/` and
`output/mascot/full-mascot-app-icon-prompt.txt`.

References:
- https://headspace.com
- https://petfinn.com
- https://developer.apple.com/design/human-interface-guidelines/app-icons

This logo change does not establish trademark clearance or change the app's name.

## Verification

Final full-mascot Release build and unsigned device archive: 0 warnings/errors.
Strict resource/configuration checks passed. The 60px icon preview retains the
whole mascot and the welcome screen was inspected on a dedicated iPhone simulator.
The exact built-in generation prompt is versioned alongside this note.
