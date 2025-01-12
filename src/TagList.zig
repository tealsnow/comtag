const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;

const Self = @This();

// @TODO: move arraylists to slices
//  since we do not need to modify them after reading

file_path: []u8, // owned
file_bytes: []u8, // owned
file_lines: ArrayListUnmanaged([]const u8) = .{}, // slices into file_bytes
tag_items: ArrayListUnmanaged(TagItem) = .{},
tag_texts: ArrayListUnmanaged([]const u8) = .{}, // slices into file_bytes
remembered_item_index: ?u31 = null,

pub fn deinit(self: *Self, alloc: Allocator) void {
    alloc.free(self.file_path);
    alloc.free(self.file_bytes);
    self.file_lines.deinit(alloc);
    self.tag_items.deinit(alloc);
    self.tag_texts.deinit(alloc);
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
