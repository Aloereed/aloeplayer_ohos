import MethodChannel, {
  MethodCallHandler,
  MethodResult
} from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import PlatformView, { Params } from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformView';
import common from '@ohos.app.ability.common';
import { BinaryMessenger } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import StandardMethodCodec from '@ohos/flutter_ohos/src/main/ets/plugin/common/StandardMethodCodec';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import audio from '@ohos.multimedia.audio';
import display from '@ohos.display';
import router from '@ohos.router';
import { Callback } from '@ohos.base';
import prompt from '@ohos.promptAction';
import abilityAccessCtrl from '@ohos.abilityAccessCtrl';
import photoAccessHelper from '@ohos.file.photoAccessHelper';
import fs from '@ohos.file.fs';
import image from "@ohos.multimedia.image"
import media from "@ohos.multimedia.media"
// import // LogUtils from '../utils/// LogUtils';
import avSession from '@ohos.multimedia.avsession';
import { AVCastPicker, AVCastPickerState } from '@kit.AVSessionKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { wantAgent } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Context } from '@kit.AbilityKit';

// Global AVSession
let session: avSession.AVSession;

// PlayStatus enum for tracking playback state
enum PlayStatus {
  IDLE = 'IDLE',
  INIT = 'INIT',
  PREPARED = 'PREPARED',
  PLAYING = 'PLAYING',
  PAUSED = 'PAUSED',
  COMPLETED = 'COMPLETED',
  STOPPED = 'STOPPED',
  ERROR = 'ERROR'
}

@Component
struct ButtonComponent {
  @Prop params: Params
  castView: CastView = this.params.platformView as CastView

  aboutToAppear() {
    console.log("aboutToAppear");


    // Apply for long-running background task
    // this.startContinuousTask();
  }

  aboutToDisappear() {
    console.log("aboutToDisappear");
    // Clean up resources
    // this.releaseSession();
  }

  build() {
    Column() {
      // Full-screen player
      Stack({ alignContent: Alignment.Center }) {
        AVCastPicker({
          onStateChange: this.onStateChange
        })
          .width('100%')
          .height('100%')
      }
      .width('100%')
      .height('100%')
    }
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .height('100%')
  }

  // Handle AVCastPicker state changes
  private onStateChange(state: AVCastPickerState) {
    if (state == AVCastPickerState.STATE_APPEARING) {
      console.log('The picker starts showing.');
    } else if (state == AVCastPickerState.STATE_DISAPPEARING) {
      console.log('The picker finishes presenting.');
    }
  }


}


@Builder
function ButtonBuilder(params: Params) {
  ButtonComponent({ params: params })
    .backgroundColor(Color.Transparent)
}

AppStorage.setOrCreate('numValue', 'test')
AppStorage.setOrCreate('cast', 0)

@Observed
export class CastView extends PlatformView implements MethodCallHandler {
  numValue: string = "test";
  cast: number = 0;
  methodChannel: MethodChannel;
  videoUrl: string = '';
  last: number = 0;
  fileDes: number = 0;
  playStatus: PlayStatus = PlayStatus.IDLE
  private url: string | null = null
  private neturl: string | null = null
  private pixelMap: image.PixelMap | undefined = undefined
  private title: string | undefined = undefined
  private artist: string | undefined = undefined
  private mediaType: string = "video"

  castController: avSession.AVCastController | undefined = undefined
  context: common.Context = getContext(this);


  constructor(context: common.Context, viewId: number, args: ESObject, message: BinaryMessenger) {
    super();
    // 注册消息通道
    this.methodChannel = new MethodChannel(message, `com.aloereed.aloeplayer/castView${viewId}`, StandardMethodCodec.INSTANCE);
    this.methodChannel.setMethodCallHandler(this);
    this.numValue = args['initParams'] as string;
    // 检查是否包含分隔符
    if (this.numValue && this.numValue.includes('|||')) {
      const parts = this.numValue.split('|||');
      this.url = parts[0];
      this.videoUrl = parts[0];
      this.neturl = parts[1];
    } else {
      // 如果没有分隔符，可以根据需求决定默认行为
      this.url = this.numValue;
      this.neturl = '';
      // 或者抛出错误，或者设置其他默认值
    }

    // Initialize context and AVSession
    // this.context = this.castView.getContext() as common.UIAbilityContext;

  }

  // Handle method calls from Flutter
  onMethodCall(call: MethodCall, result: MethodResult): void {
    // Accept messages from the Dart side
    let method: string = call.method;
    // let link1: SubscribedAbstractProperty<number> = AppStorage.link('cast');
    // let link2: SubscribedAbstractProperty<string> = AppStorage.link('videoUrl');
    // let link3: SubscribedAbstractProperty<PlayStatus> = AppStorage.link('CONTROL_PlayStatus');

    switch (method) {
      case 'getMessageFromFlutterView2':
        console.log("Received cast value");
        let value: ESObject = call.args;
        this.cast = parseFloat(value as string);
        console.log("Received message from dart: " + this.cast);
        result.success(true);
        break;

      case 'getMessageFromFlutterView':
        console.log("Received video URL");
        let value2: ESObject = call.args;
        this.numValue = value2 as string;
        if (this.numValue && this.numValue.includes('|||')) {
          const parts = this.numValue.split('|||');
          this.url = parts[0];
          this.videoUrl = parts[0];
          this.neturl = parts[1];
        } else {
          // 如果没有分隔符，可以根据需求决定默认行为
          this.url = this.numValue;
          this.videoUrl = this.numValue;
          this.neturl = '';
          // 或者抛出错误，或者设置其他默认值
        }
        console.log(`[Cast] Get from flutter: ${this.numValue}`);
        this.playStatus = PlayStatus.INIT;
        console.log(`[Cast] Get from flutter: ${this.numValue}`);
        // Set AVSession metadata when receiving a new URL
        this.createSession(this.context)
          .then((): Promise<void> => {
            // Register session listeners
            this.setSessionListener();
            // Set up AVCastController
            return this.getAVCastController();

          }).then((): Promise<void> => {
            // Set AVSession metadata
            return this.setAVMetadata();
          })
          .then(() => {
            if (this.castController) {
              // Update the cast with the new video
              this.castVideo();
            }
            result.success(true);
          })
          .catch((error: BusinessError) => {
            // 处理可能发生的错误
            result.error("ERROR_CODE", "Error message", error);
          });
        break;

      case 'newPlay':
        console.log("Received new play command");
        let value3: ESObject = call.args;
        this.videoUrl = value3 as string;

        // Check if we're currently casting
        if (this.castController) {
          // Update the cast with the new video
          this.castVideo();
        }

        console.log("Received message new play: " + this.videoUrl);
        result.success(true);
        break;

      case 'play':
        this.play();
        result.success(true);
        break;

      case 'pause':
        this.pause();
        result.success(true);
        break;

      case 'seek':
        if (call.args !== null) {
          this.seek(parseFloat(call.args as string));
        }
        result.success(true);
        break;

      case 'setVolume':
        if (call.args !== null) {
          this.setVolume(parseFloat(call.args as string));
        }
        result.success(true);
        break;

      case 'stopCasting':
        this.stopCasting();
        result.success(true);
        break;

      default:
        result.notImplemented();
    }
  }

  // Create and activate AVSession
  async createSession(context: common.Context) {
    if (context) {
      try {
        // Create AVSession for video application
        session = await avSession.createAVSession(context, 'AloePlayer', 'video');
        await session.activate();

        // Set extras to indicate support for casting
        session.setExtras({
          requireAbilityList: ['url-cast'],
        });

        console.log(`Session created. sessionId: ${session.sessionId}`);
      } catch (error) {
        console.error(`Failed to create session: ${error}`);
      }
    }
  }

  async fetchMetadataFromFdSrcByPromise() {
    if (canIUse("SystemCapability.Multimedia.Media.AVMetadataExtractor")) {
      // 创建AVMetadataExtractor对象
      let avMetadataExtractor: media.AVMetadataExtractor =
        await media.createAVMetadataExtractor()
      // 设置fdSrc
      if (this.url != null && this.url.startsWith("file")) {
        console.log(`trying to get metadata from file: ${this.url}`)
        let file = fs.openSync(this.url, fs.OpenMode.READ_ONLY)
        let state = fs.statSync(file.fd)
        let avFileDescriptor: media.AVFileDescriptor = {
          fd: file.fd,
          offset: 0,
          length: state.size,
        }
        avMetadataExtractor.fdSrc = avFileDescriptor
      } else {
        avMetadataExtractor.release()
        return
      }

      // avMetadataExtractor.fdSrc = await getContext(this).resourceManager.getRawFd(this.url);

      // 获取元数据（promise模式）
      let metadata = await avMetadataExtractor.fetchMetadata()
      console.info(`get meta data, hasAudio: ${metadata.hasAudio}`)

      // 获取专辑封面（promise模式）
      try {
        if (metadata.hasVideo == "yes") {
          let avImageGenerator: media.AVImageGenerator =
            await media.createAVImageGenerator()
          if (this.url != null && this.url.startsWith("file")) {
            console.log(
              `trying to get video cover from file: ${this.url}`
            )
            let file = fs.openSync(this.url, fs.OpenMode.READ_ONLY)
            let state = fs.statSync(file.fd)
            let avFileDescriptor: media.AVFileDescriptor = {
              fd: file.fd,
              offset: 0,
              length: state.size,
            }
            avImageGenerator.fdSrc = avFileDescriptor
          }

          // 初始化入参
          let timeUs = 0
          let queryOption =
            media.AVImageQueryOptions.AV_IMAGE_QUERY_NEXT_SYNC
          let param: media.PixelMapParams = {
            width: 300,
            height: 300,
          }

          // 获取缩略图（promise模式）
          this.pixelMap = await avImageGenerator.fetchFrameByTime(
            timeUs,
            queryOption,
            param
          )

          // 释放资源（promise模式）
          avImageGenerator.release()
          console.info(`release success.`)
        } else {
          this.mediaType = "audio"
          this.title = metadata.title
          this.artist = metadata.artist
          this.pixelMap = await avMetadataExtractor.fetchAlbumCover()
        }
      } catch (e) {
        console.error(`fetchAlbumCover failed: ${e}`)
      }

      // 释放资源（promise模式）
      avMetadataExtractor.release()
      console.info(`release success.`)
    }
  }

  // Set AVSession metadata for casting
  async setAVMetadata() {
    if (!session) {
      return;
    }
    // this.url = this.numValue

    await this.fetchMetadataFromFdSrcByPromise()


    try {
      const metadata: avSession.AVMetadata = {
        assetId: `video-${Date.now()}`,
        title: this.title ?? 'AloePlayer',
        subtitle: '由AloePlayer投播',
        filter: avSession.ProtocolType.TYPE_CAST_PLUS_STREAM | avSession.ProtocolType.TYPE_DLNA,
        mediaImage: this.pixelMap,
        artist: this.artist ?? 'AloePlayer',
        // fdSrc: avFileDescriptor,
      };

      await session.setAVMetadata(metadata);
      console.log('AVMetadata set successfully');
    } catch (error) {
      console.error(`Failed to set AVMetadata: ${error}`);
    }
  }

  // Register session listeners for basic playback controls
  setSessionListener() {
    if (!session) {
      return;
    }

    session.on('play', () => {
      console.log('Session play command received');
      this.playStatus = PlayStatus.PLAYING;
    });

    session.on('pause', () => {
      console.log('Session pause command received');
      this.playStatus = PlayStatus.PAUSED;
    });

    session.on('stop', () => {
      console.log('Session stop command received');
      this.playStatus = PlayStatus.STOPPED;
    });

    console.log(`[cast] set session listener done.`)

    // session.on('seekDone', (position: number) => {
    //   console.log(`Session seekDone to position: ${position}`);
    // });
  }

  // Get AVCastController and set up device change listener
  async getAVCastController(): Promise<void> {
    if (!session) {
      return;
    }

    // this.castController = await session.getAVCastController();
    console.log('[cast] Succeeded in getting a init cast controller');

    // Listen for device connection changes
    session.on('outputDeviceChange', async (connectState: avSession.ConnectionState,
      device: avSession.OutputDeviceInfo) => {
      let currentDevice: avSession.DeviceInfo = device?.devices?.[0];

      if (currentDevice && currentDevice.castCategory === avSession.AVCastCategory.CATEGORY_REMOTE &&
        connectState === avSession.ConnectionState.STATE_CONNECTED) {
        // Device connected successfully
        console.log(`[cast] Device connected: ${JSON.stringify(device)}`);

        try {
          this.castController = await session.getAVCastController();
          console.log('[cast] Succeeded in getting a cast controller');

          // Set up playback state change listener
          this.setupPlaybackStateListener();

          // Setup DRM key request listener if needed
          if (currentDevice.supportedDrmCapabilities?.includes('3d5e6d35-9b9a-41e8-b843-dd3c6e72c42c')) {
            // this.castController?.on('keyRequest', this.keyRequestCallback.bind(this));
          }

          // Start casting the current video
          this.castVideo();
        } catch (error) {
          console.error(`[cast] Failed to get AVCastController: ${error}`);
        }
      }

      // Update UI based on connection state
      if (connectState === avSession.ConnectionState.STATE_DISCONNECTED) {
        console.log('[cast] Device disconnected');
        this.castController = undefined;
        this.playStatus = PlayStatus.IDLE;
      }
    });
  }

  // Setup listeners for playback state changes
  setupPlaybackStateListener() {
    if (!this.castController) {
      return;
    }

    // Listen for playback state changes
    this.castController.on('playbackStateChange', 'all', (state: avSession.AVPlaybackState) => {
      console.log(`Playback state changed: ${JSON.stringify(state)}`);

      if (state?.state === avSession.PlaybackState.PLAYBACK_STATE_PLAY) {
        this.playStatus = PlayStatus.PLAYING;
      } else if (state?.state === avSession.PlaybackState.PLAYBACK_STATE_PAUSE) {
        this.playStatus = PlayStatus.PAUSED;
      } else if (state?.state === avSession.PlaybackState.PLAYBACK_STATE_STOP) {
        this.playStatus = PlayStatus.STOPPED;
      }
    });

    // Listen for media item changes
    this.castController.on('mediaItemChange', (item: avSession.AVQueueItem) => {
      console.log(`Media item changed: ${JSON.stringify(item)}`);
    });

    // Listen for end of stream
    this.castController.on('endOfStream', () => {
      console.log('End of stream reached');
      // Restart the video or handle completion based on app requirements
      this.playStatus = PlayStatus.COMPLETED;
    });

    // Listen for seeking completion
    this.castController.on('seekDone', (position: number) => {
      console.log(`Seek completed to position: ${position}`);
    });

    // Listen for previous/next requests
    this.castController.on('playPrevious', () => {
      console.log('Play previous requested');
    });

    this.castController.on('playNext', () => {
      console.log('Play next requested');
    });
  }

  // Cast the video to the connected device
  castVideo() {
    let url = this.url
    let neturl = this.neturl
    if (!this.castController || !url) {
      console.log('Cannot cast: controller or URL is missing');
      return;
    }



    // let file = fs.openSync(url, fs.OpenMode.READ_ONLY)
    // let state = fs.statSync(file.fd)
    // let avFileDescriptor: media.AVFileDescriptor = {
    //   fd: file.fd,
    //   offset: 0,
    //   length: state.size,
    // }

    console.log(`Casting video: ${url}`);
    this.fetchMetadataFromFdSrcByPromise().then(() => {
      // Set up playback item
      const playItem: avSession.AVQueueItem = {
        itemId: 0,
        description: {
          assetId: `VIDEO-${Date.now()}`,
          title: this.title ?? 'AloePlayer',
          artist: this.artist ?? 'AloePlayer',
          // fdSrc: avFileDescriptor,
          mediaUri: neturl??'',
          mediaType: 'VIDEO',
          mediaSize: 1000,
          startPosition: 0,
          duration: 100000,
          appName: 'AloePlayer',
        }
      };
      // Prepare and start playback
      this.castController?.prepare(playItem, () => {
        console.log('Preparation done');

        // Start playback
        this.castController?.start(playItem, () => {
          console.log('Playback started');
          this.playStatus = PlayStatus.PLAYING;
        });
      });
    });




  }

  // Handle DRM key requests if needed
  private keyRequestCallback(assetId: string, requestData: Uint8Array) {
    console.log(`DRM key request for assetId: ${assetId}`);

    // This would typically involve getting a license from a server
    // For demonstration purposes only:
    this.getLicense('https://license.example.com/getLicense', requestData)
      .then(licenseData => {
        if (this.castController && licenseData) {
          this.castController.processMediaKeyResponse(assetId, licenseData)
            .then(() => {
              console.log('License processed successfully');
            })
            .catch((error: BusinessError) => {
              console.error(`Failed to process license: ${error}`);
            });
        }
      })
      .catch((error: BusinessError) => {
        console.error(`Failed to get license: ${error}`);
      });
  }

  // Mock implementation for getting DRM license
  async getLicense(url: string, requestData: Uint8Array): Promise<Uint8Array> {
    // In a real implementation, this would make a network request to the license server
    console.log(`Getting license from ${url}`);
    return new Uint8Array(10); // Mock response
  }



  // Playback control methods
  play() {
    if (!this.castController) {
      return;
    }

    const avCommand: avSession.AVCastControlCommand = { command: 'play' };
    this.castController.sendControlCommand(avCommand);
  }

  pause() {
    if (!this.castController) {
      return;
    }

    const avCommand: avSession.AVCastControlCommand = { command: 'pause' };
    this.castController.sendControlCommand(avCommand);
  }

  setVolume(volume: number) {
    if (!this.castController) {
      return;
    }

    const avCommand: avSession.AVCastControlCommand = {
      command: 'setVolume',
      parameter: volume
    };
    this.castController.sendControlCommand(avCommand);
  }

  seek(position: number) {
    if (!this.castController) {
      return;
    }

    const avCommand: avSession.AVCastControlCommand = {
      command: 'seek',
      parameter: position
    };
    this.castController.sendControlCommand(avCommand);
  }

  // Stop casting
  stopCasting() {
    if (session) {
      session.stopCasting((err: BusinessError) => {
        if (err) {
          console.error(`stopCasting BusinessError: code: ${err.code}, message: ${err.message}`);
        } else {
          console.info('stopCasting successfully');
        }
      });
    }
  }

  // Release resources
  releaseSession() {
    if (session) {
      try {
        session.destroy();
        console.log('Session released');
      } catch (error) {
        console.error(`Failed to release session: ${error}`);
      }
    }

  }

  getView(): WrappedBuilder<[Params]> {
    return new WrappedBuilder(ButtonBuilder);
  }

  dispose(): void {
    this.releaseSession();
  }
}