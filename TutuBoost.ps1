# =========================================================
#  TUTUBOOST - Windows optimizer for CS2
#  - Matrix-style interface with side menu, cards and toggles
#  - Saves the ORIGINAL value of everything it changes (backups\tutuboost_baseline.json)
#  - REVERT ALL restores the PC to its state before TutuBoost
#  - HPET is never enabled (it dropped CS2 from ~546 to ~250 FPS)
# =========================================================

$ErrorActionPreference = 'Continue'

function Show-Fatal($msg) {
    try { (New-Object -ComObject WScript.Shell).Popup($msg, 0, 'TutuBoost', 16) | Out-Null } catch {}
}
trap { Show-Fatal ("Error: " + $_.Exception.Message + "`nLine: " + $_.InvocationInfo.ScriptLineNumber); exit 1 }

# ---- Auto-elevation to Administrator ----
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`""
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$ScriptDir = Split-Path -Parent $PSCommandPath
$BackupDir = Join-Path $ScriptDir 'backups'
if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir | Out-Null }
$BaseFile  = Join-Path $BackupDir 'tutuboost_baseline.json'
$LogFile   = Join-Path $BackupDir 'tutuboost.log'
$CleanFile = Join-Path $BackupDir 'ultima_limpeza.txt'

# ---------------------------------------------------------
# Native API: monitor Hz, instant mouse apply and dark title bar
# ---------------------------------------------------------
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class TBNative {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public struct DEVMODE {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
        public short dmSpecVersion; public short dmDriverVersion; public short dmSize; public short dmDriverExtra;
        public int dmFields;
        public int dmPositionX; public int dmPositionY; public int dmDisplayOrientation; public int dmDisplayFixedOutput;
        public short dmColor; public short dmDuplex; public short dmYResolution; public short dmTTOption; public short dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel; public int dmPelsWidth; public int dmPelsHeight; public int dmDisplayFlags; public int dmDisplayFrequency;
        public int dmICMMethod; public int dmICMIntent; public int dmMediaType; public int dmDitherType;
        public int dmReserved1; public int dmReserved2; public int dmPanningWidth; public int dmPanningHeight;
    }
    [DllImport("user32.dll", CharSet = CharSet.Ansi)] public static extern bool EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);
    [DllImport("user32.dll", CharSet = CharSet.Ansi)] public static extern int ChangeDisplaySettings(ref DEVMODE devMode, int flags);
    [DllImport("user32.dll")] public static extern bool SystemParametersInfo(int action, int param, int[] vparam, int winIni);
    [DllImport("user32.dll", EntryPoint = "SystemParametersInfo")] public static extern bool SystemParametersInfoPtr(int action, int param, IntPtr vparam, int winIni);
    [DllImport("user32.dll", EntryPoint = "SystemParametersInfo")] public static extern bool SpiGetInt(int action, int param, ref int v, int winIni);
    [DllImport("dwmapi.dll")] private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int val, int size);
    public static void DarkTitle(IntPtr h, int cap, int txt, int bor, int dark) {
        int one = dark;
        DwmSetWindowAttribute(h, 20, ref one, 4);
        DwmSetWindowAttribute(h, 19, ref one, 4);
        DwmSetWindowAttribute(h, 35, ref cap, 4);
        DwmSetWindowAttribute(h, 36, ref txt, 4);
        DwmSetWindowAttribute(h, 34, ref bor, 4);
    }
}
'@

# ---------------------------------------------------------
# Custom-drawn controls (card, toggle, menu, button, chip, scroll)
# ---------------------------------------------------------
$ControlsCode = @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Windows.Forms;

public static class TbTheme
{
    public static double Shift = 0;
    public static int Mode = 0;

    private static double Hue2(double p, double q, double t)
    {
        if (t < 0) t += 1;
        if (t > 1) t -= 1;
        if (t < 1.0 / 6) return p + (q - p) * 6 * t;
        if (t < 0.5) return q;
        if (t < 2.0 / 3) return p + (q - p) * (2.0 / 3 - t) * 6;
        return p;
    }

    public static Color C(int r, int g, int b)
    {
        if (Mode == 1 || Mode == 2)
        {
            double y = 0.2126 * r + 0.7152 * g + 0.0722 * b;
            double v = System.Math.Min(255.0, y * 1.3);
            if (Mode == 2) v = 255.0 - v;
            int k = (int)System.Math.Round(v);
            return Color.FromArgb(k, k, k);
        }
        if (Shift == 0) return Color.FromArgb(r, g, b);
        double rf = r / 255.0, gf = g / 255.0, bf = b / 255.0;
        double mx = System.Math.Max(rf, System.Math.Max(gf, bf));
        double mn = System.Math.Min(rf, System.Math.Min(gf, bf));
        double l = (mx + mn) / 2, h = 0, s = 0, d = mx - mn;
        if (d < 0.00001) return Color.FromArgb(r, g, b);
        s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn);
        if (mx == rf) h = (gf - bf) / d + (gf < bf ? 6 : 0);
        else if (mx == gf) h = (bf - rf) / d + 2;
        else h = (rf - gf) / d + 4;
        h = h * 60 + Shift;
        h = h % 360;
        if (h < 0) h += 360;
        h = h / 360.0;
        double q = l < 0.5 ? l * (1 + s) : l + s - l * s;
        double p = 2 * l - q;
        int R = (int)System.Math.Round(Hue2(p, q, h + 1.0 / 3) * 255);
        int G = (int)System.Math.Round(Hue2(p, q, h) * 255);
        int B = (int)System.Math.Round(Hue2(p, q, h - 1.0 / 3) * 255);
        return Color.FromArgb(R, G, B);
    }
}

public static class TbGfx
{
    public static GraphicsPath Round(float x, float y, float w, float h, float r)
    {
        GraphicsPath p = new GraphicsPath();
        float d = r * 2f;
        if (d > w) { d = w; }
        if (d > h) { d = h; }
        if (d < 1f) { d = 1f; }
        p.AddArc(x, y, d, d, 180f, 90f);
        p.AddArc(x + w - d, y, d, d, 270f, 90f);
        p.AddArc(x + w - d, y + h - d, d, d, 0f, 90f);
        p.AddArc(x, y + h - d, d, d, 90f, 90f);
        p.CloseFigure();
        return p;
    }

    public static void Quality(Graphics g)
    {
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
    }
}

// Rounded card: children automatically get the card background color
public class TbCard : Panel
{
    private Color _fill = TbTheme.C(5, 20, 9);
    private Color _border = TbTheme.C(12, 58, 24);
    private int _radius = 12;

    public TbCard()
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
    }

    public Color Fill
    {
        get { return _fill; }
        set { _fill = value; ApplyChildren(); Invalidate(); }
    }

    public Color Border
    {
        get { return _border; }
        set { _border = value; Invalidate(); }
    }

    public int Radius
    {
        get { return _radius; }
        set { _radius = value; Invalidate(); }
    }

    public void ApplyChildren()
    {
        foreach (Control c in Controls)
        {
            if (!(c is TbCard)) { c.BackColor = _fill; }
        }
    }

    protected override void OnControlAdded(ControlEventArgs e)
    {
        base.OnControlAdded(e);
        if (!(e.Control is TbCard)) { e.Control.BackColor = _fill; }
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        TbGfx.Quality(g);
        g.Clear(BackColor);
        using (GraphicsPath p = TbGfx.Round(0.5f, 0.5f, Width - 2f, Height - 2f, _radius))
        using (SolidBrush b = new SolidBrush(_fill))
        using (Pen pen = new Pen(_border, 1f))
        {
            g.FillPath(b, p);
            g.DrawPath(pen, p);
        }
    }
}

// iOS-style toggle switch
public class TbToggle : Control
{
    private bool _on;
    public Color OnColor = TbTheme.C(0, 255, 65);
    public Color OffColor = TbTheme.C(14, 40, 20);
    public event EventHandler CheckedChanged;

    public TbToggle()
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        SetStyle(ControlStyles.Selectable, false);
        Size = new Size(44, 24);
        Cursor = Cursors.Hand;
        TabStop = false;
    }

    public bool Checked
    {
        get { return _on; }
        set
        {
            if (_on == value) { return; }
            _on = value;
            Invalidate();
            EventHandler h = CheckedChanged;
            if (h != null) { h(this, EventArgs.Empty); }
        }
    }

    protected override void OnClick(EventArgs e)
    {
        base.OnClick(e);
        if (Enabled) { Checked = !_on; }
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        TbGfx.Quality(g);
        g.Clear(BackColor);
        Color track = _on ? OnColor : OffColor;
        Color edge = _on ? OnColor : TbTheme.C(30, 100, 50);
        using (GraphicsPath p = TbGfx.Round(0.5f, 0.5f, Width - 2f, Height - 2f, (Height - 2f) / 2f))
        using (SolidBrush b = new SolidBrush(track))
        using (Pen pen = new Pen(edge, 1f))
        {
            g.FillPath(b, p);
            g.DrawPath(pen, p);
        }
        int k = Height - 10;
        int x = _on ? (Width - k - 5) : 5;
        using (SolidBrush kb = new SolidBrush(_on ? TbTheme.C(0, 20, 5) : TbTheme.C(0, 190, 55)))
        {
            g.FillEllipse(kb, x, 5, k, k);
        }
    }
}

// Side menu button
public class TbNav : Control
{
    public string Glyph = "";
    public Color Accent = TbTheme.C(0, 255, 65);
    public Color Dim = TbTheme.C(0, 150, 40);
    private bool _sel;
    private bool _hover;

    public TbNav()
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        SetStyle(ControlStyles.Selectable, false);
        Cursor = Cursors.Hand;
        TabStop = false;
    }

    public bool Selected
    {
        get { return _sel; }
        set { _sel = value; Invalidate(); }
    }

    protected override void OnMouseEnter(EventArgs e) { base.OnMouseEnter(e); _hover = true; Invalidate(); }
    protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); _hover = false; Invalidate(); }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        TbGfx.Quality(g);
        g.Clear(BackColor);
        if (_sel || _hover)
        {
            using (GraphicsPath p = TbGfx.Round(4f, 2f, Width - 8f, Height - 5f, 9f))
            using (SolidBrush b = new SolidBrush(_sel ? TbTheme.C(7, 44, 18) : TbTheme.C(4, 26, 11)))
            {
                g.FillPath(b, p);
            }
        }
        if (_sel)
        {
            using (SolidBrush bar = new SolidBrush(Accent))
            {
                g.FillRectangle(bar, 0, 9, 3, Height - 18);
            }
        }
        Color fc = _sel ? Accent : Dim;
        using (SolidBrush tb = new SolidBrush(fc))
        using (Font gf = new Font("Segoe MDL2 Assets", 12f))
        using (Font tf = new Font("Consolas", 10.5f, FontStyle.Bold))
        {
            g.DrawString(Glyph, gf, tb, 18f, (Height - gf.Height) / 2f);
            g.DrawString(Text, tf, tb, 50f, (Height - tf.Height) / 2f);
        }
    }
}

// Action button. Style: 0 = filled (green), 1 = outline, 2 = danger (red)
public class TbButton : Control
{
    public int Style = 0;
    public Color Accent = TbTheme.C(0, 255, 65);
    private bool _hover;
    private bool _down;

    public TbButton()
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        SetStyle(ControlStyles.Selectable, false);
        Cursor = Cursors.Hand;
        TabStop = false;
        Font = new Font("Consolas", 10f, FontStyle.Bold);
    }

    protected override void OnMouseEnter(EventArgs e) { base.OnMouseEnter(e); _hover = true; Invalidate(); }
    protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); _hover = false; _down = false; Invalidate(); }
    protected override void OnMouseDown(MouseEventArgs e) { base.OnMouseDown(e); _down = true; Invalidate(); }
    protected override void OnMouseUp(MouseEventArgs e) { base.OnMouseUp(e); _down = false; Invalidate(); }
    protected override void OnEnabledChanged(EventArgs e) { base.OnEnabledChanged(e); Invalidate(); }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        TbGfx.Quality(g);
        g.Clear(BackColor);
        Color c = (Style == 2) ? Color.FromArgb(255, 70, 70) : Accent;
        if (!Enabled) { c = TbTheme.C(35, 85, 50); }
        Color textColor;
        using (GraphicsPath p = TbGfx.Round(0.5f, 0.5f, Width - 2f, Height - 2f, 9f))
        {
            if (Style == 0 && Enabled)
            {
                Color f = _down ? TbTheme.C(0, 190, 50) : (_hover ? TbTheme.C(90, 255, 130) : c);
                using (SolidBrush b = new SolidBrush(f)) { g.FillPath(b, p); }
                textColor = TbTheme.C(0, 20, 5);
            }
            else
            {
                if (_hover && Enabled)
                {
                    using (SolidBrush b = new SolidBrush(Color.FromArgb(_down ? 70 : 40, c))) { g.FillPath(b, p); }
                }
                using (Pen pen = new Pen(c, 1.5f)) { g.DrawPath(pen, p); }
                textColor = c;
            }
        }
        using (SolidBrush tb = new SolidBrush(textColor))
        using (StringFormat sf = new StringFormat())
        {
            sf.Alignment = StringAlignment.Center;
            sf.LineAlignment = StringAlignment.Center;
            g.DrawString(Text, Font, tb, new RectangleF(0f, 0f, (float)Width, (float)Height), sf);
        }
    }
}

// Filter chip (pill)
public class TbChip : Control
{
    public Color Accent = TbTheme.C(0, 255, 65);
    private bool _sel;
    private bool _hover;

    public TbChip()
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        SetStyle(ControlStyles.Selectable, false);
        Cursor = Cursors.Hand;
        TabStop = false;
        Font = new Font("Consolas", 9f, FontStyle.Bold);
    }

    public bool Selected
    {
        get { return _sel; }
        set { _sel = value; Invalidate(); }
    }

    protected override void OnMouseEnter(EventArgs e) { base.OnMouseEnter(e); _hover = true; Invalidate(); }
    protected override void OnMouseLeave(EventArgs e) { base.OnMouseLeave(e); _hover = false; Invalidate(); }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        TbGfx.Quality(g);
        g.Clear(BackColor);
        Color textColor;
        using (GraphicsPath p = TbGfx.Round(0.5f, 0.5f, Width - 2f, Height - 2f, (Height - 2f) / 2f))
        {
            if (_sel)
            {
                using (SolidBrush b = new SolidBrush(Accent)) { g.FillPath(b, p); }
                textColor = TbTheme.C(0, 20, 5);
            }
            else
            {
                using (SolidBrush b = new SolidBrush(_hover ? TbTheme.C(6, 34, 14) : TbTheme.C(4, 18, 8))) { g.FillPath(b, p); }
                using (Pen pen = new Pen(TbTheme.C(14, 70, 30), 1f)) { g.DrawPath(pen, p); }
                textColor = TbTheme.C(0, 190, 55);
            }
        }
        using (SolidBrush tb = new SolidBrush(textColor))
        using (StringFormat sf = new StringFormat())
        {
            sf.Alignment = StringAlignment.Center;
            sf.LineAlignment = StringAlignment.Center;
            g.DrawString(Text, Font, tb, new RectangleF(0f, 0f, (float)Width, (float)Height), sf);
        }
    }
}

// Custom scroll area (thin green bar, mouse wheel scrolling)
public class TbScroll : Panel
{
    public Panel Inner;
    private int _off = 0;
    private int _content = 0;

    public TbScroll()
    {
        SetStyle(ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        Inner = new Panel();
        Inner.Location = new Point(0, 0);
        Inner.Size = new Size(100, 100);
        Controls.Add(Inner);
    }

    public override Color BackColor
    {
        get { return base.BackColor; }
        set
        {
            base.BackColor = value;
            if (Inner != null) { Inner.BackColor = value; }
        }
    }

    protected override void OnResize(EventArgs e)
    {
        base.OnResize(e);
        if (Inner != null)
        {
            Inner.Width = Math.Max(10, Width - 14);
            Inner.Height = Math.Max(_content, Height);
            SetOffset(_off);
        }
    }

    public void SetContentHeight(int h)
    {
        _content = h;
        Inner.Width = Math.Max(10, Width - 14);
        Inner.Height = Math.Max(h, Height);
        SetOffset(_off);
    }

    public void ScrollBy(int delta)
    {
        SetOffset(_off + delta);
    }

    private void SetOffset(int v)
    {
        int max = Math.Max(0, Inner.Height - Height);
        if (v < 0) { v = 0; }
        if (v > max) { v = max; }
        _off = v;
        Inner.Top = -_off;
        Invalidate();
    }

    protected override void OnMouseDown(MouseEventArgs e)
    {
        base.OnMouseDown(e);
        if (e.X >= Width - 14 && Inner.Height > Height)
        {
            double ratio = (double)e.Y / (double)Height;
            SetOffset((int)(ratio * (Inner.Height - Height)));
        }
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        TbGfx.Quality(g);
        g.Clear(BackColor);
        if (Inner.Height > Height)
        {
            int max = Inner.Height - Height;
            int th = Math.Max(30, (int)((double)Height * Height / Inner.Height));
            int ty = (int)((double)(Height - th) * _off / max);
            using (SolidBrush tr = new SolidBrush(TbTheme.C(6, 28, 12)))
            using (SolidBrush tb = new SolidBrush(TbTheme.C(0, 170, 48)))
            {
                g.FillRectangle(tr, Width - 8, 0, 4, Height);
                g.FillRectangle(tb, Width - 8, ty, 4, th);
            }
        }
    }
}
'@
Add-Type -TypeDefinition $ControlsCode -ReferencedAssemblies 'System.Windows.Forms', 'System.Drawing'

# ---------------------------------------------------------
# Settings (theme and first run)
# ---------------------------------------------------------
$ConfigFile = Join-Path $BackupDir 'config.json'
$script:Config = @{ Theme = 'matrix'; FirstRunDone = $false; PendingGuide = $false; Cs2Path = '' }
try {
    if (Test-Path $ConfigFile) {
        $j = Get-Content $ConfigFile -Raw | ConvertFrom-Json
        foreach ($k in @('Theme', 'FirstRunDone', 'PendingGuide', 'Cs2Path')) { if ($null -ne $j.$k) { $script:Config[$k] = $j.$k } }
    }
} catch {}
function Save-Config {
    try { ($script:Config | ConvertTo-Json) | Set-Content -Path $ConfigFile -Encoding UTF8 } catch {}
}
$script:Themes = [ordered]@{
    matrix = @{ Name = 'Matrix';         Shift = 0;  Mode = 0; Acc = [System.Drawing.Color]::FromArgb(0, 255, 65) }
    ciano  = @{ Name = 'Cyan';          Shift = 50; Mode = 0; Acc = [System.Drawing.Color]::FromArgb(0, 229, 255) }
    mono   = @{ Name = 'Black and White'; Shift = 0;  Mode = 1; Acc = [System.Drawing.Color]::FromArgb(235, 235, 235) }
    claro  = @{ Name = 'Light';          Shift = 0;  Mode = 2; Acc = [System.Drawing.Color]::FromArgb(70, 70, 70) }
}
if (-not $script:Themes.Contains([string]$script:Config.Theme)) { $script:Config.Theme = 'matrix' }
[TbTheme]::Shift = [double]$script:Themes[[string]$script:Config.Theme].Shift
[TbTheme]::Mode = [int]$script:Themes[[string]$script:Config.Theme].Mode
$script:IsLight = ([TbTheme]::Mode -eq 2)
function Bgr($c) { return ([int]$c.R + ([int]$c.G -shl 8) + ([int]$c.B -shl 16)) }
function Restart-App {
    try { Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`"" } catch {}
    $Form.Close()
}

# ---------------------------------------------------------
# Colors / fonts (Matrix theme)
# ---------------------------------------------------------
function RGB($r, $g, $b) { return [TbTheme]::C($r, $g, $b) }
function Mk-Font($size, $bold = $false, $name = 'Consolas') {
    $st = [System.Drawing.FontStyle]::Regular
    if ($bold) { $st = [System.Drawing.FontStyle]::Bold }
    return (New-Object System.Drawing.Font($name, [single]$size, $st))
}
$cBg     = RGB 2 10 4
$cSide   = RGB 1 7 3
$cCard   = RGB 5 20 9
$cCard2  = RGB 3 13 6
$cBorder = RGB 12 58 24
$cOnFill = RGB 6 38 15
$cOnBord = RGB 0 190 55
$cGreen  = RGB 0 255 65
$cDim    = RGB 0 160 45
$cMuted  = RGB 60 130 80
if ($script:IsLight) {
    $cRed    = [System.Drawing.Color]::FromArgb(200, 40, 40)
    $cRedBg  = [System.Drawing.Color]::FromArgb(255, 232, 232)
    $cRedBd  = [System.Drawing.Color]::FromArgb(220, 120, 120)
} else {
    $cRed    = [System.Drawing.Color]::FromArgb(255, 70, 70)
    $cRedBg  = [System.Drawing.Color]::FromArgb(30, 8, 8)
    $cRedBd  = [System.Drawing.Color]::FromArgb(120, 30, 30)
}
$cIcon   = RGB 4 48 18
$fTitle  = Mk-Font 15 $true
$fH      = Mk-Font 11 $true
$fB      = Mk-Font 10 $true
$fN      = Mk-Font 9
$fSm     = Mk-Font 8.5
$fBig    = Mk-Font 15 $true
$fGlyph  = Mk-Font 16 $false 'Segoe MDL2 Assets'

# ---------------------------------------------------------
# Log
# ---------------------------------------------------------
$script:LogBox = $null
function Log($m) {
    if ($script:LogBox) {
        $script:LogBox.AppendText("$m`r`n")
        [System.Windows.Forms.Application]::DoEvents()
    }
    try { Add-Content -Path $LogFile -Value ("{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) -Encoding UTF8 -ErrorAction SilentlyContinue } catch {}
}
function Ask($msg, $title = 'TutuBoost') {
    return ([System.Windows.Forms.MessageBox]::Show($msg, $title, 'YesNo', 'Question') -eq 'Yes')
}

# ---------------------------------------------------------
# Baseline (ORIGINAL state of everything TutuBoost touches)
# ---------------------------------------------------------
function Arr($x) { if ($null -eq $x) { return ,@() } else { return ,@($x) } }

function Load-Base {
    if (Test-Path $BaseFile) {
        $j = Get-Content $BaseFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $script:Base = @{
            Reg = (Arr $j.Reg); Bcd = (Arr $j.Bcd); Svc = (Arr $j.Svc); Power = (Arr $j.Power)
            Plan = $j.Plan; Display = $j.Display; Defender = $j.Defender; Hibernate = $j.Hibernate; Anim = $j.Anim
        }
    } else {
        $script:Base = @{ Reg = @(); Bcd = @(); Svc = @(); Power = @(); Plan = $null; Display = $null; Defender = $null; Hibernate = $null; Anim = $null }
    }
}
function Save-Base {
    ConvertTo-Json -InputObject $script:Base -Depth 6 | Out-File -FilePath $BaseFile -Encoding UTF8
}
function Base-Has($list, $key) {
    foreach ($i in $list) { if ($i.Key -eq $key) { return $true } }
    return $false
}

# ---------------------------------------------------------
# Registry (with automatic backup of the old value)
# ---------------------------------------------------------
function RegPath($Hive, $Path) { return "$($Hive):\$Path" }

function Get-RegVal($Hive, $Path, $Name) {
    try { return (Get-ItemProperty -LiteralPath (RegPath $Hive $Path) -Name $Name -ErrorAction Stop).$Name } catch { return $null }
}

function Backup-Reg($Hive, $Path, $Name) {
    $key = "$Hive|$Path|$Name"
    if (Base-Has $script:Base.Reg $key) { return }
    $full = RegPath $Hive $Path
    $old = $null; $kind = $null
    if (Test-Path -LiteralPath $full) {
        $k = Get-Item -LiteralPath $full
        if ($k.GetValueNames() -contains $Name) {
            $old  = $k.GetValue($Name, $null, 'DoNotExpandEnvironmentNames')
            $kind = $k.GetValueKind($Name).ToString()
        }
    }
    $script:Base.Reg += [PSCustomObject]@{ Key = $key; Hive = $Hive; Path = $Path; Name = $Name; Kind = $kind; Old = $old }
}

function Set-Reg($Hive, $Path, $Name, $Type, $Value) {
    Backup-Reg $Hive $Path $Name
    $full = RegPath $Hive $Path
    try {
        if (-not (Test-Path -LiteralPath $full)) { New-Item -Path $full -Force | Out-Null }
        New-ItemProperty -LiteralPath $full -Name $Name -PropertyType $Type -Value $Value -Force -ErrorAction Stop | Out-Null
    } catch {
        Log "  ! failed: $Name ($($_.Exception.Message))"
    }
}

function Remove-RegValue($Hive, $Path, $Name) {
    $full = RegPath $Hive $Path
    if ($null -eq (Get-RegVal $Hive $Path $Name)) { return $false }
    Backup-Reg $Hive $Path $Name
    Remove-ItemProperty -LiteralPath $full -Name $Name -ErrorAction SilentlyContinue
    return $true
}

function Restore-Reg($r) {
    $full = RegPath $r.Hive $r.Path
    try {
        if ($null -eq $r.Old) {
            Remove-ItemProperty -LiteralPath $full -Name $r.Name -ErrorAction SilentlyContinue
        } else {
            $type = switch ($r.Kind) { 'DWord' { 'DWord' } 'QWord' { 'QWord' } 'Binary' { 'Binary' } 'ExpandString' { 'ExpandString' } 'MultiString' { 'MultiString' } default { 'String' } }
            $val = $r.Old
            if ($type -eq 'Binary') { $val = [byte[]]@($r.Old) }
            if ($type -eq 'DWord')  { $val = [int]$r.Old }
            if (-not (Test-Path -LiteralPath $full)) { New-Item -Path $full -Force | Out-Null }
            New-ItemProperty -LiteralPath $full -Name $r.Name -PropertyType $type -Value $val -Force -ErrorAction Stop | Out-Null
        }
    } catch { Log "  ! could not restore $($r.Name): $($_.Exception.Message)" }
}

# ---------------------------------------------------------
# bcdedit
# ---------------------------------------------------------
function Get-BcdValue($Name) {
    $out = & bcdedit /enum '{current}' 2>$null
    foreach ($line in $out) {
        if ($line -match "^\s*$([regex]::Escape($Name))\s+(.+?)\s*$") { return $Matches[1] }
    }
    return $null
}
function Run-Bcd([string[]]$BcdArgs) { & bcdedit @BcdArgs 2>&1 | Out-Null }
function Backup-Bcd($Name) {
    if (Base-Has $script:Base.Bcd $Name) { return }
    $script:Base.Bcd += [PSCustomObject]@{ Key = $Name; Name = $Name; Old = (Get-BcdValue $Name) }
}

# ---------------------------------------------------------
# Services
# ---------------------------------------------------------
function Disable-Svc($name) {
    $s = Get-Service -Name $name -ErrorAction SilentlyContinue
    if (-not $s) { return }
    if (-not (Base-Has $script:Base.Svc $name)) {
        $script:Base.Svc += [PSCustomObject]@{ Key = $name; Name = $name; Start = $s.StartType.ToString(); Status = $s.Status.ToString() }
    }
    Stop-Service -Name $name -Force -ErrorAction SilentlyContinue
    Set-Service -Name $name -StartupType Disabled -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------
# Power (powercfg)
# ---------------------------------------------------------
function Get-ActivePlan {
    $t = (powercfg /getactivescheme) -join ' '
    if ($t -match '([0-9a-fA-F]{8}-[0-9a-fA-F-]{27})') { return $Matches[1] }
    return $null
}
function Get-PowerAC($plan, $sub, $set) {
    $o = (powercfg /query $plan $sub $set 2>$null) -join "`n"
    $m = [regex]::Matches($o, '0x[0-9a-fA-F]{8}')
    if ($m.Count -ge 2) { return [Convert]::ToUInt32($m[$m.Count - 2].Value.Substring(2), 16) }
    return $null
}
function Get-PerfPlan {
    $lines = (powercfg /list) -split "`n"
    foreach ($line in $lines) {
        if ($line -match '([0-9a-fA-F]{8}-[0-9a-fA-F-]{27})\s+\((.+?)\)') {
            $g = $Matches[1]; $n = $Matches[2]
            if ($n -match '(?i)ultimate|m[aá]ximo') { return $g }
        }
    }
    $dup = (powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1) -join ' '
    if ($dup -match '([0-9a-fA-F]{8}-[0-9a-fA-F-]{27})') { return $Matches[1] }
    return '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'   # Alto desempenho
}

# ---------------------------------------------------------
# Monitor: maximum Hz at the current resolution
# ---------------------------------------------------------
function Set-Refresh([int]$Target = 0) {
    $dm = New-Object TBNative+DEVMODE
    $dm.dmSize = [int16][System.Runtime.InteropServices.Marshal]::SizeOf([type]'TBNative+DEVMODE')
    if (-not [TBNative]::EnumDisplaySettings($null, -1, [ref]$dm)) { Log '  ! could not read the monitor'; return $null }
    $cur = $dm.dmDisplayFrequency; $w = $dm.dmPelsWidth; $h = $dm.dmPelsHeight; $bpp = $dm.dmBitsPerPel
    $best = $null; $bestHz = $cur
    $i = 0
    while ($true) {
        $m = New-Object TBNative+DEVMODE
        $m.dmSize = $dm.dmSize
        if (-not [TBNative]::EnumDisplaySettings($null, $i, [ref]$m)) { break }
        $i++
        if ($m.dmPelsWidth -ne $w -or $m.dmPelsHeight -ne $h -or $m.dmBitsPerPel -ne $bpp) { continue }
        if (($m.dmDisplayFlags -band 2) -ne 0) { continue }   # skip interlaced
        if ($Target -eq 0) {
            if ($m.dmDisplayFrequency -gt $bestHz) { $bestHz = $m.dmDisplayFrequency; $best = $m }
        } elseif ($m.dmDisplayFrequency -eq $Target -and $Target -ne $cur) { $best = $m }
    }
    if (-not $best) { Log "  Monitor Hz: $cur Hz (already at maximum)"; return $null }
    if ([TBNative]::ChangeDisplaySettings([ref]$best, 2) -ne 0) { Log "  ! monitor did not accept $($best.dmDisplayFrequency) Hz"; return $null }
    if ([TBNative]::ChangeDisplaySettings([ref]$best, 1) -ne 0) { Log '  ! failed to change the Hz'; return $null }
    Log "  Monitor Hz: $cur -> $($best.dmDisplayFrequency) Hz"
    return $cur
}

function Apply-MouseNow {
    try {
        $m = Get-ItemProperty 'HKCU:\Control Panel\Mouse'
        $sens = 10; if ($m.MouseSensitivity) { $sens = [int]$m.MouseSensitivity }
        [int[]]$v = @([int]$m.MouseThreshold1, [int]$m.MouseThreshold2, [int]$m.MouseSpeed)
        [void][TBNative]::SystemParametersInfo(0x0004, 0, $v, 3)
        [void][TBNative]::SystemParametersInfoPtr(0x0071, 0, [IntPtr]$sens, 3)
    } catch {}
}

# =========================================================
#  MODULES (each one is applied automatically)
# =========================================================
function Mod-Energia {
    $cur = Get-ActivePlan
    if ($null -eq $script:Base.Plan) { $script:Base.Plan = $cur }
    $target = Get-PerfPlan
    powercfg /setactive $target 2>&1 | Out-Null
    $now = Get-ActivePlan
    if ($now -ne $target) { $target = $now }
    Log "  Power plan: maximum performance active"

    $settings = @(
        @('54533251-82be-4824-96c1-47b60b740d00', '0cc5b647-c1df-4637-891a-dec35c318583', 100),  # cores always active (core parking off)
        @('54533251-82be-4824-96c1-47b60b740d00', '893dee8e-2bef-41e0-89c6-b55d0929964c', 100),  # minimum processor state
        @('2a737441-1930-4402-8d77-b2bebba308a3', '48e6b7a6-50f5-4782-a5d4-53bb8f07e226', 0),    # USB without selective suspend
        @('501a4d13-42af-4429-9fd1-a8218c268e20', 'ee12f906-d277-404b-b6da-e5fa1a576df5', 0)     # PCIe without power saving (ASPM)
    )
    foreach ($s in $settings) {
        $k = "$target|$($s[0])|$($s[1])"
        if (-not (Base-Has $script:Base.Power $k)) {
            $old = Get-PowerAC $target $s[0] $s[1]
            if ($null -ne $old) { $script:Base.Power += [PSCustomObject]@{ Key = $k; Plan = $target; Sub = $s[0]; Set = $s[1]; Old = $old } }
        }
        powercfg /setacvalueindex $target $s[0] $s[1] $s[2] 2>&1 | Out-Null
    }
    powercfg /setactive $target 2>&1 | Out-Null
    Log '  Cores 100% active, USB/PCIe without suspend'

    if ($null -eq $script:Base.Hibernate) {
        $hb = Get-RegVal 'HKLM' 'SYSTEM\CurrentControlSet\Control\Power' 'HibernateEnabled'
        if ($null -eq $hb) { $hb = 0 }
        $script:Base.Hibernate = [int]$hb
    }
    powercfg /h off 2>&1 | Out-Null
    Set-Reg 'HKLM' 'SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 'DWord' 0
    Set-Reg 'HKLM' 'SYSTEM\CurrentControlSet\Control\Power' 'CsEnabled' 'DWord' 0
    Set-Reg 'HKLM' 'SYSTEM\CurrentControlSet\Control\Power' 'EnergyEstimationEnabled' 'DWord' 0
    Set-Reg 'HKLM' 'SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'CoalescingTimerInterval' 'DWord' 0
    Log '  Hibernation and fast startup disabled'
}

function Mod-CpuJogos {
    $g = 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'
    Set-Reg 'HKLM' $g 'GPU Priority' 'DWord' 8
    Set-Reg 'HKLM' $g 'Priority' 'DWord' 6
    Set-Reg 'HKLM' $g 'Scheduling Category' 'String' 'High'
    Set-Reg 'HKLM' $g 'SFIO Priority' 'String' 'High'
    Set-Reg 'HKLM' $g 'Latency Sensitive' 'String' 'True'
    Set-Reg 'HKLM' $g 'Background Only' 'String' 'False'
    Set-Reg 'HKLM' 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'SystemResponsiveness' 'DWord' 0
    Set-Reg 'HKLM' 'SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation' 'DWord' 0x1A
    Set-Reg 'HKLM' 'SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' 'PowerThrottlingOff' 'DWord' 1
    Set-Reg 'HKLM' 'SYSTEM\CurrentControlSet\Control\Session Manager\Kernel' 'GlobalTimerResolutionRequests' 'DWord' 1
    Set-Reg 'HKLM' 'SYSTEM\CurrentControlSet\Control\Session Manager\Kernel' 'SerializeTimerExpiration' 'DWord' 1
    Log '  Game MMCSS, priority 0x1A, power throttling off'
}

function Mod-Boot {
    foreach ($n in @('bootux', 'tscsyncpolicy', 'uselegacyapicmode', 'x2apicpolicy', 'disabledynamictick', 'useplatformclock')) { Backup-Bcd $n }
    Run-Bcd @('/set', 'bootux', 'disabled')
    Run-Bcd @('/set', 'tscsyncpolicy', 'enhanced')
    Run-Bcd @('/set', 'uselegacyapicmode', 'No')
    Run-Bcd @('/set', 'x2apicpolicy', 'Enable')
    Run-Bcd @('/set', 'disabledynamictick', 'yes')
    Run-Bcd @('/deletevalue', 'useplatformclock')
    Log '  bcdedit: x2APIC, TSC enhanced, dynamic tick off, HPET removed'
}

function Mod-GpuTela {
    Set-Reg 'HKLM' 'SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 'DWord' 2
    Set-Reg 'HKLM' 'SYSTEM\CurrentControlSet\Services\GpuEnergyDrv' 'Start' 'DWord' 4
    Set-Reg 'HKCU' 'Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 'DWord' 0
    Set-Reg 'HKCU' 'System\GameConfigStore' 'GameDVR_Enabled' 'DWord' 0
    Set-Reg 'HKLM' 'SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' 'DWord' 0
    Set-Reg 'HKCU' 'Software\Microsoft\GameBar' 'AutoGameModeEnabled' 'DWord' 1
    Set-Reg 'HKCU' 'Software\Microsoft\GameBar' 'AllowAutoGameMode' 'DWord' 1
    Set-Reg 'HKCU' 'Software\Microsoft\GameBar' 'UseNexusForGameBarEnabled' 'DWord' 0

    $dxp = 'Software\Microsoft\DirectX\UserGpuPreferences'
    $cur = Get-RegVal 'HKCU' $dxp 'DirectXUserGlobalSettings'
    if ($cur -match 'SwapEffectUpgradeEnable=\d') { $new = $cur -replace 'SwapEffectUpgradeEnable=\d', 'SwapEffectUpgradeEnable=1' }
    else { $new = "$cur" + 'SwapEffectUpgradeEnable=1;' }
    Set-Reg 'HKCU' $dxp 'DirectXUserGlobalSettings' 'String' $new

    $old = Set-Refresh 0
    if ($null -ne $old -and $null -eq $script:Base.Display) { $script:Base.Display = [PSCustomObject]@{ Hz = $old } }
    Log '  HAGS on, Game Mode on, Game Bar off, optimized windowed mode'
}

function Mod-Mouse {
    $m = 'Control Panel\Mouse'
    Set-Reg 'HKCU' $m 'MouseSpeed' 'String' '0'
    Set-Reg 'HKCU' $m 'MouseThreshold1' 'String' '0'
    Set-Reg 'HKCU' $m 'MouseThreshold2' 'String' '0'
    Set-Reg 'HKCU' $m 'MouseSensitivity' 'String' '10'
    Set-Reg 'HKCU' $m 'MouseHoverTime' 'String' '10'
    Set-Reg 'HKCU' 'Control Panel\Desktop' 'MenuShowDelay' 'String' '0'
    # Input queues smaller than the default (100) do not help and may drop events: back to default
    $a = Remove-RegValue 'HKLM' 'SYSTEM\CurrentControlSet\Services\mouclass\Parameters' 'MouseDataQueueSize'
    $b = Remove-RegValue 'HKLM' 'SYSTEM\CurrentControlSet\Services\kbdclass\Parameters' 'KeyboardDataQueueSize'
    if ($a -or $b) { Log '  Mouse/keyboard queue restored to the Windows default' }
    Apply-MouseNow
    Log '  Mouse acceleration off (1:1), sensitivity 6/11'
}

function Mod-Rede {
    $classPath = 'SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}'
    $guids = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' } | ForEach-Object { $_.InterfaceGuid })
    $n = 0
    foreach ($sub in (Get-ChildItem -LiteralPath "HKLM:\$classPath" -ErrorAction SilentlyContinue)) {
        $id = (Get-ItemProperty -LiteralPath $sub.PSPath -ErrorAction SilentlyContinue).NetCfgInstanceId
        if ($id -and ($guids -contains $id)) {
            Set-Reg 'HKLM' "$classPath\$($sub.PSChildName)" 'PnPCapabilities' 'DWord' 24
            $n++
        }
    }
    Set-Reg 'HKLM' 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex' 'DWord' -1
    Log "  Power saving disabled on $n active network adapter(s) (takes effect after reboot)"
}

function Mod-Privacidade {
    $dc = 'SOFTWARE\Policies\Microsoft\Windows\DataCollection'
    Set-Reg 'HKLM' $dc 'AllowTelemetry' 'DWord' 0
    Set-Reg 'HKLM' $dc 'MaxTelemetryAllowed' 'DWord' 0
    Set-Reg 'HKLM' 'SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' 'AllowTelemetry' 'DWord' 0
    Set-Reg 'HKCU' 'SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 'DWord' 0
    Set-Reg 'HKLM' 'SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo' 'DisabledByGroupPolicy' 'DWord' 1
    Set-Reg 'HKLM' 'SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'AllowCortana' 'DWord' 0
    Set-Reg 'HKLM' 'SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'ConnectedSearchUseWeb' 'DWord' 0
    $sy = 'SOFTWARE\Policies\Microsoft\Windows\System'
    Set-Reg 'HKLM' $sy 'EnableActivityFeed' 'DWord' 0
    Set-Reg 'HKLM' $sy 'PublishUserActivities' 'DWord' 0
    Set-Reg 'HKLM' $sy 'UploadUserActivities' 'DWord' 0
    $cc = 'SOFTWARE\Policies\Microsoft\Windows\CloudContent'
    Set-Reg 'HKCU' $cc 'DisableTailoredExperiencesWithDiagnosticData' 'DWord' 1
    Set-Reg 'HKLM' $cc 'DisableWindowsConsumerFeatures' 'DWord' 1
    Set-Reg 'HKLM' $cc 'DisableSoftLanding' 'DWord' 1
    Set-Reg 'HKLM' $cc 'DisableThirdPartySuggestions' 'DWord' 1
    Set-Reg 'HKCU' 'SOFTWARE\Microsoft\Siuf\Rules' 'NumberOfSIUFInPeriod' 'DWord' 0
    Set-Reg 'HKCU' 'SOFTWARE\Microsoft\Siuf\Rules' 'PeriodInNanoSeconds' 'DWord' 0
    Set-Reg 'HKCU' 'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_TrackProgs' 'DWord' 0
    Set-Reg 'HKLM' 'SOFTWARE\Microsoft\WcmSvc\wifinetworkmanager\config' 'AutoConnectAllowedOEM' 'DWord' 0
    Set-Reg 'HKLM' 'SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 'DWord' 1
    Set-Reg 'HKCU' 'Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 'DWord' 1
    Set-Reg 'HKLM' 'SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' 'Value' 'String' 'Deny'
    Set-Reg 'HKCU' 'Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 'DWord' 1
    Disable-Svc 'DiagTrack'
    Disable-Svc 'dmwappushservice'
    Log '  Telemetry, ads, Cortana, Copilot, location and data collection services disabled'
}

function Mod-Notificacoes {
    Set-Reg 'HKCU' 'Software\Microsoft\Windows\CurrentVersion\PushNotifications' 'ToastEnabled' 'DWord' 0
    $ns = 'Software\Microsoft\Windows\CurrentVersion\Notifications\Settings'
    Set-Reg 'HKCU' $ns 'NOC_GLOBAL_SETTING_ALLOW_TOASTS_ABOVE_LOCK' 'DWord' 0
    Set-Reg 'HKCU' $ns 'NOC_GLOBAL_SETTING_ALLOW_CRITICAL_TOASTS_ABOVE_LOCK' 'DWord' 0
    Set-Reg 'HKCU' 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowSyncProviderNotifications' 'DWord' 0
    $cd = 'Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    foreach ($n in @('SubscribedContent-310093Enabled', 'SubscribedContent-338387Enabled', 'SubscribedContent-338388Enabled', 'SubscribedContent-338389Enabled', 'SubscribedContent-338393Enabled', 'SubscribedContent-353694Enabled', 'SubscribedContent-353696Enabled', 'SystemPaneSuggestionsEnabled', 'SoftLandingEnabled', 'RotatingLockScreenEnabled', 'ContentDeliveryAllowed', 'OemPreInstalledAppsEnabled', 'PreInstalledAppsEnabled', 'SilentInstalledAppsEnabled')) {
        Set-Reg 'HKCU' $cd $n 'DWord' 0
    }
    Set-Reg 'HKCU' 'Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 'DWord' 0
    Log '  Windows notifications, tips, suggestions and ads disabled'
}

function Mod-Sistema {
    $ramKB = [int64]((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1KB)
    $thr = [int][Math]::Min($ramKB + 1048576, 2147483647)
    Set-Reg 'HKLM' 'SYSTEM\CurrentControlSet\Control' 'SvcHostSplitThresholdInKB' 'DWord' $thr
    Set-Reg 'HKCU' 'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Serialize' 'StartupDelayInMSec' 'DWord' 0
    Set-Reg 'HKLM' 'SOFTWARE\Policies\Microsoft\Edge' 'StartupBoostEnabled' 'DWord' 0
    Set-Reg 'HKLM' 'SOFTWARE\Policies\Microsoft\Edge' 'BackgroundModeEnabled' 'DWord' 0
    Set-Reg 'HKLM' 'SYSTEM\CurrentControlSet\Control\CrashControl' 'DisplayParameters' 'DWord' 1
    Log '  svchost grouped (fewer processes), no startup delay, Edge without boost'
}

function Mod-Visual {
    $p = 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    Set-Reg 'HKCU' $p 'AppsUseLightTheme' 'DWord' 0
    Set-Reg 'HKCU' $p 'SystemUsesLightTheme' 'DWord' 0
    $a = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    Set-Reg 'HKCU' $a 'TaskbarAl' 'DWord' 0
    Set-Reg 'HKCU' $a 'HideFileExt' 'DWord' 0
    Set-Reg 'HKCU' $a 'Hidden' 'DWord' 1
    Set-Reg 'HKCU' "$a\TaskbarDeveloperSettings" 'TaskbarEndTask' 'DWord' 1
    Log '  Dark mode, left taskbar, extensions and hidden files visible (log off to see everything)'
}

function Mod-ExtrasReg {
    $pw = 'SYSTEM\CurrentControlSet\Control\Power'
    Set-Reg 'HKLM' $pw 'EnergySaverPolicy' 'DWord' 1
    Set-Reg 'HKLM' $pw 'EnergySaverStatus' 'DWord' 0
    Set-Reg 'HKLM' $pw 'DynamicThrottlePolicy' 'DWord' 0
    Set-Reg 'HKLM' $pw 'EcoMode' 'DWord' 0
    Set-Reg 'HKLM' $pw 'VideoIdleTimeout' 'DWord' 0
    Set-Reg 'HKLM' "$pw\ModernSleep" 'AdaptiveRefreshRate' 'DWord' 0
    $gd = 'SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
    Set-Reg 'HKLM' $gd 'PowerSavingModeEnabled' 'DWord' 0
    Set-Reg 'HKLM' $gd 'PanelSelfRefresh' 'DWord' 0
    Set-Reg 'HKLM' $gd 'ForceOffScreenTimeout' 'DWord' 0
    Set-Reg 'HKLM' "$gd\Scheduler" 'EnableFrameBufferCompression' 'DWord' 0
    Set-Reg 'HKLM' "$gd\Scheduler" 'EnableGpuBoost' 'DWord' 1
    Set-Reg 'HKLM' 'SYSTEM\CurrentControlSet\Services\Tcpip\Parameters' 'DisablePowerManagement' 'DWord' 1
    Log '  Extras from your .reg files: CPU/GPU/screen/TCP-IP power saving disabled'
}

function Mod-DpcIsr {
    $pw = 'SYSTEM\CurrentControlSet\Control\Power'
    foreach ($n in @('ExitLatency', 'ExitLatencyCheckEnabled', 'Latency', 'LatencyToleranceDefault', 'LatencyToleranceFSVP', 'LatencyTolerancePerfOverride', 'LatencyToleranceScreenOffIR', 'LatencyToleranceVSyncEnabled', 'RtlCapabilityCheckLatency')) {
        Set-Reg 'HKLM' $pw $n 'DWord' 1
    }
    $gp = 'SYSTEM\CurrentControlSet\Control\GraphicsDrivers\Power'
    foreach ($n in @('DefaultD3TransitionLatencyActivelyUsed', 'DefaultD3TransitionLatencyIdleLongTime', 'DefaultD3TransitionLatencyIdleMonitorOff', 'DefaultD3TransitionLatencyIdleNoContext', 'DefaultD3TransitionLatencyIdleShortTime', 'DefaultD3TransitionLatencyIdleVeryLongTime',
            'DefaultLatencyToleranceIdle0', 'DefaultLatencyToleranceIdle0MonitorOff', 'DefaultLatencyToleranceIdle1', 'DefaultLatencyToleranceIdle1MonitorOff', 'DefaultLatencyToleranceMemory', 'DefaultLatencyToleranceNoContext', 'DefaultLatencyToleranceNoContextMonitorOff', 'DefaultLatencyToleranceOther', 'DefaultLatencyToleranceTimerPeriod',
            'DefaultMemoryRefreshLatencyToleranceActivelyUsed', 'DefaultMemoryRefreshLatencyToleranceMonitorOff', 'DefaultMemoryRefreshLatencyToleranceNoContext',
            'Latency', 'MaxIAverageGraphicsLatencyInOneBucket', 'MiracastPerfTrackGraphicsLatency', 'MonitorLatencyTolerance', 'MonitorRefreshLatencyTolerance', 'TransitionLatency')) {
        Set-Reg 'HKLM' $gp $n 'DWord' 1
    }
    Log '  DPC/ISR latency tolerances at minimum (34 values)'
}

function Mod-GuiaWindows {
    # Dynamic Lighting (Windows RGB)
    Set-Reg 'HKCU' 'Software\Microsoft\Lighting' 'AmbientLightingEnabled' 'DWord' 0
    Set-Reg 'HKCU' 'Software\Microsoft\Lighting' 'ControlledByForegroundApp' 'DWord' 0
    # Share across devices
    $cdp = 'Software\Microsoft\Windows\CurrentVersion\CDP'
    Set-Reg 'HKCU' $cdp 'CdpSessionUserAuthzPolicy' 'DWord' 0
    Set-Reg 'HKCU' $cdp 'NearShareChannelUserAuthzPolicy' 'DWord' 0
    Set-Reg 'HKCU' $cdp 'RomeSdkChannelUserAuthzPolicy' 'DWord' 0
    # Delivery Optimization: no downloads from other PCs
    Set-Reg 'HKLM' 'SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 'DWord' 0
    # Transparency and animations
    Set-Reg 'HKCU' 'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 'DWord' 0
    if ($null -eq $script:Base.Anim) {
        [int]$v = 1
        if ([TBNative]::SpiGetInt(0x1042, 0, [ref]$v, 0)) { $script:Base.Anim = $v }
    }
    [void][TBNative]::SystemParametersInfoPtr(0x1043, 0, [IntPtr]0, 3)
    Log '  Dynamic Lighting, share across devices, Delivery Optimization, transparency and animations disabled'
}

function Mod-ExpAjustes {
    Set-Reg 'HKLM' 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' 'Affinity' 'DWord' 0
    Set-Reg 'HKLM' 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'SystemResponsiveness' 'DWord' 10
    Set-Reg 'HKCU' 'Software\Policies\Microsoft\MicrosoftEdge\TabPreloader' 'AllowTabPreloading' 'DWord' 0
    Set-Reg 'HKLM' 'SOFTWARE\Policies\Microsoft\MicrosoftEdge\TabPreloader' 'AllowTabPreloading' 'DWord' 0
    Log '  SystemResponsiveness 10 (the guide says 10; the CPU module uses 0), Affinity and legacy Edge keys'
}

function Mod-RiscoHvci {
    Set-Reg 'HKLM' 'SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled' 'DWord' 0
    Log '  Core Isolation (HVCI) disabled - takes effect after reboot'
}

function Mod-RiscoDefender {
    try {
        $before = (Get-MpPreference -ErrorAction Stop).DisableRealtimeMonitoring
        if ($null -eq $script:Base.Defender) { $script:Base.Defender = [bool]$before }
        Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction Stop
        if ((Get-MpPreference).DisableRealtimeMonitoring) { Log '  Defender real-time protection disabled' }
        else { Log '  ! Defender is still active: turn off Tamper Protection in Windows Security first' }
    } catch { Log "  ! Defender: $($_.Exception.Message)" }
}

$Modules = @(
    @{ Fn = 'Mod-Energia';       Label = 'Power: Maximum plan';          Desc = 'Maximum Performance plan, cores always active, USB/PCIe without power saving and no hibernation.'; Cats = @('Performance'); Star = $true;  On = $true;  Risk = $false },
    @{ Fn = 'Mod-CpuJogos';      Label = 'CPU and game priority';      Desc = 'Game priority (MMCSS), Win32PrioritySeparation 0x1A and power throttling disabled.'; Cats = @('Performance', 'Gaming'); Star = $true; On = $true; Risk = $false },
    @{ Fn = 'Mod-Boot';          Label = 'Boot and kernel (timer)';          Desc = 'x2APIC, TSC enhanced, dynamic tick disabled and forced HPET removed.'; Cats = @('Performance'); Star = $true; On = $true; Risk = $false },
    @{ Fn = 'Mod-GpuTela';       Label = 'GPU and display';                     Desc = 'HAGS on, Game Mode, Game Bar off and maximum monitor refresh rate.'; Cats = @('Gaming', 'Performance'); Star = $true; On = $true; Risk = $false },
    @{ Fn = 'Mod-Mouse';         Label = 'Mouse and menus';                  Desc = 'No mouse acceleration (1:1), instant menus and tooltips, input queue at default.'; Cats = @('Gaming'); Star = $true; On = $true; Risk = $false },
    @{ Fn = 'Mod-Rede';          Label = 'Network';                           Desc = 'Active network adapter without power saving and without network throttling.'; Cats = @('Network'); Star = $false; On = $true; Risk = $false },
    @{ Fn = 'Mod-Privacidade';   Label = 'Privacy';                    Desc = 'Telemetry, ads, Cortana, Copilot, location and data collection services disabled.'; Cats = @('Privacy'); Star = $true; On = $true; Risk = $false },
    @{ Fn = 'Mod-Notificacoes';  Label = 'Notifications and suggestions';       Desc = 'Turns off Windows alerts, tips, suggestions and ads.'; Cats = @('Privacy'); Star = $false; On = $true; Risk = $false },
    @{ Fn = 'Mod-Sistema';       Label = 'System';                        Desc = 'Grouped svchost, no app startup delay and Edge without background boost.'; Cats = @('Performance'); Star = $false; On = $true; Risk = $false },
    @{ Fn = 'Mod-Visual';        Label = 'Windows appearance';              Desc = 'Dark mode, left-aligned taskbar, file extensions and hidden files visible.'; Cats = @('Appearance'); Star = $false; On = $true; Risk = $false },
    @{ Fn = 'Mod-GuiaWindows';   Label = 'Guide settings (Windows)'; Desc = 'Dynamic Lighting off, share across devices off, Delivery Optimization off, no transparency or animations.'; Cats = @('Performance', 'Privacy'); Star = $false; On = $false; Risk = $false },
    @{ Fn = 'Mod-ExtrasReg';     Label = 'Extras from your .reg files';           Desc = 'CPU/GPU/screen/TCP-IP power: EcoMode, PSR, GPU Boost, FBC, DynamicThrottle... (effect varies by PC).'; Cats = @('Performance', 'Network'); Star = $false; On = $false; Risk = $false },
    @{ Fn = 'Mod-DpcIsr';        Label = 'DPC/ISR latency at minimum';     Desc = '34 latency tolerance values = 1 (from your "6 dont tolerate high dpcisr.reg"). Effect depends on the driver.'; Cats = @('Performance', 'Gaming'); Star = $false; On = $false; Risk = $false },
    @{ Fn = 'Mod-ExpAjustes';    Label = 'Guide fine-tuning';          Desc = 'SystemResponsiveness 10 (as in the video), game task Affinity and legacy Edge keys.'; Cats = @('Performance'); Star = $false; On = $false; Risk = $false },
    @{ Fn = 'Mod-Cs2Prio';       Label = 'CS2: High priority';           Desc = 'cs2.exe always launches with High priority in Windows. If the anticheat complains, revert.'; Cats = @('Gaming'); Star = $true; On = $true; Risk = $false },
    @{ Fn = 'Mod-Cs2Gpu';        Label = 'CS2: high-performance GPU';    Desc = 'Forces the game to use the dedicated graphics card. Useful on laptops with two GPUs.'; Cats = @('Gaming'); Star = $true; On = $true; Risk = $false },
    @{ Fn = 'Mod-Cs2Fso';        Label = 'CS2: fullscreen optimizations off';  Desc = 'Turns off fullscreen optimizations for cs2.exe only. The effect varies from PC to PC.'; Cats = @('Gaming'); Star = $false; On = $false; Risk = $false },
    @{ Fn = 'Mod-RiscoHvci';     Label = 'Disable Core Isolation';  Desc = 'Turns off Memory Integrity (+2 to 5% FPS, less malware protection).'; Cats = @('Risk', 'Performance'); Star = $false; On = $false; Risk = $true },
    @{ Fn = 'Mod-RiscoDefender'; Label = 'Disable Defender (real-time)'; Desc = 'Turns off real-time protection. Does not work with Tamper Protection on.'; Cats = @('Risk'); Star = $false; On = $false; Risk = $true }
)
$Modules = @($Modules | ForEach-Object { [PSCustomObject]$_ })
$ExpFns = @('Mod-GuiaWindows', 'Mod-ExtrasReg', 'Mod-DpcIsr', 'Mod-ExpAjustes')
foreach ($m in $Modules) { $m | Add-Member -NotePropertyName Exp -NotePropertyValue ($ExpFns -contains $m.Fn) -Force }
$Cs2Fns = @('Mod-Cs2Prio', 'Mod-Cs2Gpu', 'Mod-Cs2Fso')
foreach ($m in $Modules) { $m | Add-Member -NotePropertyName Cs2 -NotePropertyValue ($Cs2Fns -contains $m.Fn) -Force }
$MainModules = @($Modules | Where-Object { (-not $_.Exp) -and (-not $_.Cs2) })
$Cs2Modules = @($Modules | Where-Object { $_.Cs2 })
$ExpModules  = @($Modules | Where-Object { $_.Exp })

# =========================================================
#  SYSTEM INFORMATION (for the Dashboard)
# =========================================================
function Get-VramBytes($name) {
    try {
        foreach ($k in (Get-ChildItem -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}' -ErrorAction SilentlyContinue)) {
            $p = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue
            if ($p.DriverDesc -eq $name) {
                $v = $p.'HardwareInformation.qwMemorySize'
                if ($null -ne $v) {
                    if ($v -is [byte[]]) { if ($v.Length -ge 8) { return [BitConverter]::ToInt64($v, 0) } }
                    else { return [int64]$v }
                }
            }
        }
    } catch {}
    return -1
}

function Get-SysInfo {
    $i = @{ Cpu = '-'; Cores = ''; Gpu = '-'; Vram = ''; Ram = '-'; RamType = ''; Storage = '-'; StorageType = ''; Os = '-'; OsVer = '-'; Disk = '-' }
    try {
        $c = Get-CimInstance Win32_Processor | Select-Object -First 1
        $i.Cpu = (($c.Name -replace '\s+', ' ').Trim())
        $i.Cores = "$($c.NumberOfCores) CORES"
    } catch {}
    try {
        $gs = @(Get-CimInstance Win32_VideoController | Where-Object { $_.Name -notmatch 'Basic|Remote|Virtual|Parsec' })
        if ($gs.Count -eq 0) { $gs = @(Get-CimInstance Win32_VideoController) }
        $best = $gs | Select-Object -First 1
        $bestV = -1
        foreach ($g in $gs) { $v = Get-VramBytes $g.Name; if ($v -gt $bestV) { $bestV = $v; $best = $g } }
        $i.Gpu = $best.Name
        if ($bestV -le 0 -and $best.AdapterRAM) { $bestV = [int64]$best.AdapterRAM }
        if ($bestV -gt 0) { $i.Vram = "{0} GB" -f [math]::Round($bestV / 1GB) }
    } catch {}
    try {
        $cs = Get-CimInstance Win32_ComputerSystem
        $i.Ram = "{0:N1} GB" -f ($cs.TotalPhysicalMemory / 1GB)
        $f = @(Get-CimInstance Win32_PhysicalMemory) | Select-Object -First 1
        $t = 'RAM'
        switch ([int]$f.SMBIOSMemoryType) { 24 { $t = 'DDR3' } 26 { $t = 'DDR4' } 34 { $t = 'DDR5' } }
        if ($f.ConfiguredClockSpeed) { $i.RamType = "$t $($f.ConfiguredClockSpeed) MT/s" } else { $i.RamType = $t }
    } catch {}
    try {
        $pd = @(Get-PhysicalDisk -ErrorAction Stop)
        $sz = ($pd | Measure-Object Size -Sum).Sum
        $i.Storage = "{0:N0} GB" -f ($sz / 1GB)
        $sysName = $null
        try { $sysName = (Get-Partition -DriveLetter ($env:SystemDrive.TrimEnd(':')) -ErrorAction Stop | Get-Disk -ErrorAction Stop).FriendlyName } catch {}
        $d = $pd | Where-Object { $_.FriendlyName -eq $sysName } | Select-Object -First 1
        if (-not $d) { $d = $pd | Select-Object -First 1 }
        $i.Disk = $d.FriendlyName
        if ($d.BusType -eq 'NVMe') { $i.StorageType = 'NVMe' }
        elseif ($d.MediaType -eq 'SSD') { $i.StorageType = 'SSD' }
        elseif ($d.MediaType -eq 'HDD') { $i.StorageType = 'HDD' }
        else { $i.StorageType = 'DISK' }
    } catch {}
    try {
        $o = Get-CimInstance Win32_OperatingSystem
        $i.Os = ($o.Caption -replace 'Microsoft ', '')
        $dv = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').DisplayVersion
        $i.OsVer = "$dv (build $($o.BuildNumber))"
    } catch {}
    return $i
}

# =========================================================
#  ACTIONS
# =========================================================
$script:AppliedCount = 0

function Invoke-RestorePoint {
    Log '>> Creating restore point...'
    $k = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    $old = $null
    try { $old = (Get-ItemProperty -Path $k -Name SystemRestorePointCreationFrequency -ErrorAction Stop).SystemRestorePointCreationFrequency } catch {}
    try {
        New-ItemProperty -Path $k -Name SystemRestorePointCreationFrequency -PropertyType DWord -Value 0 -Force -ErrorAction SilentlyContinue | Out-Null
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description 'TutuBoost' -RestorePointType 'MODIFY_SETTINGS' -WarningAction SilentlyContinue -ErrorAction Stop
        Log '   restore point created'
    } catch {
        Log "   (could not create the restore point: $($_.Exception.Message))"
    } finally {
        if ($null -eq $old) { Remove-ItemProperty -Path $k -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue }
        else { New-ItemProperty -Path $k -Name SystemRestorePointCreationFrequency -PropertyType DWord -Value $old -Force -ErrorAction SilentlyContinue | Out-Null }
    }
}

function Invoke-Optimize($list, $NoRestart = $false) {
    Set-Busy $true
    try {
        Load-Base
        Invoke-RestorePoint
        $done = 0
        foreach ($m in $list) {
            if (-not $m.Box.Checked) { continue }
            Log ">> $($m.Label)"
            try { & $m.Fn; $done++ } catch { Log "  ! error: $($_.Exception.Message)" }
            Save-Base
        }
        Save-Base
        $script:AppliedCount += $done
        Update-Dash
        Log ''
        Log "[ OK ] $done module(s) applied. RESTART the PC for full effect."
    } finally { Set-Busy $false }
    if ((-not $NoRestart) -and (Ask 'TutuBoost finished. Restart the PC now to apply everything?')) { shutdown /r /t 5 }
}

function Invoke-Revert {
    if (-not (Test-Path $BaseFile)) { Log 'Nothing to revert: TutuBoost has not applied anything yet.'; return }
    if (-not (Ask 'Revert EVERYTHING TutuBoost changed and return to the original state?')) { return }
    Set-Busy $true
    try {
        Load-Base
        Log '>> Reverting registry...'
        foreach ($r in @($script:Base.Reg)) { Restore-Reg $r }
        Log '>> Reverting bcdedit...'
        foreach ($b in @($script:Base.Bcd)) {
            if ($null -eq $b.Old) { Run-Bcd @('/deletevalue', $b.Name) } else { Run-Bcd @('/set', $b.Name, "$($b.Old)") }
        }
        Log '>> Reverting services...'
        foreach ($s in @($script:Base.Svc)) {
            Set-Service -Name $s.Name -StartupType $s.Start -ErrorAction SilentlyContinue
            if ($s.Status -eq 'Running') { Start-Service -Name $s.Name -ErrorAction SilentlyContinue }
        }
        Log '>> Reverting power settings...'
        foreach ($p in @($script:Base.Power)) { powercfg /setacvalueindex $p.Plan $p.Sub $p.Set ([uint32]$p.Old) 2>&1 | Out-Null }
        if ($script:Base.Plan) { powercfg /setactive $script:Base.Plan 2>&1 | Out-Null }
        if ($script:Base.Hibernate -eq 1) { powercfg /h on 2>&1 | Out-Null }
        if ($script:Base.Display -and $script:Base.Display.Hz) { [void](Set-Refresh ([int]$script:Base.Display.Hz)) }
        if ($null -ne $script:Base.Defender) {
            try { Set-MpPreference -DisableRealtimeMonitoring ([bool]$script:Base.Defender) -ErrorAction Stop; Log '   Defender restored' } catch { Log "   ! Defender: $($_.Exception.Message)" }
        }
        if ($null -ne $script:Base.Anim) { [void][TBNative]::SystemParametersInfoPtr(0x1043, 0, [IntPtr][int]$script:Base.Anim, 3) }
        Apply-MouseNow
        $arch = Join-Path $BackupDir ("baseline_revertido_{0}.json" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
        Move-Item -Path $BaseFile -Destination $arch -Force
        $script:AppliedCount = 0
        Update-Dash
        Log ''
        Log '[ OK ] Everything reverted. Restart the PC.'
    } finally { Set-Busy $false }
}

function Dir-Size($p) {
    try { return [int64](Get-ChildItem -LiteralPath $p -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum } catch { return 0 }
}

function Invoke-Clean {
    $c = $script:CleanToggles
    $any = $false
    foreach ($k in $c.Keys) { if ($c[$k].Checked) { $any = $true } }
    if (-not $any) { Log 'Cleanup: nothing selected.'; return }
    if ($c['Recycle'].Checked) {
        if (-not (Ask 'Emptying the Recycle Bin deletes everything PERMANENTLY. Continue?')) { return }
    }
    Set-Busy $true
    try {
        $total = [int64]0
        if ($c['Temp'].Checked) {
            foreach ($p in @($env:TEMP, "$env:WINDIR\Temp")) {
                if (Test-Path $p) { $total += (Dir-Size $p); Remove-Item "$p\*" -Recurse -Force -ErrorAction SilentlyContinue }
            }
            Log '   temp files cleaned'
        }
        if ($c['Prefetch'].Checked) {
            $p = "$env:WINDIR\Prefetch"
            if (Test-Path $p) { $total += (Dir-Size $p); Remove-Item "$p\*" -Force -ErrorAction SilentlyContinue }
            Log '   prefetch cleaned'
        }
        if ($c['Recycle'].Checked) {
            try { Clear-RecycleBin -Force -ErrorAction Stop; Log '   recycle bin emptied' } catch { Log "   ! recycle bin: $($_.Exception.Message)" }
        }
        if ($c['WUCache'].Checked) {
            Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
            $wu = "$env:WINDIR\SoftwareDistribution\Download"
            if (Test-Path $wu) { $total += (Dir-Size $wu); Remove-Item "$wu\*" -Recurse -Force -ErrorAction SilentlyContinue }
            Start-Service wuauserv -ErrorAction SilentlyContinue
            Log '   Windows Update cache cleaned'
        }
        if ($c['Thumbs'].Checked) {
            Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 800
            Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db" -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) { Start-Process explorer }
            Log '   thumbnails cleaned'
        }
        (Get-Date).ToString('dd/MM/yyyy HH:mm') | Set-Content -Path $CleanFile -Encoding UTF8
        $script:CleanHeader.Text = "Last cleanup: " + (Get-Content $CleanFile -Raw).Trim()
        Log ("[ OK ] Cleanup complete: ~{0} MB freed." -f [int]($total / 1MB))
    } finally { Set-Busy $false }
}

$script:AppDefs = @(
    @{ Id = 'xbox';   Name = 'Xbox (app, overlay, identity)'; Desc = 'Without this, Game Pass and Microsoft Store games stop working. Steam/CS2 are not affected.'; Pre = $true;  Pk = @('Microsoft.XboxApp', 'Microsoft.Xbox.TCUI', 'Microsoft.XboxGameOverlay', 'Microsoft.XboxGamingOverlay', 'Microsoft.XboxIdentityProvider', 'Microsoft.XboxSpeechToTextOverlay', 'Microsoft.GamingApp') },
    @{ Id = 'sol';    Name = 'Solitaire / Microsoft Games';     Desc = 'Microsoft Solitaire Collection.'; Pre = $true;  Pk = @('Microsoft.MicrosoftSolitaireCollection') },
    @{ Id = 'office'; Name = 'Office Hub';                      Desc = 'Office shortcuts (does not remove the real Office).'; Pre = $true;  Pk = @('Microsoft.MicrosoftOfficeHub') },
    @{ Id = 'tips';   Name = 'Tips / Feedback / Get Help';  Desc = 'Get Started, Feedback Hub and Get Help.'; Pre = $true;  Pk = @('Microsoft.Getstarted', 'Microsoft.WindowsFeedbackHub', 'Microsoft.GetHelp') },
    @{ Id = '3d';     Name = '3D Viewer / Mixed Reality';     Desc = '3D viewer and mixed reality portal.'; Pre = $true;  Pk = @('Microsoft.Microsoft3DViewer', 'Microsoft.MixedReality.Portal') },
    @{ Id = 'skype';  Name = 'Skype';                           Desc = 'Pre-installed Skype.'; Pre = $true;  Pk = @('Microsoft.SkypeApp') },
    @{ Id = 'clip';   Name = 'Clipchamp';                       Desc = 'Microsoft video editor.'; Pre = $true;  Pk = @('Clipchamp.Clipchamp') },
    @{ Id = 'bing';   Name = 'News / Weather / Finance';     Desc = 'Apps do Bing (News, Weather, Finance).'; Pre = $false; Pk = @('Microsoft.BingNews', 'Microsoft.BingWeather', 'Microsoft.BingFinance') },
    @{ Id = 'zune';   Name = 'Groove Music / Movies & TV';     Desc = 'Old Microsoft players.'; Pre = $false; Pk = @('Microsoft.ZuneMusic', 'Microsoft.ZuneVideo') },
    @{ Id = 'todo';   Name = 'Microsoft To Do';                 Desc = 'Task list.'; Pre = $false; Pk = @('Microsoft.Todos') },
    @{ Id = 'teams';  Name = 'Teams (consumer version)';       Desc = 'Does not affect work/school Teams.'; Pre = $false; Pk = @('MicrosoftTeams') },
    @{ Id = 'people'; Name = 'People (Contacts)';               Desc = 'Contacts app.'; Pre = $false; Pk = @('Microsoft.People') },
    @{ Id = 'phone';  Name = 'Your Phone / Phone Link';        Desc = 'Phone integration.'; Pre = $false; Pk = @('Microsoft.YourPhone') },
    @{ Id = 'outlook'; Name = 'New Outlook';                   Desc = 'New email client.'; Pre = $false; Pk = @('Microsoft.OutlookForWindows') }
)

function Invoke-Bloat {
    $sel = @($script:AppDefs | Where-Object { $script:AppToggles[$_.Id].Checked })
    if ($sel.Count -eq 0) { Log 'Apps: nothing selected.'; return }
    $names = ($sel | ForEach-Object { $_.Name }) -join "`n - "
    if (-not (Ask "Remove these apps?`n`n - $names")) { return }
    Set-Busy $true
    try {
        foreach ($a in $sel) {
            foreach ($p in $a.Pk) {
                Get-AppxPackage -Name "*$p*" -AllUsers -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
                Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.PackageName -like "*$p*" } | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Out-Null
            }
            Log "   removed: $($a.Name)"
        }
        Log '[ OK ] Apps removed. Some icons only disappear after logoff.'
    } finally { Set-Busy $false }
}

function Invoke-Repair {
    Start-Process cmd.exe -ArgumentList '/k DISM /Online /Cleanup-Image /RestoreHealth && sfc /scannow'
    Log 'DISM + SFC started in another window (needs internet, may take several minutes).'
}
function Invoke-NetReset {
    if (-not (Ask 'Reset the network stack (Winsock/IP/DNS)? The connection will drop and the PC must restart.')) { return }
    Start-Process cmd.exe -ArgumentList '/k netsh winsock reset && netsh int ip reset && ipconfig /flushdns && echo Done - RESTART the PC'
    Log 'Network reset started in another window. Restart the PC when it finishes.'
}
function Invoke-WUReset {
    if (-not (Ask 'Reset Windows Update? (renames SoftwareDistribution and catroot2)')) { return }
    $cmds = 'net stop wuauserv && net stop bits && net stop cryptsvc && ren %WINDIR%\SoftwareDistribution SoftwareDistribution.old && ren %WINDIR%\System32\catroot2 catroot2.old && net start wuauserv && net start bits && net start cryptsvc && echo Done'
    Start-Process cmd.exe -ArgumentList "/k $cmds"
    Log 'Windows Update reset started in another window.'
}

function Invoke-Diag {
    Set-Busy $true
    $script:Diag = New-Object System.Collections.Generic.List[string]
    $script:DiagBox.Clear()
    function D($s) { $script:Diag.Add([string]$s); $script:DiagBox.AppendText("$s`r`n"); [System.Windows.Forms.Application]::DoEvents() }
    try {
        D "===== TUTUBOOST DIAGNOSTICS - $(Get-Date -Format 'yyyy-MM-dd HH:mm') ====="
        $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
        D "Windows: $($cv.ProductName) $($cv.DisplayVersion) build $($cv.CurrentBuild).$($cv.UBR)"
        foreach ($c in Get-CimInstance Win32_Processor) { D "CPU: $($c.Name) | $($c.NumberOfCores) cores / $($c.NumberOfLogicalProcessors) threads" }
        foreach ($g in Get-CimInstance Win32_VideoController) { D "GPU: $($g.Name) | driver $($g.DriverVersion)" }
        $ram = @(Get-CimInstance Win32_PhysicalMemory)
        foreach ($m in $ram) { D "RAM: $([int]($m.Capacity/1GB)) GB | nominal $($m.Speed) MT/s | running at $($m.ConfiguredClockSpeed) MT/s" }
        if ($ram.Count -eq 1) { D '[!!] Only 1 stick = single channel. Dual channel performs much better in CS2.' }
        $first = $ram | Select-Object -First 1
        if ($first -and $first.ConfiguredClockSpeed -and $first.Speed -and $first.ConfiguredClockSpeed -lt ($first.Speed * 0.9)) { D '[!!] RAM below rated speed: enable XMP/DOCP/EXPO in the BIOS.' }
        D ("Power plan: " + ((powercfg /getactivescheme) -join ' '))

        $hpet = Get-BcdValue 'useplatformclock'
        if ($hpet -match 'Yes|true') { D '[!!] HPET forced ACTIVE. Apply the Boot and kernel module (removes it).' } else { D '[OK] HPET is not forced.' }
        $dt = Get-BcdValue 'disabledynamictick'
        D "[..] disabledynamictick = $(if ($dt) { $dt } else { 'default' })"

        $hv = Get-RegVal 'HKLM' 'SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled'
        if ($hv -eq 1) { D '[!!] Core Isolation (Memory Integrity) ON: costs 2 to 5% FPS.' } else { D '[OK] Core Isolation off.' }
        try {
            $dg = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard -ErrorAction Stop
            D "[..] VBS: $($dg.VirtualizationBasedSecurityStatus) (2 = active) | services: $($dg.SecurityServicesRunning -join ',')"
        } catch {}
        D "[..] HAGS (HwSchMode) = $(Get-RegVal 'HKLM' 'SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode') (2 = on)"
        $gm = Get-RegVal 'HKCU' 'Software\Microsoft\GameBar' 'AutoGameModeEnabled'
        if ($gm -eq 0) { D '[!!] Game Mode OFF.' } else { D '[OK] Game Mode OK.' }
        $ps = Get-RegVal 'HKLM' 'SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation'
        if ($null -ne $ps) { D ("[..] Win32PrioritySeparation = 0x{0:X}" -f [int]$ps) }
        $ma = Get-RegVal 'HKCU' 'Control Panel\Mouse' 'MouseSpeed'
        if ($ma -ne '0') { D '[!!] Mouse acceleration (Enhance pointer precision) ON.' } else { D '[OK] Mouse acceleration off.' }
        foreach ($q in @(@('mouclass', 'MouseDataQueueSize'), @('kbdclass', 'KeyboardDataQueueSize'))) {
            $v = Get-RegVal 'HKLM' "SYSTEM\CurrentControlSet\Services\$($q[0])\Parameters" $q[1]
            if ($null -ne $v -and $v -ne 100) { D "[!!] $($q[1]) = $v (default 100): apply the Mouse and menus module to restore the default." }
        }
        D '[..] Top 8 processes by RAM usage:'
        Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 8 | ForEach-Object { D ("     {0,-28} {1,6} MB" -f $_.Name, [int]($_.WorkingSet64 / 1MB)) }
        D '[REMINDER] BIOS: XMP/DOCP/EXPO enabled, Above 4G Decoding + Resizable BAR enabled'
        D '[REMINDER] GPU control panel (cannot be checked by script): NVIDIA = Low Latency + Maximum Performance; AMD = Boost, Enhanced Sync, Anti-Lag and Chill OFF.'
        $file = Join-Path ([Environment]::GetFolderPath('Desktop')) 'tutuboost_diagnostics.txt'
        $script:Diag | Set-Content -Path $file -Encoding UTF8
        D "Report saved to: $file"
    } finally { Set-Busy $false }
}

# =========================================================
#  INTERFACE (Matrix look)
# =========================================================
$script:Buttons = New-Object System.Collections.ArrayList
$script:Pages   = [ordered]@{}
$script:NavBtns = [ordered]@{}
$script:Filter  = 'All'
$script:Info    = Get-SysInfo

$Form = New-Object System.Windows.Forms.Form
$Form.Text = 'TutuBoost'
$Form.ClientSize = New-Object System.Drawing.Size(1100, 700)
$Form.StartPosition = 'CenterScreen'
$Form.FormBorderStyle = 'Sizable'
$Form.MaximizeBox = $true
$Form.BackColor = $cBg
$Form.ForeColor = $cGreen
$Form.Font = Mk-Font 9
try { $Form.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'Instance,NonPublic').SetValue($Form, $true, $null) } catch {}

function Set-Busy($b) {
    foreach ($x in $script:Buttons) { $x.Enabled = -not $b }
    if ($b) { $Form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor } else { $Form.Cursor = [System.Windows.Forms.Cursors]::Default }
    [System.Windows.Forms.Application]::DoEvents()
}

# ---- build helpers ----
function New-Card($parent, $x, $y, $w, $h, $fill, $border, $radius = 12) {
    $c = New-Object TbCard
    $c.Location = New-Object System.Drawing.Point($x, $y)
    $c.Size = New-Object System.Drawing.Size($w, $h)
    if ($parent -is [TbCard]) { $c.BackColor = $parent.Fill } else { $c.BackColor = $parent.BackColor }
    $c.Fill = $fill
    $c.Border = $border
    $c.Radius = $radius
    $parent.Controls.Add($c)
    return $c
}
function New-Label($parent, $text, $x, $y, $w, $h, $font, $color) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text
    $l.Location = New-Object System.Drawing.Point($x, $y)
    $l.Size = New-Object System.Drawing.Size($w, $h)
    $l.Font = $font
    $l.ForeColor = $color
    $l.AutoEllipsis = $true
    if (-not ($parent -is [TbCard])) { $l.BackColor = $parent.BackColor }
    $parent.Controls.Add($l)
    return $l
}
function New-Btn($parent, $text, $x, $y, $w, $h, $style = 0) {
    $b = New-Object TbButton
    $b.Text = $text
    $b.Style = $style
    $b.Location = New-Object System.Drawing.Point($x, $y)
    $b.Size = New-Object System.Drawing.Size($w, $h)
    if ($parent -is [TbCard]) { $b.BackColor = $parent.Fill } else { $b.BackColor = $parent.BackColor }
    $parent.Controls.Add($b)
    [void]$script:Buttons.Add($b)
    return $b
}
function New-Toggle($parent, $x, $y, $on) {
    $t = New-Object TbToggle
    $t.Location = New-Object System.Drawing.Point($x, $y)
    $t.Checked = $on
    if ($parent -is [TbCard]) { $t.BackColor = $parent.Fill } else { $t.BackColor = $parent.BackColor }
    $parent.Controls.Add($t)
    return $t
}
function New-Page($key) {
    $p = New-Object System.Windows.Forms.Panel
    $p.Location = New-Object System.Drawing.Point(0, 0)
    $p.Size = New-Object System.Drawing.Size(890, 548)
    $p.BackColor = $cBg
    $p.Visible = $false
    $Main.Controls.Add($p)
    $script:Pages[$key] = $p
    return $p
}
function New-Header($page, $glyph, $title, $sub) {
    $h = New-Card $page 20 16 850 70 $cCard $cBorder 12
    $ic = New-Card $h 16 13 44 44 $cIcon $cBorder 10
    $gl = New-Label $ic $glyph 0 0 44 44 $fGlyph $cGreen
    $gl.TextAlign = 'MiddleCenter'
    [void](New-Label $h $title 74 12 560 24 $fTitle $cGreen)
    $s = New-Label $h $sub 74 40 640 18 $fN $cMuted
    return $s
}
function New-Line($parent, $x, $y, $w) {
    $l = New-Object System.Windows.Forms.Panel
    $l.Location = New-Object System.Drawing.Point($x, $y)
    $l.Size = New-Object System.Drawing.Size($w, 1)
    $parent.Controls.Add($l)
    $l.BackColor = $cBorder
    return $l
}

# ---- Side menu ----
$Side = New-Object System.Windows.Forms.Panel
$Side.Location = New-Object System.Drawing.Point(0, 0)
$Side.Size = New-Object System.Drawing.Size(210, 700)
$Side.BackColor = $cSide
$Form.Controls.Add($Side)
$Side.Add_Resize({ $Side.Invalidate() })
$Side.Add_Paint({
    param($s, $e)
    $pen = New-Object System.Drawing.Pen($cBorder)
    $e.Graphics.DrawLine($pen, 209, 0, 209, $s.Height)
    $pen.Dispose()
})
$lg = New-Label $Side ([string][char]0xE945) 18 20 34 40 (Mk-Font 22 $false 'Segoe MDL2 Assets') $cGreen
$lg.TextAlign = 'MiddleCenter'
[void](New-Label $Side 'TUTU' 56 18 140 24 (Mk-Font 15 $true) $cGreen)
[void](New-Label $Side 'BOOST' 56 40 140 20 (Mk-Font 11 $true) $cDim)
[void](New-Line $Side 14 76 182)

$NavItems = @(
    @('dash',    'Dashboard',        [string][char]0xE80F),
    @('tweaks',  'Optimizations',   [string][char]0xE945),
    @('cs2',     'CS2',           [string][char]0xE7FC),
    @('exp',     'Experimental',  [string][char]0xE7BA),
    @('clean',   'Cleanup',       [string][char]0xE74D),
    @('restore', 'Restore',   [string][char]0xE81C),
    @('apps',    'Apps',          [string][char]0xE71D),
    @('setup',   'Post-format', [string][char]0xE896),
    @('diag',    'Diagnostics',   [string][char]0xE721),
    @('config',  'Settings', [string][char]0xE713)
)
$ny = 92
foreach ($it in $NavItems) {
    $n = New-Object TbNav
    $n.Text = $it[1]
    $n.Glyph = $it[2]
    $n.Tag = $it[0]
    $n.Location = New-Object System.Drawing.Point(8, $ny)
    $n.Size = New-Object System.Drawing.Size(194, 42)
    $n.BackColor = $cSide
    $Side.Controls.Add($n)
    $script:NavBtns[$it[0]] = $n
    $n.Add_Click({ param($s, $e) Show-Page $s.Tag })
    $ny += 46
}
[void](New-Label $Side 'V.1  //  wake up, tutu...' 18 672 180 16 $fSm $cMuted)

# ---- Main area ----
$Main = New-Object System.Windows.Forms.Panel
$Main.Location = New-Object System.Drawing.Point(210, 0)
$Main.Size = New-Object System.Drawing.Size(890, 700)
$Main.BackColor = $cBg
$Form.Controls.Add($Main)

function Show-Page($key) {
    foreach ($k in $script:Pages.Keys) { $script:Pages[$k].Visible = ($k -eq $key) }
    foreach ($k in $script:NavBtns.Keys) { $script:NavBtns[$k].Selected = ($k -eq $key) }
}

# ---- Log (footer) ----
$lgl = New-Label $Main '> LOG' 22 552 200 14 $fSm $cMuted
$logCard = New-Card $Main 20 568 850 122 $cCard $cBorder 10
$script:LogBox = New-Object System.Windows.Forms.TextBox
$script:LogBox.Multiline = $true
$script:LogBox.ReadOnly = $true
$script:LogBox.ScrollBars = 'Vertical'
$script:LogBox.BorderStyle = 'None'
$script:LogBox.Font = Mk-Font 9
$script:LogBox.ForeColor = $cGreen
$script:LogBox.Location = New-Object System.Drawing.Point(10, 8)
$script:LogBox.Size = New-Object System.Drawing.Size(830, 106)
$logCard.Controls.Add($script:LogBox)

# =========================================================
#  PAGE: DASHBOARD
# =========================================================
$pDash = New-Page 'dash'

# Hero com chuva Matrix
$RainW = 2600; $HeroW = 850; $RainH = 104; $FS = 14
$Hero = New-Object System.Windows.Forms.Panel
$Hero.Location = New-Object System.Drawing.Point(20, 16)
$Hero.Size = New-Object System.Drawing.Size($HeroW, $RainH)
$Hero.BackColor = $cBg
try { $Hero.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'Instance,NonPublic').SetValue($Hero, $true, $null) } catch {}
$pDash.Controls.Add($Hero)
$Hero.Region = New-Object System.Drawing.Region([TbGfx]::Round(0, 0, $HeroW, $RainH, 14))

$script:RainBmp = New-Object System.Drawing.Bitmap $RainW, $RainH
$script:RainG = [System.Drawing.Graphics]::FromImage($script:RainBmp)
$script:HeroBg = [System.Drawing.Color]::Black
if ($script:IsLight) { $script:HeroBg = $cBg }
$script:RainG.Clear($script:HeroBg)
$script:RainG.TextRenderingHint = 'AntiAliasGridFit'
$RainCols = [int]($RainW / $FS)
$script:Drops = New-Object 'int[]' $RainCols
$Rnd = New-Object System.Random
for ($i = 0; $i -lt $RainCols; $i++) { $script:Drops[$i] = -$Rnd.Next(0, 20) }
$RainChars = '01234567890ABCDEFGHIJKLMNOPQRSTUVWXYZ<>/\|=+*#$%&'
$RainFont  = Mk-Font 11 $true
$BrGreen   = New-Object System.Drawing.SolidBrush($cGreen)
$BrHead    = New-Object System.Drawing.SolidBrush((RGB 210 255 220))
$BrFade    = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(34, $script:HeroBg.R, $script:HeroBg.G, $script:HeroBg.B))
$BrBanner  = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(205, $script:HeroBg.R, $script:HeroBg.G, $script:HeroBg.B))
$BrDimTxt  = New-Object System.Drawing.SolidBrush((RGB 120 230 150))
$HeroTitle = Mk-Font 20 $true
$HeroSub   = Mk-Font 10

$Timer = New-Object System.Windows.Forms.Timer
$Timer.Interval = 70
$Timer.Add_Tick({
    if (-not $script:Pages['dash'].Visible) { return }
    $script:RainG.FillRectangle($BrFade, 0, 0, $RainW, $RainH)
    for ($i = 0; $i -lt $RainCols; $i++) {
        $y = $script:Drops[$i] * $FS
        if ($y -ge 0) {
            $c = [string]$RainChars[$Rnd.Next($RainChars.Length)]
            if ($Rnd.Next(10) -eq 0) { $script:RainG.DrawString($c, $RainFont, $BrHead, ($i * $FS), $y) }
            else { $script:RainG.DrawString($c, $RainFont, $BrGreen, ($i * $FS), $y) }
        }
        if ($y -gt $RainH -and $Rnd.NextDouble() -gt 0.96) { $script:Drops[$i] = 0 } else { $script:Drops[$i]++ }
    }
    $Hero.Invalidate()
})
$Hero.Add_Paint({
    param($s, $e)
    $gg = $e.Graphics
    $gg.DrawImage($script:RainBmp, 0, 0)
    $gg.TextRenderingHint = 'AntiAliasGridFit'
    $gg.FillRectangle($BrBanner, 0, 0, 520, $RainH)
    $gg.DrawString('OPTIMIZE YOUR PC', $HeroTitle, $BrGreen, 24, 20)
    $gg.DrawString('Apply the tweaks and get Windows ready for CS2.', $HeroSub, $BrDimTxt, 26, 58)
    $pen = New-Object System.Drawing.Pen($cBorder, 2)
    $gp = [TbGfx]::Round(1, 1, ($s.Width - 2), ($RainH - 2), 14)
    $gg.DrawPath($pen, $gp)
    $gp.Dispose(); $pen.Dispose()
})
$btnHero = New-Btn $Hero 'OPEN TWEAKS' 650 31 180 42 0
$btnHero.BackColor = $script:HeroBg
$btnHero.Add_Click({ Show-Page 'tweaks' })
$Timer.Start()

# Info cards (CPU / GPU / RAM / Storage)
$info = $script:Info
$cards4 = @(
    @('CPU', 'PROCESSOR',   $info.Cores,       $info.Cpu),
    @('GPU', 'GRAPHICS',      $info.Vram,        $info.Gpu),
    @('RAM', 'MEMORY',       $info.RamType,     $info.Ram),
    @('SSD', 'STORAGE', $info.StorageType, $info.Storage)
)
$script:InfoCards = @()
$cx = 20
foreach ($ci in $cards4) {
    $k = New-Card $pDash $cx 134 202 98 $cCard $cBorder 12
    $tag = New-Card $k 14 14 40 40 $cIcon $cBorder 9
    $tl = New-Label $tag $ci[0] 0 0 40 40 $fSm $cGreen
    $tl.TextAlign = 'MiddleCenter'
    $ia = New-Label $k $ci[1] 62 14 134 16 $fSm $cMuted
    $ib = New-Label $k $ci[2] 62 32 134 18 $fN $cDim
    $ic2 = New-Label $k $ci[3] 14 62 176 30 $fB $cGreen
    $script:InfoCards += @{ K = $k; A = $ia; B = $ib; C = $ic2 }
    $cx += 216
}

# Operating system
$osCard = New-Card $pDash 20 246 414 244 $cCard $cBorder 12
[void](New-Label $osCard 'OPERATING SYSTEM' 18 14 300 20 $fH $cGreen)
[void](New-Label $osCard 'System information' 18 36 300 16 $fSm $cMuted)
$rowsOs = @(@('OS', $info.Os), @('VERSION', $info.OsVer), @('DISK MODEL', $info.Disk), @('GPU', $info.Gpu))
$script:OsVals = @(); $script:OsLines = @()
$ry = 70
foreach ($r in $rowsOs) {
    [void](New-Label $osCard $r[0] 18 $ry 130 20 $fSm $cMuted)
    $v = New-Label $osCard $r[1] 150 $ry 246 20 $fB $cGreen
    $v.TextAlign = 'MiddleRight'
    $script:OsVals += $v
    $script:OsLines += (New-Line $osCard 18 ($ry + 34) 378)
    $ry += 42
}

# Optimization status
$stCard = New-Card $pDash 450 246 420 244 $cCard $cBorder 12
[void](New-Label $stCard 'OPTIMIZATION STATUS' 18 14 300 20 $fH $cGreen)
[void](New-Label $stCard 'Tweaks summary' 18 36 300 16 $fSm $cMuted)
$script:StatNums = @{}
$stRows = @(@('avail', 'Available tweaks'), @('sel', 'Selected tweaks'), @('applied', 'Applied this session'), @('level', 'Optimization level'))
$script:StatCards = @()
$sy = 64
foreach ($sr in $stRows) {
    $rc = New-Card $stCard 16 $sy 388 40 $cCard2 $cBorder 9
    $script:StatCards += $rc
    $num = New-Label $rc '0' 12 7 86 26 $fBig $cGreen
    $num.TextAlign = 'MiddleLeft'
    [void](New-Label $rc $sr[1] 104 11 270 20 $fN $cDim)
    $script:StatNums[$sr[0]] = $num
    $sy += 44
}

function Update-Dash {
    $total = $Modules.Count
    $sel = 0; $selMain = 0; $selExp = 0
    foreach ($m in $Modules) { if ($m.Box.Checked) { $sel++; if ($m.Exp) { $selExp++ } elseif (-not $m.Cs2) { $selMain++ } } }
    $script:StatNums['avail'].Text = "$total"
    $script:StatNums['sel'].Text = "$sel"
    $script:StatNums['applied'].Text = "$($script:AppliedCount)"
    $lv = 0
    if ($total -gt 0) { $lv = [int][math]::Min(100, [math]::Round(100 * $script:AppliedCount / $total)) }
    $script:StatNums['level'].Text = "$lv%"
    if ($script:TweaksSub) { $script:TweaksSub.Text = "Choose what to apply  -  $selMain of $($MainModules.Count) selected" }
    if ($script:SelBadge) { $script:SelBadge.Text = "$selMain selected" }
    if ($script:ExpBadge) { $script:ExpBadge.Text = "$selExp selected" }
}

# =========================================================
#  PAGE: OPTIMIZATIONS
# =========================================================
$pTw = New-Page 'tweaks'
$script:TweaksSub = New-Header $pTw ([string][char]0xE945) 'Performance Tweaks' 'Choose what to apply'
$badge = New-Card $pTw 738 38 114 28 $cOnFill $cOnBord 14
$script:SelBadge = New-Label $badge '0 selected' 0 0 114 28 $fSm $cGreen
$script:SelBadge.TextAlign = 'MiddleCenter'
$badge.BringToFront()

# busca
$sc = New-Card $pTw 20 100 850 38 $cCard $cBorder 10
$sg = New-Label $sc ([string][char]0xE721) 12 8 22 22 (Mk-Font 12 $false 'Segoe MDL2 Assets') $cMuted
$script:SearchBox = New-Object System.Windows.Forms.TextBox
$script:SearchBox.BorderStyle = 'None'
$script:SearchBox.Font = Mk-Font 10
$script:SearchBox.ForeColor = $cGreen
$script:SearchBox.Location = New-Object System.Drawing.Point(42, 10)
$script:SearchBox.Size = New-Object System.Drawing.Size(790, 20)
$sc.Controls.Add($script:SearchBox)
$script:SearchBox.Add_TextChanged({ Apply-Filter })

# chips
$script:Chips = @{}
$cxp = 20
foreach ($nm in @('All', 'Performance', 'Gaming', 'Privacy', 'Network', 'Appearance', 'Risk')) {
    $w = 30 + 9 * $nm.Length
    $ch = New-Object TbChip
    $ch.Text = $nm
    $ch.Tag = $nm
    $ch.Location = New-Object System.Drawing.Point($cxp, 148)
    $ch.Size = New-Object System.Drawing.Size($w, 28)
    $ch.BackColor = $cBg
    if ($nm -eq 'All') { $ch.Selected = $true }
    $pTw.Controls.Add($ch)
    $script:Chips[$nm] = $ch
    $ch.Add_Click({
        param($s, $e)
        $script:Filter = $s.Tag
        foreach ($k in $script:Chips.Keys) { $script:Chips[$k].Selected = ($k -eq $script:Filter) }
        Apply-Filter
    })
    $cxp += $w + 8
}

# card grid
$script:ModScroll = New-Object TbScroll
$script:ModScroll.Location = New-Object System.Drawing.Point(20, 188)
$script:ModScroll.Size = New-Object System.Drawing.Size(850, 304)
$script:ModScroll.BackColor = $cBg
$pTw.Controls.Add($script:ModScroll)

function Set-CardState($m) {
    $on = $m.Box.Checked
    if ($on) {
        if ($m.Risk) { $m.Card.Fill = $cRedBg; $m.Card.Border = $cRed }
        else { $m.Card.Fill = $cOnFill; $m.Card.Border = $cOnBord }
    } else {
        $m.Card.Fill = $cCard; $m.Card.Border = $cBorder
    }
    $m.Box.BackColor = $m.Card.Fill
    if ($on) {
        if ($m.Risk) { $m.Status.Text = [string][char]0x26A0 + ' RISK - SELECTED'; $m.Status.ForeColor = $cRed }
        else { $m.Status.Text = [string][char]0x25CF + ' SELECTED'; $m.Status.ForeColor = $cGreen }
    } else {
        $m.Status.Text = [string][char]0x25CB + ' OFF'
        $m.Status.ForeColor = $cMuted
    }
    Update-Dash
}

function Build-ModCard($m, $parent) {
    $card = New-Card $parent 0 0 266 134 $cCard $cBorder 12
    $catText = ($m.Cats -join '  /  ').ToUpper()
    [void](New-Label $card $catText 14 12 160 16 $fSm $cMuted)
    $st = $null
    if ($m.Star) {
        $st = New-Label $card ([string][char]0x2605) 176 9 22 20 $fB $cGreen
    }
    $tg = New-Toggle $card 208 9 $m.On
    $nl = New-Label $card $m.Label 14 36 240 20 $fB $cGreen
    $dl = New-Label $card $m.Desc 14 58 240 50 $fSm $cDim
    $dl.AutoEllipsis = $false
    $stl = New-Label $card '' 14 112 240 16 $fSm $cMuted
    $m | Add-Member -NotePropertyName Card -NotePropertyValue $card -Force
    $m | Add-Member -NotePropertyName Box -NotePropertyValue $tg -Force
    $m | Add-Member -NotePropertyName Status -NotePropertyValue $stl -Force
    $m | Add-Member -NotePropertyName StarLbl -NotePropertyValue $st -Force
    $m | Add-Member -NotePropertyName DescLbl -NotePropertyValue $dl -Force
    $m | Add-Member -NotePropertyName NameLbl -NotePropertyValue $nl -Force
    $m | Add-Member -NotePropertyName Show -NotePropertyValue $true -Force
    $tg.Tag = $m
    $tg.Add_CheckedChanged({ param($s, $e) Set-CardState $s.Tag })
}
function Set-CardWidth($m, $w) {
    $m.Card.Width = $w
    $m.Box.Left = $w - 58
    if ($m.StarLbl) { $m.StarLbl.Left = $w - 90 }
    $m.NameLbl.Width = $w - 26
    $m.DescLbl.Width = $w - 26
    $m.Status.Width = $w - 26
}
function Flow-Grid($mods, $scroll) {
    $scroll.SetContentHeight(0)
    $iw = $scroll.Inner.Width
    $cols = [int][math]::Max(1, [math]::Floor(($iw + 18) / 284))
    $cw = [int][math]::Floor(($iw - 18 * ($cols - 1)) / $cols)
    $n = 0
    foreach ($m in $mods) {
        Set-CardWidth $m $cw
        if ($m.Show) {
            $m.Card.Location = New-Object System.Drawing.Point((($cw + 18) * ($n % $cols)), (148 * [int][math]::Floor($n / $cols)))
            $n++
        }
    }
    $scroll.SetContentHeight(([int][math]::Ceiling($n / $cols)) * 148 + 4)
}
foreach ($m in $MainModules) { Build-ModCard $m $script:ModScroll.Inner }
foreach ($m in $MainModules) { Set-CardState $m }

function Apply-Filter {
    $q = $script:SearchBox.Text.Trim().ToLower()
    foreach ($m in $MainModules) {
        $show = $true
        if ($script:Filter -ne 'All') { $show = ($m.Cats -contains $script:Filter) }
        if ($show -and $q) { $show = (($m.Label + ' ' + $m.Desc).ToLower().Contains($q)) }
        $m.Show = $show
        $m.Card.Visible = $show
    }
    Flow-Grid $MainModules $script:ModScroll
}
Apply-Filter

$btnOpt = New-Btn $pTw 'OPTIMIZE ALL' 20 500 270 40 0
$btnRec = New-Btn $pTw 'SELECT RECOMMENDED' 304 500 270 40 1
$btnRevTw = New-Btn $pTw 'REVERT ALL' 600 500 270 40 2
$btnOpt.Add_Click({ try { Invoke-Optimize $MainModules } catch { Log "ERROR: $($_.Exception.Message)"; Set-Busy $false } })
$btnRec.Add_Click({ foreach ($m in $MainModules) { $m.Box.Checked = ($m.Star -or ((-not $m.Risk) -and $m.On)) } })
$btnRevTw.Add_Click({ try { Invoke-Revert } catch { Log "ERROR: $($_.Exception.Message)"; Set-Busy $false } })

# =========================================================
#  PAGE: EXPERIMENTAL
# =========================================================
$pEx = New-Page 'exp'
[void](New-Header $pEx ([string][char]0xE7BA) 'Experimental' 'Unproven effect that varies from PC to PC. Off by default.')
$exBadge = New-Card $pEx 738 38 114 28 $cOnFill $cOnBord 14
$script:ExpBadge = New-Label $exBadge '0 selected' 0 0 114 28 $fSm $cGreen
$script:ExpBadge.TextAlign = 'MiddleCenter'
$exBadge.BringToFront()
$exNote = New-Card $pEx 20 100 850 44 $cRedBg $cRedBd 10
[void](New-Label $exNote ([string][char]0x26A0 + '  Test one at a time. If FPS drops or something looks odd, turn it off and use REVERT ALL.') 16 12 820 20 $fN $cRed)
$script:ExpScroll = New-Object TbScroll
$script:ExpScroll.Location = New-Object System.Drawing.Point(20, 156)
$script:ExpScroll.Size = New-Object System.Drawing.Size(850, 336)
$script:ExpScroll.BackColor = $cBg
$pEx.Controls.Add($script:ExpScroll)
foreach ($m in $ExpModules) { Build-ModCard $m $script:ExpScroll.Inner }
Flow-Grid $ExpModules $script:ExpScroll
foreach ($m in $ExpModules) { Set-CardState $m }
$btnExp = New-Btn $pEx 'APPLY EXPERIMENTAL' 20 500 270 40 0
$btnRevEx = New-Btn $pEx 'REVERT ALL' 600 500 270 40 2
$btnExp.Add_Click({ try { Invoke-Optimize $ExpModules } catch { Log "ERROR: $($_.Exception.Message)"; Set-Busy $false } })
$btnRevEx.Add_Click({ try { Invoke-Revert } catch { Log "ERROR: $($_.Exception.Message)"; Set-Busy $false } })

# =========================================================
#  PAGE: CLEANUP
# =========================================================
$pCl = New-Page 'clean'
$script:CleanHeader = New-Header $pCl ([string][char]0xE74D) 'System Cleanup' 'Last cleanup: never'
if (Test-Path $CleanFile) { try { $script:CleanHeader.Text = 'Last cleanup: ' + (Get-Content $CleanFile -Raw).Trim() } catch {} }

$clCard = New-Card $pCl 20 100 850 312 $cCard $cBorder 12
$script:CleanToggles = [ordered]@{}
$cleanItems = @(
    @('Temp',     'Clean temporary files',   'Removes user and Windows temporary files.', $true,  $false),
    @('Prefetch', 'Clean Prefetch files',      'Empties the Prefetch folder (apps open slightly slower the first time).', $false, $false),
    @('Recycle',  'Empty Recycle Bin (dangerous)',   'Permanently deletes everything in the Recycle Bin.', $false, $true),
    @('WUCache',  'Clean Windows Update cache', 'Removes installation files downloaded by Windows Update.', $true,  $false),
    @('Thumbs',   'Clean thumbnail cache',    'Deletes cached File Explorer thumbnails.', $true,  $false)
)
$yy = 8
$idx = 0
foreach ($ci in $cleanItems) {
    $tcol = $cGreen
    if ($ci[4]) { $tcol = $cRed }
    [void](New-Label $clCard $ci[1] 22 ($yy + 10) 600 20 $fB $tcol)
    [void](New-Label $clCard $ci[2] 22 ($yy + 32) 640 16 $fSm $cMuted)
    $tg = New-Toggle $clCard 786 ($yy + 18) $ci[3]
    $script:CleanToggles[$ci[0]] = $tg
    $idx++
    if ($idx -lt $cleanItems.Count) { [void](New-Line $clCard 16 ($yy + 60) 818) }
    $yy += 60
}
$btnClean = New-Btn $pCl 'CLEAN SELECTED' 600 424 270 42 0
$btnClean.Add_Click({ try { Invoke-Clean } catch { Log "ERROR: $($_.Exception.Message)"; Set-Busy $false } })

# =========================================================
#  PAGE: RESTORE
# =========================================================
$pRs = New-Page 'restore'
[void](New-Header $pRs ([string][char]0xE81C) 'Restore and Repair' 'Go back or fix Windows')

$rc1 = New-Card $pRs 20 100 850 92 $cCard $cBorder 12
[void](New-Label $rc1 'Restore point' 22 18 500 22 $fH $cGreen)
[void](New-Label $rc1 'Creates a Windows restore point now (TutuBoost also creates one before optimizing).' 22 46 560 36 $fSm $cMuted)
$btnRp = New-Btn $rc1 'CREATE NOW' 590 26 236 40 1
$btnRp.Add_Click({ Set-Busy $true; try { Invoke-RestorePoint } finally { Set-Busy $false } })

$rc2 = New-Card $pRs 20 204 850 92 $cCard $cBorder 12
[void](New-Label $rc2 'Revert everything to original' 22 18 500 22 $fH $cGreen)
[void](New-Label $rc2 'Undoes everything TutuBoost changed: registry, boot, services, power and refresh rate.' 22 46 560 36 $fSm $cMuted)
$btnRv = New-Btn $rc2 'REVERT ALL' 590 26 236 40 2
$btnRv.Add_Click({ try { Invoke-Revert } catch { Log "ERROR: $($_.Exception.Message)"; Set-Busy $false } })

[void](New-Label $pRs 'SYSTEM REPAIR' 22 314 400 18 $fB $cGreen)
$repairs = @(
    @('DISM + SFC',          'Repairs corrupted Windows files (needs internet).', { Invoke-Repair }),
    @('Reset network',        'Winsock, IP and DNS. The connection drops and the PC must restart.',   { Invoke-NetReset }),
    @('Reset Windows Update', 'Renames SoftwareDistribution and catroot2.',                 { Invoke-WUReset })
)
$rx = 20
foreach ($rp in $repairs) {
    $k = New-Card $pRs $rx 342 270 150 $cCard $cBorder 12
    [void](New-Label $k $rp[0] 18 16 234 22 $fH $cGreen)
    $d = New-Label $k $rp[1] 18 44 234 44 $fSm $cMuted
    $d.AutoEllipsis = $false
    $b = New-Btn $k 'RUN' 18 98 234 36 1
    $b.Tag = $rp[2]
    $b.Add_Click({ param($s, $e) try { & $s.Tag } catch { Log "ERROR: $($_.Exception.Message)" } })
    $rx += 290
}

# =========================================================
#  PAGE: APPS
# =========================================================
$pAp = New-Page 'apps'
[void](New-Header $pAp ([string][char]0xE71D) 'Remove Apps' 'Pre-installed Windows apps (select the ones you want to remove)')
$script:AppScroll = New-Object TbScroll
$script:AppScroll.Location = New-Object System.Drawing.Point(20, 100)
$script:AppScroll.Size = New-Object System.Drawing.Size(850, 392)
$script:AppScroll.BackColor = $cBg
$pAp.Controls.Add($script:AppScroll)
$script:AppToggles = @{}
$script:AppRows = @()
$ay = 0
foreach ($a in $script:AppDefs) {
    $rc = New-Card $script:AppScroll.Inner 0 $ay 836 56 $cCard $cBorder 10
    [void](New-Label $rc $a.Name 18 8 600 20 $fB $cGreen)
    [void](New-Label $rc $a.Desc 18 31 700 16 $fSm $cMuted)
    $tg = New-Toggle $rc 770 16 $a.Pre
    $script:AppToggles[$a.Id] = $tg
    $script:AppRows += @{ C = $rc; T = $tg }
    $ay += 62
}
$script:AppScroll.SetContentHeight($ay)
function Flow-Apps {
    $iw = $script:AppScroll.Inner.Width
    foreach ($r in $script:AppRows) { $r.C.Width = $iw - 14; $r.T.Left = $iw - 14 - 66 }
}
$btnApps = New-Btn $pAp 'REMOVE SELECTED' 600 500 270 40 2
$btnApps.Add_Click({ try { Invoke-Bloat } catch { Log "ERROR: $($_.Exception.Message)"; Set-Busy $false } })

# =========================================================
#  PAGE: POST-FORMAT
# =========================================================
$script:SetupItems = @(
    @{ Id = 'runtimes'; Cat = 'Gaming essentials'; Name = 'Essential runtimes'; Desc = 'VC++ 2008-2015+, .NET 8, DirectX'; Kind = 'winget'; Pre = $true; Ids = @('Microsoft.VCRedist.2015+.x64', 'Microsoft.VCRedist.2015+.x86', 'Microsoft.VCRedist.2013.x64', 'Microsoft.VCRedist.2013.x86', 'Microsoft.VCRedist.2012.x64', 'Microsoft.VCRedist.2012.x86', 'Microsoft.VCRedist.2010.x64', 'Microsoft.VCRedist.2010.x86', 'Microsoft.VCRedist.2008.x64', 'Microsoft.VCRedist.2008.x86', 'Microsoft.DotNet.DesktopRuntime.8', 'Microsoft.DirectX') },
    @{ Id = 'sevenzip'; Cat = 'Gaming essentials'; Name = '7-Zip'; Desc = 'Opens .zip, .rar and .7z'; Kind = 'winget'; Pre = $true; Ids = @('7zip.7zip') },
    @{ Id = 'gpudrv'; Cat = 'Drivers (opens the official page)'; Name = 'Graphics card driver'; Desc = 'Detects NVIDIA, AMD or Intel'; Kind = 'gpu'; Pre = $true },
    @{ Id = 'boarddrv'; Cat = 'Drivers (opens the official page)'; Name = 'Motherboard drivers'; Desc = 'Chipset, audio, network'; Kind = 'board'; Pre = $true },
    @{ Id = 'gc'; Cat = 'Anticheats'; Name = 'GamersClub'; Desc = 'Downloads from the official link'; Kind = 'url'; Pre = $false; Url = 'https://acupdate.gamersclub.com.br/download' },
    @{ Id = 'faceit'; Cat = 'Anticheats'; Name = 'FACEIT Anti-Cheat'; Desc = 'Downloads the official installer'; Kind = 'faceit'; Pre = $false; Url = 'https://anticheat-client.faceit-cdn.net/FACEITInstaller_64.exe' },
    @{ Id = 'steam'; Cat = 'Games'; Name = 'Steam'; Desc = 'Valve'; Kind = 'winget'; Pre = $false; Ids = @('Valve.Steam') },
    @{ Id = 'epic'; Cat = 'Games'; Name = 'Epic Games Launcher'; Desc = 'Epic Games'; Kind = 'winget'; Pre = $false; Ids = @('EpicGames.EpicGamesLauncher') },
    @{ Id = 'bnet'; Cat = 'Games'; Name = 'Battle.net'; Desc = 'Blizzard'; Kind = 'winget'; Pre = $false; Ids = @('Blizzard.BattleNet') },
    @{ Id = 'gog'; Cat = 'Games'; Name = 'GOG Galaxy'; Desc = 'GOG'; Kind = 'winget'; Pre = $false; Ids = @('GOG.Galaxy') },
    @{ Id = 'discord'; Cat = 'Communication'; Name = 'Discord'; Desc = 'Voice and chat'; Kind = 'winget'; Pre = $false; Ids = @('Discord.Discord') },
    @{ Id = 'teamspeak'; Cat = 'Communication'; Name = 'TeamSpeak'; Desc = 'Voice'; Kind = 'winget'; Pre = $false; Ids = @('TeamSpeakSystems.TeamSpeakClient') },
    @{ Id = 'telegram'; Cat = 'Communication'; Name = 'Telegram'; Desc = 'Messaging'; Kind = 'winget'; Pre = $false; Ids = @('Telegram.TelegramDesktop') },
    @{ Id = 'zoom'; Cat = 'Communication'; Name = 'Zoom'; Desc = 'Meetings'; Kind = 'winget'; Pre = $false; Ids = @('Zoom.Zoom') },
    @{ Id = 'chrome'; Cat = 'Browsers'; Name = 'Google Chrome'; Desc = 'Google'; Kind = 'winget'; Pre = $false; Ids = @('Google.Chrome') },
    @{ Id = 'firefox'; Cat = 'Browsers'; Name = 'Firefox'; Desc = 'Mozilla'; Kind = 'winget'; Pre = $false; Ids = @('Mozilla.Firefox') },
    @{ Id = 'brave'; Cat = 'Browsers'; Name = 'Brave'; Desc = 'With ad blocker'; Kind = 'winget'; Pre = $false; Ids = @('Brave.Brave') },
    @{ Id = 'opera'; Cat = 'Browsers'; Name = 'Opera'; Desc = 'Opera'; Kind = 'winget'; Pre = $false; Ids = @('Opera.Opera') },
    @{ Id = 'obs'; Cat = 'Stream and media'; Name = 'OBS Studio'; Desc = 'Record and livestream'; Kind = 'winget'; Pre = $false; Ids = @('OBSProject.OBSStudio') },
    @{ Id = 'vlc'; Cat = 'Stream and media'; Name = 'VLC'; Desc = 'Video player'; Kind = 'winget'; Pre = $false; Ids = @('VideoLAN.VLC') },
    @{ Id = 'spotify'; Cat = 'Stream and media'; Name = 'Spotify'; Desc = 'Music'; Kind = 'winget'; Pre = $false; Ids = @('Spotify.Spotify') },
    @{ Id = 'audacity'; Cat = 'Stream and media'; Name = 'Audacity'; Desc = 'Audio editor'; Kind = 'winget'; Pre = $false; Ids = @('Audacity.Audacity') },
    @{ Id = 'handbrake'; Cat = 'Stream and media'; Name = 'HandBrake'; Desc = 'Convert videos'; Kind = 'winget'; Pre = $false; Ids = @('HandBrake.HandBrake') },
    @{ Id = 'hwinfo'; Cat = 'Monitoring'; Name = 'HWiNFO'; Desc = 'Sensors and temperatures'; Kind = 'winget'; Pre = $false; Ids = @('REALiX.HWiNFO') },
    @{ Id = 'afterburner'; Cat = 'Monitoring'; Name = 'MSI Afterburner'; Desc = 'Overlay and GPU curve'; Kind = 'winget'; Pre = $false; Ids = @('Guru3D.Afterburner') },
    @{ Id = 'cpuz'; Cat = 'Monitoring'; Name = 'CPU-Z'; Desc = 'CPU and RAM information'; Kind = 'winget'; Pre = $false; Ids = @('CPUID.CPU-Z') },
    @{ Id = 'gpuz'; Cat = 'Monitoring'; Name = 'GPU-Z'; Desc = 'GPU information'; Kind = 'winget'; Pre = $false; Ids = @('TechPowerUp.GPU-Z') },
    @{ Id = 'cdi'; Cat = 'Monitoring'; Name = 'CrystalDiskInfo'; Desc = 'SSD/HDD health'; Kind = 'winget'; Pre = $false; Ids = @('CrystalDewWorld.CrystalDiskInfo') },
    @{ Id = 'ghub'; Cat = 'Peripherals'; Name = 'Logitech G HUB'; Desc = 'Logitech mouse and keyboard'; Kind = 'winget'; Pre = $false; Ids = @('Logitech.GHUB') },
    @{ Id = 'everything'; Cat = 'Utilities'; Name = 'Everything'; Desc = 'Instant file search'; Kind = 'winget'; Pre = $false; Ids = @('voidtools.Everything') },
    @{ Id = 'notepadpp'; Cat = 'Utilities'; Name = 'Notepad++'; Desc = 'Text editor'; Kind = 'winget'; Pre = $false; Ids = @('Notepad++.Notepad++') },
    @{ Id = 'powertoys'; Cat = 'Utilities'; Name = 'PowerToys'; Desc = 'Microsoft tools'; Kind = 'winget'; Pre = $false; Ids = @('Microsoft.PowerToys') },
    @{ Id = 'sharex'; Cat = 'Utilities'; Name = 'ShareX'; Desc = 'Screenshots'; Kind = 'winget'; Pre = $false; Ids = @('ShareX.ShareX') },
    @{ Id = 'bitwarden'; Cat = 'Utilities'; Name = 'Bitwarden'; Desc = 'Password manager'; Kind = 'winget'; Pre = $false; Ids = @('Bitwarden.Bitwarden') },
    @{ Id = 'gdrive'; Cat = 'Cloud'; Name = 'Google Drive'; Desc = 'Google'; Kind = 'winget'; Pre = $false; Ids = @('Google.GoogleDrive') },
    @{ Id = 'dropbox'; Cat = 'Cloud'; Name = 'Dropbox'; Desc = 'Dropbox'; Kind = 'winget'; Pre = $false; Ids = @('Dropbox.Dropbox') }
)

$script:Questions = @(
    @{ Q = 'Will you record videos or livestream?'; Hint = 'Selects OBS Studio.'; Multi = $false; Opts = @(
        @{ L = 'Yes'; Ids = @('obs') }, @{ L = 'No'; Ids = @() }) },
    @{ Q = 'Do you play on GamersClub and/or FACEIT?'; Hint = 'Selects the anticheat for each platform.'; Multi = $false; Opts = @(
        @{ L = 'GamersClub'; Ids = @('gc') }, @{ L = 'FACEIT'; Ids = @('faceit') }, @{ L = 'Both'; Ids = @('gc', 'faceit') }, @{ L = 'None'; Ids = @() }) },
    @{ Q = 'Which voice chat app do you use?'; Hint = 'Discord, TeamSpeak or both.'; Multi = $false; Opts = @(
        @{ L = 'Discord'; Ids = @('discord') }, @{ L = 'TeamSpeak'; Ids = @('teamspeak') }, @{ L = 'Both'; Ids = @('discord', 'teamspeak') }, @{ L = 'None'; Ids = @() }) },
    @{ Q = 'Which game stores do you use?'; Hint = 'You can select more than one.'; Multi = $true; Opts = @(
        @{ L = 'Steam'; Ids = @('steam') }, @{ L = 'Epic Games'; Ids = @('epic') }, @{ L = 'Battle.net'; Ids = @('bnet') }, @{ L = 'GOG'; Ids = @('gog') }) },
    @{ Q = 'Which browser do you prefer?'; Hint = 'Edge already comes with Windows.'; Multi = $false; Opts = @(
        @{ L = 'Chrome'; Ids = @('chrome') }, @{ L = 'Firefox'; Ids = @('firefox') }, @{ L = 'Brave'; Ids = @('brave') }, @{ L = 'Opera'; Ids = @('opera') }, @{ L = 'Edge only'; Ids = @() }) },
    @{ Q = 'Music and messaging?'; Hint = 'You can select more than one.'; Multi = $true; Opts = @(
        @{ L = 'Spotify'; Ids = @('spotify') }, @{ L = 'Telegram'; Ids = @('telegram') }, @{ L = 'Zoom'; Ids = @('zoom') }) },
    @{ Q = 'Want to monitor PC temperature and health?'; Hint = 'HWiNFO, Afterburner, CPU-Z, GPU-Z and CrystalDiskInfo.'; Multi = $false; Opts = @(
        @{ L = 'Yes'; Ids = @('hwinfo', 'afterburner', 'cpuz', 'gpuz', 'cdi') }, @{ L = 'No'; Ids = @() }) },
    @{ Q = 'Is your mouse or keyboard Logitech?'; Hint = 'Selects G HUB.'; Multi = $false; Opts = @(
        @{ L = 'Yes'; Ids = @('ghub') }, @{ L = 'No'; Ids = @() }) },
    @{ Q = 'Want some extra utilities?'; Hint = 'Everything, Notepad++, PowerToys, ShareX and VLC.'; Multi = $false; Opts = @(
        @{ L = 'Yes'; Ids = @('everything', 'notepadpp', 'powertoys', 'sharex', 'vlc') }, @{ L = 'No'; Ids = @() }) }
)

function Get-GpuVendor {
    $names = @()
    try { $names = @(Get-CimInstance Win32_VideoController -ErrorAction Stop | ForEach-Object { $_.Name }) } catch {}
    $all = ($names -join ' ')
    if ($all -match 'NVIDIA|GeForce|RTX|GTX') { return 'NVIDIA' }
    if ($all -match 'AMD|Radeon') { return 'AMD' }
    if ($all -match 'Intel') { return 'Intel' }
    return ''
}

function Invoke-Setup {
    $sel = @($script:SetupItems | Where-Object { $script:SetupBox[$_.Id].Checked })
    if ($sel.Count -eq 0) { Log 'Post-format: nothing selected.'; return }
    $hasWg = $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
    $needWg = @($sel | Where-Object { $_.Kind -eq 'winget' }).Count -gt 0
    if ($needWg -and -not $hasWg) {
        Log '[ WARNING ] winget not found. Install/update "App Installer" from the Microsoft Store and try again.'
    }
    $names = ($sel | ForEach-Object { $_.Name }) -join "`n - "
    if (-not (Ask "Install / open these items?`n`n - $names")) { return }
    Set-Busy $true
    try {
        foreach ($it in $sel) {
            switch ($it.Kind) {
                'winget' {
                    if (-not $hasWg) { Log "   skipped (no winget): $($it.Name)"; break }
                    foreach ($wid in $it.Ids) {
                        Log "   installing: $($it.Name)  [$wid]"
                        & winget install --id $wid -e --silent --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1 | Out-Null
                        $code = $LASTEXITCODE
                        if ($code -eq 0) { Log '      ok' }
                        elseif ($code -eq -1978335189 -or $code -eq -1978335135) { Log '      already installed' }
                        else { Log "      failed (code $code)" }
                    }
                }
                'url' {
                    Log "   opening: $($it.Name)"
                    try { Start-Process $it.Url } catch { Log "      could not open: $($it.Url)" }
                }
                'faceit' {
                    Log "   downloading: $($it.Name)"
                    $dst = Join-Path $env:TEMP 'FACEITInstaller_64.exe'
                    try {
                        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                        Invoke-WebRequest -Uri $it.Url -OutFile $dst -UseBasicParsing -ErrorAction Stop
                        Log '      downloaded, opening the installer'
                        Start-Process $dst
                    } catch {
                        Log '      download failed, opening the link in the browser'
                        try { Start-Process $it.Url } catch {}
                    }
                }
                'gpu' {
                    $v = Get-GpuVendor
                    $u = 'https://www.nvidia.com/Download/index.aspx?lang=br'
                    if ($v -eq 'AMD') { $u = 'https://www.amd.com/en/support/download/drivers.html' }
                    elseif ($v -eq 'Intel') { $u = 'https://www.intel.com.br/content/www/br/pt/download-center/home.html' }
                    elseif ($v -eq '') { $u = 'https://www.google.com/search?q=graphics+card+driver+download' }
                    Log "   video driver ($v): opening the official page"
                    try { Start-Process $u } catch {}
                }
                'board' {
                    $man = ''; $prod = ''
                    try { $bb = Get-CimInstance Win32_BaseBoard -ErrorAction Stop; $man = $bb.Manufacturer; $prod = $bb.Product } catch {}
                    $q = [Uri]::EscapeDataString("$man $prod drivers download")
                    Log "   motherboard drivers ($man $prod): opening search"
                    try { Start-Process "https://www.google.com/search?q=$q" } catch {}
                }
            }
        }
        Log '[ OK ] Post-format setup complete. Restart the PC if any installer asks.'
    } finally { Set-Busy $false }
}

$pSu = New-Page 'setup'
[void](New-Header $pSu ([string][char]0xE896) 'Post-format' 'Install everything at once. The guide is optional: it selects what fits you.')

# ---- view: list ----
$script:SetScroll = New-Object TbScroll
$script:SetScroll.Location = New-Object System.Drawing.Point(20, 100)
$script:SetScroll.Size = New-Object System.Drawing.Size(850, 392)
$script:SetScroll.BackColor = $cBg
$pSu.Controls.Add($script:SetScroll)
$script:SetupBox = @{}
$script:SetupSeq = @()
$lastCat = ''
foreach ($it in $script:SetupItems) {
    if ($it.Cat -ne $lastCat) {
        $lastCat = $it.Cat
        $hl = New-Label $script:SetScroll.Inner $it.Cat.ToUpper() 4 0 800 18 $fB $cDim
        $script:SetupSeq += @{ H = $hl }
    }
    $rc = New-Card $script:SetScroll.Inner 0 0 412 52 $cCard $cBorder 10
    [void](New-Label $rc $it.Name 16 7 280 20 $fB $cGreen)
    [void](New-Label $rc $it.Desc 16 29 290 16 $fSm $cMuted)
    $tg = New-Toggle $rc 340 13 $it.Pre
    $script:SetupBox[$it.Id] = $tg
    $script:SetupSeq += @{ C = $rc; T = $tg }
}
function Flow-Setup {
    $script:SetScroll.SetContentHeight(0)
    $iw = $script:SetScroll.Inner.Width
    $cols = [int][math]::Max(1, [math]::Floor(($iw + 12) / 424))
    $cw = [int][math]::Floor(($iw - 12 * ($cols - 1)) / $cols)
    $y = 0; $col = 0
    foreach ($e in $script:SetupSeq) {
        if ($e.H) {
            if ($col -ne 0) { $y += 58; $col = 0 }
            $e.H.Location = New-Object System.Drawing.Point(4, ($y + 6))
            $e.H.Width = $iw - 8
            $y += 30
        } else {
            $e.C.Width = $cw
            $e.T.Left = $cw - 72
            $e.C.Location = New-Object System.Drawing.Point((($cw + 12) * $col), $y)
            if ($col -lt $cols - 1) { $col++ } else { $col = 0; $y += 58 }
        }
    }
    if ($col -ne 0) { $y += 58 }
    $script:SetScroll.SetContentHeight($y + 4)
}

# ---- view: guide ----
$script:SetWiz = New-Object System.Windows.Forms.Panel
$script:SetWiz.Location = New-Object System.Drawing.Point(20, 100)
$script:SetWiz.Size = New-Object System.Drawing.Size(850, 392)
$script:SetWiz.BackColor = $cBg
$script:SetWiz.Visible = $false
$pSu.Controls.Add($script:SetWiz)
$script:WizCard = New-Card $script:SetWiz 0 0 850 392 $cCard $cBorder 12
$script:WizStep = New-Label $script:WizCard '' 28 24 600 16 $fSm $cMuted
$script:WizQ = New-Label $script:WizCard '' 28 52 790 30 $fTitle $cGreen
$script:WizHint = New-Label $script:WizCard '' 28 92 790 18 $fN $cMuted
$script:WbTrack = New-Card $script:WizCard 28 362 794 8 $cBg $cBorder 4
$script:WizBar = New-Card $script:WizCard 28 362 10 8 $cOnBord $cOnBord 4
$script:WizBar.BringToFront()
$script:WizChips = New-Object System.Collections.ArrayList
$script:WizIdx = 0
$script:WizAns = @{}
$script:WizList = $script:Questions
$script:ThemeQ = @{ Q = 'Which theme do you want to use?'; Hint = 'You can change it later in Settings.'; Multi = $false; Theme = $true; Opts = @(foreach ($tk in $script:Themes.Keys) { @{ L = $script:Themes[$tk].Name; Ids = @(); Color = $script:Themes[$tk].Acc } }) }

function Wiz-Render {
    foreach ($c in @($script:WizChips)) { $script:WizCard.Controls.Remove($c); $c.Dispose() }
    $script:WizChips.Clear()
    $q = $script:WizList[$script:WizIdx]
    $n = $script:WizList.Count
    $script:WizStep.Text = ('QUESTION {0} OF {1}' -f ($script:WizIdx + 1), $n)
    $script:WizQ.Text = $q.Q
    $script:WizHint.Text = $q.Hint
    $script:WizBar.Width = [int]($script:WbTrack.Width * ($script:WizIdx + 1) / $n)
    $prev = @()
    if ($script:WizAns.ContainsKey($script:WizIdx)) { $prev = @($script:WizAns[$script:WizIdx]) }
    elseif ($q.Theme) { $prev = @([array]::IndexOf(@($script:Themes.Keys), [string]$script:Config.Theme)) }
    $x = 28; $y = 140; $i = 0
    foreach ($o in $q.Opts) {
        $w = 44 + 11 * $o.L.Length
        if ($x + $w -gt ($script:WizCard.Width - 30)) { $x = 28; $y += 52 }
        $ch = New-Object TbChip
        $ch.Text = $o.L
        $ch.Tag = $i
        $ch.Location = New-Object System.Drawing.Point($x, $y)
        $ch.Size = New-Object System.Drawing.Size($w, 40)
        $ch.BackColor = $script:WizCard.Fill
        if ($o.Color) { $ch.Accent = $o.Color }
        if ($prev -contains $i) { $ch.Selected = $true }
        $script:WizCard.Controls.Add($ch)
        [void]$script:WizChips.Add($ch)
        $ch.Add_Click({
            param($s, $e)
            $qq = $script:WizList[$script:WizIdx]
            if ($qq.Multi) { $s.Selected = -not $s.Selected }
            else { foreach ($o2 in $script:WizChips) { $o2.Selected = ($o2 -eq $s) } }
        })
        $x += $w + 12
        $i++
    }
    $script:WizBar.BringToFront()
    if ($script:WizIdx -eq $n - 1) { $btnWizNext.Text = 'FINISH' } else { $btnWizNext.Text = 'NEXT' }
    $btnWizBack.Enabled = ($script:WizIdx -gt 0)
}
function Wiz-Store {
    $sel = @()
    foreach ($c in $script:WizChips) { if ($c.Selected) { $sel += [int]$c.Tag } }
    if ($sel.Count -gt 0) { $script:WizAns[$script:WizIdx] = $sel }
    elseif ($script:WizAns.ContainsKey($script:WizIdx)) { $script:WizAns.Remove($script:WizIdx) }
}
function Show-SetupView($wiz) {
    $script:SetWiz.Visible = $wiz
    $script:SetScroll.Visible = -not $wiz
    $btnWizStart.Visible = -not $wiz
    $btnSetup.Visible = -not $wiz
    $btnWizBack.Visible = $wiz
    $btnWizExit.Visible = $wiz
    $btnWizNext.Visible = $wiz
}
function Wiz-Finish {
    $count = 0
    foreach ($qi in $script:WizAns.Keys) {
        $q = $script:WizList[$qi]
        foreach ($o in $q.Opts) { foreach ($id in $o.Ids) { $script:SetupBox[$id].Checked = $false } }
        foreach ($oi in @($script:WizAns[$qi])) { foreach ($id in $q.Opts[$oi].Ids) { $script:SetupBox[$id].Checked = $true; $count++ } }
    }
    Show-SetupView $false
    Log "Guide complete: items selected according to your answers. Review the list and click INSTALL SELECTED."
}

$btnWizStart = New-Btn $pSu 'GUIDE (OPTIONAL)' 20 500 270 40 1
$btnSetup = New-Btn $pSu 'INSTALL SELECTED' 600 500 270 40 0
$btnWizBack = New-Btn $pSu 'BACK' 20 500 270 40 1
$btnWizExit = New-Btn $pSu 'EXIT GUIDE' 310 500 270 40 1
$btnWizNext = New-Btn $pSu 'NEXT' 600 500 270 40 0
$btnWizBack.Visible = $false; $btnWizExit.Visible = $false; $btnWizNext.Visible = $false

function Start-Guide($withTheme) {
    if ($withTheme) { $script:WizList = @($script:ThemeQ) + @($script:Questions) } else { $script:WizList = @($script:Questions) }
    $script:WizIdx = 0; $script:WizAns = @{}
    Show-SetupView $true
    Wiz-Render
}
$btnWizStart.Add_Click({ Start-Guide $false })
$btnWizExit.Add_Click({ Show-SetupView $false })
$btnWizBack.Add_Click({ Wiz-Store; if ($script:WizIdx -gt 0) { $script:WizIdx--; Wiz-Render } })
$btnWizNext.Add_Click({
    Wiz-Store
    if ($script:WizList[$script:WizIdx].Theme -and $script:WizAns.ContainsKey($script:WizIdx)) {
        $tkey = [string]@($script:Themes.Keys)[[int]@($script:WizAns[$script:WizIdx])[0]]
        if ($tkey -ne [string]$script:Config.Theme) {
            $script:Config.Theme = $tkey; $script:Config.PendingGuide = $true; Save-Config
            Restart-App
            return
        }
    }
    if ($script:WizIdx -lt $script:WizList.Count - 1) { $script:WizIdx++; Wiz-Render }
    else { Wiz-Finish }
})
$btnSetup.Add_Click({ try { Invoke-Setup } catch { Log "ERROR: $($_.Exception.Message)"; Set-Busy $false } })

# =========================================================
#  PAGE: CS2
# =========================================================
function Find-Cs2 {
    $cands = @()
    if ($script:Config.Cs2Path) { $cands += [string]$script:Config.Cs2Path }
    $steam = $null
    try { $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath } catch {}
    if (-not $steam) { try { $steam = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -ErrorAction Stop).InstallPath } catch {} }
    $libs = @()
    if ($steam) {
        $steam = ([string]$steam) -replace '/', '\'
        $libs += $steam
        $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
        if (Test-Path $vdf) {
            foreach ($ln in @(Get-Content $vdf -ErrorAction SilentlyContinue)) {
                if ($ln -match '"path"\s+"([^"]+)"') { $libs += ($Matches[1] -replace '\\\\', '\') }
            }
        }
    }
    foreach ($l in $libs) { $cands += (Join-Path $l 'steamapps\common\Counter-Strike Global Offensive') }
    foreach ($c in $cands) { if ($c -and (Test-Path (Join-Path $c 'game\bin\win64\cs2.exe'))) { return $c } }
    return ''
}
$script:Cs2Root = ''
function Get-Cs2Exe { if ($script:Cs2Root) { return (Join-Path $script:Cs2Root 'game\bin\win64\cs2.exe') } return '' }
function Get-Cs2Cfg { if ($script:Cs2Root) { return (Join-Path $script:Cs2Root 'game\csgo\cfg\autoexec.cfg') } return '' }

function Mod-Cs2Prio {
    Set-Reg 'HKLM' 'SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\cs2.exe\PerfOptions' 'CpuPriorityClass' 'DWord' 3
    Log '  cs2.exe now always launches with High priority'
}
function Mod-Cs2Gpu {
    $exe = Get-Cs2Exe
    if (-not $exe) { Log '  CS2 not found. Use LOCATE FOLDER.'; return }
    Set-Reg 'HKCU' 'Software\Microsoft\DirectX\UserGpuPreferences' $exe 'String' 'GpuPreference=2;'
    Log '  cs2.exe uses the high-performance GPU'
}
function Mod-Cs2Fso {
    $exe = Get-Cs2Exe
    if (-not $exe) { Log '  CS2 not found. Use LOCATE FOLDER.'; return }
    Set-Reg 'HKCU' 'Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers' $exe 'String' '~ DISABLEDXMAXIMIZEDWINDOWEDMODE'
    Log '  fullscreen optimizations disabled for cs2.exe'
}

$script:CvarDefs = @(
    @{ N = 'fps_max'; L = 'Max FPS'; D = '0 removes the limit. Use 0 or a value well above your monitor refresh rate.'; T = 'int'; Min = 0; Max = 1000; Def = '0'; Rec = '0'; C = 'Performance' },
    @{ N = 'fps_max_ui'; L = 'Max FPS in menus'; D = 'Limits FPS outside matches and spares the GPU.'; T = 'int'; Min = 30; Max = 1000; Def = '120'; Rec = '120'; C = 'Performance' },
    @{ N = 'cl_showfps'; L = 'Show FPS'; D = '0 off, 1 shows FPS in the screen corner.'; T = 'int'; Min = 0; Max = 3; Def = '0'; Rec = ''; C = 'Performance' },
    @{ N = 'rate'; L = 'Data rate (rate)'; D = 'How much data the server can send. Use the maximum.'; T = 'int'; Min = 64000; Max = 786432; Def = '786432'; Rec = '786432'; C = 'Network' },
    @{ N = 'mm_dedicated_search_maxping'; L = 'Max ping in search'; D = 'Ignores servers above this ping in matchmaking.'; T = 'int'; Min = 10; Max = 350; Def = '150'; Rec = ''; C = 'Network' },
    @{ N = 'cl_crosshairstyle'; L = 'Crosshair style'; D = '0 to 5. 4 is the classic static crosshair.'; T = 'int'; Min = 0; Max = 5; Def = '2'; Rec = '4'; C = 'Crosshair' },
    @{ N = 'cl_crosshairsize'; L = 'Crosshair size'; D = 'Line length.'; T = 'float'; Min = 0; Max = 10; Def = '5'; Rec = ''; C = 'Crosshair' },
    @{ N = 'cl_crosshairthickness'; L = 'Crosshair thickness'; D = 'Line thickness.'; T = 'float'; Min = 0; Max = 3; Def = '0.5'; Rec = ''; C = 'Crosshair' },
    @{ N = 'cl_crosshairgap'; L = 'Crosshair center gap'; D = 'Distance between the center and the lines.'; T = 'float'; Min = -5; Max = 5; Def = '0'; Rec = ''; C = 'Crosshair' },
    @{ N = 'cl_crosshaircolor'; L = 'Crosshair color'; D = '0 to 4 are preset colors. 5 uses the custom color.'; T = 'int'; Min = 0; Max = 5; Def = '1'; Rec = ''; C = 'Crosshair' },
    @{ N = 'cl_crosshairalpha'; L = 'Crosshair opacity'; D = '0 to 255.'; T = 'int'; Min = 0; Max = 255; Def = '255'; Rec = '255'; C = 'Crosshair' },
    @{ N = 'cl_crosshair_drawoutline'; L = 'Crosshair outline'; D = 'Draws a black outline, helps visibility.'; T = 'bool'; Def = '0'; Rec = '1'; C = 'Crosshair' },
    @{ N = 'cl_crosshairdot'; L = 'Center dot'; D = 'Turns on the dot in the middle of the crosshair.'; T = 'bool'; Def = '0'; Rec = '0'; C = 'Crosshair' },
    @{ N = 'cl_righthand'; L = 'Right-handed weapon'; D = 'Off puts the weapon in the left hand.'; T = 'bool'; Def = '1'; Rec = ''; C = 'Viewmodel' },
    @{ N = 'viewmodel_fov'; L = 'Viewmodel FOV'; D = 'Weapon field of view. 54 to 68.'; T = 'int'; Min = 54; Max = 68; Def = '60'; Rec = '68'; C = 'Viewmodel' },
    @{ N = 'viewmodel_offset_x'; L = 'Weapon position: sideways'; D = '-2 to 2.5.'; T = 'float'; Min = -2; Max = 2.5; Def = '1'; Rec = ''; C = 'Viewmodel' },
    @{ N = 'viewmodel_offset_y'; L = 'Weapon position: forward'; D = '-2 to 2.'; T = 'float'; Min = -2; Max = 2; Def = '1'; Rec = ''; C = 'Viewmodel' },
    @{ N = 'viewmodel_offset_z'; L = 'Weapon position: height'; D = '-2 to 2.'; T = 'float'; Min = -2; Max = 2; Def = '-1'; Rec = ''; C = 'Viewmodel' },
    @{ N = 'viewmodel_presetpos'; L = 'Weapon preset position'; D = '1 to 3. Shortcut for default positions.'; T = 'int'; Min = 1; Max = 3; Def = '1'; Rec = ''; C = 'Viewmodel' },
    @{ N = 'sensitivity'; L = 'Sensitivity'; D = 'Your in-game sensitivity.'; T = 'float'; Min = 0.01; Max = 20; Def = '1'; Rec = ''; C = 'Mouse' },
    @{ N = 'zoom_sensitivity_ratio'; L = 'Zoom sensitivity'; D = 'Multiplier when using a scope. 1 keeps it the same.'; T = 'float'; Min = 0; Max = 2; Def = '1'; Rec = '1'; C = 'Mouse' },
    @{ N = 'volume'; L = 'Master volume'; D = '0 to 1.'; T = 'float'; Min = 0; Max = 1; Def = '0.5'; Rec = ''; C = 'Audio' },
    @{ N = 'snd_headphone_eq'; L = 'Headphone equalization'; D = '0 soft, 1 natural, 2 crisp.'; T = 'int'; Min = 0; Max = 2; Def = '1'; Rec = ''; C = 'Audio' },
    @{ N = 'snd_menumusic_volume'; L = 'Menu music'; D = '0 mutes it.'; T = 'float'; Min = 0; Max = 1; Def = '0.5'; Rec = '0'; C = 'Audio' },
    @{ N = 'snd_mvp_volume'; L = 'MVP music'; D = '0 mutes it.'; T = 'float'; Min = 0; Max = 1; Def = '0.5'; Rec = '0'; C = 'Audio' },
    @{ N = 'snd_roundstart_volume'; L = 'Round start music'; D = '0 mutes it.'; T = 'float'; Min = 0; Max = 1; Def = '0.5'; Rec = '0'; C = 'Audio' },
    @{ N = 'snd_roundend_volume'; L = 'Round end music'; D = '0 mutes it.'; T = 'float'; Min = 0; Max = 1; Def = '0.5'; Rec = '0'; C = 'Audio' },
    @{ N = 'cl_radar_scale'; L = 'Radar map size'; D = '0.3 to 1. How much of the map shows on the radar.'; T = 'float'; Min = 0.3; Max = 1; Def = '0.7'; Rec = '0.4'; C = 'Interface' },
    @{ N = 'cl_hud_radar_scale'; L = 'On-screen radar size'; D = '0.8 to 1.3.'; T = 'float'; Min = 0.8; Max = 1.3; Def = '1'; Rec = ''; C = 'Interface' },
    @{ N = 'cl_radar_always_centered'; L = 'Radar always centered'; D = 'Off lets the radar show the whole map.'; T = 'bool'; Def = '0'; Rec = '0'; C = 'Interface' },
    @{ N = 'gameinstructor_enable'; L = 'Game hints'; D = 'Off removes beginner hints.'; T = 'bool'; Def = '1'; Rec = '0'; C = 'Interface' }
)

$pCs = New-Page 'cs2'
$script:Cs2Sub = New-Header $pCs ([string][char]0xE7FC) 'CS2' 'Game settings and autoexec editor'
$script:Cs2Tabs = @{}
$tabx = 20
foreach ($tn in @('Game settings', 'Autoexec')) {
    $tw = 40 + 10 * $tn.Length
    $tcc = New-Object TbChip
    $tcc.Text = $tn
    $tcc.Tag = $tn
    $tcc.Location = New-Object System.Drawing.Point($tabx, 102)
    $tcc.Size = New-Object System.Drawing.Size($tw, 34)
    $tcc.BackColor = $cBg
    $pCs.Controls.Add($tcc)
    $script:Cs2Tabs[$tn] = $tcc
    $tcc.Add_Click({ param($s, $e) Show-Cs2View ([string]$s.Tag) })
    $tabx += $tw + 10
}
$btnCs2Find = New-Btn $pCs 'LOCATE FOLDER' 650 100 220 38 1

# ---- view A: game settings ----
$script:Cs2Scroll = New-Object TbScroll
$script:Cs2Scroll.Location = New-Object System.Drawing.Point(20, 148)
$script:Cs2Scroll.Size = New-Object System.Drawing.Size(850, 344)
$script:Cs2Scroll.BackColor = $cBg
$pCs.Controls.Add($script:Cs2Scroll)
foreach ($m in $Cs2Modules) { Build-ModCard $m $script:Cs2Scroll.Inner }
Flow-Grid $Cs2Modules $script:Cs2Scroll
foreach ($m in $Cs2Modules) { Set-CardState $m }
$btnCs2Apply = New-Btn $pCs 'APPLY CS2 TWEAKS' 20 500 270 40 0
$btnCs2Rev = New-Btn $pCs 'REVERT ALL' 600 500 270 40 2

# ---- view B: autoexec editor ----
function New-Input($parent, $x, $y, $w, $text) {
    $t = New-Object System.Windows.Forms.TextBox
    $t.Text = $text
    $t.Location = New-Object System.Drawing.Point($x, $y)
    $t.Size = New-Object System.Drawing.Size($w, 24)
    $t.Font = Mk-Font 10
    $parent.Controls.Add($t)
    $t.BorderStyle = 'FixedSingle'
    $t.BackColor = $cCard2
    $t.ForeColor = $cGreen
    return $t
}
$script:AutoScroll = New-Object TbScroll
$script:AutoScroll.Location = New-Object System.Drawing.Point(20, 148)
$script:AutoScroll.Size = New-Object System.Drawing.Size(850, 344)
$script:AutoScroll.BackColor = $cBg
$script:AutoScroll.Visible = $false
$pCs.Controls.Add($script:AutoScroll)
$script:AuRows = @{}
$script:AuSeq = @()
$lastC = ''
foreach ($d in $script:CvarDefs) {
    if ($d.C -ne $lastC) {
        $lastC = $d.C
        $hl = New-Label $script:AutoScroll.Inner $d.C.ToUpper() 4 0 800 18 $fB $cDim
        $script:AuSeq += @{ H = $hl }
    }
    $rc = New-Card $script:AutoScroll.Inner 0 0 500 52 $cCard $cBorder 10
    $inc = New-Toggle $rc 12 13 $false
    $nl = New-Label $rc $d.L 84 7 280 20 $fB $cGreen
    $dl = New-Label $rc $d.D 84 29 380 16 $fSm $cMuted
    if ($d.T -eq 'bool') { $val = New-Toggle $rc 420 13 ($d.Def -eq '1') } else { $val = New-Input $rc 380 13 100 $d.Def }
    $row = @{ D = $d; Inc = $inc; Val = $val; Name = $nl; Desc = $dl }
    $script:AuRows[$d.N] = $row
    $script:AuSeq += @{ C = $rc; R = $row }
}
$script:AuHeadX = New-Label $script:AutoScroll.Inner 'OTHER LINES FROM YOUR AUTOEXEC (ADVANCED)' 4 0 800 18 $fB $cDim
$script:AuExtra = New-Object System.Windows.Forms.TextBox
$script:AuExtra.Multiline = $true
$script:AuExtra.ScrollBars = 'Vertical'
$script:AuExtra.Font = Mk-Font 9.5
$script:AuExtra.Size = New-Object System.Drawing.Size(600, 150)
$script:AutoScroll.Inner.Controls.Add($script:AuExtra)
$script:AuExtra.BorderStyle = 'FixedSingle'
$script:AuExtra.BackColor = $cCard2
$script:AuExtra.ForeColor = $cGreen

function Flow-Auto {
    $script:AutoScroll.SetContentHeight(0)
    $iw = $script:AutoScroll.Inner.Width
    $cols = [int][math]::Max(1, [math]::Floor(($iw + 12) / 524))
    $cw = [int][math]::Floor(($iw - 12 * ($cols - 1)) / $cols)
    $y = 0; $col = 0
    foreach ($e in $script:AuSeq) {
        if ($e.H) {
            if ($col -ne 0) { $y += 58; $col = 0 }
            $e.H.Location = New-Object System.Drawing.Point(4, ($y + 6))
            $e.H.Width = $iw - 8
            $y += 30
        } else {
            $e.C.Width = $cw
            $r = $e.R
            $r.Name.Width = [int][math]::Max(80, $cw - 84 - 150)
            $r.Desc.Width = [int][math]::Max(80, $cw - 84 - 16)
            if ($r.D.T -eq 'bool') { $r.Val.Left = $cw - 70 } else { $r.Val.Left = $cw - 130; $r.Val.Width = 110 }
            $e.C.Location = New-Object System.Drawing.Point((($cw + 12) * $col), $y)
            if ($col -lt $cols - 1) { $col++ } else { $col = 0; $y += 58 }
        }
    }
    if ($col -ne 0) { $y += 58 }
    $script:AuHeadX.Location = New-Object System.Drawing.Point(4, ($y + 6))
    $script:AuHeadX.Width = $iw - 8
    $script:AuExtra.Location = New-Object System.Drawing.Point(4, ($y + 32))
    $script:AuExtra.Width = $iw - 8
    $script:AutoScroll.SetContentHeight($y + 32 + 150 + 12)
}

function Read-Autoexec {
    foreach ($k in $script:AuRows.Keys) {
        $r = $script:AuRows[$k]
        $r.Inc.Checked = $false
        if ($r.D.T -eq 'bool') { $r.Val.Checked = ($r.D.Def -eq '1') } else { $r.Val.Text = $r.D.Def }
    }
    $extra = @()
    $f = Get-Cs2Cfg
    if ($f -and (Test-Path $f)) {
        foreach ($ln in @(Get-Content $f -ErrorAction SilentlyContinue)) {
            $t = $ln.Trim()
            if ($t -eq '') { continue }
            if ($t -like '// autoexec gerado pelo TutuBoost*' -or $t -like '// autoexec generated by TutuBoost*') { continue }
            if ($t -match '^([A-Za-z0-9_\.]+)\s+"?([^"\s/]*)"?\s*(//.*)?$' -and $script:AuRows.ContainsKey($Matches[1].ToLower())) {
                $r = $script:AuRows[$Matches[1].ToLower()]
                $r.Inc.Checked = $true
                if ($r.D.T -eq 'bool') { $r.Val.Checked = ($Matches[2] -ne '0' -and $Matches[2] -ne '') } else { $r.Val.Text = $Matches[2] }
            } else { $extra += $t }
        }
    }
    $script:AuExtra.Text = ($extra -join "`r`n")
}

function Save-Autoexec {
    $f = Get-Cs2Cfg
    if (-not $f) { Log 'CS2 not found. Use LOCATE FOLDER.'; return }
    $dir = Split-Path -Parent $f
    if (-not (Test-Path $dir)) { Log "Config folder does not exist: $dir"; return }
    $bk = Join-Path $BackupDir 'autoexec_original.cfg'
    $flag = Join-Path $BackupDir 'autoexec_nao_existia.flag'
    if (-not (Test-Path $bk) -and -not (Test-Path $flag)) {
        if (Test-Path $f) { Copy-Item $f $bk -Force } else { Set-Content -Path $flag -Value 'did not exist' }
    }
    $lines = @('// autoexec generated by TutuBoost')
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    foreach ($d in $script:CvarDefs) {
        $r = $script:AuRows[$d.N]
        if (-not $r.Inc.Checked) { continue }
        if ($d.T -eq 'bool') { $v = '0'; if ($r.Val.Checked) { $v = '1' } }
        else {
            $num = 0.0
            $txt = $r.Val.Text.Trim().Replace(',', '.')
            if (-not [double]::TryParse($txt, [System.Globalization.NumberStyles]::Float, $inv, [ref]$num)) { Log "  ignored (invalid value): $($d.N) = $($r.Val.Text)"; continue }
            if ($num -lt $d.Min) { $num = [double]$d.Min }
            if ($num -gt $d.Max) { $num = [double]$d.Max }
            if ($d.T -eq 'int') { $v = ([int][math]::Round($num)).ToString($inv) } else { $v = $num.ToString('0.####', $inv) }
        }
        $lines += ('{0} "{1}"' -f $d.N, $v)
    }
    foreach ($x in ($script:AuExtra.Text -split "`r?`n")) { if ($x.Trim() -ne '') { $lines += $x.Trim() } }
    [System.IO.File]::WriteAllLines($f, [string[]]$lines, (New-Object System.Text.UTF8Encoding $false))
    Log "[ OK ] autoexec.cfg saved ($($lines.Count - 1) line(s)): $f"
}

function Restore-Autoexec {
    $f = Get-Cs2Cfg
    if (-not $f) { Log 'CS2 not found.'; return }
    $bk = Join-Path $BackupDir 'autoexec_original.cfg'
    $flag = Join-Path $BackupDir 'autoexec_nao_existia.flag'
    if (Test-Path $bk) { Copy-Item $bk $f -Force; Log '[ OK ] original autoexec restored.' }
    elseif (Test-Path $flag) { if (Test-Path $f) { Remove-Item $f -Force }; Log '[ OK ] autoexec removed (did not exist before TutuBoost).' }
    else { Log 'No autoexec backup found: TutuBoost has not saved anything yet.' }
    Read-Autoexec
}

function Refresh-Cs2 {
    $script:Cs2Root = Find-Cs2
    if ($script:Cs2Root) { $script:Cs2Sub.Text = "CS2 found at: $($script:Cs2Root)" }
    else { $script:Cs2Sub.Text = 'CS2 not found. Use LOCATE FOLDER.' }
    Read-Autoexec
}

function Show-Cs2View($name) {
    $a = ($name -eq 'Autoexec')
    $script:Cs2Scroll.Visible = -not $a
    $script:AutoScroll.Visible = $a
    $btnCs2Apply.Visible = -not $a; $btnCs2Rev.Visible = -not $a
    $btnAuRec.Visible = $a; $btnAuRest.Visible = $a; $btnAuCopy.Visible = $a; $btnAuSave.Visible = $a
    foreach ($k in $script:Cs2Tabs.Keys) { $script:Cs2Tabs[$k].Selected = ($k -eq $name) }
}

$btnAuRec = New-Btn $pCs 'SELECT RECOMMENDED' 20 500 202 40 1
$btnAuRest = New-Btn $pCs 'RESTORE ORIGINAL' 236 500 202 40 1
$btnAuCopy = New-Btn $pCs 'COPY +exec' 452 500 202 40 1
$btnAuSave = New-Btn $pCs 'SAVE AUTOEXEC' 668 500 202 40 0
$btnAuRec.Visible = $false; $btnAuRest.Visible = $false; $btnAuCopy.Visible = $false; $btnAuSave.Visible = $false

$btnCs2Apply.Add_Click({ try { Invoke-Optimize $Cs2Modules $true } catch { Log "ERROR: $($_.Exception.Message)"; Set-Busy $false } })
$btnCs2Rev.Add_Click({ try { Invoke-Revert } catch { Log "ERROR: $($_.Exception.Message)"; Set-Busy $false } })
$btnAuSave.Add_Click({ try { Save-Autoexec } catch { Log "ERROR: $($_.Exception.Message)" } })
$btnAuRest.Add_Click({ try { Restore-Autoexec } catch { Log "ERROR: $($_.Exception.Message)" } })
$btnAuRec.Add_Click({
    foreach ($d in $script:CvarDefs) {
        if ($d.Rec -eq '') { continue }
        $r = $script:AuRows[$d.N]
        $r.Inc.Checked = $true
        if ($d.T -eq 'bool') { $r.Val.Checked = ($d.Rec -eq '1') } else { $r.Val.Text = $d.Rec }
    }
    Log 'Recommended selected. Review and click SAVE AUTOEXEC.'
})
$btnAuCopy.Add_Click({
    try { [System.Windows.Forms.Clipboard]::SetText('+exec autoexec'); Log 'Copied: +exec autoexec. Paste it into the CS2 launch options in Steam if the file does not load by itself.' } catch { Log 'Could not copy.' }
})
$btnCs2Find.Add_Click({
    $fb = New-Object System.Windows.Forms.FolderBrowserDialog
    $fb.Description = 'Choose the "Counter-Strike Global Offensive" folder (the one that contains the game folder)'
    if ($fb.ShowDialog() -eq 'OK') {
        if (Test-Path (Join-Path $fb.SelectedPath 'game\bin\win64\cs2.exe')) {
            $script:Config.Cs2Path = $fb.SelectedPath; Save-Config; Refresh-Cs2
        } else { Log 'That folder does not contain game\\bin\\win64\\cs2.exe. Choose the Counter-Strike Global Offensive folder.' }
    }
})
Show-Cs2View 'Game settings'
Refresh-Cs2
Flow-Auto

# =========================================================
#  PAGE: DIAGNOSTICS
# =========================================================
$pDg = New-Page 'diag'
[void](New-Header $pDg ([string][char]0xE721) 'Diagnostics' 'Checks HPET, RAM, power, security and input. Saves the report to the Desktop.')
$btnDiag = New-Btn $pDg 'RUN DIAGNOSTICS' 20 100 300 40 0
$dgCard = New-Card $pDg 20 152 850 388 $cCard $cBorder 12
$script:DiagBox = New-Object System.Windows.Forms.TextBox
$script:DiagBox.Multiline = $true
$script:DiagBox.ReadOnly = $true
$script:DiagBox.ScrollBars = 'Vertical'
$script:DiagBox.BorderStyle = 'None'
$script:DiagBox.Font = Mk-Font 9.5
$script:DiagBox.ForeColor = $cGreen
$script:DiagBox.Location = New-Object System.Drawing.Point(12, 12)
$script:DiagBox.Size = New-Object System.Drawing.Size(824, 364)
$dgCard.Controls.Add($script:DiagBox)
$btnDiag.Add_Click({ try { Invoke-Diag } catch { Log "ERROR: $($_.Exception.Message)"; Set-Busy $false } })

# =========================================================
#  GENERAL EVENTS
# =========================================================
$Form.Add_MouseWheel({
    param($s, $e)
    if ($script:Pages['tweaks'].Visible) { $script:ModScroll.ScrollBy(-[int]($e.Delta / 2)) }
    elseif ($script:Pages['exp'].Visible) { $script:ExpScroll.ScrollBy(-[int]($e.Delta / 2)) }
    elseif ($script:Pages['cs2'].Visible) { if ($script:AutoScroll.Visible) { $script:AutoScroll.ScrollBy(-[int]($e.Delta / 2)) } else { $script:Cs2Scroll.ScrollBy(-[int]($e.Delta / 2)) } }
    elseif ($script:Pages['apps'].Visible) { $script:AppScroll.ScrollBy(-[int]($e.Delta / 2)) }
    elseif ($script:Pages['setup'].Visible -and $script:SetScroll.Visible) { $script:SetScroll.ScrollBy(-[int]($e.Delta / 2)) }
})
$script:SearchBox.Add_MouseWheel({
    param($s, $e)
    if ($script:Pages['tweaks'].Visible) { $script:ModScroll.ScrollBy(-[int]($e.Delta / 2)) }
})
$Form.Add_FormClosing({ $Timer.Stop() })
# =========================================================
#  PAGE: SETTINGS
# =========================================================
$pCf = New-Page 'config'
[void](New-Header $pCf ([string][char]0xE713) 'Settings' 'Theme, guide and TutuBoost files')
$cfT = New-Card $pCf 20 100 850 130 $cCard $cBorder 12
[void](New-Label $cfT 'THEME' 20 14 300 18 $fB $cDim)
[void](New-Label $cfT 'When you switch, TutuBoost reopens by itself with the new colors.' 20 36 780 16 $fSm $cMuted)
$tx = 20
foreach ($tk in $script:Themes.Keys) {
    $tt = $script:Themes[$tk]
    $tw = 50 + 11 * $tt.Name.Length
    $tc = New-Object TbChip
    $tc.Text = $tt.Name
    $tc.Tag = $tk
    $tc.Accent = $tt.Acc
    $tc.Location = New-Object System.Drawing.Point($tx, 70)
    $tc.Size = New-Object System.Drawing.Size($tw, 40)
    $tc.BackColor = $cfT.Fill
    $tc.Selected = ($tk -eq [string]$script:Config.Theme)
    $cfT.Controls.Add($tc)
    $tc.Add_Click({
        param($s, $e)
        if ([string]$s.Tag -eq [string]$script:Config.Theme) { return }
        if (Ask "Switch the theme to $($script:Themes[[string]$s.Tag].Name)? TutuBoost will reopen.") {
            $script:Config.Theme = [string]$s.Tag
            Save-Config
            Restart-App
        }
    })
    $tx += $tw + 12
}
$cfG = New-Card $pCf 20 242 850 84 $cCard $cBorder 12
[void](New-Label $cfG 'SETUP GUIDE' 20 14 400 18 $fB $cDim)
[void](New-Label $cfG 'Answer a few questions and TutuBoost selects the apps to install.' 20 38 520 32 $fSm $cMuted)
$btnCfGuide = New-Btn $cfG 'REDO THE GUIDE' 560 22 270 40 1
$btnCfGuide.Add_Click({ Show-Page 'setup'; Start-Guide $false })
$cfF = New-Card $pCf 20 338 850 84 $cCard $cBorder 12
[void](New-Label $cfF 'BACKUPS AND LOGS' 20 14 400 18 $fB $cDim)
[void](New-Label $cfF 'Original values saved before each tweak, used by REVERT ALL.' 20 38 520 32 $fSm $cMuted)
$btnCfDir = New-Btn $cfF 'OPEN FOLDER' 560 22 270 40 1
$btnCfDir.Add_Click({ try { Start-Process explorer.exe -ArgumentList "`"$BackupDir`"" } catch { Log "ERROR: $($_.Exception.Message)" } })
[void](New-Label $pCf 'TutuBoost V1  //  free and open source' 22 438 700 18 $fSm $cMuted)

# ---- resizable window: hand-computed layout ----
$script:Orig = @{}
$script:LayBusy = $false
function Layout-All {
    if ($script:LayBusy) { return }
    $fw = $Form.ClientSize.Width; $fh = $Form.ClientSize.Height
    if ($fw -lt 400 -or $fh -lt 400) { return }
    $script:LayBusy = $true
    $Form.SuspendLayout()
    try {
        $Side.Height = $fh
        $Main.SetBounds(210, 0, ($fw - 210), $fh)
        $W = $Main.Width; $H = $Main.Height
        $lgl.Top = $H - 148
        $logCard.SetBounds(20, ($H - 132), ($W - 40), 122)
        $script:LogBox.Size = New-Object System.Drawing.Size(($logCard.Width - 20), 106)
        $PH = $H - 152
        foreach ($k in @($script:Pages.Keys)) {
            $pg = $script:Pages[$k]
            $pg.SetBounds(0, 0, $W, $PH)
            if ($k -eq 'dash') { continue }
            foreach ($c in $pg.Controls) {
                $cid = $c.GetHashCode()
                if (-not $script:Orig.ContainsKey($cid)) { $script:Orig[$cid] = @($c.Left, $c.Top, $c.Width, $c.Height) }
                $o = $script:Orig[$cid]
                if ($c -is [TbButton]) {
                    if ($o[1] -ge 400) {
                        $c.Top = $PH - (548 - $o[1])
                        if ($o[0] -ge 500) { $c.Left = $W - (890 - $o[0]) }
                    } elseif ($o[0] -ge 600) { $c.Left = $W - (890 - $o[0]) }
                } elseif ($o[2] -ge 840) {
                    $c.Width = $W - 40
                    if (($c -is [TbScroll]) -or (($o[1] + $o[3]) -ge 440)) {
                        $c.Height = [int][math]::Max(60, ($PH - $o[1] - (548 - $o[1] - $o[3])))
                    }
                } elseif ($o[0] -ge 700 -and $o[1] -le 60) {
                    $c.Left = $W - (890 - $o[0])
                }
            }
        }
        # inner content
        $script:DiagBox.Size = New-Object System.Drawing.Size(($dgCard.Width - 24), ($dgCard.Height - 24))
        $script:SearchBox.Width = $sc.Width - 60
        $script:WizCard.Size = $script:SetWiz.Size
        $script:WbTrack.SetBounds(28, ($script:WizCard.Height - 30), ($script:WizCard.Width - 56), 8)
        $script:WizBar.Top = $script:WbTrack.Top
        $btnCfGuide.Left = $cfG.Width - 290
        $btnCfDir.Left = $cfF.Width - 290
        # dashboard
        $dw = $W - 40
        if ($Hero.Width -ne $dw) {
            $Hero.Width = $dw
            $Hero.Region = New-Object System.Drawing.Region([TbGfx]::Round(0, 0, $dw, $RainH, 14))
            $btnHero.Left = $dw - 200
        }
        $iwd = [int][math]::Max(160, [math]::Floor(($dw - 42) / 4))
        for ($i = 0; $i -lt $script:InfoCards.Count; $i++) {
            $ic = $script:InfoCards[$i]
            $ic.K.SetBounds((20 + $i * ($iwd + 14)), 134, $iwd, 98)
            $ic.A.Width = $iwd - 68; $ic.B.Width = $iwd - 68; $ic.C.Width = $iwd - 26
        }
        $w2 = [int][math]::Floor(($dw - 16) / 2)
        $h2 = [int][math]::Max(244, ($PH - 246 - 58))
        $osCard.SetBounds(20, 246, $w2, $h2)
        $stCard.SetBounds((20 + $w2 + 16), 246, ($dw - $w2 - 16), $h2)
        foreach ($v in $script:OsVals) { $v.Width = $osCard.Width - 168 }
        foreach ($l in $script:OsLines) { $l.Width = $osCard.Width - 36 }
        foreach ($r in $script:StatCards) { $r.Width = $stCard.Width - 32 }
        # grids
        Apply-Filter
        Flow-Grid $ExpModules $script:ExpScroll
        Flow-Grid $Cs2Modules $script:Cs2Scroll
        Flow-Auto
        Flow-Setup
        Flow-Apps
    } finally {
        $Form.ResumeLayout($true)
        $script:LayBusy = $false
    }
}
$Form.Add_Resize({ try { Layout-All } catch {} })
$Form.MinimumSize = New-Object System.Drawing.Size(1116, 739)
Layout-All

$Form.Add_Shown({ try { [TBNative]::DarkTitle($Form.Handle, (Bgr $cBg), (Bgr $cGreen), (Bgr $cBorder), $(if ($script:IsLight) { 0 } else { 1 })) } catch {} })

Update-Dash
$script:StartGuide = ''
if (-not $script:Config.FirstRunDone) { $script:Config.FirstRunDone = $true; Save-Config; $script:StartGuide = 'first' }
elseif ($script:Config.PendingGuide) { $script:Config.PendingGuide = $false; Save-Config; $script:StartGuide = 'resume' }
if ($script:StartGuide -eq 'first') { Show-Page 'setup'; Start-Guide $true }
elseif ($script:StartGuide -eq 'resume') { Show-Page 'setup'; Start-Guide $false }
else { Show-Page 'dash' }
Log 'TutuBoost ready. Choose the tweaks in Optimizations and click OPTIMIZE ALL - the original is saved for REVERT ALL.'
[void]$Form.ShowDialog()
