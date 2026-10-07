using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace Kornucopia.Windows;

internal static class Ui
{
    public static Brush Brush(string hex) => (SolidColorBrush)new BrushConverter().ConvertFromString(hex)!;
    public static readonly Brush Canvas = Brush("#F4F8F7"), Column = Brush("#E7F0ED"), Ink = Brush("#17243C"), Secondary = Brush("#566578"), Line = Brush("#CCDCD7"), Accent = Brush("#147D76"), Strong = Brush("#11645F"), Night = Brush("#0B252B"), Warning = Brush("#8A5113");
    public static Brush Paper(string column) => Brush(column switch { "backlog" => "#F6E8A9", "doing" => "#D5E7EF", "review" => "#E4DDF0", "done" => "#D9E8CF", _ => "#F6E8A9" });
    public static TextBlock Text(string text, double size = 13, Brush? color = null, bool bold = false) => new() { Text = text, FontSize = size, Foreground = color ?? Ink, FontWeight = bold ? FontWeights.SemiBold : FontWeights.Normal, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 7) };
    public static Button Button(string text, RoutedEventHandler action, bool primary = false)
    {
        var button = new Button { Content = text, Padding = new Thickness(15, 9, 15, 9), Margin = new Thickness(0, 0, 8, 0), Background = primary ? Accent : Brushes.White, Foreground = primary ? Brushes.White : Ink, BorderBrush = Line, Cursor = System.Windows.Input.Cursors.Hand, MinHeight = 36 };
        button.Click += action;
        return button;
    }
    public static TextBox Input(string value, string accessibleName, bool multiline = false)
    {
        var input = new TextBox { Text = value, Padding = new Thickness(10), Background = Canvas, Foreground = Ink, BorderBrush = Line, FontSize = 14, AcceptsReturn = multiline, TextWrapping = multiline ? TextWrapping.Wrap : TextWrapping.NoWrap, VerticalScrollBarVisibility = multiline ? ScrollBarVisibility.Auto : ScrollBarVisibility.Hidden };
        System.Windows.Automation.AutomationProperties.SetName(input, accessibleName);
        return input;
    }
    public static Border Round(UIElement child, Brush background, double radius = 12, Thickness? padding = null) => new() { Child = child, Background = background, BorderBrush = Line, BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(radius), Padding = padding ?? new Thickness(16) };
    public static bool Confirm(Window? owner, string title, string message, string cancel, string accept)
    {
        var dialog = new Window { Owner = owner, Title = title, Width = 490, SizeToContent = SizeToContent.Height, ResizeMode = ResizeMode.NoResize, WindowStartupLocation = owner is null ? WindowStartupLocation.CenterScreen : WindowStartupLocation.CenterOwner, Background = Canvas, FontFamily = new FontFamily("Segoe UI"), MaxHeight = SystemParameters.WorkArea.Height };
        var panel = new StackPanel { Margin = new Thickness(24) }; panel.Children.Add(Text(message, 13));
        var actions = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 16, 0, 0) };
        if (cancel.Length > 0) { var cancelButton = Button(cancel, (_, _) => dialog.DialogResult = false, true); cancelButton.IsDefault = true; cancelButton.IsCancel = true; actions.Children.Add(cancelButton); }
        var acceptButton = Button(accept, (_, _) => dialog.DialogResult = true, cancel.Length == 0); acceptButton.IsDefault = cancel.Length == 0; actions.Children.Add(acceptButton); panel.Children.Add(actions);
        dialog.Content = new ScrollViewer { Content = panel, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, MaxHeight = Math.Max(320, SystemParameters.WorkArea.Height - 60) };
        return dialog.ShowDialog() == true;
    }
    public static void Alert(Window? owner, string title, string message, string action) => Confirm(owner, title, message, "", action);
}
