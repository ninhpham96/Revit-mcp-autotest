# Xác nhận command đã chạy tới đâu — DebugLog pattern

Sau khi `PostCommand` (xem [01-trigger-ribbon-button.md](01-trigger-ribbon-button.md)),
không có return value, không biết command đã chạy tới đâu hay lỗi ở bước nào.
2 cách "hiển nhiên" để kiểm tra đều **không dùng được** trong ngữ cảnh này —
đã verify thật, không phải suy đoán.

## Vì sao không query state WPF trực tiếp

Sau khi `PostCommand`, bản năng là gọi tiếp `revit_send_code_to_revit` để đọc
`System.Windows.Application.Current.Windows` xem cửa sổ đã mở chưa. 2 vấn đề
thật đã gặp:

1. **Cross-thread**: mỗi lần gọi `revit_send_code_to_revit` có thể chạy trên
   context/thread khác nhau, và object WPF (`Window`, `Application.Current`...)
   bị ràng buộc thread — đọc từ thread khác ném
   `InvalidOperationException: The calling thread cannot access this object
   because a different thread owns it`, kể cả khi chỉ đọc 1 property đơn giản
   như `.Count`.
2. **`Application.Current` có thể null hoàn toàn**: khi cửa sổ WPF được tạo
   trực tiếp trong process host (`new MyWindow().Show()`, không đi qua
   `System.Windows.Application` chuẩn — đúng tình huống 1 add-in Revit dev qua
   loader runtime) thì **không hề có instance `System.Windows.Application`
   nào tồn tại** trong process. Đã verify: `System.Windows.Application.Current == null`.
   Mọi code dựa vào `Application.Current.Windows`/`Application.Current.MainWindow`
   sẽ crash với `NullReferenceException`.

(Tìm cửa sổ vẫn có cách khác không qua `Application.Current` —
`System.Windows.PresentationSource.CurrentSources` liệt kê được mọi
`Window` đang mở trong process bất kể có `Application` hay không, dùng được
để **debug/test tương tác** — xem
[04-ui-automation-testing.md](04-ui-automation-testing.md) cho cách test qua
UI thật. Nhưng đây vẫn không phải cách "hỏi command chạy tới đâu" — chỉ dùng
được SAU khi cửa sổ đã chắc chắn tồn tại.)

## Vì sao không dùng thẳng Serilog/DI/Host có sẵn của project

Khi command được nạp qua loader khác (Mini AppLoader hoặc tương tự) thay vì
qua `.addin` + `Application.OnStartupAsync()` chuẩn, pipeline khởi tạo
DI/Serilog của project **không được gọi** → dùng `Host.GetService<ILogger<T>>()`
trong tình huống này có thể `NullReferenceException` ngay tại chỗ đang cố
debug.

## Giải pháp: logger tối giản, ghi thẳng ra file

Không phụ thuộc `Host`/DI/Serilog, ghi thẳng `System.IO.File`, tự nuốt lỗi
(logger không được phép làm crash command nó đang chẩn đoán):

```csharp
// Utils/DebugLog.cs
using System;
using System.IO;

namespace YourAddin.Utils
{
    public static class DebugLog
    {
        private static readonly string LogPath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "YourAddin", "addin.log");

        public static void Write(string message)
        {
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(LogPath)!);
                File.AppendAllText(LogPath, $"{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff} {message}{Environment.NewLine}");
            }
            catch
            {
                // Logging không được phép làm crash command nó đang chẩn đoán.
            }
        }
    }
}
```

Bọc thân `Execute()` trong `try/catch`, log các mốc quan trọng (bắt đầu, kết
quả trung gian, thành công), log cả exception nếu có rồi `throw` lại (để
Revit vẫn báo lỗi bình thường cho người dùng thật):

```csharp
public override void Execute()
{
    DebugLog.Write("MyCommand.Execute: started");
    try
    {
        // ... logic thật ...
        DebugLog.Write($"MyCommand.Execute: found {items.Count} items");
        // ...
        DebugLog.Write("MyCommand.Execute: window shown successfully");
    }
    catch (Exception ex)
    {
        DebugLog.Write($"MyCommand.Execute: FAILED - {ex}");
        throw;
    }
}
```

## Quy trình test đầy đủ

1. Build lại DLL (`dotnet build ... -c Debug.R2x`).
2. Ghi nhớ số dòng log hiện có (hoặc xoá file cũ) để phân biệt lần chạy mới.
3. Bấm nút bằng kỹ thuật `PostCommand` ([01-trigger-ribbon-button.md](01-trigger-ribbon-button.md)).
4. Đợi 1-2 giây (hàng đợi command xử lý bất đồng bộ), rồi đọc file log — biết
   chắc chắn đã chạy tới đâu, thành công hay lỗi ở bước nào, không cần đoán
   qua exception thread hay query state WPF.

Nếu add-in được nạp qua 1 dev loader dạng "đọc lại DLL mới sau mỗi lần build"
(nhiều dev loader làm vậy) thì quy trình trên **không cần restart Revit** —
sửa code, build, `PostCommand` lại là thấy log mới ngay, không bị dính
assembly cũ cache trong process. Nếu add-in đăng ký qua `.addin` chuẩn (không
qua dev loader), Revit **có** cache assembly cũ trong process — cần restart
Revit sau mỗi lần build để nạp bản mới (verify: `AppDomain.CurrentDomain.GetAssemblies()`
lọc theo tên assembly, so `LastWriteTime` của `.Location` với file `.dll` vừa
build, để biết chắc bản đang chạy có phải bản mới không trước khi mất công
debug 1 lỗi đã sửa từ trước).
