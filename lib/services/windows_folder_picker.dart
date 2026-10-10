import 'windows_folder_picker_stub.dart'
    if (dart.library.io) 'windows_folder_picker_io.dart' as impl;

Future<String?> pickFolderWithExplorer({String? title}) {
  return impl.pickFolderWithExplorer(title: title);
}
