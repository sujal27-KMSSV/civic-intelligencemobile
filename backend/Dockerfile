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
# OPTIONAL one-time staff bootstrap for hosts WITHOUT an interactive shell
# (e.g. Render's free web service). It only runs when
# CIVIC_BOOTSTRAP_ADMIN_EMAIL is set, is idempotent (never resets an existing
# password) and is non-fatal (a bad value can never stop the API from serving).
# The generated password is printed ONCE to this service's private deploy logs;
# set CIVIC_ADMIN_PASSWORD to supply your own instead. REMOVE the
# CIVIC_BOOTSTRAP_ADMIN_EMAIL variable once the admin account exists.
CMD ["sh", "-c", "python manage.py migrate --noinput && python manage.py collectstatic --noinput && if [ -n \"$CIVIC_BOOTSTRAP_ADMIN_EMAIL\" ]; then python manage.py bootstrap_admin --email \"$CIVIC_BOOTSTRAP_ADMIN_EMAIL\" ${CIVIC_BOOTSTRAP_ADMIN_SUPERUSER:+--superuser} || echo 'WARNING: bootstrap_admin failed; continuing startup'; fi && gunicorn config.wsgi:application --bind 0.0.0.0:$PORT --workers 3 --timeout 120"]