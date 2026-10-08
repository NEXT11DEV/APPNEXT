FROM python:3.12-slim
ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1
WORKDIR /srv
RUN apt-get update && apt-get install -y --no-install-recommends curl openssl ca-certificates && rm -rf /var/lib/apt/lists/*
COPY APPNEXT-Source.zip /tmp/source.zip
RUN python -c 'import zipfile; from pathlib import PurePosixPath; z=zipfile.ZipFile('"'"'/tmp/source.zip'"'"'); assert all(not PurePosixPath(n).is_absolute() and '"'"'..'"'"' not in PurePosixPath(n).parts and PurePosixPath(n).parts[0]=='"'"'APPNEXT'"'"' for n in z.namelist()); z.extractall('"'"'/srv'"'"'); z.close()' && rm /tmp/source.zip
RUN pip install --no-cache-dir -r /srv/APPNEXT/server/requirements.txt
RUN python -c 'from pathlib import Path; Path('"'"'/srv/render_start.py'"'"').write_text('"'"'import os\nimport sys\nfrom pathlib import Path\nfrom urllib.parse import urlparse\nos.environ.setdefault("PUBLIC_URL", os.environ.get("RENDER_EXTERNAL_URL", ""))\nos.environ.setdefault("DATA_DIR", "/srv/data")\nsys.path.insert(0, str(Path(__file__).parent / "APPNEXT" / "server"))\nimport app\nif len(app.TOKEN) < 32:\n    raise SystemExit("Set STORE_TOKEN to a random value of at least 32 characters in Render environment settings")\nif urlparse(app.PUBLIC).scheme != "https" or not urlparse(app.PUBLIC).netloc:\n    raise SystemExit("PUBLIC_URL or RENDER_EXTERNAL_URL must be a public HTTPS origin")\nclass CatalogHandler(app.Handler):\n    def do_GET(self):\n        if urlparse(self.path).path in ("/", "/health"):\n            return self.send_json(200, {"service": "APPNEXT", "status": "ok", "mode": "catalogue"})\n        return super().do_GET()\n    def do_POST(self):\n        if not self.authorized():\n            return self.send_json(401, {"message": "رمز الوصول غير صحيح"})\n        return self.send_json(503, {"message": "خدمة التوقيع لم تفعّل بعد"})\napp.ThreadingHTTPServer.daemon_threads = True\nport = int(os.environ.get("PORT", "10000"))\nprint("APPNEXT catalogue service listening on port", port, flush=True)\napp.ThreadingHTTPServer(("0.0.0.0", port), CatalogHandler).serve_forever()\n'"'"', encoding='"'"'utf-8'"'"')'
RUN mkdir -p /srv/data && chown -R 10001:10001 /srv
USER 10001:10001
EXPOSE 10000
CMD ["python", "-u", "/srv/render_start.py"]
