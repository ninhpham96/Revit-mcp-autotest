using UiAutomationToolkit.Core;

if (args.Length == 0)
{
    PrintUsage();
    return 1;
}

try
{
    var command = args[0];
    var opts = ParseOptions(args);

    if (command == "debug-echo")
    {
        var w = Require(opts, "window");
        Console.WriteLine($"len={w.Length} codepoints=[{string.Join(",", w.Select(c => ((int)c).ToString("X4")))}]");
        return 0;
    }

    if (command == "debug-titles")
    {
        using var s = Attach(opts);
        foreach (var w in s.GetAllWindows())
            Console.WriteLine($"title='{w.Title}' len={w.Title.Length} codepoints=[{string.Join(",", w.Title.Select(c => ((int)c).ToString("X4")))}]");
        return 0;
    }

    if (command == "watch-windows")
    {
        using var s = Attach(opts);
        var seconds = opts.TryGetValue("seconds", out var secStr) ? double.Parse(secStr) : 8.0;
        var logFile = Require(opts, "log");
        var seen = new HashSet<string>();
        var sw = System.Diagnostics.Stopwatch.StartNew();
        while (sw.Elapsed.TotalSeconds < seconds)
        {
            foreach (var w in s.GetAllWindows())
            {
                var key = $"{w.Title}|{w.Properties.NativeWindowHandle.Value}";
                if (seen.Add(key))
                {
                    var codepoints = string.Join(",", w.Title.Select(c => ((int)c).ToString("X4")));
                    File.AppendAllText(logFile, $"{sw.ElapsedMilliseconds}ms NEW WINDOW title='{w.Title}' handle={w.Properties.NativeWindowHandle.Value} codepoints=[{codepoints}]\n");
                }
            }
            Thread.Sleep(50);
        }
        File.AppendAllText(logFile, "watch done\n");
        return 0;
    }

    if (command == "debug-buttons")
    {
        using var s = Attach(opts);
        var win = s.WaitForWindow(Require(opts, "window"));
        foreach (var name in win.ListButtonNames())
            Console.WriteLine($"button='{name}' codepoints=[{string.Join(",", name.Select(c => ((int)c).ToString("X4")))}]");
        return 0;
    }

    if (command == "run-script")
    {
        // Gộp nhiều bước vào 1 lần attach — tránh chi phí khởi động process +
        // quét lại UI tree cho mỗi bước riêng lẻ (đây là phần tốn thời gian nhất
        // khi chạy từng lệnh uitest.exe rời rạc).
        using var s = Attach(opts);
        var scriptTimeout = opts.TryGetValue("timeout", out var st) ? TimeSpan.FromSeconds(double.Parse(st)) : (TimeSpan?)null;

        var lineNo = 0;
        foreach (var rawLine in File.ReadLines(Require(opts, "file")))
        {
            lineNo++;
            var line = rawLine.Trim();
            if (line.Length == 0 || line.StartsWith('#')) continue;

            var tokens = Tokenize(line);
            var lineCommand = tokens[0];
            var lineOpts = ParseOptions(tokens);

            Console.WriteLine($"[{lineNo}] {lineCommand} ...");
            ExecuteWindowCommand(lineCommand, lineOpts, s, scriptTimeout);
        }

        Console.WriteLine("OK: script chạy xong.");
        return 0;
    }

    using var session = Attach(opts);
    var timeout = opts.TryGetValue("timeout", out var t) ? TimeSpan.FromSeconds(double.Parse(t)) : (TimeSpan?)null;
    ExecuteWindowCommand(command, opts, session, timeout);
    return 0;
}
catch (Exception ex)
{
    Console.Error.WriteLine($"LỖI: {ex.Message}");
    return 1;
}

static AutomationSession Attach(Dictionary<string, string> opts) =>
    opts.TryGetValue("pid", out var pidStr)
        ? AutomationSession.AttachByProcessId(int.Parse(pidStr))
        : AutomationSession.AttachByProcessName(Require(opts, "process"));

static void ExecuteWindowCommand(string command, Dictionary<string, string> opts, AutomationSession session, TimeSpan? timeout)
{
    switch (command)
    {
        case "list-windows":
            foreach (var w in session.GetAllWindows())
                Console.WriteLine(w.Title);
            break;

        case "list-buttons":
        {
            var window = session.WaitForWindow(Require(opts, "window"), timeout);
            foreach (var name in window.ListButtonNames())
                Console.WriteLine(name);
            break;
        }

        case "click-button":
        {
            var window = session.WaitForWindow(Require(opts, "window"), timeout);
            window.ClickButton(Require(opts, "button"));
            Console.WriteLine("OK: đã bấm nút.");
            break;
        }

        case "click-and-confirm":
        {
            var window = session.WaitForWindow(Require(opts, "window"), timeout);
            window.ClickButtonAndHandleDialog(
                session,
                Require(opts, "button"),
                Require(opts, "dialog-button"),
                Require(opts, "dialog-title"),
                timeout);
            Console.WriteLine("OK: đã bấm nút và xử lý dialog con.");
            break;
        }

        case "select-row":
        {
            var window = session.WaitForWindow(Require(opts, "window"), timeout);
            window.SelectDataGridRow(Require(opts, "grid"), int.Parse(Require(opts, "row")));
            Console.WriteLine("OK: đã chọn dòng.");
            break;
        }

        default:
            throw new ArgumentException($"Lệnh không hợp lệ: '{command}'");
    }
}

static Dictionary<string, string> ParseOptions(IReadOnlyList<string> args)
{
    var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
    for (var i = 1; i < args.Count - 1; i++)
    {
        if (!args[i].StartsWith("--")) continue;
        result[args[i][2..]] = args[i + 1];
    }
    return result;
}

static string Require(Dictionary<string, string> opts, string key) =>
    opts.TryGetValue(key, out var value)
        ? value
        : throw new ArgumentException($"Thiếu tham số bắt buộc --{key}");

/// <summary>Tách 1 dòng script thành token, hỗ trợ chuỗi trong dấu ngoặc kép chứa khoảng trắng.</summary>
static string[] Tokenize(string line)
{
    var tokens = new List<string>();
    var current = new System.Text.StringBuilder();
    var inQuotes = false;

    foreach (var c in line)
    {
        if (c == '"')
        {
            inQuotes = !inQuotes;
        }
        else if (char.IsWhiteSpace(c) && !inQuotes)
        {
            if (current.Length > 0) { tokens.Add(current.ToString()); current.Clear(); }
        }
        else
        {
            current.Append(c);
        }
    }
    if (current.Length > 0) tokens.Add(current.ToString());
    return tokens.ToArray();
}

static void PrintUsage()
{
    Console.WriteLine("""
        uitest — điều khiển UI của app WPF/WinForms đang chạy qua UI Automation (FlaUI).

        Chọn 1 trong 2 cách gắn vào process: --process <tên process> HOẶC --pid <process id>.

        Lệnh:
          list-windows   --process <name>
          list-buttons   --process <name> --window <chứa-tiêu-đề>
          click-button   --process <name> --window <chứa-tiêu-đề> --button <tên-nút>
          click-and-confirm --process <name> --window <chứa-tiêu-đề> --button <tên-nút>
                         --dialog-button <tên-nút-trên-dialog-con> --dialog-title <chứa-tiêu-đề>
          select-row     --process <name> --window <chứa-tiêu-đề> --grid <AutomationId> --row <index>
          run-script     --process <name> --file <path>   (gộp nhiều bước, 1 lần attach — xem bên dưới)

        Tuỳ chọn chung: --timeout <giây> (mặc định 10s)

        Ví dụ:
          uitest click-and-confirm --process Revit --window "Danh sách tường" \
              --button "Xoá tường đã chọn" --dialog-button Yes --dialog-title "Xác nhận xoá"

        Định dạng file --file cho run-script (mỗi dòng 1 lệnh, không cần --process/--pid,
        dùng chung 1 session; dòng trống hoặc bắt đầu bằng # bị bỏ qua):

          select-row --window "Danh s" --grid WallsDataGrid --row 0
          click-and-confirm --window "Danh s" --button "Xoá tường đã chọn" \
              --dialog-button "Yes" --dialog-title "nh"
        """);
}
