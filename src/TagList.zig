const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;

const Self = @This();

file_path: []u8, // owned
file_bytes: []u8, // owned
file_lines: []const []const u8, // slices into file_bytes
tag_items: []const TagItem,
tag_texts: []const []const u8, // slices into file_bytes
remembered_item_index: ?u31 = null,

pub fn deinit(self: *Self, alloc: Allocator) void {
    alloc.free(self.file_path);
    alloc.free(self.file_bytes);
    alloc.free(self.file_lines);
    alloc.free(self.tag_items);
    alloc.free(self.tag_texts);
}

pub const TagItem = struct {
    tag: []const u8, // slice into file
    author: ?[]const u8, // slice into file
    text: Range, // range into `TagList.tag_items`
    line_number: u32,
    // @FIXME: maybe make smaller depending on alignment
    num_lines: u32,
};

pub const Range = struct {
    start: u32,
    len: u32,
};
