import zmq
import json
import sys
import threading
import time
import os
from jupyter_client.session import Session

# Configurazione del logging (semplice, per debug)
LOG_FILE_PATH = os.path.join(os.path.expanduser("~"), "am_i_neokernel_py_client.log")


def log_message(message):
    with open(LOG_FILE_PATH, "a") as f:
        f.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} - {message}\n")


class KernelClient:
    def __init__(self, connection_file_path):
        log_message(
            f"Initializing KernelClient with connection file: {connection_file_path}"
        )
        self.connection_file_path = connection_file_path
        self.context = zmq.Context()
        self.shell_socket = None
        self.iopub_socket = None
        self.poller = zmq.Poller()
        self.stop_event = threading.Event()
        self.kernel_listener_thread = None  # <<< CHANGE: Renamed for clarity

        self.kernel_info = self._read_connection_file()
        if not self.kernel_info:
            log_message("Failed to read or parse connection file.")
            self.send_to_lua(
                {"type": "error", "message": "Failed to read connection file"}
            )
            sys.exit(1)

        self.session = Session(key=self.kernel_info["key"].encode("utf-8"))

        self._connect_sockets()

    def _read_connection_file(self):
        try:
            with open(self.connection_file_path, "r") as f:
                return json.load(f)
        except Exception as e:
            log_message(
                f"Error reading connection file {self.connection_file_path}: {e}"
            )
            return None

    def _connect_sockets(self):
        ip = self.kernel_info["ip"]
        transport = self.kernel_info["transport"]

        log_message(f"Connecting to kernel at {ip} using {transport}")

        self.shell_socket = self.context.socket(zmq.DEALER)
        self.shell_socket.connect(
            f"{transport}://{ip}:{self.kernel_info['shell_port']}"
        )
        log_message(
            f"Shell socket connected to {transport}://{ip}:{self.kernel_info['shell_port']}"
        )

        self.iopub_socket = self.context.socket(zmq.SUB)
        self.iopub_socket.connect(
            f"{transport}://{ip}:{self.kernel_info['iopub_port']}"
        )
        self.iopub_socket.setsockopt_string(zmq.SUBSCRIBE, "")
        log_message(
            f"IOPub socket connected and subscribed to {transport}://{ip}:{self.kernel_info['iopub_port']}"
        )

        # <<< CHANGE: The poller is already set up for both, which is perfect!
        self.poller.register(self.shell_socket, zmq.POLLIN)
        self.poller.register(self.iopub_socket, zmq.POLLIN)

        # <<< CHANGE: Start the unified listener thread
        self.kernel_listener_thread = threading.Thread(
            target=self._listen_kernel, daemon=True
        )
        self.kernel_listener_thread.start()
        log_message("Unified kernel listener thread started.")
        self.send_to_lua(
            {"type": "status", "message": "connected", "kernel_info": self.kernel_info}
        )

    # <<< CHANGE: This function now listens to BOTH shell and iopub sockets
    def _listen_kernel(self):
        log_message("Kernel listener thread running.")
        while not self.stop_event.is_set():
            try:
                # Poll both sockets with a timeout
                sockets = dict(self.poller.poll(timeout=100))

                # Check for a message on the Shell socket (e.g., execute_reply)
                if (
                    self.shell_socket in sockets
                    and sockets[self.shell_socket] == zmq.POLLIN
                ):
                    multipart_msg = self.shell_socket.recv_multipart()
                    try:
                        msg = self.session.deserialize(multipart_msg)
                        msg_type = msg.get("header", {}).get("msg_type", "unknown")
                        log_message(f"Shell received: {msg_type}")
                        # Forward the entire shell reply to Lua
                        self.send_to_lua({"type": "shell", "message": msg})
                    except Exception as e:
                        log_message(
                            f"Shell received raw message but failed to deserialize: {e} - Raw: {multipart_msg}"
                        )

                # Check for a message on the IOPub socket (e.g., status, stream, error)
                if (
                    self.iopub_socket in sockets
                    and sockets[self.iopub_socket] == zmq.POLLIN
                ):
                    multipart_msg = self.iopub_socket.recv_multipart()
                    try:
                        msg = self.session.deserialize(multipart_msg)
                        msg_type = msg.get("header", {}).get("msg_type", "unknown")
                        log_message(f"IOPub received: {msg_type}")
                        self.send_to_lua({"type": "iopub", "message": msg})
                    except Exception as e:
                        log_message(
                            f"IOPub received raw message but failed to deserialize: {e} - Raw: {multipart_msg}"
                        )

            except zmq.ZMQError as e:
                if e.errno == zmq.ETERM:
                    log_message("Kernel Listener: Context terminated.")
                    break
                log_message(f"Kernel Listener ZMQError: {e}")
                time.sleep(0.1)
            except Exception as e:
                log_message(f"Kernel Listener thread error: {e}")
                time.sleep(0.1)

    def send_execute_request(self, jupyter_msg_payload):
        log_message(f"Preparing to send execute_request.")
        try:
            content = jupyter_msg_payload.get("content", {})
            if not content or "code" not in content:
                log_message("Error: execute_request content is missing or malformed.")
                self.send_to_lua(
                    {
                        "type": "error",
                        "message": "Execute request content missing 'code'.",
                    }
                )
                return

            self.session.send(
                self.shell_socket,
                "execute_request",
                content=content,
                parent=jupyter_msg_payload.get("parent_header", {}),
                metadata=jupyter_msg_payload.get("metadata", {}),
            )
            log_message(
                f"Execute request for code '{content.get('code', '')[:50]}...' sent via session."
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
            json_data = json.dumps(data)
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
            # <<< CHANGE: Replace the 'for' loop with a more robust 'while' loop
            while True:
                # readline() will block until a full line (ending in \n) is received
                line = sys.stdin.readline()

                # If readline() returns an empty string, it means stdin was closed (EOF).
                if not line:
                    log_message("Stdin closed (EOF). Exiting run loop.")
                    break

                line = line.strip()
                if not line:
                    continue

                log_message(
                    f"Received from Lua (stdin): {line[:500]}"
                )  # Increased log length
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

        if self.shell_socket:
            self.shell_socket.close()
            log_message("Shell socket closed.")
        if self.iopub_socket:
            self.iopub_socket.close()
            log_message("IOPub socket closed.")
        if self.context:
            self.context.term()
            log_message("ZMQ context terminated.")
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
        LOG_FILE_PATH = os.path.join(os.getcwd(), "am_i_neokernel_py_client.log")
        log_message("Log file path changed to current working directory.")

    client = KernelClient(connection_file)
    client.run()
    log_message("Python KernelClient finished.")
