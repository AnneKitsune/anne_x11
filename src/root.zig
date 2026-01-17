const std = @import("std");
pub const c = @import("c.zig").c;
pub const x11 = @import("x11/window.zig");

pub const X11Window = x11.X11Window;
pub const InitOptions = x11.InitOptions;
pub const Dimensions = x11.Dimensions;
pub const Motion = x11.Motion;

test {
    _ = @import("x11/window.zig");
}
