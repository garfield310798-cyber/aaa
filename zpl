# ================================
# ENVIAR ZPL A IMPRESORA (FTP / RAW 9100)
# Reemplaza el proceso manual:  cmd -> ftp -> open IP -> enter/enter -> put etiqueta.txt
# PowerShell 5.1 / Windows 11 - sin instalar nada
# ================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ---- Codificacion Latin1: preserva los bytes del ZPL tal cual ----
$Enc = [System.Text.Encoding]::GetEncoding(28591)

# ==========================================================
#  FUNCION FTP  (equivale a: ftp -> open IP -> put archivo)
# ==========================================================
function Send-ZplFtp {
    param([string]$ip, [int]$port, [string]$zpl, [bool]$passive)

    $uri = "ftp://${ip}:${port}/etiqueta.txt"
    $req = [System.Net.FtpWebRequest]::Create($uri)
    $req.Method      = [System.Net.WebRequestMethods+Ftp]::UploadFile
    $req.Credentials = New-Object System.Net.NetworkCredential("anonymous", "")  # enter/enter (anonimo)
    $req.UseBinary   = $true
    $req.UsePassive  = $passive
    $req.KeepAlive   = $false
    $req.Timeout     = 10000

    $bytes = $Enc.GetBytes($zpl)
    $req.ContentLength = $bytes.Length

    $stream = $req.GetRequestStream()
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Close()

    $resp   = [System.Net.FtpWebResponse]$req.GetResponse()
    $estado = $resp.StatusDescription
    $resp.Close()
    return $estado.Trim()
}

# ==========================================================
#  FUNCION RAW 9100  (respaldo: muchas Zebra son mas estables asi)
# ==========================================================
function Send-ZplRaw {
    param([string]$ip, [int]$port, [string]$zpl)

    $client = New-Object System.Net.Sockets.TcpClient
    $client.Connect($ip, $port)
    $netStream = $client.GetStream()

    $bytes = $Enc.GetBytes($zpl)
    $netStream.Write($bytes, 0, $bytes.Length)
    $netStream.Flush()

    $netStream.Close()
    $client.Close()
    return "Enviado por puerto RAW $port"
}

# ==========================================================
#  FORMULARIO
# ==========================================================
$form = New-Object System.Windows.Forms.Form
$form.Text            = "Enviar ZPL"
$form.ClientSize      = New-Object System.Drawing.Size(360, 486)
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox     = $false
$form.StartPosition   = "CenterScreen"

# --- IP ---
$lblIp = New-Object System.Windows.Forms.Label
$lblIp.Text = "IP de la impresora:"
$lblIp.Location = New-Object System.Drawing.Point(10, 10)
$lblIp.Size = New-Object System.Drawing.Size(150, 18)
$form.Controls.Add($lblIp)

$txtIp = New-Object System.Windows.Forms.TextBox
$txtIp.Location = New-Object System.Drawing.Point(10, 30)
$txtIp.Size = New-Object System.Drawing.Size(200, 22)
$form.Controls.Add($txtIp)

# --- Metodo ---
$lblMetodo = New-Object System.Windows.Forms.Label
$lblMetodo.Text = "Metodo:"
$lblMetodo.Location = New-Object System.Drawing.Point(220, 10)
$lblMetodo.Size = New-Object System.Drawing.Size(120, 18)
$form.Controls.Add($lblMetodo)

$cboMetodo = New-Object System.Windows.Forms.ComboBox
$cboMetodo.DropDownStyle = "DropDownList"
$cboMetodo.Items.AddRange(@("FTP (21)", "RAW (9100)"))
$cboMetodo.SelectedIndex = 0
$cboMetodo.Location = New-Object System.Drawing.Point(220, 30)
$cboMetodo.Size = New-Object System.Drawing.Size(120, 22)
$form.Controls.Add($cboMetodo)

# --- Puerto ---
$lblPuerto = New-Object System.Windows.Forms.Label
$lblPuerto.Text = "Puerto:"
$lblPuerto.Location = New-Object System.Drawing.Point(10, 60)
$lblPuerto.Size = New-Object System.Drawing.Size(80, 18)
$form.Controls.Add($lblPuerto)

$txtPuerto = New-Object System.Windows.Forms.TextBox
$txtPuerto.Text = "21"
$txtPuerto.Location = New-Object System.Drawing.Point(10, 80)
$txtPuerto.Size = New-Object System.Drawing.Size(80, 22)
$form.Controls.Add($txtPuerto)

# --- Modo pasivo (solo FTP) ---
$chkPasivo = New-Object System.Windows.Forms.CheckBox
$chkPasivo.Text = "Modo pasivo (FTP)"
$chkPasivo.Checked = $true
$chkPasivo.Location = New-Object System.Drawing.Point(110, 80)
$chkPasivo.Size = New-Object System.Drawing.Size(230, 22)
$form.Controls.Add($chkPasivo)

# Cambiar puerto automaticamente segun el metodo
$cboMetodo.Add_SelectedIndexChanged({
    if ($cboMetodo.SelectedItem -eq "RAW (9100)") {
        $txtPuerto.Text = "9100"
        $chkPasivo.Enabled = $false
    } else {
        $txtPuerto.Text = "21"
        $chkPasivo.Enabled = $true
    }
})

# --- ZPL ---
$lblZpl = New-Object System.Windows.Forms.Label
$lblZpl.Text = "Codigo ZPL:"
$lblZpl.Location = New-Object System.Drawing.Point(10, 112)
$lblZpl.Size = New-Object System.Drawing.Size(150, 18)
$form.Controls.Add($lblZpl)

$txtZpl = New-Object System.Windows.Forms.TextBox
$txtZpl.Multiline = $true
$txtZpl.ScrollBars = "Vertical"
$txtZpl.WordWrap = $false
$txtZpl.Font = New-Object System.Drawing.Font("Consolas", 9)
$txtZpl.Location = New-Object System.Drawing.Point(10, 132)
$txtZpl.Size = New-Object System.Drawing.Size(340, 180)
$form.Controls.Add($txtZpl)

# --- Cargar .txt ---
$btnCargar = New-Object System.Windows.Forms.Button
$btnCargar.Text = "Cargar .txt..."
$btnCargar.Location = New-Object System.Drawing.Point(10, 320)
$btnCargar.Size = New-Object System.Drawing.Size(110, 28)
$form.Controls.Add($btnCargar)

$btnCargar.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = "Etiquetas (*.txt;*.zpl;*.prn)|*.txt;*.zpl;*.prn|Todos (*.*)|*.*"
    if ($dlg.ShowDialog() -eq "OK") {
        $txtZpl.Text = [System.IO.File]::ReadAllText($dlg.FileName, $Enc)
    }
})

# --- Enviar ---
$btnEnviar = New-Object System.Windows.Forms.Button
$btnEnviar.Text = "Enviar"
$btnEnviar.Font = New-Object System.Drawing.Font("Arial", 9, [System.Drawing.FontStyle]::Bold)
$btnEnviar.Location = New-Object System.Drawing.Point(250, 320)
$btnEnviar.Size = New-Object System.Drawing.Size(100, 28)
$form.Controls.Add($btnEnviar)

# --- Estado / Log ---
$lblLog = New-Object System.Windows.Forms.Label
$lblLog.Text = "Estado:"
$lblLog.Location = New-Object System.Drawing.Point(10, 356)
$lblLog.Size = New-Object System.Drawing.Size(150, 18)
$form.Controls.Add($lblLog)

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Multiline = $true
$txtLog.ReadOnly = $true
$txtLog.ScrollBars = "Vertical"
$txtLog.Location = New-Object System.Drawing.Point(10, 376)
$txtLog.Size = New-Object System.Drawing.Size(340, 100)
$form.Controls.Add($txtLog)

function Escribir-Log([string]$msg) {
    $txtLog.AppendText((Get-Date -Format "HH:mm:ss") + "  " + $msg + "`r`n")
}

# --- Logica del boton Enviar ---
$btnEnviar.Add_Click({
    $ip  = $txtIp.Text.Trim()
    $zpl = $txtZpl.Text

    if ([string]::IsNullOrWhiteSpace($ip)) {
        [System.Windows.Forms.MessageBox]::Show("Escribe la IP de la impresora.", "Falta IP",
            [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }
    if ([string]::IsNullOrWhiteSpace($zpl)) {
        [System.Windows.Forms.MessageBox]::Show("Pega o carga el codigo ZPL.", "Falta ZPL",
            [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }

    $puerto = 0
    if (-not [int]::TryParse($txtPuerto.Text.Trim(), [ref]$puerto)) {
        [System.Windows.Forms.MessageBox]::Show("Puerto invalido.", "Error",
            [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        return
    }

    $btnEnviar.Enabled = $false
    try {
        if ($cboMetodo.SelectedItem -eq "RAW (9100)") {
            Escribir-Log "Enviando por RAW a ${ip}:${puerto} ..."
            $r = Send-ZplRaw -ip $ip -port $puerto -zpl $zpl
        } else {
            Escribir-Log "Enviando por FTP a ${ip}:${puerto} ..."
            $r = Send-ZplFtp -ip $ip -port $puerto -zpl $zpl -passive $chkPasivo.Checked
        }
        Escribir-Log "OK -> $r"
    }
    catch {
        Escribir-Log "ERROR: $($_.Exception.Message)"
    }
    finally {
        $btnEnviar.Enabled = $true
    }
})

[void]$form.ShowDialog()
