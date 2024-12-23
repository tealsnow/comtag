const builtin = @import("builtin");
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;

const vaxis = @import("vaxis");
const Cell = vaxis.Cell;
const TextInput = vaxis.widgets.TextInput;
const border = vaxis.widgets.border;
const ScrollView = vaxis.widgets.ScrollView;
const Color = vaxis.Color;
const Segment = vaxis.Segment;
const Key = vaxis.Key;

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
        // if (builtin.mode == .Debug) {
        //     const deinit_status = gpa.deinit();
        //     if (deinit_status == .leak) {
        //         std.log.err("memory leak", .{});
        //     }
        // }
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

    // const arena_allocator = std.heap.ArenaAllocator.init(alloc);
    // defer arena_allocator.deinit();
    // const arena = arena_allocator.allocator();

    var tag_list1 = TagList{
        .file_path = try std.fmt.allocPrint(alloc, "{s}", .{"src/main.zig"}),
        .tag_items = .{},
        .expanded = true,
    };

    var tag_list2 = TagList{
        .file_path = try std.fmt.allocPrint(alloc, "{s}", .{"src/root.zig"}),
        .tag_items = .{},
        .expanded = false,
    };

    for (0..20) |i| {
        const tag = if (i % 2 == 0)
            "TODO"
        else if (i % 3 == 0)
            "FIXME"
        else
            "NOTE";
        // const tag_alloc = try std.fmt.allocPrint(alloc, "{s}", .{tag});
        const tag_alloc = try alloc.alloc(u8, tag.len);
        @memcpy(tag_alloc, tag);

        const author = if (i % 4 == 0)
            try std.fmt.allocPrint(alloc, "{s}", .{"ketanr"})
        else
            null;

        const text = try std.fmt.allocPrint(
            alloc,
            "{s}",
            .{"this is a description of the tag"},
        );

        const tag_item = TagItem{
            .tag = tag_alloc,
            .author = author,
            .text = text,
            .line_number = @intCast(i),
        };

        try tag_list1.tag_items.append(alloc, tag_item);
        try tag_list2.tag_items.append(alloc, tag_item);
    }

    var tag_list_view = TagListView{};
    // defer tag_list_view.deinit(alloc);
    try tag_list_view.tag_lists.append(alloc, tag_list1);
    try tag_list_view.tag_lists.append(alloc, tag_list2);

    // var selected_item: u32 = 0;

    const left_status_bar_text = "left status bar";
    const right_status_bar_text: []const u8 = "right status bar";

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
        for (tag_list_view.tag_lists.items, 0..) |tag_list, tag_list_i| {
            const is_current_tag_list =
                tag_list_i == tag_list_view.list_index;
            const tag_list_selected =
                is_current_tag_list and tag_list_view.list_item_index == null;

            const tag_list_bg = if (tag_list_selected)
                bg_selected
            else
                bg_left_pane;

            const tag_list_row = left_pane.child(.{
                .x_off = 0,
                .y_off = y,
                .height = 1,
                .width = left_pane_width,
            });

            _ = tag_list_row.print(
                &.{
                    .{
                        .text = if (tag_list.expanded) "v " else "> ",
                        .style = .{ .bg = tag_list_bg },
                    },
                    .{
                        .text = tag_list.file_path,
                        .style = .{ .bg = tag_list_bg },
                    },
                },
                .{},
            );
            y += 1;

            if (tag_list.expanded) {
                for (tag_list.tag_items.items, 0..) |item, tag_item_i| {
                    const tag_item_selected =
                        if (tag_list_view.list_item_index) |index|
                        is_current_tag_list and index == tag_item_i
                    else
                        false;

                    const tag_item_bg = if (tag_item_selected)
                        bg_selected
                    else
                        bg_left_pane;

                    const tag_item_row = left_pane.child(.{
                        .x_off = 0,
                        .y_off = y,
                        .height = 1,
                        .width = left_pane_width,
                    });

                    _ = tag_item_row.print(
                        &.{
                            .{
                                .text = "   ",
                                .style = .{ .bg = tag_item_bg },
                            },
                            .{
                                .text = item.tag,
                                .style = .{ .bg = tag_item_bg },
                            },
                        },
                        .{},
                    );
                    y += 1;
                }
            }

            // const selected = i == selected_item;

            // const bg = if (selected) bg_selected else bg_left_pane;

            // const row = left_pane.child(.{
            //     .x_off = 0,
            //     .y_off = y,
            //     .height = 1,
            //     .width = 50,
            // });
            // row.fill(.{ .style = .{ .bg = bg } });
            // const item_res = row.printSegment(
            //     .{ .text = item, .style = .{ .bg = bg } },
            //     .{},
            // );
            // if (item_res.overflow) {
            //     right_status_bar_text = "warn: left pane item overflowed";
            // }
            // y += 1;
        }

        // =-= left pane end

        try vx.render(tty_writer);
        try tty_buffered_writer.flush();
    }
}

const TagListView = struct {
    list_index: u32 = 0,
    list_item_index: ?u32 = null,
    tag_lists: ArrayListUnmanaged(TagList) = .{},

    // pub fn deinit(self: *TagListView, alloc: Allocator) void {
    //     for (self.tag_list.items) |*list| list.deinit(alloc);
    //     self.tag_list.deinit(alloc);
    // }

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
};

const TagList = struct {
    file_path: []u8,
    tag_items: ArrayListUnmanaged(TagItem),
    expanded: bool, // might be worth storing out of line, in TagListView
    remembered_item_index: ?u32 = null,

    // pub fn deinit(self: *TagList, alloc: Allocator) void {
    //     alloc.free(self.file_path);
    //     for (self.tag_items.items) |*item| item.deinit(alloc);
    //     self.tag_items.deinit(alloc);
    // }
};

const TagItem = struct {
    tag: []u8,
    author: ?[]u8,
    text: []u8,
    line_number: u32,

    // pub fn deinit(self: *TagItem, alloc: Allocator) void {
    //     alloc.free(self.tag);
    //     if (self.author) |author| alloc.free(author);
    //     alloc.free(self.text);
    // }
};
