# PDFsrv
This script converts incoming PCL or PostScript print jobs into pdf files  

This script requires GhostScript and GhostPCL to be installed to function properly.  
Find GhostScript at: [GhostScript](https://ghostscript.com/releases/gsdnld.html)  
Find GhostPCL at: [GhostPCL](https://ghostscript.com/releases/gpcldnld.html)  

See GhostScript license at: [Ghostscript licensing](https://ghostscript.com/licensing/index.html#open-source)  

```
usage: PDFsrv [-h] [-host HOST] [-port PORT]  
  
options:  
  -h, --help  show this help message and exit  
  -host HOST  defines on which IP the server listens. Default all -> 0.0.0.0  
  -port PORT  defines on which port the server listens. Default 9100
```
