from pathlib import Path
import re, subprocess
r=Path(__file__).resolve().parent
source=(r/'mpv/video/out/vo_ohcodec.c').read_text()
source=re.sub(r'^#include.*$', '', source, flags=re.M)
stubs=r"""
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <errno.h>
#define AVERROR(x) (-(x))
#define AV_HWDEVICE_TYPE_OHCODEC 1
#define IMGFMT_OHCODEC 42
#define VO_TRUE 1
#define VO_NOTIMPL 0
#define VOCTRL_RESET 1
#define VO_CAP_NORETAIN 4
#define VO_CAP_UNTIMED 16
#define MP_INFO(...) ((void)0)
#define MP_WARN(...) ((void)0)
typedef struct { bool released; int rendered, discarded, error; } AVOHCodecBuffer;
struct mp_image { void *planes[4]; int refs; };
struct mp_image_params { int dummy; };
struct vo_frame { struct mp_image *current; bool redraw, repeat; };
typedef struct { void *native_window; } AVOHCodecDeviceContext;
typedef struct { void *hwctx; } AVHWDeviceContext;
typedef struct { void *data; } AVBufferRef;
struct mp_hwdec_ctx { const char *driver_name; AVBufferRef *av_device_ref; int hw_imgfmt; };
struct vo { void *priv, *hwdec_devs; bool window; };
static int devices, windows, buffers, fail_alloc, fail_init;
static bool vo_ohos_init(struct vo *v) { v->window=true; windows++; return true; }
static void vo_ohos_uninit(struct vo *v) { if(v->window)windows--; v->window=false; }
static void *vo_ohos_native_window(struct vo *v) { return v; }
static void vo_ohos_invalidate_color(struct vo *v) {}
static bool vo_ohos_set_color(struct vo *v, struct mp_image_params *p) { return true; }
static void *hwdec_devices_create(void) { devices++; return malloc(1); }
static void hwdec_devices_destroy(void *p) { if(p){ devices--;free(p); } }
static void hwdec_devices_add(void *d, struct mp_hwdec_ctx *c) {}
static void hwdec_devices_remove(void *d, struct mp_hwdec_ctx *c) {}
static AVBufferRef *av_hwdevice_ctx_alloc(int t) {
 if(fail_alloc)return NULL;
 AVBufferRef *r=calloc(1,sizeof(*r));
 AVHWDeviceContext *c=calloc(1,sizeof(*c)); c->hwctx=calloc(1,sizeof(AVOHCodecDeviceContext));
 r->data=c; buffers++; return r;
}
static int av_hwdevice_ctx_init(AVBufferRef *r) { return fail_init ? -1 : 0; }
static void av_buffer_unref(AVBufferRef **r) { if(!*r)return; AVHWDeviceContext *c=(*r)->data;free(c->hwctx);free(c);free(*r);*r=NULL;buffers--; }
static int av_ohcodec_release_buffer(AVOHCodecBuffer *t,int render) {
 if(t->released)return render ? AVERROR(EALREADY):0;
 t->released=true;
 if(render && !t->error)t->rendered++; else t->discarded++;
 return t->error;
}
static struct mp_image *mp_image_new_ref(struct mp_image *p) { p->refs++;return p; }
static void mp_image_unrefp(struct mp_image **p) {
 if(!*p)return;
 if(--(*p)->refs==0)av_ohcodec_release_buffer((*p)->planes[3],0);
 *p=NULL;
}
struct vo_driver {
 const char *description,*name; int caps;
 int (*preinit)(struct vo*),(*query_format)(struct vo*,int),(*reconfig)(struct vo*,struct mp_image_params*),(*control)(struct vo*,uint32_t,void*);
 bool (*draw_frame)(struct vo*,struct vo_frame*);
 void (*flip_page)(struct vo*),(*uninit)(struct vo*);size_t priv_size;
};
"""
cases=r"""
int main(void) {
 struct priv p={0}; struct vo v={.priv=&p};
 assert(!(video_out_ohcodec.caps & VO_CAP_UNTIMED));
 assert(query_format(&v,42) && !query_format(&v,1));
 fail_alloc=1;assert(preinit(&v)<0);assert(!windows&&!devices&&!buffers);fail_alloc=0;
 fail_init=1;assert(preinit(&v)<0);assert(!windows&&!devices&&!buffers);fail_init=0;
 assert(preinit(&v)==0);
 for(int i=0;i<1000;i++) {
  AVOHCodecBuffer a={0};struct mp_image image={.planes={0,0,0,&a}};struct vo_frame f={.current=&image};
  draw_frame(&v,&f);flip_page(&v);flip_page(&v);
  assert(a.rendered==1 && a.discarded==0 && image.refs==0);
  f.redraw=true;draw_frame(&v,&f);flip_page(&v);assert(a.rendered==1);
  f.redraw=false;f.repeat=true;draw_frame(&v,&f);flip_page(&v);assert(a.rendered==1);
  AVOHCodecBuffer b={0};struct mp_image img2={.planes={0,0,0,&b}};f=(struct vo_frame){.current=&img2};
  draw_frame(&v,&f);control(&v,VOCTRL_RESET,NULL);flip_page(&v);
  assert(b.rendered==0 && b.discarded==1 && img2.refs==0);
  AVOHCodecBuffer c={.error=AVERROR(ESTALE)};struct mp_image img3={.planes={0,0,0,&c}};f.current=&img3;
  draw_frame(&v,&f);flip_page(&v);assert(c.rendered==0 && c.discarded==1 && img3.refs==0);
 }
 AVOHCodecBuffer d={0};struct mp_image img4={.planes={0,0,0,&d}};struct vo_frame f={.current=&img4};
 draw_frame(&v,&f);uninit(&v);assert(d.discarded==1 && !windows && !devices && !buffers);
 puts("PASS: 1000 present/reset/stale/redraw/repeat cycles; init failures and teardown release all mock resources; timed VO");
}
"""
p=r/'build/test_direct_lifecycle.c';p.parent.mkdir(exist_ok=True);p.write_text(stubs+source+cases)
exe=r/'build/test_direct_lifecycle'
subprocess.run(['cc','-std=c11','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer',str(p),'-o',str(exe)],check=True)
subprocess.run([str(exe)],check=True)
