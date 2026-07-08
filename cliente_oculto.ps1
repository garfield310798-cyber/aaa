# ================================
# CLIENTE DE CONTEO - VERSION OCULTA (reporta al servidor-tablero)
# - Cuenta cajas (Retail / ECOM), CPM(5 min), estimado e historial por hora.
# - Guarda el registro del DIA en la misma carpeta del script (registro_YYYY-MM-DD.csv).
# - Escucha invitacion UDP del servidor y se conecta por TCP; al conectar envia todo.
# - TOTALMENTE OCULTO: sin consola y SIN icono de bandeja.
#   * Ctrl+F10  -> muestra / oculta la ventana.
#   * Boton "Salir" (dentro de la ventana) -> cierra el programa.
# PowerShell 5.1 compatible
# ================================

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32Console {
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
$h = [Win32Console]::GetConsoleWindow()
if ($h -ne [IntPtr]::Zero) { [Win32Console]::ShowWindow($h, 0) }

$base = $PSScriptRoot
if ([string]::IsNullOrEmpty($base)) { $base = (Get-Location).Path }

Add-Type -ReferencedAssemblies @(
    "System.Windows.Forms",
    "System.Drawing"
) -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;
using System.Drawing;

public class ClienteConteo : Form
{
    static ClienteConteo Instancia;

    // ---- UI ----
    ComboBox cboModo;
    Label lblMini;
    Label lblEstado;
    NotifyIcon trayIcon;
    bool permitirVisible = false;   // arranca oculto; SetVisibleCore lo respeta

    // ---- conteo ----
    static int contador = 0;
    static string buffer = "";
    static bool ultimoFueECOM = false;
    static DateTime ultimoF10 = DateTime.MinValue;   // anti-rebote del hotkey Ctrl+F10
    string modoActual = "Retail";

    static IntPtr hookID = IntPtr.Zero;
    static LowLevelKeyboardProc proc = HookCallback;

    // ---- metricas ----
    List<DateTime> scans = new List<DateTime>();
    const int VENTANA_SEGUNDOS = 300; // 5 min
    const int AUSENTE_SEG = 60;        // sin mouse/teclado por mas de esto = ausente
    double cpmActual = 0;
    int estActual = 0;

    // ---- historial por hora ----
    // Turno de trabajo: 6:00 am a 2:30 pm
    const int HORA_INICIO = 6;   // primera hora del turno (06:00)
    const int HORA_FIN = 14;     // ultima casilla (14 = 2 pm; el turno cierra a las 2:30 pm)
    static readonly TimeSpan TURNO_INI = new TimeSpan(6, 0, 0);
    static readonly TimeSpan TURNO_FIN = new TimeSpan(14, 30, 0);
    List<int> historial = new List<int>();
    List<double> histCpm = new List<double>();
    List<int> histEst = new List<int>();
    int ultimaHora;
    DateTime fechaActual;

    // ---- muestras cada 2 min (CPM e inactividad) ----
    class Muestra { public string Hora; public double Cpm; public int Idle; }
    List<Muestra> muestras = new List<Muestra>();
    object lockMuestras = new object();
    DateTime ultimaMuestra = DateTime.Now;
    const int MUESTRA_SEG = 120; // cada 2 minutos

    // ---- persistencia ----
    public static string CarpetaBase = ".";
    string ArchivoDia { get { return Path.Combine(CarpetaBase, "registro_" + fechaActual.ToString("yyyy-MM-dd") + ".csv"); } }
    string ArchMuestras { get { return Path.Combine(CarpetaBase, "muestras2min_" + fechaActual.ToString("yyyy-MM-dd") + ".csv"); } }

    // ---- red ----
    UdpClient udpEscucha;
    TcpClient tcp;
    NetworkStream flujo;
    bool conectado = false;
    int puertoUdp = 9500;
    string ipServidor = "";
    object lockEnvio = new object();

    // ---- timer ----
    Timer timer;
    int ticksParaEnviar = 0;
    const int ENVIAR_CADA = 3; // segundos

    public ClienteConteo()
    {
        Instancia = this;

        Text = "Conteo";
        Width = 250;
        Height = 190;
        FormBorderStyle = FormBorderStyle.FixedToolWindow;
        StartPosition = FormStartPosition.CenterScreen;
        ShowInTaskbar = false;

        Label l1 = new Label();
        l1.Text = "Area:";
        l1.AutoSize = true;
        l1.Location = new Point(10, 12);

        cboModo = new ComboBox();
        cboModo.DropDownStyle = ComboBoxStyle.DropDownList;
        cboModo.Items.AddRange(new string[] { "Retail", "ECOM" });
        cboModo.SelectedIndex = 0;
        cboModo.Location = new Point(55, 9);
        cboModo.Width = 165;
        cboModo.SelectedIndexChanged += delegate { modoActual = cboModo.Text; };

        lblMini = new Label();
        lblMini.AutoSize = false;
        lblMini.Location = new Point(10, 44);
        lblMini.Width = 220;
        lblMini.Height = 18;
        lblMini.Text = "Contando en segundo plano.";
        lblMini.ForeColor = Color.DimGray;

        lblEstado = new Label();
        lblEstado.AutoSize = false;
        lblEstado.Location = new Point(10, 66);
        lblEstado.Width = 220;
        lblEstado.Height = 30;
        lblEstado.Text = "Buscando servidor...";
        lblEstado.ForeColor = Color.DimGray;

        Label lblAyuda = new Label();
        lblAyuda.AutoSize = false;
        lblAyuda.Location = new Point(10, 96);
        lblAyuda.Width = 220;
        lblAyuda.Height = 16;
        lblAyuda.Text = "Ctrl+F10 = mostrar / ocultar";
        lblAyuda.ForeColor = Color.DimGray;

        Button btnOcultar = new Button();
        btnOcultar.Text = "Ocultar";
        btnOcultar.Location = new Point(10, 116);
        btnOcultar.Width = 100;
        btnOcultar.Height = 26;
        btnOcultar.Click += delegate { ToggleVentana(); };

        Button btnSalir = new Button();
        btnSalir.Text = "Salir";
        btnSalir.Location = new Point(130, 116);
        btnSalir.Width = 100;
        btnSalir.Height = 26;
        btnSalir.Click += delegate { SalirReal(); };

        Controls.Add(cboModo);
        Controls.Add(l1);
        Controls.Add(lblMini);
        Controls.Add(lblEstado);
        Controls.Add(lblAyuda);
        Controls.Add(btnOcultar);
        Controls.Add(btnSalir);

        // ---- bandeja ----
        ContextMenu menu = new ContextMenu();
        menu.MenuItems.Add("Mostrar / ocultar", delegate { ToggleVentana(); });
        menu.MenuItems.Add("Salir", delegate { SalirReal(); });

        trayIcon = new NotifyIcon();
        trayIcon.Icon = SystemIcons.Application;
        trayIcon.Text = "Conteo";
        trayIcon.Visible = false;   // OCULTO: no se muestra icono de bandeja
        trayIcon.ContextMenu = menu;
        trayIcon.DoubleClick += delegate { ToggleVentana(); };

        // ---- historial ----
        for (int hh = HORA_INICIO; hh <= HORA_FIN; hh++) { historial.Add(0); histCpm.Add(0); histEst.Add(0); }
        ultimaHora = DateTime.Now.Hour;
        fechaActual = DateTime.Now.Date;

        CargarDia();
        CargarMuestras();
        ultimaMuestra = DateTime.Now;

        hookID = SetHook(proc);

        timer = new Timer();
        timer.Interval = 1000;
        timer.Tick += Tick;
        timer.Start();

        IniciarEscuchaUdp();
        ActualizarMetricas();

        // Fuerza crear el handle (la ventana sigue oculta) para que el hotkey
        // pueda usar BeginInvoke aunque el formulario nunca se haya mostrado.
        { IntPtr forzarHandle = this.Handle; }
    }

    // ==========================
    // Ventana (oculta por defecto)
    // ==========================
    // Mientras permitirVisible sea false, se ignora cualquier intento de mostrar
    // el formulario (incluido el de Application.Run al arrancar), pero se crea el
    // handle para que el hook, el Timer y la red sigan corriendo en segundo plano.
    protected override void SetVisibleCore(bool value)
    {
        if (!permitirVisible)
        {
            if (!this.IsHandleCreated) { CreateHandle(); }
            value = false;
        }
        base.SetVisibleCore(value);
    }

    void ToggleVentana()
    {
        if (permitirVisible && Visible)
        {
            permitirVisible = false;
            TopMost = false;
            Hide();
        }
        else
        {
            permitirVisible = true;
            Show();
            WindowState = FormWindowState.Normal;
            TopMost = true;      // asegura que salga al frente aunque otra app tenga el foco
            Activate();
            BringToFront();
        }
    }

    void SalirReal()
    {
        try { trayIcon.Visible = false; } catch { }
        try { UnhookWindowsHookEx(hookID); } catch { }
        try { if (udpEscucha != null) udpEscucha.Close(); } catch { }
        try { if (tcp != null) tcp.Close(); } catch { }
        Application.Exit();
    }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        if (e.CloseReason == CloseReason.UserClosing)
        {
            e.Cancel = true;   // la X solo oculta; salir es por la bandeja
            Hide();
            return;
        }
        base.OnFormClosing(e);
    }

    // ==========================
    // Metricas
    // ==========================
    static bool EnTurno()
    {
        TimeSpan t = DateTime.Now.TimeOfDay;
        return t >= TURNO_INI && t < TURNO_FIN;
    }

    void PruneScans()
    {
        DateTime limite = DateTime.Now.AddSeconds(-VENTANA_SEGUNDOS);
        for (int i = scans.Count - 1; i >= 0; i--)
            if (scans[i] < limite) scans.RemoveAt(i);
    }

    void ActualizarMetricas()
    {
        PruneScans();
        double ventanaMin = VENTANA_SEGUNDOS / 60.0;
        cpmActual = scans.Count / ventanaMin;

        DateTime ahora = DateTime.Now;
        DateTime finHora = new DateTime(ahora.Year, ahora.Month, ahora.Day, ahora.Hour, 0, 0).AddHours(1);
        DateTime finTurno = ahora.Date + TURNO_FIN;          // hoy a las 14:30
        DateTime tope = (finTurno < finHora) ? finTurno : finHora;
        double minsRest = (tope - ahora).TotalMinutes;
        if (minsRest < 0) minsRest = 0;
        estActual = contador + (int)Math.Round(cpmActual * minsRest);
    }

    void Tick(object s, EventArgs e)
    {
        DateTime ahora = DateTime.Now;

        // nuevo dia
        if (ahora.Date != fechaActual)
        {
            for (int i = 0; i < historial.Count; i++) { historial[i] = 0; histCpm[i] = 0; histEst[i] = 0; }
            contador = 0;
            scans.Clear();
            lock (lockMuestras) { muestras.Clear(); }
            ultimaMuestra = ahora;
            fechaActual = ahora.Date;
            ultimaHora = ahora.Hour;
        }

        // nueva hora: se congela la foto (conteo, CPM, estimado) de la hora que cierra
        if (ahora.Hour != ultimaHora)
        {
            int idx = ultimaHora - HORA_INICIO;
            if (idx >= 0 && idx < historial.Count) { historial[idx] = contador; histCpm[idx] = cpmActual; histEst[idx] = estActual; }
            contador = 0;
            scans.Clear();
            ultimaHora = ahora.Hour;
        }

        ActualizarMetricas();

        // hora en curso: mantiene CPM y estimado al dia en su casilla
        int idxA = ahora.Hour - HORA_INICIO;
        if (idxA >= 0 && idxA < historial.Count) { histCpm[idxA] = cpmActual; histEst[idxA] = estActual; }

        if (ahora.Second % 15 == 0) GuardarDia();

        // muestra cada 2 min: CPM e inactividad (solo dentro del turno)
        if (EnTurno() && (ahora - ultimaMuestra).TotalSeconds >= MUESTRA_SEG)
        {
            ultimaMuestra = ahora;
            Muestra m = new Muestra();
            m.Hora = ahora.ToString("HH:mm");
            m.Cpm = cpmActual;
            m.Idle = IdleSegundos();
            lock (lockMuestras) { muestras.Add(m); }
            GuardarMuestras();
            EnviarMuestra(m);
        }

        ticksParaEnviar++;
        if (ticksParaEnviar >= ENVIAR_CADA) { ticksParaEnviar = 0; EnviarReporte(); }

        lblEstado.Text = conectado ? ("Conectado a " + ipServidor) : "Buscando servidor...";
    }

    // ==========================
    // Deteccion de escaneos
    // ==========================
    static bool EsNumerico(string s) { return Regex.IsMatch(s, @"^\d{8,15}$"); }
    static bool EsECOM(string s) { return Regex.IsMatch(s, @"^[A-Z]{2}-\d{4}$"); }

    static void Procesar(string txt)
    {
        if (string.IsNullOrEmpty(txt)) return;
        ClienteConteo f = Instancia;
        if (f == null) return;
        if (!EnTurno()) return; // solo cuenta dentro del turno 06:00 - 14:30

        bool sumar = false;
        if (f.modoActual == "Retail")
        {
            if (EsNumerico(txt)) sumar = true;
        }
        else
        {
            if (EsECOM(txt)) { sumar = true; ultimoFueECOM = true; }
            else if (EsNumerico(txt)) { sumar = true; if (ultimoFueECOM) contador--; ultimoFueECOM = false; }
            else ultimoFueECOM = false;
        }

        if (sumar)
        {
            contador++;
            f.scans.Add(DateTime.Now);
            f.ActualizarMetricas();
        }
    }

    static IntPtr HookCallback(int nCode, IntPtr w, IntPtr l)
    {
        // WM_KEYDOWN = 0x0100 ; WM_SYSKEYDOWN = 0x0104 (F10 llega como tecla de sistema)
        if (nCode >= 0 && (w == (IntPtr)0x0100 || w == (IntPtr)0x0104))
        {
            int k = Marshal.ReadInt32(l);

            // ---- Hotkey Ctrl+F10 -> mostrar / ocultar la ventana ----
            // 0x79 = F10 ; 0x11 = Ctrl. El bit 0x8000 indica que la tecla esta abajo.
            if (k == 0x79 && (GetAsyncKeyState(0x11) & 0x8000) != 0)
            {
                // Anti-rebote: ignora el autorepeat dentro de 400 ms, para que un
                // toque de Ctrl+F10 haga UN solo mostrar/ocultar (y no termine oculta).
                if ((DateTime.Now - ultimoF10).TotalMilliseconds >= 400)
                {
                    ultimoF10 = DateTime.Now;
                    ClienteConteo f = Instancia;
                    if (f != null)
                    {
                        // Se difiere al hilo de UI: el hook debe responder rapido y no
                        // conviene mostrar/activar la ventana dentro del propio callback.
                        try { f.BeginInvoke((MethodInvoker)delegate { f.ToggleVentana(); }); } catch { }
                    }
                }
                return CallNextHookEx(hookID, nCode, w, l);
            }

            // ---- Captura de escaneos: solo teclas normales (WM_KEYDOWN) ----
            if (w == (IntPtr)0x0100)
            {
                if (k >= 48 && k <= 57) buffer += (char)k;
                else if (k >= 65 && k <= 90) buffer += (char)k;
                else if (k == 189) buffer += "-";
                else if (k == 13 || k == 9) { Procesar(buffer); buffer = ""; }
                else buffer = "";
            }
        }
        return CallNextHookEx(hookID, nCode, w, l);
    }

    // ==========================
    // Red
    // ==========================
    void IniciarEscuchaUdp()
    {
        try
        {
            udpEscucha = new UdpClient(puertoUdp);
            udpEscucha.BeginReceive(OnInvitacion, null);
        }
        catch (Exception ex) { lblEstado.Text = "Error UDP: " + ex.Message; }
    }

    void OnInvitacion(IAsyncResult ar)
    {
        IPEndPoint remoto = new IPEndPoint(IPAddress.Any, 0);
        byte[] datos;
        try { datos = udpEscucha.EndReceive(ar, ref remoto); }
        catch { return; }

        string msg = Encoding.UTF8.GetString(datos).Trim();
        if (msg.StartsWith("CONNECT:") && !conectado)
        {
            int puertoTcp;
            if (int.TryParse(msg.Substring(8), out puertoTcp))
            {
                ipServidor = remoto.Address.ToString();
                Conectar(ipServidor, puertoTcp);
            }
        }
        try { udpEscucha.BeginReceive(OnInvitacion, null); } catch { }
    }

    void Conectar(string ip, int puerto)
    {
        try { tcp = new TcpClient(); tcp.BeginConnect(ip, puerto, OnConectado, null); }
        catch { }
    }

    void OnConectado(IAsyncResult ar)
    {
        try
        {
            tcp.EndConnect(ar);
            flujo = tcp.GetStream();
            conectado = true;
            EnviarReporte();        // manda el resumen actual
            EnviarMuestrasBulk();   // manda todas las muestras del dia
            byte[] buf = new byte[1024];
            flujo.BeginRead(buf, 0, buf.Length, OnLeer, buf);
        }
        catch { conectado = false; }
    }

    void OnLeer(IAsyncResult ar)
    {
        byte[] buf = (byte[])ar.AsyncState;
        int n;
        try { n = flujo.EndRead(ar); } catch { n = 0; }
        if (n <= 0) { conectado = false; try { tcp.Close(); } catch { } return; }
        try { flujo.BeginRead(buf, 0, buf.Length, OnLeer, buf); } catch { conectado = false; }
    }

    void EnviarReporte()
    {
        if (!conectado || flujo == null) return;
        lock (lockEnvio)
        {
            try
            {
                int horaAhora = DateTime.Now.Hour;
                StringBuilder sb = new StringBuilder();
                sb.Append("REP|MID=").Append(Environment.MachineName);
                sb.Append("|MODO=").Append(modoActual);
                sb.Append("|CNT=").Append(contador);
                sb.Append("|CPM=").Append(cpmActual.ToString("0.00", CultureInfo.InvariantCulture));
                sb.Append("|EST=").Append(estActual);
                sb.Append("|HR=").Append(horaAhora);
                sb.Append("|HINI=").Append(HORA_INICIO);
                sb.Append("|HIST=");
                for (int i = 0; i < historial.Count; i++)
                {
                    if (i > 0) sb.Append(",");
                    int v = historial[i];
                    if ((HORA_INICIO + i) == horaAhora) v = contador; // hora en curso
                    sb.Append(v);
                }
                sb.Append("|HCPM=");
                for (int i = 0; i < histCpm.Count; i++)
                {
                    if (i > 0) sb.Append(",");
                    double v = histCpm[i];
                    if ((HORA_INICIO + i) == horaAhora) v = cpmActual;
                    sb.Append(v.ToString("0.00", CultureInfo.InvariantCulture));
                }
                sb.Append("|HEST=");
                for (int i = 0; i < histEst.Count; i++)
                {
                    if (i > 0) sb.Append(",");
                    int v = histEst[i];
                    if ((HORA_INICIO + i) == horaAhora) v = estActual;
                    sb.Append(v);
                }
                int idle = IdleSegundos();
                sb.Append("|IDLE=").Append(idle);
                sb.Append("|PRES=").Append(idle < AUSENTE_SEG ? 1 : 0);
                sb.Append("\n");
                byte[] datos = Encoding.UTF8.GetBytes(sb.ToString());
                flujo.Write(datos, 0, datos.Length);
            }
            catch { conectado = false; }
        }
    }

    void EnviarMuestra(Muestra m)
    {
        if (!conectado || flujo == null) return;
        lock (lockEnvio)
        {
            try
            {
                string s = "SAMP|MID=" + Environment.MachineName + "|MODO=" + modoActual +
                    "|T=" + m.Hora + "|CPM=" + m.Cpm.ToString("0.00", CultureInfo.InvariantCulture) +
                    "|IDLE=" + m.Idle + "\n";
                byte[] d = Encoding.UTF8.GetBytes(s);
                flujo.Write(d, 0, d.Length);
            }
            catch { conectado = false; }
        }
    }

    void EnviarMuestrasBulk()
    {
        Muestra[] arr;
        lock (lockMuestras) { arr = muestras.ToArray(); }
        foreach (Muestra m in arr) EnviarMuestra(m);
    }

    // ==========================
    // Persistencia (archivo del dia)
    // ==========================
    // Escribe el archivo y lo deja OCULTO. Como WriteAllLines falla si el
    // destino ya esta oculto, primero se le quita el atributo, se escribe y
    // luego se vuelve a marcar como oculto.
    static void EscribirOculto(string ruta, string[] lineas)
    {
        if (File.Exists(ruta))
        {
            try { File.SetAttributes(ruta, FileAttributes.Normal); } catch { }
        }
        File.WriteAllLines(ruta, lineas);
        try { File.SetAttributes(ruta, FileAttributes.Hidden); } catch { }
    }

    void GuardarDia()
    {
        try
        {
            Directory.CreateDirectory(CarpetaBase);
            List<string> lineas = new List<string>();
            lineas.Add("Fecha,Modo,Hora,Conteo,CPM,Estimado");
            string fecha = fechaActual.ToString("yyyy-MM-dd");
            int horaAhora = DateTime.Now.Hour;
            for (int i = 0; i < historial.Count; i++)
            {
                int hora = HORA_INICIO + i;
                int v = historial[i];
                double cpm = histCpm[i];
                int est = histEst[i];
                if (hora == horaAhora) { v = contador; cpm = cpmActual; est = estActual; }
                lineas.Add(fecha + "," + modoActual + "," + hora + "," + v + "," +
                    cpm.ToString("0.00", CultureInfo.InvariantCulture) + "," + est);
            }
            EscribirOculto(ArchivoDia, lineas.ToArray());
        }
        catch { }
    }

    void CargarDia()
    {
        try
        {
            string arch = ArchivoDia;
            if (!File.Exists(arch)) return;
            string[] ls = File.ReadAllLines(arch);
            int horaAhora = DateTime.Now.Hour;
            for (int i = 1; i < ls.Length; i++)
            {
                string[] p = ls[i].Split(',');
                if (p.Length < 4) continue;
                if (p.Length >= 2 && (p[1] == "Retail" || p[1] == "ECOM")) modoActual = p[1];
                int hora, val;
                if (!int.TryParse(p[2], out hora)) continue;
                if (!int.TryParse(p[3], out val)) continue;
                int idx = hora - HORA_INICIO;
                if (idx >= 0 && idx < historial.Count)
                {
                    historial[idx] = val;
                    if (p.Length >= 5) { double cp; if (double.TryParse(p[4], NumberStyles.Any, CultureInfo.InvariantCulture, out cp)) histCpm[idx] = cp; }
                    if (p.Length >= 6) { int es; if (int.TryParse(p[5], out es)) histEst[idx] = es; }
                }
                if (hora == horaAhora) contador = val;
            }
            cboModo.SelectedIndex = (modoActual == "ECOM") ? 1 : 0;
        }
        catch { }
    }

    void GuardarMuestras()
    {
        try
        {
            Directory.CreateDirectory(CarpetaBase);
            Muestra[] arr;
            lock (lockMuestras) { arr = muestras.ToArray(); }
            string fecha = fechaActual.ToString("yyyy-MM-dd");
            List<string> lineas = new List<string>();
            lineas.Add("Fecha,Hora,CPM,InactivoSeg");
            foreach (Muestra m in arr)
                lineas.Add(fecha + "," + m.Hora + "," + m.Cpm.ToString("0.00", CultureInfo.InvariantCulture) + "," + m.Idle);
            EscribirOculto(ArchMuestras, lineas.ToArray());
        }
        catch { }
    }

    void CargarMuestras()
    {
        try
        {
            string arch = ArchMuestras;
            if (!File.Exists(arch)) return;
            string[] ls = File.ReadAllLines(arch);
            for (int i = 1; i < ls.Length; i++)
            {
                string[] p = ls[i].Split(',');
                if (p.Length < 4) continue;
                Muestra m = new Muestra();
                m.Hora = p[1];
                double cp; double.TryParse(p[2], NumberStyles.Any, CultureInfo.InvariantCulture, out cp); m.Cpm = cp;
                int id; int.TryParse(p[3], out id); m.Idle = id;
                muestras.Add(m);
            }
        }
        catch { }
    }

    protected override void OnFormClosed(FormClosedEventArgs e)
    {
        try { UnhookWindowsHookEx(hookID); } catch { }
        try { trayIcon.Visible = false; } catch { }
        base.OnFormClosed(e);
    }

    [STAThread]
    public static void Main()
    {
        Application.EnableVisualStyles();
        Application.Run(new ClienteConteo());
    }

    // ---- hook ----
    static IntPtr SetHook(LowLevelKeyboardProc p) { return SetWindowsHookEx(13, p, IntPtr.Zero, 0); }
    delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] static extern IntPtr SetWindowsHookEx(int id, LowLevelKeyboardProc p, IntPtr h, uint t);
    [DllImport("user32.dll")] static extern bool UnhookWindowsHookEx(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr h, int n, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vKey);

    // ---- presencia: tiempo sin mouse/teclado ----
    [StructLayout(LayoutKind.Sequential)]
    struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
    [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);

    static int IdleSegundos()
    {
        LASTINPUTINFO lii = new LASTINPUTINFO();
        lii.cbSize = (uint)Marshal.SizeOf(lii);
        if (!GetLastInputInfo(ref lii)) return 0;
        long idleMs = (long)((uint)Environment.TickCount) - (long)lii.dwTime;
        if (idleMs < 0) idleMs = 0;
        return (int)(idleMs / 1000);
    }
}
"@

[ClienteConteo]::CarpetaBase = $base
[ClienteConteo]::Main()
