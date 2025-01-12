const std = @import("std");
const Allocator = std.mem.Allocator;

const TagList = @import("TagList.zig");
const Colors = @import("Colors.zig");

const vaxis = @import("vaxis");
const Window = vaxis.Window;
const Segment = vaxis.Segment;

const TagListView = @This();

list_index: u32 = 0,
list_item_index: ?u31 = null,
tag_lists: std.MultiArrayList(struct {
    list: TagList,
    expanded: bool = true,
}) = .{},

pub fn deinit(self: *TagListView, alloc: Allocator) void {
    for (self.tag_lists.items(.list)) |*list| list.deinit(alloc);
    self.tag_lists.deinit(alloc);
}

pub fn move_down(self: *TagListView) void {
    const current_tag_list =
        &self.tag_lists.items(.list)[self.list_index];
    const not_at_end_of_tag_lists =
        self.list_index != self.tag_lists.len - 1;

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
    else if (self.tag_lists.get(self.list_index).expanded) {
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
                &self.tag_lists.items(.list)[self.list_index];
            current_tag_list.remembered_item_index = null;
        } else {
            self.list_item_index = current_item_index - 1;
        }
    }
    // not at begining of tag_lists
    else if (self.list_index != 0) {
        self.list_index -= 1;
        if (self.tag_lists.get(self.list_index).expanded) {
            const prev_list = &self.tag_lists.items(.list)[self.list_index];
            self.list_item_index = @intCast(prev_list.tag_items.items.len - 1);
        }
    }
}

pub fn toggle_expanded(self: *TagListView) void {
    const current_tag_list =
        &self.tag_lists.items(.list)[self.list_index];

    if (self.tag_lists.get(self.list_index).expanded) {
        current_tag_list.remembered_item_index = self.list_item_index;
        self.tag_lists.items(.expanded)[self.list_index] = false;
        self.list_item_index = null;
    } else {
        self.list_item_index = current_tag_list.remembered_item_index;
        self.tag_lists.items(.expanded)[self.list_index] = true;
    }
}

pub fn draw(self: *TagListView, window: Window, colors: Colors, arena: Allocator) !void {
    window.fill(.{ .style = .{ .bg = colors.bg_tag_list } });

    var y: i17 = 0;
    for (self.tag_lists.items(.list), 0..) |tag_list, tag_list_i| {
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

        const expanded = self.tag_lists.get(tag_list_i).expanded;

        _ = tag_list_row.print(
            &.{
                .{
                    .text = if (expanded) "v " else "> ",
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

        if (!expanded)
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
                var list = std.ArrayList(Segment).init(arena);
                try list.ensureTotalCapacity(1 + item.text.len * 2);

                try list.append(.{
                    .text = " ",
                    .style = .{ .bg = tag_item_bg },
                });

                const texts = tag_list.tag_texts.items[item.text.start..(item.text.start + item.text.len)];
                for (texts, 0..) |text, i| {
                    try list.append(.{
                        .text = text,
                        .style = .{ .bg = tag_item_bg },
                    });
                    if (i < texts.len - 1)
                        try list.append(.{
                            .text = " ",
                            .style = .{ .bg = tag_item_bg },
                        });
                }

                print_res = tag_item_row.print(
                    list.items,
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
