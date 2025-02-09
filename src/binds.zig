const vaxis = @import("vaxis");
const VKey = vaxis.Key;

pub const Key = struct {
    cps: []const u21, // codepoints
    mods: VKey.Modifiers = .{},
};

pub const BindAction = enum {
    quit,
    move_down,
    move_up,
    toggle_expanded,
    reload,
    open_in_editor,
    sidebar_width_dec,
    sidebar_width_inc,

    pub fn name(self: BindAction) []const u8 {
        return switch (self) {
            .quit, .reload => @tagName(self),
            .move_down => "move down",
            .move_up => "move up",
            .toggle_expanded => "toggle expanded",
            .open_in_editor => "open in editor",
            .sidebar_width_dec => "decrease sidebar width",
            .sidebar_width_inc => "increase sidebar width",
        };
    }
};

pub const KeyBinding = struct {
    keys: Key,
    action: BindAction,
    show_hint: bool = true,
};

pub const bindings: []const KeyBinding = &.{
    .{
        .keys = .{ .cps = &.{ 'q', VKey.escape } },
        .action = .quit,
    },
    .{
        .keys = .{ .cps = &.{'c'}, .mods = .{ .ctrl = true } },
        .action = .quit,
        .show_hint = false,
    },
    .{
        .keys = .{ .cps = &.{ 'j', VKey.down } },
        .action = .move_down,
    },
    .{
        .keys = .{ .cps = &.{ 'k', VKey.up } },
        .action = .move_up,
    },
    .{
        .keys = .{ .cps = &.{VKey.tab} },
        .action = .toggle_expanded,
    },
    .{
        .keys = .{ .cps = &.{'r'} },
        .action = .reload,
    },
    .{
        .keys = .{ .cps = &.{VKey.enter} },
        .action = .open_in_editor,
        .show_hint = false,
    },
    .{
        .keys = .{ .cps = &.{'<'} },
        .action = .sidebar_width_dec,
        .show_hint = false,
    },
    .{
        .keys = .{ .cps = &.{'>'} },
        .action = .sidebar_width_inc,
        .show_hint = false,
    },
};
