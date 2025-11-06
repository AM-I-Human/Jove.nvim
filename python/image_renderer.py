import base64
import io
import sys
import json
import math

# Assicurarsi che Pillow sia disponibile.
try:
    from PIL import Image
except ImportError:
    # Questa è una dipendenza richiesta.
    # In un plugin reale, si dovrebbe gestire questo caso più elegantemente.
    raise

# Assumiamo un rapporto d'aspetto comune per le celle del terminale (larghezza:altezza).
# Molti font monospazio hanno un rapporto vicino a 1:2 (es. 8x16 pixel).
CELL_ASPECT_RATIO = 1 / 2.0

def prepare_iterm_image(image_path, max_width_chars=80):
    """
    Apre un'immagine, calcola le sue dimensioni in celle di terminale per una
    data larghezza massima, la codifica in Base64 e restituisce un oggetto
    JSON con i dati necessari per il rendering e la pulizia.
    """
    try:
        with Image.open(image_path) as img:
            img_w, img_h = img.size
            if img_w == 0 or img_h == 0:
                return json.dumps({"error": "L'immagine ha dimensioni nulle."})

            # Calcola il rapporto d'aspetto dell'immagine in pixel
            image_aspect_in_pixels = img_w / img_h

            # Estrapola il rapporto d'aspetto in celle del terminale
            image_aspect_in_cells = image_aspect_in_pixels / CELL_ASPECT_RATIO

            # Calcola l'altezza finale in celle, arrotondando per eccesso
            final_width_chars = int(max_width_chars)
            final_height_chars = math.ceil(final_width_chars / image_aspect_in_cells)

            with io.BytesIO() as buffer:
                # Convertiamo in RGBA per la massima compatibilità
                img.convert("RGBA").save(buffer, format="PNG")
                image_bytes = buffer.getvalue()
                # La stringa Base64 deve essere decodificata in utf-8 per passarla a Lua.
                b64_data = base64.b64encode(image_bytes).decode('utf-8')

            result = {
                "b64": b64_data,
                "width": final_width_chars,
                "height": int(final_height_chars),
            }
            return json.dumps(result)

    except FileNotFoundError:
        return json.dumps({"error": f"File non trovato: '{image_path}'"})
    except Exception as e:
        # Restituisce il messaggio di errore a Neovim per la notifica.
        return json.dumps({"error": str(e)})
