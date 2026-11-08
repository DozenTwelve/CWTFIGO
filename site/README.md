Static landing page: preview with `cd site && python3 -m http.server` (Chinese at `/zh/`), or open `index.html` as a file; deploys to Cloudflare Pages as a static directory, build command none, output directory `site`.

## Images

Copied from the repo's `assets/` (which is not deployed); recopy them when those change:

- `banner-light.png`, `banner-dark.png` (1280x640): the hero, swapped by `prefers-color-scheme`. The page background (`--color-paper` in `style.css`) is set to each banner's own background colour, so keep the two in step.
- `report.png`, `approve.png`, `tui.png`: the walkthrough's screenshots, letterboxed in its fixed panel. `report.png` is cropped to the summary line and the Health table.
- `robot.png` (61x64, shown at 32px tall): the robot's head, cut from `assets/banner-light.png` with its flat background made transparent. It is the favicon and the mark beside the wordmark in the nav and footer of both pages.

`mascot.svg` is the older placeholder face. The pages no longer use it, but `og-image.html` still does, so `og-image.png` and `apple-touch-icon.png` still show it; they were left alone. The two PNGs are rendered from `og-image.html`, which shows the mascot next to the headline:

- `og-image.png`, 1200x630, the social card (`og:image` on both pages)
- `apple-touch-icon.png`, 180x180, the same page at `og-image.html#icon`

To swap in the real mascot, replace `mascot.svg` (keep a square viewBox; it may carry its own `prefers-color-scheme` styles), edit `og-image.html` if the card should change, then regenerate the PNGs from `site/` with any Chrome or Chromium:

```sh
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
"$CHROME" --headless --hide-scrollbars --force-device-scale-factor=1 --window-size=1200,630 --screenshot=og-image.png "file://$PWD/og-image.html"
"$CHROME" --headless --hide-scrollbars --force-device-scale-factor=1 --window-size=180,180 --screenshot=apple-touch-icon.png "file://$PWD/og-image.html#icon"
```

`og:image` and `og:url` point at https://cwtf.diamonddoge.org (absolute, as crawlers want).

## Fonts

`fonts.css` holds Red Hat Display, Text and Mono (latin subset, SIL OFL, `fonts/OFL.txt`) as base64 data URIs, so they arrive with the stylesheet and also load when the page is opened as a file. Chinese and Japanese come from the system stacks in `style.css` (`--font-cjk`, `--font-ja`).
