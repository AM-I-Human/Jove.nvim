import sys
import tkinter as tk
from PIL import Image, ImageTk

def show_image_popup(image_path):
    """
    Displays an image in a Tkinter popup window, creating a thumbnail if it's too large.
    """
    try:
        root = tk.Tk()
        root.title(f"Jove Image Preview: {image_path}")

        # Get screen size to calculate max image dimensions (e.g., 80% of screen)
        max_width = int(root.winfo_screenwidth() * 0.8)
        max_height = int(root.winfo_screenheight() * 0.8)

        pil_image = Image.open(image_path)

        # Create a thumbnail to fit the screen, preserving aspect ratio.
        # This modifies the image in-place.
        # Image.Resampling.LANCZOS is a high-quality downscaling filter.
        pil_image.thumbnail((max_width, max_height), Image.Resampling.LANCZOS)

        tk_image = ImageTk.PhotoImage(pil_image)

        label = tk.Label(root, image=tk_image)
        label.pack()

        # Center the window
        root.update_idletasks()
        width = root.winfo_width()
        height = root.winfo_height()
        x = (root.winfo_screenwidth() // 2) - (width // 2)
        y = (root.winfo_screenheight() // 2) - (height // 2)
        root.geometry(f'{width}x{height}+{x}+{y}')

        root.mainloop()

    except Exception as e:
        # This will be hard to see from Neovim, but good practice.
        print(f"Error displaying image: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    if len(sys.argv) > 1:
        show_image_popup(sys.argv[1])
    else:
        print("Usage: python popup_renderer.py <image_path>", file=sys.stderr)
        sys.exit(1)
