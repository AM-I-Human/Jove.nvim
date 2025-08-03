import base64
import io
import sys

# Assicurarsi che Pillow sia disponibile.
try:
    from PIL import Image
except ImportError:
    # Questa è una dipendenza richiesta.
    # In un plugin reale, si dovrebbe gestire questo caso più elegantemente.
    raise

def prepare_iterm_image(image_path):
    """
    Apre un'immagine, la converte in un buffer di byte PNG,
    e restituisce la stringa codificata in Base64.
    """
    try:
        with Image.open(image_path) as img:
            with io.BytesIO() as buffer:
                # Convertiamo in RGBA per assicurarci che anche immagini con palette
                # o in scala di grigi siano gestite correttamente e abbiano un canale alpha.
                img.convert("RGBA").save(buffer, format="PNG")
                image_bytes = buffer.getvalue()
                # La stringa Base64 deve essere decodificata in utf-8 per passarla a Lua.
                return base64.b64encode(image_bytes).decode('utf-8')
    except FileNotFoundError:
        return f"Error: File not found at '{image_path}'"
    except Exception as e:
        # Restituisce il messaggio di errore a Neovim per la notifica.
        return f"Error: {str(e)}"
