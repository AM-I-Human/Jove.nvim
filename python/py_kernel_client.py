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
    with open(LOG_FILE_PATH, "a") as f:
        f.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} - {message}\n")


class KernelClient:
    def __init__(self, connection_file_path):
        log_message(
            f"Initializing KernelClient with connection file: {connection_file_path}"
        )
        try:
            self.kc = jupyter_client.KernelClient(
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
                # This is more efficient than two timeouts or busy-waiting.
                try:
                    msg = self.kc.get_iopub_msg(timeout=0.1)
                    msg_type = msg.get("header", {}).get("msg_type", "unknown")
                    log_message(f"IOPub received: {msg_type}")
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
                # Don't sleep here, get_iopub_msg timeout provides the wait

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

            # The high-level `execute` method is simpler than session.send
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

    def send_to_lua(self, data):
        try:
            json_data = json.dumps(data, default=repr)
            sys.stdout.write(json_data + "\n")
            sys.stdout.flush()
        except Exception as e:
            log_message(f"Error sending data to Lua: {e} (Data was: {str(data)[:200]})")

    def process_command(self, command_data):
        command = command_data.get("command")
        log_message(f"Processing command from Lua: {command}")

        if command == "execute":
            jupyter_msg_payload = command_data.get("payload")
            if jupyter_msg_payload:
                self.send_execute_request(jupyter_msg_payload)
            else:
                log_message("Execute command received without payload.")
                self.send_to_lua(
                    {
                        "type": "error",
                        "message": "Python client: Execute command missing payload.",
                    }
                )
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
    log_message(f"Python KernelClient starting with connection file: {connection_file}")

    try:
        with open(LOG_FILE_PATH, "a") as f:
            f.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} - Python client started.\n")
    except Exception:
        LOG_FILE_PATH = os.path.join(os.getcwd(), "jove_py_client.log")
        log_message("Log file path changed to current working directory.")

    client = KernelClient(connection_file)
    client.run()
    log_message("Python KernelClient finished.")
