# ConceptShots

A Mac app that takes the screenshots of a web page for you. Paste a link, press one button, and it saves how the page looks on a desktop and on a phone. Need other sizes too? Add them, and they come out in the same run.

Made by [productive.studio](https://productive.studio).

## Use

1. Open ConceptShots and paste the page link.
2. Optional: add extra sizes, for example `768x1024, 1920x1080`. They are remembered.
3. Pick the folder where the images go with the "Folder…" button. It is remembered too.
4. Press "Take shots". The app scrolls through the page so content that appears on scroll is loaded, waits a few seconds, takes every screenshot and opens Finder with the files selected.

Want to choose the exact spot yourself? Tick "I scroll to each frame myself". Each size opens in its own window, you scroll to the part you want and press Enter. Esc skips a frame.

## The files

| File | Contents | Saved size |
| --- | --- | --- |
| `name_desktop.jpg` | desktop, 1440x900 window | 800x500 |
| `name_phone.jpg` | phone, 375 pt wide window | 750x1624 |
| `name_768x1024.jpg` | any size you add (width x height) | exactly that |

`name` comes from the last part of the link (`example.com/designs/bakery/` gives `bakery`) or from the field in the window. If a file already exists, the app asks before replacing it.

Want a before and after? Fill the "Second page" field with the current site. Both pages get the same set, named `name_old_desktop.jpg`, `name_new_desktop.jpg` and so on.

The page language that sites see is set in the window and defaults to `en-US`.

## Install

1. Download `ConceptShots.zip` from the Releases page and unzip it.
2. The app is not signed with a paid Apple certificate, so macOS blocks the first launch. Open System Settings, Privacy & Security, scroll down and press "Open Anyway".

## Use it from Claude Code (MCP)

The zip also contains `mcp_server.py`. Keep it next to `ConceptShots.app` and add it once:

```bash
claude mcp add concept-shots -- python3 /full/path/to/mcp_server.py
```

After that you can ask Claude to take the screenshots of a link. Two tools are available: `capture_lead_screens` (desktop, phone and any sizes you ask for) and `capture_page` (one image, with a scroll position). Defaults can be changed with environment variables in the server config: `CONCEPTSHOTS_DIR` (folder), `CONCEPTSHOTS_LANG` (browser language) and `CONCEPTSHOTS_NAMES` (`en`, or `cs` for Czech file names). Python 3 is the only thing it needs.

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
