using System.Runtime.InteropServices;
using System.Text;

namespace UiAutomationToolkit.Core;

/// <summary>
///     Finds and clicks native Win32 dialogs (MessageBox, and other dialogs built on
///     the same plumbing) via raw <c>user32.dll</c> calls instead of UI Automation.
///
///     <para>
///     Verified empirically: a WPF <c>MessageBox.Show(...)</c> dialog raised while the
///     owning app's UI thread is deep inside a host process's nested message loop
///     (observed hosting a Revit add-in's window) is a completely normal, visible
///     top-level HWND — <c>EnumWindows</c> finds it immediately, with the correct
///     title, diacritics included. But <see cref="FlaUI.Core.Application.GetAllTopLevelWindows"/>
///     / <c>AutomationElement.RootElement.FindFirst/FindAll</c> (both wrap the same
///     underlying IUIAutomation COM interface) never discover it at all — most likely
///     because UI Automation relies on the target window responding to
///     <c>WM_GETOBJECT</c> to build its tree, and that isn't being serviced reliably
///     for this window while its owning thread is nested this deeply. Raw
///     <c>EnumWindows</c> needs no such cooperation from the target, so it is the
///     reliable choice specifically for dialog handling in this scenario.
///     </para>
///
///     <para>
///     Separately, and unrelated to the above: a top-level window's <b>title bar
///     text</b> retrieved through UI Automation's Name property has been observed
///     silently ANSI-"best-fit" mangled for non-ASCII characters (Vietnamese "tường"
///     became "tu?ng") — while the *same* text read as a control's Name (e.g. a
///     button) is not. Raw <c>GetWindowText</c> (Unicode P/Invoke) does not exhibit
///     this at all. Two independent, unrelated defects — keep them straight if this
///     ever needs re-diagnosing.
///     </para>
/// </summary>
public static class NativeDialogHelper
{
    private const uint BM_CLICK = 0x00F5;

    /// <summary>
    ///     Polls for a new top-level, visible window belonging to <paramref name="processId"/>
    ///     whose title contains <paramref name="titleContains"/> (diacritics-safe — compares
    ///     through <see cref="TextMatch"/>), other than <paramref name="excludeHandle"/>.
    /// </summary>
    public static IntPtr? WaitForDialog(int processId, string titleContains, IntPtr excludeHandle, TimeSpan timeout)
    {
        var deadline = DateTime.UtcNow + timeout;
        while (DateTime.UtcNow < deadline)
        {
            foreach (var (handle, title) in EnumerateTopLevelWindows(processId))
            {
                if (handle != excludeHandle && TextMatch.Contains(title, titleContains))
                    return handle;
            }
            Thread.Sleep(100);
        }
        return null;
    }

    /// <summary>
    ///     Finds a button child of <paramref name="dialogHandle"/> by its text (mnemonic
    ///     "&amp;" prefix ignored, diacritics-safe) and sends it a BM_CLICK.
    /// </summary>
    public static bool ClickDialogButton(IntPtr dialogHandle, string buttonText)
    {
        IntPtr? found = null;
        EnumChildWindows(dialogHandle, (hWnd, _) =>
        {
            if (!string.Equals(GetClassName(hWnd), "Button", StringComparison.OrdinalIgnoreCase))
                return true;

            var text = GetWindowText(hWnd).TrimStart('&');
            if (TextMatch.Equals(text, buttonText))
            {
                found = hWnd;
                return false; // stop enumerating
            }
            return true;
        }, IntPtr.Zero);

        if (found is not { } hWndFound)
            return false;

        SendMessage(hWndFound, BM_CLICK, IntPtr.Zero, IntPtr.Zero);
        return true;
    }

    public static IReadOnlyList<string> ListDialogButtonTexts(IntPtr dialogHandle)
    {
        var texts = new List<string>();
        EnumChildWindows(dialogHandle, (hWnd, _) =>
        {
            if (string.Equals(GetClassName(hWnd), "Button", StringComparison.OrdinalIgnoreCase))
                texts.Add(GetWindowText(hWnd).TrimStart('&'));
            return true;
        }, IntPtr.Zero);
        return texts;
    }

    private static IEnumerable<(IntPtr Handle, string Title)> EnumerateTopLevelWindows(int processId)
    {
        var results = new List<(IntPtr, string)>();
        EnumWindows((hWnd, _) =>
        {
            GetWindowThreadProcessId(hWnd, out var windowPid);
            if (windowPid == processId && IsWindowVisible(hWnd))
            {
                var title = GetWindowText(hWnd);
                if (!string.IsNullOrEmpty(title))
                    results.Add((hWnd, title));
            }
            return true;
        }, IntPtr.Zero);
        return results;
    }

    private static string GetWindowText(IntPtr hWnd)
    {
        var length = GetWindowTextLength(hWnd);
        if (length == 0) return string.Empty;
        var sb = new StringBuilder(length + 1);
        GetWindowTextW(hWnd, sb, sb.Capacity);
        return sb.ToString();
    }

    private static string GetClassName(IntPtr hWnd)
    {
        var sb = new StringBuilder(256);
        GetClassNameW(hWnd, sb, sb.Capacity);
        return sb.ToString();
    }

    private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsProc enumProc, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool EnumChildWindows(IntPtr hWndParent, EnumWindowsProc enumProc, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern int GetWindowTextLength(IntPtr hWnd);

    [DllImport("user32.dll", EntryPoint = "GetWindowTextW", CharSet = CharSet.Unicode)]
    private static extern int GetWindowTextW(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll", EntryPoint = "GetClassNameW", CharSet = CharSet.Unicode)]
    private static extern int GetClassNameW(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern IntPtr SendMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
}
