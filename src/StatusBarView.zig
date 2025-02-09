const Colors = @import("Colors.zig");

const vaxis = @import("vaxis");
const Window = vaxis.Window;
const Segment = vaxis.Segment;

const StatusBarView = @This();

left_text: []const u8,
right_text: []const u8,

pub const height = 1;

pub fn window(parent: Window) Window {
    return parent.child(.{
        .x_off = 0,
        .y_off = parent.height - height,
        .width = parent.width,
        .height = height,
    });
}

pub fn draw(self: *StatusBarView, win: Window, colors: *Colors) void {
    win.fill(.{ .style = .{ .bg = colors.bg_status_bar } });

    _ = win.printSegment(
        .{
            .text = self.left_text,
            .style = .{ .bg = colors.bg_status_bar },
        },
        .{},
    );

    const right_status_bar_segment = win.child(.{
        .x_off = @intCast(win.width - self.right_text.len),
        .width = @intCast(self.right_text.len),
        .height = win.height,
    });
    _ = right_status_bar_segment.printSegment(
        .{
            .text = self.right_text,
            .style = .{ .bg = colors.bg_status_bar },
        },
        .{},
    );
}
