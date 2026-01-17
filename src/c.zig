const tag = @import("builtin").os.tag;

pub const c = @cImport({
    if (tag == .linux or tag == .freebsd or tag == .netbsd or tag == .openbsd) {
        @cInclude("X11/Xlib.h");
    } else {
        @compileError("anne_x11 currently supports only Unix platforms with X11.");
    }
});
