FROM python:3.14-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY requirements.txt /app/
RUN pip install --no-cache-dir -r requirements.txt

COPY . /app/

RUN mkdir -p /app/staticfiles /app/media

EXPOSE 8000

# Migrate + collectstatic on boot for one-step deploys (idempotent).
#
# OPTIONAL one-time staff bootstrap for hosts WITHOUT a shell, SSH or one-off
# job (e.g. Render's Free web service). It runs only when the strong, private,
# backend-only CIVIC_BOOTSTRAP_SECRET (>= 32 chars) is present, requires
# CIVIC_ADMIN_PASSWORD (so no password is generated or logged), is ONE-TIME
# (a no-op once any staff account exists) and is non-fatal (a bad value can
# never stop the API from serving). REMOVE all three variables after the first
# successful boot. See backend/authority/management/commands/bootstrap_admin.py.
CMD ["sh", "-c", "python manage.py migrate --noinput && python manage.py collectstatic --noinput && if [ -n \"$CIVIC_BOOTSTRAP_SECRET\" ]; then python manage.py bootstrap_admin --unattended --email \"$CIVIC_BOOTSTRAP_ADMIN_EMAIL\" ${CIVIC_BOOTSTRAP_ADMIN_SUPERUSER:+--superuser} || echo 'WARNING: bootstrap_admin failed; continuing startup'; fi && gunicorn config.wsgi:application --bind 0.0.0.0:$PORT --workers 3 --timeout 120"]