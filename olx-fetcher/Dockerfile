FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

EXPOSE 4020

# 2 workers is plenty — the Node backend calls this serially (rate-limited) per
# country. 60s timeout covers a slow OLX page + curl_cffi handshake.
CMD ["gunicorn", "--bind", "0.0.0.0:4020", "--workers", "2", "--timeout", "60", "app:app"]
