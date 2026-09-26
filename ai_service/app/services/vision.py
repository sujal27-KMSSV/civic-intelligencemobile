"""Image loading and validation (Pillow, no heavy deps)."""

from __future__ import annotations

from io import BytesIO

from PIL import Image, ImageOps

from .. import config
from ..model_registry import ModelUnavailable


class ImageTooLarge(ValueError):
    pass


def load_image(data: bytes) -> Image.Image:
    """Parse raw upload bytes into an RGB image with safe limits.

    Rejects oversized payloads explicitly (a clear 4xx beats a trivially
    forged 'giant' image crashing the worker), and refuses to allocate more
    than ``AI_MAX_IMAGE_DIM`` pixels per side.
    """
    if not data:
        raise ValueError("empty image payload")
    if len(data) > config.MAX_IMAGE_BYTES:
        raise ImageTooLarge(
            f"image exceeds maximum size of {config.MAX_IMAGE_BYTES} bytes"
        )
    try:
        im = Image.open(BytesIO(data))
        im = ImageOps.exif_transpose(im)
        im.load()
    except Exception as exc:
        raise ValueError(f"could not decode image: {exc}") from exc
    w, h = im.size
    if max(w, h) > config.MAX_IMAGE_DIM:
        im.thumbnail((config.MAX_IMAGE_DIM, config.MAX_IMAGE_DIM), Image.LANCZOS)
    return im.convert("RGB")


def describe(im: Image.Image) -> dict:
    return {"width": im.size[0], "height": im.size[1], "format": im.format or "RGB"}