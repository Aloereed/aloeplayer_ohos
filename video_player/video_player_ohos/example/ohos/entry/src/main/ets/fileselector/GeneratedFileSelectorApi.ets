import { ByteBuffer } from '@ohos/flutter_ohos/src/main/ets/util/ByteBuffer';
import StandardMessageCodec from '@ohos/flutter_ohos/src/main/ets/plugin/common/StandardMessageCodec';
import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';

const TAG = "GeneratedFileSelectorApi";

class FlutterError extends Error {
  /** The error code. */
  public code: string;

  /** The error details. Must be a datatype supported by the api codec. */
  public details: ESObject;

  constructor(code: string, message: string, details: ESObject) {
    super(message);
    this.code = code;
    this.details = details;
  }
}

export function wrapError(exception: Error): Array<ESObject> {
  let errorList: Array<ESObject> = new Array<ESObject>();
  if (exception instanceof FlutterError) {
    let error = exception as FlutterError;
    errorList.push(error.code);
    errorList.push(error.message);
    errorList.push(error.details);
  } else {
    errorList.push(exception.toString());
    errorList.push(exception.name);
    errorList.push(
      "Cause: " + exception.message + ", Stacktrace: " + exception.stack);
  }
  return errorList;
}

export class FileResponse {
  private path: string;

  public getPath(): string {
    return this.path;
  }

  public setPath(setterArg: string): void {
    if (setterArg == null) {
      throw new Error('Nonnull field \'path\' is null.');
    }
    this.path = setterArg;
  }

  private name: string;

  public getName(): string {
    return this.name;
  }

  public setName(setterArg: string): void {
    this.name = setterArg;
  }

  private fd: number;

  public getFd(): number {
    return this.fd;
  }

  public setFd(setterArg: number): void {
    if (setterArg == null) {
      throw new Error("Nonnull field \"fd\" is null.");
    }
    this.fd = setterArg;
  }

  constructor(path: string, name: string, fd: number) {
    this.path = path;
    this.name = name;
    this.fd = fd;
  }

  toList(): Array<ESObject> {
    let toListResult: Array<ESObject> = new Array<ESObject>();
    toListResult.push(this.path);
    toListResult.push(this.name);
    toListResult.push(this.fd);
    return toListResult;
  }

  static fromList(list: Array<ESObject>): FileResponse {
    let path: ESObject = list[0];
    let name: ESObject = list[1];
    let fd: ESObject = list[2];
    let response = new FileResponse(path, name, fd);
    return response;
  }
}

export class FileTypes {
  mimeTypes: Array<string> = [];

  getMimeTypes(): Array<string>  {
    return this.mimeTypes;
  }

  setMimeTypes(setterArg: Array<string> | null): void {
    if (setterArg == null) {
      throw new Error("Nonnull field \"mimeTypes\" is null.");
    }
    this.mimeTypes = setterArg;
  }

  extensions: Array<string> = [];

  getExtensions(): Array<string> {
    return this.extensions;
  }

  setExtensions(setterArg: Array<string>): void {
    if (setterArg == null) {
      throw new Error("Nonnull field \"extensions\" is null.");
    }
    this.extensions = setterArg;
  }

  /** Constructor is non-public to enforce null safety; use Builder. */
  FileTypes() {}

  toList(): Array<ESObject> {
    let toListResult: Array<ESObject>  = new Array<ESObject>();
    toListResult.push(this.mimeTypes);
    toListResult.push(this.extensions);
    return toListResult;
  }

  static fromList(list: Array<ESObject>): FileTypes {
    let pigeonResult = new FileTypes();
    let mimeTypes: ESObject = list[0];
    pigeonResult.setMimeTypes(mimeTypes as Array<string>);
    let extensions: ESObject = list[1];
    pigeonResult.setExtensions(extensions as Array<string>);
    return pigeonResult;
  }
}


export interface Result<T> {
  success(result: T): void;
  error(error: Error): void;
}

export class FileSelectorApiCodec extends StandardMessageCodec {
    public static INSTANCE = new FileSelectorApiCodec();

    readValueOfType(type: number, buffer: ByteBuffer): ESObject {
      switch (type) {
        case 128:
          let res0 =  FileResponse.fromList(super.readValue(buffer) as Array<ESObject>);
          return res0;
        case 129:
          let vur: ESObject = super.readValue(buffer)
          let res1 =  FileTypes.fromList(vur as Array<ESObject>);
          return res1;
        default:
          let res2: ESObject = super.readValueOfType(type, buffer);
          return res2;
      }
    }

    writeValue(stream: ByteBuffer, value: ESObject): ESObject {
      if (value instanceof FileResponse) {
        stream.writeInt8(128);
        return this.writeValue(stream, (value as FileResponse).toList());
      } else if (value instanceof FileTypes) {
        stream.writeInt8(129);
        return this.writeValue(stream, (value as FileTypes).toList());
      } else {
        return super.writeValue(stream, value);
      }
    }
  }
