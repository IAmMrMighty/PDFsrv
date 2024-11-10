'''
--- PDFsrv ---
This script serves as a virtual printer, processing incoming print jobs into pdf files.
Allows PostScript, PCL connections
Uses GhostScript, GhostPCL licensed under AGPL license
Requires printer configured @ SERVERIP:9100 with Generic PCL6/PostScript driver
Made by Sandro Kohn in 2024
Inspired by Ingo
'''

import socket, os, subprocess, tempfile, argparse
from datetime import datetime

SAVEPATH = r"/home/hun7/Desktop/"   ## PATH WHERE GENERATED PDFs ARE SAVED

### DETECT PRINT TYPE

def is_postscript(data):
    return data.startswith(b'%!PS')

def is_pcl(data):
    return data.startswith(b'\x1b')

### FUNCTIONS
def listen_for_print_jobs(host, port):
    server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server_socket.bind((host, port))
    server_socket.listen(50)
    print(f"Listening for print jobs on {host}:{port}...")

    while True:
        try:
            client_socket, client_address = server_socket.accept()
            print(f"Connection from {client_address}")
            handle_print_job(client_socket)
        except KeyboardInterrupt:
            print("Stopping server socket... Bye")
            server_socket.close()
            False   ## BREAK WHILE LOOP
            exit()  ## EXIT SCRIPT

def handle_print_job(client_socket):
    data = client_socket.recv(1024) # BUFFER SIZE OF 1024 BYTES
    full_data = b''

    while data:
        full_data += data
        data = client_socket.recv(1024)

    client_socket.close() # CLOSE CLIENT CONNECTION IF ALL DATA TRANSMITTED

    print("Received print job, processing...")
    
    if is_postscript(full_data):
        pdf_file = convert_postscript_to_pdf(full_data)
    elif is_pcl(full_data):
        pdf_file = convert_pcl_to_pdf(full_data)
    else:
        print("Unknown format")
        return

    print(f"Converted to PDF: {pdf_file}")

def generate_pdf_filename():
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    return f"print_job_{timestamp}.pdf"

def convert_postscript_to_pdf(ps_data):
    with tempfile.NamedTemporaryFile(delete=False) as ps_file:
        ps_file.write(ps_data)
        ps_file_path = ps_file.name
    
    pdf_filename = generate_pdf_filename()
    pdf_file_path = os.path.join(SAVEPATH, pdf_filename)

    command = ['gs', '-sDEVICE=pdfwrite', '-o', pdf_file_path, ps_file_path]
    subprocess.run(command)

    return pdf_file_path

def convert_pcl_to_pdf(pcl_data):
    with tempfile.NamedTemporaryFile(delete=False, suffix=".pcl") as pcl_file:
        pcl_file.write(pcl_data)
        pcl_file_path = pcl_file.name

    pdf_filename = generate_pdf_filename()
    pdf_file_path = os.path.join(SAVEPATH, pdf_filename)

    command = ['gpcl6', '-sDEVICE=pdfwrite', '-o', pdf_file_path, pcl_file_path]
    subprocess.run(command, capture_output=True, text=True, check=True)

    return pdf_file_path

### ARGUMENTS

parser = argparse.ArgumentParser("server.py")
parser.add_argument("-host", dest="host", default="0.0.0.0", type=str, help="defines on which IP the server listens. Default all -> 0.0.0.0")
parser.add_argument("-port", dest="port", default=9100, type=int, help="defines on which port the server listens. Default 9100")
args = parser.parse_args()

### STARTUP SEQUENCE

if __name__ == "__main__":
    if not os.path.exists(SAVEPATH):
        os.makedirs(SAVEPATH)

    host = args.host
    port = args.port

    listen_for_print_jobs(host, port)
