const Colors = @This();

const std = @import("std");

const vaxis = @import("vaxis");
const Color = vaxis.Color;

bg_default: Color,
bg_selected: Color,
bg_tag_list: Color,
bg_status_bar: Color,
bg_status_bar_hl: Color,

red: Color,
green: Color,
yellow: Color,
blue: Color,
purple: Color,
aqua: Color,

tag_map: std.ArrayHashMapUnmanaged(
    []const u8,
    TagColor,
    std.array_hash_map.StringContext,
    false,
) = .{},

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
