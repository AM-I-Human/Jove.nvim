import sys
import tkinter as tk
from PIL import Image, ImageTk
import base64
import io


def show_image_popup(image_bytes):
    """
    Displays an image from bytes in a Tkinter popup window, creating a thumbnail if it's too large.
    """
    try:
        root = tk.Tk()
        root.title("Jove Image Preview")

        # Get screen size to calculate max image dimensions (e.g., 80% of screen)
        max_width = int(root.winfo_screenwidth() * 0.8)
        max_height = int(root.winfo_screenheight() * 0.8)

        pil_image = Image.open(io.BytesIO(image_bytes))

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
    try:
        # Read base64 data from stdin, decode it, and display the image.
        b64_data = sys.stdin.read()
        if not b64_data:
            raise ValueError("No data received from stdin.")

        image_bytes = base64.b64decode(b64_data)
        show_image_popup(image_bytes)

    except Exception as e:
        print(f"Error processing image from stdin: {e}", file=sys.stderr)
        sys.exit(1)
