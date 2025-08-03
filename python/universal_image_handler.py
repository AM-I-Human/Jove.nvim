import io
import sys
from PIL import Image
import numpy as np


# Funzione centrale che converte un oggetto Pillow Image in Sixel
# (Questa è una versione migliorata della funzione precedente)
def render_pil_image_to_sixel(img, max_colors=255):
    """Converte un oggetto PIL.Image in una stringa Sixel."""

    # 1. Quantizzazione (passo cruciale)
    # Convertiamo in RGBA per gestire la trasparenza, poi quantizziamo.
    # Il metodo MAXCOVERAGE di solito dà i risultati migliori.
    quantized_img = img.convert("RGBA").quantize(
        colors=max_colors, method=Image.Quantize.MAXCOVERAGE
    )
    palette = quantized_img.getpalette()
    pixels = np.array(quantized_img)  # Indici della palette
    width, height = quantized_img.size

    sixel_data = io.StringIO()

    # 2. Scrittura dell'intestazione e della palette Sixel
    sixel_data.write("\x1bPq")  # 7-bit Sixel
    sixel_data.write(f'"1;1;{width};{height}')  # Dimensioni

    if palette:
        for i in range(max_colors):
            if i * 3 + 2 < len(palette):
                r, g, b = palette[i * 3 : i * 3 + 3]
                sixel_data.write(
                    f"#{i};2;{r * 100 // 255};{g * 100 // 255};{b * 100 // 255}"
                )

    # 3. Codifica dei dati dei pixel in sixels
    # (La logica di codifica rimane la stessa della risposta precedente)
    for y in range(0, height, 6):
        # ... logica di codifica per la banda di 6 righe ...
        # (per brevità, si omette la logica RLE già vista)
        bands = {}
        for i in range(6):
            if y + i >= height:
                continue
            for x in range(width):
                color_index = pixels[y + i, x]
                if color_index not in bands:
                    bands[color_index] = np.zeros(width, dtype=int)
                bands[color_index][x] |= 1 << i

        for color_index, data in sorted(bands.items()):
            sixel_data.write(f"#{color_index}")
            last_val = -1
            count = 0
            for val in data:
                if val == last_val:
                    count += 1
                else:
                    if count > 3:
                        sixel_data.write(f"!{count}{chr(last_val + 63)}")
                    else:
                        sixel_data.write(chr(last_val + 63) * count)
                    last_val = val
                    count = 1
            if count > 3:
                sixel_data.write(f"!{count}{chr(last_val + 63)}")
            else:
                sixel_data.write(chr(last_val + 63) * count)

        sixel_data.write("-")

    sixel_data.write("\x1b\\")  # Terminatore
    return sixel_data.getvalue()


# Funzione "Dispatcher" che IPython chiamerà
def universal_sixel_formatter(obj):
    """
    Gestore universale che converte vari tipi di oggetti immagine in Sixel.
    """
    import matplotlib.pyplot as plt
    from matplotlib.figure import Figure
    from PIL import Image as PIL_Image

    pil_img = None

    # Caso 1: È una figura Matplotlib
    if isinstance(obj, Figure):
        with io.BytesIO() as buf:
            obj.savefig(buf, format="png", bbox_inches="tight", pad_inches=0.1)
            buf.seek(0)
            pil_img = PIL_Image.open(buf)
        plt.close(obj)  # Fondamentale per non visualizzarla due volte

    # Caso 2: È già un'immagine Pillow
    elif isinstance(obj, PIL_Image.Image):
        pil_img = obj

    # Caso 3: È un array NumPy (comune con OpenCV, scikit-image)
    elif isinstance(obj, np.ndarray):
        pil_img = PIL_Image.fromarray(obj)

    # Se siamo riusciti a convertirlo in un'immagine Pillow, renderizzala
    if pil_img:
        return render_pil_image_to_sixel(pil_img)

    # Se il tipo non è supportato, solleva un'eccezione per far usare a IPython
    # il formatter di fallback (es. text/plain)
    raise TypeError(f"Nessun formatter Sixel per il tipo {type(obj)}")


def register_sixel_drivers():
    """Registra il nostro gestore universale in IPython per vari tipi."""
    try:
        from IPython import get_ipython
        from matplotlib.figure import Figure
        from PIL import Image as PIL_Image
    except ImportError:
        return  # Non siamo in un ambiente con le dipendenze necessarie

    ipython = get_ipython()
    if not ipython:
        return

    formatter = ipython.display_formatter.formatters["image/sixel"]

    # Registra il nostro dispatcher per tutti i tipi che vogliamo gestire
    formatter.for_type(Figure, universal_sixel_formatter)
    formatter.for_type(PIL_Image.Image, universal_sixel_formatter)
    formatter.for_type(np.ndarray, universal_sixel_formatter)
    print("Jove: Driver di immagine Sixel universali registrati.")


# Chiamare questa funzione all'avvio del kernel
register_sixel_drivers()
