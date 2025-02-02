const builtin = @import("builtin");
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;

const read = @import("read.zig");
const TagList = @import("TagList.zig");
const TagListView = @import("TagListView.zig");
const Colors = @import("Colors.zig");
const renderSrcView = @import("renderSrcView.zig").renderSrcView;

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

    const load_opts = if (matches.getSingleValue("file")) |file_path|
        LoadOptions{ .file = file_path }
    else blk: {
        const maybe_dir = matches.getSingleValue("DIR");
        if (maybe_dir == null) {
            std.debug.print("ERROR: expected argument DIR\n", .{});
            std.process.exit(1);
        }
        const dir_path = maybe_dir.?;

        break :blk LoadOptions{ .dir = dir_path };
    };

    var tag_list_view = try load(alloc, load_opts);
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

    // @TODO: put controls hints here
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
                    tag_list_view.moveDown();
                } else if (key.matchesAny(&.{ 'k', Key.up }, .{})) {
                    tag_list_view.moveUp();
                } else if (key.matches(Key.tab, .{})) {
                    tag_list_view.toggleExpanded();
                } else if (key.matches('r', .{})) {
                    // @TODO: restore expanded state
                    //  this would involve keeping a list of each filename and
                    //  its exanded state, comparing them to the new and setting
                    //  accordingly
                    const list_index = tag_list_view.list_index;
                    const list_item_index = tag_list_view.list_item_index;

                    tag_list_view.deinit(alloc);
                    tag_list_view = try load(alloc, load_opts);

                    tag_list_view.list_index = @min(list_index, tag_list_view.tag_lists.len - 1);

                    if (tag_list_view.list_index == list_index and list_item_index != null) {
                        const tag_list: TagList = tag_list_view.tag_lists.items(.list)[list_index];
                        tag_list_view.list_item_index = @min(list_item_index.?, tag_list.tag_items.len - 1);
                    }
                } else if (key.matches(Key.enter, .{})) {
                    try openInEditor(alloc, tag_list_view);
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
        status_bar_view.draw(status_bar, &colors);

        const tag_list_width = 50;
        const tag_list_win = win.child(.{
            .x_off = 0,
            .y_off = 0,
            .height = win.height - status_bar_height,
            .width = tag_list_width,
        });
        try tag_list_view.draw(tag_list_win, &colors, arena);

        const src_win = win.child(.{
            .x_off = tag_list_width,
            .y_off = 0,
            .height = win.height - status_bar_height,
            .width = win.width - tag_list_win.width,
        });
        renderSrcView(src_win, &colors, &tag_list_view);

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

    pub fn draw(self: *StatusBarView, window: Window, colors: *Colors) void {
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

const LoadOptions = union(enum) {
    file: []const u8,
    dir: []const u8,
};

fn load(alloc: Allocator, opts: LoadOptions) !TagListView {
    return switch (opts) {
        .file => |file_path| blk: {
            const path = try alloc.dupe(u8, file_path);
            break :blk try read.read_single_file(alloc, path);
        },
        .dir => |dir_path| try read.read_dir(alloc, dir_path),
    };
}

// @TODO: allow for command to be configured
fn openInEditor(alloc: Allocator, tag_list_view: TagListView) !void {
    const current_list: TagList = tag_list_view.tag_lists.items(.list)[tag_list_view.list_index];
    if (tag_list_view.list_item_index) |tag_index| {
        const current_tag = current_list.tag_items[tag_index];

        var args = std.ArrayList([]const u8).init(alloc);
        defer args.deinit();
        try args.ensureTotalCapacity(8);
        try args.appendSlice(&.{ "emacsclient", "-n", "-r" });

        const position = try std.fmt.allocPrint(
            alloc,
            "+{d}",
            .{current_tag.line_number},
        );
        defer alloc.free(position);
        try args.append(position);

        const path = try std.fs.realpathAlloc(alloc, current_list.file_path);
        defer alloc.free(path);
        try args.append(path);

        var proc = std.process.Child.init(args.items, alloc);
        proc.stdin_behavior = .Ignore;
        proc.stdout_behavior = .Ignore;

        try proc.spawn();
        _ = try proc.wait();
    }
}
