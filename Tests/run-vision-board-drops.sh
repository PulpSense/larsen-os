#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p build/tests
sources=(DigitalWall/**/*.swift)
sources=(${sources:#DigitalWall/App/DigitalWallApp.swift})
swiftc -parse-as-library -o build/tests/vision-board-drops "${sources[@]}" Tests/VisionBoardDropTests.swift
fixture_dir=$(mktemp -d)
server_pid=''
trap 'if [[ -n "$server_pid" ]]; then kill "$server_pid" 2>/dev/null || true; fi; rm -rf "$fixture_dir"' EXIT
python3 - "$fixture_dir/port" "$PWD/docs/images/world-clocks.png" <<'PY' &
import http.server, pathlib, sys
image = pathlib.Path(sys.argv[2]).read_bytes()
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        status = 200 if self.path in ('/image', '/not-an-image.png') else 404
        body = image if self.path == '/image' else b'<html>Not an image</html>'
        self.send_response(status)
        # Deliberately misleading to verify validation uses the actual image bytes.
        self.send_header('Content-Type', 'text/html')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args): pass
server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
pathlib.Path(sys.argv[1]).write_text(str(server.server_port))
server.serve_forever()
PY
server_pid=$!
for attempt in {1..100}; do
    [[ -s "$fixture_dir/port" ]] && break
    sleep 0.05
done
build/tests/vision-board-drops "http://127.0.0.1:$(cat "$fixture_dir/port")" "$PWD/docs/images/world-clocks.png"
