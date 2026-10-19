"""Run with python3 -m scripts.gallery from the worktree root."""
import argparse
import json
from pathlib import Path
import signal

from .adapter import Gallery, Manifest
from .server import GalleryServer


def main(argv=None, *, root=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', required=True, type=Path,
                        help='Explicit TodayScenes-generated schema 1 JSON file')
    parser.add_argument('--port', default=0, type=int)
    parser.add_argument('--no-watch', action='store_true')
    args = parser.parse_args(argv)
    root = Path(root or Path(__file__).resolve().parents[2]).resolve()
    manifest = Manifest.parse(json.loads(args.manifest.read_text()), root)
    gallery = Gallery(root, manifest)
    server = None
    previous = {}
    def stop(signum, frame):
        gallery.native.cancel.set()
        raise KeyboardInterrupt
    try:
        server = GalleryServer(gallery, port=args.port, watch=not args.no_watch)
        for sig in (signal.SIGINT, signal.SIGTERM):
            previous[sig] = signal.signal(sig, stop)
        print('Gallery: ' + server.url, flush=True)
        print('Evidence: ' + str(gallery.directory), flush=True)
        server.serve_forever(poll_interval=0.2)
    except KeyboardInterrupt:
        pass
    finally:
        if server:
            server.server_close()
        gallery.close()
        for sig, handler in previous.items():
            signal.signal(sig, handler)


if __name__ == '__main__':
    main()
