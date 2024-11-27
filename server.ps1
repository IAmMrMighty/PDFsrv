<#
    --- PDFsrv ---
    Dieses Skript dient als virtueller PDF Drucker,
    welcher eingehende Druckaufträge über das Netzwerk verarbeitet.
    Benötigte Software: GhostScript, GhostPCL
    Benötigt konfigurierten Drucker unter SERVERIP:PORT mit Generic PCL6/PostScript-Treiber
    
    Autor: Sandro Kohn in 2024
#>

param([int]$port = 9100)

$SAVEPATH = "Dokumente\"                                                                                ## Pfad, an dem die PDFs gespeichert werden
$rootpath = "Dokumente\"

function CheckAndCreateExportDirectory
{
    param(
        [String[]]$destination
    )

    if(-not (Test-Path $destination))                                                                   ## Wenn der Pfad nicht verfügbar ist
    {
        Write-Host '[' $(currentTimestamp) '] Der Exportordner '$($global:SAVEPATH)' wurde angelegt.' -ForegroundColor Yellow
        New-Item -ItemType Directory -Path $destination | Out-Null                                      ## Erstelle den Pfad neu
    }
}

function Is-Postscript                                                                                  ## Überprüfe, ob Druckauftrag ein PostScript-Auftrag ist
{
    param (
        [byte[]]$data
    )

    return ($data[0] -eq 37 -and $data[1] -eq 33 -and $data[2] -eq 80 -and $data[3] -eq 83)             ## Überprüfe, ob ersten vier Bytes --> %!PS <-- sind
}

function Is-PCL                                                                                         ## Überprüfe, ob Druckauftrag ein PCL-Auftrag ist
{
    param (
        [byte[]]$data
    )

    return ($data[0] -eq 27)                                                                            ## ASCII ESC (0x18)
}

function Get-Highest-PDFCount                                                                           ## Erfassen der letzten Rechnung
{
    [long]$PDFcount = 0                                                                                 ## Initialisieren des PDF-Zählers
    Get-ChildItem -Path $SAVEPATH -Filter *.pdf | Foreach-Object {                                      ## Für jede PDF-Datei
        $fileName = @($_.Name)                                                                          ## Erfasse den Namen der PDF
        [long]$localcount = $fileName.Split("_").Split(".")[1]                                          ## Teile ihn an der Stelle mit dem Zeichen "_", "." und entnimm die Zahl
        if(($localcount -gt $PDFcount) -or ($localcount -eq $PDFcount))                                 ## Wenn der Zähler aus dem Dateinamen größer als der aktuelle Zählerstand
        {
            $PDFcount = $localcount                                                                     ## Ersetze den aktuellen Zählerstand mit der Nummer aus dem Dateinamen
            $PDFcount++                                                                                 ## Erhöhe den Wert des Zählerstandes um 1
        }
    } -ErrorAction SilentlyContinue
    return $PDFcount                                                                                    ## Gib den Zählerstand zurück
}

function Generate-PDFFileName                                                                           ## Generierung eines Dateinamen
{
    #$timestamp = Get-Date -Format "ddMMyyyy_HHmmss"                                                    ## erfasse aktuelle Zeit
    return "Rechnung_$(Get-Highest-PDFCount).pdf"                                                       ## Gib den Dateinamen zurück
}

function currentTimestamp
{
    return Get-Date -Format "HH:mm:ss - dd.MM.yyyy"                                                     ## Erfasse aktuellen Zeitstempel
}

function GetLoggedOnUser
{
    param(
        [String[]]$RemoteEndPoint                                                                       ## Erwarte IP-Adresse von eingehender TCP-Verbindung
    )

    $RemoteEndPoint = $RemoteEndPoint.Split(":")                                                        ## Teile die IP von dem Port
    $UserName = (Get-WmiObject -Class win32_computersystem -ComputerName $($RemoteEndPoint[0])).UserName## Frage den aktuell angemeldeten Benutzer vom 
    $Username = $UserName.Split("\")                                                                    ## Teile den Benutzernamen von der Domain
    return $UserName[1]                                                                                 ## Gib den reinen Benutzernamen zurück
}

function SetUserSpecificExport
{
    param(
        [String]$UserName
    )

    If(-not ($global:SAVEPATH -eq (Join-Path $rootpath $UserName)))                                     ## Wenn der aktuelle Exportpfad nicht den Benutzernamen enthält
    {
        $global:SAVEPATH = Join-Path $rootpath $UserName                                                ## Füge dem Exportpfad den Benutzernamen 
    }
}

function Convert-PostScript-To-PDF                                                                      ## Konvertierungsfunktion von PostScript zu PDF
{
    param(
        [byte[]]$psData
    )

    $psFilePath = [System.IO.Path]::GetTempFileName()                                                   ## erstelle temporäre Datei
    [System.IO.File]::WriteAllBytes($psFilePath, $psData)                                               ## schreibe die eingehenden Bytes in die temporäre Datei

    $pdfFilename = Generate-PDFFileName                                                                 ## generiere Dateiname
    $pdfFilePath = Join-Path -Path $SAVEPATH -ChildPath $pdfFilename                                    ## Füge den Speicherpfad mit dem generierten Dateinamen zusammen

    $gsCommand = "gs", "-sDEVICE=pdfwrite", "-o", $pdfFilePath, $psFilePath                             ## Bereite den GhostScript-Verarbeitungsprozess vor
    Start-Process -FilePath $gsCommand[0] -ArgumentList $gsCommand[1..$gsCommand.Length] -Wait          ## Starte den GhostScript-Verarbeitungsprozess und warte auf Beendigung

    return $pdfFilePath                                                                                 ## Rückgabe Pfad zur erstellten PDF
}

function Convert-PCL-To-PDF                                                                             ## Konvertierungsfunktion von PCL6 zu PDF
{
    param(
        [byte[]]$psData
    )

    $pclFilePath = [System.IO.Path]::GetTempFileName()                                                  ## erstelle temporäre Datei
    [System.IO.File]::WriteAllBytes($pclFilePath, $psData)                                              ## schreibe die eingehenden Bytes in die temporäre Datei

    $pdfFilename = Generate-PDFFileName                                                                 ## generiere Dateiname
    $pdfFilePath = Join-Path -Path $SAVEPATH -ChildPath $pdfFilename                                    ## Füge den Speicherpfad mit dem generierten Dateinamen zusammen

    $gpcl6Command = "gpcl6win64", "-sDEVICE=pdfwrite", "-o", $pdfFilePath, $pclFilePath                      ## Bereite den GhostPCL-Verarbeitungsprozess vor
    Start-Process -FilePath $gpcl6Command[0] -ArgumentList $gpcl6Command[1..$gpcl6Command.Length] -Wait ## Starte den GhostPCL-Verarbeitungsprozess und warte auf Beendigung

    return $pdfFilePath                                                                                 ## Rückgabe Pfad zur erstellten PDF
}

function Handle-PrintJob
{
    param (
        [System.Net.Sockets.TcpClient]$client                                                           ## Deklaration eines neuen TCP Clients
    )

    $stream = $client.GetStream()                                                                       ## Deklaration eines Streams
    $buffer = New-Object byte[] 1024                                                                    ## Erfasse eingehenden Daten immer im Buffer von 1024 Bytes
    $fullData = @()

    while ($bytesRead = $stream.Read($buffer, 0, $buffer.Length))                                       ## Während die eingehenden Druckdaten empfangen werden...
    {
        $fullData += $buffer[0..($bytesRead-1)]                                                         ## schreibe die empfangenen Daten in die Variable fullData
    }

    $client.Close()                                                                                     ## Schließe bei Fertigstellung den Client wieder

    Write-Host '[' $(currentTimestamp) '] Eingehenden Druckauftrag erhalten, verarbeite...' -Foreground Green

    if(Is-PCL $fullData)                                                                                ## Wenn Druckauftrag PCL
    {
        Write-Host '[' $(currentTimestamp) '] Eingehender Druckauftrag ist ein PCL-Auftrag' -Foreground Cyan
        $pdfFile = Convert-PCL-To-PDF $fullData                                                         ## Leite weiter an PCL-Konvertierungsfunktion
    }
    elseif(Is-Postscript $fulldata)                                                                     ## Wenn Druckauftrag PostScript
    {
        Write-Host '[' $(currentTimestamp) '] Eingehender Druckauftrag ist ein PostScript-Auftrag' -Foreground Cyan
        $pdfFile = Convert-PostScript-To-PDF $fulldata                                                  ## Leite weiter an PostScript-Konvertierungsfunktion
    }
    else                                                                                                ## Wenn unbekannter Druckauftrag
    {
        Write-Host '[' $(currentTimestamp) '] Eingehende Druckauftragsart unbekannt. Überspringe...' -ForegroundColor Yellow
        return                                                                                          ## überspringe
    }

    Write-Host '[' $(currentTimestamp) '] PDF-Datei umkonvertiert in: ' + $pdfFile -ForegroundColor DarkGreen
}

function Listen-For-Printjobs
{
    param (
        $port
    )
    
    $server_listener = [System.Net.Sockets.TcpListener]$port                                            ## Definieren des neuen TCP Socket Listeners
    $server_listener.Start()                                                                            ## Starten des TCP Socket Listeners
    Write-Host '[' $(currentTimestamp) '] PDF Druckserver läuft auf:' $(Get-NetIPAddress | Where-Object{$_.IPAddress -and $_.AddressState -eq 'Preferred' -and $_.InterfaceAlias -like '*Ethernet*'})':'$port -ForegroundColor Green

    try
    {
        while($true)
        {
            $client = $server_listener.AcceptTcpClient()                                                ## Akzeptiere eingehende TCP Verbindungen
            Write-Host '[' $(currentTimestamp) '] Verbindung von' $($client.Client.RemoteEndPoint) -ForegroundColor Magenta
            SetUserSpecificExport(GetLoggedOnUser($client.Client.RemoteEndPoint))                       ## Setze den Exportpfad auf den des angemeldeten Benutzers aus der eingehenden TCP-Verbindung
            CheckAndCreateExportDirectory($SAVEPATH)                                                    ## Überprüfe, ob der Pfad existiert und erstelle ihn ggf. neu
            Handle-PrintJob -client $client                                                             ## Leite Anfrage des Clients weiter
        }
    }
    catch {                                                                                             ## Wenn weitere Verarbeitung nicht möglich ist:
        Write-Host $_                                                                                   ## Gibt letzte Fehlermeldung zurück
        Write-Host '[' $(currentTimestamp) '] Ein schwerwiegender Fehler ist bei der Verarbeitung aufgetreten. Stoppe Server...' -ForegroundColor Red
        $server_listener.Stop()                                                                         ## Stoppe den Socket Listener
    }
}

Listen-For-Printjobs -port $port                                                                        ## Server starten
