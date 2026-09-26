FROM python:3.14-slim

# torch CPU needs libgomp for its native OpenMP kernels.
RUN apt-get update \
    && apt-get install -y --no-install-recommends libgomp1 \
    && rm -rf /var/lib/apt/lists/*

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    AI_MODEL_DIR=/app/artifacts

WORKDIR /app

# CPU wheels by default (small image, runs anywhere); swap requirements.txt for
# a CUDA build on GPU-capable hosts. See docs/deployment.md for the memory
# constraint (Render free is too small to host torch).
COPY requirements-cpu.txt /app/requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

COPY . /app/

EXPOSE 8000

# Health first, then the API. Heavy models load lazily on first request; the
# container downloads the pinned weights on first warm-up (see app/config.py).
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port $PORT --workers 1"]