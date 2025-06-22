import zmq
import json
import sys
import threading
import time
import os

# Configurazione del logging (semplice, per debug)
LOG_FILE_PATH = os.path.join(os.path.expanduser("~"), "am_i_neokernel_py_client.log")
def log_message(message):
    with open(LOG_FILE_PATH, "a") as f:
        f.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} - {message}\n")

class KernelClient:
    def __init__(self, connection_file_path):
        log_message(f"Initializing KernelClient with connection file: {connection_file_path}")
        self.connection_file_path = connection_file_path
        self.context = zmq.Context()
        self.shell_socket = None
        self.iopub_socket = None
        self.poller = zmq.Poller()
        self.stop_event = threading.Event()
        self.iopub_thread = None
        self.kernel_info = self._read_connection_file()
        if not self.kernel_info:
            log_message("Failed to read or parse connection file.")
            # Invia un messaggio di errore a Lua e esci o gestisci
            self.send_to_lua({"type": "error", "message": "Failed to read connection file"})
            sys.exit(1)
        self._connect_sockets()

    def _read_connection_file(self):
        try:
            with open(self.connection_file_path, 'r') as f:
                return json.load(f)
        except Exception as e:
            log_message(f"Error reading connection file {self.connection_file_path}: {e}")
            return None

    def _connect_sockets(self):
        ip = self.kernel_info['ip']
        transport = self.kernel_info['transport']

        log_message(f"Connecting to kernel at {ip} using {transport}")

        self.shell_socket = self.context.socket(zmq.DEALER) # o REQ, ma DEALER è più flessibile per asincrono
        self.shell_socket.connect(f"{transport}://{ip}:{self.kernel_info['shell_port']}")
        log_message(f"Shell socket connected to {transport}://{ip}:{self.kernel_info['shell_port']}")


        self.iopub_socket = self.context.socket(zmq.SUB)
        self.iopub_socket.connect(f"{transport}://{ip}:{self.kernel_info['iopub_port']}")
        self.iopub_socket.setsockopt_string(zmq.SUBSCRIBE, "")
        log_message(f"IOPub socket connected and subscribed to {transport}://{ip}:{self.kernel_info['iopub_port']}")

        self.poller.register(self.shell_socket, zmq.POLLIN)
        self.poller.register(self.iopub_socket, zmq.POLLIN)

        # Avvia il thread per ascoltare i messaggi IOPub
        self.iopub_thread = threading.Thread(target=self._listen_iopub, daemon=True)
        self.iopub_thread.start()
        log_message("IOPub listener thread started.")
        self.send_to_lua({"type": "status", "message": "connected", "kernel_info": self.kernel_info})


    def _listen_iopub(self):
        log_message("IOPub listener thread running.")
        while not self.stop_event.is_set():
            try:
                # Non bloccante per permettere al thread di terminare
                if self.iopub_socket.poll(timeout=100, flags=zmq.POLLIN): # Timeout di 100ms
                    multipart_msg = self.iopub_socket.recv_multipart()
                    # Jupyter messages have multiple parts. The actual message is usually after some identity frames.
                    # We need to find the part that contains the JSON header.
                    # Typically, the message parts are: identities*, DELIMITER, hmac_signature, header, parent_header, metadata, content
                    # The DELIMITER is b'<IDS|MSG>'
                    # For simplicity, we'll assume the relevant JSON is in one of the later parts.
                    # A more robust parser would be needed for all cases.
                    # For now, try to decode the part that looks like a header.
                    msg = {}
                    for part in multipart_msg:
                        try:
                            # Find the part that is the main message content (usually after DELIMITER)
                            # This is a simplification. A robust client needs to parse the wire protocol.
                            # The actual message is typically after a b'<IDS|MSG>' delimiter.
                            # We are interested in header, parent_header, metadata, content.
                            # The zmq message is a list of byte strings.
                            # header, parent_header, metadata, content are JSON strings.
                            # We are looking for the part that contains the 'header'.
                            # A common pattern is that the actual message starts after a delimiter part.
                            # Let's find the delimiter
                            if part == b"<IDS|MSG>": # This is the delimiter
                                # The next parts are signature, header, parent_header, metadata, content
                                header_idx = multipart_msg.index(part) + 2 # header is 2 after delimiter
                                if header_idx < len(multipart_msg):
                                    header = json.loads(multipart_msg[header_idx].decode('utf-8'))
                                    parent_header = json.loads(multipart_msg[header_idx+1].decode('utf-8'))
                                    metadata = json.loads(multipart_msg[header_idx+2].decode('utf-8'))
                                    content = json.loads(multipart_msg[header_idx+3].decode('utf-8'))
                                    msg = {
                                        "header": header,
                                        "parent_header": parent_header,
                                        "metadata": metadata,
                                        "content": content
                                    }
                                    break # Found the message
                        except (json.JSONDecodeError, UnicodeDecodeError):
                            continue # Not a JSON part or not utf-8

                    if msg and "header" in msg: # Check if we successfully parsed a message
                        log_message(f"IOPub received: {msg.get('header', {}).get('msg_type')}")
                        self.send_to_lua({"type": "iopub", "message": msg})
                    elif multipart_msg: # If we couldn't parse but received something
                        log_message(f"IOPub received raw (could not parse as full Jupyter msg): {multipart_msg}")

            except zmq.ZMQError as e:
                if e.errno == zmq.ETERM:
                    log_message("IOPub: Context terminated.")
                    break
                log_message(f"IOPub ZMQError: {e}")
                time.sleep(0.1) # Avoid busy-looping on other errors
            except Exception as e:
                log_message(f"IOPub thread error: {e}")
                time.sleep(0.1)


    def send_execute_request(self, jupyter_msg):
        # The jupyter_msg received from Lua is already a complete message structure
        # We need to serialize each part (header, parent_header, metadata, content) to JSON strings
        # and send them as a multipart ZMQ message.
        # The client (DEALER) prepends an empty frame for routing when talking to a ROUTER (kernel shell).
        # identities (none for kernel)
        # <IDS|MSG> (delimiter)
        # hmac (signature, can be empty if not using security)
        # header (json string)
        # parent_header (json string, can be empty dict)
        # metadata (json string, can be empty dict)
        # content (json string)
        # buffers (optional)

        log_message(f"Sending execute_request: {jupyter_msg.get('header', {}).get('msg_type')}")
        try:
            # Ensure parent_header and metadata are at least empty dicts if not present
            parent_header = jupyter_msg.get('parent_header', {})
            metadata = jupyter_msg.get('metadata', {})

            # Construct the multipart message
            # Note: pyzmq expects bytes. We need to encode JSON strings to UTF-8.
            # The kernel might not require a signature if not configured for security.
            # For simplicity, we'll send an empty signature. A real client should compute it.
            # The shell socket is DEALER, it adds its own identity frame.
            # Kernel's shell socket is ROUTER. It expects [identities..., DELIMITER, SIGNATURE, HEADER, PARENT_HEADER, METADATA, CONTENT, BUFFERS...]
            # Since we are a DEALER, we don't add identities.
            # The kernel might not be using security, so an empty signature might work.
            # A proper client should handle message signing.
            # For now, let's assume no signature or an empty one is fine.
            # The structure is: [b"", <IDS|MSG>, signature, header_json, parent_header_json, metadata_json, content_json]
            # However, when sending from DEALER to ROUTER, the ROUTER adds an identity frame for the DEALER.
            # So the kernel receives: [dealer_identity, b"", <IDS|MSG>, ...]
            # We send: [b"", <IDS|MSG>, ...]
            # Let's try a simpler format first if the above is too complex for ipykernel_launcher default.
            # Often, for execute_request, just sending the serialized parts is enough if not using full wire protocol.
            # Let's try the full wire protocol structure.

            delimiter = b"<IDS|MSG>"
            # For now, an empty signature. A real client should generate this.
            # This might cause issues if the kernel expects a valid signature.
            signature = b"" # HMAC signature, should be calculated if security is enabled.

            header_json = json.dumps(jupyter_msg["header"]).encode('utf-8')
            parent_header_json = json.dumps(parent_header).encode('utf-8')
            metadata_json = json.dumps(metadata).encode('utf-8')
            content_json = json.dumps(jupyter_msg["content"]).encode('utf-8')

            self.shell_socket.send_multipart([
                delimiter,
                signature,
                header_json,
                parent_header_json,
                metadata_json,
                content_json
            ])
            log_message("Execute request sent to shell socket.")

            # Shell socket should reply (e.g., execute_reply)
            # This part is simplified; a full client would handle shell replies.
            # For now, we assume IOPub will give us the results.
            # shell_reply_parts = self.shell_socket.recv_multipart()
            # log_message(f"Shell reply: {shell_reply_parts}")
            # We can parse and send this to Lua if needed.
            # For now, focus on IOPub for output.

        except Exception as e:
            log_message(f"Error sending execute_request: {e}")
            self.send_to_lua({"type": "error", "message": f"Python client error sending request: {e}"})


    def send_to_lua(self, data):
        try:
            json_data = json.dumps(data)
            sys.stdout.write(json_data + "\n")
            sys.stdout.flush()
            # log_message(f"Sent to Lua: {json_data[:200]}") # Log snippet
        except Exception as e:
            log_message(f"Error sending data to Lua: {e} (Data was: {str(data)[:200]})")


    def process_command(self, command_data):
        command = command_data.get("command")
        log_message(f"Processing command from Lua: {command}")

        if command == "execute":
            jupyter_msg = command_data.get("payload")
            if jupyter_msg:
                self.send_execute_request(jupyter_msg)
            else:
                log_message("Execute command received without payload.")
                self.send_to_lua({"type": "error", "message": "Python client: Execute command missing payload."})
        elif command == "shutdown":
            log_message("Shutdown command received. Stopping client.")
            self.stop()
        else:
            log_message(f"Unknown command: {command}")
            self.send_to_lua({"type": "error", "message": f"Python client: Unknown command '{command}'."})


    def run(self):
        log_message("Python KernelClient now running and listening for commands from Lua via stdin.")
        try:
            for line in sys.stdin:
                line = line.strip()
                if not line:
                    continue
                log_message(f"Received from Lua (stdin): {line[:200]}")
                try:
                    command_data = json.loads(line)
                    self.process_command(command_data)
                except json.JSONDecodeError as e:
                    log_message(f"Failed to decode JSON from Lua: {e}. Line: {line}")
                    self.send_to_lua({"type": "error", "message": f"Python client: Invalid JSON from Lua: {line}"})
                except Exception as e:
                    log_message(f"Error processing line from Lua: {e}. Line: {line}")
                    self.send_to_lua({"type": "error", "message": f"Python client: Error processing command: {line}"})

        except KeyboardInterrupt:
            log_message("KeyboardInterrupt received, shutting down.")
        finally:
            self.stop()

    def stop(self):
        log_message("Stopping KernelClient...")
        self.stop_event.set()
        if self.iopub_thread and self.iopub_thread.is_alive():
            self.iopub_thread.join(timeout=1) # Wait for thread to finish
            log_message("IOPub thread joined.")

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
        # This case should ideally not happen if Lua starts it correctly
        log_message("Error: Connection file path not provided.")
        print(json.dumps({"type": "error", "message": "Python client: Connection file path not provided."}), file=sys.stderr)
        sys.exit(1)

    connection_file = sys.argv[1]
    log_message(f"Python KernelClient starting with connection file: {connection_file}")

    # Simple way to ensure the log file path is writable, or fallback.
    try:
        with open(LOG_FILE_PATH, "a") as f:
            f.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} - Python client started.\n")
    except Exception:
        # Fallback if default log path is not writable (e.g. permissions)
        # This is a very basic fallback.
        LOG_FILE_PATH = os.path.join(os.getcwd(), "am_i_neokernel_py_client.log")
        log_message("Log file path changed to current working directory.")


    client = KernelClient(connection_file)
    client.run()
    log_message("Python KernelClient finished.")
