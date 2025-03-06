/*
 * @Author: 
 * @Date: 2025-02-19 14:58:38
 * @LastEditors: Please set LastEditors
 * @LastEditTime: 2025-02-19 15:48:56
 * @Description: file content
 */
/*
 * Copyright (C) 2006 Evgeniy Stepanov <eugeni.stepanov@gmail.com>
 * Copyright (C) 2009 Grigori Goronzy <greg@geekmind.org>
 *
 * This file is part of libass.
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 */

 #include <stdio.h>
 #include <stdlib.h>
 #include <stdarg.h>
 #include <string.h>
 #include <ass/ass.h>
 #include <png.h>
 #include "asstest.h"
 
 typedef struct image_s {
     int width, height, stride;
     unsigned char *buffer;      // RGB24
 } image_t;
 
 ASS_Library *ass_library;
 ASS_Renderer *ass_renderer;
 ASS_Track *track;
 void msg_callback(int level, const char *fmt, va_list va, void *data)
 {
     if (level > 6)
         return;
     printf("libass: ");
     vprintf(fmt, va);
     printf("\n");
 }
 
 static void write_png(char *fname, image_t *img)
 {
     FILE *fp;
     png_structp png_ptr;
     png_infop info_ptr;
     png_byte **row_pointers;
     int k;
 
     png_ptr =
         png_create_write_struct(PNG_LIBPNG_VER_STRING, NULL, NULL, NULL);
     info_ptr = png_create_info_struct(png_ptr);
     fp = NULL;
 
     if (setjmp(png_jmpbuf(png_ptr))) {
         png_destroy_write_struct(&png_ptr, &info_ptr);
         fclose(fp);
         return;
     }
 
     fp = fopen(fname, "wb");
     if (fp == NULL) {
         printf("PNG Error opening %s for writing!\n", fname);
         return;
     }
 
     png_init_io(png_ptr, fp);
     png_set_compression_level(png_ptr, 0);
 
     png_set_IHDR(png_ptr, info_ptr, img->width, img->height,
                  8, PNG_COLOR_TYPE_RGB, PNG_INTERLACE_NONE,
                  PNG_COMPRESSION_TYPE_DEFAULT, PNG_FILTER_TYPE_DEFAULT);
 
     png_write_info(png_ptr, info_ptr);
 
     png_set_bgr(png_ptr);
 
     row_pointers = malloc(img->height * sizeof(png_byte *));
     for (k = 0; k < img->height; k++)
         row_pointers[k] = img->buffer + img->stride * k;
 
     png_write_image(png_ptr, row_pointers);
     png_write_end(png_ptr, info_ptr);
     png_destroy_write_struct(&png_ptr, &info_ptr);
 
     free(row_pointers);
 
     fclose(fp);
 }

 static char *write_png_to_base64(image_t *img)
 {
     png_structp png_ptr;
     png_infop info_ptr;
     png_byte **row_pointers;
     int k;
 
     // 创建一个内存缓冲区来存储 PNG 数据
     png_byte *buffer = NULL;
     size_t buffer_size = 0;
     FILE *fp = open_memstream((char **)&buffer, &buffer_size);
 
     if (fp == NULL) {
         printf("Error creating memory stream!\n");
         return NULL;
     }
 
     png_ptr = png_create_write_struct(PNG_LIBPNG_VER_STRING, NULL, NULL, NULL);
     info_ptr = png_create_info_struct(png_ptr);
 
     if (setjmp(png_jmpbuf(png_ptr))) {
         png_destroy_write_struct(&png_ptr, &info_ptr);
         fclose(fp);
         free(buffer);
         return NULL;
     }
 
     png_init_io(png_ptr, fp);
     png_set_compression_level(png_ptr, 0);
 
     png_set_IHDR(png_ptr, info_ptr, img->width, img->height,
                  8, PNG_COLOR_TYPE_RGB, PNG_INTERLACE_NONE,
                  PNG_COMPRESSION_TYPE_DEFAULT, PNG_FILTER_TYPE_DEFAULT);
 
     png_write_info(png_ptr, info_ptr);
 
     png_set_bgr(png_ptr);
 
     row_pointers = malloc(img->height * sizeof(png_byte *));
     for (k = 0; k < img->height; k++)
         row_pointers[k] = img->buffer + img->stride * k;
 
     png_write_image(png_ptr, row_pointers);
     png_write_end(png_ptr, info_ptr);
     png_destroy_write_struct(&png_ptr, &info_ptr);
 
     free(row_pointers);
 
     // 关闭内存流并获取缓冲区内容
     fclose(fp);
 
     // Base64 编码
     const char *base64_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
     size_t base64_size = 4 * ((buffer_size + 2) / 3);
     char *base64_data = malloc(base64_size + 1);
     if (base64_data == NULL) {
         free(buffer);
         return NULL;
     }
 
     for (size_t i = 0, j = 0; i < buffer_size; i += 3, j += 4) {
         uint32_t triplet = (buffer[i] << 16) | (i + 1 < buffer_size ? buffer[i + 1] << 8 : 0) | (i + 2 < buffer_size ? buffer[i + 2] : 0);
         base64_data[j] = base64_chars[(triplet >> 18) & 0x3F];
         base64_data[j + 1] = base64_chars[(triplet >> 12) & 0x3F];
         base64_data[j + 2] = i + 1 < buffer_size ? base64_chars[(triplet >> 6) & 0x3F] : '=';
         base64_data[j + 3] = i + 2 < buffer_size ? base64_chars[triplet & 0x3F] : '=';
     }
     base64_data[base64_size] = '\0';
 
     free(buffer);
 
     return base64_data;
 }
 
 static void init(int frame_w, int frame_h)
 {
     ass_library = ass_library_init();
     if (!ass_library) {
         printf("ass_library_init failed!\n");
         exit(1);
     }
 
     ass_set_message_cb(ass_library, msg_callback, NULL);
     ass_set_extract_fonts(ass_library, 1);
 
     ass_renderer = ass_renderer_init(ass_library);
     if (!ass_renderer) {
         printf("ass_renderer_init failed!\n");
         exit(1);
     }
 
     ass_set_storage_size(ass_renderer, frame_w, frame_h);
     ass_set_frame_size(ass_renderer, frame_w, frame_h);
     ass_set_fonts(ass_renderer, NULL, "sans-serif",
                   ASS_FONTPROVIDER_AUTODETECT, NULL, 1);
 }
 
 static image_t *gen_image(int width, int height)
 {
     image_t *img = malloc(sizeof(image_t));
     img->width = width;
     img->height = height;
     img->stride = width * 3;
     img->buffer = calloc(1, height * width * 3);
     memset(img->buffer, 63, img->stride * img->height);
     //for (int i = 0; i < height * width * 3; ++i)
     // img->buffer[i] = (i/3/50) % 100;
     return img;
 }
 
 #define _r(c)  ((c)>>24)
 #define _g(c)  (((c)>>16)&0xFF)
 #define _b(c)  (((c)>>8)&0xFF)
 #define _a(c)  ((c)&0xFF)
 
 static void blend_single(image_t * frame, ASS_Image *img)
 {
     int x, y;
     unsigned char opacity = 255 - _a(img->color);
     unsigned char r = _r(img->color);
     unsigned char g = _g(img->color);
     unsigned char b = _b(img->color);
 
     unsigned char *src;
     unsigned char *dst;
 
     src = img->bitmap;
     dst = frame->buffer + img->dst_y * frame->stride + img->dst_x * 3;
     for (y = 0; y < img->h; ++y) {
         for (x = 0; x < img->w; ++x) {
             unsigned k = ((unsigned) src[x]) * opacity / 255;
             // possible endianness problems
             dst[x * 3] = (k * b + (255 - k) * dst[x * 3]) / 255;
             dst[x * 3 + 1] = (k * g + (255 - k) * dst[x * 3 + 1]) / 255;
             dst[x * 3 + 2] = (k * r + (255 - k) * dst[x * 3 + 2]) / 255;
         }
         src += img->stride;
         dst += frame->stride;
     }
 }
 
 static void blend(image_t * frame, ASS_Image *img)
 {
     int cnt = 0;
     while (img) {
         blend_single(frame, img);
         ++cnt;
         img = img->next;
     }
     printf("%d images blended\n", cnt);
 }
 
 char *font_provider_labels[] = {
     [ASS_FONTPROVIDER_NONE]       = "None",
     [ASS_FONTPROVIDER_AUTODETECT] = "Autodetect",
     [ASS_FONTPROVIDER_CORETEXT]   = "CoreText",
     [ASS_FONTPROVIDER_FONTCONFIG] = "Fontconfig",
     [ASS_FONTPROVIDER_DIRECTWRITE]= "DirectWrite",
 };
 
 static void print_font_providers(ASS_Library *ass_library)
 {
     int i;
     ASS_DefaultFontProvider *providers;
     size_t providers_size = 0;
     ass_get_available_font_providers(ass_library, &providers, &providers_size);
     printf("test.c: Available font providers (%zu): ", providers_size);
     for (i = 0; i < providers_size; i++) {
         const char *separator = i > 0 ? ", ": "";
         printf("%s'%s'", separator,  font_provider_labels[providers[i]]);
     }
     printf(".\n");
     free(providers);
 }
 
 int initassinner(const char * subfile, int frame_w , int frame_h)
 {

     print_font_providers(ass_library);
 
     init(frame_w, frame_h);
     track = ass_read_file(ass_library, subfile, NULL);
     if (!track) {
         printf("track init failed!\n");
         return 0;
     }
 
     
 
     return 1;
 }
 
char* getPng(int tm,int frame_w , int frame_h){
    ASS_Image *img =
         ass_render_frame(ass_renderer, track,tm, NULL);
     image_t *frame = gen_image(frame_w, frame_h);
     blend(frame, img);
 
    //  ass_free_track(track);
    //  ass_renderer_done(ass_renderer);
    //  ass_library_done(ass_library);
 
    //  write_png("/storage/Users/currentUser/Download/com.aloereed.aloeplayer/test.png", frame);

     char *base64_data = write_png_to_base64(frame);
     free(frame->buffer);
     free(frame);
    //  cleanupinner();
     return base64_data;
     
}

void cleanupinner(){
    ass_free_track(track);
    ass_renderer_done(ass_renderer);
    ass_library_done(ass_library);
}