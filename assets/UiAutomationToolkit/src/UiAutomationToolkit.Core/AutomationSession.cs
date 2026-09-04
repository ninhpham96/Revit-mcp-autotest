using FlaUI.Core;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Tools;
using FlaUI.UIA3;

namespace UiAutomationToolkit.Core;

/// <summary>
///     Entry point of the toolkit: attaches to an already-running process from this
///     (separate) tool process and drives its UI through real Windows UI Automation.
///     Running as a separate process — not code injected into the target app — is
///     what makes dialog handling reliable: the target app's UI thread can be
///     blocked inside a modal message loop (e.g. MessageBox.Show) while this
///     process's own thread keeps its own message pump and can still poll/click.
/// </summary>
public sealed class AutomationSession : IDisposable
{
    public UIA3Automation Automation { get; }
    public Application App { get; }

    private AutomationSession(Application app, UIA3Automation automation)
    {
        App = app;
        Automation = automation;
    }

    public static AutomationSession AttachByProcessName(string processName)
    {
        var automation = new UIA3Automation();
        try
        {
            var app = Application.Attach(processName);
            return new AutomationSession(app, automation);
        }
        catch
        {
            automation.Dispose();
            throw;
        }
    }

    public static AutomationSession AttachByProcessId(int processId)
    {
        var automation = new UIA3Automation();
        try
        {
            var app = Application.Attach(processId);
            return new AutomationSession(app, automation);
        }
        catch
        {
            automation.Dispose();
            throw;
        }
    }

    /// <summary>
    ///     Waits for a top-level window whose title contains <paramref name="titleContains"/>
    ///     (case-insensitive). Retries — new windows opened by an addin/plugin loaded
    ///     into a host process (e.g. a Revit add-in) can take a moment to appear.
    /// </summary>
    public Window WaitForWindow(string titleContains, TimeSpan? timeout = null)
    {
        timeout ??= TimeSpan.FromSeconds(10);

        var window = Retry.WhileNull(
            () => App.GetAllTopLevelWindows(Automation)
                .FirstOrDefault(w => TextMatch.Contains(w.Title, titleContains)),
            timeout.Value,
            TimeSpan.FromMilliseconds(200)).Result;

        return window ?? throw new TimeoutException(
            $"Không tìm thấy cửa sổ chứa '{titleContains}' sau {timeout.Value.TotalSeconds:F0}s.");
    }

    public IReadOnlyList<Window> GetAllWindows() => App.GetAllTopLevelWindows(Automation);

    public void Dispose() => Automation.Dispose();
}
