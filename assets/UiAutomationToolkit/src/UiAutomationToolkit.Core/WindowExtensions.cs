using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.Core.Tools;

namespace UiAutomationToolkit.Core;

public static class WindowExtensions
{
    public static Button FindButton(this Window window, string name)
    {
        // Đường nhanh: FindFirstDescendant với ByName+ByControlType được UI Automation
        // lọc phía provider (native), không phải duyệt+so khớp thủ công phía managed —
        // đo được nhanh hơn ~4-5 lần so với FindAllDescendants(quét TOÀN BỘ cây, kể cả
        // bên trong DataGrid) rồi mới lọc. Tên nút (khác tiêu đề cửa sổ) đã verify KHÔNG
        // bị lỗi Unicode mangling nên so khớp chính xác qua UIA an toàn ở đây.
        var fast = window.FindFirstDescendant(cf =>
            cf.ByControlType(ControlType.Button).And(cf.ByName(name)));
        if (fast != null)
            return fast.AsButton();

        // Đường chậm dự phòng: nếu vì lý do gì đó tên không khớp exact qua UIA
        // (control khác, môi trường khác...), quét toàn bộ + so khớp qua TextMatch.
        var slow = window.FindAllDescendants(cf => cf.ByControlType(ControlType.Button))
            .FirstOrDefault(e => TextMatch.Equals(e.Name, name));

        return slow?.AsButton()
               ?? throw new InvalidOperationException($"Không tìm thấy nút '{name}' trong cửa sổ '{window.Title}'.");
    }

    public static IReadOnlyList<string> ListButtonNames(this Window window) =>
        window.FindAllDescendants(cf => cf.ByControlType(ControlType.Button))
            .Select(e => e.Name)
            .ToList();

    /// <summary>Bấm nút — đi qua đúng InvokePattern, tương đương chuột click thật.</summary>
    public static void ClickButton(this Window window, string name) => window.FindButton(name).Invoke();

    /// <summary>
    ///     Bấm 1 nút rồi tự xử lý dialog con (modal) mà nó mở ra — ví dụ MessageBox
    ///     xác nhận, ColorDialog, SaveFileDialog.
    ///
    ///     <para>
    ///     Tìm/bấm nút trên dialog qua <see cref="NativeDialogHelper"/> (raw Win32
    ///     <c>EnumWindows</c>/<c>SendMessage BM_CLICK</c>), KHÔNG qua UI Automation —
    ///     đã verify UI Automation (cả FlaUI lẫn <c>System.Windows.Automation</c> gốc)
    ///     không thấy được <c>MessageBox.Show(...)</c> hiện lên khi UI thread của app
    ///     đích đang lồng sâu trong 1 message loop khác (vd Revit add-in), dù
    ///     <c>EnumWindows</c> thấy nó ngay lập tức, tiêu đề đúng nguyên vẹn kể cả dấu.
    ///     </para>
    /// </summary>
    /// <param name="window">Cửa sổ chứa nút cần bấm.</param>
    /// <param name="session">Phiên automation đang gắn vào process (để lấy process id).</param>
    /// <param name="buttonName">Tên nút sẽ bấm (mở ra dialog).</param>
    /// <param name="dialogButtonName">Tên nút cần bấm trên dialog con (vd: "Yes", "OK").</param>
    /// <param name="dialogTitleContains">
    ///     Lọc theo tiêu đề dialog — BẮT BUỘC phải đủ đặc trưng để không trùng với
    ///     cửa sổ chính hoặc cửa sổ khác đang mở, vì giờ tìm trên toàn bộ process.
    /// </param>
    /// <param name="timeout">Thời gian tối đa chờ dialog xuất hiện + xử lý xong.</param>
    public static void ClickButtonAndHandleDialog(
        this Window window,
        AutomationSession session,
        string buttonName,
        string dialogButtonName,
        string dialogTitleContains,
        TimeSpan? timeout = null)
    {
        timeout ??= TimeSpan.FromSeconds(10);
        var button = window.FindButton(buttonName);
        var mainHandle = window.Properties.NativeWindowHandle.Value;
        var processId = session.App.ProcessId;

        var dialogTask = Task.Run(() =>
        {
            var dialogHandle = NativeDialogHelper.WaitForDialog(processId, dialogTitleContains, mainHandle, timeout.Value);
            if (dialogHandle == null)
                return (Success: false, Reason: "Không thấy dialog con xuất hiện.");

            if (!NativeDialogHelper.ClickDialogButton(dialogHandle.Value, dialogButtonName))
            {
                var seen = string.Join(", ", NativeDialogHelper.ListDialogButtonTexts(dialogHandle.Value));
                return (Success: false, Reason: $"Dialog không có nút '{dialogButtonName}'. Các nút thấy được: {seen}");
            }

            return (Success: true, Reason: "");
        });

        // UIA Invoke() theo chuẩn không block chờ handler chạy xong — chỉ post rồi trả về ngay.
        button.Invoke();

        if (!dialogTask.Wait(timeout.Value))
            throw new TimeoutException("Xử lý dialog con quá thời gian chờ.");

        if (!dialogTask.Result.Success)
            throw new InvalidOperationException(dialogTask.Result.Reason);
    }

    public static void SelectDataGridRow(this Window window, string gridAutomationId, int rowIndex)
    {
        var grid = window.FindFirstDescendant(cf => cf.ByAutomationId(gridAutomationId))?.AsDataGridView();
        if (grid == null)
            throw new InvalidOperationException($"Không tìm thấy DataGrid có AutomationId='{gridAutomationId}'.");

        var rows = grid.Rows;
        if (rowIndex < 0 || rowIndex >= rows.Length)
            throw new ArgumentOutOfRangeException(nameof(rowIndex), $"Grid chỉ có {rows.Length} dòng.");

        rows[rowIndex].Patterns.SelectionItem.Pattern.Select();
    }
}
