import jupyter_client
import json
import sys
import threading
import time
import os
from queue import Empty

# Configurazione del logging (semplice, per debug)
LOG_FILE_PATH = os.path.join(os.path.expanduser("~"), "jove_py_client.log")


def log_message(message):
    # Appends a message to the log file with a timestamp.
    with open(LOG_FILE_PATH, "a") as f:
        f.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} - {message}\n")


class KernelClient:
    def __init__(self, connection_file_path):
        log_message(
            f"Initializing KernelClient with connection file: {connection_file_path}"
        )
        try:
            self.kc = jupyter_client.BlockingKernelClient(
                connection_file=connection_file_path
            )
            self.kc.load_connection_file()
            self.kc.start_channels()
            self.kc.control_channel.start()
            log_message("IOPub, Shell, and Control channels started.")
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
                for channel_name in ["iopub", "shell", "control"]:
                    try:
                        channel = getattr(self.kc, f"{channel_name}_channel")
                        msg = channel.get_msg(
                            timeout=0.05
                        )  # Timeout piccolo per non bloccare
                        msg_type = msg.get("header", {}).get("msg_type", "unknown")
                        log_message(f"Message received on {channel_name}: {msg_type}")
                        self.send_to_lua({"type": channel_name, "message": msg})
                    except Empty:
                        pass  # Nessun messaggio, normale
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

    def send_execute_request(self, content):
        log_message("Preparing to send execute_request.")
        try:
            self.kc.execute(
                code=content.get("code", ""),
                silent=content.get("silent", False),
                store_history=content.get("store_history", True),
                user_expressions=content.get("user_expressions", {}),
                allow_stdin=content.get("allow_stdin", False),
                stop_on_error=content.get("stop_on_error", True),
            )
        except Exception as e:
            log_message(f"Error sending execute_request: {e}")
            self.send_to_lua(
                {"type": "error", "message": f"Error sending execute_request: {e}"}
            )

    def send_inspect_request(self, content):
        """Sends an inspect_request to the kernel."""
        log_message(
            f"Sending inspect_request for code: '{content.get('code')}' at pos {content.get('cursor_pos')}"
        )
        try:
            self.kc.inspect(
                code=content.get("code", ""),
                cursor_pos=content.get("cursor_pos", 0),
                detail_level=0,
            )
        except Exception as e:
            log_message(f"Error sending inspect_request: {e}")
            self.send_to_lua(
                {"type": "error", "message": f"Error sending inspect_request: {e}"}
            )

    # --- CORREZIONE: Usa il canale di controllo per interrupt e restart ---
    def send_interrupt_request(self):
        """Sends an interrupt_request via the control channel."""
        log_message("Sending interrupt_request to kernel via control channel.")
        try:
            self.kc.control_channel.interrupt()
            log_message("Interrupt request sent.")
        except Exception as e:
            log_message(f"Error sending interrupt_request: {e}")
            self.send_to_lua(
                {"type": "error", "message": f"Error sending interrupt_request: {e}"}
            )

    def send_restart_request(self):
        """Sends a restart_request via the control channel."""
        log_message("Requesting kernel restart via control channel.")
        try:
            self.kc.control_channel.restart()
            log_message("Restart request sent.")
            # La risposta 'restart_reply' verrà catturata dal listener
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

        # Estrai il 'content' dal payload per tutti i messaggi
        content = payload.get("content", {}) if payload else {}

        if command == "execute":
            if content:
                self.send_execute_request(content)
            else:
                log_message("Execute command received without content.")

        elif command == "inspect":
            if content:
                self.send_inspect_request(content)
            else:
                log_message("Inspect command received without content.")

        elif command == "interrupt":
            self.send_interrupt_request()

        elif command == "restart":
            self.send_restart_request()

        elif command == "history":
            self.send_history_request(content)

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
            for line in sys.stdin:
                line = line.strip()
                if not line:
                    continue

                log_message(f"Received from Lua (stdin): {line[:500]}")
                try:
                    command_data = json.loads(line)
                    self.process_command(command_data)
                except json.JSONDecodeError as e:
                    log_message(f"Failed to decode JSON from Lua: {e}. Line: {line}")
                except Exception as e:
                    log_message(f"Error processing line from Lua: {e}. Line: {line}")
        except KeyboardInterrupt:
            log_message("KeyboardInterrupt received, shutting down.")
        finally:
            self.stop()

    def stop(self):
        log_message("Stopping KernelClient...")
        self.stop_event.set()
        if self.kernel_listener_thread and self.kernel_listener_thread.is_alive():
            self.kernel_listener_thread.join(timeout=1)

        if self.kc.is_alive():
            self.kc.stop_channels()
            self.kc.control_channel.stop()
        log_message("KernelClient stopped.")
        self.send_to_lua({"type": "status", "message": "disconnected"})


if __name__ == "__main__":
    if len(sys.argv) < 2:
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
    try:
        with open(LOG_FILE_PATH, "w") as f:  # 'w' to clear log on start
            f.write(
                f"{time.strftime('%Y-%m-%d %H:%M:%S')} - Python client starting with connection file: {connection_file}\n"
            )
    except Exception:
        LOG_FILE_PATH = os.path.join(os.getcwd(), "jove_py_client.log")
        log_message("Log file path changed to current working directory.")

    client = KernelClient(connection_file)
    client.run()
    log_message("Python KernelClient finished.")
