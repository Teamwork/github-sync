"""Mock Teamwork API for tests/run.sh.

Answers from the fixed data below and records every request it receives, in a
readable form, to the file given as its only argument.
"""
import base64
import json
import re
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

LOG_PATH = sys.argv[1]
AUTHORIZATION = "Basic " + base64.b64encode(b"test-token:").decode()

# Task id -> project id. Requests about any other task fail with a 404.
TASKS = {"1001": 100, "1002": 200, "1003": 300}
# Adding a comment to these tasks fails with a server error.
FAILING_COMMENTS = {"1003"}
# Every project uses the same workflow (id 7), with these stages.
STAGES = {
    str(stage_id): {"id": stage_id, "name": name, "workflow": {"id": 7, "type": "workflows"}}
    for stage_id, name in [(71, "To Do"), (72, "PR Open"), (73, "Ready to Test"), (74, "Rejected")]
}


def render(value, indent=1):
    """Renders a JSON body as indented "key: value" lines. Multi-line strings are
    shown line by line after a "|" gutter, with control characters such as \\r
    shown as their Unicode pictures (␍)."""
    pad = "  " * indent
    if not isinstance(value, dict):
        return [pad + json.dumps(value, ensure_ascii=False)]
    lines = []
    for key in sorted(value):
        item = value[key]
        if isinstance(item, dict):
            lines += [f"{pad}{key}:", *render(item, indent + 1)]
        elif isinstance(item, str) and "\n" in item:
            lines.append(f"{pad}{key}:")
            for line in item.split("\n"):
                line = "".join(chr(0x2400 + ord(c)) if ord(c) < 0x20 else c for c in line)
                lines.append(f"{pad}  | {line}".rstrip())
        else:
            lines.append(f"{pad}{key}: {json.dumps(item, ensure_ascii=False)}")
    return lines


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def handle_request(self):
        raw = self.rfile.read(int(self.headers.get("Content-Length") or 0)).decode()
        status, response, details = self.respond(raw)
        # Record before replying, so the log is complete once the action exits
        with open(LOG_PATH, "a") as log:
            log.write("\n" + "\n".join([f"{self.command} {self.path} -> {status}", *details]) + "\n")

        body = json.dumps(response).encode() if response is not None else b""
        self.send_response(status)
        if body:
            self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    do_GET = do_POST = do_PUT = do_PATCH = handle_request

    def respond(self, raw):
        """Returns the status, response body and recorded details of a request."""
        details = []
        if raw:
            if not self.headers.get("Content-Type", "").startswith("application/json"):
                return 415, {"MESSAGE": "Expected a JSON body"}, ["  " + json.dumps(raw)]
            try:
                details = render(json.loads(raw))
            except ValueError as error:
                return 400, {"MESSAGE": "Invalid JSON"}, [f"  invalid JSON: {error}", "  " + json.dumps(raw)]

        if self.headers.get("Authorization") != AUTHORIZATION:
            return 401, {"MESSAGE": "Unauthorized"}, details

        task = re.search(r"/tasks/(\d+)", self.path)
        if task and task[1] not in TASKS:
            return 404, {"MESSAGE": "Not found"}, details

        request = f"{self.command} {self.path}"
        if task := re.fullmatch(r"GET /projects/api/v1/tasks/(\d+)\.json", request):
            return 200, {"todo-item": {"id": int(task[1]), "project-id": TASKS[task[1]]}}, details
        if re.fullmatch(r"GET /projects/api/v3/workflows\.json\?projectIds=\d+&include=stages", request):
            return 200, {"workflows": [{"id": 7, "name": "Development"}], "included": {"stages": STAGES}}, details
        if task := re.fullmatch(r"POST /tasks/(\d+)/comments\.json", request):
            if task[1] in FAILING_COMMENTS:
                return 500, {"MESSAGE": "Internal server error"}, details
            return 201, {"STATUS": "OK", "commentId": "1"}, details
        if re.fullmatch(r"PUT /tasks/\d+/tags\.json", request):
            return 200, {"STATUS": "OK"}, details
        if re.fullmatch(r"PATCH /projects/api/v3/tasks/\d+/workflows/7\.json", request):
            return 204, None, details
        return 404, {"MESSAGE": "Unknown route"}, details


server = HTTPServer(("", 8080), Handler)
print("listening", flush=True)
server.serve_forever()
