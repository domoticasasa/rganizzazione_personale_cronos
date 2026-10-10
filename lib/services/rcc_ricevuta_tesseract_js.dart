import 'dart:js_interop';

@JS('Tesseract.createWorker')
external JSPromise createWorker(JSString langs);

@JS()
extension type TesseractWorker(JSObject _) implements JSObject {
  external JSPromise setParameters(JSObject params);
  external JSPromise recognize(JSAny image);
  external JSPromise terminate();
}

@JS()
extension type TesseractResult(JSObject _) implements JSObject {
  external TesseractData get data;
}

@JS()
extension type TesseractData(JSObject _) implements JSObject {
  external JSString get text;
}
