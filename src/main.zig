const std = @import("std");
const Interpreter = @import("./interpreter.zig").Interpreter;
const bc = @import("./bc.zig");

fn repl(out: *const std.fs.File.Writer, in: *const std.fs.File.Reader) !void {
    var buffer: [2048]u8 = undefined;
    var vm = Interpreter.new();
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
            vm.load(command);
            vm.run_to_end(out, in, debug and line_by_line) catch |err| {
                std.debug.print("\nError: '{}'\n", .{err});
            };
            if (debug and !line_by_line) {
                vm.dump();
            }
            continue;
        };
        switch (cmd) {
            .quit => break,
            .reset => vm.reset(),
            .dump => vm.dump(),
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

    // var vm = Interpreter.new();
    // vm.load(data[0..]);
    // return vm.run_to_end(&stdout, &stdin, false);

    const code = try bc.compile(data, alloc);
    defer code.deinit();

    // bc.dump_all(code.items);
    // std.debug.print("\n\n", .{});

    var vm = bc.Interpreter.new();
    vm.load(code.items[0..]);
    return vm.run_to_end(&stdout, &stdin, true);
}
