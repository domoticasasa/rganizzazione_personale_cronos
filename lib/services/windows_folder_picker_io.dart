import 'dart:io';

Future<String?> pickFolderWithExplorer({String? title}) async {
  if (!Platform.isWindows) return null;

  final safeTitle = (title ?? 'Seleziona cartella')
      .replaceAll("'", "''")
      .replaceAll('\r', ' ')
      .replaceAll('\n', ' ');

  final winFormsScript = r'''
Add-Type -AssemblyName System.Windows.Forms
$dialog = New-Object System.Windows.Forms.FolderBrowserDialog
$dialog.Description = '__TITLE__'
$dialog.ShowNewFolderButton = $false
$result = $dialog.ShowDialog()
if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
  Write-Output $dialog.SelectedPath
}
'''
      .replaceAll('__TITLE__', safeTitle);

  // Fallback COM (alcune macchine bloccano WinForms dialog)
  final comScript = r'''
$shell = New-Object -ComObject Shell.Application
$folder = $shell.BrowseForFolder(0, '__TITLE__', 0, 0)
if ($folder -ne $null) {
  Write-Output $folder.Self.Path
}
'''
      .replaceAll('__TITLE__', safeTitle);

  final candidates = <List<String>>[
    <String>['powershell', '-NoProfile', '-STA', '-Command', winFormsScript],
    <String>['powershell', '-NoProfile', '-STA', '-Command', comScript],
    <String>['pwsh', '-NoProfile', '-STA', '-Command', winFormsScript],
    <String>['pwsh', '-NoProfile', '-STA', '-Command', comScript],
  ];

  for (final cmd in candidates) {
    final exe = cmd.first;
    final args = cmd.sublist(1);
    final out = await _runPs(exe, args);
    if (out != null && out.isNotEmpty) return out;
  }
  return null;
}

Future<String?> _runPs(String executable, List<String> args) async {
  try {
    final res = await Process.run(
      executable,
      args,
      runInShell: true,
    ).timeout(const Duration(seconds: 25));
    if (res.exitCode != 0) return null;
    final out = (res.stdout ?? '').toString().trim();
    return out.isEmpty ? null : out;
  } catch (_) {
    return null;
  }
}
