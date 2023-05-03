const std = @import("std");
const image = @import("image.zig");

pub const ArgError = error{
    OpInvalid,
    NotEnoughArgs,
    BytesInvalid,
    FormatInvalid,
};

const Op = enum(u8) {
    Help = 0,
    HelpLong = 1,
    FileTxt = 2,
    FileTxtLong = 3,
    FileBin = 4,
    FileBinLong = 5,
    Text = 6,
    TextLong = 7,

    fn parse(op_str_user: []const u8) ArgError!Op {
        const ops = [_][]const u8{ "-h", "--help", "-ft", "--file-txt", "-fb", "--file-bin", "-t", "--text" };
        var op_idx: u8 = 0;
        for (ops) |op_str| {
            if (std.mem.eql(u8, op_str, op_str_user)) {
                return @intToEnum(Op, op_idx);
            }
            op_idx += 1;
        }
        return ArgError.OpInvalid;
    }
};

/// Ignores errors
fn usage(writer: std.fs.File.Writer) void {
    writer.writeByte('\n') catch {};
    writer.print(
        \\Usage: bytes2img <[-h | -f | -t] width height img_format byte_src>
        \\
        \\-h,--help: Displays a help message.
        \\-ft,--file-txt: Reads bytes from a file and interprets them as text so "4f" becomes 0x04 and 0xFF.
        \\-fb,--file-bin: Read bytes from a file and interprets them as binary.
        \\-t,--text: Reads bytes from the string that has been passed in.
        \\
        \\Note: The output will be saved inside the current working directory as 'out.[img_format]'.
        \\Note: The 'img_format' is the extension name like 'pbm'.
        \\Note: The byte string is assumed to be a lowercase string of hex digits like '1badb002'. Placing any symbol that is not in the hex alphabet will lead to immediate exit.
    , .{}) catch {};
    writer.writeByte('\n') catch {};
}

fn fileReadAll(allocator: std.mem.Allocator, writer: std.fs.File.Writer, path: []const u8) ![]u8 {
    var path_absolute: []const u8 = undefined;
    if (std.fs.path.isAbsolute(path) == true) {
        path_absolute = path;
    } else {
        path_absolute = try std.fs.path.resolve(allocator, &[_][]const u8{path});
    }
    try writer.print("Parsed path to absolute path: '{s}'\n", .{path_absolute});
    const file: std.fs.File = try std.fs.openFileAbsolute(path_absolute, std.fs.File.OpenFlags{ .read = true, .write = false });
    const buf: []u8 = try file.readToEndAllocOptions(allocator, std.math.maxInt(u64), null, @alignOf(u32), null);
    try writer.print("Read {d} bytes from file\n", .{buf.len});
    return buf;
}

/// Check if all characters in a buffer are a hex digits (0-9,a-f)
fn validateHexChars(buffer: []const u8) bool {
    for (buffer) |char| {
        switch (char) {
            '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f' => continue,
            else => return false,
        }
    }
    return true;
}

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    var argv = std.process.args();

    errdefer usage(stdout);
    var gp = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gp.deinit() == .ok);
    const allocator = gp.allocator();

    // Skip exe name
    std.debug.assert(argv.skip() == true);

    // Read byte source type
    const src_op_str = argv.next() orelse return ArgError.NotEnoughArgs;
    const src_op = Op.parse(src_op_str) catch |err| {
        try stdout.print("Failed to parse operation string, got: {}\n", .{err});
        return err;
    };
    // Early exit since help was requested
    if (src_op == Op.Help or src_op == Op.HelpLong) {
        usage(stdout);
        return;
    }

    // Read width and height
    const width_str = argv.next() orelse return ArgError.NotEnoughArgs;
    const height_str = argv.next() orelse return ArgError.NotEnoughArgs;
    const width: u16 = try std.fmt.parseUnsigned(u16, width_str, 10);
    const height: u16 = try std.fmt.parseUnsigned(u16, height_str, 10);

    // Read image format
    const format_str = argv.next() orelse return ArgError.NotEnoughArgs;
    const format: image.ImageFormat = image.ImageFormat.parse(format_str) catch |err| {
        switch (err) {
            ArgError.FormatInvalid => try stdout.print("The provided file format is not supported\n", .{}),
            else => unreachable,
        }
        return err;
    };
    const file_name_base = "out";
    var file_name: [16]u8 = undefined;
    _ = try std.fmt.bufPrint(&file_name, file_name_base ++ ".{s}", .{format_str});
    // The output file is created and opened here
    const file_save = try std.fs.cwd().createFile(file_name[0..(4 + format_str.len)], std.fs.File.CreateFlags{});
    defer file_save.close();

    // Get a buffer hex digit characters
    var hex_digits_allocated: bool = false;
    var hex_digits: []u8 = undefined;
    defer if (hex_digits_allocated) allocator.free(hex_digits) else {};
    switch (src_op) {
        Op.Help, Op.HelpLong => {
            usage(stdout);
            return;
        },
        Op.FileTxt, Op.FileTxtLong, Op.FileBin, Op.FileBinLong => {
            const file_path = (argv.next() orelse {
                try stdout.print("Expected third argument to be a path to file with bytes\n", .{});
                return error.InvalidArgs;
            });
            const cwd_dir = std.fs.cwd();
            var data_file = try cwd_dir.openFile(file_path, .{});
            defer data_file.close();
            const hex_digits_raw: []u8 = try data_file.readToEndAlloc(allocator, 1 << (@bitSizeOf(usize) - 1));
            errdefer allocator.free(hex_digits_raw);
            hex_digits_allocated = true;
            if (src_op == Op.FileTxt or src_op == Op.FileTxtLong) {
                if (validateHexChars(hex_digits_raw) != true) {
                    return ArgError.BytesInvalid;
                }
            }
            hex_digits = hex_digits_raw;
        },
        Op.Text, Op.TextLong => {
            const hex_digits_raw = (argv.next() orelse {
                try stdout.print("Expected third argument to be a string of bytes\n", .{});
                return error.InvalidArgs;
            });
            if (validateHexChars(hex_digits_raw) == true) {
                hex_digits = (try allocator.alloc(u8, hex_digits_raw.len));
                hex_digits_allocated = true;
                std.mem.copyForwards(u8, hex_digits, hex_digits_raw);
            } else {
                return ArgError.BytesInvalid;
            }
        },
    }

    // This slice contains a byte per pixel/color channel
    var bytes: []const u8 = undefined;
    switch (src_op) {
        Op.FileBin, Op.FileBinLong => {
            bytes = hex_digits[0..];
        },
        else => {
            // Combine 2 characters together into a pixel/color value
            var hex_digit_idx: u32 = 0;
            while (hex_digit_idx < (hex_digits.len / 2)) : (hex_digit_idx += 1) {
                var byte_a = hex_digits[(hex_digit_idx) * 2];
                if (byte_a >= '0' and byte_a <= '9') {
                    byte_a = byte_a - '0';
                } else {
                    byte_a = 10 + (byte_a - 'a');
                }
                var byte_b = hex_digits[(hex_digit_idx * 2) + 1];
                if (byte_b >= '0' and byte_b <= '9') {
                    byte_b = byte_b - '0';
                } else {
                    byte_b = 10 + (byte_b - 'a');
                }
                hex_digits[hex_digit_idx] = (byte_a * 16) + byte_b;
            }
            bytes = hex_digits[0..(hex_digits.len / 2)];
        },
    }

    try stdout.print("Writing output to '{s}'\n", .{file_name[0..(file_name_base.len + 1 + format_str.len)]});
    try image.saveFile(&file_save, bytes, format, width, height);
}
