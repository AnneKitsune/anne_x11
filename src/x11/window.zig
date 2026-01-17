const std = @import("std");
const c = @import("../c.zig").c;

const EVENT_MASK = c.StructureNotifyMask | c.ExposureMask | c.KeyPressMask | c.KeyReleaseMask | c.ButtonPressMask | c.ButtonReleaseMask | c.PointerMotionMask | c.FocusChangeMask;

pub const Motion = struct {
    dx: i32 = 0,
    dy: i32 = 0,
};

pub const Dimensions = struct {
    width: u32,
    height: u32,
};

pub const InitOptions = struct {
    title: [*:0]const u8 = "anne_x11",
    width: u32 = 800,
    height: u32 = 600,
};

pub const X11Window = struct {
    display: *c.Display,
    screen: c_int,
    root: c.Window,
    window: c.Window,
    delete_atom: c.Atom,
    last_event: c.XEvent = undefined,
    should_close: bool = false,
    resized: bool = false,
    motion: Motion = .{},
    size: Dimensions,
    xinput_opcode: c_int,
    pointer_grabbed: bool = false,

    pub fn init(options: InitOptions) !X11Window {
        try validateDimensions(options.width, options.height);

        const display = c.XOpenDisplay(null) orelse return error.CannotOpenDisplay;
        errdefer _ = c.XCloseDisplay(display);

        const screen = c.DefaultScreen(display);
        const root = c.RootWindow(display, screen);

        var window: c.Window = 0;
        errdefer {
            if (window != 0) _ = c.XDestroyWindow(display, window);
        }

        const black = c.BlackPixel(display, screen);
        const white = c.WhitePixel(display, screen);
        window = c.XCreateSimpleWindow(
            display,
            root,
            0,
            0,
            @intCast(options.width),
            @intCast(options.height),
            1,
            black,
            white,
        );
        _ = c.XSelectInput(display, window, EVENT_MASK);

        _ = c.XMapWindow(display, window);
        _ = c.XStoreName(display, window, options.title);

        var delete_atom = c.XInternAtom(display, "WM_DELETE_WINDOW", 0);
        _ = c.XSetWMProtocols(display, window, &delete_atom, 1);

        // XInput2 removed - raw motion events should be handled by a separate library if needed
        const xinput_opcode: c_int = 0;

        return X11Window{
            .display = display,
            .screen = screen,
            .root = root,
            .window = window,
            .delete_atom = delete_atom,
            .size = .{ .width = options.width, .height = options.height },
            .xinput_opcode = xinput_opcode,
        };
    }

    pub fn update(self: *X11Window) !void {
        self.motion = .{};
        self.resized = false;

        while (c.XPending(self.display) != 0) {
            if (c.XNextEvent(self.display, &self.last_event) != 0) {
                return error.FailedToGetEvent;
            }

            switch (self.last_event.type) {
                c.ClientMessage => {
                    if (self.last_event.xclient.data.l[0] == self.delete_atom) {
                        self.should_close = true;
                    }
                },
                c.MotionNotify => {
                    self.motion.dx = self.last_event.xmotion.x;
                    self.motion.dy = self.last_event.xmotion.y;
                },
                c.ConfigureNotify => {
                    const new_w: u32 = @intCast(self.last_event.xconfigure.width);
                    const new_h: u32 = @intCast(self.last_event.xconfigure.height);
                    if (new_w != self.size.width or new_h != self.size.height) {
                        self.size.width = new_w;
                        self.size.height = new_h;
                        self.resized = true;
                    }
                },
                c.FocusIn => {
                    try self.setPointerGrabbed(true);
                    self.hidePointer();
                },
                c.FocusOut => {
                    try self.setPointerGrabbed(false);
                    self.showPointer();
                },
                else => {},
            }

            try self.handleGenericEvent();
        }
    }

    pub fn deinit(self: *X11Window) void {
        _ = c.XDestroyWindow(self.display, self.window);
        _ = c.XCloseDisplay(self.display);
    }

    pub fn setTitle(self: *X11Window, title: [*:0]const u8) void {
        _ = c.XStoreName(self.display, self.window, title);
    }

    pub fn resize(self: *X11Window, width: u32, height: u32) void {
        if (width == 0 or height == 0) return;
        self.size = .{ .width = width, .height = height };
        _ = c.XResizeWindow(self.display, self.window, @intCast(width), @intCast(height));
    }

    pub fn setPointerGrabbed(self: *X11Window, grabbed: bool) !void {
        if (grabbed and self.pointer_grabbed) return;
        if (!grabbed and !self.pointer_grabbed) return;

        if (grabbed) {
            _ = c.XUngrabPointer(self.display, c.CurrentTime);
            const result = c.XGrabPointer(
                self.display,
                self.window,
                c.True,
                c.ButtonPressMask | c.ButtonReleaseMask | c.PointerMotionMask,
                c.GrabModeAsync,
                c.GrabModeAsync,
                self.window,
                c.None,
                c.CurrentTime,
            );

            switch (result) {
                c.BadCursor => return error.BadCursor,
                c.BadValue => return error.BadValue,
                c.BadWindow => return error.BadWindow,
                c.GrabSuccess => {
                    self.pointer_grabbed = true;
                },
                else => return error.UnexpectedGrabFailure,
            }
        } else {
            _ = c.XUngrabPointer(self.display, c.CurrentTime);
            self.pointer_grabbed = false;
        }

        _ = c.XFlush(self.display);
    }

    pub fn centerPointer(self: *X11Window) void {
        const half_w: c_int = @intCast(self.size.width / 2);
        const half_h: c_int = @intCast(self.size.height / 2);
        _ = c.XWarpPointer(self.display, c.None, self.window, 0, 0, 0, 0, half_w, half_h);
        _ = c.XFlush(self.display);
    }

    pub fn hidePointer(self: *X11Window) void {
        // Xfixes extension not required - this is a no-op
        // If Xfixes support is needed, it should be handled by a separate library
        _ = self;
    }

    pub fn showPointer(self: *X11Window) void {
        // Xfixes extension not required - this is a no-op
        // If Xfixes support is needed, it should be handled by a separate library
        _ = self;
    }

    pub fn maximize(self: *X11Window) void {
        const wm_state = c.XInternAtom(self.display, "_NET_WM_STATE", 0);
        if (wm_state == 0) return;

        var event = std.mem.zeroes(c.XClientMessageEvent);
        event.type = c.ClientMessage;
        event.format = 32;
        event.window = self.window;
        event.message_type = wm_state;
        event.data.l[0] = 2;
        event.data.l[1] = @intCast(c.XInternAtom(self.display, "_NET_WM_STATE_MAXIMIZED_HORZ", 0));
        event.data.l[2] = @intCast(c.XInternAtom(self.display, "_NET_WM_STATE_MAXIMIZED_VERT", 0));
        event.data.l[3] = 1;

        const event_ptr: *c.XEvent = @ptrCast(&event);
        c.XSendEvent(self.display, c.DefaultRootWindow(self.display), 0, c.SubstructureRedirectMask | c.SubstructureNotifyMask, event_ptr);
    }

    pub fn fullscreen(self: *X11Window) void {
        const wm_state = c.XInternAtom(self.display, "_NET_WM_STATE", 0);
        if (wm_state == 0) return;

        const fullscreen_atom = c.XInternAtom(self.display, "_NET_WM_STATE_FULLSCREEN", 0);
        if (fullscreen_atom == 0) return;

        var event = std.mem.zeroes(c.XClientMessageEvent);
        event.type = c.ClientMessage;
        event.format = 32;
        event.window = self.window;
        event.message_type = wm_state;
        event.data.l[0] = 1; // _NET_WM_STATE_ADD
        event.data.l[1] = @intCast(fullscreen_atom);
        event.data.l[2] = 0;
        event.data.l[3] = 0;

        const event_ptr: *c.XEvent = @ptrCast(&event);
        _ = c.XSendEvent(self.display, c.DefaultRootWindow(self.display), 0, c.SubstructureRedirectMask | c.SubstructureNotifyMask, event_ptr);
    }

    fn handleGenericEvent(self: *X11Window) !void {
        // XInput2 removed - raw motion events should be handled by a separate library if needed
        _ = self;
    }
};

fn validateDimensions(width: u32, height: u32) !void {
    if (width == 0 or height == 0) return error.InvalidDimensions;
}

test "init options reject zero dimensions" {
    try std.testing.expectError(error.InvalidDimensions, validateDimensions(0, 10));
    try std.testing.expectError(error.InvalidDimensions, validateDimensions(10, 0));
}

test "create x11 window" {
    var win = try X11Window.init(.{ .title = "anne_x11_test" });
    defer win.deinit();

    for (0..16) |_| {
        try win.update();
    }
}

test "open x11 window for one second" {
    var win = try X11Window.init(.{
        .title = "anne_x11_one_second_test",
        .width = 400,
        .height = 300,
    });
    defer win.deinit();

    const start_time = std.time.nanoTimestamp();
    const one_second_ns: i64 = 1_000_000_000;
    const half_second_ns: i64 = 500_000_000;
    var fullscreened = false;

    while (true) {
        try win.update();
        if (win.should_close) break;

        const elapsed = std.time.nanoTimestamp() - start_time;

        // Fullscreen after 500ms
        if (!fullscreened and elapsed >= half_second_ns) {
            win.fullscreen();
            fullscreened = true;
        }

        if (elapsed >= one_second_ns) break;

        // Small sleep to avoid busy-waiting
        std.Thread.sleep(10_000_000); // 10ms
    }
}
