const builtin = @import("builtin");
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;

const read = @import("read.zig");
const TagList = @import("TagList.zig");
const TagListView = @import("TagListView.zig");
const StatusBarView = @import("StatusBarView.zig");
const Colors = @import("Colors.zig");
const SrcView = @import("SrcView.zig");
const binds = @import("binds.zig");

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
        if (builtin.mode == .Debug) app.deinit();
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

    var status_bar_view = StatusBarView{};

    var colors = Colors{
        .bg_default = .{ .index = 235 },
        .bg_tag_list = .{ .index = 236 },
        .bg_status_bar = .{ .index = 237 },
        .bg_status_bar_hl = .{ .index = 234 },
        .bg_selected = .{ .index = 238 },

        .red = .{ .index = 1 + 8 },
        .green = .{ .index = 2 + 8 },
        .yellow = .{ .index = 3 + 8 },
        .blue = .{ .index = 4 + 8 },
        .purple = .{ .index = 5 + 8 },
        .aqua = .{ .index = 6 + 8 },
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
    var running = true;
    while (running) {
        const event = loop.nextEvent();
        switch (event) {
            .key_press => |key| {
                for (binds.bindings) |binding| {
                    if (key.matchesAny(binding.keys.cps, binding.keys.mods)) {
                        switch (binding.action) {
                            .quit => {
                                running = false;
                            },
                            .move_down => {
                                tag_list_view.moveDown();
                            },
                            .move_up => {
                                tag_list_view.moveUp();
                            },
                            .toggle_expanded => {
                                tag_list_view.toggleExpanded();
                            },
                            .reload => {
                                try reload(alloc, &tag_list_view, load_opts);
                            },
                            .open_in_editor => {
                                try openInEditor(alloc, tag_list_view);
                            },
                            .sidebar_width_dec => {
                                tag_list_view.width -= 1;
                            },
                            .sidebar_width_inc => {
                                tag_list_view.width += 1;
                            },
                        }
                    }
                }
            },

            .winsize => |ws| try vx.resize(alloc, tty.anyWriter(), ws),
        }

        const root = vx.window();
        root.clear();

        const status_bar_win = StatusBarView.window(root);
        try status_bar_view.draw(arena, status_bar_win, &colors);

        const tag_list_win = tag_list_view.window(root);
        try tag_list_view.draw(tag_list_win, &colors, arena);

        const src_win = SrcView.window(root, tag_list_view.width);
        SrcView.render(src_win, &colors, &tag_list_view);

        try vx.render(tty_writer);
        try tty_buffered_writer.flush();

        // @FIXME: Limit this accordingly
        _ = arena_allocator.reset(.retain_capacity);
    }
}

const LoadOptions = union(enum) {
    file: []const u8,
    dir: []const u8,
};

fn load(alloc: Allocator, opts: LoadOptions) !TagListView {
    return switch (opts) {
        .file => |file_path| blk: {
            const path = try alloc.dupe(u8, file_path);
            break :blk try read.readSingleFile(alloc, path);
        },
        .dir => |dir_path| try read.readDir(alloc, dir_path),
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

fn reload(
    alloc: Allocator,
    tag_list_view: *TagListView,
    load_opts: LoadOptions,
) !void {
    // @TODO: restore expanded state
    //  this would involve keeping a list of each filename and
    //  its exanded state, comparing them to the new and setting
    //  accordingly
    const list_index = tag_list_view.list_index;
    const list_item_index = tag_list_view.list_item_index;

    tag_list_view.deinit(alloc);
    tag_list_view.* = try load(alloc, load_opts);

    tag_list_view.list_index = @min(list_index, tag_list_view.tag_lists.len - 1);

    if (tag_list_view.list_index == list_index and list_item_index != null) {
        const tag_list: TagList = tag_list_view.tag_lists.items(.list)[list_index];
        tag_list_view.list_item_index = @min(list_item_index.?, tag_list.tag_items.len - 1);
    }
}
