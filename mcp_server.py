#!/usr/bin/env python3
"""MCP server (stdio) for ConceptShots: lets Claude take screenshots of a page on desktop and on phone, plus custom sizes.

Only the Python standard library is used. Each tool call runs the `shots` binary from ConceptShots.app.
"""
import base64, json, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.path.join(HERE, "ConceptShots.app", "Contents", "MacOS", "shots")
# Defaults can be changed with environment variables in the MCP server config.
DEFAULT_DIR = os.path.expanduser(os.environ.get("CONCEPTSHOTS_DIR", "~/Pictures/ConceptShots"))
DEFAULT_LANG = os.environ.get("CONCEPTSHOTS_LANG", "en-US")
DEFAULT_NAMES = os.environ.get("CONCEPTSHOTS_NAMES", "en")   # en: old/new + phone/desktop, cs: stary_web/koncept + telefon/pocitac

TOOLS = [
    {
        "name": "capture_lead_screens",
        "description": (
            "One call, a set of screenshots of a page: desktop (saved 800x500), phone (saved 750x1624) and any custom sizes. "
            "Saves <name>_desktop.jpg, <name>_phone.jpg and <name>_<W>x<H>.jpg into out_dir (default: CONCEPTSHOTS_DIR or ~/Pictures/ConceptShots). "
            "With old_url the same set is taken for a second page too, named <name>_old_* and <name>_new_* (before and after). "
            "The page is scrolled through first so scroll-revealed content appears, then the first screen is captured. "
            "Refuses to replace existing files unless overwrite is true. With pick=true a window opens for the person at the "
            "computer, who scrolls to each frame and presses Enter."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "concept_url": {"type": "string", "description": "URL of the page to capture"},
                "old_url": {"type": "string", "description": "Optional second page captured the same way, for example the current site"},
                "sizes": {"type": "array", "items": {"type": "string"}, "description": "Extra sizes as WxH in CSS pixels, for example [\"768x1024\", \"1920x1080\"]"},
                "slug": {"type": "string", "description": "File name prefix; taken from the last part of the URL if omitted"},
                "out_dir": {"type": "string", "description": "Folder for the files"},
                "overwrite": {"type": "boolean", "default": False},
                "pick": {"type": "boolean", "default": False, "description": "Let the person choose each frame by scrolling"},
                "wait_seconds": {"type": "number", "default": 5},
                "lang": {"type": "string", "description": "Browser language the sites see (default CONCEPTSHOTS_LANG or en-US)"},
                "names": {"type": "string", "enum": ["en", "cs"], "description": "File name language; en is the default, cs gives stary_web/koncept/telefon/pocitac"},
                "return_images": {"type": "boolean", "default": False, "description": "Also return the images so they can be checked"},
            },
            "required": ["concept_url"],
        },
    },
    {
        "name": "capture_page",
        "description": (
            "Screenshot one page as JPEG on phone (375 pt wide, saved 750x1624), desktop (1440x900, saved 800x500) or a custom WxH size. "
            "Scrolls through the page, scrolls to scroll_y, waits, then captures the visible screen."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "url": {"type": "string"},
                "device": {"type": "string", "description": "phone, desktop, or a custom size such as 1024x768"},
                "out_path": {"type": "string", "description": "Where to save the .jpg"},
                "scroll_y": {"type": "number", "default": 0, "description": "Scroll position in CSS pixels"},
                "wait_seconds": {"type": "number", "default": 5},
                "lang": {"type": "string", "description": "Browser language (default CONCEPTSHOTS_LANG or en-US)"},
                "return_image": {"type": "boolean", "default": True},
            },
            "required": ["url", "device", "out_path"],
        },
    },
]


def run(args, pick):
    if not os.path.exists(BIN):
        return [{"ok": False, "error": f"binary not found: {BIN}. Run build.sh in {HERE}."}]
    try:
        p = subprocess.run([BIN] + args, capture_output=True, text=True, timeout=None if pick else 300)
    except subprocess.TimeoutExpired:
        return [{"ok": False, "error": "timed out"}]
    out = []
    for line in p.stdout.splitlines():
        try:
            out.append(json.loads(line))
        except json.JSONDecodeError:
            pass
    if not out:
        out.append({"ok": False, "error": (p.stderr or "no output").strip()[-500:]})
    return out


def image_block(path):
    with open(path, "rb") as f:
        return {"type": "image", "data": base64.b64encode(f.read()).decode(), "mimeType": "image/jpeg"}


def call(name, a):
    if name == "capture_page":
        out = os.path.expanduser(a["out_path"])
        args = ["capture", "--url", a["url"], "--device", a["device"], "--out", out,
                "--scroll", str(a.get("scroll_y", 0)), "--wait", str(a.get("wait_seconds", 5)),
                "--lang", a.get("lang", DEFAULT_LANG)]
        res = run(args, False)
        content = [{"type": "text", "text": json.dumps(res, ensure_ascii=False)}]
        if a.get("return_image", True):
            content += [image_block(r["path"]) for r in res if r.get("ok")]
        return content, not all(r.get("ok") for r in res)

    if name == "capture_lead_screens":
        pick = bool(a.get("pick", False))
        args = ["lead", "--concept", a["concept_url"], "--dir", os.path.expanduser(a.get("out_dir") or DEFAULT_DIR),
                "--wait", str(a.get("wait_seconds", 5)), "--lang", a.get("lang", DEFAULT_LANG),
                "--names", a.get("names", DEFAULT_NAMES)]
        if a.get("old_url"):
            args += ["--old", a["old_url"]]
        if a.get("sizes"):
            args += ["--sizes", ",".join(a["sizes"])]
        if a.get("slug"):
            args += ["--slug", a["slug"]]
        if a.get("overwrite"):
            args.append("--force")
        if pick:
            args.append("--pick")
        res = run(args, pick)
        content = [{"type": "text", "text": json.dumps(res, ensure_ascii=False)}]
        if a.get("return_images"):
            content += [image_block(r["path"]) for r in res if r.get("ok") and r.get("path")]
        return content, not all(r.get("ok") for r in res)

    raise KeyError(name)


def reply(msg_id, result=None, error=None):
    m = {"jsonrpc": "2.0", "id": msg_id}
    if error is not None:
        m["error"] = error
    else:
        m["result"] = result
    sys.stdout.write(json.dumps(m) + "\n")
    sys.stdout.flush()


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue
        mid, method, params = msg.get("id"), msg.get("method"), msg.get("params") or {}
        if mid is None:
            continue  # notifications need no answer
        try:
            if method == "initialize":
                reply(mid, {
                    "protocolVersion": params.get("protocolVersion", "2025-06-18"),
                    "capabilities": {"tools": {}},
                    "serverInfo": {"name": "concept-shots", "version": "1.0.0"},
                })
            elif method == "ping":
                reply(mid, {})
            elif method == "tools/list":
                reply(mid, {"tools": TOOLS})
            elif method == "tools/call":
                try:
                    content, is_error = call(params["name"], params.get("arguments") or {})
                    reply(mid, {"content": content, "isError": is_error})
                except KeyError as e:
                    reply(mid, error={"code": -32602, "message": f"unknown tool or missing argument: {e}"})
            else:
                reply(mid, error={"code": -32601, "message": f"method not found: {method}"})
        except Exception as e:  # keep the server alive whatever happens in one call
            reply(mid, {"content": [{"type": "text", "text": f"error: {e}"}], "isError": True})


if __name__ == "__main__":
    main()
