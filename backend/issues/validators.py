from django.core.exceptions import ValidationError
from PIL import Image

MAX_IMAGE_SIZE_BYTES = 10 * 1024 * 1024  # 10 MB
# Photos too small to document an issue (e.g. a blank 1x1 test file) and
# pixel-bomb images (enormous uncompressed dimensions) are rejected outright.
MIN_IMAGE_DIMENSION = 320
MAX_IMAGE_PIXELS = 24_000_000  # 24 MP


def validate_issue_image(file):
    """Rejects oversized or non-image uploads before anything is persisted."""
    if file.size > MAX_IMAGE_SIZE_BYTES:
        raise ValidationError("Image file is too large. Maximum size is 10 MB.")
    try:
        file.seek(0)
        image = Image.open(file)
        image.verify()
        file.seek(0)
        # Re-open after verify() (which closes the internal decode) and check
        # real pixel dimensions: image.verify() alone lets a header-only or
        # truncated file through if PIL does not fully decode it.
        image = Image.open(file)
        width, height = image.size
        if width < MIN_IMAGE_DIMENSION or height < MIN_IMAGE_DIMENSION:
            raise ValidationError(
                "Image is too small to identify the issue clearly. "
                "Please upload a clear photo of the reported civic issue."
            )
        if width * height > MAX_IMAGE_PIXELS:
            raise ValidationError(
                "Image resolution is too high. Please upload a photo taken "
                "with a phone camera."
            )
    except ValidationError:
        raise
    except Exception as exc:
        raise ValidationError("Uploaded file is not a valid image.") from exc
    finally:
        file.seek(0)