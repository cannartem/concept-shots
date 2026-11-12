# ConceptShots

A small Mac app that takes before and after screenshots for you. Give it the link to a new design and the link to the client's current site, and it saves four images: current site and new design, each on a phone and on a desktop.

Made by [productive.studio](https://productive.studio).

## Use

1. Open ConceptShots. A window asks for two links: the new design and the current site (leave the second empty if there is none).
2. Pick the folder where the images go with the "Folder…" button. It is remembered.
3. Each page opens in phone size, then in desktop size. Scroll to the part you want to show and press Enter. Esc skips a frame.
4. When all four are done, Finder opens with the files selected.

Untick "I scroll to each frame myself" and the app takes the first screen of every page on its own. Before taking the shot it scrolls through the page and waits a few seconds, so content that only appears on scroll is there.

## The files

| File | Contents | Size |
| --- | --- | --- |
| `name_old_phone.jpg` | current site, phone | 750x1624 |
| `name_old_desktop.jpg` | current site, desktop | 800x500 |
| `name_new_phone.jpg` | new design, phone | 750x1624 |
| `name_new_desktop.jpg` | new design, desktop | 800x500 |

`name` comes from the last part of the new design link (`example.com/designs/bakery/` gives `bakery`) or from the field in the window. If a file already exists, the app asks before replacing it.

The page language that sites see is set in the window and defaults to `en-US`.

## Install

1. Download `ConceptShots.zip` from the Releases page and unzip it.
2. The app is not signed with a paid Apple certificate, so macOS blocks the first launch. Open System Settings, Privacy & Security, scroll down and press "Open Anyway".

## Use it from Claude Code (MCP)

The zip also contains `mcp_server.py`. Keep it next to `ConceptShots.app` and add it once:

```bash
claude mcp add concept-shots -- python3 /full/path/to/mcp_server.py
```

After that you can ask Claude to take the four screenshots for a link. Two tools are available: `capture_lead_screens` (all four images) and `capture_page` (one image, with a scroll position). Defaults can be changed with environment variables in the server config: `CONCEPTSHOTS_DIR` (folder), `CONCEPTSHOTS_LANG` (browser language) and `CONCEPTSHOTS_NAMES` (`en`, or `cs` for Czech file names). Python 3 is the only thing it needs.

## Good to know

- Pages are drawn with WebKit, the engine of Safari. Tiny differences from Chrome are possible.
- The first screen is captured. Pages that load content late may need a longer wait: pass `wait_seconds` in the MCP tool or use the scroll-yourself mode.
- Nothing is uploaded anywhere. Pages are loaded from your Mac and the images are saved in your folder.

## Build from source

```bash
./build.sh
```

Needs the Swift compiler (Xcode or Command Line Tools).

## License

MIT
