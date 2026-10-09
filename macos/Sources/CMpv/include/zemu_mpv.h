#ifndef ZEMU_MPV_H
#define ZEMU_MPV_H

#include "mpv/client.h"
#include "mpv/render.h"
#include "mpv/render_gl.h"

/*
 * libmpv is loaded at runtime (dlopen) instead of being linked, so Zemu builds and runs without
 * it and falls back to AVPlayer. The mpv_* functions declared in the headers above are defined in
 * cmpv.c as trampolines into the loaded library; call them only after zm_mpv_load() succeeds.
 */

/** Tries each path in order (NULL-terminated). Returns the path that loaded, or NULL. */
const char *zm_mpv_load(const char *const *paths);

/** True once a libmpv with every needed symbol has been loaded. */
int zm_mpv_loaded(void);

/** Address of an OpenGL function, for mpv's render API. */
void *zm_gl_get_proc_address(void *ctx, const char *name);

#endif
