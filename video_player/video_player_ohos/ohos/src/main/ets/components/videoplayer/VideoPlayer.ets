// Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE_ODID file.
// Based on VideoPlayer.java originally written by
// Copyright 2013 The Flutter Authors.

import media from "@ohos.multimedia.media"
import prompt from "@ohos.promptAction"
import resourceManager from "@ohos.resourceManager"
import window from "@ohos.window"
import Log from "@ohos/flutter_ohos/src/main/ets/util/Log"
import { SurfaceTextureEntry } from "@ohos/flutter_ohos/src/main/ets/view/TextureRegistry"
import image from "@ohos.multimedia.image"
import {
    AvplayerStatus,
    CommonConstants,
    Events,
    SliderMode,
} from "./constants/CommonConstants"
import { PlayConstants } from "./constants/PlayConstants"

import { PlayerModel } from "./PlayerModel"
import DateFormatUtil from "./util/DateFormatUtil"
import { GlobalContext } from "./util/GlobalContext"
import { VideoItem } from "./VideoItem"
import { BusinessError } from "@ohos.base"
import { EventChannel } from "@ohos/flutter_ohos"
import {
    EventSink,
    StreamHandler,
} from "@ohos/flutter_ohos/src/main/ets/plugin/common/EventChannel"
import { QueuingEventSink } from "./QueuingEventSink"
import { ArrayList, HashMap } from "@kit.ArkTS"
import { audio } from "@kit.AudioKit"
import { avSession } from "@kit.AVSessionKit"
import fs from "@ohos.file.fs"

const FORMAT_SS: String = "ss"
const FORMAT_DASH: String = "dash"
const FORMAT_HLS: String = "hls"
const FORMAT_OTHER: String = "other"

const OPERATE_ERROR: number = 801
const AVPLAYER_STATE_ERROR: number = 5400102
const AVPLAYER_IO_ERROR: number = 5400103

const TAG = "VideoPlayer"
export class VideoPlayer {
    private avPlayer: media.AVPlayer | null = null
    private session: avSession.AVSession | null = null
    private currentState: avSession.AVPlaybackState = {
        state: avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
    }
    public playerModel: PlayerModel | null = null
    private sessionName: string | null = null
    private duration: number = 0
    private status: number = -1
    private loop: boolean = false
    private index: number = 0
    private rawFile?: resourceManager.RawFileDescriptor | null =
        {} as resourceManager.RawFileDescriptor
    private url: string | null = null
    private pixelMap: image.PixelMap | undefined = undefined
    private title: string | undefined = undefined
    private artist: string | undefined = undefined
    private surfaceId: string = ""
    private seekTime: number = PlayConstants.PROGRESS_SEEK_TIME
    private positionX: number = PlayConstants.POSITION_X
    private positionY: number = PlayConstants.POSITION_Y
    private textureEntry: SurfaceTextureEntry
    private eventChannel: EventChannel | null = null
    private eventSink: QueuingEventSink | null = null
    private interruptMode: audio.InterruptMode =
        audio.InterruptMode.INDEPENDENT_MODE
    private fd: number | null = null
    private headers: Record<string, string> | null
    private mediaType: string = "video"

    constructor(
        playerModel: PlayerModel,
        textureEntry: SurfaceTextureEntry,
        rawFile: resourceManager.RawFileDescriptor | null,
        url: string | null,
        eventChannel: EventChannel,
        AudioFocus: Boolean,
        headers: Record<string, string> | null
    ) {
        this.playerModel = playerModel
        this.textureEntry = textureEntry
        this.surfaceId = textureEntry.getSurfaceId().toString()
        this.rawFile = rawFile
        this.url = url
        this.eventChannel = eventChannel
        this.headers = headers
        this.sessionName = this.createGuid()
        if (AudioFocus == true) {
            this.interruptMode = audio.InterruptMode.SHARE_MODE
            Log.i(TAG, "set interruptMode : " + this.interruptMode)
        }
        Log.i(TAG, "surfaceId : " + this.surfaceId)
    }

    // 注册avplayer回调函数
    setAVPlayerCallback() {
        // seek操作结果回调函数
        this.avPlayer?.on("seekDone", (seekDoneTime: number) => {
            console.info(
                `AVPlayer seek succeeded, seek time is ${seekDoneTime}`
            )
        })
        this.avPlayer?.on(
            "videoSizeChange",
            (width: number, height: number) => {
                console.info(
                    "videoSizeChange called,and width is:" +
                        width +
                        ", height is :" +
                        height
                )
            }
        )
        // error回调监听函数,当avPlayer在操作过程中出现错误时调用 reset接口触发重置流程
        this.avPlayer?.on("error", (err: BusinessError) => {
            console.error(
                `Invoke avPlayer failed, code is ${err.code}, message is ${err.message}`
            )
            this.avPlayer?.reset() // 调用reset重置资源，触发idle状态
        })
        // 状态机变化回调函数
        this.avPlayer?.on(
            "stateChange",
            async (state: string, reason: media.StateChangeReason) => {
                switch (state) {
                    case "idle": // 成功调用reset接口后触发该状态机上报
                        console.info("AVPlayer state idle called.")
                        // this.avPlayer?.release(); // 调用release接口销毁实例对象
                        break
                    case "initialized": // avplayer 设置播放源后触发该状态上报
                        console.info("AVPlayer state initialized called.")
                        this.avPlayer?.prepare()
                        break
                    case "prepared": // prepare调用成功后上报该状态机
                        console.info("AVPlayer state prepared called.")
                        this.avPlayer!.audioInterruptMode =
                            audio.InterruptMode.SHARE_MODE
                        // this.avPlayer?.play(); // 调用播放接口开始播放
                        break
                    case "playing": // play成功调用后触发该状态机上报
                        console.info("AVPlayer state playing called.")
                        break
                    case "paused": // pause成功调用后触发该状态机上报
                        console.info("AVPlayer state paused called.")
                        // this.avPlayer?.play(); // 再次播放接口开始播放
                        break
                    case "completed": // 播放结束后触发该状态机上报
                        console.info("AVPlayer state completed called.")
                        this.avPlayer?.stop() //调用播放结束接口
                        break
                    case "stopped": // stop接口成功调用后触发该状态机上报
                        console.info("AVPlayer state stopped called.")
                        // this.avPlayer?.reset(); // 调用reset接口初始化avplayer状态
                        break
                    case "released":
                        console.info("AVPlayer state released called.")
                        break
                    default:
                        console.info("AVPlayer state unknown called.")
                        break
                }
            }
        )
    }

    //生成一个GUID的函数
    createGuid(): string {
        let guid = ""
        for (let i = 1; i <= 32; i++) {
            let n = Math.floor(Math.random() * 16.0).toString(16)
            guid += n
            if (i === 8 || i === 12 || i === 16 || i === 20) {
                guid += "-"
            }
        }
        return guid
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
            } else if (this.rawFile != null) {
                let state = fs.statSync(this.rawFile.fd)
                let avFileDescriptor: media.AVFileDescriptor = {
                    fd: this.rawFile.fd,
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
            console.info(TAG, `get meta data, hasAudio: ${metadata.hasAudio}`)

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
                    } else if (this.rawFile != null) {
                        let state = fs.statSync(this.rawFile.fd)
                        let avFileDescriptor: media.AVFileDescriptor = {
                            fd: this.rawFile.fd,
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
                    console.info(TAG, `release success.`)
                } else {
                    this.mediaType = "audio"
                    this.title = metadata.title
                    this.artist = metadata.artist
                    this.pixelMap = await avMetadataExtractor.fetchAlbumCover()
                }
            } catch (e) {
                console.error(TAG, `fetchAlbumCover failed: ${e}`)
            }

            // 释放资源（promise模式）
            avMetadataExtractor.release()
            console.info(TAG, `release success.`)
        }
    }
    async createSession(): Promise<avSession.AVSession> {
        let type: avSession.AVSessionType =
            this.mediaType == "audio" ? "audio" : "video"
        /*
         * context:应用上下文，提供获取应用程序环境信息的能力。
         * tag:会话的自定义名称。
         *type:会话类型。
         */
        let context = getContext(this) as Context
        if (this.sessionName == null) {
            this.sessionName = this.createGuid()
        }

        this.session = await avSession.createAVSession(
            context,
            this.sessionName,
            type
        )
        console.info(`session get done : sessionName : ${this.sessionName}`)
        await this.fetchMetadataFromFdSrcByPromise()
        // 设置必要的媒体信息
        let metadata: avSession.AVMetadata = {
            assetId: "0", // 由应用指定，用于标识应用媒体库里的媒体
            title: this.title ?? "AloePlayer",
            mediaImage: this.pixelMap,
            artist: this.artist ?? "正在播放",
            duration: this.duration, // 资源的时长，以ms为单位
        }
        this.session
            .setAVMetadata(metadata)
            .then(() => {
                console.info("SetAVMetadata successfully")
            })
            .catch((err: BusinessError) => {
                console.error(
                    `Failed to set AVMetadata. Code: ${err.code}, message: ${err.message}`
                )
            })
        //监听事件
        await this.RegisterSessionListener()
        // 激活接口要在元数据、控制命令注册完成之后再执行
        await this.session.activate()
        console.info(
            `session create done : sessionId : ${this.session.sessionId}`
        )
        return this.session
    }

    async RegisterSessionListener(): Promise<void> {
        // Processes playback commands.
        this.session?.on("play", async () => {
            // Logger.info(TAG, 'on play, do play task');
            this.avPlayer?.play()
            // this.isPlayLink!.set(true);
            this.currentState = {
                state: avSession.PlaybackState.PLAYBACK_STATE_PLAY,
                position: {
                    elapsedTime: this.getPosition(),
                    updateTime: new Date().getTime(),
                },
            }
            await this.session?.setAVPlaybackState(this.currentState)
        })

        // Suspend instruction processing.
        this.session?.on("pause", async () => {
            // Logger.info(TAG, 'on pause, do pause task');
            this.avPlayer?.pause()
            // this.isPlayLink!.set(false);
            this.currentState = {
                state: avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
                position: {
                    elapsedTime: this.getPosition(),
                    updateTime: new Date().getTime(),
                },
            }
            await this.session?.setAVPlaybackState(this.currentState)
        })

        // Stop instruction processing.
        this.session?.on("stop", async () => {
            // Logger.info(TAG, 'on stop , do stop task');
            this.avPlayer?.stop()
            // this.isPlayLink!.set(false);
            this.currentState = {
                state: avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
            }
            await this.session?.setAVPlaybackState(this.currentState)
        })

        // Next song/set instruction processing.
        this.session?.on("playNext", async () => {
            // Logger.info(TAG, 'on playNext , do playNext task');
        })

        // Previous song/set instruction processing.
        this.session?.on("playPrevious", async () => {
            // Logger.info(TAG, 'on playPrevious , do playPrevious task');
        })

        // Processes the progress bar dragging command.
        this.session?.on("seek", (position: number) => {
            // Logger.info(TAG, 'on seek: seek to' + position);
            this.seekTo(position)
            // Modify the playback progress based on the instruction.
            // if (position >= this.currentAVMetadataLink!.get().duration!) {
            //   this.next();
            // } else {
            //   this.avPlayer?.seek(position);
            //   this.currentState?.position = {
            //     elapsedTime: position,
            //     updateTime: new Date().getTime()
            //   };
            //   this.session?.setAVPlaybackState(this.currentState);
            // }
        })

        // Processes the favorite/like command for the audio session.
        this.session?.on("toggleFavorite", (assetId: string) => {
            // If a system callback message is received, the user clicks the favorites button when playing the song.
            // The app stores the favorites status based on the song ID and reports the current favorites status.
            // Logger.info(TAG, 'on toggleFavorite session, do toggleFavorite task: ' + assetId);
            // this.isFavorMapLink!.get().set(assetId, !this.isFavorMapLink!.get().get(assetId));
            // this.currentState?.isFavorite = this.isFavorMapLink!.get().get(assetId);
            // this.session?.setAVPlaybackState(this.currentState);
        })

        // Cyclic mode instruction processing for audio session.
        this.session?.on("setLoopMode", (mode) => {
            // Logger.info(TAG, 'on setLoopMode: ');
            this.setLoop()
            // The value transferred by the playback control is not processed.
            // The value is switched based on the application sequence.
            // let currentMode = this.currentLoopModeLink!.get();
            // this.currentLoopModeLink!.set(currentMode === 3 ? 0 : currentMode + 1);
            // // The playback status is updated. The cyclic mode after application processing is reported in the playback status.
            // this.currentState?.loopMode = this.currentLoopModeLink!.get();
            // // Logger.info(TAG, 'self setLoopMode: ' + this.currentState?.loopMode);
            // this.session?.setAVPlaybackState(this.currentState);
        })

        // Fast-forward command processing for video sessions.
        this.session?.on("fastForward", (skipInterval?: number) => {
            // Logger.info(TAG, 'on fastForward: ');
            if (
                skipInterval != null &&
                this.getPosition() + skipInterval! * 1000 <= this.duration
            )
                this.seekTo(this.getPosition() + skipInterval! * 1000)
            // let currentTime: number =
            //   (skipInterval! * 1000 + this.avPlayer!.currentTime) > this.currentAVMetadataLink!.get().duration! ?
            //     this.currentAVMetadataLink!.get().duration! : (skipInterval! * 1000 + this.avPlayer!.currentTime);
            // if (currentTime >= this.currentAVMetadataLink!.get().duration!) {
            //   this.next();
            // } else {
            //   this.avPlayer?.seek(currentTime);
            //   this.currentState?.position = {
            //     elapsedTime: currentTime,
            //     updateTime: new Date().getTime()
            //   };
            //   this.currentState?.state = avSession.PlaybackState.PLAYBACK_STATE_PLAY;
            //   this.session?.setAVPlaybackState(this.currentState);
            // }
        })

        // Rewind command processing, for video session.
        this.session?.on("rewind", (skipInterval?: number) => {
            // Logger.info(TAG, 'on rewind: ');
            if (
                skipInterval != null &&
                this.getPosition() - skipInterval! * 1000 > 0
            )
                this.seekTo(this.getPosition() - skipInterval! * 1000)
            // let currentTime: number = (this.avPlayer!.currentTime - skipInterval! * 1000) <= 0 ?
            //   0 : (this.avPlayer!.currentTime - skipInterval! * 1000);
            // this.avPlayer?.seek(skipInterval);
            // // Logger.info(TAG, ' currentTime' + JSON.stringify(currentTime));
            // if (currentTime <= 0) {
            //   this.previous();
            // } else {
            //   this.avPlayer?.seek(currentTime);
            //   this.currentState?.position = {
            //     elapsedTime: currentTime,
            //     updateTime: new Date().getTime()
            //   };
            //   this.currentState?.state = avSession.PlaybackState.PLAYBACK_STATE_PLAY;
            //   this.session?.setAVPlaybackState(this.currentState);
            // }
        })
    }

    /**
     * Creates a videoPlayer object.
     */
    async createAVPlayer() {
        Log.i(TAG + ":" + this.textureEntry.getTextureId(), " createAVPlayer")
        if (this.avPlayer == null) {
            this.avPlayer = await media.createAVPlayer()
        }
        if (this.avPlayer != null) {
            this.eventSink = new QueuingEventSink()
            Log.i(TAG, "enter setStreamHandler")
            this.eventChannel?.setStreamHandler(
                new StreamHandlerImpl(this.eventSink)
            )

            await this.bindState()

            /// 同时使用avPlayer.url和avPlayer.setMediaSource会导致直播视频无法正确播放
            if (!this.headers) {
                if (this.url) {
                    this.avPlayer.url = this.getIUri()
                } else {
                    this.avPlayer.fdSrc = this.rawFile!
                }
            } else {
                let mediaSource: media.MediaSource =
                    media.createMediaSourceWithUrl(this.url, this.headers)
                /// 网络直播视频必须设置之后才能正常缓存
                let playbackStrategy: media.PlaybackStrategy = {}
                // 设置媒体来源和播放策略
                await this.avPlayer.setMediaSource(
                    mediaSource,
                    playbackStrategy
                )
            }
        }
    }

    /**
     * AVPlayer binding event.
     */
    async bindState() {
        Log.i(TAG, "enter bindState")
        if (this.avPlayer == null) {
            Log.e(TAG, "bindState, avPlayer is null")
            return
        }
        this.avPlayer.on(
            Events.STATE_CHANGE,
            async (state: media.AVPlayerState) => {
                let avplayerStatus: string = state
                Log.i(TAG, "bindState, on avPlayer, step1")
                if (this.avPlayer == null) {
                    Log.e(TAG, "bindState, avPlayer is null, step2")
                    return
                }
                Log.i(
                    TAG,
                    "bindState, on STATE_CHANGE, avplayerStatus=" +
                        avplayerStatus
                )
                switch (avplayerStatus) {
                    case AvplayerStatus.IDLE:
                        this.resetProgress()
                        if (this.url) {
                            this.avPlayer.url = this.getIUri()
                        } else {
                            this.avPlayer.fdSrc = this.rawFile!
                        }
                        this.currentState = {
                            state: avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
                            position: {
                                elapsedTime: this.getPosition(),
                                updateTime: new Date().getTime(),
                            },
                        }
                        await this.session?.setAVPlaybackState(
                            this.currentState
                        )
                        break
                    case AvplayerStatus.INITIALIZED:
                        this.avPlayer.surfaceId = this.surfaceId
                        this.avPlayer.prepare()
                        this.currentState = {
                            state: avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
                            position: {
                                elapsedTime: this.getPosition(),
                                updateTime: new Date().getTime(),
                            },
                        }
                        await this.session?.setAVPlaybackState(
                            this.currentState
                        )
                        break
                    case AvplayerStatus.PREPARED:
                        this.avPlayer.videoScaleType = 0
                        this.avPlayer.audioInterruptMode = this.interruptMode
                        this.setVideoSize()
                        this.sendInitialized()
                        this.duration = this.avPlayer.duration
                        let metadata: avSession.AVMetadata = {
                            assetId: "0",
                            title: this.title ?? "AloePlayer",
                            mediaImage: this.pixelMap,
                            artist: this.artist ?? "正在播放",
                            duration: this.duration, // 资源的时长，以ms为单位
                        }
                        await this.session
                            ?.setAVMetadata(metadata)
                            .then(() => {
                                console.info(`SetAVMetadata successfully`)
                            })
                            .catch((err: BusinessError) => {
                                console.error(
                                    `Failed to set AVMetadata. Code: ${err.code}, message: ${err.message}`
                                )
                            })
                        this.currentState = {
                            state: avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
                            position: {
                                elapsedTime: this.getPosition(),
                                updateTime: new Date().getTime(),
                            },
                        }
                        await this.session?.setAVPlaybackState(
                            this.currentState
                        )
                        break
                    case AvplayerStatus.PLAYING:
                        this.status = CommonConstants.STATUS_START
                        this.watchStatus()
                        // this.isPlayLink!.set(true);
                        this.currentState = {
                            state: avSession.PlaybackState.PLAYBACK_STATE_PLAY,
                            position: {
                                elapsedTime: this.getPosition(),
                                updateTime: new Date().getTime(),
                            },
                        }
                        await this.session?.setAVPlaybackState(
                            this.currentState
                        )
                        break
                    case AvplayerStatus.PAUSED:
                        this.status = CommonConstants.STATUS_PAUSE
                        this.watchStatus()
                        // this.isPlayLink!.set(true);
                        this.currentState = {
                            state: avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
                            position: {
                                elapsedTime: this.getPosition(),
                                updateTime: new Date().getTime(),
                            },
                        }
                        await this.session?.setAVPlaybackState(
                            this.currentState
                        )

                        break
                    case AvplayerStatus.COMPLETED:
                        if (this.playerModel != null) {
                            this.playerModel.playSpeed =
                                PlayConstants.PLAY_SPEED
                        }
                        this.sendCompleted()
                        this.duration = PlayConstants.PLAYER_DURATION
                        // this.isPlayLink!.set(true);
                        this.currentState = {
                            state: avSession.PlaybackState.PLAYBACK_STATE_PLAY,
                            position: {
                                elapsedTime: this.getPosition(),
                                updateTime: new Date().getTime(),
                            },
                        }
                        await this.session?.setAVPlaybackState(
                            this.currentState
                        )
                        if (!this.loop) {
                            let curIndex =
                                this.index + PlayConstants.PLAYER_NEXT
                            let globalVideoList =
                                GlobalContext.getContext().getObject(
                                    "globalVideoList"
                                ) as VideoItem[]
                            this.index =
                                curIndex === globalVideoList.length
                                    ? PlayConstants.PLAYER_FIRST
                                    : curIndex
                            if (this.url) {
                                this.url = globalVideoList[this.index].iSrc
                            } else {
                                this.rawFile = globalVideoList[this.index].src
                            }
                        }
                        break
                    case AvplayerStatus.RELEASED:
                        // this.isPlayLink!.set(true);
                        this.currentState = {
                            state: avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
                        }
                        await this.session?.setAVPlaybackState(
                            this.currentState
                        )
                        this.avPlayer.release()
                        this.status = CommonConstants.STATUS_STOP
                        this.watchStatus()
                        Log.i(TAG, "[PlayVideoModel] state released called")
                        break
                    default:
                        Log.i(TAG, "[PlayVideoModel] unKnown state: " + state)
                        break
                }
            }
        )

        this.avPlayer.on(Events.TIME_UPDATE, (time: number) => {
            this.initProgress(time)
            // let metadata: avSession.AVMetadata = {
            //     assetId: "0",
            //     title: this.title ?? "AloePlayer",
            //     mediaImage: this.pixelMap,
            //     artist: this.artist ?? "正在播放",
            //     duration: this.duration, // 资源的时长，以ms为单位
            // }
            // await this.session
            //     ?.setAVMetadata(metadata)
            //     .then(() => {
            //         console.info(`SetAVMetadata successfully`)
            //     })
            //     .catch((err: BusinessError) => {
            //         console.error(
            //             `Failed to set AVMetadata. Code: ${err.code}, message: ${err.message}`
            //         )
            //     })
            // 设置状态： 播放状态，进度位置，播放倍速，缓存的时间
            let playbackState: avSession.AVPlaybackState = {
                state: avSession.PlaybackState.PLAYBACK_STATE_PLAY, // 播放状态
                position: {
                    elapsedTime: this.getPosition(), // 已经播放的位置，以ms为单位
                    updateTime: new Date().getTime(), // 应用更新当前位置时的时间戳，以ms为单位
                },
                speed: this.playerModel?.playSpeed, // 可选，默认是1.0，播放的倍速，按照应用内支持的speed进行设置，系统不做校验// 可选，资源缓存的时间，以ms为单位
            }
            this.session?.setAVPlaybackState(playbackState, (err) => {
                if (err) {
                    console.error(
                        `Failed to set AVPlaybackState. Code: ${err.code}, message: ${err.message}`
                    )
                } else {
                    console.info(`SetAVPlaybackState successfully`)
                }
            })
        })

        this.avPlayer?.on(
            Events.BUFFER_UPDATE,
            (infoType: media.BufferingInfoType, value: number) => {
                this.sendBufferingUpdate(infoType, value)
            }
        )

        this.avPlayer?.on(Events.ERROR, (err: BusinessError) => {
            // 播放直播视频时，设置 loop 会报错，而 loop 一定会设置(video_player.dart 中初始化之后会 _applyLooping)，所以屏蔽掉该报错
            // message: Unsupport Capability: The stream is live stream, not support loop
            /// 规避部分错误导致的reset，如：5400102 当前状态机不支持此操作；5400103 出现IO错误
            if (
                err.code == OPERATE_ERROR ||
                err.code == AVPLAYER_STATE_ERROR ||
                err.code == AVPLAYER_IO_ERROR
            ) {
                Log.e(
                    TAG,
                    "AvPlayer Avoid Error Reporting: " + JSON.stringify(err)
                )
                return
            }
            Log.e(TAG, "avPlayer Events.ERROR: " + JSON.stringify(err))
            this.avPlayer?.reset()
            this.sendError(err)
        })
    }

    /**
     * Release the video player.
     */
    release() {
        if (this.avPlayer !== null) {
            this.avPlayer.release()
            this.eventChannel?.setStreamHandler(null)
        }
        if (this.fd != null) {
            fs.closeSync(this.fd!)
        }
    }

    play() {
        if (this.avPlayer !== null) {
            this.avPlayer.play()
        }
    }

    /**
     * Pause Playing.
     */
    pause() {
        if (this.avPlayer !== null) {
            this.avPlayer.pause()
        }
    }

    seekTo(position: number) {
        if (this.avPlayer !== null) {
            this.avPlayer.seek(position, media.SeekMode.SEEK_CLOSEST)
        }
    }

    getPosition(): number {
        if (this.avPlayer !== null) {
            return this.avPlayer.currentTime
        } else {
            return 0
        }
    }

    /**
     * Playback mode. The options are as follows: true: playing a single video; false: playing a cyclic video.
     */
    setLoop() {
        this.loop = !this.loop
    }

    setLooping(isLooping: boolean) {
        if (this.avPlayer != null) {
            this.avPlayer.loop = isLooping
        }
        this.loop = isLooping
    }

    setVolume(volume: number) {
        if (this.avPlayer != null) {
            this.avPlayer.setVolume(volume)
        }
    }

    /**
     * Set the playback speed.
     *
     * @param playSpeed Current playback speed.
     */
    setSpeed(playSpeed: number) {
        if (this.avPlayer == null || this.playerModel == null) {
            return
        }
        if (CommonConstants.OPERATE_STATE.indexOf(this.avPlayer.state) === -1) {
            return
        }
        this.playerModel.playSpeed = playSpeed
        this.avPlayer.setSpeed(this.playerModel.playSpeed)
    }

    /**
     * Previous video.
     */
    previousVideo() {
        if (
            this.avPlayer == null ||
            this.playerModel == null ||
            this.playerModel == null
        ) {
            return
        }
        if (CommonConstants.OPERATE_STATE.indexOf(this.avPlayer.state) === -1) {
            return
        }
        this.playerModel.playSpeed = PlayConstants.PLAY_SPEED
        let globalVideoList = GlobalContext.getContext().getObject(
            "globalVideoList"
        ) as VideoItem[]
        let curIndex = this.index - PlayConstants.CONTROL_NEXT
        this.index =
            curIndex === -PlayConstants.CONTROL_NEXT
                ? globalVideoList.length - PlayConstants.CONTROL_NEXT
                : curIndex
        if (this.url) {
            this.url = globalVideoList[this.index].iSrc
        } else {
            this.rawFile = globalVideoList[this.index].src
        }
        this.avPlayer.reset()
    }

    /**
     * Next video.
     */
    nextVideo() {
        if (this.avPlayer == null || this.playerModel == null) {
            return
        }
        if (CommonConstants.OPERATE_STATE.indexOf(this.avPlayer.state) === -1) {
            return
        }
        this.playerModel.playSpeed = PlayConstants.PLAY_SPEED
        let globalVideoList = GlobalContext.getContext().getObject(
            "globalVideoList"
        ) as VideoItem[]
        let curIndex = this.index + PlayConstants.CONTROL_NEXT
        this.index =
            curIndex === globalVideoList.length
                ? PlayConstants.CONTROL_FIRST
                : curIndex
        if (this.url) {
            this.url = globalVideoList[this.index].iSrc
        } else {
            this.rawFile = globalVideoList[this.index].src
        }
        this.avPlayer.reset()
    }

    /**
     * Switching Between Video Play and Pause.
     */
    switchPlayOrPause() {
        if (this.avPlayer == null || this.playerModel == null) {
            return
        }
        if (this.status === CommonConstants.STATUS_START) {
            this.avPlayer.pause()
        } else {
            this.avPlayer.play()
        }
    }

    /**
     * Slide the progress bar to set the playback progress.
     *
     * @param value Value of the slider component.
     * @param mode Slider component change event.
     */
    setSeekTime(value: number, mode: SliderChangeMode) {
        if (this.avPlayer == null || this.playerModel == null) {
            return
        }
        if (mode === Number(SliderMode.MOVING)) {
            this.playerModel.progressVal = value
            this.playerModel.currentTime = DateFormatUtil.secondToTime(
                Math.floor(
                    (value * this.duration) /
                        CommonConstants.ONE_HUNDRED /
                        CommonConstants.A_THOUSAND
                )
            )
        }
        if (
            mode === Number(SliderMode.END) ||
            mode === Number(SliderMode.CLICK)
        ) {
            this.seekTime =
                (value * this.duration) / CommonConstants.ONE_HUNDRED
            if (this.avPlayer !== null) {
                this.avPlayer.seek(this.seekTime, media.SeekMode.SEEK_PREV_SYNC)
            }
        }
    }

    /**
     * Setting the brightness.
     */
    setBright() {
        if (this.playerModel == null) {
            return
        }
        let windowClass = GlobalContext.getContext().getObject(
            "windowClass"
        ) as window.Window
        windowClass.setWindowBrightness(this.playerModel.bright)
    }

    /**
     * Obtains the current video playing status.
     */
    getStatus() {
        return this.status
    }

    /**
     * Initialization progress bar.
     *
     * @param time Current video playback time.
     */
    initProgress(time: number) {
        if (this.playerModel == null) {
            return
        }
        let nowSeconds = Math.floor(time / CommonConstants.A_THOUSAND)
        let totalSeconds = Math.floor(
            this.duration / CommonConstants.A_THOUSAND
        )
        this.playerModel.currentTime = DateFormatUtil.secondToTime(nowSeconds)
        this.playerModel.totalTime = DateFormatUtil.secondToTime(totalSeconds)
        this.playerModel.progressVal = Math.floor(
            (nowSeconds * CommonConstants.ONE_HUNDRED) / totalSeconds
        )
    }

    /**
     * Reset progress bar data.
     */
    resetProgress() {
        if (this.playerModel == null) {
            return
        }
        this.seekTime = PlayConstants.PROGRESS_SEEK_TIME
        this.playerModel.currentTime = PlayConstants.PROGRESS_CURRENT_TIME
        this.playerModel.progressVal = PlayConstants.PROGRESS_PROGRESS_VAL
    }

    /**
     * Volume gesture method onActionStart.
     *
     * @param event Gesture event.
     */
    onVolumeActionStart(event?: GestureEvent) {
        if (!event) {
            return
        }
        this.positionX = event.offsetX
    }

    /**
     * Bright gesture method onActionStart.
     *
     * @param event Gesture event.
     */
    onBrightActionStart(event?: GestureEvent) {
        if (!event) {
            return
        }
        this.positionY = event.offsetY
    }

    /**
     * Gesture method onActionUpdate.
     *
     * @param event Gesture event.
     */
    onVolumeActionUpdate(event?: GestureEvent) {
        if (!event) {
            return
        }
        if (this.avPlayer == null || this.playerModel == null) {
            return
        }
        if (CommonConstants.OPERATE_STATE.indexOf(this.avPlayer.state) === -1) {
            return
        }
        if (this.playerModel.brightShow === false) {
            this.playerModel.volumeShow = true
            let screenWidth = GlobalContext.getContext().getObject(
                "screenWidth"
            ) as number
            let changeVolume = (event.offsetX - this.positionX) / screenWidth
            let volume: number = this.playerModel.volume
            let currentVolume = volume + changeVolume
            let volumeMinFlag = currentVolume <= PlayConstants.MIN_VALUE
            let volumeMaxFlag = currentVolume > PlayConstants.MAX_VALUE
            this.playerModel.volume = volumeMinFlag
                ? PlayConstants.MIN_VALUE
                : volumeMaxFlag
                ? PlayConstants.MAX_VALUE
                : currentVolume
            this.avPlayer.setVolume(this.playerModel.volume)
            this.positionX = event.offsetX
        }
    }

    /**
     * Gesture method onActionUpdate.
     *
     * @param event Gesture event.
     */
    onBrightActionUpdate(event?: GestureEvent) {
        if (!event || this.playerModel == null) {
            return
        }
        if (this.playerModel.volumeShow === false) {
            this.playerModel.brightShow = true
            let screenHeight = GlobalContext.getContext().getObject(
                "screenHeight"
            ) as number
            let changeBright = (this.positionY - event.offsetY) / screenHeight
            let bright: number = this.playerModel.bright
            let currentBright = bright + changeBright
            let brightMinFlag = currentBright <= PlayConstants.MIN_VALUE
            let brightMaxFlag = currentBright > PlayConstants.MAX_VALUE
            this.playerModel.bright = brightMinFlag
                ? PlayConstants.MIN_VALUE
                : brightMaxFlag
                ? PlayConstants.MAX_VALUE
                : currentBright
            this.setBright()
            this.positionY = event.offsetY
        }
    }

    /**
     * Gesture method onActionEnd.
     */
    onActionEnd() {
        setTimeout(() => {
            if (this.playerModel) {
                this.playerModel.volumeShow = false
                this.playerModel.brightShow = false
            }
            this.positionX = PlayConstants.POSITION_X
            this.positionY = PlayConstants.POSITION_Y
        }, PlayConstants.DISAPPEAR_TIME)
    }

    /**
     * Sets whether the screen is a constant based on the playback status.
     */
    watchStatus() {
        let windowClass = GlobalContext.getContext().getObject(
            "windowClass"
        ) as window.Window
        if (this.status === CommonConstants.STATUS_START) {
            windowClass.setWindowKeepScreenOn(true)
        } else {
            windowClass.setWindowKeepScreenOn(false)
        }
    }

    /**
     * Sets the playback page size based on the video size.
     */
    setVideoSize() {
        if (this.avPlayer == null || this.playerModel == null) {
            return
        }
        if (this.avPlayer.height > this.avPlayer.width) {
            this.playerModel.videoWidth = PlayConstants.PLAY_PLAYER_HEIGHT_FULL
            this.playerModel.videoHeight = PlayConstants.PLAY_PLAYER_HEIGHT_FULL
            this.playerModel.videoPosition = FlexAlign.Start
            this.playerModel.videoMargin = PlayConstants.HEIGHT
        } else {
            this.playerModel.videoWidth = CommonConstants.FULL_PERCENT
            this.playerModel.videoHeight = PlayConstants.PLAY_PLAYER_HEIGHT
            this.playerModel.videoPosition = FlexAlign.Center
            this.playerModel.videoMargin = PlayConstants.MARGIN_ZERO
        }
    }

    /**
     * An error is reported during network video playback.
     */
    playError() {
        prompt.showToast({
            duration: PlayConstants.PLAY_ERROR_TIME,
            message: $r("app.string.link_check_address_internet"),
        })
    }

    sendInitialized(): void {
        Log.i(TAG, "sendInitialized")
        let event: HashMap<string, Object> = new HashMap<string, Object>()
        event.set("event", "initialized")
        event.set("duration", this.avPlayer?.duration)
        event.set("width", this.avPlayer?.width)
        event.set("height", this.avPlayer?.height)
        this.eventSink?.success(event)
    }

    sendCompleted(): void {
        let event: HashMap<string, Object> = new HashMap<string, Object>()
        event.set("event", "completed")
        this.eventSink?.success(event)
    }

    sendBufferingUpdate(
        infoType: media.BufferingInfoType,
        bufferingPosition: number
    ): void {
        let event: HashMap<string, Object> = new HashMap<string, Object>()
        if (infoType == media.BufferingInfoType.BUFFERING_START) {
            event.set("event", "bufferingStart")
        } else if (infoType == media.BufferingInfoType.BUFFERING_END) {
            event.set("event", "bufferingEnd")
        } else if (infoType == media.BufferingInfoType.CACHED_DURATION) {
            event.set("event", "cachedDuration")
        } else {
            event.set("event", "bufferingUpdate")
            let range: ArrayList<number> = new ArrayList<number>()
            range.add(0)
            range.add(bufferingPosition)
            let valuesList: ArrayList<ArrayList<number>> = new ArrayList<
                ArrayList<number>
            >()
            valuesList.add(range)
            event.set("values", valuesList)
        }
        this.eventSink?.success(event)
    }

    sendError(error: Object): void {
        this.eventSink?.error("videoError", "video player had error！", error)
    }

    getIUri(): string {
        let iUrl = this.url
        const ohosFilePrefix = "file://"
        if (iUrl != null && iUrl.startsWith(ohosFilePrefix)) {
            this.fd = fs.openSync(iUrl, fs.OpenMode.READ_ONLY).fd
            iUrl = `fd://${this.fd!.toString()}`
        }
        return iUrl ?? ""
    }
}

class StreamHandlerImpl implements StreamHandler {
    private eventSink: QueuingEventSink | null = null

    constructor(eventSink: QueuingEventSink) {
        this.eventSink = eventSink
    }

    onListen(args: Object, events: EventSink): void {
        this.eventSink?.setDelegate(events)
    }

    onCancel(args: Object): void {
        this.eventSink?.setDelegate(null)
    }
}
