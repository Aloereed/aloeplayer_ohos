import { PipSession } from '../entryability/PipSession';

class PipSurfaceController extends XComponentController {
  onSurfaceCreated(surfaceId: string): void {
    PipSession.active?.surfaceReady(this, surfaceId);
  }
}

// Keep the PiP Surface in the window's real display hierarchy.
@Entry
@Component
struct PipPlayer {
  private controller: PipSurfaceController = new PipSurfaceController();
  private session?: PipSession;
  @State phase: string = '创建视频画面';
  @State ready: boolean = false;
  @State error: string = '';
  aboutToAppear(): void {
    this.session = PipSession.active;
    if (this.session) {
      this.session.pageMounted();
      this.session.onStatus = (phase: string, ready: boolean, error: string): void => {
        this.phase = phase; this.ready = ready; this.error = error;
      };
      this.session.refreshStatus();
    }
  }
  onBackPress(): boolean { this.session?.close(); return true; }
  aboutToDisappear(): void { if (this.session) this.session.onStatus = undefined; }
  build() {
    Column({ space: 20 }) {
      Row() {
        Button('返回播放器').onClick(() => this.session?.close())
        Text('系统画中画').fontSize(20).fontColor(Color.White).layoutWeight(1).textAlign(TextAlign.Center)
      }.width('100%')
      XComponent({ id: 'aloe-system-pip', type: XComponentType.SURFACE, controller: this.controller })
        .width('100%').layoutWeight(1)
      Text(this.error || this.phase).fontColor(this.error ? '#FFB4AB' : '#D5E4F5')
        .fontSize(15).textAlign(TextAlign.Center)
      if (!this.ready && !this.error) { LoadingProgress().width(32).height(32).color(Color.White) }
      if (this.ready) { Button('开启画中画').onClick(() => this.session?.start()) }
      Text('返回后会在 mpv 中继续当前进度').fontColor('#ADB8C8').fontSize(13)
    }.width('100%').height('100%').padding(24).backgroundColor('#10151E')
  }
}
