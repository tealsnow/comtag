const builtin = @import("builtin");
const std = @import("std");
const Allocator = std.mem.Allocator;

const vaxis = @import("vaxis");
const Cell = vaxis.Cell;
const TextInput = vaxis.widgets.TextInput;
const border = vaxis.widgets.border;
const ScrollView = vaxis.widgets.ScrollView;
const Color = vaxis.Color;

// This can contain internal events as well as Vaxis events.
// Internal events can be posted into the same queue as vaxis events to allow
// for a single event loop with exhaustive switching. Booya
const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
    focus_in,
    foo: u8,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    gpa.backing_allocator = std.heap.c_allocator;
    defer {
        if (builtin.mode == .Debug) {
            const deinit_status = gpa.deinit();
            if (deinit_status == .leak) {
                std.log.err("memory leak", .{});
            }
        }
    }
    const alloc = gpa.allocator();

    var tty = try vaxis.Tty.init();
    defer tty.deinit();
    var tty_buffered_writer = tty.bufferedWriter();
    const tty_writer = tty_buffered_writer.writer().any();
    defer tty_buffered_writer.flush() catch {};

    var vx = try vaxis.init(alloc, .{});
    // null allocator in release to save time on exit
    defer vx.deinit(if (builtin.mode == .Debug) alloc else null, tty_writer);

    var loop: vaxis.Loop(Event) = .{
        .tty = &tty,
        .vaxis = &vx,
    };
    try loop.init();

    try loop.start();
    defer loop.stop();

    try vx.enterAltScreen(tty_writer);
    try vx.queryTerminal(tty_writer, 1 * std.time.ns_per_s);

    // const arena_allocator = std.heap.ArenaAllocator.init(alloc);
    // defer arena_allocator.deinit();
    // const arena = arena_allocator.allocator();

    var list = std.ArrayList([]const u8).init(alloc);
    defer list.deinit();

    for (0..20) |i| {
        const str = try std.fmt.allocPrint(alloc, "item {d}", .{i});
        try list.append(str);
    }
    defer {
        for (list.items) |item| {
            alloc.free(item);
        }
    }

    var selected_item: u32 = 0;

    const left_status_bar_text = "left status bar";
    var right_status_bar_text: []const u8 = "right status bar";

    try tty_buffered_writer.flush();
    while (true) {
        const event = loop.nextEvent();
        switch (event) {
            .key_press => |key| {
                if (key.matches('q', .{})) {
                    break;
                } else if (key.matches('m', .{})) {
                    for (list.items.len..list.items.len + 10) |i| {
                        const str = try std.fmt.allocPrint(alloc, "item {d}", .{i});
                        try list.append(str);
                    }
                } else if (key.matches('j', .{})) {
                    selected_item +|= 1;
                } else if (key.matches('k', .{})) {
                    selected_item -|= 1;
                }
            },

            .winsize => |ws| try vx.resize(alloc, tty.anyWriter(), ws),
            else => {},
        }

        const bg_default = Color{ .rgb = [_]u8{ 0x28, 0x28, 0x28 } }; // gruvbox bg0
        const bg_status_bar = Color{ .rgb = [_]u8{ 0x66, 0x5c, 0x54 } }; // gruvbox bg3
        const bg_left_pane = Color{ .rgb = [_]u8{ 0x3c, 0x38, 0x36 } }; // gruvbox bg1
        const bg_selected = Color{ .rgb = [_]u8{ 0x7c, 0x67, 0x64 } }; // gruvbox bg4

        const win = vx.window();
        win.clear();
        win.fill(.{ .style = .{ .bg = bg_default } });

        // =-= status bar start

        const status_bar_height = 1;

        const status_bar = win.child(.{
            .x_off = 0,
            .y_off = win.height - status_bar_height,
            .width = win.width,
            .height = status_bar_height,
        });
        status_bar.fill(.{ .style = .{ .bg = bg_status_bar } });

        _ = status_bar.printSegment(
            .{
                .text = left_status_bar_text,
                .style = .{ .bg = bg_status_bar },
            },
            .{},
        );

        const right_status_bar_segment = status_bar.child(.{
            .x_off = @intCast(status_bar.width - right_status_bar_text.len),
            .width = @intCast(right_status_bar_text.len),
            .height = status_bar_height,
        });
        _ = right_status_bar_segment.printSegment(
            .{
                .text = right_status_bar_text,
                .style = .{ .bg = bg_status_bar },
            },
            .{},
        );

        // =-= status bar end

        // =-= left pane start

        const left_pane_width = 50;

        const left_pane = win.child(.{
            .x_off = 0,
            .y_off = 0,
            .height = win.height - status_bar_height,
            .width = left_pane_width,
        });
        left_pane.fill(.{ .style = .{ .bg = bg_left_pane } });

        // left pane items
        var y: i17 = 0;
        for (list.items, 0..) |item, i| {
            const selected = i == selected_item;

            const bg = if (selected) bg_selected else bg_left_pane;

            const row = left_pane.child(.{
                .x_off = 0,
                .y_off = y,
                .height = 1,
                .width = 50,
            });
            row.fill(.{ .style = .{ .bg = bg } });
            const item_res = row.printSegment(.{ .text = item, .style = .{ .bg = bg } }, .{});
            if (item_res.overflow) {
                right_status_bar_text = "warn: left pane item overflowed";
            }
            y += 1;
        }

        // =-= left pane end

        try vx.render(tty_writer);
        try tty_buffered_writer.flush();
    }
}

const TagListView = struct {
    list_index: u32 = 0,
    list_item_index: u32 = 0,

    // TagList
};

const TagList = struct {
    file_path_buf: [256]u8,
    file_path_len: u8,

    // []TagItem
    // expanded

    pub fn file_path(self: *const TagList) []const u8 {
        return self.file_path_buf[0..self.file_path_len];
    }
};

const TagItem = struct {
    // tag
    // ?author
    // line number
    // text
};
