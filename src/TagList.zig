const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;

const Self = @This();

file_path: []u8, // owned
file_bytes: []u8, // owned
tag_items: ArrayListUnmanaged(TagItem),
tag_texts: ArrayListUnmanaged([]const u8), // owned, items are slices
// @FIXME: its worth looking into makeing this a ?u31, for space saving
//  see `TagListView.list_item_index`
remembered_item_index: ?u32 = null,

pub fn deinit(self: *Self, alloc: Allocator) void {
    alloc.free(self.file_path);
    alloc.free(self.file_bytes);
    self.tag_items.deinit(alloc);
    self.tag_texts.deinit(alloc);
}

pub const TagItem = struct {
    tag: []const u8, // slice into file
    author: ?[]const u8, // slice into file
    text: Range, // range into `TagList.tag_items`
    line_number: u32,
};

pub const Range = struct {
    start: u32,
    len: u32,
};
