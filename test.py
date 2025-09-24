# %%
import pandas as pd
from matplotlib import pyplot as plt
from PIL import Image

# Per migliorare la qualità dei plot di matplotlib, puoi aumentare i DPI.
# Jupyter usa 'figure.dpi' e 'savefig.dpi' dalla configurazione di matplotlib.
plt.rcParams["figure.dpi"] = 150

Image.open(r"C:\Users\andre\Pictures\Andrea\Small_SALOTTO-CULTURALE_MG_6719.jpg")

plt.plot(pd.DataFrame({"a": list(range(10))}))
# pd.DataFrame({"a": list(range(10))})
# hello = "hello"
# print("hello") or hello

# %%

import os

hello = "hello"

print(os.getcwd())
# print(hello + "world3\nii") or 2
with open("out.ipp") as r:
    print(r.readline)

# %%
from rich.progress import track
import time

for _ in track(range(10)):
    time.sleep(0.2)
