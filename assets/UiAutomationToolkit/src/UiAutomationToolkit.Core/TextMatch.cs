using System.Text;

namespace UiAutomationToolkit.Core;

/// <summary>
///     Windows UI Automation can return element Name/Title strings in a different
///     Unicode normalization form than what the caller typed (observed with
///     Vietnamese diacritics: precomposed "ư" vs. base letter + combining horn).
///     A plain <see cref="string.Contains(string)"/> then silently fails to match
///     text that looks completely identical on screen. Always compare through
///     here instead of calling Contains directly on UI Automation text.
/// </summary>
public static class TextMatch
{
    public static bool Contains(string haystack, string needle) =>
        Normalize(haystack).Contains(Normalize(needle), StringComparison.OrdinalIgnoreCase);

    public static bool Equals(string a, string b) =>
        string.Equals(Normalize(a), Normalize(b), StringComparison.OrdinalIgnoreCase);

    private static string Normalize(string s) => s.Normalize(NormalizationForm.FormC);
}
