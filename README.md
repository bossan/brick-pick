# BrickPick

An iPhone app that helps colour-blind builders pick the right LEGO® brick. Point the
camera at a brick and it names the colour; set a target colour from the manual and it
outlines the bricks that match.

<img src="BrickPick/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="120" alt="BrickPick icon">

## What it does

- **Names the colour** under the circle in the middle of the camera view, using LEGO
  colour names ("Dark Bluish Gray", "Medium Lavender").
- **Finds a target colour**: aim at the brick in the manual and tap *Set target*, or pick
  the colour by name. Matching bricks get a white outline and everything else is dimmed.
  A badge says *Match*, *Maybe* or *Not …*, and the phone taps on a match.
- **Limits colours to your set**: search for a set by number or name and only that set's
  colours are considered. The colour list can be sorted by name or by number of bricks.
- **Corrects for room light**: *Light* turns on the torch, and *Set white* calibrates
  against a sheet of white paper.
- **Learns**: if a brick you know is named wrong, tap *Wrong colour?* and pick the right
  name. The app remembers how that colour looks to the camera.

Nothing relies on telling colours apart: every state is shown with words, symbols and
brightness.

## Privacy

The app makes no network connections. Camera frames are analysed on the phone and never
stored, and the set data ships inside the app.

## Limitations

- It identifies colour, not brick shape.
- Transparent colours are left out; a camera cannot read them reliably.
- Light and dark versions of the same colour (Tan / Dark Tan, the grays) often come out
  as *Maybe*. Lightness counts for little on purpose, because shading changes it so much.
- Anything brick-coloured gets outlined, including a wall or table of that colour, unless
  it fills a large part of the picture.
- It works best on loose bricks from about a hand's width away, after *Set white*.

## Building

Requirements: Xcode 16 or later, an iPhone on iOS 18 or later.

1. Copy `Config/Local.example.xcconfig` to `Config/Local.xcconfig` and fill in your Apple
   Team ID and a bundle ID prefix. That file is ignored by git.
2. Open `BrickPick.xcodeproj` and run on an iPhone.

The simulator needs no signing set-up, but it has no camera, so there the app shows a
fixed test scene of colour swatches instead.

The Xcode project is generated from `project.yml` with
[XcodeGen](https://github.com/yonaskolb/XcodeGen). After changing `project.yml` or adding
files, run:

```sh
xcodegen generate
```

## Tests

```sh
xcodebuild test -project BrickPick.xcodeproj -scheme BrickPick \
  -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
```

The tests cover the colour maths, matching, calibration, the highlight mask and the set
catalogue. The camera pipeline itself can only be tried on a device.

## Updating the set data

`BrickPick/Resources/colors.tsv` and `sets.tsv` are built from
[Rebrickable](https://rebrickable.com/downloads/)'s catalogue. To pick up new sets:

```sh
python3 Scripts/build_set_data.py
```

Then rebuild the app. `Scripts/make_icon.swift` redraws the app icon the same way:

```sh
swift Scripts/make_icon.swift
```

## How it works

| File | Role |
| --- | --- |
| `ColorMath.swift` | sRGB to CIE L\*a\*b\* and the CIEDE2000 colour difference |
| `ColorMatcher.swift` | Palettes, readings, the per-palette lookup table, white calibration |
| `FrameAnalyzer.swift` | Turns a video frame into a reading and the highlight mask |
| `Camera.swift` | Capture session, torch, exposure and white-balance lock |
| `Scanner.swift` | App state: target, chosen set, taught colours |
| `LegoColor.swift`, `LegoSet.swift` | The bundled colour and set tables |
| `ContentView.swift`, `Sheets.swift` | The interface |

## Credits

Set and colour data comes from [Rebrickable](https://rebrickable.com).

LEGO® is a trademark of the LEGO Group, which does not sponsor, authorise or endorse this
app.

## License

[MIT](LICENSE)
