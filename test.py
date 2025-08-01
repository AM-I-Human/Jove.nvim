import pandas as pd
from PIL import Image

# Per visualizzare un'immagine in un ambiente Jupyter (come Jove),
# l'oggetto immagine deve essere l'ultima espressione valutata nella cella.
# Il metodo .show() apre il visualizzatore di immagini predefinito del sistema operativo,
# che non è quello che vogliamo per l'integrazione nel terminale.

# Assicurati che il percorso dell'immagine sia corretto.
Image.open(r"C:\Users\andre\Pictures\Andrea\Small_SALOTTO-CULTURALE_MG_6719.jpg")

# Le righe seguenti sono state commentate per isolare il test di visualizzazione dell'immagine.
# Se non commentate, l'output di una di queste righe sovrascriverebbe l'immagine.
#
# pd.DataFrame({"a": list(range(10))})
# hello = "hello"
# print("hello") or hello
# print(hello + "world3\nii") or 2
