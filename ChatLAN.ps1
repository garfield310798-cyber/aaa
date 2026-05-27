# ============================================================
#  Chat LAN simple - PowerShell + Windows Forms
#  No requiere instalar nada (PowerShell ya viene en Windows 10)
#
#  Como ejecutar:
#    1) Abre PowerShell
#    2) Ejecuta:
#       powershell -ExecutionPolicy Bypass -File "C:\ruta\ChatLAN.ps1"
#
#  Uso:
#    - Una PC pulsa "Escuchar (Servidor)"  -> queda esperando.
#    - La otra PC pone la IP del servidor y pulsa "Conectar (Cliente)".
#    - Ambas pueden enviar y recibir mensajes.
# ============================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ---- Variables de red (scope de script) ----
$script:cliente  = $null   # TcpClient
$script:stream   = $null   # NetworkStream
$script:listener = $null   # TcpListener
$script:buffer   = ""      # buffer de recepcion
$script:enc      = [System.Text.Encoding]::UTF8

# ============================================================
#  Ventana principal
# ============================================================
$form = New-Object System.Windows.Forms.Form
$form.Text = "Chat LAN"
$form.Size = New-Object System.Drawing.Size(500, 500)
$form.MinimumSize = New-Object System.Drawing.Size(420, 380)
$form.StartPosition = "CenterScreen"

# IP
$lblIP = New-Object System.Windows.Forms.Label
$lblIP.Text = "IP:"
$lblIP.Location = New-Object System.Drawing.Point(10, 15)
$lblIP.Size = New-Object System.Drawing.Size(25, 20)
$form.Controls.Add($lblIP)

$txtIP = New-Object System.Windows.Forms.TextBox
$txtIP.Location = New-Object System.Drawing.Point(40, 12)
$txtIP.Size = New-Object System.Drawing.Size(150, 20)
$txtIP.Text = "127.0.0.1"
$form.Controls.Add($txtIP)

# Puerto
$lblPort = New-Object System.Windows.Forms.Label
$lblPort.Text = "Puerto:"
$lblPort.Location = New-Object System.Drawing.Point(200, 15)
$lblPort.Size = New-Object System.Drawing.Size(50, 20)
$form.Controls.Add($lblPort)

$txtPort = New-Object System.Windows.Forms.TextBox
$txtPort.Location = New-Object System.Drawing.Point(250, 12)
$txtPort.Size = New-Object System.Drawing.Size(60, 20)
$txtPort.Text = "5000"
$form.Controls.Add($txtPort)

# Botones de modo
$btnServidor = New-Object System.Windows.Forms.Button
$btnServidor.Text = "Escuchar (Servidor)"
$btnServidor.Location = New-Object System.Drawing.Point(10, 45)
$btnServidor.Size = New-Object System.Drawing.Size(150, 30)
$form.Controls.Add($btnServidor)

$btnConectar = New-Object System.Windows.Forms.Button
$btnConectar.Text = "Conectar (Cliente)"
$btnConectar.Location = New-Object System.Drawing.Point(170, 45)
$btnConectar.Size = New-Object System.Drawing.Size(150, 30)
$form.Controls.Add($btnConectar)

$btnDesconectar = New-Object System.Windows.Forms.Button
$btnDesconectar.Text = "Desconectar"
$btnDesconectar.Location = New-Object System.Drawing.Point(330, 45)
$btnDesconectar.Size = New-Object System.Drawing.Size(140, 30)
$btnDesconectar.Enabled = $false
$form.Controls.Add($btnDesconectar)

# Historial del chat
$txtChat = New-Object System.Windows.Forms.TextBox
$txtChat.Location = New-Object System.Drawing.Point(10, 85)
$txtChat.Size = New-Object System.Drawing.Size(460, 320)
$txtChat.Multiline = $true
$txtChat.ScrollBars = "Vertical"
$txtChat.ReadOnly = $true
$txtChat.BackColor = [System.Drawing.Color]::White
$txtChat.Anchor = [System.Windows.Forms.AnchorStyles]"Top,Bottom,Left,Right"
$form.Controls.Add($txtChat)

# Caja de mensaje
$txtMsg = New-Object System.Windows.Forms.TextBox
$txtMsg.Location = New-Object System.Drawing.Point(10, 415)
$txtMsg.Size = New-Object System.Drawing.Size(360, 20)
$txtMsg.Anchor = [System.Windows.Forms.AnchorStyles]"Bottom,Left,Right"
$form.Controls.Add($txtMsg)

# Boton enviar
$btnEnviar = New-Object System.Windows.Forms.Button
$btnEnviar.Text = "Enviar"
$btnEnviar.Location = New-Object System.Drawing.Point(380, 413)
$btnEnviar.Size = New-Object System.Drawing.Size(90, 25)
$btnEnviar.Enabled = $false
$btnEnviar.Anchor = [System.Windows.Forms.AnchorStyles]"Bottom,Right"
$form.Controls.Add($btnEnviar)

# ============================================================
#  Funciones
# ============================================================
function Log($texto) {
    $hora = (Get-Date).ToString("HH:mm:ss")
    $txtChat.AppendText("[$hora] $texto`r`n")
}

function Cerrar {
    try { if ($script:stream)   { $script:stream.Close() } }   catch {}
    try { if ($script:cliente)  { $script:cliente.Close() } }  catch {}
    try { if ($script:listener) { $script:listener.Stop() } }  catch {}
    $script:stream   = $null
    $script:cliente  = $null
    $script:listener = $null
    $script:buffer   = ""
    $btnServidor.Enabled    = $true
    $btnConectar.Enabled    = $true
    $btnDesconectar.Enabled = $false
    $btnEnviar.Enabled      = $false
}

function Enviar {
    if ($script:stream -ne $null -and $txtMsg.Text.Trim() -ne "") {
        try {
            $data = $script:enc.GetBytes($txtMsg.Text + "`n")
            $script:stream.Write($data, 0, $data.Length)
            $script:stream.Flush()
            Log "Yo: $($txtMsg.Text)"
            $txtMsg.Clear()
        } catch {
            Log "Error al enviar: $($_.Exception.Message)"
            Cerrar
        }
    }
}

# ============================================================
#  Temporizador: acepta conexiones y lee mensajes entrantes
# ============================================================
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 200
$timer.Add_Tick({
    try {
        # Modo servidor: aceptar una conexion entrante
        if ($script:listener -ne $null -and $script:cliente -eq $null) {
            if ($script:listener.Pending()) {
                $script:cliente = $script:listener.AcceptTcpClient()
                $script:stream  = $script:cliente.GetStream()
                Log "Cliente conectado: $($script:cliente.Client.RemoteEndPoint)"
                $btnEnviar.Enabled = $true
            }
        }

        # Leer datos entrantes (sin bloquear)
        if ($script:stream -ne $null -and $script:stream.DataAvailable) {
            $bytes = New-Object byte[] 4096
            $n = $script:stream.Read($bytes, 0, $bytes.Length)
            if ($n -eq 0) {
                Log "El otro extremo cerro la conexion."
                Cerrar
            } else {
                $script:buffer += $script:enc.GetString($bytes, 0, $n)
                while ($script:buffer.Contains("`n")) {
                    $idx   = $script:buffer.IndexOf("`n")
                    $linea = $script:buffer.Substring(0, $idx).TrimEnd("`r")
                    $script:buffer = $script:buffer.Substring($idx + 1)
                    if ($linea -ne "") { Log "Remoto: $linea" }
                }
            }
        }
    } catch {
        Log "Error de red: $($_.Exception.Message)"
        Cerrar
    }
})
$timer.Start()

# ============================================================
#  Eventos de botones
# ============================================================
$btnServidor.Add_Click({
    try {
        $puerto = [int]$txtPort.Text
        $script:listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, $puerto)
        $script:listener.Start()
        Log "Escuchando en el puerto $puerto ... esperando que alguien se conecte."
        $btnServidor.Enabled    = $false
        $btnConectar.Enabled    = $false
        $btnDesconectar.Enabled = $true
    } catch {
        Log "No se pudo iniciar el servidor: $($_.Exception.Message)"
        Cerrar
    }
})

$btnConectar.Add_Click({
    try {
        $ip     = $txtIP.Text.Trim()
        $puerto = [int]$txtPort.Text
        $script:cliente = New-Object System.Net.Sockets.TcpClient
        $script:cliente.Connect($ip, $puerto)
        $script:stream = $script:cliente.GetStream()
        Log "Conectado a $ip : $puerto"
        $btnServidor.Enabled    = $false
        $btnConectar.Enabled    = $false
        $btnDesconectar.Enabled = $true
        $btnEnviar.Enabled      = $true
    } catch {
        Log "No se pudo conectar: $($_.Exception.Message)"
        Cerrar
    }
})

$btnDesconectar.Add_Click({
    Cerrar
    Log "Desconectado."
})

$btnEnviar.Add_Click({ Enviar })

# Enviar con la tecla Enter
$txtMsg.Add_KeyDown({
    if ($_.KeyCode -eq "Enter") {
        $_.SuppressKeyPress = $true
        Enviar
    }
})

# Limpiar al cerrar la ventana
$form.Add_FormClosing({
    $timer.Stop()
    Cerrar
})

# Mostrar ventana
[void]$form.ShowDialog()
