const builtin = @import("builtin");
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;

const read = @import("read.zig");
const TagList = @import("TagList.zig");
const TagListView = @import("TagListView.zig");
const Colors = @import("Colors.zig");

const vaxis = @import("vaxis");
const Cell = vaxis.Cell;
const TextInput = vaxis.widgets.TextInput;
const CodeView = vaxis.widgets.CodeView;
const Color = vaxis.Color;
const Segment = vaxis.Segment;
const Key = vaxis.Key;
const Window = vaxis.Window;

const yazap = @import("yazap");
const Arg = yazap.Arg;

pub fn panic(
    msg: []const u8,
    error_return_trace: ?*std.builtin.StackTrace,
    ret_addr: ?usize,
) noreturn {
    // @BUG: The vaxis panic handler does not restore the cursor on a panic
    // @TODO: File a report https://github.com/rockorager/libvaxis/issues
    const show_cursor: []const u8 = vaxis.ctlseqs.show_cursor;
    const stdout = std.io.getStdOut();
    stdout.writeAll(show_cursor) catch {};

    vaxis.panic_handler(msg, error_return_trace, ret_addr);
}

// This can contain internal events as well as Vaxis events.
// Internal events can be posted into the same queue as vaxis events to allow
// for a single event loop with exhaustive switching. Booya
const Event = union(enum) {
    key_press: Key,
    winsize: vaxis.Winsize,
    focus_in,
    foo: u8,
};

pub fn main() !void {
    defer std.process.cleanExit();

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

    var app = yazap.App.init(alloc, "comtag", "this is comtag");
    defer {
        if (builtin.mode == .Debug)
            app.deinit();
    }

    var comtag = app.rootCommand();

    try comtag.addArg(Arg.positional("DIR", null, null));
    try comtag.addArg(Arg.singleValueOption("file", null, "single file to scan instead of folder"));
    try comtag.addArg(Arg.booleanOption("version", 'v', "print version and exit"));

    const matches = try app.parseProcess();

    if (matches.containsArg("version")) {
        std.debug.print("0.1.0\n", .{});
        return;
    }

    var tag_list_view = if (matches.getSingleValue("file")) |file_path| blk: {
        const path = try alloc.dupe(u8, file_path);
        break :blk try read.read_single_file(alloc, path);
    } else blk: {
        const maybe_dir = matches.getSingleValue("DIR");
        if (maybe_dir == null) {
            std.debug.print("ERROR: expected argument DIR\n", .{});
            std.process.exit(1);
        }
        const dir_path = maybe_dir.?;

        break :blk try read.read_dir(alloc, dir_path);
    };
    defer tag_list_view.deinit(alloc);

    var tty = try vaxis.Tty.init();
    defer tty.deinit();
    var tty_buffered_writer = tty.bufferedWriter();
    const tty_writer = tty_buffered_writer.writer().any();
    defer tty_buffered_writer.flush() catch {};

    var vx = try vaxis.init(alloc, .{});
    // null allocator in release build to save time on exit
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

    var status_bar_view = StatusBarView{
        .left_text = "left status bar",
        .right_text = "right status bar",
    };

    var colors = Colors{
        .bg_default = .{ .rgb = [_]u8{ 0x28, 0x28, 0x28 } }, // gruvbox bg0
        .bg_status_bar = .{ .rgb = [_]u8{ 0x66, 0x5c, 0x54 } }, // gruvbox bg3
        .bg_tag_list = .{ .rgb = [_]u8{ 0x3c, 0x38, 0x36 } }, // gruvbox bg1
        .bg_selected = .{ .rgb = [_]u8{ 0x7c, 0x67, 0x64 } }, // gruvbox bg4

        .red = .{ .rgb = [_]u8{ 0xfb, 0x49, 0x34 } }, // gruvbox
        .green = .{ .rgb = [_]u8{ 0xb8, 0xbb, 0x26 } }, // gruvbox
        .yellow = .{ .rgb = [_]u8{ 0xfa, 0xbd, 0x2f } }, // gruvbox
        .blue = .{ .rgb = [_]u8{ 0x83, 0xa5, 0x98 } }, // gruvbox
        .purple = .{ .rgb = [_]u8{ 0xd3, 0x86, 0x9b } }, // gruvbox
        .aqua = .{ .rgb = [_]u8{ 0x8e, 0xc0, 0x7c } }, // gruvbox
    };
    defer colors.tag_map.deinit(alloc);

    try colors.tag_map.ensureTotalCapacity(alloc, 9);
    try colors.tag_map.put(alloc, "TODO", .green);
    try colors.tag_map.put(alloc, "FIXME", .yellow);
    try colors.tag_map.put(alloc, "NOTE", .blue);
    try colors.tag_map.put(alloc, "XXX", .red);
    try colors.tag_map.put(alloc, "HACK", .purple);
    try colors.tag_map.put(alloc, "SPEED", .aqua);
    try colors.tag_map.put(alloc, "BUG", .purple);

    var arena_allocator = std.heap.ArenaAllocator.init(alloc);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();

    try tty_buffered_writer.flush();
    while (true) {
        const event = loop.nextEvent();
        switch (event) {
            .key_press => |key| {
                if (key.matchesAny(&.{ 'q', Key.escape }, .{})) {
                    break;
                } else if (key.matchesAny(&.{ 'j', Key.down }, .{})) {
                    tag_list_view.move_down();
                } else if (key.matchesAny(&.{ 'k', Key.up }, .{})) {
                    tag_list_view.move_up();
                } else if (key.matches(Key.tab, .{})) {
                    tag_list_view.toggle_expanded();
                } else if (key.matches('p', .{})) {
                    @panic("test panic");
                }
            },

            .winsize => |ws| try vx.resize(alloc, tty.anyWriter(), ws),

            else => {},
        }

        const win = vx.window();
        win.clear();
        // win.fill(.{ .style = .{ .bg = colors.bg_default } });

        const status_bar_height = 1;
        const status_bar = win.child(.{
            .x_off = 0,
            .y_off = win.height - status_bar_height,
            .width = win.width,
            .height = status_bar_height,
        });
        status_bar_view.draw(status_bar, colors);

        const tag_list_width = 50;
        const tag_list_win = win.child(.{
            .x_off = 0,
            .y_off = 0,
            .height = win.height - status_bar_height,
            .width = tag_list_width,
        });
        try tag_list_view.draw(tag_list_win, colors, arena);

        const src_win = win.child(.{
            .x_off = tag_list_width,
            .y_off = 0,
            .height = win.height - status_bar_height,
            .width = win.width - tag_list_win.width,
        });
        src_win.fill(.{ .style = .{ .bg = colors.bg_default } });

        // @TODO: Move out of main
        const current_list: TagList = tag_list_view.tag_lists.items(.list)[tag_list_view.list_index];
        if (tag_list_view.list_item_index) |tag_index| {
            const current_tag = current_list.tag_items.items[tag_index];
            const line_idx = current_tag.line_number - 1;
            const lines = current_list.file_lines.items;

            const padding = (src_win.height - current_tag.num_lines) / 2;

            var i: u16 = 0;

            const begin_lines = line_idx - (line_idx -| padding);
            const diff = padding - begin_lines;
            i += @intCast(diff);

            for (lines[(line_idx - begin_lines)..line_idx]) |line| {
                _ = src_win.printSegment(.{
                    .text = line,
                    .style = .{ .bg = colors.bg_default },
                }, .{
                    .row_offset = i,
                });
                i += 1;
            }

            const section_end_idx = line_idx + current_tag.num_lines;

            std.debug.print("end idx : {d}\n", .{section_end_idx});

            for (lines[line_idx..section_end_idx]) |line| {
                _ = src_win.printSegment(.{
                    .text = line,
                    .style = .{ .bg = colors.bg_selected },
                }, .{
                    .row_offset = i,
                });
                i += 1;
            }

            if (line_idx + padding >= lines.len) {
                for (lines[section_end_idx..]) |line| {
                    _ = src_win.printSegment(.{
                        .text = line,
                        .style = .{ .bg = colors.bg_default },
                    }, .{
                        .row_offset = i,
                    });
                    i += 1;
                }
            } else {
                // @FIXME: on files smaller than the window height not having
                //  the `- 1` indexs by 1 out of bounds, where on files larger
                //  the final line in the view is not drawn
                for (lines[section_end_idx..(section_end_idx + padding - 1)]) |line| {
                    _ = src_win.printSegment(.{
                        .text = line,
                        .style = .{ .bg = colors.bg_default },
                    }, .{
                        .row_offset = i,
                    });
                    i += 1;
                }
            }
        } else {
            _ = src_win.printSegment(.{
                .text = current_list.file_bytes,
                .style = .{ .bg = colors.bg_default },
            }, .{});
        }

        try vx.render(tty_writer);
        try tty_buffered_writer.flush();

        // @FIXME: Limit this accordingly
        _ = arena_allocator.reset(.retain_capacity);
    }
}

// @FIXME: Do we still want this?
const StatusBarView = struct {
    // @TODO: Add support for both allocated and unallocated strings here
    left_text: []const u8,
    right_text: []const u8,

    pub fn draw(self: *StatusBarView, window: Window, colors: Colors) void {
        window.fill(.{ .style = .{ .bg = colors.bg_status_bar } });

        _ = window.printSegment(
            .{
                .text = self.left_text,
                .style = .{ .bg = colors.bg_status_bar },
            },
            .{},
        );

        const right_status_bar_segment = window.child(.{
            .x_off = @intCast(window.width - self.right_text.len),
            .width = @intCast(self.right_text.len),
            .height = window.height,
        });
        _ = right_status_bar_segment.printSegment(
            .{
                .text = self.right_text,
                .style = .{ .bg = colors.bg_status_bar },
            },
            .{},
        );
    }
};
