const TagList = @import("TagList.zig");
const TagListView = @import("TagListView.zig");
const Colors = @import("Colors.zig");
const status_bar_view_height = @import("StatusBarView.zig").height;

const vaxis = @import("vaxis");
const Window = vaxis.Window;

pub fn window(parent: Window, tag_list_width: u16) Window {
    return parent.child(.{
        .x_off = tag_list_width,
        .y_off = 0,
        .height = parent.height - status_bar_view_height,
        .width = parent.width - tag_list_width,
    });
}

pub fn render(win: Window, colors: *Colors, tag_list_view: *TagListView) void {
    win.fill(.{ .style = .{ .bg = colors.bg_default } });

    const current_list: TagList = tag_list_view.tag_lists.items(.list)[tag_list_view.list_index];
    if (tag_list_view.list_item_index) |tag_index| {
        const current_tag = current_list.tag_items[tag_index];
        const line_idx = current_tag.line_number - 1;
        const lines = current_list.file_lines;

        const padding = (win.height - current_tag.num_lines) / 2;

        var i: u16 = 0;

        const begin_lines = line_idx - (line_idx -| padding);
        const diff = padding - begin_lines;
        i += @intCast(diff);

        for (lines[(line_idx - begin_lines)..line_idx]) |line| {
            _ = win.printSegment(.{
                .text = line,
                .style = .{ .bg = colors.bg_default },
            }, .{
                .row_offset = i,
            });
            i += 1;
        }

        const section_end_idx = line_idx + current_tag.num_lines;

        for (lines[line_idx..section_end_idx]) |line| {
            _ = win.printSegment(.{
                .text = line,
                .style = .{ .bg = colors.bg_selected },
            }, .{
                .row_offset = i,
            });
            i += 1;
        }

        if (line_idx + padding >= lines.len) {
            for (lines[section_end_idx..]) |line| {
                _ = win.printSegment(.{
                    .text = line,
                    .style = .{ .bg = colors.bg_default },
                }, .{
                    .row_offset = i,
                });
                i += 1;
            }
        } else {
            // @FIXME: on files smaller than the window height not having
            //  the `- 1` causes an off by 1 panic, where on files larger
            //  the final line in the view is not drawn
            for (lines[section_end_idx..(section_end_idx + padding - 1)]) |line| {
                _ = win.printSegment(.{
                    .text = line,
                    .style = .{ .bg = colors.bg_default },
                }, .{
                    .row_offset = i,
                });
                i += 1;
            }
        }
    } else {
        _ = win.printSegment(.{
            .text = current_list.file_bytes,
            .style = .{ .bg = colors.bg_default },
        }, .{});
    }
}
