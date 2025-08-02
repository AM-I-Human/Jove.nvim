import jupyter_client
import json
import sys
import threading
import time
import os
from queue import Empty
import base64
import io

try:
    from PIL import Image
except ImportError:
    Image = None

try:
    from sixel import SixelWriter
except ImportError:
    SixelWriter = None

# Configurazione del logging (semplice, per debug)
LOG_FILE_PATH = os.path.join(os.path.expanduser("~"), "jove_py_client.log")


def log_message(message):
    # Appends a message to the log file with a timestamp.
    with open(LOG_FILE_PATH, "a") as f:
        f.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} - {message}\n")


class KernelClient:
    def __init__(self, connection_file_path, image_width=80, image_renderer="sixel"):
        log_message(
            f"Initializing KernelClient with connection file: {connection_file_path}, image width: {image_width}, renderer: {image_renderer}"
        )
        self.image_width = image_width
        self.image_renderer = image_renderer
        try:
            self.kc = jupyter_client.BlockingKernelClient(
                connection_file=connection_file_path
            )
            self.kc.load_connection_file()
            self.kc.start_channels()
            log_message("IOPub and Shell channels started.")
        except Exception as e:
            log_message(f"Failed to start jupyter_client.KernelClient: {e}")
            self.send_to_lua(
                {"type": "error", "message": f"Failed to start KernelClient: {e}"}
            )
            sys.exit(1)

        self.stop_event = threading.Event()
        self.kernel_listener_thread = threading.Thread(
            target=self._listen_kernel, daemon=True
        )
        self.kernel_listener_thread.start()
        log_message("Kernel listener thread started.")
        self.send_to_lua(
            {
                "type": "status",
                "message": "connected",
                "kernel_info": self.kc.get_connection_info(),
            }
        )

    def _listen_kernel(self):
        log_message("Kernel listener thread running.")
        while not self.stop_event.is_set():
            try:
                # Block on iopub for a while, then check shell.
                try:
                    msg = self.kc.get_iopub_msg(timeout=0.1)
                    msg_type = msg.get("header", {}).get("msg_type", "unknown")
                    log_message(f"IOPub received: {msg_type}")

                    if msg_type in ("display_data", "execute_result"):
                        data = msg.get("content", {}).get("data", {})
                        if (
                            "image/png" in data
                            or "image/jpeg" in data
                            or "image/gif" in data
                        ):
                            if self.handle_image_output(data):
                                continue  # Immagine gestita, salta l'invio del messaggio originale

                    self.send_to_lua({"type": "iopub", "message": msg})
                except Empty:
                    pass  # No message on iopub, that's fine.

                # Check shell channel without blocking
                try:
                    msg = self.kc.get_shell_msg(timeout=0)
                    msg_type = msg.get("header", {}).get("msg_type", "unknown")
                    log_message(f"Shell received: {msg_type}")
                    self.send_to_lua({"type": "shell", "message": msg})
                except Empty:
                    pass  # No message on shell

            except Exception as e:
                log_message(f"Kernel Listener thread error: {e}")

    def send_to_lua(self, data):
        # Sends a JSON-serialized message to the Lua parent process via stdout.
        try:
            json_data = json.dumps(data, default=repr)
            sys.stdout.write(json_data + "\n")
            sys.stdout.flush()
        except Exception as e:
            log_message(f"Error sending data to Lua: {e} (Data was: {str(data)[:200]})")

    def _render_to_ansi(self, img, target_width):
        w, h = img.size
        aspect_ratio = h / w
        new_w = target_width
        new_h_chars = int(new_w * aspect_ratio / 2)
        new_h_pixels = new_h_chars * 2
        if new_h_pixels == 0:
            return None

        resized_img = img.resize((new_w, new_h_pixels), Image.Resampling.LANCZOS)
        ansi_lines = []
        for y in range(0, new_h_pixels, 2):
            line_str = []
            for x in range(new_w):
                top_r, top_g, top_b = resized_img.getpixel((x, y))
                bot_r, bot_g, bot_b = resized_img.getpixel((x, y + 1))
                ansi_esc = f"\x1b[38;2;{top_r};{top_g};{top_b}m"
                ansi_esc += f"\x1b[48;2;{bot_r};{bot_g};{bot_b}m"
                ansi_esc += "▄"
                line_str.append(ansi_esc)
            ansi_lines.append("".join(line_str) + "\x1b[0m")
        return "\n".join(ansi_lines)

    def _render_to_sixel(self, img, target_width):
        if not SixelWriter:
            log_message("libsixel-python not installed. Cannot use Sixel renderer.")
            return None

        w, h = img.size
        aspect_ratio = h / w
        new_w = target_width
        new_h = int(new_w * aspect_ratio)
        if new_h == 0:
            return None
        
        resized_img = img.resize((new_w, new_h), Image.Resampling.LANCZOS)
        
        d = io.BytesIO()
        writer = SixelWriter(d)
        writer.draw(resized_img)
        return d.getvalue().decode('ascii')

    def handle_image_output(self, data):
        target_width = self.image_width
        if not Image:
            log_message("Pillow library not installed.")
            return False

        b64_data = (
            data.get("image/png") or data.get("image/jpeg") or data.get("image/gif")
        )
        if not b64_data:
            return False

        try:
            image_data = base64.b64decode(b64_data)
            img = Image.open(io.BytesIO(image_data)).convert("RGB")
            
            output_str = None
            output_type = None

            if self.image_renderer == 'sixel':
                output_str = self._render_to_sixel(img, target_width)
                output_type = "image_sixel"
            
            # Fallback to ANSI if Sixel fails or is not chosen
            if not output_str:
                output_str = self._render_to_ansi(img, target_width)
                output_type = "image_ansi"

            if output_str:
                self.send_to_lua({"type": output_type, "payload": output_str})
                return True

        except Exception as e:
            log_message(f"Error processing image with Pillow: {e}")
        
        return False


    def send_execute_request(self, jupyter_msg_payload):
        log_message("Preparing to send execute_request.")
        try:
            content = jupyter_msg_payload.get("content", {})
            code = content.get("code")
            if not code:
                log_message("Error: execute_request content is missing or malformed.")
                self.send_to_lua(
                    {
                        "type": "error",
                        "message": "Execute request content missing 'code'.",
                    }
                )
                return

            self.kc.execute(
                code=code,
                silent=content.get("silent", False),
                store_history=content.get("store_history", True),
                user_expressions=content.get("user_expressions", {}),
                allow_stdin=content.get("allow_stdin", False),
                stop_on_error=content.get("stop_on_error", True),
            )
            log_message(
                f"Execute request for code '{code[:50]}...' sent via KernelClient."
            )
        except Exception as e:
            log_message(f"Error sending execute_request: {e}")
            self.send_to_lua(
                {
                    "type": "error",
                    "message": f"Python client error sending request: {e}",
                }
            )

    def send_inspect_request(self, content, high_detail=False):
        """Sends an inspect_request to the kernel."""
        log_message(
            f"Sending inspect_request for code: '{content.get('code')}' at pos {content.get('cursor_pos')}"
        )
        try:
            self.kc.inspect(
                code=content.get("code", ""),
                cursor_pos=content.get("cursor_pos", 0),
                detail_level=int(high_detail),
            )
        except Exception as e:
            log_message(f"Error sending inspect_request: {e}")
            self.send_to_lua(
                {"type": "error", "message": f"Error sending inspect_request: {e}"}
            )

    # --- METODI CORRETTI ---

    def send_interrupt_request(self):
        """Sends an interrupt_request to the kernel via the control channel."""
        log_message("Sending interrupt_request to kernel.")
        try:
            # CORREZIONE: Invia un messaggio grezzo invece di chiamare un metodo di alto livello.
            # Questo è più stabile tra le versioni di jupyter-client.
            msg = self.kc.session.msg("interrupt_request", content={})
            self.kc.control_channel.send(msg)
            log_message("Interrupt request sent successfully.")
        except Exception as e:
            log_message(f"Error sending interrupt_request: {e}")
            self.send_to_lua(
                {"type": "error", "message": f"Error sending interrupt_request: {e}"}
            )

    def send_restart_request(self):
        """Sends a shutdown_request with restart=True to the kernel."""
        log_message("Requesting kernel restart.")
        try:
            # CORREZIONE: Invia un messaggio grezzo 'shutdown_request' con restart=True.
            self.kc.shutdown(restart=True)
            log_message("Restart request sent successfully.")
            # Notifica a Lua che la richiesta è stata inviata. Il listener del kernel
            # si occuperà di rilevare il nuovo stato 'idle' quando il riavvio sarà completato.
            self.send_to_lua({"type": "status", "message": "kernel_restarted"})
        except Exception as e:
            log_message(f"Error on kernel restart: {e}")
            self.send_to_lua(
                {"type": "error", "message": f"Error on kernel restart: {e}"}
            )

    def send_history_request(self, content):
        """Sends a history_request to the kernel."""
        log_message("Sending history_request.")
        try:
            self.kc.history(
                hist_access_type=content.get("hist_access_type", "range"),
                raw=content.get("raw", True),
                output=content.get("output", False),
            )
        except Exception as e:
            log_message(f"Error sending history_request: {e}")
            self.send_to_lua(
                {"type": "error", "message": f"Error sending history_request: {e}"}
            )

    def process_command(self, command_data):
        command = command_data.get("command")
        payload = command_data.get("payload")
        log_message(f"Processing command from Lua: {command}")

        if command == "execute":
            if payload:
                self.send_execute_request(payload)
            else:
                log_message("Execute command received without payload.")
                self.send_to_lua(
                    {
                        "type": "error",
                        "message": "Python client: Execute command missing payload.",
                    }
                )

        elif command == "inspect":
            if payload:
                self.send_inspect_request(payload)
            else:
                log_message("Inspect command received without payload.")
                self.send_to_lua(
                    {
                        "type": "error",
                        "message": "Python client: Inspect command missing payload.",
                    }
                )

        elif command == "interrupt":
            self.send_interrupt_request()

        elif command == "restart":
            self.send_restart_request()

        elif command == "history":
            self.send_history_request(payload if payload else {})

        elif command == "shutdown":
            log_message("Shutdown command received. Stopping client.")
            self.stop()
        else:
            log_message(f"Unknown command: {command}")
            self.send_to_lua(
                {
                    "type": "error",
                    "message": f"Python client: Unknown command '{command}'.",
                }
            )

    def run(self):
        log_message(
            "Python KernelClient now running and listening for commands from Lua via stdin."
        )
        try:
            while True:
                line = sys.stdin.readline()
                if not line:
                    log_message("Stdin closed (EOF). Exiting run loop.")
                    break
                line = line.strip()
                if not line:
                    continue

                log_message(f"Received from Lua (stdin): {line[:500]}")
                try:
                    command_data = json.loads(line)
                    self.process_command(command_data)
                except json.JSONDecodeError as e:
                    log_message(f"Failed to decode JSON from Lua: {e}. Line: {line}")
                    self.send_to_lua(
                        {
                            "type": "error",
                            "message": f"Python client: Invalid JSON from Lua: {line}",
                        }
                    )
                except Exception as e:
                    log_message(f"Error processing line from Lua: {e}. Line: {line}")
                    self.send_to_lua(
                        {
                            "type": "error",
                            "message": f"Python client: Error processing command: {line}",
                        }
                    )
        except KeyboardInterrupt:
            log_message("KeyboardInterrupt received, shutting down.")
        finally:
            self.stop()

    def stop(self):
        log_message("Stopping KernelClient...")
        self.stop_event.set()
        if self.kernel_listener_thread and self.kernel_listener_thread.is_alive():
            self.kernel_listener_thread.join(timeout=1)
            log_message("Kernel listener thread joined.")

        if self.kc.is_alive():
            self.kc.stop_channels()
            log_message("Jupyter channels stopped.")
        log_message("KernelClient stopped.")
        self.send_to_lua({"type": "status", "message": "disconnected"})


if __name__ == "__main__":
    if len(sys.argv) < 2:
        log_message("Error: Connection file path not provided.")
        print(
            json.dumps(
                {
                    "type": "error",
                    "message": "Python client: Connection file path not provided.",
                }
            ),
            file=sys.stderr,
        )
        sys.exit(1)

    connection_file = sys.argv[1]
    image_width = int(sys.argv[2]) if len(sys.argv) > 2 else 120
    image_renderer = sys.argv[3] if len(sys.argv) > 3 else "sixel"
    try:
        with open(LOG_FILE_PATH, "w") as f:
            f.write(
                f"{time.strftime('%Y-%m-%d %H:%M:%S')} - Python client starting with connection file: {connection_file}\n"
            )
    except Exception:
        LOG_FILE_PATH = os.path.join(os.getcwd(), "jove_py_client.log")
        log_message("Log file path changed to current working directory.")

    client = KernelClient(connection_file, image_width, image_renderer)
    client.run()
    log_message("Python KernelClient finished.")
