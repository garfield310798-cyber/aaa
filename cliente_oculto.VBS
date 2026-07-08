' ================================================
' Iniciador SIN ventana para cliente_oculto.ps1
' - Arranca PowerShell con la ventana oculta (0)
' - No espera (False): no bloquea ninguna terminal
' Uso: doble clic a este archivo, o  wscript cliente_oculto.vbs
' ================================================
Dim sh, ruta
Set sh = CreateObject("WScript.Shell")

' Ruta al script, relativa a la carpeta de este .vbs
ruta = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName) & "\cliente_oculto.ps1"

sh.Run "powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File """ & ruta & """", 0, False
