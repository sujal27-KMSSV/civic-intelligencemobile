from django.core.exceptions import ValidationError
from PIL import Image

MAX_IMAGE_SIZE_BYTES = 10 * 1024 * 1024  # 10 MB


def validate_issue_image(file):
    """Rejects oversized or non-image uploads before anything is persisted."""
    if file.size > MAX_IMAGE_SIZE_BYTES:
        raise ValidationError("Image file is too large. Maximum size is 10 MB.")
    try:
        file.seek(0)
        image = Image.open(file)
        image.verify()
    except Exception as exc:
        raise ValidationError("Uploaded file is not a valid image.") from exc
    finally:
        file.seek(0)