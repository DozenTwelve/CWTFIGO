Static landing page: preview with `cd site && python3 -m http.server` (Chinese at `/zh/`), or open `index.html` as a file; deploys by hand to the Cloudflare Pages project `cwtfigo` (direct upload, no Git connection; https://cwtfigo.diamonddoge.org). From a clean checkout of `main`: `npx wrangler pages deploy site --project-name cwtfigo --branch main`.

## Images

Copied from the repo's `assets/` (which is not deployed); recopy them when those change:

- `banner-light.png`, `banner-dark.png` (1280x640): the hero, swapped by `prefers-color-scheme`. The page background (`--color-paper` in `style.css`) is set to each banner's own background colour, so keep the two in step.
- `report.png`, `approve.png`, `tui.png`: the walkthrough's screenshots, letterboxed in its fixed panel. `report.png` is cropped to the summary line and the Health table.
- `robot.png` (206x216, shown at 32px tall): the robot's head, cut from `assets/banner-light.png` at full resolution (x 200, y 96, 206x216) with its flat background made transparent by a flood fill from the top edge and the upper sides (filling from the bottom leaks into the body). It is the favicon, the mark beside the wordmark in the nav and footer of both pages, and the home-screen icon.

Two more PNGs are rendered from `og-image.html`:

- `og-image.png`, 1200x630, the social card (`og:image` on both pages): the banner cropped to its drawing, the headline and the hero's line, centred, with wide margins so it survives cropping and reads as a small thumbnail
- `apple-touch-icon.png`, 180x180, the same page at `og-image.html#icon`: `robot.png` on the paper colour, with no transparency (iOS would fill it with black)

When the banner, the robot or the hero's line changes, edit `og-image.html` and regenerate both from `site/` with any Chrome or Chromium (Playwright's "Google Chrome for Testing" works too):

```sh
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
"$CHROME" --headless --hide-scrollbars --force-device-scale-factor=1 --window-size=1200,630 --screenshot=og-image.png "file://$PWD/og-image.html"
"$CHROME" --headless --hide-scrollbars --force-device-scale-factor=1 --window-size=180,180 --screenshot=apple-touch-icon.png "file://$PWD/og-image.html#icon"
```

`og:image` and `og:url` point at https://cwtfigo.diamonddoge.org (absolute, as crawlers want).

## Fonts

`fonts.css` holds Red Hat Display, Text and Mono (latin subset, SIL OFL, `fonts/OFL.txt`) as base64 data URIs, so they arrive with the stylesheet and also load when the page is opened as a file. Chinese and Japanese come from the system stacks in `style.css` (`--font-cjk`, `--font-ja`).
