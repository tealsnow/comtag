const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

const TagList = @import("TagList.zig");
const TagItem = TagList.TagItem;

pub fn read(alloc: Allocator, file_path: []u8) !TagList {
    const comment_str = "//"; // @TODO: config

    const cwd = std.fs.cwd(); // @TODO: persist

    const file_bytes = bytes: {
        const file = try cwd.openFile(file_path, .{});
        defer file.close();
        const file_size = try file.getEndPos();
        break :bytes try file.readToEndAlloc(alloc, file_size);
    };

    var tag_list = TagList{
        .file_path = file_path,
        .file_bytes = file_bytes,
        .tag_items = .{},
        .tag_texts = .{},
        .expanded = true,
    };

    var line_number: u32 = 1;
    var lines = mem.splitScalar(u8, file_bytes, '\n');
    while (lines.next()) |line_raw| : (line_number += 1) {
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

        const text_start: u32 = @intCast(tag_list.tag_texts.items.len);
        if (text) |s|
            try tag_list.tag_texts.append(alloc, s);

        var tag_item = TagItem{
            .tag = tag_name,
            .author = author,
            .line_number = line_number,
            .text = .{
                .start = text_start,
                .len = if (text == null) 0 else 1,
            },
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

            const cont = next_comment[text_begin_i..];

            try tag_list.tag_texts.append(alloc, cont);
            tag_item.text.len += 1;
        }

        try tag_list.tag_items.append(alloc, tag_item);
    }

    return tag_list;
}
