export const add: (a: number, b: number) => number;
export const getsrt: (a: any) => any;
export class JSBind{

     static bindFunction: (param: string,func: (code: number, msg: string) => void) => void

}
export const executeFFmpegCommandAPP:(a:string,b:number,c:any)=>any;
export const executeFFmpegCommandAPP2:(a:string,b:number,c:any)=>any;
export const get_video_duration:(a:string)=>any;
// 读取元信息
export const getTitle: (filename: string) => any;
export const getArtist: (filename: string) => any;
export const getAlbum: (filename: string) => any;
export const getYear: (filename: string) => any;
export const getTrack: (filename: string) => any;
export const getDisc: (filename: string) => any;
export const getGenre: (filename: string) => any;
export const getAlbumArtist: (filename: string) => any;
export const getComposer: (filename: string) => any;
export const getLyricist: (filename: string) => any;
export const getComment: (filename: string) => any;
export const getLyrics: (filename: string) => any;
export const getCover: (filename: string) => any;

// 写入元信息
export const setTitle: (filename: string, title: string) => any;
export const setArtist: (filename: string, artist: string) => any;
export const setAlbum: (filename: string, album: string) => any;
export const setYear: (filename: string, year: number) => any;
export const setTrack: (filename: string, track: number) => any;
export const setDisc: (filename: string, disc: number) => any;
export const setGenre: (filename: string, genre: string) => any;
export const setAlbumArtist: (filename: string, albumArtist: string) => any;
export const setComposer: (filename: string, composer: string) => any;
export const setLyricist: (filename: string, lyricist: string) => any;
export const setComment: (filename: string, comment: string) => any;
export const setLyrics: (filename: string, lyrics: string) => any;
export const setCover: (filename: string, coverBase64: string) => any;

export const init_libass: (assFilename: string, width: number, height: number) => any;
export const get_png_data_at_time: (time: number, width: number, height: number) => any;
export const cleanup_libass: () => any;
