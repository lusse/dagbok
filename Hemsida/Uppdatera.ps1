# Bygger data.js till dagbokshemsidan från Dagbok-addonets sparade data.
# WoW skriver den sparade datan när du loggar ut eller kör /reload.

param(
    [string]$WowPath # t.ex. C:\Spel\World of Warcraft\_forever_
)

$ErrorActionPreference = "Stop"
$site = $PSScriptRoot
$imageDir = Join-Path $site "bilder"
$invariant = [Globalization.CultureInfo]::InvariantCulture

if (-not $WowPath) {
    $install = (Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft" -ErrorAction SilentlyContinue).InstallPath
    $WowPath = if ($install) { $install.TrimEnd('\') } else { "C:\Spel\World of Warcraft\_forever_" }
}

Add-Type -AssemblyName System.Drawing
Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

// Läser WoW:s SavedVariables (en delmängd av Lua) och skriver JSON.
public class DagbokLua {
    string s;
    int i;

    DagbokLua(string source) { s = source; }

    public static Dictionary<string, object> ParseAssignments(string source) {
        var parser = new DagbokLua(source);
        var result = new Dictionary<string, object>();
        while (true) {
            parser.Skip();
            if (parser.i >= parser.s.Length) break;
            string name = parser.Ident();
            parser.Expect('=');
            result[name] = parser.Value();
        }
        return result;
    }

    void Skip() {
        while (i < s.Length) {
            if (char.IsWhiteSpace(s[i])) i++;
            else if (s[i] == '-' && i + 1 < s.Length && s[i + 1] == '-') { while (i < s.Length && s[i] != '\n') i++; }
            else break;
        }
    }

    void Expect(char c) {
        Skip();
        if (i >= s.Length || s[i] != c) throw new Exception("Väntade '" + c + "' vid tecken " + i);
        i++;
    }

    string Ident() {
        Skip();
        int start = i;
        while (i < s.Length && (char.IsLetterOrDigit(s[i]) || s[i] == '_')) i++;
        if (start == i) throw new Exception("Väntade ett namn vid tecken " + i);
        return s.Substring(start, i - start);
    }

    object Value() {
        Skip();
        char c = s[i];
        if (c == '{') return Table();
        if (c == '"' || c == '\'') return Str();
        if (c == '-' || c == '.' || char.IsDigit(c)) return Num();
        string id = Ident();
        if (id == "true") return true;
        if (id == "false") return false;
        if (id == "nil") return null;
        throw new Exception("Okänt värde '" + id + "' vid tecken " + i);
    }

    string Str() {
        char quote = s[i++];
        var sb = new StringBuilder();
        while (s[i] != quote) {
            char c = s[i++];
            if (c != '\\') { sb.Append(c); continue; }
            char e = s[i++];
            switch (e) {
                case 'n': sb.Append('\n'); break;
                case 't': sb.Append('\t'); break;
                case 'r': sb.Append('\r'); break;
                case '\n': sb.Append('\n'); break;
                default:
                    if (char.IsDigit(e)) {
                        int n = e - '0';
                        for (int k = 0; k < 2 && char.IsDigit(s[i]); k++) n = n * 10 + (s[i++] - '0');
                        sb.Append((char)n);
                    } else {
                        sb.Append(e);
                    }
                    break;
            }
        }
        i++;
        return sb.ToString();
    }

    object Num() {
        int start = i;
        if (s[i] == '-') i++;
        while (i < s.Length && (char.IsLetterOrDigit(s[i]) || s[i] == '.' ||
               ((s[i] == '-' || s[i] == '+') && (s[i - 1] == 'e' || s[i - 1] == 'E')))) i++;
        string text = s.Substring(start, i - start);
        double d;
        if (double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out d)) return d;
        if (text.Contains("inf")) return text.StartsWith("-") ? double.NegativeInfinity : double.PositiveInfinity;
        return double.NaN;
    }

    object Table() {
        i++;
        var pairs = new List<KeyValuePair<object, object>>();
        int nextIndex = 1;
        while (true) {
            Skip();
            if (s[i] == '}') { i++; break; }
            object key, value;
            if (s[i] == '[') {
                i++;
                key = Value();
                Expect(']');
                Expect('=');
                value = Value();
            } else if (char.IsLetter(s[i]) || s[i] == '_') {
                int save = i;
                string id = Ident();
                Skip();
                if (s[i] == '=') { i++; key = id; value = Value(); }
                else { i = save; key = (double)nextIndex++; value = Value(); }
            } else {
                key = (double)nextIndex++;
                value = Value();
            }
            if (value != null) pairs.Add(new KeyValuePair<object, object>(key, value));
            Skip();
            if (s[i] == ',' || s[i] == ';') i++;
        }
        return Normalize(pairs);
    }

    // Tabeller med nycklarna 1..n blir listor, allt annat blir objekt
    static object Normalize(List<KeyValuePair<object, object>> pairs) {
        bool isList = pairs.Count > 0;
        var byIndex = new SortedDictionary<int, object>();
        foreach (var pair in pairs) {
            if (!(pair.Key is double)) { isList = false; break; }
            double d = (double)pair.Key;
            if (d < 1 || d != Math.Floor(d) || byIndex.ContainsKey((int)d)) { isList = false; break; }
            byIndex[(int)d] = pair.Value;
        }
        if (isList) {
            int expected = 1;
            foreach (int k in byIndex.Keys) { if (k != expected++) { isList = false; break; } }
        }
        if (isList) return new List<object>(byIndex.Values);

        var dict = new Dictionary<string, object>();
        foreach (var pair in pairs) {
            string key = pair.Key is double ? ((double)pair.Key).ToString("R", CultureInfo.InvariantCulture) : pair.Key.ToString();
            dict[key] = pair.Value;
        }
        return dict;
    }

    public static string ToJson(object value) {
        var sb = new StringBuilder();
        Write(sb, value);
        return sb.ToString();
    }

    static void Write(StringBuilder sb, object v) {
        // PowerShell slår ibland in värden i PSObject
        while (v != null && v.GetType().FullName == "System.Management.Automation.PSObject") {
            v = v.GetType().GetProperty("BaseObject").GetValue(v, null);
        }
        if (v == null) { sb.Append("null"); return; }
        if (v is bool) { sb.Append((bool)v ? "true" : "false"); return; }
        if (v is double || v is int || v is long) {
            double d = Convert.ToDouble(v, CultureInfo.InvariantCulture);
            sb.Append(double.IsNaN(d) || double.IsInfinity(d) ? "null" : d.ToString("R", CultureInfo.InvariantCulture));
            return;
        }
        if (v is string) { WriteString(sb, (string)v); return; }
        var dict = v as System.Collections.IDictionary;
        if (dict != null) {
            sb.Append('{');
            bool first = true;
            foreach (System.Collections.DictionaryEntry entry in dict) {
                if (!first) sb.Append(',');
                first = false;
                WriteString(sb, entry.Key.ToString());
                sb.Append(':');
                Write(sb, entry.Value);
            }
            sb.Append('}');
            return;
        }
        var list = v as System.Collections.IEnumerable;
        if (list != null) {
            sb.Append('[');
            bool first = true;
            foreach (object item in list) {
                if (!first) sb.Append(',');
                first = false;
                Write(sb, item);
            }
            sb.Append(']');
            return;
        }
        WriteString(sb, v.ToString());
    }

    static void WriteString(StringBuilder sb, string str) {
        sb.Append('"');
        foreach (char c in str) {
            switch (c) {
                case '"': sb.Append("\\\""); break;
                case '\\': sb.Append("\\\\"); break;
                case '\n': sb.Append("\\n"); break;
                case '\r': sb.Append("\\r"); break;
                case '\t': sb.Append("\\t"); break;
                default:
                    if (c < 0x20 || c == '<' || c == '\u2028' || c == '\u2029') sb.AppendFormat("\\u{0:x4}", (int)c);
                    else sb.Append(c);
                    break;
            }
        }
        sb.Append('"');
    }
}
'@

function Get-ScreenshotTime([string]$name) {
    if ($name -match '^WoWScrnShot_(\d{6})_(\d{6})') {
        return [datetime]::ParseExact($matches[1] + $matches[2], "MMddyyHHmmss", $invariant)
    }
    if ($name -match '^Dagbok_(\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2})') {
        return [datetime]::ParseExact($matches[1], "yyyy-MM-dd_HH-mm-ss", $invariant)
    }
    return $null
}

function Convert-Image($source, $target) {
    $image = [System.Drawing.Image]::FromFile($source)
    try {
        $scale = [Math]::Min(1.0, 1920 / $image.Width)
        $width = [int]($image.Width * $scale)
        $height = [int]($image.Height * $scale)
        $bitmap = New-Object System.Drawing.Bitmap $width, $height
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.DrawImage($image, 0, 0, $width, $height)
        $codec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq "image/jpeg" }
        $params = New-Object System.Drawing.Imaging.EncoderParameters 1
        $params.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), 85L
        $bitmap.Save($target, $codec, $params)
        $graphics.Dispose()
        $bitmap.Dispose()
    } finally {
        $image.Dispose()
    }
}

# Kopierar en förminskad JPG till hemsidans bildmapp och returnerar den relativa sökvägen
function Publish-Image($shot) {
    $name = [IO.Path]::GetFileNameWithoutExtension($shot.File.Name) + ".jpg"
    $target = Join-Path $imageDir $name
    if (-not (Test-Path $target)) { Convert-Image $shot.File.FullName $target }
    return "bilder/$name"
}

function ConvertTo-Unix([datetime]$time) {
    return [double]([DateTimeOffset]$time).ToUnixTimeSeconds()
}

New-Item -ItemType Directory -Force $imageDir | Out-Null

# Alla skärmdumpar med tidpunkt, så att dagbokens filnamn kan matchas även om de skiljer en sekund
$shots = New-Object System.Collections.Generic.List[object]
$shotDir = Join-Path $WowPath "Screenshots"
if (Test-Path $shotDir) {
    foreach ($file in Get-ChildItem $shotDir -File) {
        $time = Get-ScreenshotTime $file.Name
        if ($time) { $shots.Add([pscustomobject]@{ File = $file; Time = $time; Used = $false }) }
    }
}

function Find-Screenshot([string]$name) {
    $time = Get-ScreenshotTime $name
    if (-not $time) { return $null }
    $best = $null
    foreach ($shot in $shots) {
        $diff = [Math]::Abs(($shot.Time - $time).TotalSeconds)
        if ($diff -le 5 -and (-not $best -or $diff -lt $best.Diff)) {
            $best = [pscustomobject]@{ Shot = $shot; Diff = $diff }
        }
    }
    if ($best) { return $best.Shot }
    return $null
}

$characters = New-Object System.Collections.Generic.List[object]
$accountDir = Join-Path $WowPath "WTF\Account"
$files = Get-ChildItem $accountDir -Recurse -Filter "Dagbok.lua" | Where-Object { $_.Directory.Name -eq "SavedVariables" }

foreach ($file in $files) {
    $text = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8)
    $vars = [DagbokLua]::ParseAssignments($text)
    if (-not $vars.ContainsKey("DagbokDB")) { continue }
    $db = $vars["DagbokDB"]
    $db["folder"] = $file.Directory.Parent.Name

    $entries = $db["entries"]
    if ($entries -is [System.Collections.IList]) {
        foreach ($entry in $entries) {
            if (-not $entry.ContainsKey("screenshot")) { continue }
            $shot = Find-Screenshot $entry["screenshot"]
            if ($shot) {
                $entry["image"] = Publish-Image $shot
                $shot.Used = $true
            }
        }
    }
    $characters.Add($db)
    Write-Host "Läste dagboken för $($db["folder"])"
}

# Bilder du tagit själv kopplas till den karaktär som spelade vid tillfället
foreach ($db in $characters) {
    $extras = New-Object System.Collections.Generic.List[object]
    $sessions = @()
    if ($db["sessions"] -is [System.Collections.IList]) { $sessions = $db["sessions"] }
    $entryTimes = @()
    if ($db["entries"] -is [System.Collections.IList]) { $entryTimes = @($db["entries"] | ForEach-Object { $_["time"] }) }

    foreach ($shot in $shots) {
        if ($shot.Used) { continue }
        $unix = ConvertTo-Unix $shot.Time
        $belongs = $false
        foreach ($session in $sessions) {
            $finish = if ($session.ContainsKey("finish")) { $session["finish"] } else { $session["start"] + 12 * 3600 }
            if ($unix -ge $session["start"] -and $unix -le $finish) { $belongs = $true; break }
        }
        if (-not $belongs -and $characters.Count -eq 1 -and $entryTimes.Count -gt 0) {
            $first = ($entryTimes | Measure-Object -Minimum).Minimum
            $last = ($entryTimes | Measure-Object -Maximum).Maximum
            $belongs = $unix -ge $first -and $unix -le $last + 3 * 3600
        }
        if ($belongs) {
            $extra = New-Object 'System.Collections.Generic.Dictionary[string,object]'
            $extra["time"] = $unix
            $extra["image"] = Publish-Image $shot
            $extras.Add($extra)
            $shot.Used = $true
        }
    }
    $db["extraShots"] = $extras
}

$data = New-Object 'System.Collections.Generic.Dictionary[string,object]'
$data["generated"] = [double][DateTimeOffset]::Now.ToUnixTimeSeconds()
$data["characters"] = $characters
$json = [DagbokLua]::ToJson($data)
[IO.File]::WriteAllText((Join-Path $site "data.js"), "window.DAGBOK = $json;`n", (New-Object Text.UTF8Encoding $false))
Write-Host "Klart! $($characters.Count) karaktär(er), $(@($shots | Where-Object Used).Count) bilder."
