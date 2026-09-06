import { MethodChannel } from '@ohos/flutter_ohos';

@Observed
export class NativeVideoHostState {
  handle: string = '';
  viewId: number = -1;
  left: number = 0;
  top: number = 0;
  width: number = 1;
  height: number = 1;
}

AppStorage.setOrCreate('mediaKitNativeVideo', new NativeVideoHostState());

export class NativeVideoHost {
  static mounted: boolean = false;
  static channel: MethodChannel | null = null;
  static surfaceId: string = '';
  static get state(): NativeVideoHostState {
    return AppStorage.get<NativeVideoHostState>('mediaKitNativeVideo')!;
  }
  static create(handle: string, viewId: number): void {
    if (!NativeVideoHost.mounted) throw new Error('Mount MediaKitNativeVideoHost below a transparent FlutterPage first.');
    const state = NativeVideoHost.state;
    if (state.viewId !== -1 && (state.viewId !== viewId || state.handle !== handle)) {
      throw new Error('Only one native HDR surface can be displayed.');
    }
    state.handle = handle;
    state.viewId = viewId;
  }
  static dispose(handle: string, viewId: number): void {
    const state = NativeVideoHost.state;
    if (state.handle !== handle || state.viewId !== viewId) return;
    state.viewId = -1;
    state.handle = '';
    NativeVideoHost.surfaceId = '';
  }
}

@Component
struct NativeVideoSurface {
  @Prop handle: string;
  @Prop viewId: number;
  private controller: XComponentController = new XComponentController();
  build() {
    XComponent({ type: XComponentType.SURFACE, controller: this.controller })
      .width('100%').height('100%')
      .onLoad(() => {
        if (NativeVideoHost.state.viewId !== this.viewId || NativeVideoHost.state.handle !== this.handle) return;
        NativeVideoHost.surfaceId = this.controller.getXComponentSurfaceId();
        NativeVideoHost.channel?.invokeMethod('NativeSurface.Created', {
          handle: this.handle, viewId: this.viewId, surfaceId: NativeVideoHost.surfaceId
        });
      })
      .onDestroy(() => {
        NativeVideoHost.channel?.invokeMethod('NativeSurface.Destroyed', { handle: this.handle, viewId: this.viewId });
      });
  }
}

// This component must live in the real ArkUI tree, never inside a PlatformView
// BuilderNode using RENDER_TYPE_TEXTURE. Flutter paints a transparent hole above it.
@Component
export struct MediaKitNativeVideoHost {
  @StorageLink('mediaKitNativeVideo') state: NativeVideoHostState = new NativeVideoHostState();
  aboutToAppear(): void { NativeVideoHost.mounted = true; }
  aboutToDisappear(): void { NativeVideoHost.mounted = false; }
  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      ForEach(this.state.viewId < 0 ? [] : [this.state.viewId], (viewId: number) => {
        NativeVideoSurface({ handle: this.state.handle, viewId: viewId })
          .width(this.getUIContext().px2vp(this.state.width))
          .height(this.getUIContext().px2vp(this.state.height))
          .position({ x: this.getUIContext().px2vp(this.state.left), y: this.getUIContext().px2vp(this.state.top) });
      }, (viewId: number) => `${viewId}`);
    }.width('100%').height('100%').hitTestBehavior(HitTestMode.None);
  }
}
