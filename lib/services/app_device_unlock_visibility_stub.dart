/// Stub non-web: lifecycle nativo gestisce già resume/pause.
void attachAppDeviceUnlockVisibilityListener({
  required void Function() onHidden,
  required void Function() onVisible,
}) {}

void persistAppDeviceUnlockAt(DateTime? _) {}

DateTime? readPersistedAppDeviceUnlockAt() => null;

void persistAppDevicePickerGraceUntil(DateTime? _) {}

DateTime? readPersistedAppDevicePickerGraceUntil() => null;
