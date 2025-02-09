const StatusBarView = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

const Colors = @import("Colors.zig");
const binds = @import("binds.zig");

const vaxis = @import("vaxis");
const Window = vaxis.Window;
const Segment = vaxis.Segment;

pub const height = 1;

pub fn window(parent: Window) Window {
    return parent.child(.{
        .x_off = 0,
        .y_off = parent.height - height,
        .width = parent.width,
        .height = height,
    });
}

pub fn draw(self: *StatusBarView, arena: Allocator, win: Window, colors: *Colors) !void {
    win.fill(.{ .style = .{ .bg = colors.bg_status_bar } });

    _ = self;

    var offset: u16 = 0;
    for (binds.bindings) |binding| {
        if (!binding.show_hint) continue;

        for (binding.keys.cps, 0..) |c, idx| {
            var buf = try arena.alloc(u8, 4);

            const str: []const u8 = switch (c) {
                vaxis.Key.escape => "esc",
                vaxis.Key.tab => "tab",
                vaxis.Key.enter => "enter",

                else => for (vaxis.Key.name_map.values(), 0..) |value, i| {
                    if (value == c) {
                        break vaxis.Key.name_map.kvs.keys[i];
                    }
                } else blk: {
                    const count = try std.unicode.utf8Encode(c, buf);
                    break :blk buf[0..count];
                },
            };

            var res = win.printSegment(
                .{
                    .text = str,
                    .style = .{ .bg = colors.bg_status_bar_hl },
                },
                .{
                    .col_offset = offset,
                },
            );
            offset = res.col;

            if (idx != binding.keys.cps.len - 1) {
                res = win.printSegment(
                    .{
                        .text = ",",
                        .style = .{ .bg = colors.bg_status_bar_hl },
                    },
                    .{
                        .col_offset = offset,
                    },
                );
                offset = res.col;
            }
        }

        var res = win.printSegment(
            .{
                .text = " → ",
                .style = .{ .bg = colors.bg_status_bar_hl },
            },
            .{
                .col_offset = offset,
            },
        );
        offset = res.col;

        res = win.printSegment(
            .{
                .text = binding.action.name(),
                .style = .{ .bg = colors.bg_status_bar_hl },
            },
            .{
                .col_offset = offset,
            },
        );
        offset = res.col;

        res = win.printSegment(
            .{
                .text = " ",
                .style = .{ .bg = colors.bg_status_bar },
            },
            .{
                .col_offset = offset,
            },
        );
        offset = res.col;
    }
}
