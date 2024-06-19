const std = @import("std");
const Interpreter = @import("./interpreter.zig").Interpreter;

const Writer = std.fs.File.Writer;
const Reader = std.fs.File.Reader;

fn repl(out: *const Writer, in: *const Reader) !void {
    var buffer: [2048]u8 = undefined;
    var interpreter = Interpreter.new(""[0..]);
    var debug = false;
    var line_by_line = false;
    while (true) {
        std.debug.print(">> ", .{});

        const Command = enum { quit, reset, dump, debug, line_by_line };
        const command = in.readUntilDelimiter(&buffer, '\n') catch |err| {
            if (err == error.EndOfStream) {
                return;
            }

            std.debug.print("Error reading input: '{}'\n", .{err});
            continue;
        };

        const cmd = std.meta.stringToEnum(Command, command) orelse {
            interpreter.program = command;
            interpreter.ip = 0;
            interpreter.run_to_end(out, in, debug and line_by_line) catch |err| {
                std.debug.print("\nError: '{}'\n", .{err});
            };
            if (debug and !line_by_line) {
                interpreter.dump();
            }
            continue;
        };
        switch (cmd) {
            .quit => break,
            .reset => interpreter.reset(),
            .dump => interpreter.dump(),
            .debug => {
                debug = !debug;
                std.debug.print("Debug mode is {s}\n", .{if (debug) "enabled" else "disabled" });
            },
            .line_by_line => {
                line_by_line = !line_by_line;
                std.debug.print("Line-by-line mode is {s}\n", .{if (debug) "enabled" else "disabled" });
            },
        }
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator(); 

    const args = try std.process.argsAlloc(std.heap.page_allocator);
    defer std.process.argsFree(std.heap.page_allocator, args);

    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();

    if (args.len < 2) {
        return repl(&stdout, &stdin);
    }

    const fp = try std.fs.cwd().openFile(args[1], .{});
    defer fp.close();

    const data = try fp.readToEndAlloc(alloc, 0xffff_ffff);
    defer alloc.free(data);

    var interpreter = Interpreter.new(data[0..]);
    return interpreter.run_to_end(&stdout, &stdin, false);
}
