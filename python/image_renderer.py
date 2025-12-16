import base64
import io
import sys
import json
import math

# Assicurarsi che Pillow sia disponibile.
try:
    from PIL import Image
except ImportError:
    raise

CELL_ASPECT_RATIO = 1 / 2.0


def prepare_iterm_image_from_b64(b64_data, max_width_chars=80):
    """
    Calcola le dimensioni di un'immagine da dati base64.
    """
    try:
        image_bytes = base64.b64decode(b64_data)
        with Image.open(io.BytesIO(image_bytes)) as img:
            img_w, img_h = img.size
            if img_w == 0 or img_h == 0:
                return json.dumps({"error": "L'immagine ha dimensioni nulle."})

            image_aspect_in_pixels = img_w / img_h
            image_aspect_in_cells = image_aspect_in_pixels / CELL_ASPECT_RATIO

            final_width_chars = int(max_width_chars)
            final_height_chars = math.ceil(final_width_chars / image_aspect_in_cells)

            # Non ricodifichiamo, usiamo i dati originali
            result = {
                "b64": b64_data,
                "width": final_width_chars,
                "height": int(final_height_chars),
            }
            return json.dumps(result)
    except Exception as e:
        return json.dumps({"error": str(e)})


def prepare_iterm_image(image_path, max_width_chars=80):
    """
    Apre un'immagine da un file, la codifica in Base64 e calcola le dimensioni.
    """
    try:
        with open(image_path, "rb") as f:
            image_bytes = f.read()
            b64_data = base64.b64encode(image_bytes).decode("utf-8")
            return prepare_iterm_image_from_b64(b64_data, max_width_chars)
    except FileNotFoundError:
        return json.dumps({"error": f"File non trovato: '{image_path}'"})
    except Exception as e:
        return json.dumps({"error": str(e)})


if __name__ == "__main__":
    # Legge i dati b64 da stdin e stampa il risultato JSON
    input_data = sys.stdin.read().strip()
    if input_data:
        print(prepare_iterm_image_from_b64(input_data))
