const std = @import("std");
const mem = std.mem;
const fs = std.fs;
const Allocator = mem.Allocator;

const TagList = @import("TagList.zig");
const TagListView = @import("TagListView.zig");
const TagItem = TagList.TagItem;

const dir_options = fs.Dir.OpenDirOptions{
    .access_sub_paths = true,
    .iterate = true,
    .no_follow = false,
};

pub fn readSingleFile(alloc: Allocator, file_path: []u8) !TagListView {
    var tag_list_view = TagListView{};
    errdefer tag_list_view.deinit(alloc);

    const cwd = fs.cwd();
    const file = try cwd.openFile(file_path, .{});
    const tag_list = try readFile(alloc, file_path, file);
    if (tag_list) |list| {
        try tag_list_view.tag_lists.append(alloc, .{ .list = list });
    }

    return tag_list_view;
}

pub fn readDir(alloc: Allocator, dir_path: []const u8) !TagListView {
    const cwd = fs.cwd();
    var dir = try cwd.openDir(dir_path, dir_options);
    defer dir.close();

    var tag_list_view = TagListView{};
    errdefer tag_list_view.deinit(alloc);

    try iterDir(alloc, dir, dir_path, &tag_list_view);

    return tag_list_view;
}

fn iterDir(
    alloc: Allocator,
    dir: fs.Dir,
    dir_path: []const u8,
    tag_list_view: *TagListView,
) !void {
    var it = dir.iterate();
    while (try it.next()) |entry| {
        switch (entry.kind) {
            .directory => {
                var sub_dir = try dir.openDir(entry.name, dir_options);
                defer sub_dir.close();

                const full_dir_path = try fs.path.join(
                    alloc,
                    &.{ dir_path, entry.name },
                );
                defer alloc.free(full_dir_path);

                try iterDir(alloc, sub_dir, full_dir_path, tag_list_view);
            },
            .file => {
                const file = try dir.openFile(entry.name, .{});
                errdefer file.close();

                const path = try fs.path.join(
                    alloc,
                    &.{ dir_path, entry.name },
                );
                errdefer alloc.free(path);

                const tag_list = readFile(alloc, path, file) catch |err| {
                    if (err == error.invalid_utf8) {
                        alloc.free(path);
                        continue;
                    }
                    return err;
                };
                if (tag_list) |list| {
                    try tag_list_view.tag_lists.append(alloc, .{ .list = list });
                }
            },
            else => {},
        }
    }
}

/// Closes the `file` passed
fn readFile(alloc: Allocator, file_path: []u8, file: fs.File) !?TagList {
    // @TODO: extract from file extension
    const comment_str = "//";

    const file_bytes = bytes: {
        defer file.close();
        const file_size = try file.getEndPos();
        break :bytes try file.readToEndAlloc(alloc, file_size);
    };
    errdefer alloc.free(file_bytes);
    if (!std.unicode.utf8ValidateSlice(file_bytes))
        return error.invalid_utf8;

    // var tag_list = TagList{
    //     .file_path = file_path,
    //     .file_bytes = file_bytes,
    // };
    // errdefer tag_list.deinit(alloc);

    var file_lines = std.ArrayListUnmanaged([]const u8){};
    errdefer file_lines.deinit(alloc);
    var tag_items = std.ArrayListUnmanaged(TagItem){};
    errdefer tag_items.deinit(alloc);
    var tag_texts = std.ArrayListUnmanaged([]const u8){};
    errdefer tag_texts.deinit(alloc);

    var line_number: u32 = 1;
    var lines = mem.splitScalar(u8, file_bytes, '\n');
    while (lines.next()) |line_raw| : (line_number += 1) {
        try file_lines.append(alloc, line_raw);

        // find all comments
        const line = mem.trim(u8, line_raw, " \t");
        if (!mem.startsWith(u8, line, comment_str))
            continue;
        const comment_start_i = mem.indexOfAny(u8, line_raw, comment_str).?;

        // filter for all those starting with '@'
        const comment = mem.trim(u8, line[comment_str.len..], " \t");
        if (!mem.startsWith(u8, comment, "@"))
            continue;
        const tag_start_i = comment_start_i + mem.indexOfAny(u8, line, "@").?;

        const full_tag = comment[1..];
        var i: usize = 0;

        var found_colon = false;
        var at_author = false;

        // grab the tag name
        while (i < full_tag.len) : (i += 1) {
            const at = full_tag[i];
            if (at == ':') {
                found_colon = true;
                break;
            } else if (at == '(') {
                at_author = true;
                break;
            }
        }
        const tag_name = full_tag[0..i];

        // grab the author
        const author = if (at_author) blk: {
            i += 1;
            const author_start = i;
            while (i < full_tag.len) : (i += 1) {
                const at = full_tag[i];
                if (at == ':') {
                    found_colon = true;
                    break;
                }
            }
            break :blk full_tag[author_start..(i - 1)];
        } else null;

        // then the text
        const text = if (found_colon)
            mem.trim(u8, full_tag[(i + 1)..], " ")
        else
            null;

        const text_start: u32 = @intCast(tag_texts.items.len);
        if (text) |s|
            try tag_texts.append(alloc, s);

        var tag_item = TagItem{
            .tag = tag_name,
            .author = author,
            .text = .{
                .start = text_start,
                .len = if (text == null) 0 else 1,
            },
            .line_number = line_number,
            .num_lines = 1,
        };

        // if the following lines is also a comment that starts in the same
        // column and the leading whitespace is greator than that of the
        // tag, it is a continuation of the text
        while (lines.peek()) |next_line_raw| {
            const next_line = mem.trim(u8, next_line_raw, " \t");
            if (!mem.startsWith(u8, next_line, comment_str))
                break;
            const begin_i = mem.indexOfAny(u8, next_line_raw, comment_str).?;

            if (begin_i != comment_start_i)
                break;

            const next_comment = mem.trimRight(u8, next_line[comment_str.len..], " \t");
            var text_begin_i: usize = 0;
            while (text_begin_i < next_comment.len) : (text_begin_i += 1) {
                const at = next_comment[text_begin_i];
                if (at == ' ' or at == '\t')
                    continue;
                break;
            }
            if (text_begin_i + begin_i + comment_str.len <= tag_start_i)
                break;

            _ = lines.next();
            line_number += 1;
            try file_lines.append(alloc, next_line_raw);

            const cont = next_comment[text_begin_i..];

            try tag_texts.append(alloc, cont);
            tag_item.text.len += 1;
            tag_item.num_lines += 1;
        }

        try tag_items.append(alloc, tag_item);
    }

    if (tag_items.items.len == 0) {
        alloc.free(file_path);
        alloc.free(file_bytes);
        file_lines.deinit(alloc);
        tag_items.deinit(alloc);
        tag_texts.deinit(alloc);

        return null;
    } else {
        return TagList{
            .file_path = file_path,
            .file_bytes = file_bytes,
            .file_lines = try file_lines.toOwnedSlice(alloc),
            .tag_items = try tag_items.toOwnedSlice(alloc),
            .tag_texts = try tag_texts.toOwnedSlice(alloc),
        };
    }
}
