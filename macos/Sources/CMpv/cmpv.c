#include "zemu_mpv.h"
#include <dlfcn.h>
#include <stddef.h>

static int loaded = 0;

#define FN(ret, name, params, args) \
    static ret (*p_##name) params = NULL; \
    ret name params { return p_##name args; }
#define VFN(name, params, args) \
    static void (*p_##name) params = NULL; \
    void name params { p_##name args; }

FN(unsigned long, mpv_client_api_version, (void), ())
FN(const char *, mpv_error_string, (int error), (error))
VFN(mpv_free, (void *data), (data))
FN(mpv_handle *, mpv_create, (void), ())
FN(int, mpv_initialize, (mpv_handle *ctx), (ctx))
VFN(mpv_terminate_destroy, (mpv_handle *ctx), (ctx))
FN(int, mpv_set_option_string, (mpv_handle *ctx, const char *name, const char *data), (ctx, name, data))
FN(int, mpv_command, (mpv_handle *ctx, const char **args), (ctx, args))
FN(int, mpv_command_async, (mpv_handle *ctx, uint64_t reply_userdata, const char **args), (ctx, reply_userdata, args))
FN(int, mpv_set_property, (mpv_handle *ctx, const char *name, mpv_format format, void *data), (ctx, name, format, data))
FN(int, mpv_set_property_string, (mpv_handle *ctx, const char *name, const char *data), (ctx, name, data))
FN(int, mpv_get_property, (mpv_handle *ctx, const char *name, mpv_format format, void *data), (ctx, name, format, data))
FN(char *, mpv_get_property_string, (mpv_handle *ctx, const char *name), (ctx, name))
FN(int, mpv_observe_property, (mpv_handle *mpv, uint64_t reply_userdata, const char *name, mpv_format format), (mpv, reply_userdata, name, format))
FN(int, mpv_request_log_messages, (mpv_handle *ctx, const char *min_level), (ctx, min_level))
FN(mpv_event *, mpv_wait_event, (mpv_handle *ctx, double timeout), (ctx, timeout))
VFN(mpv_wakeup, (mpv_handle *ctx), (ctx))
VFN(mpv_set_wakeup_callback, (mpv_handle *ctx, void (*cb)(void *d), void *d), (ctx, cb, d))
FN(int, mpv_render_context_create, (mpv_render_context **res, mpv_handle *mpv, mpv_render_param *params), (res, mpv, params))
VFN(mpv_render_context_set_update_callback, (mpv_render_context *ctx, mpv_render_update_fn callback, void *callback_ctx), (ctx, callback, callback_ctx))
FN(uint64_t, mpv_render_context_update, (mpv_render_context *ctx), (ctx))
FN(int, mpv_render_context_render, (mpv_render_context *ctx, mpv_render_param *params), (ctx, params))
VFN(mpv_render_context_report_swap, (mpv_render_context *ctx), (ctx))
VFN(mpv_render_context_free, (mpv_render_context *ctx), (ctx))

#define LOAD(name) if (!(p_##name = dlsym(h, #name))) return 0;

static int resolve(void *h) {
    LOAD(mpv_client_api_version) LOAD(mpv_error_string) LOAD(mpv_free) LOAD(mpv_create)
    LOAD(mpv_initialize) LOAD(mpv_terminate_destroy) LOAD(mpv_set_option_string) LOAD(mpv_command)
    LOAD(mpv_command_async) LOAD(mpv_set_property) LOAD(mpv_set_property_string) LOAD(mpv_get_property)
    LOAD(mpv_get_property_string) LOAD(mpv_observe_property) LOAD(mpv_request_log_messages)
    LOAD(mpv_wait_event) LOAD(mpv_wakeup) LOAD(mpv_set_wakeup_callback) LOAD(mpv_render_context_create)
    LOAD(mpv_render_context_set_update_callback) LOAD(mpv_render_context_update)
    LOAD(mpv_render_context_render) LOAD(mpv_render_context_report_swap) LOAD(mpv_render_context_free)
    return 1;
}

const char *zm_mpv_load(const char *const *paths) {
    if (loaded) return "already loaded";
    for (int i = 0; paths[i] != NULL; i++) {
        void *h = dlopen(paths[i], RTLD_NOW | RTLD_LOCAL);
        if (!h) continue;
        if (resolve(h)) {
            loaded = 1;
            return paths[i];
        }
        dlclose(h);
    }
    return NULL;
}

int zm_mpv_loaded(void) { return loaded; }

void *zm_gl_get_proc_address(void *ctx, const char *name) {
    static void *gl = NULL;
    if (!gl) gl = dlopen("/System/Library/Frameworks/OpenGL.framework/OpenGL", RTLD_LAZY | RTLD_LOCAL);
    return gl ? dlsym(gl, name) : NULL;
}
