const builtin = @import("builtin");
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;

const vaxis = @import("vaxis");
const Cell = vaxis.Cell;
const TextInput = vaxis.widgets.TextInput;
const CodeView = vaxis.widgets.CodeView;
// const ScrollView = vaxis.widgets.ScrollView;
const Color = vaxis.Color;
const Segment = vaxis.Segment;
const Key = vaxis.Key;
const Window = vaxis.Window;

const DisplayWidth = @import("DisplayWidth");

const yazap = @import("yazap");
const Arg = yazap.Arg;

const read = @import("read.zig");
const TagList = @import("TagList.zig");

// pub const PanicGlobals = struct {
//     vx: *vaxis.Vaxis,
//     tty: *std.io.AnyWriter,
// };

// var g_panic_globals: ?PanicGlobals = null;

// pub fn panic(
//     msg: []const u8,
//     error_return_trace: ?*std.builtin.StackTrace,
//     ret_addr: ?usize,
// ) noreturn {
//     if (g_panic_globals) |pg| {
//         pg.vx.exitAltScreen(pg.tty.*) catch {};
//         pg.vx.deinit(null, pg.tty.*);
//     }

//     if (std.meta.hasFn(std.builtin, "default_panic")) {
//         std.builtin.default_panic(msg, error_return_trace, ret_addr);
//     }
//     std.debug.defaultPanic(msg, error_return_trace, ret_addr);
// }

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

    try comtag.addArg(Arg.positional("FILE", null, null));
    try comtag.addArg(Arg.booleanOption("version", 'v', "print version and exit"));

    const matches = try app.parseProcess();

    if (matches.containsArg("version")) {
        std.debug.print("0.1.0\n", .{});
        std.process.cleanExit();
        return;
    }

    const maybe_file = matches.getSingleValue("FILE");
    if (maybe_file == null) {
        std.debug.print("ERROR: expected argument FILE\n", .{});
        std.process.exit(1);
    }
    const file_path = try alloc.dupe(u8, maybe_file.?);

    const tag_list = try read.read(alloc, file_path);

    var tag_list_view = TagListView{};
    defer tag_list_view.deinit(alloc);
    try tag_list_view.tag_lists.append(alloc, tag_list);

    var tty = try vaxis.Tty.init();
    defer tty.deinit();
    var tty_buffered_writer = tty.bufferedWriter();
    const tty_writer = tty_buffered_writer.writer().any();
    defer tty_buffered_writer.flush() catch {};

    var vx = try vaxis.init(alloc, .{});
    // null allocator in release build to save time on exit
    defer vx.deinit(if (builtin.mode == .Debug) alloc else null, tty_writer);

    // g_panic_globals = .{ .vx = &vx, .tty = &tty_writer };

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

        try vx.render(tty_writer);
        try tty_buffered_writer.flush();

        // @FIXME: Limit this accordingly
        _ = arena_allocator.reset(.retain_capacity);
    }

    std.process.cleanExit();
}

const Colors = struct {
    bg_default: Color,
    bg_status_bar: Color,
    bg_tag_list: Color,
    bg_selected: Color,

    red: Color,
    green: Color,
    yellow: Color,
    blue: Color,
    purple: Color,
    aqua: Color,

    tag_map: std.ArrayHashMapUnmanaged([]const u8, TagColor, std.array_hash_map.StringContext, false) = .{},

    pub const TagColor = enum {
        red,
        green,
        yellow,
        blue,
        purple,
        aqua,
    };

    pub fn getTagColor(self: *const Colors, tag: []const u8) ?Color {
        return if (self.tag_map.get(tag)) |tag_color|
            switch (tag_color) {
                .red => self.red,
                .green => self.green,
                .yellow => self.yellow,
                .blue => self.blue,
                .purple => self.purple,
                .aqua => self.aqua,
            }
        else
            null;
    }
};

const TagListView = struct {
    list_index: u32 = 0,
    // @FIXME: its worth looking into makeing this a ?u31, for space saving
    //  see TagList.remembered_item_index
    list_item_index: ?u32 = null,
    tag_lists: ArrayListUnmanaged(TagList) = .{}, // owned

    pub fn deinit(self: *TagListView, alloc: Allocator) void {
        for (self.tag_lists.items) |*list| list.deinit(alloc);
        self.tag_lists.deinit(alloc);
    }

    pub fn move_down(self: *TagListView) void {
        const current_tag_list =
            &self.tag_lists.items[self.list_index];
        const not_at_end_of_tag_lists =
            self.list_index != self.tag_lists.items.len - 1;

        // inside of list
        if (self.list_item_index) |current_item_index| {
            // not at end of list
            if (current_item_index != current_tag_list.tag_items.items.len - 1) {
                self.list_item_index = current_item_index + 1;
            }
            // not at end of lists
            else if (not_at_end_of_tag_lists) {
                self.list_item_index = null;
                self.list_index += 1;
            }
        }
        // not in a list but on one that is expanded
        else if (current_tag_list.expanded) {
            self.list_item_index = 0;
        }
        // not at the end of lists
        else if (not_at_end_of_tag_lists) {
            self.list_index += 1;
        }
    }

    pub fn move_up(self: *TagListView) void {
        // inside of tag_list
        if (self.list_item_index) |current_item_index| {
            if (current_item_index == 0) {
                self.list_item_index = null;

                const current_tag_list =
                    &self.tag_lists.items[self.list_index];
                current_tag_list.remembered_item_index = null;
            } else {
                self.list_item_index = current_item_index - 1;
            }
        }
        // not at begining of tag_lists
        else if (self.list_index != 0) {
            const prev_list = &self.tag_lists.items[self.list_index - 1];
            if (prev_list.expanded) {
                self.list_index -= 1;
                self.list_item_index = @intCast(prev_list.tag_items.items.len - 1);
            } else {
                self.list_index -= 1;
            }
        }
    }

    pub fn toggle_expanded(self: *TagListView) void {
        // @FIXME: maybe pull up a scope
        const current_tag_list =
            &self.tag_lists.items[self.list_index];

        if (current_tag_list.expanded) {
            current_tag_list.remembered_item_index = self.list_item_index;
            current_tag_list.expanded = false;
            self.list_item_index = null;
        } else {
            self.list_item_index = current_tag_list.remembered_item_index;
            current_tag_list.expanded = true;
        }
    }

    pub fn draw(self: *TagListView, window: Window, colors: Colors, arena: Allocator) !void {
        window.fill(.{ .style = .{ .bg = colors.bg_tag_list } });

        var y: i17 = 0;
        for (self.tag_lists.items, 0..) |tag_list, tag_list_i| {
            const is_current_tag_list =
                tag_list_i == self.list_index;
            const tag_list_selected =
                is_current_tag_list and self.list_item_index == null;

            const tag_list_bg = if (tag_list_selected)
                colors.bg_selected
            else
                colors.bg_tag_list;

            const tag_list_row = window.child(.{
                .x_off = 0,
                .y_off = y,
                .height = 1,
                .width = window.width,
            });

            _ = tag_list_row.print(
                &.{
                    .{
                        .text = if (tag_list.expanded) "v " else "> ",
                        .style = .{ .bg = colors.bg_tag_list },
                    },
                    .{
                        .text = tag_list.file_path,
                        .style = .{ .bg = tag_list_bg },
                    },
                },
                .{},
            );
            y += 1;

            if (!tag_list.expanded)
                continue;

            var max_line_len: usize = 0;
            for (tag_list.tag_items.items) |item| {
                if (item.line_number == 0)
                    max_line_len = @max(max_line_len, 1)
                else
                    max_line_len = @max(
                        max_line_len,
                        std.math.log10_int(item.line_number) + 1,
                    );
            }

            for (tag_list.tag_items.items, 0..) |item, tag_item_i| {
                const tag_item_selected =
                    if (self.list_item_index) |index|
                    is_current_tag_list and index == tag_item_i
                else
                    false;

                const tag_item_bg = if (tag_item_selected)
                    colors.bg_selected
                else
                    colors.bg_tag_list;

                const tag_item_row = window.child(.{
                    .x_off = 0,
                    .y_off = y,
                    .height = 1,
                    .width = window.width,
                });

                const tag_color = colors.getTagColor(item.tag) orelse .default;

                var line_num_buf = try arena.alloc(u8, max_line_len);
                const line_num_buf_len = std.fmt.formatIntBuf(
                    line_num_buf,
                    item.line_number,
                    10,
                    .lower,
                    .{ .width = max_line_len },
                );
                const line_num = line_num_buf[0..line_num_buf_len];

                var print_res = tag_item_row.print(
                    &.{
                        .{
                            .text = "   ",
                            .style = .{ .bg = colors.bg_tag_list },
                        },
                        .{
                            .text = line_num,
                            .style = .{ .bg = tag_item_bg },
                        },
                        .{
                            .text = " ",
                            .style = .{ .bg = tag_item_bg },
                        },
                        .{
                            .text = item.tag,
                            .style = .{ .bg = tag_item_bg, .fg = tag_color },
                        },
                    },
                    .{},
                );

                if (item.author) |author| {
                    print_res = tag_item_row.print(
                        &.{
                            .{
                                .text = " (",
                                .style = .{ .bg = tag_item_bg, .dim = true },
                            },
                            .{
                                .text = author,
                                .style = .{ .bg = tag_item_bg, .dim = true },
                            },
                            .{
                                .text = ")",
                                .style = .{ .bg = tag_item_bg, .dim = true },
                            },
                        },
                        .{ .col_offset = print_res.col },
                    );
                }

                if (item.text.len > 0) {
                    const text = tag_list.tag_texts.items[item.text.start];
                    print_res = tag_item_row.print(
                        &.{
                            .{
                                .text = " ",
                                .style = .{ .bg = tag_item_bg },
                            },
                            .{
                                .text = text,
                                .style = .{ .bg = tag_item_bg },
                            },
                        },
                        .{
                            .col_offset = print_res.col,
                            .wrap = .none,
                        },
                    );
                }

                // …
                if (print_res.overflow) {
                    _ = tag_item_row.writeCell(
                        tag_item_row.width - 1,
                        0,
                        .{
                            .char = .{ .grapheme = "…" },
                            .style = .{ .bg = tag_item_bg },
                        },
                    );
                }

                y += 1;
            }
        }
    }
};

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
