FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

EXPOSE 4020

# Keep a small process pool per fetcher service. max-requests periodically
# recycles long-lived curl_cffi/libcurl state so one degraded worker cannot stay
# unhealthy indefinitely. The UA service gets its own identical pool in compose.
CMD ["gunicorn", "--bind", "0.0.0.0:4020", "--workers", "2", "--timeout", "60", "--max-requests", "100", "--max-requests-jitter", "20", "app:app"]
